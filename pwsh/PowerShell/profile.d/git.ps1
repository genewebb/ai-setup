# profile.d\git: commit, push and sync (gpush, pps, psql, pushrules, dpAI). Definitions only; loaded by the core profile.

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
