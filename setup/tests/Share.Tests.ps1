#requires -Version 7
# prof setup share (Gene.Profile\Share.ps1): the offer, the repo state, the pick, the closure (pulled commands, modules,
# machine keys), the key questions and the -WhatIf plan. A fixture hub and a temp git clone stand in for the real ones.
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mod = Join-Path $repoRoot 'pwsh\PowerShell\Modules\Gene.Profile'
foreach ($f in 'Target.ps1', 'Menu.ps1', 'Verbs.ps1', 'OtherGroup.ps1', 'Share.ps1') { . (Join-Path $mod $f) }

$root = New-TestRoot 'share'
function New-Queue([string[]]$Answers) { $q = [System.Collections.Generic.Queue[string]]::new(); foreach ($a in $Answers) { $q.Enqueue($a) }; { param($p) $q.Dequeue() }.GetNewClosure() }
function Write-File([string]$Path, [string]$Text) { New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null; Set-Content -LiteralPath $Path -Value $Text -Encoding utf8NoBOM }

# ---------------------------------------------------------------- fixture hub: profile.d files with real catalog names
$hub = Join-Path $root 'hub'
$pd = Join-Path $hub 'pwsh\PowerShell\profile.d'
Write-File "$pd\navigate.ps1" @'
function cdevops { Set-Location $global:GeneMachine.ReposRoot }
function cspeed { $p = $global:GeneMachine['SpeedMerchantsRepo']; Set-Location $p }
function csql { Set-Location $global:GeneMachine.SqlScriptsDir }
'@
Write-File "$pd\build.ps1" @'
function Publish-GeneSharedBits { $h = $global:GeneMachine.SharedBitsHost; if ($global:GeneMachine.Contains('SharedBitsShare')) { $null } }
function Publish-SpeedMerchantsPackage { $share = $global:GeneMachine['PackageShare']; Publish-GeneSharedBits; $zip = Get-GeneBitsZipPath }
function dpspeed { $s = Get-GeneMachineSetting -Name LocalSpeedSecretsFile -MustExist; Publish-SpeedMerchantsPackage }
function dpcrewchief { Write-Host ($global:GeneMachine.Keys -join ',') }
function dpall { dpspeed; dpcrewchief }
'@
Write-File "$pd\board.ps1" @'
function addStreams { $global:GeneMachine.StreamMaxAuthors }
'@
Write-File "$pd\profile.ps1" @'
function sp { 'hub' }
function ep { 'hub' }
function rp { . $PROFILE }
'@
Write-File "$pd\tools.ps1" @'
function newguid { [guid]::NewGuid().ToString() }
function markitdown { $global:GeneMachine.MarkitdownVenv }
'@
Write-File "$pd\claude.ps1" @'
function Get-ClaudeAccount { 'x' }
Set-Alias -Name claude-which -Value Get-ClaudeAccount -Scope Global
'@
Write-File "$hub\pwsh\PowerShell\Modules\Gene.DevOpsTools\Gene.DevOpsTools.psm1" @'
function Get-GeneMachineRoot([string]$Key, [string]$Default) { if ($global:GeneMachine -and $global:GeneMachine[$Key]) { return $global:GeneMachine[$Key] }; return $Default }
function Get-GeneBitsZipPath { Join-Path (Get-GeneMachineRoot BitsDir 'C:\Bits') 'x.zip' }
'@
Write-File "$hub\pwsh\PowerShell\Modules\Gene.GitTools\Gene.GitTools.psm1" @'
function Get-GeneMachineRoot([string]$Key, [string]$Default) { if ($global:GeneMachine -and $global:GeneMachine[$Key]) { return $global:GeneMachine[$Key] }; return $Default }
function Push-SqlScripts { Get-GeneMachineRoot SqlScriptsDir 'D:\SqlScripts' }
'@
Write-File "$hub\pwsh\PowerShell\Modules\Gene.Profile\BuildGroup.ps1" @'
function Invoke-GeneProfBuildRun { $global:GeneMachine.BitsDir }
'@
Write-File "$hub\pwsh\PowerShell\Modules\Gene.Profile\GitGroup.ps1" 'function Invoke-GeneProfGitPush { }'
Write-File "$hub\pwsh\PowerShell\Modules\Gene.Profile\SetupGroup.ps1" 'function Invoke-GeneProfPush { }'
foreach ($f in 'Gene.Profile.psm1', 'Gene.Profile.psd1', 'Menu.ps1', 'Verbs.ps1', 'OtherGroup.ps1') { Copy-Item -LiteralPath (Join-Path $mod $f) -Destination "$hub\pwsh\PowerShell\Modules\Gene.Profile\$f" }
Write-File "$hub\pwsh\PowerShell\Modules\Gene.Completions\Gene.Completions.psm1" 'function Enable-DotnetSuggestCompletions { }'
Write-File "$hub\pwsh\PowerShell\Modules\Gene.Completions\Gene.Completions.psd1" "@{ RootModule = 'Gene.Completions.psm1'; ModuleVersion = '1.0' }"
Write-File "$hub\pwsh\PowerShell\Modules\Gene.Completions\old.psm1.bak" 'never copied'
Write-File "$hub\pwsh\PowerShell\powershell.config.json" '{"Microsoft.PowerShell:ExecutionPolicy":"RemoteSigned"}'
Write-File "$hub\pwsh\modules.txt" "# PSGallery modules`nPowerShell PwshSpectreConsole`nPowerShell BurntToast`nWindowsPowerShell posh-git"
Write-File "$hub\pwsh\PowerShell\Microsoft.PowerShell_profile.ps1" @'
# core (fixture)
$global:GeneMachineDefaults = [ordered]@{
    ReposRoot = 'C:\devops\repos'
    # a comment between rows
    BitsDir   = "C:\Bits"
    Empty     = ''
}
function Test-HelpRequested { $false }
foreach ($geneCategoryFile in Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'profile.d') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name) { . $geneCategoryFile.FullName }
'@
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\Find-Secrets.ps1') -Destination (New-Item -ItemType Directory -Force -Path "$hub\tools").FullName
Write-File "$hub\share.yaml" "blockedPatterns:`n  - 'owner1'`n  - 'BOX7'"
Write-File "$hub\pwsh\Install-Profile.ps1" '# installer stub (fixture)'
$env:GENE_PROF_HUB = $hub
$env:GENE_SHARE_STAGE = Join-Path $root 'stage-root'

