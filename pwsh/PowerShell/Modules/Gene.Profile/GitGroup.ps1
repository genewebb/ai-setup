# prof git: status, push and pull for one repo's current branch.
# The repo is the folder you stand in, or -Repo <name> (a repo from this machine's profile, by folder name) or a path.
# With -Repo, prof moves this window into that repo and leaves it there.

$script:ProfGitVerbs = [ordered]@{
    status = 'What changed in the repo, and is the current branch ahead of or behind the server? (changes nothing)'
    push   = 'Save every change in the repo as one commit and send the current branch (gpush)'
    pull   = 'Bring the current branch up to date from the server (only when that needs no merge)'
    main   = 'Go to main and pull'
    new    = 'Switch to a branch by name (asks for the name; makes the branch when it does not exist yet)'
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
        'gpush itself still works. The PowerShell and SQL scripts folders are repos here too: prof git push',
        'PowershellScripts replaces pps, prof git push SqlScripts replaces psql.'
    )
    pull   = @(
        'git pull --ff-only on the current branch. When this branch and GitHub both have new commits, it stops',
        'and says so instead of merging; then merge or rebase by hand.'
    )
    main   = @(
        'git switch main, then git pull --ff-only. Stops before switching when the repo has uncommitted changes,',
        'so they are not carried onto main; commit (prof git push) or put them aside first.'
    )
    new    = @(
        'git switch <name> when the branch exists here, else git switch -c <name> (a new branch from where you stand).',
        'Uncommitted changes come along to the branch. prof git push sends the new branch to the server.'
    )
}
$script:ProfGitUsage = @{
    status = 'prof git status [<repo>] [-WhatIf]'
    push   = 'prof git push [<repo>] [-Message <text>] [-WhatIf]'
    pull   = 'prof git pull [<repo>] [-WhatIf]'
    main   = 'prof git main [<repo>] [-WhatIf]'
    new    = 'prof git new [<repo>] -Branch <name> [-WhatIf]'
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
    <# Repos named in this machine's profile that exist here (every *Repo key, the script folders, AIWorkRoot): Name (folder name), Path, Key. #>
    if (-not $global:GeneMachine) { return @() }
    # The profile keeps repo paths in $global:GeneMachine and the AI keys (AIWorkRoot) in $global:GeneMachineAI.
    $all = [ordered]@{}
    foreach ($k in @($global:GeneMachine.Keys | Where-Object { $_ -like '*Repo' -or $_ -in 'PowershellScriptsDir', 'SqlScriptsDir' })) { $all[$k] = [string]$global:GeneMachine.$k }
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

function Get-GeneGitSync {
    <# Fetches, then compares the branch with its server copy: Fetched, Upstream (has one), Ahead, Behind, Dirty (uncommitted changes). #>
    param([Parameter(Mandatory)][string]$Top)
    git -c safe.directory=* -C $Top fetch --quiet
    $fetched = $LASTEXITCODE -eq 0
    $dirty = [bool](git -c safe.directory=* -C $Top status --porcelain)
    $counts = git -c safe.directory=* -C $Top rev-list --left-right --count 'HEAD...@{u}' 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $counts) { return [pscustomobject]@{ Fetched = $fetched; Upstream = $false; Ahead = 0; Behind = 0; Dirty = $dirty } }
    $ahead, $behind = @(([string]$counts).Trim() -split '\s+')
    [pscustomobject]@{ Fetched = $fetched; Upstream = $true; Ahead = [int]$ahead; Behind = [int]$behind; Dirty = $dirty }
}

function Invoke-GeneProfGitStatus {
    param([string]$Repo, [switch]$WhatIf)
    $top = Enter-GeneGitRepo -Repo $Repo
    $sync = Get-GeneGitSync $top
    if (-not $sync.Fetched) { Write-ProfWarn 'Could not fetch from the server; ahead/behind below is as of the last fetch.' }
    git -c safe.directory=* -C $top status -sb
    if (-not $sync.Upstream) { Write-ProfNote 'This branch is not on the server yet. prof git push sends it.'; return }
    if ($sync.Ahead -eq 0 -and $sync.Behind -eq 0) { Write-ProfNote 'Same as the server.' }
    if ($sync.Ahead -gt 0) { Write-ProfNote "$($sync.Ahead) commit(s) here are not on the server yet: prof git push sends them." }
    if ($sync.Behind -gt 0) { Write-ProfNote "$($sync.Behind) commit(s) on the server are not here yet: prof git pull brings them." }
}

