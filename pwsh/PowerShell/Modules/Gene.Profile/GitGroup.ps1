# prof git: status, push and pull for one repo's current branch.
# The repo is the folder you stand in, or -Repo <name> (a repo from this machine's profile, by folder name) or a path.
# With -Repo, prof moves this window into that repo and leaves it there.

$script:ProfGitVerbs = [ordered]@{
    status = 'What changed in the repo, and is the current branch ahead of or behind GitHub? (changes nothing)'
    push   = 'Save every change in the repo as one commit and send the current branch to GitHub (same as gpush)'
    pull   = 'Bring the current branch up to date from GitHub (only when that needs no merge)'
}
$script:ProfGitDetails = @{
    status = @(
        'Use it before a push or pull to see where the repo stands.',
        'Fetches from GitHub first (reads only), then lists changed files and says how many commits this branch',
        'has that GitHub does not (push sends them) and how many GitHub has that this branch does not (pull brings them).'
    )
    push   = @(
        'The gpush you know: stages everything under this folder (git add .), stops if a staged file looks like a',
        'secret (*.env, *secret*, *.key ...), commits with -Message (default "Update latest") when anything is',
        'staged, then pushes the current branch to origin (setting the upstream on the first push).',
        'gpush itself still works.'
    )
    pull   = @(
        'git pull --ff-only on the current branch. When this branch and GitHub both have new commits, it stops',
        'and says so instead of merging; then merge or rebase by hand.'
    )
}
$script:ProfGitUsage = @{
    status = 'prof git status [<repo>] [-WhatIf]'
    push   = 'prof git push [<repo>] [-Message <text>] [-WhatIf]'
    pull   = 'prof git pull [<repo>] [-WhatIf]'
}

$script:ProfGroups['git'] = [pscustomobject]@{
    Description = "Status, push and pull for a repo's current branch (the repo you are in, or pick one)"
    Verbs       = $script:ProfGitVerbs
    Details     = $script:ProfGitDetails
    Usage       = $script:ProfGitUsage
    Prefix      = 'Invoke-GeneProfGit'
    NeedMachine = @()
    Ask         = 'Read-GeneGitMenuParams'
    TopicParam  = 'Repo'
    TopicNames  = { @(Get-GeneKnownRepos | ForEach-Object Name) }
}

function Get-GeneLocalPath([string]$Key) {
    <# A path from this machine's profile, as the PowerShell profile loaded it ($global:GeneMachine). #>
    if (-not $global:GeneMachine) { throw 'This machine''s settings are not loaded ($global:GeneMachine). Open a new PowerShell tab so the profile loads them.' }
    return [string]$global:GeneMachine.$Key
}

function Get-GeneRepoTop([string]$Path) {
    <# The top folder of the git repo that holds Path, or $null. #>
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $null }
    $top = git -c safe.directory=* -C $Path rev-parse --show-toplevel 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $top) { return $null }
    return ([string]$top).Replace('/', '\')
}

function Get-GeneKnownRepos {
    <# Repos named in this machine's profile (every *Repo key plus AIWorkRoot) that exist here: Name (folder name), Path, Key. #>
    if (-not $global:GeneMachine) { return @() }
    # The profile keeps repo paths in $global:GeneMachine and the AI keys (AIWorkRoot) in $global:GeneMachineAI.
    $all = [ordered]@{}
    foreach ($k in @($global:GeneMachine.Keys | Where-Object { $_ -like '*Repo' })) { $all[$k] = [string]$global:GeneMachine.$k }
    if ($global:GeneMachineAI -and $global:GeneMachineAI.AIWorkRoot) { $all['AIWorkRoot'] = [string]$global:GeneMachineAI.AIWorkRoot }
    $seen = @{}
    foreach ($k in $all.Keys) {
        $p = $all[$k]
        if (-not $p -or $seen.Contains($p.ToLowerInvariant()) -or -not (Test-Path -LiteralPath (Join-Path $p '.git'))) { continue }
        $seen[$p.ToLowerInvariant()] = $true
        [pscustomobject]@{ Name = (Split-Path $p -Leaf); Path = $p; Key = $k }
    }
}

