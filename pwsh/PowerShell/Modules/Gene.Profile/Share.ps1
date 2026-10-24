# prof setup share: hand picked parts of the profile (and, with 'ai-setup', picked Claude skills) to a coworker through
# one shared git repo. Design: vault 99_Frequent\Profile\Share Design.md (section 5). The repo is the state: the picker
# preselects what the repo already holds, and unpicking removes it. share writes the repo's working tree and prints the
# git commands; it never commits or pushes.
#
# This file is never shipped (section 4.2): it assumes the ai-setup hub. Gene.Profile.psm1 loads it when present.
using namespace System.Management.Automation.Language

# What is never offered: the board (stream kit, needs ai-setup) and the two profile commands that call the hub.
$script:ShareNeverCategories = @('board')
$script:ShareNeverCommands = @('sp', 'ep')
# Where the profile half lives inside the shared repo, and its manifest.
$script:ShareProfileRel = 'ai\profile'
$script:ShareManifestName = 'prof-share.json'
# The plugin marketplace's name (its .claude-plugin\marketplace.json at the repo root): the coworker installs
# <category>@<this name>. ShareSkills.ps1 writes it; the README here names it.
$script:ShareMarketplaceName = 'speed-merchants-dba'
# Hub group files that ship with a category (section 4.1: BuildGroup = build; GitGroup + AiGroup = git).
$script:ShareGroupFiles = @{ build = @('BuildGroup.ps1'); git = @('GitGroup.ps1', 'AiGroup.ps1') }
# Own modules a picked command may call into (section 5.1: shipped only when called). Gene.Completions always ships.
$script:ShareCallableModules = @('Gene.GitTools', 'Gene.DevOpsTools')
# Members of $global:GeneMachine that are not keys.
$script:ShareNotKeys = @('Keys', 'Values', 'Count', 'Contains', 'ContainsKey', 'Remove', 'Add', 'GetEnumerator')

