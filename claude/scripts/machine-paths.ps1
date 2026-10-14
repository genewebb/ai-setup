# SessionStart hook: machine-paths (spec D6, 4.4, R1).
#
# Puts this machine's resolved paths into Claude's context once per session, so skill prose that says
# {WorktreesRoot} or {ScratchRoot} resolves. It never applies anything. It also warns (to the user, zero tokens)
# when the session was started without the ai launcher, or on a revision older than the installed one.
# Runs via hook-dispatch.ps1 -Id machine-paths.

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

try {
    $libs = @((Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1'), (Join-Path $PSScriptRoot '..\..\lib\MachineConfig.psm1'))
    $lib = $libs | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    Import-Module $lib -Force -DisableNameChecking
    $prof = Get-AIMachineProfile
    $cfg = @(Get-AIConfig)

    $show = 'AIWorkRoot', 'ClaudeHome', 'ReposRoot', 'SpeedyRepo', 'SpeedMerchantsRepo', 'WorktreesRoot', 'ScratchRoot',
    'StatusPageDir', 'VaultWorkRoot', 'VaultPersonalRoot', 'VaultDocsRoot', 'DocumentationDir', 'PowershellScriptsDir', 'SecretsDir', 'ArchiveRoot'
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("Machine paths ($env:COMPUTERNAME, from $($prof.Path)). {Key} in a skill means the value below; if a key is missing, run Get-AIConfig.")
    foreach ($k in $show) {
        $c = $cfg | Where-Object Key -eq $k
        if (-not $c) { continue }
        $v = if ($c.Value) { $c.Value } else { '(blank: not on this machine)' }
        $loc = if ($c.Value -and $c.Location -notin 'value', 'blank') { $c.Location } else { '' }
        $lines.Add(('  {0,-20} {1}  {2}' -f $k, $v, $loc).TrimEnd())
    }
    $gp = @($prof.GitPolicy | ForEach-Object { "$($_.Repo) commit=$($_.Commit) push=$($_.Push) worktrees=$($_.Worktrees)" })
    $lines.Add('Git policy (git-guard enforces; a repo not listed gets no commit, push or worktree): ' + $(if ($gp) { $gp -join '; ' } else { 'none' }))

    $warn = [System.Collections.Generic.List[string]]::new()
    foreach ($c in $cfg | Where-Object { $_.Location -in 'share (disconnected)', 'missing' }) { $warn.Add("$($c.Key) unavailable ($($c.Location)): $($c.Value)") }
    $statePath = Join-Path $prof.Keys['ClaudeHome'] 'machine-config.state.json'
    if (Test-Path -LiteralPath $statePath) {
        $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $lines.Add("Installed AI runtime revision $($st.identity.Substring(0,12)) ($($st.installedAt)).")
        if (-not $env:AI_LAUNCH_REVISION) { $warn.Add("This session was not started with 'ai'; profile or corpus changes since the last apply are not active. Start Claude with 'ai'.") }
        elseif ($env:AI_LAUNCH_REVISION -ne $st.identity) { $warn.Add("This session runs revision $($env:AI_LAUNCH_REVISION.Substring(0,12)); revision $($st.identity.Substring(0,12)) is installed. Restart with 'ai'.") }
    }
    else { $warn.Add('No machine-config install record; run Install-AIMachine.ps1.') }

    $out = @{ hookSpecificOutput = @{ hookEventName = 'SessionStart'; additionalContext = ($lines -join "`n") } }
    if ($warn.Count) { $out.systemMessage = 'machine-config: ' + ($warn -join ' | ') }
    $out | ConvertTo-Json -Compress -Depth 5
}
catch {
    @{ systemMessage = "machine-config: could not read the machine profile ($_). Paths in skills will not resolve; run Install-AIMachine.ps1 -Check." } | ConvertTo-Json -Compress
}