function Resolve-GeneGitRepo {
    <# -Repo -> the repo's top folder. Empty = the repo of the current folder; a name = a known repo's folder name; else a path. #>
    param([string]$Repo)
    if (-not $Repo) {
        $top = Get-GeneRepoTop (Get-Location).ProviderPath
        if (-not $top) { throw "This folder is not in a git repo: $((Get-Location).ProviderPath). Go to one, or name one: prof git status <repo> ($((@(Get-GeneKnownRepos) | ForEach-Object Name) -join ', '))" }
        return $top
    }
    $hit = @(Get-GeneKnownRepos | Where-Object { $_.Name -ieq $Repo -or $_.Key -ieq $Repo }) | Select-Object -First 1
    if ($hit) { return $hit.Path }
    $top = Get-GeneRepoTop $Repo
    if ($top) { return $top }
    throw "No repo called '$Repo'. Known here: $((@(Get-GeneKnownRepos) | ForEach-Object Name) -join ', '), or give a folder path."
}

function Enter-GeneGitRepo {
    <# Resolves the repo and, when -Repo named one, moves the window there (and leaves it there). Returns the top folder. #>
    param([string]$Repo)
    $top = Resolve-GeneGitRepo -Repo $Repo
    if ($Repo) { Set-Location -LiteralPath $top }
    $branch = ([string](git -c safe.directory=* -C $top rev-parse --abbrev-ref HEAD 2>$null)).Trim()
    Write-ProfNote "Repo: $top   branch: $branch"
    return $top
}

function Invoke-GeneProfGitStatus {
    param([string]$Repo, [switch]$WhatIf)
    $top = Enter-GeneGitRepo -Repo $Repo
    git -c safe.directory=* -C $top fetch --quiet
    if ($LASTEXITCODE -ne 0) { Write-ProfWarn 'Could not fetch from GitHub; ahead/behind below is as of the last fetch.' }
    git -c safe.directory=* -C $top status -sb
    $counts = git -c safe.directory=* -C $top rev-list --left-right --count 'HEAD...@{u}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $counts) { Write-ProfNote 'This branch is not on GitHub yet. prof git push sends it.'; return }
    $ahead, $behind = @(([string]$counts).Trim() -split '\s+')
    if ([int]$ahead -eq 0 -and [int]$behind -eq 0) { Write-ProfNote 'Same as GitHub.' }
    if ([int]$ahead -gt 0) { Write-ProfNote "$ahead commit(s) here are not on GitHub yet: prof git push sends them." }
    if ([int]$behind -gt 0) { Write-ProfNote "$behind commit(s) on GitHub are not here yet: prof git pull brings them." }
}

function Invoke-GeneProfGitPush {
    param([string]$Repo, [string]$Message, [switch]$WhatIf)
    [void](Enter-GeneGitRepo -Repo $Repo)
    if (-not (Get-Command Git-QuickPush -ErrorAction SilentlyContinue)) { Import-Module Gene.GitTools -ErrorAction Stop }
    Git-QuickPush -Message $(if ($Message) { $Message } else { 'Update latest' }) -WhatIf:$WhatIf
}

function Invoke-GeneProfGitPull {
    param([string]$Repo, [switch]$WhatIf)
    $top = Enter-GeneGitRepo -Repo $Repo
    if ($WhatIf) { Write-Host '[WhatIf] Would run: git pull --ff-only' -ForegroundColor Yellow; return }
    git -c safe.directory=* -C $top pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw 'git pull --ff-only stopped (see above). If this branch and GitHub both have new commits, merge or rebase by hand.' }
}

function Read-GeneGitMenuParams {
    <# The menu's questions for one git command. Returns the parameters, or $null when the user cancels. #>
    param([Parameter(Mandatory)][string]$Verb, [scriptblock]$Reader)
    $p = [ordered]@{}
    $here = Get-GeneRepoTop (Get-Location).ProviderPath
    $items = @()
    if ($here) { $items += [pscustomobject]@{ Name = '(this folder)'; Description = $here } }
    $items += @(Get-GeneKnownRepos | Where-Object { $_.Path -ne $here } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Description = $_.Path } })
    $items += [pscustomobject]@{ Name = '(type a folder)'; Description = '' }
    $r = Select-GeneMenu -Title 'Which repo?' -Items $items -Default 1 -Reader $Reader
    if (-not $r) { return $null }
    if ($r.Name -eq '(type a folder)') { $p.Repo = ([string](Read-GeneText -Reader $Reader -Prompt 'Repo folder')).Trim(); if (-not $p.Repo) { return $null } }
    elseif ($r.Name -ne '(this folder)') { $p.Repo = $r.Name }
    if ($Verb -eq 'push') {
        $m = ([string](Read-GeneText -Reader $Reader -Prompt 'Commit message (Enter = Update latest)')).Trim()
        if ($m) { $p.Message = $m }
    }
    if ($Verb -in 'push', 'pull' -and (Read-GeneYesNo -Question 'Dry run only (-WhatIf)?' -Reader $Reader)) { $p.WhatIf = $true }
    return $p
}