function Invoke-GeneProfGitPush {
    param([string]$Repo, [string]$Message, [switch]$WhatIf)
    $top = Enter-GeneGitRepo -Repo $Repo
    # Check against the server first, so "behind" and "nothing to do" are said plainly instead of as git's push rejection.
    $sync = Get-GeneGitSync $top
    $pull = "prof git pull$(if ($Repo) { " $Repo" })"
    if (-not $sync.Fetched) { Write-ProfWarn 'Could not fetch from the server; pushing anyway (git refuses if the server has newer commits).' }
    elseif ($sync.Behind -gt 0) {
        if (-not $sync.Dirty -and $sync.Ahead -eq 0) {
            Write-ProfNote "Nothing to commit or push here. The server has $($sync.Behind) newer commit(s): $pull brings them."
            return
        }
        throw "The server has $($sync.Behind) newer commit(s) this copy does not have. Nothing was committed or pushed. Pull first ($pull); with commits of your own here ($($sync.Ahead)), merge or rebase by hand."
    }
    elseif ($sync.Upstream -and -not $sync.Dirty -and $sync.Ahead -eq 0) {
        Write-ProfNote 'Nothing to commit or push: same as the server.'
        return
    }
    if (-not (Get-Command Git-QuickPush -ErrorAction SilentlyContinue)) { Import-Module Gene.GitTools -ErrorAction Stop }
    # Some clones belong to the other account (ai-profisee is CORP\genewe's), which git refuses as "dubious ownership".
    # Git-QuickPush runs plain git, so trust every folder through git's environment config for this one call.
    $saved = @{}; foreach ($n in 'GIT_CONFIG_COUNT', 'GIT_CONFIG_KEY_0', 'GIT_CONFIG_VALUE_0') { $saved[$n] = [Environment]::GetEnvironmentVariable($n) }
    $env:GIT_CONFIG_COUNT = '1'; $env:GIT_CONFIG_KEY_0 = 'safe.directory'; $env:GIT_CONFIG_VALUE_0 = '*'
    try { Git-QuickPush -Message $(if ($Message) { $Message } else { 'Update latest' }) -WhatIf:$WhatIf }
    finally { foreach ($n in $saved.Keys) { [Environment]::SetEnvironmentVariable($n, $saved[$n]) } }
}

function Invoke-GeneProfGitPull {
    param([string]$Repo, [switch]$WhatIf)
    $top = Enter-GeneGitRepo -Repo $Repo
    if ($WhatIf) { Write-Host '[WhatIf] Would run: git pull --ff-only' -ForegroundColor Yellow; return }
    git -c safe.directory=* -C $top pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw 'git pull --ff-only stopped (see above). If this branch and the server both have new commits, merge or rebase by hand.' }
}

function Invoke-GeneProfGitMain {
    param([string]$Repo, [switch]$WhatIf)
    $top = Enter-GeneGitRepo -Repo $Repo
    if ($WhatIf) { Write-Host '[WhatIf] Would run: git switch main, then git pull --ff-only' -ForegroundColor Yellow; return }
    if (git -c safe.directory=* -C $top status --porcelain) { throw 'This repo has uncommitted changes; nothing was switched. Commit them (prof git push) or put them aside, then run prof git main again.' }
    git -c safe.directory=* -C $top switch main
    if ($LASTEXITCODE -ne 0) { throw 'git switch main stopped (see above).' }
    git -c safe.directory=* -C $top pull --ff-only
    if ($LASTEXITCODE -ne 0) { throw 'git pull --ff-only stopped (see above). If main here and the server both have new commits, merge or rebase by hand.' }
}

function Invoke-GeneProfGitNew {
    param([string]$Repo, [string]$Branch, [switch]$WhatIf)
    if (-not $Branch) { throw 'Give the branch name: prof git new [<repo>] -Branch <name> (the menu asks for it).' }
    git check-ref-format --branch $Branch 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "'$Branch' is not a valid branch name." }
    $top = Enter-GeneGitRepo -Repo $Repo
    git -c safe.directory=* -C $top show-ref --verify --quiet "refs/heads/$Branch"
    $gitArgs = if ($LASTEXITCODE -eq 0) { @('switch', $Branch) } else { @('switch', '-c', $Branch) }
    if ($WhatIf) { Write-Host "[WhatIf] Would run: git $($gitArgs -join ' ')" -ForegroundColor Yellow; return }
    git -c safe.directory=* -C $top @gitArgs
    if ($LASTEXITCODE -ne 0) { throw "git $($gitArgs -join ' ') stopped (see above)." }
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
    if ($Verb -eq 'new') {
        $p.Branch = ([string](Read-GeneText -Reader $Reader -Prompt 'Branch name')).Trim()
        if (-not $p.Branch) { return $null }
    }
    if ($Verb -in 'push', 'pull', 'main', 'new' -and (Read-GeneYesNo -Question 'Dry run only (-WhatIf)?' -Reader $Reader)) { $p.WhatIf = $true }
    return $p
}
