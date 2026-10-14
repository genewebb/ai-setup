#requires -Version 7
<#
Session context nudge - WARN-ONLY SessionStart hook. Phase 5 of
"Reducing Claude Code Prompt Cost".

Covers the most common expensive failure mode: resuming yesterday's 900-turn
session instead of starting clean. Fires ONCE, on resume only, when the
transcript being picked back up is already over threshold.

SOURCE FILTERING
----------------
SessionStart carries a 'source' field: startup | resume | clear | compact.
Only 'resume' is actionable:
  - startup : brand new session, context is the config floor by definition
  - clear   : you just did the thing this hook would ask for
  - compact : context was just reduced on purpose
Nagging on any of those three would be noise, and noise trains you to ignore
the one case that matters.

OUTPUT CHANNEL
--------------
systemMessage, NOT stdout and NOT hookSpecificOutput.additionalContext.

This is the important design point. A SessionStart hook's stdout IS injected
into the model's context - that is how the remember plugin does its job. For a
hook that exists to REDUCE token cost, injecting context would be
self-defeating: it would add tokens to the very session it is complaining is
too big, and those tokens would then be re-read on every subsequent turn.
systemMessage is displayed to the user at zero token cost. Use it.

Note this event already has the remember plugin registered on it. Both run;
ordering is not guaranteed. Keeping this one at zero injected tokens means it
cannot compound with whatever remember emits.

Disable:  add 'session-context-nudge' to ~\.claude\hooks-disabled.txt
          (or $env:CLAUDE_DISABLED_HOOKS before launch)
#>

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

$ResumeThreshold = 250000

. (Join-Path $PSScriptRoot 'lib\context-size.ps1')

try {
    if ([string]::IsNullOrWhiteSpace($HookJson)) { return }

    Save-ClaudeHookSample -Raw $HookJson -EventName 'SessionStart'

    $d = $HookJson | ConvertFrom-Json

    $source = [string]$d.source
    if ($source -and $source -ne 'resume') { return }

    $ctx = Get-ClaudeContextSize -Payload $d
    if ($ctx -lt $ResumeThreshold) { return }

    $k       = [math]::Round($ctx / 1000)
    $perTurn = Format-ClaudeContextCost -Tokens $ctx

    $msg = "[RESUMED] This session is already ${k}k tokens - roughly `$$perTurn per turn before you type anything. If you are starting a different task, a fresh session is cheaper than continuing this one."

    @{ continue = $true; systemMessage = $msg } | ConvertTo-Json -Compress -Depth 5

    [System.Console]::Error.WriteLine("[session-context-nudge] resumed at ${k}k")
}
catch {
    # Advisory hook: any fault is silently ignored. Never affect the session.
}
