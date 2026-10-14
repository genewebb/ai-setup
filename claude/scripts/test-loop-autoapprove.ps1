# PreToolUse hook: scoped auto-approve for the speed-merchants test-fix loop.
#
# Approves ONLY the loop's known-safe maintenance commands that otherwise sit in
# the global `ask` list (taskkill/kill/mkdir) or are unlisted (Stop-Process/Remove-Item),
# so the skill-fix-integration-tests loop runs unattended WITHOUT a blanket bypass.
#
# Anything not matched here falls through to the normal permission flow (exit 0, no output),
# so the global ask/deny safety net stays fully intact for every other command.
#
# Safety guards:
#   - Each pattern requires the loop-specific target (testhost/vstest.console / TestResults / tmp).
#   - Commands containing `;` or a newline are NEVER auto-approved (blocks chained-statement
#     example-path: injection like "Stop-Process testhost; Remove-Item C:\important").

$json = [System.Console]::In.ReadToEnd()
try {
    $d   = $json | ConvertFrom-Json
    $cmd = [string]$d.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return }

    # Guard: refuse to approve any chained/compound command. Every approved pattern below is a
    # single simple statement, so the presence of a statement separator, pipe, call operator,
    # backtick continuation, or subexpression means something else is riding along — fall through.
    if ($cmd -match '[;|&`]' -or $cmd -match "`n" -or $cmd -match '\$\(') { return }

    $trimmed = $cmd.Trim()

    # Loop maintenance commands, anchored, each requiring its loop-specific target.
    $approved = @(
        # Kill stale test hosts that lock TestAuto.Web.dll (never matches the running WebUI app).
        '^taskkill\b.*(testhost|vstest\.console)'
        '^p?kill\b.*(testhost|vstest)'
        '^Stop-Process\b.*(testhost|vstest)'
        # Ensure the TRX output folder exists.
        '^(mkdir|New-Item)\b.*TestResults'
        # Clean the loop''s own temp TRX/console scratch files (a \tmp\ or /tmp/ path segment only).
        '^(Remove-Item|rm)\b.*[/\\]tmp[/\\]'
        # Inter-step pause used by the pre-flight kill step.
        '^Start-Sleep\b'
    )

    foreach ($p in $approved) {
        if ($trimmed -match $p) {
            @{
                hookSpecificOutput = @{
                    hookEventName            = 'PreToolUse'
                    permissionDecision       = 'allow'
                    permissionDecisionReason = 'Scoped test-fix loop maintenance command (test-loop-autoapprove hook).'
                }
            } | ConvertTo-Json -Compress -Depth 5
            return
        }
    }
}
catch {}
