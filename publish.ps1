#requires -Version 7
<#
.SYNOPSIS
    Commit every change in the AI setup, rebase on the remote and push.

.DESCRIPTION
    The other half of install.ps1. Run it on the machine where you changed skills, the stream kit or memory:
      1. secret scan of the changed files: on a hit it lists file, line, rule and the masked match, and commits only
         if you type 'yes' (no console to answer on = nothing committed)
      2. git add -A; git commit
      3. git pull --rebase (a conflict stops here; resolve it with normal git, then re-run)
      4. git push

.EXAMPLE
    pwsh -NoProfile -File C:\devops\repos\ai-setup\publish.ps1 -Message "stream-author: tighten ticket clauses"
#>
[CmdletBinding()]
param(
    [string]$Message = "update from $env:COMPUTERNAME"
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot

git -C $repo add -A
$staged = @(git -C $repo diff --cached --name-only)
if ($staged.Count -eq 0) { Write-Host 'Nothing to publish.' }
else {
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
    git -C $repo commit -q -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
}

git -C $repo pull --rebase
if ($LASTEXITCODE -ne 0) { throw 'Rebase stopped on a conflict. Resolve it with git (status/add/rebase --continue), then re-run publish.' }

git -C $repo push
if ($LASTEXITCODE -ne 0) { throw 'git push failed.' }
Write-Host "Published $((git -C $repo rev-parse --short HEAD))."
