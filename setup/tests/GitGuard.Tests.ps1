#requires -Version 7
# Spec 5.9 git-guard tests, plus the R25 WorktreeCreate / WorktreeRemove redirect hooks.
# Scratch profile + three scratch repos (all yes; commit only; absent) + a worktree of the first.
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$scripts = Join-Path $PSScriptRoot '..\..\claude\scripts'
$guard = Join-Path $scripts 'git-guard.ps1'

$root = New-TestRoot 'gg'
$savedCfg = $env:AI_MACHINE_CONFIG
try {
    $repos = Join-Path $root 'repos'; $wtRoot = Join-Path $root 'worktrees'; $scratch = Join-Path $root 'scratch'
    New-Item -ItemType Directory $repos, $wtRoot, $scratch | Out-Null
    $all = Join-Path $repos 'all'; $commitOnly = Join-Path $repos 'commitonly'; $absent = Join-Path $repos 'absent'
    foreach ($r in $all, $commitOnly, $absent) {
        git init -q -b main $r
        git -C $r -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
    }
    $wt1 = Join-Path $wtRoot 'all\w1'
    git -C $all worktree add -q --detach $wt1 2>$null

    $cfg = Join-Path $root 'profile.md'
    New-TestProfile -Path $cfg -Keys ([ordered]@{ ReposRoot = $repos; AIWorkRoot = $root; ScratchRoot = $scratch; WorktreesRoot = $wtRoot; AllRepo = $all }) -Sections ([ordered]@{
            'Git policy' = "| Repo | Commit | Push | Worktrees | Note |`n|---|---|---|---|---|`n| {AllRepo} | yes | yes | yes | |`n| $commitOnly | yes | no | no | |"
        })
    $env:AI_MACHINE_CONFIG = $cfg

    function Invoke-Guard([string]$Command, [string]$Cwd) {
        $json = @{ tool_name = 'Bash'; cwd = $Cwd; tool_input = @{ command = $Command } } | ConvertTo-Json -Compress
        $out = $json | pwsh -NoProfile -File $guard
        return ($out -join '')
    }
    function Assert-Allowed([string]$Command, [string]$Cwd) { $o = Invoke-Guard $Command $Cwd; if ($o -match '"deny"') { throw "expected ALLOW for [$Command] in $Cwd, got $o" } }
    function Assert-Denied([string]$Command, [string]$Cwd, [string]$Like = '*') {
        $o = Invoke-Guard $Command $Cwd
        if ($o -notmatch '"deny"') { throw "expected DENY for [$Command] in $Cwd, got [$o]" }
        $reason = ($o | ConvertFrom-Json).hookSpecificOutput.permissionDecisionReason
        if ($reason -notlike $Like) { throw "deny reason [$reason] not like [$Like]" }
    }

    Test-Case 'read-only git is never blocked, in every repo' {
        foreach ($r in $all, $commitOnly, $absent) {
            foreach ($c in 'git status', 'git log --oneline -3', 'git diff HEAD', 'git branch --list', 'git branch', 'git worktree list', 'git stash list', 'git tag -l', 'git rev-parse HEAD', 'git show HEAD') {
                Assert-Allowed $c $r
            }
        }
    }
    Test-Case 'commit verbs: allowed where Commit = yes, denied where absent' {
        foreach ($c in 'git commit -m x', 'git add .', 'git reset --hard', 'git checkout -b x', 'git stash', 'git branch newb', 'git branch -D old', 'git tag v1', 'git merge x', 'git rebase main', 'git clean -fd', 'git apply --index p.patch', 'git pull') {
            Assert-Allowed $c $all
            Assert-Allowed $c $commitOnly
            Assert-Denied $c $absent '*Commit = no*'
        }
    }
    Test-Case 'push: allowed only where Push = yes' {
        Assert-Allowed 'git push origin main' $all
        Assert-Denied 'git push origin main' $commitOnly '*Push = no*'
        Assert-Denied 'git push' $absent
    }
    Test-Case 'git -C form targets the named repo' {
        Assert-Denied "git -C `"$absent`" commit -m x" $all
        Assert-Allowed "git -C `"$all`" commit -m x" $absent
        Assert-Denied "git -C $absent -c core.x=y add ." $all
    }
    Test-Case 'chained forms: ; && | and cd in the chain' {
        Assert-Denied "git status; git commit -m x" $absent
        Assert-Denied "git status && git push" $commitOnly
        Assert-Denied "cd `"$absent`" && git commit -m x" $all
        Assert-Allowed "cd `"$all`"; git commit -m x" $absent
        Assert-Denied "Set-Location $absent; git add -A" $all
        Assert-Allowed 'git log | Select-Object -First 3' $absent
    }
    Test-Case 'worktree follows its main repo' {
        Assert-Allowed 'git commit -m x' $wt1
        Assert-Allowed 'git push' $wt1
    }
    Test-Case 'worktree add: allowed under WorktreesRoot only, on the yes repo only' {
        Assert-Allowed "git worktree add `"$wtRoot\all\w2`" -b b2" $all
        Assert-Allowed "git worktree add -b b3 `"$wtRoot\all\w3`"" $all
        Assert-Denied "git worktree add `"$all\.claude\worktrees\x`"" $all '*must be under {WorktreesRoot}*'
        Assert-Denied "git worktree add ..\outside" $all '*must be under {WorktreesRoot}*'
        Assert-Denied "git worktree add `"$wtRoot\all\..\..\escape`"" $all '*must be under {WorktreesRoot}*'
        Assert-Denied "git worktree add `"$wtRoot\c\w`"" $commitOnly '*worktrees are not allowed*'
        Assert-Denied "git worktree add `"$wtRoot\a\w`"" $absent '*worktrees are not allowed*'
        Assert-Denied "git worktree remove --force `"$wt1`"" $all '*dirty worktree*'
        Assert-Allowed "git worktree prune" $all
    }
    Test-Case 'unevaluable commands: state-changing denied, read-only allowed (R19)' {
        Assert-Denied 'git commit -m "unbalanced' $all '*fails closed*'
        Assert-Allowed 'git log --format="%h' $all
        Assert-Denied 'git $verb -m x' $all '*built at run time*'
        Assert-Denied 'cd $somewhere; git commit -m x' $all '*fails closed*'
    }
    Test-Case 'deny message names the repo and the profile file' {
        Assert-Denied 'git commit -m x' $absent "*$absent*$cfg*"
    }
    Test-Case 'unreadable profile: state-changing denied, read-only allowed' {
        $env:AI_MACHINE_CONFIG = Join-Path $root 'missing.md'
        try {
            Assert-Denied 'git commit -m x' $all '*profile could not be read*'
            Assert-Allowed 'git status' $all
        }
        finally { $env:AI_MACHINE_CONFIG = $cfg }
    }
    Test-Case 'non-git commands pass untouched' {
        Assert-Allowed 'dotnet build' $absent
        Assert-Allowed 'echo digit commit' $absent
    }

    # --- R25 WorktreeCreate / WorktreeRemove redirect ---
    function Invoke-Hook([string]$Script, [hashtable]$Payload) {
        $json = $Payload | ConvertTo-Json -Compress
        $out = $json | pwsh -NoProfile -File (Join-Path $scripts $Script) 2>&1
        [pscustomobject]@{ Exit = $LASTEXITCODE; Out = ($out -join "`n") }
    }
    Test-Case 'WorktreeCreate redirects to {WorktreesRoot}\<repo>\<name> on a yes repo' {
        $r = Invoke-Hook 'worktree-create.ps1' @{ repo_path = $all; worktree_path = "$all\.claude\worktrees\feat1"; branch = 'worktree-feat1'; detached = $false }
        Assert-Equal 0 $r.Exit $r.Out
        Assert-Equal (Join-Path $wtRoot 'all\feat1') $r.Out.Trim()
        Assert-True (Test-Path (Join-Path $wtRoot 'all\feat1\.git'))
        Assert-True (-not (Test-Path "$all\.claude\worktrees\feat1"))
        Assert-Equal 'worktree-feat1' (git -C (Join-Path $wtRoot 'all\feat1') branch --show-current)
    }
    Test-Case 'WorktreeCreate refuses where Worktrees = no or the repo has no row' {
        foreach ($r0 in $commitOnly, $absent) {
            $r = Invoke-Hook 'worktree-create.ps1' @{ repo_path = $r0; worktree_path = "$r0\.claude\worktrees\x"; branch = 'worktree-x'; detached = $false }
            Assert-True ($r.Exit -ne 0) "expected failure for $r0"
            Assert-Match $r.Out 'not allowed'
        }
    }
    Test-Case 'WorktreeRemove refuses a dirty worktree and removes a clean one' {
        $w = Join-Path $wtRoot 'all\feat1'
        Set-Content (Join-Path $w 'dirty.txt') 'x'
        $r = Invoke-Hook 'worktree-remove.ps1' @{ repo_path = $all; worktree_path = $w; branch = 'worktree-feat1' }
        Assert-True ($r.Exit -ne 0) 'dirty remove should fail'
        Assert-True (Test-Path $w)
        Remove-Item (Join-Path $w 'dirty.txt')
        $r = Invoke-Hook 'worktree-remove.ps1' @{ repo_path = $all; worktree_path = $w; branch = 'worktree-feat1' }
        Assert-Equal 0 $r.Exit $r.Out
        Assert-True (-not (Test-Path $w))
    }
}
finally {
    $env:AI_MACHINE_CONFIG = $savedCfg
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
