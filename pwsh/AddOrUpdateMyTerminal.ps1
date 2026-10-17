<#
.SYNOPSIS
    Adds or updates my Windows Terminal (admin and normal) on this machine, with my saved terminal settings.

.DESCRIPTION
    The settings travel INSIDE this script (the MyTerminalSnapshot section below), so copying
    this one file to a machine is enough. Safe to re-run: that is how you update.

    Add / update (default):
      1. Re-launches itself as administrator if needed.
      2. Installs Windows Terminal with winget if it is missing.
      3. Applies the embedded settings to BOTH the administrator account the script runs as and
         the account logged on to this desktop (e.g. CORP\agenewe and CORP\genewe), so the admin
         and normal terminals match. An account already up to date is left alone; otherwise its
         settings.json is backed up first (last 5 backups kept). Icon / background files the
         settings point at are restored to their original paths if they are missing there.
         Every profile starting directory that is a fixed path (C:\...) is set to THIS machine's
         starting directory: -StartingDirectory if given, else ReposRoot from
         C:\Deploy\Setup\ProfileMachineConfig.md, else you are asked. %USERPROFILE%-style values
         are left alone.
      4. Creates or refreshes two desktop shortcuts: "Terminal (Admin)", which always runs as
         administrator, and "Terminal", which runs as whoever clicks it.

    -Capture:
      Rewrites the MyTerminalSnapshot section of this script with this account's current
      Windows Terminal settings (plus the icon / background files they point at). Run it on
      the machine whose settings you want, then copy the script to the other machines and run it.

    -ForUser (what 'prof terminal' runs on another machine, over WinRM):
      Applies the embedded settings to the ACCOUNT RUNNING THE SCRIPT only. No elevation, no
      Windows Terminal install, no desktop-account lookup, no shortcuts, never asks anything:
      a WinRM session has no desktop and no UAC. Starting directory: -StartingDirectory, else
      ReposRoot when that folder exists, else the captured values are kept. Exit 0 = applied or
      already up to date; exit 3 = this account has no Windows Terminal settings yet (Windows
      Terminal missing or never opened), nothing changed.

.EXAMPLE
    .\AddOrUpdateMyTerminal.ps1 -Capture

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\AddOrUpdateMyTerminal.ps1
#>
[CmdletBinding()]
param(
    # Save the current settings into this script instead of applying them.
    [switch]$Capture,
    # Default: the Public desktop, so the shortcuts show for whoever logs on.
    [string]$DesktopPath = [Environment]::GetFolderPath('CommonDesktopDirectory'),
    [string]$AdminShortcutName = 'Terminal (Admin)',
    [string]$UserShortcutName = 'Terminal',
    # Only create the shortcuts; leave Windows Terminal settings alone.
    [switch]$SkipSettings,
    # Folder new tabs open in on this machine. Default: ReposRoot from the machine config, else asked.
    [string]$StartingDirectory,
    # Settings for the account running the script only (prof terminal over WinRM); see -Help.
    [switch]$ForUser,
    # Show the options and exit.
    [Alias('h')]
    [switch]$Help
)
$ErrorActionPreference = 'Stop'

if ($Help) {
    Write-Host @'
AddOrUpdateMyTerminal.ps1 - add or update my Windows Terminal (admin and normal) on this machine

Usage:
  .\AddOrUpdateMyTerminal.ps1 [-StartingDirectory <dir>] [-SkipSettings] [-DesktopPath <dir>]
                              [-AdminShortcutName <name>] [-UserShortcutName <name>]
  .\AddOrUpdateMyTerminal.ps1 -Capture
  .\AddOrUpdateMyTerminal.ps1 -ForUser [-StartingDirectory <dir>]
  .\AddOrUpdateMyTerminal.ps1 -Help

Default (no options):
  Elevates if needed, installs Windows Terminal if missing, applies the settings saved in this
  script to the admin account AND the account logged on to this desktop (backup only when
  something changes), sets the starting directory for this machine, and creates or refreshes
  both desktop shortcuts. Safe to re-run.

Options:
  -Capture                  Save THIS account's current Windows Terminal settings into this
                            script. Run on the machine whose settings you want, then copy the
                            script to the other machines and run it there.
  -StartingDirectory <dir>  Folder new tabs open in on this machine. Without it: ReposRoot from
                            C:\Deploy\Setup\ProfileMachineConfig.md if that folder exists here,
                            otherwise you are asked (Enter keeps the suggested folder).
  -SkipSettings             Only create the shortcuts; leave Windows Terminal settings alone.
  -ForUser                  Settings for the account running the script only: no elevation,
                            install, shortcuts or questions (prof terminal, over WinRM).
                            Exit 3 = no Windows Terminal settings for this account yet.
  -DesktopPath <dir>        Where the shortcuts go. Default: Public desktop (all users).
  -AdminShortcutName <name> Name of the run-as-administrator shortcut. Default: Terminal (Admin)
  -UserShortcutName <name>  Name of the normal shortcut. Default: Terminal
  -Help, -h                 Show this help and exit.
'@
    return
}

