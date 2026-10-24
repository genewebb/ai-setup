# =====================================================================
# PowerShell 7.x Profile (Gene) - FAST bootstrap + lazy-loaded modules
# =====================================================================
#region Machine config ---------------------------------------------------------
# Everything that differs between machines (repo roots, script folders, secrets files, shares)
# is read from one Markdown file so the SAME profile runs on the laptop, SMVMTR1 and SMVMTR2.
# The file holds a table: | Key | Value | Used by |. Edit the Value column by hand.
#   - A missing row (or a missing file) keeps the default below.
#   - A blank Value means "not available on this machine"; commands that need it say so.
#   - %VARIABLES% such as %USERPROFILE% are expanded.
$global:GeneMachineConfigPath = 'C:\Deploy\Setup\ProfileMachineConfig.md'

$global:GeneMachineDefaults = [ordered]@{
    ReposRoot             = 'C:\devops\repos'
    SpeedMerchantsRepo    = 'C:\devops\repos\speed-merchants'
    SpeedyRepo            = 'C:\devops\repos\speedmerchants'
    AIProfiseeRepo        = 'C:\devops\repos\ai-profisee'
    PlatformRepo          = 'C:\devops\repos\platform'
    BitsDir               = 'C:\Bits'
    PowershellScriptsDir  = 'D:\PowershellScripts'
    SqlScriptsDir         = 'D:\SqlScripts'
    LocalSpeedSecretsFile = 'D:\secrets\corpltr94.localspeed.json'
    PackageShare          = '\\CORPNAS01\RnD\Utilities\SpeedMerchants'
    # Second publish target (Publish-GeneSharedBits): blank SharedBitsHost = off.
    SharedBitsHost        = ''
    SharedBitsShare       = ''
    SharedBitsKeyScript   = ''
    SharedBitsStaging     = ''
    VaultDocsRoot         = 'Q:\Work\Work\99 Documentation'
    MarkitdownVenv        = '%USERPROFILE%\.venvs\markitdown'
    MarkitdownOcrScript   = 'C:\devopslocal\powershellscripts\ocr_pdf.py'
    # Optional caps for addStreamTab (whole numbers); blank = no limit, the owner decides how many to run.
    StreamMaxAuthors      = ''
    StreamMaxBuilders     = ''
}

# Keys the AI runtime adds to the same first table (read by lib\MachineConfig.psm1 in the AI corpus).
# The profile does not use them; it only accepts them without a warning.
$global:GeneMachineAIKeys = @(
    'AIWorkRoot', 'ClaudeHome', 'WorktreesRoot', 'ScratchRoot', 'StatusPageDir', 'VaultWorkRoot',
    'VaultPersonalRoot', 'SecretsDir', 'ArchiveRoot', 'TestedClaudeVersion', 'TranscriptRetentionDays',
    'AllowTempInRepo', 'SkillsLinkRoot', 'DeployRoot', 'StreamHostDir', 'ShareRepo'
)

function Read-GeneMachineConfig {
    <#
    .SYNOPSIS
        Builds $global:GeneMachine from the defaults plus the Value column of the machine config table.
    #>
    [CmdletBinding()]
    param([string]$Path = $global:GeneMachineConfigPath)

    $settings = [ordered]@{}
    foreach ($key in $global:GeneMachineDefaults.Keys) { $settings[$key] = $global:GeneMachineDefaults[$key] }
    # The AI runtime's keys, read-only here (e.g. ClaudeHome for the stream commands): $global:GeneMachineAI.
    $aiValues = [ordered]@{}

    if (Test-Path -LiteralPath $Path) {
        $inTable = $false
        foreach ($line in Get-Content -LiteralPath $Path) {
            # Only the FIRST table is the profile's. Later tables (Resources, Claude access, Git policy,
            # MCP servers) belong to the AI runtime (lib\MachineConfig.psm1) and are never read here.
            if ($line -notmatch '^\s*\|') {
                if ($inTable) { break }
                continue
            }
            $inTable = $true
            # | Key | Value | ... - the header and separator rows fall out because their key is unknown.
            if ($line -notmatch '^\s*\|\s*`?([A-Za-z][A-Za-z0-9]*)`?\s*\|([^|]*)\|') { continue }
            $key = $Matches[1]
            if (-not $global:GeneMachineDefaults.Contains($key)) {
                if ($key -in $global:GeneMachineAIKeys) { $aiValues[$key] = [Environment]::ExpandEnvironmentVariables($Matches[2].Trim().Trim('`').Trim()) }
                elseif ($key -notin @('Key', 'Setting')) { Write-Warning "Machine config: unknown key '$key' in $Path (ignored)." }
                continue
            }
            $settings[$key] = $Matches[2].Trim().Trim('`').Trim()
        }
    }

    foreach ($key in @($settings.Keys)) {
        $settings[$key] = [Environment]::ExpandEnvironmentVariables([string]$settings[$key])
    }
    $global:GeneMachine = $settings
    $global:GeneMachineAI = $aiValues
}

