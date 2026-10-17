# PermissionRequest hook: scoped-autoapprove
#
# Policy (Gene, 2026-10-17): "All agents should be able to do whatever is needed in the scratch or repo areas, as
# those are either temporary or under git control." Unattended stream units (builders above all) kept stopping on
# permission prompts nobody could answer: a Monitor loop polling a grader by PID, a redirect into .streams\logs, a
# command with a variable in it. The owner's pre-approval never took, for two reasons the permissions docs state:
# auto mode drops broad allow rules such as Bash(*), and a matching ask rule (kill:*, taskkill:*) still prompts even
# when a PreToolUse hook answered allow. The PermissionRequest event is different: it fires at the moment the dialog
# would open, after every rule and the auto-mode classifier have had their say, and in a headless `-p` run with
# `--permission-prompts none` it is the only thing that can turn the automatic denial into a yes.
#
# Runs via hook-dispatch.ps1 -Id scoped-autoapprove on every prompt for a command tool (Bash, PowerShell, Monitor) or
# a file tool (Read, Edit, Write, MultiEdit, NotebookEdit, Glob, Grep). It answers ALLOW only when ALL hold:
#   1. the session's working directory is inside the trusted roots (lib\PathScope.ps1 -ForApproval: ReposRoot,
#      WorktreesRoot, ScratchRoot, the user's temp, and EVERY '## Claude access' row of the machine profile without a
#      deny: the vaults, the deploy and script folders, ~\.claude. Owner 2026-10-17: places the agents routinely read,
#      write or delete outside the repo and scratch areas are treated the same; the aim is that they control what they
#      read, write and delete. destructive-path-guard keeps its narrower delete-right roots for the prompt it raises);
#   2. every absolute path the call names is inside those roots (heredoc and here-string bodies are data; relative
#      paths resolve under the working directory); and
#   3. the command does not act by NAME or on the machine as a whole: pkill/killall, taskkill /IM or /FI,
#      Stop-Process -Name, Get-Process | Stop-Process, docker rm/stop/prune/down/push, netsh, icacls, takeown, sudo,
#      obsidian, schtasks, reg, net user, shutdown. Those keep their prompt: a path rule cannot vouch for them, and on
#      the shared stream host a kill by name takes every other unit's graders too (kit item IN-20261009021255-91b2).
# Anything else writes nothing, so the prompt opens exactly as before. A deny rule, or a deny from git-guard or
# credentials-guard, has already blocked the call before any prompt; this hook cannot and does not override those.
#
# Every yes is logged, one line each:
#   {ScratchRoot}\ai-config-work\autoapprove\<yyyyMMdd>.log           (every session on this machine), and
#   <STREAM_UNIT_OUT>.approvals.log                                  (inside a stream runner unit; the runner reports the count).
# CLAUDE_AUTOAPPROVE_LOG_DIR points the first log elsewhere (the tests). Switch the hook off like any other:
# $env:CLAUDE_DISABLED_HOOKS = 'scoped-autoapprove', or a line in ~\.claude\hooks-disabled.txt (mid-session).

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

