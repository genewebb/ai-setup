# Creates the builder's detached worktree and lays the base down: HEAD, then the main tree's uncommitted diff, then its
# untracked non-ignored files, then the patches of dependencies that are built but not yet integrated. The whole base
# is staged in the worktree's own index, so the builder's change is exactly what `git diff` shows afterwards.
# No branch and no commit is created. Prints the worktree path.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Task,
    [Parameter(Mandatory)] [string] $Session,
    [string] $WorktreeRoot = ''
)
. "$PSScriptRoot\lib\Streams.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$doc = Read-Tasks $P
$t = Get-Task $doc $Task

if (-not $WorktreeRoot) { $WorktreeRoot = Get-StreamWorktreeRoot $Repo }
if (-not (Test-Path $WorktreeRoot)) { New-Item -ItemType Directory -Path $WorktreeRoot | Out-Null }
$name = $Task; $n = 1
while (Test-Path (Join-Path $WorktreeRoot $name)) { $n++; $name = "$Task-$n" }
$wt = Join-Path $WorktreeRoot $name

# Untracked, non-ignored files of the main tree, listed before the worktree exists (lib\Streams.ps1 Get-MainUntracked).
# ONE commit is the base, read once, before anything else. HEAD was read three times (worktree add, the main diff, the
# recorded fingerprint), and an integrator commit landing in between split the base: on 2026-10-01 G3.T205's worktree
# sat at a8edaaf, its recorded head said 95de2f1, and G3.T045 (committed between the two reads) arrived as its
# untracked test file without its two ValueEditor.razor edits (kit item IN-20261001203252-2789). Diffing the main tree
# against this pinned commit carries anything committed after it as part of the dirty diff, so nothing is lost.
$baseSha = (Invoke-Git $Repo @('rev-parse', 'HEAD')) | Select-Object -First 1
$untracked = Get-MainUntracked $Repo

[void](Invoke-Git $Repo @('worktree', 'add', '--detach', $wt, $baseSha))
# From here the tree exists. If anything below fails before the tree is recorded on the task, the tree is marked
# abandoned in worktrees.md, so it is visible and the reaper takes it. Before 2026-10-04 such a tree was recorded
# nowhere, and a builder's retry made <task>-2 and -3 beside it (G3.T170, kit item IN-20261004204921-2c98).
$recorded = $false
try {
# Test seam: a self-test sets STREAM_TEST_WORKTREE_HOOK to a script that commits to the main tree right here, where the
# G3.T045 commit landed.
if ($env:STREAM_TEST_WORKTREE_HOOK) { & $env:STREAM_TEST_WORKTREE_HOOK }

$sha = [Security.Cryptography.SHA256]::Create()
function Get-Hash([byte[]] $b) { [BitConverter]::ToString($sha.ComputeHash($b)).Replace('-', '').Substring(0, 16) }

# Whatever base is laid down is staged, even when a step below fails. On 2026-10-02 G3.T235 and G3.T202-2 failed
# applying a dependency patch, so the `git add -A` after step 3 never ran, and the owner's uncommitted compose.yaml and
# Dockerfile.coordinator sat UNSTAGED in both trees. The watchdog's export then called them work outside the write set
# and kept both trees forever (kit item IN-20261002073838-76a8). Staged, a failed tree reads EMPTY and is reaped.
try {
# 1-2. main tree's uncommitted tracked changes, then its untracked non-ignored files (listed above)
$mainDiff = Join-Path $P.Logs "$name.base-main.patch"
Add-MainBase $Repo $wt $baseSha $mainDiff $untracked

# 3. dependency patches that are built but not in the main tree yet, in dependency order
$depPatches = [Collections.Generic.List[string]]::new()
$notes = [Collections.Generic.List[string]]::new()
$seen = @{}
function Add-Deps($id) {
    foreach ($d in @((Get-Task $doc $id).dependsOn)) {
        if (-not $d -or $seen[$d]) { continue }
        $seen[$d] = $true
        Add-Deps $d
        $dt = Get-Task $doc $d
        if ($dt.state -ne 'built' -or $dt.kind -notin @('code', 'docs')) { continue }
        # An in-place dependency's artifacts.patch is the artifact's own path, not a patch: `git apply` on it fails,
        # and its file is under .streams, which no worktree carries anyway.
        if (Test-InPlaceWriteSet $dt.writeSet) { $script:notes.Add("IN-PLACE dependency $d delivers under .streams and carries no patch; nothing to apply") ; continue }
        if (-not $dt.artifacts.patch) { $script:notes.Add("WARN dependency $d is built with NO patch, so its change is NOT in this base") ; continue }
        $depPatches.Add($dt.artifacts.patch)
    }
}
Add-Deps $Task
# A dependency integrated WHILE this tree was made is already in the base: the integrator applies a patch to the main
# tree (and may commit it) before its row leaves `built`, so the dirty diff read above already holds it, and applying it
# again threw "patch does not apply" / "already exists in working directory" (G3.T301 over G3.T285, 2026-10-03, kit
# item IN-20261003225331-626c). The content decides, not the row state: a patch that does not apply forward but
# reverses cleanly is in the base and is skipped with a note. A patch that does neither still fails as before.
$applied = [Collections.Generic.List[string]]::new()
foreach ($pp in $depPatches) {
    $full = if ([IO.Path]::IsPathRooted($pp)) { $pp } else { Join-Path $Repo $pp }
    & git -C $wt apply --check --binary --whitespace=nowarn $full 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        & git -C $wt apply --check --reverse --binary --whitespace=nowarn $full 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) { $notes.Add("SKIPPED dependency patch $(Split-Path -Leaf $full): the base already holds it (integrated while this tree was made)"); continue }
    }
    [void](Invoke-Git $wt @('apply', '--binary', '--whitespace=nowarn', $full))
    $applied.Add($pp)
}
} catch {
    # Stage the partial base, then fail as before. Plain git, not Invoke-Git: a second error must not hide the first.
    & git -C $wt add -A 2>&1 | Out-Null
    throw
}

