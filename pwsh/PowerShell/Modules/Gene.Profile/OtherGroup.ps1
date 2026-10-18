# prof other: a catalog of the profile's other commands, by category. It runs nothing; it says what each command does
# and how to call it. prof other alone browses it; prof other <category> lists one category; prof other <category>
# <command> shows one command. Commands prof already covers say so (Also).

function New-GeneOtherEntry([string]$Name, [string]$What, [string[]]$Usage, [string]$Also = '') {
    [pscustomobject]@{ Name = $Name; What = $What; Usage = $Usage; Also = $Also }
}

$script:ProfOtherCatalog = [ordered]@{
    navigate = [pscustomobject]@{
        Title    = 'Go to a folder (paths come from this machine''s profile)'
        Commands = @(
            New-GeneOtherEntry 'cdevops' 'Go to the repos root (ReposRoot)' @('cdevops')
            New-GeneOtherEntry 'cspeed' 'Go to the speed-merchants repo (TestAuto, CrewChief, DataGen, Mutate)' @('cspeed')
            New-GeneOtherEntry 'ccrew' 'Go to CrewChief inside speed-merchants' @('ccrew')
            New-GeneOtherEntry 'csm' 'Go to the Speedy repo, speedmerchants (SpeedyRepo)' @('csm')
            New-GeneOtherEntry 'caiprof' 'Go to the shared Profisee AI repo (ai-profisee)' @('caiprof')
            New-GeneOtherEntry 'cpower' 'Go to the PowerShell scripts folder (PowershellScriptsDir)' @('cpower')
            New-GeneOtherEntry 'csql' 'Go to the SQL scripts folder (SqlScriptsDir)' @('csql')
            New-GeneOtherEntry 'ccursor' 'Go to the Cursor rules templates repo (CursorRulesDir)' @('ccursor')
        )
    }
    tabs     = [pscustomobject]@{
        Title    = 'Windows Terminal tabs and remote shells'
        Commands = @(
            New-GeneOtherEntry 'addtab' 'Open one new tab in this Windows Terminal window with the title you give, in a folder' @('addtab <name...> [<path>]', 'addtab Author 1        (title "Author 1", current folder)', 'addtab Logs C:\scratch')
            New-GeneOtherEntry 'addnew' 'Open 1 to 50 new tabs with the default title (alias ntab)' @('addnew [<count>] [<path>]', 'addnew 3', 'ntab 2 C:\devops\repos')
            New-GeneOtherEntry 'addLinux' 'SSH into the DigitalOcean Ubuntu droplet (gene@138.68.42.81); -Desktop and -Cockpit also open their tunnels' @('addLinux [<remote command>] [-Desktop] [-Cockpit] [-User <name>] [-HostAddress <ip>] [-KeyFile <path>]', 'addLinux', "addLinux 'sudo apt update'", 'addLinux -Desktop')
        )
    }
    build    = [pscustomobject]@{
        Title    = 'Build, run and package the products (prof build drives these)'
        Commands = @(
            New-GeneOtherEntry 'dpspeed' 'TestAuto: build + publish + run here; -Package makes the install package' @('dpspeed [-Run] [-Update] [-CleanBuild] [-Configuration Debug|Release] [-Package [-Bump|-BumpMinor|-BumpMajor]] [-ClearSecrets] [-UpdateClientId] [-WhatIf]') 'prof build run|publish speed'
            New-GeneOtherEntry 'dpcrewchief' 'CrewChief: build + publish + run here (-Cli for the CLI); -Package makes the install package' @('dpcrewchief [-Cli] [-Run] [-Update] [-CleanBuild] [-Package [-Bump...]] [-SealSecret] [-Unlock] [-WhatIf] [-- <cli args>]') 'prof build run|publish crewchief'
            New-GeneOtherEntry 'dpdatagen' 'DataGen: build + publish + run here; -Package makes the install package' @('dpdatagen [-Cli] [-Run] [-Update] [-CleanBuild] [-Package [-Bump...]] [-WhatIf] [-- <cli args>]') 'prof build run|publish datagen'
            New-GeneOtherEntry 'dpmutate' 'DataGen + Mutation: build + publish + run here; -Package makes the install package' @('dpmutate [-Cli] [-Run] [-Update] [-CleanBuild] [-Package [-Bump...]] [-WhatIf] [-- <cli args>]') 'prof build run|publish mutate'
            New-GeneOtherEntry 'dpall' 'Package all four products in one go (optionally bumping each version)' @('dpall -Package [-Bump|-BumpMinor|-BumpMajor] [-Products speed,crewchief,datagen,mutate] [-Parallel] [-SkipShare] [-WhatIf]') 'prof build publish all'
            New-GeneOtherEntry 'dpv2' 'Speedy: rebuild the local containers; also tests (-Test, -Arch, -Chaos), runs a host (-Run), compose up/down, -Package the server release' @('dpv2 [-Test] [-Arch] [-Chaos] [-Dial] [-Run Coordinator|Agent|Cli|Web] [-ComposeUp] [-ComposeDown] [-CleanBuild] [-LoopStatus] [-Criteria] [-Package [-Bump...] [-AllowDirty]] [-WhatIf]') 'prof build run|publish|more speedy'
            New-GeneOtherEntry 'dpContainers' 'Speedy: rebuild the images and restart the stack on them (-NoBuild restarts on the existing images)' @('dpContainers [-NoBuild] [-WhatIf]') 'prof build containers speedy'
            New-GeneOtherEntry 'Publish-SpeedMerchantsPackage' 'The step dp* -Package ends with: copy the new setup exe(s) to the team share and remove older versions. Rarely typed by hand' @('Publish-SpeedMerchantsPackage -Product <product,...> -BuiltAfter <time>')
        )
    }
    git      = [pscustomobject]@{
        Title    = 'Commit, push and sync'
        Commands = @(
            New-GeneOtherEntry 'gpush' 'Stage everything, commit and push the current branch of the repo you are in' @('gpush [<message>] [-WhatIf]', "gpush 'fix: tidy logging'") 'prof git push'
            New-GeneOtherEntry 'pps' 'Commit and push the PowerShell scripts folder to github.com/genewebb/powershellscripts' @('pps [-Message <text>] [-WhatIf]') 'prof git push PowershellScripts'
            New-GeneOtherEntry 'psql' 'Commit and push the SQL scripts folder to github.com/genewebb/sqlscripts (note: hides the PostgreSQL psql client of the same name)' @('psql [-Message <text>] [-WhatIf]') 'prof git push SqlScripts'
            New-GeneOtherEntry 'pushrules' 'Commit and push ONLY the AI files (.cursor, .vscode, .github, .swarm, .claude) of the repo you are in' @('pushrules [-Message <text>] [-Remote <remote>]') 'prof git push -AIOnly'
            New-GeneOtherEntry 'dpAI' 'Sync AI rules/settings between the template and the current repo: -Local template to repo, -Remote repo to template, -Git template to its remote, -Promote both' @('dpAI (-Local | -Remote | -Git | -Promote) [-Message <text>] [-Force] [-Try] [-WhatIf]', 'dpAI -Local -WhatIf', "dpAI -Promote -Message 'rules: promote updates'") 'prof ai local|remote|git|promote'
        )
    }
    board    = [pscustomobject]@{
        Title    = 'The stream board: agent tabs on the stream host (prof streams drives these)'
        Commands = @(
            New-GeneOtherEntry 'addStreams' 'Open the whole set of stream tabs in this Windows Terminal window: Planner, Integrator, Kit, Coordinator, Status, then authors and builders' @('addStreams [-Repo <repo>] [-Force] [-AnyHost] [-DryRun]') 'prof streams add'
            New-GeneOtherEntry 'addStreamTab' 'Open one more stream tab: any role, or -Author / -Builder runners (-Count for several)' @('addStreamTab -Role <role> [-Count <n>]', 'addStreamTab -Author -Count 2', 'addStreamTab -Builder [-ClearStop]') 'prof streams tab'
            New-GeneOtherEntry 'stopStreams' 'Stop runners cleanly: each finishes its current unit, exits and its tab closes; -CloseSessions also closes the long sessions' @('stopStreams [-Role <name>,...] [-CloseSessions] [-DryRun]') 'prof streams stop'
            New-GeneOtherEntry 'removeStreamTab' 'Stop one or more author or builder tabs by number, cleanly' @('removeStreamTab (-Author | -Builder) -Number <n>[,<n>...] [-DryRun]') 'prof streams remove'
            New-GeneOtherEntry 'rerunStreamTab' 'In a stopped author or builder tab: start its runner again' @('rerunStreamTab') 'prof streams rerun'
            New-GeneOtherEntry 'getStreams' 'Bring this machine up to date (kit + code); -FromHost <old host> takes the board over from another machine' @('getStreams [-NoKit] [-NoCode] [-Yes] [-DryRun]', 'getStreams -FromHost <old host> [-FromRepo <unc>] [-NoHandoff] [-AllowClaims] [-DryRun]') 'prof streams get'
            New-GeneOtherEntry 'pushStreams' 'Send this machine''s changes up (kit via publish, code branch); -Handoff stops everything first, to move the board' @('pushStreams [-Message <text>] [-NoKit] [-NoCode] [-Yes] [-DryRun]', 'pushStreams -Handoff [-Message <text>] [-AllowClaims] [-TimeoutMinutes <n>]') 'prof streams push'
            New-GeneOtherEntry 'updateStreams' 'Rolling update of a RUNNING board: stop runners cleanly, update, start the same layout again' @('updateStreams [-Code] [-RestartSessions] [-TimeoutMinutes <n>] [-Yes] [-DryRun]') 'prof streams update'
        )
    }
    profile  = [pscustomobject]@{
        Title    = 'This PowerShell profile and machine settings'
        Commands = @(
            New-GeneOtherEntry 'sp' 'Is the installed profile the same as the one I edit?' @('sp') 'prof setup show'
            New-GeneOtherEntry 'ep' 'Open the repo copy of the profile for editing' @('ep') 'prof setup edit'
            New-GeneOtherEntry 'rp' 'Reload the profile in this window only' @('rp') 'prof setup reload (installs too)'
            New-GeneOtherEntry 'machinecfg' 'Show this machine''s folder settings' @('machinecfg') 'prof setup config'
        )
    }
    claude   = [pscustomobject]@{
        Title    = 'Claude accounts'
        Commands = @(
            New-GeneOtherEntry 'claude-work' 'Start Claude Code with the work account' @('claude-work [<claude args>]')
            New-GeneOtherEntry 'claude-home' 'Start Claude Code with the home account' @('claude-home [<claude args>]')
            New-GeneOtherEntry 'claude-which' 'Show each Claude account''s config folder and whether it is logged in' @('claude-which')
            New-GeneOtherEntry 'Start-ClaudeAccount' 'What claude-work and claude-home call' @('Start-ClaudeAccount -Account work|home [-ClaudeArgs <args>]')
        )
    }
    tools    = [pscustomobject]@{
        Title    = 'Small tools'
        Commands = @(
            New-GeneOtherEntry 'markitdown' 'Convert a document (PDF, Word, ...) to Markdown; a scanned PDF is retried through OCR' @('markitdown <file> -o <out.md>', 'markitdown C:\tmp\will.pdf -o C:\tmp\will.md')
            New-GeneOtherEntry 'clearSeq' 'Delete Seq log events in a time window (default: last hour of TestAuto.Web here); -ProbeOnly counts without deleting' @('clearSeq [-HoursBack <n>] [-From <time> -To <time>] [-Filter <seq filter>] [-ProbeOnly]', 'clearSeq -HoursBack 2')
            New-GeneOtherEntry 'newguid' 'Print a new GUID' @('newguid')
            New-GeneOtherEntry 'cleannul' 'Delete a stubborn "nul" file Windows created in the current folder' @('cleannul')
            New-GeneOtherEntry 'chocoenv' 'Load Chocolatey''s PowerShell helpers into this window' @('chocoenv')
        )
    }
}

