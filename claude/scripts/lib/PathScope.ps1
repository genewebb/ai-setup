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
    # example-path: a bash-escaped backslash (D:\\x\\y, kit item IN-20261020133758-c46f) and a doubled separator are one separator;
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

# True when the quoted string at $Index of $cmd is the SCRIPT of a sed / awk / perl / grep command: its first
# non-option operand, or the value of -e / --expression / --regexp. A script is data ("0,/x/s//y/", "\\u001f",
# "new Dictionary<string, string>()/"), never a path: on 2026-10-21 three builders' mutation checks sat 2-3 h on
# guard prompts nobody could answer, read as "/s//", "\\u001f" and "/" (kit item IN-20261021063004-304d). A quoted
# FILE operand after the script is still a path. $Masked is $cmd with every quoted string replaced by as many Qs, so
# a separator inside an earlier quoted string does not end the simple command.
function Test-ScriptOperand([string] $Masked, [int] $Index) {
    $prefix = $Masked.Substring(0, $Index)
    $start  = $prefix.LastIndexOfAny([char[]](';&|(' + "`n")) + 1
    $words  = @(($prefix.Substring($start)) -split '\s+' | Where-Object { $_ })
    # Skip leading VAR=value assignments and wrappers (timeout takes its duration with it).
    $i = 0
    while ($i -lt $words.Count) {
        if ($words[$i] -match '^[A-Za-z_][A-Za-z0-9_]*=' -or $words[$i] -match '^(sudo|nohup|env|xargs|nice|time|command)$') { $i++ }
        elseif ($words[$i] -eq 'timeout') { $i += 2 }
        else { break }
    }
    if ($i -ge $words.Count -or $words[$i] -notmatch '^(?:.*[\\/])?(sed|gsed|awk|gawk|mawk|perl|grep|egrep|fgrep|rg)(\.exe)?$') { return $false }
    $ops = @($words | Select-Object -Skip ($i + 1))
    if ($ops.Count -and $ops[-1] -match '^(-e|--expression|--regexp)$') { return $true }
    foreach ($o in $ops) { if ($o -notmatch '^-') { return $false } }
    $true
}

# True when the quoted string at $Index of $cmd is a script some launcher runs: the value of -Command / -c / -lc /
# /c / /k / -ArgumentList / -Args / -ScriptBlock, the operand of iex / Invoke-Expression / eval, or a later element
# of a comma list ('-NoProfile','-Command','...'). $Masked is as in Test-ScriptOperand.
function Test-NestedCommandOperand([string] $Masked, [int] $Index) {
    $words = @(($Masked.Substring(0, $Index)) -split '\s+' | Where-Object { $_ })
    if (-not $words.Count) { return $false }
    $last = $words[-1]
    if ($last -match ',$') { return $true }
    $last -match '(?i)^(-[a-z]{0,3}c|-com(m(a(n(d)?)?)?)?|/[ck]|-ArgumentList|-Args|-ScriptBlock|iex|Invoke-Expression|eval)$'
}

# True when the quoted string at $Index of $cmd is an argument of a function or method call: its nearest unclosed
# '(' follows a name (x('/c'), $g.Replace(...), [regex]::Replace(...)), not a keyword (if, foreach), '@', '$' or a
# space. Such a string is data handed to code; on 2026-10-21 two authors stalled on "/c" out of x('/c') and on a
# comma-list recursion into .Replace(..., 'at <c>b</c>') (kit item IN-20261021201746-bedf). $Masked is as in
# Test-ScriptOperand.
function Test-CallArgument([string] $Masked, [int] $Index) {
    $depth = 0
    for ($p = $Index - 1; $p -ge 0; $p--) {
        $ch = $Masked[$p]
        if ($ch -eq ')') { $depth++ }
        elseif ($ch -eq '(') {
            if ($depth -gt 0) { $depth--; continue }
            $before = $Masked.Substring(0, $p)
            if ($before -notmatch '[A-Za-z0-9_\]]$') { return $false }
            return $before -notmatch '(?i)(?:^|[^A-Za-z0-9_-])(if|elseif|foreach|for|while|until|switch|catch|function|param)$'
        }
        elseif ($depth -eq 0 -and ($ch -eq ';' -or $ch -eq "`n")) { return $false }
    }
    $false
}

# The destructive verbs the guard looks for: one in command position (start, after a separator, subshell or loop
# keyword, or after a wrapper such as sudo / xargs / find -exec / cmd /c), or find ... -delete.
$script:DestructiveVerbRx = '(?im)(?:^|[;&|(]\s*|\b(?:do|then|else|sudo|gsudo|nohup|xargs(?:\s+-\S+)*|-exec(?:dir)?|timeout\s+\S+|nice(?:\s+-n\s+\d+)?|cmd(?:\.exe)?\s+/[cCkK])\s+)(?:rm|rmdir|rd|del|erase|Remove-Item|ri)(?=\s|$)'
$script:FindDeleteRx      = '(?im)(?:^|[;&|(]\s*)find\b[^;&|]*\s-delete\b'
function Test-DestructiveCommand([string] $cmd) { $cmd -match $script:DestructiveVerbRx -or $cmd -match $script:FindDeleteRx }

