# Install-CorpVm17Prereqs.ps1 -- the ELEVATED half of preparing CORPVM17 as the speedmerchants stream host.
# Run ON CORPVM17, signed in as corp\agenewe, in an elevated pwsh 7 (Run as administrator):
#   pwsh -NoProfile -File C:\tmp\stream-host\Install-CorpVm17Prereqs.ps1
# Everything goes on C: (CORPVM17 has no D: drive). Safe to re-run: each step checks first.
# It installs Git and the Python packages, creates the C: folders, then runs Install-StreamHost.ps1 with C: container
# root and WSL sized from this machine, which installs WSL2 and prints what is LEFT TO DO (the non-elevated steps).
param(
    [switch] $SkipInstallStreamHost
)
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
function Say([string] $m) { Write-Host "  $m" }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this from an elevated pwsh 7 (Run as administrator).' }
if ($env:COMPUTERNAME -ne 'CORPVM17') { throw "This script is for CORPVM17; this is $env:COMPUTERNAME." }

# 0. Machine size; WSL gets half the memory and all but two cores, because this box also runs Profisee and SQL Server.
Write-Host '0. machine'
$cores = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
$ramGB = [math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1MB)
$wslCpu = [math]::Max(2, $cores - 2)
$wslMem = '{0}GB' -f [math]::Max(8, [math]::Floor($ramGB / 2))
Say "$cores logical cores, $ramGB GB RAM -> WSL $wslCpu vCPU, $wslMem"
Say "hypervisor present: $((Get-CimInstance Win32_ComputerSystem).HypervisorPresent) (CORPVM17 is a VM: WSL2 needs nested virtualization enabled on its host)"

# 1. Git for Windows (machine-wide; includes Git Credential Manager).
Write-Host '1. git'
$gitExe = 'C:\Program Files\Git\cmd\git.exe'
if (Test-Path $gitExe) { Say "ok: $(& $gitExe --version)" }
else {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($winget) { winget install --id Git.Git -e --source winget --scope machine --silent --accept-package-agreements --accept-source-agreements }
    elseif (Test-Path 'C:\ProgramData\chocolatey\choco.exe') { & 'C:\ProgramData\chocolatey\choco.exe' install git -y }
    else { throw 'Neither winget nor choco found: install Git for Windows from https://git-scm.com/download/win' }
    if (-not (Test-Path $gitExe)) { throw "git install finished but $gitExe is missing" }
    Say "installed: $(& $gitExe --version)"
    $env:Path = "C:\Program Files\Git\cmd;$env:Path"
}

# 2. Python packages the requirements tooling needs (tools\requirements\reqtools.py).
Write-Host '2. python packages'
$py = 'C:\Python313\python.exe'
if (Test-Path $py) {
    & $py -m pip install --quiet --disable-pip-version-check pyyaml jsonschema referencing
    $vers = & $py -c 'import yaml, jsonschema, referencing; print(yaml.__version__, jsonschema.__version__)'
    if ($LASTEXITCODE) { throw 'python packages did not import after pip install' }
    Say "ok: pyyaml / jsonschema $vers"
} else { Say "SKIPPED: $py not found" }

# 3. Folders on C:.
Write-Host '3. folders'
foreach ($d in 'C:\devops\repos', 'C:\devops\worktrees', 'C:\devops\myworkspace', 'C:\scratch', 'C:\Deploy\Secrets', 'C:\DataArchive') {
    if (Test-Path $d) { Say "ok: $d" } else { New-Item -ItemType Directory -Force -Path $d | Out-Null; Say "created $d" }
}

# 4. The stream-host installer: .NET SDK check, WSL2, .wslconfig, Rancher check, clone check, node, Claude, env vars.
#    -ContainerRoot C:\ : Rancher keeps its WSL disks in its default place on C:; nothing is moved to D:.
if (-not $SkipInstallStreamHost) {
    Write-Host '4. Install-StreamHost.ps1'
    & (Join-Path $here 'Install-StreamHost.ps1') -ContainerRoot 'C:\' -WslProcessors $wslCpu -WslMemory $wslMem
}
Write-Host ''
Write-Host 'Never run Move-StreamHostLayout.ps1 on this machine: it moves things to D:, which CORPVM17 does not have.' -ForegroundColor Yellow
