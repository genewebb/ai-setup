#requires -Version 7
<#
GateGuard - fact-forcing PreToolUse gate.
Adapted from ECC (MIT, (c) 2026 Affaan Mustafa) - https://github.com/affaan-m/ECC

Blocks the FIRST Edit/Write/MultiEdit of each file per session and demands
concrete investigation before allowing it. Three stages: DENY -> FORCE -> ALLOW.

The premise: asking a model to self-evaluate ("are you sure?") is worthless -
the answer is always yes. Demanding a specific fact ("list every file that
references this") compels an actual Grep, and the resulting context is what
changes the output.

The marker is written at DENY time, so presenting the facts and re-issuing the
same edit always succeeds. The gate fires once per file per session.

Disable for a session:
    $env:CLAUDE_DISABLED_HOOKS = 'gateguard'

Denial messages are capped (default 3 full blocks per session, then a single
condensed line). Per ECC issue #2142, repeated near-identical denial blocks
accumulate in the context window and amplify model repetition loops.
#>

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

$FullDenialCap = 3

# Paths never worth gating: generated output, dependencies, VCS internals,
# test artefacts, scratch space, and the harness's own config.
$IgnorePatterns = @(
    '[/\\](obj|bin)[/\\]'
    '[/\\]node_modules[/\\]'
    '[/\\]\.git[/\\]'
    '[/\\]TestResults[/\\]'
    '[/\\]\.vs[/\\]'
    '[/\\]packages[/\\]'
    '[/\\]scratchpad[/\\]'
    '[/\\]AppData[/\\]Local[/\\]Temp[/\\]'
    '[/\\]\.claude[/\\]'
    '\.(trx|dll|exe|pdb|nupkg|lock)$'
    '\.min\.(js|css)$'
    '\.(g|Designer)\.cs$'
    # Documentation folders explicitly whitelisted - free to edit without fact-forcing prompt.
    '[/\\]TestAuto\.Web[/\\]Documentation[/\\]'
    '[/\\]CrewChief\.Web[/\\]Documentation[/\\]'
    # Secrets template folders - contain sample/placeholder values only, no real secrets.
    '[/\\]TestAuto\.Web[/\\]SecretsTemplate[/\\]'
)

function Write-Deny {
    param([string]$Reason)
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = $Reason
        }
    } | ConvertTo-Json -Compress -Depth 5
}

try {
    if ([string]::IsNullOrWhiteSpace($HookJson)) { return }

    $d = $HookJson | ConvertFrom-Json
    $tool = [string]$d.tool_name
    if ($tool -notin @('Edit', 'Write', 'MultiEdit')) { return }

    $filePath = [string]$d.tool_input.file_path
    if ([string]::IsNullOrWhiteSpace($filePath)) { return }

    foreach ($p in $IgnorePatterns) {
        if ($filePath -match $p) { return }
    }

    $session = [string]$d.session_id
    if ([string]::IsNullOrWhiteSpace($session)) { $session = 'no-session' }
    # session_id is external input; keep it filesystem-safe regardless.
    $session = $session -replace '[^A-Za-z0-9._-]', '_'

    $stateDir = Join-Path $env:TEMP "claude-gateguard\$session"
    if (-not (Test-Path -LiteralPath $stateDir)) {
        New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    }

    # example-path: normalise so C:\A\B.cs and c:/a/b.cs resolve to one marker.
    $norm = $filePath.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
    $sha  = [System.Security.Cryptography.SHA1]::Create()
    try {
        $hash = [System.BitConverter]::ToString(
            $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($norm))
        ).Replace('-', '')
    }
    finally { $sha.Dispose() }

    $marker = Join-Path $stateDir "$hash.marker"
    if (Test-Path -LiteralPath $marker) { return }   # already gated -> ALLOW

    # Mark BEFORE denying, so the immediate retry passes.
    Set-Content -LiteralPath $marker -Value $filePath -Encoding utf8

    $countFile = Join-Path $stateDir 'denials.count'
    $count = 0
    if (Test-Path -LiteralPath $countFile) {
        $raw = (Get-Content -LiteralPath $countFile -Raw).Trim()
        [void][int]::TryParse($raw, [ref]$count)
    }
    $count++
    Set-Content -LiteralPath $countFile -Value $count -Encoding utf8

    if ($count -gt $FullDenialCap) {
        Write-Deny ("GateGuard (denial {0}, condensed): state the callers, the members affected, and the user's instruction for '{1}', then retry the same operation. Disable with `$env:CLAUDE_DISABLED_HOOKS='gateguard'." -f $count, $filePath)
        return
    }

    # Show the parent folder as well as the file name. Bare leaf names are
    # useless where a convention repeats them - 140 skills all named SKILL.md,
    # every Blazor component split into .razor / .razor.cs, etc.
    $leaf   = Split-Path -Leaf $filePath
    $parent = Split-Path -Leaf (Split-Path -Parent $filePath)
    if ($parent) { $leaf = "$parent\$leaf" }

    if ($tool -eq 'Write') {
        $reason = @"
GateGuard: before creating '$leaf', present these facts, then retry the same Write.

1. Name the file(s) and line(s) that will call into this new file.
2. Confirm no existing file already serves the same purpose (search the tree with Glob/Grep).
3. If it reads or writes data, show the real field names, structure, and date/number formats (redacted or synthetic values only).
4. Quote the user's current instruction verbatim.

This gate fires once per file per session. Presenting the facts and retrying will succeed.
Disable for this session with: `$env:CLAUDE_DISABLED_HOOKS='gateguard'
"@
    }
    else {
        $reason = @"
GateGuard: before editing '$leaf', present these facts, then retry the same edit.

1. List ALL files that reference or import this file (Glob/Grep the tree - do not guess).
2. List the public members this change affects.
3. If it reads or writes data, show the real field names, structure, and date/number formats (redacted or synthetic values only).
4. Quote the user's current instruction verbatim.

This gate fires once per file per session. Presenting the facts and retrying will succeed.
Disable for this session with: `$env:CLAUDE_DISABLED_HOOKS='gateguard'
"@
    }

    Write-Deny $reason
}
catch {
    # Any fault must fall through to the normal permission flow, never block.
}
