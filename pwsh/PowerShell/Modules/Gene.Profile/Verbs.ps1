# prof: the groups, the dispatcher and the menu. Each *Group.ps1 file adds its own group.
# Design: docs\manageprofile-design.md in the ai-setup clone.

# Old command -> the prof command that replaced it. A row is shown only when Needs (the prof-side function) is
# defined, so a trimmed copy (prof setup share) does not advertise a prof command it does not have.
$script:ProfOldNames = @(
    [pscustomobject]@{ Old = 'sp'; New = 'prof setup show'; Needs = 'Invoke-GeneProfShow' }
    [pscustomobject]@{ Old = 'ep'; New = 'prof setup edit'; Needs = 'Invoke-GeneProfEdit' }
    [pscustomobject]@{ Old = 'rp'; New = 'prof setup reload (rp itself only reloads the profile in this window)'; Needs = 'Invoke-GeneProfReload' }
    [pscustomobject]@{ Old = 'machinecfg'; New = 'prof setup config'; Needs = 'Invoke-GeneProfConfig' }
    [pscustomobject]@{ Old = 'gpush'; New = 'prof git push'; Needs = 'Invoke-GeneProfGitPush' }
    [pscustomobject]@{ Old = 'dpspeed, dpcrewchief, dpdatagen, dpmutate, dpv2'; New = 'prof build run testauto | crewchief | datagen | mutate | speedy'; Needs = 'Invoke-GeneProfBuildRun' }
    [pscustomobject]@{ Old = 'dp* -Package -Bump...'; New = 'prof build publish <product> -Bump Patch|Minor|Major'; Needs = 'Invoke-GeneProfBuildPublish' }
    [pscustomobject]@{ Old = 'dpall -Package'; New = 'prof build publish all'; Needs = 'Invoke-GeneProfBuildPublish' }
)

# The groups: prof <group> <command>. The main menu lists them; each is one area of work. A group's commands are
# the functions <Prefix><Command> (TitleCase). Ask (optional) is the menu's question flow for a command: it returns
# the parameters as an ordered dictionary, or $null when the user cancels. Refresh (optional) is run before the
# group is listed, for a group whose commands depend on what the profile defines (other). Each *Group.ps1 file adds
# its own group; Gene.Profile.psm1 loads the group files that exist, so a copy without a group file simply has no
# such group, and a group none of whose command functions exist is not listed (Get-GeneProfGroupNames).
$script:ProfGroups = [ordered]@{}

function Get-GeneProfVerbFunction {
    <# The function a group's command runs: <Prefix><Word><Word> (status-rebuild -> StatusRebuild). #>
    param([Parameter(Mandatory)]$Group, [Parameter(Mandatory)][string]$Verb)
    return $Group.Prefix + (($Verb -split '-' | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join '')
}

function Get-GeneProfGroupNames {
    <# The groups prof lists: the ones with at least one command whose function is defined, in menu order. #>
    foreach ($gn in @($script:ProfGroups.Keys)) {
        $g = $script:ProfGroups[$gn]
        if ($g.Refresh) { & $g.Refresh }
        foreach ($v in @($g.Verbs.Keys)) {
            if (Get-Command (Get-GeneProfVerbFunction -Group $g -Verb $v) -ErrorAction SilentlyContinue) { $gn; break }
        }
    }
}


# ------------------------------------------------------------------------------------------------ small helpers
function Write-ProfStep([string]$m) { Write-Host "== $m" -ForegroundColor Cyan }
function Write-ProfWarn([string]$m) { Write-Host "  WARNING: $m" -ForegroundColor Yellow }
function Write-ProfNote([string]$m) { Write-Host "  $m" }

function Format-GeneProfCommand {
    <# The command line a run is equivalent to, so a menu session teaches the syntax. #>
    param([string]$Group, [Parameter(Mandatory)][string]$Verb, [System.Collections.IDictionary]$Params = @{})
    $topic = if ($Group -and $script:ProfGroups.Contains($Group)) { $script:ProfGroups[$Group].TopicParam }
    $order = @('Topic') + @($topic | Where-Object { $_ }) + @('Machine', 'User', 'WorkDrive', 'Retire', 'Message', 'Bump', 'Configuration', 'Out', 'FixProfile', 'WithTerminal', 'WithSecrets', 'NoPublish', 'AllowSecrets', 'AIOnly', 'Extra', 'WhatIf')
    $parts = @('prof') + @($Group | Where-Object { $_ }) + @($Verb)
    foreach ($k in $order + @($Params.Keys | Where-Object { $_ -notin $order })) {
        if (-not $Params.Contains($k)) { continue }
        $v = $Params[$k]
        if ($k -eq 'Topic' -or ($topic -and $k -eq $topic)) { if ($v) { $parts += $v }; continue }
        if ($k -eq 'Extra') { foreach ($e in @($v)) { $parts += $(if ($e -is [array]) { @($e) -join ',' } elseif ("$e" -match '\s') { "'$e'" } else { "$e" }) }; continue }
        if ($v -is [switch] -or $v -is [bool]) { if ([bool]$v) { $parts += "-$k" }; continue }
        if ($null -eq $v -or "$v" -eq '') { continue }
        $s = if ($v -is [array]) { (@($v) -join ',') } else { [string]$v }
        if ($s -match '\s') { $s = "'$s'" }
        $parts += "-$k", $s
    }
    return ($parts -join ' ')
}

function Confirm-GeneProf([string]$Question) {
    if ([Console]::IsInputRedirected) { throw "$Question - needs an answer and there is no console to ask on. Run prof in a terminal." }
    return (Read-GeneYesNo -Question $Question)
}

function Resolve-GeneProfCommand {
    <#
    The words typed after prof -> Group, Verb, Topic (or Help + Words). A command only one group has may be typed
    without its group: 'prof push' means 'prof setup push'. Ambiguous lists the groups when several have it.
    #>
    param([string]$First, [string]$Second, [string]$Third)
    $f = "$First".ToLowerInvariant(); $s = "$Second".ToLowerInvariant()
    $r = [pscustomobject]@{ Group = ''; Verb = ''; Topic = ''; Help = $false; Words = @(); Ambiguous = @() }
    if (-not $f) { return $r }
    if ($f -eq 'help') { $r.Help = $true; $r.Words = @(@($Second, $Third) | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() }); return $r }
    $names = @(Get-GeneProfGroupNames)
    if ($names -contains $f) { $r.Group = $f; $r.Verb = $s; $r.Topic = "$Third"; return $r }
    $owners = @($names | Where-Object { $script:ProfGroups[$_].Verbs.Contains($f) })
    if ($owners.Count -eq 1) { $r.Group = $owners[0]; $r.Verb = $f; $r.Topic = "$Second"; return $r }
    $r.Verb = $f; $r.Ambiguous = $owners
    return $r
}

