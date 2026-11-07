# Step A of stream-integrate: applies the next ready built patch to the main tree and re-runs its grader there.
#   clean + grader PASS : task -> integrated, then the patch's paths (and only those) are committed
#   not clean           : task -> ticketed ("rebase: base moved"), main tree untouched; the patch stays for reuse
#   already on main     : the patch reverse-applies clean: held uncommitted it is graded in place (ALREADY-APPLIED, then
#                         as an apply); held in HEAD the row is integrated with nothing applied or committed
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
# After a commit the ref -PushRef (default: the machine profile's Git policy 'Push ref' for the repo, blank or 'branch' = the main tree's checked-out branch,
# which the owner merges to main by PR; STREAM_PUSH_REF overrides; empty disables)
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
    [string] $PushRef = $(if ($null -ne $env:STREAM_PUSH_REF) { $env:STREAM_PUSH_REF } else { '<profile>' }),
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
        [pscustomobject]@{ Commit = $pol.Commit; Push = $pol.Push; PushRef = $pol.PushRef; Why = $why }
    } catch {
        [pscustomobject]@{ Commit = $false; Push = $false; PushRef = ''; Why = "machine profile could not be read: $(("$_" -split "`n")[0])" }
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
$script:appliedPatch = $null; $script:appliedTask = $null; $script:intentPaths = @()
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
# A mockup is a no-tree-change row only when it is delivered in place under .streams; a mockup whose write set is in
# the tree (docs/ui/<screen>) hands off a patch and lands like a docs row (kit item IN-20261107203530-f681).
$inPlaceMockups = @($ready | Where-Object { $_.kind -eq 'mockup' -and (Test-InPlaceWriteSet $_.writeSet) })
foreach ($m in $inPlaceMockups) {
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
$t = @($ready | Where-Object { $_.kind -in @('code', 'docs', 'mockup') -and -not (Test-InPlaceWriteSet $_.writeSet) -and (Test-DepsAt $doc $_ @('integrated', 'done')) }) | Select-Object -First 1
if (-not $t) { if (-not ($inPlaceMockups.Count + $inPlace.Count)) { 'NONE' }; exit 0 }

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
# NO-CODE-CHANGE (kit item IN-20261026203916-9d38): a row built with no code change (its clause already true at HEAD)
# hands off a patch with no file sections. git apply --check refuses such a file, the composition merge and the reverse
# check refuse it too, so it REBASEd and looped (G17.T116 built and REBASEd twice). There is nothing to apply or commit:
# the row's check/grader runs on main as it stands; green integrates it with no commit, red sends it back to ticketed.
if ((Test-Path -LiteralPath $patch -PathType Leaf) -and -not @(Get-PatchPaths $patch).Count) {
    $g = @(& "$PSScriptRoot\Invoke-Grader.ps1" -Repo $Repo -Task $t.id -Root $Repo -Label main -BeatSession $Session); $gcode = $LASTEXITCODE
    $mainLog = Join-Path $P.Logs "$($t.id).grader.main.txt"
    if ($gcode -eq 0) {
        $u = @(& $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To integrated -Note 'no code change: the patch has no file sections (clause already true at HEAD); check/grader PASS on main in place, nothing applied or committed')
        if ($LASTEXITCODE -ne 0) { throw "state write -To integrated refused (exit $LASTEXITCODE): $($u -join ' ')" }
        Add-Decision $P $Session "$($t.id): no code change (patch has no file sections); graded on main in place, integrated with no apply or commit"
        "INTEGRATED $($t.id) (no code change)"; exit 0
    }
    $envHit = @(@(Get-Content $mainLog -ErrorAction SilentlyContinue) + $g | Where-Object { "$_" -match $script:EnvFailurePattern } | Select-Object -First 1)
    if ($gcode -in @(5, 8) -or $envHit.Count) {
        & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -Note "integrate: no-code-change row could not be graded on main (exit $gcode), task stays built for retry" | Out-Null
        "RETRY $($t.id) (no code change, grader exit $gcode)"; exit 0
    }
    $fails = ($g | Where-Object { "$_" -like 'FAIL *' }) -join ' | '
    & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To ticketed -Note "integrate: no code change handed off, but its check/grader is RED on main (log $mainLog): $fails" | Out-Null
    Add-Decision $P $Session "$($t.id): no-code-change row red on main; to ticketed"
    "BOUNCED $($t.id) (no code change, red on main)"; exit 0
}
# A write to main and a main-tree grader build must exclude each other. Without this an author's RED run compiled a
# tree that was being rewritten under it and reported a phantom CS1061 for a member HEAD declares (kit item
# IN-20260929183913-7850). The lock is released before the grader, which takes it itself.
# TIMING (owner request IN-20261106154815-b0f8, phase 0): one `TIMING <id> <step> <s>s` line per step of a patch,
# appended to .streams\logs\integrate-timing.log and written to the host (a detached drain's stdout log), so a drain's
# cost per step can be compared before and after a change to the drain. Each line measures the time since the previous
# one. The host stream keeps the lines out of the outcome lines callers read by position.
$script:stepWatch = [Diagnostics.Stopwatch]::StartNew()
function Write-StepTime([string] $Id, [string] $Step, [string] $Detail = '') {
    $line = "TIMING $Id $Step $([Math]::Round($script:stepWatch.Elapsed.TotalSeconds, 1))s$(if ($Detail) { " $Detail" })"
    $script:stepWatch.Restart()
    try { Add-LineTo (Join-Path $P.Logs 'integrate-timing.log') "$(Get-Now) $Session $line" } catch { }
    Write-Host $line
}
# BATCH DRAIN (kit item IN-20261106155331-d772, design in its evidence file): with config drain.batchMax N > 1, up to N
# ready rows whose patches touch disjoint paths, apply alone on main, and touch no id register or composition file are
# applied as ONE combined patch and graded row by row on it, the census once on the last grade; all green commits each
# row's own paths and pushes once. Any red reverses the whole batch, writes no row state, and the first row drains
# singly below, so its own grade decides as without a batch. The default, 1, never enters this branch.
$drainCfg = (Get-StreamConfig $P)['drain']
$batchMax = 1; if ($drainCfg -is [Collections.IDictionary] -and $drainCfg['batchMax']) { $batchMax = [int]$drainCfg['batchMax'] }
if ($batchMax -gt 1) {
    $bLock = Enter-MainTreeLock $P "integrate batch apply" 600
    if (-not $bLock) { "RETRY $($t.id) (main tree busy: $(Get-MainTreeLockHolder $P))"; exit 0 }
    $bRows = [Collections.Generic.List[object]]::new(); $bPatch = @{}; $bOwn = @{}
    $bSeen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($c in @($ready | Where-Object { $_.kind -in @('code', 'docs', 'mockup') -and -not (Test-InPlaceWriteSet $_.writeSet) -and (Test-DepsAt $doc $_ @('integrated', 'done')) })) {
        if ($bRows.Count -ge $batchMax) { break }
        $ok = $false
        $cp = [string](Get-Field $c 'artifacts', 'patch'); if ($cp -and -not [IO.Path]::IsPathRooted($cp)) { $cp = Join-Path $Repo $cp }
        if (((Get-Field $c 'artifacts', 'check') -or (Get-Field $c 'artifacts', 'grader')) -and $cp -and (Test-Path -LiteralPath $cp -PathType Leaf) -and -not @(Get-DependencyBaseDrift $P $doc $c | Where-Object { $_ }).Count) {
            $cps = @(Get-PatchPaths $cp | Where-Object { $_ })
            if ($cps.Count -and -not @($cps | Where-Object { $_ -match $script:AllocatorFileRx -or $_ -match $script:CompositionFileRx -or $bSeen.Contains($_) }).Count) {
                & git -C $Repo apply --check --binary --whitespace=nowarn $cp 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0 -and -not @(Get-AllocatorDuplicates $Repo $cp | Where-Object { $_ }).Count) { $ok = $true }
            }
        }
        # The first ready row must itself qualify, so a batch never lands a row ahead of one priority puts before it.
        if (-not $ok) { if (-not $bRows.Count) { break } else { continue } }
        $bRows.Add($c); $bPatch[[string]$c.id] = $cp; $bOwn[[string]$c.id] = $cps; foreach ($x in $cps) { [void]$bSeen.Add($x) }
    }
    $bStamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss')
    $bId = "batch-$bStamp"
    $combined = Join-Path $P.Patches "$bId.patch"
    $bOk = $false
    if ($bRows.Count -ge 2) {
        $sb = [Text.StringBuilder]::new()
        foreach ($r in $bRows) { $txt = [IO.File]::ReadAllText($bPatch[[string]$r.id]); [void]$sb.Append($txt); if (-not $txt.EndsWith("`n")) { [void]$sb.Append("`n") } }
        [IO.File]::WriteAllText($combined, $sb.ToString())
        & git -C $Repo apply --check --binary --whitespace=nowarn $combined 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $bOk = $true } else { Remove-Item -LiteralPath $combined -Force -ErrorAction SilentlyContinue }
    }
    if (-not $bOk) { $bLock.Dispose() } else {
        $bIds = @($bRows | ForEach-Object { [string]$_.id })
        Write-StepTime $bId 'check' ($bIds -join ',')
        $union = @($bSeen)
        # Census baseline over the union of the batch's paths. A stale baseline is run now, or emptied under
        # census.baselineOnRed; either way a census red in the batch grade sends the batch back to the single drain.
        $bCensus = (Get-StreamConfig $P)['census']
        if ($bCensus -is [Collections.IDictionary] -and $bCensus['script']) {
            $cRx = if ($bCensus['paths']) { [string]$bCensus['paths'] } else { '.' }
            $cScript = [string]$bCensus['script']; if (-not [IO.Path]::IsPathRooted($cScript)) { $cScript = Join-Path $Repo $cScript }
            if (@($union | Where-Object { $_ -match $cRx }).Count -and (Test-Path -LiteralPath $cScript)) {
                $bFile = Join-Path $P.Root 'suites\census-baseline.json'
                $cHead = (& git -C $Repo rev-parse HEAD 2>$null | Select-Object -First 1)
                $cDirtyText = (@(& git -C $Repo diff HEAD 2>$null) + @(& git -C $Repo ls-files --others --exclude-standard 2>$null)) -join "`n"
                $cDirty = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($cDirtyText))).Replace('-', '')
                $cOld = $null
                if (Test-Path -LiteralPath $bFile) { try { $cOld = Get-Content -LiteralPath $bFile -Raw | ConvertFrom-Json -AsHashtable } catch { $cOld = $null } }
                if (-not $cOld -or $cOld['head'] -ne $cHead -or $cOld['dirtyHash'] -ne $cDirty) {
                    New-Item -ItemType Directory -Path (Split-Path $bFile) -Force | Out-Null
                    if ($bCensus['baselineOnRed'] -eq $true) {
                        Write-AtomicText $bFile (@{ head = ''; dirtyHash = ''; fails = @(); at = (Get-Date).ToUniversalTime().ToString('o'); deferred = $true } | ConvertTo-Json -Depth 4)
                    } else {
                        $cOut = @(& pwsh -NoProfile -NonInteractive -File $cScript -Root $Repo 2>&1 | ForEach-Object { "$_" })
                        $cFails = @($cOut | Where-Object { $_ -match '^FAIL\s+([^\s:]+)' } | ForEach-Object { $Matches[1] })
                        Write-AtomicText $bFile (@{ head = $cHead; dirtyHash = $cDirty; fails = $cFails; at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 4)
                    }
                }
            }
        }
        Write-StepTime $bId 'baseline-census'
        [void](Invoke-Git $Repo @('apply', '--binary', '--whitespace=nowarn', $combined))
        $script:appliedPatch = $combined; $script:appliedTask = $t.id
        $bNew = @(Get-Content -LiteralPath $combined | ForEach-Object -Begin { $cur = $null } -Process {
                if ($_ -match '^diff --git a/(.+?) b/(.+)$') { $cur = $Matches[2] } elseif ($cur -and $_ -match '^new file mode') { $cur } })
        if ($bNew.Count) {
            $script:intentPaths = @(& git -C $Repo ls-files --others -- @bNew 2>$null)
            if ($script:intentPaths.Count) { & git -C $Repo add -N -f -- @($script:intentPaths) 2>&1 | Out-Null; if ($LASTEXITCODE -ne 0) { $script:intentPaths = @() } }
        }
        $bLock.Dispose()
        Write-StepTime $bId 'apply'
        $redId = ''
        for ($i = 0; $i -lt $bRows.Count; $i++) {
            $r = $bRows[$i]; $rid = [string]$r.id
            # Get-GradePendingPatch honors the marker only for the task the main-grader lock names, so it is rewritten
            # per row; it names the combined patch, so a base laid meanwhile reverses the whole batch out.
            Write-AtomicText (Join-Path $P.Root 'main-pending.json') (@{ task = $rid; patch = $combined; at = (Get-Now) } | ConvertTo-Json)
            try {
                if ($i -lt $bRows.Count - 1) { $null = @(& "$PSScriptRoot\Invoke-Grader.ps1" -Repo $Repo -Task $rid -Root $Repo -Label main -BeatSession $Session -NoCensus); $rc = $LASTEXITCODE }
                else { $null = @(& "$PSScriptRoot\Invoke-Grader.ps1" -Repo $Repo -Task $rid -Root $Repo -Label main -BeatSession $Session -CensusPaths $union); $rc = $LASTEXITCODE }
            } catch { $rc = -1 }
            Write-StepTime $bId "grader $rid" "exit $rc"
            if ($rc -ne 0) { $redId = $rid; break }
        }
        if (-not (Test-IntegratorLock $P $Session)) {
            $revLock = Enter-MainTreeLock $P "integrate $bId reverse" 600
            [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $combined))
            $script:appliedPatch = $null
            if ($revLock) { $revLock.Dispose() }
            & git -C $Repo update-index -q --refresh 2>&1 | Out-Null
            Add-Decision $P $Session "integrator lock lost to $(Get-IntegratorLockHolder $P) while batch $($bIds -join ',') graded on main; batch reversed, rows left built"
            "LOCK-LOST $($bIds -join ',') (batch reversed, still built)"; exit 5
        }
        if ($redId) {
            $revLock = Enter-MainTreeLock $P "integrate $bId reverse" 600
            [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $combined))
            $script:appliedPatch = $null
            if ($revLock) { $revLock.Dispose() }
            & git -C $Repo update-index -q --refresh 2>&1 | Out-Null
            $gone = @($script:intentPaths | Where-Object { $_ -and -not (Test-Path -LiteralPath (Join-Path $Repo $_)) })
            if ($gone.Count) { & git -C $Repo rm --cached -q --ignore-unmatch -- @gone 2>&1 | Out-Null }
            $script:intentPaths = @()
            Remove-Item -LiteralPath (Join-Path $P.Root 'main-pending.json') -Force -ErrorAction SilentlyContinue
            Write-StepTime $bId 'reverse'
            Add-Decision $P $Session "BATCH-RED $($bIds -join ',') (red: $redId); draining singly"
            "BATCH-RED $($bIds -join ',') (red: $redId); draining singly"
        } else {
            $landed = [Collections.Generic.List[object]]::new()
            foreach ($r in $bRows) {
                $u = @(& $update -Repo $Repo -Task $r.id -Role integrate -Session $Session -To integrated -Note "applied in $bId with $($bIds -join ','); grader PASS on main")
                if ($LASTEXITCODE -ne 0) { Add-Decision $P $Session "batch ${bId}: state write -To integrated for $($r.id) refused (exit $LASTEXITCODE): $($u -join ' ')"; break }
                $landed.Add($r); "INTEGRATED $($r.id)"
            }
            $script:appliedPatch = $null
            # A row whose state write was refused must not keep code on main: its own patch comes off (paths are disjoint).
            foreach ($r in @($bRows | Where-Object { $landed -notcontains $_ })) {
                $revLock = Enter-MainTreeLock $P "integrate $($r.id) reverse" 600
                try { [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $bPatch[[string]$r.id])) } finally { if ($revLock) { $revLock.Dispose() } }
                "RETRY $($r.id) (batch state write refused; its patch reversed, still built)"
            }
            if ($NoCommit -or -not $landed.Count) { exit 0 }
            $gitPolicy = Get-IntegrateGitPolicy $Repo
            if ($PushRef -eq '<profile>') { $PushRef = Resolve-StreamPushRef $Repo $gitPolicy.PushRef }
            if (-not $gitPolicy.Commit) {
                foreach ($r in $landed) { Add-Decision $P $Session "commit of $($r.id) skipped, left uncommitted: Commit is not allowed ($($gitPolicy.Why))"; "COMMIT SKIPPED $($r.id) (git policy: $($gitPolicy.Why))" }
                exit 0
            }
            $sha = ''; $done = @()
            foreach ($r in $landed) {
                $paths = @(Get-Content -LiteralPath $bPatch[[string]$r.id] | ForEach-Object { if ($_ -match '^diff --git a/(.+) b/(.+)$') { $Matches[1]; $Matches[2] } } | Sort-Object -Unique)
                try {
                    $staleLock = Clear-StaleGitIndexLock $P $Session $Repo; if ($staleLock) { "STALE-INDEX-LOCK removed $staleLock" }
                    [void](Invoke-Git $Repo (@('add', '-A', '-f', '--') + $paths))
                    [void](Invoke-Git $Repo (@('commit', '-q', '-m', "$($r.id): $($r.title)", '-m', "Integrated by stream-integrate ($Session) in $bId; grader PASS on main.", '-m', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>', '--') + $paths))
                    $sha = (Invoke-Git $Repo @('rev-parse', '--short', 'HEAD')) | Select-Object -First 1
                    Add-Decision $P $Session "committed $($r.id) as $sha ($bId)"
                    "COMMITTED $($r.id) $sha"; $done += [string]$r.id
                } catch {
                    Add-Decision $P $Session "commit of $($r.id) failed, left uncommitted: $($_.Exception.Message)"
                    "COMMIT FAILED $($r.id) (left uncommitted)"
                }
            }
            Write-StepTime $bId 'commit'
            $remotes = @(& git -C $Repo remote 2>$null)
            if ($sha -and $PushRef -and ($remotes -contains 'origin')) {
                if (-not $gitPolicy.Push) {
                    Add-Decision $P $Session "push of $sha to origin $PushRef skipped: Push is not allowed ($($gitPolicy.Why))"
                    "PUSH SKIPPED BATCH $($done -join ',') $sha (git policy: $($gitPolicy.Why))"
                } else {
                    try {
                        [void](Invoke-Git $Repo @('push', 'origin', "HEAD:$PushRef"))
                        Add-Decision $P $Session "pushed $sha to origin $PushRef ($bId)"
                        "PUSHED BATCH $($done -join ',') $sha -> $PushRef"
                    } catch {
                        Add-Decision $P $Session "push of $sha to origin $PushRef failed (commits stand, integration unaffected): $($_.Exception.Message)"
                        "PUSH FAILED BATCH $($done -join ',') $sha (committed; integration unaffected)"
                    }
                    Write-StepTime $bId 'push'
                }
            }
            exit 0
        }
    }
}$applyLock = Enter-MainTreeLock $P "integrate $($t.id) apply" 600
if (-not $applyLock) { "RETRY $($t.id) (main tree busy: $(Get-MainTreeLockHolder $P))"; exit 0 }
& git -C $Repo apply --check --binary --whitespace=nowarn $patch 2>&1 | Out-Null; $applyExit = $LASTEXITCODE
# STRAY-EMPTY (kit item IN-20261019112954-86bc): a 0-byte UNTRACKED file at a path the patch creates is not a moved
# base. A builder's [IO.File] call with a relative path resolves against the process directory, the main tree, not
# its Set-Location worktree, and left an empty tests/Tests.Web/CredentialPickerTests.cs there; G14.T028 REBASEd twice
# on it. Such files are moved to .streams\stray\<id>-<stamp>\ (never deleted) and the check re-run; when the patch
# still does not apply they are put back, so only a stray that alone blocked the apply is cleared.
if ($applyExit -ne 0) {
    $created = [Collections.Generic.List[string]]::new(); $cur = $null
    foreach ($l in [IO.File]::ReadLines($patch)) {
        if ($l -match '^diff --git a/(.+?) b/(.+)$') { $cur = $Matches[2] } elseif ($cur -and $l -match '^new file mode') { $created.Add($cur) }
    }
    $strays = @()
    if ($created.Count) {
        $strays = @(& git -C $Repo ls-files --others -- @created 2>$null | Where-Object {
                $sp = Join-Path $Repo $_; (Test-Path -LiteralPath $sp -PathType Leaf) -and (Get-Item -LiteralPath $sp).Length -eq 0 })
    }
    if ($strays.Count) {
        $strayDir = Join-Path $P.Root "stray\$($t.id)-$((Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))"
        foreach ($s in $strays) {
            $dst = Join-Path $strayDir $s; New-Item -ItemType Directory -Path (Split-Path $dst) -Force | Out-Null
            Move-Item -LiteralPath (Join-Path $Repo $s) -Destination $dst
        }
        & git -C $Repo apply --check --binary --whitespace=nowarn $patch 2>&1 | Out-Null; $applyExit = $LASTEXITCODE
        if ($applyExit -eq 0) {
            Add-Decision $P $Session "$($t.id): moved empty untracked file(s) at patch paths out of the main tree to $strayDir before apply: $($strays -join ', ')"
            "STRAY-EMPTY $($t.id) $($strays -join ',')"
        } else {
            foreach ($s in $strays) { Move-Item -LiteralPath (Join-Path $strayDir $s) -Destination (Join-Path $Repo $s) }
        }
    }
}
# ORDERED-BY-MERGE (kit item IN-20261018134210-ede5): rows that share a composition file unordered only append there,
# so a patch that no longer applies only because another row appended to the same file is merged by its added lines
# (lib New-CompositionMergedPatch) and that merged patch is applied, graded, reversed and committed instead. Anything
# else that does not apply is still a REBASE.
$clean = $applyExit -eq 0; $mergeWhy = ''
if (-not $clean) {
    $merge = New-CompositionMergedPatch $Repo $patch (Join-Path $P.Patches "$($t.id).merged.patch")
    if ($merge.Ok) {
        $clean = $true; $patch = $merge.Path
        Add-Decision $P $Session "$($t.id): patch merged by its added lines into $($merge.Files -join ', ') (ORDERED-BY-MERGE), applying $($t.id).merged.patch"
        "MERGED $($t.id) $($merge.Files -join ',')"
    } elseif ($merge.Reason -ne 'the conflict is not in a composition file') { $mergeWhy = "; composition merge refused: $($merge.Reason)" }
}
# ALREADY-ON-MAIN (kit item IN-20261019062723-9b6e): a patch that does not apply because main already holds it (it
# reverse-applies clean) is not a moved base. Bouncing it looped: G13.T033 sat on main uncommitted, REBASE sent it to a
# builder, the rebuilt identical patch REBASEd again. Held uncommitted, it is graded in place and committed like an
# apply (a red grader reverses it, so main keeps no work the row does not record). Held in HEAD already, there is
# nothing to apply or commit: the row is integrated with a note.
$alreadyOnMain = $false
if (-not $clean) {
    & git -C $Repo apply --check --reverse --binary --whitespace=nowarn $patch 2>&1 | Out-Null
    if ($LASTEXITCODE -eq 0) {
        $held = @(Get-PatchPaths $patch)
        & git -C $Repo diff --quiet HEAD -- @held 2>&1 | Out-Null; $sameAsHead = $LASTEXITCODE -eq 0
        $untracked = @(& git -C $Repo ls-files --others --exclude-standard -- @held 2>$null)
        if ($sameAsHead -and -not $untracked.Count) {
            $applyLock.Dispose()
            $u = @(& $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To integrated -Note 'already on main: the patch content is committed on HEAD; nothing applied or committed')
            if ($LASTEXITCODE -ne 0) { throw "state write -To integrated refused (exit $LASTEXITCODE): $($u -join ' ')" }
            Add-Decision $P $Session "$($t.id): patch already committed on HEAD (reverse-applies clean, no diff); integrated with no apply or commit"
            "INTEGRATED $($t.id) (already in HEAD)"; exit 0
        }
        $clean = $true; $alreadyOnMain = $true
        Add-Decision $P $Session "$($t.id): patch already applied on main uncommitted (reverse-applies clean); grading in place instead of REBASE"
        "ALREADY-APPLIED $($t.id)"
    }
}
# ID REGISTER (kit item IN-20261023221543-c537): rows append to ids.yaml unordered, so two may allocate the same id; a
# patch that allocates an id main already allocates applies clean but must not land: rebase, so the builder re-numbers.
if ($clean -and -not $alreadyOnMain) {
    $dupIds = @(Get-AllocatorDuplicates $Repo $patch)
    if ($dupIds.Count) {
        $clean = $false; $mergeWhy = "; id register: $($dupIds -join ', ') already allocated on main, re-number"
        Add-Decision $P $Session "$($t.id): allocates $($dupIds -join ', ') already allocated on main (ids.yaml, parallel allocation); REBASE to re-number"
        "ID-CLASH $($t.id) $($dupIds -join ',')"
    }
}
if (-not $clean) {
    & $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To ticketed -Note "rebase: base moved (patch kept as the builder's starting point)$mergeWhy" | Out-Null
    $applyLock.Dispose()
    "REBASE $($t.id)"; exit 0
}
Write-StepTime $t.id 'check'
$baselineState = 'none'
$script:deferredCensus = $null
# CENSUS BASELINE (kit item IN-20261023162852-ea21): before the apply, while this session holds the main tree, the repo
# census (config "census") is run on main as it stands when the cached baseline is for another HEAD or dirty tree, so
# Invoke-Grader can tell main's own census red (BASELINE) from red this patch brings. Only when the patch touches a
# census path: a patch the census never judges costs no census run.
$censusCfg = (Get-StreamConfig $P)['census']
if ($censusCfg -is [Collections.IDictionary] -and $censusCfg['script'] -and -not $alreadyOnMain) {
    $cRx = if ($censusCfg['paths']) { [string]$censusCfg['paths'] } else { '.' }
    $cPaths = @(Get-Content -LiteralPath $patch | Where-Object { $_ -match '^diff --git a/(\S+) b/' } | ForEach-Object { $Matches[1] } | Where-Object { $_ -match $cRx })
    $cScript = [string]$censusCfg['script']; if (-not [IO.Path]::IsPathRooted($cScript)) { $cScript = Join-Path $Repo $cScript }
    if ($cPaths.Count -and (Test-Path -LiteralPath $cScript)) {
        $bFile = Join-Path $P.Root 'suites\census-baseline.json'
        $cHead = (& git -C $Repo rev-parse HEAD 2>$null | Select-Object -First 1)
        $cDirtyText = (@(& git -C $Repo diff HEAD 2>$null) + @(& git -C $Repo ls-files --others --exclude-standard 2>$null)) -join "`n"
        $cDirty = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($cDirtyText))).Replace('-', '')
        $cOld = $null
        if (Test-Path -LiteralPath $bFile) { try { $cOld = Get-Content -LiteralPath $bFile -Raw | ConvertFrom-Json -AsHashtable } catch { $cOld = $null } }
        $baselineState = 'cached'
        if ($censusCfg['baselineOnRed'] -eq $true -and (-not $cOld -or $cOld['head'] -ne $cHead -or $cOld['dirtyHash'] -ne $cDirty)) {
            # BASELINE-ON-RED (kit item IN-20261106155330-1e2e, config census.baselineOnRed): the baseline census is run
            # only once the graded patch shows a census red. A stale baseline must not excuse a red, so it is emptied:
            # the grade sees every census FAIL as new, and the red path below re-runs the census on main to sort them.
            $baselineState = 'deferred'
            $script:deferredCensus = @{ script = $cScript; file = $bFile }
            New-Item -ItemType Directory -Path (Split-Path $bFile) -Force | Out-Null
            Write-AtomicText $bFile (@{ head = ''; dirtyHash = ''; fails = @(); at = (Get-Date).ToUniversalTime().ToString('o'); deferred = $true } | ConvertTo-Json -Depth 4)
        } elseif (-not $cOld -or $cOld['head'] -ne $cHead -or $cOld['dirtyHash'] -ne $cDirty) {
            $baselineState = 'ran'
            $cOut = @(& pwsh -NoProfile -NonInteractive -File $cScript -Root $Repo 2>&1 | ForEach-Object { "$_" })
            $cFails = @($cOut | Where-Object { $_ -match '^FAIL\s+([^\s:]+)' } | ForEach-Object { $Matches[1] })
            New-Item -ItemType Directory -Path (Split-Path $bFile) -Force | Out-Null
            Write-AtomicText $bFile (@{ head = $cHead; dirtyHash = $cDirty; fails = $cFails; at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 4)
            if ($cFails.Count) { Add-Decision $P $Session "census baseline on main before $($t.id): already red $($cFails -join ',')" }
        }
    }
}
Write-StepTime $t.id 'baseline-census' $baselineState
if (-not $alreadyOnMain) { [void](Invoke-Git $Repo @('apply', '--binary', '--whitespace=nowarn', $patch)) }
$script:appliedPatch = $patch; $script:appliedTask = $t.id
# INTENT-TO-ADD (kit item IN-20261106113700-53f1): a check that reads the index (a census over `git ls-files --cached`)
# sees a file the patch creates in the builder's worktree, where Export-TaskPatch staged it, but not on main, where the
# apply leaves it untracked; G21.T115 and G17.T114 bounced on that alone. The new paths that are untracked here are
# marked intent-to-add for the grade; the drain's finally drops the mark again for any such path the patch no longer
# holds (reversed), so a bounce leaves the index as it found it.
$newPaths = @(Get-Content -LiteralPath $patch | ForEach-Object -Begin { $cur = $null } -Process {
        if ($_ -match '^diff --git a/(.+?) b/(.+)$') { $cur = $Matches[2] } elseif ($cur -and $_ -match '^new file mode') { $cur } })
