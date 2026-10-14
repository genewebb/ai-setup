# Move-StreamHostLayout.ps1 -- put a stream host into the standing layout: CODE ON C:, CONTAINERS ON D:.
#   code:       C:\devops\repos\speedmerchants and C:\devops\worktrees are real folders, like the laptop. An old
#               junction to D:\devops is removed, its content copied back to C:, verified, and the D: copy deleted.
#   containers: the Rancher Desktop WSL disks (images, containers, volumes) move to D:\RancherDesktop with
#               wsl --manage <distro> --move. Rancher Desktop is shut down for the move and left stopped.
# Run it ON the host, in an ELEVATED pwsh 7, in the RDP session of the loop user (CORP\speedmerchants), with no
# Claude Code loop running. Safe to re-run: each step checks first and skips what is already in place.
#   pwsh -NoProfile -File .\Move-StreamHostLayout.ps1
#   pwsh -NoProfile -File .\Move-StreamHostLayout.ps1 -RemoveStrayReposGit   # also delete C:\devops\repos\.git and .vs
param(
    [string] $Repo = 'C:\devops\repos\speedmerchants',
    [string] $Worktrees = 'C:\devops\worktrees',
    [string] $OldRoot = 'D:\devops',
    [string] $ContainerRoot = 'D:\RancherDesktop',
    [switch] $SkipContainers,
    [switch] $RemoveStrayReposGit
)
$ErrorActionPreference = 'Stop'
function Say([string] $m) { Write-Host "  $m" }

$admin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $admin) { throw 'Run this from an elevated pwsh 7 (Run as administrator).' }
if ($env:USERNAME -ne 'speedmerchants') { Write-Host "WARNING: running as $env:USERNAME; the Rancher WSL distros are per user, so only this user's distros move." -ForegroundColor Yellow }
$loops = @(Get-Process claude -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -like "*\$env:USERNAME" })
if ($loops) { throw "Claude Code is running for $env:USERNAME (pid $(($loops.Id) -join ', ')). Stop every loop first." }
$tj = Join-Path $Repo '.streams\tasks.json'
if (Test-Path $tj) {
    $claims = @((Get-Content -Raw $tj | ConvertFrom-Json).tasks | Where-Object { $_.claim })
    if ($claims -or (Test-Path (Join-Path $Repo '.streams\integrator.lock'))) { throw "Board not quiet ($($claims.Count) claims or integrator.lock). Stop the loops and let the watchdog clear it first." }
}

# Relative path -> length, for a copy check that does not depend on robocopy's summary text.
function Get-FileMap([string] $Root) {
    $m = @{}
    $n = $Root.TrimEnd('\').Length + 1
    Get-ChildItem -LiteralPath $Root -Recurse -File -Force -Attributes !ReparsePoint | ForEach-Object { $m[$_.FullName.Substring($n)] = $_.Length }
    $m
}

function Move-BackToC([string] $Path, [string] $Default) {
    $item = Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
    $src = $Default
    if ($item -and $item.LinkType) {
        $src = [string]@($item.Target)[0]
        if ($src -notmatch '^[A-Za-z]:\\') { throw "$Path is a $($item.LinkType) to '$src'; expected a local drive path" }
        cmd /c rmdir "$Path"      # removes the link only, never the target's content
        if (Test-Path -LiteralPath $Path) { throw "could not remove the $($item.LinkType) at $Path" }
        Say "removed $($item.LinkType) $Path -> $src"
    }
    if (-not (Test-Path -LiteralPath $src)) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null }; Say "ok: $Path is a real folder"; return }
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    & robocopy $src $Path /E /COPY:DAT /DCOPY:DAT /XJ /R:1 /W:1 /MT:16 /NP /NFL /NDL /NJH /NJS
    if ($LASTEXITCODE -ge 8) { throw "robocopy $src -> $Path failed ($LASTEXITCODE); the D: copy is untouched, re-run after fixing" }
    $a = Get-FileMap $src; $b = Get-FileMap $Path
    $bad = @($a.Keys | Where-Object { -not $b.ContainsKey($_) -or $b[$_] -ne $a[$_] })
    if ($bad) { throw "copy check failed for $($bad.Count) files (first: $($bad[0])); the D: copy is untouched at $src" }
    Remove-Item -LiteralPath $src -Recurse -Force
    Say "copied $($a.Count) files $src -> $Path, verified, deleted $src"
}

