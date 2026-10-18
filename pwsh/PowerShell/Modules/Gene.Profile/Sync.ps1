# Git sync engine for prof.
#
# A repo object says where a clone is and how to run git in it:
#   Path     where its machine sees it (git runs there: in the WinRM session for another machine)
#   Url      how THIS machine's git reaches it for fetch and push (admin-share path, forward slashes)
#   ReadPath how THIS machine reads its files (admin-share path) for the secret scan
#   Session  the WinRM session, or $null for a clone on this machine (the hub, and the tests)
#
# Worktree commands (status, add, commit, merge) always run on the clone's own machine: across the share, git status
# on a 1,400-file clone took 40 s and every run re-hashed the index the other machine wrote. Only object transfer
# (fetch from it, push to the side ref refs/prof/incoming) crosses the share. Every call passes -c safe.directory=*:
# command-line scope is the protected configuration git honours for that setting, for that one call.

function New-GeneRepo {
    param([Parameter(Mandatory)][string]$Path, $Session, [string]$Machine)
    if ($Session) {
        $unc = ConvertTo-GeneUncPath -Machine $Machine -Path $Path
        return [pscustomobject]@{ Path = $Path; Url = (ConvertTo-GeneGitUrl $unc); ReadPath = $unc; Session = $Session; Name = "$Machine`:$Path" }
    }
    [pscustomobject]@{ Path = $Path; Url = $Path; ReadPath = $Path; Session = $null; Name = $Path }
}

function Invoke-GeneGitResult {
    <# git in a local folder; returns Code and Out. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$GitArgs)
    $out = & git -c safe.directory=* -C $Path @GitArgs 2>&1 | ForEach-Object { "$_" }
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = @($out) }
}

function Invoke-GeneGit {
    <# git in a local folder; throws with git's own output on a non-zero exit. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$GitArgs)
    $r = Invoke-GeneGitResult -Path $Path -GitArgs $GitArgs
    if ($r.Code -ne 0) { throw "git $($GitArgs -join ' ') in $Path failed ($($r.Code)): $($r.Out -join ' ')" }
    return $r.Out
}

function Invoke-GeneRepoGitResult {
    <# git in a repo object, on its own machine. #>
    param([Parameter(Mandatory)]$Repo, [Parameter(Mandatory)][string[]]$GitArgs)
    if (-not $Repo.Session) { return Invoke-GeneGitResult -Path $Repo.Path -GitArgs $GitArgs }
    $lines = @(Invoke-Command -Session $Repo.Session -ArgumentList $Repo.Path, $GitArgs -ScriptBlock {
            param($p, $a)
            $ErrorActionPreference = 'Continue'
            & git -c safe.directory=* -C $p @a 2>&1 | ForEach-Object { "$_" }
            "__PROF_GIT_EXIT__$LASTEXITCODE"
        })
    $code = 1
    $last = $lines[-1]
    if ($last -match '^__PROF_GIT_EXIT__(-?\d+)$') { $code = [int]$Matches[1]; $lines = @($lines | Select-Object -SkipLast 1) }
    [pscustomobject]@{ Code = $code; Out = $lines }
}

function Invoke-GeneRepoGit {
    param([Parameter(Mandatory)]$Repo, [Parameter(Mandatory)][string[]]$GitArgs)
    $r = Invoke-GeneRepoGitResult -Repo $Repo -GitArgs $GitArgs
    if ($r.Code -ne 0) { throw "git $($GitArgs -join ' ') in $($Repo.Name) failed ($($r.Code)): $($r.Out -join ' ')" }
    return $r.Out
}

