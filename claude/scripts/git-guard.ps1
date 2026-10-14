# PreToolUse hook: git-guard (spec D19, R18, R19).
#
# Commit, push and worktree rights come from the machine profile's '## Git policy' table
# (ProfileMachineConfig.md). A repo with no row gets none of them. A worktree follows its main repo.
#
#   Commit    : every git verb that changes the repo, the index or the worktree state
#   Push      : push
#   Worktrees : worktree add / remove / prune / move (needs Commit = yes); new paths only under {WorktreesRoot}
#   Always    : read-only git (status, log, diff, show, ls-files, rev-parse, branch --list, worktree list, ...)
#
# FAILS CLOSED (R19): when a command cannot be evaluated (unbalanced quotes, a verb built at run time such as
# 'git $v', an unreadable profile), state-changing git is denied and read-only git is allowed.
#
# Runs via hook-dispatch.ps1 -Id git-guard on PreToolUse for Bash|PowerShell. hook-dispatch swallows errors and
# exits 0, so this script catches its own errors and decides itself.
# Known limit: command-text matching is heuristic (an alias or a script that runs git is not seen).

if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

$script:CommitVerbs = @('commit', 'merge', 'rebase', 'cherry-pick', 'revert', 'am', 'tag', 'add', 'rm', 'mv', 'restore',
    'checkout', 'switch', 'reset', 'stash', 'branch', 'clean', 'apply', 'pull', 'update-ref', 'notes', 'commit-tree')
$script:StateVerbsRegex = '(?i)\bgit(?:\.exe)?\b.*?\b(' + (($script:CommitVerbs + @('push', 'worktree')) -join '|') + ')\b'

function Write-GitGuardDeny([string]$Reason) {
    @{
        hookSpecificOutput = @{
            hookEventName            = 'PreToolUse'
            permissionDecision       = 'deny'
            permissionDecisionReason = "git-guard: $Reason"
        }
    } | ConvertTo-Json -Compress -Depth 5
}

function Split-GitGuardTokens([string]$Text) {
    # Shell-ish tokenizer: whitespace separated, '...' and "..." quoted. Throws on an unbalanced quote.
    $tokens = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new(); $q = [char]0; $have = $false
    foreach ($ch in $Text.ToCharArray()) {
        if ($q) {
            if ($ch -eq $q) { $q = [char]0 } else { [void]$sb.Append($ch) }
            continue
        }
        if ($ch -eq '"' -or $ch -eq "'") { $q = $ch; $have = $true; continue }
        if ([char]::IsWhiteSpace($ch)) {
            if ($have -or $sb.Length) { $tokens.Add($sb.ToString()); [void]$sb.Clear(); $have = $false }
            continue
        }
        [void]$sb.Append($ch)
    }
    if ($q) { throw 'unbalanced quote' }
    if ($have -or $sb.Length) { $tokens.Add($sb.ToString()) }
    return , $tokens
}

function Split-GitGuardSegments([string]$Command) {
    # Statement separators outside quotes: ; && || | newline. Returns segment strings.
    $segs = [System.Collections.Generic.List[string]]::new()
    $sb = [System.Text.StringBuilder]::new(); $q = [char]0
    $chars = $Command.ToCharArray()
    for ($i = 0; $i -lt $chars.Length; $i++) {
        $ch = $chars[$i]
        if ($q) { if ($ch -eq $q) { $q = [char]0 }; [void]$sb.Append($ch); continue }
        if ($ch -eq '"' -or $ch -eq "'") { $q = $ch; [void]$sb.Append($ch); continue }
        if ($ch -eq ';' -or $ch -eq "`n" -or $ch -eq "`r" -or $ch -eq '|' -or ($ch -eq '&' -and $i + 1 -lt $chars.Length -and $chars[$i + 1] -eq '&')) {
            $segs.Add($sb.ToString()); [void]$sb.Clear()
            if (($ch -eq '&' -or $ch -eq '|') -and $i + 1 -lt $chars.Length -and $chars[$i + 1] -eq $ch) { $i++ }
            continue
        }
        [void]$sb.Append($ch)
    }
    if ($q) { throw 'unbalanced quote' }
    $segs.Add($sb.ToString())
    return @($segs | Where-Object { $_.Trim() })
}

