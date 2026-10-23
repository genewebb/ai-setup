# prof: the groups, the setup commands, the dispatcher and the menu.
# Design: docs\manageprofile-design.md in the ai-setup clone.

# The setup group (profile + AI setup between machines): one line each for the menu and 'prof help'.
$script:ProfVerbs = [ordered]@{
    push      = 'Copy my profile and AI setup from this machine to another one, and install it there'
    pull      = 'Bring another machine''s changes (Claude memory, edits) back here, and install them here'
    status    = 'Show every machine: is it up to date with this one, does it have unsaved changes (changes nothing)'
    check     = 'Health check one machine: missing folders, settings gaps, what an install would change (changes nothing)'
    bootstrap = 'First-time setup of a new machine or account (can also archive an old account''s setup)'
    terminal  = 'Copy my Windows Terminal settings to another machine'
    secrets   = 'Copy my Claude API keys to another machine, protected by a one-time passphrase'
    config    = 'Show a machine''s folder settings (its ProfileMachineConfig.md)'
    edit      = 'Open my PowerShell profile for editing (the copy that every install uses)'
    reload    = 'Install my profile and AI setup on this machine again, after I edited them'
    show      = 'Is the profile this machine runs the same as the one I edit?'
    export    = 'Pack my profile for a coworker: one zip with the profile, modules, a blank machine config and an installer'
}

# The longer explanation 'prof help setup <command>' and '-h' print under the usage line.
$script:ProfDetails = @{
    push      = @(
        'Use it after you changed your profile or AI setup here and want another machine to have it.'
        'Steps: saves your changes here (and to GitHub), picks up anything new on the other machine (for example'
        'memory Claude wrote there), combines both, sends the result there, then runs the install there.'
        'Afterwards both machines have the same setup. -WhatIf shows what would happen and changes nothing.'
    )
    pull      = @(
        'Use it when you worked on another machine and want those changes here.'
        'Steps: saves what is new on the other machine, brings it here, combines it with this machine''s copy,'
        'then installs here. GitHub is not updated; push or publish.ps1 does that.'
    )
    status    = @(
        'One table: every machine and account prof knows, whether its copy matches this one, how many files'
        'it has not saved yet, when Claude''s setup was last installed there, and whether its profile matches.'
    )
    check     = @(
        'Looks at one machine without changing it: settings rows it is missing, folders it names that do not'
        'exist, and a dry run of the install (what it would change).'
    )
    bootstrap = @(
        'For a machine or account that has never had your setup. Creates its settings file if missing (or fixes'
        'it with -FixProfile), optionally moves an old account''s setup into the archive (-Retire), copies your'
        'setup there, installs it, and ends with a list of what is left to do by hand.'
    )
    terminal  = @(
        'Writes your Windows Terminal tabs, colours and fonts into that account''s Terminal settings (a backup'
        'is kept). Windows Terminal must have been opened once there as that account.'
    )
    secrets   = @(
        'Your Claude API keys never go through GitHub. This packs them into a file locked with a passphrase you'
        'type, copies it to the machine, installs it there, then deletes the file on both machines.'
    )
    config    = @(
        'Every machine has its own settings file (C:\Deploy\Setup\ProfileMachineConfig.md) saying where its'
        'folders are. This shows it, and for this machine whether each folder exists.'
    )
    edit      = @(
        'Opens the profile kept in the ai-setup repo. Edit that one: the copy in Documents\PowerShell is'
        'replaced by every install. When saved, run prof setup reload here or prof setup push for another machine.'
    )
    reload    = @(
        'Runs the install from your local ai-setup repo on this machine (nothing is downloaded), so your edits'
        'take effect. Then open a new tab, or type . $PROFILE, to load the new profile.'
    )
    show      = @(
        'Compares the profile this machine loads with the one in the repo, plus your own modules.'
        'If they differ, prof setup reload makes them the same.'
    )
    export    = @(
        'For someone who is not on my ai-setup repo. Copies the pwsh folder of the repo (profile, Gene.* modules,'
        'AddOrUpdateMyTerminal.ps1, modules.txt, Install-Profile.ps1), writes a ProfileMachineConfig.md with every'
        'value blank for them to fill in, a README, then zips it under ScratchRoot\prof (or -Out). Nothing from the AI'
        'setup and no secrets: the secret scan refuses, and every mention of my accounts, machines or personal paths'
        'is listed first so I can say no. They run Install-Profile.ps1 from the unzipped folder.'
    )
}
$script:ProfUsage = @{
    push      = 'prof setup push -Machine <name> [-User <DOMAIN\name>] [-NoPublish] [-AllowSecrets] [-Message <text>] [-WhatIf]'
    pull      = 'prof setup pull -Machine <name> [-User <DOMAIN\name>] [-AllowSecrets] [-WhatIf]'
    status    = 'prof setup status [-Machine <name>]'
    check     = 'prof setup check -Machine <name> [-User <DOMAIN\name>]'
    bootstrap = 'prof setup bootstrap -Machine <name> [-User <DOMAIN\name>] [-WorkDrive D:] [-FixProfile] [-Retire <DOMAIN\name>[,...]] [-WithTerminal] [-WithSecrets] [-WhatIf]'
    terminal  = 'prof setup terminal -Machine <name> [-User <DOMAIN\name>] [-WhatIf]'
    secrets   = 'prof setup secrets -Machine <name> [-User <DOMAIN\name>] [-WhatIf]'
    config    = 'prof setup config [-Machine <name>]'
    edit      = 'prof setup edit'
    reload    = 'prof setup reload [-WhatIf]'
    show      = 'prof setup show'
    export    = 'prof setup export [-Out <folder or file.zip>] [-WhatIf]'
}
$script:ProfOldNames = [ordered]@{
    sp = 'prof setup show'; ep = 'prof setup edit'; rp = 'prof setup reload (rp itself only reloads the profile in this window)'; machinecfg = 'prof setup config'
    gpush = 'prof git push'
    'dpspeed, dpcrewchief, dpdatagen, dpmutate, dpv2' = 'prof build run testauto | crewchief | datagen | mutate | speedy'
    'dp* -Package -Bump...' = 'prof build publish <product> -Bump Patch|Minor|Major'
    'dpall -Package' = 'prof build publish all'
}