# 1. Code back on C:.
Write-Host '1. code on C:'
$head = if (Test-Path (Join-Path $Repo '.git')) { git -C $Repo rev-parse HEAD }
$tjHash = if (Test-Path $tj) { (Get-FileHash $tj).Hash }
Move-BackToC $Repo (Join-Path $OldRoot 'repos\speedmerchants')
Move-BackToC $Worktrees (Join-Path $OldRoot 'worktrees')
if ($head -and (git -C $Repo rev-parse HEAD) -ne $head) { throw "HEAD changed across the move ($head)" }
if ($tjHash -and (Get-FileHash $tj).Hash -ne $tjHash) { throw 'tasks.json changed across the move' }
if ((Test-Path $OldRoot) -and -not @(Get-ChildItem $OldRoot -Recurse -File -Force).Count) { Remove-Item $OldRoot -Recurse -Force; Say "removed empty $OldRoot" }
elseif (Test-Path $OldRoot) { Write-Host "  NOTE: $OldRoot still holds files; left as is" -ForegroundColor Yellow }

# 2. git: safe.directory for the C: path only; .streams (the live board) never tracked.
Write-Host '2. git settings'
$safe = @(git config --system --get-all safe.directory)
$old = ($OldRoot -replace '\\', '/') + '/repos/speedmerchants'
if ($safe -contains $old) { git config --system --unset safe.directory ('^' + [regex]::Escape($old) + '$'); Say "removed safe.directory $old" }
$new = $Repo -replace '\\', '/'
if ($safe -notcontains $new) { git config --system --add safe.directory $new; Say "added safe.directory $new" } else { Say "ok: safe.directory $new" }
if (Test-Path (Join-Path $Repo '.git')) {
    $ex = Join-Path $Repo '.git\info\exclude'
    $have = @(if (Test-Path $ex) { Get-Content $ex })
    $need = @('.streams/', '.foreman/', '**/.claude/worktrees/', '**/.claude/scheduled_tasks.lock', '**/.claude/scheduled_tasks.json') | Where-Object { $_ -notin $have }
    if ($need) { Add-Content -Path $ex -Value $need; Say "added to .git\info\exclude: $($need -join ', ')" } else { Say 'ok: .git\info\exclude holds .streams/' }
    $dirty = @(git -C $Repo status --porcelain)
    Say "repo $Repo at $(git -C $Repo rev-parse --short HEAD), $($dirty.Count) changed/untracked entries"
}

# 3. Leftover clone at C:\devops\repos itself (an old speed-merchants checkout with every file deleted).
Write-Host '3. stray C:\devops\repos\.git'
$stray = @('C:\devops\repos\.git', 'C:\devops\repos\.vs') | Where-Object { Test-Path $_ }
if (-not $stray) { Say 'ok: none' }
elseif ($RemoveStrayReposGit) { $stray | ForEach-Object { Remove-Item $_ -Recurse -Force; Say "removed $_" } }
else { Write-Host "  NOTE: present: $($stray -join ', '). Re-run with -RemoveStrayReposGit to delete." -ForegroundColor Yellow }

# 4. Containers on D:.
Write-Host "4. containers on $ContainerRoot"
if ($SkipContainers) { Say 'skipped (-SkipContainers)' }
else {
    $lxss = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss'
    $ds = @(Get-ChildItem $lxss -ErrorAction SilentlyContinue | ForEach-Object { [pscustomobject]@{ Key = $_.PSPath; Name = $_.GetValue('DistributionName'); Base = ([string]$_.GetValue('BasePath')).Replace('\\?\', '') } } | Where-Object { $_.Name -like 'rancher-desktop*' })
    $move = @($ds | Where-Object { $_.Base -notlike "$ContainerRoot*" })
    if (-not $ds) { Say 'no rancher-desktop WSL distros for this user: install Rancher Desktop first' }
    elseif (-not $move) { $ds | ForEach-Object { Say "ok: $($_.Name) on $($_.Base)" } }
    else {
        $rd = 'C:\Program Files\Rancher Desktop\resources\resources\win32\bin\rdctl.exe'
        if (Test-Path $rd) { & $rd shutdown; Say 'Rancher Desktop shut down' }
        wsl --shutdown
        New-Item -ItemType Directory -Path $ContainerRoot -Force | Out-Null
        foreach ($d in $move) {
            $leaf = if ($d.Name -eq 'rancher-desktop') { 'distro' } else { $d.Name -replace '^rancher-desktop-', 'distro-' }
            $dst = Join-Path $ContainerRoot $leaf
            wsl --manage $d.Name --move $dst
            if ($LASTEXITCODE -ne 0) { throw "wsl --manage $($d.Name) --move $dst failed ($LASTEXITCODE)" }
            $now = ([string](Get-ItemProperty $d.Key).BasePath).Replace('\\?\', '')
            if ($now -notlike "$ContainerRoot*") { throw "$($d.Name) still at $now after the move" }
            Say "moved $($d.Name): $($d.Base) -> $now"
        }
        Write-Host '  Start Rancher Desktop again (Start menu), then check: docker version; docker compose ls' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Done. Run Test-StreamHostReady.ps1.' -ForegroundColor Green
