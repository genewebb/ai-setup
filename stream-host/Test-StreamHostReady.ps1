# Test-StreamHostReady.ps1 -- read-only readiness check for a machine that will run the speedmerchants stream kit.
# Run it on the target host, in the interactive session that will run the Claude Code loops (not over WinRM:
# mapped drives and per-user tools only show up in that session). It changes nothing; it prints PASS / WARN / FAIL
# rows and exits 1 when any FAIL is present.
#   pwsh -NoProfile -File Test-StreamHostReady.ps1
param(
    [string] $Repo = 'C:\devops\repos\speedmerchants',
    [string] $WorktreeRoot = 'C:\devops\worktrees\speedmerchants',
    [string] $ContainerRoot = 'D:\RancherDesktop',
    [int] $MinFreeGB = 10
)
$ErrorActionPreference = 'Continue'
$rows = [Collections.Generic.List[object]]::new()
function Add-Row([string] $Status, [string] $Check, [string] $Detail) { $rows.Add([pscustomobject]@{ Status = $Status; Check = $Check; Detail = $Detail }) }
function Get-First([string] $Exe, [string[]] $ArgList) {
    if (-not (Get-Command $Exe -ErrorAction SilentlyContinue)) { return $null }
    try { return ((& $Exe @ArgList 2>&1 | Select-Object -First 1) -replace "`0", '').ToString().Trim() } catch { return $null }
}

