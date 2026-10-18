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
    DocumentationDir      = 'D:\documentation'
    CursorRulesDir        = 'D:\repos\cursor-rules-templates'
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
    'AllowTempInRepo', 'SkillsLinkRoot', 'DeployRoot', 'StreamHostDir'
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

# AI-related paths tracked by pushrules / dpAI
$script:GeneAiPaths = @(
    '.cursor',
    '.vscode',
    '.github',
    '.swarm',
    '.claude',
    '.opencode'
)

function Get-GeneAiGitPaths {
    [CmdletBinding()]
    param()
    return $script:GeneAiPaths
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
# Git helper: commit/push ONLY AI-related paths in the CURRENT repo
# (Used by dpAI, including when dpAI temporarily enters template repo)
# -----------------------------
function pushrules {
    [CmdletBinding()]
    param(
        [string]$Message = "",
        [string]$Remote = "origin",
        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "pushrules [-Message <msg>] [-Remote <remote>] [-h|--help]" @(
            "Commits and pushes ONLY AI-related paths (.cursor/.vscode/.github/.swarm/.claude) in the CURRENT repo.",
            "Examples:",
            "  pushrules",
            "  pushrules -Message 'rules: sync local tweaks'",
            "  pushrules -Remote origin"
        )
        return
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        throw "git not found on PATH."
    }

    $top = (& git rev-parse --show-toplevel 2>$null).Trim()
    if (-not $top) { throw "Not in a git repo." }

    Push-Location $top
    try {
        $allowedPaths = Get-GeneAiGitPaths

        # Informational repo status
        & git status

        # Guard: if user already has staged changes OUTSIDE allowed AI paths, abort.
        $stagedFiles = (& git diff --cached --name-only 2>$null) | Where-Object { $_ -and $_.Trim() }
        if ($stagedFiles) {
            $outside = @()

            foreach ($f in $stagedFiles) {
                $normF = ($f -replace '\\','/').TrimStart('./')
                $isAllowed = $false

                foreach ($p in $allowedPaths) {
                    $normP = ($p -replace '\\','/').TrimStart('./')
                    if ($normF -eq $normP -or $normF.StartsWith("$normP/")) {
                        $isAllowed = $true
                        break
                    }
                }

                if (-not $isAllowed) { $outside += $f }
            }

            if ($outside.Count -gt 0) {
                Write-Host "Aborting: staged non-AI changes detected." -ForegroundColor Yellow
                $outside | ForEach-Object { Write-Host "  $_" -ForegroundColor DarkYellow }
                Write-Host "Commit/stash/reset those first, then run pushrules again." -ForegroundColor Yellow
                return
            }
        }

        # Stage ONLY allowed AI paths (adds/updates/deletes)
        foreach ($p in $allowedPaths) {
            $full = Join-Path $top $p
            if (Test-Path -LiteralPath $full) {
                Invoke-GitChecked -GitArgs @('add','-A','--',$p) | Out-Null
            }
        }

        # If nothing staged in those paths, exit cleanly
        & git diff --cached --quiet
        if ($LASTEXITCODE -eq 0) {
            Write-Host "No AI-related changes to commit (.cursor/.vscode/.github/.swarm/.claude)." -ForegroundColor DarkGray
            return
        }

        if ([string]::IsNullOrWhiteSpace($Message)) {
            $Message = "rules: sync $(Get-Date -Format 'yyyy-MM-dd HH:mm')"
        }

        Invoke-GitChecked -GitArgs @('commit','-m',$Message) | Out-Null

        # Push (auto-set upstream if missing)
        & git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
        $hasUpstream = ($LASTEXITCODE -eq 0)

        $branch = (& git branch --show-current).Trim()
        if ([string]::IsNullOrWhiteSpace($branch)) {
            throw "Could not determine current branch."
        }

        if (-not $hasUpstream) {
            Invoke-GitChecked -GitArgs @('push','-u',$Remote,$branch) | Out-Null
        }
        else {
            Invoke-GitChecked -GitArgs @('push',$Remote) | Out-Null
        }

        Write-Host "AI-related changes pushed successfully." -ForegroundColor Green
    }
    finally {
        Pop-Location
    }
}


# -----------------------------
# Unified AI sync / publish command
# -----------------------------
function dpAI {
    [CmdletBinding(DefaultParameterSetName='None')]
    param(
        # Exactly one mode:
        [Parameter(ParameterSetName='Local')]
        [switch]$Local,    # template -> current repo

        [Parameter(ParameterSetName='Remote')]
        [switch]$Remote,   # current repo -> template

        [Parameter(ParameterSetName='Git')]
        [switch]$Git,      # template repo -> actual git remote (ALWAYS template)

        [Parameter(ParameterSetName='Promote')]
        [switch]$Promote,  # current repo -> template, then template -> actual git remote

        [string]$TemplatePath = $global:GeneMachine.DocumentationDir,
        [string]$RepoPath = (Get-Location).Path,
        [string]$GitRemoteName = "origin",
        [string]$Message = "",

        [switch]$Force,
        [switch]$WhatIf,
        [switch]$Try,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "dpAI (-Local | -Remote | -Git | -Promote) [options] [-h|--help]" @(
            "Single command for AI rules/settings sync + template publishing.",
            "Documentation repos are auto-created and configured on first use.",
            "",
            "Modes:",
            "  -Local    Apply template to current repo (template -> repo)",
            "  -Remote   Sync current repo AI files back to template repo (repo -> template)",
            "  -Git      Commit/push each tool's documentation repo to git remote",
            "  -Promote  Sync current repo -> template, then commit/push each tool's documentation repo",
            "",
            "Options:",
            "  -Force        Overwrite all (skip smart diff). Not valid with -Git.",
            "  -WhatIf/-Try  Preview only, don't copy or commit.",
            "  -Message      Custom commit message for -Git/-Promote.",
            "",
            "Examples:",
            "  dpAI -Local",
            "  dpAI -Local -WhatIf",
            "  dpAI -Remote -Force",
            "  dpAI -Git",
            "  dpAI -Promote -Force",
            "  dpAI -Promote -Message 'rules: promote updates'"
        )
        return
    }

    if (-not ($Local -or $Remote -or $Git -or $Promote)) {
        throw "Specify a mode: -Local, -Remote, -Git, or -Promote. Use dpAI -help for examples."
    }

    $scriptPath = Join-Path $global:GeneMachine.PowershellScriptsDir "sync-ai-rules.ps1"
    $previewMode = $WhatIf -or $Try

    # Build common args for sync-ai-rules.ps1
    $syncArgs = @{}
    if ($Force)       { $syncArgs.Force = $true }
    if ($previewMode) { $syncArgs.Try = $true }

    # Load tools config for -Git/-Promote (needed to find per-tool documentation repos)
    function Load-DpAIToolsConfig {
        $configPath = Join-Path $global:GeneMachine.PowershellScriptsDir "sync-ai-rules.json"
        if (-not (Test-Path $configPath)) { throw "Missing: $configPath" }
        return (Get-Content $configPath -Raw | ConvertFrom-Json)
    }

    # Resolve a remoteUrl template: {owner} from config, {token} from env var
    function Resolve-RemoteUrl {
        param(
            [string]$UrlTemplate,
            [string]$Owner,
            [string]$TokenEnvVar
        )
        $url = $UrlTemplate -replace '\{owner\}', $Owner
        if ($TokenEnvVar) {
            $token = [Environment]::GetEnvironmentVariable($TokenEnvVar)
            if ($token) {
                # Insert token into https URL: https://<token>@github.com/...
                $url = $url -replace 'https://', "https://$token@"
            }
        }
        return $url
    }

    # Commit/push a single tool's documentation repo
    function Invoke-ToolGitSync {
        param(
            [string]$ToolName,
            [string]$RepoFullPath,
            [string]$CommitMessage,
            [string]$RemoteName,
            [string]$RemoteUrl,
            [bool]$Preview
        )

        if (-not (Test-Path $RepoFullPath)) {
            Write-Host "  [$ToolName] Documentation repo not found: $RepoFullPath — skipping." -ForegroundColor DarkYellow
            return
        }

        # Check if it's a git repo
        $gitDir = Join-Path $RepoFullPath ".git"
        if (-not (Test-Path $gitDir)) {
            Write-Host "  [$ToolName] Not a git repo: $RepoFullPath — skipping." -ForegroundColor DarkYellow
            return
        }

        Push-Location $RepoFullPath
        try {
            # Ensure the remote is configured with the correct URL
            if ($RemoteUrl) {
                $currentUrl = & git remote get-url $RemoteName 2>$null
                if (-not $currentUrl) {
                    # Remote doesn't exist — add it
                    & git remote add $RemoteName $RemoteUrl 2>$null
                    Write-Host "  [$ToolName] Added remote '$RemoteName' -> $($RemoteUrl -replace '://[^@]+@', '://***@')" -ForegroundColor DarkGray
                } elseif ($currentUrl -ne $RemoteUrl) {
                    # Remote URL changed — update it
                    & git remote set-url $RemoteName $RemoteUrl 2>$null
                    Write-Host "  [$ToolName] Updated remote '$RemoteName' URL" -ForegroundColor DarkGray
                }
            }

            # Check for any changes (tracked modifications + untracked files)
            $status = & git status --porcelain 2>$null
            if (-not $status) {
                Write-Host "  [$ToolName] No changes to commit." -ForegroundColor DarkGray
                return
            }

            if ($Preview) {
                Write-Host "  [$ToolName] [WhatIf] Would commit and push:" -ForegroundColor Yellow
                Write-Host "    Remote:  $RemoteName ($($RemoteUrl -replace '://[^@]+@', '://***@'))" -ForegroundColor DarkGray
                Write-Host "    Message: $CommitMessage" -ForegroundColor DarkGray
                & git status --short
                return
            }

            # Stage and commit
            & git add -A . 2>$null | Out-Null
            Invoke-GitChecked -GitArgs @('commit', '-m', $CommitMessage) | Out-Null

            # Push (auto-set upstream if missing)
            & git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null | Out-Null
            $hasUpstream = ($LASTEXITCODE -eq 0)
            $branch = (& git branch --show-current).Trim()

            if (-not $hasUpstream) {
                Invoke-GitChecked -GitArgs @('push', '-u', $RemoteName, $branch) | Out-Null
            } else {
                Invoke-GitChecked -GitArgs @('push', $RemoteName) | Out-Null
            }

            Write-Host "  [$ToolName] Committed and pushed." -ForegroundColor Green
        }
        finally {
            Pop-Location
        }
    }

    # Ensure all documentation repos exist, are git-initialized, and have remotes configured.
    # Silently fixes anything missing — no prompts, no stopping.
    function Ensure-DocumentationRepos {
        param($FullConfig, [string]$RemoteName, [bool]$Preview)

        $docRoot    = $FullConfig.documentationRoot
        $gitDef     = $FullConfig.gitDefaults
        $owner      = $gitDef.remoteOwner
        $tokenEnv   = $gitDef.tokenEnvVar

        # Documentation root
        if (-not (Test-Path $docRoot)) {
            if ($Preview) {
                Write-Host "  [WhatIf] Would create documentation root: $docRoot" -ForegroundColor Yellow
            } else {
                New-Item -ItemType Directory -Path $docRoot -Force | Out-Null
                Write-Host "  Created documentation root: $docRoot" -ForegroundColor Green
            }
        }

        foreach ($toolName in $FullConfig.tools.PSObject.Properties.Name) {
            $tool = $FullConfig.tools.$toolName
            if (-not $tool.documentationRepo) { continue }

            $toolRepoPath = Join-Path $docRoot $tool.documentationRepo
            $gitDir = Join-Path $toolRepoPath ".git"

            # Create directory
            if (-not (Test-Path $toolRepoPath)) {
                if ($Preview) {
                    Write-Host "  [WhatIf] Would create: $toolRepoPath" -ForegroundColor Yellow
                } else {
                    New-Item -ItemType Directory -Path $toolRepoPath -Force | Out-Null
                    Write-Host "  Created: $toolRepoPath" -ForegroundColor Green
                }
            }

            # Git init
            if (-not (Test-Path $gitDir) -and -not $Preview) {
                Push-Location $toolRepoPath
                try {
                    & git init 2>$null | Out-Null
                    Write-Host "  [$toolName] Initialized git repo" -ForegroundColor Green
                } finally { Pop-Location }
            }

            # Set remote
            if ($tool.remoteUrl -and (Test-Path $gitDir)) {
                $remoteUrl = Resolve-RemoteUrl -UrlTemplate $tool.remoteUrl -Owner $owner -TokenEnvVar $tokenEnv
                Push-Location $toolRepoPath
                try {
                    $currentUrl = & git remote get-url $RemoteName 2>$null
                    if (-not $currentUrl) {
                        & git remote add $RemoteName $remoteUrl 2>$null
                        $masked = $remoteUrl -replace '://[^@]+@', '://***@'
                        Write-Host "  [$toolName] Added remote '$RemoteName' -> $masked" -ForegroundColor Green
                    } elseif ($currentUrl -ne $remoteUrl) {
                        & git remote set-url $RemoteName $remoteUrl 2>$null
                        $masked = $remoteUrl -replace '://[^@]+@', '://***@'
                        Write-Host "  [$toolName] Updated remote '$RemoteName'" -ForegroundColor Green
                    }
                } finally { Pop-Location }
            }

            # Create subdirectories for documentationPath entries
            $docPaths = @()
            if ($tool.global) { foreach ($g in @($tool.global)) { $docPaths += $g.documentationPath } }
            if ($tool.repo)   { foreach ($r in @($tool.repo))   { $docPaths += $r.documentationPath } }
            foreach ($dp in $docPaths) {
                $fullDocPath = Join-Path $docRoot $dp
                if (-not (Test-Path $fullDocPath) -and -not $Preview) {
                    New-Item -ItemType Directory -Path $fullDocPath -Force | Out-Null
                }
            }
        }
    }

    # Silently ensure documentation repos are ready before any mode runs
    $fullConfigValidation = Load-DpAIToolsConfig
    $remoteNameValidation = if ($GitRemoteName) { $GitRemoteName } elseif ($fullConfigValidation.gitDefaults.remote) { $fullConfigValidation.gitDefaults.remote } else { "origin" }
    Ensure-DocumentationRepos -FullConfig $fullConfigValidation -RemoteName $remoteNameValidation -Preview $previewMode

    if ($Local) {
        # template -> repo
        if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Missing: $scriptPath" }
        Assert-PathExists -PathToCheck $RepoPath

        & $scriptPath @syncArgs -TemplatePath $TemplatePath -TargetRepo $RepoPath

        if ($LASTEXITCODE -ne 0) {
            throw "sync-ai-rules.ps1 failed in LOCAL mode (template -> repo)."
        }

        Write-Host "dpAI LOCAL complete (template -> repo)." -ForegroundColor Green
        return
    }

    if ($Remote) {
        # repo -> template
        if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Missing: $scriptPath" }
        Assert-PathExists -PathToCheck $RepoPath

        & $scriptPath @syncArgs -Pull -TemplatePath $TemplatePath -SourceRepo $RepoPath

        if ($LASTEXITCODE -ne 0) {
            throw "sync-ai-rules.ps1 failed in REMOTE mode (repo -> template)."
        }

        Write-Host "dpAI REMOTE complete (repo -> template)." -ForegroundColor Green
        return
    }

    if ($Git) {
        # Commit/push each tool's documentation repo
        if ($Force) {
            throw "-Force is not supported with -Git. Use -Force with -Local, -Remote, or -Promote sync steps only."
        }

        $fullConfig = Load-DpAIToolsConfig
        $docRoot = $fullConfig.documentationRoot
        $gitDefaults = $fullConfig.gitDefaults
        $remoteName = if ($GitRemoteName) { $GitRemoteName } elseif ($gitDefaults.remote) { $gitDefaults.remote } else { "origin" }
        $owner = $gitDefaults.remoteOwner
        $tokenEnvVar = $gitDefaults.tokenEnvVar
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'

        Write-Host "dpAI GIT: committing/pushing per-tool documentation repos..." -ForegroundColor Cyan

        foreach ($toolName in $fullConfig.tools.PSObject.Properties.Name) {
            $tool = $fullConfig.tools.$toolName
            if (-not $tool.documentationRepo) { continue }

            $toolRepoPath = Join-Path $docRoot $tool.documentationRepo
            $remoteUrl = if ($tool.remoteUrl) { Resolve-RemoteUrl -UrlTemplate $tool.remoteUrl -Owner $owner -TokenEnvVar $tokenEnvVar } else { $null }
            $msg = $Message
            if ([string]::IsNullOrWhiteSpace($msg)) {
                $msg = $gitDefaults.updateMessage -replace '\{tool\}', $toolName -replace '\{timestamp\}', $timestamp
            }

            Invoke-ToolGitSync -ToolName $toolName -RepoFullPath $toolRepoPath -CommitMessage $msg -RemoteName $remoteName -RemoteUrl $remoteUrl -Preview $previewMode
        }

        Write-Host "dpAI GIT complete." -ForegroundColor Green
        return
    }

    if ($Promote) {
        # Step 1: repo -> template (sync)
        if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Missing: $scriptPath" }
        Assert-PathExists -PathToCheck $RepoPath

        Write-Host "dpAI PROMOTE step 1/2: syncing current repo -> template..." -ForegroundColor Cyan

        & $scriptPath @syncArgs -Pull -TemplatePath $TemplatePath -SourceRepo $RepoPath

        if ($LASTEXITCODE -ne 0) {
            throw "sync-ai-rules.ps1 failed in PROMOTE step 1 (repo -> template)."
        }

        # Step 2: commit/push each tool's documentation repo
        Write-Host "dpAI PROMOTE step 2/2: committing/pushing per-tool documentation repos..." -ForegroundColor Cyan

        $fullConfig = Load-DpAIToolsConfig
        $docRoot = $fullConfig.documentationRoot
        $gitDefaults = $fullConfig.gitDefaults
        $remoteName = if ($GitRemoteName) { $GitRemoteName } elseif ($gitDefaults.remote) { $gitDefaults.remote } else { "origin" }
        $owner = $gitDefaults.remoteOwner
        $tokenEnvVar = $gitDefaults.tokenEnvVar
        $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm'
        $repoName = Split-Path -Leaf $RepoPath

        foreach ($toolName in $fullConfig.tools.PSObject.Properties.Name) {
            $tool = $fullConfig.tools.$toolName
            if (-not $tool.documentationRepo) { continue }

            $toolRepoPath = Join-Path $docRoot $tool.documentationRepo
            $remoteUrl = if ($tool.remoteUrl) { Resolve-RemoteUrl -UrlTemplate $tool.remoteUrl -Owner $owner -TokenEnvVar $tokenEnvVar } else { $null }
            $msg = $Message
            if ([string]::IsNullOrWhiteSpace($msg)) {
                $msg = $gitDefaults.updateMessage -replace '\{tool\}', $toolName -replace '\{timestamp\}', "$repoName $timestamp"
            }

            Invoke-ToolGitSync -ToolName $toolName -RepoFullPath $toolRepoPath -CommitMessage $msg -RemoteName $remoteName -RemoteUrl $remoteUrl -Preview $previewMode
        }

        Write-Host "dpAI PROMOTE complete (repo -> template -> git)." -ForegroundColor Green
        return
    }
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
# Profile utilities
# -----------------------------
function sp {
    [CmdletBinding()]
    param(
        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "sp [-h|--help]" @(
            "Same as: prof setup show (installed vs repo profile, and whether they match)."
        )
        return
    }

    Write-Host '(sp = prof setup show)' -ForegroundColor DarkGray
    Invoke-GeneProf streams show
}

function ep {
    [CmdletBinding()]
    param(
        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "ep [-h|--help]" @(
            "Same as: prof setup edit. Opens the REPO copy of the profile (the installed copy is overwritten by every install)."
        )
        return
    }

    Write-Host '(ep = prof setup edit)' -ForegroundColor DarkGray
    Invoke-GeneProf streams edit
}

Remove-Alias -Name rp -Force -ErrorAction SilentlyContinue
function rp {
    [CmdletBinding()]
    param(
        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "rp [-h|--help]" @(
            "Reloads the current PowerShell profile.",
            "Shows success/failure clearly."
        )
        return
    }

    try {
        . $PROFILE
        Write-Host "Profile reloaded: $PROFILE" -ForegroundColor Green
    }
    catch {
        Write-Host "Profile reload failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# -----------------------------
# Quick nav (work)
# -----------------------------
function cdevops {
    [CmdletBinding()]
    param([Alias('h','help')][switch]$ShowHelp)

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "cdevops [-h|--help]" @("Navigate to $($global:GeneMachine.ReposRoot)")
        return
    }

    $path = $global:GeneMachine.ReposRoot
    Assert-PathExists -PathToCheck $path
    Set-Location $path
}

function caiprof {
    [CmdletBinding()]
    param([Alias('h','help')][switch]$ShowHelp)

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "caiprof [-h|--help]" @("Navigate to $($global:GeneMachine.AIProfiseeRepo) (the shared Profisee AI repo)")
        return
    }

    $path = $global:GeneMachine.AIProfiseeRepo
    Assert-PathExists -PathToCheck $path
    Set-Location $path
}

function cspeed {
    [CmdletBinding()]
    param([Alias('h','help')][switch]$ShowHelp)

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "cspeed [-h|--help]" @("Navigate to $($global:GeneMachine.SpeedMerchantsRepo)")
        return
    }

    $path = $global:GeneMachine.SpeedMerchantsRepo
    Assert-PathExists -PathToCheck $path
    Set-Location $path
}

function ccrew {
    [CmdletBinding()]
    param([Alias('h','help')][switch]$ShowHelp)

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "ccrew [-h|--help]" @("Navigate to $(Join-Path $global:GeneMachine.SpeedMerchantsRepo 'CrewChief')")
        return
    }

    $path = Join-Path $global:GeneMachine.SpeedMerchantsRepo 'CrewChief'
    Assert-PathExists -PathToCheck $path
    Set-Location $path
}

# -----------------------------
# Quick nav (personal GitHub repos)
# -----------------------------
function cpower {
    [CmdletBinding()]
    param([Alias('h','help')][switch]$ShowHelp)

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "cpower [-h|--help]" @("Navigate to $($global:GeneMachine.PowershellScriptsDir)")
        return
    }

    $path = $global:GeneMachine.PowershellScriptsDir
    Assert-PathExists -PathToCheck $path
    Set-Location $path
}

function csql {
    [CmdletBinding()]
    param([Alias('h','help')][switch]$ShowHelp)

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "csql [-h|--help]" @("Navigate to $($global:GeneMachine.SqlScriptsDir)")
        return
    }

    $path = $global:GeneMachine.SqlScriptsDir
    Assert-PathExists -PathToCheck $path
    Set-Location $path
}

function ccursor {
    [CmdletBinding()]
    param([Alias('h','help')][switch]$ShowHelp)

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "ccursor [-h|--help]" @("Navigate to $($global:GeneMachine.CursorRulesDir)")
        return
    }

    $path = $global:GeneMachine.CursorRulesDir
    Assert-PathExists -PathToCheck $path
    Set-Location $path
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

function addtab {
    [CmdletBinding()]
    param(
        [Parameter(Position=0, ValueFromRemainingArguments=$true)]
        [string[]]$Name,

        [string]$Path,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "addtab <name...> [<path>] [-Path <path>] [-h|--help]" @(
            "Open a new tab in the current Windows Terminal window, titled <name>.",
            "The name is required; all words join into one title ('addtab Author 1' -> 'Author 1').",
            "Directory: -Path, or a trailing word that is an existing folder, else the current folder.",
            "Examples:",
            "  addtab Author 1",
            "  addtab Author 1 D:\devops\repos\speedmerchants",
            "  addtab build 2 -Path D:\devops\repos\speedmerchants"
        )
        return
    }

    if (-not (Test-GeneWt -Caller 'addtab')) { return }

    $words = @($Name | Where-Object { $_ })
    # A trailing word that is an existing folder is the directory, not part of the title.
    if (-not $Path -and $words.Count -gt 1 -and (Test-Path -LiteralPath $words[-1] -PathType Container)) {
        $Path  = $words[-1]
        $words = @($words[0..($words.Count - 2)])
    }

    $title = ($words -join ' ').Trim()
    if (-not $title) {
        Write-Warning "addtab: a tab name is required. Use 'addnew' for a tab with the default name."
        return
    }

    if (-not $Path) { $Path = (Get-Location).ProviderPath }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "addtab: folder not found: $Path"
        return
    }

    New-GeneTab -Directory $Path -Title $title
    Write-Host "Opened tab '$title' -> $Path" -ForegroundColor DarkGray
}

function addnew {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [ValidateRange(1,50)]
        [int]$Count = 1,

        [Parameter(Position=1)]
        [string]$Path,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "addnew [[-Count] <1..50>] [[-Path] <path>] [-h|--help]" @(
            "Open 1..N new tabs in the current Windows Terminal window with the default tab name.",
            "Directory: -Path, else the current folder.",
            "Alias: ntab",
            "Examples:",
            "  addnew",
            "  addnew 3",
            "  addnew 2 D:\devops\repos"
        )
        return
    }

    if (-not (Test-GeneWt -Caller 'addnew')) { return }

    if (-not $Path) { $Path = (Get-Location).ProviderPath }
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
        Write-Warning "addnew: folder not found: $Path"
        return
    }

    1..$Count | ForEach-Object { New-GeneTab -Directory $Path }
}

# Optional short alias (safer than using 'add')
Set-Alias -Name ntab -Value addnew -ErrorAction SilentlyContinue

# -----------------------------
# DevOps commands (lazy-loaded)
# -----------------------------

function Publish-GeneSharedBits {
    <#
        Second publish target for the dp* -Package tail (Publish-SpeedMerchantsPackage): copies the freshly built
        setup exes to SharedBitsShare and prunes STRICTLY-OLDER versions of the SAME product there, the same rule
        as the team share. Off while SharedBitsHost is blank in this machine's config.

        SharedBitsShare is SMVMTR1's S: (an Azure Files share). Outbound port 445 to Azure is blocked on the
        laptop's network, so the laptop cannot open it; SharedBitsHost can. The exes are staged on that host
        through its admin share (SharedBitsStaging is a path on the host), and a remote session there copies
        and prunes. The storage key is read ON the host from SharedBitsKeyScript (the `$AccountKey = "..."` line
        of MapDrive.ps1), used for a connection that lives only in that session, and never sent back: the
        session returns status lines only. Best-effort like the team share: every failure is a warning and
        the packages stay in the bits folder.
    #>
    param([Parameter(Mandatory)][object[]]$Plan, [Parameter(Mandatory)][string]$BitsDir)

    $relayHost = $global:GeneMachine.SharedBitsHost
    if (-not $relayHost) { return }
    $share     = $global:GeneMachine.SharedBitsShare
    $keyScript = $global:GeneMachine.SharedBitsKeyScript
    $staging   = $global:GeneMachine.SharedBitsStaging
    if (-not ($share -and $keyScript -and $staging)) {
        Write-Warning "Shared bits skipped: SharedBitsHost is set but SharedBitsShare, SharedBitsKeyScript or SharedBitsStaging is blank in $global:GeneMachineConfigPath."
        return
    }
    if ($staging -notmatch '^(?<d>[A-Za-z]):\\(?<rest>.+)$') {
        Write-Warning "Shared bits skipped: SharedBitsStaging must be a local path on $relayHost (e.g. C:\ProgramData\GeneSharedBits), not '$staging'."
        return
    }
    $stagingUnc = "\\$relayHost\$($Matches.d)`$\$($Matches.rest)"

    # 1. Stage the exes on the host (laptop -> host admin share; the host -> Azure leg is step 2).
    $names = @($Plan | ForEach-Object { $_.Built.Name })
    try { New-Item -ItemType Directory -Path $stagingUnc -Force -ErrorAction Stop | Out-Null }
    catch {
        Write-Warning "Shared bits skipped: cannot reach $stagingUnc ($($_.Exception.Message)) - package(s) left in $BitsDir."
        return
    }
    Write-Host "Staging $($names.Count) package(s) on $relayHost for $share..." -ForegroundColor Yellow
    $null = & robocopy $BitsDir $stagingUnc @names /J /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
    if ($LASTEXITCODE -ge 8) {
        Write-Warning "Shared bits skipped: staging on $relayHost failed (robocopy exit $LASTEXITCODE) - package(s) left in $BitsDir."
        return
    }

    # 2. Copy + prune on the host. Only Level/Text lines come back.
    $items = @($Plan | ForEach-Object {
        [pscustomobject]@{ Name = $_.Built.Name; Length = $_.Built.Length; Filter = $_.Filter; Version = [string]$_.Version }
    })
    try {
        $lines = Invoke-Command -ComputerName $relayHost -ErrorAction Stop -ArgumentList $share, $keyScript, $staging, $items -ScriptBlock {
            param($Share, $KeyScript, $Staging, $Items)
            $out = [System.Collections.Generic.List[object]]::new()
            function Say([string]$Level, [string]$Text) { $out.Add([pscustomobject]@{ Level = $Level; Text = $Text }) }
            $root = $null
            try {
                if ($Share -notmatch '^\\\\(?<srv>[^\\]+)\\(?<sh>[^\\]+)') { Say 'Warn' "SharedBitsShare is not a UNC path: $Share"; return }
                $root    = "\\$($Matches.srv)\$($Matches.sh)"
                $account = $Matches.srv.Split('.')[0]
                $hit = Select-String -LiteralPath $KeyScript -Pattern '^\s*\$AccountKey\s*=\s*"([^"]+)"' -ErrorAction SilentlyContinue | Select-Object -First 1
                if (-not $hit) { Say 'Warn' "No `$AccountKey line in $KeyScript on $env:COMPUTERNAME."; $root = $null; return }
                $null = & net.exe use $root "/user:Azure\$account" $hit.Matches[0].Groups[1].Value 2>&1
                $hit = $null
                if ($LASTEXITCODE -ne 0) { Say 'Warn' "Could not connect $root from $env:COMPUTERNAME (net use exit $LASTEXITCODE)."; $root = $null; return }

                New-Item -ItemType Directory -Path $Share -Force -ErrorAction Stop | Out-Null
                $existing = @(Get-ChildItem -LiteralPath $Share -Filter '*-Setup-*.exe' -File -ErrorAction Stop)
                foreach ($i in $Items) {
                    $on = $existing | Where-Object { $_.Name -eq $i.Name } | Select-Object -First 1
                    if ($on -and $on.Length -eq $i.Length) {
                        Say 'Gray' "Already on shared bits, upload skipped: $($i.Name)"
                    }
                    else {
                        $null = & robocopy $Staging $Share $i.Name /J /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
                        if ($LASTEXITCODE -ge 8) { Say 'Warn' "robocopy to $Share failed for $($i.Name) (exit $LASTEXITCODE); nothing pruned for it."; continue }
                        Say 'Ok' "Copied $($i.Name) -> $Share"
                    }
                    # Prune against the listing taken before any copy, so a sibling product's fresh upload is never seen.
                    $version = [version]$i.Version
                    foreach ($f in $existing) {
                        if ($f.Name -notlike $i.Filter -or $f.Name -eq $i.Name) { continue }
                        if ($f.Name -notmatch '-Setup-(?<v>\d+\.\d+\.\d+)\.exe$') { Say 'Warn' "Unrecognized package name left in shared bits: $($f.Name)"; continue }
                        if ([version]$Matches.v -ge $version) { Say 'Warn' "Newer package kept in shared bits: $($f.Name) (built $version is older)."; continue }
                        try { Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop; Say 'Gray' "Removed older package from shared bits: $($f.Name)" }
                        catch { Say 'Warn' "Could not remove old package from shared bits $($f.Name): $($_.Exception.Message)" }
                    }
                }
            }
            catch { Say 'Warn' "Shared bits on ${env:COMPUTERNAME}: $($_.Exception.Message)" }
            finally {
                foreach ($i in $Items) { Remove-Item -LiteralPath (Join-Path $Staging $i.Name) -Force -ErrorAction SilentlyContinue }
                if ($root) { $null = & net.exe use $root /delete /y 2>&1 }
                $out
            }
        }
    }
    catch {
        Write-Warning "Shared bits: the remote session on $relayHost failed ($($_.Exception.Message)) - package(s) left in $BitsDir."
        return
    }
    foreach ($l in @($lines)) {
        switch ($l.Level) {
            'Ok'    { Write-Host $l.Text -ForegroundColor Green }
            'Gray'  { Write-Host $l.Text -ForegroundColor DarkGray }
            default { Write-Warning $l.Text }
        }
    }
}