# The groups: prof <group> <command>. The main menu lists them; each is one area of work. A group's commands are
# the functions <Prefix><Command> (TitleCase). Ask (optional) is the menu's question flow for a command: it returns
# the parameters as an ordered dictionary, or $null when the user cancels. Add a group here to add it to prof.
$script:ProfGroups = [ordered]@{
    setup = [pscustomobject]@{
        Description = 'Move my profile and AI setup between machines (push, pull, status, first-time setup, secrets)'
        Verbs       = $script:ProfVerbs
        Details     = $script:ProfDetails
        Usage       = $script:ProfUsage
        Prefix      = 'Invoke-GeneProf'
        NeedMachine = @('push', 'pull', 'check', 'bootstrap', 'terminal', 'secrets')
        Ask         = 'Read-GeneSetupMenuParams'
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

function Get-GeneHubProfile { Read-GeneTargetProfile -Path (Get-GeneTargetProfilePath -Machine $env:COMPUTERNAME) }

function Get-GeneHubRepo { New-GeneRepo -Path (Get-GeneHubRoot) }

function Invoke-GeneLocalInstall {
    param([string]$Hub, [switch]$WhatIf)
    $a = @('-NoProfile', '-File', (Join-Path $Hub 'install.ps1'), '-NoPull') + $(if ($WhatIf) { '-Check' } else { '-Yes' })
    & pwsh @a
    return $LASTEXITCODE
}

function Confirm-GeneProf([string]$Question) {
    if ([Console]::IsInputRedirected) { throw "$Question - needs an answer and there is no console to ask on. Run prof in a terminal." }
    return (Read-GeneYesNo -Question $Question)
}

function Get-GeneTargetClone {
    <# The target clone (local path, share path, repo object) for a resolved target with a session. #>
    param($Target, [switch]$MustExist)
    $local = $Target.Paths.Local['AIWorkRoot']; $unc = $Target.Paths.Unc['AIWorkRoot']
    if (-not $local) { throw "AIWorkRoot is blank in $($Target.ProfilePath). Run: prof setup bootstrap -Machine $($Target.Machine) -User $($Target.User) -FixProfile" }
    if ($MustExist -and -not (Test-Path -LiteralPath (Join-Path $unc '.git'))) {
        throw "No ai-setup clone for $($Target.User) on $($Target.Machine) at $local. Run: prof setup bootstrap -Machine $($Target.Machine) -User $($Target.User)"
    }
    [pscustomobject]@{ Local = $local; Unc = $unc; Repo = (New-GeneRepo -Path $local -Session $Target.Session -Machine $Target.Machine) }
}

function Assert-GenePerUser {
    param($Target)
    if (@($Target.Users).Count -gt 1 -and -not (Test-GenePerUserValue $Target.Profile.Raw['AIWorkRoot'])) {
        throw "$($Target.Machine) lists $(@($Target.Users).Count) accounts but its AIWorkRoot ($($Target.Profile.Raw['AIWorkRoot'])) is not per-user, so they would share one clone. Run: prof setup bootstrap -Machine $($Target.Machine) -User $($Target.User) -FixProfile"
    }
}

# ------------------------------------------------------------------------------------------------ status
function Get-GeneRemoteRepoStates {
    <#
    HEAD and uncommitted-file count of clones on another machine, read ON that machine through one WinRM session as
    the caller (Kerberos, no prompt). Without WinRM: HEAD over the share, Dirty '?'. Returns path => state.
    #>
    param([Parameter(Mandatory)][string]$Machine, [string[]]$Paths)
    $result = @{}
    if (-not $Paths) { return $result }
    try {
        $rows = Invoke-Command -ComputerName $Machine -ErrorAction Stop -ArgumentList (, $Paths) -ScriptBlock {
            param($paths)
            foreach ($p in $paths) {
                if (-not (Test-Path -LiteralPath (Join-Path $p '.git'))) { [pscustomobject]@{ Path = $p; Exists = $false; Head = $null; Dirty = '' }; continue }
                $h = (& git -c safe.directory=* -C $p rev-parse HEAD 2>$null | Select-Object -First 1)
                $d = @(& git -c safe.directory=* -C $p status --porcelain --untracked-files=all 2>$null | Where-Object { $_ }).Count
                [pscustomobject]@{ Path = $p; Exists = $true; Head = "$h"; Dirty = $d }
            }
        }
        foreach ($r in $rows) { $result[$r.Path] = $r }
    }
    catch {
        foreach ($p in $Paths) {
            $unc = ConvertTo-GeneUncPath -Machine $Machine -Path $p
            $exists = Test-Path -LiteralPath (Join-Path $unc '.git')
            $h = if ($exists) { (Invoke-GeneGitResult $unc @('rev-parse', 'HEAD')).Out | Select-Object -First 1 } else { $null }
            $result[$p] = [pscustomobject]@{ Path = $p; Exists = $exists; Head = $h; Dirty = '? (no WinRM)' }
        }
    }
    return $result
}

function Get-GeneRuntimeRevision {
    param([string]$ClaudeHome)
    $f = Join-Path $ClaudeHome 'machine-config.state.json'
    if (-not (Test-Path -LiteralPath $f)) { return 'not installed' }
    try { $s = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json; return "$($s.identity.Substring(0, 12)) $(([datetime]$s.installedAt).ToString('MM-dd HH:mm'))" }
    catch { return 'unreadable state' }
}

function Invoke-GeneProfStatus {
    param([string]$Machine)
    $hub = Get-GeneHubRoot
    $hubProfileHash = (Get-FileHash -LiteralPath (Join-Path $hub 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1')).Hash
    $rows = [System.Collections.Generic.List[object]]::new()

    if (-not $Machine -or (Test-GeneIsLocalMachine $Machine)) {
        $s = Get-GeneRepoState (Get-GeneHubRepo)
        $ab = (Invoke-GeneGitResult $hub @('rev-list', '--left-right', '--count', 'origin/main...HEAD')).Out | Select-Object -First 1
        $rel = if ($ab -match '^(\d+)\s+(\d+)$') { "origin: ahead $($Matches[2]), behind $($Matches[1]) (as of last fetch)" } else { 'origin: unknown' }
        $rows.Add([pscustomobject]@{ Machine = "$env:COMPUTERNAME (hub)"; User = (Get-GeneCaller); Clone = "yes ($hub)"; Head = $s.Head.Substring(0, 7); Dirty = $s.Dirty.Count; Relation = $rel
                Runtime = (Get-GeneRuntimeRevision (Join-Path $HOME '.claude')); Profile = $(if ((Test-Path -LiteralPath $PROFILE) -and (Get-FileHash -LiteralPath $PROFILE).Hash -eq $hubProfileHash) { 'in sync' } else { 'DIFFERS (prof setup reload)' }) })
    }
    $known = Get-GeneMachines
    foreach ($name in $known.Keys) {
        if ($Machine -and $name -ine $Machine) { continue }
        if (Test-GeneIsLocalMachine $name) { continue }
        $sd = $known[$name].systemDrive
        if (-not (Test-Path -LiteralPath "\\$name\$($sd)`$")) { $rows.Add([pscustomobject]@{ Machine = $name; User = '*'; Clone = 'unreachable'; Head = ''; Dirty = ''; Relation = "no \\$name\$($sd)`$"; Runtime = ''; Profile = '' }); continue }
        $tp = Read-GeneTargetProfile -Path (Get-GeneTargetProfilePath -Machine $name -SystemDrive $sd)
        if (-not $tp) { $rows.Add([pscustomobject]@{ Machine = $name; User = '*'; Clone = 'no machine profile'; Head = ''; Dirty = ''; Relation = 'prof setup bootstrap'; Runtime = ''; Profile = '' }); continue }
        $users = @($known[$name].users)
        $clonePaths = @($users | ForEach-Object { Expand-GeneOffline -Value $tp.Raw['AIWorkRoot'] -User $_ -SystemDrive $sd } | Where-Object { $_ } | Select-Object -Unique)
        $states = Get-GeneRemoteRepoStates -Machine $name -Paths $clonePaths
        foreach ($u in $users) {
            $aiw = Expand-GeneOffline -Value $tp.Raw['AIWorkRoot'] -User $u -SystemDrive $sd
            $ch = Expand-GeneOffline -Value $(if ($tp.Raw['ClaudeHome']) { $tp.Raw['ClaudeHome'] } else { '%USERPROFILE%\.claude' }) -User $u -SystemDrive $sd
            $docs = Expand-GeneOffline -Value '%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1' -User $u -SystemDrive $sd
            $row = [ordered]@{ Machine = $name; User = $u; Clone = ''; Head = ''; Dirty = ''; Relation = ''; Runtime = ''; Profile = '' }
            if (-not $aiw) { $row.Clone = 'AIWorkRoot unresolved'; $rows.Add([pscustomobject]$row); continue }
            $state = $states[$aiw]
            $row.Clone = if ($state.Exists) { "yes ($aiw)" } else { "none at $aiw" }
            if ($state.Exists) { $row.Head = $state.Head.Substring(0, 7); $row.Dirty = $state.Dirty; $row.Relation = Get-GeneRelation -Hub $hub -TargetHead $state.Head }
            else { $row.Relation = 'prof setup bootstrap' }
            if ($ch) { $row.Runtime = Get-GeneRuntimeRevision (ConvertTo-GeneUncPath -Machine $name -Path $ch) }
            if ($docs) {
                $pf = ConvertTo-GeneUncPath -Machine $name -Path $docs
                $row.Profile = if (-not (Test-Path -LiteralPath $pf)) { 'none' } elseif ((Get-FileHash -LiteralPath $pf).Hash -eq $hubProfileHash) { 'in sync' } else { 'differs' }
            }
            $rows.Add([pscustomobject]$row)
        }
    }
    if ($Machine -and -not (Test-GeneIsLocalMachine $Machine) -and -not @($known.Keys | Where-Object { $_ -ieq $Machine })) {
        Write-ProfWarn "$Machine is not in machines.yaml. prof setup bootstrap adds it; prof setup status lists only known machines."
    }
    $rows | Format-Table -AutoSize -Wrap | Out-String -Width 220 | Write-Host
}

# ------------------------------------------------------------------------------------------------ config / edit / reload / show / help
function Invoke-GeneProfConfig {
    param([string]$Machine)
    $local = -not $Machine -or (Test-GeneIsLocalMachine $Machine)
    $path = if ($local) { Get-GeneTargetProfilePath -Machine $env:COMPUTERNAME } else {
        $known = Get-GeneMachines; $k = @($known.Keys | Where-Object { $_ -ieq $Machine }) | Select-Object -First 1
        Get-GeneTargetProfilePath -Machine $Machine -SystemDrive $(if ($k) { $known[$k].systemDrive } else { 'C' })
    }
    $p = Read-GeneTargetProfile -Path $path
    if (-not $p) { throw "No machine profile at $path." }
    Write-ProfStep "machine profile $path"
    $rows = foreach ($k in $p.Raw.Keys) {
        $v = $p.Raw[$k]
        if ($local) {
            $e = if ($v) { [Environment]::ExpandEnvironmentVariables($v) } else { '' }
            [pscustomobject]@{ Key = $k; Value = $v; Here = $e; Exists = $(if ($e -match '^[A-Za-z]:\\|^\\\\') { Test-Path -LiteralPath $e } else { '' }) }
        }
        else { [pscustomobject]@{ Key = $k; Value = $v; PerUser = $(if (Test-GenePerUserValue $v) { 'yes' } else { '' }) } }
    }
    $rows | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
    Write-ProfNote "Later tables: $((@($p.Tables.Keys | Where-Object { $_ }) -join ', '))"
}

function Invoke-GeneProfEdit {
    $f = Join-Path (Get-GeneHubRoot) 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1'
    Write-ProfNote "Editing the repo copy: $f"
    Write-ProfNote 'When saved: prof setup reload (this machine), prof setup push -Machine <name> (another one).'
    if (Get-Command code -ErrorAction SilentlyContinue) { code $f } else { notepad $f }
}

function Invoke-GeneProfReload {
    param([switch]$WhatIf)
    $code = Invoke-GeneLocalInstall -Hub (Get-GeneHubRoot) -WhatIf:$WhatIf
    if ($code -ne 0) { Write-ProfWarn "install.ps1 exited $code (see above)." }
    elseif (-not $WhatIf) {
        # By name: piping Get-Module's output to Import-Module -Force does not re-read the files. -Global: from inside
        # a module, Import-Module would otherwise load into this module's own scope, not the window's.
        foreach ($m in @(Get-Module -Name 'Gene.*' | Select-Object -ExpandProperty Name -Unique)) { Import-Module -Name $m -Force -Global -DisableNameChecking }
        Write-ProfNote 'Installed, and prof and the other Gene modules are reloaded in this window. For the profile''s own commands (dp*, addStreams ...): . $PROFILE. Any other window: . $PROFILE there reloads both.'
    }
}

function Invoke-GeneProfShow {
    $hub = Get-GeneHubRoot
    $repoFile = Join-Path $hub 'pwsh\PowerShell\Microsoft.PowerShell_profile.ps1'
    $rh = (Get-FileHash -LiteralPath $repoFile).Hash
    $ih = if (Test-Path -LiteralPath $PROFILE) { (Get-FileHash -LiteralPath $PROFILE).Hash } else { '' }
    $mods = 0
    $repoMods = Join-Path $hub 'pwsh\PowerShell\Modules'
    foreach ($f in Get-ChildItem -LiteralPath $repoMods -Recurse -File) {
        $dest = Join-Path (Join-Path (Split-Path $PROFILE) 'Modules') ([IO.Path]::GetRelativePath($repoMods, $f.FullName))
        if (-not (Test-Path -LiteralPath $dest) -or (Get-FileHash -LiteralPath $dest).Hash -ne (Get-FileHash -LiteralPath $f.FullName).Hash) { $mods++ }
    }
    [pscustomobject]@{ Copy = 'installed (what loads)'; Path = $PROFILE; Hash = $(if ($ih) { $ih.Substring(0, 12) } else { 'missing' }) },
    [pscustomobject]@{ Copy = 'repo (what you edit)'; Path = $repoFile; Hash = $rh.Substring(0, 12) } | Format-Table -AutoSize | Out-String -Width 220 | Write-Host
    Write-ProfNote $(if ($ih -eq $rh) { 'Profile: in sync.' } else { 'Profile: DIFFERS. prof setup reload installs the repo copy.' })
    Write-ProfNote $(if ($mods) { "Own modules: $mods file(s) differ from the repo. prof setup reload installs them." } else { 'Own modules: in sync.' })
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
    if ($script:ProfGroups.Contains($f)) { $r.Group = $f; $r.Verb = $s; $r.Topic = "$Third"; return $r }
    $owners = @($script:ProfGroups.Keys | Where-Object { $script:ProfGroups[$_].Verbs.Contains($f) })
    if ($owners.Count -eq 1) { $r.Group = $owners[0]; $r.Verb = $f; $r.Topic = "$Second"; return $r }
    $r.Verb = $f; $r.Ambiguous = $owners
    return $r
}

function Show-GeneProfHelp {
    <# No words: every group and its commands. A group: its commands. A group and a command (or a command alone): that command in full. #>
    param([string[]]$Words)
    $w = @($Words | Where-Object { $_ } | ForEach-Object { $_.ToLowerInvariant() })
    $group = $null; $verb = $null
    if ($w.Count -and $script:ProfGroups.Contains($w[0])) { $group = $w[0]; if ($w.Count -gt 1) { $verb = $w[1] } }
    elseif ($w.Count) {
        $owners = @($script:ProfGroups.Keys | Where-Object { $script:ProfGroups[$_].Verbs.Contains($w[0]) })
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
    foreach ($gn in $script:ProfGroups.Keys) {
        $g = $script:ProfGroups[$gn]
        Write-Host ''
        Write-Host ("{0}  {1}" -f $gn, $g.Description) -ForegroundColor Cyan
        foreach ($v in $g.Verbs.Keys) { Write-Host ("  {0,-14} {1}" -f $v, $g.Verbs[$v]) }
    }
    Write-Host ''
    Write-Host 'help       This list. prof help <group> lists one group; prof help <group> <command> explains one command.'
    Write-Host 'A command only one group has also works without the group: prof publish = prof build publish.'
    Write-Host ''
    Write-Host 'Old commands still work:' -ForegroundColor Cyan
    foreach ($k in $script:ProfOldNames.Keys) { Write-Host ("  {0} -> {1}" -f $k.PadRight(10), $script:ProfOldNames[$k]) }
    Write-Host ''
    Write-Host "Machines prof knows are listed in $(Get-GeneMachinesPath). Each machine's folders come from its own settings file (prof setup config)."
}

# ------------------------------------------------------------------------------------------------ pull
function Invoke-GeneProfPull {
    param([Parameter(Mandatory)][string]$Machine, [string]$User, [switch]$AllowSecrets, [switch]$WhatIf)
    $hub = Get-GeneHubRoot
    $t = Resolve-GeneTarget -Machine $Machine -User $User
    Assert-GenePerUser $t
    $aiw = Expand-GeneOffline -Value $t.Profile.Raw['AIWorkRoot'] -User $t.User -SystemDrive $t.SystemDrive
    if (-not $aiw) { throw "AIWorkRoot ($($t.Profile.Raw['AIWorkRoot'])) on $($t.Machine) cannot be expanded without a session as that account. Use prof setup push, which opens one." }
    # Worktree git runs on that machine as you (Kerberos, no prompt); the clone may belong to another account.
    $session = New-PSSession -ComputerName $t.Machine -ErrorAction Stop
    try {
        $repo = New-GeneRepo -Path $aiw -Session $session -Machine $t.Machine
        $state = Get-GeneRepoState $repo
        if (-not $state.Exists) { throw "No ai-setup clone for $($t.User) on $($t.Machine) at $aiw. Run: prof setup bootstrap -Machine $($t.Machine) -User $($t.User)" }
        if ($state.Branch -ne 'main') { throw "The clone on $($t.Machine) is on '$($state.Branch)', not main. Fix it there first." }
        $hubState = Get-GeneRepoState (Get-GeneHubRepo)
        Write-ProfStep "pull $($t.Machine)\$(Get-GeneUserName $t.User) -> $env:COMPUTERNAME"
        Write-ProfNote "target clone $aiw at $($state.Head.Substring(0,7)), $($state.Dirty.Count) uncommitted file(s); $(Get-GeneRelation -Hub $hub -TargetHead $state.Head)"
        Write-ProfNote "hub $hub, $($hubState.Dirty.Count) uncommitted file(s)"
        if ($WhatIf) {
            foreach ($d in @($state.Dirty | Select-Object -First 15)) { Write-ProfNote "  target: $d" }
            Write-ProfNote '(-WhatIf: nothing committed, merged or installed)'
            return
        }
        $h1 = Invoke-GeneHarvest -Repo $repo -Label "$($t.Machine)\$(Get-GeneUserName $t.User)" -Hub $hub -AllowSecrets:$AllowSecrets
        $h0 = Invoke-GeneHarvest -Repo (Get-GeneHubRepo) -Label "$env:COMPUTERNAME hub" -Hub $hub -AllowSecrets:$AllowSecrets
        $m = Invoke-GeneMergeFromTarget -Hub $hub -Repo $repo
        Write-ProfStep 'install here'
        $code = Invoke-GeneLocalInstall -Hub $hub
        Write-ProfStep 'summary'
        Write-ProfNote "target: $(if ($h1.Committed) { "$($h1.Files.Count) file(s) committed there" } else { 'nothing uncommitted' }); hub: $(if ($h0.Committed) { "$($h0.Files.Count) local file(s) committed" } else { 'clean' })"
        Write-ProfNote "merged $($m.Merged) commit(s) from $($t.Machine); install here exited $code"
        Write-ProfNote 'GitHub not touched: publish.ps1 (or prof setup push) sends it.'
    }
    finally { Remove-PSSession $session -ErrorAction SilentlyContinue }
}

# ------------------------------------------------------------------------------------------------ push
function Invoke-GeneProfPush {
    param([Parameter(Mandatory)][string]$Machine, [string]$User, [switch]$NoPublish, [switch]$AllowSecrets, [string]$Message, [switch]$WhatIf)
    $hub = Get-GeneHubRoot
    $t = Resolve-GeneTarget -Machine $Machine -User $User -NeedSession
    try {
        Assert-GenePerUser $t
        $clone = Get-GeneTargetClone -Target $t -MustExist
        $state = Get-GeneRepoState $clone.Repo
        if ($state.Branch -ne 'main') { throw "The clone on $($t.Machine) is on '$($state.Branch)', not main. Fix it there first." }
        $label = "$($t.Machine)\$(Get-GeneUserName $t.User)"
        Write-ProfStep "push $env:COMPUTERNAME -> $label"
        Write-ProfNote "target clone $($clone.Local) at $($state.Head.Substring(0,7)), $($state.Dirty.Count) uncommitted; $(Get-GeneRelation -Hub $hub -TargetHead $state.Head)"
        Write-ProfNote "hub $hub, $((Get-GeneRepoState (Get-GeneHubRepo)).Dirty.Count) uncommitted"
        if ($WhatIf) {
            foreach ($d in @($state.Dirty | Select-Object -First 15)) { Write-ProfNote "  target: $d" }
            Write-ProfStep "install.ps1 -Check on $($t.Machine) as $($t.User)"
            $c = Invoke-GeneRemotePwsh -Target $t -File (Join-Path $clone.Local 'install.ps1') -Arguments @('-NoPull', '-Check')
            Write-ProfNote "(-WhatIf: nothing committed, merged, pushed or installed; the check exited $c)"
            return
        }
        Set-GeneTargetGitConfig -Hub $hub -Repo $clone.Repo

        Write-ProfStep '1. publish here'
        if ($NoPublish) {
            $h0 = Invoke-GeneHarvest -Repo (Get-GeneHubRepo) -Label "$env:COMPUTERNAME hub" -Hub $hub -AllowSecrets:$AllowSecrets
            Write-ProfNote "-NoPublish: $(if ($h0.Committed) { "$($h0.Files.Count) hub file(s) committed locally" } else { 'hub clean' }); GitHub not touched"
        }
        else {
            $pa = @('-NoProfile', '-File', (Join-Path $hub 'publish.ps1')) + $(if ($Message) { @('-Message', $Message) } else { @() })
            & pwsh @pa
            $pc = $LASTEXITCODE
            if ($pc -ne 0) {
                if ((Get-GeneRepoState (Get-GeneHubRepo)).Dirty.Count) { throw "publish.ps1 exited $pc and the hub still has uncommitted changes (declined or failed; see above). Nothing was sent to $($t.Machine). Re-run, or use -NoPublish to commit locally only." }
                Write-ProfWarn "publish.ps1 exited $pc (GitHub not updated; see above). Carrying on: $($t.Machine) is the goal."
            }
        }

        Write-ProfStep "2. harvest $label"
        $h1 = Invoke-GeneHarvest -Repo $clone.Repo -Label $label -Hub $hub -AllowSecrets:$AllowSecrets
        Write-ProfNote $(if ($h1.Committed) { "$($h1.Files.Count) file(s) committed there" } else { 'nothing uncommitted there' })

        Write-ProfStep "3. merge $label into the hub"
        $m = Invoke-GeneMergeFromTarget -Hub $hub -Repo $clone.Repo
        Write-ProfNote "$($m.Merged) commit(s) merged"

        Write-ProfStep "4. push into $label"
        $hubHead = (Invoke-GeneGit $hub @('rev-parse', 'HEAD')) | Select-Object -First 1
        $p = if ($hubHead -ne (Get-GeneRepoState $clone.Repo).Head) { Invoke-GenePushToTarget -Hub $hub -Repo $clone.Repo } else { $null }
        Write-ProfNote $(if ($p) { "$($p.From.Substring(0,7)) -> $($p.To.Substring(0,7))" } else { 'already at the hub''s HEAD' })

        if (-not $NoPublish -and $m.Merged -gt 0) {
            Write-ProfStep '5. GitHub (the merge)'
            $r = Invoke-GeneGitResult $hub @('push', '-q', 'origin', 'HEAD:main')
            if ($r.Code -ne 0) { Write-ProfWarn "git push origin failed: $($r.Out -join ' '). Publish again later (publish.ps1)." } else { Write-ProfNote 'pushed' }
        }

        Write-ProfStep "6. install on $($t.Machine) as $($t.User)"
        $ic = Invoke-GeneRemotePwsh -Target $t -File (Join-Path $clone.Local 'install.ps1') -Arguments @('-NoPull', '-Yes')

        Write-ProfStep 'summary'
        Write-ProfNote "from $label`: $(if ($h1.Committed) { "$($h1.Files.Count) file(s) harvested, " } else { '' })$($m.Merged) commit(s) merged here"
        Write-ProfNote "to $label`: $(if ($p) { "$($p.From.Substring(0,7)) -> $($p.To.Substring(0,7))" } else { 'no change' })"
        Write-ProfNote "install there exited $ic$(switch ($ic) { 0 { ' (ok)' } 2 { ' (machine profile invalid: prof setup check)' } 3 { ' (stopped on drift: see above)' } default { '' } })"
        Write-ProfNote "Open a new pwsh on $($t.Machine) (or prof setup reload there) to load the new profile."
    }
    finally { Close-GeneTarget $t }
}

# ------------------------------------------------------------------------------------------------ check
function Invoke-GeneProfCheck {
    param([Parameter(Mandatory)][string]$Machine, [string]$User)
    $hub = Get-GeneHubRoot
    $t = Resolve-GeneTarget -Machine $Machine -User $User -NeedSession -AllowMissingProfile
    try {
        Write-ProfStep "check $($t.Machine) for $($t.User)"
        if (-not $t.Profile) { Write-ProfWarn "No machine profile at $($t.ProfilePath). prof setup bootstrap creates one."; return }
        $fix = Get-GeneProfileFix -HubRaw (Get-GeneHubProfile).Raw -TargetRaw $t.Profile.Raw
        Write-ProfNote "machine profile $($t.ProfilePath)"
        if ($fix.Missing.Count) { Write-ProfWarn "rows this machine lacks (the hub has them): $($fix.Missing -join ', ')" } else { Write-ProfNote 'no rows missing compared with the hub' }
        if ($fix.AIWorkRoot) { Write-ProfWarn "AIWorkRoot '$($fix.AIWorkRoot.Old)' is not per-user (one clone per account): prof setup bootstrap -FixProfile sets '$($fix.AIWorkRoot.New)'" }
        $paths = Invoke-Command -Session $t.Session -ArgumentList $t.Profile.Raw -ScriptBlock {
            param($raw)
            foreach ($k in $raw.Keys) {
                $v = [string]$raw[$k]; if (-not $v) { continue }
                $e = [Environment]::ExpandEnvironmentVariables($v)
                if ($e -match '^[A-Za-z]:\\') { [pscustomobject]@{ Key = $k; Path = $e; Exists = (Test-Path -LiteralPath $e) } }
            }
        }
        $gone = @($paths | Where-Object { -not $_.Exists })
        if ($gone.Count) { foreach ($g in $gone) { Write-ProfWarn "$($g.Key) = $($g.Path) does not exist on $($t.Machine) for $($t.User)" } } else { Write-ProfNote 'every path row exists there' }
        $clone = Get-GeneTargetClone -Target $t
        $state = Get-GeneRepoState $clone.Repo
        if (-not $state.Exists) { Write-ProfWarn "no clone at $($clone.Local): prof setup bootstrap"; return }
        Write-ProfNote "clone $($clone.Local) at $($state.Head.Substring(0,7)), $($state.Dirty.Count) uncommitted; $(Get-GeneRelation -Hub $hub -TargetHead $state.Head)"
        Write-ProfStep "install.ps1 -Check on $($t.Machine) as $($t.User)"
        $c = Invoke-GeneRemotePwsh -Target $t -File (Join-Path $clone.Local 'install.ps1') -Arguments @('-NoPull', '-Check')
        Write-ProfNote "the check exited $c"
    }
    finally { Close-GeneTarget $t }
}

# ------------------------------------------------------------------------------------------------ machine profile seed and fix
function Get-GeneProfileFix {
    <# Rows the target lacks compared with the hub, and the per-user AIWorkRoot it should have. #>
    param([Parameter(Mandatory)][System.Collections.IDictionary]$HubRaw, [Parameter(Mandatory)][System.Collections.IDictionary]$TargetRaw)
    $missing = @($HubRaw.Keys | Where-Object { -not $TargetRaw.Contains($_) })
    $aiw = $null
    if (-not (Test-GenePerUserValue $TargetRaw['AIWorkRoot'])) {
        $repos = [string]$TargetRaw['ReposRoot']
        $base = if ($repos) { Split-Path $repos } else { '' }
        if (-not $base) { $base = Split-Path ([string]$HubRaw['ReposRoot']) }
        $aiw = [pscustomobject]@{ Old = [string]$TargetRaw['AIWorkRoot']; New = (Join-Path $base '%USERNAME%\ai-setup') }
    }
    [pscustomobject]@{ Missing = $missing; AIWorkRoot = $aiw; Empty = (-not $missing.Count -and -not $aiw) }
}

function Edit-GeneProfileLines {
    <#
    Applies a fix to the lines of a machine profile: replaces the AIWorkRoot value and appends missing rows (blank
    value) at the end of the first table. Every other line is kept as it is.
    #>
    param([Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines, [Parameter(Mandatory)]$Fix, [string]$Note = 'added by prof setup bootstrap: fill in')
    $out = [System.Collections.Generic.List[string]]::new()
    $inFirst = $false; $done = $false
    foreach ($line in $Lines) {
        $isRow = $line -match '^\s*\|'
        if (-not $done -and $isRow) { $inFirst = $true }
        if ($inFirst -and -not $done -and $isRow -and $Fix.AIWorkRoot -and $line -match '^(\s*\|\s*`?AIWorkRoot`?\s*\|)([^|]*)(\|.*)$') {
            $line = "$($Matches[1]) $($Fix.AIWorkRoot.New) $($Matches[3])"
        }
        if ($inFirst -and -not $done -and -not $isRow) {
            foreach ($k in $Fix.Missing) { $out.Add("| $k |  | $Note | unverified |") }
            $done = $true; $inFirst = $false
        }
        $out.Add($line)
    }
    if ($inFirst -and -not $done) { foreach ($k in $Fix.Missing) { $out.Add("| $k |  | $Note | unverified |") } }
    return , $out.ToArray()
}

function New-GeneSeedProfile {
    <#
    A machine profile for a machine that has none: the hub's, with the hub's work drive moved to -WorkDrive, a per-user
    AIWorkRoot, the machine name in the title and 'unverified' in the Status column. Later tables are copied as they
    are and listed for review: they hold this machine's literal paths.
    #>
    param([Parameter(Mandatory)][string]$Machine, [string]$WorkDrive)
    $hp = Get-GeneHubProfile
    $hubDrive = ([string]$hp.Raw['ReposRoot']).Substring(0, 1)
    $wd = if ($WorkDrive) { $WorkDrive.Substring(0, 1).ToUpperInvariant() } else { $hubDrive }
    $out = [System.Collections.Generic.List[string]]::new()
    $inFirst = $false; $done = $false; $literal = [System.Collections.Generic.List[string]]::new()
    foreach ($line in $hp.Lines) {
        $isRow = $line -match '^\s*\|'
        if ($line -match '^#\s') { $line = $line -replace [regex]::Escape($env:COMPUTERNAME), $Machine }
        if (-not $done -and $isRow) { $inFirst = $true }
        if ($inFirst -and -not $done -and -not $isRow) { $done = $true; $inFirst = $false }
        if ($inFirst -and $isRow) {
            $cells = @($line.Trim().Trim('|') -split '\|' | ForEach-Object { $_.Trim() })
            if ($cells.Count -ge 2 -and $cells[0] -match '^`?[A-Za-z][A-Za-z0-9]*`?$' -and $cells[0] -notin 'Key', 'Setting') {
                $v = $cells[1]
                if ($v -match "^$hubDrive`:\\") { $v = "$wd" + $v.Substring(1) }
                if ($cells[0].Trim('`') -eq 'AIWorkRoot') {
                    $repos = [string]$hp.Raw['ReposRoot']; if ($repos -match "^$hubDrive`:\\") { $repos = "$wd" + $repos.Substring(1) }
                    $v = Join-Path (Split-Path $repos) '%USERNAME%\ai-setup'
                }
                if ($cells.Count -ge 4) { $cells[3] = 'unverified' }
                $cells[1] = $v
                $line = '| ' + ($cells -join ' | ') + ' |'
            }
            elseif ($cells[0] -in 'Key', 'Setting' -and $cells.Count -ge 4) { $cells[3] = "Status on $Machine"; $line = '| ' + ($cells -join ' | ') + ' |' }
        }
        elseif ($done -and $isRow -and $line -match '[A-Za-z]:\\') { $literal.Add($line.Trim()) }
        $out.Add($line)
    }
    [pscustomobject]@{ Lines = $out.ToArray(); LiteralRows = $literal.ToArray() }
}

# ------------------------------------------------------------------------------------------------ retire
function Get-GeneInstalledAccounts {
    <# Accounts on the machine with an installed Claude runtime (ClaudeHome\machine-config.state.json under Users). #>
    param([Parameter(Mandatory)][string]$Machine, [string]$SystemDrive = 'C')
    $users = "\\$Machine\$($SystemDrive)`$\Users"
    @(Get-ChildItem -LiteralPath $users -Directory -ErrorAction SilentlyContinue | Where-Object {
            Test-Path -LiteralPath (Join-Path $_.FullName '.claude\machine-config.state.json')
        } | ForEach-Object { $_.Name })
}

function Invoke-GeneRetire {
    <#
    Moves (never deletes) one account's Claude install on the target into {ArchiveRoot}\ai-retire-<stamp>\<name>: its
    .claude folder, .claude.json, PowerShell profile folders and its old AIWorkRoot when that is not a git clone.
    Memory found there is merged into the hub first. Refuses while that account runs Claude or node.
    #>
    param([Parameter(Mandatory)]$Target, [Parameter(Mandatory)][string]$Account, [string]$Hub = (Get-GeneHubRoot), [switch]$WhatIf)
    $acc = Resolve-GeneUser $Account; $name = Get-GeneUserName $acc
    $sd = $Target.SystemDrive
    $archive = Expand-GeneOffline -Value $Target.Profile.Raw['ArchiveRoot'] -User $acc -SystemDrive $sd
    if (-not $archive) { throw "ArchiveRoot is blank or unresolved in $($Target.ProfilePath); retire needs it (the archive is never a drive that may not exist)." }
    $cands = @("$($sd):\Users\$name\.claude", "$($sd):\Users\$name\.claude.json", "$($sd):\Users\$name\Documents\PowerShell", "$($sd):\Users\$name\Documents\WindowsPowerShell")
    $oldAiw = Expand-GeneOffline -Value $Target.Profile.Raw['AIWorkRoot'] -User $acc -SystemDrive $sd
    if ($oldAiw -and -not (Test-Path -LiteralPath (Join-Path (ConvertTo-GeneUncPath -Machine $Target.Machine -Path $oldAiw) '.git'))) { $cands += $oldAiw }
    $items = @($cands | Where-Object { Test-Path -LiteralPath (ConvertTo-GeneUncPath -Machine $Target.Machine -Path $_) })
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $dest = Join-Path $archive "ai-retire-$stamp\$name"
    Write-ProfStep "retire $acc on $($Target.Machine)"
    if (-not $items.Count) { Write-ProfNote 'nothing of that account''s Claude install is there'; return }
    foreach ($i in $items) { Write-ProfNote "move $i -> $dest" }
    $running = @(Invoke-Command -Session $Target.Session -ArgumentList $name -ScriptBlock {
            param($n) Get-Process -IncludeUserName -ErrorAction SilentlyContinue | Where-Object { $_.UserName -and ($_.UserName -split '\\')[-1] -ieq $n -and $_.Name -in 'claude', 'node' } | ForEach-Object { "$($_.Name) $($_.Id)" }
        })
    if ($running.Count) { throw "$acc is running $($running -join ', ') on $($Target.Machine). Close those first; nothing was moved." }
    if ($WhatIf) { Write-ProfNote '(-WhatIf: nothing moved)'; return }
    if (-not (Confirm-GeneProf "Move these to $dest on $($Target.Machine)?")) { throw "Retire of $acc declined; nothing was moved and bootstrap stopped." }

    $mem = ConvertTo-GeneUncPath -Machine $Target.Machine -Path "$($sd):\Users\$name\.claude\memory"
    $mi = Get-Item -LiteralPath $mem -Force -ErrorAction SilentlyContinue
    if ($mi -and -not $mi.LinkType) {
        $merged = 0
        foreach ($f in Get-ChildItem -LiteralPath $mem -Recurse -File) {
            $rel = [IO.Path]::GetRelativePath($mem, $f.FullName); $to = Join-Path $Hub "memory\$rel"
            $d = Get-Item -LiteralPath $to -ErrorAction SilentlyContinue
            if (-not $d -or ((Get-FileHash -LiteralPath $f.FullName).Hash -ne (Get-FileHash -LiteralPath $to).Hash -and $f.LastWriteTimeUtc -gt $d.LastWriteTimeUtc)) {
                New-Item -ItemType Directory -Force -Path (Split-Path $to) | Out-Null
                Copy-Item -LiteralPath $f.FullName -Destination $to -Force; $merged++
            }
        }
        Write-ProfNote "memory: $merged file(s) merged into $Hub\memory (uncommitted; the next publish carries them)"
    }
    $res = Invoke-Command -Session $Target.Session -ArgumentList $items, $dest, $name -ScriptBlock {
        param($items, $dest, $n)
        New-Item -ItemType Directory -Force -Path $dest | Out-Null
        foreach ($i in $items) {
            $to = Join-Path $dest (Split-Path $i -Leaf)
            $sameRoot = [IO.Path]::GetPathRoot($i) -ieq [IO.Path]::GetPathRoot($dest)
            if ((Test-Path -LiteralPath $i -PathType Leaf) -or $sameRoot) { Move-Item -LiteralPath $i -Destination $to -Force; "moved $i" }
            else {
                $null = robocopy $i $to /E /MOVE /COPY:DAT /R:1 /W:1 /NFL /NDL /NJH /NJS /NP
                if ($LASTEXITCODE -ge 8) { "FAILED $i (robocopy $LASTEXITCODE)" } else { "moved $i" }
            }
        }
        $task = Get-ScheduledTask -TaskName 'AI scratch cleanup' -ErrorAction SilentlyContinue
        if ($task -and ($task.Principal.UserId -split '\\')[-1] -ieq $n) { Unregister-ScheduledTask -TaskName 'AI scratch cleanup' -Confirm:$false; "unregistered the 'AI scratch cleanup' task of $n" }
    }
    foreach ($r in $res) { Write-ProfNote $r }
    if (@($res | Where-Object { $_ -like 'FAILED*' }).Count) { throw "Some moves failed (above). Fix them on $($Target.Machine) before going on." }
    if (Remove-GeneMachineUser -Name $Target.Machine -User $acc) { Write-ProfNote "removed $acc from machines.yaml" }
}

# ------------------------------------------------------------------------------------------------ clone
function New-GeneTargetClone {
    <#
    Clones the hub's main on the target, AS -User, from a bundle file: one file crosses the share, the checkout is
    written by the target's own git, and the clone belongs to that account (no ACL or safe.directory work).
    #>
    param($Target, $Clone, [string]$Hub)
    $scratchLocal = $Target.Paths.Local['ScratchRoot']; $scratchUnc = $Target.Paths.Unc['ScratchRoot']
    if (-not $scratchLocal) { throw "ScratchRoot is blank in $($Target.ProfilePath); the clone bundle is staged there." }
    $hubScratch = (Get-AIMachineProfile).Keys['ScratchRoot']
    $name = "ai-setup-$(Get-Date -Format yyyyMMdd-HHmmss).bundle"
    $here = Join-Path $hubScratch "prof\$name"; $thereUnc = Join-Path $scratchUnc "prof\$name"; $thereLocal = Join-Path $scratchLocal "prof\$name"
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $here), (Split-Path $thereUnc) | Out-Null
        Invoke-GeneGit $Hub @('bundle', 'create', '-q', $here, 'main') | Out-Null
        Copy-Item -LiteralPath $here -Destination $thereUnc -Force
        $out = @(Invoke-Command -Session $Target.Session -ArgumentList $thereLocal, $Clone.Local -ScriptBlock {
                param($b, $dest)
                $ErrorActionPreference = 'Continue'
                New-Item -ItemType Directory -Force -Path (Split-Path $dest) | Out-Null
                & git clone -q -b main $b $dest 2>&1 | ForEach-Object { "$_" }
                "__PROF_GIT_EXIT__$LASTEXITCODE"
            })
        if ($out[-1] -ne '__PROF_GIT_EXIT__0') { throw "git clone on $($Target.Machine) failed: $(($out | Select-Object -SkipLast 1) -join ' ')" }
        Set-GeneTargetGitConfig -Hub $Hub -Repo $Clone.Repo
        Write-ProfNote "cloned $((Get-GeneRepoState $Clone.Repo).Head.Substring(0,7)) into $($Clone.Local) as $($Target.User)"
    }
    finally { foreach ($f in $here, $thereUnc) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } } }
}

# ------------------------------------------------------------------------------------------------ bootstrap
function Invoke-GeneProfBootstrap {
    param(
        [Parameter(Mandatory)][string]$Machine, [string]$User, [string]$WorkDrive, [switch]$FixProfile, [string[]]$Retire,
        [switch]$WithTerminal, [switch]$WithSecrets, [switch]$AllowSecrets, [switch]$WhatIf
    )
    $hub = Get-GeneHubRoot
    $t = Resolve-GeneTarget -Machine $Machine -User $User -NeedSession -AllowMissingProfile
    $left = [System.Collections.Generic.List[string]]::new()
    try {
        $retire = @($Retire | ForEach-Object { $_ -split ',' } | Where-Object { $_ } | ForEach-Object { Resolve-GeneUser $_.Trim() })
        if ($retire -contains $t.User) { throw "-Retire names $($t.User), the account being bootstrapped." }

        Write-ProfStep "1. machine profile $($t.ProfilePath)"
        $fix = $null
        if (-not $t.Profile) {
            $seed = New-GeneSeedProfile -Machine $t.Machine -WorkDrive $WorkDrive
            Write-ProfNote "none there: a new one from $env:COMPUTERNAME's, work drive $(if ($WorkDrive) { $WorkDrive } else { 'unchanged' }), per-user AIWorkRoot"
            foreach ($l in @($seed.Lines | Where-Object { $_ -match '^\|\s*`?(AIWorkRoot|ReposRoot|ScratchRoot|ClaudeHome|ArchiveRoot)`?\s*\|' })) { Write-ProfNote "  $l" }
            foreach ($l in $seed.LiteralRows) { Write-ProfWarn "review (copied literally from $env:COMPUTERNAME): $l" }
            if ($WhatIf) { Write-ProfNote '(-WhatIf: not written)' }
            else {
                if (-not (Confirm-GeneProf "Write this machine profile to $($t.ProfilePath)?")) { throw 'Declined; nothing was written.' }
                New-Item -ItemType Directory -Force -Path (Split-Path $t.ProfilePath) | Out-Null
                Set-Content -LiteralPath $t.ProfilePath -Value $seed.Lines -Encoding utf8NoBOM
                $t.Profile = Read-GeneTargetProfile -Path $t.ProfilePath
                $left.Add("Review every row of $($t.ProfilePath) (Status says unverified; later tables were copied from $env:COMPUTERNAME).")
            }
        }
        else {
            $fix = Get-GeneProfileFix -HubRaw (Get-GeneHubProfile).Raw -TargetRaw $t.Profile.Raw
            if ($fix.Missing.Count) { Write-ProfNote "rows missing compared with the hub: $($fix.Missing -join ', ')" }
            if ($fix.AIWorkRoot) { Write-ProfNote "AIWorkRoot '$($fix.AIWorkRoot.Old)' -> '$($fix.AIWorkRoot.New)' (one clone per account)" }
            if ($fix.Empty) { Write-ProfNote 'nothing to change' }
            elseif ($FixProfile) {
                $new = Edit-GeneProfileLines -Lines $t.Profile.Lines -Fix $fix
                if ($WhatIf) { Write-ProfNote '(-WhatIf: -FixProfile would apply the lines above)' }
                else {
                    if (-not (Confirm-GeneProf "Apply these changes to $($t.ProfilePath) (a .bak copy is kept)?")) { throw 'Declined; nothing was written.' }
                    Copy-Item -LiteralPath $t.ProfilePath -Destination "$($t.ProfilePath).bak-$(Get-Date -Format yyyyMMdd-HHmmss)"
                    Set-Content -LiteralPath $t.ProfilePath -Value $new -Encoding utf8NoBOM
                    $t.Profile = Read-GeneTargetProfile -Path $t.ProfilePath
                    if ($fix.Missing.Count) { $left.Add("Fill in the rows added to $($t.ProfilePath): $($fix.Missing -join ', ').") }
                }
            }
            elseif ($fix.AIWorkRoot) {
                if ($WhatIf) { Write-ProfWarn 'a real run needs -FixProfile for the AIWorkRoot change' }
                else { throw "AIWorkRoot on $($t.Machine) is not per-user. Re-run with -FixProfile (shows the change and asks)." }
            }
        }

        $others = @(Get-GeneInstalledAccounts -Machine $t.Machine -SystemDrive $t.SystemDrive | Where-Object { $_ -ine (Get-GeneUserName $t.User) })
        $uncovered = @($others | Where-Object { $o = $_; -not @($retire | Where-Object { (Get-GeneUserName $_) -ieq $o }).Count })
        if ($fix -and $fix.AIWorkRoot -and $uncovered.Count) {
            $msg = "Changing AIWorkRoot changes it for every account on $($t.Machine). These accounts have an installed runtime there: $($uncovered -join ', '). Name them in -Retire (archived) or bootstrap them too."
            if ($WhatIf) { Write-ProfWarn $msg } else { throw $msg }
        }

        if ($retire.Count) { Write-ProfStep '2. retire'; foreach ($r in $retire) { Invoke-GeneRetire -Target $t -Account $r -Hub $hub -WhatIf:$WhatIf } }

        Write-ProfStep "3. paths for $($t.User)"
        if (-not $t.Profile) { Write-ProfNote '(-WhatIf: the machine profile does not exist yet, so the rest cannot be resolved)'; return }
        $raw = $t.Profile.Raw
        if ($WhatIf -and $fix -and $fix.AIWorkRoot) { $raw = [ordered]@{} + $raw; $raw['AIWorkRoot'] = $fix.AIWorkRoot.New }
        $t.Paths = Get-GeneTargetPaths -Machine $t.Machine -Raw $raw -Session $t.Session
        $clone = Get-GeneTargetClone -Target $t
        Write-ProfNote "AIWorkRoot $($clone.Local); ClaudeHome $($t.Paths.Local['ClaudeHome']); ScratchRoot $($t.Paths.Local['ScratchRoot'])"

        Write-ProfStep '4. clone'
        if (Test-Path -LiteralPath (Join-Path $clone.Unc '.git')) { Write-ProfNote 'already cloned (prof setup push from now on)' }
        elseif ((Test-Path -LiteralPath $clone.Unc) -and @(Get-ChildItem -LiteralPath $clone.Unc -Force).Count) { throw "$($clone.Local) exists, is not empty and is not a git clone. Move it aside first." }
        elseif ($WhatIf) { Write-ProfNote "(-WhatIf: would clone $hub's main into $($clone.Local) as $($t.User), from a bundle file)" }
        else { New-GeneTargetClone -Target $t -Clone $clone -Hub $hub }

        Write-ProfStep "5. install on $($t.Machine) as $($t.User)"
        if ($WhatIf) {
            if (Test-Path -LiteralPath (Join-Path $clone.Unc 'install.ps1')) { $c = Invoke-GeneRemotePwsh -Target $t -File (Join-Path $clone.Local 'install.ps1') -Arguments @('-NoPull', '-Check'); Write-ProfNote "the check exited $c" }
            else { Write-ProfNote '(-WhatIf: no clone yet, so install.ps1 -Check cannot run there)' }
        }
        else {
            $ic = Invoke-GeneRemotePwsh -Target $t -File (Join-Path $clone.Local 'install.ps1') -Arguments @('-NoPull', '-Yes')
            Write-ProfNote "install exited $ic"
            if ($ic -ne 0) { $left.Add("install.ps1 on $($t.Machine) exited ${ic}: read its output above, fix, then prof setup push -Machine $($t.Machine) -User $($t.User).") }
        }

        if (-not $WhatIf) {
            if (Add-GeneMachine -Name $t.Machine -User $t.User) { Write-ProfNote "added $($t.User) on $($t.Machine) to machines.yaml (uncommitted)" }
            if ($WithTerminal) { Invoke-GeneTerminalOn -Target $t -Clone $clone -Left $left } else { $left.Add("Windows Terminal settings: prof setup terminal -Machine $($t.Machine) -User $($t.User)") }
            if ($WithSecrets) { Invoke-GeneSecretsOn -Target $t -Clone $clone -Hub $hub } else { $left.Add("Claude secrets (MCP keys): prof setup secrets -Machine $($t.Machine) -User $($t.User)") }
        }
        $left.Add("Sign in to Claude as $($t.User) on $($t.Machine): start it with 'ai'.")
        $left.Add('Chocolatey tools and anything install.ps1 reported as not installed are not done by prof.')
        Write-ProfStep 'LEFT TO DO'
        foreach ($l in $left) { Write-ProfNote "- $l" }
    }
    finally { Close-GeneTarget $t }
}

# ------------------------------------------------------------------------------------------------ terminal / secrets
function Invoke-GeneTerminalOn {
    param($Target, $Clone, [System.Collections.Generic.List[string]]$Left)
    $script = Join-Path $Clone.Local 'pwsh\AddOrUpdateMyTerminal.ps1'
    if (-not (Test-Path -LiteralPath (Join-Path $Clone.Unc 'pwsh\AddOrUpdateMyTerminal.ps1'))) { throw "The clone on $($Target.Machine) has no pwsh\AddOrUpdateMyTerminal.ps1 yet: prof setup push first." }
    Write-ProfStep "Windows Terminal settings for $($Target.User) on $($Target.Machine)"
    $c = Invoke-GeneRemotePwsh -Target $Target -File $script -Arguments @('-ForUser')
    if ($c -eq 3) { $Left.Add("Open Windows Terminal once as $($Target.User) on $($Target.Machine) (install it there if missing), then prof setup terminal -Machine $($Target.Machine) -User $($Target.User).") }
    elseif ($c -ne 0) { $Left.Add("prof setup terminal on $($Target.Machine) exited $c (see above).") }
    $Left.Add("Desktop shortcuts on $($Target.Machine): run pwsh\AddOrUpdateMyTerminal.ps1 there at the desktop (needs a console and admin).")
}

function Invoke-GeneSecretsOn {
    param($Target, $Clone, [string]$Hub)
    Write-ProfStep "Claude secrets -> $($Target.User) on $($Target.Machine)"
    if (-not (Test-Path -LiteralPath (Join-Path $Clone.Unc 'install.ps1'))) { throw "No clone on $($Target.Machine) yet: prof setup bootstrap first." }
    $p1 = Read-Host 'Passphrase for this one transfer (12+ characters, used once, never stored)' -AsSecureString
    $p2 = Read-Host 'Type it again' -AsSecureString
    $plain = { param($s) $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s); try { [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) } }
    $a = & $plain $p1; $b = & $plain $p2
    if ($a -cne $b) { throw 'The passphrases differ; nothing was exported.' }
    if ($a.Length -lt 12) { throw 'Use at least 12 characters; nothing was exported.' }
    $a = $null; $b = $null
    $hubScratch = (Get-AIMachineProfile).Keys['ScratchRoot']
    $name = "secrets-$($Target.Machine)-$(Get-GeneUserName $Target.User)-$(Get-Date -Format yyyyMMdd-HHmmss).bin"
    $localOut = Join-Path $hubScratch "prof\$name"
    $remoteLocal = Join-Path $Target.Paths.Local['ScratchRoot'] "prof\$name"
    $remoteUnc = Join-Path $Target.Paths.Unc['ScratchRoot'] "prof\$name"
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $localOut), (Split-Path $remoteUnc) | Out-Null
        & (Join-Path $Hub 'setup\Export-AISecrets.ps1') -Out $localOut -Passphrase $p1
        Copy-Item -LiteralPath $localOut -Destination $remoteUnc -Force
        $c = Invoke-GeneRemotePwsh -Target $Target -File (Join-Path $Clone.Local 'install.ps1') -Arguments @('-NoPull', '-Yes', '-SecretsFile', $remoteLocal, '-PassphraseFromStdin') -Stdin $p1
        Write-ProfNote "install with the secrets exited $c"
    }
    finally {
        foreach ($f in $localOut, $remoteUnc) { if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f -Force } }
        Write-ProfNote 'the secrets file was deleted here and there'
    }
}

