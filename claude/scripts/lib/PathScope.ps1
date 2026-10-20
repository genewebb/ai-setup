# PathScope.ps1: the one answer to "does this command or path stay inside the repo / scratch roots?", shared by
#   destructive-path-guard.ps1  (PreToolUse: a destructive verb that reaches OUTSIDE the roots prompts), and
#   scoped-autoapprove.ps1      (PermissionRequest: a prompt about work INSIDE the roots is answered yes and logged).
# Both hooks must draw the line in the same place, or a command the guard lets through silently could still be refused
# an automatic yes, and the other way round. Dot-source it:  . (Join-Path $PSScriptRoot 'lib\PathScope.ps1')
#
# The roots are the machine profile's ReposRoot, WorktreesRoot and ScratchRoot, every '## Claude access' row with the
# delete AND edit rights (whole working trees, e.g. a devops drive or ~\.claude; Gene 2026-09-28/29, 10/1), and the
# running user's temp folder (the scratchpad lives under it). An unreadable profile leaves only temp trusted, so every
# other absolute target reads as outside (fail closed).

# Normalized form of a path for prefix comparison: backslashes, lower case, trailing backslash, /c/x -> c:\x.  # example-path
function ConvertTo-ScopePath([string] $p) {
    $p = $p.Trim().Trim('"', "'", '`')
    if ($p -match '^/([a-zA-Z])(/|$)') { $p = "$($Matches[1]):" + $p.Substring(2) }   # example-path: /c/x -> c:/x
    $p = $p -replace '/', '\'
    # A bash-escaped backslash (D:\\x\\y, kit item IN-20261020133758-c46f) and a doubled separator are one separator;
    # a leading \\ (UNC) is kept.
    $p = $p.Substring(0, [Math]::Min(2, $p.Length)) + ($p.Substring([Math]::Min(2, $p.Length)) -replace '\\{2,}', '\')
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

# The trusted roots, normalized. $ScriptRoot is the hook scripts folder (the caller's $PSScriptRoot): the machine
# configuration module is looked for beside it (installed: {ClaudeHome}\lib) and one level up (the corpus).
# Default (the destructive-path-guard line): access rows with BOTH the delete and the edit right. -ForApproval (the
# scoped-autoapprove line): every access row without a deny, whatever its rights. Owner 2026-10-17: the folders the
# agents routinely read, write or delete outside the repo and scratch areas are treated the same as those areas for
# the automatic yes, so the agents control what they read, write and delete; a destructive verb outside a delete-right
# row still prompts.
function Get-ScopeRoots([string] $ScriptRoot, [switch] $ForApproval) {
    $roots = [System.Collections.Generic.List[string]]::new()
    $roots.Add(([System.IO.Path]::GetTempPath()).ToLowerInvariant())
    try {
        $lib = @((Join-Path $ScriptRoot '..\lib\MachineConfig.psm1'), (Join-Path $ScriptRoot '..\..\lib\MachineConfig.psm1')) |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if ($lib) {
            Import-Module $lib -Force
            foreach ($k in 'ReposRoot', 'WorktreesRoot', 'ScratchRoot') {
                $v = Get-AIPath -Name $k -Optional
                if ($v) { $roots.Add((ConvertTo-ScopePath $v)) }
            }
            $prof = Get-AIMachineProfile
            foreach ($a in @($prof.Access)) {
                if (-not $a.Path -or 'deny' -in $a.Access) { continue }
                if ($ForApproval -or ('delete' -in $a.Access -and 'edit' -in $a.Access)) { $roots.Add((ConvertTo-ScopePath $a.Path)) }
            }
        }
    }
    catch {}
    $roots
}

# Heredoc bodies (<<EOF / <<'EOF' / <<-EOF ... EOF) and PowerShell here-strings (@' ... '@, @" ... "@) are DATA
# written to a file or a pipe, never paths or verbs this command acts on. On 2026-10-04 a C# string "/obj/" inside
# a <<'XEOF' body, beside "rm -rf old" in a scratchpad, read as an absolute path outside the roots and stopped an
# unattended builder on a prompt nobody could answer. The opener line stays; only the body lines go.
function Remove-HereDocBodies([string] $cmd) {
    $cmd = [regex]::Replace($cmd, '(?ms)<<-?[ \t]*([''"]?)([A-Za-z_][A-Za-z0-9_]*)\1[^\r\n]*\r?\n.*?^[ \t]*\2[ \t]*$', {
            param($m) $m.Value.Substring(0, $m.Value.IndexOf("`n") + 1) + $m.Groups[2].Value })
    [regex]::Replace($cmd, '(?ms)@([''"])[ \t]*\r?\n.*?^\1@', ' ')
}

# Candidate path tokens of a shell command: quoted strings first, then bare tokens split on shell separators.
function Get-CommandPathTokens([string] $cmd) {
    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($m in [regex]::Matches($cmd, '"([^"]*)"|''([^'']*)''')) {
        $v = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        if ($v) { $tokens.Add($v) }
        # A quoted string with whitespace may be a nested command (pwsh -Command "...", bash -c '...'): its own tokens
        # are checked too, since the whole string reads as no path and would hide an outside one (IN-20261018050026-e429).
        if ($v -match '\s') { foreach ($i in (Get-CommandPathTokens $v)) { $tokens.Add($i) } }
    }
    $stripped = [regex]::Replace($cmd, '"[^"]*"|''[^'']*''', ' ')
    # cmd.exe-family tools take /x switches (cmd /c, mklink /J, robocopy /MIR, icacls /grant). Without
    # this, "/c" reads as the Git Bash drive root and every such segment prompts. Switches are dropped
    # only in segments that invoke one of these tools; "rm -rf /c" in any other segment still prompts.
    # taskkill /PID, tasklist /FI, sc query, net stop, schtasks /query, reg query, findstr /c: and the other Windows
    # tools below take the same /x switches; a builder's Monitor loop polling its grader by PID stopped on one.
    $cmdFamily = '(?i)(?:^|\s)(?:cmd|mklink|robocopy|xcopy|icacls|attrib|takeown|taskkill|tasklist|sc|net|schtasks|reg|findstr|wmic|where|forfiles|wevtutil|certutil|msiexec|dism|sfc|chkdsk|netsh|netstat|ipconfig|ping|tracert|nslookup|systeminfo|powercfg|bcdedit|shutdown)(?:\.exe)?(?=\s|$)'
    $segments  = foreach ($s in ($stripped -split '[;|&\r\n]+')) {
        # Git Bash spells a switch //x so MSYS does not rewrite the slash; both forms go.
        if ($s -match $cmdFamily) { [regex]::Replace($s, '(?<=^|\s)//?[A-Za-z?][A-Za-z0-9]{0,5}(?::\S*)?(?=\s|$)', ' ') } else { $s }
    }
    foreach ($t in (($segments -join ' ; ') -split '[\s;|&()<>]+')) { if ($t) { $tokens.Add($t) } }
    , $tokens
}

# The first token that names a place outside the roots, or $null when every absolute token is inside. Relative tokens
# are inside (the shell starts in a trusted working directory). Home-relative (~, $HOME, %USERPROFILE%), UNC shares,
# drive roots and other POSIX absolutes (/etc, /q/...) are outside; /tmp and /dev/null are inside.
function Find-OutsideScopeToken($Tokens, $Roots) {
    foreach ($t in $Tokens) {
        # example-path: a path must start the token, or follow an option separator (--path=C:\x, -LiteralPath:C:\x).
        # Anchoring here keeps relative tokens like src/obj or HEAD:CrewChief/x.cs from reading as absolute.
        $p = $t
        # A URL (https://host/..., a commit's Claude-Session trailer) names no file on this machine; it read as prefix
        # "https:" + POSIX "//host" and stopped three runners on 2026-10-20 (kit item IN-20261020133758-c46f).
        # A file: URL is a path and is still checked.
        if ($p -match '^[A-Za-z][A-Za-z0-9+.-]+://' -and $p -notmatch '^file:') { continue }
        # example-path: the optional prefix is lazy (??) so "C:/x" is read as a drive path first, not as prefix "C:" + POSIX "/x".
        # The prefix holds no whitespace, quote or comma: an option name is one word, and a nested command's
        # "... 'C:/x' ..." must not read as prefix "... 'C:" + POSIX "/x" (its own tokens are checked instead).
        if ($p -match '^(?:[^=:\s''",]*[=:])??(?<path>(?:[A-Za-z]:[\\/]|\\\\|/[A-Za-z]/|/|~|\$env:USERPROFILE|\$HOME|%USERPROFILE%|%HOMEPATH%).*)$') { $p = $Matches['path'] }
        else { continue }

        if ($p -match '^(/dev/null|/dev/stdout|/dev/stderr)$') { continue }
        if ($p -match '^(~|\$HOME|\$env:USERPROFILE|%USERPROFILE%|%HOMEPATH%)([\\/]|$)') { return $t }   # home-relative
        if ($p -match '^\\\\') { return $t }                                                             # UNC share
        if ($p -match '^/tmp(/|$)') { continue }                                                         # Git Bash temp
        if ($p -match '^/[A-Za-z]/' -or $p -match '^[A-Za-z]:[\\/]') {
            $n = ConvertTo-ScopePath $p
            if ($n -match '^[a-z]:\\$') { return $t }                                                   # drive root
            $inside = $false
            foreach ($r in $Roots) { if ($n.StartsWith($r)) { $inside = $true; break } }
            if (-not $inside) { return $t }
            continue
        }
        if ($p -match '^/') { return $t }                                                                # other POSIX absolute (/, /etc, /q/...)
    }
    $null
}