function Publish-SpeedMerchantsPackage {
    <#
        Shared tail step for dpspeed / dpcrewchief / dpdatagen / dpmutate -Package and for dpall:
        copies the setup exe(s) the packaging script(s) just produced (in C:\Bits, $global:GeneBitsDir) to the
        team share and prunes STRICTLY-OLDER versions of the SAME product from C:\Bits and the share (version
        parsed from the filename - a newer package already on the share is kept and named in a
        warning, so a downgrade rebuild can never destroy it). Reached only when packaging succeeded
        (the repo scripts throw on any failure). Best-effort: an unreachable share warns and never
        fails the build - the package is still in C:\Bits. -BuiltAfter guards against re-publishing a
        stale exe. Then the same packages go to the shared bits (Publish-GeneSharedBits, SMVMTR1's S:)
        when SharedBitsHost is set, whether or not the team share was reachable.

        -Product takes a LIST so dpall hands over all four products in ONE call. That is what makes
        the share optimisations possible. Measured 2026-08-25 against CORPNAS01, which moves only
        ~1.8 MB/s, so an 81 MB upload costs ~45s and dominates every other step in this function
        (a share delete is 0.84s, a share listing 0.48s):
          * ONE share listing per batch instead of Test-Path + Get-ChildItem per product (~1.7s
            each). A successful listing also proves reachability, which is why the separate
            Test-Path probe is gone - it was the expensive 1.22s half of that pair.
          * A copy is SKIPPED when the share already holds the same filename at the same byte
            length. A repackage with no version bump used to re-upload ~81 MB per product for
            nothing (~3 min on a four-product dpall).
          * The remaining copies run in PARALLEL, one runspace each, via robocopy rather than
            Copy-Item so a runspace needs no profile state. Only the copies parallelise; the prunes
            stay serial in this session because they cost under a second and serial ordering keeps
            the warnings readable.

        The share prune deliberately reads the PRE-RUN snapshot: it only ever considers packages
        that existed before this call, so it can neither see nor delete a sibling product's fresh
        upload. It is also skipped for any product whose own upload failed, so a failed copy never
        deletes the version it was meant to replace.
    #>
    param(
        [Parameter(Mandatory)][ValidateSet('CrewChief', 'TestAuto', 'TestDataGeneration', 'TestDataGenerationAndMutation')][string[]]$Product,
        [Parameter(Mandatory)][datetime]$BuiltAfter
    )

    # UNC, not Z:, so this works from elevated shells too (mapped drives are
    # per-logon-token - an admin session cannot see the user's Z: mapping).
    $share = $global:GeneMachine.PackageShare
    $bits  = $global:GeneBitsDir

    # Version parsed from the package filename (TestAuto-Setup-2.5.2.exe -> [version]2.5.2), or
    # $null when the name doesn't match. Prunes compare VERSIONS, not names: only strictly-older
    # packages are removed, so rebuilding an old version can never destroy a newer package that is
    # already on the share (the in-app update feed compares versions the same way).
    function Get-PackageVersion([System.IO.FileInfo]$File) {
        if ($File.Name -match '-Setup-(?<v>\d+\.\d+\.\d+)\.exe$') { [version]$Matches.v } else { $null }
    }

    # Removes packages matching $Filter that are STRICTLY OLDER than $Version; keeps (and names)
    # anything newer or unparseable. $Existing is a listing taken once by the caller, so neither
    # the bits folder nor the share is enumerated more than once per batch.
    function Remove-OlderPackages {
        param($Existing, [string]$Filter, [version]$Version, [string]$KeepName, [string]$FolderLabel)

        foreach ($f in @($Existing)) {
            if ($f.Name -notlike $Filter) { continue }
            if ($f.Name -eq $KeepName)    { continue }

            $v = Get-PackageVersion $f
            if (-not $v) {
                Write-Warning "Unrecognized package name left in ${FolderLabel}: $($f.Name)"
                continue
            }
            if ($v -ge $Version) {
                Write-Warning "Newer package kept in ${FolderLabel}: $($f.Name) (built $Version is older)."
                continue
            }
            try {
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
                Write-Host "Removed older package from ${FolderLabel}: $($f.Name)" -ForegroundColor DarkGray
            }
            catch {
                Write-Warning "Could not remove old package from $FolderLabel $($f.Name): $($_.Exception.Message)"
            }
        }
    }

    # 1. Locate each freshly built package in the bits folder (local, cheap - one listing for all products).
    $bitsItems = @(Get-ChildItem -Path $bits -Filter '*-Setup-*.exe' -File -ErrorAction SilentlyContinue)
    $plan = foreach ($p in $Product) {
        $productFilter = "$p-Setup-*.exe"
        $built = $bitsItems |
            Where-Object { $_.Name -like $productFilter -and $_.LastWriteTime -ge $BuiltAfter } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if (-not $built) {
            Write-Warning "No freshly built $productFilter found in $bits - nothing copied to $share."
            continue
        }
        $builtVersion = Get-PackageVersion $built
        if (-not $builtVersion) {
            Write-Warning "Could not parse a version from '$($built.Name)' - copied nothing, pruned nothing."
            continue
        }
        [pscustomobject]@{ Product = $p; Filter = $productFilter; Built = $built; Version = $builtVersion }
    }
    $plan = @($plan)
    if ($plan.Count -eq 0) { return }

    # 2. Prune the bits folder first, so an unreachable share still leaves it clean.
    foreach ($item in $plan) {
        Remove-OlderPackages -Existing $bitsItems -Filter $item.Filter -Version $item.Version `
            -KeepName $item.Built.Name -FolderLabel $bits
    }

    # 3. ONE share listing for the whole batch; it doubles as the reachability probe.
    $shareItems = $null
    $shareOk = $true
    try {
        $shareItems = @(Get-ChildItem -Path $share -Filter '*-Setup-*.exe' -File -ErrorAction Stop)
    }
    catch {
        # The folder can be missing on a share that is perfectly reachable; only a share we cannot
        # reach at all is fatal here (the packages are still in the bits folder either way).
        try {
            New-Item -ItemType Directory -Path $share -Force -ErrorAction Stop | Out-Null
            $shareItems = @()
        }
        catch {
            Write-Warning "Share not reachable: $share - package(s) left in $bits."
            $shareOk = $false
        }
    }

    if ($shareOk) {
        # 4. Same name at the same byte length means the share already has this exact build: skip ~45s.
        $toCopy = foreach ($item in $plan) {
            $onShare = $shareItems | Where-Object { $_.Name -eq $item.Built.Name } | Select-Object -First 1
            if ($onShare -and $onShare.Length -eq $item.Built.Length) {
                Write-Host ("Already on share, upload skipped: {0} ({1:N1} MB)" -f $item.Built.Name, ($item.Built.Length / 1MB)) -ForegroundColor DarkGray
                continue
            }
            $item
        }
        $toCopy = @($toCopy)

        # 5. Upload in parallel. robocopy exit codes below 8 are its success range; 8 and up is a real
        #    failure. robocopy also skips a byte- and timestamp-identical file on its own, which is a
        #    harmless second line of defence behind the check in step 4.
        $copyResults = @()
        if ($toCopy.Count -gt 0) {
            Write-Host "Uploading $($toCopy.Count) package(s) to $share..." -ForegroundColor Yellow
            $copyResults = $toCopy | ForEach-Object -ThrottleLimit $toCopy.Count -Parallel {
                $name = $_.Built.Name
                $out  = & robocopy $using:bits $using:share $name /J /R:1 /W:1 /NFL /NDL /NJH /NJS /NP 2>&1
                [pscustomobject]@{ FileName = $name; Code = $LASTEXITCODE; Output = ($out -join ' ').Trim() }
            }
        }
        foreach ($r in @($copyResults)) {
            if ($r.Code -lt 8) {
                Write-Host "Copied $($r.FileName) -> $share" -ForegroundColor Green
            }
            else {
                Write-Warning "robocopy failed for $($r.FileName) (exit $($r.Code)): $($r.Output) - the package is still in $bits."
            }
        }
        $failedNames = @(@($copyResults) | Where-Object { $_.Code -ge 8 } | ForEach-Object { $_.FileName })

        # 6. Prune the share against the pre-run snapshot (see the header note on why it is a snapshot).
        foreach ($item in $plan) {
            if ($failedNames -contains $item.Built.Name) { continue }
            Remove-OlderPackages -Existing $shareItems -Filter $item.Filter -Version $item.Version `
                -KeepName $item.Built.Name -FolderLabel 'share'
        }
    }

    # 7. The shared bits on SMVMTR1's S: (off while SharedBitsHost is blank).
    Publish-GeneSharedBits -Plan $plan -BitsDir $bits
}

function dpspeed {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [ValidateSet('Debug','Release')]
        [string]$Configuration,

        [switch]$Update,
        [switch]$Run,
        [switch]$CleanBuild,
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [string]$SolutionPath,
        [string]$ProjectName,

        [switch]$ClearSecrets,

        [switch]$UpdateClientId,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    # Compact help (daily use)
    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpspeed  - Speed-Merchants build/publish/run helper" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpspeed [-UpdateClientId] [-ClearSecrets] [-Configuration Debug|Release] [-Update] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-Run] [-CleanBuild] [-SolutionPath <path>] [-ProjectName <name>] [-ShowHelp] [-WhatIf]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -UpdateClientId Reads encrypted ClientId from meta.tUser, decrypts it, updates"
        Write-Host "                  corpltr94.localspeed.json, and clears cached secrets. Use after"
        Write-Host "                  a full platform build that regenerates the API key."
        Write-Host "  -ClearSecrets   Deletes $env:APPDATA\TestAuto\master.json before running."
        Write-Host "  -Configuration  Build/publish configuration (Debug or Release)."
        Write-Host "  -Update         Build + publish + create update zip, then exit (do not run app)."
        Write-Host "  -Package        Build the full install package (self-contained publish + Inno Setup)"
        Write-Host "                  -> $global:GeneBitsDir\TestAuto-Setup-<version>.exe, then exit. Thin wrapper over"
        Write-Host "                  installer\New-TestAutoInstaller.ps1."
        Write-Host "  -Bump           With -Package: bump the patch version (2.5.0 -> 2.5.1) in"
        Write-Host "                  TestAuto.Web.csproj <Version> before packaging."
        Write-Host "  -BumpMinor      With -Package: bump the minor version (2.5.3 -> 2.6.0)."
        Write-Host "  -BumpMajor      With -Package: bump the major version (2.5.3 -> 3.0.0)."
        Write-Host "                  Same Major.Minor.Patch scheme and switches as dpcrewchief -Package."
        Write-Host "                  At most one bump switch; without one the current version is reused."
        Write-Host "  -Run            Run existing published output only (skip build/publish)."
        Write-Host "  -CleanBuild     dotnet clean + wipe publish folder before build/publish. Use when"
        Write-Host "                  builds start feeling slow/wrong or stale plugin DLLs are suspected."
        Write-Host "  -SolutionPath   Override solution path."
        Write-Host "  -ProjectName    Override target project name."
        Write-Host "  -WhatIf         Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  -Debug is a PowerShell common parameter (debug tracing),"
        Write-Host "  not the same as -Configuration Debug."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpspeed -Run"
        Write-Host "    Run existing published output only."
        Write-Host "  dpspeed -UpdateClientId -Run"
        Write-Host "    Refresh API key after platform build, then run."
        Write-Host "  dpspeed -ClearSecrets -Run"
        Write-Host "    Clear local secrets file, then run published output."
        Write-Host "  dpspeed -Update"
        Write-Host "    Build + publish + create update zip, then exit."
        Write-Host "  dpspeed -Package [-Bump|-BumpMinor|-BumpMajor]"
        Write-Host "    Build the TestAuto-Setup-<version>.exe install package, then exit."
        Write-Host "    Version is Major.Minor.Patch in TestAuto.Web.csproj <Version> (same scheme as"
        Write-Host "    CrewChief): -Bump = patch, -BumpMinor = minor, -BumpMajor = major."
        Write-Host "    On success the package is copied to the team share and older"
        Write-Host "    TestAuto packages are removed from that share."
        Write-Host "    Share: $($global:GeneMachine.PackageShare)  (UNC, not Z: — mapped"
        Write-Host "    drives are per-logon-token and invisible to elevated shells.)"
        Write-Host "  dpspeed -Configuration Debug"
        Write-Host "    Build + publish + run using Debug."
        Write-Host ""
        Write-Host "Tip: dpspeed -? shows full native PowerShell help." -ForegroundColor DarkGray
        Write-Host ""
        return
    }

    # Guard: bump switches only mean something inside the -Package path below. Without this,
    # `dpspeed -Bump` (forgot -Package) falls through to the default build+publish+run with NO
    # version bump, no installer, and no error. Multi-bump throws HERE (not just in the repo
    # script) so a -WhatIf preview refuses exactly like a real run would.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if ($bumpSwitchCount -gt 0 -and -not $Package) {
        throw 'dpspeed: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpspeed: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }

    # Full install package: everything lives in the repo script (profile-free path documented in
    # installer\BUILDING.md); this switch is just a convenience entry point.
    if ($Package) {
        $packageScript = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'installer\New-TestAutoInstaller.ps1')
        if (-not (Test-Path -LiteralPath $packageScript)) {
            throw "Packaging script not found: $packageScript"
        }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: $packageScript -Configuration $(if ($Configuration) { $Configuration } else { 'Release' })" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (2.5.3 -> 3.0.0) in TestAuto.Web.csproj first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (2.5.3 -> 2.6.0) in TestAuto.Web.csproj first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (2.5.0 -> 2.5.1) in TestAuto.Web.csproj first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would produce: $global:GeneBitsDir\TestAuto-Setup-<version>.exe" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would copy it to $($global:GeneMachine.PackageShare) and remove older TestAuto-Setup-*.exe there." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
            return
        }
        $packStarted = Get-Date
        $packArgs = @{ OutputDir = $global:GeneBitsDir }
        if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
        if ($Bump) { $packArgs.Bump = $true }
        if ($BumpMinor) { $packArgs.BumpMinor = $true }
        if ($BumpMajor) { $packArgs.BumpMajor = $true }
        & $packageScript @packArgs
        # Deploy to the team share + prune older versions there — only reached on success
        # (the packaging script throws on any failure).
        Publish-SpeedMerchantsPackage -Product 'TestAuto' -BuiltAfter $packStarted
        return
    }

    Import-GeneModuleOnce "Gene.DevOpsTools"

    # --- UpdateClientId: decrypt from DB, update secrets JSON, auto-clear cache ---
    if ($UpdateClientId) {
        $secretsFile  = Get-GeneMachineSetting -Name LocalSpeedSecretsFile -MustExist

        # Newest installed platform version wins (was a hardcoded 26.1.0 pin, which went stale the
        # moment 26.2.0 landed). Version-named folders only; anything unparseable is ignored.
        $maestroRoot = Join-Path $env:ProgramFiles 'Profisee\Master Data Maestro Server'
        $securityDll = Get-ChildItem -LiteralPath $maestroRoot -Directory -ErrorAction Stop |
            Where-Object { $_.Name -match '^\d+(\.\d+)+$' } |
            Sort-Object { [version]$_.Name } -Descending |
            ForEach-Object { Join-Path $_.FullName 'Gateway\Profisee.Platform.Utilities.Security.dll' } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Select-Object -First 1
        if (-not $securityDll) { throw "Profisee.Platform.Utilities.Security.dll not found under any version folder in $maestroRoot" }

        # Read-only: query and decrypt (always runs, even with -WhatIf)
        $rawJson   = Get-Content -Raw -LiteralPath $secretsFile
        $secrets   = $rawJson | ConvertFrom-Json
        $connStr   = $secrets[0].ConnectionStrings.ProfiseeDB
        $oldApiKey = $secrets[0].RestClients.Profisee.ApiKey

        if (-not $connStr) { throw "ProfiseeDB connection string not found in $secretsFile" }

        # Query encrypted ClientId from meta.tUser. All LIKE matches are collected (ExecuteScalar
        # took an arbitrary first row when several names contained the username); an exact
        # DOMAIN\username (or bare-name) match wins, anything else ambiguous throws with the names.
        $conn = [System.Data.SqlClient.SqlConnection]::new($connStr)
        $conn.Open()
        $userRows = @()
        try {
            $cmd = $conn.CreateCommand()
            $cmd.CommandText = "SELECT NAME, ClientID FROM [meta].[tUser] WHERE NAME LIKE @u"
            [void]$cmd.Parameters.AddWithValue('@u', "%$env:USERNAME%")
            $reader = $cmd.ExecuteReader()
            while ($reader.Read()) {
                $userRows += [pscustomobject]@{
                    Name     = $reader.GetString(0)
                    ClientId = if ($reader.IsDBNull(1)) { $null } else { $reader.GetValue(1) }
                }
            }
        }
        finally { $conn.Dispose() }

        $userRows = @($userRows | Where-Object { $_.ClientId })
        if ($userRows.Count -eq 0) { throw "No ClientID found in meta.tUser for '$env:USERNAME'" }
        if ($userRows.Count -gt 1) {
            $exact = @($userRows | Where-Object { $_.Name -eq $env:USERNAME -or $_.Name -match "\\$([regex]::Escape($env:USERNAME))$" })
            if ($exact.Count -eq 1) {
                Write-Host "Multiple tUser rows matched '$env:USERNAME'; using exact match '$($exact[0].Name)'." -ForegroundColor DarkGray
                $userRows = $exact
            }
            else {
                throw "Ambiguous: $($userRows.Count) meta.tUser rows match '%$env:USERNAME%' ($(($userRows.Name) -join ', ')) and none/several match exactly. Refusing to guess."
            }
        }
        $encrypted = $userRows[0].ClientId

        # Decrypt using Profisee platform assembly (internal class, via reflection)
        if (-not (Test-Path $securityDll)) { throw "Security DLL not found: $securityDll" }
        $asm    = [System.Reflection.Assembly]::LoadFrom($securityDll)
        $type   = $asm.GetType('Profisee.Platform.Utilities.Security.Encryption')
        $method = $type.GetMethod('Decrypt',
            [System.Reflection.BindingFlags]'NonPublic,Static',
            $null, @([string]), $null)
        if (-not $method) { throw "Encryption.Decrypt method not found via reflection" }
        $newApiKey = $method.Invoke($null, @([string]$encrypted))

        if (-not $newApiKey) { throw "Decryption returned null" }

        # Masked 3+3 (same convention as CrewChief's SecretCatalog.GetMaskedValue) — full keys stay
        # out of console scrollback/transcripts; the new key lands in the secrets file either way.
        $maskKey = {
            param($k)
            if (-not $k) { '(none)' }
            elseif ($k.Length -le 8) { '********' }
            else { $k.Substring(0, 3) + ('*' * 6) + $k.Substring($k.Length - 3) }
        }
        Write-Host "Old ApiKey: $(& $maskKey $oldApiKey)" -ForegroundColor DarkGray
        Write-Host "New ApiKey: $(& $maskKey $newApiKey)" -ForegroundColor Green

        if ($oldApiKey -eq $newApiKey) {
            Write-Host "ClientId unchanged - nothing to update." -ForegroundColor Yellow
        }
        elseif ($PSCmdlet.ShouldProcess($secretsFile, "Replace ApiKey in secrets file")) {
            # Replace all occurrences in raw JSON (preserves original formatting)
            $updatedJson = $rawJson.Replace($oldApiKey, $newApiKey)
            $count = ([regex]::Matches($rawJson, [regex]::Escape($oldApiKey))).Count
            Set-Content -LiteralPath $secretsFile -Value $updatedJson -NoNewline
            Write-Host "Replaced $count occurrence(s) in $secretsFile" -ForegroundColor Green

            # Auto-clear cached secrets (stale after key change)
            $ClearSecrets = $true
        }
    }

    # Wrapper-only pre-step (supports -WhatIf)
    if ($ClearSecrets) {
        # Installed-as-service boxes read the MACHINE store advertised by TESTAUTO_SECRETS_FOLDER
        # (%ProgramData%\TestAuto) — this switch only clears the per-user dev-box file. Warn when
        # the env var is present so a cleared-but-still-bootstrapped app isn't a mystery.
        if ($env:TESTAUTO_SECRETS_FOLDER) {
            Write-Warning "TESTAUTO_SECRETS_FOLDER is set ($env:TESTAUTO_SECRETS_FOLDER) - an installed TestAuto reads that machine store; this clears only the per-user file below."
        }
        $secretFile = Join-Path $env:APPDATA 'TestAuto\master.json'

        if ($PSCmdlet.ShouldProcess($secretFile, 'Delete local TestAuto secrets file')) {
            if (Test-Path -LiteralPath $secretFile) {
                try {
                    Remove-Item -LiteralPath $secretFile -Force -ErrorAction Stop
                    Write-Host "Deleted secrets file: $secretFile" -ForegroundColor DarkGray
                }
                catch {
                    throw "Failed to delete secrets file '$secretFile': $($_.Exception.Message)"
                }
            }
            else {
                Write-Host "Secrets file not found (nothing to clear): $secretFile" -ForegroundColor DarkGray
            }
        }
    }

    # Build splat for underlying command
    $invoke = @{}

    if ($PSBoundParameters.ContainsKey('Configuration')) { $invoke.Configuration = $Configuration }
    if ($Update) { $invoke.Update = $true }
    if ($Run) { $invoke.Run = $true }
    if ($CleanBuild) { $invoke.CleanBuild = $true }
    if ($PSBoundParameters.ContainsKey('SolutionPath')) { $invoke.SolutionPath = $SolutionPath }
    if ($PSBoundParameters.ContainsKey('ProjectName')) { $invoke.ProjectName = $ProjectName }
    if ($WhatIfPreference) { $invoke.WhatIf = $true }

    Dev-SpeedMerchantsRestart @invoke
}

function dpcrewchief {
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding=$false)]
    param(
        [ValidateSet('Debug','Release')]
        [string]$Configuration,

        [switch]$Update,
        [switch]$Run,
        [switch]$CleanBuild,
        [switch]$Cli,
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [switch]$SealSecret,
        [switch]$Unlock,

        [string]$SolutionPath,
        [string]$ProjectName,

        [switch]$ClearSecrets,

        [switch]$UpdateClientId,

        [Alias('h','help')]
        [switch]$ShowHelp,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CliArgs = @()
    )

    # Compact help (daily use)
    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpcrewchief  - CrewChief build/publish/run helper" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpcrewchief [-Cli] [-Configuration Debug|Release] [-Update] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-Run] [-CleanBuild] [-SealSecret] [-Unlock] [-SolutionPath <path>] [-ProjectName <name>] [-ClearSecrets] [-UpdateClientId] [-ShowHelp] [-WhatIf] [-- <cli args>]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -Cli            Target CrewChief.Cli instead of CrewChief.Web. Remaining args are"
        Write-Host "                  passed to the CLI when it starts."
        Write-Host "  -SealSecret     Seal the Tier-1 RSA key, then exit. Interactive: prompts (hidden) for"
        Write-Host "                  the raw key XML + travel passphrase. Passphrase is NEVER an argument."
        Write-Host "                  (Also accepts the token form: dpcrewchief --sealsecret)"
        Write-Host "  -Unlock         Unlock the Tier-1 key on this box (hidden passphrase prompt), then exit."
        Write-Host "                  (Also accepts the token form: dpcrewchief --unlock)"
        Write-Host "                  Encrypted secret files live per-user in %APPDATA%\CrewChief (TestAuto-style)."
        Write-Host "  -Configuration  Build/publish configuration (Debug or Release)."
        Write-Host "  -Update         Build + publish + create $global:GeneBitsDir\CrewChief.zip, then exit."
        Write-Host "  -Package        Build the full install package (self-contained publish + Inno Setup)"
        Write-Host "                  -> $global:GeneBitsDir\CrewChief-Setup-<version>.exe, then exit. Thin wrapper over"
        Write-Host "                  CrewChief\installer\New-CrewChiefInstaller.ps1 (see BUILDING.md there)."
        Write-Host "  -Bump           With -Package: bump the patch version (1.0.0 -> 1.0.1) in"
        Write-Host "                  Directory.Build.props before packaging."
        Write-Host "  -BumpMinor      With -Package: bump the minor version (1.4.2 -> 1.5.0)."
        Write-Host "  -BumpMajor      With -Package: bump the major version (1.4.2 -> 2.0.0)."
        Write-Host "                  Same Major.Minor.Patch scheme and switches as dpspeed -Package."
        Write-Host "  -Run            Run existing Release published output only (skip build/publish)."
        Write-Host "  -CleanBuild     dotnet clean + wipe publish folder before build/publish."
        Write-Host "  -SolutionPath   Override solution path."
        Write-Host "  -ProjectName    Override target project name."
        Write-Host "  -ClearSecrets   Clears the per-user encrypted secret store (%APPDATA%\CrewChief\*):"
        Write-Host "                  sealed RSA key, Tier-2 store, DPAPI passphrases, lockout state."
        Write-Host "  -UpdateClientId Accepted for dpspeed parity; CrewChief has no Profisee ClientId."
        Write-Host "  -WhatIf         Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  -Debug is a PowerShell common parameter (debug tracing),"
        Write-Host "  not the same as -Configuration Debug."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpcrewchief"
        Write-Host "    Build + publish + run CrewChief.Web using Release."
        Write-Host "  dpcrewchief -Cli list steps"
        Write-Host "    Build + publish + run CrewChief.Cli with arguments."
        Write-Host "  dpcrewchief -Cli -Run history --last 5"
        Write-Host "    Run existing Release CLI publish output with arguments."
        Write-Host "  dpcrewchief -Update"
        Write-Host "    Build + publish + create $global:GeneBitsDir\CrewChief.zip, then exit."
        Write-Host "  dpcrewchief -Package"
        Write-Host "    Build the CrewChief-Setup-<version>.exe install package, then exit."
        Write-Host "    On success the package is copied to the team share and older"
        Write-Host "    CrewChief packages are removed from that share."
        Write-Host "    Share: $($global:GeneMachine.PackageShare)  (UNC, not Z: — mapped"
        Write-Host "    drives are per-logon-token and invisible to elevated shells.)"
        Write-Host "  dpcrewchief -Package -Bump"
        Write-Host "    Bump 1.0.0 -> 1.0.1, then build CrewChief-Setup-1.0.1.exe."
        Write-Host "  dpcrewchief -Configuration Debug"
        Write-Host "    Build + publish + run CrewChief.Web using Debug."
        Write-Host ""
        return
    }

    # Interactive Tier-1 secret admin: prompts (hidden) for the passphrase — NEVER an argument, by design.
    # Accepts either the switch form (-SealSecret / -Unlock) or the token form (--sealsecret / --unlock).
    # Runs the CLI verb directly via dotnet run, defaulting --data-folder to the Web app's data folder so
    # the blob/passphrase land where the Web UI reads them. seal-secret must run before unlock.
    $wantSeal   = $SealSecret -or ($CliArgs -contains '--sealsecret') -or ($CliArgs -contains '--seal-secret')
    $wantUnlock = $Unlock     -or ($CliArgs -contains '--unlock')
    if ($wantSeal -or $wantUnlock) {
        $verb = if ($wantSeal) { 'seal-secret' } else { 'unlock' }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run CrewChief.Cli verb '$verb' (interactive: hidden passphrase prompt)." -ForegroundColor Yellow
            return
        }
        $rest = @($CliArgs | Where-Object { $_ -notin '--sealsecret', '--seal-secret', '--unlock' })
        $cliProject = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'CrewChief\CrewChief.Cli')
        # Encrypted secret files are per-user in %APPDATA%\CrewChief (fixed), so --data-folder is irrelevant here.
        dotnet run --project $cliProject -- $verb @rest
        return
    }

    # Guard: $CliArgs is a ValueFromRemainingArguments catch-all that only carries meaning in -Cli
    # mode (it is splatted onto CrewChief.Cli). Without this check an invented switch (--Publish) or
    # a double-dashed real one (--Bump — PowerShell binds single-dash switch names only) is silently
    # swallowed and the command falls through to the default build+publish+run path: no version
    # bump, no installer, no share copy, and no error. Fail loudly instead.
    # Runs after the seal/unlock block so the documented --sealsecret/--unlock token forms still work.
    if (-not $Cli -and $CliArgs.Count -gt 0) {
        # Derived from param() metadata rather than hand-copied (a hand-maintained list silently
        # missed BumpMinor). Common parameters are excluded but WhatIf/Confirm are kept — they are
        # real dpcrewchief switches via SupportsShouldProcess. CliArgs is the catch-all itself.
        $knownSwitches = $MyInvocation.MyCommand.Parameters.Keys | Where-Object {
            $_ -ne 'CliArgs' -and $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters
        }
        $argLines = foreach ($badArg in $CliArgs) {
            $bare = $badArg.TrimStart('-')
            $hit  = $knownSwitches | Where-Object { $_ -eq $bare } | Select-Object -First 1
            if ($hit) { "  $badArg  ->  did you mean -$hit ?  (PowerShell binds single-dash switch names only)" }
            else      { "  $badArg  ->  not a dpcrewchief switch" }
        }
        $message = @("dpcrewchief: unrecognized argument(s) - nothing was built, bumped, or copied.") +
                   $argLines +
                   @("Run 'dpcrewchief -ShowHelp' for the switch list, or pass -Cli to forward these to CrewChief.Cli.")
        throw ($message -join [Environment]::NewLine)
    }

    # Guard: bump switches only mean something inside the -Package path below (same rationale as
    # dpspeed — a forgotten -Package would otherwise build+run with no bump and no error). Multi-bump
    # throws HERE so a -WhatIf preview refuses exactly like a real run would.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if ($bumpSwitchCount -gt 0 -and -not $Package) {
        throw 'dpcrewchief: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpcrewchief: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }
    # -Cli and -Package are different destinations (run the CLI vs build an installer); silently
    # preferring one over the other would discard the CLI args without a trace.
    if ($Package -and $Cli) {
        throw 'dpcrewchief: -Cli and -Package cannot be combined - pick one.'
    }

    # Full install package: everything lives in the repo script (profile-free path documented in
    # CrewChief\installer\BUILDING.md); this switch is just a convenience entry point.
    if ($Package) {
        $packageScript = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'CrewChief\installer\New-CrewChiefInstaller.ps1')
        if (-not (Test-Path -LiteralPath $packageScript)) {
            throw "Packaging script not found: $packageScript"
        }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: $packageScript -Configuration $(if ($Configuration) { $Configuration } else { 'Release' })" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (1.4.2 -> 2.0.0) in Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (1.4.2 -> 1.5.0) in Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (x.y.z -> x.y.z+1) in Directory.Build.props first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would produce: $global:GeneBitsDir\CrewChief-Setup-<version>.exe" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would copy it to $($global:GeneMachine.PackageShare) and remove older CrewChief-Setup-*.exe there." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
            return
        }
        $packStarted = Get-Date
        $packArgs = @{ OutputDir = $global:GeneBitsDir }
        if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
        if ($Bump) { $packArgs.Bump = $true }
        if ($BumpMinor) { $packArgs.BumpMinor = $true }
        if ($BumpMajor) { $packArgs.BumpMajor = $true }
        & $packageScript @packArgs
        # Deploy to the team share + prune older versions there — only reached on success
        # (the packaging script throws on any failure).
        Publish-SpeedMerchantsPackage -Product 'CrewChief' -BuiltAfter $packStarted
        return
    }

    if ($UpdateClientId) {
        Write-Host "CrewChief does not use Profisee ClientId/API key secrets; nothing to update." -ForegroundColor DarkGray
    }

    if ($ClearSecrets) {
        # secrets.local.json was eliminated from CrewChief (no config source loads it any more) —
        # the only per-user secret state is the encrypted %APPDATA%\CrewChief store below.
        # Encrypted per-user secret store (sealed RSA key, Tier-2 store, DPAPI passphrases, lockout) —
        # same %APPDATA% pattern as TestAuto's master.json (Remove-Item "$env:APPDATA\CrewChief\*").
        $appSecrets = Join-Path $env:APPDATA 'CrewChief'
        if ($PSCmdlet.ShouldProcess("$appSecrets\*", 'Delete per-user CrewChief encrypted secrets')) {
            if (Test-Path $appSecrets) {
                Remove-Item "$appSecrets\*" -Force -ErrorAction SilentlyContinue
                Write-Host "Cleared per-user secrets: $appSecrets" -ForegroundColor DarkGray
            }
            else {
                Write-Host "No per-user secrets to clear: $appSecrets" -ForegroundColor DarkGray
            }
        }
    }

    Import-GeneModuleOnce "Gene.DevOpsTools"

    # Build splat for underlying command
    $invoke = @{}

    if ($PSBoundParameters.ContainsKey('Configuration')) { $invoke.Configuration = $Configuration }
    if ($Update) { $invoke.Update = $true }
    if ($Run) { $invoke.Run = $true }
    if ($CleanBuild) { $invoke.CleanBuild = $true }
    if ($Cli) { $invoke.Cli = $true }
    if ($PSBoundParameters.ContainsKey('SolutionPath')) { $invoke.SolutionPath = $SolutionPath }
    if ($PSBoundParameters.ContainsKey('ProjectName')) { $invoke.ProjectName = $ProjectName }
    if ($WhatIfPreference) { $invoke.WhatIf = $true }
    if ($CliArgs.Count -gt 0) { $invoke.CliArgs = $CliArgs }

    Dev-CrewChiefRestart @invoke
}