function Get-GenePorcelainPath {
    <# One 'git status --porcelain' line -> the path it names (the new name for a rename, quotes removed). #>
    param([string]$Line)
    $p = $Line.Substring(3)
    if ($p -match ' -> (.+)$') { $p = $Matches[1] }
    if ($p.StartsWith('"') -and $p.EndsWith('"')) { $p = $p.Substring(1, $p.Length - 2) -replace '\\"', '"' -replace '\\\\', '\' }
    return $p
}

function Get-GeneRepoState {
    param([Parameter(Mandatory)]$Repo)
    if (-not (Test-Path -LiteralPath (Join-Path $Repo.ReadPath '.git'))) {
        return [pscustomobject]@{ Exists = $false; Head = $null; Branch = $null; Dirty = @() }
    }
    $head = (Invoke-GeneRepoGitResult $Repo @('rev-parse', 'HEAD')).Out | Select-Object -First 1
    $branch = (Invoke-GeneRepoGitResult $Repo @('rev-parse', '--abbrev-ref', 'HEAD')).Out | Select-Object -First 1
    $dirty = @((Invoke-GeneRepoGit $Repo @('status', '--porcelain', '--untracked-files=all')) | Where-Object { $_ })
    [pscustomobject]@{ Exists = $true; Head = $head; Branch = $branch; Dirty = $dirty }
}

function Invoke-GeneHarvest {
    <#
    Commits whatever is uncommitted in a clone (on a target: memory written by Claude sessions there), after a secret
    scan of exactly those files (read through ReadPath). A hit stops unless -AllowSecrets. Returns Committed and Files.
    #>
    param(
        [Parameter(Mandatory)]$Repo,
        [Parameter(Mandatory)][string]$Label,
        [string]$Hub = (Get-GeneHubRoot),
        [switch]$AllowSecrets,
        [switch]$WhatIf
    )
    $state = Get-GeneRepoState -Repo $Repo
    if (-not $state.Exists) { throw "$($Repo.Name) is not a git clone." }
    if (-not $state.Dirty.Count) { return [pscustomobject]@{ Committed = $false; Files = @() } }
    $files = @($state.Dirty | ForEach-Object { Get-GenePorcelainPath $_ })
    if ($WhatIf) { return [pscustomobject]@{ Committed = $false; Files = $files } }
    $existing = @($files | Where-Object { Test-Path -LiteralPath (Join-Path $Repo.ReadPath $_) -PathType Leaf })
    if ($existing.Count) {
        $hits = @(& (Join-Path $Hub 'tools\Find-Secrets.ps1') -Root $Repo.ReadPath -Files $existing)
        if ($hits.Count -and -not $AllowSecrets) {
            $list = ($hits | ForEach-Object { "$($_.File):$($_.Line) $($_.Rule) $($_.Match)" }) -join "`n  "
            throw "Possible secrets in $Label's uncommitted files; nothing was committed:`n  $list`nRemove them there, or re-run with -AllowSecrets after checking every line."
        }
    }
    Invoke-GeneRepoGit $Repo @('add', '-A') | Out-Null
    Invoke-GeneRepoGit $Repo @('commit', '-q', '-m', "prof: $Label local changes") | Out-Null
    [pscustomobject]@{ Committed = $true; Files = $files }
}

function Invoke-GeneMergeFromTarget {
    <#
    Brings the target's main into the hub: fetch over the share, then merge --no-edit here. Memory index files merge by
    union (.gitattributes). Any other conflict aborts the merge, leaves the hub as it was and throws the file list.
    #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)]$Repo)
    Invoke-GeneGit $Hub @('fetch', '-q', $Repo.Url, 'main') | Out-Null
    $incoming = [int]((Invoke-GeneGit $Hub @('rev-list', '--count', 'HEAD..FETCH_HEAD')) | Select-Object -First 1)
    if ($incoming -eq 0) { return [pscustomobject]@{ Merged = 0 } }
    $r = Invoke-GeneGitResult $Hub @('merge', '--no-edit', '-m', "prof: merge $($Repo.Name)", 'FETCH_HEAD')
    if ($r.Code -ne 0) {
        $conflicts = @((Invoke-GeneGitResult $Hub @('diff', '--name-only', '--diff-filter=U')).Out | Where-Object { $_ })
        Invoke-GeneGitResult $Hub @('merge', '--abort') | Out-Null
        throw "Merging $($Repo.Name) into $Hub conflicts in: $($conflicts -join ', '). The merge was undone; both clones are as they were. Resolve by hand: git -C `"$Hub`" fetch `"$($Repo.Url)`" main; git -C `"$Hub`" merge FETCH_HEAD; fix the files, git add, git commit; then run prof again."
    }
    [pscustomobject]@{ Merged = $incoming }
}

function Invoke-GenePushToTarget {
    <#
    Sends the hub's HEAD to the target as refs/prof/incoming (objects only cross the share; the target's work tree is
    not touched), then fast-forwards the target's main to it ON the target. Refused, with nothing changed there, when
    that is not a fast-forward or an uncommitted file would be overwritten (a Claude session wrote after the harvest).
    #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)]$Repo)
    $before = (Invoke-GeneRepoGitResult $Repo @('rev-parse', 'HEAD')).Out | Select-Object -First 1
    # A push to a folder path starts its own receive-pack, and git does not hand it our -c settings. On a clone another
    # account owns (genewe's on SMVMTR1, pushed from agenewe here) it then refuses with "dubious ownership", so
    # receive-pack gets safe.directory itself. git runs this string through sh: the quotes stop the * globbing.
    Invoke-GeneGit $Hub @('push', '-q', '--no-verify', "--receive-pack=git -c 'safe.directory=*' receive-pack", $Repo.Url, '+HEAD:refs/prof/incoming') | Out-Null
    $r = Invoke-GeneRepoGitResult $Repo @('merge', '--ff-only', '-q', 'refs/prof/incoming')
    if ($r.Code -ne 0) {
        throw "Fast-forwarding $($Repo.Name) was refused; nothing there changed: $($r.Out -join ' '). Usually a Claude session there wrote after the harvest: run prof setup push again."
    }
    $after = (Invoke-GeneRepoGitResult $Repo @('rev-parse', 'HEAD')).Out | Select-Object -First 1
    [pscustomobject]@{ From = $before; To = $after }
}

