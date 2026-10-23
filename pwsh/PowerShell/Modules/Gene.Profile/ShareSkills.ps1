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

# ------------------------------------------------------------------------------------------------ checks and the rewrite
# How skills refer to each other today: [[name]] (also [[name|alias]], [[name#heading]]), `name` and /name.
$script:ShareWikiRx = [regex]'\[\[([^\]|#]+)(?:[|#][^\]]*)?\]\]'
$script:ShareTickRx = [regex]'`([a-z0-9]+(?:-[a-z0-9]+)*)`'
$script:ShareSlashRx = [regex]'(?<![\w/:])/([a-z0-9]+(?:-[a-z0-9]+)*)(?![\w-])'

function Get-GeneShareMachineKeys {
    <#
    The machine-profile key names, read from the hub core by AST (never dot-sourced): the $global:GeneMachineDefaults
    keys plus $global:GeneMachineAIKeys. A {Key} token in a shared skill names one of these.
    #>
    param([string]$Hub = (Get-GeneHubRoot))
    $core = Join-Path $Hub 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1'
    if (-not (Test-Path -LiteralPath $core)) { throw "No core profile in the hub ($core): the machine keys cannot be read." }
    $ast = Get-GeneShareAst -Path $core
    $keys = [System.Collections.Generic.List[string]]::new()
    foreach ($a in $ast.FindAll({ param($n) $n -is [AssignmentStatementAst] -and $n.Left -is [VariableExpressionAst] -and $n.Left.VariablePath.UserPath -in 'global:GeneMachineDefaults', 'global:GeneMachineAIKeys' }, $false)) {
        if ($a.Left.VariablePath.UserPath -eq 'global:GeneMachineDefaults') {
            foreach ($t in $a.Right.FindAll({ param($n) $n -is [HashtableAst] }, $true)) { foreach ($p in $t.KeyValuePairs) { if ($p.Item1 -is [StringConstantExpressionAst]) { $keys.Add($p.Item1.Value) } } }
        }
        else { foreach ($s in $a.Right.FindAll({ param($n) $n -is [StringConstantExpressionAst] }, $true)) { $keys.Add($s.Value) } }
    }
    return @($keys | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-GeneShareSkillRefs {
    <# Every reference in a text: @({ Kind = wiki|tick|slash; Name; Match; Line }). Only names are returned; the caller decides. #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text)
    $refs = [System.Collections.Generic.List[object]]::new()
    $lineOf = { param($i) ([regex]::Matches($Text.Substring(0, $i), "`n")).Count + 1 }
    foreach ($m in $script:ShareWikiRx.Matches($Text)) { $refs.Add([pscustomobject]@{ Kind = 'wiki'; Name = $m.Groups[1].Value.Trim(); Match = $m.Value; Line = (& $lineOf $m.Index) }) }
    foreach ($m in $script:ShareTickRx.Matches($Text)) { $refs.Add([pscustomobject]@{ Kind = 'tick'; Name = $m.Groups[1].Value; Match = $m.Value; Line = (& $lineOf $m.Index) }) }
    foreach ($m in $script:ShareSlashRx.Matches($Text)) { $refs.Add([pscustomobject]@{ Kind = 'slash'; Name = $m.Groups[1].Value; Match = $m.Value; Line = (& $lineOf $m.Index) }) }
    return @($refs)
}

function Test-GeneShareSkillText {
    <#
    The hard stops for one text of a picked skill: {Key} machine-profile tokens (the coworker has no such key) and
    references to hub skills that are not picked (the coworker would be sent to something he does not have).
    Returns the problems as strings; empty = fine. A name that is no hub skill (/plugin, /loop, a memory note) is never one.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [Parameter(Mandatory)][string]$Skill, [AllowEmptyCollection()][string[]]$AllSkills = @(), [AllowEmptyCollection()][string[]]$Picked = @(), [AllowEmptyCollection()][string[]]$Keys = @())
    $problems = [System.Collections.Generic.List[string]]::new()
    if ($Keys.Count) {
        $keyRx = [regex]('\{(' + (($Keys | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\}')
        foreach ($m in $keyRx.Matches($Text)) {
            $line = ([regex]::Matches($Text.Substring(0, $m.Index), "`n")).Count + 1
            $problems.Add("line $line`: $($m.Value) is a machine-profile token; the coworker has no $($m.Groups[1].Value). Edit the source skill or do not pick it.")
        }
    }
    foreach ($r in Get-GeneShareSkillRefs -Text $Text) {
        if ($r.Name -in $AllSkills -and $r.Name -notin $Picked) { $problems.Add("line $($r.Line): $($r.Match) refers to the hub skill '$($r.Name)', which is not picked. Pick it too, or edit the source skill.") }
    }
    return @($problems)
}

function Convert-GeneShareSkillText {
    <#
    The rewrite, in the copy only: [[p]], [[p|alias]], [[p#heading]], `p` and /p where p is a picked skill become
    <category>:<p> (`<category>:<p>`, /<category>:<p>); a [[name]] that is no hub skill (a memory note) loses its brackets
    and keeps its text. Returns { Text; Rewrites; Unlinked }.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Text, [AllowEmptyCollection()][string[]]$Picked = @(), [Parameter(Mandatory)][hashtable]$Category, [AllowEmptyCollection()][string[]]$AllSkills = @())
    $count = @{ rw = 0; ul = 0 }
    $qual = { param($n) "$($Category[$n]):$n" }
    $t = $script:ShareWikiRx.Replace($Text, {
            param($m)
            $n = $m.Groups[1].Value.Trim()
            if ($n -in $Picked) { $count.rw++; return (& $qual $n) }
            if ($n -in $AllSkills) { return $m.Value }
            $count.ul++; return $m.Value.Substring(2, $m.Value.Length - 4)
        })
    $t = $script:ShareTickRx.Replace($t, { param($m) $n = $m.Groups[1].Value; if ($n -in $Picked) { $count.rw++; return ('`' + (& $qual $n) + '`') }; return $m.Value })
    $t = $script:ShareSlashRx.Replace($t, { param($m) $n = $m.Groups[1].Value; if ($n -in $Picked) { $count.rw++; return ('/' + (& $qual $n)) }; return $m.Value })
    return [pscustomobject]@{ Text = $t; Rewrites = $count.rw; Unlinked = $count.ul }
}

function Copy-GeneShareSkill {
    <#
    One skill folder into the stage: every .md checked (a problem throws before anything is written) and rewritten; every
    other file copied byte for byte. Returns { Files (relative, sorted); Rewrites; Unlinked }.
    #>
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Dest, [Parameter(Mandatory)][string]$Skill, [AllowEmptyCollection()][string[]]$Picked = @(), [Parameter(Mandatory)][hashtable]$Category, [AllowEmptyCollection()][string[]]$AllSkills = @(), [AllowEmptyCollection()][string[]]$Keys = @())
    $files = @(Get-ChildItem -LiteralPath $Source -Recurse -File | Sort-Object { [IO.Path]::GetRelativePath($Source, $_.FullName) })
    $texts = [ordered]@{}; $problems = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files | Where-Object Extension -eq '.md') {
        $rel = [IO.Path]::GetRelativePath($Source, $f.FullName)
        $texts[$rel] = [IO.File]::ReadAllText($f.FullName)
        foreach ($p in Test-GeneShareSkillText -Text $texts[$rel] -Skill $Skill -AllSkills $AllSkills -Picked $Picked -Keys $Keys) { $problems.Add("$Skill\$rel $p") }
    }
    if ($problems.Count) { throw "skill $Skill cannot be shared ($($problems.Count) problem(s)):`n  $($problems -join "`n  ")" }
    $rewrites = 0; $unlinked = 0; $written = [System.Collections.Generic.List[string]]::new()
    foreach ($f in $files) {
        $rel = [IO.Path]::GetRelativePath($Source, $f.FullName)
        $to = Join-Path $Dest $rel
        New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
        if ($texts.Contains($rel)) {
            $r = Convert-GeneShareSkillText -Text $texts[$rel] -Picked $Picked -Category $Category -AllSkills $AllSkills
            [IO.File]::WriteAllText($to, $r.Text, [Text.UTF8Encoding]::new($false)); $rewrites += $r.Rewrites; $unlinked += $r.Unlinked
        }
        else { Copy-Item -LiteralPath $f.FullName -Destination $to -Force }
        $written.Add($rel)
    }
    return [pscustomobject]@{ Files = @($written | Sort-Object); Rewrites = $rewrites; Unlinked = $unlinked }
}
