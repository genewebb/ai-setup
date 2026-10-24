# =====================================================================
# PowerShell Profile (Gene) - Minimal, quiet, enhanced + repo workflows
# =====================================================================

# -----------------------------
# PSReadLine config (coloring + history search + QoL)
# -----------------------------
Import-Module PSReadLine -ErrorAction SilentlyContinue
if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
    Set-PSReadLineOption -EditMode Windows -PredictionSource None

    $cmap = @{
        Command   = 'Yellow'
        Parameter = 'Cyan'
        String    = 'Green'
        Comment   = 'DarkGray'
        Keyword   = 'Magenta'
        Operator  = 'White'
        Number    = 'DarkYellow'
    }
    foreach ($k in $cmap.Keys) {
        try { Set-PSReadLineOption -Colors @{ $k = $cmap[$k] } } catch {}
    }

    # History search (your current preference)
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    # QoL
    Set-PSReadLineOption -BellStyle None
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -MaximumHistoryCount 50000
    try { Set-PSReadLineOption -PredictionViewStyle ListView } catch {}
    Set-PSReadLineKeyHandler -Key Tab    -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
}

# -----------------------------
# Prompt: full path in colored bar (original behavior)
# -----------------------------
function prompt {
    "$([char]27)[44;97m$(Get-Location)$([char]27)[0m> "
}

# -----------------------------
# Profile utilities
# -----------------------------
function sp { $PROFILE }

function ep {
    # Prefer VS Code if available; fall back to notepad
    if (Get-Command code -ErrorAction SilentlyContinue) {
        code $PROFILE
    } else {
        notepad $PROFILE
    }
}

function rp {
    . $PROFILE
    Write-Host "Profile reloaded: $PROFILE" -ForegroundColor Green
}

# -----------------------------
# Quick nav (work)
# -----------------------------
function cdevops { Set-Location C:\devops\repos }
function cspeed  { Set-Location C:\devops\repos\speed-merchants }
function csm     { Set-Location C:\devops\repos\speedmerchants }

# -----------------------------
# Quick nav (personal GitHub repos)
# -----------------------------
function cpower  { Set-Location D:\PowershellScripts }
function csql    { Set-Location D:\SqlScripts }

function newguid { (New-Guid).Guid }