$script:ProfGroups['other'] = [pscustomobject]@{
    Description = "Every other profile command, by category: what it does and how to call it (runs nothing)"
    Verbs       = [ordered]@{}
    Details     = @{}
    Usage       = @{}
    Prefix      = 'Invoke-GeneProfOther'
    NeedMachine = @()
    Menu        = 'Read-GeneOtherMenu'
    TopicParam  = 'Name'
    TopicNames  = { @($script:ProfOtherCatalog.Values | ForEach-Object { $_.Commands.Name }) }
}
foreach ($k in $script:ProfOtherCatalog.Keys) {
    $c = $script:ProfOtherCatalog[$k]
    $script:ProfGroups['other'].Verbs[$k] = $c.Title
    $script:ProfGroups['other'].Details[$k] = @("Commands: $(($c.Commands.Name) -join ', '). prof other $k <command> shows one.")
    $script:ProfGroups['other'].Usage[$k] = "prof other $k [<command>]"
}

function Show-GeneOtherEntry($Entry) {
    Write-Host ''
    Write-Host $Entry.Name -ForegroundColor Cyan
    Write-Host "  $($Entry.What)"
    Write-Host ''
    Write-Host '  How to use:'
    foreach ($u in $Entry.Usage) { Write-Host "    $u" }
    if ($Entry.Also) { Write-Host ''; Write-Host "  Also through prof: $($Entry.Also)" -ForegroundColor DarkCyan }
    # Only point at a help switch the command really has (cleannul or newguid would just run).
    $cmd = Get-Command $Entry.Name -ErrorAction SilentlyContinue
    $hs = if ($cmd -and $cmd.Parameters) { if ($cmd.Parameters.ContainsKey('ShowHelp')) { '-h' } elseif ($cmd.Parameters.ContainsKey('Help')) { '-Help' } }
    if ($hs) { Write-Host "  Full help: $($Entry.Name) $hs" -ForegroundColor DarkGray }
}

