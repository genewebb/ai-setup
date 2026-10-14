#requires -Version 7
# WorktreeCreate hook (spec R25): Claude Code's built-in worktrees (--worktree, EnterWorktree, agent
# isolation: "worktree") are created under {WorktreesRoot}\<repo>\<name> instead of <repo>\.claude\worktrees,
# and only where the machine profile's git policy says Worktrees = yes.
#
# Contract (code.claude.com/docs/en/hooks, WorktreeCreate): input has repo_path, worktree_path, branch, detached;
# the hook prints the created path on stdout; any non-zero exit fails the creation.
# Wired directly (not through hook-dispatch, which always exits 0).
$ErrorActionPreference = 'Stop'

function Fail([string]$Why) { [Console]::Error.WriteLine("worktree-create: $Why"); exit 1 }

try {
    $d = [Console]::In.ReadToEnd() | ConvertFrom-Json
    $repo = [string]$d.repo_path
    $proposed = [string]$d.worktree_path
    $branch = [string]$d.branch
    if (-not $repo) { Fail 'no repo_path in the hook input.' }

    $libs = @((Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1'), (Join-Path $PSScriptRoot '..\..\lib\MachineConfig.psm1'))
    $lib = $libs | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $lib) { Fail 'MachineConfig.psm1 not found next to the hook.' }
    Import-Module $lib -Force -DisableNameChecking
    $prof = Get-AIMachineProfile

    $pol = Get-AIGitPolicy -Path $repo -Profile $prof
    if (-not $pol.RepoRoot) { Fail "$repo is not a git repository." }
    if (-not $pol.Worktrees) { Fail "worktrees are not allowed for $($pol.RepoRoot) (Git policy in $($prof.Path): Worktrees = no, or no row). Work in the main tree." }

    $root = $prof.Keys['WorktreesRoot']
    if (-not $root) { Fail "WorktreesRoot is not set in $($prof.Path)." }
    $name = if ($proposed) { Split-Path ($proposed -replace '/', '\').TrimEnd('\') -Leaf } else { $branch -replace '[\\/]', '-' }
    if (-not $name) { $name = 'wt-' + (Get-Date -Format 'yyyyMMdd-HHmmss') }
    $target = Join-Path (Join-Path $root (Split-Path $pol.RepoRoot -Leaf)) $name
    if (Test-Path -LiteralPath $target) { Fail "$target already exists." }
    New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null

    $git = @('-C', $pol.RepoRoot, 'worktree', 'add')
    if ($d.detached -eq $true -or -not $branch) { $git += @('--detach', $target) }
    else {
        & git -C $pol.RepoRoot show-ref --verify --quiet "refs/heads/$branch"
        if ($LASTEXITCODE -eq 0) { $git += @($target, $branch) } else { $git += @('-b', $branch, $target) }
    }
    $out = & git @git 2>&1
    if ($LASTEXITCODE -ne 0) { Fail "git worktree add failed: $($out -join ' ')" }
    [Console]::Out.WriteLine($target)
    exit 0
}
catch { Fail "$_" }