# =====================================================================
# Speed-Merchants (Kestrel-hosted) - publish + restart
# Command name: dpspeed (aligned with cspeed)
#
# Behavior:
# - default: build + publish -> <repo>\.run\speed-merchants, stop prior, then run dotnet <published dll> (foreground)
# - supports -WhatIf
# - supports -Configuration Debug|Release (default Release)
# - supports -Update (publish + create zip ONLY; does NOT start)
# - supports -Run (FORCES Release; skip build/publish/zip; stop prior + run existing published dll)
# =====================================================================

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

        [string]$SolutionPath = "C:\devops\repos\speed-merchants\speed-merchants.sln",
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

        # Stop existing process by matching the published DLL path in the command line
        $escaped = [regex]::Escape($dllPath)
        $procs = Get-CimInstance Win32_Process |
            Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -match $escaped }

        foreach ($p in $procs) {
            Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Running $ProjectName (Kestrel) [Release]..." -ForegroundColor Yellow
        Push-Location $OutDir
        try {
            & dotnet $dllPath
        }
        finally {
            Pop-Location
        }

        return
    }

    if ($WhatIf) {
        Write-Host "[WhatIf] Would publish ($Configuration): $projectPath -> $OutDir" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
        if ($Update) {
            Write-Host "[WhatIf] Would create update zip ONLY (and would NOT start):" -ForegroundColor Yellow
            Write-Host "        C:\tmp\TestAuto.Web.zip" -ForegroundColor Yellow
        } else {
            Write-Host "[WhatIf] Would start (foreground): dotnet `"$dllPath`"" -ForegroundColor Yellow
        }
        return
    }

    Write-Host "Building solution to ensure plugins are copied..." -ForegroundColor Yellow
    dotnet build $SolutionPath -c $Configuration

    Write-Host "Publishing Speed-Merchants ($ProjectName) [$Configuration]..." -ForegroundColor Yellow
    dotnet publish $projectPath -c $Configuration -o $OutDir --no-build

    # Stop existing process by matching the published DLL path in the command line
    $escaped = [regex]::Escape($dllPath)
    $procs = Get-CimInstance Win32_Process |
        Where-Object { $_.Name -eq "dotnet.exe" -and $_.CommandLine -match $escaped }

    foreach ($p in $procs) {
        Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    if ($Update) {
        # --- Config (as provided) ---
        $publishDir = $OutDir
        $zipPath    = "C:\tmp\TestAuto.Web.zip"
        $stageDir   = Join-Path $env:TEMP ("PublishStage_" + [guid]::NewGuid().ToString("N"))

        # --- Safety & diagnostics ---
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'

        Write-Host "PublishDir : $publishDir"
        Write-Host "ZipPath    : $zipPath"
        Write-Host "StageDir   : $stageDir"

        # 0) Validate source exists and has content
        if (-not (Test-Path -LiteralPath $publishDir)) {
            throw "Publish directory does not exist: $publishDir"
        }
        if (-not (Get-ChildItem -LiteralPath $publishDir -Force -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1)) {
            throw "Publish directory is empty: $publishDir"
        }

        # 1) Create staging folder
        if (Test-Path -LiteralPath $stageDir) { Remove-Item -LiteralPath $stageDir -Recurse -Force }
        New-Item -ItemType Directory -Path $stageDir -Force | Out-Null
        Write-Host "Created staging folder."

        # 2) Copy everything while excluding *all* appsettings*.json files
        $robolog = Join-Path $env:TEMP ("robocopy_" + [guid]::NewGuid().ToString("N") + ".log")
        $null = robocopy $publishDir $stageDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP /XF appsettings*.json /MT:8 /XJ /COPY:DAT /DCOPY:D /LOG:$robolog
        $rc = $LASTEXITCODE
        Write-Host "Robocopy exit code: $rc  (log: $robolog)"

        if ($rc -gt 7) {
            Write-Host "Robocopy failed. Showing tail of log:"
            Get-Content -Path $robolog -Tail 200 | Write-Host
            throw "Robocopy error (exit code $rc)."
        }

        # Quick check that we actually copied something
        $stagedCount = (Get-ChildItem -LiteralPath $stageDir -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host "Staged file count: $stagedCount"
        if ($stagedCount -eq 0) { throw "Nothing was staged. Check your exclude patterns and source folder." }

        # 3) Remove existing zip if any
        if (Test-Path -LiteralPath $zipPath) {
            Remove-Item -LiteralPath $zipPath -Force
            Write-Host "Removed existing zip at $zipPath"
        }

        # 4) Zip the staged folder using .NET ZipFile
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory($stageDir, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $false)
        Write-Host "Created zip at $zipPath"

        # Validate the zip exists and show size
        if (-not (Test-Path -LiteralPath $zipPath)) {
            throw "Zip creation reported success but file is missing: $zipPath"
        }
        $zipInfo = Get-Item -LiteralPath $zipPath
        Write-Host ("Zip size: {0:N0} bytes" -f $zipInfo.Length)

        # 5) Clean up staging folder
        Remove-Item -LiteralPath $stageDir -Recurse -Force
        Write-Host "Cleaned up staging folder."
        Write-Host "Done (update zip only)." -ForegroundColor Green

        return
    }

    Write-Host "Starting $ProjectName (Kestrel)..." -ForegroundColor Yellow
    Push-Location $OutDir
    try {
        & dotnet $dllPath
    }
    finally {
        Pop-Location
    }

    Write-Host "Done." -ForegroundColor Green
}
Set-Alias dpspeed Dev-SpeedMerchantsRestart

# =====================================================================
# Git helpers for your personal private GitHub repos
# =====================================================================

function Ensure-OriginRemote {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Url
    )

    $existing = (git remote get-url origin 2>$null)
    if (-not $existing) {
        git remote add origin $Url | Out-Null
        return
    }

    if ($existing -ne $Url) {
        git remote set-url origin $Url | Out-Null
    }
}

function Git-QuickPush {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding()]
    param(
        [string]$Message = "Update",
        [switch]$WhatIf
    )

    $top = (git rev-parse --show-toplevel 2>$null)
    if (-not $top) { throw "Not in a git repository: $((Get-Location).Path)" }

    $branch = (git rev-parse --abbrev-ref HEAD).Trim()

    if ($WhatIf) {
        Write-Host "[WhatIf] Would run: git add ." -ForegroundColor Yellow
        Write-Host "[WhatIf] Would run: git commit -m `"$Message`" (if staged changes exist)" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would run: git push -u origin $branch" -ForegroundColor Yellow
        return
    }

    git add .

    # Commit only if something is staged
    $staged = (git diff --cached --name-only)
    if ($staged) {
        git commit -m $Message | Out-Null
    }

    git push -u origin $branch
}

