# Machine-specific roots come from the profile's $global:GeneMachine (C:\Deploy\Setup\ProfileMachineConfig.md);
# the fallback keeps the module usable when it is imported without the profile.
function Get-GeneMachineRoot([string]$Key, [string]$Default) {
    if ($global:GeneMachine -and $global:GeneMachine[$Key]) { return $global:GeneMachine[$Key] }
    return $Default
}
# Gene.DevOpsTools.psm1
# DevOps/repo workflow functions (lazy-loaded by profile)

$script:AppCmd = "$env:windir\System32\inetsrv\appcmd.exe"

# Drop folder for -Update zips. The profile owns the value ($global:GeneBitsDir) so the dp* commands
# and this module can never disagree; importing the module without the profile fails loudly instead.
function Get-GeneBitsZipPath([string]$FileName) {
    if (-not (Get-Variable -Name GeneBitsDir -Scope Global -ErrorAction SilentlyContinue)) {
        throw 'Gene.DevOpsTools: $global:GeneBitsDir is not set - load the PowerShell profile first.'
    }
    New-Item -ItemType Directory -Path $global:GeneBitsDir -Force | Out-Null
    return Join-Path $global:GeneBitsDir $FileName
}

function Wait-AppPoolState {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    param([string]$Name, [string]$Desired)
    for ($i = 0; $i -lt 20; $i++) {
        $s = & $script:AppCmd list apppool /name:$Name /text:state
        if ($s.Trim() -eq $Desired) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Stop-AppPoolWithRetry {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    param([string]$Name)
    for ($i = 1; $i -le 3; $i++) {
        Write-Host "Stopping App Pool '$Name' ($i/3)..." -ForegroundColor Yellow
        & $script:AppCmd stop apppool /apppool.name:$Name | Out-Null
        if (Wait-AppPoolState $Name 'Stopped') {
            Write-Host "Stopped." -ForegroundColor Green
            return $true
        }
        Start-Sleep -Seconds (2 * $i)
    }
    Write-Host "Failed to stop '$Name'." -ForegroundColor Red
    return $false
}

function Start-AppPoolSafe {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    param([string]$Name)
    Write-Host "Starting App Pool '$Name'..." -ForegroundColor Yellow
    & $script:AppCmd start apppool /apppool.name:$Name | Out-Null
    if (Wait-AppPoolState $Name 'Started') {
        Write-Host "Started." -ForegroundColor Green
    } else {
        Write-Host "Start failed." -ForegroundColor Red
    }
}

function Build-And-Publish {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding()]
    param(
        [ValidateSet("Debug","Release")]
        [string]$Configuration = "Release",
        [switch]$WhatIf
    )

    $proj = Join-Path (Get-GeneMachineRoot GovernanceRepo 'C:\devops\repos\governance') 'Governance.Service.Api\Governance.Service.Api.csproj'
    $out  = Join-Path (Get-GeneMachineRoot PlatformRepo 'C:\devops\repos\platform') 'Server\Services\governance'

    if ($WhatIf) {
        Write-Host "[WhatIf] Would publish Governance [$Configuration] -> $out" -ForegroundColor Yellow
        Write-Host "[WhatIf] dotnet publish `"$proj`" -c $Configuration -o `"$out`" --no-restore" -ForegroundColor Yellow
        return
    }

    Write-Host "Publishing Governance [$Configuration] -> service location..." -ForegroundColor Yellow
    dotnet publish $proj -c $Configuration -o $out --no-restore
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet publish failed with exit code $LASTEXITCODE."
    }
}

function Dev-ProfiseeGovRestart {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding()]
    param(
        [switch]$WhatIf,
        [ValidateSet("Debug","Release")]
        [string]$Configuration = "Release"
    )

    if ($WhatIf) {
        Write-Host "[WhatIf] Would run: dev profisee stop" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would stop app pool: Profisee-governance" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would publish Governance [$Configuration]" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would start app pool: Profisee-governance" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would run: dev profisee start" -ForegroundColor Yellow
        return
    }

    Clear-Host
    Write-Host "Stopping Profisee dev environment..." -ForegroundColor Yellow
    dev profisee stop

    if (-not (Stop-AppPoolWithRetry 'Profisee-governance')) {
        throw "Cannot proceed: failed to stop app pool 'Profisee-governance'."
    }
    Build-And-Publish -Configuration $Configuration
    Start-AppPoolSafe 'Profisee-governance'

    Write-Host "Starting Profisee dev environment..." -ForegroundColor Yellow
    dev profisee start

    Write-Host "Done." -ForegroundColor Green
}