# ------------------------------------------------------------------------------------------------ the shared repo
function Get-GeneShareRepo {
    <# The coworker repo clone: -Repo, else the ShareRepo key of this machine's profile. #>
    param([string]$Repo)
    if ($Repo) { return $Repo }
    if ($env:GENE_SHARE_REPO) { return $env:GENE_SHARE_REPO }
    if ($global:GeneMachineAI -and $global:GeneMachineAI['ShareRepo']) { return $global:GeneMachineAI['ShareRepo'] }
    $cfg = if ($env:AI_MACHINE_CONFIG) { $env:AI_MACHINE_CONFIG } else { Join-Path "$env:SystemDrive\" $script:GeneProfileRelPath }
    if (Test-Path -LiteralPath $cfg) {
        foreach ($line in Get-Content -LiteralPath $cfg) {
            if ($line -match '^\s*\|\s*`?ShareRepo`?\s*\|([^|]*)\|') {
                $v = [Environment]::ExpandEnvironmentVariables($Matches[1].Trim().Trim('`').Trim())
                if ($v) { return $v }
            }
        }
    }
    throw "No ShareRepo on $env:COMPUTERNAME: add a ShareRepo row (the clone of the coworker repo) to $cfg, or give -Repo."
}

function Assert-GeneShareRepo {
    <# A git clone whose share folders (ai\, .claude-plugin\) have no uncommitted change from a previous share. #>
    param([Parameter(Mandatory)][string]$Repo)
    if (-not (Test-Path -LiteralPath (Join-Path $Repo '.git'))) { throw "$Repo is not a git clone. Clone the coworker repo there first (prof setup share help)." }
    $dirty = @(& git -C $Repo status --porcelain --untracked-files=all -- ai .claude-plugin 2>&1 | Where-Object { "$_" -and $_ -isnot [System.Management.Automation.ErrorRecord] })
    if ($dirty.Count) {
        throw "$Repo has $($dirty.Count) uncommitted change(s) under ai\ or .claude-plugin\ from a previous share. Commit and push them (the printed git commands), or discard them, then share again."
    }
}

function Get-GeneShareProfileDir { param([Parameter(Mandatory)][string]$Repo) Join-Path $Repo $script:ShareProfileRel }

function Get-GeneShareOwner {
    <#
    Who the share says it is from: the repo's git user.name (the display name the commits carry), else the account.
    The template's Status column and the README carry it, and both are scanned for the owner's account names, so the
    account name would flag every share.
    #>
    param([Parameter(Mandatory)][string]$Repo)
    $n = (& git -C $Repo config user.name 2>$null | Select-Object -First 1)
    if ($n -and "$n".Trim()) { return "$n".Trim() }
    return Get-GeneCaller
}

# ------------------------------------------------------------------------------------------------ AST helpers
function Get-GeneShareAst {
    param([Parameter(Mandatory)][string]$Path)
    $tokens = $null; $errors = $null
    $ast = [Parser]::ParseFile((Resolve-Path -LiteralPath $Path).ProviderPath, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "$Path does not parse: $($errors[0].Message) at line $($errors[0].Extent.StartLineNumber)" }
    return $ast
}

function Get-GeneShareFileMap {
    <#
    One file's top-level definitions: Functions = name => FunctionDefinitionAst, Aliases = alias => function name
    (Set-Alias / New-Alias at the top level), and the parsed Ast.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $ast = Get-GeneShareAst -Path $Path
    $fns = [ordered]@{}
    foreach ($s in $ast.EndBlock.Statements) { if ($s -is [FunctionDefinitionAst]) { $fns[$s.Name] = $s } }
    $aliases = [ordered]@{}
    foreach ($s in $ast.EndBlock.Statements) {
        if ($s -isnot [PipelineAst] -or $s.PipelineElements.Count -ne 1) { continue }
        $c = $s.PipelineElements[0]
        if ($c -isnot [CommandAst] -or $c.GetCommandName() -notin 'Set-Alias', 'New-Alias') { continue }
        $name = $null; $value = $null; $pos = @()
        $els = $c.CommandElements
        for ($i = 1; $i -lt $els.Count; $i++) {
            $e = $els[$i]
            if ($e -is [CommandParameterAst]) {
                if ($i + 1 -lt $els.Count -and $els[$i + 1] -isnot [CommandParameterAst]) {
                    $v = $els[$i + 1].Extent.Text.Trim("'`"")
                    if ($e.ParameterName -eq 'Name') { $name = $v } elseif ($e.ParameterName -eq 'Value') { $value = $v }
                    $i++
                }
                continue
            }
            $pos += $e.Extent.Text.Trim("'`"")
        }
        if (-not $name -and $pos.Count -ge 1) { $name = $pos[0] }
        if (-not $value -and $pos.Count -ge 2) { $value = $pos[1] }
        if ($name -and $value) { $aliases[$name] = $value }
    }
    return [pscustomobject]@{ Path = $Path; Ast = $ast; Functions = $fns; Aliases = $aliases }
}

function Get-GeneShareCalls {
    <# Command names a function body invokes (unique). #>
    param([Parameter(Mandatory)][Ast]$Ast)
    return @($Ast.FindAll({ param($n) $n -is [CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
}

function Get-GeneShareKeyReads {
    <#
    Machine-profile keys a piece of code reads: $global:GeneMachine.Key, $global:GeneMachine['Key'],
    Get-GeneMachineSetting -Name Key (or positional), Get-GeneMachineRoot Key. Unique, sorted.
    #>
    param([Parameter(Mandatory)][Ast]$Ast)
    $keys = [System.Collections.Generic.List[string]]::new()
    $isMachine = { param($e) $e -is [VariableExpressionAst] -and $e.VariablePath.UserPath -in 'global:GeneMachine', 'GeneMachine' }
    foreach ($m in $Ast.FindAll({ param($n) $n -is [MemberExpressionAst] }, $true)) {
        if ((& $isMachine $m.Expression) -and $m.Member -is [StringConstantExpressionAst]) { $keys.Add($m.Member.Value) }
    }
    foreach ($x in $Ast.FindAll({ param($n) $n -is [IndexExpressionAst] }, $true)) {
        if ((& $isMachine $x.Target) -and $x.Index -is [StringConstantExpressionAst]) { $keys.Add($x.Index.Value) }
    }
    foreach ($c in $Ast.FindAll({ param($n) $n -is [CommandAst] -and $n.GetCommandName() -in 'Get-GeneMachineSetting', 'Get-GeneMachineRoot' }, $true)) {
        $els = $c.CommandElements; $named = $null; $pos = @()
        for ($i = 1; $i -lt $els.Count; $i++) {
            $e = $els[$i]
            if ($e -is [CommandParameterAst]) {
                if ($e.ParameterName -in 'Name', 'Key' -and $i + 1 -lt $els.Count -and $els[$i + 1] -is [StringConstantExpressionAst]) { $named = $els[$i + 1].Value }
                if ($i + 1 -lt $els.Count -and $els[$i + 1] -isnot [CommandParameterAst]) { $i++ }
                continue
            }
            if ($e -is [StringConstantExpressionAst]) { $pos += $e.Value }
        }
        $k = if ($named) { $named } elseif ($pos.Count) { $pos[0] } else { $null }
        if ($k) { $keys.Add($k) }
    }
    return @($keys | Where-Object { $_ -and $_ -notin $script:ShareNotKeys } | Sort-Object -Unique)
}

# ------------------------------------------------------------------------------------------------ what can be shared
function Get-GeneShareOffer {
    <#
    The categories and commands share can offer: every prof other catalog category that has a profile.d file in the
    hub (board never), and in each the catalog commands that file defines (a function, or an alias to one), minus sp/ep.
    A catalog command the file does not define (clearSeq, loaded from a folder outside the repo) is not offered.
    #>
    param([string]$Hub = (Get-GeneHubRoot))
    $dir = Join-Path $Hub 'pwsh\PowerShell\profile.d'
    $offer = [System.Collections.Generic.List[object]]::new()
    foreach ($cat in $script:ProfOtherCatalog.Keys) {
        if ($cat -in $script:ShareNeverCategories) { continue }
        $file = Join-Path $dir "$cat.ps1"
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $map = Get-GeneShareFileMap -Path $file
        $cmds = @($script:ProfOtherCatalog[$cat].Commands | Where-Object {
                $_.Name -notin $script:ShareNeverCommands -and ($map.Functions.Contains($_.Name) -or $map.Aliases.Contains($_.Name)) })
        if (-not $cmds.Count) { continue }
        $offer.Add([pscustomobject]@{ Category = $cat; Title = $script:ProfOtherCatalog[$cat].Title; File = $file; Commands = $cmds })
    }
    return @($offer)
}

function Get-GeneShareState {
    <#
    What the repo already holds: Categories = ordered category => command names (from prof-share.json; without a
    manifest, every command of each profile.d file present), Keys = key => value from the shipped ProfileMachineConfig.md
    template, Manifest = the parsed manifest or $null.
    #>
    param([Parameter(Mandatory)][string]$Repo)
    $dir = Get-GeneShareProfileDir -Repo $Repo
    $cats = [ordered]@{}; $keys = [ordered]@{}; $manifest = $null
    $mf = Join-Path $dir $script:ShareManifestName
    if (Test-Path -LiteralPath $mf) {
        try { $manifest = Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json -AsHashtable } catch { throw "$mf is not valid JSON: $_" }
        if ($manifest.categories) { foreach ($k in $manifest.categories.Keys) { $cats[$k] = @($manifest.categories[$k]) } }
    }
    else {
        $pd = Join-Path $dir 'PowerShell\profile.d'
        if (Test-Path -LiteralPath $pd) {
            foreach ($f in Get-ChildItem -LiteralPath $pd -Filter '*.ps1' | Sort-Object Name) {
                $map = Get-GeneShareFileMap -Path $f.FullName
                $cats[$f.BaseName] = @(@($map.Functions.Keys) + @($map.Aliases.Keys))
            }
        }
    }
    $tpl = Join-Path $dir 'ProfileMachineConfig.md'
    if (Test-Path -LiteralPath $tpl) {
        foreach ($line in Get-Content -LiteralPath $tpl) {
            if ($line -match '^\s*\|\s*`?([A-Za-z][A-Za-z0-9]*)`?\s*\|([^|]*)\|' -and $Matches[1] -notin 'Key', 'Setting') { $keys[$Matches[1]] = $Matches[2].Trim().Trim('`').Trim() }
        }
    }
    return [pscustomobject]@{ Categories = $cats; Keys = $keys; Manifest = $manifest }
}

# ------------------------------------------------------------------------------------------------ the pick
function Read-GeneSharePicks {
    <#
    Categories, then the commands in each. What the repo holds is the default: Enter keeps it; 'change' re-picks.
    Returns ordered category => command names, or $null when cancelled. An empty pick for a category drops it.
    #>
    param([Parameter(Mandatory)][object[]]$Offer, [Parameter(Mandatory)]$State, [scriptblock]$Reader)
    $have = @($State.Categories.Keys | Where-Object { $_ -in $Offer.Category })
    $items = @($Offer | ForEach-Object {
            $mark = if ($_.Category -in $have) { ' (shared now)' } else { '' }
            [pscustomobject]@{ Name = $_.Category; Description = "$($_.Title)$mark" } })
    $cats = $null
    if ($have.Count) {
        if (Read-GeneYesNo -Question "Keep the shared categories ($($have -join ', '))? n = pick again" -Default $true -Reader $Reader) { $cats = $have }
    }
    if ($null -eq $cats) {
        $picked = Select-GeneMenu -Title 'Share which categories of commands?' -Items $items -Multi -AllowEmpty -Reader $Reader
        if ($null -eq $picked) { return $null }
        $cats = @($picked | ForEach-Object Name)
    }
    $result = [ordered]@{}
    foreach ($cat in $cats) {
        $o = $Offer | Where-Object Category -eq $cat
        $current = @($State.Categories[$cat] | Where-Object { $_ -in $o.Commands.Name })
        $names = $null
        if ($current.Count) {
            if (Read-GeneYesNo -Question "$cat`: keep the shared commands ($($current -join ', '))? n = pick again" -Default $true -Reader $Reader) { $names = $current }
        }
        if ($null -eq $names) {
            $cItems = @($o.Commands | ForEach-Object {
                    $mark = if ($_.Name -in $current) { ' (shared now)' } else { '' }
                    [pscustomobject]@{ Name = $_.Name; Description = "$($_.What)$mark" } })
            $picked = Select-GeneMenu -Title "$cat`: share which commands?" -Items $cItems -Multi -AllowEmpty -Reader $Reader
            if ($null -eq $picked) { return $null }
            $names = @($picked | ForEach-Object Name)
        }
        if ($names.Count) { $result[$cat] = @($names) }
    }
    return $result
}

# ------------------------------------------------------------------------------------------------ what the pick needs
function Get-GeneShareModuleMaps {
    <# name => @{ Module; Ast } for every function the callable own modules define. #>
    param([Parameter(Mandatory)][string]$Hub)
    $m = @{}
    foreach ($mod in $script:ShareCallableModules) {
        $f = Join-Path $Hub "pwsh\PowerShell\Modules\$mod\$mod.psm1"
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $ast = Get-GeneShareAst -Path $f
        foreach ($fn in $ast.FindAll({ param($n) $n -is [FunctionDefinitionAst] }, $false)) { $m[$fn.Name] = @{ Module = $mod; Ast = $fn } }
    }
    return $m
}

function Resolve-GeneShareClosure {
    <#
    For a pick: per category the file, the picked commands, the catalog commands they pull in (a picked command calls
    them), every function that ships because the pick reaches it, and the own modules it calls into; across the pick
    the machine-profile keys read (with the commands that read each). Hub group files of a picked category ship whole
    and are scanned for keys too.
    #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)][System.Collections.IDictionary]$Picks, [object[]]$Offer = (Get-GeneShareOffer -Hub $Hub))
    $modules = Get-GeneShareModuleMaps -Hub $Hub
    $cats = [ordered]@{}
    $keyReaders = [ordered]@{}
    $addKey = { param($k, $who) if (-not $keyReaders.Contains($k)) { $keyReaders[$k] = [System.Collections.Generic.List[string]]::new() }; if ($who -notin $keyReaders[$k]) { $keyReaders[$k].Add($who) } }
    foreach ($cat in $Picks.Keys) {
        $o = $Offer | Where-Object Category -eq $cat
        if (-not $o) { throw "'$cat' is not a category share can offer." }
        $map = Get-GeneShareFileMap -Path $o.File
        $catalog = @($o.Commands.Name)
        $picked = @($Picks[$cat] | ForEach-Object { if ($_ -in $catalog) { $_ } else { throw "'$_' is not a command share offers under $cat." } })
        $usedModules = [System.Collections.Generic.List[string]]::new()
        $reached = [ordered]@{}
        $queue = [System.Collections.Generic.Queue[object]]::new()
        foreach ($p in $picked) {
            $fn = if ($map.Aliases.Contains($p)) { $map.Aliases[$p] } else { $p }
            $queue.Enqueue(@{ Name = $fn; Via = $p })
        }
        while ($queue.Count) {
            $item = $queue.Dequeue()
            $n = $item.Name
            if ($reached.Contains($n)) { continue }
            $node = if ($map.Functions.Contains($n)) { @{ Module = ''; Ast = $map.Functions[$n] } } elseif ($modules.ContainsKey($n)) { $modules[$n] } else { continue }
            $reached[$n] = $node
            if ($node.Module -and $node.Module -notin $usedModules) { $usedModules.Add($node.Module) }
            foreach ($k in Get-GeneShareKeyReads -Ast $node.Ast) { & $addKey $k $item.Via }
            foreach ($c in Get-GeneShareCalls -Ast $node.Ast) {
                $target = if ($map.Aliases.Contains($c)) { $map.Aliases[$c] } else { $c }
                if ($target -ne $n) { $queue.Enqueue(@{ Name = $target; Via = $item.Via }) }
            }
        }
        $pulled = @($catalog | Where-Object { $_ -notin $picked } | Where-Object { $t = if ($map.Aliases.Contains($_)) { $map.Aliases[$_] } else { $_ }; $reached.Contains($t) })
        # The hub group files of this category ship whole: their key reads count.
        foreach ($gf in @($script:ShareGroupFiles[$cat] | Where-Object { $_ })) {
            $gp = Join-Path $Hub "pwsh\PowerShell\Modules\Gene.Profile\$gf"
            if (Test-Path -LiteralPath $gp) { foreach ($k in Get-GeneShareKeyReads -Ast (Get-GeneShareAst -Path $gp)) { & $addKey $k "prof $cat" } }
        }
        $cats[$cat] = [pscustomobject]@{
            Category = $cat; File = $o.File; Picked = $picked; Pulled = $pulled
            Functions = @($reached.Keys | Where-Object { -not $reached[$_].Module })
            Modules = @($usedModules)
            GroupFiles = @($script:ShareGroupFiles[$cat] | Where-Object { $_ })
        }
    }
    $keys = [ordered]@{}
    foreach ($k in @($keyReaders.Keys | Sort-Object)) { $keys[$k] = @($keyReaders[$k]) }
    return [pscustomobject]@{ Categories = $cats; Keys = $keys; Modules = @($cats.Values | ForEach-Object Modules | Sort-Object -Unique) }
}

# ------------------------------------------------------------------------------------------------ the keys
function Read-GeneShareKeyValues {
    <#
    One question per key the pick reads: blank (the coworker fills it in), my value, or a typed value. The default
    is the value the repo template holds, else my value when it is %USERPROFILE%-relative, else blank.
    Returns ordered key => value ('' = blank), or $null when cancelled.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Keys, [Parameter(Mandatory)]$State, [scriptblock]$Reader)
    $result = [ordered]@{}
    foreach ($k in $Keys.Keys) {
        $mine = if ($global:GeneMachine -and $global:GeneMachine.Contains($k)) { [string]$global:GeneMachine[$k] } else { '' }
        $cur = if ($State.Keys.Contains($k)) { [string]$State.Keys[$k] } else { $null }
        $items = @(
            [pscustomobject]@{ Name = 'blank'; Description = 'the coworker is asked for it at install' }
            [pscustomobject]@{ Name = 'my value'; Description = $(if ($mine) { $mine } else { '(blank here too)' }) }
            [pscustomobject]@{ Name = 'type a value'; Description = '' }
        )
        $default = 1
        if ($null -ne $cur -and $cur -ne '') {
            $items += [pscustomobject]@{ Name = 'keep'; Description = "what the repo has now: $cur" }
            $default = 4
        }
        elseif ($mine -match '^%USERPROFILE%') { $default = 2 }
        $pick = Select-GeneMenu -Title "$k (read by $($Keys[$k] -join ', ')): value to ship?" -Items $items -Default $default -Reader $Reader
        if ($null -eq $pick) { return $null }
        $result[$k] = switch ($pick.Name) {
            'blank' { '' }
            'my value' { $mine }
            'keep' { $cur }
            'type a value' { ([string](Read-GeneText -Prompt "$k =" -Reader $Reader)).Trim() }
        }
    }
    return $result
}

# ------------------------------------------------------------------------------------------------ trim and copy
# Hub module files that always ship with the trimmed hub; every other Gene.Profile file ships only as a category's
# group file (ShareGroupFiles). SetupGroup, Target, Sync, Export, Share and StreamsGroup therefore never ship.
$script:ShareHubCoreFiles = @('Gene.Profile.psm1', 'Gene.Profile.psd1', 'Menu.ps1', 'Verbs.ps1', 'OtherGroup.ps1')
$script:ShareAlwaysModules = @('Gene.Completions')

function Get-GeneShareNewline([string]$Text) { if ($Text -match "`r`n") { "`r`n" } else { "`n" } }

function Edit-GeneShareCategoryText {
    <#
    The text of one category file with the unpicked catalog commands cut out: each cut function with the comment
    lines glued to its top, and every top-level Set-Alias / New-Alias that names a cut function. Functions the
    catalog does not list are helpers and stay. Returns the text; the caller writes it.
    #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string[]]$Catalog, [AllowEmptyCollection()][string[]]$Keep = @())
    $map = Get-GeneShareFileMap -Path $Path
    $raw = [IO.File]::ReadAllText($Path)
    $nl = Get-GeneShareNewline $raw
    $lines = $raw -split "`r?`n"
    # A cataloged name may be an alias: the function behind it is the one the catalog lists.
    $cataloged = @($Catalog | ForEach-Object { if ($map.Aliases.Contains($_)) { $map.Aliases[$_] } else { $_ } } | Sort-Object -Unique)
    $keepFns = @($Keep | ForEach-Object { if ($map.Aliases.Contains($_)) { $map.Aliases[$_] } else { $_ } })
    $cut = @($map.Functions.Keys | Where-Object { $_ -in $cataloged -and $_ -notin $keepFns })
    $drop = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($n in $cut) {
        $fn = $map.Functions[$n]
        $start = $fn.Extent.StartLineNumber; $end = $fn.Extent.EndLineNumber
        # The comment lines directly above the function (its own description) go with it; a banner separated by a
        # blank line stays.
        while ($start -gt 1 -and $lines[$start - 2] -match '^\s*#') { $start-- }
        for ($i = $start; $i -le $end; $i++) { [void]$drop.Add($i) }
    }
    foreach ($s in $map.Ast.EndBlock.Statements) {
        if ($s -isnot [PipelineAst] -or $s.PipelineElements.Count -ne 1 -or $s.PipelineElements[0] -isnot [CommandAst]) { continue }
        $c = $s.PipelineElements[0]
        if ($c.GetCommandName() -notin 'Set-Alias', 'New-Alias') { continue }
        $alias = @($map.Aliases.Keys | Where-Object { $map.Aliases[$_] -in $cut -and $c.Extent.Text -match "(?i)\b$([regex]::Escape($_))\b" })
        $cutName = @($cut | Where-Object { $c.Extent.Text -match "(?i)\b$([regex]::Escape($_))\b" })
        if ($alias.Count -or $cutName.Count) { for ($i = $s.Extent.StartLineNumber; $i -le $s.Extent.EndLineNumber; $i++) { [void]$drop.Add($i) } }
    }
    $out = [System.Collections.Generic.List[string]]::new()
    $removedJustNow = $false
    for ($i = 1; $i -le $lines.Count; $i++) {
        if ($drop.Contains($i)) { $removedJustNow = $true; continue }
        # Where a block was cut between two blank lines, keep one of them.
        if ($removedJustNow -and $lines[$i - 1] -eq '' -and $out.Count -and $out[$out.Count - 1] -eq '') { $removedJustNow = $false; continue }
        $removedJustNow = $false
        $out.Add($lines[$i - 1])
    }
    return ($out -join $nl)
}

function Edit-GeneShareCoreText {
    <#
    The core profile with every $global:GeneMachineDefaults value emptied: on the coworker's machine a missing row
    means "not available", never one of my paths. Returns the text.
    #>
    param([Parameter(Mandatory)][string]$Path)
    $ast = Get-GeneShareAst -Path $Path
    $assign = @($ast.FindAll({ param($n) $n -is [AssignmentStatementAst] -and $n.Left -is [VariableExpressionAst] -and $n.Left.VariablePath.UserPath -eq 'global:GeneMachineDefaults' }, $false))
    if ($assign.Count -ne 1) { throw "$Path`: expected one `$global:GeneMachineDefaults assignment, found $($assign.Count)." }
    $table = @($assign[0].Right.FindAll({ param($n) $n -is [HashtableAst] }, $true)) | Select-Object -First 1
    if (-not $table) { throw "$Path`: `$global:GeneMachineDefaults is not a hashtable literal." }
    $text = [IO.File]::ReadAllText($Path)
    foreach ($pair in @($table.KeyValuePairs | Sort-Object { $_.Item2.Extent.StartOffset } -Descending)) {
        $e = $pair.Item2.Extent
        $text = $text.Substring(0, $e.StartOffset) + "''" + $text.Substring($e.EndOffset)
    }
    return $text
}

function Copy-GeneShareFile {
    param([Parameter(Mandatory)][string]$Source, [Parameter(Mandatory)][string]$Dest)
    New-Item -ItemType Directory -Force -Path (Split-Path $Dest) | Out-Null
    Copy-Item -LiteralPath $Source -Destination $Dest -Force
}

function Get-GeneShareModuleRows {
    <#
    The PSGallery rows of modules.txt the shipped code can use: PowerShell-edition rows whose module the staged text
    mentions (Import-Module, Get-Module, #requires, a cmdlet's module name). The 5.1 rows never ship. Comments stay.
    #>
    param([Parameter(Mandatory)][string]$ModulesTxt, [Parameter(Mandatory)][string]$Stage)
    $text = (Get-ChildItem -LiteralPath $Stage -Recurse -File -Include '*.ps1', '*.psm1', '*.psd1' | ForEach-Object { [IO.File]::ReadAllText($_.FullName) }) -join "`n"
    $rows = foreach ($line in Get-Content -LiteralPath $ModulesTxt) {
        if ($line -match '^\s*(#|$)') { $line; continue }
        if ($line -notmatch '^\s*PowerShell\s+(\S+)') { continue }
        if ($text -match "(?i)(?<![\w.])$([regex]::Escape($Matches[1]))(?![\w.])") { $line }
    }
    return @($rows)
}

function New-GeneShareProfileTree {
    <#
    Builds the profile half of a share under -Stage (emptied first) from a plan (Invoke-GeneShareProfile -WhatIf):
      PowerShell\Microsoft.PowerShell_profile.ps1   the core, defaults emptied
      PowerShell\profile.d\<category>.ps1            trimmed to the pick
      PowerShell\Modules\Gene.Profile\               the hub core files + the group files of the picked categories
      PowerShell\Modules\<module>\                   Gene.Completions always; Gene.GitTools / Gene.DevOpsTools when reached
      PowerShell\powershell.config.json, modules.txt (rows the shipped code can use)
    Every written .ps1 is parsed again. Returns the relative paths written, sorted.
    #>
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$Stage)
    $src = Join-Path $Plan.Hub 'pwsh'
    $ps = Join-Path $src 'PowerShell'
    if (Test-Path -LiteralPath $Stage) { Remove-Item -LiteralPath $Stage -Recurse -Force }
    New-Item -ItemType Directory -Force -Path $Stage | Out-Null
    $written = [System.Collections.Generic.List[string]]::new()
    $put = { param([string]$Rel, [string]$Text) $d = Join-Path $Stage $Rel; New-Item -ItemType Directory -Force -Path (Split-Path $d) | Out-Null; [IO.File]::WriteAllText($d, $Text, [Text.UTF8Encoding]::new($false)); $written.Add($Rel) }
    $copy = { param([string]$Rel) Copy-GeneShareFile -Source (Join-Path $src $Rel) -Dest (Join-Path $Stage $Rel); $written.Add($Rel) }

    & $put 'PowerShell\Microsoft.PowerShell_profile.ps1' (Edit-GeneShareCoreText -Path (Join-Path $ps 'Microsoft.PowerShell_profile.ps1'))
    foreach ($c in $Plan.Closure.Categories.Values) {
        $catalog = @($script:ProfOtherCatalog[$c.Category].Commands.Name)
        & $put "PowerShell\profile.d\$($c.Category).ps1" (Edit-GeneShareCategoryText -Path $c.File -Catalog $catalog -Keep $c.Functions)
    }
    $groupFiles = @($Plan.Closure.Categories.Values | ForEach-Object GroupFiles | Where-Object { $_ } | Sort-Object -Unique)
    foreach ($f in $script:ShareHubCoreFiles + $groupFiles) {
        $rel = "PowerShell\Modules\Gene.Profile\$f"
        if (Test-Path -LiteralPath (Join-Path $src $rel)) { & $copy $rel }
    }
    foreach ($m in @($script:ShareAlwaysModules) + @($Plan.Closure.Modules)) {
        $dir = Join-Path $ps "Modules\$m"
        if (-not (Test-Path -LiteralPath $dir)) { continue }
        foreach ($f in Get-ChildItem -LiteralPath $dir -Recurse -File | Where-Object Name -notlike '*.bak*') { & $copy ([IO.Path]::GetRelativePath($src, $f.FullName)) }
    }
    if (Test-Path -LiteralPath (Join-Path $ps 'powershell.config.json')) { & $copy 'PowerShell\powershell.config.json' }
    $mt = Join-Path $src 'modules.txt'
    if (Test-Path -LiteralPath $mt) { & $put 'modules.txt' ((Get-GeneShareModuleRows -ModulesTxt $mt -Stage $Stage) -join "`n") }

    foreach ($rel in $written | Where-Object { $_ -match '\.ps(1|m1)$' }) { [void](Get-GeneShareAst -Path (Join-Path $Stage $rel)) }
    return @($written | Sort-Object)
}

# ------------------------------------------------------------------------------------------------ template, manifest, README
function Get-GeneShareStageRoot {
    <# Where a share is staged before the scans: GENE_SHARE_STAGE (tests), else ScratchRoot\prof, else the temp folder. #>
    if ($env:GENE_SHARE_STAGE) { return $env:GENE_SHARE_STAGE }
    $scratch = if ($global:GeneMachineAI -and $global:GeneMachineAI['ScratchRoot']) { $global:GeneMachineAI['ScratchRoot'] }
    if (-not $scratch) {
        $cfg = if ($env:AI_MACHINE_CONFIG) { $env:AI_MACHINE_CONFIG } else { Join-Path "$env:SystemDrive\" $script:GeneProfileRelPath }
        if (Test-Path -LiteralPath $cfg) {
            foreach ($line in Get-Content -LiteralPath $cfg) { if ($line -match '^\s*\|\s*`?ScratchRoot`?\s*\|([^|]*)\|') { $scratch = [Environment]::ExpandEnvironmentVariables($Matches[1].Trim().Trim('`').Trim()); break } }
        }
    }
    if ($scratch) { return (Join-Path $scratch 'prof') }
    return (Join-Path ([IO.Path]::GetTempPath()) 'prof')
}

function New-GeneShareTemplate {
    <#
    The coworker's ProfileMachineConfig.md: only the keys the shared commands read, with the values chosen at share
    time (blank = the installer asks). Same shape as the real file, so the shipped profile reads it unchanged.
    #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$KeyValues, [Parameter(Mandatory)][System.Collections.IDictionary]$KeyReaders, [string]$Owner)
    $out = [System.Collections.Generic.List[string]]::new()
    $out.Add('# PowerShell profile machine config - <MACHINE>')
    $out.Add('')
    $out.Add('Read by the PowerShell 7 profile every time it loads. Only this file differs between machines.')
    $out.Add('')
    $out.Add('- Edit the **Value** column. Keep one row per key and keep the `|` separators.')
    $out.Add('- A blank value means "not on this machine": the commands in **Used by** say so when run.')
    $out.Add('- Environment variables such as `%USERPROFILE%` are expanded.')
    $out.Add('- Run `machinecfg` to see what this machine resolved. Run `. $PROFILE` after editing.')
    $out.Add('')
    $out.Add('| Key | Value | Used by | Status |')
    $out.Add('|---|---|---|---|')
    foreach ($k in $KeyValues.Keys) {
        $v = [string]$KeyValues[$k]
        $status = if ($v) { "set by $Owner" } else { 'fill in' }
        $out.Add("| $k | $v | $($KeyReaders[$k] -join ', ') | $status |")
    }
    $out.Add('')
    return ($out -join "`n") + "`n"
}

function New-GeneShareManifest {
    <# prof-share.json: when, who, the pick, what it pulled in, the keys and their shipped values, every file's hash. #>
    param([Parameter(Mandatory)]$Plan, [Parameter(Mandatory)][string]$Stage, [Parameter(Mandatory)][string[]]$Files, [Parameter(Mandatory)][string]$Stamp, [string]$Owner)
    $cats = [ordered]@{}; $pulled = [ordered]@{}; $modules = [ordered]@{}
    foreach ($c in $Plan.Closure.Categories.Values) { $cats[$c.Category] = @($c.Picked); $pulled[$c.Category] = @($c.Pulled); $modules[$c.Category] = @($c.Modules) }
    $hashes = [ordered]@{}
    foreach ($f in $Files | Sort-Object) { $hashes[$f.Replace('\', '/')] = (Get-FileHash -LiteralPath (Join-Path $Stage $f) -Algorithm SHA256).Hash.ToLowerInvariant() }
    $keys = [ordered]@{}
    foreach ($k in $Plan.KeyValues.Keys) { $keys[$k] = [ordered]@{ value = [string]$Plan.KeyValues[$k]; usedBy = @($Plan.Closure.Keys[$k]) } }
    return ([ordered]@{ version = 1; stamp = $Stamp; owner = $Owner; categories = $cats; pulled = $pulled; modules = $modules; keys = $keys; files = $hashes } | ConvertTo-Json -Depth 6)
}

function Get-GeneShareReadmeText {
    <#
    ai\README.md for the whole share: the profile half from prof-share.json (commands by category with the catalog's
    one-liners, the settings asked for, install and update), the skills half from ai\plugins (or "none shared yet").
    Generated by every share, so the two halves always describe what the repo holds now.
    #>
    param([Parameter(Mandatory)][string]$Repo, [string]$Owner)
    $dir = Get-GeneShareProfileDir -Repo $Repo
    $mf = Join-Path $dir $script:ShareManifestName
    $m = if (Test-Path -LiteralPath $mf) { Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json -AsHashtable } else { $null }
    $o = [System.Collections.Generic.List[string]]::new()
    $o.Add('# Shared PowerShell profile and Claude skills')
    $o.Add('')
    $o.Add("Shared by $Owner with ``prof setup share``. This folder (``ai\``) and ``.claude-plugin\marketplace.json`` at the repo root are the only")
    $o.Add('things the share writes; everything else in the repo is untouched. Every later share is a commit: `git pull` brings it.')
    $o.Add('')
    $o.Add('## PowerShell profile')
    $o.Add('')
    if (-not $m) { $o.Add('No profile shared yet.'); $o.Add('') }
    else {
        $o.Add("Last shared $($m.stamp). Install (PowerShell 7, as the account that will use it), from this clone:")
        $o.Add('')
        $o.Add('```powershell')
        $o.Add('.\ai\profile\Install-Profile.ps1 -WhatIf')
        $o.Add('```')
        $o.Add('')
        $o.Add('```powershell')
        $o.Add('.\ai\profile\Install-Profile.ps1')
        $o.Add('```')
        $o.Add('')
        $o.Add('It copies `ai\profile\PowerShell\` into your PowerShell 7 profile folder (replaced files are backed up, the folder is')
        $o.Add('printed), installs the PSGallery modules in `modules.txt` you do not have, then asks for every blank machine setting')
        $o.Add('and writes `C:\Deploy\Setup\ProfileMachineConfig.md` (an existing file only gains missing rows). Then open a new')
        $o.Add('PowerShell 7 window. `prof help` lists the command groups, `prof other` the typed commands, `machinecfg` your settings.')
        $o.Add('')
        $o.Add('Update: `git pull`, then `.\ai\profile\Install-Profile.ps1` again.')
        $o.Add('')
        $o.Add('### Commands')
        $o.Add('')
        foreach ($cat in $m.categories.Keys) {
            $title = if ($script:ProfOtherCatalog.Contains($cat)) { $script:ProfOtherCatalog[$cat].Title } else { $cat }
            $o.Add("**$cat** - $title")
            $o.Add('')
            $names = @($m.categories[$cat]) + @($m.pulled[$cat])
            foreach ($n in $names) {
                $e = if ($script:ProfOtherCatalog.Contains($cat)) { $script:ProfOtherCatalog[$cat].Commands | Where-Object Name -eq $n | Select-Object -First 1 }
                $what = if ($e) { $e.What } else { '' }
                $usage = if ($e -and $e.Usage) { " (``$($e.Usage[0])``)" } else { '' }
                $note = if ($n -in @($m.pulled[$cat])) { ' - needed by a shared command' } else { '' }
                $o.Add("- ``$n``: $what$usage$note")
            }
            $o.Add('')
        }
        $o.Add('Also there: `prof` (the menu; `prof help`), `machinecfg`, and the helpers the commands above use.')
        $o.Add('')
        $o.Add('### Machine settings')
        $o.Add('')
        if ($m.keys.Count) {
            $o.Add('| Key | Shipped value | Used by |')
            $o.Add('|---|---|---|')
            foreach ($k in $m.keys.Keys) { $o.Add("| $k | $(if ($m.keys[$k].value) { $m.keys[$k].value } else { '(asked at install)' }) | $(@($m.keys[$k].usedBy) -join ', ') |") }
        }
        else { $o.Add('The shared commands read no machine setting.') }
        $o.Add('')
    }
    $o.Add('## Claude skills')
    $o.Add('')
    $plugins = @(Get-ChildItem -LiteralPath (Join-Path $Repo 'ai\plugins') -Directory -ErrorAction SilentlyContinue | Sort-Object Name)
    if (-not $plugins.Count) { $o.Add('No skills shared yet.'); $o.Add('') }
    else {
        $o.Add('One Claude Code plugin per category. In Claude Code, once:')
        $o.Add('')
        $o.Add('```text')
        $o.Add("/plugin marketplace add $Repo")
        $o.Add('```')
        $o.Add('')
        $o.Add('(the clone path; the repo URL works too when Claude can reach it). Then, per plugin:')
        $o.Add('')
        foreach ($p in $plugins) {
            $skills = @(Get-ChildItem -LiteralPath (Join-Path $p.FullName 'skills') -Directory -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object Name)
            $o.Add("- ``/plugin install $($p.Name)@$script:ShareMarketplaceName``: $($skills -join ', ')")
        }
        $o.Add('')
        $o.Add('Update: `git pull`, then `/plugin update` in Claude Code.')
        $o.Add('')
    }
    $o.Add('## Questions')
    $o.Add('')
    $o.Add("Ask $Owner. The source of all of this is private; this repo carries the shared copy.")
    $o.Add('')
    return ($o -join "`n")
}

# ------------------------------------------------------------------------------------------------ scans
function Get-GeneShareBlockedPatterns {
    <# share.yaml blockedPatterns from the hub: the owner's account names, machine names and personal paths. #>
    param([string]$Hub = (Get-GeneHubRoot))
    $f = Join-Path $Hub 'share.yaml'
    if (-not (Test-Path -LiteralPath $f)) { return @() }
    Import-Module powershell-yaml -ErrorAction Stop
    $y = ConvertFrom-Yaml (Get-Content -LiteralPath $f -Raw) -Ordered
    return @(if ($y -and $y['blockedPatterns']) { $y['blockedPatterns'] | ForEach-Object { [string]$_ } })
}

function Find-GeneShareMentions {
    <# Lines under -Root matching a blocked pattern: file, line, matched text. Shown, then the owner decides. #>
    param([Parameter(Mandatory)][string]$Root, [string[]]$Patterns)
    $hits = [System.Collections.Generic.List[object]]::new()
    if (-not $Patterns) { return $hits }
    $rx = [regex]::new(($Patterns -join '|'), 'IgnoreCase')
    foreach ($f in Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object Extension -in '.ps1', '.psm1', '.psd1', '.md', '.txt', '.json') {
        $n = 0
        foreach ($line in [IO.File]::ReadLines($f.FullName)) {
            $n++
            $m = $rx.Match($line)
            # The one convention path (ProfileMachineConfig.md under Deploy\Setup) is not a personal path.
            if ($m.Success -and $line -match 'Deploy\\Setup\\ProfileMachineConfig\.md' -and $m.Value -match '^[A-Za-z]:\\') { $m = $rx.Match($line, $m.Index + $m.Length) }
            if ($m.Success) { $hits.Add([pscustomobject]@{ File = [IO.Path]::GetRelativePath($Root, $f.FullName); Line = $n; Match = $m.Value }) }
        }
    }
    return $hits
}

function Find-GeneShareSecrets {
    <# tools\Find-Secrets.ps1 from the hub over the staged tree: file, line, rule, masked match. Empty when clean. #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)][string]$Root)
    $finder = Join-Path $Hub 'tools\Find-Secrets.ps1'
    if (-not (Test-Path -LiteralPath $finder)) { throw "No tools\Find-Secrets.ps1 in the hub $Hub`: the share cannot be checked for secrets, so nothing is written." }
    return @(& $finder -Root $Root)
}

function Test-GeneShareScans {
    <#
    Secrets = stop (listed, nothing written). Mentions of the owner (blockedPatterns) = listed; with -Ask, one yes/no.
    Returns the mention count, or $null when the owner said no.
    #>
    param([Parameter(Mandatory)][string]$Hub, [Parameter(Mandatory)][string]$Root, [switch]$Ask, [scriptblock]$Reader)
    $secrets = Find-GeneShareSecrets -Hub $Hub -Root $Root
    if ($secrets.Count) {
        foreach ($s in $secrets) { Write-ProfWarn "$($s.File):$($s.Line) $($s.Rule) $($s.Match)" }
        throw "Possible secrets in the share ($($secrets.Count)); nothing written. Fix the source file(s) in the hub and share again."
    }
    $hits = Find-GeneShareMentions -Root $Root -Patterns (Get-GeneShareBlockedPatterns -Hub $Hub)
    if ($hits.Count) {
        Write-ProfNote "$($hits.Count) line(s) mention your accounts, machines or personal paths (they travel with the share):"
        foreach ($h in $hits | Group-Object File) { Write-ProfNote ("  {0}: {1} ({2})" -f $h.Name, $h.Count, (@($h.Group.Match | Select-Object -Unique) -join ', ')) }
        if ($Ask) {
            $go = if ($Reader) { Read-GeneYesNo -Question 'Share them anyway?' -Reader $Reader } else { Confirm-GeneProf 'Share them anyway?' }
            if (-not $go) { return $null }
        }
    }
    return $hits.Count
}

# ------------------------------------------------------------------------------------------------ write
function Add-GeneShareRootPointer {
    <# The repo's own README gets one line pointing at ai\README.md, once; a repo without a README is left alone. #>
    param([Parameter(Mandatory)][string]$Repo)
    $f = Join-Path $Repo 'README.md'
    if (-not (Test-Path -LiteralPath $f)) { return $false }
    $text = [IO.File]::ReadAllText($f)
    if ($text -match 'ai[\\/]README\.md') { return $false }
    $nl = Get-GeneShareNewline $text
    if ($text.Length -and -not $text.EndsWith("`n")) { $text += $nl }
    [IO.File]::WriteAllText($f, $text + $nl + "Shared PowerShell commands and Claude skills: see [ai/README.md](ai/README.md)." + $nl, [Text.UTF8Encoding]::new($false))
    return $true
}

function Show-GeneShareGitCommands {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Message)
    Write-ProfStep 'Now commit and push (share never does):'
    Write-Host "  git -C $Repo add -- ai README.md .claude-plugin"
    Write-Host "  git -C $Repo commit -m `"$Message`""
    Write-Host "  git -C $Repo push"
}

function Write-GeneShareProfile {
    <#
    Steps 4-7 of the profile flow: stage the trimmed tree, add the installer, template, manifest; scan (secrets stop,
    mentions ask); replace <repo>\ai\profile with the stage; regenerate ai\README.md; print the git commands.
    -WhatIf: stage and scan, list the files, write nothing.
    #>
    param([Parameter(Mandatory)]$Plan, [switch]$WhatIf, [scriptblock]$Reader)
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $owner = Get-GeneShareOwner -Repo $Plan.Repo
    $stage = Join-Path (Get-GeneShareStageRoot) "share-profile-$stamp"
    try {
        $files = [System.Collections.Generic.List[string]]::new()
        foreach ($f in New-GeneShareProfileTree -Plan $Plan -Stage $stage) { $files.Add($f) }
        $installer = Join-Path $Plan.Hub 'pwsh\Install-Profile.ps1'
        if (-not (Test-Path -LiteralPath $installer)) { throw "No pwsh\Install-Profile.ps1 in the hub $($Plan.Hub)." }
        Copy-GeneShareFile -Source $installer -Dest (Join-Path $stage 'Install-Profile.ps1'); $files.Add('Install-Profile.ps1')
        [IO.File]::WriteAllText((Join-Path $stage 'ProfileMachineConfig.md'), (New-GeneShareTemplate -KeyValues $Plan.KeyValues -KeyReaders $Plan.Closure.Keys -Owner $owner), [Text.UTF8Encoding]::new($false)); $files.Add('ProfileMachineConfig.md')
        [IO.File]::WriteAllText((Join-Path $stage $script:ShareManifestName), (New-GeneShareManifest -Plan $Plan -Stage $stage -Files $files -Stamp $stamp -Owner $owner), [Text.UTF8Encoding]::new($false)); $files.Add($script:ShareManifestName)

        $mentions = Test-GeneShareScans -Hub $Plan.Hub -Root $stage -Ask:(-not $WhatIf) -Reader $Reader
        if ($null -eq $mentions) { Write-ProfNote 'Share cancelled; nothing written.'; return $null }

        $dest = Get-GeneShareProfileDir -Repo $Plan.Repo
        if ($WhatIf) {
            Write-ProfStep "-WhatIf: would replace $dest with $($files.Count) file(s):"
            foreach ($f in $files | Sort-Object) { Write-ProfNote "  $f" }
            Write-ProfNote '(nothing written)'
            return [pscustomobject]@{ Repo = $Plan.Repo; Files = @($files | Sort-Object); Mentions = $mentions; Stamp = $stamp; Written = $false }
        }
        if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($f in $files) { Copy-GeneShareFile -Source (Join-Path $stage $f) -Dest (Join-Path $dest $f) }
        [IO.File]::WriteAllText((Join-Path $Plan.Repo 'ai\README.md'), (Get-GeneShareReadmeText -Repo $Plan.Repo -Owner $owner), [Text.UTF8Encoding]::new($false))
        $pointer = Add-GeneShareRootPointer -Repo $Plan.Repo
        # The share owns ai\ and the root README pointer, nothing else: anything else changed is a bug, said loudly.
        $changed = @(& git -C $Plan.Repo status --porcelain --untracked-files=all 2>$null | ForEach-Object { $_.Substring(3).Trim('"') })
        $outside = @($changed | Where-Object { $_ -notmatch '^(ai/|README\.md$|\.claude-plugin/)' })
        if ($outside.Count) { throw "The share changed files it must not touch: $($outside -join ', '). Inspect the repo before committing." }
        Write-ProfStep "written: $dest ($($files.Count) file(s)) and ai\README.md$(if ($pointer) { ', one pointer line in README.md' })"
        Show-GeneShareGitCommands -Repo $Plan.Repo -Message "share: profile $stamp"
        return [pscustomobject]@{ Repo = $Plan.Repo; Files = @($files | Sort-Object); Mentions = $mentions; Stamp = $stamp; Written = $true }
    }
    finally { if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force -ErrorAction SilentlyContinue } }
}

# ------------------------------------------------------------------------------------------------ summary and entry
function Show-GeneSharePlan {
    <# The pick, what it pulls in, and the key table: what a share would write. #>
    param([Parameter(Mandatory)]$Closure, [Parameter(Mandatory)][System.Collections.IDictionary]$KeyValues, [Parameter(Mandatory)][string]$Repo)
    Write-ProfStep "profile share -> $(Get-GeneShareProfileDir -Repo $Repo)"
    foreach ($c in $Closure.Categories.Values) {
        $extra = @()
        if ($c.Pulled.Count) { $extra += "pulls in $($c.Pulled -join ', ')" }
        if ($c.Modules.Count) { $extra += "needs $($c.Modules -join ', ')" }
        if ($c.GroupFiles.Count) { $extra += "prof group: $(($c.GroupFiles -replace '\.ps1$') -join ', ')" }
        Write-ProfNote ("{0,-10} {1}{2}" -f $c.Category, ($c.Picked -join ', '), $(if ($extra.Count) { "   [" + ($extra -join '; ') + "]" } else { '' }))
    }
    if ($KeyValues.Count) {
        Write-ProfNote 'Machine settings the shared commands read:'
        $w = ($KeyValues.Keys | Measure-Object -Property Length -Maximum).Maximum
        foreach ($k in $KeyValues.Keys) {
            $v = if ($KeyValues[$k]) { $KeyValues[$k] } else { '(blank: asked at install)' }
            Write-ProfNote ("  {0}  {1}   used by {2}" -f $k.PadRight($w), $v, ($Closure.Keys[$k] -join ', '))
        }
    }
    else { Write-ProfNote 'The shared commands read no machine setting.' }
}

function Show-GeneShareHelp {
    Write-Host 'prof setup share: hand picked commands and Claude skills to a coworker through one shared git repo' -ForegroundColor Cyan
    Write-Host ''
    Write-Host '  prof setup share profile  [-Repo <clone>] [-WhatIf]   pick categories and commands of the profile; ship the trimmed'
    Write-Host '                                                       profile, its modules, an installer and a settings template'
    Write-Host '  prof setup share ai-setup [-Repo <clone>] [-WhatIf]   pick Claude skills; ship them as one plugin per category'
    Write-Host '  prof setup share help                                 this text'
    Write-Host ''
    $repoLine = try { "$(Get-GeneShareRepo) (the ShareRepo row of this machine's profile; -Repo overrides)" } catch { "the ShareRepo row of this machine's profile, not set here yet (-Repo overrides)" }
    Write-Host "  The repo: $repoLine. The repo is the state: what it holds is"
    Write-Host '  preselected, unpicking removes it. share writes the working tree under ai\ and .claude-plugin\ only, then prints'
    Write-Host '  the git add / commit / push commands for you to run. -WhatIf shows the pick and the settings table, writes nothing.'
    Write-Host ''
    Write-Host '  Never shared: prof setup, prof streams and the board commands, sp and ep, the Windows PowerShell 5.1 profile,'
    Write-Host '  agents, slash commands, hooks, settings, memory, secrets. A secret in a picked file stops the share; every'
    Write-Host '  mention of your accounts, machines and personal paths is listed first and needs a yes.'
    Write-Host ''
    Write-Host '  The coworker: clone the repo, run ai\profile\Install-Profile.ps1 (-WhatIf first), and in Claude Code'
    Write-Host '  /plugin marketplace add <repo>, then /plugin install <category>@<marketplace>. Updates: git pull, Install-Profile.ps1'
    Write-Host '  again, /plugin update. ai\README.md in the repo says the same with the real names.'
}

function Invoke-GeneShareProfile {
    <# The profile flow (section 5.3). -WhatIf: pick, keys, plan; nothing written. #>
    param([string]$Repo, [switch]$WhatIf, [scriptblock]$Reader)
    $hub = Get-GeneHubRoot
    $Repo = Get-GeneShareRepo -Repo $Repo
    Assert-GeneShareRepo -Repo $Repo
    $offer = Get-GeneShareOffer -Hub $hub
    if (-not $offer.Count) { throw "Nothing to share: no profile.d category file under $hub\pwsh\PowerShell." }
    $state = Get-GeneShareState -Repo $Repo
    $picks = Read-GeneSharePicks -Offer $offer -State $state -Reader $Reader
    if ($null -eq $picks) { Write-ProfNote 'Cancelled; nothing written.'; return $null }
    if (-not $picks.Count) { throw 'Nothing picked; nothing written. (Removing everything shared is done by hand: delete ai\profile in the repo and commit.)' }
    $closure = Resolve-GeneShareClosure -Hub $hub -Picks $picks -Offer $offer
    $keyValues = Read-GeneShareKeyValues -Keys $closure.Keys -State $state -Reader $Reader
    if ($null -eq $keyValues) { Write-ProfNote 'Cancelled; nothing written.'; return $null }
    Show-GeneSharePlan -Closure $closure -KeyValues $keyValues -Repo $Repo
    $plan = [pscustomobject]@{ Repo = $Repo; Hub = $hub; Picks = $picks; Closure = $closure; KeyValues = $keyValues; State = $state }
    $result = Write-GeneShareProfile -Plan $plan -WhatIf:$WhatIf -Reader $Reader
    if ($null -eq $result) { return $null }
    if ($WhatIf) {
        $plan | Add-Member -NotePropertyName Files -NotePropertyValue $result.Files
        $plan | Add-Member -NotePropertyName Mentions -NotePropertyValue $result.Mentions
        return $plan
    }
    return $result
}

function Invoke-GeneProfShare {
    <#
    prof setup share [profile | ai-setup | help] [-Repo <clone>] [-WhatIf]
    No word: a menu. The flows are in this file (profile) and, when built, the ai-setup flow (skills).
    #>
    param([string]$What, [string]$Repo, [switch]$WhatIf, [scriptblock]$Reader)
    $w = "$What".ToLowerInvariant()
    if (-not $w) {
        $items = @(
            [pscustomobject]@{ Name = 'profile'; Description = 'PowerShell commands: pick categories and commands, ship the trimmed profile' }
            [pscustomobject]@{ Name = 'ai-setup'; Description = 'Claude skills: pick skills, ship them as plugins' }
            [pscustomobject]@{ Name = 'help'; Description = 'What share does, what it never shares, the coworker steps' }
        )
        $pick = Select-GeneMenu -Title 'prof setup share: what?' -Items $items -Reader $Reader
        if (-not $pick) { return $null }
        $w = $pick.Name
    }
    switch ($w) {
        'help' { Show-GeneShareHelp; return $null }
        'profile' { return Invoke-GeneShareProfile -Repo $Repo -WhatIf:$WhatIf -Reader $Reader }
        'ai-setup' {
            if (-not (Test-GeneProfFunction -Name Invoke-GeneShareAiSetup)) { throw 'prof setup share ai-setup: not built yet (design section 5.4).' }
            return Invoke-GeneShareAiSetup -Repo $Repo -WhatIf:$WhatIf -Reader $Reader
        }
        default { throw "prof setup share: 'profile', 'ai-setup' or 'help', not '$What'." }
    }
}
