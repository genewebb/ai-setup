#requires -Version 7
<#
.SYNOPSIS
    Installs the PowerShell profile from a 'prof setup export' zip on THIS machine, for the account running it.

.DESCRIPTION
    Run it from the unzipped folder (it reads the files next to itself):
      1. PowerShell\        -> the PowerShell 7 profile folder ($PROFILE): profile, powershell.config.json, Gene.* modules
      2. WindowsPowerShell\ -> the Windows PowerShell 5.1 profile folder (skip with -SkipWindowsPowerShell)
      3. modules.txt        -> installs the PSGallery modules that are missing (skip with -SkipModules)
      4. ProfileMachineConfig.md -> C:\Deploy\Setup\ProfileMachineConfig.md, only when that file does not exist yet
    A file that already exists and differs is backed up first (the backup folder is printed). Nothing else is touched.
    -WhatIf lists what would change and writes nothing.

.NOTES
    After it: edit C:\Deploy\Setup\ProfileMachineConfig.md (the Value column), then open a new PowerShell 7 window or
    type . $PROFILE, then machinecfg to see what resolved. AddOrUpdateMyTerminal.ps1 (Windows Terminal tabs) is
    separate and optional. The README.md next to this script explains every command.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ConfigPath = 'C:\Deploy\Setup\ProfileMachineConfig.md',
    [switch]$SkipWindowsPowerShell,
    [switch]$SkipModules
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$dry = $WhatIfPreference
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path ([IO.Path]::GetTempPath()) "profile-install-$stamp"
$summary = [System.Collections.Generic.List[string]]::new()

function Step([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }

# Profile folders come from PowerShell itself, not from an assumed Documents path (OneDrive can move Documents).
$pwshDir = Split-Path $PROFILE.CurrentUserCurrentHost
$winPsDir = $null
if (-not $SkipWindowsPowerShell -and (Get-Command powershell.exe -ErrorAction SilentlyContinue)) {
    try { $winPsDir = (& powershell.exe -NoProfile -NonInteractive -Command 'Split-Path $PROFILE.CurrentUserCurrentHost' 2>$null | Select-Object -First 1) } catch { }
    if (-not $winPsDir) { $winPsDir = Join-Path (Split-Path $pwshDir) 'WindowsPowerShell' }
}

Write-Host "Installing the profile from $here as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)$(if ($dry) { ' (-WhatIf: nothing is written)' })"
Write-Host "  PowerShell 7 profile folder : $pwshDir"
Write-Host "  Windows PowerShell folder   : $(if ($winPsDir) { $winPsDir } else { '(skipped)' })"
Write-Host "  machine config              : $ConfigPath"
Write-Host "  backups of replaced files   : $backupDir"

# 1 + 2. Profile folders: copy every file whose hash differs; back up the old one.
$targets = [ordered]@{ PowerShell = $pwshDir }
if ($winPsDir) { $targets['WindowsPowerShell'] = $winPsDir }
foreach ($edition in $targets.Keys) {
    Step $edition
    $from = Join-Path $here $edition
    if (-not (Test-Path -LiteralPath $from)) { Write-Host "  no $edition folder in the export; skipped"; continue }
    $to = $targets[$edition]
    $updated = 0
    foreach ($f in Get-ChildItem -LiteralPath $from -Recurse -File) {
        $rel = [IO.Path]::GetRelativePath($from, $f.FullName)
        $dest = Join-Path $to $rel
        if ((Test-Path -LiteralPath $dest) -and (Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash) { continue }
        $updated++
        if ($dry) { Write-Host "  would update $dest"; continue }
        if (Test-Path -LiteralPath $dest) {
            $bak = Join-Path $backupDir "$edition\$rel"
            New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
            Copy-Item -LiteralPath $dest -Destination $bak
        }
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host "  updated $dest"
    }
    $summary.Add("$edition profile: $(if ($dry) { "$updated file(s) would change" } else { "$updated file(s) updated" }) in $to$(if ($updated -and -not $dry) { "; old copies in $backupDir" })")
}

# 3. PSGallery modules listed in modules.txt: install the missing ones only. A failure (no internet, gallery down) is
# reported and the install goes on: the profile still loads without them.
Step 'PSGallery modules'
$modFile = Join-Path $here 'modules.txt'
if ($SkipModules -or -not (Test-Path -LiteralPath $modFile)) { Write-Host '  skipped' }
else {
    $listed = Get-Content -LiteralPath $modFile | Where-Object { $_ -match '^\s*(PowerShell|WindowsPowerShell)\s+(\S+)' } |
        ForEach-Object { [pscustomobject]@{ Edition = $Matches[1]; Name = $Matches[2] } }
    if (-not $winPsDir) { $listed = @($listed | Where-Object Edition -eq 'PowerShell') }
    $modInstalled = 0; $modFailed = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $listed) {
        $present = if ($m.Edition -eq 'PowerShell') { [bool](Get-Module -ListAvailable -Name $m.Name) }
                   else { (powershell.exe -NoProfile -NonInteractive -Command "[bool](Get-Module -ListAvailable -Name '$($m.Name)')") -eq 'True' }
        if ($present) { continue }
        if ($dry) { Write-Host "  would install $($m.Edition) module $($m.Name)"; $modInstalled++; continue }
        try {
            if ($m.Edition -eq 'PowerShell') { Install-Module $m.Name -Scope CurrentUser -Force -AcceptLicense -Repository PSGallery }
            else { powershell.exe -NoProfile -NonInteractive -Command "Install-Module '$($m.Name)' -Scope CurrentUser -Force -Repository PSGallery"; if ($LASTEXITCODE) { throw "powershell.exe exit $LASTEXITCODE" } }
            Write-Host "  installed $($m.Edition) module $($m.Name)"; $modInstalled++
        }
        catch { Write-Warning "  could not install $($m.Edition) module $($m.Name): $($_.Exception.Message)"; $modFailed.Add("$($m.Edition) $($m.Name)") }
    }
    $summary.Add("modules: $(if ($dry) { "$modInstalled would be installed" } else { "$modInstalled installed" })$(if ($modFailed.Count) { "; FAILED: $($modFailed -join ', ')" })")
}

# 4. The machine config: placed once, never overwritten (it is yours to edit).
Step 'Machine config'
$tpl = Join-Path $here 'ProfileMachineConfig.md'
if (-not (Test-Path -LiteralPath $tpl)) { Write-Host '  no ProfileMachineConfig.md in the export; skipped' }
elseif (Test-Path -LiteralPath $ConfigPath) { Write-Host "  $ConfigPath exists; kept as it is (compare it with the template by hand)"; $summary.Add("machine config: kept the existing $ConfigPath") }
elseif ($dry) { Write-Host "  would create $ConfigPath from the template"; $summary.Add("machine config: would create $ConfigPath") }
else {
    New-Item -ItemType Directory -Force -Path (Split-Path $ConfigPath) | Out-Null
    Copy-Item -LiteralPath $tpl -Destination $ConfigPath
    Write-Host "  created $ConfigPath"; $summary.Add("machine config: created $ConfigPath (fill in the Value column)")
}

Step 'Summary'
foreach ($s in $summary) { Write-Host "  $s" }
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host "  1. Edit $ConfigPath : fill in the Value column (a blank value = 'not on this machine')."
Write-Host '  2. Open a new PowerShell 7 window (or type: . $PROFILE), then: machinecfg'
Write-Host '  3. prof help  lists every command. README.md in this folder explains them.'
Write-Host '  4. Optional, Windows Terminal tabs: .\AddOrUpdateMyTerminal.ps1 -Help'