# A mapped drive (D:) is not visible to an elevated session, so always work from the UNC path.
function ConvertTo-UncPath([string]$Path) {
    if ($Path -match '^([A-Za-z]):\\(.*)$') {
        $disk = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($Matches[1]):' AND DriveType=4"
        if ($disk -and $disk.ProviderName) { return (Join-Path $disk.ProviderName $Matches[2]) }
    }
    return $Path
}

function Get-TerminalSettingsPath([string]$LocalAppData = $env:LOCALAPPDATA) {
    $candidates = @(
        "$LocalAppData\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json",
        "$LocalAppData\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json",
        "$LocalAppData\Microsoft\Windows Terminal\settings.json"
    )
    foreach ($c in $candidates) { if (Test-Path -LiteralPath $c) { return $c } }
    return $null
}

# LocalAppData of the account(s) running Explorer in THIS session (the person at the desktop),
# so other people logged on to a shared server are never touched.
function Get-DesktopUserLocalAppData {
    $session = (Get-Process -Id $PID).SessionId
    $sids = Get-CimInstance Win32_Process -Filter "Name='explorer.exe' AND SessionId=$session" |
        ForEach-Object { (Invoke-CimMethod -InputObject $_ -MethodName GetOwnerSid).Sid } |
        Sort-Object -Unique
    foreach ($sid in $sids) {
        $userProfile = Get-CimInstance Win32_UserProfile -Filter "SID='$sid'"
        if ($userProfile) { Join-Path $userProfile.LocalPath 'AppData\Local' }
    }
}

# One value from the per-machine profile config table (| Key | Value | ... |); blank = not set.
function Get-MachineConfigValue([string]$Key) {
    $configPath = 'C:\Deploy\Setup\ProfileMachineConfig.md'
    if (-not (Test-Path -LiteralPath $configPath)) { return $null }
    foreach ($line in Get-Content -LiteralPath $configPath) {
        if ($line -match "^\|\s*$([regex]::Escape($Key))\s*\|\s*([^|]*?)\s*\|") {
            if ($Matches[1]) { return [Environment]::ExpandEnvironmentVariables($Matches[1]) }
            return $null
        }
    }
    return $null
}

