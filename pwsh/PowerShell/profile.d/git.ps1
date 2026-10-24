# profile.d\git: commit, push and sync (gpush, pps, psql). Definitions only; loaded by the core profile.

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