function Get-GeneMachineSetting {
    <#
    .SYNOPSIS
        Returns one machine-specific setting; with -MustExist, throws a clear error when the
        setting is blank or its path is missing on this machine.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$MustExist
    )

    if (-not $global:GeneMachine.Contains($Name)) { throw "Unknown machine setting '$Name'." }
    $value = $global:GeneMachine[$Name]
    if ($MustExist) {
        if (-not $value) {
            throw "$Name is not available on $env:COMPUTERNAME (blank in $global:GeneMachineConfigPath)."
        }
        if (-not (Test-Path -LiteralPath $value)) {
            throw "$Name not found on $env:COMPUTERNAME`: '$value'. Fix it in $global:GeneMachineConfigPath."
        }
    }
    return $value
}

function Show-GeneMachineConfig {
    <#
    .SYNOPSIS
        Lists every machine setting, its value on this machine and whether that path exists.
    #>
    [CmdletBinding()]
    param()

    $fileState = if (Test-Path -LiteralPath $global:GeneMachineConfigPath) { 'found' } else { 'MISSING - using defaults' }
    Write-Host "Machine config: $global:GeneMachineConfigPath ($fileState)" -ForegroundColor Cyan
    foreach ($key in $global:GeneMachine.Keys) {
        $value = $global:GeneMachine[$key]
        [pscustomobject]@{
            Setting = $key
            Value   = $value
            Exists  = if ($value) { Test-Path -LiteralPath $value } else { $null }
            Default = ($value -eq [Environment]::ExpandEnvironmentVariables($global:GeneMachineDefaults[$key]))
        }
    }
}
Set-Alias -Name machinecfg -Value Show-GeneMachineConfig -Scope Global

Read-GeneMachineConfig
#endregion ---------------------------------------------------------------------

# -----------------------------
# Helpers: usage + common utilities
# -----------------------------
function Test-HelpRequested {
    [CmdletBinding()]
    param(
        [switch]$ShowHelp,
        [string[]]$RemainingArgs = @()
    )

    if ($ShowHelp) { return $true }

    foreach ($a in $RemainingArgs) {
        if ($a -in @('--help', '--Help')) {
            return $true
        }
    }

    return $false
}

function Write-Usage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Command,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    Write-Host ""
    Write-Host "Usage: $Command" -ForegroundColor Cyan
    foreach ($line in $Lines) {
        if ($null -eq $line -or $line -eq '') {
            Write-Host ""
        }
        else {
            Write-Host "  $line"
        }
    }
    Write-Host ""
}

function Assert-PathExists {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PathToCheck
    )

    if (-not (Test-Path -LiteralPath $PathToCheck)) {
        throw "Path not found: $PathToCheck"
    }
}

function Invoke-GitChecked {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string[]]$GitArgs,
        [switch]$AllowNonZero
    )

    & git @GitArgs
    $code = $LASTEXITCODE

    if (-not $AllowNonZero -and $code -ne 0) {
        throw "git $($GitArgs -join ' ') failed with exit code $code"
    }

    return $code
}

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

    try { Set-PSReadLineOption -Colors $cmap } catch {
        foreach ($k in $cmap.Keys) {
            try { Set-PSReadLineOption -Colors @{ $k = $cmap[$k] } } catch {}
        }
    }

    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward

    Set-PSReadLineOption -BellStyle None
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -MaximumHistoryCount 50000
    Set-PSReadLineKeyHandler -Key Tab    -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
}


# -----------------------------
# Prompt: full path in colored bar (with fallback)
# -----------------------------
function prompt {
    $markA = "`e]133;A`a"
    $markB = "`e]133;B`a"

    if ($PSStyle) {
        return "${markA}$($PSStyle.Background.Blue)$($PSStyle.Foreground.BrightWhite)$(Get-Location)$($PSStyle.Reset)> ${markB}"
    }

    return "${markA}$([char]27)[44;97m$(Get-Location)$([char]27)[0m> ${markB}"
}

# -----------------------------
# Lazy module loader
# -----------------------------
$script:GeneModulesLoaded = @{}

# Where every dp* build drop lands: -Package setup exes, -Update zips, dpall logs. Global (not
# script) because Gene.DevOpsTools reads it too, and a module cannot see profile script scope.
$global:GeneBitsDir = $global:GeneMachine.BitsDir

function Import-GeneModuleOnce {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Name
    )

    if ($script:GeneModulesLoaded.ContainsKey($Name)) { return }

    Import-Module $Name -ErrorAction Stop -WarningAction SilentlyContinue
    $script:GeneModulesLoaded[$Name] = $true
}