[void](Invoke-Git $wt @('add', '-A'))

$fp = [ordered]@{
    worktree  = $wt
    head      = $baseSha
    mainDiff  = (Get-Hash ([IO.File]::ReadAllBytes($mainDiff)))
    untracked = (Get-Hash ([Text.Encoding]::UTF8.GetBytes(($untracked -join "`n"))))
    deps      = @($applied | ForEach-Object { $f = if ([IO.Path]::IsPathRooted($_)) { $_ } else { Join-Path $Repo $_ }; '{0}:{1}' -f (Split-Path -Leaf $f), (Get-Hash ([IO.File]::ReadAllBytes($f))) })
    at        = Get-Now
}
# The one tasks.json write waits at least 120 s for the lock. The 15 s default ran out under planner churn, so the
# script died after making the tree (kit item IN-20261004204921-2c98). Integrate-Patch.ps1 widens its wait the same way.
$prevTasksWait = $env:STREAM_TASKS_LOCK_WAIT_SECONDS
if (-not ("$prevTasksWait" -match '^\d+$' -and [int]$prevTasksWait -ge 120)) { $env:STREAM_TASKS_LOCK_WAIT_SECONDS = '120' }
try { $r = & "$PSScriptRoot\Update-Task.ps1" -Repo $Repo -Task $Task -Role build -Session $Session -Base $fp -Beat -Note "worktree $wt"; $code = $LASTEXITCODE }
finally { if ($null -eq $prevTasksWait) { Remove-Item Env:\STREAM_TASKS_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue } else { $env:STREAM_TASKS_LOCK_WAIT_SECONDS = $prevTasksWait } }
if ($code -eq 3) {
    Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | abandoned (New-TaskWorktree: claim lost before the tree was recorded)" -f $Task, $wt, (Get-Now))
    $recorded = $true
    Write-Output $r; exit 3
}
$recorded = $true
Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | building" -f $Task, $wt, (Get-Now))
} catch {
    if (-not $recorded) {
        $why = ("$_" -split "`n")[0].Trim() -replace '\|', '/'
        try { Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | abandoned (New-TaskWorktree failed before the tree was recorded: {3})" -f $Task, $wt, (Get-Now), $why) } catch { }
    }
    throw
}
$notes | ForEach-Object { $_ }
$wt