function dpdatagen {
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding=$false)]
    param(
        [ValidateSet('Debug','Release')]
        [string]$Configuration,

        [switch]$Update,
        [switch]$Run,
        [switch]$CleanBuild,
        [switch]$Cli,
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [string]$SolutionPath,
        [string]$ProjectName,

        [Alias('h','help')]
        [switch]$ShowHelp,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CliArgs = @()
    )

    # Compact help (daily use)
    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpdatagen  - TestDataGeneration build/publish/run helper" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpdatagen [-Cli] [-Configuration Debug|Release] [-Update] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-Run] [-CleanBuild] [-SolutionPath <path>] [-ProjectName <name>] [-ShowHelp] [-WhatIf] [-- <cli args>]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -Cli            Target TestData.Generation.Cli instead of TestData.Generation.Web."
        Write-Host "                  Remaining args are passed to the CLI when it starts."
        Write-Host "  -Configuration  Build/publish configuration (Debug or Release). Default Release."
        Write-Host "  -Update         Build + publish + create $global:GeneBitsDir\TestDataGeneration.zip, then exit."
        Write-Host "                  Excludes a box's own state so an update never clobbers it:"
        Write-Host "                  Samples\* (shape definitions), *.local.json (credentials/overrides),"
        Write-Host "                  *.runtime.json and *.resume.json (generated run state)."
        Write-Host "  -Package        Build the full install package (self-contained publish + Inno Setup)"
        Write-Host "                  -> $global:GeneBitsDir\TestDataGeneration-Setup-<version>.exe, then exit. Thin"
        Write-Host "                  wrapper over TestData.Generation\Installer\New-TestDataGenerationInstaller.ps1."
        Write-Host "  -Bump           With -Package: bump the patch version (1.0.0 -> 1.0.1) in"
        Write-Host "                  TestData.Generation\Directory.Build.props before packaging."
        Write-Host "  -BumpMinor      With -Package: bump the minor version (1.4.2 -> 1.5.0)."
        Write-Host "  -BumpMajor      With -Package: bump the major version (1.4.2 -> 2.0.0)."
        Write-Host "                  Same Major.Minor.Patch scheme and switches as dpspeed/dpcrewchief -Package."
        Write-Host "  -Run            Run existing Release published output only (skip build/publish)."
        Write-Host "  -CleanBuild     dotnet clean + wipe publish folder before build/publish."
        Write-Host "  -SolutionPath   Override solution path."
        Write-Host "  -ProjectName    Override target project name."
        Write-Host "  -WhatIf         Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  -Debug is a PowerShell common parameter (debug tracing),"
        Write-Host "  not the same as -Configuration Debug."
        Write-Host "  This tool has no secret store and no Profisee ClientId, so there is no"
        Write-Host "  -SealSecret/-Unlock/-ClearSecrets/-UpdateClientId here (unlike dpcrewchief/dpspeed)."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpdatagen"
        Write-Host "    Build + publish + run TestData.Generation.Web using Release."
        Write-Host "  dpdatagen -Cli generate --shape PDATAGEN1M"
        Write-Host "    Build + publish + run TestData.Generation.Cli with arguments."
        Write-Host "  dpdatagen -Cli -Run verify --shape PDATAGEN1M"
        Write-Host "    Run existing Release CLI publish output with arguments."
        Write-Host "  dpdatagen -Update"
        Write-Host "    Build + publish + create $global:GeneBitsDir\TestDataGeneration.zip, then exit."
        Write-Host "  dpdatagen -Package"
        Write-Host "    Build the TestDataGeneration-Setup-<version>.exe install package, then exit."
        Write-Host "    On success the package is copied to the team share and older"
        Write-Host "    TestDataGeneration packages are removed from that share."
        Write-Host "    Share: $($global:GeneMachine.PackageShare)  (UNC, not Z: - mapped"
        Write-Host "    drives are per-logon-token and invisible to elevated shells.)"
        Write-Host "  dpdatagen -Package -Bump"
        Write-Host "    Bump 1.0.0 -> 1.0.1, then build TestDataGeneration-Setup-1.0.1.exe."
        Write-Host "  dpdatagen -Configuration Debug"
        Write-Host "    Build + publish + run TestData.Generation.Web using Debug."
        Write-Host ""
        return
    }

    # Guard: $CliArgs is a ValueFromRemainingArguments catch-all that only carries meaning in -Cli
    # mode (it is splatted onto TestData.Generation.Cli). Without this check an invented switch
    # (--Publish) or a double-dashed real one (--Bump - PowerShell binds single-dash switch names
    # only) is silently swallowed and the command falls through to the default build+publish+run
    # path: no version bump, no installer, no share copy, and no error. Fail loudly instead.
    if (-not $Cli -and $CliArgs.Count -gt 0) {
        # Derived from param() metadata rather than hand-copied (in dpcrewchief a hand-maintained
        # list silently missed BumpMinor). Common parameters are excluded but WhatIf/Confirm are
        # kept - they are real dpdatagen switches via SupportsShouldProcess. CliArgs is the
        # catch-all itself.
        $knownSwitches = $MyInvocation.MyCommand.Parameters.Keys | Where-Object {
            $_ -ne 'CliArgs' -and $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters
        }
        $argLines = foreach ($badArg in $CliArgs) {
            $bare = $badArg.TrimStart('-')
            $hit  = $knownSwitches | Where-Object { $_ -eq $bare } | Select-Object -First 1
            if ($hit) { "  $badArg  ->  did you mean -$hit ?  (PowerShell binds single-dash switch names only)" }
            else      { "  $badArg  ->  not a dpdatagen switch" }
        }
        $message = @("dpdatagen: unrecognized argument(s) - nothing was built, bumped, or copied.") +
                   $argLines +
                   @("Run 'dpdatagen -ShowHelp' for the switch list, or pass -Cli to forward these to TestData.Generation.Cli.")
        throw ($message -join [Environment]::NewLine)
    }

    # Guard: bump switches only mean something inside the -Package path below (same rationale as
    # dpspeed/dpcrewchief - a forgotten -Package would otherwise build+run with no bump and no
    # error). Multi-bump throws HERE so a -WhatIf preview refuses exactly like a real run would.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if ($bumpSwitchCount -gt 0 -and -not $Package) {
        throw 'dpdatagen: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpdatagen: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }
    # -Cli and -Package are different destinations (run the CLI vs build an installer); silently
    # preferring one over the other would discard the CLI args without a trace.
    if ($Package -and $Cli) {
        throw 'dpdatagen: -Cli and -Package cannot be combined - pick one.'
    }

    # Full install package: everything lives in the repo script (profile-free path documented in the
    # script's own comment header); this switch is just a convenience entry point. Note the folder is
    # 'Installer' (capital I) here, unlike CrewChief's lower-case 'installer'.
    if ($Package) {
        $packageScript = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'TestData.Generation\Installer\New-TestDataGenerationInstaller.ps1')
        if (-not (Test-Path -LiteralPath $packageScript)) {
            throw "Packaging script not found: $packageScript"
        }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: $packageScript -Configuration $(if ($Configuration) { $Configuration } else { 'Release' })" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (1.4.2 -> 2.0.0) in TestData.Generation\Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (1.4.2 -> 1.5.0) in TestData.Generation\Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (x.y.z -> x.y.z+1) in TestData.Generation\Directory.Build.props first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would produce: $global:GeneBitsDir\TestDataGeneration-Setup-<version>.exe" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would copy it to $($global:GeneMachine.PackageShare) and remove older TestDataGeneration-Setup-*.exe there." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
            return
        }
        $packStarted = Get-Date
        $packArgs = @{ OutputDir = $global:GeneBitsDir }
        if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
        if ($Bump) { $packArgs.Bump = $true }
        if ($BumpMinor) { $packArgs.BumpMinor = $true }
        if ($BumpMajor) { $packArgs.BumpMajor = $true }
        & $packageScript @packArgs

        # Deploy to the team share + prune older versions there - only reached on success (the
        # packaging script throws on any failure). Same shared tail step dpspeed/dpcrewchief use.
        #
        # Publish-SpeedMerchantsPackage carries [ValidateSet('CrewChief','TestAuto')] on -Product, so
        # 'TestDataGeneration' is rejected until that set is widened by one token. Checked from the
        # attribute rather than assumed, so this call site is already exact-parity and starts working
        # the moment the set includes it - and a successful package is never destroyed by a
        # parameter-binding throw in the tail step (the exe is already in C:\Bits either way).
        $publishCmd = Get-Command Publish-SpeedMerchantsPackage -ErrorAction SilentlyContinue
        $productSet = @(
            if ($publishCmd -and $publishCmd.Parameters.ContainsKey('Product')) {
                $publishCmd.Parameters['Product'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                    ForEach-Object { $_.ValidValues }
            }
        )
        if ($productSet.Count -gt 0 -and $productSet -notcontains 'TestDataGeneration') {
            Write-Warning ("Share deploy skipped: Publish-SpeedMerchantsPackage -Product accepts only [{0}]. Add 'TestDataGeneration' to that ValidateSet to enable the copy+prune. The package is in $global:GeneBitsDir." -f ($productSet -join ', '))
        }
        else {
            Publish-SpeedMerchantsPackage -Product 'TestDataGeneration' -BuiltAfter $packStarted
        }
        return
    }

    Import-GeneModuleOnce "Gene.DevOpsTools"

    # Build splat for underlying command
    $invoke = @{}

    if ($PSBoundParameters.ContainsKey('Configuration')) { $invoke.Configuration = $Configuration }
    if ($Update) { $invoke.Update = $true }
    if ($Run) { $invoke.Run = $true }
    if ($CleanBuild) { $invoke.CleanBuild = $true }
    if ($Cli) { $invoke.Cli = $true }
    if ($PSBoundParameters.ContainsKey('SolutionPath')) { $invoke.SolutionPath = $SolutionPath }
    if ($PSBoundParameters.ContainsKey('ProjectName')) { $invoke.ProjectName = $ProjectName }
    if ($WhatIfPreference) { $invoke.WhatIf = $true }
    if ($CliArgs.Count -gt 0) { $invoke.CliArgs = $CliArgs }

    Dev-DataGenRestart @invoke
}

