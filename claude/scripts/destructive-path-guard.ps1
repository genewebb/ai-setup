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

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

try {
    $d   = $HookJson | ConvertFrom-Json
    $cmd = [string]$d.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd)) { return }

    # Heredoc bodies (<<EOF / <<'EOF' / <<-EOF ... EOF) and PowerShell here-strings (@' ... '@, @" ... "@) are DATA
    # written to a file or a pipe, never paths or verbs this command acts on. On 2026-10-04 a C# string "/obj/" inside
    # a <<'XEOF' body, beside "rm -rf old" in a scratchpad, read as an absolute path outside the roots and stopped an
    # unattended builder on a prompt nobody could answer. The opener line stays; only the body lines go.
    $cmd = [regex]::Replace($cmd, '(?ms)<<-?[ \t]*([''"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\r\n]*\r?\n.*?^[ \t]*\2[ \t]*$', {
            param($m) $m.Value.Substring(0, $m.Value.IndexOf("`n") + 1) + $m.Groups[2].Value })
    $cmd = [regex]::Replace($cmd, '(?ms)@([''"])[ \t]*\r?\n.*?^\1@', ' ')

    # 1. Destructive verb in command position (start, after a separator/subshell/loop keyword,
    #    or after a wrapper such as sudo/xargs/find -exec/cmd /c).
    $verbAt   = '(?im)(?:^|[;&|(]\s*|\b(?:do|then|else|sudo|gsudo|nohup|xargs(?:\s+-\S+)*|-exec(?:dir)?|timeout\s+\S+|nice(?:\s+-n\s+\d+)?|cmd(?:\.exe)?\s+/[cCkK])\s+)(?:rm|rmdir|rd|del|erase|Remove-Item|ri)(?=\s|$)'
    $findDel  = '(?im)(?:^|[;&|(]\s*)find\b[^;&|]*\s-delete\b'
    if (-not ($cmd -match $verbAt -or $cmd -match $findDel)) { return }

    function Normalize([string]$p) {
        $p = $p.Trim().Trim('"', "'", '`')
        if ($p -match '^/([a-zA-Z])(/|$)') { $p = "$($Matches[1]):" + $p.Substring(2) }   # example-path: /c/x -> c:/x
        $p = $p -replace '/', '\'
        $p = $p.ToLowerInvariant()
        # The harness hands out scratchpad paths with the 8.3 profile name (<users>\SPEEDM~1\...). Expand the CURRENT
        # user's short name so it matches the same root as the long form. 8.3 keeps the first 6 characters, so another
        # account's short name (<users>\otheru~1\) does not expand and stays outside.
        if ($env:USERPROFILE) {
            $usersDir = [regex]::Escape((Split-Path $env:USERPROFILE).ToLowerInvariant())
            $me = (Split-Path $env:USERPROFILE -Leaf).ToLowerInvariant()
            if ($p -match "^$usersDir\\([^\\]{1,6})~\d+\\" -and $me.StartsWith($Matches[1])) {
                $p = [regex]::Replace($p, "^($usersDir)\\[^\\]+~\d+(?=\\)", { param($m) $m.Groups[1].Value + '\' + $me })
            }
        }
        if ($p -notmatch '\\$') { $p += '\' }
        return $p
    }

    # 2. Trusted roots from the machine profile: ReposRoot, WorktreesRoot, ScratchRoot, every '## Claude access' row
    #    with the delete right (whole working trees, e.g. a devops drive or ~\.claude; Gene 2026-09-28/29, 10/1),
    #    plus the running user's temp (the scratchpad lives under it). Normalized: backslashes, lower-case, trailing
    #    backslash. An unreadable profile leaves only temp trusted, so every other absolute target prompts (fail closed).
    $roots = [System.Collections.Generic.List[string]]::new()
    $roots.Add(([System.IO.Path]::GetTempPath()).ToLowerInvariant())
    try {
        $lib = @((Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1'), (Join-Path $PSScriptRoot '..\..\lib\MachineConfig.psm1')) |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($lib) {
            Import-Module $lib -Force
            foreach ($k in 'ReposRoot', 'WorktreesRoot', 'ScratchRoot') {
                $v = Get-AIPath -Name $k -Optional
                if ($v) { $roots.Add((Normalize $v)) }
            }
            $prof = Get-AIMachineProfile
            foreach ($a in @($prof.Access)) {
                if ($a.Path -and 'delete' -in $a.Access -and 'edit' -in $a.Access -and 'deny' -notin $a.Access) { $roots.Add((Normalize $a.Path)) }
            }
        }
    }
    catch {}

    # Collect candidate path tokens: quoted strings first, then bare tokens.
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($cmd, '"([^"]*)"|''([^'']*)''')) {
        $v = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        if ($v) { $tokens.Add($v) }
    }
    $stripped = [regex]::Replace($cmd, '"[^"]*"|''[^'']*''', ' ')
    # cmd.exe-family tools take /x switches (cmd /c, mklink /J, robocopy /MIR, icacls /grant). Without
    # this, "/c" reads as the Git Bash drive root and every such segment prompts. Switches are dropped
    # only in segments that invoke one of these tools; "rm -rf /c" in any other segment still prompts.
    $cmdFamily = '(?i)(?:^|\s)(?:cmd|mklink|robocopy|xcopy|icacls|attrib|takeown)(?:\.exe)?(?=\s|$)'
    $segments  = foreach ($s in ($stripped -split '[;|&\r\n]+')) {
        if ($s -match $cmdFamily) { [regex]::Replace($s, '(?<=^|\s)/[A-Za-z?][A-Za-z0-9]{0,5}(?::\S*)?(?=\s|$)', ' ') } else { $s }
    }
    foreach ($t in (($segments -join ' ; ') -split '[\s;|&()<>]+')) { if ($t) { $tokens.Add($t) } }

    $offender = $null
    foreach ($t in $tokens) {
        # example-path: a path must start the token, or follow an option separator (--path=C:\x, -LiteralPath:C:\x).
        # Anchoring here keeps relative tokens like src/obj or HEAD:CrewChief/x.cs from reading as absolute.
        $p = $t
        # example-path: the optional prefix is lazy (??) so "C:/x" is read as a drive path first, not as prefix "C:" + POSIX "/x".
        if ($p -match '^(?:[^=:]*[=:])??(?<path>(?:[A-Za-z]:[\\/]|\\\\|/[A-Za-z]/|/|~|\$env:USERPROFILE|\$HOME|%USERPROFILE%|%HOMEPATH%).*)$') { $p = $Matches['path'] }
        else { continue }

        if ($p -match '^(/dev/null|/dev/stdout|/dev/stderr)$') { continue }
        if ($p -match '^(~|\$HOME|\$env:USERPROFILE|%USERPROFILE%|%HOMEPATH%)([\\/]|$)') { $offender = $t; break }   # home-relative
        if ($p -match '^\\\\') { $offender = $t; break }                                                             # UNC share
        if ($p -match '^/tmp(/|$)') { continue }                                                                     # Git Bash temp
        if ($p -match '^/[A-Za-z]/' -or $p -match '^[A-Za-z]:[\\/]') {
            $n = Normalize $p
            if ($n -match '^[a-z]:\\$') { $offender = $t; break }                                                   # drive root
            $inside = $false
            foreach ($r in $roots) { if ($n.StartsWith($r)) { $inside = $true; break } }
            if (-not $inside) { $offender = $t; break }
            continue
        }
        if ($p -match '^/') { $offender = $t; break }                                                                # other POSIX absolute (/, /etc, /q/...)
    }

    if ($offender) {
        @{
            hookSpecificOutput = @{
                hookEventName            = 'PreToolUse'
                permissionDecision       = 'ask'
                permissionDecisionReason = "destructive-path-guard: destructive command targets a path outside the repo/scratch roots ($offender). Confirm before it runs."
            }
        } | ConvertTo-Json -Compress -Depth 5
    }
}
catch {}