function Git-TrustHere {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding()]
    param()

    $top = (git rev-parse --show-toplevel 2>$null)
    if (-not $top) { throw "Not in a git repository: $((Get-Location).Path)" }

    $safe = ($top -replace '\\', '/')
    git config --global --add safe.directory $safe | Out-Null
    Write-Host "Trusted safe.directory: $top" -ForegroundColor Green
}

# Push: PowerShell scripts repo
function Push-PowerShellScripts {
    [CmdletBinding()]
    param(
        [string]$Message = "Update PowerShell scripts",
        [switch]$WhatIf
    )

    Set-Location D:\PowershellScripts
    Ensure-OriginRemote -Url "https://github.com/genewebb/powershellscripts"
    Git-QuickPush -Message $Message -WhatIf:$WhatIf
}
Set-Alias pps Push-PowerShellScripts

# Push: SQL scripts repo
function Push-SqlScripts {
    [CmdletBinding()]
    param(
        [string]$Message = "Update SQL scripts",
        [switch]$WhatIf
    )

    Set-Location D:\SqlScripts
    Ensure-OriginRemote -Url "https://github.com/genewebb/sqlscripts"
    Git-QuickPush -Message $Message -WhatIf:$WhatIf
}
Set-Alias psql Push-SqlScripts

# Cursor rules: sync into cursor local repo, then commit + push
function Sync-And-Push-CursorRules {
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseApprovedVerbs', '', Justification='Profile helper')]
    [CmdletBinding()]
    param(
        [string]$Message = "Update cursor rules",
        [switch]$WhatIf
    )

    $scriptPath = "D:\PowershellScripts\sync-ai-rules.ps1"
    $targetRepo = "D:\repos\cursor-rules-templates"

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Missing sync script: $scriptPath"
    }
    if (-not (Test-Path -LiteralPath $targetRepo)) {
        throw "Missing target repo: $targetRepo"
    }

    if ($WhatIf) {
        & $scriptPath -TargetRepo $targetRepo -WhatIf
        Write-Host "[WhatIf] Skipping git commit/push for cursor rules repo." -ForegroundColor Yellow
        return
    }

    & $scriptPath -TargetRepo $targetRepo

    Set-Location $targetRepo
    Ensure-OriginRemote -Url "https://github.com/genewebb/cursor-rules-templates"
    Git-QuickPush -Message $Message
}
Set-Alias prules Sync-And-Push-CursorRules

# =====================================================================
# dotnet-suggest (System.CommandLine) completions
# =====================================================================

$_isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $_isAdmin -and (Get-Command "dotnet-suggest" -ErrorAction SilentlyContinue)) {
    $availableToComplete = (dotnet-suggest list) | Out-String
    $availableToCompleteArray = $availableToComplete.Split([Environment]::NewLine, [System.StringSplitOptions]::RemoveEmptyEntries)

    Register-ArgumentCompleter -Native -CommandName $availableToCompleteArray -ScriptBlock {
        param($wordToComplete, $commandAst, $cursorPosition)
        $fullpath = (Get-Command $commandAst.CommandElements[0]).Source

        $arguments = $commandAst.Extent.ToString().Replace('"', '\"')
        dotnet-suggest get -e $fullpath --position $cursorPosition -- "$arguments" | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
    }
}
elseif (-not $_isAdmin) {
    "Unable to provide System.CommandLine tab completion support unless the [dotnet-suggest] tool is first installed."
    "See the following for tool installation: https://www.nuget.org/packages/dotnet-suggest"
}
Remove-Variable _isAdmin

$env:DOTNET_SUGGEST_SCRIPT_VERSION = "1.0.2"

# =====================================================================
# AI repo shell integrations (~/AI/init.ps1)
# PS7+ only — init.ps1 uses Unicode characters that PS5.1 misparsed
# =====================================================================
$aiInit = Join-Path $HOME 'AI\init.ps1'
if ((Test-Path $aiInit) -and ($PSVersionTable.PSVersion.Major -ge 7)) { . $aiInit }

# =====================================================================
# Chocolatey profile import
# =====================================================================

$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
    Import-Module "$ChocolateyProfile"
}