function Invoke-GeneProfTerminal {
    param([Parameter(Mandatory)][string]$Machine, [string]$User, [switch]$WhatIf)
    $t = Resolve-GeneTarget -Machine $Machine -User $User -NeedSession
    try {
        $clone = Get-GeneTargetClone -Target $t -MustExist
        if ($WhatIf) { Write-ProfNote "(-WhatIf: would run $($clone.Local)\pwsh\AddOrUpdateMyTerminal.ps1 -ForUser on $($t.Machine) as $($t.User))"; return }
        $left = [System.Collections.Generic.List[string]]::new()
        Invoke-GeneTerminalOn -Target $t -Clone $clone -Left $left
        if ($left.Count) { Write-ProfStep 'LEFT TO DO'; foreach ($l in $left) { Write-ProfNote "- $l" } }
    }
    finally { Close-GeneTarget $t }
}

function Invoke-GeneProfSecrets {
    param([Parameter(Mandatory)][string]$Machine, [string]$User, [switch]$WhatIf)
    $t = Resolve-GeneTarget -Machine $Machine -User $User -NeedSession
    try {
        $clone = Get-GeneTargetClone -Target $t -MustExist
        if ($WhatIf) { Write-ProfNote "(-WhatIf: would export Claude secrets here, copy them to $($t.Paths.Local['ScratchRoot'])\prof on $($t.Machine), run install.ps1 -SecretsFile there as $($t.User), then delete both copies)"; return }
        Invoke-GeneSecretsOn -Target $t -Clone $clone -Hub (Get-GeneHubRoot)
    }
    finally { Close-GeneTarget $t }
}

