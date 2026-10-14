#requires -Version 7
<#
Context watch - WARN-ONLY Stop hook. Phase 2 of "Reducing Claude Code Prompt Cost".

Fires when the session's resident context crosses a threshold, and says so once
per cooldown window rather than once per turn. Silent below the threshold, which
is nearly always.

WHY THIS EXISTS
---------------
Every assistant turn re-reads the entire context. Measured average was ~225,000
tokens/turn across a 48h window, of which only ~38k is configuration floor - the
rest is accumulated conversation. Cost scales roughly with the SQUARE of session
length, so the single biggest lever is /clear at task boundaries. The status line
already shows ctx:N%, but a percentage of a 1M window reads as "plenty of room"
at exactly the point where per-turn cost has become the problem. This puts the
absolute number and the dollar figure in front of you instead.

THIS HOOK NEVER BLOCKS. It emits continue:true and always exits 0.

OUTPUT CHANNEL
--------------
systemMessage, NOT stdout. Two reasons:
  1. Stop-hook stdout with exit 0 is only visible in transcript mode (Ctrl-R) -
     the nudge would be invisible in normal use.
  2. systemMessage is shown to the user but does NOT enter the model's context.
     A hook whose purpose is cutting token cost must not itself add tokens on
     every turn. That constraint is the whole design.

Disable:  add 'context-watch' to ~\.claude\hooks-disabled.txt
          (or $env:CLAUDE_DISABLED_HOOKS before launch)

Tuning:   $NudgeThreshold / $HardThreshold / $CooldownMinutes below.
#>

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

# Thresholds come from the measurement: 120k is the target average context per
# turn, 250k is where a session has demonstrably become multi-task, 400k is the
# territory of the single worst measured session (~393k avg over 897 turns).
$NudgeThreshold  = 300000
$HardThreshold   = 375000
$CooldownMinutes = 30

. (Join-Path $PSScriptRoot 'lib\context-size.ps1')

try {
    if ([string]::IsNullOrWhiteSpace($HookJson)) { return }

    Save-ClaudeHookSample -Raw $HookJson -EventName 'Stop'

    $d = $HookJson | ConvertFrom-Json

    # Already inside a stop-hook continuation: do not pile on.
    if ($d.stop_hook_active) { return }

    $ctx = Get-ClaudeContextSize -Payload $d
    # 0 means "could not determine" - stay quiet rather than nag on a guess.
    if ($ctx -lt $NudgeThreshold) { return }

    $session = [string]$d.session_id
    if ([string]::IsNullOrWhiteSpace($session)) { $session = 'no-session' }
    $session = $session -replace '[^A-Za-z0-9._-]', '_'

    # Cooldown is per session, so a fresh session never inherits a suppression
    # from the one before it - which would silence the nudge exactly when a new
    # session is most likely to be a resumed monster.
    $stateDir = Join-Path $env:TEMP 'claude-context-watch'
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }
    $stateFile = Join-Path $stateDir "$session.json"

    if (Test-Path -LiteralPath $stateFile) {
        try {
            $last = (Get-Content -LiteralPath $stateFile -Raw | ConvertFrom-Json).lastNag
            if ((Get-Date) -lt ([datetime]$last).AddMinutes($CooldownMinutes)) { return }
        } catch { }   # unreadable state = treat as no cooldown
    }
    @{ lastNag = (Get-Date).ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath $stateFile -Encoding utf8

    $k       = [math]::Round($ctx / 1000)
    $perTurn = Format-ClaudeContextCost -Tokens $ctx
    $band    = if ($ctx -ge $HardThreshold) { 'CLEAR' } else { 'WARN' }

    $msg = "[$band] Context is ${k}k tokens - about `$$perTurn per turn, and every turn from here re-reads all of it. If you have moved on to a different task, /clear (or /compact to keep continuity). Silent again for $CooldownMinutes min."

    @{ continue = $true; systemMessage = $msg } | ConvertTo-Json -Compress -Depth 5

    [System.Console]::Error.WriteLine("[context-watch] $band ${k}k")
}
catch {
    # Advisory hook: any fault is silently ignored. Never affect the session.
}