function Show-GeneProfHelp {
    <# No words: every group and its commands. A group: its commands. A group and a command (or a command alone): that command in full. #>
    param([string[]]$Words)
    $w = @($Words | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $group = $null; $verb = $null
    $names = @(Get-GeneProfGroupNames)
    if ($w.Count -and $names -contains $w[0]) { $group = $w[0]; if ($w.Count -gt 1) { $verb = $w[1] } }
    elseif ($w.Count) {
        $owners = @($names | Where-Object { $script:ProfGroups[$_].Verbs.Contains($w[0]) })
        if ($owners.Count -eq 1) { $group = $owners[0]; $verb = $w[0] }
        else { Write-Host "No group or command called '$($w[0])'." -ForegroundColor Red }
    }
    if ($group -and $verb -and $script:ProfGroups[$group].Verbs.Contains($verb)) {
        $g = $script:ProfGroups[$group]
        Write-Host $g.Usage[$verb] -ForegroundColor Cyan
        Write-Host "  $($g.Verbs[$verb])"
        Write-Host ''
        foreach ($l in $g.Details[$verb]) { Write-Host "  $l" }
        Write-Host ''
        Write-Host '  -h shows this text. -WhatIf (on any command that changes something) shows what it would do and changes nothing.'
        return
    }
    if ($group) {
        $g = $script:ProfGroups[$group]
        Write-Host "prof $group <command> [options]     $($g.Description)" -ForegroundColor Cyan
        foreach ($v in $g.Verbs.Keys) { Write-Host ("  {0,-14} {1}" -f $v, $g.Verbs[$v]) }
        Write-Host ''
        Write-Host "prof $group alone opens this group's menu. prof help $group <command> explains one command."
        return
    }
    Write-Host 'prof <group> <command> [options] [-WhatIf] [-h]     (long name: manageProfile)' -ForegroundColor Cyan
    Write-Host 'prof alone opens a menu: pick a group, then a command, answer its questions, and it shows the full command before running it.'
    foreach ($gn in $names) {
        $g = $script:ProfGroups[$gn]
        Write-Host ''
        Write-Host ("{0}  {1}" -f $gn, $g.Description) -ForegroundColor Cyan
        foreach ($v in $g.Verbs.Keys) { Write-Host ("  {0,-14} {1}" -f $v, $g.Verbs[$v]) }
    }
    Write-Host ''
    Write-Host 'help       This list. prof help <group> lists one group; prof help <group> <command> explains one command.'
    Write-Host 'A command only one group has also works without the group: prof publish = prof build publish.'
    $old = @($script:ProfOldNames | Where-Object { Get-Command $_.Needs -ErrorAction SilentlyContinue })
    if ($old.Count) {
        Write-Host ''
        Write-Host 'Old commands still work:' -ForegroundColor Cyan
        foreach ($o in $old) { Write-Host ("  {0} -> {1}" -f $o.Old.PadRight(10), $o.New) }
    }
    if (Get-Command Get-GeneMachinesPath -ErrorAction SilentlyContinue) {
        Write-Host ''
        Write-Host "Machines prof knows are listed in $(Get-GeneMachinesPath). Each machine's folders come from its own settings file (prof setup config)."
    }
}

function Invoke-GeneProfMenu {
    <# Main menu (groups + help), then the group's menu, then the command's questions; shows the command, asks, runs. #>
    param([string]$Group, [scriptblock]$Reader)
    if (-not $Group) {
        $names = @(Get-GeneProfGroupNames)
        $items = @($names | ForEach-Object { [pscustomobject]@{ Name = $_; Description = $script:ProfGroups[$_].Description } }) +
        [pscustomobject]@{ Name = 'help'; Description = 'Explain the groups and their commands' }
        $pick = Select-GeneMenu -Title 'prof: what do you want to do?' -Items $items -Reader $Reader
        if (-not $pick) { return }
        if ($pick.Name -eq 'help') {
            $t = Select-GeneMenu -Title 'Help on?' -Items (@('(everything)') + $names) -Default 1 -Reader $Reader
            if ($t) { Show-GeneProfHelp -Words @($t | Where-Object { $_ -ne '(everything)' }) }
            return
        }
        $Group = $pick.Name
    }
    $g = $script:ProfGroups[$Group]
    if ($g.Menu) {
        # The group asks its own questions in its own order (build: product first, then what to do).
        $res = & $g.Menu -Reader $Reader
        if ($null -eq $res) { return }
        if ($res -eq 'help') { Show-GeneProfHelp -Words @($Group); return }
        Write-Host ''
        Write-Host "> $(Format-GeneProfCommand -Group $Group -Verb $res.Verb -Params $res.Params)" -ForegroundColor DarkCyan
        if (-not (Read-GeneYesNo -Question 'Run it?' -Default $true -Reader $Reader)) { return }
        $p = $res.Params
        Invoke-GeneProf -Group $Group -Verb $res.Verb @p
        return
    }
    $items = @($g.Verbs.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Description = $g.Verbs[$_] } }) +
    [pscustomobject]@{ Name = 'help'; Description = "Explain one of these commands in full" }
    $pick = Select-GeneMenu -Title "prof $Group`: what do you want to do?" -Items $items -Reader $Reader
    if (-not $pick) { return }
    if ($pick.Name -eq 'help') {
        $t = Select-GeneMenu -Title 'Help on?' -Items (@('(all of them)') + @($g.Verbs.Keys)) -Default 1 -Reader $Reader
        if ($t) { Show-GeneProfHelp -Words (@($Group) + @($t | Where-Object { $_ -ne '(all of them)' })) }
        return
    }
    $verb = $pick.Name
    $p = if ($g.Ask) { & $g.Ask -Verb $verb -Reader $Reader } else { [ordered]@{} }
    if ($null -eq $p) { return }
    Write-Host ''
    Write-Host "> $(Format-GeneProfCommand -Group $Group -Verb $verb -Params $p)" -ForegroundColor DarkCyan
    if (-not (Read-GeneYesNo -Question 'Run it?' -Default $true -Reader $Reader)) { return }
    Invoke-GeneProf -Group $Group -Verb $verb @p
}