# ------------------------------------------------------------------------------------------------ menu
function Read-GeneSetupMenuParams {
    <# The menu's questions for one setup command. Returns the parameters, or $null when the user cancels. #>
    param([Parameter(Mandatory)][string]$Verb, [scriptblock]$Reader)
    $g = $script:ProfGroups['setup']
    $p = [ordered]@{}
    $known = Get-GeneMachines
    if ($Verb -in $g.NeedMachine -or $Verb -in 'config', 'status') {
        $mItems = @()
        if ($Verb -eq 'config') { $mItems += [pscustomobject]@{ Name = '(this machine)'; Description = $env:COMPUTERNAME } }
        if ($Verb -eq 'status') { $mItems += [pscustomobject]@{ Name = '(every known machine)'; Description = '' } }
        $mItems += @($known.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Description = ($known[$_].users -join ', ') } })
        $mItems += [pscustomobject]@{ Name = '(type another name)'; Description = '' }
        $m = Select-GeneMenu -Title 'Which machine?' -Items $mItems -Default 1 -Reader $Reader
        if (-not $m) { return $null }
        if ($m.Name -eq '(type another name)') { $p.Machine = ([string](Read-GeneText -Reader $Reader -Prompt 'Machine name')).Trim(); if (-not $p.Machine) { return $null } }
        elseif ($m.Name -notlike '(*') { $p.Machine = $m.Name }
    }
    if ($Verb -in $g.NeedMachine) {
        $k = @($known.Keys | Where-Object { $_ -ieq $p.Machine }) | Select-Object -First 1
        $uList = @(@(Get-GeneCaller) + @(if ($k) { $known[$k].users }) | Select-Object -Unique)
        $uItems = @($uList | ForEach-Object { [pscustomobject]@{ Name = $_; Description = $(if ($_ -ieq (Get-GeneCaller)) { 'you' } else { '' }) } }) + [pscustomobject]@{ Name = '(type another account)'; Description = 'DOMAIN\name' }
        $u = Select-GeneMenu -Title 'As which account there?' -Items $uItems -Default 1 -Reader $Reader
        if (-not $u) { return $null }
        $p.User = if ($u.Name -eq '(type another account)') { Resolve-GeneUser ([string](Read-GeneText -Reader $Reader -Prompt 'Account (DOMAIN\name)')).Trim() } else { $u.Name }
    }
    $yn = { param($q, $d = $false) Read-GeneYesNo -Question $q -Default $d -Reader $Reader }
    switch ($Verb) {
        'push' { if (& $yn 'Dry run only (-WhatIf)?') { $p.WhatIf = $true }; if (& $yn 'Skip GitHub (-NoPublish: commit here only)?') { $p.NoPublish = $true } }
        'pull' { if (& $yn 'Dry run only (-WhatIf)?') { $p.WhatIf = $true } }
        'bootstrap' {
            if (& $yn 'Dry run only (-WhatIf)?' $true) { $p.WhatIf = $true }
            $wd = ([string](Read-GeneText -Reader $Reader -Prompt 'Work drive for a NEW machine profile (e.g. D:, Enter = same as this machine)')).Trim(); if ($wd) { $p.WorkDrive = $wd }
            if (& $yn 'Fix the existing machine profile if needed (-FixProfile)?') { $p.FixProfile = $true }
            $r = ([string](Read-GeneText -Reader $Reader -Prompt 'Accounts to retire there, comma separated (Enter = none)')).Trim(); if ($r) { $p.Retire = @($r -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }) }
            if (& $yn 'Also Windows Terminal settings (-WithTerminal)?') { $p.WithTerminal = $true }
            if (& $yn 'Also Claude secrets (-WithSecrets)?') { $p.WithSecrets = $true }
        }
        { $_ -in 'terminal', 'secrets', 'reload' } { if (& $yn 'Dry run only (-WhatIf)?') { $p.WhatIf = $true } }
        'export' {
            if (& $yn 'Dry run only (-WhatIf: list, write nothing)?') { $p.WhatIf = $true }
            $o = ([string](Read-GeneText -Reader $Reader -Prompt 'Where to write the zip (folder or file.zip; Enter = ScratchRoot\prof)')).Trim(); if ($o) { $p.Out = $o }
        }
    }
    return $p
}