# --- machine
$cores = (Get-CimInstance Win32_Processor | Measure-Object NumberOfLogicalProcessors -Sum).Sum
$ramGB = [math]::Round((Get-CimInstance Win32_OperatingSystem).TotalVisibleMemorySize / 1MB)
Add-Row ($(if ($cores -ge 16) { 'PASS' } else { 'WARN' })) 'cores' "$cores logical"
Add-Row ($(if ($ramGB -ge 64) { 'PASS' } else { 'WARN' })) 'memory' "$ramGB GB"
# Code lives on C: in real folders, like the laptop; containers live on D: (the Rancher WSL disks).
$links = @($Repo, (Split-Path $WorktreeRoot), 'C:\devops\repos', 'C:\devops' | ForEach-Object { Get-Item $_ -Force -ErrorAction SilentlyContinue } | Where-Object { $_.LinkType })
Add-Row ($(if ($links) { 'FAIL' } else { 'PASS' })) 'code on C: (no junctions)' ($(if ($links) { "$(($links | ForEach-Object { "$($_.FullName) -> $($_.Target)" }) -join '; '): run Move-StreamHostLayout.ps1" } else { "$Repo and $(Split-Path $WorktreeRoot) are real folders" }))
$free = [math]::Round((Get-PSDrive C).Free / 1GB)
Add-Row ($(if ($free -ge $MinFreeGB) { 'PASS' } else { 'FAIL' })) 'disk for repo + worktrees' "$free GB free on C: (need $MinFreeGB)"
$distros = @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Name = $_.GetValue('DistributionName'); Base = ([string]$_.GetValue('BasePath')).Replace('\\?\', '') } } | Where-Object { $_.Name -like 'rancher-desktop*' })
$offD = @($distros | Where-Object { $_.Base -notlike "$ContainerRoot*" })
Add-Row ($(if (-not $distros) { 'WARN' } elseif ($offD) { 'FAIL' } else { 'PASS' })) "containers on $ContainerRoot" ($(if (-not $distros) { 'no rancher-desktop WSL distros for this user' } else { ($distros | ForEach-Object { "$($_.Name): $($_.Base)" }) -join '; ' }))

# --- toolchain
$git = Get-First git @('--version')
Add-Row ($(if ($git) { 'PASS' } else { 'FAIL' })) 'git' ($git ?? 'not on PATH')
Add-Row ($(if ($PSVersionTable.PSVersion.Major -ge 7) { 'PASS' } else { 'FAIL' })) 'pwsh 7' $PSVersionTable.PSVersion.ToString()
$sdks = if (Get-Command dotnet -ErrorAction SilentlyContinue) { @(dotnet --list-sdks 2>$null) } else { @() }
$sdk10 = @($sdks | Where-Object { $_ -match '^10\.0\.4\d\d' })
Add-Row ($(if ($sdk10) { 'PASS' } else { 'FAIL' })) '.NET SDK 10.0.4xx (global.json pins 10.0.400, latestPatch)' ($(if ($sdk10) { $sdk10[0] } else { "found: $($sdks -join '; ')" }))
$node = Get-First node @('--version')
Add-Row ($(if ($node -and [int]($node.TrimStart('v').Split('.')[0]) -ge 22) { 'PASS' } else { 'FAIL' })) 'node >= 22 (laptop: v24.12.0)' ($node ?? 'not on PATH')
$pw = Join-Path $env:LOCALAPPDATA 'ms-playwright'
$pwDirs = @(Get-ChildItem $pw -Directory -ErrorAction SilentlyContinue | Where-Object Name -match '^(chromium|firefox|webkit)')
Add-Row ($(if ($pwDirs) { 'PASS' } else { 'FAIL' })) 'Playwright browsers' ($(if ($pwDirs) { ($pwDirs.Name -join ', ') } else { "none under $pw -- run: npx playwright install (in tests\Tests.E2E)" }))
$wsl = Get-First wsl @('--version')
Add-Row ($(if ($wsl -match 'WSL version') { 'PASS' } else { 'FAIL' })) 'WSL2' ($wsl ?? 'not installed')
$docker = Get-First docker @('version', '--format', '{{.Server.Version}}')
Add-Row ($(if ($docker -match '^\d') { 'PASS' } else { 'FAIL' })) 'docker engine (Rancher Desktop, moby)' ($docker ?? 'not reachable')
$compose = Get-First docker @('compose', 'version', '--short')
Add-Row ($(if ($compose -match '^\d') { 'PASS' } else { 'FAIL' })) 'docker compose v2' ($compose ?? 'missing')
$ps = if ($docker -match '^\d') { @(docker ps --format '{{.Names}}' 2>$null) } else { @() }
$clash = @($ps | Where-Object { $_ -like 'speedmerchants-*' })
Add-Row ($(if ($clash) { 'WARN' } else { 'PASS' })) 'no other speedmerchants compose project running' ($(if ($clash) { "running: $($clash -join ', ') -- the G-suite deploy would replace it" } else { 'none' }))
$claude = Get-First claude @('--version')
Add-Row ($(if ($claude) { 'PASS' } else { 'FAIL' })) 'Claude Code' ($claude ?? 'not on PATH')

# --- ports the dev stack binds on loopback
foreach ($port in 5310, 5311, 5343, 5672, 14400, 15672, 15692) {
    $l = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
    $owner = if ($l) { (Get-Process -Id @($l)[0].OwningProcess -ErrorAction SilentlyContinue).ProcessName } else { $null }
    $ok = (-not $l) -or ($owner -match 'com\.docker|wslrelay|rancher|vpnkit|docker|host-switch')
    Add-Row ($(if ($ok) { 'PASS' } else { 'FAIL' })) "port $port" ($(if ($l) { "listening: $owner" } else { 'free' }))
}

# --- skills and shared drive
$q = Test-Path 'Q:\Work\Work\03 Shared\work-ai\skills'
Add-Row ($(if ($q) { 'PASS' } else { 'WARN' })) 'Q: vault share (skills source)' ($(if ($q) { 'reachable' } else { 'not mapped: fine when Copy-StreamToHost.ps1 copied the skills locally' }))
$kit = Join-Path $env:USERPROFILE '.claude\skills\stream-kit\scripts\Get-StreamStatus.ps1'
Add-Row ($(if (Test-Path $kit) { 'PASS' } else { 'FAIL' })) 'stream-kit skill linked' ($(if (Test-Path $kit) { (Get-Item (Split-Path (Split-Path $kit))).Target ?? 'local copy' } else { 'missing: link ~\.claude\skills (mklink /D, not /J)' }))
foreach ($s in 'stream-plan', 'stream-author', 'stream-build', 'stream-integrate', 'stream-status') {
    $f = Join-Path $env:USERPROFILE ".claude\skills\$s\SKILL.md"
    Add-Row ($(if (Test-Path $f) { 'PASS' } else { 'FAIL' })) "skill $s" ($(if (Test-Path $f) { 'present' } else { 'missing' }))
}

# --- repo and stream state
if (Test-Path (Join-Path $Repo '.git')) {
    $head = (git -C $Repo rev-parse --short HEAD 2>$null)
    $dirty = @(git -C $Repo status --porcelain 2>$null).Count
    Add-Row ($(if ($dirty) { 'WARN' } else { 'PASS' })) 'repo' "$Repo at $head, $dirty changed/untracked entries"
    $ex = Join-Path $Repo '.git\info\exclude'
    $exOk = (Test-Path $ex) -and (@(Get-Content $ex) -contains '.streams/')
    Add-Row ($(if ($exOk) { 'PASS' } else { 'FAIL' })) '.git\info\exclude' ($(if ($exOk) { 'holds .streams/' } else { 'missing .streams/: every builder worktree would copy the board; re-run Install-StreamHost.ps1' }))
} else { Add-Row 'FAIL' 'repo' "no git repo at ${Repo}: git clone -b users/agenewe/stream-sync from origin (tasks.json holds absolute C:\devops\... paths: keep this exact path)" }
$tj = Join-Path $Repo '.streams\tasks.json'
if (Test-Path $tj) {
    $doc = Get-Content -Raw $tj | ConvertFrom-Json
    $live = @($doc.tasks | Where-Object { $_.claim })
    Add-Row ($(if ($live) { 'WARN' } else { 'PASS' })) '.streams\tasks.json' "$(@($doc.tasks).Count) tasks, $($live.Count) with a claim$(if ($live) { ' (claims from the old host: let the watchdog break them, or clear before starting)' })"
    Add-Row ($(if (Test-Path (Join-Path $Repo '.streams\integrator.lock')) { 'WARN' } else { 'PASS' })) 'integrator.lock' ($(if (Test-Path (Join-Path $Repo '.streams\integrator.lock')) { 'present: copied from the old host, remove before the first /stream-integrate' } else { 'absent' }))
} else { Add-Row 'FAIL' '.streams\tasks.json' 'missing: .streams is excluded from git (.git/info/exclude), copy it separately' }
Add-Row ($(if (Test-Path $WorktreeRoot) { 'PASS' } else { 'WARN' })) 'worktree root' ($(if (Test-Path $WorktreeRoot) { $WorktreeRoot } else { "$WorktreeRoot absent (New-TaskWorktree creates it)" }))

# --- test secrets: names only, never values
foreach ($n in 'SM_SA_PASSWORD', 'SM_SUT_URL', 'SM_SUT_APIKEY', 'SM_WORKLOAD_URL', 'SM_WORKLOAD_APIKEY', 'SPEEDY_CENTRAL_CONNECTION', 'SPEEDY_CENTRAL_SETTINGS') {
    $set = [bool][Environment]::GetEnvironmentVariable($n, 'User') -or [bool][Environment]::GetEnvironmentVariable($n, 'Machine')
    Add-Row ($(if ($set) { 'PASS' } else { 'WARN' })) "env $n" ($(if ($set) { 'set' } else { 'not set (graders or suites that read it will fail or skip)' }))
}

# --- clock (claims and locks are judged by UTC beats and file times)
$w32 = "$(w32tm /query /status 2>$null | Select-String 'Source:')".Trim()
Add-Row ($(if ($w32) { 'PASS' } else { 'WARN' })) 'time source' ($w32 ?? 'w32tm gave no source')

$rows | Format-Table -AutoSize -Wrap | Out-String -Width 220
$fail = @($rows | Where-Object Status -eq 'FAIL').Count; $warn = @($rows | Where-Object Status -eq 'WARN').Count
"{0}: {1} FAIL, {2} WARN" -f $env:COMPUTERNAME, $fail, $warn
if ($fail) { exit 1 }