function Dev-SpeedMerchantsRestart {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding()]
    param(
        [switch]$WhatIf,

        [ValidateSet("Debug","Release")]
        [string]$Configuration = "Release",

        # Publish + create update zip (excluding appsettings*.json), then EXIT (do not start)
        [switch]$Update,

        # Run existing published output (forces Release; skips build/publish/update zip)
        [switch]$Run,

        # Force a full clean rebuild: dotnet clean + wipe publish folder before build/publish.
        # Use when stale plugin DLLs / removed package files are suspected, or when builds
        # start feeling slow/wrong. Normal runs rely on MSBuild incremental + dotnet publish.
        [switch]$CleanBuild,

        [string]$SolutionPath = (Join-Path (Get-GeneMachineRoot SpeedMerchantsRepo 'C:\devops\repos\speed-merchants') 'speed-merchants.sln'),
        [string]$ProjectName  = "TestAuto.Web"
    )

    if (-not (Test-Path -LiteralPath $SolutionPath)) {
        throw "Speed-Merchants solution not found: $SolutionPath"
    }

    $RepoRoot = Split-Path -Parent $SolutionPath
    $OutDir   = Join-Path $RepoRoot "$ProjectName\bin\$Configuration\publish"

    # Resolve project path:
    $projectPath = Join-Path (Join-Path $RepoRoot $ProjectName) ($ProjectName + ".csproj")
    if (-not (Test-Path -LiteralPath $projectPath)) {
        $hits = Get-ChildItem -Path $RepoRoot -Recurse -Filter ($ProjectName + ".csproj") -File -ErrorAction SilentlyContinue
        if (-not $hits -or $hits.Count -eq 0) {
            throw "Project not found: $ProjectName. Expected $projectPath or any *\$ProjectName.csproj under $RepoRoot."
        }
        if ($hits.Count -gt 1) {
            $list = ($hits | Select-Object -ExpandProperty FullName) -join "`n"
            throw "Multiple projects named $ProjectName.csproj found. Please disambiguate by updating this function to accept an explicit project path. Found:`n$list"
        }
        $projectPath = $hits[0].FullName
    }

    # Ensure output directory exists
    if (-not (Test-Path -LiteralPath $OutDir)) {
        if ($WhatIf) {
            Write-Host "[WhatIf] Would create output folder: $OutDir" -ForegroundColor Yellow
        } else {
            New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
        }
    }

    $dllName = ($ProjectName + ".dll")
    $dllPath = Join-Path $OutDir $dllName

    # -Run => force Release, run only, no build/publish/zip
    if ($Run) {
        $Configuration = "Release"

        if ($WhatIf) {
            Write-Host "[WhatIf] -Run specified: would NOT build/publish/update zip." -ForegroundColor Yellow
            Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would start (foreground): dotnet `"$dllPath`"" -ForegroundColor Yellow
            return
        }

        if (-not (Test-Path -LiteralPath $dllPath)) {
            throw "Published DLL not found (run requires existing publish output): $dllPath`nHint: run dpspeed once (or dpspeed -Configuration Release) to publish first."
        }

        $escaped = [regex]::Escape($dllPath)
        $procs = Get-CimInstance Win32_Process |
            Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -match $escaped }

        foreach ($p in $procs) {
            Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Running $ProjectName (Kestrel) [Release]..." -ForegroundColor Yellow
        Push-Location $OutDir
        try { & dotnet $dllPath }
        finally { Pop-Location }
        return
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] Would publish ($Configuration): $projectPath -> $OutDir" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
        if ($Update) {
            Write-Host "[WhatIf] Would create update zip ONLY (and would NOT start):" -ForegroundColor Yellow
            Write-Host "        $global:GeneBitsDir\TestAuto.Web.zip" -ForegroundColor Yellow
        } else {
            Write-Host "[WhatIf] Would start (foreground): dotnet `"$dllPath`"" -ForegroundColor Yellow
        }
        return
    }

    if ($CleanBuild) {
        Write-Host "CleanBuild: dotnet clean $projectPath -c $Configuration" -ForegroundColor DarkGray
        dotnet clean $projectPath -c $Configuration --nologo --verbosity minimal
        if ($LASTEXITCODE -ne 0) { throw "dotnet clean failed (exit $LASTEXITCODE)" }

        if (Test-Path -LiteralPath $OutDir) {
            Write-Host "CleanBuild: wiping publish folder $OutDir" -ForegroundColor DarkGray
            Remove-Item -LiteralPath $OutDir -Recurse -Force -ErrorAction Stop
        }
    }

    if (-not (Test-Path -LiteralPath $OutDir)) {
        New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
    }

    Write-Host "Building $ProjectName (and reference closure) [$Configuration]..." -ForegroundColor Yellow
    dotnet build $projectPath -c $Configuration --nologo --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed (exit $LASTEXITCODE)" }

    Write-Host "Publishing $ProjectName [$Configuration]..." -ForegroundColor Yellow
    dotnet publish $projectPath -c $Configuration -o $OutDir --no-build --nologo --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

    $escaped = [regex]::Escape($dllPath)
    $procs = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -match $escaped }

    foreach ($p in $procs) {
        Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    if ($Update) {
        $publishDir = $OutDir
        $zipPath    = Get-GeneBitsZipPath 'TestAuto.Web.zip'
        $stageDir   = Join-Path $env:TEMP ("PublishStage_" + [guid]::NewGuid().ToString("N"))
        $robolog    = Join-Path $env:TEMP ("robocopy_" + [guid]::NewGuid().ToString("N") + ".log")

        $oldEAP = $ErrorActionPreference
        try {
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'

            if (-not (Test-Path -LiteralPath $publishDir)) { throw "Publish directory does not exist: $publishDir" }
            if (-not (Get-ChildItem -LiteralPath $publishDir -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                throw "Publish directory is empty: $publishDir"
            }

            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

            $null = robocopy $publishDir $stageDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP `
                /XF appsettings*.json /MT:8 /XJ /COPY:DAT /DCOPY:D /LOG:$robolog

            $rc = $LASTEXITCODE
            if ($rc -gt 7) {
                Write-Host "Robocopy failed. Tail of log:" -ForegroundColor Red
                Get-Content -Path $robolog -Tail 200 | Write-Host
                throw "Robocopy error (exit code $rc)."
            }

            $stagedCount = (Get-ChildItem -LiteralPath $stageDir -Recurse -File -ErrorAction SilentlyContinue).Count
            if ($stagedCount -eq 0) { throw "Nothing was staged. Check exclude patterns and source folder." }

            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

            $zipInfo = Get-Item -LiteralPath $zipPath
            Write-Host "Created zip: $zipPath  ($($zipInfo.Length) bytes)" -ForegroundColor Green
        }
        finally {
            $ErrorActionPreference = $oldEAP
            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
        }

        return
    }

    Write-Host "Starting $ProjectName (Kestrel)..." -ForegroundColor Yellow
    Push-Location $OutDir
    try { & dotnet $dllPath }
    finally { Pop-Location }

    Write-Host "Done." -ForegroundColor Green
}