function dpmutate {
    <#
        Sibling of dpdatagen for the Data Generation And Mutation tool (TestData.Mutation).
        Unlike dpspeed/dpcrewchief/dpdatagen there is no Dev-*Restart command for this product in
        Gene.DevOpsTools, so the build/publish/run body lives HERE rather than in the module. It is
        an adaptation of Dev-DataGenRestart with this product's own solution, projects, loopback
        port (5047) and update-zip name - values that Dev-DataGenRestart hard-codes for
        TestData.Generation and does not expose as parameters.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding=$false)]
    param(
        [ValidateSet('Debug','Release')]
        [string]$Configuration,

        [switch]$Update,
        [switch]$Run,
        [switch]$CleanBuild,
        [switch]$Cli,
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [string]$SolutionPath,
        [string]$ProjectName,

        [Alias('h','help')]
        [switch]$ShowHelp,

        [Parameter(ValueFromRemainingArguments=$true)]
        [string[]]$CliArgs = @()
    )

    # Compact help (daily use)
    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpmutate  - Data Generation And Mutation build/publish/run helper" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpmutate [-Cli] [-Configuration Debug|Release] [-Update] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-Run] [-CleanBuild] [-SolutionPath <path>] [-ProjectName <name>] [-ShowHelp] [-WhatIf] [-- <cli args>]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -Cli            Target TestData.Mutation.Cli instead of TestData.Mutation.Web."
        Write-Host "                  Remaining args are passed to the CLI when it starts - the CLI takes"
        Write-Host "                  a shape file first: <shape.json> [--test-mode] [--verify-only]"
        Write-Host "                  [--skip-verify] [--reset]."
        Write-Host "  -Configuration  Build/publish configuration (Debug or Release). Default Release."
        Write-Host "  -Update         Build + publish + create $global:GeneBitsDir\TestDataGenerationAndMutation.zip,"
        Write-Host "                  then exit. Excludes a box's own state so an update never clobbers it:"
        Write-Host "                  Samples\* (shape definitions) and *.local.json (shape files, which use"
        Write-Host "                  that suffix, plus per-box overrides/credentials). Chunk/resume state is"
        Write-Host "                  kept in SQL checkpoint tables, not on disk, so nothing else is excluded."
        Write-Host "  -Package        Build the full install package (self-contained publish + Inno Setup)"
        Write-Host "                  -> $global:GeneBitsDir\TestDataGenerationAndMutation-Setup-<version>.exe, then exit."
        Write-Host "                  Thin wrapper over TestData.Mutation\Installer\New-DataGenerationAndMutationInstaller.ps1."
        Write-Host "  -Bump           With -Package: bump the patch version (0.1.0 -> 0.1.1) in"
        Write-Host "                  TestData.Mutation\Directory.Build.props before packaging."
        Write-Host "  -BumpMinor      With -Package: bump the minor version (1.4.2 -> 1.5.0)."
        Write-Host "  -BumpMajor      With -Package: bump the major version (1.4.2 -> 2.0.0)."
        Write-Host "                  Same Major.Minor.Patch scheme and switches as dpspeed/dpcrewchief/dpdatagen -Package."
        Write-Host "  -Run            Run existing Release published output only (skip build/publish)."
        Write-Host "  -CleanBuild     dotnet clean + wipe publish folder before build/publish."
        Write-Host "  -SolutionPath   Override solution path."
        Write-Host "  -ProjectName    Override target project name."
        Write-Host "  -WhatIf         Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  -Debug is a PowerShell common parameter (debug tracing),"
        Write-Host "  not the same as -Configuration Debug."
        Write-Host "  This tool has no secret store and no Profisee ClientId, so there is no"
        Write-Host "  -SealSecret/-Unlock/-ClearSecrets/-UpdateClientId here (unlike dpcrewchief/dpspeed)."
        Write-Host "  The Web host listens on http://localhost:5047 (WebUI:HttpPort in appsettings.json"
        Write-Host "  wins) - one past the sibling data-generation tool's 5045 HTTP / 5046 reserved pair."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpmutate"
        Write-Host "    Build + publish + run TestData.Mutation.Web using Release."
        Write-Host "  dpmutate -Cli C:\path\shape.json --test-mode"
        Write-Host "    Build + publish + run TestData.Mutation.Cli as a small probe run."
        Write-Host "  dpmutate -Cli -Run C:\path\shape.json --verify-only"
        Write-Host "    Run existing Release CLI publish output with arguments."
        Write-Host "  dpmutate -Update"
        Write-Host "    Build + publish + create $global:GeneBitsDir\TestDataGenerationAndMutation.zip, then exit."
        Write-Host "  dpmutate -Package"
        Write-Host "    Build the TestDataGenerationAndMutation-Setup-<version>.exe install package, then exit."
        Write-Host "    On success the package is copied to the team share and older"
        Write-Host "    TestDataGenerationAndMutation packages are removed from that share."
        Write-Host "    Share: $($global:GeneMachine.PackageShare)  (UNC, not Z: - mapped"
        Write-Host "    drives are per-logon-token and invisible to elevated shells.)"
        Write-Host "  dpmutate -Package -Bump"
        Write-Host "    Bump 0.1.0 -> 0.1.1, then build TestDataGenerationAndMutation-Setup-0.1.1.exe."
        Write-Host "  dpmutate -Configuration Debug"
        Write-Host "    Build + publish + run TestData.Mutation.Web using Debug."
        Write-Host ""
        return
    }

    # Guard: $CliArgs is a ValueFromRemainingArguments catch-all that only carries meaning in -Cli
    # mode (it is splatted onto TestData.Mutation.Cli). Without this check an invented switch
    # (--Publish) or a double-dashed real one (--Bump - PowerShell binds single-dash switch names
    # only) is silently swallowed and the command falls through to the default build+publish+run
    # path: no version bump, no installer, no share copy, and no error. Fail loudly instead.
    if (-not $Cli -and $CliArgs.Count -gt 0) {
        # Derived from param() metadata rather than hand-copied (in dpcrewchief a hand-maintained
        # list silently missed BumpMinor). Common parameters are excluded but WhatIf/Confirm are
        # kept - they are real dpmutate switches via SupportsShouldProcess. CliArgs is the
        # catch-all itself.
        $knownSwitches = $MyInvocation.MyCommand.Parameters.Keys | Where-Object {
            $_ -ne 'CliArgs' -and $_ -notin [System.Management.Automation.PSCmdlet]::CommonParameters
        }
        $argLines = foreach ($badArg in $CliArgs) {
            $bare = $badArg.TrimStart('-')
            $hit  = $knownSwitches | Where-Object { $_ -eq $bare } | Select-Object -First 1
            if ($hit) { "  $badArg  ->  did you mean -$hit ?  (PowerShell binds single-dash switch names only)" }
            else      { "  $badArg  ->  not a dpmutate switch" }
        }
        $message = @("dpmutate: unrecognized argument(s) - nothing was built, bumped, or copied.") +
                   $argLines +
                   @("Run 'dpmutate -ShowHelp' for the switch list, or pass -Cli to forward these to TestData.Mutation.Cli.")
        throw ($message -join [Environment]::NewLine)
    }

    # Guard: bump switches only mean something inside the -Package path below (same rationale as
    # dpspeed/dpcrewchief/dpdatagen - a forgotten -Package would otherwise build+run with no bump
    # and no error). Multi-bump throws HERE so a -WhatIf preview refuses exactly like a real run.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if ($bumpSwitchCount -gt 0 -and -not $Package) {
        throw 'dpmutate: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpmutate: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }
    # -Cli and -Package are different destinations (run the CLI vs build an installer); silently
    # preferring one over the other would discard the CLI args without a trace.
    if ($Package -and $Cli) {
        throw 'dpmutate: -Cli and -Package cannot be combined - pick one.'
    }

    # Full install package: everything lives in the repo script; this switch is just a convenience
    # entry point. Folder is 'Installer' (capital I), matching TestData.Generation.
    if ($Package) {
        $packageScript = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'TestData.Mutation\Installer\New-DataGenerationAndMutationInstaller.ps1')
        if (-not (Test-Path -LiteralPath $packageScript)) {
            throw "Packaging script not found: $packageScript"
        }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: $packageScript -Configuration $(if ($Configuration) { $Configuration } else { 'Release' })" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (1.4.2 -> 2.0.0) in TestData.Mutation\Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (1.4.2 -> 1.5.0) in TestData.Mutation\Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (x.y.z -> x.y.z+1) in TestData.Mutation\Directory.Build.props first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would produce: $global:GeneBitsDir\TestDataGenerationAndMutation-Setup-<version>.exe" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would copy it to $($global:GeneMachine.PackageShare) and remove older TestDataGenerationAndMutation-Setup-*.exe there." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
            return
        }
        $packStarted = Get-Date
        $packArgs = @{ OutputDir = $global:GeneBitsDir }
        if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
        if ($Bump) { $packArgs.Bump = $true }
        if ($BumpMinor) { $packArgs.BumpMinor = $true }
        if ($BumpMajor) { $packArgs.BumpMajor = $true }
        & $packageScript @packArgs

        # Deploy to the team share + prune older versions there - only reached on success (the
        # packaging script throws on any failure). Same shared tail step dpspeed/dpcrewchief/dpdatagen use.
        #
        # Publish-SpeedMerchantsPackage carries [ValidateSet('CrewChief','TestAuto','TestDataGeneration')]
        # on -Product, so 'TestDataGenerationAndMutation' is rejected until that set is widened by one
        # token. Checked from the attribute rather than assumed, so this call site is already
        # exact-parity and starts working the moment the set includes it - and a successful package is
        # never destroyed by a parameter-binding throw in the tail step (the exe is already in C:\Bits
        # either way).
        $publishCmd = Get-Command Publish-SpeedMerchantsPackage -ErrorAction SilentlyContinue
        $productSet = @(
            if ($publishCmd -and $publishCmd.Parameters.ContainsKey('Product')) {
                $publishCmd.Parameters['Product'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                    ForEach-Object { $_.ValidValues }
            }
        )
        if ($productSet.Count -gt 0 -and $productSet -notcontains 'TestDataGenerationAndMutation') {
            Write-Warning ("Share deploy skipped: Publish-SpeedMerchantsPackage -Product accepts only [{0}]. Add 'TestDataGenerationAndMutation' to that ValidateSet to enable the copy+prune. The package is in $global:GeneBitsDir." -f ($productSet -join ', '))
        }
        else {
            Publish-SpeedMerchantsPackage -Product 'TestDataGenerationAndMutation' -BuiltAfter $packStarted
        }
        return
    }

    # ---- build / publish / run (inline; no Dev-MutateRestart exists in Gene.DevOpsTools) ----

    if ([string]::IsNullOrWhiteSpace($Configuration)) { $Configuration = 'Release' }
    if ([string]::IsNullOrWhiteSpace($SolutionPath)) {
        $SolutionPath = (Join-Path $global:GeneMachine.SpeedMerchantsRepo 'TestData.Mutation\TestData.Mutation.sln')
    }
    if (-not (Test-Path -LiteralPath $SolutionPath)) {
        throw "TestData.Mutation solution not found: $SolutionPath"
    }

    $solutionRoot = Split-Path -Parent $SolutionPath
    if ([string]::IsNullOrWhiteSpace($ProjectName)) {
        $ProjectName = if ($Cli) { 'TestData.Mutation.Cli' } else { 'TestData.Mutation.Web' }
    }

    $outDir = Join-Path $solutionRoot "$ProjectName\bin\$Configuration\publish"

    # Resolve project path.
    $projectPath = Join-Path (Join-Path $solutionRoot $ProjectName) ($ProjectName + '.csproj')
    if (-not (Test-Path -LiteralPath $projectPath)) {
        $hits = Get-ChildItem -Path $solutionRoot -Recurse -Filter ($ProjectName + '.csproj') -File -ErrorAction SilentlyContinue
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
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would create output folder: $outDir" -ForegroundColor Yellow
        } else {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }
    }

    # Neither csproj overrides <AssemblyName>, so the dll matches the project name for both targets.
    $assemblyName = $ProjectName
    $dllPath = Join-Path $outDir ($assemblyName + '.dll')
    $runDescription = if ($Cli) { "dotnet `"$dllPath`" $($CliArgs -join ' ')".TrimEnd() } else { "dotnet `"$dllPath`"" }

    # TestData.Mutation.Web pins its own default in Program.cs (DefaultHttpPort = 5047) but only when
    # nothing else supplied "urls", so the wrapper sets ASPNETCORE_URLS to the same port the app and
    # installer use. 5047 continues the sibling tool's block (5045 HTTP, 5046 reserved for HTTPS).
    # A WebUI:HttpPort in appsettings.json wins here too - Program.cs reads the same key.
    $webUrls = @()
    $webUrlEnv = $null
    if (-not $Cli) {
        $httpPort = 5047
        $appSettingsPath = Join-Path $solutionRoot 'TestData.Mutation.Web\appsettings.json'
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

    # Starts the target in the foreground with ASPNETCORE_URLS pinned for the child process only -
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
        $Configuration = 'Release'
        $outDir = Join-Path $solutionRoot "$ProjectName\bin\$Configuration\publish"
        $dllPath = Join-Path $outDir ($assemblyName + '.dll')
        $runDescription = if ($Cli) { "dotnet `"$dllPath`" $($CliArgs -join ' ')".TrimEnd() } else { "dotnet `"$dllPath`"" }

        if ($WhatIfPreference) {
            Write-Host "[WhatIf] -Run specified: would NOT build/publish/update zip." -ForegroundColor Yellow
            Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would start (foreground): $runDescription" -ForegroundColor Yellow
            if (-not $Cli) { Write-Host "[WhatIf] Would serve at:" -ForegroundColor Cyan; & $showUrls $webUrls }
            return
        }

        if (-not (Test-Path -LiteralPath $dllPath)) {
            throw "Published DLL not found (run requires existing publish output): $dllPath`nHint: run dpmutate once (or dpmutate -Configuration Release) to publish first."
        }

        $escaped = [regex]::Escape($dllPath)
        $procs = Get-CimInstance Win32_Process |
            Where-Object { $_.Name -eq 'dotnet.exe' -and $_.CommandLine -match $escaped }

        foreach ($p in $procs) {
            Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
            Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
        }

        Write-Host "Running $ProjectName [Release]..." -ForegroundColor Yellow
        & $showUrls $webUrls
        & $startTarget $outDir $dllPath $webUrlEnv $CliArgs
        return
    }

    if ($WhatIfPreference) {
        Write-Host "[WhatIf] Would publish ($Configuration): $projectPath -> $outDir" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would stop any running dotnet processes executing: $dllPath" -ForegroundColor Yellow
        if ($Update) {
            Write-Host "[WhatIf] Would create update zip ONLY (and would NOT start):" -ForegroundColor Yellow
            Write-Host "        $global:GeneBitsDir\TestDataGenerationAndMutation.zip" -ForegroundColor Yellow
            Write-Host "[WhatIf] Would exclude operator state: Samples\*, *.local.json" -ForegroundColor Yellow
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
        Where-Object { $_.Name -eq 'dotnet.exe' -and $_.CommandLine -match $escaped }

    foreach ($p in $procs) {
        Write-Host "Stopping existing $ProjectName PID $($p.ProcessId)..." -ForegroundColor Yellow
        Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue
    }

    if ($Update) {
        $publishDir = $outDir
        $zipPath    = Join-Path $global:GeneBitsDir 'TestDataGenerationAndMutation.zip'
        $stageDir   = Join-Path $env:TEMP ('PublishStage_' + [guid]::NewGuid().ToString('N'))
        $robolog    = Join-Path $env:TEMP ('robocopy_' + [guid]::NewGuid().ToString('N') + '.log')

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
            #   /XD Samples        operator-edited shape definitions (shipped under
            #                      TestData.Mutation.Cli\Samples)
            #   *.local.json       the shape files' own suffix, plus per-box overrides/credentials
            # There is no *.runtime.json / *.resume.json here (unlike the data-generation tool):
            # chunk checkpoints and resume state live in SQL tables, not on disk.
            $null = robocopy $publishDir $stageDir /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP `
                /XD Samples /XF *.local.json /MT:8 /XJ /COPY:DAT /DCOPY:D /LOG:$robolog

            $rc = $LASTEXITCODE
            if ($rc -gt 7) {
                Write-Host "Robocopy failed. Tail of log:" -ForegroundColor Red
                Get-Content -Path $robolog -Tail 200 | Write-Host
                throw "Robocopy error (exit code $rc)."
            }

            $stagedCount = (Get-ChildItem -LiteralPath $stageDir -Recurse -File -ErrorAction SilentlyContinue).Count
            if ($stagedCount -eq 0) { throw "Nothing was staged. Check exclude patterns and source folder." }

            if (Test-Path -LiteralPath $zipPath) { Remove-Item -LiteralPath $zipPath -Force }
            New-Item -ItemType Directory -Path (Split-Path -Parent $zipPath) -Force | Out-Null

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

function dpall {
    <#
    .SYNOPSIS
        Packages ALL four SpeedMerchants products in one shot (optionally bumping the version of
        each), serially by default.

    .DESCRIPTION
        One release command over the four products that dpspeed / dpcrewchief / dpdatagen / dpmutate
        package individually. It calls each repo's profile-free New-*Installer.ps1 DIRECTLY rather
        than re-entering the sibling dp* wrappers, because a background job runs in a fresh pwsh
        process with NO profile loaded - the dp* functions do not exist there. The installer scripts
        were designed to be callable that way (see each script's comment header).

        The default is SERIAL - one product at a time with live console output - because four
        concurrent self-contained win-x64 publishes saturate a laptop for a sublinear wall-clock win.
        -Parallel opts into background jobs when the box can spare the cores.

        Parallel is safe (verified 2026-08-25 on a concurrent datagen+mutate run, ISCC 7 included)
        because the four product trees are disjoint: separate installer\stage folders, separate
        <Version> files, and NO shared ProjectReference, so no two publishes ever write the same
        obj\ or bin\. The produced exes have product-distinct names in C:\Bits and the share prune
        filters per product, so they cannot delete each other's packages.

        This command PACKAGES only - it never builds-and-runs an app. Use the individual dp*
        commands for the build/publish/run loop.

    .PARAMETER Products
        Which products to package. Default: all four.

    .PARAMETER Package
        Required. Packages the selected products - the same -Package the dp* commands take. The bump
        switches only apply with it, exactly as in dpspeed.

    .PARAMETER Bump
        With -Package: bump the PATCH version of EVERY selected product before packaging (2.5.0 -> 2.5.1).

    .PARAMETER BumpMinor
        With -Package: bump the MINOR version of EVERY selected product and reset patch (2.5.3 -> 2.6.0).

    .PARAMETER BumpMajor
        With -Package: bump the MAJOR version of EVERY selected product and reset the rest (2.5.3 -> 3.0.0).

    .PARAMETER Parallel
        Package all selected products at once as background jobs instead of one at a time. Faster,
        but four concurrent publishes will peg the machine; each job's output goes to its own log.

    .PARAMETER SkipShare
        Skip the copy-to-share + prune tail; leave the packages in C:\Bits only.

    .EXAMPLE
        dpall -Package -Bump
        Patch-bumps and packages all four products one at a time, then publishes each to the share.

    .EXAMPLE
        dpall -Products speed,crewchief -Package -BumpMinor
        Minor-bumps and packages just TestAuto and CrewChief.

    .EXAMPLE
        dpall -Package -Parallel
        Repackages all four at their current versions concurrently, one log file per product.
    #>
    [CmdletBinding(SupportsShouldProcess = $true, PositionalBinding = $false)]
    param(
        [ValidateSet('speed', 'crewchief', 'datagen', 'mutate')]
        [string[]]$Products = @('speed', 'crewchief', 'datagen', 'mutate'),

        [ValidateSet('Debug', 'Release')]
        [string]$Configuration,

        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,

        [switch]$Parallel,
        [switch]$SkipShare,

        [Alias('h', 'help')]
        [switch]$ShowHelp
    )

    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpall  - package (and optionally version-bump) ALL SpeedMerchants products" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "USAGE" -ForegroundColor Yellow
        Write-Host "  dpall -Package [-Bump|-BumpMinor|-BumpMajor] [-Products speed,crewchief,datagen,mutate] [-Configuration Debug|Release] [-Parallel] [-SkipShare] [-ShowHelp] [-WhatIf]"
        Write-Host ""
        Write-Host "PRODUCTS" -ForegroundColor Yellow
        Write-Host "  speed      TestAuto                        (dpspeed -Package)"
        Write-Host "  crewchief  CrewChief                       (dpcrewchief -Package)"
        Write-Host "  datagen    TestDataGeneration              (dpdatagen -Package)"
        Write-Host "  mutate     TestDataGenerationAndMutation   (dpmutate -Package)"
        Write-Host ""
        Write-Host "OPTIONS" -ForegroundColor Yellow
        Write-Host "  -Package        Required. Package the selected products (same as dp* -Package)."
        Write-Host "  -Bump           With -Package: patch bump on EVERY selected product (2.5.0 -> 2.5.1)."
        Write-Host "  -BumpMinor      With -Package: minor bump + reset patch (2.5.3 -> 2.6.0)."
        Write-Host "  -BumpMajor      With -Package: major bump + reset the rest (2.5.3 -> 3.0.0)."
        Write-Host "                  At most one; without one the current versions are reused. The SAME"
        Write-Host "                  level applies to all selected products; per-product bumps stay in"
        Write-Host "                  the individual dp* commands."
        Write-Host "  -Parallel       All at once as background jobs (default is one at a time)."
        Write-Host "  -SkipShare      Leave packages in $global:GeneBitsDir; no copy/prune on the team share."
        Write-Host ""
        Write-Host "EXAMPLES" -ForegroundColor Yellow
        Write-Host "  dpall -Package -Bump"
        Write-Host "  dpall -Products speed,crewchief -Package -BumpMinor"
        Write-Host "  dpall -Package -Parallel"
        Write-Host ""
        Write-Host "Serial builds print to the console; -Parallel logs to $global:GeneBitsDir\dpall-<product>.log and the summary names each log." -ForegroundColor DarkGray
        Write-Host "dpall packages only - it never builds-and-runs an app. Use dpspeed/dpcrewchief/dpdatagen/dpmutate for that." -ForegroundColor DarkGray
        return
    }

    # Same guards as dpspeed: bump switches only apply with -Package, and at most one of them. They
    # throw HERE (not just in the repo scripts) so a -WhatIf preview refuses exactly like a real run.
    $bumpCount = @($Bump, $BumpMinor, $BumpMajor | Where-Object { $_ }).Count
    if ($bumpCount -gt 0 -and -not $Package) {
        throw 'dpall: -Bump/-BumpMinor/-BumpMajor only apply with -Package - nothing was built or bumped.'
    }
    if (-not $Package) {
        throw 'dpall: pass -Package (dpall packages only). Example: dpall -Package -Bump. See dpall -h.'
    }
    if ($bumpCount -gt 1) {
        throw 'dpall: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }

    $repoRoot = $global:GeneMachine.SpeedMerchantsRepo

    # Single source of truth for the per-product knobs. Product = the token
    # Publish-SpeedMerchantsPackage validates; VersionFile is read back AFTER packaging so the
    # summary shows what actually shipped rather than what we asked for.
    $catalog = [ordered]@{
        speed = @{
            Label       = 'TestAuto'
            Product     = 'TestAuto'
            Script      = Join-Path $repoRoot 'installer\New-TestAutoInstaller.ps1'
            VersionFile = Join-Path $repoRoot 'TestAuto.Web\TestAuto.Web.csproj'
        }
        crewchief = @{
            Label       = 'CrewChief'
            Product     = 'CrewChief'
            Script      = Join-Path $repoRoot 'CrewChief\installer\New-CrewChiefInstaller.ps1'
            VersionFile = Join-Path $repoRoot 'CrewChief\Directory.Build.props'
        }
        datagen = @{
            Label       = 'TestDataGeneration'
            Product     = 'TestDataGeneration'
            Script      = Join-Path $repoRoot 'TestData.Generation\Installer\New-TestDataGenerationInstaller.ps1'
            VersionFile = Join-Path $repoRoot 'TestData.Generation\Directory.Build.props'
        }
        mutate = @{
            Label       = 'TestDataGenerationAndMutation'
            Product     = 'TestDataGenerationAndMutation'
            Script      = Join-Path $repoRoot 'TestData.Mutation\Installer\New-DataGenerationAndMutationInstaller.ps1'
            VersionFile = Join-Path $repoRoot 'TestData.Mutation\Directory.Build.props'
        }
    }

    # De-duplicated and ordered by the catalog, not by the order the caller typed them, so
    # "-Products mutate,speed,speed" is one predictable run.
    $selected = @($catalog.Keys | Where-Object { $Products -contains $_ })
    if ($selected.Count -eq 0) { throw 'dpall: no products selected.' }

    # Preflight every script BEFORE launching anything - a missing script found halfway through a
    # parallel run would leave a partially bumped set of repos.
    foreach ($key in $selected) {
        $scriptPath = $catalog[$key].Script
        if (-not (Test-Path -LiteralPath $scriptPath)) {
            throw "dpall: packaging script not found for '$key': $scriptPath"
        }
    }

    # <Version> reader shared by the -WhatIf preview and the post-run summary. Returns $null rather
    # than throwing - a version we cannot parse is a cosmetic gap in the summary, never a failure.
    $readVersion = {
        param($Path)
        if (-not (Test-Path -LiteralPath $Path)) { return $null }
        $text = Get-Content -Raw -LiteralPath $Path
        if ($text -match '<Version>\s*(?<v>\d+\.\d+\.\d+)\s*</Version>') { $Matches.v } else { $null }
    }

    $bumpLabel = if ($BumpMajor) { 'MAJOR' } elseif ($BumpMinor) { 'MINOR' } elseif ($Bump) { 'PATCH' } else { $null }
    $cfgLabel  = if ($Configuration) { $Configuration } else { 'Release' }

    if ($WhatIfPreference) {
        $mode = if ($Parallel) { 'in parallel' } else { 'serially' }
        Write-Host "[WhatIf] Would package $($selected.Count) product(s) $mode (-Configuration $cfgLabel):" -ForegroundColor Yellow
        foreach ($key in $selected) {
            $entry = $catalog[$key]
            $cur   = & $readVersion $entry.VersionFile
            $curTxt = if ($cur) { $cur } else { '<unreadable>' }
            if ($bumpLabel) {
                Write-Host ("[WhatIf]   {0,-30} {1} bump from {2} in {3}" -f $entry.Label, $bumpLabel, $curTxt, $entry.VersionFile) -ForegroundColor Yellow
            }
            else {
                Write-Host ("[WhatIf]   {0,-30} repackage at {1} (no bump)" -f $entry.Label, $curTxt) -ForegroundColor Yellow
            }
            Write-Host ("[WhatIf]   {0,-30} -> $global:GeneBitsDir\{1}-Setup-<version>.exe" -f '', $entry.Product) -ForegroundColor Yellow
        }
        if ($SkipShare) {
            Write-Host "[WhatIf] Would NOT touch the team share (-SkipShare)." -ForegroundColor Yellow
        }
        else {
            Write-Host "[WhatIf] Would then copy each package to $($global:GeneMachine.PackageShare) and prune strictly-older versions of the SAME product." -ForegroundColor Yellow
            if ($global:GeneMachine.SharedBitsHost) { Write-Host "[WhatIf] Would also copy it to $($global:GeneMachine.SharedBitsShare) through $($global:GeneMachine.SharedBitsHost) and remove older versions there." -ForegroundColor Yellow }
        }
        return
    }

    if (-not $PSCmdlet.ShouldProcess(($selected -join ', '), "Package$(if ($bumpLabel) { " with $bumpLabel bump" })")) { return }

    # Arg splat handed to every installer script. Identical for all four - that uniformity is the
    # whole point of the command, and it is why -Bump is not per-product.
    $packArgs = @{ OutputDir = $global:GeneBitsDir }
    if ($PSBoundParameters.ContainsKey('Configuration')) { $packArgs.Configuration = $Configuration }
    if ($Bump)      { $packArgs.Bump      = $true }
    if ($BumpMinor) { $packArgs.BumpMinor = $true }
    if ($BumpMajor) { $packArgs.BumpMajor = $true }

    # Taken ONCE, before anything builds, and passed to every Publish-SpeedMerchantsPackage call so
    # its -BuiltAfter staleness guard covers the whole run.
    $packStarted = Get-Date
    $results = [System.Collections.Generic.List[object]]::new()

    if (-not $Parallel) {
        foreach ($key in $selected) {
            $entry = $catalog[$key]
            Write-Host ""
            Write-Host "=== $($entry.Label) ===" -ForegroundColor Cyan
            $started = Get-Date
            $ok = $true
            $err = $null
            try { & $entry.Script @packArgs }
            catch { $ok = $false; $err = $_.Exception.Message; Write-Warning "$($entry.Label) FAILED: $err" }
            $results.Add([pscustomobject]@{
                Key = $key; Label = $entry.Label; Product = $entry.Product
                VersionFile = $entry.VersionFile; Ok = $ok; Error = $err
                Duration = (Get-Date) - $started; Log = '(live console)'
            })
        }
    }
    else {
        # Each job is its own pwsh process: no profile, no shared runspace state, and one product's
        # $ErrorActionPreference or working directory cannot leak into another's build.
        $jobs = @{}
        foreach ($key in $selected) {
            $entry = $catalog[$key]
            New-Item -ItemType Directory -Path $global:GeneBitsDir -Force | Out-Null
            $log   = Join-Path $global:GeneBitsDir "dpall-$key.log"
            $jobs[$key] = @{
                Entry   = $entry
                Log     = $log
                Started = Get-Date
                Job     = Start-Job -Name "dpall-$key" -ScriptBlock {
                    param($ScriptPath, $ArgTable, $LogPath)

                    # Output is COLLECTED, not piped straight to a file, so a throw partway through
                    # still leaves the lines that led up to it in the log (a pipeline to Out-File
                    # loses its buffer when the upstream command throws).
                    $lines = [System.Collections.Generic.List[string]]::new()
                    $ok = $true
                    $err = $null
                    try {
                        & $ScriptPath @ArgTable *>&1 | ForEach-Object { $lines.Add([string]$_) }
                    }
                    catch {
                        $ok = $false
                        $err = $_.Exception.Message
                        $lines.Add(($_ | Out-String))
                    }
                    finally {
                        try { Set-Content -LiteralPath $LogPath -Value $lines -Encoding utf8 } catch { }
                    }
                    [pscustomobject]@{ Ok = $ok; Error = $err }
                } -ArgumentList $entry.Script, $packArgs, $log
            }
        }

        Write-Host ""
        Write-Host "Packaging $($selected.Count) product(s) in parallel. Logs:" -ForegroundColor Cyan
        foreach ($key in $selected) { Write-Host ("  {0,-30} {1}" -f $catalog[$key].Label, $jobs[$key].Log) -ForegroundColor DarkGray }
        Write-Host ""

        # Light completion ticker rather than a live tail - four interleaved build logs on one
        # console are unreadable, and each product's full output is already on disk.
        $pending = [System.Collections.Generic.List[string]]::new([string[]]$selected)
        while ($pending.Count -gt 0) {
            Start-Sleep -Seconds 5
            foreach ($key in @($pending)) {
                $j = $jobs[$key].Job
                if ($j.State -in 'Completed', 'Failed', 'Stopped') {
                    $entry   = $jobs[$key].Entry
                    $elapsed = (Get-Date) - $jobs[$key].Started
                    $payload = Receive-Job -Job $j -ErrorAction SilentlyContinue | Select-Object -Last 1
                    $ok  = ($j.State -eq 'Completed') -and $payload -and $payload.Ok
                    $err = if ($payload -and $payload.Error) { $payload.Error }
                           elseif (-not $ok) { "job ended $($j.State)" }
                           else { $null }
                    $results.Add([pscustomobject]@{
                        Key = $key; Label = $entry.Label; Product = $entry.Product
                        VersionFile = $entry.VersionFile; Ok = $ok; Error = $err
                        Duration = $elapsed; Log = $jobs[$key].Log
                    })
                    $color = if ($ok) { 'Green' } else { 'Red' }
                    $verb  = if ($ok) { 'done' } else { 'FAILED' }
                    Write-Host ("  {0,-30} {1} in {2:mm\:ss}" -f $entry.Label, $verb, $elapsed) -ForegroundColor $color
                    Remove-Job -Job $j -Force -ErrorAction SilentlyContinue
                    [void]$pending.Remove($key)
                }
            }
        }
    }

    # Share tail runs in this session (Publish-SpeedMerchantsPackage lives in this profile, so a
    # background job would not have it) but is handed ALL succeeded products in ONE call. That is
    # what lets it take a single share listing, skip any package the share already holds byte-for-
    # byte, and upload the rest in parallel - the upload is ~45s per 81 MB package against
    # CORPNAS01, so four serial calls used to cost ~3 min on their own.
    if (-not $SkipShare) {
        $publishCmd = Get-Command Publish-SpeedMerchantsPackage -ErrorAction SilentlyContinue
        if (-not $publishCmd) {
            Write-Warning "Publish-SpeedMerchantsPackage not found - packages left in $global:GeneBitsDir."
        }
        else {
            $productSet = @(
                $publishCmd.Parameters['Product'].Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } |
                    ForEach-Object { $_.ValidValues }
            )
            Write-Host ""
            # Unsupported products are filtered out BEFORE the batch call: -Product has a
            # ValidateSet, so one unknown name would fail the whole batch instead of just its own.
            $shareProducts = foreach ($r in @($results | Where-Object { $_.Ok })) {
                if ($productSet.Count -gt 0 -and $productSet -notcontains $r.Product) {
                    Write-Warning ("Share deploy skipped for {0}: Publish-SpeedMerchantsPackage -Product accepts only [{1}]. The package is in $global:GeneBitsDir." -f $r.Label, ($productSet -join ', '))
                    continue
                }
                $r.Product
            }
            $shareProducts = @($shareProducts)
            if ($shareProducts.Count -gt 0) {
                Publish-SpeedMerchantsPackage -Product $shareProducts -BuiltAfter $packStarted
            }
        }
    }

    # Version read back from the file AFTER the run, so the summary reports what shipped.
    Write-Host ""
    Write-Host "dpall summary ($cfgLabel$(if ($bumpLabel) { ", $bumpLabel bump" }))" -ForegroundColor Cyan
    foreach ($r in $results) {
        $ver    = & $readVersion $r.VersionFile
        $verTxt = if ($ver) { $ver } else { '?' }
        $status = if ($r.Ok) { 'OK    ' } else { 'FAILED' }
        $color  = if ($r.Ok) { 'Green' } else { 'Red' }
        Write-Host ("  {0}  {1,-30} {2,-10} {3:mm\:ss}" -f $status, $r.Label, $verTxt, $r.Duration) -ForegroundColor $color
        if (-not $r.Ok) {
            Write-Host ("          {0}" -f $r.Error) -ForegroundColor Red
            Write-Host ("          log: {0}" -f $r.Log) -ForegroundColor DarkGray
        }
    }

    # Failures throw only AFTER the summary and the share tail, so one broken product never hides
    # the other three's results or strands their packages in C:\Bits.
    $failed = @($results | Where-Object { -not $_.Ok })
    if ($failed.Count -gt 0) {
        throw ("dpall: {0} of {1} product(s) failed to package: {2}. See the log(s) above." -f $failed.Count, $results.Count, (($failed.Label) -join ', '))
    }
}

# -----------------------------
# Git/push commands (lazy-loaded)
# -----------------------------
function pps {
    [CmdletBinding()]
    param(
        [Alias('h','help')]
        [switch]$ShowHelp,
        [Parameter(ValueFromRemainingArguments=$true)]
        $PassThruArgs
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp -RemainingArgs $PassThruArgs) {
        Write-Usage "pps [<args passed through>] [-h|--help]" @(
            "Lazy-loads Gene.GitTools and runs Push-PowerShellScripts."
        )
        return
    }

    Import-GeneModuleOnce "Gene.GitTools"
    Push-PowerShellScripts @PassThruArgs
}

function psql {
    [CmdletBinding()]
    param(
        [Alias('h','help')]
        [switch]$ShowHelp,
        [Parameter(ValueFromRemainingArguments=$true)]
        $PassThruArgs
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp -RemainingArgs $PassThruArgs) {
        Write-Usage "psql [<args passed through>] [-h|--help]" @(
            "Lazy-loads Gene.GitTools and runs Push-SqlScripts."
        )
        return
    }

    Import-GeneModuleOnce "Gene.GitTools"
    Push-SqlScripts @PassThruArgs
}

# -----------------------------
# Linux droplet (DigitalOcean SFO2, Ubuntu 24.04 LTS)
# -----------------------------
function addLinux {
    [CmdletBinding(PositionalBinding=$false)]
    param(
        [string]$User = 'gene',
        [string]$HostAddress = '138.68.42.81',
        [string]$KeyFile = (Join-Path $HOME '.ssh\do_droplet_ed25519'),
        [switch]$Desktop,
        [int]$DesktopLocalPort = 13389,
        [switch]$Cockpit,
        [int]$CockpitLocalPort = 19090,
        [Alias('h','help')]
        [switch]$ShowHelp,
        [Parameter(ValueFromRemainingArguments=$true)]
        $RemoteCommand
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp -RemainingArgs $RemoteCommand) {
        Write-Usage "addLinux [-User <name>] [-HostAddress <ip>] [-KeyFile <path>] [-Desktop [-DesktopLocalPort <port>]] [-Cockpit [-CockpitLocalPort <port>]] [<remote command>] [-h|--help]" @(
            "SSH into the DigitalOcean Ubuntu droplet (default gene@138.68.42.81, SFO2, 2 GB)."
            "Root SSH login is disabled; gene has passwordless sudo, e.g. addLinux 'sudo apt update'."
            "Uses passphrase-less key $HOME\.ssh\do_droplet_ed25519."
            "Anything after the options runs as a one-off remote command, e.g. addLinux uptime"
            ""
            "-Desktop  Opens a hidden SSH tunnel localhost:$DesktopLocalPort -> droplet xrdp (3389), then"
            "          launches Remote Desktop to it. Log in as gene. RDP is never exposed to the internet."
            "-Cockpit  Opens a hidden SSH tunnel localhost:$CockpitLocalPort -> droplet Cockpit (9090), then"
            "          opens https://localhost:$CockpitLocalPort (self-signed cert warning is expected). Log in as gene."
            "Stop a tunnel with the Stop-Process command it prints."
        )
        return
    }

    Assert-PathExists $KeyFile
    $baseArgs = @('-i', $KeyFile, '-o', 'IdentitiesOnly=yes', '-o', 'StrictHostKeyChecking=accept-new')

    # Hidden 'ssh -N -L local:localhost:remote'; returns the ssh process once the local port accepts connections.
    $openTunnel = {
        param([int]$LocalPort, [int]$RemotePort, [string]$Label)
        $tunnelArgs = $baseArgs + @('-N', '-o', 'ExitOnForwardFailure=yes', '-L', "${LocalPort}:localhost:${RemotePort}", "$User@$HostAddress")
        $tunnel = Start-Process ssh -ArgumentList $tunnelArgs -WindowStyle Hidden -PassThru

        $ready = $false
        for ($i = 0; $i -lt 30 -and -not $ready -and -not $tunnel.HasExited; $i++) {
            $client = [System.Net.Sockets.TcpClient]::new()
            try { $ready = $client.ConnectAsync('127.0.0.1', $LocalPort).Wait(500) -and $client.Connected } catch { $ready = $false }
            finally { $client.Dispose() }
            if (-not $ready) { Start-Sleep -Milliseconds 500 }
        }
        if (-not $ready) {
            if (-not $tunnel.HasExited) { Stop-Process -Id $tunnel.Id -Force }
            throw "$Label tunnel did not come up on localhost:$LocalPort (port in use, or SSH failed - try plain addLinux first)."
        }
        $tunnel
    }

    if ($Desktop) {
        $tunnel = & $openTunnel $DesktopLocalPort 3389 'Desktop'
        Start-Process mstsc -ArgumentList "/v:localhost:$DesktopLocalPort"
        Write-Host "Desktop tunnel up (ssh PID $($tunnel.Id)). Log in as gene. Stop it with: Stop-Process -Id $($tunnel.Id)" -ForegroundColor Green
    }
    if ($Cockpit) {
        $tunnel = & $openTunnel $CockpitLocalPort 9090 'Cockpit'
        Start-Process "https://localhost:$CockpitLocalPort"
        Write-Host "Cockpit tunnel up (ssh PID $($tunnel.Id)). Log in as gene. Stop it with: Stop-Process -Id $($tunnel.Id)" -ForegroundColor Green
    }
    if ($Desktop -or $Cockpit) { return }

    $sshArgs = $baseArgs + @("$User@$HostAddress")
    if ($RemoteCommand) { $sshArgs += $RemoteCommand }
    ssh @sshArgs
}

function gpush {
    [CmdletBinding()]
    param(
        [Parameter(Position=0)]
        [string]$Message = "Update latest",

        [switch]$WhatIf,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "gpush [[-Message] <msg>] [-WhatIf] [-h|--help]" @(
            "Stage all, commit, and push the CURRENT repo (git add . -> commit -> push).",
            "Lazy-loads Gene.GitTools and runs Git-QuickPush:",
            "  - guards against staging sensitive files (*.env, *secret*, *.key, etc.)",
            "  - skips the commit if there is nothing staged",
            "  - auto-sets upstream (push -u origin <branch>) on first push",
            "",
            "Default message: 'Update latest'.",
            "Examples:",
            "  gpush",
            "  gpush 'fix: tidy logging'",
            "  gpush -WhatIf"
        )
        return
    }

    Import-GeneModuleOnce "Gene.GitTools"
    Git-QuickPush -Message $Message -WhatIf:$WhatIf
}


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
# Chocolatey profile import (on demand)
# -----------------------------
function chocoenv {
    [CmdletBinding()]
    param(
        [Alias('h','help')]
        [switch]$ShowHelp
    )

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "chocoenv [-h|--help]" @(
            "Loads Chocolatey's profile module on demand."
        )
        return
    }

    if (-not $env:ChocolateyInstall) {
        Write-Host "Chocolatey not installed (CHOCOLATEYINSTALL not set)." -ForegroundColor DarkGray
        return
    }

    $ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
    if (Test-Path -LiteralPath $ChocolateyProfile) {
        Import-Module $ChocolateyProfile -Force
        Write-Host "Chocolatey profile loaded." -ForegroundColor DarkGray
    }
    else {
        Write-Host "Chocolatey profile not found." -ForegroundColor DarkGray
    }
}

# -----------------------------
# cleannul: remove stubborn "nul" file created by Windows in the current directory
# -----------------------------
function cleannul {
    cmd /c del /f /q "\\?\$PWD\nul"
}

# -----------------------------
# newguid: generate a new GUID
# -----------------------------
function newguid { (New-Guid).Guid }

# -----------------------------
# Seq: clear events (TestAuto.Web / local)
# -----------------------------
$clearSeqScript = "$($global:GeneMachine.PowershellScriptsDir)\clearseq.ps1"
if (Test-Path -LiteralPath $clearSeqScript) {
    . $clearSeqScript
}

# -----------------------------
# markitdown: convert documents to Markdown
#   markitdown C:\tmp\will.pdf -o C:\tmp\will.md   (preferred)
#   markitdown C:\tmp\will.pdf > C:\tmp\will.md
#
# Venv is on local disk (C:) on purpose: the repo lives on the
# SMB-mapped D: drive, and importing onnxruntime/numpy over the
# network cost ~55s per invocation vs ~4.6s locally.
#
# Encoding: a ">" redirect crosses TWO encoders.
#   1. CPython picks the locale codepage (cp1252) when stdout is a
#      pipe instead of a console, so PYTHONIOENCODING forces UTF-8
#      at the producer.
#   2. This shell's [Console]::OutputEncoding is ibm437, so it must
#      be told to decode those bytes as UTF-8.
# Fixing only one of the two silently turns every curly quote and
# dash into U+FFFD. Both are restored in finally{}, so no other
# command in the session is affected.
# -----------------------------
$global:markitdownExe    = "$($global:GeneMachine.MarkitdownVenv)\Scripts\markitdown.exe"
$global:markitdownPython = "$($global:GeneMachine.MarkitdownVenv)\Scripts\python.exe"
$global:markitdownOcr    = $global:GeneMachine.MarkitdownOcrScript

function markitdown {
    if (-not (Test-Path -LiteralPath $global:markitdownExe)) {
        Write-Error "markitdown not found at $global:markitdownExe"
        return
    }

    # Find the source file and any -o/--output destination, so an empty
    # result can be retried through OCR without the caller doing anything.
    $source = $null
    $dest   = $null
    for ($i = 0; $i -lt $args.Count; $i++) {
        $a = $args[$i]
        if ($a -eq '-o' -or $a -eq '--output') {
            if ($i + 1 -lt $args.Count) { $dest = $args[$i + 1]; $i++ }
            continue
        }
        if ($null -eq $source -and $a -notlike '-*' -and (Test-Path -LiteralPath $a -PathType Leaf)) {
            $source = $a
        }
    }

    $prevEnc  = [Console]::OutputEncoding
    $prevPy   = $env:PYTHONIOENCODING
    $prevWarn = $env:PYTHONWARNINGS
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $env:PYTHONIOENCODING = 'utf-8'
        # pydub warns at import that ffmpeg is missing. Only audio
        # transcription needs ffmpeg, so the warning is pure console
        # noise. Scoped to that one module so real warnings from
        # markitdown's own converters still surface.
        $env:PYTHONWARNINGS = 'ignore::RuntimeWarning:pydub.utils'

        if ($dest) {
            & $global:markitdownExe @args
            $produced = if (Test-Path -LiteralPath $dest) { (Get-Item -LiteralPath $dest).Length } else { 0 }
        }
        else {
            $captured = & $global:markitdownExe @args
            $produced = ($captured | Out-String).Trim().Length
        }

        # markitdown reads an existing text layer and has no OCR. A scanned
        # or photographed PDF therefore yields an empty file and still exits
        # 0. Retry those through Tesseract automatically.
        $needsOcr = ($produced -le 2) -and
                    $source -and ($source -match '\.pdf$') -and
                    (Test-Path -LiteralPath $global:markitdownOcr)

        if ($needsOcr) {
            # Write-Host, not Write-Output: the information stream is not
            # captured by a ">" redirect, so progress never enters the file.
            Write-Host "No text layer found - running OCR, roughly 6s per page..." -ForegroundColor Yellow
            $target = if ($dest) { $dest } else { [System.IO.Path]::GetTempFileName() }
            & $global:markitdownPython $global:markitdownOcr $source $target 300 | Out-Null
            if ($dest) {
                Write-Host "OCR complete: $((Get-Item -LiteralPath $dest).Length) bytes" -ForegroundColor Green
            }
            else {
                Get-Content -LiteralPath $target -Raw -Encoding UTF8
                Remove-Item -LiteralPath $target -Force -ErrorAction SilentlyContinue
            }
        }
        elseif (-not $dest) {
            $captured
        }
    }
    finally {
        [Console]::OutputEncoding = $prevEnc
        $env:PYTHONIOENCODING = $prevPy
        $env:PYTHONWARNINGS = $prevWarn
    }
}

function dpv2 {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        [switch]$Test,
        [switch]$Arch,
        [switch]$Chaos,

        [ValidateSet('Coordinator','Agent','Cli','Web')]
        [string]$Run,

        [switch]$ComposeUp,
        [switch]$ComposeDown,

        # Dial a REAL authenticated Profisee REST GET workload up and back down, and print the
        # observed worker count and achieved request rate at each step. This is UoW-8's U0 proof.
        [switch]$Dial,

        [switch]$CleanBuild,

        [switch]$LoopStatus,
        [switch]$Criteria,

        # Build the Speedy server release: images + offline bundle + SpeedyServer-Setup-<version>.exe,
        # written straight to the NAS by New-SpeedyBundle.ps1 (the repo's deploy\ folder).
        [switch]$Package,
        [switch]$Bump,
        [switch]$BumpMinor,
        [switch]$BumpMajor,
        [switch]$AllowDirty,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    $repo = $global:GeneMachine.SpeedyRepo
    $bundleScript = Join-Path $repo 'deploy\New-SpeedyBundle.ps1'
    $sln  = Join-Path $repo 'Speedmerchants.sln'

    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpv2  - Speedmerchants vNext build/test/run helper (standalone repo, NOT speed-merchants)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpv2 [-Test] [-Arch] [-Chaos] [-Dial] [-Run Coordinator|Agent|Cli|Web] [-ComposeUp] [-ComposeDown] [-CleanBuild] [-LoopStatus] [-Criteria] [-Package [-Bump|-BumpMinor|-BumpMajor] [-AllowDirty]] [-ShowHelp] [-WhatIf]"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  (none)        Rebuild the LOCAL environment: dpContainers (all images from this tree, compose up,"
        Write-Host "                fleet-2/fleet-3, migrate exited 0, web answers on /health, standing services hold). No tests."
        Write-Host "  -Test         dotnet build -warnaserror, then the full test suite."
        Write-Host "  -Arch         Run Tests.Architecture only (dependency direction, token census, config round-trip)."
        Write-Host "  -Chaos        Run Tests.Chaos only (kill/restart durability suites; needs Docker for container chaos)."
        Write-Host "  -Dial         Dial a REAL authenticated Profisee REST GET workload up and back down."
        Write-Host "                Prints the observed worker count and achieved request rate at each step."
        Write-Host "                Needs SM_WORKLOAD_URL + SM_WORKLOAD_APIKEY at User scope. ~2700 GETs."
        Write-Host "  -Run <host>   dotnet run the Coordinator, Agent, Cli, or Web host project."
        Write-Host "  -ComposeUp    docker compose up -d --wait (RabbitMQ mgmt UI: http://localhost:15672, SQL warehouse)."
        Write-Host "  -ComposeDown  docker compose down (volumes preserved)."
        Write-Host "  -CleanBuild   dotnet clean + wipe bin/obj before building."
        Write-Host "  -LoopStatus   Show the overnight loop's last PROGRESS entries + criteria state (.loop\)."
        Write-Host "  -Criteria     Show Done-when criteria pass/fail from .loop\CRITERIA.json (read-only; never re-runs them)."
        Write-Host "  -Package      Rebuild the LOCAL environment on the new version FIRST (as plain dpv2), then build the"
        Write-Host "                Speedy server release: the images, the offline bundle and"
        Write-Host "                SpeedyServer-Setup-<version>.exe, written straight to"
        Write-Host "                $($global:GeneMachine.PackageShare)\Deployment\<version>\ (latest.txt moves last)."
        Write-Host "                Thin wrapper over $bundleScript."
        Write-Host "                Version = <Version> in Directory.Build.props; a version that already has a bundle is refused."
        Write-Host "  -Bump         With -Package: bump the patch version (1.0.0 -> 1.0.1) first. Commit Directory.Build.props after."
        Write-Host "  -BumpMinor    With -Package: bump the minor version (1.4.2 -> 1.5.0)."
        Write-Host "  -BumpMajor    With -Package: bump the major version (1.4.2 -> 2.0.0)."
        Write-Host "  -AllowDirty   With -Package: build from uncommitted changes (tag <version>-dirty.<time>; never a release)."
        Write-Host "  -WhatIf       Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  Repo: $repo  (own git; commits allowed here, unlike other repos)."
        Write-Host "  Design docs: $($global:GeneMachine.VaultDocsRoot)\speed-merchants\vNext\vNextImplementation_v2.md"
        Write-Host "               (the planning\ plan is SUPERSEDED - it lives in that folder's Archive\ now)."
        Write-Host ""
        Write-Host "Examples:" -ForegroundColor Yellow
        Write-Host "  dpv2                 Rebuild the local containers from this tree."
        Write-Host "  dpv2 -Test           Build + test everything."
        Write-Host "  dpv2 -Arch           Fast architecture-rule check."
        Write-Host "  dpv2 -ComposeUp      Bring up broker + warehouse, wait for health."
        Write-Host "  dpv2 -Dial           Dial a real REST workload up and back down (UoW-8 U0)."
        Write-Host "  dpv2 -Run Cli        Run the CLI host."
        Write-Host "  dpv2 -LoopStatus     What did the overnight loop do?"
        Write-Host "  dpv2 -Package -Bump  Bump 1.0.0 -> 1.0.1, rebuild the local containers on 1.0.1, then build the"
        Write-Host "                       bundle + SpeedyServer-Setup-1.0.1.exe on the NAS."
        Write-Host "                       Then relay it on CORPSQL03 (Copy-SpeedyBundle.ps1) and run the Setup on each VM."
        Write-Host ""
        return
    }

    if (-not (Test-Path -LiteralPath $repo)) {
        throw "dpv2: repo not found at $repo - has the vNext loop created it yet?"
    }

    # Guard: bump switches only mean something with -Package (a forgotten -Package would otherwise fall
    # through to build+test with no bump and no error). Multi-bump throws HERE so -WhatIf refuses too.
    $bumpSwitchCount = @($Bump, $BumpMinor, $BumpMajor).Where({ $_ }).Count
    if (($bumpSwitchCount -gt 0 -or $AllowDirty) -and -not $Package) {
        throw 'dpv2: -Bump/-BumpMinor/-BumpMajor/-AllowDirty only apply with -Package - nothing was built or bumped.'
    }
    if ($bumpSwitchCount -gt 1) {
        throw 'dpv2: use at most one of -Bump (patch), -BumpMinor (minor), -BumpMajor (major).'
    }

    # --- Speedy server release package (profile-free path: run the bundle script directly) ---
    if ($Package) {
        if (-not (Test-Path -LiteralPath $bundleScript)) {
            throw "dpv2: bundle script not found: '$bundleScript'. It ships in the speedmerchants repo (deploy\New-SpeedyBundle.ps1); check SpeedyRepo in $global:GeneMachineConfigPath and that the tree is current."
        }
        # -LocalStack: the bundle script rebuilds and restarts the local stack on the version it just wrote,
        # before any bundle image, so the laptop runs what the bundle ships.
        $bundleArgs = @('-LocalStack')
        if ($Bump) { $bundleArgs += '-Bump' }
        if ($BumpMinor) { $bundleArgs += '-BumpMinor' }
        if ($BumpMajor) { $bundleArgs += '-BumpMajor' }
        if ($AllowDirty) { $bundleArgs += '-AllowDirty' }
        if ($WhatIfPreference) {
            Write-Host "[WhatIf] Would run: powershell.exe -File `"$bundleScript`" $($bundleArgs -join ' ')" -ForegroundColor Yellow
            if ($BumpMajor) { Write-Host "[WhatIf] Would bump the MAJOR version (1.4.2 -> 2.0.0) in Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($BumpMinor) { Write-Host "[WhatIf] Would bump the MINOR version (1.4.2 -> 1.5.0) in Directory.Build.props first." -ForegroundColor Yellow }
            elseif ($Bump) { Write-Host "[WhatIf] Would bump the PATCH version (x.y.z -> x.y.z+1) in Directory.Build.props first." -ForegroundColor Yellow }
            Write-Host "[WhatIf] Would rebuild the local containers on that version first (compose build, up, fleet-2/3)." -ForegroundColor Yellow
            Write-Host "[WhatIf] Would produce: $($global:GeneMachine.PackageShare)\Deployment\<version>\SpeedyServer-Setup-<version>.exe" -ForegroundColor Yellow
            return
        }
        # Windows PowerShell 5.1, the runtime every bundle so far was built and proven with.
        powershell.exe -NoProfile -ExecutionPolicy Bypass -File $bundleScript @bundleArgs
        if ($LASTEXITCODE -ne 0) { throw "dpv2: packaging FAILED (exit $LASTEXITCODE). A bundle folder without BUNDLE-COMPLETE may be left on the NAS: delete it and run again." }
        if ($bumpSwitchCount -gt 0) {
            Write-Host "dpv2: commit Directory.Build.props - the next -Package refuses a dirty tree until you do." -ForegroundColor Yellow
        }
        return
    }

    # --- Read-only loop views (work even while a loop is running; never mutate .loop state) ---
    if ($LoopStatus -or $Criteria) {
        $loopDir = Join-Path $repo '.loop'
        if (-not (Test-Path -LiteralPath $loopDir)) {
            Write-Host "No .loop\ state at $repo - no loop has been initialized." -ForegroundColor Yellow
            return
        }
        $critFile = Join-Path $loopDir 'CRITERIA.json'
        if (Test-Path -LiteralPath $critFile) {
            $doc = Get-Content -Raw -LiteralPath $critFile | ConvertFrom-Json
            Write-Host ""
            Write-Host "Done-when criteria (latest recorded run):" -ForegroundColor Cyan
            foreach ($c in $doc.criteria) {
                # Schema per Test-Criteria.ps1: nested baseline{exit,passed,at,...} and latest (null until re-run)
                $state = if ($null -ne $c.latest) { $c.latest } else { $c.baseline }
                $ok = [bool]$state.passed
                $when = if ($null -ne $c.latest) { 'latest' } else { 'baseline' }
                $mark = if ($ok) { '[PASS]' } else { '[fail]' }
                $color = if ($ok) { 'Green' } else { 'DarkYellow' }
                Write-Host ("  {0} {1}  ({2})" -f $mark, $c.label, $when) -ForegroundColor $color
            }
        }
        if ($LoopStatus) {
            $prog = Join-Path $loopDir 'PROGRESS.md'
            if (Test-Path -LiteralPath $prog) {
                Write-Host ""
                Write-Host "PROGRESS (tail):" -ForegroundColor Cyan
                Get-Content -LiteralPath $prog -Tail 40
            }
            Write-Host ""
            Write-Host "Recent commits:" -ForegroundColor Cyan
            git -C $repo log --oneline -10 2>$null
        }
        return
    }

    # --- The dial proof: a real authenticated REST GET workload, dialled up and back down ---
    #
    # The credential is read from the User-scope environment and passed to the child process through
    # the environment, never as an argument: an argument lands in this process's command line, where
    # `ps`, a crash dump and the shell history can all read it. Nothing here echoes either value.
    if ($Dial) {
        $proof = Join-Path $repo 'scripts\dial\Invoke-RestDialProof.ps1'
        if (-not (Test-Path -LiteralPath $proof)) {
            throw "dpv2: $proof not found - UoW-8 iteration 1 lands it."
        }

        # A profile function runs inside a shell that may have started BEFORE these were set, and a
        # process does not re-read the registry once it is running. Read the User scope explicitly
        # rather than trusting what this process happens to have inherited - the failure mode of
        # getting that wrong is a run that succeeds against the wrong installation.
        foreach ($name in 'SM_WORKLOAD_URL', 'SM_WORKLOAD_APIKEY') {
            $value = [Environment]::GetEnvironmentVariable($name, 'User')
            if ([string]::IsNullOrWhiteSpace($value)) {
                throw "dpv2: $name is not set at User scope. It must carry the workload target; nothing is defaulted, because a guessed target turns 'nobody configured this' into 'the target answered nothing'."
            }
            # [Environment]::SetEnvironmentVariable and NOT Set-Item, for one specific reason:
            # Set-Item supports ShouldProcess, so under -WhatIf it announces the operation INCLUDING
            # the value it would set - which prints the API key to the console in the one code path
            # whose entire job is keeping that key off the command line. A .NET call has no WhatIf
            # narration and says nothing. Found by running `dpv2 -Dial -WhatIf` and reading it.
            [Environment]::SetEnvironmentVariable($name, $value, 'Process')
        }

        Write-Host "Dialling $([Environment]::GetEnvironmentVariable('SM_WORKLOAD_URL','User'))" -ForegroundColor Cyan
        Write-Host "Roughly 2700 GETs against a SHARED cloud instance. Run it deliberately." -ForegroundColor Yellow

        if ($PSCmdlet.ShouldProcess($proof, 'run the REST dial proof')) {
            pwsh -NoProfile -File $proof
            if ($LASTEXITCODE -ne 0) { throw "dpv2: the dial proof FAILED (exit $LASTEXITCODE)." }
            Write-Host "dpv2: the fleet followed the dial up and back down." -ForegroundColor Green
        }
        return
    }

    # --- Compose lifecycle ---
    if ($ComposeUp -or $ComposeDown) {
        $compose = Join-Path $repo 'compose.yaml'
        if (-not (Test-Path -LiteralPath $compose)) {
            throw "dpv2: $compose not found in $repo."
        }
        if ($ComposeUp -and $PSCmdlet.ShouldProcess($compose, 'docker compose up -d --wait')) {
            docker compose -f $compose up -d --wait
            if ($LASTEXITCODE -ne 0) { throw "dpv2: docker compose up failed (exit $LASTEXITCODE). Is Rancher Desktop running?" }
            Write-Host "Services healthy. RabbitMQ mgmt: http://localhost:15672" -ForegroundColor Green
        }
        if ($ComposeDown -and $PSCmdlet.ShouldProcess($compose, 'docker compose down')) {
            docker compose -f $compose down
        }
        return
    }

    # --- Run a host ---
    if ($Run) {
        $proj = Join-Path $repo "src\$Run\$Run.csproj"
        if (-not (Test-Path -LiteralPath $proj)) { throw "dpv2: $proj not found." }
        if ($PSCmdlet.ShouldProcess($proj, 'dotnet run')) {
            dotnet run --project $proj
        }
        return
    }

    if (-not (Test-Path -LiteralPath $sln)) {
        throw "dpv2: $sln not found - the scaffold loop (UoW-0) has not landed it yet. Try: dpv2 -LoopStatus"
    }

    # --- Clean ---
    if ($CleanBuild -and $PSCmdlet.ShouldProcess($sln, 'dotnet clean + wipe bin/obj')) {
        dotnet clean $sln | Out-Host
        Get-ChildItem -LiteralPath $repo -Recurse -Directory -Force |
            Where-Object { $_.Name -in 'bin','obj' -and $_.FullName -notmatch '\\\.git\\|\\\.loop\\' } |
            Remove-Item -Recurse -Force -Confirm:$false
    }

    # --- Targeted test suites ---
    if ($Arch) {
        if ($PSCmdlet.ShouldProcess($sln, 'run Tests.Architecture')) {
            dotnet test (Join-Path $repo 'tests\Tests.Architecture\Tests.Architecture.csproj')
            if ($LASTEXITCODE -ne 0) { throw 'dpv2: architecture tests FAILED.' }
        }
        return
    }
    if ($Chaos) {
        if ($PSCmdlet.ShouldProcess($sln, 'run Tests.Chaos')) {
            dotnet test (Join-Path $repo 'tests\Tests.Chaos\Tests.Chaos.csproj')
            if ($LASTEXITCODE -ne 0) { throw 'dpv2: chaos tests FAILED.' }
        }
        return
    }
    if ($Test) {
        if ($PSCmdlet.ShouldProcess($sln, 'dotnet build -warnaserror + dotnet test')) {
            dotnet build $sln -warnaserror
            if ($LASTEXITCODE -ne 0) { throw 'dpv2: build FAILED.' }
            dotnet test $sln --no-build
            if ($LASTEXITCODE -ne 0) { throw 'dpv2: test suite FAILED.' }
            Write-Host "dpv2: build + tests green." -ForegroundColor Green
        }
        return
    }

    # --- Default: rebuild the local environment (Gene, 2026-09-25) ---
    dpContainers -WhatIf:$WhatIfPreference
}

function dpContainers {
    [CmdletBinding(SupportsShouldProcess = $true)]
    param(
        # Restart on the existing images; skip the image build.
        [switch]$NoBuild,

        [Alias('h','help')]
        [switch]$ShowHelp
    )

    $repo    = $global:GeneMachine.SpeedyRepo
    $compose = Join-Path $repo 'compose.yaml'
    $fleets  = Join-Path $repo 'compose.fleets.yaml'

    if ($ShowHelp) {
        Write-Host ""
        Write-Host "dpContainers  - Rebuild the Speedy (speedmerchants) images and restart the stack on them" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Syntax:" -ForegroundColor Yellow
        Write-Host "  dpContainers [-NoBuild] [-ShowHelp] [-WhatIf]"
        Write-Host ""
        Write-Host "Steps:" -ForegroundColor Yellow
        Write-Host "  1. docker compose --profile tools build        (all images, migrate included)"
        Write-Host "  2. docker compose up -d                        (recreates containers on the new images)"
        Write-Host "  3. docker compose -f compose.yaml -f compose.fleets.yaml up -d fleet-2 fleet-3"
        Write-Host "  4. Checks migrate exited 0, web answers on /health (https://localhost:5310 when .env.local sets https,"
        Write-Host "     else http://127.0.0.1:5310), and coordinator + fleets stay running for 20s without restarting"
        Write-Host ""
        Write-Host "Options:" -ForegroundColor Yellow
        Write-Host "  -NoBuild      Skip step 1; restart on the images already built."
        Write-Host "  -WhatIf       Preview actions without executing."
        Write-Host ""
        Write-Host "Notes:" -ForegroundColor Yellow
        Write-Host "  Needs Rancher Desktop running and SM_SA_PASSWORD at User scope."
        Write-Host "  Never 'docker start' after a rebuild - it restarts the OLD containers on the OLD images."
        Write-Host ""
        return
    }

    if (-not (Test-Path -LiteralPath $compose)) { throw "dpContainers: $compose not found." }

    # A shell started before the variable was set does not have it; read the User scope explicitly.
    # Never echoed.
    $sa = [Environment]::GetEnvironmentVariable('SM_SA_PASSWORD', 'User')
    if ([string]::IsNullOrWhiteSpace($sa)) {
        throw "dpContainers: SM_SA_PASSWORD is not set at User scope; compose cannot start the warehouse without it."
    }
    [Environment]::SetEnvironmentVariable('SM_SA_PASSWORD', $sa, 'Process')

    docker info --format '{{.ServerVersion}}' | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "dpContainers: Docker is not answering. Is Rancher Desktop running?" }

    if (-not $NoBuild -and $PSCmdlet.ShouldProcess($compose, 'docker compose --profile tools build')) {
        docker compose -f $compose --profile tools build
        if ($LASTEXITCODE -ne 0) { throw "dpContainers: image build FAILED (exit $LASTEXITCODE)." }
    }

    if ($PSCmdlet.ShouldProcess($compose, 'docker compose up -d')) {
        docker compose -f $compose up -d
        if ($LASTEXITCODE -ne 0) { throw "dpContainers: compose up FAILED (exit $LASTEXITCODE). Check: docker compose logs migrate" }
    }

    if ($PSCmdlet.ShouldProcess($fleets, 'docker compose up -d fleet-2 fleet-3')) {
        docker compose -f $compose -f $fleets up -d fleet-2 fleet-3
        if ($LASTEXITCODE -ne 0) { throw "dpContainers: fleet-2/fleet-3 up FAILED (exit $LASTEXITCODE)." }
    }

    if ($WhatIfPreference) { return }

    docker compose -f $compose ps -a | Out-Host

    $migrate = docker inspect speedmerchants-migrate-1 --format '{{.State.Status}} {{.State.ExitCode}}' 2>$null
    if ($migrate -ne 'exited 0') {
        throw "dpContainers: migrate is '$migrate', expected 'exited 0'. Check: docker compose -f $compose logs migrate"
    }

    # A crash-looping container reads 'running' for the second after each restart, so one inspect right
    # after 'up' can pass a dead service. Snapshot each restart count, let the stack settle, then require
    # the service to be running AND its count unchanged.
    $standing = 'coordinator', 'fleet', 'fleet-2', 'fleet-3'
    $restartsBefore = @{}
    foreach ($svc in $standing) {
        $restartsBefore[$svc] = docker inspect "speedmerchants-$svc-1" --format '{{.RestartCount}}'
    }
    Start-Sleep -Seconds 20

    # Probe the anonymous /health route; every other web route sits behind sign-in and answers 401.
    # Once scripts\e2e\Write-SpeedyStackEnv.ps1 has written .env.local the same port serves https only,
    # with the CN=localhost dev certificate, so the probe follows the scheme that file sets.
    $envLocal = Join-Path $repo '.env.local'
    $servesHttps = (Test-Path -LiteralPath $envLocal) -and
        (Select-String -LiteralPath $envLocal -Pattern '^ASPNETCORE_URLS=https:' -Quiet)
    $webProbe = if ($servesHttps) { 'https://localhost:5310/health' } else { 'http://127.0.0.1:5310/health' }
    try {
        $code = (Invoke-WebRequest -Uri $webProbe -UseBasicParsing -TimeoutSec 30).StatusCode
    }
    catch {
        throw "dpContainers: web did not answer on $webProbe ($($_.Exception.Message))."
    }

    # Standing services must be running, not crash-looping.
    $restarting = @(foreach ($svc in $standing) {
        $state = docker inspect "speedmerchants-$svc-1" --format '{{.State.Status}} {{.State.ExitCode}} {{.RestartCount}}'
        $status, $exit, $restarts = -split $state
        if ($status -ne 'running' -or $restarts -ne $restartsBefore[$svc]) {
            "$svc ($status, exit $exit, restarts $($restartsBefore[$svc]) -> $restarts)"
        }
    })
    if ($restarting.Count -gt 0) {
        throw "dpContainers: not running: $($restarting -join ', '). Check: docker compose -f $compose logs --tail 50 <service>"
    }
    Write-Host "dpContainers: migrate exited 0, web answered $code on $webProbe." -ForegroundColor Green
}

#region Claude account profiles ------------------------------------------------
# Claude Code keeps credentials, settings, skills, plugins, memory, MCP servers
# and project history inside one directory. CLAUDE_CONFIG_DIR relocates that
# whole directory, so a second config dir == a second, permanently logged-in
# account. Bare `claude` is untouched and keeps using ~\.claude.

$script:ClaudeAccountDirs = @{
    work = Join-Path $HOME '.claude'
    home = Join-Path $HOME '.claude-home'
}

function Start-ClaudeAccount {
    <#
    .SYNOPSIS
        Launches Claude Code against a named account's config directory.
    .DESCRIPTION
        Sets CLAUDE_CONFIG_DIR for the duration of the call only, then restores
        whatever it was before. Each account logs in once; the credentials live
        on disk in that account's config directory and survive terminal restarts.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('work', 'home')]
        [string]$Account,

        [Parameter(ValueFromRemainingArguments)]
        [string[]]$ClaudeArgs
    )

    $dir = $script:ClaudeAccountDirs[$Account]
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        Write-Host "Created new Claude config dir for '$Account': $dir" -ForegroundColor Yellow
        Write-Host "First run will prompt for login - use the $Account account." -ForegroundColor Yellow
    }

    $previous = if (Test-Path Env:\CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { $null }
    try {
        $env:CLAUDE_CONFIG_DIR = $dir
        Write-Host "claude [$Account] -> $dir" -ForegroundColor DarkCyan
        claude @ClaudeArgs
    }
    finally {
        if ($null -eq $previous) {
            Remove-Item Env:\CLAUDE_CONFIG_DIR -ErrorAction SilentlyContinue
        }
        else {
            $env:CLAUDE_CONFIG_DIR = $previous
        }
    }
}

function claude-work { Start-ClaudeAccount -Account work -ClaudeArgs $args }
function claude-home { Start-ClaudeAccount -Account home -ClaudeArgs $args }

function Get-ClaudeAccount {
    <#
    .SYNOPSIS
        Shows each Claude account's config directory and whether it holds credentials.
    #>
    [CmdletBinding()]
    param()

    foreach ($name in $script:ClaudeAccountDirs.Keys | Sort-Object) {
        $dir = $script:ClaudeAccountDirs[$name]
        [pscustomobject]@{
            Account   = $name
            ConfigDir = $dir
            Exists    = Test-Path -LiteralPath $dir
            LoggedIn  = Test-Path -LiteralPath (Join-Path $dir '.credentials.json')
            Active    = ($env:CLAUDE_CONFIG_DIR -eq $dir)
        }
    }
}
Set-Alias -Name claude-which -Value Get-ClaudeAccount -Scope Global
#endregion ---------------------------------------------------------------------


#region Stream sessions (addStreams, addStreamTab, stopStreams, removeStreamTab, rerunStreamTab, getStreams, pushStreams, updateStreams)
# Two kinds of stream tab (owner rulings 2026-10-04 and 2026-10-17):
#   - Planner (and Adhoc): ONE long interactive session per tab, started with the role's /loop, so the owner can work
#     with it. The stream-compact mod (stream-kit\mods\stream-compact) compacts it after a turn once context fill
#     reaches STREAM_COMPACT_PCT. Each tab keeps a marker, .streams\tabs\<tab>.json (its shell's PID), while its
#     session runs: the planner wait, the duplicate check and stopStreams read it.
#   - Integrator, Kit, Coordinator, Status, Author N, Builder N: a stream-kit runner in -Live mode that starts a FRESH
#     'claude --permission-mode bypassPermissions' session only for a unit of work. Integrator, Kit and Coordinator
#     launch only when the runner's script gate finds work, and Status is a PowerShell tick with a Claude unit only for
#     its own inbox (owner 2026-10-17, "Both 1 + 2"): as long /loop sessions they would spend a Claude turn every
#     interval. Each runner is started with -Tab <tab title>, so its state file (.streams\runners\runner-*.json) says
#     which tab it runs in: tab numbers, the duplicate check and removeStreamTab read it.

$global:GeneStreamDisabledHooks = 'gateguard'
# Context fill (percent) at which a long session compacts after a turn.
$global:GeneStreamCompactPct = 35

# Tab title -> stream-kit role. addStreams opens these in this order (Planner always first).
$global:GeneStreamRoles = [ordered]@{
    'Planner'     = 'plan'
    'Integrator'  = 'integrate'
    'Kit'         = 'kit'
    'Coordinator' = 'coordinator'
    'Status'      = 'status'
}
# The starting prompt of each long session, as the role's skill documents it ({repo} is filled in).
$global:GeneStreamLoops = @{
    'Planner'     = '/loop /stream-plan inbox repo: {repo}'
    'Integrator'  = '/loop /stream-integrate repo: {repo}'
    'Kit'         = '/loop 10m /stream-kit inbox repo: {repo}'
    'Coordinator' = '/loop 20m /stream-coordinator repo: {repo}'
    'Status'      = '/loop 10m /stream-status repo: {repo}'
    'Adhoc'       = '/stream-adhoc repo: {repo}'
}
$global:GeneStreamTabRoles = [ordered]@{ 'Author' = 'author'; 'Builder' = 'build' }
# Tabs of GeneStreamRoles that addStreams / addStreamTab start as a gated runner, not a long /loop session
# (owner 2026-10-17). Planner stays a long session: the owner talks to it.
$global:GeneStreamRunnerSessionTabs = @('Integrator', 'Kit', 'Coordinator', 'Status')
# Long interactive sessions that addStreams does NOT open; only addStreamTab -Role opens them (owner 2026-10-11:
# Adhoc carries one owner request from requirement to commit, and runs only when the owner wants it).
$global:GeneStreamOnDemandRoles = [ordered]@{ 'Adhoc' = 'adhoc' }
# Optional per-machine caps (ProfileMachineConfig.md). Blank or missing = no limit: the owner decides how many to run.
$global:GeneStreamCapKeys = @{ 'author' = 'StreamMaxAuthors'; 'build' = 'StreamMaxBuilders' }
# Plain PowerShell tabs addStreams opens after the agents, in the repo, running nothing.
$global:GeneStreamPlainTabs = @('Git', 'Compile')
# How long addStreams waits for the Planner's session to start before opening the other tabs.
$global:GeneStreamPlannerWaitSeconds = 60

function Get-GeneStreamKitPath {
    param([Parameter(Mandatory)][string]$Relative)
    # CLAUDE_CONFIG_DIR, else the machine config's ClaudeHome, else the default.
    $claudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR }
    elseif ($global:GeneMachineAI -and $global:GeneMachineAI['ClaudeHome']) { $global:GeneMachineAI['ClaudeHome'] }
    else { Join-Path $HOME '.claude' }
    return Join-Path $claudeHome "skills\stream-kit\$Relative"
}
function Get-GeneStreamRunnerPath { return Get-GeneStreamKitPath 'scripts\Start-StreamRunner.ps1' }
function Get-GeneStreamCompactModPath { return Get-GeneStreamKitPath 'mods\stream-compact' }