# ---------------------------------------------------------------- fixture repo: a git clone, clean
function New-ShareRepo([string]$Name) {
    $r = Join-Path $root $Name
    git init -q -b main $r
    git -C $r config user.name t; git -C $r config user.email t@t; git -C $r config core.autocrlf false
    Write-File "$r\README.md" 'coworker repo'
    git -C $r add -A; git -C $r commit -q -m init
    return $r
}
$repo = New-ShareRepo 'repo'
$global:GeneMachine = [ordered]@{ ReposRoot = 'C:\devops\repos'; SpeedMerchantsRepo = 'C:\devops\repos\speed-merchants'; SqlScriptsDir = 'D:\SqlScripts'; PackageShare = '\\NAS\share'; LocalSpeedSecretsFile = 'D:\secrets\x.json'; BitsDir = 'C:\Bits'; MarkitdownVenv = '%USERPROFILE%\.venvs\markitdown'; SharedBitsHost = ''; SharedBitsShare = '' }
$global:GeneMachineAI = [ordered]@{}

try {
    # ---------------------------------------------------------------- repo
    Test-Case 'repo: -Repo wins, then GENE_SHARE_REPO, then the ShareRepo row of the machine profile; none = a clear error' {
        Assert-Equal 'X:\r' (Get-GeneShareRepo -Repo 'X:\r')
        $env:GENE_SHARE_REPO = 'Y:\r'
        try { Assert-Equal 'Y:\r' (Get-GeneShareRepo) } finally { $env:GENE_SHARE_REPO = $null }
        $cfg = Join-Path $root 'cfg.md'
        New-TestProfile -Path $cfg -Keys ([ordered]@{ ReposRoot = 'C:\devops\repos'; ShareRepo = 'Z:\dba' })
        $env:AI_MACHINE_CONFIG = $cfg
        try { Assert-Equal 'Z:\dba' (Get-GeneShareRepo) } finally { $env:AI_MACHINE_CONFIG = $null }
        $env:AI_MACHINE_CONFIG = (Join-Path $root 'none.md')
        try { Assert-Throws { Get-GeneShareRepo } '*No ShareRepo*' } finally { $env:AI_MACHINE_CONFIG = $null }
    }
    Test-Case 'repo: not a clone refuses; a dirty ai\ from a previous share refuses; a clean clone passes' {
        Assert-Throws { Assert-GeneShareRepo -Repo (Join-Path $root 'notarepo') } '*not a git clone*'
        Assert-GeneShareRepo -Repo $repo
        Write-File "$repo\ai\profile\x.txt" 'left over'
        try { Assert-Throws { Assert-GeneShareRepo -Repo $repo } '*uncommitted change*' } finally { Remove-Item -LiteralPath "$repo\ai" -Recurse -Force }
        Write-File "$repo\other.txt" 'not ours'
        try { Assert-GeneShareRepo -Repo $repo } finally { Remove-Item -LiteralPath "$repo\other.txt" -Force }
    }

    # ---------------------------------------------------------------- offer
    Test-Case 'offer: catalog categories with a profile.d file, in catalog order; board never; sp/ep never; undefined catalog commands not offered' {
        $o = @(Get-GeneShareOffer -Hub $hub)
        Assert-Equal @('navigate', 'build', 'profile', 'claude', 'tools') @($o.Category)
        Assert-Equal @('cdevops', 'cspeed', 'csql') @(($o | Where-Object Category -eq navigate).Commands.Name)
        Assert-Equal @('dpspeed', 'dpcrewchief', 'dpall', 'Publish-SpeedMerchantsPackage') @(($o | Where-Object Category -eq build).Commands.Name) 'catalog order, and a cataloged helper is offered too'
        Assert-Equal @('rp') @(($o | Where-Object Category -eq profile).Commands.Name)
        Assert-Equal @('claude-which') @(($o | Where-Object Category -eq claude).Commands.Name) 'an alias to a function counts'
        Assert-Equal @('markitdown', 'newguid') @(($o | Where-Object Category -eq tools).Commands.Name) 'clearSeq is not in the file'
    }

    # ---------------------------------------------------------------- state
    Test-Case 'state: an empty repo holds nothing' {
        $s = Get-GeneShareState -Repo $repo
        Assert-Equal 0 $s.Categories.Count; Assert-Equal 0 $s.Keys.Count; Assert-True ($null -eq $s.Manifest)
    }
    Test-Case 'state: the manifest gives the commands per category and the template the key values' {
        $r2 = New-ShareRepo 'repo-state'
        Write-File "$r2\ai\profile\prof-share.json" '{ "categories": { "navigate": ["cdevops", "cspeed"], "build": ["dpspeed"] }, "keys": {} }'
        Write-File "$r2\ai\profile\ProfileMachineConfig.md" "| Key | Value | Used by | Status |`n|---|---|---|---|`n| ReposRoot |  | cdevops | fill in |`n| PackageShare | \\NAS\share | dpspeed | set |"
        $s = Get-GeneShareState -Repo $r2
        Assert-Equal @('navigate', 'build') @($s.Categories.Keys)
        Assert-Equal @('cdevops', 'cspeed') @($s.Categories['navigate'])
        Assert-Equal '' $s.Keys['ReposRoot']; Assert-Equal '\\NAS\share' $s.Keys['PackageShare']
    }
    Test-Case 'state: without a manifest, the profile.d files present say what is shared' {
        $r3 = New-ShareRepo 'repo-files'
        Write-File "$r3\ai\profile\PowerShell\profile.d\navigate.ps1" 'function cdevops { }'
        $s = Get-GeneShareState -Repo $r3
        Assert-Equal @('navigate') @($s.Categories.Keys); Assert-Equal @('cdevops') @($s.Categories['navigate'])
    }

    # ---------------------------------------------------------------- pick
    $offer = @(Get-GeneShareOffer -Hub $hub)
    Test-Case 'pick: nothing shared yet -> categories then commands by number; empty pick drops the category' {
        $s = Get-GeneShareState -Repo $repo
        $p = Read-GeneSharePicks -Offer $offer -State $s -Reader (New-Queue @('1,2', '1 3', ''))
        Assert-Equal @('navigate') @($p.Keys)
        Assert-Equal @('cdevops', 'csql') @($p['navigate'])
    }
    Test-Case 'pick: q cancels at either level' {
        $s = Get-GeneShareState -Repo $repo
        Assert-True ($null -eq (Read-GeneSharePicks -Offer $offer -State $s -Reader (New-Queue @('q'))))
        Assert-True ($null -eq (Read-GeneSharePicks -Offer $offer -State $s -Reader (New-Queue @('1', 'q'))))
    }
    Test-Case 'pick: what the repo holds is kept on Enter, re-picked on n' {
        $s = [pscustomobject]@{ Categories = [ordered]@{ navigate = @('cdevops', 'cspeed'); build = @('dpspeed') }; Keys = [ordered]@{}; Manifest = $null }
        $p = Read-GeneSharePicks -Offer $offer -State $s -Reader (New-Queue @('', '', ''))
        Assert-Equal @('navigate', 'build') @($p.Keys); Assert-Equal @('cdevops', 'cspeed') @($p['navigate']); Assert-Equal @('dpspeed') @($p['build'])
        $p = Read-GeneSharePicks -Offer $offer -State $s -Reader (New-Queue @('n', '2', 'n', '2,3'))
        Assert-Equal @('build') @($p.Keys); Assert-Equal @('dpcrewchief', 'dpall') @($p['build'])
    }

    # ---------------------------------------------------------------- closure
    Test-Case 'closure: a picked command pulls in the catalog commands it calls, the module it reaches, and every key on the way' {
        $c = Resolve-GeneShareClosure -Hub $hub -Picks ([ordered]@{ build = @('dpall') }) -Offer $offer
        $b = $c.Categories['build']
        Assert-Equal @('dpall') @($b.Picked)
        Assert-Equal @('dpspeed', 'dpcrewchief', 'Publish-SpeedMerchantsPackage') @($b.Pulled) 'every cataloged command the pick reaches'
        Assert-Equal @('dpall', 'dpcrewchief', 'dpspeed', 'Publish-GeneSharedBits', 'Publish-SpeedMerchantsPackage') @($b.Functions | Sort-Object)
        Assert-Equal @('Gene.DevOpsTools') @($b.Modules)
        Assert-Equal @('BuildGroup.ps1') @($b.GroupFiles)
        Assert-Equal @('BitsDir', 'LocalSpeedSecretsFile', 'PackageShare', 'SharedBitsHost') @($c.Keys.Keys) 'GeneMachine.Keys / .Contains are not keys; BitsDir comes from the module and the group file'
        Assert-Equal @('dpall', 'prof build') @($c.Keys['BitsDir'])
        Assert-Equal @('dpall') @($c.Keys['PackageShare'])
    }
    Test-Case 'closure: a plain pick reaches no module, pulls nothing; keys name the commands that read them' {
        $c = Resolve-GeneShareClosure -Hub $hub -Picks ([ordered]@{ navigate = @('cdevops', 'cspeed') }) -Offer $offer
        $n = $c.Categories['navigate']
        Assert-Equal @() @($n.Pulled); Assert-Equal @() @($n.Modules); Assert-Equal @() @($n.GroupFiles)
        Assert-Equal @('ReposRoot', 'SpeedMerchantsRepo') @($c.Keys.Keys)
        Assert-Equal @('cspeed') @($c.Keys['SpeedMerchantsRepo'])
    }
    Test-Case 'closure: an alias pick resolves to its function' {
        $c = Resolve-GeneShareClosure -Hub $hub -Picks ([ordered]@{ claude = @('claude-which') }) -Offer $offer
        Assert-Equal @('Get-ClaudeAccount') @($c.Categories['claude'].Functions)
    }
    Test-Case 'closure: an unknown category or command is refused' {
        Assert-Throws { Resolve-GeneShareClosure -Hub $hub -Picks ([ordered]@{ board = @('addStreams') }) -Offer $offer } "*not a category*"
        Assert-Throws { Resolve-GeneShareClosure -Hub $hub -Picks ([ordered]@{ navigate = @('sp') }) -Offer $offer } "*not a command*"
    }
    Test-Case 'key reads: member, index, -Name, positional, Get-GeneMachineRoot; non-key members ignored' {
        $f = Join-Path $root 'keys.ps1'
        Write-File $f @'
function t {
    $a = $global:GeneMachine.AlphaKey
    $b = $global:GeneMachine['BetaKey']
    $c = Get-GeneMachineSetting -Name GammaKey -MustExist
    $d = Get-GeneMachineSetting DeltaKey
    $e = Get-GeneMachineRoot EpsilonKey 'C:\x'
    $n = $global:GeneMachine.Keys; if ($global:GeneMachine.Contains('x')) { }
}
'@
        Assert-Equal @('AlphaKey', 'BetaKey', 'DeltaKey', 'EpsilonKey', 'GammaKey') @(Get-GeneShareKeyReads -Ast (Get-GeneShareAst -Path $f))
    }

    # ---------------------------------------------------------------- key questions
    Test-Case 'keys: default is blank, my value when %USERPROFILE%-relative, keep when the repo has a value; typed works; q cancels' {
        $keys = [ordered]@{ ReposRoot = @('cdevops'); MarkitdownVenv = @('markitdown'); PackageShare = @('dpspeed'); BitsDir = @('dpspeed') }
        $s = [pscustomobject]@{ Categories = [ordered]@{}; Keys = [ordered]@{ PackageShare = '\\OLD\share' }; Manifest = $null }
        $v = Read-GeneShareKeyValues -Keys $keys -State $s -Reader (New-Queue @('', '', '', '3', 'C:\MyBits'))
        Assert-Equal '' $v['ReposRoot'] 'blank by default'
        Assert-Equal '%USERPROFILE%\.venvs\markitdown' $v['MarkitdownVenv'] 'my value by default when per-user'
        Assert-Equal '\\OLD\share' $v['PackageShare'] 'keeps the repo value by default'
        Assert-Equal 'C:\MyBits' $v['BitsDir'] 'typed'
        $v = Read-GeneShareKeyValues -Keys ([ordered]@{ ReposRoot = @('cdevops') }) -State $s -Reader (New-Queue @('2'))
        Assert-Equal 'C:\devops\repos' $v['ReposRoot'] 'my value on request'
        Assert-True ($null -eq (Read-GeneShareKeyValues -Keys $keys -State $s -Reader (New-Queue @('q'))))
    }

    # ---------------------------------------------------------------- trim and copy
    Test-Case 'trim: unpicked catalog functions go with their own comment lines and alias lines; helpers and banners stay; one blank line remains' {
        $f = Join-Path $root 'trim.ps1'
        Write-File $f @'
# -----------------------------
# Quick nav (banner stays)
# -----------------------------
function cdevops { 1 }

# cspeed: goes to speed-merchants (this comment goes with it)
# second comment line
function cspeed {
    2
}
Set-Alias -Name csp -Value cspeed
Set-Alias cdv cdevops

function Get-Helper { 'helper stays' }

function csql { 3 }
'@
        $t = Edit-GeneShareCategoryText -Path $f -Catalog @('cdevops', 'cspeed', 'csql', 'csp') -Keep @('cdevops')
        Assert-Match $t 'Quick nav \(banner stays\)'
        Assert-Match $t 'function cdevops'
        Assert-Match $t 'Set-Alias cdv cdevops'
        Assert-Match $t 'function Get-Helper'
        Assert-NoMatch $t 'cspeed|csql|csp\b|this comment goes with it|second comment line'
        Assert-NoMatch $t '\n\s*\n\s*\n' 'no run of blank lines'
        $out = Join-Path $root 'trim-out.ps1'; Set-Content -LiteralPath $out -Value $t
        $m = Get-GeneShareFileMap -Path $out
        Assert-Equal @('cdevops', 'Get-Helper') @($m.Functions.Keys); Assert-Equal @('cdv') @($m.Aliases.Keys)
    }
    Test-Case 'trim: keeping an alias keeps the function behind it; keeping nothing cuts every cataloged function' {
        $t = Edit-GeneShareCategoryText -Path "$pd\claude.ps1" -Catalog @('claude-which') -Keep @('claude-which')
        Assert-Match $t 'function Get-ClaudeAccount'; Assert-Match $t 'Set-Alias -Name claude-which'
        $t = Edit-GeneShareCategoryText -Path "$pd\navigate.ps1" -Catalog @('cdevops', 'cspeed', 'csql')
        Assert-NoMatch $t 'function'
    }
    Test-Case 'core: every GeneMachineDefaults value is emptied, the rest of the file is untouched, and it still parses' {
        $t = Edit-GeneShareCoreText -Path "$hub\pwsh\PowerShell\Microsoft.PowerShell_profile.ps1"
        Assert-Match $t "ReposRoot = ''"; Assert-Match $t "BitsDir   = ''"; Assert-Match $t "Empty     = ''"
        Assert-NoMatch $t 'C:\\devops|C:\\Bits'
        Assert-Match $t '# a comment between rows'; Assert-Match $t 'function Test-HelpRequested'
        $out = Join-Path $root 'core-out.ps1'; Set-Content -LiteralPath $out -Value $t
        $v = pwsh -NoProfile -Command "`$global:GeneMachineDefaults = `$null; . '$out' 2>&1 | Out-Null; (`$global:GeneMachineDefaults.Values | ForEach-Object { [string]`$_ }) -join '|'"
        Assert-Equal '||' $v
    }
    Test-Case 'tree: the staged tree holds the core, trimmed picked categories, the hub core files plus picked group files, reached modules, Completions, config and the usable module rows' {
        $plan = Invoke-GeneProfShare -What profile -Repo $repo -WhatIf -Reader (New-Queue @('2', '1', '', '', '', ''))
        $stage = Join-Path $root 'stage'
        $files = New-GeneShareProfileTree -Plan $plan -Stage $stage
        Assert-Equal @(
            'modules.txt'
            'PowerShell\Microsoft.PowerShell_profile.ps1'
            'PowerShell\Modules\Gene.Completions\Gene.Completions.psd1'
            'PowerShell\Modules\Gene.Completions\Gene.Completions.psm1'
            'PowerShell\Modules\Gene.DevOpsTools\Gene.DevOpsTools.psm1'
            'PowerShell\Modules\Gene.Profile\BuildGroup.ps1'
            'PowerShell\Modules\Gene.Profile\Gene.Profile.psd1'
            'PowerShell\Modules\Gene.Profile\Gene.Profile.psm1'
            'PowerShell\Modules\Gene.Profile\Menu.ps1'
            'PowerShell\Modules\Gene.Profile\OtherGroup.ps1'
            'PowerShell\Modules\Gene.Profile\Verbs.ps1'
            'PowerShell\powershell.config.json'
            'PowerShell\profile.d\build.ps1'
        ) @($files | Sort-Object)
        $b = Get-GeneShareFileMap -Path "$stage\PowerShell\profile.d\build.ps1"
        Assert-Equal @('dpspeed', 'Publish-GeneSharedBits', 'Publish-SpeedMerchantsPackage') @($b.Functions.Keys | Sort-Object)
        Assert-NoMatch (Get-Content -LiteralPath "$stage\PowerShell\Microsoft.PowerShell_profile.ps1" -Raw) 'C:\\devops'
        Assert-Equal @('# PSGallery modules', 'PowerShell PwshSpectreConsole') @(Get-Content -LiteralPath "$stage\modules.txt")
        Assert-True (-not (Test-Path "$stage\PowerShell\Modules\Gene.Profile\SetupGroup.ps1")) 'SetupGroup never ships'
        Assert-True (-not (Test-Path "$stage\PowerShell\Modules\Gene.GitTools")) 'GitTools not reached'
    }
    Test-Case 'tree: the REAL hub trimmed to navigate + build loads in a fresh pwsh; prof lists other + build only; defaults are empty' {
        $env:GENE_PROF_HUB = $repoRoot
        try {
            # navigate + build; cdevops + csm; dpspeed; then Enter (blank) for every key the pick reads
            $plan = Invoke-GeneProfShare -What profile -Repo $repo -WhatIf -Reader (New-Queue (@('1,3', '1,4', '1') + @('') * 30))
            Assert-Equal @('navigate', 'build') @($plan.Picks.Keys)
            Assert-Equal @('cdevops', 'csm') @($plan.Picks['navigate']); Assert-Equal @('dpspeed') @($plan.Picks['build'])
            $stage = Join-Path $root 'stage-real'
            $files = New-GeneShareProfileTree -Plan $plan -Stage $stage
            Assert-True ($files -contains 'PowerShell\Modules\Gene.Profile\BuildGroup.ps1')
            Assert-True ($files -notcontains 'PowerShell\Modules\Gene.Profile\GitGroup.ps1')
            $probe = @"
`$env:PSModulePath = '$stage\PowerShell\Modules;' + `$env:PSModulePath
`$env:GENE_PLAIN_MENU = '1'
. '$stage\PowerShell\Microsoft.PowerShell_profile.ps1'
Import-Module Gene.Profile -DisableNameChecking
`$m = Get-Module Gene.Profile
'cats=' + ((& `$m { Get-GeneOtherCategories }) -join ',')
'nav=' + ((& `$m { (Get-GeneOtherEntries -Category navigate).Name }) -join ',')
'build=' + ((& `$m { (Get-GeneOtherEntries -Category build).Name }) -join ',')
'groups=' + ((& `$m { Get-GeneProfGroupNames }) -join ',')
'products=' + ((& `$m { @((Get-GeneBuildProducts).Keys) }) -join ',')
'defaults=' + ((`$global:GeneMachineDefaults.Values | Where-Object { `$_ }) -join ',')
'missing=' + ((@('dpcrewchief', 'dpall', 'cspeed', 'sp', 'addStreams') | Where-Object { -not (Test-Path "function:\`$_") }) -join ',')
prof help | Out-Null; 'help=ok'
"@
            $out = @(pwsh -NoProfile -NonInteractive -Command $probe 2>&1 | ForEach-Object { "$_" })
            Assert-True ($out -contains 'cats=navigate,build,profile') "got: $($out -join ' / ')"
            Assert-True ($out -contains 'nav=cdevops,csm') "got: $($out -join ' / ')"
            Assert-True ($out -contains 'build=dpspeed,Publish-SpeedMerchantsPackage') "got: $($out -join ' / ')"
            Assert-True ($out -contains 'groups=build,other') "got: $($out -join ' / ')"
            Assert-True ($out -contains 'products=testauto') "prof build offers only the product whose dp* command shipped; got: $($out -join ' / ')"
            Assert-True ($out -contains 'defaults=') "got: $($out -join ' / ')"
            Assert-True ($out -contains 'missing=dpcrewchief,dpall,cspeed,sp,addStreams') "got: $($out -join ' / ')"
            Assert-True ($out -contains 'help=ok') "got: $($out -join ' / ')"
        }
        finally { $env:GENE_PROF_HUB = $hub }
    }

    # ---------------------------------------------------------------- the flow with -WhatIf
    Test-Case 'flow: share profile -WhatIf runs pick, keys and plan, returns the plan and writes nothing' {
        $before = @(Get-ChildItem -LiteralPath $repo -Recurse -Force | Where-Object FullName -notmatch '\\\.git(\\|$)' | ForEach-Object FullName)
        # build, dpspeed, then Enter on each of the four keys (BitsDir, LocalSpeedSecretsFile, PackageShare, SharedBitsHost)
        $plan = Invoke-GeneProfShare -What profile -Repo $repo -WhatIf -Reader (New-Queue @('2', '1', '', '', '', ''))
        Assert-Equal @('build') @($plan.Picks.Keys); Assert-Equal @('dpspeed') @($plan.Picks['build'])
        Assert-Equal @('dpspeed', 'Publish-SpeedMerchantsPackage', 'Publish-GeneSharedBits') @($plan.Closure.Categories['build'].Functions)
        Assert-Equal @('BitsDir', 'LocalSpeedSecretsFile', 'PackageShare', 'SharedBitsHost') @($plan.KeyValues.Keys)
        Assert-Equal '' $plan.KeyValues['PackageShare']
        $after = @(Get-ChildItem -LiteralPath $repo -Recurse -Force | Where-Object FullName -notmatch '\\\.git(\\|$)' | ForEach-Object FullName)
        Assert-Equal $before $after 'the repo tree must not change'
        Assert-Equal '' ((git -C $repo status --porcelain) -join '')
    }
    Test-Case 'flow: cancelling the pick returns null and writes nothing' {
        Assert-True ($null -eq (Invoke-GeneProfShare -What profile -Repo $repo -WhatIf -Reader (New-Queue @('q'))))
    }
    Test-Case 'flow: the menu offers profile, ai-setup, help; an unknown word is refused' {
        Assert-Throws { Invoke-GeneProfShare -What bogus -Repo $repo } "*'profile', 'ai-setup' or 'help'*"
        Assert-True ($null -eq (Invoke-GeneProfShare -Repo $repo -Reader (New-Queue @('q'))))
        Assert-True ($null -eq (Invoke-GeneProfShare -Repo $repo -Reader (New-Queue @('3'))))
    }
    Test-Case 'flow: -WhatIf also stages and scans: the file list is on the plan, and the stage folder is gone afterwards' {
        $plan = Invoke-GeneProfShare -What profile -Repo $repo -WhatIf -Reader (New-Queue @('1', '1', ''))
        Assert-True ($plan.Files -contains 'PowerShell\profile.d\navigate.ps1'); Assert-True ($plan.Files -contains 'ProfileMachineConfig.md')
        Assert-True ($plan.Files -contains 'prof-share.json'); Assert-True ($plan.Files -contains 'Install-Profile.ps1')
        Assert-Equal 0 $plan.Mentions
        Assert-Equal @() @(Get-ChildItem -LiteralPath $env:GENE_SHARE_STAGE -ErrorAction SilentlyContinue)
    }

    # ---------------------------------------------------------------- write
    function Get-RepoChanges([string]$Path) { @(git -C $Path status --porcelain --untracked-files=all | ForEach-Object { $_.Substring(3) } | Sort-Object) }
    Test-Case 'write: ai\profile gets the tree, installer, template, manifest; ai\README.md and one root pointer line; nothing else changes; git commands printed' {
        $r = Invoke-GeneProfShare -What profile -Repo $repo -Reader (New-Queue @('2', '1', '', '2', '', ''))
        Assert-True $r.Written
        $dir = "$repo\ai\profile"
        foreach ($f in 'Install-Profile.ps1', 'ProfileMachineConfig.md', 'prof-share.json', 'modules.txt', 'PowerShell\Microsoft.PowerShell_profile.ps1', 'PowerShell\profile.d\build.ps1', 'PowerShell\Modules\Gene.Profile\BuildGroup.ps1', 'PowerShell\Modules\Gene.DevOpsTools\Gene.DevOpsTools.psm1') {
            Assert-True (Test-Path -LiteralPath "$dir\$f") "missing $f"
        }
        $tpl = Get-Content -LiteralPath "$dir\ProfileMachineConfig.md"
        Assert-True ($tpl -contains '| BitsDir |  | dpspeed, prof build | fill in |') "template: $($tpl -join ' / ')"
        Assert-True (($tpl | Where-Object { $_ -like '| LocalSpeedSecretsFile | D:\secrets\x.json | dpspeed | set by *' }).Count -eq 1) 'my value shipped'
        Assert-Equal @('BitsDir', 'LocalSpeedSecretsFile', 'PackageShare', 'SharedBitsHost') @($tpl | Where-Object { $_ -match '^\| ([A-Za-z]+) \|' -and $Matches[1] -ne 'Key' } | ForEach-Object { ($_ -split '\|')[1].Trim() })
        $m = Get-Content -LiteralPath "$dir\prof-share.json" -Raw | ConvertFrom-Json -AsHashtable
        Assert-Equal @('dpspeed') @($m.categories.build); Assert-Equal @('Publish-SpeedMerchantsPackage') @($m.pulled.build); Assert-Equal @('Gene.DevOpsTools') @($m.modules.build)
        Assert-Equal 'D:\secrets\x.json' $m.keys.LocalSpeedSecretsFile.value; Assert-Equal '' $m.keys.BitsDir.value
        Assert-Equal ((Get-FileHash -LiteralPath "$dir\PowerShell\profile.d\build.ps1").Hash.ToLower()) $m.files['PowerShell/profile.d/build.ps1']
        $readme = Get-Content -LiteralPath "$repo\ai\README.md" -Raw
        Assert-Match $readme '\*\*build\*\*'; Assert-Match $readme '- `dpspeed`: TestAuto'; Assert-Match $readme 'Publish-SpeedMerchantsPackage`:.*needed by a shared command'
        Assert-Match $readme '\| BitsDir \| \(asked at install\) \| dpspeed, prof build \|'; Assert-Match $readme 'No skills shared yet'
        Assert-Match (Get-Content -LiteralPath "$repo\README.md" -Raw) 'coworker repo\r?\n\r?\nShared PowerShell commands and Claude skills: see \[ai/README.md\]'
        $changes = Get-RepoChanges $repo
        Assert-True (($changes | Where-Object { $_ -notmatch '^ai/|^README\.md$' }).Count -eq 0) "outside ai/: $($changes -join ', ')"
        Assert-True ($changes -contains 'README.md') 'root README pointer'
    }
    Test-Case 'write: a second share is refused until the first is committed; after the commit the repo state preselects the pick' {
        Assert-Throws { Invoke-GeneProfShare -What profile -Repo $repo -WhatIf -Reader (New-Queue @('q')) } '*uncommitted change*'
        git -C $repo add -- ai README.md; git -C $repo commit -q -m 'share: profile'
        $s = Get-GeneShareState -Repo $repo
        Assert-Equal @('build') @($s.Categories.Keys); Assert-Equal @('dpspeed') @($s.Categories['build']); Assert-Equal 'D:\secrets\x.json' $s.Keys['LocalSpeedSecretsFile']
        # Enter keeps the category and its command, and the four keys keep their repo values (BitsDir: my value this time)
        $plan = Invoke-GeneProfShare -What profile -Repo $repo -WhatIf -Reader (New-Queue @('', '', '2', '', '', ''))
        Assert-Equal @('dpspeed') @($plan.Picks['build']); Assert-Equal 'C:\Bits' $plan.KeyValues['BitsDir']; Assert-Equal 'D:\secrets\x.json' $plan.KeyValues['LocalSpeedSecretsFile']
    }
    Test-Case 'write: a smaller pick removes what is no longer shared, the root pointer is not added twice' {
        $r = Invoke-GeneProfShare -What profile -Repo $repo -Reader (New-Queue @('n', '1', '1,2', '', ''))
        Assert-True (-not (Test-Path "$repo\ai\profile\PowerShell\profile.d\build.ps1")) 'build dropped'
        Assert-True (-not (Test-Path "$repo\ai\profile\PowerShell\Modules\Gene.DevOpsTools")) 'module no longer reached'
        Assert-True (Test-Path "$repo\ai\profile\PowerShell\profile.d\navigate.ps1")
        Assert-Equal 1 @(Get-Content -LiteralPath "$repo\README.md" | Where-Object { $_ -match 'ai/README\.md' }).Count
        $changes = Get-RepoChanges $repo
        Assert-True ($changes -notcontains 'README.md') 'root README untouched the second time'
        git -C $repo add -- ai README.md; git -C $repo commit -q -m 'share: profile 2'
    }
    Test-Case 'scan: a secret in a picked file stops the share; nothing is written' {
        $r4 = New-ShareRepo 'repo-secret'
        $bak = Get-Content -LiteralPath "$pd\tools.ps1" -Raw
        Set-Content -LiteralPath "$pd\tools.ps1" -Value ($bak + "`nfunction newguid2 { 'Server=x;Password=hunter22;' }")
        try {
            Assert-Throws { Invoke-GeneProfShare -What profile -Repo $r4 -Reader (New-Queue @('5', '2', '')) } '*Possible secrets*'
            Assert-True (-not (Test-Path "$r4\ai")) 'nothing written'
            Assert-Equal @() @(Get-ChildItem -LiteralPath $env:GENE_SHARE_STAGE -ErrorAction SilentlyContinue)
        }
        finally { Set-Content -LiteralPath "$pd\tools.ps1" -Value $bak -NoNewline }
    }
    Test-Case 'scan: a mention of the owner is listed; n cancels and writes nothing; y writes; -WhatIf lists without asking' {
        $r5 = New-ShareRepo 'repo-mention'
        $bak = Get-Content -LiteralPath "$pd\navigate.ps1" -Raw
        Set-Content -LiteralPath "$pd\navigate.ps1" -Value ($bak + "`n# owner1 keeps this on BOX7")
        try {
            $plan = Invoke-GeneProfShare -What profile -Repo $r5 -WhatIf -Reader (New-Queue @('1', '1', ''))
            Assert-Equal 1 $plan.Mentions
            Assert-True ($null -eq (Invoke-GeneProfShare -What profile -Repo $r5 -Reader (New-Queue @('1', '1', '', 'n'))))
            Assert-True (-not (Test-Path "$r5\ai")) 'nothing written after n'
            $r = Invoke-GeneProfShare -What profile -Repo $r5 -Reader (New-Queue @('1', '1', '', 'y'))
            Assert-True $r.Written; Assert-Equal 1 $r.Mentions
            Assert-True (Test-Path "$r5\ai\profile\PowerShell\profile.d\navigate.ps1")
        }
        finally { Set-Content -LiteralPath "$pd\navigate.ps1" -Value $bak -NoNewline }
    }
    Test-Case 'write: a repo without a README gets no pointer and no README' {
        $r6 = New-ShareRepo 'repo-noreadme'
        Remove-Item -LiteralPath "$r6\README.md"; git -C $r6 add -A; git -C $r6 commit -q -m 'no readme'
        $out = Invoke-GeneProfShare -What profile -Repo $r6 -Reader (New-Queue @('1', '1', '')) 6>&1
        $r = $out | Where-Object { $_ -is [pscustomobject] } | Select-Object -Last 1
        $text = ($out | ForEach-Object { "$_" }) -join "`n"
        Assert-True $r.Written; Assert-True (-not (Test-Path "$r6\README.md")); Assert-True (Test-Path "$r6\ai\README.md")
        Assert-Match $text '(?m)git -C .* add -- ai$' 'the printed git add names only paths that exist'
        Assert-NoMatch $text 'add -- ai README'
    }
    Test-Case 'write: a dirty unrelated file in the clone does not stop the share and is left alone' {
        $r8 = New-ShareRepo 'repo-dirty'
        Write-File "$r8\HCQ\query.sql" 'select 1'; git -C $r8 add -A; git -C $r8 commit -q -m hcq
        Write-File "$r8\HCQ\query.sql" 'select 2'
        $r = Invoke-GeneProfShare -What profile -Repo $r8 -Reader (New-Queue @('1', '1', '2')) 6>$null
        Assert-True $r.Written
        Assert-Equal 'select 2' (Get-Content -LiteralPath "$r8\HCQ\query.sql" -Raw).Trim()
        Assert-True ((Get-RepoChanges $r8) -contains 'HCQ/query.sql') 'the dirty file is still dirty'
    }
    Test-Case 'owner: git user.name of the repo, never the account name; the template and README carry it' {
        $r7 = New-ShareRepo 'repo-owner'
        git -C $r7 config user.name 'Test Owner'
        Assert-Equal 'Test Owner' (Get-GeneShareOwner -Repo $r7)
        $r = Invoke-GeneProfShare -What profile -Repo $r7 -Reader (New-Queue @('1', '1', '2')) 6>$null
        Assert-True $r.Written
        Assert-Match ((Get-Content "$r7\ai\profile\ProfileMachineConfig.md") -join "`n") 'set by Test Owner'
        Assert-Match ((Get-Content "$r7\ai\README.md") -join "`n") 'Shared by Test Owner'
        Assert-NoMatch ((Get-Content "$r7\ai\README.md") -join "`n") ([regex]::Escape((Get-GeneCaller)))
    }
}
finally {
    $env:GENE_PROF_HUB = $null
    $env:GENE_SHARE_STAGE = $null
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
