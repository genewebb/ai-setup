# Saves the builder's change (everything unstaged in the worktree, new files included) as the task's patch.
# Refuses (exit 2, no patch written) when any changed file is outside the task's write set, and lists each one:
# the builder narrows its change or marks the task blocked; it never widens the write set.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Task,
    [Parameter(Mandatory)] [string] $Worktree,
    # Where to write. Default is the task's one patch. The watchdog passes a salvage path so an unverified harvest can
    # never overwrite a patch a builder already handed off: on 2026-09-30 a reap of a tree that was mid-verification
    # replaced G3.T030's good patch with one carrying a deliberate verifier mutation, and nothing on the board said so.
    [string] $OutFile = ''
)
. "$PSScriptRoot\lib\Streams.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$t = Get-Task (Read-Tasks $P) $Task
# An in-place task has no patch to export, and the honest answer is not EMPTY: git cannot see .streams at all, so a
# builder who wrote the artifact correctly would read EMPTY as "my work is gone" and start over.
if (Test-InPlaceWriteSet $t.writeSet) {
    "IN-PLACE $Task delivers under .streams\, which git ignores: there is no patch to export"
    'Write the artifact where the grader reads it, set artifacts.patch to that path, and move the task to built.'
    exit 2
}

# Only the NEW (untracked) files get intent-to-add so they show in the diff. `git add -N .` would also stage every
# deletion, which then drops out of `git diff` (index vs worktree) and silently out of the patch.
$untracked = @(& git -C $Worktree ls-files --others --exclude-standard)
if ($LASTEXITCODE -ne 0) { throw "git ls-files failed in $Worktree" }
if ($untracked.Count) {
    $list = [IO.Path]::GetTempFileName()
    try {
        [IO.File]::WriteAllLines($list, [string[]]$untracked, [Text.UTF8Encoding]::new($false))
        [void](Invoke-Git $Worktree @('add', '-N', "--pathspec-from-file=$list"))
    } finally { Remove-Item -LiteralPath $list -ErrorAction SilentlyContinue }
}
# stdout only: git's stderr warnings (CRLF conversion and the like) are not file names
$changed = @(& git -C $Worktree -c core.safecrlf=false diff --name-only | Where-Object { $_ })
if ($LASTEXITCODE -ne 0) { throw "git diff --name-only failed in $Worktree" }
if (-not $changed.Count) { 'EMPTY no change in worktree'; exit 2 }
$outside = @($changed | Where-Object { -not (Test-InWriteSet $_ $t.writeSet) })
if ($outside.Count) { $outside | ForEach-Object { "OUTSIDE $_" }; exit 2 }

$patch = if ($OutFile) { if ([IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path $Repo $OutFile } } else { Join-Path $P.Patches "$Task.patch" }
& git -C $Worktree -c core.safecrlf=false diff --binary --output=$patch
if ($LASTEXITCODE -ne 0) { throw "git diff failed in $Worktree" }
$changed | ForEach-Object { "IN $_" }
"PATCH $patch"