if ($newPaths.Count) {
    $script:intentPaths = @(& git -C $Repo ls-files --others -- @newPaths 2>$null)
    # Best effort: a held index.lock (cleared later, before the commit) only costs the grade its index view.
    if ($script:intentPaths.Count) {
        & git -C $Repo add -N -f -- @($script:intentPaths) 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { Add-Decision $P $Session "$($t.id): could not mark new file(s) intent-to-add before the main grade: $($script:intentPaths -join ', ')"; $script:intentPaths = @() }
    }
}
# GRADE-PENDING (kit item IN-20261024221200-772a): while this patch sits on main for its grader, the grader holds
# main-grader.lock for the whole run (27 min for G23.T074) and every builder pre-stage starved behind it. The grade
# writes nothing tracked, so main is read-stable under it: this marker names the patch, and New-TaskWorktree lays a
# base beside the grade with the patch reversed out (lib Get-GradePendingPatch). The drain's finally removes it.
Write-AtomicText (Join-Path $P.Root 'main-pending.json') (@{ task = $t.id; patch = $patch; at = (Get-Now) } | ConvertTo-Json)
$applyLock.Dispose()
Write-StepTime $t.id 'apply'
# A grader that crashes must never leave the patch half-integrated on main: reverse it and bounce the task.
# The patch's own paths decide whether the repo census (config "census", Invoke-Grader) runs on main.
$censusPaths = @(Get-Content -LiteralPath $patch | Where-Object { $_ -match '^diff --git a/(\S+) b/' } | ForEach-Object { $Matches[1] })
try { $g = & "$PSScriptRoot\Invoke-Grader.ps1" -Repo $Repo -Task $t.id -Root $Repo -Label main -BeatSession $Session -CensusPaths $censusPaths; $gcode = $LASTEXITCODE }
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
# The grade's split by script comes from Invoke-Grader's `== <dir> <script> exit <n> in <s>s` section lines.
$gradeSplit = @(Get-Content -LiteralPath (Join-Path $P.Logs "$($t.id).grader.main.txt") -ErrorAction SilentlyContinue |
        ForEach-Object { if ("$_" -match '^== \S+ (\S+) exit -?\d+ in ([\d.]+)s$') { "$($Matches[1])=$($Matches[2])s" } })
