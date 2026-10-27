# PreToolUse hook: destructive-path-guard
#
# Policy (Gene, 2026-09-04): non-destructive shell commands never prompt; destructive ones are
# fine INSIDE the repo / scratch roots; destructive commands that reach OUTSIDE those roots
# must still prompt. Permission rules cannot express "rm, but only under these paths"
# (ask beats allow by tier, globs cannot say "except"), so this hook re-imposes the prompt.
#
# Runs via hook-dispatch.ps1 -Id destructive-path-guard on every Bash/PowerShell call.
# Emits {"permissionDecision":"ask"} ONLY when BOTH hold:
#   1. a destructive verb sits in command position (rm, rmdir, rd, del, erase, Remove-Item, ri,
#      or find ... -delete), and
#   2. some path token in the command is absolute AND outside the trusted roots, or is a
#      root/home/UNC-style target (C:\, /, ~, $HOME, $env:USERPROFILE, %USERPROFILE%, \\server).
# Everything else falls through silently (exit 0, no output), so the deny tier, the ask tier,
# and the Bash(*)/PowerShell(*) allow floor behave exactly as configured.
#
# Heredoc and here-string bodies are data and are not checked.
#
# Relative paths are treated as inside the working directory (the shell starts in a trusted
# working dir). A `cd <outside path>` earlier in the same command IS caught, because every path
# token in the whole command is checked, not just the destructive verb's arguments.
#
# The roots, the token rules and the heredoc stripping live in lib\PathScope.ps1, shared with scoped-autoapprove.ps1
# (the PermissionRequest hook that answers yes INSIDE the same roots), so the two hooks draw one line.

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

try {
    . (Join-Path $PSScriptRoot 'lib\PathScope.ps1')
    $d   = $HookJson | ConvertFrom-Json
    $cmd = [string]$d.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return }

    $cmd = Remove-HereDocBodies $cmd

    # 1. Destructive verb in command position (start, after a separator/subshell/loop keyword,
    #    or after a wrapper such as sudo/xargs/find -exec/cmd /c).
    #    The patterns live in lib\PathScope.ps1 (Test-DestructiveCommand), which also reads a container script by them.
    if (-not (Test-DestructiveCommand $cmd)) { return }

    # 2. Any path token outside the trusted roots.
    $roots    = Get-ScopeRoots $PSScriptRoot
    # Bash reads '\"' inside a double-quoted string as a quote, not its end; PowerShell does not.
    $offender = Find-OutsideScopeToken (Get-CommandPathTokens $cmd -Posix:([string]$d.tool_name -eq 'Bash')) $roots

    if ($offender) {
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'ask'
                permissionDecisionReason = "destructive-path-guard: destructive command targets a path outside the repo/scratch roots ($offender). Trusted roots: $((@($roots) | ForEach-Object { $_.TrimEnd('\') }) -join ', '). Confirm before it runs."
            }
        } | ConvertTo-Json -Compress -Depth 5
    }
}
catch {}
