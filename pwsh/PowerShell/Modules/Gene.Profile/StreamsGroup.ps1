# prof streams: the stream board (agent tabs on the stream host), through the stream commands in the PowerShell profile
# (addStreams, addStreamTab, stopStreams, removeStreamTab, rerunStreamTab, getStreams, pushStreams, updateStreams).
# The repo is SpeedyRepo from this machine's profile unless -Repo. -WhatIf becomes the commands' -DryRun. Their other
# switches (-Author, -Count 2, -CloseSessions, -FromHost ...) follow the command as they are.

$script:ProfStreamsCommands = [ordered]@{
    add              = 'addStreams'
    tab              = 'addStreamTab'
    stop             = 'stopStreams'
    remove           = 'removeStreamTab'
    rerun            = 'rerunStreamTab'
    get              = 'getStreams'
    push             = 'pushStreams'
    update           = 'updateStreams'
    'status-rebuild' = ''
}
$script:ProfStreamsVerbs = [ordered]@{
    add              = 'Open the whole set of stream tabs in this Windows Terminal window (addStreams)'
    tab              = 'Open one more stream tab: a role, or more authors/builders (addStreamTab)'
    stop             = 'Stop runners cleanly; each finishes its current unit first (stopStreams)'
    remove           = 'Stop some author or builder tabs by number (removeStreamTab)'
    rerun            = 'In a stopped author/builder tab: start its runner again (rerunStreamTab)'
    get              = 'Bring this machine up to date, or take the board over from another host (getStreams)'
    push             = "Send this machine's changes up, or hand the board off (pushStreams)"
    update           = 'Rolling update of a running board: stop cleanly, update, start the same layout (updateStreams)'
    'status-rebuild' = "Make the Status runner rebuild the status page now (touches its inbox file)"
}
$script:ProfStreamsDetails = @{
    add              = @('Planner first, then Integrator, Kit, Coordinator, Status, then the authors and builders. Run it from a', 'Windows Terminal tab on the stream host. -Force reopens roles that look alive; -AnyHost skips the host check.')
    tab              = @('-Role Planner|Integrator|Kit|Coordinator|Status|Adhoc opens that role; -Author or -Builder adds runners', '(-Count n for several; -ClearStop clears an old STOP file first).')
    stop             = @('Writes the STOP file(s): every runner (or -Role a,b) finishes its unit, exits, and its tab closes.', '-CloseSessions also closes the long Planner/Adhoc sessions. Returns at once.')
    remove           = @('(-Author | -Builder) -Number 2,3: only those runners finish their unit and exit.')
    rerun            = @('Type it inside the stopped tab itself; it starts the same runner script addStreamTab used.')
    get              = @('Default: install the kit (AIWorkRoot) and pull the code (SpeedyRepo). -NoKit / -NoCode skip one.', '-FromHost <old host> takes the board over from that machine (stop there, mirror, mark it moved).')
    push             = @('Default: publish the kit and push the code branch where the Git policy allows. Run it in a Windows', 'Terminal tab (sign-in and questions need a console). -Handoff stops everything first, to move the board.')
    update           = @('Records what runs, stops it cleanly, installs the kit (and the code with -Code), then starts the same', 'runners again. -RestartSessions also restarts the long sessions.')
    'status-rebuild' = @('Sets the LastWriteTime of <repo>\.streams\inbox\stream-status.md to now, so the Status runner sees', 'new work in its inbox and rebuilds. The repo is SpeedyRepo from this machine''s profile unless -Repo.')
}
$script:ProfStreamsUsage = @{
    add              = 'prof streams add [-Repo <repo>] [-Force] [-AnyHost] [-WhatIf]'
    tab              = 'prof streams tab (-Role <role> | -Author | -Builder) [-Count <n>] [-ClearStop] [-Repo <repo>] [-WhatIf]'
    stop             = 'prof streams stop [-Role <name>,...] [-CloseSessions] [-Repo <repo>] [-WhatIf]'
    remove           = 'prof streams remove (-Author | -Builder) -Number <n>,... [-Repo <repo>] [-WhatIf]'
    rerun            = 'prof streams rerun'
    get              = 'prof streams get [-NoKit] [-NoCode] [-FromHost <old host>] [-Yes] [-Repo <repo>] [-WhatIf]'
    push             = 'prof streams push [-Message <text>] [-NoKit] [-NoCode] [-Handoff] [-Yes] [-Repo <repo>] [-WhatIf]'
    update           = 'prof streams update [-Code] [-RestartSessions] [-Yes] [-Repo <repo>] [-WhatIf]'
    'status-rebuild' = 'prof streams status-rebuild [-Repo <repo>] [-WhatIf]'
}