# A tab title as a file name: each run of non-alphanumerics becomes _ (the runner's -Tab stop file uses the same rule).
function Get-GeneStreamTabToken {
    param([Parameter(Mandatory)][string]$Tab)
    return ($Tab -replace '[^A-Za-z0-9]+', '_').Trim('_')
}

# The script a long-session tab runs, as readable text (for -help and for the tab itself).
# The Claude session id is chosen HERE and passed with --session-id, so the stream cost ledger (Get-StreamCost.ps1) can
# map this transcript to its stream session: .streams\sessions\<uuid>.json names it before claude starts. The stream
# session id is <role>-<first 8 hex of that uuid> and travels in the prompt as 'session: <id>'.
function Get-GeneStreamSessionScript {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $role = $global:GeneStreamRoles[$Tab]
    if (-not $role) { $role = $global:GeneStreamOnDemandRoles[$Tab] }
    if (-not $role) { throw "No role for tab '$Tab' in GeneStreamRoles or GeneStreamOnDemandRoles" }
    $prompt = $global:GeneStreamLoops[$Tab].Replace('{repo}', $Repo) + ' session: {session}'
    return "`$env:CLAUDE_DISABLED_HOOKS = '$($global:GeneStreamDisabledHooks)'; " +
        "`$env:STREAM_COMPACT_PCT = '$($global:GeneStreamCompactPct)'; " +
        "Set-Location -LiteralPath '$Repo'; " +
        "`$sid = [guid]::NewGuid().ToString(); `$ss = '$role-' + `$sid.Substring(0, 8); " +
        "New-Item -ItemType Directory -Force -Path '$Repo\.streams\sessions' | Out-Null; " +
        "@{ streamSession = `$ss; role = '$role'; tab = '$Tab'; startedAt = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath ('$Repo\.streams\sessions\' + `$sid + '.json'); " +
        "Enter-GeneStreamSession -Repo '$Repo' -Tab '$Tab'; " +
        "try { claude --session-id `$sid --permission-mode bypassPermissions --plugin-dir '$(Get-GeneStreamCompactModPath)' -n '$Tab' ('$prompt'.Replace('{session}', `$ss)) } " +
        "finally { Exit-GeneStreamSession -Repo '$Repo' -Tab '$Tab' }"
}

# The script a runner tab (Author N, Builder N) runs. The finally block runs when the runner exits for any reason,
# Ctrl+C included, so the tab closes after a requested stop and is marked stopped otherwise.
function Get-GeneStreamRunnerScript {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Role, [Parameter(Mandatory)][string]$Tab)
    return "`$env:CLAUDE_DISABLED_HOOKS = '$($global:GeneStreamDisabledHooks)'; " +
        "Set-Location -LiteralPath '$Repo'; " +
        "try { pwsh -NoProfile -File '$(Get-GeneStreamRunnerPath)' -Repo '$Repo' -Role $Role -Live -Tab '$Tab' } " +
        "finally { Complete-GeneStreamTab -Repo '$Repo' -Tab '$Tab' }"
}

# The script a GeneStreamRoles tab runs: a gated runner for the GeneStreamRunnerSessionTabs, a long session otherwise.
function Get-GeneStreamTabScript {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    if ($Tab -in $global:GeneStreamRunnerSessionTabs) {
        return Get-GeneStreamRunnerScript -Repo $Repo -Role $global:GeneStreamRoles[$Tab] -Tab $Tab
    }
    return Get-GeneStreamSessionScript -Repo $Repo -Tab $Tab
}

# The runner role behind a tab title ('Author 2' -> author, 'Status' -> status), or $null for a long-session tab.
function Get-GeneStreamRunnerRole {
    param([Parameter(Mandatory)][string]$Tab)
    $role = $global:GeneStreamTabRoles[($Tab -split ' ')[0]]
    if ($role) { return $role }
    if ($Tab -in $global:GeneStreamRunnerSessionTabs) { return $global:GeneStreamRoles[$Tab] }
    return $null
}

# One line saying what a GeneStreamRoles tab starts, for the progress output.
function Format-GeneStreamTabStart {
    param([Parameter(Mandatory)][string]$Tab)
    $role = Get-GeneStreamRunnerRole -Tab $Tab
    if ($role) { return "runner -Role $role -Live" }
    return $global:GeneStreamLoops[$Tab].Replace(' repo: {repo}', '')
}

# Stream tabs are Windows Terminal tabs, opened in the window the command runs in (owner 2026-10-05: the owner groups
# tabs by choosing which terminal to type addStreams / addStreamTab in; outside Windows Terminal they refuse). Wave 0.14.5 could only add
# panes to the current Wave tab from a script, and WezTerm tabs had no close button, rename or force close. wt.exe opens
# a named, colored tab running 'pwsh -NoExit -EncodedCommand <script>'; the tab's pwsh loads this profile, so its
# script can call the functions below. Windows Terminal cannot list or close tabs from outside, so:
#   - a tab retitles itself from inside ([Console]::Title); CLAUDE_CODE_DISABLE_TERMINAL_TITLE stops Claude Code from
#     overwriting that title;
#   - a tab closes when its own shell exits with 0 (closeOnExit 'automatic', the default); stopStreams/removeStreamTab
#     ask a tab to close by writing its close flag (.streams\tabs\close\<tab>), which the tab's shell watches;
#   - tab numbers come from the runner state files and the stopped-tab markers (.streams\tabs\stopped\<tab>.json).
$global:GeneStreamTabColors = @{
    'Planner' = '#2563EB'; 'Integrator' = '#7C3AED'; 'Kit' = '#475569'; 'Coordinator' = '#0D9488'; 'Status' = '#16A34A'
    'Author' = '#EA580C'; 'Builder' = '#CA8A04'; 'Adhoc' = '#DB2777'; 'Git' = '#334155'; 'Compile' = '#334155'
}

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