# True when the quoted string at $Index of $cmd belongs to a command that runs it inside a container: docker / podman
# / nerdctl run or exec (also docker compose run / exec) and kubectl exec. Its POSIX paths (/w/a, /var/opt/x) name
# the container's file system, not this host's. $Masked is as in Test-ScriptOperand.
function Test-ContainerCommand([string] $Masked, [int] $Index) {
    $prefix = $Masked.Substring(0, $Index)
    $start  = $prefix.LastIndexOfAny([char[]](';&|(' + "`n")) + 1
    $words  = @(($prefix.Substring($start)) -split '\s+' | Where-Object { $_ })
    $i = 0
    while ($i -lt $words.Count -and ($words[$i] -match '^[A-Za-z_][A-Za-z0-9_]*=' -or $words[$i] -match '^(sudo|nohup|env|time|command)$')) { $i++ }
    if ($i -ge $words.Count) { return $false }
    $rest = @($words | Select-Object -Skip ($i + 1))
    if ($words[$i] -match '^(?:.*[\\/])?(docker|podman|nerdctl)(\.exe)?$') { return [bool]($rest | Where-Object { $_ -match '^(run|exec)$' }) }
    if ($words[$i] -match '^(?:.*[\\/])?kubectl(\.exe)?$') { return [bool]($rest | Where-Object { $_ -eq 'exec' }) }
    $false
}
# True when $Before (the command text up to a value) ends in an assignment to PATH: bash PATH= / export PATH= or
# PowerShell $env:PATH = / +=. Only PATH itself: another variable's value may be the target a later command deletes.
function Test-PathAssignment([string] $Before) {
    $Before -cmatch '(?:^|[\s;|&(])PATH=$' -or $Before -match '(?i)\$env:PATH\s*\+?=\s*$'
}

# Candidate path tokens of a shell command: quoted strings first, then bare tokens split on shell separators.
function Get-CommandPathTokens([string] $cmd) {
    $tokens = New-Object System.Collections.Generic.List[string]
    $quoted = [regex]::Matches($cmd, '"([^"]*)"|''([^'']*)''')
    $masked = [regex]::Replace($cmd, '"[^"]*"|''[^'']*''', { param($q) 'Q' * $q.Length })
    foreach ($m in $quoted) {
        if (Test-ScriptOperand $masked $m.Index) { continue }
        # The value assigned to PATH (PATH="/c/a:/c/b", export PATH='...', $env:PATH = '...') is a search list, not
        # an operand: it read as one POSIX absolute and stalled a builder on 2026-10-23 (kit item IN-20261023161132-1e65).
        if (Test-PathAssignment $masked.Substring(0, $m.Index)) { continue }
        $v = if ($m.Groups[1].Success) { $m.Groups[1].Value } else { $m.Groups[2].Value }
        # A call's argument is data: never a nested command, and a POSIX-form value ('/c', '/>') is no path; a drive,
        # UNC or home value is still checked ([IO.Path]::Combine('C:\x', ...)).
        if (Test-CallArgument $masked $m.Index) {
            if ($v -and $v -notmatch '^/') { $tokens.Add($v) }
            continue
        }
        # A literal appended with + or += (sys.argv[1]+'/sim/x', $base + '/x') is a suffix of another value, so a
        # POSIX-form one is no absolute path; it stalled a builder on 2026-10-23 (kit item IN-20261023212118-f23c).
        # A drive, UNC or home value is still checked, and so is a literal that leads ('/c/x' + $y).
        if ($v -match '^/' -and $masked.Substring(0, $m.Index) -match '\+=?\s*$') { continue }
        if ($v) { $tokens.Add($v) }
        # A quoted string with whitespace may be a nested command (pwsh -Command "...", bash -c '...'): its own tokens
        # are checked too, since the whole string reads as no path and would hide an outside one (IN-20261018050026-e429).
        # Only a launcher's script recurses: quoted prose ("-Value 'see bin/<config>/<tfm>'") split on <> into a bare
        # "/" and stalled an author on a prompt nobody could answer (kit item IN-20261021183719-aa28).
        # A script a container runs (docker run ... sh -c '...') names container paths, so its POSIX-form tokens are
        # dropped while the script deletes nothing: 'mkdir -p /w/a && cd /w/a' held a builder on a prompt nobody could
        # answer on 2026-10-24 (kit item IN-20261024162923-3943). A script that deletes ('rm -rf /w/a') is checked whole,
        # and a drive, UNC or home token in any container script is still checked.
        if ($v -match '\s' -and (Test-NestedCommandOperand $masked $m.Index)) {
            $inContainer = (Test-ContainerCommand $masked $m.Index) -and -not (Test-DestructiveCommand $v)
            foreach ($i in (Get-CommandPathTokens $v)) { if (-not ($inContainer -and $i -match '^/')) { $tokens.Add($i) } }
        }
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
        # A bare PATH=/c/a:/c/b (also after export) is a search list, as its quoted form (kit item IN-20261023161132-1e65).
        if ($p -cmatch '^PATH=') { continue }
        # example-path: the optional prefix is lazy (??) so "C:/x" is read as a drive path first, not as prefix "C:" + POSIX "/x".
        # The prefix holds no whitespace, quote or comma: an option name is one word, and a nested command's
        # example-path: "... 'C:/x' ..." must not read as prefix "... 'C:" + POSIX "/x" (its own tokens are checked instead).
        if ($p -match '^(?:[^=:\s''",]*[=:])??(?<path>(?:[A-Za-z]:[\\/]|\\\\|/[A-Za-z]/|/|~|\$env:USERPROFILE|\$HOME|%USERPROFILE%|%HOMEPATH%).*)$') { $p = $Matches['path'] }
        else { continue }

        if ($p -match '^(/dev/null|/dev/stdout|/dev/stderr)$') { continue }
        # A UNC share needs a server name right after //: '// ' opens a comment line in a quoted value ("// x.txt ...`n
        # class ..."), which stalled an author on 2026-10-23 (kit item IN-20261023124711-6fbc). '//server/share' is checked.
        if ($p -match '^//\s') { continue }
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