try {
    . (Join-Path $PSScriptRoot 'lib\PathScope.ps1')
    $d = $HookJson | ConvertFrom-Json
    $tool = [string]$d.tool_name
    $commandTools = @('Bash', 'PowerShell', 'Monitor')
    $fileTools = @('Read', 'Edit', 'Write', 'MultiEdit', 'NotebookEdit', 'Glob', 'Grep')
    if ($tool -notin $commandTools -and $tool -notin $fileTools) { return }

    # -ForApproval: every folder the profile lets the agents read, edit or delete counts (owner, 2026-10-17: "if there
    # are things outside the repo or the scratch area that they routinely write to they should be treated the same;
    # the goal is that they have control over things they write and read and delete").
    $roots = Get-ScopeRoots $PSScriptRoot -ForApproval

    # 1. The working directory. No cwd in the payload = no proof it is trusted (fail closed).
    $cwd = [string]$d.cwd
    if ([string]::IsNullOrWhiteSpace($cwd)) { return }
    if (Find-OutsideScopeToken @($cwd) $roots) { return }
    $n = ConvertTo-ScopePath $cwd
    $inside = $false; foreach ($r in $roots) { if ($n.StartsWith($r)) { $inside = $true; break } }
    if (-not $inside) { return }

    $what = ''
    if ($tool -in $commandTools) {
        $cmd = [string]$d.tool_input.command
        if ([string]::IsNullOrWhiteSpace($cmd)) { return }
        $cmd = Remove-HereDocBodies $cmd
        # 3. Acts by name or machine-wide: the prompt stays. Verbs are matched in command position (start, after a
        #    separator or subshell, after a loop keyword or a wrapper), the way destructive-path-guard finds its verbs.
        $lead = '(?im)(?:^|[;&|(]\s*|\b(?:do|then|else|sudo|gsudo|nohup|xargs(?:\s+-\S+)*|timeout\s+\S+|nice(?:\s+-n\s+\d+)?|cmd(?:\.exe)?\s+/[cCkK])\s+)'
        # One double-quoted string per pattern (${lead} spliced in): an array element written as "$lead" + '...' was
        # read as TWO elements, and the bare prefix then matched every command.
        $never = @(
            "${lead}(?:pkill|killall|sudo|gsudo|netsh|icacls|takeown|obsidian|schtasks|reg|reg\.exe|regedit|regini|shutdown|wmic|Stop-Computer|Restart-Computer|New-NetFirewallRule|Set-NetFirewallRule|Remove-NetFirewallRule)(?=\s|`$)",
            "${lead}(?:net|net\.exe)\s+(?:user|localgroup)\b",
            "${lead}(?:docker|docker-compose|podman)\s+(?:compose\s+)?(?:down|rm|rmi|kill|stop|push|prune|system|volume|network|image|container|builder)\b",
            "${lead}taskkill(?:\.exe)?\b[^;&|]*\s/(?:im|fi)\b",
            '(?i)\b(?:Stop-Process|spps|kill)\b[^;&|]*\s-(?:Name|ProcessName)\b',
            '(?i)\bpgrep\b[^;&]*\|\s*xargs\s+kill\b',
            '(?i)\bkill\b[^;&|]*\$\(\s*pgrep\b',
            '(?i)Win32_Process[\s\S]*\bTerminate\b'
        )
        foreach ($rx in $never) { if ($cmd -match $rx) { return } }
        foreach ($m in [regex]::Matches($cmd, '(?i)\b(?:Get-Process|gps|ps)\b([^|;&]*)(\|[^;&]*?)?\|\s*(?:Stop-Process|spps|kill)\b')) {
            if ($m.Groups[1].Value -notmatch '(?i)\s-Id\b') { return }
        }
        # 2. Every absolute path inside the roots.
        if (Find-OutsideScopeToken (Get-CommandPathTokens $cmd) $roots) { return }
        $what = $cmd
    }
    else {
        $paths = @()
        foreach ($k in 'file_path', 'path', 'notebook_path') { if ($d.tool_input.PSObject.Properties[$k] -and $d.tool_input.$k) { $paths += [string]$d.tool_input.$k } }
        foreach ($p in $paths) { if (Find-OutsideScopeToken @($p) $roots) { return } }
        $what = if ($paths.Count) { $paths -join ' ' } else { '(no path: the working directory)' }
    }

    # Log the yes before giving it, so a log line exists for every automatic approval.
    $text = ($what -replace '\s+', ' ').Trim()
    if ($text.Length -gt 400) { $text = $text.Substring(0, 400) + '...' }
    $sid = [string]$d.session_id; if ($sid.Length -gt 8) { $sid = $sid.Substring(0, 8) }
    $unit = if ($env:STREAM_UNIT_SESSION) { $env:STREAM_UNIT_SESSION } else { '-' }
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ALLOW unit=$unit session=$sid tool=$tool cwd=$cwd :: $text"
    try {
        $logDir = $env:CLAUDE_AUTOAPPROVE_LOG_DIR
        if (-not $logDir) {
            $scratch = $null
            try { $scratch = Get-AIPath -Name ScratchRoot -Optional } catch {}
            if (-not $scratch) { $scratch = [System.IO.Path]::GetTempPath() }
            $logDir = Join-Path $scratch 'ai-config-work\autoapprove'
        }
        if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -LiteralPath (Join-Path $logDir "$(Get-Date -Format 'yyyyMMdd').log") -Value $line -Encoding utf8
    } catch {}
    if ($env:STREAM_UNIT_OUT) { try { Add-Content -LiteralPath "$($env:STREAM_UNIT_OUT).approvals.log" -Value $line -Encoding utf8 } catch {} }

    @{
        hookSpecificOutput = @{
            hookEventName = 'PermissionRequest'
            decision      = @{ behavior = 'allow' }
        }
    } | ConvertTo-Json -Compress -Depth 5
}
catch {
    # Nothing on stdout (it would be read as a decision); the error is visible in hook debug output.
    [System.Console]::Error.WriteLine("[scoped-autoapprove] $_ at $($_.InvocationInfo.ScriptLineNumber)")
}
