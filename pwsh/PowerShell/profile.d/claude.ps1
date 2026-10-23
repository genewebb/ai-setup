# profile.d\claude: Claude Code accounts (claude-work, claude-home, claude-which). Definitions only; loaded by the core profile.

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