function Set-GeneTargetGitConfig {
    <# The target clone's local git config: byte-for-byte files, the hub's identity, origin = the hub's origin URL. #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)]$Repo)
    Invoke-GeneRepoGit $Repo @('config', 'core.autocrlf', 'false') | Out-Null
    foreach ($k in 'user.name', 'user.email') {
        $v = (Invoke-GeneGitResult $Hub @('config', '--get', $k)).Out | Select-Object -First 1
        if ($v) { Invoke-GeneRepoGit $Repo @('config', $k, $v) | Out-Null }
    }
    $origin = (Invoke-GeneGitResult $Hub @('remote', 'get-url', 'origin')).Out | Select-Object -First 1
    if ($origin) {
        $has = (Invoke-GeneRepoGitResult $Repo @('remote', 'get-url', 'origin')).Code -eq 0
        Invoke-GeneRepoGit $Repo @('remote', $(if ($has) { 'set-url' } else { 'add' }), 'origin', $origin) | Out-Null
    }
}

function Get-GeneRelation {
    <# How a target's HEAD relates to the hub's, without fetching: same / behind N / has commits the hub lacks. #>
    param([Parameter(Mandatory)][string]$Hub, [string]$TargetHead)
    if (-not $TargetHead) { return 'no clone' }
    $hubHead = (Invoke-GeneGit $Hub @('rev-parse', 'HEAD')) | Select-Object -First 1
    if ($hubHead -eq $TargetHead) { return 'same as hub' }
    if ((Invoke-GeneGitResult $Hub @('cat-file', '-e', "$TargetHead^{commit}")).Code -ne 0) { return 'has commits the hub lacks (prof setup pull)' }
    if ((Invoke-GeneGitResult $Hub @('merge-base', '--is-ancestor', $TargetHead, 'HEAD')).Code -eq 0) {
        $n = (Invoke-GeneGit $Hub @('rev-list', '--count', "$TargetHead..HEAD")) | Select-Object -First 1
        return "behind hub by $n (prof setup push)"
    }
    return 'diverged (prof setup push merges)'
}