# Opens one tab in the Windows Terminal window this command runs in (wt -w 0: the current window), titled and colored by
# its type (the title's first word). The tab's script first drops the env of the terminal it was launched from (Wave,
# WezTerm; the runner would retitle THAT terminal otherwise), stops Claude Code retitling the tab, and sets the title;
# then it runs -Script, if any. -NoExit keeps the shell afterwards.
function New-GeneWtTab {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Title, [string]$Script)
    $prefix = "Get-ChildItem Env: | Where-Object { `$_.Name -like 'WAVETERM*' -or `$_.Name -eq 'WEZTERM_PANE' } | " +
        "ForEach-Object { Remove-Item -LiteralPath `"Env:`$(`$_.Name)`" }; " +
        "`$env:CLAUDE_CODE_DISABLE_TERMINAL_TITLE = '1'; Set-GeneStreamTabTitle '$Title'; "
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prefix + $Script))
    $wtArgs = @('-w', '0', 'new-tab', '--title', $Title)
    $color = $global:GeneStreamTabColors[($Title -split ' ')[0]]
    if ($color) { $wtArgs += @('--tabColor', $color) }
    $wtArgs += @('-d', $Directory, (Join-Path $PSHOME 'pwsh.exe'), '-NoExit', '-EncodedCommand', $encoded)
    & (Get-GeneWtPath) @wtArgs
    if ($LASTEXITCODE) { throw "wt.exe new-tab '$Title' failed (exit $LASTEXITCODE)" }
}

# Retitles this shell's own terminal tab (Windows Terminal follows the console title).
function Set-GeneStreamTabTitle {
    param([Parameter(Mandatory)][string]$Title)
    try { [Console]::Title = $Title } catch { }
}

# Per-tab files under <repo>\.streams\tabs: the long-session marker (<tab>.json), the close flag (close\<tab>) and the
# stopped-runner marker (stopped\<tab>.json).
function Get-GeneStreamTabFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab, [ValidateSet('marker', 'close', 'stopped')][string]$Kind = 'marker')
    $token = Get-GeneStreamTabToken $Tab
    switch ($Kind) {
        'marker' { return Join-Path $Repo ".streams\tabs\$token.json" }
        'close' { return Join-Path $Repo ".streams\tabs\close\$token" }
        'stopped' { return Join-Path $Repo ".streams\tabs\stopped\$token.json" }
    }
}

# Asks a tab to close: writes its close flag. The tab's shell exits with 0 when it sees it (Watch-GeneStreamTabClose,
# or at once when its session or runner ends), and Windows Terminal closes the tab.
function Request-GeneStreamTabClose {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab, [string]$By = 'owner')
    $flag = Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind close
    New-Item -ItemType Directory -Path (Split-Path $flag) -Force | Out-Null
    Set-Content -LiteralPath $flag -Value "$By $(Get-Date -Format s) $env:USERNAME"
}

# Exits this shell with 0 (closing its tab) if its close flag is set; returns otherwise.
function Exit-GeneStreamTabIfClosed {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $flag = Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind close
    if (-not (Test-Path -LiteralPath $flag)) { return }
    Remove-Item -LiteralPath $flag -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind stopped) -ErrorAction SilentlyContinue
    [Environment]::Exit(0)
}

# While this tab's shell sits at its prompt, polls its close flag every 2 s (a timer event; PSReadLine runs event
# actions while it waits for input) and exits when it is set.
function Watch-GeneStreamTabClose {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $id = "GeneStreamTabClose"
    Get-EventSubscriber -SourceIdentifier $id -ErrorAction SilentlyContinue | Unregister-Event
    $timer = [Timers.Timer]::new(2000)
    $null = Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $id -MessageData @{ Repo = $Repo; Tab = $Tab } -Action {
        Exit-GeneStreamTabIfClosed -Repo $Event.MessageData.Repo -Tab $Event.MessageData.Tab
    }
    $timer.Start()
}
function Stop-GeneStreamTabCloseWatch {
    Get-EventSubscriber -SourceIdentifier 'GeneStreamTabClose' -ErrorAction SilentlyContinue | Unregister-Event
}

# Lines of help text showing what a tab runs.
function Format-GeneStreamScriptHelp {
    param([Parameter(Mandatory)][string]$Tab, [Parameter(Mandatory)][string]$Script)
    return @("  [$Tab]") + ($Script -split '; ' | ForEach-Object { "    $_" })
}

# Long-session markers: written by the tab before claude starts, removed when it exits.
function Get-GeneStreamMarkerPath {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    return Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind marker
}
function Enter-GeneStreamSession {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $path = Get-GeneStreamMarkerPath -Repo $Repo -Tab $Tab
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    Remove-Item -LiteralPath (Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind close) -ErrorAction SilentlyContinue
    [ordered]@{ tab = $Tab; pid = $PID; started = (Get-Date).ToUniversalTime().ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
}
function Exit-GeneStreamSession {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    Remove-Item -LiteralPath (Get-GeneStreamMarkerPath -Repo $Repo -Tab $Tab) -ErrorAction SilentlyContinue
    Exit-GeneStreamTabIfClosed -Repo $Repo -Tab $Tab
    Write-Host "$Tab session ended. The tab stays open as a shell." -ForegroundColor Yellow
    Set-GeneStreamTabTitle "$Tab (ended)"
    Watch-GeneStreamTabClose -Repo $Repo -Tab $Tab
}

# Long sessions running now: a marker whose tab shell is alive. Claude = the session's claude process, when it runs.
function Get-GeneStreamSessions {
    param([Parameter(Mandatory)][string]$Repo)
    $dir = Join-Path $Repo '.streams\tabs'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter '*.json' -File) {
        try { $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $shell = Get-Process -Id ([int]$m.pid) -ErrorAction SilentlyContinue
        if (-not $shell -or $shell.ProcessName -ne 'pwsh') { continue }
        $claude = Get-CimInstance Win32_Process -Filter "ParentProcessId = $([int]$m.pid) AND Name = 'claude.exe'" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        [pscustomobject]@{ Tab = $m.tab; Pid = [int]$m.pid; ClaudePid = $claude.ProcessId; File = $f.FullName; Written = $f.LastWriteTime }
    }
}

# Author/Builder tabs whose runner exited and whose shell is still open ('<tab> (stopped)'): Tab and Pid.
function Get-GeneStreamStoppedTabs {
    param([Parameter(Mandatory)][string]$Repo)
    $dir = Join-Path $Repo '.streams\tabs\stopped'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter '*.json' -File) {
        try { $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $shell = Get-Process -Id ([int]$m.pid) -ErrorAction SilentlyContinue
        if (-not $shell -or $shell.ProcessName -ne 'pwsh') { Remove-Item -LiteralPath $f.FullName -ErrorAction SilentlyContinue; continue }
        [pscustomobject]@{ Tab = $m.tab; Pid = [int]$m.pid; File = $f.FullName }
    }
}

# Runs in a runner tab after its runner exits. A runner stopped by a STOP file (or with every group closed), or a tab
# asked to close, closes its tab; any other exit (a crash, Ctrl+C, a refused launch) leaves the shell open for a look,
# retitled '<tab> (stopped)', with rerunStreamTab ready and its close flag watched.
function Complete-GeneStreamTab {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    Exit-GeneStreamTabIfClosed -Repo $Repo -Tab $Tab
    $last = Get-GeneStreamRunners -Repo $Repo -IncludeDead | Where-Object { $_.Tab -eq $Tab } |
        Sort-Object { (Get-Item -LiteralPath $_.File).LastWriteTimeUtc } | Select-Object -Last 1
    $status = if ($last) { "$($last.Status)" } else { 'no runner state' }
    if ($status -like 'stopped (STOP file)*' -or $status -like 'stopped (all groups closed)*') {
        Write-Host "$Tab runner $status; closing this tab." -ForegroundColor Green
        Start-Sleep -Seconds 3
        [Environment]::Exit(0)
    }
    Write-Host "$Tab runner exited: $status. The tab stays open; close it, or type rerunStreamTab to start it again." -ForegroundColor Yellow
    Set-GeneStreamTabTitle "$Tab (stopped)"
    $stopped = Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind stopped
    New-Item -ItemType Directory -Path (Split-Path $stopped) -Force | Out-Null
    [ordered]@{ tab = $Tab; pid = $PID; at = (Get-Date).ToUniversalTime().ToString('o'); status = $status } |
        ConvertTo-Json | Set-Content -LiteralPath $stopped -Encoding utf8
    $global:GeneStreamTabRerun = @{ Repo = $Repo; Tab = $Tab }
    Watch-GeneStreamTabClose -Repo $Repo -Tab $Tab
}

# Starts the runner again in a stopped author/builder tab, with exactly the script addStreamTab gave it (hooks env,
# repo, -Tab). Retyping or pasting that script by hand is what broke on 2026-10-04: two pasted lines joined without a
# ';' turned the CLAUDE_DISABLED_HOOKS assignment into an unknown command, so the runner ran with gateguard on.
function rerunStreamTab {
    param([Alias('h', '?')][switch]$Help)
    if ($Help) {
        @(
            'rerunStreamTab [-Help]',
            '',
            'In an author or builder tab whose runner has exited ("<tab> (stopped)"), starts that runner again with the',
            'same script addStreamTab ran: CLAUDE_DISABLED_HOOKS, the repo, -Tab. The console is reset first and the tab',
            'title goes back to "<tab>". Refused when a live runner already records this tab.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    $r = $global:GeneStreamTabRerun
    if (-not $r) { Write-Error 'rerunStreamTab: this tab has no stopped runner to start again (run it in a "<tab> (stopped)" tab). Nothing was done.'; return }
    $role = Get-GeneStreamRunnerRole -Tab $r.Tab
    if (-not $role) { Write-Error "rerunStreamTab: '$($r.Tab)' is not a runner tab. Nothing was done."; return }
    $live = @(Get-GeneStreamRunners -Repo $r.Repo -Role $role | Where-Object { $_.Tab -eq $r.Tab })
    if ($live.Count) { Write-Error "rerunStreamTab: '$($r.Tab)' already has a live runner ($($live[0].Runner), pid $($live[0].Pid)). Nothing was done."; return }
    $global:GeneStreamTabRerun = $null
    Stop-GeneStreamTabCloseWatch
    Remove-Item -LiteralPath (Get-GeneStreamTabFile -Repo $r.Repo -Tab $r.Tab -Kind stopped) -ErrorAction SilentlyContinue
    [Console]::Write("$([char]27)[0m$([char]27)[?25h$([char]27)[?1049l$([char]27)[?2004l$([char]27)[?1004l$([char]27)[?1000l$([char]27)[?1002l$([char]27)[?1003l$([char]27)[?1006l$([char]27)[<u$([char]27)[>4m")
    Clear-Host
    Set-GeneStreamTabTitle $r.Tab
    Invoke-Expression (Get-GeneStreamRunnerScript -Repo $r.Repo -Role $role -Tab $r.Tab)
}

# Runner state files under <repo>\.streams\runners, one object each. Alive = the runner's pwsh process still runs (and
# is older than the runner's start stamp, so a reused PID does not count) and the runner has not recorded a stop.
function Get-GeneStreamRunners {
    param([Parameter(Mandatory)][string]$Repo, [string[]]$Role, [switch]$IncludeDead)
    $dir = Join-Path $Repo '.streams\runners'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter 'runner-*.json' -File) {
        try { $s = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($Role -and $s.role -notin $Role) { continue }
        $alive = $false
        if ($s.pid -and "$($s.status)" -notlike 'stopped*') {
            $p = Get-Process -Id ([int]$s.pid) -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -eq 'pwsh') {
                $started = try { ([datetime]$s.started).ToUniversalTime() } catch { $null }
                $alive = (-not $started) -or ($p.StartTime.ToUniversalTime() -le $started.AddMinutes(2))
            }
        }
        if (-not $alive -and -not $IncludeDead) { continue }
        $tab = if ($s.PSObject.Properties['tab']) { $s.tab } else { $null }
        [pscustomobject]@{
            Runner = $s.runner; Role = $s.role; Tab = $tab; Pid = $s.pid; Alive = $alive
            Status = $s.status; Session = $s.session; Started = $s.started; File = $f.FullName
        }
    }
}

# The stream repo folder: -Repo, else the machine config's SpeedyRepo. Full path, or $null after writing the error.
function Resolve-GeneStreamRepoPath {
    param([string]$Repo, [Parameter(Mandatory)][string]$Caller)
    if (-not $Repo) { $Repo = $global:GeneMachine['SpeedyRepo'] }
    if (-not $Repo) {
        Write-Error "${Caller}: no repo: pass -Repo, or set SpeedyRepo in $global:GeneMachineConfigPath. Nothing was done."
        return $null
    }
    if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
        Write-Error "${Caller}: repo folder not found: $Repo. Nothing was done."
        return $null
    }
    return (Resolve-Path -LiteralPath $Repo).ProviderPath.TrimEnd('\')
}

# Validates -Repo (default SpeedyRepo) and changes to it. Returns the full repo path, or $null after writing the error.
function Enter-GeneStreamRepo {
    param([string]$Repo, [Parameter(Mandatory)][string]$Caller)
    $full = Resolve-GeneStreamRepoPath -Repo $Repo -Caller $Caller
    if (-not $full) { return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $full '.streams\tasks.json') -PathType Leaf)) {
        Write-Error "${Caller}: $full is not a stream repo (no .streams\tasks.json). Nothing was done."
        return $null
    }
    Set-Location -LiteralPath $full
    return $full
}

# Checks everything a stream tab needs before any tab opens. Returns $true, or $false after writing the error.
# -Need names what the tabs use: runner (Author/Builder) and/or compact (the long sessions' mod).
# STOP / STOP-<role> files (runner roles only): when no runner they would stop is still alive, the stop has finished and
# the file is removed; while one is still finishing its unit, a new runner would exit at once, so it refuses
# (-ClearStop removes the file anyway). -DryRun reports instead of checking Windows Terminal or removing anything.
function Test-GeneStreamPrereqs {
    param([Parameter(Mandatory)][string]$Repo, [string[]]$Roles = @(), [Parameter(Mandatory)][string[]]$Need,
        [Parameter(Mandatory)][string]$Caller, [switch]$ClearStop, [switch]$DryRun)
    if (-not $DryRun) {
        if (-not (Test-GeneWt -Caller $Caller)) { return $false }
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
            Write-Error "${Caller}: claude was not found on PATH. Nothing was opened."; return $false
        }
    }
    $paths = @{ runner = (Get-GeneStreamRunnerPath); compact = (Join-Path (Get-GeneStreamCompactModPath) 'hooks\register.ts') }
    foreach ($n in $Need) {
        if (-not (Test-Path -LiteralPath $paths[$n] -PathType Leaf)) {
            Write-Error "${Caller}: stream kit file not found: $($paths[$n]) (run /machine-config apply). Nothing was opened."; return $false
        }
    }
    if (-not $Roles.Count) { return $true }
    $dir = Join-Path $Repo '.streams\runners'
    $runnerRoles = @(@($global:GeneStreamTabRoles.Values) + @($global:GeneStreamRunnerSessionTabs | ForEach-Object { $global:GeneStreamRoles[$_] }))
    foreach ($name in @(@('STOP') + @($Roles | ForEach-Object { "STOP-$_" }) | Sort-Object -Unique)) {
        $file = Join-Path $dir $name
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $affected = if ($name -eq 'STOP') { $runnerRoles } else { @($name.Substring(5)) }
        $finishing = @(Get-GeneStreamRunners -Repo $Repo -Role $affected)
        if ($finishing.Count -and -not $ClearStop) {
            $who = ($finishing | ForEach-Object { if ($_.Tab) { $_.Tab } else { $_.Runner } }) -join ', '
            Write-Error "${Caller}: $name is stopping runners that are still finishing a unit ($who); a new runner would exit at once. Wait for them, or add -ClearStop to cancel the stop. Nothing was opened."
            return $false
        }
        $why = if ($finishing.Count) { '(-ClearStop)' } else { '(its stop has finished)' }
        if ($DryRun) { Write-Host "  would remove $file $why" -ForegroundColor DarkYellow; continue }
        Remove-Item -LiteralPath $file
        Write-Host "Removed $file $why" -ForegroundColor DarkYellow
    }
    return $true
}

# Numbers in use for '<type> N': live runners started with that tab, plus stopped tabs still open (Complete-GeneStreamTab
# records them; rerunStreamTab may start them again).
function Get-GeneStreamUsedNumbers {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Type)
    $pattern = "^$Type (\d+)$"
    $titles = @(@(Get-GeneStreamRunners -Repo $Repo) | ForEach-Object { $_.Tab }) + @(@(Get-GeneStreamStoppedTabs -Repo $Repo) | ForEach-Object { $_.Tab })
    return @($titles | ForEach-Object { if ("$_" -match $pattern) { [int]$Matches[1] } } | Sort-Object -Unique)
}

# Planner first: waits until the Planner tab's claude process runs (marker written after $Since), up to the limit.
function Wait-GeneStreamPlanner {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][datetime]$Since, [int]$Seconds = $global:GeneStreamPlannerWaitSeconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $up = @(Get-GeneStreamSessions -Repo $Repo | Where-Object { $_.Tab -eq 'Planner' -and $_.ClaudePid -and $_.Written -ge $Since })
        if ($up.Count) { return $up[0] }
        Start-Sleep -Seconds 2
    }
    return $null
}

# Maps tab titles and role names ('Planner', 'plan', 'Author', 'build', ...) to the tab title.
function Resolve-GeneStreamTab {
    param([Parameter(Mandatory)][string]$Name)
    foreach ($k in $global:GeneStreamRoles.Keys) { if ($Name -eq $k -or $Name -eq $global:GeneStreamRoles[$k]) { return $k } }
    foreach ($k in $global:GeneStreamTabRoles.Keys) { if ($Name -eq $k -or $Name -eq $global:GeneStreamTabRoles[$k]) { return $k } }
    foreach ($k in $global:GeneStreamOnDemandRoles.Keys) { if ($Name -eq $k -or $Name -eq $global:GeneStreamOnDemandRoles[$k]) { return $k } }
    return $null
}

# Live sessions or runners already behind a once-per-repo tab, as 'session pid N' / 'runner <id> pid N' strings.
function Get-GeneStreamTabHolders {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $hits = @(Get-GeneStreamSessions -Repo $Repo | Where-Object { $_.Tab -eq $Tab } | ForEach-Object { "session pid $($_.Pid)" })
    $role = Get-GeneStreamRunnerRole -Tab $Tab
    if ($role) { $hits += @(Get-GeneStreamRunners -Repo $Repo -Role $role | ForEach-Object { "runner $($_.Runner) pid $($_.Pid)" }) }
    return $hits
}

# Opens ONE once-per-repo tab (Planner, Integrator, Kit, Coordinator, Status, Adhoc) for addStreamTab -Role: a long
# session, or a gated runner for the GeneStreamRunnerSessionTabs. A live session or runner for that tab refuses the
# open unless -Force.
function Open-GeneStreamSessionTab {
    param([string]$Repo, [Parameter(Mandatory)][string]$Tab, [int]$Count = 1, [switch]$ClearStop, [switch]$Force, [switch]$AnyHost, [switch]$DryRun)
    if ($Count -ne 1) { Write-Error "addStreamTab: $Tab runs once per repo; -Count does not apply to it. Nothing was opened."; return }
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'addStreamTab'
    if (-not $full) { return }
    if (-not (Test-GeneStreamHost -Repo $full -Caller 'addStreamTab' -AnyHost:$AnyHost)) { return }
    $role = Get-GeneStreamRunnerRole -Tab $Tab
    $ok = if ($role) { Test-GeneStreamPrereqs -Repo $full -Roles @($role) -Need @('runner') -Caller 'addStreamTab' -ClearStop:$ClearStop -DryRun:$DryRun }
    else { Test-GeneStreamPrereqs -Repo $full -Need @('compact') -Caller 'addStreamTab' -DryRun:$DryRun }
    if (-not $ok) { return }
    $live = @(Get-GeneStreamTabHolders -Repo $full -Tab $Tab)
    if ($live.Count -and -not $Force) {
        Write-Error "addStreamTab: $Tab already runs ($($live -join ', ')). Close it first, or add -Force. Nothing was opened."
        return
    }
    if ($role -and -not $DryRun) { Remove-Item -LiteralPath (Join-Path $full ".streams\runners\STOP-tab-$(Get-GeneStreamTabToken $Tab)") -ErrorAction SilentlyContinue }
    $script = Get-GeneStreamTabScript -Repo $full -Tab $Tab
    if ($DryRun) {
        Write-Host "DryRun: would open this tab in this Windows Terminal window, in ${full}:" -ForegroundColor Cyan
        Format-GeneStreamScriptHelp -Tab $Tab -Script $script | ForEach-Object { Write-Host $_ }
        return
    }
    New-GeneWtTab -Directory $full -Title $Tab -Script $script
    Write-Host "  $Tab -> $(Format-GeneStreamTabStart -Tab $Tab)" -ForegroundColor DarkCyan
    Write-Host "Opened the $Tab tab in $full." -ForegroundColor Green
}

function addStreams {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [switch]$Force,
        [switch]$AnyHost,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )

    $shownRepo = if ($Repo) { $Repo } elseif ($global:GeneMachine['SpeedyRepo']) { $global:GeneMachine['SpeedyRepo'] } else { '<repo>' }
    if ($Help) {
        $lines = @(
            'addStreams [-Repo <repo>] [-Force] [-AnyHost] [-DryRun] [-Help]',
            '',
            'Adds one named, colored tab per stream agent to the Windows Terminal window you run it in (run it from a WT tab),',
            'in this order:',
            '  Planner (always first), Integrator, Kit, Coordinator, Status,',
            'then two plain PowerShell tabs in the repo for your own commands: Git and Compile.',
            "Planner first: it waits until the Planner's claude is running (at most $($global:GeneStreamPlannerWaitSeconds) s) before opening the rest.",
            'Authors, builders and Adhoc are not opened here; use addStreamTab -Role Author|Builder|Adhoc.',
            '',
            "Planner is ONE long interactive session you can work with. It starts the role's /loop, and the stream-compact",
            "mod compacts it after a turn once context fill reaches $($global:GeneStreamCompactPct)% (STREAM_COMPACT_PCT).",
            "$($global:GeneStreamRunnerSessionTabs -join ', ') are stream runners (-Live): a fresh Claude session only when",
            'the runner finds work (Status: a PowerShell tick, a Claude unit only for its own inbox). Idle costs no tokens.',
            "Before opening anything it checks -Repo (folder with .streams\tasks.json) and changes to it.",
            'Each tab runs:'
        )
        foreach ($title in $global:GeneStreamRoles.Keys) {
            $lines += Format-GeneStreamScriptHelp -Tab $title -Script (Get-GeneStreamTabScript -Repo $shownRepo -Tab $title)
        }
        $lines += @(
            '',
            'Enter-/Exit-GeneStreamSession keep .streams\tabs\<tab>.json while the session runs (planner wait, stopStreams).',
            'When claude exits the tab stays open as a shell. A runner tab closes after a STOP; any other exit leaves it',
            'open as "<tab> (stopped)", where rerunStreamTab starts it again.',
            "  [Git], [Compile]  plain PowerShell, started in $shownRepo; nothing else runs.",
            'Each tab is pwsh -NoExit -EncodedCommand <script>; the script also sets CLAUDE_CODE_DISABLE_TERMINAL_TITLE so the tab keeps its name.',
            '',
            'Options:',
            '  -Repo       The stream repo. Default: SpeedyRepo in the machine config.',
            '  -Force      Open the tabs even when these sessions already run or tabs with these titles are open.',
            '  -AnyHost    Open even when the board says another machine hosts it (.streams\host.json / MOVED.json).',
            '  -DryRun     Check the repo and print the tabs and commands; open nothing.',
            '  -Help, -h   Show this help and exit.',
            '',
            'See also: addStreamTab, stopStreams, removeStreamTab, rerunStreamTab, getStreams, pushStreams, updateStreams.'
        )
        $lines | ForEach-Object { Write-Host $_ }
        return
    }

    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'addStreams'
    if (-not $full) { return }
    if (-not (Test-GeneStreamHost -Repo $full -Caller 'addStreams' -AnyHost:$AnyHost)) { return }
    $runnerRoles =@($global:GeneStreamRunnerSessionTabs | ForEach-Object { $global:GeneStreamRoles[$_] })
    if (-not (Test-GeneStreamPrereqs -Repo $full -Roles $runnerRoles -Need @('compact', 'runner') -Caller 'addStreams' -DryRun:$DryRun)) { return }

    # Each of these roles runs once per repo (the integrator lock and the planner guard enforce it), so a live session
    # or runner for one is almost always an old one to close first.
    if (-not $Force) {
        $dupes = @($global:GeneStreamRoles.Keys | ForEach-Object {
                $title = $_
                $hits = @(Get-GeneStreamTabHolders -Repo $full -Tab $title)
                if ($hits.Count) { "$title ($($hits -join ', '))" } })
        if ($dupes.Count) {
            Write-Error "addStreams: already running or open: $($dupes -join '; '). Close them first, or add -Force. Nothing was opened."
            return
        }
    }

    if ($DryRun) {
        Write-Host "DryRun: would open these tabs in this Windows Terminal window, in ${full}:" -ForegroundColor Cyan
        foreach ($title in $global:GeneStreamRoles.Keys) {
            Format-GeneStreamScriptHelp -Tab $title -Script (Get-GeneStreamTabScript -Repo $full -Tab $title) | ForEach-Object { Write-Host $_ }
            if ($title -eq 'Planner') { Write-Host "    (then wait up to $($global:GeneStreamPlannerWaitSeconds) s for the Planner's claude)" -ForegroundColor DarkGray }
        }
        foreach ($title in $global:GeneStreamPlainTabs) { Write-Host "  [$title] plain PowerShell" }
        return
    }

    $created = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($title in $global:GeneStreamRoles.Keys) {
            $since = Get-Date
            # A leftover per-tab stop file would stop a runner tab at once.
            if (Get-GeneStreamRunnerRole -Tab $title) { Remove-Item -LiteralPath (Join-Path $full ".streams\runners\STOP-tab-$(Get-GeneStreamTabToken $title)") -ErrorAction SilentlyContinue }
            New-GeneWtTab -Directory $full -Title $title -Script (Get-GeneStreamTabScript -Repo $full -Tab $title)
            $created.Add($title)
            Write-Host "  $title -> $(Format-GeneStreamTabStart -Tab $title)" -ForegroundColor DarkCyan
            if ($title -eq 'Planner') {
                $up = Wait-GeneStreamPlanner -Repo $full -Since $since
                if ($up) { Write-Host "  Planner claude is running (pid $($up.ClaudePid)); opening the rest." -ForegroundColor DarkCyan }
                else { Write-Warning "addStreams: the Planner's claude did not start within $($global:GeneStreamPlannerWaitSeconds) s; opening the rest anyway. Check the Planner block." }
            }
        }
        # Plain shells for the owner's own git and build commands.
        foreach ($title in $global:GeneStreamPlainTabs) {
            New-GeneWtTab -Directory $full -Title $title
            $created.Add($title)
            Write-Host "  $title -> plain PowerShell" -ForegroundColor DarkCyan
        }
        Write-Host "Streams ready: $($created.Count) tabs in this window, $full. Add authors and builders with addStreamTab." -ForegroundColor Green
    }
    catch {
        foreach ($t in $created) { Request-GeneStreamTabClose -Repo $full -Tab $t -By 'addStreams (failed)' }
        Write-Error "addStreams: $($_.Exception.Message). Asked the $($created.Count) tab(s) already opened to close."
    }
}

function addStreamTab {
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param(
        [Parameter(ParameterSetName = 'Author')][switch]$Author,
        [Parameter(ParameterSetName = 'Builder')][switch]$Builder,
        [Parameter(ParameterSetName = 'Role')]
        [ValidateSet('Planner', 'Integrator', 'Kit', 'Coordinator', 'Status', 'Author', 'Builder', 'Adhoc', 'plan', 'integrate', 'build')]
        [string]$Role,
        [ValidateRange(1, 32)][int]$Count = 1,
        [string]$Repo,
        [switch]$ClearStop,
        [switch]$Force,
        [switch]$AnyHost,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )

    $shownRepo = if ($Repo) { $Repo } elseif ($global:GeneMachine['SpeedyRepo']) { $global:GeneMachine['SpeedyRepo'] } else { '<repo>' }
    if ($Help) {
        $lines = @(
            'addStreamTab -Role <role> [-Repo <repo>] [-Count <n>] [-ClearStop] [-Force] [-AnyHost] [-DryRun] [-Help]',
            'addStreamTab (-Author | -Builder) [-Repo <repo>] [-Count <n>] [-ClearStop] [-Force] [-AnyHost] [-DryRun] [-Help]',
            '',
            'Opens one tab for ANY stream role in the Windows Terminal window you run it in:',
            '  -Role Planner | Adhoc                                              one long interactive session, once per repo',
            '  -Role Integrator | Kit | Coordinator | Status                      one gated runner tab, once per repo',
            '                                                                    (refused while that tab''s session or runner runs; -Force opens anyway)',
            '  -Role Author | Builder (same as -Author | -Builder)                runner tabs, -Count of them',
            'Adhoc is never opened by addStreams: it carries one request you type in its tab from requirement to commit.'
        )
        foreach ($title in @($global:GeneStreamRoles.Keys) + @($global:GeneStreamOnDemandRoles.Keys)) {
            $lines += Format-GeneStreamScriptHelp -Tab $title -Script (Get-GeneStreamTabScript -Repo $shownRepo -Tab $title)
        }
        $lines += @(
            '',
            'Author and Builder: opens -Count new tabs (default 1), one stream runner each.',
            'Tabs are named Author 1, Author 2, ... or Builder 1, Builder 2, ...; each takes the lowest number not used by a',
            'live runner of that tab (from .streams\runners) or by a stopped tab still open (.streams\tabs\stopped).',
            'A permission prompt in a runner''s session retitles its tab "<tab> - NEEDS YOU" and rings the bell.',
            '',
            "Before opening anything it checks -Repo (folder with .streams\tasks.json) and changes to it.",
            'Each tab runs:'
        )
        $lines += Format-GeneStreamScriptHelp -Tab 'Author N' -Script (Get-GeneStreamRunnerScript -Repo $shownRepo -Role 'author' -Tab 'Author N')
        $lines += Format-GeneStreamScriptHelp -Tab 'Builder N' -Script (Get-GeneStreamRunnerScript -Repo $shownRepo -Role 'build' -Tab 'Builder N')
        $lines += @(
            '',
            'The runner starts a FRESH Claude session for each ticket or build, so each starts with a clean context:',
            '  claude --remote-control <session> --permission-mode bypassPermissions -n <session> --plugin-dir <stream-unit mod>',
            '         --append-system-prompt-file <unit rules> "/stream-author once repo: <repo>"  (or /stream-build)',
            'shown in the tab and in claude.ai/code under <session>; it inherits CLAUDE_DISABLED_HOOKS from the tab.',
            'With nothing to take it sleeps 30 minutes.',
            'When the runner is stopped (removeStreamTab, stopStreams) the tab closes; any other exit leaves it as "<tab> (stopped)"; type rerunStreamTab there to start it again.',
            '',
            "Optional caps on this machine ($global:GeneMachineConfigPath; you choose the numbers):"
        )
        foreach ($role in $global:GeneStreamTabRoles.Values) {
            $key = $global:GeneStreamCapKeys[$role]; $v = $global:GeneMachine[$key]
            $lines += "  $key = $(if ($v) { $v } else { '(blank: no limit)' })"
        }
        $lines += @(
            '',
            'Options:',
            '  -Role               The role to open: Planner, Integrator, Kit, Coordinator, Status, Author, Builder or Adhoc',
            '                      (role names plan, integrate, build work too).',
            '  -Author | -Builder  The same as -Role Author / -Role Builder. One of -Role, -Author, -Builder is required.',
            '  -Count              Number of Author or Builder tabs to open (default 1). Long-session roles open one.',
            '  -Repo               The stream repo. Default: SpeedyRepo in the machine config.',
            '  -ClearStop          Remove STOP / STOP-<role> files even while runners are still finishing a stop.',
            '                      A stop file whose runners have all exited is removed without it.',
            '  -Force              Open past the machine cap, or a long-session role whose session already runs.',
            '  -AnyHost            Open even when the board says another machine hosts it (.streams\host.json / MOVED.json).',
            '  -DryRun             Check the repo and print the tabs and commands; open nothing.',
            '  -Help, -h           Show this help and exit.',
            '',
            'Examples:',
            '  addStreamTab -Author',
            '  addStreamTab -Builder -Count 2',
            '  addStreamTab -Role Adhoc',
            '  addStreamTab -Role Coordinator -Repo d:\devops\repos\speedmerchants'
        )
        $lines | ForEach-Object { Write-Host $_ }
        return
    }

    if ($Role) {
        $resolved = Resolve-GeneStreamTab -Name $Role
        if ($resolved -eq 'Author') { $Author = [switch]::Present }
        elseif ($resolved -eq 'Builder') { $Builder = [switch]::Present }
        else { Open-GeneStreamSessionTab -Repo $Repo -Tab $resolved -Count $Count -ClearStop:$ClearStop -Force:$Force -AnyHost:$AnyHost -DryRun:$DryRun; return }
    }
    if (-not ($Author -or $Builder)) {
        Write-Error 'addStreamTab: a role is required: -Role <role>, -Author or -Builder (see addStreamTab -Help). Nothing was opened.'
        return
    }
    if (-not $DryRun -and -not (Test-GeneWt -Caller 'addStreamTab')) { return }
    $type = if ($Author) { 'Author' } else { 'Builder' }
    $role = $global:GeneStreamTabRoles[$type]

    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'addStreamTab'
    if (-not $full) { return }
    if (-not (Test-GeneStreamHost -Repo $full -Caller 'addStreamTab' -AnyHost:$AnyHost)) { return }
    if (-not (Test-GeneStreamPrereqs -Repo $full -Roles @($role) -Need @('runner') -Caller 'addStreamTab' -ClearStop:$ClearStop -DryRun:$DryRun)) { return }

    # Optional cap: live runners of this role plus the new ones.
    $capKey = $global:GeneStreamCapKeys[$role]
    $cap = "$($global:GeneMachine[$capKey])".Trim()
    $live = @(Get-GeneStreamRunners -Repo $full -Role $role)
    if ($cap) {
        if ($cap -notmatch '^\d+$') { Write-Error "addStreamTab: $capKey = '$cap' in $global:GeneMachineConfigPath is not a whole number. Nothing was opened."; return }
        if ($live.Count + $Count -gt [int]$cap -and -not $Force) {
            Write-Error "addStreamTab: $($live.Count) $role runner(s) live + $Count new is over $capKey = $cap. Add -Force, or raise the cap. Nothing was opened."
            return
        }
    }

    $used = Get-GeneStreamUsedNumbers -Repo $full -Type $type
    $numbers = [System.Collections.Generic.List[int]]::new()
    for ($n = 1; $numbers.Count -lt $Count; $n++) { if ($used -notcontains $n) { $numbers.Add($n) } }

    if ($DryRun) {
        Write-Host "DryRun: $($live.Count) $role runner(s) live; would open: $(($numbers | ForEach-Object { "$type $_" }) -join ', ')" -ForegroundColor Cyan
        foreach ($n in $numbers) { Format-GeneStreamScriptHelp -Tab "$type $n" -Script (Get-GeneStreamRunnerScript -Repo $full -Role $role -Tab "$type $n") | ForEach-Object { Write-Host $_ } }
        return
    }

    $runners = Join-Path $full '.streams\runners'
    $created = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($n in $numbers) {
            $tab = "$type $n"
            # A leftover stop file for this tab would stop the new runner at once.
            Remove-Item -LiteralPath (Join-Path $runners "STOP-tab-$(Get-GeneStreamTabToken $tab)") -ErrorAction SilentlyContinue
            New-GeneWtTab -Directory $full -Title $tab -Script (Get-GeneStreamRunnerScript -Repo $full -Role $role -Tab $tab)
            $created.Add($tab)
            Write-Host "  $tab -> runner -Role $role -Live" -ForegroundColor DarkCyan
        }
        Write-Host "Opened $($created.Count) $type tab(s) in $full." -ForegroundColor Green
    }
    catch {
        foreach ($t in $created) { Set-Content -LiteralPath (Join-Path $runners "STOP-tab-$(Get-GeneStreamTabToken $t)") -Value 'addStreamTab (failed)' }
        Write-Error "addStreamTab: $($_.Exception.Message). Stopped the $($created.Count) tab(s) already opened (STOP-tab files)."
    }
}