function Show-GeneOtherCategory {
    param([Parameter(Mandatory)][string]$Category, [string]$Name)
    $c = $script:ProfOtherCatalog[$Category]
    if ($Name) {
        $e = @($c.Commands | Where-Object { $_.Name -ieq $Name }) | Select-Object -First 1
        if (-not $e) { throw "No command '$Name' under $Category. There: $(($c.Commands.Name) -join ', ')" }
        Show-GeneOtherEntry $e
        return
    }
    Write-Host $c.Title -ForegroundColor Cyan
    $w = ($c.Commands.Name | Measure-Object -Property Length -Maximum).Maximum
    foreach ($e in $c.Commands) {
        Write-Host ("  {0}  {1}" -f $e.Name.PadRight($w), $e.What)
        Write-Host ("  {0}  {1}" -f ''.PadRight($w), $e.Usage[0]) -ForegroundColor DarkGray
    }
}

function Invoke-GeneProfOtherNavigate([string]$Name) { Show-GeneOtherCategory navigate $Name }
function Invoke-GeneProfOtherTabs([string]$Name) { Show-GeneOtherCategory tabs $Name }
function Invoke-GeneProfOtherBuild([string]$Name) { Show-GeneOtherCategory build $Name }
function Invoke-GeneProfOtherGit([string]$Name) { Show-GeneOtherCategory git $Name }
function Invoke-GeneProfOtherBoard([string]$Name) { Show-GeneOtherCategory board $Name }
function Invoke-GeneProfOtherProfile([string]$Name) { Show-GeneOtherCategory profile $Name }
function Invoke-GeneProfOtherClaude([string]$Name) { Show-GeneOtherCategory claude $Name }
function Invoke-GeneProfOtherTools([string]$Name) { Show-GeneOtherCategory tools $Name }

function Read-GeneOtherMenu {
    <# Browse: category, then command, then its description; back to the command list until cancelled. Runs nothing. #>
    param([scriptblock]$Reader)
    $cats = @($script:ProfOtherCatalog.Keys | ForEach-Object { [pscustomobject]@{ Name = $_; Description = $script:ProfOtherCatalog[$_].Title } })
    $cat = Select-GeneMenu -Title 'prof other: which kind of command?' -Items $cats -Reader $Reader
    if (-not $cat) { return $null }
    $c = $script:ProfOtherCatalog[$cat.Name]
    while ($true) {
        $items = @($c.Commands | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Description = $_.What; Entry = $_ } })
        $pick = Select-GeneMenu -Title "$($cat.Name): which command?" -Items $items -Reader $Reader
        if (-not $pick) { return $null }
        Show-GeneOtherEntry $pick.Entry
    }
}
