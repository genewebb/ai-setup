#requires -Version 7
<#
.SYNOPSIS
    Installs the shared PowerShell profile (from 'prof setup share') on THIS machine, for the account running it.

.DESCRIPTION
    Run it from the share folder it sits in (<repo>\ai\profile; it reads the files next to itself):
      1. PowerShell\             -> your PowerShell 7 profile folder (-ProfileDir; default: where $PROFILE lives).
                                    A file that exists and differs is backed up first (the folder is printed).
      2. modules.txt             -> installs the PSGallery modules you do not have yet (skip with -SkipModules).
      3. ProfileMachineConfig.md -> the machine config (-ConfigPath; default C:\Deploy\Setup\ProfileMachineConfig.md):
           - no file yet: every blank value is asked for (the "Used by" column says which commands read it), then
             the file is written. A folder that does not exist is a warning, not a stop.
           - the file exists: only rows whose key is missing are added (asked the same way); nothing else changes.
             -Force replaces it (old copy backed up).
           - -NonInteractive asks nothing and writes the template as it is (blank stays blank).
    -WhatIf lists what would change and writes nothing. Run it again after every git pull: unchanged files are skipped.

.NOTES
    Afterwards open a new PowerShell 7 window (or type . $PROFILE), then: machinecfg (your settings), prof help (the
    command groups), prof other (the typed commands). README.md one folder up (ai\README.md) explains every command.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [string]$ProfileDir,
    [string]$ConfigPath = 'C:\Deploy\Setup\ProfileMachineConfig.md',
    [switch]$SkipModules,
    [switch]$NonInteractive,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$dry = [bool]$WhatIfPreference
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path ([IO.Path]::GetTempPath()) "profile-install-$stamp"
$summary = [System.Collections.Generic.List[string]]::new()
$utf8 = [Text.UTF8Encoding]::new($false)