function stopStreams {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [string[]]$Role,
        [switch]$CloseSessions,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'stopStreams [-Repo <repo>] [-Role <name>[,<name>...]] [-CloseSessions] [-DryRun] [-Help]',
            '',
            'Runners (Integrator, Kit, Coordinator, Status, authors, builders): stop cleanly. Each finishes the unit it is',
            'running (never killed mid-unit), then exits, and its tab closes. Writes .streams\runners\STOP (no -Role) or',
            'STOP-<role>. Returns at once; the next addStreams / addStreamTab removes the stop file once those runners have exited.',
            '',
            'Planner, Adhoc (long sessions): a STOP file cannot reach them. Without',
            '-CloseSessions it lists the live ones so you can end each at a quiet moment (Esc, then /exit). With -CloseSessions',
            'it closes their tabs now, ending any turn in progress.',
            '',
            'Options:',
            '  -Repo           The stream repo. Default: SpeedyRepo in the machine config.',
            '  -Role           Tab names or roles: Planner|plan, Integrator|integrate, Kit|kit, Coordinator|coordinator,',
            '                  Status|status, Author|author, Builder|build, Adhoc|adhoc. Omit for all.',
            '  -CloseSessions  Close the long-session tabs now.',
            '  -DryRun         Show what would stop or close; change nothing.',
            '  -Help           Show this help and exit.',
            '',
            'To stop one author or builder tab, use removeStreamTab.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'stopStreams'
    if (-not $full) { return }
    $tabs = @()
    foreach ($r in $Role) {
        $resolved = Resolve-GeneStreamTab -Name $r
        if (-not $resolved) { Write-Error "stopStreams: unknown role '$r' (see stopStreams -Help). Nothing was done."; return }
        $tabs += $resolved
    }
    $all = -not $tabs.Count
    $runnerTypes = @(@($global:GeneStreamTabRoles.Keys) + @($global:GeneStreamRunnerSessionTabs) | Where-Object { $all -or $_ -in $tabs })
    $sessionTabs = @(@($global:GeneStreamRoles.Keys) + @($global:GeneStreamOnDemandRoles.Keys) |
            Where-Object { $_ -notin $global:GeneStreamRunnerSessionTabs -and ($all -or $_ -in $tabs) })

    # Runners: STOP files.
    if ($runnerTypes.Count) {
        $roles = @($runnerTypes | ForEach-Object { Get-GeneStreamRunnerRole -Tab $_ })
        $files = if ($all) { @('STOP') } else { @($roles | ForEach-Object { "STOP-$_" }) }
        $live = @(Get-GeneStreamRunners -Repo $full -Role $roles)
        $verb = if ($DryRun) { 'would stop' } else { 'stopping' }
        foreach ($r in $live) { Write-Host "  $verb $(if ($r.Tab) { $r.Tab } else { $r.Role }) ($($r.Runner)): $($r.Status)" -ForegroundColor DarkCyan }
        if (-not $live.Count) { Write-Host "  no live $($roles -join '/') runner" -ForegroundColor DarkGray }
        if ($DryRun) { Write-Host "DryRun: would write $($files -join ', ') in $(Join-Path $full '.streams\runners')." -ForegroundColor Cyan }
        elseif ($live.Count) {
            $dir = Join-Path $full '.streams\runners'
            foreach ($f in $files) { Set-Content -LiteralPath (Join-Path $dir $f) -Value "stopStreams $(Get-Date -Format s) $env:USERNAME" }
            Write-Host "Wrote $($files -join ', '). Each runner exits after its current unit; its tab then closes." -ForegroundColor Green
        }
    }

    # Long sessions: list, or close with -CloseSessions.
    if ($sessionTabs.Count) {
        $sessions = @(Get-GeneStreamSessions -Repo $full | Where-Object { $_.Tab -in $sessionTabs })
        if (-not $sessions.Count) { Write-Host "  no live long session for $($sessionTabs -join ', ')" -ForegroundColor DarkGray }
        foreach ($s in $sessions) {
            if (-not $CloseSessions) { Write-Host "  $($s.Tab): long session running (shell pid $($s.Pid)). End it with Esc then /exit, or rerun with -CloseSessions." -ForegroundColor Yellow; continue }
            if ($DryRun) { Write-Host "DryRun: would close the $($s.Tab) tab (claude pid $($s.ClaudePid), shell pid $($s.Pid))." -ForegroundColor Cyan; continue }
            # The close flag makes the tab's shell exit with 0 once claude ends (Exit-GeneStreamSession), so the tab closes.
            Request-GeneStreamTabClose -Repo $full -Tab $s.Tab -By 'stopStreams -CloseSessions'
            if ($s.ClaudePid) { $null = & taskkill.exe /PID $s.ClaudePid /T /F 2>&1 } else { Stop-Process -Id $s.Pid -Confirm:$false }
            Write-Host "  Closed the $($s.Tab) tab." -ForegroundColor Green
        }
    }
}

function removeStreamTab {
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param(
        [Parameter(ParameterSetName = 'Author')][switch]$Author,
        [Parameter(ParameterSetName = 'Builder')][switch]$Builder,
        [int[]]$Number,
        [string]$Repo,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'removeStreamTab (-Author | -Builder) -Number <n>[,<n>...] [-Repo <repo>] [-DryRun] [-Help]',
            '(-Repo defaults to SpeedyRepo in the machine config.)',
            '',
            'Stops one author or builder tab cleanly: writes .streams\runners\STOP-tab-<Author_N> so only that runner',
            'finishes its current unit and exits; its tab then closes. Returns at once.',
            'A tab with that title whose runner has already exited is closed now.',
            '',
            'Examples:',
            '  removeStreamTab -Author -Number 2 -Repo d:\devops\repos\speedmerchants',
            '  removeStreamTab -Builder -Number 3,4 -Repo d:\devops\repos\speedmerchants'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    if (-not ($Author -or $Builder)) { Write-Error 'removeStreamTab: a type is required: -Author or -Builder. Nothing was done.'; return }
    if (-not $Number) { Write-Error 'removeStreamTab: -Number is required, e.g. -Number 2. Nothing was done.'; return }
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'removeStreamTab'
    if (-not $full) { return }
    $type = if ($Author) { 'Author' } else { 'Builder' }
    $role = $global:GeneStreamTabRoles[$type]
    $live = @(Get-GeneStreamRunners -Repo $full -Role $role)
    $stoppedTabs = @(Get-GeneStreamStoppedTabs -Repo $full)
    $dir = Join-Path $full '.streams\runners'
    foreach ($n in $Number) {
        $tab = "$type $n"
        $runner = @($live | Where-Object { $_.Tab -eq $tab }) | Select-Object -First 1
        if ($runner) {
            $stop = Join-Path $dir "STOP-tab-$(Get-GeneStreamTabToken $tab)"
            if ($DryRun) { Write-Host "DryRun: would write $stop ($tab, $($runner.Status))" -ForegroundColor Cyan; continue }
            Set-Content -LiteralPath $stop -Value "removeStreamTab $(Get-Date -Format s) $env:USERNAME"
            Write-Host "  $tab ($($runner.Runner)) stops after its current unit ($($runner.Status)); its tab then closes." -ForegroundColor Green
            continue
        }
        $open = @($stoppedTabs | Where-Object { $_.Tab -eq $tab })
        if (-not $open.Count) { Write-Warning "removeStreamTab: no live runner and no stopped tab for '$tab'. A tab this command cannot see can be closed with its X."; continue }
        if ($DryRun) { Write-Host "DryRun: would close the stopped tab '$tab' (shell pid $($open[0].Pid))." -ForegroundColor Cyan; continue }
        Request-GeneStreamTabClose -Repo $full -Tab $tab -By 'removeStreamTab'
        Write-Host "  '$tab (stopped)' closes within a few seconds; its runner was not running." -ForegroundColor Green
    }
}

# --- Sync and host moves (getStreams, pushStreams, updateStreams) --------------------------------------------------
# Owner 2026-10-17. Every location comes from the machine config: the stream repo is SpeedyRepo, the AI setup clone is
# AIWorkRoot, the owner's push right is the git policy row's 'Owner push' column (blank = Push), read through
# lib\MachineConfig.psm1 Get-AIGitPolicy. git-guard reads only Push, so a row can give the owner push while Claude
# sessions keep Push = no. Another machine's paths come from ITS machine config, read over the admin share.
# Board markers, all in <repo>\.streams (the board is not in git, so they travel with it):
#   host.json     the machine that runs this board (written by getStreams -FromHost). No host.json = no guard.
#   MOVED.json    on a board that was taken over: where it went. Every command that starts a stream tab refuses here.
#   handoff.json  written by pushStreams -Handoff once the old host is stopped, quiet and pushed: what ran, to reopen.

$global:GeneStreamNightlyPrefix = 'Speedy Tier2 nightly'
# Services 'docker compose ps' must show running on a stream host (migrate/backup-setup exit; tools are on demand).
$global:GeneStreamComposeServices = @('coordinator', 'fleet', 'throttle', 'warehouse', 'web')
# Seconds between checks while waiting for runners to finish their unit.
$global:GeneStreamWaitPollSeconds = 30

# Every runner role a tab can run: authors, builders and the once-per-repo runner tabs.
function Get-GeneStreamRunnerRoles {
    return @(@($global:GeneStreamTabRoles.Values) + @($global:GeneStreamRunnerSessionTabs | ForEach-Object { $global:GeneStreamRoles[$_] }))
}

function Get-GeneStreamBoardFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][ValidateSet('host', 'moved', 'handoff')][string]$Kind)
    $name = @{ host = 'host.json'; moved = 'MOVED.json'; handoff = 'handoff.json' }[$Kind]
    return Join-Path $Repo ".streams\$name"
}

# A board marker as an object; $null when absent. An unreadable marker still counts (host/to = '(unreadable)').
function Read-GeneStreamBoardFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][ValidateSet('host', 'moved', 'handoff')][string]$Kind)
    $path = Get-GeneStreamBoardFile -Repo $Repo -Kind $Kind
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ host = '(unreadable)'; to = '(unreadable)'; at = ''; file = $path } }
}

function Write-GeneStreamBoardFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][ValidateSet('host', 'moved', 'handoff')][string]$Kind,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Data)
    $Data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-GeneStreamBoardFile -Repo $Repo -Kind $Kind) -Encoding utf8
}

# $true when this machine may start the board's tabs. A board that moved away (MOVED.json) or names another host
# (host.json) refuses, unless -AnyHost: two hosts on one board claim and build the same tasks twice.
function Test-GeneStreamHost {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Caller, [switch]$AnyHost)
    $moved = Read-GeneStreamBoardFile -Repo $Repo -Kind moved
    $mark = Read-GeneStreamBoardFile -Repo $Repo -Kind host
    $why = if ($moved) { "this board moved to $($moved.to) on $($moved.at) ($(Get-GeneStreamBoardFile -Repo $Repo -Kind moved))" }
    elseif ($mark -and $mark.host -ne $env:COMPUTERNAME) { "this board's host is $($mark.host) ($(Get-GeneStreamBoardFile -Repo $Repo -Kind host))" }
    if (-not $why) { return $true }
    if ($AnyHost) { Write-Warning "${Caller}: $why; going on here anyway (-AnyHost)."; return $true }
    Write-Error "${Caller}: $why. Run the stream there, or add -AnyHost. Nothing was opened."
    return $false
}

# The AI setup clone (AIWorkRoot), or $null after writing the error.
function Get-GeneAIWorkRoot {
    param([Parameter(Mandatory)][string]$Caller)
    $root = if ($global:GeneMachineAI) { $global:GeneMachineAI['AIWorkRoot'] }
    if (-not $root -or -not (Test-Path -LiteralPath (Join-Path $root '.git'))) {
        Write-Error "${Caller}: AIWorkRoot ('$root') in $global:GeneMachineConfigPath is not the AI setup clone. Nothing was done."
        return $null
    }
    return $root.TrimEnd('\')
}

# git against -Dir; safe.directory=* so a clone on another machine's admin share reads too. Output lines; throws on failure.
function Invoke-GeneStreamGit {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string[]]$GitArgs)
    $out = @(& git -c safe.directory=* -C $Dir @GitArgs 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE) { throw "git -C $Dir $($GitArgs -join ' ') failed: $($out -join ' ')" }
    return $out
}

# Branch, upstream, uncommitted files and commits ahead of / behind the upstream (as last fetched; -Fetch fetches first).
function Get-GeneCloneState {
    param([Parameter(Mandatory)][string]$Dir, [switch]$Fetch)
    $branch = @(Invoke-GeneStreamGit -Dir $Dir -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD'))[0]
    $files = @(Invoke-GeneStreamGit -Dir $Dir -GitArgs @('status', '--porcelain'))
    $upstream = @(& git -c safe.directory=* -C $Dir rev-parse --abbrev-ref '@{u}' 2>$null)
    $hasUpstream = ($LASTEXITCODE -eq 0) -and $upstream.Count
    $behind = 0; $ahead = 0
    if ($hasUpstream) {
        if ($Fetch) { Invoke-GeneStreamGit -Dir $Dir -GitArgs @('fetch', '--quiet') | Out-Null }
        $counts = @(Invoke-GeneStreamGit -Dir $Dir -GitArgs @('rev-list', '--left-right', '--count', '@{u}...HEAD'))[0] -split '\s+'
        $behind = [int]$counts[0]; $ahead = [int]$counts[1]
    }
    [pscustomobject]@{
        Dir = $Dir; Branch = $branch; Upstream = $(if ($hasUpstream) { "$($upstream[0])" } else { $null })
        Files = $files.Count; Ahead = $ahead; Behind = $behind
    }
}

# This machine's git policy for -Repo (Get-AIGitPolicy: Commit, Push, Worktrees, OwnerPush).
function Get-GeneRepoGitPolicy {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$AIWorkRoot)
    Import-Module (Join-Path $AIWorkRoot 'lib\MachineConfig.psm1') -Force -Global
    return Get-AIGitPolicy -Path $Repo -Profile (Get-AIMachineProfile)
}

# Another machine's value for a first-table path key, read from ITS machine config over the admin share and returned
# as a UNC path (C:\x -> \\HOST\C$\x). Throws when the file, the row or a plain drive path is missing.
function Get-GeneRemoteMachinePath {
    param([Parameter(Mandatory)][string]$ComputerName, [Parameter(Mandatory)][string]$Key)
    $cfg = "\\$ComputerName\" + ($global:GeneMachineConfigPath -replace '^([A-Za-z]):', '$1$')
    if (-not (Test-Path -LiteralPath $cfg)) { throw "cannot read $cfg (admin share on $ComputerName)" }
    foreach ($line in Get-Content -LiteralPath $cfg) {
        if ($line -notmatch "^\s*\|\s*``?$Key``?\s*\|([^|]*)\|") { continue }
        $value = $Matches[1].Trim().Trim('`').Trim()
        if (-not $value) { throw "$Key is blank in $cfg" }
        if ($value -notmatch '^([A-Za-z]):\\?(.*)$') { throw "$Key in $cfg is not a plain drive path ('$value'); pass the path yourself" }
        return "\\$ComputerName\$($Matches[1])`$\$($Matches[2])".TrimEnd('\')
    }
    throw "no $Key row in $cfg"
}

# Why a board is not quiet, as Copy-StreamToHost.ps1 -Phase Final judges it: claims, building tasks (one parked on
# unfinished dependencies is carried as is), the integrator lock, uncommitted product code. Built tasks travel: their
# patches are on the board and the new host's integrator applies them.
function Get-GeneStreamBoardNoise {
    param([Parameter(Mandatory)][string]$Repo)
    $doc = Get-Content -LiteralPath (Join-Path $Repo '.streams\tasks.json') -Raw | ConvertFrom-Json
    $state = @{}; foreach ($t in $doc.tasks) { $state[$t.id] = $t.state }
    $claims = @($doc.tasks | Where-Object { $_.claim })
    $flight = @($doc.tasks | Where-Object {
            $_.state -eq 'building' -and -not (-not $_.claim -and @($_.dependsOn | Where-Object { $state[$_] -notin 'integrated', 'done' }).Count) })
    [pscustomobject]@{
        Claims = @($claims | ForEach-Object { $_.id })
        Flight = @($flight | ForEach-Object { $_.id })
        Lock   = Test-Path -LiteralPath (Join-Path $Repo '.streams\integrator.lock')
        Dirty  = @(Invoke-GeneStreamGit -Dir $Repo -GitArgs @('status', '--porcelain'))
    }
}

# What runs on a board now, to reopen after a stop: author and builder counts, the once-per-repo runner tabs that are
# live, and the long sessions (Planner, Adhoc).
function Get-GeneStreamLiveLayout {
    param([Parameter(Mandatory)][string]$Repo)
    $live = @(Get-GeneStreamRunners -Repo $Repo -Role (Get-GeneStreamRunnerRoles))
    [pscustomobject]@{
        Authors  = @($live | Where-Object { $_.Role -eq 'author' }).Count
        Builders = @($live | Where-Object { $_.Role -eq 'build' }).Count
        Tabs     = @($global:GeneStreamRunnerSessionTabs | Where-Object { $role = $global:GeneStreamRoles[$_]; @($live | Where-Object { $_.Role -eq $role }).Count })
        Sessions = @(Get-GeneStreamSessions -Repo $Repo | ForEach-Object { $_.Tab })
    }
}

function Format-GeneStreamLayout {
    param([Parameter(Mandatory)][object]$Layout)
    $parts = @($Layout.Tabs) + @("$($Layout.Authors) author(s)", "$($Layout.Builders) builder(s)")
    if (@($Layout.Sessions).Count) { $parts += "long: $(@($Layout.Sessions) -join ', ')" }
    return $parts -join ', '
}

# Waits until no runner of -Role is alive. $true when they all exited, $false at the timeout (stops stay in place).
function Wait-GeneStreamRunnersExit {
    param([Parameter(Mandatory)][string]$Repo, [string[]]$Role = (Get-GeneStreamRunnerRoles), [int]$TimeoutMinutes = 60)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $last = ''
    while ($true) {
        $live = @(Get-GeneStreamRunners -Repo $Repo -Role $Role)
        if (-not $live.Count) { return $true }
        $line = ($live | ForEach-Object { if ($_.Tab) { $_.Tab } else { $_.Runner } }) -join ', '
        if ($line -ne $last) {
            Write-Host "  $(Get-Date -Format HH:mm:ss) waiting for $($live.Count) runner(s) to finish their unit: $line" -ForegroundColor DarkGray
            $last = $line
        }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds $global:GeneStreamWaitPollSeconds
    }
}

# Reopens a layout recorded by Get-GeneStreamLiveLayout (runner tabs and counts; long sessions are the caller's).
function Open-GeneStreamLayout {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][object]$Layout, [switch]$AnyHost)
    foreach ($t in $Layout.Tabs) { addStreamTab -Role $t -Repo $Repo -AnyHost:$AnyHost }
    if ($Layout.Authors) { addStreamTab -Author -Count $Layout.Authors -Repo $Repo -AnyHost:$AnyHost }
    if ($Layout.Builders) { addStreamTab -Builder -Count $Layout.Builders -Repo $Repo -AnyHost:$AnyHost }
}

# After a kit install: what picks the change up by itself and what needs a restart.
function Show-GeneStreamRestartNeeds {
    param([string]$Repo)
    if (-not $Repo -or -not (Test-Path -LiteralPath (Join-Path $Repo '.streams\tasks.json'))) { return }
    $layout = Get-GeneStreamLiveLayout -Repo $Repo
    $runners = $layout.Authors + $layout.Builders + @($layout.Tabs).Count
    if ($runners) { Write-Host "  $runners runner(s) live: each new unit reads the installed skills; a changed runner script takes updateStreams." -ForegroundColor DarkCyan }
    foreach ($s in $layout.Sessions) { Write-Host "  ${s}: long session, still on the old setup until restarted (updateStreams -RestartSessions restarts the Planner)." -ForegroundColor Yellow }
}

# Kit half of getStreams: refuses over unpublished AI setup changes (offers to publish them first), then install.ps1.
function Invoke-GeneStreamKitGet {
    param([Parameter(Mandatory)][string]$Caller, [switch]$Yes, [switch]$DryRun)
    $ai = Get-GeneAIWorkRoot -Caller $Caller
    if (-not $ai) { return $false }
    $st = Get-GeneCloneState -Dir $ai
    if ($st.Files -or $st.Ahead) {
        $what = "$ai has unpublished changes ($($st.Files) file(s), $($st.Ahead) commit(s)), and install.ps1 pulls first"
        if ($DryRun) { Write-Host "Kit: DryRun: $what; getStreams would offer to publish them first." -ForegroundColor DarkYellow }
        elseif ([Console]::IsInputRedirected) { Write-Error "${Caller}: $what. Run pushStreams -NoCode first. Nothing was installed."; return $false }
        else {
            Write-Host "Kit: $what." -ForegroundColor Yellow
            $answer = Read-Host 'Publish them now (pushStreams -NoCode)? [y/N]'
            if ($answer -notmatch '^(y|yes)$') { Write-Error "${Caller}: stopped; publish with pushStreams -NoCode, or use -NoKit. Nothing was installed."; return $false }
            if (-not (Invoke-GeneStreamPush -Caller $Caller -NoCode)) { return $false }
        }
    }
    # @(...) around the if: a one-element array would come back as a bare string, and splatting a string passes its characters.
    $installArgs = @(if ($DryRun) { '-NoPull', '-WhatIf' } elseif ($Yes) { '-Yes' })
    Write-Host "Kit: pwsh -NoProfile -File $ai\install.ps1 $($installArgs -join ' ')" -ForegroundColor Cyan
    # Out-Host: the script's output must not become this function's return value (a failure would read as true).
    & pwsh -NoProfile -File (Join-Path $ai 'install.ps1') @installArgs | Out-Host
    if ($LASTEXITCODE) {
        Write-Error "${Caller}: install.ps1 exited $LASTEXITCODE (1 = you said no, 2 = invalid machine config, 3 = drift: run install.ps1 -AcceptDrift). Stopped there."
        return $false
    }
    return $true
}

# Code half of getStreams: fast-forwards the stream repo's branch from its upstream; never merges or rebases.
function Invoke-GeneStreamCodeGet {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Caller, [switch]$DryRun)
    try {
        $st = Get-GeneCloneState -Dir $Repo -Fetch
        if (-not $st.Upstream) { Write-Error "${Caller}: $Repo branch '$($st.Branch)' tracks no upstream. Nothing was pulled."; return $false }
        Write-Host "Code: $Repo $($st.Branch) vs $($st.Upstream): $($st.Behind) behind, $($st.Ahead) ahead." -ForegroundColor Cyan
        if (-not $st.Behind) { Write-Host '  up to date.' -ForegroundColor DarkGray; return $true }
        if ($st.Ahead) { Write-Error "${Caller}: $($st.Branch) has diverged from $($st.Upstream) ($($st.Ahead) local commit(s)); a fast-forward cannot take it. Resolve it with git, then rerun. Nothing was pulled."; return $false }
        if ($DryRun) { Write-Host "  DryRun: would fast-forward $($st.Behind) commit(s)." -ForegroundColor Cyan; return $true }
        Invoke-GeneStreamGit -Dir $Repo -GitArgs @('pull', '--ff-only', '--quiet') | Out-Null
        $head = @(Invoke-GeneStreamGit -Dir $Repo -GitArgs @('rev-parse', '--short', 'HEAD'))[0]
        Write-Host "  fast-forwarded $($st.Behind) commit(s) to $head." -ForegroundColor Green
        return $true
    }
    catch { Write-Error "${Caller}: $($_.Exception.Message)"; return $false }
}

# pushStreams without -Handoff: publish.ps1 for the kit, then git push of the stream branch where the git policy gives
# this machine an owner push. -RequireCode turns a missing push right or an unpushed result into a failure (handoff).
function Invoke-GeneStreamPush {
    param([string]$Repo, [string]$Message, [Parameter(Mandatory)][string]$Caller,
        [switch]$NoKit, [switch]$NoCode, [switch]$RequireCode, [switch]$Yes, [switch]$DryRun)
    $ai = Get-GeneAIWorkRoot -Caller $Caller
    if (-not $ai) { return $false }
    if (-not $DryRun -and -not $Yes -and [Console]::IsInputRedirected) {
        Write-Error "${Caller}: needs a console (the GitHub sign-in and publish.ps1's questions cannot show here). Run it in a Windows Terminal tab, or add -Yes. Nothing was pushed."
        return $false
    }
    if (-not $NoKit) {
        $st = Get-GeneCloneState -Dir $ai
        if (-not $st.Files -and -not $st.Ahead) { Write-Host "Kit: $ai has nothing to publish." -ForegroundColor DarkGray }
        elseif ($DryRun) { Write-Host "Kit: DryRun: would publish $($st.Files) file(s) and $($st.Ahead) commit(s) from $ai (publish.ps1)." -ForegroundColor Cyan }
        else {
            $pubArgs = @(); if ($Message) { $pubArgs += @('-Message', $Message) }; if ($Yes) { $pubArgs += '-Yes' }
            Write-Host "Kit: pwsh -NoProfile -File $ai\publish.ps1" -ForegroundColor Cyan
            & pwsh -NoProfile -File (Join-Path $ai 'publish.ps1') @pubArgs | Out-Host
            if ($LASTEXITCODE) { Write-Error "${Caller}: publish.ps1 exited $LASTEXITCODE. Stopped before the code."; return $false }
        }
    }
    if ($NoCode) { return $true }
    $full = Resolve-GeneStreamRepoPath -Repo $Repo -Caller $Caller
    if (-not $full) { return $false }
    try {
        $policy = Get-GeneRepoGitPolicy -Repo $full -AIWorkRoot $ai
        if (-not $policy.OwnerPush) {
            $msg = "the git policy in $global:GeneMachineConfigPath gives $full no owner push on $env:COMPUTERNAME (Owner push, else Push)"
            if ($RequireCode) { Write-Error "${Caller}: $msg; the new host pulls the code from the remote, so it must go there. Set Owner push = yes on that row."; return $false }
            Write-Host "Code: skipped: $msg." -ForegroundColor DarkYellow
            return $true
        }
        $st = Get-GeneCloneState -Dir $full -Fetch
        if (-not $st.Upstream) { Write-Error "${Caller}: $full branch '$($st.Branch)' tracks no upstream. Nothing was pushed."; return $false }
        Write-Host "Code: $full $($st.Branch) vs $($st.Upstream): $($st.Ahead) ahead, $($st.Behind) behind." -ForegroundColor Cyan
        if (-not $st.Ahead) { Write-Host '  nothing to push.' -ForegroundColor DarkGray; return $true }
        if ($st.Behind) { Write-Error "${Caller}: $($st.Upstream) has $($st.Behind) commit(s) this clone lacks; run getStreams -NoKit (or resolve the divergence), then push. Nothing was pushed."; return $false }
        if ($DryRun) { Write-Host "  DryRun: would push $($st.Ahead) commit(s)." -ForegroundColor Cyan; return $true }
        Invoke-GeneStreamGit -Dir $full -GitArgs @('push', '--quiet') | Out-Null
        Write-Host "  pushed $($st.Ahead) commit(s) to $($st.Upstream)." -ForegroundColor Green
        return $true
    }
    catch { Write-Error "${Caller}: $($_.Exception.Message)"; return $false }
}