function Dev-CrewChiefRestart {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [switch]$WhatIf,

        [ValidateSet("Debug","Release")]
        [string]$Configuration = "Release",

        # Publish + create update zip (ships appsettings.json; excludes secrets.local*.json), then EXIT (do not start)
        [switch]$Update,

        # Run existing published output (forces Release; skips build/publish/update zip)
        [switch]$Run,

        # Force a full clean rebuild: dotnet clean + wipe publish folder before build/publish.
        [switch]$CleanBuild,

        # Target CrewChief.Cli instead of CrewChief.Web.
        [switch]$Cli,

        [string]$SolutionPath = (Join-Path (Get-GeneMachineRoot SpeedMerchantsRepo 'C:\devops\repos\speed-merchants') 'CrewChief\CrewChief.sln'),
        [string]$ProjectName,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CliArgs = @()
    )

    if (-not (Test-Path -LiteralPath $SolutionPath)) {
        throw "CrewChief solution not found: $SolutionPath"
    }

    $solutionRoot = Split-Path -Parent $SolutionPath
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ProjectName = if ($Cli) { "CrewChief.Cli" } else { "CrewChief.Web" }
    }

    $outDir = Join-Path $solutionRoot "$ProjectName\bin\$Configuration\publish"

    # Resolve project path.
    $projectPath = Join-Path (Join-Path $solutionRoot $ProjectName) ($ProjectName + ".csproj")
    if (-not (Test-Path -LiteralPath $projectPath)) {
        $hits = Get-ChildItem -Path $solutionRoot -Recurse -Filter ($ProjectName + ".csproj") -File -ErrorAction SilentlyContinue
        if (-not $hits -or $hits.Count -eq 0) {
            throw "Project not found: $ProjectName. Expected $projectPath or any *\$ProjectName.csproj under $solutionRoot."
        }
        if ($hits.Count -gt 1) {
            $list = ($hits | Select-Object -ExpandProperty FullName) -join "`n"
            throw "Multiple projects named $ProjectName.csproj found. Please disambiguate with -ProjectName. Found:`n$list"
        }
        $projectPath = $hits[0].FullName
    }

    if (-not (Test-Path -LiteralPath $outDir)) {
        if ($WhatIf) {
            Write-Host "[WhatIf] Would create output folder: $outDir" -ForegroundColor Yellow
        } else {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
    }

    $assemblyName = if ($ProjectName -eq "CrewChief.Cli") { "crewchief" } else { $ProjectName }
    $dllPath = Join-Path $outDir ($assemblyName + ".dll")
    $runDescription = if ($Cli) { "dotnet `"$dllPath`" $($CliArgs -join ' ')".TrimEnd() } else { "dotnet `"$dllPath`"" }

    # The Web app now self-configures its Kestrel ports (WebUI:HttpPort/HttpsPort in appsettings.json,
    # bound via ListenAnyIP on all interfaces), so the wrapper no longer sets ASPNETCORE_URLS. It only
    # DISPLAYS the intended URLs — http/https on localhost AND on the machine FQDN — mirroring
    # TestAuto runtime behavior (the app binds; the wrapper shows where to reach it).
    $webUrls = @()
    if (-not $Cli) {
        $httpPort = 5030; $httpsPort = 5031
        $appSettingsPath = Join-Path $solutionRoot "CrewChief.Web\appsettings.json"
        try {
            if (Test-Path -LiteralPath $appSettingsPath) {
                $cfg = Get-Content -LiteralPath $appSettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($cfg.WebUI.HttpPort)  { $httpPort  = [int]$cfg.WebUI.HttpPort }
                if ($cfg.WebUI.HttpsPort) { $httpsPort = [int]$cfg.WebUI.HttpsPort }
            }
        } catch {
            Write-Host "[warn] Could not read WebUI ports from appsettings.json; using defaults 5030/5031." -ForegroundColor DarkYellow
        }
        $fqdn = try { [System.Net.Dns]::GetHostEntry('').HostName } catch { 'localhost' }
        $webUrls = @(
            "http://localhost:$httpPort",
            "https://localhost:$httpsPort",
            "http://${fqdn}:$httpPort",
            "https://${fqdn}:$httpsPort"
        )
    }

    # Prints the intended web URLs (no-op for the CLI).
    $showUrls = {
        param($urls)
        if ($urls -and $urls.Count -gt 0) {
            Write-Host "  Web UI URLs:" -ForegroundColor Cyan
            foreach ($u in $urls) { Write-Host ("    {0}" -f $u) -ForegroundColor Cyan }
        }
    }

    # -Run => force Release, run only, no build/publish/zip.
    if ($Run) {
        $Configuration = "Release"
        $outDir = Join-Path $solutionRoot "$ProjectName\bin\$Configuration\publish"
        $dllPath = Join-Path $outDir ($assemblyName + ".dll")
        $runDescription = if ($Cli) { "dotnet `"$dllPath`" $($CliArgs -join ' ')".TrimEnd() } else { "dotnet `"$dllPath`"" }

        if ($WhatIf) {
            Write-Host "[WhatIf] -Run specified: would NOT build/publish/update zip." -ForegroundColor Yellow
            Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would start (foreground): $runDescription" -ForegroundColor Yellow
            if (-not $Cli) { Write-Host "[WhatIf] Would serve at:" -ForegroundColor Cyan; & $showUrls $webUrls }
            return
        }

        if (-not (Test-Path -LiteralPath $dllPath)) {
            throw "Published DLL not found (run requires existing publish output): $dllPath`nHint: run dpcrewchief once (or dpcrewchief -Configuration Release) to publish first."
        }

        $escaped = [regex]::Escape($dllPath)
        $procs = Get-CimInstance Win32_Process |
            Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -match $escaped }

        foreach ($p in $procs) {
            Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Running $ProjectName [Release]..." -ForegroundColor Yellow
        & $showUrls $webUrls
        Push-Location $outDir
        try { & dotnet $dllPath @CliArgs }
        finally { Pop-Location }
        return
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] Would publish ($Configuration): $projectPath -> $outDir" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
        if ($Update) {
            Write-Host "[WhatIf] Would create update zip ONLY (and would NOT start):" -ForegroundColor Yellow
            Write-Host "        $global:GeneBitsDir\CrewChief.zip" -ForegroundColor Yellow
        } else {
            Write-Host "[WhatIf] Would start (foreground): $runDescription" -ForegroundColor Yellow
            if (-not $Cli) { Write-Host "[WhatIf] Would serve at:" -ForegroundColor Cyan; & $showUrls $webUrls }
        }
        return
    }

    if ($CleanBuild) {
        Write-Host "CleanBuild: dotnet clean $projectPath -c $Configuration" -ForegroundColor DarkGray
        dotnet clean $projectPath -c $Configuration --nologo --verbosity minimal
        if ($LASTEXITCODE -ne 0) { throw "dotnet clean failed (exit $LASTEXITCODE)" }

        if (Test-Path -LiteralPath $outDir) {
            Write-Host "CleanBuild: wiping publish folder $outDir" -ForegroundColor DarkGray
            Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction Stop
        }
    }

    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Write-Host "Building $ProjectName (and reference closure) [$Configuration]..." -ForegroundColor Yellow
    dotnet build $projectPath -c $Configuration --nologo --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed (exit $LASTEXITCODE)" }

    Write-Host "Publishing $ProjectName [$Configuration]..." -ForegroundColor Yellow
    dotnet publish $projectPath -c $Configuration -o $outDir --no-build --nologo --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

    $escaped = [regex]::Escape($dllPath)
    $procs = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -match $escaped }

    foreach ($p in $procs) {
        Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    if ($Update) {
        $publishDir = $outDir
        $zipPath    = Get-GeneBitsZipPath 'CrewChief.zip'
        $stageDir   = Join-Path $env:TEMP ("PublishStage_" + [guid]::NewGuid().ToString("N"))
        $robolog    = Join-Path $env:TEMP ("robocopy_" + [guid]::NewGuid().ToString("N") + ".log")

        $oldEAP = $ErrorActionPreference
        try {
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'

            if (-not (Test-Path -LiteralPath $publishDir)) { throw "Publish directory does not exist: $publishDir" }
            if (-not (Get-ChildItem -LiteralPath $publishDir -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                throw "Publish directory is empty: $publishDir"
            }

            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

            # Ship appsettings.json with the code (it holds NO per-machine values — those live in
            # secrets.local.json, which stays excluded so an update never clobbers a box's cert/hostname).
            $null = robocopy $publishDir $stageDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP `
                /XF secrets.local*.json /MT:8 /XJ /COPY:DAT /DCOPY:D /LOG:$robolog

            $rc = $LASTEXITCODE
            if ($rc -gt 7) {
                Write-Host "Robocopy failed. Tail of log:" -ForegroundColor Red
                Get-Content -Path $robolog -Tail 200 | Write-Host
                throw "Robocopy error (exit code $rc)."
            }

            $stagedCount = (Get-ChildItem -LiteralPath $stageDir -Recurse -File -ErrorAction SilentlyContinue).Count
            if ($stagedCount -eq 0) { throw "Nothing was staged. Check exclude patterns and source folder." }

            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

            $zipInfo = Get-Item -LiteralPath $zipPath
            Write-Host "Created zip: $zipPath  ($($zipInfo.Length) bytes)" -ForegroundColor Green
        }
        finally {
            $ErrorActionPreference = $oldEAP
            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
        }

        return
    }

    Write-Host "Starting $ProjectName..." -ForegroundColor Yellow
    & $showUrls $webUrls
    Push-Location $outDir
    try { & dotnet $dllPath @CliArgs }
    finally { Pop-Location }

    Write-Host "Done." -ForegroundColor Green
}

function Dev-DataGenRestart {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [switch]$WhatIf,

        [ValidateSet("Debug","Release")]
        [string]$Configuration = "Release",

        # Publish + create update zip, then EXIT (do not start). Operator state is excluded — see the
        # -Update block below for the exact exclude list.
        [switch]$Update,

        # Run existing published output (forces Release; skips build/publish/update zip)
        [switch]$Run,

        # Force a full clean rebuild: dotnet clean + wipe publish folder before build/publish.
        [switch]$CleanBuild,

        # Target TestData.Generation.Cli instead of TestData.Generation.Web.
        [switch]$Cli,

        [string]$SolutionPath = (Join-Path (Get-GeneMachineRoot SpeedMerchantsRepo 'C:\devops\repos\speed-merchants') 'TestData.Generation\TestData.Generation.sln'),
        [string]$ProjectName,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CliArgs = @()
    )

    if (-not (Test-Path -LiteralPath $SolutionPath)) {
        throw "TestData.Generation solution not found: $SolutionPath"
    }

    $solutionRoot = Split-Path -Parent $SolutionPath
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ProjectName = if ($Cli) { "TestData.Generation.Cli" } else { "TestData.Generation.Web" }
    }

    $outDir = Join-Path $solutionRoot "$ProjectName\bin\$Configuration\publish"

    # Resolve project path.
    $projectPath = Join-Path (Join-Path $solutionRoot $ProjectName) ($ProjectName + ".csproj")
    if (-not (Test-Path -LiteralPath $projectPath)) {
        $hits = Get-ChildItem -Path $solutionRoot -Recurse -Filter ($ProjectName + ".csproj") -File -ErrorAction SilentlyContinue
        if (-not $hits -or $hits.Count -eq 0) {
            throw "Project not found: $ProjectName. Expected $projectPath or any *\$ProjectName.csproj under $solutionRoot."
        }
        if ($hits.Count -gt 1) {
            $list = ($hits | Select-Object -ExpandProperty FullName) -join "`n"
            throw "Multiple projects named $ProjectName.csproj found. Please disambiguate with -ProjectName. Found:`n$list"
        }
        $projectPath = $hits[0].FullName
    }

    if (-not (Test-Path -LiteralPath $outDir)) {
        if ($WhatIf) {
            Write-Host "[WhatIf] Would create output folder: $outDir" -ForegroundColor Yellow
        } else {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
    }

    # Neither csproj overrides <AssemblyName>, so the dll matches the project name for both targets.
    $assemblyName = $ProjectName
    $dllPath = Join-Path $outDir ($assemblyName + ".dll")
    $runDescription = if ($Cli) { "dotnet `"$dllPath`" $($CliArgs -join ' ')".TrimEnd() } else { "dotnet `"$dllPath`"" }

    # Unlike CrewChief.Web, TestData.Generation.Web configures NO Kestrel endpoint of its own
    # (Program.cs deliberately leaves HTTP/HTTPS to the host), so the wrapper pins the port via
    # ASPNETCORE_URLS to the same loopback port the installer uses (TestDataGeneration.iss
    # WebHttpPort = 5045) instead of letting the framework pick 5000. A WebUI:HttpPort in
    # appsettings.json wins (Program.cs reads the same key), keeping this forward-compatible.
    # NOT 5040: that port is already bound on every Windows box by svchost.exe for the Connected
    # Devices Platform service (CDPSvc), so a host pinned there fails with address-in-use. 5046 is
    # reserved alongside 5045 for a future HTTPS endpoint.
    $webUrls = @()
    $webUrlEnv = $null
    if (-not $Cli) {
        $httpPort = 5045
        $appSettingsPath = Join-Path $solutionRoot "TestData.Generation.Web\appsettings.json"
        try {
            if (Test-Path -LiteralPath $appSettingsPath) {
                $cfg = Get-Content -LiteralPath $appSettingsPath -Raw | ConvertFrom-Json -ErrorAction Stop
                if ($cfg.PSObject.Properties.Name -contains 'WebUI' -and $cfg.WebUI.HttpPort) { $httpPort = [int]$cfg.WebUI.HttpPort }
            }
        } catch {
            Write-Host "[warn] Could not read WebUI ports from appsettings.json; using default $httpPort." -ForegroundColor DarkYellow
        }
        $fqdn = try { [System.Net.Dns]::GetHostEntry('').HostName } catch { 'localhost' }
        $webUrls = @(
            "http://localhost:$httpPort",
            "http://${fqdn}:$httpPort"
        )
        # Loopback-only bind: this is a local operator tool with no authentication (same posture the
        # installed shortcut uses), so it is deliberately NOT ListenAnyIP. The FQDN line above is
        # informational for a machine-local browser.
        $webUrlEnv = "http://localhost:$httpPort"
    }

    # Prints the intended web URLs (no-op for the CLI).
    $showUrls = {
        param($urls)
        if ($urls -and $urls.Count -gt 0) {
            Write-Host "  Web UI URLs:" -ForegroundColor Cyan
            foreach ($u in $urls) { Write-Host ("    {0}" -f $u) -ForegroundColor Cyan }
        }
    }

    # Starts the target in the foreground with ASPNETCORE_URLS pinned for the child process only —
    # the previous value is restored so the switch never leaks into the caller's shell.
    $startTarget = {
        param($workDir, $dll, $urlEnv, $extraArgs)
        $priorUrls = $env:ASPNETCORE_URLS
        Push-Location $workDir
        try {
            if ($urlEnv) { $env:ASPNETCORE_URLS = $urlEnv }
            & dotnet $dll @extraArgs
        }
        finally {
            Pop-Location
            $env:ASPNETCORE_URLS = $priorUrls
        }
    }

    # -Run => force Release, run only, no build/publish/zip.
    if ($Run) {
        $Configuration = "Release"
        $outDir = Join-Path $solutionRoot "$ProjectName\bin\$Configuration\publish"
        $dllPath = Join-Path $outDir ($assemblyName + ".dll")
        $runDescription = if ($Cli) { "dotnet `"$dllPath`" $($CliArgs -join ' ')".TrimEnd() } else { "dotnet `"$dllPath`"" }

        if ($WhatIf) {
            Write-Host "[WhatIf] -Run specified: would NOT build/publish/update zip." -ForegroundColor Yellow
            Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would start (foreground): $runDescription" -ForegroundColor Yellow
            if (-not $Cli) { Write-Host "[WhatIf] Would serve at:" -ForegroundColor Cyan; & $showUrls $webUrls }
            return
        }

        if (-not (Test-Path -LiteralPath $dllPath)) {
            throw "Published DLL not found (run requires existing publish output): $dllPath`nHint: run dpdatagen once (or dpdatagen -Configuration Release) to publish first."
        }

        $escaped = [regex]::Escape($dllPath)
        $procs = Get-CimInstance Win32_Process |
            Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -match $escaped }

        foreach ($p in $procs) {
            Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Running $ProjectName [Release]..." -ForegroundColor Yellow
        & $showUrls $webUrls
        & $startTarget $outDir $dllPath $webUrlEnv $CliArgs
        return
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] Would publish ($Configuration): $projectPath -> $outDir" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
        if ($Update) {
            Write-Host "[WhatIf] Would create update zip ONLY (and would NOT start):" -ForegroundColor Yellow
            Write-Host "        $global:GeneBitsDir\TestDataGeneration.zip" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would exclude operator state: Samples\*, *.local.json, *.runtime.json, *.resume.json" -ForegroundColor Yellow
        } else {
            Write-Host "[WhatIf] Would start (foreground): $runDescription" -ForegroundColor Yellow
            if (-not $Cli) { Write-Host "[WhatIf] Would serve at:" -ForegroundColor Cyan; & $showUrls $webUrls }
        }
        return
    }

    if ($CleanBuild) {
        Write-Host "CleanBuild: dotnet clean $projectPath -c $Configuration" -ForegroundColor DarkGray
        dotnet clean $projectPath -c $Configuration --nologo --verbosity minimal
        if ($LASTEXITCODE -ne 0) { throw "dotnet clean failed (exit $LASTEXITCODE)" }

        if (Test-Path -LiteralPath $outDir) {
            Write-Host "CleanBuild: wiping publish folder $outDir" -ForegroundColor DarkGray
            Remove-Item -LiteralPath $outDir -Recurse -Force -ErrorAction Stop
        }
    }

    if (-not (Test-Path -LiteralPath $outDir)) {
        New-Item -ItemType Directory -Path $outDir -Force | Out-Null
    }

    Write-Host "Building $ProjectName (and reference closure) [$Configuration]..." -ForegroundColor Yellow
    dotnet build $projectPath -c $Configuration --nologo --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet build failed (exit $LASTEXITCODE)" }

    Write-Host "Publishing $ProjectName [$Configuration]..." -ForegroundColor Yellow
    dotnet publish $projectPath -c $Configuration -o $outDir --no-build --nologo --verbosity minimal
    if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed (exit $LASTEXITCODE)" }

    $escaped = [regex]::Escape($dllPath)
    $procs = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -match $escaped }

    foreach ($p in $procs) {
        Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    if ($Update) {
        $publishDir = $outDir
        $zipPath    = Get-GeneBitsZipPath 'TestDataGeneration.zip'
        $stageDir   = Join-Path $env:TEMP ("PublishStage_" + [guid]::NewGuid().ToString("N"))
        $robolog    = Join-Path $env:TEMP ("robocopy_" + [guid]::NewGuid().ToString("N") + ".log")

        $oldEAP = $ErrorActionPreference
        try {
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'

            if (-not (Test-Path -LiteralPath $publishDir)) { throw "Publish directory does not exist: $publishDir" }
            if (-not (Get-ChildItem -LiteralPath $publishDir -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                throw "Publish directory is empty: $publishDir"
            }

            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
            New-Item -ItemType Directory -Path $stageDir -Force | Out-Null

            # appsettings.json ships with the code (it holds no per-machine values). Everything a box
            # OWNS is excluded so an update can never clobber it:
            #   /XD Samples        operator-edited shape definitions (the installer likewise stages
            #                      Samples with 'onlyifdoesntexist')
            #   *.local.json       per-box overrides and credentials
            #   *.runtime.json     generated runtime state (stripped from the installer stage too)
            #   *.resume.json      chunk checkpoint / resume state for an in-flight generation run
            $null = robocopy $publishDir $stageDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP `
                /XD Samples /XF *.local.json *.runtime.json *.resume.json /MT:8 /XJ /COPY:DAT /DCOPY:D /LOG:$robolog

            $rc = $LASTEXITCODE
            if ($rc -gt 7) {
                Write-Host "Robocopy failed. Tail of log:" -ForegroundColor Red
                Get-Content -Path $robolog -Tail 200 | Write-Host
                throw "Robocopy error (exit code $rc)."
            }

            $stagedCount = (Get-ChildItem -LiteralPath $stageDir -Recurse -File -ErrorAction SilentlyContinue).Count
            if ($stagedCount -eq 0) { throw "Nothing was staged. Check exclude patterns and source folder." }

            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }

            Add-Type -AssemblyName System.IO.Compression.FileSystem
            [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)

            $zipInfo = Get-Item -LiteralPath $zipPath
            Write-Host "Created zip: $zipPath  ($($zipInfo.Length) bytes)" -ForegroundColor Green
        }
        finally {
            $ErrorActionPreference = $oldEAP
            if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue }
        }

        return
    }

    Write-Host "Starting $ProjectName..." -ForegroundColor Yellow
    & $showUrls $webUrls
    & $startTarget $outDir $dllPath $webUrlEnv $CliArgs

    Write-Host "Done." -ForegroundColor Green
}

Export-ModuleMember -Function `
    Dev-ProfiseeGovRestart, Dev-SpeedMerchantsRestart, Dev-CrewChiefRestart, Dev-DataGenRestart
