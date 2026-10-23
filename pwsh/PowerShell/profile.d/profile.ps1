# profile.d\profile: this PowerShell profile (sp, ep, rp). Definitions only; loaded by the core profile.

# -----------------------------
# Profile utilities
# -----------------------------
# sp and rp are built-in aliases (Set-ItemProperty, Remove-ItemProperty); an alias wins over a function of the same name.
Remove-Alias -Name sp -Force -ErrorAction SilentlyContinue

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
    Invoke-GeneProf setup show
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
    Invoke-GeneProf setup edit
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

