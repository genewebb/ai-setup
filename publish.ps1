#requires -Version 7
<#
.SYNOPSIS
    Commit every change in the AI setup, rebase on the remote and push.

.DESCRIPTION
    The other half of install.ps1. Run it on the machine where you changed skills, the stream kit or memory:
      1. secret scan of the changed files (blocks the commit on a hit)
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
        git -C $repo reset -q
        $hits | Format-Table -AutoSize | Out-String | Write-Host
        throw 'Possible secrets in the change. Nothing was committed. Remove them (or move them to SecretsDir) and re-run.'
    }
    git -C $repo commit -q -m $Message
    if ($LASTEXITCODE -ne 0) { throw 'git commit failed.' }
}

git -C $repo pull --rebase
if ($LASTEXITCODE -ne 0) { throw 'Rebase stopped on a conflict. Resolve it with git (status/add/rebase --continue), then re-run publish.' }

git -C $repo push
if ($LASTEXITCODE -ne 0) { throw 'git push failed.' }
Write-Host "Published $((git -C $repo rev-parse --short HEAD))."
