#requires -Version 7
<#
Shared helper: how big is the session's resident context right now?

Dot-sourced by context-watch.ps1 (Stop) and session-context-nudge.ps1
(SessionStart). Both need the same number and neither should guess at it.

Two functions:

    Get-ClaudeContextSize -Payload <pscustomobject>   -> [int] tokens, or 0
    Save-ClaudeHookSample -Raw <string> -Event <name>  -> one-shot payload dump

WHY A FALLBACK EXISTS
---------------------
The status line receives context_window.* directly on stdin, which is O(1) and
cannot drift from the harness's own accounting. It is NOT confirmed that Stop
and SessionStart payloads carry the same block - the documented common fields
are session_id / transcript_path / cwd / hook_event_name, and Stop adds
stop_hook_active. So: prefer stdin when the block is present, otherwise
reconstruct from the transcript tail. Whichever path fires, the caller gets a
number and the hook never no-ops just because a field was assumed.

Run Save-ClaudeHookSample once per event to find out which path is live, then
read {ScratchRoot}\claude-hook-payload-<event>.json. Delete that file to re-capture.
#>

function Save-ClaudeHookSample {
    <#
    One-shot raw payload capture. Writes only if the sample file is absent, so
    it self-disables after the first fire and costs one stat() thereafter.
    Deliberately permanent rather than throwaway: the "dump the payload before
    writing logic against guessed field names" rule is easier to follow when
    the dump is already wired.
    #>
    param(
        [string] $Raw,
        [string] $EventName
    )
    try {
        if ([string]::IsNullOrWhiteSpace($Raw)) { return }
        # ScratchRoot: the AI_SCRATCHROOT env the settings file sets, else the machine profile.
        $dir = $env:AI_SCRATCHROOT
        if (-not $dir) {
            $lib = @((Join-Path $PSScriptRoot '..\..\lib\MachineConfig.psm1'), (Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1')) |
                Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
            if (-not $lib) { return }
            Import-Module $lib -Force
            $dir = Get-AIPath -Name ScratchRoot -Optional
        }
        if (-not $dir) { return }
        if (-not (Test-Path -LiteralPath $dir)) { return }   # never create it
        $f = Join-Path $dir "claude-hook-payload-$EventName.json"
        if (Test-Path -LiteralPath $f) { return }
        Set-Content -LiteralPath $f -Value $Raw -Encoding utf8
    } catch { }
}

function Get-ClaudeContextSize {
    <#
    Returns resident context in tokens for the most recent assistant turn.
    Returns 0 when it cannot be determined - callers must treat 0 as "unknown,
    stay silent", never as "small".
    #>
    param([Parameter(Mandatory)] $Payload)

    # --- Path 1: straight off stdin. O(1), authoritative, no file I/O. --------
    $cw = $Payload.context_window
    if ($cw) {
        $n = [int]$cw.total_input_tokens + [int]$cw.total_output_tokens
        if ($n -gt 0) { return $n }
    }

    # --- Path 2: reconstruct from the transcript tail. -----------------------
    # Last assistant message carrying a usage block wins. input + both cache
    # counters is the full prompt the model just re-read, which is exactly the
    # quantity that gets billed again on the next turn.
    $tp = [string]$Payload.transcript_path
    if ([string]::IsNullOrWhiteSpace($tp) -or -not (Test-Path -LiteralPath $tp)) { return 0 }

    $ctx = 0
    try {
        # 300 lines is generous: tool_result lines can run long stretches
        # between assistant turns, and a tail read is cheap either way.
        foreach ($line in (Get-Content -LiteralPath $tp -Tail 300 -ErrorAction SilentlyContinue)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $o = $null
            try { $o = $line | ConvertFrom-Json } catch { continue }
            if ($o.type -ne 'assistant') { continue }
            $u = $o.message.usage
            if (-not $u) { continue }
            $ctx = [int]$u.input_tokens +
                   [int]$u.cache_read_input_tokens +
                   [int]$u.cache_creation_input_tokens
        }
    } catch { return 0 }

    return $ctx
}

function Format-ClaudeContextCost {
    <# Per-turn cache-read cost at Opus 5 rates ($0.50 / MTok cache read). #>
    param([int] $Tokens)
    '{0:N2}' -f ($Tokens * 0.5 / 1000000)
}