# First in the main menu: the board is what prof is used for most.
$script:ProfGroups.Insert(0, 'streams', [pscustomobject]@{
    Description = 'The stream board: open, stop, update and move the agent tabs; rebuild the status page'
    Verbs       = $script:ProfStreamsVerbs
    Details     = $script:ProfStreamsDetails
    Usage       = $script:ProfStreamsUsage
    Prefix      = 'Invoke-GeneProfStreams'
    NeedMachine = @()
    Ask         = 'Read-GeneStreamsBoardParams'
})

function Invoke-GeneStreamsCommand {
    <# Runs one stream command with prof's -Repo/-Message, the extra switches, and -WhatIf as -DryRun. #>
    param([Parameter(Mandatory)][string]$Verb, [string]$Repo, [string]$Message, [object[]]$Extra, [switch]$WhatIf)
    $name = $script:ProfStreamsCommands[$Verb]
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) { throw "$name is not loaded. It lives in the PowerShell profile: open a new tab, or . `$PROFILE." }
    $splat = ConvertTo-GeneCommandArgs -Command $name -Extra $Extra
    $params = (Get-Command $name).Parameters
    if ($Repo) { if ($params.ContainsKey('Repo')) { $splat.Repo = $Repo } else { throw "$name takes no -Repo." } }
    if ($Message) { if ($params.ContainsKey('Message')) { $splat.Message = $Message } else { throw "$name takes no -Message." } }
    if ($WhatIf) { if ($params.ContainsKey('DryRun')) { $splat.DryRun = $true } else { throw "$name has no dry run." } }
    $shown = @($name) + @($splat.Keys | ForEach-Object { $v = $splat[$_]; if ($v -is [bool] -or $v -is [switch]) { if ($v) { "-$_" } } else { "-$_ $(@($v) -join ',')" } })
    Write-ProfNote "Running: $($shown -join ' ')"
    & $name @splat
}

