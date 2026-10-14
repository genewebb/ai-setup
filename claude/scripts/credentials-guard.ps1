# PreToolUse hook: credentials-guard
#
# The single directory the agent must never read: the Obsidian vault's "00 Credentials" folder
# ({VaultWorkRoot}\00 Credentials\, and any stale copy left in an older vault location).
#
# Why a hook and not a Read() deny rule: any configured Read() deny rule makes Claude Code prompt on
# every `cd <dir> && git ...` compound ("would search a directory that cannot be determined here, and a
# Read() deny rule is configured"). This hook gives the same protection with zero Read() deny rules.
#
# Runs via hook-dispatch.ps1 -Id credentials-guard; matcher Read|Grep|Glob|Edit|Write|NotebookEdit|Bash|PowerShell.
# Denies when the tool's path/command text names the folder. Folder-name match is deliberate: it covers
# both drive letters, both slash styles, UNC, URL-encoded and underscore spellings.

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

try {
    $d  = $HookJson | ConvertFrom-Json
    $ti = $d.tool_input
    if (-not $ti) { return }

    $text = @($ti.file_path, $ti.path, $ti.notebook_path, $ti.command) | Where-Object { $_ } | Out-String

    if ($text -match '(?i)00(?:[ _]|%20)Credentials') {
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'deny'
                permissionDecisionReason = 'credentials-guard: the vault "00 Credentials" folder is off-limits to the agent (read, list, search, edit). Ask the user for anything you need from it.'
            }
        } | ConvertTo-Json -Compress -Depth 5
    }
}
catch {}