function Invoke-GeneProfMenu {
    <# Main menu (groups + help), then the group's menu, then the command's questions; shows the command, asks, runs. #>
    param([string]$Group, [scriptblock]$Reader)
    if (-not $Group) {
        $items = @($script:ProfGroups.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Description = $script:ProfGroups[$_].Description } }) +
        [pscustomobject]@{ Name = 'help'; Description = 'Explain the groups and their commands' }
        $pick = Select-GeneMenu -Title 'prof: what do you want to do?' -Items $items -Reader $Reader
        if (-not $pick) { return }
        if ($pick.Name -eq 'help') {
            $t = Select-GeneMenu -Title 'Help on?' -Items (@('(everything)') + @($script:ProfGroups.Keys)) -Default 1 -Reader $Reader
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
        [ArgumentCompleter({ param($c, $p, $w) @($script:ProfGroups.Keys) + 'help' | Where-Object { $_ -like "$w*" } })]
        [string]$Group,
        [Parameter(Position = 1)]
        [ArgumentCompleter({
                param($c, $p, $w, $a, $fb)
                $g = "$($fb['Group'])".ToLowerInvariant()
                $list = if ($g -eq 'help') { @($script:ProfGroups.Keys) } elseif ($script:ProfGroups.Contains($g)) { @($script:ProfGroups[$g].Verbs.Keys) + 'help' } else { @() }
                $list | Where-Object { $_ -like "$w*" }
            })]
        [string]$Verb,
        [Parameter(Position = 2)]
        [ArgumentCompleter({
                param($c, $p, $w, $a, $fb)
                $g = "$($fb['Group'])".ToLowerInvariant()
                if ($script:ProfGroups.Contains($g) -and $script:ProfGroups[$g].TopicNames) { & $script:ProfGroups[$g].TopicNames | Where-Object { $_ -like "$w*" } }
            })]
        [string]$Topic,
        [ArgumentCompleter({ param($c, $p, $w) (Get-GeneMachines).Keys | Where-Object { $_ -like "$w*" } })]
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
    # status-rebuild -> StatusRebuild: a command's function is <Prefix><Word><Word>.
    $fn = $g.Prefix + (($r.Verb -split '-' | ForEach-Object { (Get-Culture).TextInfo.ToTitleCase($_) }) -join '')
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