# First "startingDirectory" in a settings.json, JSON-unescaped.
function Get-StartingDirectoryValue([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $m = [regex]::Match([IO.File]::ReadAllText($Path), '"startingDirectory"\s*:\s*"([^"]*)"')
    if ($m.Success) { return ($m.Groups[1].Value -replace '\\\\', '\') }
    return $null
}

# This machine's starting directory: -StartingDirectory, else ReposRoot, else ask.
function Resolve-StartingDirectory([string[]]$ExistingSettingsPaths) {
    if ($StartingDirectory) {
        if (-not (Test-Path -LiteralPath $StartingDirectory -PathType Container)) { throw "-StartingDirectory not found: $StartingDirectory" }
        return $StartingDirectory
    }
    $reposRoot = Get-MachineConfigValue 'ReposRoot'
    if ($reposRoot -and (Test-Path -LiteralPath $reposRoot -PathType Container)) {
        Write-Host "Starting directory: $reposRoot (ReposRoot in ProfileMachineConfig.md)"
        return $reposRoot
    }
    # Suggest what this machine already uses, when that folder exists here; else the user profile.
    $suggested = $env:USERPROFILE
    foreach ($p in $ExistingSettingsPaths) {
        $existing = Get-StartingDirectoryValue $p
        if ($existing -and (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($existing)) -PathType Container)) { $suggested = $existing; break }
    }
    while ($true) {
        $answer = Read-Host "Starting directory for new terminal tabs on this machine [$suggested]"
        if (-not $answer) { $answer = $suggested }
        if (Test-Path -LiteralPath ([Environment]::ExpandEnvironmentVariables($answer)) -PathType Container) { return $answer }
        Write-Host "Folder not found: $answer" -ForegroundColor Yellow
    }
}

# Point every fixed-path (C:\...) startingDirectory at $Dir; %VAR% / ~ values are left alone.
function Set-StartingDirectory([string]$Json, [string]$Dir) {
    if ($Dir.Length -gt 3) { $Dir = $Dir.TrimEnd('\') }
    $escaped = $Dir -replace '\\', '\\'
    return [regex]::Replace($Json, '("startingDirectory"\s*:\s*")[A-Za-z]:\\\\[^"]*(")',
        [Text.RegularExpressions.MatchEvaluator] { param($m) $m.Groups[1].Value + $escaped + $m.Groups[2].Value }.GetNewClosure())
}

# Write $Content to one settings.json unless it already matches.
function Update-TerminalSettings([string]$Path, [string]$Content) {
    $current = [IO.File]::ReadAllText($Path).TrimEnd()
    if ($current -eq $Content.TrimEnd()) {
        Write-Host "Up to date: $Path"
        return
    }
    $backup = "$Path.bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
    Copy-Item -LiteralPath $Path -Destination $backup
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    Write-Host "Updated:    $Path"
    Write-Host "  backup:   $backup"
    Get-ChildItem -LiteralPath (Split-Path $Path -Parent) -Filter 'settings.json.bak-????????-??????' |
        Sort-Object Name -Descending | Select-Object -Skip 5 | Remove-Item -Force
}

$scriptPath = ConvertTo-UncPath $PSCommandPath
# Built from two parts so these strings never match the markers themselves.
$beginMarker = '# <' + 'MyTerminalSnapshot>'
$endMarker = '# </' + 'MyTerminalSnapshot>'

# <MyTerminalSnapshot>  (written by -Capture; do not edit by hand)
$SnapshotSource = 'CORPLTR94 CORP\agenewe 2026-10-17 14:47'
$SnapshotSettings = @'
{
    "$help": "https://aka.ms/terminal-documentation",
    "$schema": "https://aka.ms/terminal-profiles-schema",
    "actions": 
    [
        {
            "command": 
            {
                "action": "copy",
                "singleLine": false
            },
            "id": "User.copy.644BA8F2"
        },
        {
            "command": "paste",
            "id": "User.paste"
        },
        {
            "command": 
            {
                "action": "splitPane",
                "split": "auto",
                "splitMode": "duplicate"
            },
            "id": "User.splitPane.A6751878"
        },
        {
            "command": "find",
            "id": "User.find"
        },
        {
            "command": 
            {
                "action": "sendInput",
                "input": "\u001b\r"
            },
            "id": "User.sendInput.8F63D3A9"
        }
    ],
    "copyFormatting": "none",
    "copyOnSelect": false,
    "defaultProfile": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
    "experimental.scrollToChangeOpacity": false,
    "experimental.scrollToZoom": false,
    "firstWindowPreference": "defaultProfile",
    "keybindings": 
    [
        {
            "id": "User.splitPane.A6751878",
            "keys": "alt+shift+d"
        },
        {
            "id": "User.sendInput.8F63D3A9",
            "keys": "shift+enter"
        },
        {
            "id": "User.copy.644BA8F2",
            "keys": "ctrl+c"
        },
        {
            "id": "User.copy.644BA8F2",
            "keys": "ctrl+shift+c"
        },
        {
            "id": "User.find",
            "keys": "ctrl+shift+f"
        },
        {
            "id": "User.paste",
            "keys": "ctrl+v"
        }
    ],
    "newTabMenu": 
    [
        {
            "type": "remainingProfiles"
        }
    ],
    "profiles": 
    {
        "defaults": 
        {
            "bellStyle": 
            [
                "window",
                "taskbar"
            ]
        },
        "list": 
        [
            {
                "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                "guid": "{61c54bbd-c2c6-5271-96e7-009a87ff44bf}",
                "hidden": false,
                "name": "Windows PowerShell"
            },
            {
                "commandline": "%SystemRoot%\\System32\\cmd.exe",
                "guid": "{0caa0dad-35be-5f56-a8ff-afceeeaa6101}",
                "hidden": true,
                "name": "Command Prompt"
            },
            {
                "guid": "{b453ae62-4e3d-5e58-b989-0a998ec441b8}",
                "hidden": true,
                "name": "Azure Cloud Shell",
                "source": "Windows.Terminal.Azure"
            },
            {
                "guid": "{c933aed4-7a1f-5c6c-bd8e-89d2337391db}",
                "hidden": true,
                "name": "Developer Command Prompt for VS 2022",
                "source": "Windows.Terminal.VisualStudio"
            },
            {
                "guid": "{fdab42a2-28b1-568e-9ec2-fe9fd31b2b8b}",
                "hidden": false,
                "name": "Developer PowerShell for VS 2022",
                "source": "Windows.Terminal.VisualStudio"
            },
            {
                "altGrAliasing": true,
                "antialiasingMode": "grayscale",
                "closeOnExit": "automatic",
                "colorScheme": "Campbell",
                "commandline": "%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                "cursorShape": "bar",
                "elevate": true,
                "font": 
                {
                    "face": "Cascadia Mono",
                    "size": 12
                },
                "guid": "{aca84944-fc82-4cc2-8d70-8d30c0e4f696}",
                "hidden": false,
                "historySize": 9001,
                "icon": "C:\\devopslocal\\Incons\\__TemplateIcon.ico",
                "name": "Dev Tools",
                "padding": "8, 8, 8, 8",
                "snapOnInput": true,
                "startingDirectory": "C:\\devops\\repos",
                "tabTitle": "Developer Tool",
                "useAcrylic": false
            },
            {
                "colorScheme": "Campbell Powershell",
                "guid": "{574e775e-4f2a-5b96-ac1e-a2962a402336}",
                "hidden": false,
                "name": "PowerShell",
                "source": "Windows.Terminal.PowershellCore",
                "startingDirectory": "C:\\devops\\repos",
                "useAcrylic": false
            },
            {
                "guid": "{c369cd08-ea05-5584-85d7-b493abec0075}",
                "hidden": true,
                "name": "Developer Command Prompt for VS 18",
                "source": "Windows.Terminal.VisualStudio"
            },
            {
                "guid": "{788ae5f0-f22c-580c-b2ff-87205d249434}",
                "hidden": true,
                "name": "Developer PowerShell for VS 18",
                "source": "Windows.Terminal.VisualStudio"
            },
            {
                "guid": "{3661acc0-fe77-5767-b23e-8c767325daf8}",
                "hidden": true,
                "name": "Developer Command Prompt for VS 2022 (2)",
                "source": "Windows.Terminal.VisualStudio"
            },
            {
                "guid": "{2cc1ee7e-76e3-5580-9b28-17660b88ee61}",
                "hidden": true,
                "name": "Developer PowerShell for VS 2022 (2)",
                "source": "Windows.Terminal.VisualStudio"
            },
            {
                "guid": "{16208362-94fc-5b1f-a491-5b2624d5ab56}",
                "hidden": true,
                "name": "Visual Studio Debug Console",
                "source": "VSDebugConsole"
            },
            {
                "guid": "{e83a650b-57fb-5f94-a5ab-bff922ba6109}",
                "hidden": false,
                "name": "Ubuntu",
                "source": "Microsoft.WSL"
            }
        ]
    },
    "schemes": [],
    "showAdminShield": false,
    "theme": "legacySystem",
    "themes": [],
    "warning.confirmCloseAllTabs": false,
    "warning.inputService": false,
    "warning.multiLinePaste": "never"
}
'@
$SnapshotAssets = @(
)
# </MyTerminalSnapshot>

# ---------------------------------------------------------------- capture
if ($Capture) {
    $src = Get-TerminalSettingsPath
    if (-not $src) { throw "No Windows Terminal settings.json found for $([Security.Principal.WindowsIdentity]::GetCurrent().Name)." }
    $json = [IO.File]::ReadAllText($src).TrimEnd()
    if ($json -match "(?m)^'@") { throw "settings.json has a line starting with '@ and cannot be embedded in a here-string." }

    # Absolute file paths in "icon" / "backgroundImage" (JSON-escaped backslashes)
    $assetLines = @()
    $seen = @()
    foreach ($m in [regex]::Matches($json, '"(?:icon|backgroundImage)"\s*:\s*"([A-Za-z]:\\\\[^"]+)"')) {
        $original = $m.Groups[1].Value -replace '\\\\', '\'
        if (($seen -contains $original) -or -not (Test-Path -LiteralPath $original)) { continue }
        $seen += $original
        $data = [Convert]::ToBase64String([IO.File]::ReadAllBytes($original))
        $assetLines += "    @{ Original = '$($original -replace "'", "''")'; Data = '$data' }"
    }

    $source = '{0} {1} {2:yyyy-MM-dd HH:mm}' -f $env:COMPUTERNAME, [Security.Principal.WindowsIdentity]::GetCurrent().Name, (Get-Date)
    $block = @(
        "$beginMarker  (written by -Capture; do not edit by hand)"
        "`$SnapshotSource = '$source'"
        "`$SnapshotSettings = @'"
        $json
        "'@"
        '$SnapshotAssets = @('
        $assetLines
        ')'
        $endMarker
    ) -join "`r`n"

    $self = [IO.File]::ReadAllText($PSCommandPath)
    $start = $self.IndexOf("`n$beginMarker")
    $end = $self.IndexOf("`n$endMarker")
    if ($start -lt 0 -or $end -lt $start) { throw "Snapshot markers not found in $PSCommandPath." }
    $self = $self.Substring(0, $start + 1) + $block + $self.Substring($end + 1 + $endMarker.Length)
    # BOM so Windows PowerShell 5.1 reads any non-ASCII characters in the settings correctly
    [IO.File]::WriteAllText($PSCommandPath, $self, [Text.UTF8Encoding]::new($true))

    Write-Host "Captured $src ($source)"
    Write-Host "  into $PSCommandPath ($($assetLines.Count) asset file(s))"
    return
}

# ---------------------------------------------------------------- -ForUser (prof terminal, over WinRM)
# The account running the script only. Nothing here may elevate, install, prompt or touch a desktop.
if ($ForUser) {
    if ($SkipSettings) { throw '-ForUser writes settings only; -SkipSettings would leave nothing to do.' }
    if (-not $SnapshotSettings) {
        throw "This copy of the script has no settings in it. Run '.\AddOrUpdateMyTerminal.ps1 -Capture' on the source machine first."
    }
    $me = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    $mine = Get-TerminalSettingsPath
    if (-not $mine) {
        Write-Host "No Windows Terminal settings for $me on $env:COMPUTERNAME (Windows Terminal not installed for this account, or never opened). Nothing changed. Open Windows Terminal once as $me, then run prof terminal again."
        exit 3
    }
    $dir = $null
    if ($StartingDirectory) {
        if (-not (Test-Path -LiteralPath $StartingDirectory -PathType Container)) { throw "-StartingDirectory not found: $StartingDirectory" }
        $dir = $StartingDirectory
    }
    else {
        $reposRoot = Get-MachineConfigValue 'ReposRoot'
        if ($reposRoot -and (Test-Path -LiteralPath $reposRoot -PathType Container)) { $dir = $reposRoot }
    }
    $content = if ($dir) { Set-StartingDirectory $SnapshotSettings $dir } else { $SnapshotSettings }
    Write-Host "Settings from $SnapshotSource for $me$(if ($dir) { ", starting directory $dir" } else { ' (no ReposRoot folder here: starting directories kept as captured)' })"
    Update-TerminalSettings $mine $content
    foreach ($a in $SnapshotAssets) {
        if (Test-Path -LiteralPath $a.Original) { continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $a.Original -Parent) | Out-Null
        [IO.File]::WriteAllBytes($a.Original, [Convert]::FromBase64String($a.Data))
        Write-Host "Restored asset: $($a.Original)"
    }
    exit 0
}

# ---------------------------------------------------------------- elevate
$principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $argList = @('-NoProfile', '-NoExit', '-ExecutionPolicy', 'Bypass', '-File', "`"$scriptPath`"",
                 '-DesktopPath', "`"$DesktopPath`"", '-AdminShortcutName', "`"$AdminShortcutName`"",
                 '-UserShortcutName', "`"$UserShortcutName`"")
    if ($SkipSettings) { $argList += '-SkipSettings' }
    if ($StartingDirectory) { $argList += @('-StartingDirectory', "`"$StartingDirectory`"") }
    Start-Process -FilePath (Get-Process -Id $PID).Path -Verb RunAs -ArgumentList $argList
    return
}

# ---------------------------------------------------------------- Windows Terminal installed
if (-not (Get-Command wt.exe -ErrorAction SilentlyContinue)) {
    if (-not (Get-Command winget.exe -ErrorAction SilentlyContinue)) {
        throw 'Windows Terminal is not installed and winget is not available. Install Windows Terminal from the Microsoft Store, then re-run.'
    }
    Write-Host 'Installing Windows Terminal...'
    winget install --id Microsoft.WindowsTerminal -e --accept-source-agreements --accept-package-agreements
    if ($LASTEXITCODE -ne 0) { throw "winget install failed ($LASTEXITCODE)." }
    $env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
}

# ---------------------------------------------------------------- settings
if (-not $SkipSettings) {
    if (-not $SnapshotSettings) {
        throw "This copy of the script has no settings in it. Run '.\AddOrUpdateMyTerminal.ps1 -Capture' on the source machine, then copy the script again."
    }
    Write-Host "Settings from $SnapshotSource"

    # Administrator account (the one this elevated script runs as)
    $adminSettings = Get-TerminalSettingsPath
    if (-not $adminSettings) {
        # Never run for this account: start it once so it creates its settings folder, then close only that window.
        Write-Host 'First run of Windows Terminal for this account...'
        $before = @(Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue).Id
        Start-Process wt.exe
        for ($s = 0; $s -lt 30 -and -not ($adminSettings = Get-TerminalSettingsPath); $s++) { Start-Sleep -Seconds 1 }
        Get-Process -Name WindowsTerminal -ErrorAction SilentlyContinue |
            Where-Object { $before -notcontains $_.Id } | Stop-Process -Force
        if (-not $adminSettings) { throw 'Windows Terminal did not create its settings.json within 30 seconds.' }
    }
    $targets = @($adminSettings)

    # Account logged on to this desktop, when it is a different account
    foreach ($localAppData in Get-DesktopUserLocalAppData) {
        if ($localAppData -eq $env:LOCALAPPDATA) { continue }
        $userSettings = Get-TerminalSettingsPath $localAppData
        if ($userSettings) {
            $targets += $userSettings
        } else {
            Write-Host "Skipped $localAppData : open Windows Terminal once as that account, then re-run."
        }
    }

    $machineStart = Resolve-StartingDirectory $targets
    $content = Set-StartingDirectory $SnapshotSettings $machineStart
    foreach ($t in $targets) { Update-TerminalSettings $t $content }

    foreach ($a in $SnapshotAssets) {
        if (Test-Path -LiteralPath $a.Original) { continue }
        New-Item -ItemType Directory -Force -Path (Split-Path $a.Original -Parent) | Out-Null
        [IO.File]::WriteAllBytes($a.Original, [Convert]::FromBase64String($a.Data))
        Write-Host "Restored asset: $($a.Original)"
    }
}

# ---------------------------------------------------------------- desktop shortcuts
# Recreated every run, so the icon follows Windows Terminal updates.
# Target is Windows PowerShell (always present) launching wt, so wt.exe is resolved for whoever
# clicks. The admin shortcut is flagged "Run as administrator", so wt starts from an elevated
# process and opens elevated; the normal one opens as the person who clicked it.
$wtPackage = Get-AppxPackage -Name Microsoft.WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
$icon = if ($wtPackage -and (Test-Path (Join-Path $wtPackage.InstallLocation 'WindowsTerminal.exe'))) {
    (Join-Path $wtPackage.InstallLocation 'WindowsTerminal.exe') + ',0'
} else {
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe,0"
}

function New-TerminalShortcut([string]$Name, [switch]$RunAsAdmin) {
    $lnk = Join-Path $DesktopPath "$Name.lnk"
    # Start clean so a previous "Run as administrator" flag never survives on the normal shortcut.
    if (Test-Path -LiteralPath $lnk) { Remove-Item -LiteralPath $lnk -Force }

    $shell = New-Object -ComObject WScript.Shell
    $shortcut = $shell.CreateShortcut($lnk)
    $shortcut.TargetPath = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $shortcut.Arguments = '-NoProfile -WindowStyle Hidden -Command "Start-Process wt.exe"'
    $shortcut.WindowStyle = 7   # minimized, so the launcher does not flash
    $shortcut.IconLocation = $icon
    $shortcut.Description = if ($RunAsAdmin) { 'Windows Terminal (administrator)' } else { 'Windows Terminal' }
    $shortcut.Save()

    if ($RunAsAdmin) {
        # Set the "Run as administrator" flag (SLDF_RUNAS_USER, LinkFlags bit 0x2000 = byte 0x15, bit 0x20)
        $bytes = [IO.File]::ReadAllBytes($lnk)
        $bytes[0x15] = $bytes[0x15] -bor 0x20
        [IO.File]::WriteAllBytes($lnk, $bytes)
        Write-Host "Shortcut:   $lnk (runs as administrator)"
    } else {
        Write-Host "Shortcut:   $lnk (runs as the person who clicks it)"
    }
}

New-TerminalShortcut -Name $AdminShortcutName -RunAsAdmin
New-TerminalShortcut -Name $UserShortcutName
