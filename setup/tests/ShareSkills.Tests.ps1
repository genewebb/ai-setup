#requires -Version 7
# prof setup share ai-setup (Gene.Profile\ShareSkills.ps1): skill categories, the offer, the repo state, the pick, the
# hard-stop checks, the reference rewrite, plugin.json / marketplace.json and the write flow. A fixture hub with a
# skills\ folder and a temp git clone stand in for the real ones.
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$mod = Join-Path $repoRoot 'pwsh\PowerShell\Modules\Gene.Profile'
foreach ($f in 'Target.ps1', 'Menu.ps1', 'Verbs.ps1', 'OtherGroup.ps1', 'Share.ps1', 'ShareSkills.ps1') { . (Join-Path $mod $f) }

$root = New-TestRoot 'shareskills'
function New-Queue([string[]]$Answers) { $q = [System.Collections.Generic.Queue[string]]::new(); foreach ($a in $Answers) { $q.Enqueue($a) }; { param($p) $q.Dequeue() }.GetNewClosure() }
function Write-File([string]$Path, [string]$Text) { New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null; Set-Content -LiteralPath $Path -Value $Text -Encoding utf8NoBOM }
function New-Skill([string]$Name, [string]$Body = 'body', [string]$Extra = '') {
    Write-File "$hub\skills\$Name\SKILL.md" "---`nname: $Name`ndescription: >`n  What $Name does.`n$Extra---`n$Body"
}

# ---------------------------------------------------------------- fixture hub
$hub = Join-Path $root 'hub'
New-Skill 'testauto-a' "See [[testauto-b]] and ``testauto-c``; run /testauto-b. Memory: [[project_notes_2026]]. Not a skill: /plugin, /loop."
New-Skill 'testauto-b' 'plain'
New-Skill 'testauto-c' 'uses [[testauto-a|the first one]] and [[testauto-b#Heading]]'
New-Skill 'crewchief-x' 'two of us: general'
New-Skill 'crewchief-y' 'two of us: general'
New-Skill 'solo' 'alone: general'
New-Skill 'odd-one' 'front matter says tools' "category: tools`n"
New-Skill 'leaky' 'reads {ReposRoot} and {ShareRepo}'
New-Skill 'linker' 'points at [[solo]] which may be unpicked, and at /testauto-ab which is no skill'
Write-File "$hub\skills\testauto-b\scripts\run.ps1" 'Write-Host "[[testauto-a]] stays in a script"'
[IO.File]::WriteAllBytes("$hub\skills\testauto-b\pic.png", [byte[]](0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A))
Write-File "$hub\pwsh\PowerShell\Microsoft.PowerShell_profile.ps1" @'
$global:GeneMachineDefaults = [ordered]@{
    ReposRoot = 'C:\devops\repos'
    BitsDir   = 'C:\Bits'
}
$global:GeneMachineAIKeys = @('AIWorkRoot', 'ShareRepo')
'@
Write-File "$hub\share.yaml" @('blockedPatterns:', "  - 'owner1'", "  - 'BOX7'") -join "`n"
New-Item -ItemType Directory -Force -Path "$hub\tools" | Out-Null
Copy-Item -LiteralPath (Join-Path $repoRoot 'tools\Find-Secrets.ps1') -Destination "$hub\tools\Find-Secrets.ps1"
$env:GENE_PROF_HUB = $hub
$env:GENE_SHARE_STAGE = Join-Path $root 'stage-root'

# ---------------------------------------------------------------- fixture repo
function New-ShareRepo([string]$Name) {
    $r = Join-Path $root $Name
    git init -q -b main $r
    git -C $r config user.name 'Test Owner'; git -C $r config user.email t@t; git -C $r config core.autocrlf false
    Write-File "$r\README.md" 'coworker repo'
    git -C $r add -A; git -C $r commit -q -m init
    return $r
}
$repo = New-ShareRepo 'repo'

try {
    # ---------------------------------------------------------------- category, offer, state, pick
    Test-Case 'category: 3+ sharing the first token = that token; fewer = general; front matter wins' {
        Assert-Equal 'testauto' (Get-GeneShareSkillCategory -Name 'testauto-a' -Counts @{ testauto = 3 } -FrontMatter @{})
        Assert-Equal 'general' (Get-GeneShareSkillCategory -Name 'crewchief-x' -Counts @{ crewchief = 2 } -FrontMatter @{})
        Assert-Equal 'general' (Get-GeneShareSkillCategory -Name 'solo' -Counts @{ solo = 1 } -FrontMatter @{})
        Assert-Equal 'tools' (Get-GeneShareSkillCategory -Name 'odd-one' -Counts @{ odd = 1 } -FrontMatter @{ category = 'tools' })
    }
    $offer = Get-GeneShareSkillOffer -Hub $hub
    Test-Case 'offer: categories in name order, skills in name order, descriptions from the front matter' {
        Assert-Equal @('general', 'testauto', 'tools') @($offer.Category)
        Assert-Equal @('crewchief-x', 'crewchief-y', 'leaky', 'linker', 'solo') @(($offer | Where-Object Category -eq 'general').Skills.Name)
        Assert-Equal @('testauto-a', 'testauto-b', 'testauto-c') @(($offer | Where-Object Category -eq 'testauto').Skills.Name)
        Assert-Equal @('odd-one') @(($offer | Where-Object Category -eq 'tools').Skills.Name)
        Assert-Equal 'What testauto-a does.' (($offer | Where-Object Category -eq 'testauto').Skills | Where-Object Name -eq 'testauto-a').Description
    }
    Test-Case 'state: an empty repo holds nothing; plugins present say what is shared' {
        Assert-Equal 0 (Get-GeneShareSkillState -Repo $repo).Count
        $r2 = New-ShareRepo 'repo-state'
        Write-File "$r2\ai\plugins\testauto\skills\testauto-b\SKILL.md" 'x'
        Write-File "$r2\ai\plugins\general\skills\solo\SKILL.md" 'x'
        $s = Get-GeneShareSkillState -Repo $r2
        Assert-Equal @('general', 'testauto') @($s.Keys)
        Assert-Equal @('solo') @($s['general']); Assert-Equal @('testauto-b') @($s['testauto'])
    }
    Test-Case 'pick: categories then skills by number; q cancels; Enter keeps what the repo has; n re-picks' {
        $empty = [ordered]@{}
        $p = Read-GeneShareSkillPicks -Offer $offer -State $empty -Reader (New-Queue @('2', '1 3'))
        Assert-Equal @('testauto') @($p.Keys); Assert-Equal @('testauto-a', 'testauto-c') @($p['testauto'])
        Assert-True ($null -eq (Read-GeneShareSkillPicks -Offer $offer -State $empty -Reader (New-Queue @('q'))))
        Assert-True ($null -eq (Read-GeneShareSkillPicks -Offer $offer -State $empty -Reader (New-Queue @('2', 'q'))))
        $have = [ordered]@{ testauto = @('testauto-b') }
        $p = Read-GeneShareSkillPicks -Offer $offer -State $have -Reader (New-Queue @('', ''))
        Assert-Equal @('testauto-b') @($p['testauto'])
        $p = Read-GeneShareSkillPicks -Offer $offer -State $have -Reader (New-Queue @('', 'n', '2 3'))
        Assert-Equal @('testauto-b', 'testauto-c') @($p['testauto'])
    }
}
finally {
    $env:GENE_PROF_HUB = $null
    $env:GENE_SHARE_STAGE = $null
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
