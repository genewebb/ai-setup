#requires -Version 7
<#
.SYNOPSIS
    Copy the items listed in share.yaml into a work plugin-marketplace clone, after checking each one can stand alone.

.DESCRIPTION
    One way only: this private repo -> the work marketplace. For every listed skill or agent:
      1. checks: blocked patterns from share.yaml, machine-profile {Key} tokens, secrets, and references to
         private skills that are not promoted too (a promoted skill must not depend on something coworkers lack)
      2. mirrors skills\<name>\ to <TargetRepo>\skills\<name>\ (agents: agents\<name>.md -> <TargetRepo>\agents\<name>\AGENT.md)
      3. runs the target's scripts\build-plugins.sh when it has one
    Any failed check stops before anything is copied. It never commits or pushes the target; review its diff
    and commit there under that repo's own rules.

.EXAMPLE
    pwsh -NoProfile -File tools\Promote-ToWork.ps1 -TargetRepo C:\devops\repos\ai-profisee -WhatIf
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TargetRepo,
    [switch]$WhatIf
)
$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent
if (-not (Get-Module -ListAvailable powershell-yaml)) { throw 'powershell-yaml module missing (install.ps1 installs it).' }
Import-Module powershell-yaml
$share = Get-Content -LiteralPath (Join-Path $repo 'share.yaml') -Raw | ConvertFrom-Yaml
$skills = @($share.skills | Where-Object { $_ })
$agents = @($share.agents | Where-Object { $_ })
if ($skills.Count + $agents.Count -eq 0) { Write-Host 'share.yaml lists nothing to promote.'; return }
if (-not (Test-Path -LiteralPath $TargetRepo)) { throw "Target repo not found: $TargetRepo" }

$privateSkills = @(Get-ChildItem -LiteralPath (Join-Path $repo 'skills') -Directory | ForEach-Object Name)
$items = @(
    $skills | ForEach-Object { [pscustomobject]@{ Kind = 'skill'; Name = $_; Source = Join-Path $repo "skills\$_" } }
    $agents | ForEach-Object { [pscustomobject]@{ Kind = 'agent'; Name = $_; Source = Join-Path $repo "agents\$_.md" } }
)

$problems = [Collections.Generic.List[object]]::new()
foreach ($it in $items) {
    if (-not (Test-Path -LiteralPath $it.Source)) { $problems.Add([pscustomobject]@{ Item = $it.Name; Problem = "source missing: $($it.Source)" }); continue }
    $files = if ($it.Kind -eq 'skill') { Get-ChildItem -LiteralPath $it.Source -Recurse -File } else { Get-Item -LiteralPath $it.Source }
    foreach ($f in $files) {
        if ($f.Extension -in '.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.pdf') { continue }
        $text = Get-Content -LiteralPath $f.FullName -Raw
        if (-not $text) { continue }
        $rel = [IO.Path]::GetRelativePath($repo, $f.FullName)
        foreach ($pat in $share.blockedPatterns) {
            if ($text -match "(?i)$pat") { $problems.Add([pscustomobject]@{ Item = $it.Name; Problem = "$rel matches blocked pattern '$pat'" }) }
        }
        foreach ($m in [regex]::Matches($text, '\{([A-Z][A-Za-z]+(Root|Dir|Repo|Home|File|Share))\}')) {
            $problems.Add([pscustomobject]@{ Item = $it.Name; Problem = "$rel uses machine-profile key {$($m.Groups[1].Value)}" })
        }
        foreach ($m in [regex]::Matches($text, '`([a-z0-9]+(?:-[a-z0-9]+)*)`')) {
            $ref = $m.Groups[1].Value
            if ($ref -ne $it.Name -and $ref -in $privateSkills -and $ref -notin $skills) {
                $problems.Add([pscustomobject]@{ Item = $it.Name; Problem = "$rel references private skill '$ref' that is not promoted" })
            }
        }
    }
    $relFiles = @($files | ForEach-Object { [IO.Path]::GetRelativePath($repo, $_.FullName) })
    foreach ($h in @(& (Join-Path $PSScriptRoot 'Find-Secrets.ps1') -Root $repo -Files $relFiles)) {
        $problems.Add([pscustomobject]@{ Item = $it.Name; Problem = "$($h.File):$($h.Line) possible secret ($($h.Rule))" })
    }
}
if ($problems.Count) {
    $problems | Sort-Object Item, Problem -Unique | Format-Table -AutoSize -Wrap | Out-String | Write-Host
    throw "$($problems.Count) problem(s). Nothing was copied."
}

foreach ($it in $items) {
    $dest = if ($it.Kind -eq 'skill') { Join-Path $TargetRepo "skills\$($it.Name)" } else { Join-Path $TargetRepo "agents\$($it.Name)\AGENT.md" }
    if ($WhatIf) { Write-Host "would copy $($it.Kind) $($it.Name) -> $dest"; continue }
    if ($it.Kind -eq 'skill') {
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        Copy-Item -LiteralPath $it.Source -Destination $dest -Recurse
    } else {
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -LiteralPath $it.Source -Destination $dest -Force
    }
    Write-Host "copied $($it.Kind) $($it.Name) -> $dest"
}

$build = Join-Path $TargetRepo 'scripts\build-plugins.sh'
if (-not $WhatIf -and (Test-Path -LiteralPath $build)) {
    bash ($build -replace '\\', '/')
    if ($LASTEXITCODE -ne 0) { throw "Target build failed: $build" }
}
if (-not $WhatIf) { Write-Host "Done. Review and commit in $TargetRepo under its own rules." }
