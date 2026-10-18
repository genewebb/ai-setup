#requires -Version 7
<#
.SYNOPSIS
    Commit every change in the AI setup, rebase on the remote and push.

.DESCRIPTION
    The other half of install.ps1. Run it on the machine where you changed skills, the stream kit or memory:
      0. refuses on anything but the main branch with origin/main upstream, or while a rebase or merge is
         unfinished (resolve it with normal git first), so a half-done state is never pushed from
      1. shows every file that will be committed and asks once (-Yes skips; redirected input refuses without -Yes)
      2. secret scan of those files: on a hit it lists file, line, rule and the masked match, and commits only
         if you type 'yes' (no console to answer on = nothing committed)
      3. git add -A; git commit
      4. git fetch, then git rebase --rebase-merges onto origin/main ONLY when origin moved (a rebase onto an unchanged
         upstream replays every local commit and flattens a hand-made merge; --rebase-merges keeps one when there is
         something to rebase onto): a CONFLICT stops here with the files to resolve; a remote that cannot be reached
         stops here too, with your commit kept locally (re-run when the remote is back)
      5. git push; a push rejected because someone pushed meanwhile is rebased and pushed once more
    Ends with the published commit, its file count and the remote it went to. Your own installed runtime picks the
    change up at the next 'ai' start (or run install.ps1 -NoPull).

.EXAMPLE
    pwsh -NoProfile -File .\publish.ps1 -Message "stream-author: tighten ticket clauses"
.EXAMPLE
    pwsh -NoProfile -File .\publish.ps1 -Message "memory from the laptop" -Yes