function Invoke-GeneProfStreamsAdd { param([string]$Repo, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneStreamsCommand add -Repo $Repo -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfStreamsTab { param([string]$Repo, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneStreamsCommand tab -Repo $Repo -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfStreamsStop { param([string]$Repo, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneStreamsCommand stop -Repo $Repo -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfStreamsRemove { param([string]$Repo, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneStreamsCommand remove -Repo $Repo -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfStreamsRerun { param([object[]]$Extra) Invoke-GeneStreamsCommand rerun -Extra $Extra }
function Invoke-GeneProfStreamsGet { param([string]$Repo, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneStreamsCommand get -Repo $Repo -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfStreamsPush { param([string]$Repo, [string]$Message, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneStreamsCommand push -Repo $Repo -Message $Message -Extra $Extra -WhatIf:$WhatIf }
function Invoke-GeneProfStreamsUpdate { param([string]$Repo, [object[]]$Extra, [switch]$WhatIf) Invoke-GeneStreamsCommand update -Repo $Repo -Extra $Extra -WhatIf:$WhatIf }

function Invoke-GeneProfStreamsStatusRebuild {
    <# Touch <repo>\.streams\inbox\stream-status.md so the Status runner rebuilds. Repo = -Repo or SpeedyRepo. #>
    param([string]$Repo, [switch]$WhatIf)
    $root = if ($Repo) { $Repo } else { Get-GeneLocalPath 'SpeedyRepo' }
    if (-not $root) { throw 'No repo: pass -Repo, or set SpeedyRepo in this machine''s profile.' }
    $file = Join-Path $root '.streams\inbox\stream-status.md'
    if (-not (Test-Path -LiteralPath $file)) { throw "No Status inbox file at $file. Is the board set up in $root (prof streams add)?" }
    if ($WhatIf) { Write-Host "[WhatIf] Would set the LastWriteTime of $file to now." -ForegroundColor Yellow; return }
    (Get-Item -LiteralPath $file).LastWriteTime = Get-Date
    Write-ProfNote "Touched $file ($((Get-Item -LiteralPath $file).LastWriteTime.ToString('HH:mm:ss'))): the Status runner rebuilds on its next tick."
}

function Read-GeneStreamsBoardParams {
    <# The menu's questions for one streams (board) command. Returns the parameters, or $null when the user cancels. #>
    param([Parameter(Mandatory)][string]$Verb, [scriptblock]$Reader)
    $p = [ordered]@{}
    $extra = @()
    $yn = { param($q, $d = $false) Read-GeneYesNo -Question $q -Default $d -Reader $Reader }
    switch ($Verb) {
        'tab' {
            $kinds = @('Author', 'Builder', 'Planner', 'Integrator', 'Kit', 'Coordinator', 'Status', 'Adhoc') | ForEach-Object {
                [pscustomobject]@{ Name = $_; Description = $(if ($_ -in 'Author', 'Builder') { 'add runner tab(s)' } else { 'one tab for this role' }) }
            }
            $k = Select-GeneMenu -Title 'Which tab?' -Items $kinds -Default 1 -Reader $Reader
            if (-not $k) { return $null }
            if ($k.Name -in 'Author', 'Builder') {
                $extra += "-$($k.Name)"
                $n = ([string](Read-GeneText -Reader $Reader -Prompt 'How many (Enter = 1)')).Trim()
                if ($n -and $n -ne '1') { $extra += '-Count'; $extra += $n }
            }
            else { $extra += '-Role'; $extra += $k.Name }
        }
        'stop' {
            $roles = @('Integrator', 'Kit', 'Coordinator', 'Status', 'Author', 'Builder')
            $r = Select-GeneMenu -Title 'Stop which runners? (Enter = all of them)' -Items $roles -Multi -AllowEmpty -Reader $Reader
            if ($null -eq $r) { return $null }
            if (@($r).Count) { $extra += '-Role'; $extra += , @($r) }
            if (& $yn 'Also close the long sessions (Planner, Adhoc) (-CloseSessions)?') { $extra += '-CloseSessions' }
        }
        'remove' {
            $k = Select-GeneMenu -Title 'Author or builder tabs?' -Items @('Author', 'Builder') -Default 1 -Reader $Reader
            if (-not $k) { return $null }
            $n = ([string](Read-GeneText -Reader $Reader -Prompt 'Tab numbers, comma separated (e.g. 2,3)')).Trim()
            if (-not $n) { return $null }
            $extra += "-$k"; $extra += '-Number'; $extra += , @($n -split '[,\s]+' | Where-Object { $_ })
        }
        'get' {
            $h = ([string](Read-GeneText -Reader $Reader -Prompt 'Take the board over from another host? Its name (Enter = no, just update here)')).Trim()
            if ($h) { $extra += '-FromHost'; $extra += $h }
        }
        'push' {
            $m = ([string](Read-GeneText -Reader $Reader -Prompt 'Message (Enter = default)')).Trim()
            if ($m) { $p.Message = $m }
            if (& $yn 'Hand the board off to another host (-Handoff: stops everything first)?') { $extra += '-Handoff' }
        }
        'update' {
            if (& $yn 'Also update the code (-Code)?') { $extra += '-Code' }
            if (& $yn 'Also restart the long sessions (-RestartSessions)?') { $extra += '-RestartSessions' }
        }
    }
    if ($extra.Count) { $p.Extra = $extra }
    if ($Verb -ne 'rerun' -and (& $yn 'Dry run only (-WhatIf)?')) { $p.WhatIf = $true }
    return $p
}
