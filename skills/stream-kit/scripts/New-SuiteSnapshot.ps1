# Lays down a frozen copy of the main tree for one group suite run (stream-integrate step B), so the suites compile and
# test the snapshot while authors and the integrator keep working on main.
#   New-SuiteSnapshot.ps1 -Repo <repo> -Session <integrator> -Group G2 -Run 5 [-CopyIgnored .env,.env.local] [-Log <suite log>]
# Why: a step-B run held .streams\main-grader.lock from its build to the end of its browser legs, 1.5-2 h. On
# 2026-10-02 G2 suites run 4 held it from 09:31 EDT into the afternoon, so every author RED re-run queued behind it,
# four root tickets could not be released, and builders read 0 claimable for over 2 hours (owner ruling, kit item
# IN-20261002150859-0d59). The lock exists so that no grader compiles a tree that is being rewritten (kit item
# IN-20260929183913-7850). A suite now compiles its own snapshot, which nothing rewrites, so the lock is held ONLY while
# the snapshot is read from main and never for the test run.
# The snapshot is the main tree as New-TaskWorktree.ps1 sees it (lib\Streams.ps1 Add-MainBase): HEAD, then main's
# uncommitted tracked diff, then its untracked non-ignored files, all staged. Ignored files never travel; -CopyIgnored
# names repo-relative ignored files the run needs (the compose stack reads .env and .env.local from the project folder).
# -CopyIgnored takes files or folders, as an array or one comma-separated string. The snapshot always gets a copy of the
# .streams folders graders read (graders, checks, mockups, tickets, patches, verdicts, owner, plans) and tasks.json,
# because .streams is untracked and a grader run with -Root <snapshot> reads them there (kit item
# IN-20261003220611-eaac: G2 suites run 5 had no .streams, no tests\Tests.E2E\.auth and no node_modules, so its
# Playwright legs and .streams-reading graders were invalid). node_modules is NOT copied: the caller runs npm ci in the
# snapshot (stream-integrate B.0).
# It is a detached worktree under the stream worktree root, named suite-<group>-<run>[-n]. Its record goes to
# .streams\suites\<name>.json and its ledger line to owner\worktrees.md. The watchdog keeps the NEWEST ready snapshot
# while its session holds a live integrator lock, and reaps every other one: a snapshot carries no work of its own.
# Prints "SNAPSHOT <path> HEAD <sha> dirty <n> untracked <m>" and then the path. With -Log the SNAPSHOT line is also
# appended there, so failures are attributed against that sha. Exit 5 = MAIN-GRADER-BUSY (the lock was not free inside
# the wait, STREAM_MAIN_LOCK_WAIT_SECONDS overrides); nothing is created.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [string] $Group,
    [Parameter(Mandatory)] [int] $Run,
    [string[]] $CopyIgnored = @(),
    [string] $Log = '',
    [string] $WorktreeRoot = ''
)
. "$PSScriptRoot\lib\Streams.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
if (-not $WorktreeRoot) { $WorktreeRoot = Get-StreamWorktreeRoot $Repo }
if (-not (Test-Path $WorktreeRoot)) { New-Item -ItemType Directory -Path $WorktreeRoot -Force | Out-Null }
if (-not (Test-Path $P.Suites)) { New-Item -ItemType Directory -Path $P.Suites -Force | Out-Null }
$base = "suite-$Group-$Run"; $name = $base; $n = 1
while ((Test-Path (Join-Path $WorktreeRoot $name)) -or (Test-Path (Join-Path $P.Suites "$name.json"))) { $n++; $name = "$base-$n" }
$wt = Join-Path $WorktreeRoot $name
$recFile = Join-Path $P.Suites "$name.json"
$CopyIgnored = @($CopyIgnored | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
foreach ($i in $CopyIgnored) {
    if (-not (Test-Path -LiteralPath (Join-Path $Repo $i))) { "REFUSED -CopyIgnored $i is not a file or folder in $Repo"; exit 2 }
}
$streamInputs = @('graders', 'checks', 'mockups', 'tickets', 'patches', 'verdicts', 'owner', 'plans')

$lock = Enter-MainTreeLock $P "suite snapshot $name by $Session"
if (-not $lock) { "MAIN-GRADER-BUSY suite snapshot $name (held by: $(Get-MainTreeLockHolder $P))"; exit 5 }
$rec = [ordered]@{ name = $name; path = $wt; group = $Group; run = $Run; session = $Session; state = 'creating'; head = ''; at = (Get-Now); seq = [DateTime]::UtcNow.Ticks }
try {
    # Read main exactly as New-TaskWorktree does: one pinned commit, the untracked list before the worktree exists.
    $sha = (Invoke-Git $Repo @('rev-parse', 'HEAD')) | Select-Object -First 1
    $rec.head = $sha
    $untracked = Get-MainUntracked $Repo
    # Recorded BEFORE the tree exists, so a tree left half-built by a failure below is still the watchdog's to reap.
    Write-AtomicText $recFile ($rec | ConvertTo-Json)
    [void](Invoke-Git $Repo @('worktree', 'add', '--detach', $wt, $sha))
    $diff = Join-Path $P.Logs "$name.base-main.patch"
    $goneUntracked = @(Add-MainBase $Repo $wt $sha $diff $untracked)
    foreach ($i in $CopyIgnored) {
        $src = Join-Path $Repo $i
        $dst = Join-Path $wt $i
        $dir = Split-Path $dst
        if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        if (Test-Path -LiteralPath $src -PathType Container) { Copy-Item -LiteralPath $src -Destination $dst -Recurse -Force }
        else { [IO.File]::Copy($src, $dst, $true) }
    }
    # .streams is untracked: graders run with -Root <snapshot> read it there. Ignored by git, so never staged.
    $snapStreams = Join-Path $wt '.streams'
    New-Item -ItemType Directory -Path $snapStreams -Force | Out-Null
    # Authors and the integrator write these folders while the copy runs: their temp files are skipped and a file that
    # vanishes mid-copy is tolerated (lib Copy-TreeTolerant, kit item IN-20261010211022-8ba5).
    $skippedInputs = [Collections.Generic.List[string]]::new()
    foreach ($d in $streamInputs) {
        $src = Join-Path $P.Root $d
        foreach ($s in (Copy-TreeTolerant $src (Join-Path $snapStreams $d))) { $skippedInputs.Add("$d\$s") }
    }
    $rec.skippedInputs = $skippedInputs.Count
    $tj = Join-Path $P.Root 'tasks.json'
    if (Test-Path -LiteralPath $tj) { [IO.File]::Copy($tj, (Join-Path $snapStreams 'tasks.json'), $true) }
    [void](Invoke-Git $wt @('add', '-A'))
    $dirty = @(& git -C $wt diff --cached --name-only $sha | Where-Object { $_ }).Count
    $rec.state = 'ready'; $rec.dirty = $dirty; $rec.untracked = $untracked.Count - $goneUntracked.Count; $rec.goneUntracked = $goneUntracked.Count; $rec.readyAt = (Get-Now)
    Write-AtomicText $recFile ($rec | ConvertTo-Json)
} catch {
    $rec.state = 'failed'; $rec.error = "$_"
    Write-AtomicText $recFile ($rec | ConvertTo-Json)
    throw
} finally { $lock.Dispose() }

Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | suite snapshot of HEAD {3} for {4} run {5}" -f $name, $wt, (Get-Now), $sha, $Group, $Run)
$line = "SNAPSHOT $wt HEAD $sha dirty $($rec.dirty) untracked $($rec.untracked)"
if ($Log) {
    if (-not [IO.Path]::IsPathRooted($Log)) { $Log = Join-Path $Repo $Log }
    Add-LineTo $Log $line
}
$line
$wt