Write-StepTime $t.id 'grader' ($gradeSplit -join ' ')
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
# BASELINE-ON-RED, the red half: a census FAIL in a grade whose baseline was deferred is sorted the way the pre-apply
# baseline sorts it. The patch comes off, the census runs on main as it stood, the patch goes back on, and a census id
# main already had is rewritten BASELINE in the main log; the grade passes when nothing else failed.
$censusLeaf = if ($script:deferredCensus) { Split-Path -Leaf $script:deferredCensus.script } else { '' }
$mainLogPath = Join-Path $P.Logs "$($t.id).grader.main.txt"
$gLines = @(Get-Content -LiteralPath $mainLogPath -ErrorAction SilentlyContinue)
if ($gcode -ne 0 -and $gcode -ne 8 -and $censusLeaf -and @($gLines | Where-Object { "$_" -match '^FAIL\s+CENSUS-' }).Count) {
    $redLock = Enter-MainTreeLock $P "integrate $($t.id) census baseline" 600
    try {
        [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $patch))
        $cHead = (& git -C $Repo rev-parse HEAD 2>$null | Select-Object -First 1)
        $cDirtyText = (@(& git -C $Repo diff HEAD 2>$null) + @(& git -C $Repo ls-files --others --exclude-standard 2>$null)) -join "`n"
        $cDirty = [BitConverter]::ToString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($cDirtyText))).Replace('-', '')
        $cOut = @(& pwsh -NoProfile -NonInteractive -File $script:deferredCensus.script -Root $Repo 2>&1 | ForEach-Object { "$_" })
        $cFails = @($cOut | Where-Object { $_ -match '^FAIL\s+([^\s:]+)' } | ForEach-Object { $Matches[1] })
        Write-AtomicText $script:deferredCensus.file (@{ head = $cHead; dirtyHash = $cDirty; fails = $cFails; at = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json -Depth 4)
        if ($cFails.Count) { Add-Decision $P $Session "census baseline on main for $($t.id) (run on red): already red $($cFails -join ',')" }
        [void](Invoke-Git $Repo @('apply', '--binary', '--whitespace=nowarn', $patch))
    } finally { if ($redLock) { $redLock.Dispose() } }
    $section = ''; $otherRed = $false; $censusNew = 0; $censusFail = 0
    $gLines = @($gLines | ForEach-Object {
            $line = "$_"
            if ($line -match '^== \S+ (\S+) exit (-?\d+) in [\d.]+s$') {
                $section = $Matches[1]
                if ($section -ne $censusLeaf -and [int]$Matches[2] -ne 0) { $otherRed = $true }
                $line
            } elseif ($section -eq $censusLeaf -and $line -match '^FAIL\s+([^\s:]+)') {
                $censusFail++
                if ($cFails -contains $Matches[1]) { "BASELINE $($Matches[1]) (red on main before this change)" } else { $censusNew++; $line }
            } else { $line }
        })
    Write-AtomicText $mainLogPath (($gLines -join [Environment]::NewLine) + [Environment]::NewLine)
    $verdict = 'red'
    if ($censusFail -and -not $censusNew -and -not $otherRed) { $gcode = 0; $verdict = 'pass' }
    Write-StepTime $t.id 'baseline-census' "ran-on-red $verdict"
}
if ($gcode -eq 0) {
    $u = @(& $update -Repo $Repo -Task $t.id -Role integrate -Session $Session -To integrated -Note $(if ($alreadyOnMain) { 'already applied on main (uncommitted, reverse-applies clean); grader PASS on main in place' } else { 'applied; grader PASS on main' }))
    if ($LASTEXITCODE -ne 0) { throw "state write -To integrated refused (exit $LASTEXITCODE): $($u -join ' ')" }
    $script:appliedPatch = $null
    "INTEGRATED $($t.id)"
    if ($NoCommit) { exit 0 }
    $gitPolicy = Get-IntegrateGitPolicy $Repo
    if ($PushRef -eq '<profile>') { $PushRef = Resolve-StreamPushRef $Repo $gitPolicy.PushRef }
    if (-not $gitPolicy.Commit) {
        Add-Decision $P $Session "commit of $($t.id) skipped, left uncommitted: Commit is not allowed ($($gitPolicy.Why))"
        "COMMIT SKIPPED $($t.id) (git policy: $($gitPolicy.Why))"; exit 0
    }
    # Commit exactly the paths the patch touched (both sides of a rename); other dirty or staged files stay out.
    # -f: an exact write-set file under a gitignored path (docs/audit/, .gitignore:98) is part of the patch, and a plain
    # add refused it, so the patch applied but never committed (kit item IN-20261021161717-670f). Only the patch's own
    # exact file paths are named, so nothing else ignored is ever added.
    $paths = @(Get-Content -LiteralPath $patch | ForEach-Object { if ($_ -match '^diff --git a/(.+) b/(.+)$') { $Matches[1]; $Matches[2] } } | Sort-Object -Unique)
    try {
        $staleLock = Clear-StaleGitIndexLock $P $Session $Repo; if ($staleLock) { "STALE-INDEX-LOCK removed $staleLock" }
        [void](Invoke-Git $Repo (@('add', '-A', '-f', '--') + $paths))
        $msg = "$($t.id): $($t.title)"
        [void](Invoke-Git $Repo (@('commit', '-q', '-m', $msg, '-m', "Integrated by stream-integrate ($Session); grader PASS on main.", '-m', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>', '--') + $paths))
        $sha = (Invoke-Git $Repo @('rev-parse', '--short', 'HEAD')) | Select-Object -First 1
        Add-Decision $P $Session "committed $($t.id) as $sha"
        "COMMITTED $($t.id) $sha"
        Write-StepTime $t.id 'commit'
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
            Write-StepTime $t.id 'push'
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
    # A census id red on main is never a grader defect: Invoke-Grader already took main's own census red out as
    # BASELINE, so what is left is red only with this patch (kit item IN-20261023162852-ea21).
    $censusRed = @($redIds | Where-Object { $_ -match '^CENSUS-' })
    if ($censusRed.Count) { $why += "census $($censusRed -join ',') red only with this patch" }
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
    # The patch names only the files the builder changed. A write-set file the patch never touched can still differ:
    # one a dependency landed on main after the worktree was cut is on main and absent from the worktree, so the check
    # read code on main the worktree never had (G14.R4F68, kit item IN-20261019210040-3dac). Exact write-set paths only.
    if ($wt -and (Test-Path $wt)) {
        $patched = @(Get-PatchPaths $patch)
        $wsOnly = @(@($t.writeSet) | ForEach-Object { "$_" -replace '\\', '/' } | Where-Object { $_ -and $_ -notmatch '[*?]' -and $_ -notmatch '/$' -and $_ -notin $patched })
        $wsDiff = @($wsOnly | Where-Object { -not (Test-SameContent $Repo $wt @($_)) })
        if ($wsDiff.Count) { $why += "write-set file(s) outside the patch differ between main and the worktree: $($wsDiff -join ', ')" }
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
    Write-StepTime $t.id 'reverse'
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
    Remove-Item -LiteralPath (Join-Path $P.Root 'main-pending.json') -Force -ErrorAction SilentlyContinue
    $gone = @($script:intentPaths | Where-Object { $_ -and -not (Test-Path -LiteralPath (Join-Path $Repo $_)) })
    if ($gone.Count) { & git -C $Repo rm --cached -q --ignore-unmatch -- @gone 2>&1 | Out-Null }
    $script:drainLock.Dispose()
    if (-not $prevTasksWait) { Remove-Item Env:\STREAM_TASKS_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue }
}
