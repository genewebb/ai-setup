# Install-StreamHost.ps1 -- prepare a lab VM (SMVMTR1) to run the speedmerchants stream kit.
# Run it ON the VM, in an ELEVATED pwsh 7, inside the RDP session of the user who will run the Claude Code loops.
# Safe to re-run: every step checks first and skips what is already done. Prints what it did and what is left.
#   pwsh -NoProfile -File .\Install-StreamHost.ps1
# Code lives on C: only, laid out like the laptop: C:\devops\repos\speedmerchants and C:\devops\worktrees are real
# folders, never junctions to another drive.
param(
    [string] $ContainerRoot = 'D:\RancherDesktop',   # the Rancher Desktop WSL disks (containers, images, volumes)
    [string] $SdkVersion = '10.0.401',     # the laptop's SDK; global.json accepts any 10.0.4xx patch
    [int] $WslProcessors = 16,
    [string] $WslMemory = '64GB',
    [string] $OriginUrl = 'https://profisee.visualstudio.com/Products/_git/speedmerchants',
    [string] $Branch = 'users/agenewe/stream-sync'   # stream itself needs a pull request; hosts track this branch
)
$ErrorActionPreference = 'Stop'
$todo = [Collections.Generic.List[string]]::new()
function Say([string] $m) { Write-Host "  $m" }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this from an elevated pwsh 7 (Run as administrator).' }

# 1. Folders on C:, at the exact C:\devops paths that tasks.json records.
Write-Host '1. folders'
foreach ($d in 'C:\devops\repos', 'C:\devops\worktrees') {
    $item = Get-Item $d -Force -ErrorAction SilentlyContinue
    if (-not $item) { New-Item -ItemType Directory -Path $d -Force | Out-Null; Say "created $d" }
    elseif ($item.LinkType) { $todo.Add("$d is a $($item.LinkType) to $($item.Target): code stays on C:, run Move-StreamHostLayout.ps1") }
    else { Say "ok: $d" }
}
$rl = Get-Item 'C:\devops\repos\speedmerchants' -Force -ErrorAction SilentlyContinue
if ($rl -and $rl.LinkType) { $todo.Add("C:\devops\repos\speedmerchants is a $($rl.LinkType) to $($rl.Target): code stays on C:, run Move-StreamHostLayout.ps1") }

# 2. .NET SDK 10.0.4xx, machine-wide, next to the existing SDKs.
Write-Host '2. .NET SDK'
$sdks = @(& 'C:\Program Files\dotnet\dotnet.exe' --list-sdks 2>$null)
if ($sdks -match '^10\.0\.4\d\d') { Say "ok: $(@($sdks -match '^10\.0\.4\d\d')[0])" }
else {
    $inst = Join-Path $env:TEMP 'dotnet-install.ps1'
    Invoke-WebRequest https://dot.net/v1/dotnet-install.ps1 -OutFile $inst
    & $inst -Version $SdkVersion -InstallDir 'C:\Program Files\dotnet'
    Say "installed SDK $SdkVersion"
}

# 3. WSL2 (needs a reboot the first time). Rancher Desktop needs it.
Write-Host '3. WSL2'
$wsl = (wsl --version 2>&1 | Out-String) -replace "`0", ''
if ($wsl -match 'WSL version') { Say "ok: $(@($wsl)[0])" }
else { wsl --install --no-distribution; $todo.Add('REBOOT the VM (WSL install), then re-run this script') }
$wc = Join-Path $env:USERPROFILE '.wslconfig'
if (-not (Test-Path $wc)) {
    Set-Content -Path $wc -Encoding utf8 -Value @("[wsl2]", "processors=$WslProcessors", "memory=$WslMemory", "swap=0")
    Say "wrote $wc ($WslProcessors vCPU, $WslMemory, no swap)"
} else { Say "ok: $wc exists (left as is)" }

