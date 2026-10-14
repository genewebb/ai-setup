# Machine-specific roots come from the profile's $global:GeneMachine (C:\Deploy\Setup\ProfileMachineConfig.md);
# the fallback keeps the module usable when it is imported without the profile.
function Get-GeneMachineRoot([string]$Key, [string]$Default) {
    if ($global:GeneMachine -and $global:GeneMachine[$Key]) { return $global:GeneMachine[$Key] }
    return $Default
}
# Gene.GitTools.psm1
# Git helpers + personal repo push commands (lazy-loaded by profile)

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
        Write-Host "[WhatIf] Would check staged files for sensitive patterns (*.env, *secret*, *password*, etc.)" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would run: git commit -m `"$Message`" (if staged changes exist)" -ForegroundColor Yellow
        Write-Host "[WhatIf] Would run: git push -u origin $branch" -ForegroundColor Yellow
        return
    }

    git add .

    $staged = @(git diff --cached --name-only)
    if ($staged.Count -gt 0) {
        # Guard against accidentally committing sensitive files
        $sensitivePatterns = @('*.env', '.env*', '*secret*', '*password*', '*credential*', '*apikey*', '*.pfx', '*.p12', '*.key')
        $suspicious = @($staged | Where-Object { $f = $_; $sensitivePatterns | Where-Object { $f -like $_ } })

        if ($suspicious.Count -gt 0) {
            Write-Host "Aborting: potentially sensitive files detected in staging:" -ForegroundColor Red
            $suspicious | ForEach-Object { Write-Host "  $_" -ForegroundColor Red }
            Write-Host "Run 'git reset HEAD' to unstage, add to .gitignore, then retry." -ForegroundColor Yellow
            git restore --staged . 2>$null
            return
        }

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

function Push-PowerShellScripts {
    [CmdletBinding()]
    param(
        [string]$Message = "Update PowerShell scripts",
        [switch]$WhatIf
    )

    Push-Location (Get-GeneMachineRoot PowershellScriptsDir 'D:\PowershellScripts')
    try {
        Ensure-OriginRemote -Url "https://github.com/genewebb/powershellscripts"
        Git-QuickPush -Message $Message -WhatIf:$WhatIf
    }
    finally {
        Pop-Location
    }
}

function Push-SqlScripts {
    [CmdletBinding()]
    param(
        [string]$Message = "Update SQL scripts",
        [switch]$WhatIf
    )

    Push-Location (Get-GeneMachineRoot SqlScriptsDir 'D:\SqlScripts')
    try {
        Ensure-OriginRemote -Url "https://github.com/genewebb/sqlscripts"
        Git-QuickPush -Message $Message -WhatIf:$WhatIf
    }
    finally {
        Pop-Location
    }
}

Export-ModuleMember -Function `
    Ensure-OriginRemote, Git-QuickPush, Git-TrustHere, `
    Push-PowerShellScripts, Push-SqlScripts