# pushStreams -Handoff, on the OLD host: stop everything, wait for quiet, publish the kit, push the code, record what
# ran (handoff.json) and take the nightly suite off this machine. getStreams -FromHost on the new host does the rest.
function Invoke-GeneStreamHandoff {
    param([string]$Repo, [string]$Message, [int]$TimeoutMinutes = 60, [switch]$AllowClaims, [switch]$Yes, [switch]$DryRun)
    $caller = 'pushStreams -Handoff'
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller $caller
    if (-not $full) { return }
    if (-not $DryRun -and -not $Yes -and [Console]::IsInputRedirected) { Write-Error "${caller}: needs a console. Run it in a Windows Terminal tab, or add -Yes. Nothing was done."; return }
    $layout = Get-GeneStreamLiveLayout -Repo $full
    Write-Host "Handoff of $full from ${env:COMPUTERNAME}: running now: $(Format-GeneStreamLayout $layout)." -ForegroundColor Cyan
    if ($DryRun) {
        @(
            'DryRun: would',
            '  1. stopStreams -CloseSessions: STOP every runner (each finishes its unit) and close the Planner/Adhoc tabs;',
            "  2. wait up to $TimeoutMinutes min until no runner is live, then drop a dead integrator.lock;",
            '  3. check the board is quiet: no claims, no building task, clean main tree (-AllowClaims carries orphan claims);',
            '  4. publish the kit (publish.ps1) and push the stream branch (needs Owner push on this machine);',
            "  5. write $(Get-GeneStreamBoardFile -Repo $full -Kind handoff) with the layout above;",
            "  6. export and unregister the '$global:GeneStreamNightlyPrefix $(Split-Path $full -Leaf)' task."
        ) | ForEach-Object { Write-Host $_ }
        $noise = Get-GeneStreamBoardNoise -Repo $full
        Write-Host "  board now: $($noise.Claims.Count) claim(s), $($noise.Flight.Count) building, lock=$($noise.Lock), $($noise.Dirty.Count) uncommitted entr(ies)." -ForegroundColor DarkGray
        $null = Invoke-GeneStreamPush -Repo $full -Caller $caller -RequireCode -DryRun
        return
    }

    stopStreams -Repo $full -CloseSessions
    if (-not (Wait-GeneStreamRunnersExit -Repo $full -TimeoutMinutes $TimeoutMinutes)) {
        Write-Error "${caller}: runners still finishing after $TimeoutMinutes min; the STOP file stays. Rerun pushStreams -Handoff to keep waiting."
        return
    }
    $lock = Join-Path $full '.streams\integrator.lock'
    if (Test-Path -LiteralPath $lock) {
        Remove-Item -LiteralPath $lock
        Write-Host "  removed $lock (no integrator runs any more)." -ForegroundColor DarkYellow
    }
    $noise = Get-GeneStreamBoardNoise -Repo $full
    if ($noise.Dirty.Count) {
        Write-Error "${caller}: $full has $($noise.Dirty.Count) uncommitted entr(ies) (an integration stopped halfway?): $(($noise.Dirty | Select-Object -First 8) -join '; '). Commit or revert them, then rerun. Streams stay stopped."
        return
    }
    if (($noise.Claims.Count -or $noise.Flight.Count) -and -not $AllowClaims) {
        Write-Error "${caller}: the board still has claims ($($noise.Claims -join ', ')) / building tasks ($($noise.Flight -join ', ')). With every runner stopped they are orphans: add -AllowClaims to carry them (the new host's watchdog frees them after 30/45 min). Streams stay stopped."
        return
    }
    if (-not (Invoke-GeneStreamPush -Repo $full -Message $Message -Caller $caller -RequireCode -Yes:$Yes)) { return }
    $after = Get-GeneCloneState -Dir $full
    if ($after.Ahead -or $after.Files) { Write-Error "${caller}: $full still has $($after.Ahead) unpushed commit(s) / $($after.Files) uncommitted entr(ies). Streams stay stopped."; return }
    $head = @(Invoke-GeneStreamGit -Dir $full -GitArgs @('rev-parse', 'HEAD'))[0]
    Write-GeneStreamBoardFile -Repo $full -Kind handoff -Data ([ordered]@{
            from = $env:COMPUTERNAME; at = (Get-Date).ToUniversalTime().ToString('o'); by = $env:USERNAME; head = $head
            authors = $layout.Authors; builders = $layout.Builders; tabs = @($layout.Tabs); sessions = @($layout.Sessions)
            carriedClaims = @($noise.Claims); carriedBuilding = @($noise.Flight)
        })
    Write-Host "Wrote $(Get-GeneStreamBoardFile -Repo $full -Kind handoff)." -ForegroundColor Green

    $task = "$global:GeneStreamNightlyPrefix $(Split-Path $full -Leaf)"
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        try {
            $dir = Join-Path $global:GeneMachineAI['ScratchRoot'] "stream-move\$(Get-Date -Format yyyyMMdd-HHmmss)"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Export-ScheduledTask -TaskName $task | Set-Content -LiteralPath (Join-Path $dir 'nightly-task.xml') -Encoding unicode
            Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction Stop
            Write-Host "  unregistered '$task' (backup $dir\nightly-task.xml)." -ForegroundColor Green
        }
        catch { Write-Warning "${caller}: could not unregister '$task' ($($_.Exception.Message)). In an elevated pwsh: Unregister-ScheduledTask -TaskName '$task'" }
    }
    Write-Host "Handoff ready. On the new host, in a Windows Terminal tab: getStreams -FromHost $env:COMPUTERNAME" -ForegroundColor Green
}

# getStreams -FromHost, on the NEW host: everything to run the board that ran on -FromHost here. Reads the old host's
# repo and AI setup paths from its own machine config over the admin share.
function Invoke-GeneStreamTakeover {
    param([string]$Repo, [Parameter(Mandatory)][string]$FromHost, [string]$FromRepo, [string]$ContainerRoot,
        [switch]$NoHandoff, [switch]$AllowClaims, [switch]$Yes, [switch]$DryRun)
    $caller = 'getStreams -FromHost'
    if ($FromHost -eq $env:COMPUTERNAME) { Write-Error "${caller}: $FromHost is this machine. Nothing was done."; return }
    $full = Resolve-GeneStreamRepoPath -Repo $Repo -Caller $caller
    if (-not $full) { return }
    $scratch = $global:GeneMachineAI['ScratchRoot']
    if (-not $scratch) { Write-Error "${caller}: ScratchRoot is blank in $global:GeneMachineConfigPath (the old board is saved there). Nothing was done."; return }

    try { $src = if ($FromRepo) { $FromRepo.TrimEnd('\') } else { Get-GeneRemoteMachinePath -ComputerName $FromHost -Key 'SpeedyRepo' } }
    catch { Write-Error "${caller}: $($_.Exception.Message). Pass -FromRepo \\$FromHost\<drive>`$\<path>. Nothing was done."; return }
    if (-not (Test-Path -LiteralPath (Join-Path $src '.streams\tasks.json'))) { Write-Error "${caller}: no board at $src\.streams. Nothing was done."; return }
    Write-Host "Takeover: $FromHost $src -> $env:COMPUTERNAME $full" -ForegroundColor Cyan

    # This machine must not be running a board itself.
    if (Test-Path -LiteralPath (Join-Path $full '.streams\tasks.json')) {
        $here = Get-GeneStreamLiveLayout -Repo $full
        if ($here.Authors + $here.Builders + @($here.Tabs).Count + @($here.Sessions).Count) {
            Write-Error "${caller}: this machine still runs its own board ($(Format-GeneStreamLayout $here)). stopStreams -CloseSessions first. Nothing was done."
            return
        }
    }

    # The old host: not already moved, handed off, quiet, kit published.
    $moved = Read-GeneStreamBoardFile -Repo $src -Kind moved
    if ($moved) { Write-Error "${caller}: the board on $FromHost already moved to $($moved.to) on $($moved.at). Nothing was done."; return }
    $handoff = Read-GeneStreamBoardFile -Repo $src -Kind handoff
    if (-not $handoff -and -not $NoHandoff) {
        Write-Error "${caller}: $FromHost has not handed off (no $(Get-GeneStreamBoardFile -Repo $src -Kind handoff)). On ${FromHost}: pushStreams -Handoff. If it cannot run commands any more, add -NoHandoff. Nothing was done."
        return
    }
    if ($handoff) { Write-Host "  handoff by $($handoff.by) at $($handoff.at): $($handoff.authors) author(s), $($handoff.builders) builder(s), tabs $(@($handoff.tabs) -join ', ')" -ForegroundColor DarkCyan }
    try { $noise = Get-GeneStreamBoardNoise -Repo $src }
    catch { Write-Error "${caller}: cannot read the board or repo on ${FromHost}: $($_.Exception.Message). Nothing was done."; return }
    if ($noise.Dirty.Count) { Write-Error "${caller}: $src has $($noise.Dirty.Count) uncommitted entr(ies): $(($noise.Dirty | Select-Object -First 8) -join '; '). That code would be lost. Nothing was done."; return }
    if (($noise.Claims.Count -or $noise.Flight.Count -or $noise.Lock) -and -not $AllowClaims) {
        Write-Error "${caller}: the board on $FromHost is not quiet: claims $($noise.Claims -join ', '); building $($noise.Flight -join ', '); integrator.lock=$($noise.Lock). If everything there is stopped these are orphans: add -AllowClaims. Nothing was done."
        return
    }
    try {
        $srcAi = Get-GeneRemoteMachinePath -ComputerName $FromHost -Key 'AIWorkRoot'
        $kit = Get-GeneCloneState -Dir $srcAi
        if ($kit.Files -or $kit.Ahead) {
            $msg = "the AI setup on $FromHost ($srcAi) has unpublished changes ($($kit.Files) file(s), $($kit.Ahead) commit(s))"
            if (-not $NoHandoff) { Write-Error "${caller}: $msg. On ${FromHost}: pushStreams -NoCode. Nothing was done."; return }
            Write-Warning "${caller}: $msg; they do not come along (see git -C $srcAi status)."
        }
    }
    catch { Write-Warning "${caller}: could not check the AI setup on ${FromHost}: $($_.Exception.Message)" }

    if ($DryRun) {
        @(
            'DryRun: checks passed. Would',
            '  1. getStreams here (install the kit, fast-forward the code) and require the same tree as the old host;',
            "  2. move this machine's .streams (if any) to $scratch\stream-move\<stamp>\;",
            "  3. robocopy /MIR $src\.streams -> $full\.streams (no *.lock files);",
            "  4. add .streams/ to $full\.git\info\exclude if missing;",
            "  5. write .streams\host.json ($env:COMPUTERNAME) here and .streams\MOVED.json on $FromHost;",
            "  6. copy $src\.env if this repo has none; then check this host (Test-StreamHostReady, .env, dev cert, compose, nightly)."
        ) | ForEach-Object { Write-Host $_ }
        return
    }

    if (-not (Invoke-GeneStreamKitGet -Caller $caller -Yes:$Yes)) { return }
    if (-not (Invoke-GeneStreamCodeGet -Repo $full -Caller $caller)) { return }
    try {
        $hereTree = @(Invoke-GeneStreamGit -Dir $full -GitArgs @('rev-parse', 'HEAD^{tree}'))[0]
        $thereTree = @(Invoke-GeneStreamGit -Dir $src -GitArgs @('rev-parse', 'HEAD^{tree}'))[0]
    }
    catch { Write-Error "${caller}: $($_.Exception.Message)"; return }
    if ($hereTree -ne $thereTree) {
        Write-Error "${caller}: the code differs: here tree $hereTree, $FromHost $thereTree. Push it from $FromHost (pushStreams -NoKit), then rerun. The board was not copied."
        return
    }

    $moveDir = Join-Path $scratch "stream-move\$(Get-Date -Format yyyyMMdd-HHmmss)"
    New-Item -ItemType Directory -Path $moveDir -Force | Out-Null
    $log = Join-Path $moveDir 'robocopy.log'
    $board = Join-Path $full '.streams'
    if (Test-Path -LiteralPath $board) {
        $old = Join-Path $moveDir "$(Split-Path $full -Leaf)-streams-old"
        & robocopy $board $old /E /MOVE /R:2 /W:2 /NP /NFL /NDL "/LOG+:$log" | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Error "${caller}: saving the old board to $old failed (robocopy $LASTEXITCODE, $log). Nothing else was changed."; return }
        if (Test-Path -LiteralPath $board) {
            if (@(Get-ChildItem -LiteralPath $board -Recurse -File -Force).Count) { Write-Error "${caller}: files left in $board after saving it to $old (in use?). Close what holds them and rerun."; return }
            Remove-Item -LiteralPath $board -Recurse -Force
        }
        Write-Host "  saved this machine's old board to $old" -ForegroundColor DarkCyan
    }
    Write-Host "  copying the board from $FromHost (robocopy, log $log) ..." -ForegroundColor DarkCyan
    & robocopy (Join-Path $src '.streams') $board /MIR /XF '*.lock' /R:2 /W:2 /MT:16 /NP /NFL /NDL "/LOG+:$log" | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Error "${caller}: robocopy of the board failed ($LASTEXITCODE). See $log. $FromHost was not marked moved."; return }
    $files = @(Get-ChildItem -LiteralPath $board -Recurse -File -Force).Count
    Write-Host "  board copied: $files file(s)." -ForegroundColor Green
    Remove-Item -LiteralPath (Get-GeneStreamBoardFile -Repo $full -Kind handoff) -ErrorAction SilentlyContinue

    $exclude = Join-Path $full '.git\info\exclude'
    if ((Test-Path -LiteralPath (Split-Path $exclude)) -and -not (Select-String -LiteralPath $exclude -Pattern '^\s*/?\.streams/?\s*$' -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -LiteralPath $exclude -Value '.streams/'
        Write-Host "  added .streams/ to $exclude" -ForegroundColor DarkCyan
    }

    $at = (Get-Date).ToUniversalTime().ToString('o')
    Write-GeneStreamBoardFile -Repo $full -Kind host -Data ([ordered]@{ host = $env:COMPUTERNAME; from = $FromHost; at = $at; by = $env:USERNAME })
    try {
        Write-GeneStreamBoardFile -Repo $src -Kind moved -Data ([ordered]@{ to = $env:COMPUTERNAME; at = $at; by = $env:USERNAME })
        Write-Host "  marked the board on $FromHost moved (MOVED.json): stream tabs there now refuse." -ForegroundColor Green
    }
    catch { Write-Warning "${caller}: could not write MOVED.json on ${FromHost} ($($_.Exception.Message)). Nothing stops streams starting there: do not start them." }

    $envFile = Join-Path $full '.env'
    if (-not (Test-Path -LiteralPath $envFile) -and (Test-Path -LiteralPath (Join-Path $src '.env'))) {
        Copy-Item -LiteralPath (Join-Path $src '.env') -Destination $envFile
        Write-Host "  copied .env from $FromHost (it held only channel names there; check it fits this machine)." -ForegroundColor DarkYellow
    }

    Show-GeneStreamHostReadiness -Repo $full -ContainerRoot $ContainerRoot
    Write-Host ''
    Write-Host 'Then start the stream here, in a Windows Terminal tab:' -ForegroundColor Green
    Write-Host '  addStreams'
    if ($handoff -and $handoff.authors) { Write-Host "  addStreamTab -Author -Count $($handoff.authors)" }
    if ($handoff -and $handoff.builders) { Write-Host "  addStreamTab -Builder -Count $($handoff.builders)" }
}

# What a stream host needs that never travels with the board. Prints each check and a LEFT TO DO list; changes nothing.
function Show-GeneStreamHostReadiness {
    param([Parameter(Mandatory)][string]$Repo, [string]$ContainerRoot)
    $todo = [System.Collections.Generic.List[string]]::new()
    $row = { param($ok, $what) Write-Host ("  {0,-4} {1}" -f $(if ($ok) { 'ok' } else { 'TODO' }), $what) -ForegroundColor $(if ($ok) { 'DarkGreen' } else { 'Yellow' }) }
    Write-Host "Host readiness on ${env:COMPUTERNAME}:" -ForegroundColor Cyan

    $ai = $global:GeneMachineAI['AIWorkRoot']
    $dir = $global:GeneMachineAI['StreamHostDir']
    $ready = @($(if ($dir) { Join-Path $dir 'Test-StreamHostReady.ps1' }), $(if ($ai) { Join-Path $ai 'stream-host\Test-StreamHostReady.ps1' })) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($ready) {
        if (-not $ContainerRoot) { $ContainerRoot = if (Test-Path -LiteralPath 'D:\RancherDesktop') { 'D:\RancherDesktop' } else { 'C:\' } }
        $wt = if ($global:GeneMachineAI['WorktreesRoot']) { Join-Path $global:GeneMachineAI['WorktreesRoot'] (Split-Path $Repo -Leaf) } else { 'C:\devops\worktrees\speedmerchants' }
        & pwsh -NoProfile -File $ready -Repo $Repo -WorktreeRoot $wt -ContainerRoot $ContainerRoot | Out-Host
        if ($LASTEXITCODE) { $todo.Add("Test-StreamHostReady: fix the FAIL rows above (ContainerRoot $ContainerRoot; pass -ContainerRoot if Rancher keeps its disks elsewhere).") }
    }
    else { $todo.Add('Test-StreamHostReady.ps1 not found (StreamHostDir / AIWorkRoot\stream-host): run install.ps1.') }

    $hasEnv = Test-Path -LiteralPath (Join-Path $Repo '.env')
    & $row $hasEnv "root .env in $Repo"
    if (-not $hasEnv) { $todo.Add("root .env missing in $Repo (the nightly suite refuses without it): copy it from the old host, or write the 11 Channel keys (src\Agent\appsettings.sample.json).") }
    $hasLocal = Test-Path -LiteralPath (Join-Path $Repo '.env.local')
    & $row $hasLocal "$Repo\.env.local"
    if (-not $hasLocal) { $todo.Add("$Repo\.env.local missing: $Repo\scripts\e2e\Write-SpeedyStackEnv.ps1 -RepoRoot $Repo") }
    $channel = Join-Path $env:LOCALAPPDATA 'Speedy\dev-stack\worker-channel'
    $hasChannel = Test-Path -LiteralPath $channel
    & $row $hasChannel "worker-channel certificates ($channel)"
    if (-not $hasChannel) { $todo.Add("worker-channel certificates missing: $Repo\scripts\fleet\New-WorkerChannelCertificates.ps1") }
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        $null = & dotnet dev-certs https --check --trust 2>&1
        $trusted = ($LASTEXITCODE -eq 0)
        & $row $trusted 'ASP.NET dev certificate trusted (dotnet dev-certs https --check --trust)'
        if (-not $trusted) { $todo.Add('dev certificate not trusted: dotnet dev-certs https --trust (desktop session, answer Yes)') }
    }
    $compose = Join-Path $Repo 'compose.yaml'
    if ((Get-Command docker -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $compose)) {
        $running = @(& docker compose -f $compose ps --status running --services 2>$null)
        $missing = @($global:GeneStreamComposeServices | Where-Object { $_ -notin $running })
        & $row (-not $missing.Count) "compose services running ($($global:GeneStreamComposeServices -join ', '))"
        if ($missing.Count) { $todo.Add("compose services not running: $($missing -join ', '). docker compose -f $compose up -d (Rancher must be up)") }
    }
    else { $todo.Add('docker or compose.yaml not found: Rancher Desktop + the compose stack (SyncStream B1/B3a).') }
    $task = "$global:GeneStreamNightlyPrefix $(Split-Path $Repo -Leaf)"
    $hasTask = [bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)
    & $row $hasTask "nightly task '$task'"
    if (-not $hasTask) {
        $claudeHome = if ($global:GeneMachineAI['ClaudeHome']) { $global:GeneMachineAI['ClaudeHome'] } else { Join-Path $HOME '.claude' }
        $reg = Join-Path $claudeHome 'skills\stream-kit\scripts\Register-NightlySuite.ps1'
        $todo.Add("nightly suite not registered (after the stack is up), elevated: pwsh -NoProfile -File $reg -Repo $Repo")
    }
    if (-not $global:GeneMachineAI['StatusPageDir']) { Write-Host "  info StatusPageDir is blank: the status page goes to $Repo\.streams\status.html" -ForegroundColor DarkGray }

    if ($todo.Count) {
        Write-Host 'LEFT TO DO:' -ForegroundColor Yellow
        $i = 0; foreach ($t in $todo) { $i++; Write-Host "  $i. $t" -ForegroundColor Yellow }
    }
    else { Write-Host 'Host ready: nothing left to do.' -ForegroundColor Green }
}

function getStreams {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [string]$FromHost,
        [string]$FromRepo,
        [string]$ContainerRoot,
        [switch]$NoHandoff,
        [switch]$AllowClaims,
        [switch]$NoKit,
        [switch]$NoCode,
        [switch]$Yes,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'getStreams [-Repo <repo>] [-NoKit] [-NoCode] [-Yes] [-DryRun] [-Help]',
            'getStreams -FromHost <old host> [-FromRepo <unc>] [-NoHandoff] [-AllowClaims] [-ContainerRoot <dir>] [-Yes] [-DryRun]',
            '',
            'Brings this machine up to date. Paths come from the machine config: the kit from AIWorkRoot, the code from',
            'SpeedyRepo (or -Repo).',
            '  1. Kit: refuses over unpublished AI setup changes (offers to publish them first: memory lives in that clone),',
            '     then runs install.ps1 (pull + apply). -Yes skips its confirmation.',
            '  2. Code: fetch, then a fast-forward of the current branch from its upstream (never a merge or rebase).',
            '  3. Says what picks the change up by itself (runner units) and what needs a restart (Planner, Adhoc).',
            'It never touches the board (.streams).',
            '',
            '-FromHost: TAKE OVER the stream that ran on another machine (run pushStreams -Handoff there first). It reads the',
            'old host''s SpeedyRepo and AIWorkRoot from ITS machine config (\\<host>\C$\Deploy\Setup\ProfileMachineConfig.md),',
            'refuses unless that board is handed off, quiet and its kit published, runs steps 1-2 here, requires the same code',
            'tree, saves this machine''s old board under {ScratchRoot}\stream-move\, mirrors the board (no lock files), writes',
            '.streams\host.json here and .streams\MOVED.json there (stream tabs on the old host then refuse), copies .env when',
            'this repo has none, checks this host (Test-StreamHostReady, .env, dev cert, compose, nightly task) and prints',
            'LEFT TO DO plus the addStreams / addStreamTab commands for what ran there.',
            '',
            'Options:',
            '  -Repo           The stream repo here. Default: SpeedyRepo.',
            '  -NoKit/-NoCode  Skip the kit or the code step.',
            '  -FromHost       The old host''s computer name.',
            '  -FromRepo       The old host''s repo as a UNC path, when its machine config cannot be read.',
            '  -NoHandoff      Take over without pushStreams -Handoff (the old host cannot run commands any more).',
            '  -AllowClaims    Carry orphan claims, building tasks and a dead integrator.lock (the watchdog frees them).',
            '  -ContainerRoot  Where Rancher keeps its disks, for Test-StreamHostReady (default D:\RancherDesktop if present, else C:\).',
            '  -Yes            No confirmation from install.ps1.',
            '  -DryRun         Check and print what would happen; change nothing (the code is fetched to count commits).',
            '',
            'See also: pushStreams, updateStreams, addStreams.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    if ($FromHost) {
        Invoke-GeneStreamTakeover -Repo $Repo -FromHost $FromHost -FromRepo $FromRepo -ContainerRoot $ContainerRoot -NoHandoff:$NoHandoff -AllowClaims:$AllowClaims -Yes:$Yes -DryRun:$DryRun
        return
    }
    $full = $null
    if (-not $NoCode) {
        $full = Resolve-GeneStreamRepoPath -Repo $Repo -Caller 'getStreams'
        if (-not $full) { return }
    }
    if (-not $NoKit -and -not (Invoke-GeneStreamKitGet -Caller 'getStreams' -Yes:$Yes -DryRun:$DryRun)) { return }
    if (-not $NoCode -and -not (Invoke-GeneStreamCodeGet -Repo $full -Caller 'getStreams' -DryRun:$DryRun)) { return }
    if (-not $NoKit) { Show-GeneStreamRestartNeeds -Repo $(if ($full) { $full } else { $global:GeneMachine['SpeedyRepo'] }) }
    Write-Host "getStreams done$(if ($DryRun) { ' (DryRun)' })." -ForegroundColor Green
}

function pushStreams {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Repo,
        [switch]$NoKit,
        [switch]$NoCode,
        [switch]$Handoff,
        [switch]$AllowClaims,
        [ValidateRange(1, 600)][int]$TimeoutMinutes = 60,
        [switch]$Yes,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'pushStreams [-Message <text>] [-Repo <repo>] [-NoKit] [-NoCode] [-Yes] [-DryRun] [-Help]',
            'pushStreams -Handoff [-Message <text>] [-AllowClaims] [-TimeoutMinutes <n>] [-Yes] [-DryRun]',
            '',
            'Sends this machine''s changes up. Run it in a Windows Terminal tab, not Claude''s ! box (the GitHub sign-in and',
            'publish.ps1''s questions need a console).',
            '  1. Kit: publish.ps1 in AIWorkRoot (shows the files, secret scan, commit, rebase, push).',
            '  2. Code: git push of the stream repo''s branch (SpeedyRepo, or -Repo) to its upstream, only where this',
            '     machine''s git policy row gives the owner push: the Owner push column, else Push. Never commits product',
            '     code (the integrator does) and never force-pushes; refuses when the upstream has commits this clone lacks.',
            '',
            '-Handoff: on the OLD host, before getStreams -FromHost on the new one: stopStreams -CloseSessions, wait until',
            'every runner finished its unit, drop the dead integrator.lock, require a quiet board (no claims, nothing',
            'building, clean tree), publish + push (the push must be allowed), record what ran in .streams\handoff.json,',
            'and export + unregister this machine''s nightly suite task.',
            '',
            'Options:',
            '  -Message         Commit message for the kit (default: publish.ps1''s "update from <machine>").',
            '  -Repo            The stream repo. Default: SpeedyRepo.',
            '  -NoKit/-NoCode   Skip the kit or the code step.',
            '  -AllowClaims     Handoff: carry orphan claims / building tasks (the new host''s watchdog frees them).',
            '  -TimeoutMinutes  Handoff: how long to wait for runners to finish (default 60).',
            '  -Yes             No confirmation from publish.ps1 (a secret-scan hit still needs a typed yes).',
            '  -DryRun          Print what would be published and pushed; change nothing.',
            '',
            'See also: getStreams, updateStreams.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    if ($Handoff) {
        Invoke-GeneStreamHandoff -Repo $Repo -Message $Message -TimeoutMinutes $TimeoutMinutes -AllowClaims:$AllowClaims -Yes:$Yes -DryRun:$DryRun
        return
    }
    if (Invoke-GeneStreamPush -Repo $Repo -Message $Message -Caller 'pushStreams' -NoKit:$NoKit -NoCode:$NoCode -Yes:$Yes -DryRun:$DryRun) {
        Write-Host "pushStreams done$(if ($DryRun) { ' (DryRun)' })." -ForegroundColor Green
    }
}

function updateStreams {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [switch]$Code,
        [ValidateRange(1, 600)][int]$TimeoutMinutes = 60,
        [switch]$RestartSessions,
        [switch]$AnyHost,
        [switch]$Yes,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'updateStreams [-Repo <repo>] [-Code] [-TimeoutMinutes <n>] [-RestartSessions] [-AnyHost] [-Yes] [-DryRun] [-Help]',
            '',
            'Rolling update of a RUNNING stream on its host, run from a Windows Terminal tab:',
            '  1. records what runs (Integrator/Kit/Coordinator/Status runners, author and builder counts, long sessions);',
            '  2. stopStreams: a STOP file; each runner finishes its unit (never killed mid-unit) and its tab closes;',
            '  3. waits until no runner is live (-TimeoutMinutes, default 60; on timeout the STOP stays, rerun to keep waiting);',
            '  4. getStreams -NoCode: install the kit (with -Code it also fast-forwards the code);',
            '  5. reopens the same runner tabs and counts (addStreamTab);',
            '  6. lists the long sessions (Planner, Adhoc), which keep the old setup until restarted. -RestartSessions closes',
            '     and reopens the Planner tab (ending any turn in progress). Adhoc is yours to restart.',
            'If step 4 fails the runners stay stopped; fix it, then addStreamTab (or rerun updateStreams).',
            '',
            'Options:',
            '  -Repo             The stream repo. Default: SpeedyRepo.',
            '  -Code             Also fast-forward the code from its upstream.',
            '  -RestartSessions  Restart the Planner tab too.',
            '  -AnyHost          Run even when the board says another machine hosts it.',
            '  -Yes              No confirmation from install.ps1.',
            '  -DryRun           Print what runs and what would happen; change nothing.',
            '',
            'See also: getStreams, pushStreams, stopStreams, addStreamTab.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'updateStreams'
    if (-not $full) { return }
    if (-not (Test-GeneStreamHost -Repo $full -Caller 'updateStreams' -AnyHost:$AnyHost)) { return }
    if (-not $DryRun -and -not (Test-GeneWt -Caller 'updateStreams')) { return }
    $layout = Get-GeneStreamLiveLayout -Repo $full
    Write-Host "updateStreams $full, running now: $(Format-GeneStreamLayout $layout)." -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host 'DryRun: would stopStreams, wait for every runner to finish its unit, then:' -ForegroundColor Cyan
        $null = Invoke-GeneStreamKitGet -Caller 'updateStreams' -DryRun
        if ($Code) { $null = Invoke-GeneStreamCodeGet -Repo $full -Caller 'updateStreams' -DryRun }
        Write-Host "  then reopen: $(@($layout.Tabs) -join ', ') $(if ($layout.Authors) { "Author x$($layout.Authors)" }) $(if ($layout.Builders) { "Builder x$($layout.Builders)" })" -ForegroundColor Cyan
        if ($RestartSessions -and 'Planner' -in $layout.Sessions) { Write-Host '  and close + reopen the Planner tab.' -ForegroundColor Cyan }
        return
    }

    stopStreams -Repo $full
    if (-not (Wait-GeneStreamRunnersExit -Repo $full -TimeoutMinutes $TimeoutMinutes)) {
        Write-Error "updateStreams: runners still finishing after $TimeoutMinutes min; the STOP file stays. Rerun updateStreams to keep waiting, or addStreamTab -ClearStop to cancel."
        return
    }
    Write-Host '  every runner has stopped.' -ForegroundColor DarkCyan
    if (-not (Invoke-GeneStreamKitGet -Caller 'updateStreams' -Yes:$Yes)) { Write-Warning 'updateStreams: the runners stay stopped; fix the above, then rerun updateStreams or addStreamTab.'; return }
    if ($Code -and -not (Invoke-GeneStreamCodeGet -Repo $full -Caller 'updateStreams')) { Write-Warning 'updateStreams: the kit is installed, the runners stay stopped; fix the code step, then rerun updateStreams or addStreamTab.'; return }
    Open-GeneStreamLayout -Repo $full -Layout $layout -AnyHost:$AnyHost

    foreach ($s in @($layout.Sessions)) {
        if ($s -eq 'Planner' -and $RestartSessions) {
            stopStreams -Repo $full -Role Planner -CloseSessions
            $deadline = (Get-Date).AddSeconds(30)
            while (@(Get-GeneStreamSessions -Repo $full | Where-Object { $_.Tab -eq 'Planner' }).Count -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
            addStreamTab -Role Planner -Repo $full -AnyHost:$AnyHost
            continue
        }
        Write-Host "  ${s}: long session, still on the old setup; restart it when it is quiet$(if ($s -eq 'Planner') { ' (or updateStreams -RestartSessions)' })." -ForegroundColor Yellow
    }
    Write-Host 'updateStreams done.' -ForegroundColor Green
}
#endregion Stream sessions -------------------------------------------------------