# 4. Rancher Desktop: per-user, first run is interactive, so this script only checks.
Write-Host '4. Rancher Desktop'
$docker = if (Get-Command docker -ErrorAction SilentlyContinue) { (docker version --format '{{.Server.Version}}' 2>$null) }
# Rancher's pathManagementStrategy is manual, so 'docker compose' only resolves when the CLI plugin dir is registered.
$dc = Join-Path $env:USERPROFILE '.docker\config.json'
if (-not (Test-Path $dc)) {
    New-Item -ItemType Directory -Force (Split-Path $dc) | Out-Null
    Set-Content -Path $dc -Encoding utf8 -Value '{"auths":{},"cliPluginsExtraDirs":["C:\\Program Files\\Rancher Desktop\\resources\\resources\\win32\\docker-cli-plugins"]}'
    Say "wrote $dc (docker compose plugin dir)"
}
# Containers, images and volumes live on D: (the Rancher WSL disks); code stays on C:.
foreach ($k in Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue) {
    $n = $k.GetValue('DistributionName'); $b = ([string]$k.GetValue('BasePath')).Replace('\\?\', '')
    if ($n -like 'rancher-desktop*') {
        if ($b -like "$ContainerRoot*") { Say "ok: $n on $b" } else { $todo.Add("WSL distro $n is at ${b}: run Move-StreamHostLayout.ps1 to move it under $ContainerRoot") }
    }
}
if ($docker -match '^\d') { Say "ok: docker engine $docker" }
else { $todo.Add('Install Rancher Desktop (laptop runs 1.24.0) from https://rancherdesktop.io as THIS user: engine dockerd (moby), Kubernetes OFF, start at login + in background') }

# 5. The repo: cloned from origin (the stream branch), never copied. .streams arrives later from Copy-StreamToHost.ps1.
Write-Host '5. repo clone'
$repo = 'C:\devops\repos\speedmerchants'
if (Test-Path (Join-Path $repo '.git')) {
    Say "ok: $repo at $(git -C $repo rev-parse --short HEAD 2>$null)"
    # .streams is the live board, never tracked: without this line every builder worktree would carry a copy of it.
    $ex = Join-Path $repo '.git\info\exclude'
    $have = @(if (Test-Path $ex) { Get-Content $ex })
    $need = @('.streams/', '.foreman/', '**/.claude/worktrees/', '**/.claude/scheduled_tasks.lock', '**/.claude/scheduled_tasks.json') | Where-Object { $_ -notin $have }
    if ($need) { Add-Content -Path $ex -Value $need; Say "added to .git\info\exclude: $($need -join ', ')" } else { Say 'ok: .git\info\exclude holds .streams/' }
}
else { $todo.Add("In a NON-elevated pwsh: git clone -b $Branch $OriginUrl $repo  (sign in when Git Credential Manager asks), then re-run this script") }

# 6. Node and Playwright: node >= 22 is enough; browsers are installed from the repo once it is cloned.
Write-Host '6. Node / Playwright'
$node = if (Get-Command node -ErrorAction SilentlyContinue) { (node --version 2>$null) }
if ($node) { Say "ok: node $node" } else { $todo.Add('Install Node.js 22 or 24 LTS') }
if (-not (Test-Path (Join-Path $env:LOCALAPPDATA 'ms-playwright'))) { $todo.Add("After the clone, NON-elevated: cd $repo\tests\Tests.E2E; npm ci; npx playwright install") }

# 7. Claude Code (per user).
Write-Host '7. Claude Code'
$claude = if (Get-Command claude -ErrorAction SilentlyContinue) { (claude --version 2>$null) }
if ($claude) { Say "ok: $claude" } else { $todo.Add('Install Claude Code in a NON-elevated pwsh: irm https://claude.ai/install.ps1 | iex ; then run claude once and sign in') }

# 8. Test secrets: names only. Set them by hand from the laptop values (setx NAME "value"), never through a file.
Write-Host '8. test environment variables'
foreach ($n in 'SM_SA_PASSWORD', 'SM_SUT_URL', 'SM_SUT_APIKEY', 'SM_WORKLOAD_URL', 'SM_WORKLOAD_APIKEY', 'SPEEDY_CENTRAL_CONNECTION', 'SPEEDY_CENTRAL_SETTINGS') {
    if ([Environment]::GetEnvironmentVariable($n, 'User')) { Say "ok: $n" } else { $todo.Add("setx $n `"<laptop value>`"") }
}

Write-Host ''
if ($todo.Count) { Write-Host 'LEFT TO DO:' -ForegroundColor Yellow; $todo | ForEach-Object { Write-Host "  - $_" } }
else { Write-Host 'Nothing left. Run Test-StreamHostReady.ps1.' -ForegroundColor Green }
