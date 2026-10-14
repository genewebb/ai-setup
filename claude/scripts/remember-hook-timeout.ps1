#requires -Version 7
<#
remember-hook-timeout - SessionStart self-heal for the remember plugin's
SessionEnd hook timeout.

WHY THIS EXISTS (verified against Claude Code 2.1.263 on 2026-09-06)
--------------------------------------------------------------------
SessionEnd hooks are run with a hard-coded 1500 ms default per-hook timeout
(`timeoutMs: 1500` in the SessionEnd runner). The only override is the hook's
own `timeout` field. The remember plugin's hooks.json declares none, and its
session-end-hook.sh needs ~2.5-3 s of bash startup on Windows before it
backgrounds the flush, so every exit prints:

    SessionEnd hook [bash "${CLAUDE_PLUGIN_ROOT}/scripts/session-end-hook.sh"] failed: Hook cancelled

A user-settings SessionEnd hook with a large `timeout` raises the OUTER abort
budget (the max over settings hooks, floor 1.5 s, cap 60 s) but does NOT touch
the per-hook default, and settings hooks cannot override a plugin hook (hook
dedup keys on pluginRoot + command). So the plugin's own hooks.json must carry
`timeout`. That file lives in the versioned plugin cache and is replaced on
every plugin update, which is what this hook repairs: it re-applies the
timeout to whatever install path installed_plugins.json currently points at.

Both pieces are required - probed with `claude -p` from a scratch dir:
  extender only            -> Hook cancelled
  plugin timeout only      -> Hook cancelled
  extender + plugin timeout -> clean exit

OUTPUT CHANNEL
--------------
Nothing on stdout, ever: a SessionStart hook's stdout is injected into the
model's context. Diagnostics go to stderr only.

TESTING
-------
Set CLAUDE_PLUGINS_DIR to point at a fixture plugins directory (containing
installed_plugins.json) instead of ~\.claude\plugins.

Disable:  add 'remember-hook-timeout' to ~\.claude\hooks-disabled.txt
          (or $env:CLAUDE_DISABLED_HOOKS before launch)
#>

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

$MinTimeoutSeconds = 15
$HookScriptName    = 'session-end-hook.sh'

try {
    $pluginsDir = if ($env:CLAUDE_PLUGINS_DIR) { $env:CLAUDE_PLUGINS_DIR }
                  else { Join-Path $env:USERPROFILE '.claude\plugins' }
    $installed = Join-Path $pluginsDir 'installed_plugins.json'
    if (-not (Test-Path -LiteralPath $installed)) { return }

    $reg = Get-Content -LiteralPath $installed -Raw | ConvertFrom-Json
    if (-not $reg.plugins) { return }

    $installPaths = @()
    foreach ($p in $reg.plugins.PSObject.Properties) {
        if ($p.Name -notlike 'remember@*') { continue }
        foreach ($entry in @($p.Value)) {
            if ($entry.installPath) { $installPaths += [string]$entry.installPath }
        }
    }

    foreach ($root in ($installPaths | Select-Object -Unique)) {
        $hooksFile = Join-Path $root 'hooks\hooks.json'
        if (-not (Test-Path -LiteralPath $hooksFile)) { continue }

        $doc = Get-Content -LiteralPath $hooksFile -Raw | ConvertFrom-Json
        $groups = $doc.hooks.SessionEnd
        if (-not $groups) { continue }

        $changed = $false
        foreach ($group in @($groups)) {
            foreach ($hook in @($group.hooks)) {
                if ($hook.type -ne 'command') { continue }
                if ([string]$hook.command -notlike "*$HookScriptName*") { continue }

                $current = 0
                if ($hook.PSObject.Properties['timeout']) { $current = [int]$hook.timeout }
                if ($current -ge $MinTimeoutSeconds) { continue }

                if ($hook.PSObject.Properties['timeout']) { $hook.timeout = $MinTimeoutSeconds }
                else { $hook | Add-Member -NotePropertyName timeout -NotePropertyValue $MinTimeoutSeconds }
                $changed = $true
            }
        }

        if ($changed) {
            $json = $doc | ConvertTo-Json -Depth 20
            Set-Content -LiteralPath $hooksFile -Value $json -Encoding utf8NoBOM
            [System.Console]::Error.WriteLine("[remember-hook-timeout] patched SessionEnd timeout=$MinTimeoutSeconds in $hooksFile")
        }
    }
}
catch {
    # Advisory hook: never affect the session. Stderr only.
    [System.Console]::Error.WriteLine("[remember-hook-timeout] $_")
}
