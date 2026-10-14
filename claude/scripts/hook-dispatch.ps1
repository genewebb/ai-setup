#requires -Version 7
<#
Single-process hook dispatcher with a kill switch.

    pwsh -NoProfile -File hook-dispatch.ps1 -Id gateguard

Reads the Claude Code hook payload from stdin once, then dot-sources
<scripts>\<Id>.ps1 with $HookJson already populated, so the target does NOT
spawn a second pwsh. Cold start is ~200-400ms on Windows and this runs on
every matched tool call, so the second process is worth avoiding.

Two ways to disable a hook. Both match whole tokens, so 'gateguard-extra' does
NOT disable 'gateguard'.

1. Environment variable - set BEFORE launching Claude Code:

       $env:CLAUDE_DISABLED_HOOKS = 'gateguard,some-other-hook'

2. Disable file - works MID-SESSION, one id per line, '#' starts a comment:

       ~\.claude\hooks-disabled.txt

   The env var cannot be changed mid-session: each tool call is its own
   process, and the hook inherits the Claude Code process environment, which
   a tool call cannot mutate. The file is the only switch that works while a
   session is running - which is exactly when you need it.

   Toggle it with:
       Add-Content ~\.claude\hooks-disabled.txt 'gateguard'      # off
       Set-Content ~\.claude\hooks-disabled.txt ''               # all back on

Contract for target scripts - open with:

    if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

so they also work when piped directly (which is how the test harness drives
them, and how the pre-existing hooks already behave).
#>
param(
    [Parameter(Mandatory)] [string] $Id
)

$ErrorActionPreference = 'Stop'

try {
    # 1. Launch-time switch.
    $disabled = $env:CLAUDE_DISABLED_HOOKS
    if ($disabled) {
        $tokens = $disabled -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
        if ($tokens -contains $Id) { exit 0 }
    }

    # 2. Mid-session switch. Also accepts commas so either style works.
    $offFile = Join-Path $PSScriptRoot '..\hooks-disabled.txt'
    if (Test-Path -LiteralPath $offFile) {
        $tokens = Get-Content -LiteralPath $offFile |
            ForEach-Object { ($_ -split '#')[0] } |
            ForEach-Object { $_ -split ',' } |
            ForEach-Object { $_.Trim() } |
            Where-Object { $_ }
        if ($tokens -contains $Id) { exit 0 }
    }

    $target = Join-Path $PSScriptRoot "$Id.ps1"
    if (-not (Test-Path -LiteralPath $target)) { exit 0 }

    $HookJson = [System.Console]::In.ReadToEnd()
    . $target
}
catch {
    # A broken hook must never block the user's tool call. Emit nothing on
    # stdout (which would be parsed as a decision); stderr is visible in hook
    # debug output without affecting the outcome.
    [System.Console]::Error.WriteLine("[hook-dispatch:$Id] $_")
}
exit 0
