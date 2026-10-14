<#
.SYNOPSIS
    Records a restore point before dispatching the Executor, WITHOUT creating a commit. Uses `git stash create`, which writes dangling objects and never moves HEAD, the branch, or the index.

.DESCRIPTION
    The default rollback (`git restore`) only undoes tracked modifications and cannot recover
    from a rollback that itself went wrong. A checkpoint gives the Verifier a real "put it all
    back" target for the whole worktree.

    Why `git stash create` and not `git stash push`: create only writes objects and prints a
    commit SHA — it does NOT clear your worktree, does NOT touch the branch or reflog, and does
    NOT create a commit on any branch. The manual-git policy stays intact; nothing is committed,
    pushed, or staged. Restore later with:

        git stash apply <sha>          (full stash semantics)
        git checkout <sha> -- <path>   (single file back)

    Untracked files are included via --include-untracked, which matters because new files are
    exactly the case `git restore` cannot undo.

    Checkpoints are appended to state.json's checkpoints[] so Invoke-Rollback.ps1 and the final
    report can find them. Dangling objects survive until `git gc` prunes them (default ~2 weeks),
    which comfortably outlives any loop.

.PARAMETER RootPath
    Absolute path to the repo root.

.PARAMETER Iteration
    Iteration number this checkpoint precedes.

.PARAMETER StatePath
    Path to state.json. Defaults to <RootPath>\.loop\state.json.

.PARAMETER IncludeUntracked
    Include untracked files in the checkpoint (default ON). Use -IncludeUntracked:$false to skip.

.PARAMETER Format
    'text' (default) or 'json'.

.EXAMPLE
    pwsh -File New-Checkpoint.ps1 -RootPath <repo> -Iteration 8

.OUTPUTS
    Appends to state.json:
      "checkpoints": [ { "iteration": 8, "stash_sha": "<40-hex>", "at": "<ISO UTC>", "untracked": true } ]
    Prints the SHA so the Verifier can log it in the PROGRESS entry.

.NOTES
    Exit codes: 0 = checkpoint created (or nothing to checkpoint — clean tree).
                1 = checkpointing unavailable (not a git repo, or no commits yet so there is no HEAD
                    for `git stash create`). The loop may continue without it — per-path rollback
                    still works via the index.
                2 = script error.
#>
[CmdletBinding()]
param(
    # Position 0 declared so every other parameter is name-only.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [int]$Iteration = 0,

    [string]$StatePath,

    [switch]$IncludeUntracked = $true,

    [ValidateSet('text', 'json')]
    [string]$Format = 'text'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LoopCommon.ps1"

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-LoopError "RootPath not found: $RootPath"
    exit 2
}
$RootPath = (Get-Item -LiteralPath $RootPath).FullName.TrimEnd('\', '/')

if (-not $StatePath) { $StatePath = Join-Path (Join-Path $RootPath '.loop') 'state.json' }

if (-not (Test-LoopGitRepo -RootPath $RootPath)) {
    Write-Host "[SKIP] Not a git repo - no checkpoint created. Rollback will fall back to file-level restore only." -ForegroundColor DarkYellow
    exit 1
}

# `git stash create` requires an initial commit. A freshly-initialized repo has no HEAD, which is a
# legitimate setup (see the loop test harness) — skip checkpointing rather than failing the iteration.
if (-not (Test-LoopGitHasHead -RootPath $RootPath)) {
    Write-Host "[SKIP] Repo has no commits yet (no HEAD) - 'git stash create' is unavailable, so no checkpoint was made." -ForegroundColor DarkYellow
    Write-Host "       Per-path rollback still works: 'git restore' reads the INDEX, and 'git clean' removes new files." -ForegroundColor DarkGray
    exit 1
}

$stashArgs = @('stash', 'create')
if ($IncludeUntracked) { $stashArgs += '--include-untracked' }

$res = Invoke-LoopGit -RootPath $RootPath -Arguments $stashArgs
if ($res.ExitCode -ne 0) {
    Write-Error ("git stash create failed: {0}" -f ($res.Lines -join '; '))
    exit 2
}

$sha = (@($res.Lines) | Where-Object { $_ -match '^[0-9a-f]{40}$' } | Select-Object -First 1)

if (-not $sha) {
    # Clean tree: git stash create prints nothing. Not an error.
    if ($Format -eq 'json') {
        [ordered]@{ created = $false; reason = 'clean-worktree'; iteration = $Iteration } | ConvertTo-Json
    } else {
        Write-Host ("[OK] Worktree clean at iteration {0} - nothing to checkpoint." -f $Iteration) -ForegroundColor DarkGray
    }
    exit 0
}

$state = Read-LoopJson -Path $StatePath
if (-not $state) {
    $state = [pscustomobject]@{
        version     = 1
        root        = $RootPath
        started_at  = Get-LoopUtcStamp
        checkpoints = @()
    }
}
if (-not ($state.PSObject.Properties.Name -contains 'checkpoints') -or -not $state.checkpoints) {
    $state | Add-Member -NotePropertyName checkpoints -NotePropertyValue @() -Force
}

$entry = [pscustomobject][ordered]@{
    iteration = $Iteration
    stash_sha = $sha
    at        = Get-LoopUtcStamp
    untracked = [bool]$IncludeUntracked
}
$state.checkpoints = @(@($state.checkpoints) + $entry)

Write-LoopJson -Object $state -Path $StatePath -Depth 8

if ($Format -eq 'json') {
    [ordered]@{ created = $true; iteration = $Iteration; stash_sha = $sha; state_path = $StatePath } | ConvertTo-Json
} else {
    Write-Host ("[OK] Checkpoint for iteration {0}: {1}" -f $Iteration, $sha) -ForegroundColor Green
    Write-Host ("     Restore with: git -C {0} stash apply {1}" -f $RootPath, $sha) -ForegroundColor DarkGray
    Write-Host  "     No commit was created - HEAD, branch, and index are untouched." -ForegroundColor DarkGray
}

exit 0
