# Step A of stream-integrate: applies the next ready built patch to the main tree and re-runs its grader there.
#   clean + grader PASS : task -> integrated, then the patch's paths (and only those) are committed
#   not clean           : task -> ticketed ("rebase: base moved"), main tree untouched; the patch stays for reuse
#   BASE-STALE          : a dependency patch the builder's base stacked (base.deps) changed before it landed; task ->
#                         ticketed before any apply, patch kept (lib\Streams.ps1 Get-DependencyBaseDrift)
#   grader red on main  : patch reversed, then one of
#       RETRY    the main log shows a build/IO environment failure (file locked, CS2012, MSB3021/3027, main tree busy):
#                the task stays built and the next pass retries it; after 3 such failures it goes to ticketed
#       SUSPECT  every clause red on main passed in the builder's worktree under the same grader (same GRADER sha), and
#                main held exactly the worktree's content: the grader, not the code, is wrong. task -> planned for a
#                new grader, patch kept so the builder re-verifies it instead of rebuilding; owner line logged
#       REVERSED otherwise: task -> ticketed; the patch stays as the builder's starting point (Restore-TaskPatch)
# Picks the first built code/docs task whose dependencies are integrated or done (dependency order keeps each base
# true); mockup tasks move to integrated with no tree change. Prints one outcome line, or NONE.
# -NoCommit leaves the integrated patch uncommitted (the owner commits by hand).
# After a commit the ref -PushRef (default refs/heads/users/agenewe/stream-sync, or STREAM_PUSH_REF; empty disables)
# is pushed to origin. A push failure is reported and never blocks integration; no origin remote means no push.
# The commit and the push each also need the machine profile's '## Git policy' row for this repo (Commit = yes,
# Push = yes; read through MachineConfig.psm1, the same source git-guard uses). git-guard sees only command text, so
# it never sees the git this script runs; this check is what holds the script to the policy. A missing row, a 'no',
# or a profile that cannot be read SKIPS the commit or push (fails closed) and never blocks integration.
# The integrator lock is checked before the apply and again after the grader: LOCK-LOST, exit 5, when another session
# holds it (the patch is reversed and the task stays built). A lock that is simply GONE - the watchdog broke it under
# this session - is retaken and noted in decisions.md.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [string] $Task = '',
    [string] $PushRef = $(if ($null -ne $env:STREAM_PUSH_REF) { $env:STREAM_PUSH_REF } else { 'refs/heads/users/agenewe/stream-sync' }),
    [switch] $NoCommit
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Recovery.ps1"
$Repo = (Resolve-Path $Repo).Path
# build/IO failures that say nothing about the code or the grader. GRADER-TIMEOUT is a hung child Invoke-Grader ended
# (kit item IN-20261010031237-259d): retried like the rest, ticketed after three.
$script:EnvFailurePattern = 'CS2012|MSB3021|MSB3026|MSB3027|being used by another process|cannot access the file|MAIN-GRADER-BUSY|GRADER-TIMEOUT|Access to the path .* is denied'
$P = Get-StreamPaths $Repo
# The repo's git policy from the machine profile: { Commit; Push; Why }. Any failure to read it denies both.
function Get-IntegrateGitPolicy([string] $Repo) {
    try {
        $lib = @((Join-Path $PSScriptRoot '..\..\..\lib\MachineConfig.psm1'), (Join-Path $HOME '.claude\lib\MachineConfig.psm1')) |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $lib) { throw 'MachineConfig.psm1 not found' }
        Import-Module $lib -Force -DisableNameChecking
        $prof = Get-AIMachineProfile
        $pol = Get-AIGitPolicy -Path $Repo -Profile $prof
        $why = if ($pol.Row) { "Git policy row for $($pol.RepoRoot) in $($prof.Path)" } else { "no Git policy row for $Repo in $($prof.Path)" }
        [pscustomobject]@{ Commit = $pol.Commit; Push = $pol.Push; Why = $why }
    } catch {
        [pscustomobject]@{ Commit = $false; Push = $false; Why = "machine profile could not be read: $(("$_" -split "`n")[0])" }
    }
}
# ONE Integrate-Patch process per repo, held for the whole run and taken BEFORE the board is read. The integrator lock
# names a session, so a second process under the same session passed it: on 2026-10-01 20:36Z-21:45Z two drains of
# 4599ecab ran at once, each picked G3.T019 off its own read of the board, one waited on the main-tree lock and then
# REBASE-bounced a patch the other had just committed, and a concurrent commit hit .git/index.lock (kit item
# IN-20261001215631-6eda). The handle is DeleteOnClose and FileShare.None, so the OS frees it when the process dies,
# and a second run fails at once with DRAIN-BUSY, exit 4, writing nothing.
try {
    $script:drainLock = [IO.FileStream]::new((Join-Path $P.Root 'integrate-patch.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose)
    $b = [Text.Encoding]::UTF8.GetBytes("$Session pid $PID at $(Get-Now)"); $script:drainLock.SetLength(0); $script:drainLock.Write($b, 0, $b.Length); $script:drainLock.Flush()
} catch [IO.IOException] {
    "DRAIN-BUSY another Integrate-Patch run holds $($P.Root)\integrate-patch.lock; this run did nothing"; exit 4
}
# Everything below runs under the drain lock; the finally frees it on every exit, so a caller that dot-runs this
# script twice in one process is not refused by its own earlier run.
try {
# A tasks.json write that waits out its lock throws, and here a throw can land between a write to main and the row's
# state: on 2026-10-03 G3.T294's -To integrated write timed out at 15 s while the coordinator held the lock, and the
# patch stayed applied (kit item IN-20261003193026-6efe). So this run waits longer (90 s, under the 120 s stale-lock
# break), and the catch at the end reverses an applied patch on ANY throw.
$prevTasksWait = $env:STREAM_TASKS_LOCK_WAIT_SECONDS
if (-not $prevTasksWait) { $env:STREAM_TASKS_LOCK_WAIT_SECONDS = '90' }
$script:appliedPatch = $null; $script:appliedTask = $null
# The lock must be this session's before anything touches the main tree: a watchdog can break it under a long grader
# run, and a second integrator on one tree is the failure this guards (kit item IN-20260929001947-2b20).
$lockState = Assert-IntegratorLock $P $Session
if ($lockState -eq 'lost') { "LOCK-LOST integrator lock is held by $(Get-IntegratorLockHolder $P)"; exit 5 }
if ($lockState -eq 'retaken') { Add-Decision $P $Session 'integrator lock was gone (broken under a live integrator); retaken before applying' }
$doc = Read-Tasks $P
$update = "$PSScriptRoot\Update-Task.ps1"

# FOCUS (2026-10-05 priority-focus-design 3.1): only rows in the focus set (lib\Streams.ps1 Get-FocusSet) are applied.
# A built row outside it is reported NOT-FOCUS and stays built until its group's turn.
$focusSet = Get-FocusSet $doc
$allBuilt = @($doc.tasks | Where-Object { $_.state -eq 'built' -and ($Task -eq '' -or $_.id -eq $Task) })
foreach ($nf in @($allBuilt | Where-Object { -not $focusSet.Contains([string]$_.id) })) { "NOT-FOCUS $($nf.id) (built; waits for its group $($nf.group) to become focus)" }
# Applied in PRIORITY order (lib\Streams.ps1 Get-PriorityRankMap: the focus groups as written in config.json), board
# order inside a group (owner ruling 2026-10-14).
$prio = Get-PriorityRankMap $doc $P
$boardAt = @{}; $bo = 0; foreach ($x in $doc.tasks) { $boardAt[[string]$x.id] = ++$bo }
$ready = @($allBuilt | Where-Object { $focusSet.Contains([string]$_.id) } | Sort-Object @{ e = { if ($prio.ContainsKey([string]$_.group)) { $prio[[string]$_.group] } else { [int]::MaxValue } } }, @{ e = { $boardAt[[string]$_.id] } })
# A folder delivered in place is re-hashed against the fingerprint its hand-off wrote, and every difference is REPORTED
# with the file that changed. It never refuses: a correction after hand-off can be right (kit item
# IN-20260930120446-f9f5). A row handed off before the fingerprint shipped has no manifest and lands unremarked.
function Get-DeliveryDrift($P, [string] $Task, $WriteSet) {
    if (-not (Test-InPlaceWriteSet $WriteSet)) { return @() }
    @(Compare-DeliveredManifest $P $Task $WriteSet | Where-Object { $_ -and $_ -ne 'NO-MANIFEST' })
}
foreach ($m in @($ready | Where-Object { $_.kind -eq 'mockup' })) {
    $drift = @(Get-DeliveryDrift $P $m.id $m.writeSet)
    foreach ($line in $drift) { "DELIVERY-CHANGED $($m.id) $line" }
    $suffix = if ($drift.Count) { " -- delivered folder changed since hand-off: $($drift -join '; ')" } else { '' }
    & $update -Repo $Repo -Task $m.id -Role integrate -Session $Session -To integrated -Note "mockup: no tree change$suffix" | Out-Null
    "INTEGRATED $($m.id) (mockup)$(if ($drift.Count) { ' CHANGED SINCE HAND-OFF' })"
}
$inPlace = @($ready | Where-Object { $_.kind -in @('code', 'docs') -and (Test-InPlaceWriteSet $_.writeSet) -and (Test-DepsAt $doc $_ @('integrated', 'done')) })
foreach ($m in $inPlace) {
    $drift = @(Get-DeliveryDrift $P $m.id $m.writeSet)
    foreach ($line in $drift) { "DELIVERY-CHANGED $($m.id) $line" }
    $suffix = if ($drift.Count) { " -- delivered folder changed since hand-off: $($drift -join '; ')" } else { '' }
    & $update -Repo $Repo -Task $m.id -Role integrate -Session $Session -To integrated -Note "in place under .streams: no tree change$suffix" | Out-Null
    "INTEGRATED $($m.id) (in place)$(if ($drift.Count) { ' CHANGED SINCE HAND-OFF' })"
}
$t = @($ready | Where-Object { $_.kind -in @('code', 'docs') -and -not (Test-InPlaceWriteSet $_.writeSet) -and (Test-DepsAt $doc $_ @('integrated', 'done')) }) | Select-Object -First 1
if (-not $t) { if (-not (@($ready | Where-Object { $_.kind -eq 'mockup' }).Count + $inPlace.Count)) { 'NONE' }; exit 0 }

# A row with neither a builder's check nor an author's grader cannot be verified on main (stream-integrate A3, owner
# rulings IN-20261002160453-ce2a and IN-20261002160643-741d), so it is bounced BEFORE the apply. On 2026-10-03
# Invoke-Grader answered NO-GRADER without writing a main log, the red branch threw reading that log, and G3.T268's
# patch stayed applied on main (kit item IN-20261003183249-a488).
if (-not (Get-Field $t 'artifacts', 'check') -and -not (Get-Field $t 'artifacts', 'grader')) {
    & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To ticketed -Note 'integrate: bounced before the apply, the row has neither a check nor a grader to verify it on main (patch kept; the builder records artifacts.check and hands off again)' | Out-Null
    Add-Decision $P $Session "bounced $($t.id) to ticketed before the apply: neither artifacts.check nor a grader"
    "BOUNCED $($t.id) (neither a check nor a grader)"; exit 0
}
# BASE-STALE (2026-10-18 dependency review, finding F1): the builder's base stacked its built dependencies' patches and
# recorded their hashes (base.deps); a dependency that bounced and was rebuilt since landed a DIFFERENT patch, so this
# row's verifier graded against code that is not on main even when its own patch still applies. Bounced to ticketed
# with the patch kept: the next build restores it on a true base (Restore-TaskPatch) and re-verifies.
$drift = Get-DependencyBaseDrift $P $doc $t
if ($drift.Count) {
    $what = @($drift | ForEach-Object { "$($_.dep) ($($_.leaf) was $($_.recorded), now $($_.now))" }) -join '; '
    & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To ticketed -Note "BASE-STALE: built on dependency patch(es) that changed before landing: $what (patch kept; rebuild restores it on the current base and re-verifies)" | Out-Null
    Add-Decision $P $Session "BASE-STALE $($t.id) to ticketed: $what"
    "BASE-STALE $($t.id) ($what)"; exit 0
}
$patch = $t.artifacts.patch
if (-not [IO.Path]::IsPathRooted($patch)) { $patch = Join-Path $Repo $patch }
# A write to main and a main-tree grader build must exclude each other. Without this an author's RED run compiled a
# tree that was being rewritten under it and reported a phantom CS1061 for a member HEAD declares (kit item
# IN-20260929183913-7850). The lock is released before the grader, which takes it itself.
$applyLock = Enter-MainTreeLock $P "integrate $($t.id) apply" 600
if (-not $applyLock) { "RETRY $($t.id) (main tree busy: $(Get-MainTreeLockHolder $P))"; exit 0 }
& git -C $Repo apply --check --binary --whitespace=nowarn $patch 2>&1 | Out-Null
# ORDERED-BY-MERGE (kit item IN-20261018134210-ede5): rows that share a composition file unordered only append there,
# so a patch that no longer applies only because another row appended to the same file is merged by its added lines
# (lib New-CompositionMergedPatch) and that merged patch is applied, graded, reversed and committed instead. Anything
# else that does not apply is still a REBASE.
$clean = $LASTEXITCODE -eq 0; $mergeWhy = ''
if (-not $clean) {
    $merge = New-CompositionMergedPatch $Repo $patch (Join-Path $P.Patches "$($t.id).merged.patch")
    if ($merge.Ok) {
        $clean = $true; $patch = $merge.Path
        Add-Decision $P $Session "$($t.id): patch merged by its added lines into $($merge.Files -join ', ') (ORDERED-BY-MERGE), applying $($t.id).merged.patch"
        "MERGED $($t.id) $($merge.Files -join ',')"
    } elseif ($merge.Reason -ne 'the conflict is not in a composition file') { $mergeWhy = "; composition merge refused: $($merge.Reason)" }
}
if (-not $clean) {
    & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To ticketed -Note "rebase: base moved (patch kept as the builder's starting point)$mergeWhy" | Out-Null
    $applyLock.Dispose()
    "REBASE $($t.id)"; exit 0
}
[void](Invoke-Git $Repo @('apply', '--binary', '--whitespace=nowarn', $patch))
$script:appliedPatch = $patch; $script:appliedTask = $t.id
$applyLock.Dispose()
# A grader that crashes must never leave the patch half-integrated on main: reverse it and bounce the task.
try { $g = & "$PSScriptRoot\Invoke-Grader.ps1" -Repo $Repo -Task $t.id -Root $Repo -Label main -BeatSession $Session; $gcode = $LASTEXITCODE }
catch {
    $revLock = Enter-MainTreeLock $P "integrate $($t.id) reverse" 600
    [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $patch))
    $script:appliedPatch = $null
    if ($revLock) { $revLock.Dispose() }
    & git -C $Repo update-index -q --refresh 2>&1 | Out-Null
    $err = ("$_" -split "`n")[0].Trim()
    Add-Decision $P $Session "grader run for $($t.id) threw; patch reversed: $err"
    & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To ticketed -Note "integrate: grader could not run on main (patch reversed): $err" | Out-Null
    "REVERSED $($t.id) (grader error)"; exit 0
}
# The grader can run for a long time. If the lock changed hands while it ran, another integrator owns this tree:
# reverse the patch and stop rather than commit under someone else's lock.
if (-not (Test-IntegratorLock $P $Session)) {
    $revLock = Enter-MainTreeLock $P "integrate $($t.id) reverse" 600
    [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $patch))
    $script:appliedPatch = $null
    if ($revLock) { $revLock.Dispose() }
    & git -C $Repo update-index -q --refresh 2>&1 | Out-Null
    Add-Decision $P $Session "integrator lock lost to $(Get-IntegratorLockHolder $P) while $($t.id) graded on main; patch reversed, task left built"
    "LOCK-LOST $($t.id) (patch reversed, still built)"; exit 5
}
if ($gcode -eq 0) {
    $u = @(& $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To integrated -Note 'applied; grader PASS on main')
    if ($LASTEXITCODE -ne 0) { throw "state write -To integrated refused (exit $LASTEXITCODE): $($u -join ' ')" }
    $script:appliedPatch = $null
    "INTEGRATED $($t.id)"
    if ($NoCommit) { exit 0 }
    $gitPolicy = Get-IntegrateGitPolicy $Repo
    if (-not $gitPolicy.Commit) {
        Add-Decision $P $Session "commit of $($t.id) skipped, left uncommitted: Commit is not allowed ($($gitPolicy.Why))"
        "COMMIT SKIPPED $($t.id) (git policy: $($gitPolicy.Why))"; exit 0
    }
    # Commit exactly the paths the patch touched (both sides of a rename); other dirty or staged files stay out.
    $paths = @(Get-Content -LiteralPath $patch | ForEach-Object { if ($_ -match '^diff --git a/(.+) b/(.+)$') { $Matches[1]; $Matches[2] } } | Sort-Object -Unique)
    try {
        [void](Invoke-Git $Repo (@('add', '-A', '--') + $paths))
        $msg = "$($t.id): $($t.title)"
        [void](Invoke-Git $Repo (@('commit', '-q', '-m', $msg, '-m', "Integrated by stream-integrate ($Session); grader PASS on main.", '-m', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>', '--') + $paths))
        $sha = (Invoke-Git $Repo @('rev-parse', '--short', 'HEAD')) | Select-Object -First 1
        Add-Decision $P $Session "committed $($t.id) as $sha"
        "COMMITTED $($t.id) $sha"
        # The stream branch is shared, so every integration commit is pushed as soon as it lands (owner decision,
        # 2026-09-29, kit item IN-20260929001946-67a7 part 1). The branch itself needs a PR, so the push names the
        # ref explicitly rather than relying on an upstream. A failed push is REPORTED and never blocks integration:
        # the commit is already in the local history and the next integration pushes both. No origin means nothing
        # to push, which is the self-test fixtures' case.
        $remotes = @(& git -C $Repo remote 2>$null)
        if ($PushRef -and ($remotes -contains 'origin') -and -not $gitPolicy.Push) {
            Add-Decision $P $Session "push of $sha to origin $PushRef skipped: Push is not allowed ($($gitPolicy.Why))"
            "PUSH SKIPPED $($t.id) $sha (git policy: $($gitPolicy.Why))"
        } elseif ($PushRef -and ($remotes -contains 'origin')) {
            try {
                [void](Invoke-Git $Repo @('push', 'origin', "HEAD:$PushRef"))
                Add-Decision $P $Session "pushed $sha to origin $PushRef"
                "PUSHED $($t.id) $sha -> $PushRef"
            } catch {
                Add-Decision $P $Session "push of $sha to origin $PushRef failed (commit stands, integration unaffected): $($_.Exception.Message)"
                "PUSH FAILED $($t.id) $sha (committed; integration unaffected)"
            }
        }
    } catch {
        Add-Decision $P $Session "commit of $($t.id) failed, left uncommitted: $($_.Exception.Message)"
        "COMMIT FAILED $($t.id) (left uncommitted)"
    }
} else {
    # red on main: decide grader defect vs code defect while main still holds the patch
    $mainLog = Join-Path $P.Logs "$($t.id).grader.main.txt"
    $wtLog = Join-Path $P.Logs "$($t.id).grader.wt.txt"
    $redIds = @(Get-ClauseIds @(Get-Content -LiteralPath $mainLog -ErrorAction SilentlyContinue) 'FAIL')
    $why = @()
    if (-not $redIds.Count) { $why += 'no FAIL clause named (grader crashed or exit code only)' }
    if (-not (Test-Path $wtLog)) { $why += 'no worktree grader log' }
    else {
        $wtLines = Get-Content $wtLog
        $notPassed = @($redIds | Where-Object { $_ -notin @(Get-ClauseIds $wtLines 'PASS') })
        if ($notPassed.Count) { $why += "clauses $($notPassed -join ',') did not pass in the worktree" }
        $wtSha = @($wtLines | ForEach-Object { if ("$_" -match '^GRADER sha (\S+)') { $Matches[1] } })
        $mainSha = @(Get-Content -LiteralPath $mainLog -ErrorAction SilentlyContinue | ForEach-Object { if ("$_" -match '^GRADER sha (\S+)') { $Matches[1] } })
        if (-not $wtSha.Count) { $why += 'worktree log has no grader identity' }
        elseif ($mainSha.Count -and $wtSha[-1] -ne $mainSha[-1]) { $why += 'the grader changed since the worktree run' }
    }
    # "main holds exactly what was graded in the worktree" is proved from the PATCH, not from the worktree: the patch is
    # that worktree's content (Export-TaskPatch runs `git diff` in it), and it is still applied to main here. So a
    # reverse-apply check answers the same question and needs no worktree, which is what lets a worktree be reclaimed
    # once its patch is verified, and what stops a builder on another host reading as evidence gone (kit IN-...-b254).
    # A grader that rewrote one of the patched files during its run fails this, which is the signal it should be.
    & git -C $Repo apply --check --reverse --binary --whitespace=nowarn $patch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { $why += 'main does not hold the patch content (something rewrote a patched file)' }
    # The worktree is better evidence when it is still there, because it also catches a builder who edited it AFTER
    # exporting the patch. It is optional: absent evidence is not a defect, so a reclaimed worktree adds no `why`.
    $wt = Get-Field $t 'base', 'worktree'
    if ($wt -and (Test-Path $wt) -and -not (Test-SameContent $Repo $wt (Get-PatchPaths $patch))) {
        $why += 'main content differs from the worktree (the worktree moved on after its patch was exported)'
    }
    # A C# compile error on main is a code defect even when the patched files match the worktree: files outside the
    # patch moved under it (main moved on since the task's base). CS2012 is a file lock, handled as environment below.
    $csHit = @(@(Get-Content $mainLog -ErrorAction SilentlyContinue) + @($g) | Where-Object { "$_" -match 'error CS(?!2012)\d{4}' } | Select-Object -First 1)
    if ($csHit.Count) {
        $baseHead = Get-Field $t 'base', 'head'
        $mainHead = (Invoke-Git $Repo @('rev-parse', 'HEAD')) | Select-Object -First 1
        $moved = if ($baseHead -and $baseHead -ne $mainHead) { "base moved: $($baseHead.Substring(0, [Math]::Min(10, $baseHead.Length)))..$($mainHead.Substring(0, [Math]::Min(10, $mainHead.Length)))" } else { 'base unchanged' }
        $cs = ([regex]::Match("$($csHit[0])", 'error CS\d{4}[^\r\n]{0,120}')).Value
        $why += "main build failed to compile ($moved): $cs"
    }

    $revLock = Enter-MainTreeLock $P "integrate $($t.id) reverse" 600
    [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $patch))
    $script:appliedPatch = $null
    if ($revLock) { $revLock.Dispose() }
    & git -C $Repo update-index -q --refresh 2>&1 | Out-Null
    $fails = ($g | Where-Object { $_ -like 'FAIL *' }) -join ' | '
    $envHit = @(@(Get-Content $mainLog -ErrorAction SilentlyContinue) + @($g) | Where-Object { "$_" -match $script:EnvFailurePattern } | Select-Object -First 1)
    if ($envHit.Count) {
        $prior = @(@($t.history) | Where-Object { "$($_.note)" -like 'integrate: environment failure*' }).Count
        $hit = ("$($envHit[0])").Trim(); if ($hit.Length -gt 160) { $hit = $hit.Substring(0, 160) }
        if ($prior -ge 2) {
            & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To ticketed -Note "integrate: environment failure 3 times on main, giving up (patch kept): $hit" | Out-Null
            "REVERSED $($t.id) (environment, 3 tries)"; exit 0
        }
        & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -Note "integrate: environment failure on main (try $($prior + 1) of 3), patch reversed, task stays built for retry: $hit" | Out-Null
        Add-Decision $P $Session "grader for $($t.id) hit an environment failure on main; retry later: $hit"
        "RETRY $($t.id) (environment)"; exit 0
    }
    if (-not $why.Count) {
        $note = "grader-suspect: $($redIds -join ',') red on main but PASS in $wt on identical content under the same grader; patch kept at $($t.artifacts.patch), no rebuild needed; the grader needs re-authoring. Main: $fails"
        & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To planned -Note $note | Out-Null
        Add-LineTo $P.Questions ("- {0} | grader red on main only ({1}); same clauses PASS in the worktree on identical content | default: task back to planned for a new grader, verified patch kept for reuse | a clause that cannot pass after git apply (file times, tree-local state) is a grader defect" -f $t.id, ($redIds -join ','))
        "SUSPECT $($t.id)"
    } else {
        & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To ticketed -Note ("integrate: grader red on main; " + $fails + " (not a grader defect: " + ($why -join '; ') + ")") | Out-Null
        "REVERSED $($t.id)"
    }
}
} catch {
    # Any throw while main holds this run's patch (a state write that timed out on the tasks.json lock, a log read, a
    # git call) reverses the patch, so main never keeps work no row records, and the row stays built for the next pass.
    if (-not $script:appliedPatch) { throw }
    $err = ("$_" -split "`n")[0].Trim()
    $revLock = Enter-MainTreeLock $P "integrate $($script:appliedTask) reverse" 600
    try { [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $script:appliedPatch)) } finally { if ($revLock) { $revLock.Dispose() } }
    & git -C $Repo update-index -q --refresh 2>&1 | Out-Null
    Add-Decision $P $Session "integrate $($script:appliedTask): a step after the apply threw, patch reversed, row left built: $err"
    try { & $update -Repo $Repo -Task $script:appliedTask -Role integrate -Session $Session -Note "integrate: a step after the apply threw, patch reversed, task stays built for retry: $err" | Out-Null } catch { }
    "RETRY $($script:appliedTask) (a step after the apply threw; patch reversed, still built): $err"; exit 0
} finally {
    $script:drainLock.Dispose()
    if (-not $prevTasksWait) { Remove-Item Env:\STREAM_TASKS_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue }
}