function Resolve-GitGuardPath([string]$Path, [string]$Base) {
    $p = $Path -replace '/', '\'
    if ($p -match '^\\[a-zA-Z]\\') { $p = $p.Substring(1, 1) + ':' + $p.Substring(2) }   # example-path: /c/x (Git Bash) -> c:\x
    if ($p -eq '~' -or $p.StartsWith('~\')) { $p = $HOME + $p.Substring(1) }
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $Base $p }
    return [IO.Path]::GetFullPath($p)
}

function Get-GitGuardInvocations([string]$Command, [string]$Cwd) {
    <# Yields { Dir; Verb; Args; Dynamic } for every git call, tracking cd / Set-Location / pushd in the chain. #>
    $dir = $Cwd
    foreach ($seg in Split-GitGuardSegments $Command) {
        $t = Split-GitGuardTokens $seg.Trim()
        if (-not $t.Count) { continue }
        # Leading wrappers: '&', '(' , 'command', 'exec', env assignments.
        $i = 0
        while ($i -lt $t.Count -and ($t[$i] -in '&', '(', 'command', 'exec', 'time', 'sudo' -or $t[$i] -match '^[A-Za-z_][A-Za-z0-9_]*=')) { $i++ }
        if ($i -ge $t.Count) { continue }
        $head = $t[$i].Trim('(', ')')
        if ($head -in 'cd', 'Set-Location', 'sl', 'pushd', 'Push-Location', 'chdir') {
            $rest = @($t | Select-Object -Skip ($i + 1) | Where-Object { $_ -notmatch '^-(LiteralPath|Path)$' })
            if ($rest.Count -and $rest[0] -notmatch '^\$') { $dir = Resolve-GitGuardPath $rest[0] $dir }
            elseif ($rest.Count) { $dir = $null }   # cd $var: the target is unknown from here on
            continue
        }
        # A git call may also appear after a wrapper word we do not know; find the token.
        $g = -1
        for ($j = $i; $j -lt $t.Count; $j++) { if ($t[$j] -match '^(?:.*[\\/])?git(?:\.exe)?$') { $g = $j; break } }
        if ($g -lt 0) { continue }
        $target = $dir
        $k = $g + 1
        while ($k -lt $t.Count -and $t[$k].StartsWith('-')) {
            $o = $t[$k]
            if ($o -ceq '-C' -and $k + 1 -lt $t.Count) {
                $target = $(if ($t[$k + 1] -match '^\$') { $null } elseif ($target) { Resolve-GitGuardPath $t[$k + 1] $target } else { $null }); $k += 2; continue
            }
            if ($o -cin '-c', '--git-dir', '--work-tree', '--namespace', '--exec-path' -and $k + 1 -lt $t.Count) { $k += 2; continue }
            $k++
        }
        $verb = if ($k -lt $t.Count) { $t[$k] } else { '' }
        [pscustomobject]@{
            Dir     = $target
            Verb    = $verb.ToLowerInvariant()
            Args    = @($t | Select-Object -Skip ($k + 1))
            Dynamic = ($verb -match '^[\$\(`]') -or ($verb -match '\$')
        }
    }
}

function Get-GitGuardNeed($inv) {
    <# Returns 'none' | 'commit' | 'push' | 'worktrees' | 'worktrees-list'. #>
    $v = $inv.Verb; $a = @($inv.Args)
    if ($v -eq 'push') { return 'push' }
    if ($v -eq 'worktree') {
        $sub = if ($a.Count) { $a[0].ToLowerInvariant() } else { '' }
        if ($sub -in 'add', 'remove', 'prune', 'move', 'repair', 'lock', 'unlock') { return 'worktrees' }
        return 'none'
    }
    if ($v -notin $script:CommitVerbs) { return 'none' }
    switch ($v) {
        'branch' {
            if (-not $a.Count) { return 'none' }
            if ($a | Where-Object { $_ -in '-d', '-D', '--delete', '-m', '-M', '--move', '-c', '-C', '--copy', '-f', '--force', '-u', '--set-upstream-to', '--unset-upstream', '--edit-description' }) { return 'commit' }
            $names = @($a | Where-Object { -not $_.StartsWith('-') })
            $listing = $a | Where-Object { $_ -in '-l', '--list', '-a', '--all', '-r', '--remotes', '--show-current', '--contains', '--no-contains', '--merged', '--no-merged', '--points-at', '-v', '-vv', '--verbose' -or $_ -like '--format*' -or $_ -like '--sort*' }
            if ($names.Count -and -not $listing) { return 'commit' }
            return 'none'
        }
        'tag' {
            if (-not $a.Count) { return 'none' }
            if ($a | Where-Object { $_ -in '-l', '--list', '-v', '--verify' -or $_ -like '--contains*' -or $_ -like '--points-at*' -or $_ -like '--sort*' -or $_ -like '--format*' }) { return 'none' }
            return 'commit'
        }
        'stash' {
            if ($a.Count -and $a[0] -in 'list', 'show') { return 'none' }
            return 'commit'
        }
        'apply' {
            if ($a | Where-Object { $_ -in '--index', '--cached', '-3', '--3way' }) { return 'commit' }
            return 'none'
        }
        'notes' {
            if (-not $a.Count -or $a[0] -in 'list', 'show') { return 'none' }
            return 'commit'
        }
        default { return 'commit' }
    }
}

function Get-GitGuardWorktreeNewPath($inv) {
    <# The new worktree path for 'worktree add' / 'worktree move', or $null. #>
    $a = @($inv.Args); if (-not $a.Count) { return $null }
    $sub = $a[0].ToLowerInvariant()
    $rest = @($a | Select-Object -Skip 1)
    $pos = [System.Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $rest.Count; $i++) {
        $x = $rest[$i]
        if ($x -in '-b', '-B', '--reason', '--orphan') { $i++; continue }
        if ($x.StartsWith('-')) { continue }
        $pos.Add($x)
    }
    if ($sub -eq 'add' -and $pos.Count -ge 1) { return $pos[0] }
    if ($sub -eq 'move' -and $pos.Count -ge 2) { return $pos[1] }
    return $null
}

function Invoke-GitGuard([string]$Json) {
    $d = $Json | ConvertFrom-Json
    $cmd = [string]$d.tool_input.command
    if ([string]::IsNullOrWhiteSpace($cmd) -or $cmd -notmatch '(?i)\bgit(\.exe)?\b') { return }
    $cwd = if ($d.cwd) { [string]$d.cwd } else { (Get-Location).Path }

    try { $invs = @(Get-GitGuardInvocations -Command $cmd -Cwd $cwd) }
    catch {
        if ($cmd -match $script:StateVerbsRegex) { Write-GitGuardDeny "could not evaluate this command ($($_.Exception.Message)), and it may change git state; the guard fails closed. Rewrite it as plain git commands." }
        return
    }
    if (-not $invs.Count) { return }

    $prof = $null; $profErr = $null
    try {
        $libs = @((Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1'), (Join-Path $PSScriptRoot '..\..\lib\MachineConfig.psm1'))
        $lib = $libs | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $lib) { throw 'MachineConfig.psm1 not found next to the hook' }
        Import-Module $lib -Force -DisableNameChecking
        $prof = Get-AIMachineProfile
    }
    catch { $profErr = "$_" }

    foreach ($inv in $invs) {
        if ($inv.Dynamic) {
            Write-GitGuardDeny "the git verb is built at run time ('$($inv.Verb)'), so the guard cannot check it and fails closed. Write the verb literally."
            return
        }
        $need = Get-GitGuardNeed $inv
        if ($need -eq 'none') { continue }
        if (-not $prof) { Write-GitGuardDeny "the machine profile could not be read ($profErr), so state-changing git ('git $($inv.Verb)') is denied. Fix the profile."; return }
        if (-not $inv.Dir) { Write-GitGuardDeny "cannot tell which repository 'git $($inv.Verb)' targets (a cd or -C to a variable path), so the guard fails closed."; return }

        $pol = Get-AIGitPolicy -Path $inv.Dir -Profile $prof
        if (-not $pol.RepoRoot) { continue }   # not a repository: git itself will refuse
        $repo = $pol.RepoRoot
        $where = "Git policy in $($prof.Path)"
        switch ($need) {
            'commit' {
                if (-not $pol.Commit) { Write-GitGuardDeny "'git $($inv.Verb)' changes git state in $repo, and that repo has Commit = no (or no row). $where. Leave the change for Gene to stage and commit."; return }
            }
            'push' {
                if (-not $pol.Push) { Write-GitGuardDeny "push is not allowed for $repo (Push = no, or no row). $where."; return }
            }
            'worktrees' {
                if (-not $pol.Worktrees) { Write-GitGuardDeny "worktrees are not allowed for $repo (Worktrees = no, or no row; Worktrees also needs Commit = yes). $where. Work in the main tree."; return }
                $sub = $inv.Args[0].ToLowerInvariant()
                if ($sub -eq 'remove' -and ($inv.Args | Where-Object { $_ -in '-f', '--force' })) {
                    Write-GitGuardDeny "'git worktree remove --force' is denied: a dirty worktree is never removed. Commit or discard its changes first."; return
                }
                $np = Get-GitGuardWorktreeNewPath $inv
                if ($np) {
                    $root = $prof.Keys['WorktreesRoot']
                    if (-not $root) { Write-GitGuardDeny "WorktreesRoot is not set in $($prof.Path)."; return }
                    $full = Resolve-GitGuardPath $np $inv.Dir
                    $rootFull = [IO.Path]::GetFullPath($root).TrimEnd('\')
                    if (-not $full.StartsWith($rootFull + '\', [StringComparison]::OrdinalIgnoreCase)) {
                        Write-GitGuardDeny "a new worktree must be under {WorktreesRoot} ($rootFull\<repo>\<name>), not $full."; return
                    }
                }
            }
        }
    }
}

try { Invoke-GitGuard -Json $HookJson }
catch {
    $c = ''
    try { $c = [string](($HookJson | ConvertFrom-Json).tool_input.command) } catch { $c = [string]$HookJson }
    if ($c -match $script:StateVerbsRegex) { Write-GitGuardDeny "internal error ($($_.Exception.Message)); state-changing git is denied (fails closed)." }
}