#>
[CmdletBinding()]
param(
    [string]$Message = "update from $env:COMPUTERNAME",
    [switch]$Yes
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
# Named Invoke-Git, not Git: a function named Git would shadow git.exe for every call in this script, including its own.
function Invoke-Git([string[]]$GitArgs) { $o = & git -C $repo @GitArgs 2>&1; if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed: $($o -join ' ')" }; $o }

# 0. The right branch, with nothing half done.
$gitDir = (Invoke-Git @('rev-parse', '--git-dir')) | Select-Object -First 1
$gitDir = if ([IO.Path]::IsPathRooted($gitDir)) { $gitDir } else { Join-Path $repo $gitDir }
foreach ($x in @('rebase-merge', 'rebase-apply', 'MERGE_HEAD', 'CHERRY_PICK_HEAD')) {
    if (Test-Path -LiteralPath (Join-Path $gitDir $x)) { throw "A rebase, merge or cherry-pick is unfinished in $repo ($x). Finish it (git status tells you how: add the resolved files, then git rebase --continue, or git rebase --abort), then re-run publish." }
}
$branch = (Invoke-Git @('rev-parse', '--abbrev-ref', 'HEAD')) | Select-Object -First 1
if ($branch -ne 'main') { throw "publish.ps1 publishes main only; this clone is on '$branch'. A detached HEAD is usually a failed rebase: git status, then git rebase --abort or git checkout main." }
$upstream = & git -C $repo rev-parse --abbrev-ref '@{u}' 2>$null
if ($LASTEXITCODE -ne 0 -or $upstream -ne 'origin/main') { throw "main must track origin/main (now: $(if ($upstream) { $upstream } else { 'no upstream' })). Fix: git branch --set-upstream-to=origin/main main" }
# The machine's Git Credential Manager holds two GitHub accounts (work and personal) and asks which one on every
# fetch/push unless the remote URL names it; with no console to answer on (Claude, a remote run) that is a hang. This
# repo lives under the personal account, so pin it in origin's URL (a fresh clone has it without).
$origin = (Invoke-Git @('remote', 'get-url', 'origin')) | Select-Object -First 1
if ($origin -match '^https://github\.com/genewebb/') {
    Invoke-Git @('remote', 'set-url', 'origin', ($origin -replace '^https://github\.com/', 'https://genewebb@github.com/')) | Out-Null
    Write-Host 'origin now names the GitHub account (genewebb@github.com), so Git Credential Manager no longer asks which account.' -ForegroundColor Cyan
}

# 1. What goes in: shown before anything is staged for good.
Invoke-Git @('add', '-A') | Out-Null
$status = @(& git -C $repo status --short --untracked-files=all)
$staged = @(Invoke-Git @('diff', '--cached', '--name-only'))
$ahead = [int]((Invoke-Git @('rev-list', '--count', '@{u}..HEAD')) | Select-Object -First 1)
if ($staged.Count -eq 0 -and $ahead -eq 0) { Write-Host 'Nothing to publish: no changes and no unpushed commits.'; exit 0 }
if ($staged.Count) {
    Write-Host "Changes to commit on $branch ($($staged.Count) file(s)):" -ForegroundColor Cyan
    foreach ($l in $status) { Write-Host "  $l" }
}
if ($ahead) { Write-Host "Plus $ahead local commit(s) not yet on origin/main." -ForegroundColor Cyan }
if (-not $Yes) {
    if ([Console]::IsInputRedirected) { git -C $repo reset -q; throw 'publish.ps1 asks to confirm the files above, and its input is redirected. Nothing was committed. Re-run with -Yes.' }
    $answer = Read-Host "Publish these to origin/main$(if ($staged.Count) { " as '$Message'" })? [y/N]"
    if ($answer -notmatch '^(y|yes)$') { git -C $repo reset -q; Write-Host 'Stopped: nothing was committed or pushed.' -ForegroundColor Yellow; exit 1 }
}

# 2. Secrets. 3. Commit.
if ($staged.Count) {
    $hits = & (Join-Path $repo 'tools\Find-Secrets.ps1') -Root $repo -Files $staged
    if ($hits) {
        Write-Host 'Possible secrets in this change (middle of each match masked):' -ForegroundColor Yellow
        $hits | Format-Table File, Line, Rule, Match -AutoSize | Out-String -Width 300 | Write-Host
        # A test fixture that proves something refuses secrets looks exactly like a secret, so the owner decides.
        # No console to answer on (redirected input) means no decision, so it stops as before.
        $answer = if (-not [Console]::IsInputRedirected) { Read-Host "Publish anyway? Type 'yes' to commit and push these lines" } else { '' }
        if ($answer -ne 'yes') {
            git -C $repo reset -q
            throw 'Possible secrets in the change. Nothing was committed. Remove them (or move them to SecretsDir) and re-run, or answer yes.'
        }
        Write-Host 'Publishing with the lines above, as you confirmed.' -ForegroundColor Yellow
    }
    Invoke-Git @('commit', '-q', '-m', $Message) | Out-Null
}

# 4. Rebase on the remote, only when it moved. `git pull --rebase` onto an UNCHANGED upstream still replays every local
#    commit and flattens a hand-made merge commit (2026-10-18: the SMVMTR1 merge was thrown away and its four conflicts
#    came straight back); --rebase-merges keeps a merge when there is something to rebase onto. A conflict and an
#    unreachable remote are different problems with different fixes.
& git -C $repo fetch origin
if ($LASTEXITCODE -ne 0) { throw "Could not fetch from origin (network, VPN or credentials; git's message is above). Your commit is safe in this clone; re-run publish when the remote is reachable." }
$behind = [int]((Invoke-Git @('rev-list', '--count', 'HEAD..@{u}')) | Select-Object -First 1)
if ($behind) {
    & git -C $repo rebase --rebase-merges '@{u}'
    if ($LASTEXITCODE -ne 0) {
        $conflicts = @(& git -C $repo diff --name-only --diff-filter=U)
        throw "Rebase stopped on a conflict in: $($conflicts -join ', '). Resolve each file, git add it, git rebase --continue (or git rebase --abort to undo), then re-run publish."
    }
}

# 5. Push, with one retry for a push that lost the race to someone else's push.
& git -C $repo push
if ($LASTEXITCODE -ne 0) {
    Write-Host 'Push rejected; rebasing once more and retrying.' -ForegroundColor Yellow
    & git -C $repo pull --rebase=merges
    if ($LASTEXITCODE -ne 0) { throw 'The retry rebase failed (see above). Resolve as git says, then re-run publish.' }
    & git -C $repo push
    if ($LASTEXITCODE -ne 0) { throw 'git push failed twice (see above). Credentials or permissions: fix as git says, then re-run publish; the commit is safe in this clone.' }
}
$head = (Invoke-Git @('rev-parse', '--short', 'HEAD')) | Select-Object -First 1
$remote = (Invoke-Git @('remote', 'get-url', 'origin')) | Select-Object -First 1
Write-Host "Published $head to $remote (main): $($staged.Count) file(s) committed$(if ($ahead) { ", $ahead earlier commit(s) pushed" }). Other machines: install.ps1. This machine: the next 'ai' start applies it." -ForegroundColor Green
