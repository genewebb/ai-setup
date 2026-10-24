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
# (fetch from it; a bundle file into it, fetched there as the side ref refs/prof/incoming) crosses the share. Every call passes -c safe.directory=*:
# command-line scope is the protected configuration git honours for that setting, for that one call. Pushing into a
# target goes as a bundle file the target's git fetches (Invoke-GenePushToTarget), not as a push over the share.

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
    Sends the hub's HEAD to the target as refs/prof/incoming (the target's work tree is not touched), then fast-forwards
    the target's main to it ON the target. Refused, with nothing changed there, when that is not a fast-forward or an
    uncommitted file would be overwritten (a Claude session wrote after the harvest).

    The commits travel as ONE bundle file written into the target's .git folder, and the target's own git fetches from
    it. A plain git push to the share path ran receive-pack on this machine against the target's .git over SMB: it
    needed safe.directory handed to it, and on SMVMTR1 (10/17) it wrote the objects and then sat for minutes without
    updating the ref.
    #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)]$Repo)
    $before = (Invoke-GeneRepoGitResult $Repo @('rev-parse', 'HEAD')).Out | Select-Object -First 1
    # Only the commits the target lacks, when the hub has its HEAD; otherwise the whole branch.
    $range = @('HEAD')
    if ($before -and (Invoke-GeneGitResult $Hub @('merge-base', '--is-ancestor', $before, 'HEAD')).Code -eq 0) { $range += "^$before" }
    $name = "prof-incoming-$(Get-Date -Format yyyyMMdd-HHmmss).bundle"
    $here = Join-Path ([IO.Path]::GetTempPath()) $name
    $thereRead = Join-Path $Repo.ReadPath ".git\$name"
    $thereLocal = Join-GeneRemotePath $Repo.Path ".git\$name"
    try {
        Invoke-GeneGit $Hub (@('bundle', 'create', '-q', $here) + $range) | Out-Null
        Copy-Item -LiteralPath $here -Destination $thereRead -Force
        $f = Invoke-GeneRepoGitResult $Repo @('fetch', '-q', '--no-write-fetch-head', $thereLocal, '+HEAD:refs/prof/incoming')
        if ($f.Code -ne 0) { throw "Fetching the bundle into $($Repo.Name) failed; nothing there changed: $($f.Out -join ' ')" }
    }
    finally { foreach ($x in $here, $thereRead) { if (Test-Path -LiteralPath $x) { Remove-Item -LiteralPath $x -Force -ErrorAction SilentlyContinue } } }
    $r = Invoke-GeneRepoGitResult $Repo @('merge', '--ff-only', '-q', 'refs/prof/incoming')
    if ($r.Code -ne 0) {
        throw "Fast-forwarding $($Repo.Name) was refused; nothing there changed: $($r.Out -join ' '). Usually a Claude session there wrote after the harvest: run prof setup push again."
    }
    $after = (Invoke-GeneRepoGitResult $Repo @('rev-parse', 'HEAD')).Out | Select-Object -First 1
    [pscustomobject]@{ From = $before; To = $after }
}

function Set-GeneTargetGitConfig {
    <#
    The target clone's local git config: byte-for-byte files, the installer's identity (-Name / -Email, asked by
    Read-GeneGitIdentity; never the hub's), and origin = the hub's repo. An origin that names the same repo with the
    account's own user (https://them@host/...) is kept, so the account's credentials keep working.
    #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)]$Repo, [string]$Name, [string]$Email)
    Invoke-GeneRepoGit $Repo @('config', 'core.autocrlf', 'false') | Out-Null
    if ($Name) { Invoke-GeneRepoGit $Repo @('config', 'user.name', $Name) | Out-Null }
    if ($Email) { Invoke-GeneRepoGit $Repo @('config', 'user.email', $Email) | Out-Null }
    $origin = (Invoke-GeneGitResult $Hub @('remote', 'get-url', 'origin')).Out | Select-Object -First 1
    if ($origin) {
        $r = Invoke-GeneRepoGitResult $Repo @('remote', 'get-url', 'origin')
        $now = if ($r.Code -eq 0) { [string]($r.Out | Select-Object -First 1) } else { '' }
        $bare = { param($u) $u -replace '^(\w+://)[^@/]+@', '$1' }
        if (-not $now) { Invoke-GeneRepoGit $Repo @('remote', 'add', 'origin', $origin) | Out-Null }
        elseif ((& $bare $now) -ne (& $bare $origin)) { Invoke-GeneRepoGit $Repo @('remote', 'set-url', 'origin', $origin) | Out-Null }
    }
}

function Get-GeneTargetIdentityDefault {
    <#
    The git identity a target account already has: the clone's own local config, else the account's global .gitconfig
    (read as a file, e.g. over the admin share). Blank when neither has it.
    #>
    param([Parameter(Mandatory)]$Repo, [string]$GlobalConfig)
    $hasClone = Test-Path -LiteralPath (Join-Path $Repo.ReadPath '.git')
    $hasGlobal = $GlobalConfig -and (Test-Path -LiteralPath $GlobalConfig)
    $get = {
        param($k)
        if ($hasClone) { $v = (Invoke-GeneRepoGitResult $Repo @('config', '--local', '--get', $k)).Out | Select-Object -First 1; if ($v) { return [string]$v } }
        if ($hasGlobal) { $v = (& git config --file $GlobalConfig --get $k 2>$null) | Select-Object -First 1; if ($v) { return [string]$v } }
        return ''
    }
    [pscustomobject]@{ Name = (& $get 'user.name'); Email = (& $get 'user.email') }
}

function Read-GeneGitIdentity {
    <# Asks for the git name and email commits on the target carry; Enter keeps the default. Both are required. #>
    param([Parameter(Mandatory)][string]$Label, [Parameter(Mandatory)]$Default, [scriptblock]$Reader)
    $ask = {
        param($what, $d)
        $a = ([string](Read-GeneText -Reader $Reader -Prompt "git $what for $Label$(if ($d) { " (Enter = $d)" })")).Trim()
        if ($a) { $a } else { [string]$d }
    }
    $name = & $ask 'user.name' $Default.Name
    $email = & $ask 'user.email' $Default.Email
    if (-not $name -or -not $email) { throw "A git name and email are needed for $Label (commits made there carry them); nothing was changed." }
    [pscustomobject]@{ Name = $name; Email = $email }
}

function Get-GenePatHint {
    <#
    The commands an account runs at its own logon so its clone can fetch and push origin itself: origin pinned to its
    own GitHub user, then a fetch, where Git Credential Manager asks for its PAT once and keeps it. prof never takes the PAT.
    #>
    param([Parameter(Mandatory)][string]$Origin, [Parameter(Mandatory)][string]$CloneLocal, [Parameter(Mandatory)][string]$Label)
    $url = $Origin -replace '^(\w+://)(?:[^@/]+@)?', '$1<github-user>@'
    "GitHub access for $Label (optional; prof setup push needs none). At a logon there run:  git -C $CloneLocal remote set-url origin $url  then  git -C $CloneLocal fetch  (Git Credential Manager asks for that account's PAT once and keeps it)."
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
