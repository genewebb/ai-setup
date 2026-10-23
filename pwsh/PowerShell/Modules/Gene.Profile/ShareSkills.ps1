# prof setup share ai-setup: hand picked Claude skills to a coworker through the shared git repo, as one Claude Code
# plugin per category under <repo>\ai\plugins with a marketplace at the repo root. Design: vault
# 99_Frequent\Profile\Share Design.md (section 5.4). The repo is the state; share writes the working tree and prints the
# git commands; it never commits or pushes. Share.ps1 holds the pieces both halves use (repo, scans, README, write guard).
#
# This file is never shipped (section 4.2): it assumes the ai-setup hub. Gene.Profile.psm1 loads it when present.

$script:SharePluginsRel = 'ai\plugins'
$script:ShareMarketplaceRel = '.claude-plugin\marketplace.json'
$script:ShareMarketplaceName = 'speed-merchants-dba'
# A skill's first hyphen token is its category when at least this many hub skills share it; else 'general'.
$script:ShareCategoryMin = 3
$script:ShareGeneralCategory = 'general'

# ------------------------------------------------------------------------------------------------ categories and the offer
function Get-GeneShareSkillFrontMatter {
    <# The front matter of one SKILL.md as a hashtable (key => value); a folded (>) or literal (|) block is joined by spaces. #>
    param([Parameter(Mandatory)][string]$Path)
    $fm = @{}
    $lines = [IO.File]::ReadAllLines($Path)
    if ($lines.Count -lt 2 -or $lines[0].Trim() -ne '---') { return $fm }
    $key = $null; $block = $null
    for ($i = 1; $i -lt $lines.Count; $i++) {
        $l = $lines[$i]
        if ($l.Trim() -eq '---') { break }
        if ($l -match '^([A-Za-z][A-Za-z0-9_-]*):\s*(.*)$') {
            $key = $Matches[1]; $v = $Matches[2].Trim()
            if ($v -in '>', '|', '>-', '|-') { $block = [System.Collections.Generic.List[string]]::new(); $fm[$key] = '' }
            else { $block = $null; $fm[$key] = $v.Trim('"', "'") }
            continue
        }
        if ($null -ne $block -and $l -match '^\s+(\S.*)$') { $block.Add($Matches[1].Trim()); $fm[$key] = ($block -join ' ') }
    }
    return $fm
}

function Get-GeneShareSkillCategory {
    <# The category of one skill: front matter category:, else the first hyphen token when enough skills share it, else general. #>
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][hashtable]$Counts, [Parameter(Mandatory)][hashtable]$FrontMatter)
    if ($FrontMatter.ContainsKey('category') -and "$($FrontMatter['category'])".Trim()) { return "$($FrontMatter['category'])".Trim().ToLowerInvariant() }
    $first = ($Name -split '-')[0]
    if ($Counts.ContainsKey($first) -and [int]$Counts[$first] -ge $script:ShareCategoryMin) { return $first }
    return $script:ShareGeneralCategory
}

function Get-GeneShareSkillOffer {
    <#
    Every hub skill (skills\<name>\SKILL.md) grouped by category: @([pscustomobject]{ Category; Skills = @({ Name; Path;
    Description }) }), categories and skills in name order.
    #>
    param([string]$Hub = (Get-GeneHubRoot))
    $dir = Join-Path $Hub 'skills'
    $skills = @(Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') } | Sort-Object Name)
    $counts = @{}
    foreach ($s in $skills) { $t = ($s.Name -split '-')[0]; $counts[$t] = 1 + [int]$counts[$t] }
    $byCat = [ordered]@{}
    foreach ($s in $skills) {
        $fm = Get-GeneShareSkillFrontMatter -Path (Join-Path $s.FullName 'SKILL.md')
        $cat = Get-GeneShareSkillCategory -Name $s.Name -Counts $counts -FrontMatter $fm
        if (-not $byCat.Contains($cat)) { $byCat[$cat] = [System.Collections.Generic.List[object]]::new() }
        $byCat[$cat].Add([pscustomobject]@{ Name = $s.Name; Path = $s.FullName; Description = [string]$fm['description'] })
    }
    return @($byCat.Keys | Sort-Object | ForEach-Object { [pscustomobject]@{ Category = $_; Skills = @($byCat[$_] | Sort-Object Name) } })
}

function Get-GeneShareSkillState {
    <# What the repo already holds: ordered category => @(skill names) from ai\plugins\<category>\skills\*. #>
    param([Parameter(Mandatory)][string]$Repo)
    $state = [ordered]@{}
    $dir = Join-Path $Repo $script:SharePluginsRel
    foreach ($p in Get-ChildItem -LiteralPath $dir -Directory -ErrorAction SilentlyContinue | Sort-Object Name) {
        $names = @(Get-ChildItem -LiteralPath (Join-Path $p.FullName 'skills') -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name)
        if ($names.Count) { $state[$p.Name] = $names }
    }
    return $state
}

# ------------------------------------------------------------------------------------------------ the pick
function Read-GeneShareSkillPicks {
    <#
    Categories, then the skills in each. What the repo holds is the default: Enter keeps it; n re-picks.
    Returns ordered category => skill names, or $null when cancelled. An empty pick for a category drops it.
    #>
    param([Parameter(Mandatory)][object[]]$Offer, [Parameter(Mandatory)]$State, [scriptblock]$Reader)
    $short = { param($t) if ($t.Length -gt 90) { $t.Substring(0, 87) + '...' } else { $t } }
    $have = @($State.Keys | Where-Object { $_ -in $Offer.Category })
    $items = @($Offer | ForEach-Object {
            $mark = if ($_.Category -in $have) { ' (shared now)' } else { '' }
            [pscustomobject]@{ Name = $_.Category; Description = "$($_.Skills.Count) skill(s)$mark" } })
    $cats = $null
    if ($have.Count) {
        if (Read-GeneYesNo -Question "Keep the shared skill categories ($($have -join ', '))? n = pick again" -Default $true -Reader $Reader) { $cats = $have }
    }
    if ($null -eq $cats) {
        $picked = Select-GeneMenu -Title 'Share which categories of skills?' -Items $items -Multi -AllowEmpty -Reader $Reader
        if ($null -eq $picked) { return $null }
        $cats = @($picked | ForEach-Object Name)
    }
    $result = [ordered]@{}
    foreach ($cat in $cats) {
        $o = $Offer | Where-Object Category -eq $cat
        $current = @($State[$cat] | Where-Object { $_ -in $o.Skills.Name })
        $names = $null
        if ($current.Count) {
            if (Read-GeneYesNo -Question "$cat`: keep the shared skills ($($current -join ', '))? n = pick again" -Default $true -Reader $Reader) { $names = $current }
        }
        if ($null -eq $names) {
            $sItems = @($o.Skills | ForEach-Object {
                    $mark = if ($_.Name -in $current) { ' (shared now)' } else { '' }
                    [pscustomobject]@{ Name = $_.Name; Description = "$(& $short $_.Description)$mark" } })
            $picked = Select-GeneMenu -Title "$cat`: share which skills?" -Items $sItems -Multi -AllowEmpty -Reader $Reader
            if ($null -eq $picked) { return $null }
            $names = @($picked | ForEach-Object Name)
        }
        if ($names.Count) { $result[$cat] = @($names) }
    }
    return $result
}
