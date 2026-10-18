# prof ai: the AI rules/settings sync (dpAI in the PowerShell profile) between the template folder (DocumentationDir)
# and a repo. The repo is the one you are in, or -Repo (a known repo by folder name, or a path); naming one moves the
# window there. dpAI's other switches (-Force, -Try, -TemplatePath ...) follow the command as they are.

$script:ProfAiModes = [ordered]@{ local = 'Local'; remote = 'Remote'; git = 'Git'; promote = 'Promote' }
$script:ProfAiVerbs = [ordered]@{
    local   = 'Copy the AI rules/settings from the template into this repo (template -> repo)'
    remote  = "Copy this repo's AI rules/settings back into the template (repo -> template)"
    git     = "Commit and push each tool's documentation repo in the template to its remote"
    promote = 'Both: this repo -> template, then commit and push the documentation repos'
}
$script:ProfAiDetails = @{
    local   = @('Use it in a repo that should get the latest rules (.cursor, .github, .claude ...). Only changed files are', 'copied unless -Force. -WhatIf previews.')
    remote  = @('Use it after improving the rules inside a repo, to make that the template. -Force overwrites all files.')
    git     = @('Publishes what the template holds; the repo you are in does not matter. -Message sets the commit message.')
    promote = @('remote and then git in one go. -Force and -Message as above.')
}
$script:ProfAiUsage = @{
    local   = 'prof ai local [<repo>] [-Force] [-WhatIf]'
    remote  = 'prof ai remote [<repo>] [-Force] [-WhatIf]'
    git     = 'prof ai git [-Message <text>] [-WhatIf]'
    promote = 'prof ai promote [<repo>] [-Message <text>] [-Force] [-WhatIf]'
}

$script:ProfGroups['ai'] = [pscustomobject]@{
    Description = 'Sync the AI rules/settings between the template and a repo, and publish the template (dpAI)'
    Verbs       = $script:ProfAiVerbs
    Details     = $script:ProfAiDetails
    Usage       = $script:ProfAiUsage
    Prefix      = 'Invoke-GeneProfAi'
    NeedMachine = @()
    Ask         = 'Read-GeneAiMenuParams'
    TopicParam  = 'Repo'
    TopicNames  = { @(Get-GeneKnownRepos | ForEach-Object Name) }
}

function Invoke-GeneAiMode {
    param([Parameter(Mandatory)][string]$Verb, [string]$Repo, [string]$Message, [object[]]$Extra, [switch]$WhatIf)
    if (-not (Get-Command dpAI -ErrorAction SilentlyContinue)) { throw 'dpAI is not loaded. It lives in the PowerShell profile: open a new tab, or . $PROFILE.' }
    $splat = ConvertTo-GeneCommandArgs -Command dpAI -Extra $Extra
    foreach ($k in 'Local', 'Remote', 'Git', 'Promote') { if ($splat.Contains($k)) { throw "The mode is the command (prof ai $($k.ToLowerInvariant())); drop -$k." } }
    $splat[$script:ProfAiModes[$Verb]] = $true
    if ($Verb -ne 'git') { $splat.RepoPath = Enter-GeneGitRepo -Repo $Repo }
    elseif ($Repo) { Write-ProfWarn 'prof ai git publishes the template; the repo is not used.' }
    if ($Message) { $splat.Message = $Message }
    if ($WhatIf) { $splat.WhatIf = $true }
    $shown = @('dpAI') + @($splat.Keys | ForEach-Object { $v = $splat[$_]; if ($v -is [bool] -or $v -is [switch]) { if ($v) { "-$_" } } else { "-$_ $v" } })
    Write-ProfNote "Running: $($shown -join ' ')"
    dpAI @splat
}

function Invoke-GeneProfAiLocal { param([string]$Repo, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneAiMode local -Repo $Repo -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfAiRemote { param([string]$Repo, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneAiMode remote -Repo $Repo -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfAiGit { param([string]$Repo, [string]$Message, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneAiMode git -Repo $Repo -Message $Message -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfAiPromote { param([string]$Repo, [string]$Message, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneAiMode promote -Repo $Repo -Message $Message -Extra $Extra -WhatIf:$WhatIf }

function Read-GeneAiMenuParams {
    <# The menu's questions for one ai command. Returns the parameters, or $null when the user cancels. #>
    param([Parameter(Mandatory)][string]$Verb, [scriptblock]$Reader)
    $p = [ordered]@{}
    if ($Verb -ne 'git') {
        $here = Get-GeneRepoTop (Get-Location).ProviderPath
        $items = @()
        if ($here) { $items += [pscustomobject]@{ Name = '(this folder)'; Description = $here } }
        $items += @(Get-GeneKnownRepos | Where-Object { $_.Path -ne $here } | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Description = $_.Path } })
        $r = Select-GeneMenu -Title 'Which repo?' -Items $items -Default 1 -Reader $Reader
        if (-not $r) { return $null }
        if ($r.Name -ne '(this folder)') { $p.Repo = $r.Name }
    }
    $yn = { param($q, $d = $false) Read-GeneYesNo -Question $q -Default $d -Reader $Reader }
    if ($Verb -in 'git', 'promote') {
        $m = ([string](Read-GeneText -Reader $Reader -Prompt 'Commit message (Enter = default)')).Trim()
        if ($m) { $p.Message = $m }
    }
    if ($Verb -ne 'git' -and (& $yn 'Overwrite every file, not only changed ones (-Force)?')) { $p.Extra = @('-Force') }
    if (& $yn 'Dry run only (-WhatIf)?' $true) { $p.WhatIf = $true }
    return $p
}
