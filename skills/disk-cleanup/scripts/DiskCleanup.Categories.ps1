# Shared allowlist for the disk-cleanup skill. Dot-sourced by Find-SafeCleanup.ps1 and Remove-SafeCleanup.ps1.
# A file is deletable ONLY when it sits under a root defined here, matches the category pattern, is old enough,
# and passes Test-DcHardExclude. To make something else deletable, add a category here - never ad hoc.
Set-StrictMode -Version Latest

$script:DcWarnings = [System.Collections.Generic.List[string]]::new()

function Get-DcDriveRoot([string]$Drive) {
    $letter = $Drive.Trim().TrimEnd('\').TrimEnd(':')
    if ($letter -notmatch '^[A-Za-z]$') { throw "Drive must be a single letter such as C or D: (got '$Drive')." }
    $root = "$($letter.ToUpper()):\"
    if (-not (Test-Path -LiteralPath $root)) { throw "Drive $root not found." }
    $root
}

function Test-DcIsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Real (non-junction) user profile folders on the drive.
function Get-DcUserProfiles([string]$Root) {
    $users = Join-Path $Root 'Users'
    if (-not (Test-Path -LiteralPath $users)) { return @() }
    Get-ChildItem -LiteralPath $users -Directory -Force -Attributes !ReparsePoint -ErrorAction SilentlyContinue |
        Where-Object Name -notin 'Public', 'Default', 'All Users', 'Default User' |
        Select-Object -ExpandProperty FullName
}

# Expands a root that may contain wildcards (browser profile folders) to existing, non-junction directories.
function Expand-DcRoot([string]$Path) {
    if ($Path -match '[\*\?]') {
        Get-Item -Path $Path -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.PSIsContainer -and -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) } |
            Select-Object -ExpandProperty FullName
    }
    elseif (Test-Path -LiteralPath $Path -PathType Container) {
        $item = Get-Item -LiteralPath $Path -Force
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { $item.FullName }
    }
}

# Tier meaning:
#   Safe        - junk the OS or apps recreate on demand (temp, dumps, update downloads, browser cache).
#   Regenerable - package caches; cleared by the tool's own command, costs a re-download (and feed auth) later.
#   Confirm     - data the owner already discarded or old logs; deletable, but say what it is first.
function Get-DcCategories([string]$Root) {
    $win = Join-Path $Root 'Windows'
    $profiles = @(Get-DcUserProfiles $Root)
    $perUser = { param([string[]]$Rel) foreach ($p in $profiles) { foreach ($r in $Rel) { Join-Path $p $r } } }

    # Command-based categories only touch the current user's caches, and only when that profile is on this drive.
    $me = $env:USERPROFILE
    $meOnDrive = $me -and $me.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase)
    $mine = { param([string[]]$Rel) if ($meOnDrive) { foreach ($r in $Rel) { Join-Path $me $r } } }

    $defs = @(
        @{ Name = 'UserTemp'; Tier = 'Safe'; MinAgeDays = 1; Pattern = '*'; Recurse = $true
           Description = 'Per-user %TEMP% folders'
           Roots = @(& $perUser 'AppData\Local\Temp') }
        @{ Name = 'WindowsTemp'; Tier = 'Safe'; MinAgeDays = 1; Pattern = '*'; Recurse = $true
           Description = 'Windows\Temp (needs admin)'
           Roots = @(Join-Path $win 'Temp') }
        @{ Name = 'WindowsUpdateDownload'; Tier = 'Safe'; MinAgeDays = 10; Pattern = '*'; Recurse = $true
           Description = 'Downloaded Windows Update payloads; re-downloaded if still needed (needs admin)'
           Roots = @(Join-Path $win 'SoftwareDistribution\Download') }
        @{ Name = 'DeliveryOptimization'; Tier = 'Safe'; MinAgeDays = 1; Pattern = '*'; Recurse = $true
           Description = 'Delivery Optimization peer cache (needs admin)'
           Roots = @(Join-Path $win 'ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache') }
        @{ Name = 'CrashDumps'; Tier = 'Safe'; MinAgeDays = 1; Pattern = '*.dmp'; Recurse = $true
           Description = 'Application crash dumps, minidumps, live kernel reports'
           Roots = @(& $perUser 'AppData\Local\CrashDumps') + @((Join-Path $win 'Minidump'), (Join-Path $win 'LiveKernelReports')) }
        @{ Name = 'KernelMemoryDump'; Tier = 'Safe'; MinAgeDays = 1; Pattern = 'MEMORY.DMP'; Recurse = $false
           Description = 'Windows\MEMORY.DMP from the last bugcheck (needs admin)'
           Roots = @($win) }
        @{ Name = 'ErrorReports'; Tier = 'Safe'; MinAgeDays = 1; Pattern = '*'; Recurse = $true
           Description = 'Windows Error Reporting queues and archives'
           Roots = @('ReportArchive', 'ReportQueue', 'Temp' | ForEach-Object { Join-Path $Root "ProgramData\Microsoft\Windows\WER\$_" }) +
                   @(& $perUser 'AppData\Local\Microsoft\Windows\WER') }
        @{ Name = 'BrowserCache'; Tier = 'Safe'; MinAgeDays = 0; Pattern = '*'; Recurse = $true
           Description = 'Chrome / Edge / Firefox disk caches (skipped while the browser runs)'
           ProcessNames = @('chrome', 'msedge', 'firefox')
           Roots = @(& $perUser @(
                'AppData\Local\Google\Chrome\User Data\*\Cache', 'AppData\Local\Google\Chrome\User Data\*\Code Cache',
                'AppData\Local\Google\Chrome\User Data\*\GPUCache',
                'AppData\Local\Microsoft\Edge\User Data\*\Cache', 'AppData\Local\Microsoft\Edge\User Data\*\Code Cache',
                'AppData\Local\Microsoft\Edge\User Data\*\GPUCache',
                'AppData\Local\Mozilla\Firefox\Profiles\*\cache2')) }
        @{ Name = 'RecycleBin'; Tier = 'Confirm'; MinAgeDays = 0; Pattern = '*'; Recurse = $true
           Description = 'Recycle Bin contents for every user on the drive (already deleted by the owner)'
           Roots = @(Join-Path $Root '$Recycle.Bin') }
        @{ Name = 'IisLogs'; Tier = 'Confirm'; MinAgeDays = 30; Pattern = '*.log'; Recurse = $true
           Description = 'IIS request logs older than 30 days'
           Roots = @(Join-Path $Root 'inetpub\logs\LogFiles') }
        @{ Name = 'NuGetCache'; Tier = 'Regenerable'; MinAgeDays = 0; Pattern = '*'; Recurse = $true
           Description = 'Current user NuGet caches; next restore re-downloads (private feeds need sign-in)'
           Command = 'dotnet'; CommandArgs = @('nuget', 'locals', 'all', '--clear')
           Roots = @(& $mine '.nuget\packages', 'AppData\Local\NuGet\v3-cache', 'AppData\Local\NuGet\plugins-cache') }
        @{ Name = 'NpmCache'; Tier = 'Regenerable'; MinAgeDays = 0; Pattern = '*'; Recurse = $true
           Description = 'Current user npm cache'
           Command = 'npm'; CommandArgs = @('cache', 'clean', '--force')
           Roots = @(& $mine 'AppData\Local\npm-cache') }
        @{ Name = 'PipCache'; Tier = 'Regenerable'; MinAgeDays = 0; Pattern = '*'; Recurse = $true
           Description = 'Current user pip cache'
           Command = 'pip'; CommandArgs = @('cache', 'purge')
           Roots = @(& $mine 'AppData\Local\pip\cache') }
    )

    foreach ($d in $defs) {
        [pscustomobject]@{
            Name         = $d.Name
            Tier         = $d.Tier
            Description  = $d.Description
            MinAgeDays   = $d.MinAgeDays
            Pattern      = $d.Pattern
            Recurse      = $d.Recurse
            Roots        = @($d.Roots | Where-Object { $_ } | ForEach-Object { Expand-DcRoot $_ } | Select-Object -Unique)
            ProcessNames = if ($d.ContainsKey('ProcessNames')) { $d.ProcessNames } else { @() }
            Command      = if ($d.ContainsKey('Command')) { $d.Command } else { $null }
            CommandArgs  = if ($d.ContainsKey('CommandArgs')) { $d.CommandArgs } else { @() }
        }
    }
}

