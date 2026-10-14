#requires -Version 7
<#
.SYNOPSIS
    Pull the latest AI setup and install all of it on this machine.

.DESCRIPTION
    The only command a machine needs after a change was pushed from anywhere:
      1. git pull --ff-only (refuses to pull over unpublished local commits; run publish.ps1 first)
      2. Claude runtime: setup\Install-AIMachine.ps1 -CorpusRoot <this repo> (skills, agents, commands, scripts,
         CLAUDE.md, generated settings.json from this machine's profile)
      3. memory: ClaudeHome\memory becomes a junction to <this repo>\memory, so every session writes straight into
         the working tree and publish.ps1 carries it. A real folder found there is merged into the repo first and
         kept as memory.pre-git-<stamp>.
      4. PowerShell: pwsh\PowerShell -> Documents\PowerShell, pwsh\WindowsPowerShell -> Documents\WindowsPowerShell
         (profiles, powershell.config.json, own Gene.* modules). Changed files are backed up next to themselves.
         PSGallery modules listed in pwsh\modules.txt are installed when missing.
      5. stream-host scripts -> the profile's StreamHostDir (skipped when the key is absent or blank).

    -WhatIf or -Check also make steps 3-5 report without writing.

.EXAMPLE
    pwsh -NoProfile -File C:\devops\repos\ai-setup\install.ps1
.EXAMPLE
    pwsh -NoProfile -File C:\devops\repos\ai-setup\install.ps1 -NoPull -WhatIf
#>
[CmdletBinding()]
param(
    [switch]$NoPull,
    [switch]$WhatIf,
    [switch]$Check,
    [switch]$AcceptDrift,
    [string]$SecretsFile
)
$ErrorActionPreference = 'Stop'
$repo = $PSScriptRoot
$dry = $WhatIf -or $Check
$InstallerArgs = @{}
foreach ($n in "WhatIf", "Check", "AcceptDrift", "SecretsFile") { if ($PSBoundParameters.ContainsKey($n)) { $InstallerArgs[$n] = $PSBoundParameters[$n] } }
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
function Step([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }

# 1. pull
if (-not $NoPull) {
    Step 'git pull'
    git -C $repo pull --ff-only
    if ($LASTEXITCODE -ne 0) {
        throw "git pull --ff-only failed: unpublished local commits or a diverged branch. Run publish.ps1 first, then re-run install."
    }
}

# 2. Claude runtime
Step 'Claude runtime (Install-AIMachine)'
$global:LASTEXITCODE = 0
& (Join-Path $repo 'setup\Install-AIMachine.ps1') -CorpusRoot $repo @InstallerArgs
$installerExit = $LASTEXITCODE
if ($installerExit -notin 0, $null) { Write-Warning "Install-AIMachine exited $installerExit; continuing with memory, PowerShell and stream-host." }

Import-Module (Join-Path $repo 'lib\MachineConfig.psm1') -Force -DisableNameChecking
$keys = (Get-AIMachineProfile).Keys

# 3. memory junction
Step 'memory'
$live = Join-Path $keys['ClaudeHome'] 'memory'
$src = Join-Path $repo 'memory'
$item = Get-Item -LiteralPath $live -Force -ErrorAction SilentlyContinue
if ($item -and $item.LinkType -eq 'Junction' -and [IO.Path]::GetFullPath([string]($item.Target | Select-Object -First 1)).TrimEnd([char]92) -ieq [IO.Path]::GetFullPath($src).TrimEnd([char]92)) {
    Write-Host "  already linked -> $src"
}
elseif ($dry) {
    Write-Host "  would link $live -> $src$(if ($item) { ' (merging the existing folder into the repo first)' })"
}
else {
    if ($item) {
        if ($item.LinkType) { throw "$live is a $($item.LinkType) to $($item.Target), not to $src. Remove it by hand and re-run." }
        # merge: files missing from the repo, or newer locally, go into the repo before the switch
        foreach ($f in Get-ChildItem -LiteralPath $live -Recurse -File) {
            $rel = [IO.Path]::GetRelativePath($live, $f.FullName)
            $dest = Join-Path $src $rel
            $d = Get-Item -LiteralPath $dest -ErrorAction SilentlyContinue
            if (-not $d -or ((Get-FileHash $f.FullName).Hash -ne (Get-FileHash $dest).Hash -and $f.LastWriteTimeUtc -gt $d.LastWriteTimeUtc)) {
                New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
                Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
                Write-Host "  merged $rel"
            }
        }
        $kept = "$live.pre-git-$stamp"
        Rename-Item -LiteralPath $live -NewName (Split-Path $kept -Leaf)
        Write-Host "  old folder kept as $kept"
    }
    New-Item -ItemType Junction -Path $live -Target $src | Out-Null
    Write-Host "  linked $live -> $src"
}

# 4. PowerShell profiles and own modules
Step 'PowerShell'
$docs = [Environment]::GetFolderPath('MyDocuments')
foreach ($edition in 'PowerShell', 'WindowsPowerShell') {
    $from = Join-Path $repo "pwsh\$edition"
    if (-not (Test-Path -LiteralPath $from)) { continue }
    foreach ($f in Get-ChildItem -LiteralPath $from -Recurse -File) {
        $rel = [IO.Path]::GetRelativePath($from, $f.FullName)
        $dest = Join-Path $docs "$edition\$rel"
        if ((Test-Path -LiteralPath $dest) -and (Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash) { continue }
        if ($dry) { Write-Host "  would update $edition\$rel"; continue }
        if (Test-Path -LiteralPath $dest) { Copy-Item -LiteralPath $dest -Destination "$dest.bak-$stamp" }
        New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host "  updated $edition\$rel"
    }
}

# 4b. PSGallery modules listed in pwsh\modules.txt: install the missing ones only
$listed = Get-Content -LiteralPath (Join-Path $repo 'pwsh\modules.txt') | Where-Object { $_ -match '^\s*(PowerShell|WindowsPowerShell)\s+(\S+)' } |
    ForEach-Object { [pscustomobject]@{ Edition = $Matches[1]; Name = $Matches[2] } }
foreach ($m in $listed) {
    $present = if ($m.Edition -eq 'PowerShell') { [bool](Get-Module -ListAvailable -Name $m.Name) }
               else { (powershell.exe -NoProfile -Command "[bool](Get-Module -ListAvailable -Name '$($m.Name)')") -eq 'True' }
    if ($present) { continue }
    if ($dry) { Write-Host "  would install $($m.Edition) module $($m.Name)"; continue }
    if ($m.Edition -eq 'PowerShell') { Install-Module $m.Name -Scope CurrentUser -Force -AcceptLicense -Repository PSGallery }
    else { powershell.exe -NoProfile -Command "Install-Module '$($m.Name)' -Scope CurrentUser -Force -Repository PSGallery" }
    Write-Host "  installed $($m.Edition) module $($m.Name)"
}

# 5. stream-host scripts
Step 'stream-host'
$shDir = if ($keys.Contains('StreamHostDir')) { $keys['StreamHostDir'] } else { '' }
if (-not $shDir) { Write-Host '  StreamHostDir not set in this machine profile: skipped' }
else {
    foreach ($f in Get-ChildItem -LiteralPath (Join-Path $repo 'stream-host') -File) {
        $dest = Join-Path $shDir $f.Name
        if ((Test-Path -LiteralPath $dest) -and (Get-FileHash $f.FullName).Hash -eq (Get-FileHash $dest).Hash) { continue }
        if ($dry) { Write-Host "  would update $dest"; continue }
        New-Item -ItemType Directory -Force -Path $shDir | Out-Null
        if (Test-Path -LiteralPath $dest) { Copy-Item -LiteralPath $dest -Destination "$dest.bak-$stamp" }
        Copy-Item -LiteralPath $f.FullName -Destination $dest -Force
        Write-Host "  updated $dest"
    }
}

exit $installerExit
