#requires -Version 7
# WorktreeRemove hook (spec R25, D19): removes a built-in worktree that worktree-create.ps1 placed under
# {WorktreesRoot}, and NEVER a dirty one. Claude Code treats the removal as failed while the folder still exists.
# Wired directly (not through hook-dispatch, which always exits 0).
$ErrorActionPreference = 'Stop'

function Fail([string]$Why) { [Console]::Error.WriteLine("worktree-remove: $Why"); exit 1 }

try {
    $d = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $wt = [string]$d.worktree_path
    if (-not $wt -or -not (Test-Path -LiteralPath $wt)) { exit 0 }   # already gone

    $dirty = & git -C $wt status --porcelain 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "cannot read the status of $wt ($($dirty -join ' ')); left in place." }
    if ($dirty) { Fail "$wt has uncommitted changes; a dirty worktree is never removed. Commit or discard them, then remove it." }

    $main = [string]$d.repo_path
    if (-not $main) { $main = $wt }
    $out = & git -C $main worktree remove $wt 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "git worktree remove failed: $($out -join ' ')" }
    exit 0
}
catch { Fail "$_" }