# ------------------------------------------------------------------------------------------------ dispatcher
function Invoke-GeneProf {
    <#
    .SYNOPSIS
        prof: one command for my everyday tools, in groups. 'prof' alone opens a menu; 'prof help' lists everything.
        prof <group> <command> [options]; a command only one group has also works alone (prof push).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [ArgumentCompleter({ param($c, $p, $w) @(Get-GeneProfGroupNames) + 'help' | Where-Object { $_ -like "$w*" } })]
        [string]$Group,
        [Parameter(Position = 1)]
        [ArgumentCompleter({
                param($c, $p, $w, $a, $fb)
                $g = "$($fb['Group'])".ToLowerInvariant()
                $names = @(Get-GeneProfGroupNames)
                $list = if ($g -eq 'help') { $names } elseif ($names -contains $g) { @($script:ProfGroups[$g].Verbs.Keys) + 'help' } else { @() }
                $list | Where-Object { $_ -like "$w*" }
            })]
        [string]$Verb,
        [Parameter(Position = 2)]
        [ArgumentCompleter({
                param($c, $p, $w, $a, $fb)
                $g = "$($fb['Group'])".ToLowerInvariant()
                if ((Get-GeneProfGroupNames) -contains $g -and $script:ProfGroups[$g].TopicNames) { & $script:ProfGroups[$g].TopicNames | Where-Object { $_ -like "$w*" } }
            })]
        [string]$Topic,
        [ArgumentCompleter({ param($c, $p, $w) if (Get-Command Get-GeneMachines -ErrorAction SilentlyContinue) { (Get-GeneMachines).Keys | Where-Object { $_ -like "$w*" } } })]
        [string]$Machine,
        [string]$User,
        [string]$WorkDrive,
        [string[]]$Retire,
        [string]$Message,
        [switch]$FixProfile,
        [switch]$WithTerminal,
        [switch]$WithSecrets,
        [switch]$NoPublish,
        [switch]$AllowSecrets,
        [string]$Repo,
        [string]$Product,
        [switch]$AIOnly,
        [ValidateSet('None', 'Patch', 'Minor', 'Major')][string]$Bump,
        [ValidateSet('Debug', 'Release')][string]$Configuration,
        [string]$Out,
        [switch]$WhatIf,
        [Alias('h')][switch]$ShowHelp,
        # Anything prof does not know (build: the dp* command's own switches, e.g. -Test, -Run Web).
        [Parameter(ValueFromRemainingArguments)][object[]]$Extra
    )
    $ErrorActionPreference = 'Stop'
    $r = Resolve-GeneProfCommand $Group $Verb $Topic
    if ($r.Help) { Show-GeneProfHelp -Words $r.Words; return }
    if (-not $r.Group -and -not $r.Verb) { if ($ShowHelp) { Show-GeneProfHelp } else { Invoke-GeneProfMenu }; return }
    if ($r.Ambiguous.Count) { Write-Host "'$($r.Verb)' is in several groups ($($r.Ambiguous -join ', ')). Say which: prof $($r.Ambiguous[0]) $($r.Verb)" -ForegroundColor Red; return }
    if (-not $r.Group) { Write-Host "No group or command called '$($r.Verb)'." -ForegroundColor Red; Show-GeneProfHelp; return }
    $g = $script:ProfGroups[$r.Group]
    if (-not $r.Verb) { if ($ShowHelp) { Show-GeneProfHelp -Words @($r.Group) } else { Invoke-GeneProfMenu -Group $r.Group }; return }
    if ($r.Verb -eq 'help') { Show-GeneProfHelp -Words (@($r.Group) + @($r.Topic | Where-Object { $_ })); return }
    if (-not $g.Verbs.Contains($r.Verb)) { Write-Host "The $($r.Group) group has no command '$($r.Verb)'." -ForegroundColor Red; Show-GeneProfHelp -Words @($r.Group); return }
    if ($ShowHelp) { Show-GeneProfHelp -Words @($r.Group, $r.Verb); return }
    if ($r.Verb -in $g.NeedMachine -and -not $Machine) { throw "prof $($r.Group) $($r.Verb) needs -Machine. $($g.Usage[$r.Verb])" }

    $bound = [ordered]@{}
    if ($r.Topic -and $g.TopicParam -and -not $PSBoundParameters.ContainsKey($g.TopicParam)) { $bound[$g.TopicParam] = $r.Topic }
    elseif ($r.Topic) { throw "prof $($r.Group) $($r.Verb): did not expect '$($r.Topic)'. $($g.Usage[$r.Verb])" }
    foreach ($k in $PSBoundParameters.Keys) { if ($k -notin 'Group', 'Verb', 'Topic', 'ShowHelp') { $bound[$k] = $PSBoundParameters[$k] } }
    Write-Host "> $(Format-GeneProfCommand -Group $r.Group -Verb $r.Verb -Params $bound)" -ForegroundColor DarkCyan
    $fn = Get-GeneProfVerbFunction -Group $g -Verb $r.Verb
    $accepts = (Get-Command $fn).Parameters.Keys
    $call = @{}
    foreach ($k in $bound.Keys) {
        if ($k -in $accepts) { $call[$k] = $bound[$k] }
        elseif ($k -eq 'Extra') { throw "prof $($r.Group) $($r.Verb) does not know: $(@($bound.Extra) -join ' '). $($g.Usage[$r.Verb])" }
        else { Write-ProfWarn "-$k does not apply to prof $($r.Group) $($r.Verb); ignored." }
    }
    & $fn @call
}

Set-Alias -Name prof -Value Invoke-GeneProf
Set-Alias -Name manageProfile -Value Invoke-GeneProf