# -----------------------------
# Terminal tab helpers
# -----------------------------
# addtab / addnew open plain Windows Terminal tabs (the default profile, nothing run in them) in the window they are
# typed in; Test-GeneWt (with the stream tab helpers below) checks for that window. Stream tabs are addStreamTab's.
# A named tab's color comes from the first rule its title starts with (case-insensitive), else the default color.
$global:GeneTabColorRules = @(
    @{ Prefix = 'status';    Color = '#2f81f7' }
    @{ Prefix = 'plan';      Color = '#a371f7' }
    @{ Prefix = 'author';    Color = '#3fb950' }
    @{ Prefix = 'build';     Color = '#d29922' }
    @{ Prefix = 'integrat';  Color = '#f85149' }
    @{ Prefix = 'kit';       Color = '#39c5cf' }
    @{ Prefix = 'coordinat'; Color = '#db61a2' }
    @{ Prefix = 'git';       Color = '#db6d28' }
    @{ Prefix = 'compile';   Color = '#5a5fd6' }
    @{ Prefix = 'general';   Color = '#8b949e' }
)
$global:GeneTabDefaultColor = '#58a6ff'

function Get-GeneWtPath { return (Get-Command wt.exe -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1).Source }

# $true when Windows Terminal is installed; writes the error otherwise.
function Test-GeneWt {
    param([Parameter(Mandatory)][string]$Caller)
    if (-not (Get-GeneWtPath)) {
        Write-Error "${Caller}: Windows Terminal (wt.exe) was not found. Install it (winget install Microsoft.WindowsTerminal). Nothing was opened."
        return $false
    }
    # Tabs open in the window this command runs in, so the owner groups them by choosing where to type it.
    if (-not $env:WT_SESSION) {
        Write-Error "${Caller}: run this from a Windows Terminal tab; the new tabs open in that terminal. Nothing was opened."
        return $false
    }
    return $true
}

function Get-GeneTabColor {
    param([Parameter(Mandatory)][string]$Title)
    $rule = $global:GeneTabColorRules | Where-Object { $Title.TrimStart().StartsWith($_.Prefix, [StringComparison]::OrdinalIgnoreCase) } |
        Select-Object -First 1
    if ($rule) { return $rule.Color }
    return $global:GeneTabDefaultColor
}

# Opens one tab in the current Windows Terminal window (wt -w 0) running the default profile. With -Title the tab is
# named and colored, and keeps that name whatever the shell or app in it sets (--suppressApplicationTitle).
function New-GeneTab {
    param([Parameter(Mandatory)][string]$Directory, [string]$Title)
    $wtArgs = @('-w', '0', 'new-tab', '-d', $Directory)
    if ($Title) { $wtArgs += @('--title', $Title, '--suppressApplicationTitle', '--tabColor', (Get-GeneTabColor -Title $Title)) }
    & (Get-GeneWtPath) @wtArgs
    if ($LASTEXITCODE) { throw "wt.exe new-tab failed (exit $LASTEXITCODE)" }
}

# -----------------------------
# DevOps commands (lazy-loaded)
# -----------------------------


# -----------------------------
# dotnet-suggest completions (lazy-load on first dotnet use)
# -----------------------------
if (Get-Command "dotnet-suggest" -ErrorAction SilentlyContinue) {
    $script:DotnetSuggestLoaded = $false

    function Enable-DotnetSuggestCompletionsOnce {
        [CmdletBinding()]
        param()

        if ($script:DotnetSuggestLoaded) { return }
        $script:DotnetSuggestLoaded = $true

        try {
            Import-GeneModuleOnce "Gene.Completions"
            Enable-DotnetSuggestCompletions
        }
        catch {
            # Ignore completion initialization errors to avoid blocking dotnet
        }
    }

    # Wrap dotnet so first invocation enables completions, then runs dotnet normally.
    if (-not (Get-Command dotnet -CommandType Function -ErrorAction SilentlyContinue)) {
        function dotnet {
            Enable-DotnetSuggestCompletionsOnce
            Remove-Item function:\dotnet -Force -ErrorAction SilentlyContinue
            & (Get-Command dotnet -CommandType Application).Source @args
        }
    }
}

# -----------------------------
# Seq: clear events (TestAuto.Web / local)
# -----------------------------
$clearSeqScript = "$($global:GeneMachine.PowershellScriptsDir)\clearseq.ps1"
if (Test-Path -LiteralPath $clearSeqScript) {
    . $clearSeqScript
}


# Categories: one file per prof other category (navigate, tabs, build, git, board, profile, claude, tools). Each holds only
# definitions, so the order is for reading, not for correctness. prof setup share copies the picked files.
foreach ($geneCategoryFile in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'profile.d') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name) { . $geneCategoryFile.FullName }
Remove-Variable -Name geneCategoryFile -ErrorAction SilentlyContinue
# A re-run of this profile (. $PROFILE, e.g. after prof setup reload) also reloads the Gene.* modules this window has
# already loaded: PowerShell otherwise keeps a loaded module's old code. Re-imported BY NAME, because piping
# Get-Module's output to Import-Module -Force reuses the loaded module and does not re-read its files (tested 10/17).
foreach ($geneModule in @(Get-Module -Name 'Gene.*' | Select-Object -ExpandProperty Name -Unique)) {
    Import-Module -Name $geneModule -Force -Global -DisableNameChecking
}
Remove-Variable -Name geneModule -ErrorAction SilentlyContinue