# Never deletable, whatever category claims them. Defense in depth behind the root allowlist.
function Test-DcHardExclude([string]$FullPath) {
    $name = [IO.Path]::GetFileName($FullPath)
    if ($name -in 'pagefile.sys', 'hiberfil.sys', 'swapfile.sys', 'desktop.ini') { return $true }
    $FullPath -match '\\Windows\\(WinSxS|Installer|System32|SysWOW64|servicing)\\' -or
    $FullPath -match '\\System Volume Information\\'
}

function Get-DcFiles([string]$Dir, [string]$Pattern, [bool]$Recurse) {
    $opts = [IO.EnumerationOptions]::new()
    $opts.RecurseSubdirectories = $Recurse
    $opts.IgnoreInaccessible = $true
    $opts.AttributesToSkip = [IO.FileAttributes]::ReparsePoint   # never follow junctions or symlinks
    $opts.MatchCasing = [IO.MatchCasing]::CaseInsensitive
    try {
        foreach ($f in [IO.DirectoryInfo]::new($Dir).EnumerateFiles($Pattern, $opts)) { $f }
    }
    catch [UnauthorizedAccessException] { $script:DcWarnings.Add("Access denied: $Dir (run elevated to include it)") }
    catch [IO.IOException] { $script:DcWarnings.Add("Could not read $Dir : $($_.Exception.Message)") }
}

function Test-DcUnderRoot([string]$FullPath, [string]$RootDir) {
    $prefix = $RootDir.TrimEnd('\') + '\'
    $FullPath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)
}

# True when the file belongs to the category by location and name (age is checked separately).
function Test-DcInCategory([string]$FullPath, $Category) {
    if (Test-DcHardExclude $FullPath) { return $false }
    $name = [IO.Path]::GetFileName($FullPath)
    if ($name -notlike $Category.Pattern) { return $false }
    foreach ($r in $Category.Roots) {
        if (-not (Test-DcUnderRoot $FullPath $r)) { continue }
        if ($Category.Recurse -or ([IO.Path]::GetDirectoryName($FullPath) -eq $r.TrimEnd('\'))) { return $true }
    }
    $false
}

function Test-DcOldEnough([datetime]$LastWriteUtc, [int]$MinAgeDays) {
    $LastWriteUtc -le [datetime]::UtcNow.AddDays(-$MinAgeDays)
}

function Format-DcSize([long]$Bytes) {
    if ($Bytes -ge 1GB) { '{0:N2} GB' -f ($Bytes / 1GB) }
    elseif ($Bytes -ge 1MB) { '{0:N1} MB' -f ($Bytes / 1MB) }
    else { '{0:N0} KB' -f ($Bytes / 1KB) }
}