function Step([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }
function Warn([string]$m) { Write-Host "  WARNING: $m" -ForegroundColor Yellow }
function Backup([string]$Path, [string]$Rel) {
    $bak = Join-Path $backupDir $Rel
    New-Item -ItemType Directory -Force -Path (Split-Path $bak) | Out-Null
    Copy-Item -LiteralPath $Path -Destination $bak
}

# The profile folder comes from PowerShell itself, not from an assumed Documents path (OneDrive can move Documents).
$pwshDir = if ($ProfileDir) { $ProfileDir } else { Split-Path $PROFILE.CurrentUserCurrentHost }

Write-Host "Installing the shared profile from $here as $([Security.Principal.WindowsIdentity]::GetCurrent().Name)$(if ($dry) { ' (-WhatIf: nothing is written)' })"
Write-Host "  PowerShell 7 profile folder : $pwshDir"
Write-Host "  machine config              : $ConfigPath"
Write-Host "  backups of replaced files   : $backupDir"

# 1. The profile folder: copy every file whose hash differs; back up the old one.
Step 'PowerShell profile'
$from = Join-Path $here 'PowerShell'
if (-not (Test-Path -LiteralPath $from)) { Write-Host '  no PowerShell folder next to this script; skipped' }
else {
    $updated = 0
    foreach ($f in Get-ChildItem -LiteralPath $from -Recurse -File) {
        $rel = [IO.Path]::GetRelativePath($from, $f.FullName)
        $dest = Join-Path $pwshDir $rel
        if ((Test-Path -LiteralPath $dest) -and (Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash) { continue }
        $updated++
        if ($dry) { Write-Host "  would update $dest"; continue }
        if (Test-Path -LiteralPath $dest) { Backup $dest "PowerShell\$rel" }
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host "  updated $dest"
    }
    $summary.Add("PowerShell profile: $updated file(s) $(if ($dry) { 'would be updated' } else { 'updated' }) in $pwshDir$(if ($updated -and -not $dry) { "; old copies in $backupDir" })")

    # Files an earlier share installed that this share no longer has (an unpicked category, a module no picked command
    # calls). The profile dot-sources every profile.d\*.ps1 and imports every Gene.* module, so a stale file would still
    # load. Only those two places are swept, and only files the manifest (prof-share.json) does not list; anything else
    # in the profile folder is the coworker's own. Removed files go to the backup folder first.
    $manifestFile = Join-Path $here 'prof-share.json'
    if (Test-Path -LiteralPath $manifestFile) {
        $shipped = @(((Get-Content -LiteralPath $manifestFile -Raw | ConvertFrom-Json -AsHashtable).files).Keys | ForEach-Object { $_ -replace '^PowerShell/', '' -replace '/', '\' })
        $swept = @(foreach ($area in 'profile.d', 'Modules') {
                $dir = Join-Path $pwshDir $area
                if (-not (Test-Path -LiteralPath $dir)) { continue }
                Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object {
                    $rel = [IO.Path]::GetRelativePath($pwshDir, $_.FullName)
                    ($area -eq 'profile.d' -or $rel -like 'Modules\Gene.*') -and $rel -notin $shipped
                }
            })
        foreach ($f in $swept) {
            $rel = [IO.Path]::GetRelativePath($pwshDir, $f.FullName)
            if ($dry) { Write-Host "  would remove $($f.FullName) (the share no longer has it)"; continue }
            Backup $f.FullName "PowerShell\$rel"
            Remove-Item -LiteralPath $f.FullName -Force
            Write-Host "  removed $($f.FullName) (the share no longer has it; copy in $backupDir)"
        }
        if ($swept.Count) { $summary.Add("$(if ($dry) { 'would remove' } else { 'removed' }) $($swept.Count) file(s) the share no longer has$(if (-not $dry) { " (copies in $backupDir)" })") }
    }
}

# 2. PSGallery modules listed in modules.txt (PowerShell edition rows only): install the missing ones. A failure (no
# internet, gallery down) is reported and the install goes on: the profile still loads without them.
Step 'PSGallery modules'
$modFile = Join-Path $here 'modules.txt'
if ($SkipModules -or -not (Test-Path -LiteralPath $modFile)) { Write-Host '  skipped' }
else {
    $listed = @(Get-Content -LiteralPath $modFile | Where-Object { $_ -match '^\s*PowerShell\s+(\S+)' } | ForEach-Object { $Matches[1] })
    $modInstalled = 0; $modFailed = [System.Collections.Generic.List[string]]::new()
    foreach ($m in $listed) {
        if (Get-Module -ListAvailable -Name $m) { continue }
        if ($dry) { Write-Host "  would install module $m"; $modInstalled++; continue }
        try { Install-Module $m -Scope CurrentUser -Force -AcceptLicense -Repository PSGallery; Write-Host "  installed module $m"; $modInstalled++ }
        catch { Warn "could not install module $m`: $($_.Exception.Message)"; $modFailed.Add($m) }
    }
    $summary.Add("modules: $modInstalled $(if ($dry) { 'would be installed' } else { 'installed' })$(if ($modFailed.Count) { "; FAILED: $($modFailed -join ', ')" })")
}

# 3. The machine config.
Step 'Machine config'
$rowRx = '^\s*\|\s*([A-Za-z][A-Za-z0-9]*)\s*\|([^|]*)\|([^|]*)\|([^|]*)\|'
function Get-Rows([string[]]$Lines) {
    foreach ($l in $Lines) {
        if ($l -match $rowRx -and $Matches[1] -ne 'Key') { [pscustomobject]@{ Key = $Matches[1]; Value = $Matches[2].Trim(); UsedBy = $Matches[3].Trim(); Status = $Matches[4].Trim() } }
    }
}
# The person installing owns this machine's file: every value written here, shared or typed, is set by them.
$installer = "$env:USERDOMAIN\$env:USERNAME"
function Format-Row($r) { "| $($r.Key) | $($r.Value) | $($r.UsedBy) | $(if ($r.Value) { "set by $installer" } else { 'fill in' }) |" }
function Ask-Row($r) {
    # A blank value in the template means "the coworker fills it in": ask, unless nothing may be asked.
    if ($r.Value -or $NonInteractive) { return $r }
    if ($dry) { Write-Host "  would ask for: $($r.Key) ($($r.UsedBy))"; return $r }
    Write-Host "  $($r.Key) ($($r.UsedBy)) - type the value, or Enter to leave it blank for now"
    $v = ([string](Read-Host "  $($r.Key)")).Trim()
    if ($v -and $v -match '^([A-Za-z]:\\|\\\\|%)' -and -not (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($v)))) {
        Warn "$($r.Key): $v does not exist on this machine (kept; fix it in $ConfigPath when it is there)"
    }
    [pscustomobject]@{ Key = $r.Key; Value = $v; UsedBy = $r.UsedBy; Status = '' }
}

$tpl = Join-Path $here 'ProfileMachineConfig.md'
if (-not (Test-Path -LiteralPath $tpl)) { Write-Host '  no ProfileMachineConfig.md next to this script; skipped' }
else {
    $tplLines = @(Get-Content -LiteralPath $tpl)
    $tplRows = @(Get-Rows $tplLines)
    $exists = Test-Path -LiteralPath $ConfigPath
    if ($exists -and -not $Force) {
        # Keep the file as it is; add the rows it lacks after its first table.
        $raw = [IO.File]::ReadAllText($ConfigPath)
        $nl = if ($raw -match "`r`n") { "`r`n" } else { "`n" }
        $lines = [System.Collections.Generic.List[string]]::new([string[]]($raw -split "`r?`n"))
        $have = @(Get-Rows $lines)
        $missing = @($tplRows | Where-Object { $_.Key -notin $have.Key })
        if ($dry) {
            foreach ($r in $missing) { [void](Ask-Row $r) }
            Write-Host "  would add $($missing.Count) row(s) to $ConfigPath (kept $($have.Count) row(s))"
            $summary.Add("machine config: would add $($missing.Count) row(s) to $ConfigPath")
        }
        else {
            $new = @($missing | ForEach-Object { Ask-Row $_ })
            if ($new.Count) {
                $last = -1; $in = $false
                for ($i = 0; $i -lt $lines.Count; $i++) {
                    if ($lines[$i] -match '^\s*\|') { $in = $true; $last = $i } elseif ($in) { break }
                }
                if ($last -lt 0) { throw "$ConfigPath has no table; cannot add rows. Run again with -Force to replace it." }
                $lines.InsertRange($last + 1, [string[]]@($new | ForEach-Object { Format-Row $_ }))
                [IO.File]::WriteAllText($ConfigPath, ($lines -join $nl), $utf8)
            }
            Write-Host "  kept $($have.Count) row(s), added $($new.Count) in $ConfigPath"
            $summary.Add("machine config: kept $($have.Count) row(s), added $($new.Count) ($ConfigPath)")
        }
    }
    else {
        $rows = @($tplRows | ForEach-Object { Ask-Row $_ })
        $header = [System.Collections.Generic.List[string]]::new()
        foreach ($l in $tplLines) { if ($l -match '^\s*\|') { break }; $header.Add($l.Replace('<MACHINE>', $env:COMPUTERNAME)) }
        $out = @($header) + @('| Key | Value | Used by | Status |', '|---|---|---|---|') + @($rows | ForEach-Object { Format-Row $_ }) + @('')
        if ($dry) {
            Write-Host "  would $(if ($exists) { 'replace' } else { 'create' }) $ConfigPath ($($rows.Count) row(s))"
            $summary.Add("machine config: would $(if ($exists) { 'replace' } else { 'create' }) $ConfigPath")
        }
        else {
            if ($exists) { Backup $ConfigPath 'ProfileMachineConfig.md' }
            New-Item -ItemType Directory -Force -Path (Split-Path $ConfigPath) | Out-Null
            [IO.File]::WriteAllText($ConfigPath, ($out -join "`n"), $utf8)
            if ($exists) { Write-Host "  replaced $ConfigPath (old copy in $backupDir)"; $summary.Add("machine config: replaced $ConfigPath (old copy in $backupDir)") }
            else { Write-Host "  created $ConfigPath ($($rows.Count) row(s))"; $summary.Add("machine config: created $ConfigPath") }
            $blank = @($rows | Where-Object { -not $_.Value })
            if ($blank.Count) { Write-Host "  still blank (the commands that need them say so): $($blank.Key -join ', ')" }
        }
    }
}

Step 'Summary'
foreach ($s in $summary) { Write-Host "  $s" }
Write-Host ''
Write-Host 'Next:' -ForegroundColor Cyan
Write-Host '  1. Open a new PowerShell 7 window (or type: . $PROFILE), then: machinecfg'
Write-Host '  2. prof help  lists the command groups; prof other  the typed commands. ..\README.md explains them.'
Write-Host "  3. Blank settings: edit $ConfigPath (the Value column), then . `$PROFILE again."
