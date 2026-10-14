#requires -Version 7
<#
Rationalization watch - WARN-ONLY Stop hook.
Adapted from ECC's delivery-gate (MIT, (c) 2026 Affaan Mustafa)
https://github.com/affaan-m/ECC

Scans the tail of the session transcript for surface phrases that usually mean
thinking got cut short - "skip the tests for now", "pre-existing bug",
"didn't verify". Surfaces them as a note.

THIS HOOK NEVER BLOCKS. It cannot: it never emits a block decision, and it
always exits 0. Regex over prose false-positives, and a gate that stops a
session on a heuristic would be worse than the problem it detects. The value is
the nudge, not enforcement.

Deduped per pattern per session, so a phrase repeated across turns warns once.

Disable:  add 'rationalization-watch' to ~\.claude\hooks-disabled.txt
          (or $env:CLAUDE_DISABLED_HOOKS before launch)

Tuning: add or remove entries in $Patterns below. Prefer specific phrasings.
Generic ones like "should work" fire constantly and train you to ignore this.
#>

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

$TailLines = 80

# Each entry: a label for dedupe + a regex. Keep them specific.
$Patterns = @(
    @{ Id = 'skip-tests';    Rx = 'skip(?:ping)?\s+(?:the\s+|these\s+|those\s+)?(?:tests?|build|suite)\b[^.]{0,20}\bfor\s+now' }
    @{ Id = 'skip-tests-2';  Rx = '\b(?:not|won''t|will\s+not)\s+(?:bother\s+)?(?:running|writing)\s+(?:the\s+)?tests?\b' }
    @{ Id = 'pre-existing';  Rx = 'pre-?existing\s+(?:bug|issue|failure|problem|breakage)' }
    @{ Id = 'good-enough';   Rx = 'good\s+enough\s+for\s+now' }
    @{ Id = 'unverified';    Rx = '\b(?:did\s*n[o'']?t|have\s*n[o'']?t|hasn''t|couldn''t|could\s+not)\s+(?:actually\s+)?(?:verif(?:y|ied)|test(?:ed)?|run|ran|check(?:ed)?)\b' }
    @{ Id = 'assuming';      Rx = 'assum(?:e|ing|ed)\s+(?:it|this|that|they)\s+(?:works?|is\s+fine|are\s+fine|is\s+correct)' }
    @{ Id = 'leave-as-is';   Rx = 'leav(?:e|ing)\s+(?:it|this|that|them)\s+(?:as[-\s]is|for\s+later|alone\s+for\s+now)' }
    @{ Id = 'out-of-scope';  Rx = 'out\s+of\s+scope\s+for\s+(?:this|now|today)' }
    @{ Id = 'probably';      Rx = '\b(?:should|will|would)\s+probably\s+(?:work|be\s+fine|do)\b' }
)

try {
    if ([string]::IsNullOrWhiteSpace($HookJson)) { return }

    $d = $HookJson | ConvertFrom-Json

    # Already inside a stop-hook continuation: do not pile on.
    if ($d.stop_hook_active) { return }

    $tp = [string]$d.transcript_path
    if ([string]::IsNullOrWhiteSpace($tp) -or -not (Test-Path -LiteralPath $tp)) { return }

    $session = [string]$d.session_id
    if ([string]::IsNullOrWhiteSpace($session)) { $session = 'no-session' }
    $session = $session -replace '[^A-Za-z0-9._-]', '_'

    # Collect assistant prose from the tail of the transcript.
    $sb = [System.Text.StringBuilder]::new()
    foreach ($line in (Get-Content -LiteralPath $tp -Tail $TailLines -ErrorAction SilentlyContinue)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $o = $null
        try { $o = $line | ConvertFrom-Json } catch { continue }   # skip malformed lines
        if ($o.type -ne 'assistant') { continue }
        $content = $o.message.content
        if ($null -eq $content) { continue }
        if ($content -is [string]) { [void]$sb.AppendLine($content); continue }
        foreach ($part in $content) {
            if ($part.type -eq 'text' -and $part.text) { [void]$sb.AppendLine([string]$part.text) }
        }
    }
    $text = $sb.ToString()
    if ([string]::IsNullOrWhiteSpace($text)) { return }

    $stateDir = Join-Path $env:TEMP "claude-rationalization\$session"
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    $hits = @()
    foreach ($p in $Patterns) {
        $m = [regex]::Match($text, $p.Rx, 'IgnoreCase')
        if (-not $m.Success) { continue }

        $marker = Join-Path $stateDir "$($p.Id).seen"
        if (Test-Path -LiteralPath $marker) { continue }      # already warned this session
        Set-Content -LiteralPath $marker -Value $m.Value -Encoding utf8

        $hits += $m.Value.Trim()
    }

    if ($hits.Count -eq 0) { return }

    $list = ($hits | ForEach-Object { "  - `"$_`"" }) -join "`n"
    $msg  = @"
Rationalization watch (advisory, nothing is blocked):

$list

If any of those describe work that was actually left undone, say so plainly
rather than in passing - or finish it. If they were accurate and deliberate,
ignore this. Each phrase is flagged once per session.
"@

    # continue:true is explicit - this hook must never halt the session.
    @{ continue = $true; systemMessage = $msg } | ConvertTo-Json -Compress -Depth 5

    # Also to stderr, which shows in hook debug output regardless of whether
    # the host surfaces systemMessage.
    [System.Console]::Error.WriteLine("[rationalization-watch] " + ($hits -join ' | '))
}
catch {
    # Advisory hook: any fault is silently ignored. Never affect the session.
}
