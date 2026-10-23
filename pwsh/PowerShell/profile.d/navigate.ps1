# profile.d\navigate: go to a folder (paths come from this machine's profile). Definitions only; loaded by the core profile.

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

function csm {
    [CmdletBinding()]
    param([Alias('h','help')][switch]$ShowHelp)

    if (Test-HelpRequested -ShowHelp:$ShowHelp) {
        Write-Usage "csm [-h|--help]" @("Navigate to $($global:GeneMachine.SpeedyRepo) (the Speedy repo, speedmerchants)")
        return
    }

    $path = $global:GeneMachine.SpeedyRepo
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

