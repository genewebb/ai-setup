# profile.d\board: the stream board (addStreams, addStreamTab, stopStreams, removeStreamTab, rerunStreamTab, getStreams, pushStreams, updateStreams). Definitions only; loaded by the core profile.

#region Stream sessions (addStreams, addStreamTab, stopStreams, removeStreamTab, rerunStreamTab, getStreams, pushStreams, updateStreams)
# Two kinds of stream tab (owner rulings 2026-10-04 and 2026-10-17):
#   - Planner (and Adhoc): ONE long interactive session per tab, started with the role's /loop, so the owner can work
#     with it. The stream-compact mod (stream-kit\mods\stream-compact) compacts it after a turn once context fill
#     reaches STREAM_COMPACT_PCT. Each tab keeps a marker, .streams\tabs\<tab>.json (its shell's PID), while its
#     session runs: the planner wait, the duplicate check and stopStreams read it.
#   - Integrator, Kit, Coordinator, Status, Author N, Builder N: a stream-kit runner in -Live mode that starts a FRESH
#     'claude --permission-mode bypassPermissions' session only for a unit of work. Integrator, Kit and Coordinator
#     launch only when the runner's script gate finds work, and Status is a PowerShell tick with a Claude unit only for
#     its own inbox (owner 2026-10-17, "Both 1 + 2"): as long /loop sessions they would spend a Claude turn every
#     interval. Each runner is started with -Tab <tab title>, so its state file (.streams\runners\runner-*.json) says
#     which tab it runs in: tab numbers, the duplicate check and removeStreamTab read it.

$global:GeneStreamDisabledHooks = 'gateguard'
# Context fill (percent) at which a long session compacts after a turn.
$global:GeneStreamCompactPct = 35

# Tab title -> stream-kit role. addStreams opens these in this order (Planner always first).
$global:GeneStreamRoles = [ordered]@{
    'Planner'     = 'plan'
    'Integrator'  = 'integrate'
    'Kit'         = 'kit'
    'Coordinator' = 'coordinator'
    'Status'      = 'status'
}
# The starting prompt of each long session, as the role's skill documents it ({repo} is filled in).
$global:GeneStreamLoops = @{
    'Planner'     = '/loop /stream-plan inbox repo: {repo}'
    'Integrator'  = '/loop /stream-integrate repo: {repo}'
    'Kit'         = '/loop 10m /stream-kit inbox repo: {repo}'
    'Coordinator' = '/loop 20m /stream-coordinator repo: {repo}'
    'Status'      = '/loop 10m /stream-status repo: {repo}'
    'Adhoc'       = '/stream-adhoc repo: {repo}'
}
$global:GeneStreamTabRoles = [ordered]@{ 'Author' = 'author'; 'Builder' = 'build' }
# Tabs of GeneStreamRoles that addStreams / addStreamTab start as a gated runner, not a long /loop session
# (owner 2026-10-17). Planner stays a long session: the owner talks to it.
$global:GeneStreamRunnerSessionTabs = @('Integrator', 'Kit', 'Coordinator', 'Status')
# Long interactive sessions that addStreams does NOT open; only addStreamTab -Role opens them (owner 2026-10-11:
# Adhoc carries one owner request from requirement to commit, and runs only when the owner wants it).
$global:GeneStreamOnDemandRoles = [ordered]@{ 'Adhoc' = 'adhoc' }
# Optional per-machine caps (ProfileMachineConfig.md). Blank or missing = no limit: the owner decides how many to run.
$global:GeneStreamCapKeys = @{ 'author' = 'StreamMaxAuthors'; 'build' = 'StreamMaxBuilders' }
# Plain PowerShell tabs addStreams opens after the agents, in the repo, running nothing.
$global:GeneStreamPlainTabs = @('Git', 'Compile')
# How long addStreams waits for the Planner's session to start before opening the other tabs.
$global:GeneStreamPlannerWaitSeconds = 60

function Get-GeneStreamKitPath {
    param([Parameter(Mandatory)][string]$Relative)
    # CLAUDE_CONFIG_DIR, else the machine config's ClaudeHome, else the default.
    $claudeHome = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR }
    elseif ($global:GeneMachineAI -and $global:GeneMachineAI['ClaudeHome']) { $global:GeneMachineAI['ClaudeHome'] }
    else { Join-Path $HOME '.claude' }
    return Join-Path $claudeHome "skills\stream-kit\$Relative"
}
function Get-GeneStreamRunnerPath { return Get-GeneStreamKitPath 'scripts\Start-StreamRunner.ps1' }
function Get-GeneStreamCompactModPath { return Get-GeneStreamKitPath 'mods\stream-compact' }

# A tab title as a file name: each run of non-alphanumerics becomes _ (the runner's -Tab stop file uses the same rule).
function Get-GeneStreamTabToken {
    param([Parameter(Mandatory)][string]$Tab)
    return ($Tab -replace '[^A-Za-z0-9]+', '_').Trim('_')
}

# The script a long-session tab runs, as readable text (for -help and for the tab itself).
# The Claude session id is chosen HERE and passed with --session-id, so the stream cost ledger (Get-StreamCost.ps1) can
# map this transcript to its stream session: .streams\sessions\<uuid>.json names it before claude starts. The stream
# session id is <role>-<first 8 hex of that uuid> and travels in the prompt as 'session: <id>'.
function Get-GeneStreamSessionScript {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab, [switch]$Remote)
    $role = $global:GeneStreamRoles[$Tab]
    if (-not $role) { $role = $global:GeneStreamOnDemandRoles[$Tab] }
    if (-not $role) { throw "No role for tab '$Tab' in GeneStreamRoles or GeneStreamOnDemandRoles" }
    $prompt = $global:GeneStreamLoops[$Tab].Replace('{repo}', $Repo) + ' session: {session}'
    # Remote Control only on -Remote (owner 2026-10-20), named after the stream session.
    $rc = if ($Remote) { "--remote-control `$ss " } else { '' }
    return "`$env:CLAUDE_DISABLED_HOOKS = '$($global:GeneStreamDisabledHooks)'; " +
        "`$env:STREAM_COMPACT_PCT = '$($global:GeneStreamCompactPct)'; " +
        "Set-Location -LiteralPath '$Repo'; " +
        "`$sid = [guid]::NewGuid().ToString(); `$ss = '$role-' + `$sid.Substring(0, 8); " +
        "New-Item -ItemType Directory -Force -Path '$Repo\.streams\sessions' | Out-Null; " +
        "@{ streamSession = `$ss; role = '$role'; tab = '$Tab'; startedAt = (Get-Date).ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content -LiteralPath ('$Repo\.streams\sessions\' + `$sid + '.json'); " +
        "Enter-GeneStreamSession -Repo '$Repo' -Tab '$Tab'; " +
        "try { claude $rc--session-id `$sid --permission-mode bypassPermissions --plugin-dir '$(Get-GeneStreamCompactModPath)' -n '$Tab' ('$prompt'.Replace('{session}', `$ss)) } " +
        "finally { Exit-GeneStreamSession -Repo '$Repo' -Tab '$Tab' }"
}

# The script a runner tab (Author N, Builder N) runs. The finally block runs when the runner exits for any reason,
# Ctrl+C included, so the tab closes after a requested stop and is marked stopped otherwise.
# -Remote adds the runner's -Remote (Remote Control on for each unit) and sets STREAM_REMOTE in the tab, so
# rerunStreamTab starts the runner again the same way.
function Get-GeneStreamRunnerScript {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Role, [Parameter(Mandatory)][string]$Tab, [switch]$Remote)
    return "`$env:CLAUDE_DISABLED_HOOKS = '$($global:GeneStreamDisabledHooks)'; " +
        $(if ($Remote) { "`$env:STREAM_REMOTE = '1'; " } else { '' }) +
        "Set-Location -LiteralPath '$Repo'; " +
        "try { pwsh -NoProfile -File '$(Get-GeneStreamRunnerPath)' -Repo '$Repo' -Role $Role -Live$(if ($Remote) { ' -Remote' }) -Tab '$Tab' } " +
        "finally { Complete-GeneStreamTab -Repo '$Repo' -Tab '$Tab' }"
}

# The script a GeneStreamRoles tab runs: a gated runner for the GeneStreamRunnerSessionTabs, a long session otherwise.
function Get-GeneStreamTabScript {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab, [switch]$Remote)
    if ($Tab -in $global:GeneStreamRunnerSessionTabs) {
        return Get-GeneStreamRunnerScript -Repo $Repo -Role $global:GeneStreamRoles[$Tab] -Tab $Tab -Remote:$Remote
    }
    return Get-GeneStreamSessionScript -Repo $Repo -Tab $Tab -Remote:$Remote
}

# The runner role behind a tab title ('Author 2' -> author, 'Status' -> status), or $null for a long-session tab.
function Get-GeneStreamRunnerRole {
    param([Parameter(Mandatory)][string]$Tab)
    $role = $global:GeneStreamTabRoles[($Tab -split ' ')[0]]
    if ($role) { return $role }
    if ($Tab -in $global:GeneStreamRunnerSessionTabs) { return $global:GeneStreamRoles[$Tab] }
    return $null
}

# One line saying what a GeneStreamRoles tab starts, for the progress output.
function Format-GeneStreamTabStart {
    param([Parameter(Mandatory)][string]$Tab, [switch]$Remote)
    $rc = if ($Remote) { ' (Remote Control on)' } else { '' }
    $role = Get-GeneStreamRunnerRole -Tab $Tab
    if ($role) { return "runner -Role $role -Live$(if ($Remote) { ' -Remote' })" }
    return $global:GeneStreamLoops[$Tab].Replace(' repo: {repo}', '') + $rc
}

# Stream tabs are Windows Terminal tabs, opened in the window the command runs in (owner 2026-10-05: the owner groups
# tabs by choosing which terminal to type addStreams / addStreamTab in; outside Windows Terminal they refuse). Wave 0.14.5 could only add
# panes to the current Wave tab from a script, and WezTerm tabs had no close button, rename or force close. wt.exe opens
# a named, colored tab running 'pwsh -NoExit -EncodedCommand <script>'; the tab's pwsh loads this profile, so its
# script can call the functions below. Windows Terminal cannot list or close tabs from outside, so:
#   - a tab retitles itself from inside ([Console]::Title); CLAUDE_CODE_DISABLE_TERMINAL_TITLE stops Claude Code from
#     overwriting that title;
#   - a tab closes when its own shell exits with 0 (closeOnExit 'automatic', the default); stopStreams/removeStreamTab
#     ask a tab to close by writing its close flag (.streams\tabs\close\<tab>), which the tab's shell watches;
#   - tab numbers come from the runner state files and the stopped-tab markers (.streams\tabs\stopped\<tab>.json).
$global:GeneStreamTabColors = @{
    'Planner' = '#2563EB'; 'Integrator' = '#7C3AED'; 'Kit' = '#475569'; 'Coordinator' = '#0D9488'; 'Status' = '#16A34A'
    'Author' = '#EA580C'; 'Builder' = '#CA8A04'; 'Adhoc' = '#DB2777'; 'Git' = '#334155'; 'Compile' = '#334155'
}

# Opens one tab in the Windows Terminal window this command runs in (wt -w 0: the current window), titled and colored by
# its type (the title's first word). The tab's script first drops the env of the terminal it was launched from (Wave,
# WezTerm; the runner would retitle THAT terminal otherwise), stops Claude Code retitling the tab, and sets the title;
# then it runs -Script, if any. -NoExit keeps the shell afterwards. -Window names another WT window instead (wt -w
# <name>: the window with that name, created on first use), so runner roles get a window of their own.
function New-GeneWtTab {
    param([Parameter(Mandatory)][string]$Directory, [Parameter(Mandatory)][string]$Title, [string]$Script, [string]$Window = '0')
    $prefix = "Get-ChildItem Env: | Where-Object { `$_.Name -like 'WAVETERM*' -or `$_.Name -eq 'WEZTERM_PANE' } | " +
        "ForEach-Object { Remove-Item -LiteralPath `"Env:`$(`$_.Name)`" }; " +
        "`$env:CLAUDE_CODE_DISABLE_TERMINAL_TITLE = '1'; Set-GeneStreamTabTitle '$Title'; "
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($prefix + $Script))
    $wtArgs = @('-w', $Window, 'new-tab', '--title', $Title)
    $color = $global:GeneStreamTabColors[($Title -split ' ')[0]]
    if ($color) { $wtArgs += @('--tabColor', $color) }
    $wtArgs += @('-d', $Directory, (Join-Path $PSHOME 'pwsh.exe'), '-NoExit', '-EncodedCommand', $encoded)
    & (Get-GeneWtPath) @wtArgs
    if ($LASTEXITCODE) { throw "wt.exe new-tab '$Title' failed (exit $LASTEXITCODE)" }
}

# The named Windows Terminal window that Author or Builder runner tabs of a repo open in, e.g. 'speedmerchants-Authors'.
# Not digits only (wt reads that as a window id) and no spaces.
function Get-GeneStreamRunnerWindow {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][ValidateSet('Author', 'Builder')][string]$Type)
    $leaf = (Split-Path -Leaf $Repo) -replace '[^A-Za-z0-9_.-]', '-'
    return "$leaf-${Type}s"
}

# Retitles this shell's own terminal tab (Windows Terminal follows the console title).
function Set-GeneStreamTabTitle {
    param([Parameter(Mandatory)][string]$Title)
    try { [Console]::Title = $Title } catch { }
}

# Per-tab files under <repo>\.streams\tabs: the long-session marker (<tab>.json), the close flag (close\<tab>) and the
# stopped-runner marker (stopped\<tab>.json).
function Get-GeneStreamTabFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab, [ValidateSet('marker', 'close', 'stopped')][string]$Kind = 'marker')
    $token = Get-GeneStreamTabToken $Tab
    switch ($Kind) {
        'marker' { return Join-Path $Repo ".streams\tabs\$token.json" }
        'close' { return Join-Path $Repo ".streams\tabs\close\$token" }
        'stopped' { return Join-Path $Repo ".streams\tabs\stopped\$token.json" }
    }
}

# Asks a tab to close: writes its close flag. The tab's shell exits with 0 when it sees it (Watch-GeneStreamTabClose,
# or at once when its session or runner ends), and Windows Terminal closes the tab.
function Request-GeneStreamTabClose {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab, [string]$By = 'owner')
    $flag = Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind close
    New-Item -ItemType Directory -Path (Split-Path $flag) -Force | Out-Null
    Set-Content -LiteralPath $flag -Value "$By $(Get-Date -Format s) $env:USERNAME"
}

# Exits this shell with 0 (closing its tab) if its close flag is set; returns otherwise.
function Exit-GeneStreamTabIfClosed {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $flag = Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind close
    if (-not (Test-Path -LiteralPath $flag)) { return }
    Remove-Item -LiteralPath $flag -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind stopped) -ErrorAction SilentlyContinue
    [Environment]::Exit(0)
}

# While this tab's shell sits at its prompt, polls its close flag every 2 s (a timer event; PSReadLine runs event
# actions while it waits for input) and exits when it is set.
function Watch-GeneStreamTabClose {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $id = "GeneStreamTabClose"
    Get-EventSubscriber -SourceIdentifier $id -ErrorAction SilentlyContinue | Unregister-Event
    $timer = [Timers.Timer]::new(2000)
    $null = Register-ObjectEvent -InputObject $timer -EventName Elapsed -SourceIdentifier $id -MessageData @{ Repo = $Repo; Tab = $Tab } -Action {
        Exit-GeneStreamTabIfClosed -Repo $Event.MessageData.Repo -Tab $Event.MessageData.Tab
    }
    $timer.Start()
}
function Stop-GeneStreamTabCloseWatch {
    Get-EventSubscriber -SourceIdentifier 'GeneStreamTabClose' -ErrorAction SilentlyContinue | Unregister-Event
}

# Lines of help text showing what a tab runs.
function Format-GeneStreamScriptHelp {
    param([Parameter(Mandatory)][string]$Tab, [Parameter(Mandatory)][string]$Script)
    return @("  [$Tab]") + ($Script -split '; ' | ForEach-Object { "    $_" })
}

# Long-session markers: written by the tab before claude starts, removed when it exits.
function Get-GeneStreamMarkerPath {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    return Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind marker
}
function Enter-GeneStreamSession {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $path = Get-GeneStreamMarkerPath -Repo $Repo -Tab $Tab
    New-Item -ItemType Directory -Path (Split-Path $path) -Force | Out-Null
    Remove-Item -LiteralPath (Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind close) -ErrorAction SilentlyContinue
    [ordered]@{ tab = $Tab; pid = $PID; started = (Get-Date).ToUniversalTime().ToString('o') } |
        ConvertTo-Json | Set-Content -LiteralPath $path -Encoding utf8
}
function Exit-GeneStreamSession {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    Remove-Item -LiteralPath (Get-GeneStreamMarkerPath -Repo $Repo -Tab $Tab) -ErrorAction SilentlyContinue
    Exit-GeneStreamTabIfClosed -Repo $Repo -Tab $Tab
    Write-Host "$Tab session ended. The tab stays open as a shell." -ForegroundColor Yellow
    Set-GeneStreamTabTitle "$Tab (ended)"
    Watch-GeneStreamTabClose -Repo $Repo -Tab $Tab
}

# Long sessions running now: a marker whose tab shell is alive. Claude = the session's claude process, when it runs.
function Get-GeneStreamSessions {
    param([Parameter(Mandatory)][string]$Repo)
    $dir = Join-Path $Repo '.streams\tabs'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter '*.json' -File) {
        try { $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $shell = Get-Process -Id ([int]$m.pid) -ErrorAction SilentlyContinue
        if (-not $shell -or $shell.ProcessName -ne 'pwsh') { continue }
        $claude = Get-CimInstance Win32_Process -Filter "ParentProcessId = $([int]$m.pid) AND Name = 'claude.exe'" -ErrorAction SilentlyContinue |
            Select-Object -First 1
        [pscustomobject]@{ Tab = $m.tab; Pid = [int]$m.pid; ClaudePid = $claude.ProcessId; File = $f.FullName; Written = $f.LastWriteTime }
    }
}

# Author/Builder tabs whose runner exited and whose shell is still open ('<tab> (stopped)'): Tab and Pid.
function Get-GeneStreamStoppedTabs {
    param([Parameter(Mandatory)][string]$Repo)
    $dir = Join-Path $Repo '.streams\tabs\stopped'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter '*.json' -File) {
        try { $m = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        $shell = Get-Process -Id ([int]$m.pid) -ErrorAction SilentlyContinue
        if (-not $shell -or $shell.ProcessName -ne 'pwsh') { Remove-Item -LiteralPath $f.FullName -ErrorAction SilentlyContinue; continue }
        [pscustomobject]@{ Tab = $m.tab; Pid = [int]$m.pid; File = $f.FullName }
    }
}

# Runs in a runner tab after its runner exits. A runner stopped by a STOP file (or with every group closed), or a tab
# asked to close, closes its tab; any other exit (a crash, Ctrl+C, a refused launch) leaves the shell open for a look,
# retitled '<tab> (stopped)', with rerunStreamTab ready and its close flag watched.
function Complete-GeneStreamTab {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    Exit-GeneStreamTabIfClosed -Repo $Repo -Tab $Tab
    $last = Get-GeneStreamRunners -Repo $Repo -IncludeDead | Where-Object { $_.Tab -eq $Tab } |
        Sort-Object { (Get-Item -LiteralPath $_.File).LastWriteTimeUtc } | Select-Object -Last 1
    $status = if ($last) { "$($last.Status)" } else { 'no runner state' }
    if ($status -like 'stopped (STOP file)*' -or $status -like 'stopped (all groups closed)*') {
        Write-Host "$Tab runner $status; closing this tab." -ForegroundColor Green
        Start-Sleep -Seconds 3
        [Environment]::Exit(0)
    }
    Write-Host "$Tab runner exited: $status. The tab stays open; close it, or type rerunStreamTab to start it again." -ForegroundColor Yellow
    Set-GeneStreamTabTitle "$Tab (stopped)"
    $stopped = Get-GeneStreamTabFile -Repo $Repo -Tab $Tab -Kind stopped
    New-Item -ItemType Directory -Path (Split-Path $stopped) -Force | Out-Null
    [ordered]@{ tab = $Tab; pid = $PID; at = (Get-Date).ToUniversalTime().ToString('o'); status = $status } |
        ConvertTo-Json | Set-Content -LiteralPath $stopped -Encoding utf8
    $global:GeneStreamTabRerun = @{ Repo = $Repo; Tab = $Tab }
    Watch-GeneStreamTabClose -Repo $Repo -Tab $Tab
}

# Starts the runner again in a stopped author/builder tab, with exactly the script addStreamTab gave it (hooks env,
# repo, -Tab). Retyping or pasting that script by hand is what broke on 2026-10-04: two pasted lines joined without a
# ';' turned the CLAUDE_DISABLED_HOOKS assignment into an unknown command, so the runner ran with gateguard on.
function rerunStreamTab {
    param([switch]$Remote, [Alias('h', '?')][switch]$Help)
    if ($Help) {
        @(
            'rerunStreamTab [-Remote] [-Help]',
            '',
            'In an author or builder tab whose runner has exited ("<tab> (stopped)"), starts that runner again with the',
            'same script addStreamTab ran: CLAUDE_DISABLED_HOOKS, the repo, -Tab. The console is reset first and the tab',
            'title goes back to "<tab>". Refused when a live runner already records this tab.',
            '  -Remote  Turn Remote Control on for its units. A tab first opened with -Remote keeps it without this.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    $r = $global:GeneStreamTabRerun
    if (-not $r) { Write-Error 'rerunStreamTab: this tab has no stopped runner to start again (run it in a "<tab> (stopped)" tab). Nothing was done.'; return }
    $role = Get-GeneStreamRunnerRole -Tab $r.Tab
    if (-not $role) { Write-Error "rerunStreamTab: '$($r.Tab)' is not a runner tab. Nothing was done."; return }
    $live = @(Get-GeneStreamRunners -Repo $r.Repo -Role $role | Where-Object { $_.Tab -eq $r.Tab })
    if ($live.Count) { Write-Error "rerunStreamTab: '$($r.Tab)' already has a live runner ($($live[0].Runner), pid $($live[0].Pid)). Nothing was done."; return }
    $global:GeneStreamTabRerun = $null
    Stop-GeneStreamTabCloseWatch
    Remove-Item -LiteralPath (Get-GeneStreamTabFile -Repo $r.Repo -Tab $r.Tab -Kind stopped) -ErrorAction SilentlyContinue
    [Console]::Write("$([char]27)[0m$([char]27)[?25h$([char]27)[?1049l$([char]27)[?2004l$([char]27)[?1004l$([char]27)[?1000l$([char]27)[?1002l$([char]27)[?1003l$([char]27)[?1006l$([char]27)[<u$([char]27)[>4m")
    Clear-Host
    Set-GeneStreamTabTitle $r.Tab
    Invoke-Expression (Get-GeneStreamRunnerScript -Repo $r.Repo -Role $role -Tab $r.Tab -Remote:($Remote -or $env:STREAM_REMOTE -eq '1'))
}

# Runner state files under <repo>\.streams\runners, one object each. Alive = the runner's pwsh process still runs (and
# is older than the runner's start stamp, so a reused PID does not count) and the runner has not recorded a stop.
function Get-GeneStreamRunners {
    param([Parameter(Mandatory)][string]$Repo, [string[]]$Role, [switch]$IncludeDead)
    $dir = Join-Path $Repo '.streams\runners'
    if (-not (Test-Path -LiteralPath $dir)) { return }
    foreach ($f in Get-ChildItem -LiteralPath $dir -Filter 'runner-*.json' -File) {
        try { $s = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($Role -and $s.role -notin $Role) { continue }
        $alive = $false
        if ($s.pid -and "$($s.status)" -notlike 'stopped*') {
            $p = Get-Process -Id ([int]$s.pid) -ErrorAction SilentlyContinue
            if ($p -and $p.ProcessName -eq 'pwsh') {
                $started = try { ([datetime]$s.started).ToUniversalTime() } catch { $null }
                $alive = (-not $started) -or ($p.StartTime.ToUniversalTime() -le $started.AddMinutes(2))
            }
        }
        if (-not $alive -and -not $IncludeDead) { continue }
        $tab = if ($s.PSObject.Properties['tab']) { $s.tab } else { $null }
        [pscustomobject]@{
            Runner = $s.runner; Role = $s.role; Tab = $tab; Pid = $s.pid; Alive = $alive
            Status = $s.status; Session = $s.session; Started = $s.started; File = $f.FullName
        }
    }
}

# The stream repo folder: -Repo, else the machine config's SpeedyRepo. Full path, or $null after writing the error.
function Resolve-GeneStreamRepoPath {
    param([string]$Repo, [Parameter(Mandatory)][string]$Caller)
    if (-not $Repo) { $Repo = $global:GeneMachine['SpeedyRepo'] }
    if (-not $Repo) {
        Write-Error "${Caller}: no repo: pass -Repo, or set SpeedyRepo in $global:GeneMachineConfigPath. Nothing was done."
        return $null
    }
    if (-not (Test-Path -LiteralPath $Repo -PathType Container)) {
        Write-Error "${Caller}: repo folder not found: $Repo. Nothing was done."
        return $null
    }
    return (Resolve-Path -LiteralPath $Repo).ProviderPath.TrimEnd('\')
}

# Validates -Repo (default SpeedyRepo) and changes to it. Returns the full repo path, or $null after writing the error.
function Enter-GeneStreamRepo {
    param([string]$Repo, [Parameter(Mandatory)][string]$Caller)
    $full = Resolve-GeneStreamRepoPath -Repo $Repo -Caller $Caller
    if (-not $full) { return $null }
    if (-not (Test-Path -LiteralPath (Join-Path $full '.streams\tasks.json') -PathType Leaf)) {
        Write-Error "${Caller}: $full is not a stream repo (no .streams\tasks.json). Nothing was done."
        return $null
    }
    Set-Location -LiteralPath $full
    return $full
}

# Checks everything a stream tab needs before any tab opens. Returns $true, or $false after writing the error.
# -Need names what the tabs use: runner (Author/Builder) and/or compact (the long sessions' mod).
# STOP / STOP-<role> files (runner roles only): when no runner they would stop is still alive, the stop has finished and
# the file is removed; while one is still finishing its unit, a new runner would exit at once, so it refuses
# (-ClearStop removes the file anyway). -DryRun reports instead of checking Windows Terminal or removing anything.
function Test-GeneStreamPrereqs {
    param([Parameter(Mandatory)][string]$Repo, [string[]]$Roles = @(), [Parameter(Mandatory)][string[]]$Need,
        [Parameter(Mandatory)][string]$Caller, [switch]$ClearStop, [switch]$DryRun)
    if (-not $DryRun) {
        if (-not (Test-GeneWt -Caller $Caller)) { return $false }
        if (-not (Get-Command claude -ErrorAction SilentlyContinue)) {
            Write-Error "${Caller}: claude was not found on PATH. Nothing was opened."; return $false
        }
    }
    $paths = @{ runner = (Get-GeneStreamRunnerPath); compact = (Join-Path (Get-GeneStreamCompactModPath) 'hooks\register.ts') }
    foreach ($n in $Need) {
        if (-not (Test-Path -LiteralPath $paths[$n] -PathType Leaf)) {
            Write-Error "${Caller}: stream kit file not found: $($paths[$n]) (run /machine-config apply). Nothing was opened."; return $false
        }
    }
    if (-not $Roles.Count) { return $true }
    $dir = Join-Path $Repo '.streams\runners'
    $runnerRoles = @(@($global:GeneStreamTabRoles.Values) + @($global:GeneStreamRunnerSessionTabs | ForEach-Object { $global:GeneStreamRoles[$_] }))
    foreach ($name in @(@('STOP') + @($Roles | ForEach-Object { "STOP-$_" }) | Sort-Object -Unique)) {
        $file = Join-Path $dir $name
        if (-not (Test-Path -LiteralPath $file)) { continue }
        $affected = if ($name -eq 'STOP') { $runnerRoles } else { @($name.Substring(5)) }
        $finishing = @(Get-GeneStreamRunners -Repo $Repo -Role $affected)
        if ($finishing.Count -and -not $ClearStop) {
            $who = ($finishing | ForEach-Object { if ($_.Tab) { $_.Tab } else { $_.Runner } }) -join ', '
            Write-Error "${Caller}: $name is stopping runners that are still finishing a unit ($who); a new runner would exit at once. Wait for them, or add -ClearStop to cancel the stop. Nothing was opened."
            return $false
        }
        $why = if ($finishing.Count) { '(-ClearStop)' } else { '(its stop has finished)' }
        if ($DryRun) { Write-Host "  would remove $file $why" -ForegroundColor DarkYellow; continue }
        Remove-Item -LiteralPath $file
        Write-Host "Removed $file $why" -ForegroundColor DarkYellow
    }
    return $true
}

# Numbers in use for '<type> N': live runners started with that tab, plus stopped tabs still open (Complete-GeneStreamTab
# records them; rerunStreamTab may start them again).
function Get-GeneStreamUsedNumbers {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Type)
    $pattern = "^$Type (\d+)$"
    $titles = @(@(Get-GeneStreamRunners -Repo $Repo) | ForEach-Object { $_.Tab }) + @(@(Get-GeneStreamStoppedTabs -Repo $Repo) | ForEach-Object { $_.Tab })
    return @($titles | ForEach-Object { if ("$_" -match $pattern) { [int]$Matches[1] } } | Sort-Object -Unique)
}

# Planner first: waits until the Planner tab's claude process runs (marker written after $Since), up to the limit.
function Wait-GeneStreamPlanner {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][datetime]$Since, [int]$Seconds = $global:GeneStreamPlannerWaitSeconds)
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $up = @(Get-GeneStreamSessions -Repo $Repo | Where-Object { $_.Tab -eq 'Planner' -and $_.ClaudePid -and $_.Written -ge $Since })
        if ($up.Count) { return $up[0] }
        Start-Sleep -Seconds 2
    }
    return $null
}

# Maps tab titles and role names ('Planner', 'plan', 'Author', 'build', ...) to the tab title.
function Resolve-GeneStreamTab {
    param([Parameter(Mandatory)][string]$Name)
    foreach ($k in $global:GeneStreamRoles.Keys) { if ($Name -eq $k -or $Name -eq $global:GeneStreamRoles[$k]) { return $k } }
    foreach ($k in $global:GeneStreamTabRoles.Keys) { if ($Name -eq $k -or $Name -eq $global:GeneStreamTabRoles[$k]) { return $k } }
    foreach ($k in $global:GeneStreamOnDemandRoles.Keys) { if ($Name -eq $k -or $Name -eq $global:GeneStreamOnDemandRoles[$k]) { return $k } }
    return $null
}

# Live sessions or runners already behind a once-per-repo tab, as 'session pid N' / 'runner <id> pid N' strings.
function Get-GeneStreamTabHolders {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Tab)
    $hits = @(Get-GeneStreamSessions -Repo $Repo | Where-Object { $_.Tab -eq $Tab } | ForEach-Object { "session pid $($_.Pid)" })
    $role = Get-GeneStreamRunnerRole -Tab $Tab
    if ($role) { $hits += @(Get-GeneStreamRunners -Repo $Repo -Role $role | ForEach-Object { "runner $($_.Runner) pid $($_.Pid)" }) }
    return $hits
}

# Opens ONE once-per-repo tab (Planner, Integrator, Kit, Coordinator, Status, Adhoc) for addStreamTab -Role: a long
# session, or a gated runner for the GeneStreamRunnerSessionTabs. A live session or runner for that tab refuses the
# open unless -Force.
function Open-GeneStreamSessionTab {
    param([string]$Repo, [Parameter(Mandatory)][string]$Tab, [int]$Count = 1, [switch]$ClearStop, [switch]$Force, [switch]$AnyHost, [switch]$Remote, [switch]$DryRun)
    if ($Count -ne 1) { Write-Error "addStreamTab: $Tab runs once per repo; -Count does not apply to it. Nothing was opened."; return }
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'addStreamTab'
    if (-not $full) { return }
    if (-not (Test-GeneStreamHost -Repo $full -Caller 'addStreamTab' -AnyHost:$AnyHost)) { return }
    $role = Get-GeneStreamRunnerRole -Tab $Tab
    $ok = if ($role) { Test-GeneStreamPrereqs -Repo $full -Roles @($role) -Need @('runner') -Caller 'addStreamTab' -ClearStop:$ClearStop -DryRun:$DryRun }
    else { Test-GeneStreamPrereqs -Repo $full -Need @('compact') -Caller 'addStreamTab' -DryRun:$DryRun }
    if (-not $ok) { return }
    $live = @(Get-GeneStreamTabHolders -Repo $full -Tab $Tab)
    if ($live.Count -and -not $Force) {
        Write-Error "addStreamTab: $Tab already runs ($($live -join ', ')). Close it first, or add -Force. Nothing was opened."
        return
    }
    if ($role -and -not $DryRun) { Remove-Item -LiteralPath (Join-Path $full ".streams\runners\STOP-tab-$(Get-GeneStreamTabToken $Tab)") -ErrorAction SilentlyContinue }
    $script = Get-GeneStreamTabScript -Repo $full -Tab $Tab -Remote:$Remote
    if ($DryRun) {
        Write-Host "DryRun: would open this tab in this Windows Terminal window, in ${full}:" -ForegroundColor Cyan
        Format-GeneStreamScriptHelp -Tab $Tab -Script $script | ForEach-Object { Write-Host $_ }
        return
    }
    New-GeneWtTab -Directory $full -Title $Tab -Script $script
    Write-Host "  $Tab -> $(Format-GeneStreamTabStart -Tab $Tab -Remote:$Remote)" -ForegroundColor DarkCyan
    Write-Host "Opened the $Tab tab in $full." -ForegroundColor Green
}

# How many Author / Builder tabs addStreams opens when -Authors / -Builders is not given: the machine cap
# (StreamMaxAuthors / StreamMaxBuilders) when set, else this.
$global:GeneStreamDefaultRunnerTabs = 5

function Get-GeneStreamDefaultTabCount {
    param([Parameter(Mandatory)][string]$Role)
    $cap = "$($global:GeneMachine[$global:GeneStreamCapKeys[$Role]])".Trim()
    if ($cap -match '^\d+$') { return [int]$cap }
    return $global:GeneStreamDefaultRunnerTabs
}

function addStreams {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [ValidateRange(-1, 32)][int]$Authors = -1,
        [ValidateRange(-1, 32)][int]$Builders = -1,
        [switch]$NoAdhoc,
        [switch]$Remote,
        [switch]$Force,
        [switch]$AnyHost,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )

    # -1 = not given: the machine cap, else GeneStreamDefaultRunnerTabs. Live runners count toward the number.
    if ($Authors -lt 0) { $Authors = Get-GeneStreamDefaultTabCount -Role 'author' }
    if ($Builders -lt 0) { $Builders = Get-GeneStreamDefaultTabCount -Role 'build' }
    $shownRepo = if ($Repo) { $Repo } elseif ($global:GeneMachine['SpeedyRepo']) { $global:GeneMachine['SpeedyRepo'] } else { '<repo>' }
    if ($Help) {
        $lines = @(
            'addStreams [-Repo <repo>] [-Authors <n>] [-Builders <n>] [-NoAdhoc] [-Remote] [-Force] [-AnyHost] [-DryRun] [-Help]',
            '',
            'Adds one named, colored tab per stream agent to the Windows Terminal window you run it in (run it from a WT tab),',
            'in this order:',
            '  Planner (always first), Integrator, Kit, Coordinator, Status,',
            "  Author 1..N (-Authors, now $Authors), Builder 1..N (-Builders, now $Builders), Adhoc (unless -NoAdhoc),",
            'then two plain PowerShell tabs in the repo for your own commands: Git and Compile.',
            "Planner first: it waits until the Planner's claude is running (at most $($global:GeneStreamPlannerWaitSeconds) s) before opening the rest.",
            'Authors and builders are topped up: live runners count, so only the missing ones open (addStreamTab adds more).',
            '',
            "Planner is ONE long interactive session you can work with. It starts the role's /loop, and the stream-compact",
            "mod compacts it after a turn once context fill reaches $($global:GeneStreamCompactPct)% (STREAM_COMPACT_PCT).",
            "$($global:GeneStreamRunnerSessionTabs -join ', ') are stream runners (-Live): a fresh Claude session only when",
            'the runner finds work (Status: a PowerShell tick, a Claude unit only for its own inbox). Idle costs no tokens.',
            "Before opening anything it checks -Repo (folder with .streams\tasks.json) and changes to it.",
            'Each tab runs:'
        )
        foreach ($title in $global:GeneStreamRoles.Keys) {
            $lines += Format-GeneStreamScriptHelp -Tab $title -Script (Get-GeneStreamTabScript -Repo $shownRepo -Tab $title)
        }
        $lines += @(
            '',
            'Enter-/Exit-GeneStreamSession keep .streams\tabs\<tab>.json while the session runs (planner wait, stopStreams).',
            'When claude exits the tab stays open as a shell. A runner tab closes after a STOP; any other exit leaves it',
            'open as "<tab> (stopped)", where rerunStreamTab starts it again.',
            "  [Git], [Compile]  plain PowerShell, started in $shownRepo; nothing else runs.",
            'Each tab is pwsh -NoExit -EncodedCommand <script>; the script also sets CLAUDE_CODE_DISABLE_TERMINAL_TITLE so the tab keeps its name.',
            '',
            'Options:',
            '  -Repo       The stream repo. Default: SpeedyRepo in the machine config.',
            "  -Authors    Author runner tabs to have (0 = none). Default: StreamMaxAuthors, else $($global:GeneStreamDefaultRunnerTabs).",
            "  -Builders   Builder runner tabs to have (0 = none). Default: StreamMaxBuilders, else $($global:GeneStreamDefaultRunnerTabs).",
            '  -NoAdhoc    Do not open the Adhoc tab.',
            '  -Remote     Turn Remote Control on (claude.ai/code, the Claude app) for every session these tabs start.',
            '              Off unless given.',
            '  -Force      Open the tabs even when these sessions already run or tabs with these titles are open.',
            '  -AnyHost    Open even when the board says another machine hosts it (.streams\host.json / MOVED.json).',
            '  -DryRun     Check the repo and print the tabs and commands; open nothing.',
            '  -Help, -h   Show this help and exit.',
            '',
            'See also: addStreamTab, stopStreams, removeStreamTab, rerunStreamTab, getStreams, pushStreams, updateStreams.'
        )
        $lines | ForEach-Object { Write-Host $_ }
        return
    }

    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'addStreams'
    if (-not $full) { return }
    if (-not (Test-GeneStreamHost -Repo $full -Caller 'addStreams' -AnyHost:$AnyHost)) { return }
    $runnerRoles = @($global:GeneStreamRunnerSessionTabs | ForEach-Object { $global:GeneStreamRoles[$_] })
    if ($Authors -gt 0) { $runnerRoles += 'author' }
    if ($Builders -gt 0) { $runnerRoles += 'build' }
    if (-not (Test-GeneStreamPrereqs -Repo $full -Roles $runnerRoles -Need @('compact', 'runner') -Caller 'addStreams' -DryRun:$DryRun)) { return }
    # Author / Builder tabs still to open: the asked number less the live runners of that role.
    $toOpen = [ordered]@{}
    foreach ($pair in @(@('Author', $Authors), @('Builder', $Builders))) {
        $liveN = @(Get-GeneStreamRunners -Repo $full -Role $global:GeneStreamTabRoles[$pair[0]]).Count
        $toOpen[$pair[0]] = [Math]::Max(0, $pair[1] - $liveN)
    }
    # Adhoc is once per repo: a live one is kept, not reopened.
    $adhocLive = @(Get-GeneStreamTabHolders -Repo $full -Tab 'Adhoc')
    if ($adhocLive.Count -and -not $NoAdhoc) { Write-Host "  Adhoc already runs ($($adhocLive -join ', ')); not opened." -ForegroundColor DarkYellow; $NoAdhoc = [switch]::Present }

    # Each of these roles runs once per repo (the integrator lock and the planner guard enforce it), so a live session
    # or runner for one is almost always an old one to close first.
    if (-not $Force) {
        $dupes = @($global:GeneStreamRoles.Keys | ForEach-Object {
                $title = $_
                $hits = @(Get-GeneStreamTabHolders -Repo $full -Tab $title)
                if ($hits.Count) { "$title ($($hits -join ', '))" } })
        if ($dupes.Count) {
            Write-Error "addStreams: already running or open: $($dupes -join '; '). Close them first, or add -Force. Nothing was opened."
            return
        }
    }

    if ($DryRun) {
        Write-Host "DryRun: would open these tabs in this Windows Terminal window, in ${full}:" -ForegroundColor Cyan
        foreach ($title in $global:GeneStreamRoles.Keys) {
            Format-GeneStreamScriptHelp -Tab $title -Script (Get-GeneStreamTabScript -Repo $full -Tab $title -Remote:$Remote) | ForEach-Object { Write-Host $_ }
            if ($title -eq 'Planner') { Write-Host "    (then wait up to $($global:GeneStreamPlannerWaitSeconds) s for the Planner's claude)" -ForegroundColor DarkGray }
        }
        foreach ($type in $toOpen.Keys) {
            if ($toOpen[$type]) { addStreamTab -Role $type -Count $toOpen[$type] -Repo $full -Force:$Force -AnyHost:$AnyHost -Remote:$Remote -DryRun }
            else { Write-Host "  [$type] none to open" }
        }
        if (-not $NoAdhoc) { Open-GeneStreamSessionTab -Repo $full -Tab 'Adhoc' -Force:$Force -AnyHost:$AnyHost -Remote:$Remote -DryRun }
        foreach ($title in $global:GeneStreamPlainTabs) { Write-Host "  [$title] plain PowerShell" }
        return
    }

    $created = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($title in $global:GeneStreamRoles.Keys) {
            $since = Get-Date
            # A leftover per-tab stop file would stop a runner tab at once.
            if (Get-GeneStreamRunnerRole -Tab $title) { Remove-Item -LiteralPath (Join-Path $full ".streams\runners\STOP-tab-$(Get-GeneStreamTabToken $title)") -ErrorAction SilentlyContinue }
            New-GeneWtTab -Directory $full -Title $title -Script (Get-GeneStreamTabScript -Repo $full -Tab $title -Remote:$Remote)
            $created.Add($title)
            Write-Host "  $title -> $(Format-GeneStreamTabStart -Tab $title -Remote:$Remote)" -ForegroundColor DarkCyan
            if ($title -eq 'Planner') {
                $up = Wait-GeneStreamPlanner -Repo $full -Since $since
                if ($up) { Write-Host "  Planner claude is running (pid $($up.ClaudePid)); opening the rest." -ForegroundColor DarkCyan }
                else { Write-Warning "addStreams: the Planner's claude did not start within $($global:GeneStreamPlannerWaitSeconds) s; opening the rest anyway. Check the Planner block." }
            }
        }
        # Authors, builders and Adhoc (owner 2026-10-20). addStreamTab numbers, caps and stop-file checks them; its
        # tabs are not in $created, so a later failure here stops them through their own STOP-tab files instead.
        foreach ($type in $toOpen.Keys) {
            if ($toOpen[$type]) { addStreamTab -Role $type -Count $toOpen[$type] -Repo $full -Force:$Force -AnyHost:$AnyHost -Remote:$Remote }
        }
        if (-not $NoAdhoc) { Open-GeneStreamSessionTab -Repo $full -Tab 'Adhoc' -Force:$Force -AnyHost:$AnyHost -Remote:$Remote }
        # Plain shells for the owner's own git and build commands.
        foreach ($title in $global:GeneStreamPlainTabs) {
            New-GeneWtTab -Directory $full -Title $title
            $created.Add($title)
            Write-Host "  $title -> plain PowerShell" -ForegroundColor DarkCyan
        }
        Write-Host "Streams ready in this window, $full; authors and builders are in their own windows. Add more with addStreamTab." -ForegroundColor Green
    }
    catch {
        foreach ($t in $created) { Request-GeneStreamTabClose -Repo $full -Tab $t -By 'addStreams (failed)' }
        Write-Error "addStreams: $($_.Exception.Message). Asked the $($created.Count) tab(s) already opened to close."
    }
}

function addStreamTab {
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param(
        [Parameter(ParameterSetName = 'Author')][switch]$Author,
        [Parameter(ParameterSetName = 'Builder')][switch]$Builder,
        [Parameter(ParameterSetName = 'Role')]
        [ValidateSet('Planner', 'Integrator', 'Kit', 'Coordinator', 'Status', 'Author', 'Builder', 'Adhoc', 'plan', 'integrate', 'build')]
        [string]$Role,
        [ValidateRange(1, 32)][int]$Count = 1,
        [string]$Repo,
        [switch]$ClearStop,
        [switch]$Force,
        [switch]$AnyHost,
        [switch]$Remote,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )

    $shownRepo = if ($Repo) { $Repo } elseif ($global:GeneMachine['SpeedyRepo']) { $global:GeneMachine['SpeedyRepo'] } else { '<repo>' }
    if ($Help) {
        $lines = @(
            'addStreamTab -Role <role> [-Repo <repo>] [-Count <n>] [-ClearStop] [-Force] [-AnyHost] [-Remote] [-DryRun] [-Help]',
            'addStreamTab (-Author | -Builder) [-Repo <repo>] [-Count <n>] [-ClearStop] [-Force] [-AnyHost] [-Remote] [-DryRun] [-Help]',
            '',
            'Opens one tab for ANY stream role in the Windows Terminal window you run it in:',
            '  -Role Planner | Adhoc                                              one long interactive session, once per repo',
            '  -Role Integrator | Kit | Coordinator | Status                      one gated runner tab, once per repo',
            '                                                                    (refused while that tab''s session or runner runs; -Force opens anyway)',
            '  -Role Author | Builder (same as -Author | -Builder)                runner tabs, -Count of them, in their own window',
            '                                                                    (<repo>-Authors / <repo>-Builders; never this one)',
            'Adhoc is never opened by addStreams: it carries one request you type in its tab from requirement to commit.'
        )
        foreach ($title in @($global:GeneStreamRoles.Keys) + @($global:GeneStreamOnDemandRoles.Keys)) {
            $lines += Format-GeneStreamScriptHelp -Tab $title -Script (Get-GeneStreamTabScript -Repo $shownRepo -Tab $title)
        }
        $lines += @(
            '',
            'Author and Builder: opens -Count new tabs (default 1), one stream runner each.',
            'Tabs are named Author 1, Author 2, ... or Builder 1, Builder 2, ...; each takes the lowest number not used by a',
            'live runner of that tab (from .streams\runners) or by a stopped tab still open (.streams\tabs\stopped).',
            'A permission prompt in a runner''s session retitles its tab "<tab> - NEEDS YOU" and rings the bell.',
            '',
            "Before opening anything it checks -Repo (folder with .streams\tasks.json) and changes to it.",
            'Each tab runs:'
        )
        $lines += Format-GeneStreamScriptHelp -Tab 'Author N' -Script (Get-GeneStreamRunnerScript -Repo $shownRepo -Role 'author' -Tab 'Author N')
        $lines += Format-GeneStreamScriptHelp -Tab 'Builder N' -Script (Get-GeneStreamRunnerScript -Repo $shownRepo -Role 'build' -Tab 'Builder N')
        $lines += @(
            '',
            'The runner starts a FRESH Claude session for each ticket or build, so each starts with a clean context:',
            '  claude [--remote-control <session>] --permission-mode bypassPermissions -n <session> --plugin-dir <stream-unit mod>',
            '         --append-system-prompt-file <unit rules> "/stream-author once repo: <repo>"  (or /stream-build)',
            'shown in the tab (and in claude.ai/code under <session> with -Remote); it inherits CLAUDE_DISABLED_HOOKS from the tab.',
            'With nothing to take it sleeps 30 minutes.',
            'When the runner is stopped (removeStreamTab, stopStreams) the tab closes; any other exit leaves it as "<tab> (stopped)"; type rerunStreamTab there to start it again.',
            '',
            "Optional caps on this machine ($global:GeneMachineConfigPath; you choose the numbers):"
        )
        foreach ($role in $global:GeneStreamTabRoles.Values) {
            $key = $global:GeneStreamCapKeys[$role]; $v = $global:GeneMachine[$key]
            $lines += "  $key = $(if ($v) { $v } else { '(blank: no limit)' })"
        }
        $lines += @(
            '',
            'Options:',
            '  -Role               The role to open: Planner, Integrator, Kit, Coordinator, Status, Author, Builder or Adhoc',
            '                      (role names plan, integrate, build work too).',
            '  -Author | -Builder  The same as -Role Author / -Role Builder. One of -Role, -Author, -Builder is required.',
            '  -Count              Number of Author or Builder tabs to open (default 1). Long-session roles open one.',
            '  -Repo               The stream repo. Default: SpeedyRepo in the machine config.',
            '  -ClearStop          Remove STOP / STOP-<role> files even while runners are still finishing a stop.',
            '                      A stop file whose runners have all exited is removed without it.',
            '  -Force              Open past the machine cap, or a long-session role whose session already runs.',
            '  -AnyHost            Open even when the board says another machine hosts it (.streams\host.json / MOVED.json).',
            '  -Remote             Turn Remote Control on (claude.ai/code, the Claude app) for the sessions this opens.',
            '                      Off unless given.',
            '  -DryRun             Check the repo and print the tabs and commands; open nothing.',
            '  -Help, -h           Show this help and exit.',
            '',
            'Examples:',
            '  addStreamTab -Author',
            '  addStreamTab -Builder -Count 2',
            '  addStreamTab -Role Adhoc',
            '  addStreamTab -Role Coordinator -Repo d:\devops\repos\speedmerchants'
        )
        $lines | ForEach-Object { Write-Host $_ }
        return
    }

    if ($Role) {
        $resolved = Resolve-GeneStreamTab -Name $Role
        if ($resolved -eq 'Author') { $Author = [switch]::Present }
        elseif ($resolved -eq 'Builder') { $Builder = [switch]::Present }
        else { Open-GeneStreamSessionTab -Repo $Repo -Tab $resolved -Count $Count -ClearStop:$ClearStop -Force:$Force -AnyHost:$AnyHost -Remote:$Remote -DryRun:$DryRun; return }
    }
    if (-not ($Author -or $Builder)) {
        Write-Error 'addStreamTab: a role is required: -Role <role>, -Author or -Builder (see addStreamTab -Help). Nothing was opened.'
        return
    }
    if (-not $DryRun -and -not (Test-GeneWt -Caller 'addStreamTab')) { return }
    $type = if ($Author) { 'Author' } else { 'Builder' }
    $role = $global:GeneStreamTabRoles[$type]

    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'addStreamTab'
    if (-not $full) { return }
    if (-not (Test-GeneStreamHost -Repo $full -Caller 'addStreamTab' -AnyHost:$AnyHost)) { return }
    if (-not (Test-GeneStreamPrereqs -Repo $full -Roles @($role) -Need @('runner') -Caller 'addStreamTab' -ClearStop:$ClearStop -DryRun:$DryRun)) { return }

    # Optional cap: live runners of this role plus the new ones.
    $capKey = $global:GeneStreamCapKeys[$role]
    $cap = "$($global:GeneMachine[$capKey])".Trim()
    $live = @(Get-GeneStreamRunners -Repo $full -Role $role)
    if ($cap) {
        if ($cap -notmatch '^\d+$') { Write-Error "addStreamTab: $capKey = '$cap' in $global:GeneMachineConfigPath is not a whole number. Nothing was opened."; return }
        if ($live.Count + $Count -gt [int]$cap -and -not $Force) {
            Write-Error "addStreamTab: $($live.Count) $role runner(s) live + $Count new is over $capKey = $cap. Add -Force, or raise the cap. Nothing was opened."
            return
        }
    }

    $used = Get-GeneStreamUsedNumbers -Repo $full -Type $type
    $numbers = [System.Collections.Generic.List[int]]::new()
    for ($n = 1; $numbers.Count -lt $Count; $n++) { if ($used -notcontains $n) { $numbers.Add($n) } }

    if ($DryRun) {
        Write-Host "DryRun: $($live.Count) $role runner(s) live; would open in the Windows Terminal window '$(Get-GeneStreamRunnerWindow -Repo $full -Type $type)': $(($numbers | ForEach-Object { "$type $_" }) -join ', ')" -ForegroundColor Cyan
        foreach ($n in $numbers) { Format-GeneStreamScriptHelp -Tab "$type $n" -Script (Get-GeneStreamRunnerScript -Repo $full -Role $role -Tab "$type $n" -Remote:$Remote) | ForEach-Object { Write-Host $_ } }
        return
    }

    $runners = Join-Path $full '.streams\runners'
    # Authors and builders never share a terminal (owner 2026-10-21): each type has its own named WT window per repo.
    $window = Get-GeneStreamRunnerWindow -Repo $full -Type $type
    $created = [System.Collections.Generic.List[string]]::new()
    try {
        foreach ($n in $numbers) {
            $tab = "$type $n"
            # A leftover stop file for this tab would stop the new runner at once.
            Remove-Item -LiteralPath (Join-Path $runners "STOP-tab-$(Get-GeneStreamTabToken $tab)") -ErrorAction SilentlyContinue
            New-GeneWtTab -Directory $full -Title $tab -Script (Get-GeneStreamRunnerScript -Repo $full -Role $role -Tab $tab -Remote:$Remote) -Window $window
            $created.Add($tab)
            Write-Host "  $tab -> runner -Role $role -Live$(if ($Remote) { ' -Remote' })" -ForegroundColor DarkCyan
        }
        Write-Host "Opened $($created.Count) $type tab(s) in $full, in the Windows Terminal window '$window'." -ForegroundColor Green
    }
    catch {
        foreach ($t in $created) { Set-Content -LiteralPath (Join-Path $runners "STOP-tab-$(Get-GeneStreamTabToken $t)") -Value 'addStreamTab (failed)' }
        Write-Error "addStreamTab: $($_.Exception.Message). Stopped the $($created.Count) tab(s) already opened (STOP-tab files)."
    }
}

function stopStreams {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [string[]]$Role,
        [switch]$CloseSessions,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'stopStreams [-Repo <repo>] [-Role <name>[,<name>...]] [-CloseSessions] [-DryRun] [-Help]',
            '',
            'Runners (Integrator, Kit, Coordinator, Status, authors, builders): stop cleanly. Each finishes the unit it is',
            'running (never killed mid-unit), then exits, and its tab closes. Writes .streams\runners\STOP (no -Role) or',
            'STOP-<role>. Returns at once; the next addStreams / addStreamTab removes the stop file once those runners have exited.',
            '',
            'Planner, Adhoc (long sessions): a STOP file cannot reach them. Without',
            '-CloseSessions it lists the live ones so you can end each at a quiet moment (Esc, then /exit). With -CloseSessions',
            'it closes their tabs now, ending any turn in progress.',
            '',
            'Options:',
            '  -Repo           The stream repo. Default: SpeedyRepo in the machine config.',
            '  -Role           Tab names or roles: Planner|plan, Integrator|integrate, Kit|kit, Coordinator|coordinator,',
            '                  Status|status, Author|author, Builder|build, Adhoc|adhoc. Omit for all.',
            '  -CloseSessions  Close the long-session tabs now.',
            '  -DryRun         Show what would stop or close; change nothing.',
            '  -Help           Show this help and exit.',
            '',
            'To stop one author or builder tab, use removeStreamTab.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'stopStreams'
    if (-not $full) { return }
    $tabs = @()
    foreach ($r in $Role) {
        $resolved = Resolve-GeneStreamTab -Name $r
        if (-not $resolved) { Write-Error "stopStreams: unknown role '$r' (see stopStreams -Help). Nothing was done."; return }
        $tabs += $resolved
    }
    $all = -not $tabs.Count
    $runnerTypes = @(@($global:GeneStreamTabRoles.Keys) + @($global:GeneStreamRunnerSessionTabs) | Where-Object { $all -or $_ -in $tabs })
    $sessionTabs = @(@($global:GeneStreamRoles.Keys) + @($global:GeneStreamOnDemandRoles.Keys) |
            Where-Object { $_ -notin $global:GeneStreamRunnerSessionTabs -and ($all -or $_ -in $tabs) })

    # Runners: STOP files.
    if ($runnerTypes.Count) {
        $roles = @($runnerTypes | ForEach-Object { Get-GeneStreamRunnerRole -Tab $_ })
        $files = if ($all) { @('STOP') } else { @($roles | ForEach-Object { "STOP-$_" }) }
        $live = @(Get-GeneStreamRunners -Repo $full -Role $roles)
        $verb = if ($DryRun) { 'would stop' } else { 'stopping' }
        foreach ($r in $live) { Write-Host "  $verb $(if ($r.Tab) { $r.Tab } else { $r.Role }) ($($r.Runner)): $($r.Status)" -ForegroundColor DarkCyan }
        if (-not $live.Count) { Write-Host "  no live $($roles -join '/') runner" -ForegroundColor DarkGray }
        if ($DryRun) { Write-Host "DryRun: would write $($files -join ', ') in $(Join-Path $full '.streams\runners')." -ForegroundColor Cyan }
        elseif ($live.Count) {
            $dir = Join-Path $full '.streams\runners'
            foreach ($f in $files) { Set-Content -LiteralPath (Join-Path $dir $f) -Value "stopStreams $(Get-Date -Format s) $env:USERNAME" }
            Write-Host "Wrote $($files -join ', '). Each runner exits after its current unit; its tab then closes." -ForegroundColor Green
        }
    }

    # Long sessions: list, or close with -CloseSessions.
    if ($sessionTabs.Count) {
        $sessions = @(Get-GeneStreamSessions -Repo $full | Where-Object { $_.Tab -in $sessionTabs })
        if (-not $sessions.Count) { Write-Host "  no live long session for $($sessionTabs -join ', ')" -ForegroundColor DarkGray }
        foreach ($s in $sessions) {
            if (-not $CloseSessions) { Write-Host "  $($s.Tab): long session running (shell pid $($s.Pid)). End it with Esc then /exit, or rerun with -CloseSessions." -ForegroundColor Yellow; continue }
            if ($DryRun) { Write-Host "DryRun: would close the $($s.Tab) tab (claude pid $($s.ClaudePid), shell pid $($s.Pid))." -ForegroundColor Cyan; continue }
            # The close flag makes the tab's shell exit with 0 once claude ends (Exit-GeneStreamSession), so the tab closes.
            Request-GeneStreamTabClose -Repo $full -Tab $s.Tab -By 'stopStreams -CloseSessions'
            if ($s.ClaudePid) { $null = & taskkill.exe /PID $s.ClaudePid /T /F 2>&1 } else { Stop-Process -Id $s.Pid -Confirm:$false }
            Write-Host "  Closed the $($s.Tab) tab." -ForegroundColor Green
        }
    }
}

function removeStreamTab {
    [CmdletBinding(DefaultParameterSetName = 'None')]
    param(
        [Parameter(ParameterSetName = 'Author')][switch]$Author,
        [Parameter(ParameterSetName = 'Builder')][switch]$Builder,
        [int[]]$Number,
        [string]$Repo,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'removeStreamTab (-Author | -Builder) -Number <n>[,<n>...] [-Repo <repo>] [-DryRun] [-Help]',
            '(-Repo defaults to SpeedyRepo in the machine config.)',
            '',
            'Stops one author or builder tab cleanly: writes .streams\runners\STOP-tab-<Author_N> so only that runner',
            'finishes its current unit and exits; its tab then closes. Returns at once.',
            'A tab with that title whose runner has already exited is closed now.',
            '',
            'Examples:',
            '  removeStreamTab -Author -Number 2 -Repo d:\devops\repos\speedmerchants',
            '  removeStreamTab -Builder -Number 3,4 -Repo d:\devops\repos\speedmerchants'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    if (-not ($Author -or $Builder)) { Write-Error 'removeStreamTab: a type is required: -Author or -Builder. Nothing was done.'; return }
    if (-not $Number) { Write-Error 'removeStreamTab: -Number is required, e.g. -Number 2. Nothing was done.'; return }
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'removeStreamTab'
    if (-not $full) { return }
    $type = if ($Author) { 'Author' } else { 'Builder' }
    $role = $global:GeneStreamTabRoles[$type]
    $live = @(Get-GeneStreamRunners -Repo $full -Role $role)
    $stoppedTabs = @(Get-GeneStreamStoppedTabs -Repo $full)
    $dir = Join-Path $full '.streams\runners'
    foreach ($n in $Number) {
        $tab = "$type $n"
        $runner = @($live | Where-Object { $_.Tab -eq $tab }) | Select-Object -First 1
        if ($runner) {
            $stop = Join-Path $dir "STOP-tab-$(Get-GeneStreamTabToken $tab)"
            if ($DryRun) { Write-Host "DryRun: would write $stop ($tab, $($runner.Status))" -ForegroundColor Cyan; continue }
            Set-Content -LiteralPath $stop -Value "removeStreamTab $(Get-Date -Format s) $env:USERNAME"
            Write-Host "  $tab ($($runner.Runner)) stops after its current unit ($($runner.Status)); its tab then closes." -ForegroundColor Green
            continue
        }
        $open = @($stoppedTabs | Where-Object { $_.Tab -eq $tab })
        if (-not $open.Count) { Write-Warning "removeStreamTab: no live runner and no stopped tab for '$tab'. A tab this command cannot see can be closed with its X."; continue }
        if ($DryRun) { Write-Host "DryRun: would close the stopped tab '$tab' (shell pid $($open[0].Pid))." -ForegroundColor Cyan; continue }
        Request-GeneStreamTabClose -Repo $full -Tab $tab -By 'removeStreamTab'
        Write-Host "  '$tab (stopped)' closes within a few seconds; its runner was not running." -ForegroundColor Green
    }
}

# --- Sync and host moves (getStreams, pushStreams, updateStreams) --------------------------------------------------
# Owner 2026-10-17. Every location comes from the machine config: the stream repo is SpeedyRepo, the AI setup clone is
# AIWorkRoot, the owner's push right is the git policy row's 'Owner push' column (blank = Push), read through
# lib\MachineConfig.psm1 Get-AIGitPolicy. git-guard reads only Push, so a row can give the owner push while Claude
# sessions keep Push = no. Another machine's paths come from ITS machine config, read over the admin share.
# Board markers, all in <repo>\.streams (the board is not in git, so they travel with it):
#   host.json     the machine that runs this board (written by getStreams -FromHost). No host.json = no guard.
#   MOVED.json    on a board that was taken over: where it went. Every command that starts a stream tab refuses here.
#   handoff.json  written by pushStreams -Handoff once the old host is stopped, quiet and pushed: what ran, to reopen.

$global:GeneStreamNightlyPrefix = 'Speedy Tier2 nightly'
# Services 'docker compose ps' must show running on a stream host (migrate/backup-setup exit; tools are on demand).
$global:GeneStreamComposeServices = @('coordinator', 'fleet', 'throttle', 'warehouse', 'web')
# Seconds between checks while waiting for runners to finish their unit.
$global:GeneStreamWaitPollSeconds = 30

# Every runner role a tab can run: authors, builders and the once-per-repo runner tabs.
function Get-GeneStreamRunnerRoles {
    return @(@($global:GeneStreamTabRoles.Values) + @($global:GeneStreamRunnerSessionTabs | ForEach-Object { $global:GeneStreamRoles[$_] }))
}

function Get-GeneStreamBoardFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][ValidateSet('host', 'moved', 'handoff')][string]$Kind)
    $name = @{ host = 'host.json'; moved = 'MOVED.json'; handoff = 'handoff.json' }[$Kind]
    return Join-Path $Repo ".streams\$name"
}

# A board marker as an object; $null when absent. An unreadable marker still counts (host/to = '(unreadable)').
function Read-GeneStreamBoardFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][ValidateSet('host', 'moved', 'handoff')][string]$Kind)
    $path = Get-GeneStreamBoardFile -Repo $Repo -Kind $Kind
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { return [pscustomobject]@{ host = '(unreadable)'; to = '(unreadable)'; at = ''; file = $path } }
}

function Write-GeneStreamBoardFile {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][ValidateSet('host', 'moved', 'handoff')][string]$Kind,
        [Parameter(Mandatory)][System.Collections.IDictionary]$Data)
    $Data | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Get-GeneStreamBoardFile -Repo $Repo -Kind $Kind) -Encoding utf8
}

# $true when this machine may start the board's tabs. A board that moved away (MOVED.json) or names another host
# (host.json) refuses, unless -AnyHost: two hosts on one board claim and build the same tasks twice.
function Test-GeneStreamHost {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Caller, [switch]$AnyHost)
    $moved = Read-GeneStreamBoardFile -Repo $Repo -Kind moved
    $mark = Read-GeneStreamBoardFile -Repo $Repo -Kind host
    $why = if ($moved) { "this board moved to $($moved.to) on $($moved.at) ($(Get-GeneStreamBoardFile -Repo $Repo -Kind moved))" }
    elseif ($mark -and $mark.host -ne $env:COMPUTERNAME) { "this board's host is $($mark.host) ($(Get-GeneStreamBoardFile -Repo $Repo -Kind host))" }
    if (-not $why) { return $true }
    if ($AnyHost) { Write-Warning "${Caller}: $why; going on here anyway (-AnyHost)."; return $true }
    Write-Error "${Caller}: $why. Run the stream there, or add -AnyHost. Nothing was opened."
    return $false
}

# The AI setup clone (AIWorkRoot), or $null after writing the error.
function Get-GeneAIWorkRoot {
    param([Parameter(Mandatory)][string]$Caller)
    $root = if ($global:GeneMachineAI) { $global:GeneMachineAI['AIWorkRoot'] }
    if (-not $root -or -not (Test-Path -LiteralPath (Join-Path $root '.git'))) {
        Write-Error "${Caller}: AIWorkRoot ('$root') in $global:GeneMachineConfigPath is not the AI setup clone. Nothing was done."
        return $null
    }
    return $root.TrimEnd('\')
}

# git against -Dir; safe.directory=* so a clone on another machine's admin share reads too. Output lines; throws on failure.
function Invoke-GeneStreamGit {
    param([Parameter(Mandatory)][string]$Dir, [Parameter(Mandatory)][string[]]$GitArgs)
    $out = @(& git -c safe.directory=* -C $Dir @GitArgs 2>&1 | ForEach-Object { "$_" })
    if ($LASTEXITCODE) { throw "git -C $Dir $($GitArgs -join ' ') failed: $($out -join ' ')" }
    return $out
}

# Branch, upstream, uncommitted files and commits ahead of / behind the upstream (as last fetched; -Fetch fetches first).
function Get-GeneCloneState {
    param([Parameter(Mandatory)][string]$Dir, [switch]$Fetch)
    $branch = @(Invoke-GeneStreamGit -Dir $Dir -GitArgs @('rev-parse', '--abbrev-ref', 'HEAD'))[0]
    $files = @(Invoke-GeneStreamGit -Dir $Dir -GitArgs @('status', '--porcelain'))
    $upstream = @(& git -c safe.directory=* -C $Dir rev-parse --abbrev-ref '@{u}' 2>$null)
    $hasUpstream = ($LASTEXITCODE -eq 0) -and $upstream.Count
    $behind = 0; $ahead = 0
    if ($hasUpstream) {
        if ($Fetch) { Invoke-GeneStreamGit -Dir $Dir -GitArgs @('fetch', '--quiet') | Out-Null }
        $counts = @(Invoke-GeneStreamGit -Dir $Dir -GitArgs @('rev-list', '--left-right', '--count', '@{u}...HEAD'))[0] -split '\s+'
        $behind = [int]$counts[0]; $ahead = [int]$counts[1]
    }
    [pscustomobject]@{
        Dir = $Dir; Branch = $branch; Upstream = $(if ($hasUpstream) { "$($upstream[0])" } else { $null })
        Files = $files.Count; Ahead = $ahead; Behind = $behind
    }
}

# This machine's git policy for -Repo (Get-AIGitPolicy: Commit, Push, Worktrees, OwnerPush).
function Get-GeneRepoGitPolicy {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$AIWorkRoot)
    Import-Module (Join-Path $AIWorkRoot 'lib\MachineConfig.psm1') -Force -Global
    return Get-AIGitPolicy -Path $Repo -Profile (Get-AIMachineProfile)
}

# Another machine's value for a first-table path key, read from ITS machine config over the admin share and returned
# as a UNC path (C:\x -> \\HOST\C$\x). Throws when the file, the row or a plain drive path is missing.
function Get-GeneRemoteMachinePath {
    param([Parameter(Mandatory)][string]$ComputerName, [Parameter(Mandatory)][string]$Key)
    $cfg = "\\$ComputerName\" + ($global:GeneMachineConfigPath -replace '^([A-Za-z]):', '$1$')
    if (-not (Test-Path -LiteralPath $cfg)) { throw "cannot read $cfg (admin share on $ComputerName)" }
    foreach ($line in Get-Content -LiteralPath $cfg) {
        if ($line -notmatch "^\s*\|\s*``?$Key``?\s*\|([^|]*)\|") { continue }
        $value = $Matches[1].Trim().Trim('`').Trim()
        if (-not $value) { throw "$Key is blank in $cfg" }
        if ($value -notmatch '^([A-Za-z]):\\?(.*)$') { throw "$Key in $cfg is not a plain drive path ('$value'); pass the path yourself" }
        return "\\$ComputerName\$($Matches[1])`$\$($Matches[2])".TrimEnd('\')
    }
    throw "no $Key row in $cfg"
}

# Why a board is not quiet, as Copy-StreamToHost.ps1 -Phase Final judges it: claims, building tasks (one parked on
# unfinished dependencies is carried as is), the integrator lock, uncommitted product code. Built tasks travel: their
# patches are on the board and the new host's integrator applies them.
function Get-GeneStreamBoardNoise {
    param([Parameter(Mandatory)][string]$Repo)
    $doc = Get-Content -LiteralPath (Join-Path $Repo '.streams\tasks.json') -Raw | ConvertFrom-Json
    $state = @{}; foreach ($t in $doc.tasks) { $state[$t.id] = $t.state }
    $claims = @($doc.tasks | Where-Object { $_.claim })
    $flight = @($doc.tasks | Where-Object {
            $_.state -eq 'building' -and -not (-not $_.claim -and @($_.dependsOn | Where-Object { $state[$_] -notin 'integrated', 'done' }).Count) })
    [pscustomobject]@{
        Claims = @($claims | ForEach-Object { $_.id })
        Flight = @($flight | ForEach-Object { $_.id })
        Lock   = Test-Path -LiteralPath (Join-Path $Repo '.streams\integrator.lock')
        Dirty  = @(Invoke-GeneStreamGit -Dir $Repo -GitArgs @('status', '--porcelain'))
    }
}

# What runs on a board now, to reopen after a stop: author and builder counts, the once-per-repo runner tabs that are
# live, and the long sessions (Planner, Adhoc).
function Get-GeneStreamLiveLayout {
    param([Parameter(Mandatory)][string]$Repo)
    $live = @(Get-GeneStreamRunners -Repo $Repo -Role (Get-GeneStreamRunnerRoles))
    [pscustomobject]@{
        Authors  = @($live | Where-Object { $_.Role -eq 'author' }).Count
        Builders = @($live | Where-Object { $_.Role -eq 'build' }).Count
        Tabs     = @($global:GeneStreamRunnerSessionTabs | Where-Object { $role = $global:GeneStreamRoles[$_]; @($live | Where-Object { $_.Role -eq $role }).Count })
        Sessions = @(Get-GeneStreamSessions -Repo $Repo | ForEach-Object { $_.Tab })
    }
}

function Format-GeneStreamLayout {
    param([Parameter(Mandatory)][object]$Layout)
    $parts = @($Layout.Tabs) + @("$($Layout.Authors) author(s)", "$($Layout.Builders) builder(s)")
    if (@($Layout.Sessions).Count) { $parts += "long: $(@($Layout.Sessions) -join ', ')" }
    return $parts -join ', '
}

# Waits until no runner of -Role is alive. $true when they all exited, $false at the timeout (stops stay in place).
function Wait-GeneStreamRunnersExit {
    param([Parameter(Mandatory)][string]$Repo, [string[]]$Role = (Get-GeneStreamRunnerRoles), [int]$TimeoutMinutes = 60)
    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
    $last = ''
    while ($true) {
        $live = @(Get-GeneStreamRunners -Repo $Repo -Role $Role)
        if (-not $live.Count) { return $true }
        $line = ($live | ForEach-Object { if ($_.Tab) { $_.Tab } else { $_.Runner } }) -join ', '
        if ($line -ne $last) {
            Write-Host "  $(Get-Date -Format HH:mm:ss) waiting for $($live.Count) runner(s) to finish their unit: $line" -ForegroundColor DarkGray
            $last = $line
        }
        if ((Get-Date) -ge $deadline) { return $false }
        Start-Sleep -Seconds $global:GeneStreamWaitPollSeconds
    }
}

# Reopens a layout recorded by Get-GeneStreamLiveLayout (runner tabs and counts; long sessions are the caller's).
function Open-GeneStreamLayout {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][object]$Layout, [switch]$AnyHost)
    foreach ($t in $Layout.Tabs) { addStreamTab -Role $t -Repo $Repo -AnyHost:$AnyHost }
    if ($Layout.Authors) { addStreamTab -Author -Count $Layout.Authors -Repo $Repo -AnyHost:$AnyHost }
    if ($Layout.Builders) { addStreamTab -Builder -Count $Layout.Builders -Repo $Repo -AnyHost:$AnyHost }
}

# After a kit install: what picks the change up by itself and what needs a restart.
function Show-GeneStreamRestartNeeds {
    param([string]$Repo)
    if (-not $Repo -or -not (Test-Path -LiteralPath (Join-Path $Repo '.streams\tasks.json'))) { return }
    $layout = Get-GeneStreamLiveLayout -Repo $Repo
    $runners = $layout.Authors + $layout.Builders + @($layout.Tabs).Count
    if ($runners) { Write-Host "  $runners runner(s) live: each new unit reads the installed skills; a changed runner script takes updateStreams." -ForegroundColor DarkCyan }
    foreach ($s in $layout.Sessions) { Write-Host "  ${s}: long session, still on the old setup until restarted (updateStreams -RestartSessions restarts the Planner)." -ForegroundColor Yellow }
}

# Kit half of getStreams: refuses over unpublished AI setup changes (offers to publish them first), then install.ps1.
function Invoke-GeneStreamKitGet {
    param([Parameter(Mandatory)][string]$Caller, [switch]$Yes, [switch]$DryRun)
    $ai = Get-GeneAIWorkRoot -Caller $Caller
    if (-not $ai) { return $false }
    $st = Get-GeneCloneState -Dir $ai
    if ($st.Files -or $st.Ahead) {
        $what = "$ai has unpublished changes ($($st.Files) file(s), $($st.Ahead) commit(s)), and install.ps1 pulls first"
        if ($DryRun) { Write-Host "Kit: DryRun: $what; getStreams would offer to publish them first." -ForegroundColor DarkYellow }
        elseif ([Console]::IsInputRedirected) { Write-Error "${Caller}: $what. Run pushStreams -NoCode first. Nothing was installed."; return $false }
        else {
            Write-Host "Kit: $what." -ForegroundColor Yellow
            $answer = Read-Host 'Publish them now (pushStreams -NoCode)? [y/N]'
            if ($answer -notmatch '^(y|yes)$') { Write-Error "${Caller}: stopped; publish with pushStreams -NoCode, or use -NoKit. Nothing was installed."; return $false }
            if (-not (Invoke-GeneStreamPush -Caller $Caller -NoCode)) { return $false }
        }
    }
    # @(...) around the if: a one-element array would come back as a bare string, and splatting a string passes its characters.
    $installArgs = @(if ($DryRun) { '-NoPull', '-WhatIf' } elseif ($Yes) { '-Yes' })
    Write-Host "Kit: pwsh -NoProfile -File $ai\install.ps1 $($installArgs -join ' ')" -ForegroundColor Cyan
    # Out-Host: the script's output must not become this function's return value (a failure would read as true).
    & pwsh -NoProfile -File (Join-Path $ai 'install.ps1') @installArgs | Out-Host
    if ($LASTEXITCODE) {
        Write-Error "${Caller}: install.ps1 exited $LASTEXITCODE (1 = you said no, 2 = invalid machine config, 3 = drift: run install.ps1 -AcceptDrift). Stopped there."
        return $false
    }
    return $true
}

# Code half of getStreams: fast-forwards the stream repo's branch from its upstream; never merges or rebases.
function Invoke-GeneStreamCodeGet {
    param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Caller, [switch]$DryRun)
    try {
        $st = Get-GeneCloneState -Dir $Repo -Fetch
        if (-not $st.Upstream) { Write-Error "${Caller}: $Repo branch '$($st.Branch)' tracks no upstream. Nothing was pulled."; return $false }
        Write-Host "Code: $Repo $($st.Branch) vs $($st.Upstream): $($st.Behind) behind, $($st.Ahead) ahead." -ForegroundColor Cyan
        if (-not $st.Behind) { Write-Host '  up to date.' -ForegroundColor DarkGray; return $true }
        if ($st.Ahead) { Write-Error "${Caller}: $($st.Branch) has diverged from $($st.Upstream) ($($st.Ahead) local commit(s)); a fast-forward cannot take it. Resolve it with git, then rerun. Nothing was pulled."; return $false }
        if ($DryRun) { Write-Host "  DryRun: would fast-forward $($st.Behind) commit(s)." -ForegroundColor Cyan; return $true }
        Invoke-GeneStreamGit -Dir $Repo -GitArgs @('pull', '--ff-only', '--quiet') | Out-Null
        $head = @(Invoke-GeneStreamGit -Dir $Repo -GitArgs @('rev-parse', '--short', 'HEAD'))[0]
        Write-Host "  fast-forwarded $($st.Behind) commit(s) to $head." -ForegroundColor Green
        return $true
    }
    catch { Write-Error "${Caller}: $($_.Exception.Message)"; return $false }
}

# pushStreams without -Handoff: publish.ps1 for the kit, then git push of the stream branch where the git policy gives
# this machine an owner push. -RequireCode turns a missing push right or an unpushed result into a failure (handoff).
function Invoke-GeneStreamPush {
    param([string]$Repo, [string]$Message, [Parameter(Mandatory)][string]$Caller,
        [switch]$NoKit, [switch]$NoCode, [switch]$RequireCode, [switch]$Yes, [switch]$DryRun)
    $ai = Get-GeneAIWorkRoot -Caller $Caller
    if (-not $ai) { return $false }
    if (-not $DryRun -and -not $Yes -and [Console]::IsInputRedirected) {
        Write-Error "${Caller}: needs a console (the GitHub sign-in and publish.ps1's questions cannot show here). Run it in a Windows Terminal tab, or add -Yes. Nothing was pushed."
        return $false
    }
    if (-not $NoKit) {
        $st = Get-GeneCloneState -Dir $ai
        if (-not $st.Files -and -not $st.Ahead) { Write-Host "Kit: $ai has nothing to publish." -ForegroundColor DarkGray }
        elseif ($DryRun) { Write-Host "Kit: DryRun: would publish $($st.Files) file(s) and $($st.Ahead) commit(s) from $ai (publish.ps1)." -ForegroundColor Cyan }
        else {
            $pubArgs = @(); if ($Message) { $pubArgs += @('-Message', $Message) }; if ($Yes) { $pubArgs += '-Yes' }
            Write-Host "Kit: pwsh -NoProfile -File $ai\publish.ps1" -ForegroundColor Cyan
            & pwsh -NoProfile -File (Join-Path $ai 'publish.ps1') @pubArgs | Out-Host
            if ($LASTEXITCODE) { Write-Error "${Caller}: publish.ps1 exited $LASTEXITCODE. Stopped before the code."; return $false }
        }
    }
    if ($NoCode) { return $true }
    $full = Resolve-GeneStreamRepoPath -Repo $Repo -Caller $Caller
    if (-not $full) { return $false }
    try {
        $policy = Get-GeneRepoGitPolicy -Repo $full -AIWorkRoot $ai
        if (-not $policy.OwnerPush) {
            $msg = "the git policy in $global:GeneMachineConfigPath gives $full no owner push on $env:COMPUTERNAME (Owner push, else Push)"
            if ($RequireCode) { Write-Error "${Caller}: $msg; the new host pulls the code from the remote, so it must go there. Set Owner push = yes on that row."; return $false }
            Write-Host "Code: skipped: $msg." -ForegroundColor DarkYellow
            return $true
        }
        $st = Get-GeneCloneState -Dir $full -Fetch
        if (-not $st.Upstream) { Write-Error "${Caller}: $full branch '$($st.Branch)' tracks no upstream. Nothing was pushed."; return $false }
        Write-Host "Code: $full $($st.Branch) vs $($st.Upstream): $($st.Ahead) ahead, $($st.Behind) behind." -ForegroundColor Cyan
        if (-not $st.Ahead) { Write-Host '  nothing to push.' -ForegroundColor DarkGray; return $true }
        if ($st.Behind) { Write-Error "${Caller}: $($st.Upstream) has $($st.Behind) commit(s) this clone lacks; run getStreams -NoKit (or resolve the divergence), then push. Nothing was pushed."; return $false }
        if ($DryRun) { Write-Host "  DryRun: would push $($st.Ahead) commit(s)." -ForegroundColor Cyan; return $true }
        Invoke-GeneStreamGit -Dir $full -GitArgs @('push', '--quiet') | Out-Null
        Write-Host "  pushed $($st.Ahead) commit(s) to $($st.Upstream)." -ForegroundColor Green
        return $true
    }
    catch { Write-Error "${Caller}: $($_.Exception.Message)"; return $false }
}

# pushStreams -Handoff, on the OLD host: stop everything, wait for quiet, publish the kit, push the code, record what
# ran (handoff.json) and take the nightly suite off this machine. getStreams -FromHost on the new host does the rest.
function Invoke-GeneStreamHandoff {
    param([string]$Repo, [string]$Message, [int]$TimeoutMinutes = 60, [switch]$AllowClaims, [switch]$Yes, [switch]$DryRun)
    $caller = 'pushStreams -Handoff'
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller $caller
    if (-not $full) { return }
    if (-not $DryRun -and -not $Yes -and [Console]::IsInputRedirected) { Write-Error "${caller}: needs a console. Run it in a Windows Terminal tab, or add -Yes. Nothing was done."; return }
    $layout = Get-GeneStreamLiveLayout -Repo $full
    Write-Host "Handoff of $full from ${env:COMPUTERNAME}: running now: $(Format-GeneStreamLayout $layout)." -ForegroundColor Cyan
    if ($DryRun) {
        @(
            'DryRun: would',
            '  1. stopStreams -CloseSessions: STOP every runner (each finishes its unit) and close the Planner/Adhoc tabs;',
            "  2. wait up to $TimeoutMinutes min until no runner is live, then drop a dead integrator.lock;",
            '  3. check the board is quiet: no claims, no building task, clean main tree (-AllowClaims carries orphan claims);',
            '  4. publish the kit (publish.ps1) and push the stream branch (needs Owner push on this machine);',
            "  5. write $(Get-GeneStreamBoardFile -Repo $full -Kind handoff) with the layout above;",
            "  6. export and unregister the '$global:GeneStreamNightlyPrefix $(Split-Path $full -Leaf)' task."
        ) | ForEach-Object { Write-Host $_ }
        $noise = Get-GeneStreamBoardNoise -Repo $full
        Write-Host "  board now: $($noise.Claims.Count) claim(s), $($noise.Flight.Count) building, lock=$($noise.Lock), $($noise.Dirty.Count) uncommitted entr(ies)." -ForegroundColor DarkGray
        $null = Invoke-GeneStreamPush -Repo $full -Caller $caller -RequireCode -DryRun
        return
    }

    stopStreams -Repo $full -CloseSessions
    if (-not (Wait-GeneStreamRunnersExit -Repo $full -TimeoutMinutes $TimeoutMinutes)) {
        Write-Error "${caller}: runners still finishing after $TimeoutMinutes min; the STOP file stays. Rerun pushStreams -Handoff to keep waiting."
        return
    }
    $lock = Join-Path $full '.streams\integrator.lock'
    if (Test-Path -LiteralPath $lock) {
        Remove-Item -LiteralPath $lock
        Write-Host "  removed $lock (no integrator runs any more)." -ForegroundColor DarkYellow
    }
    $noise = Get-GeneStreamBoardNoise -Repo $full
    if ($noise.Dirty.Count) {
        Write-Error "${caller}: $full has $($noise.Dirty.Count) uncommitted entr(ies) (an integration stopped halfway?): $(($noise.Dirty | Select-Object -First 8) -join '; '). Commit or revert them, then rerun. Streams stay stopped."
        return
    }
    if (($noise.Claims.Count -or $noise.Flight.Count) -and -not $AllowClaims) {
        Write-Error "${caller}: the board still has claims ($($noise.Claims -join ', ')) / building tasks ($($noise.Flight -join ', ')). With every runner stopped they are orphans: add -AllowClaims to carry them (the new host's watchdog frees them after 30/45 min). Streams stay stopped."
        return
    }
    if (-not (Invoke-GeneStreamPush -Repo $full -Message $Message -Caller $caller -RequireCode -Yes:$Yes)) { return }
    $after = Get-GeneCloneState -Dir $full
    if ($after.Ahead -or $after.Files) { Write-Error "${caller}: $full still has $($after.Ahead) unpushed commit(s) / $($after.Files) uncommitted entr(ies). Streams stay stopped."; return }
    $head = @(Invoke-GeneStreamGit -Dir $full -GitArgs @('rev-parse', 'HEAD'))[0]
    Write-GeneStreamBoardFile -Repo $full -Kind handoff -Data ([ordered]@{
            from = $env:COMPUTERNAME; at = (Get-Date).ToUniversalTime().ToString('o'); by = $env:USERNAME; head = $head
            authors = $layout.Authors; builders = $layout.Builders; tabs = @($layout.Tabs); sessions = @($layout.Sessions)
            carriedClaims = @($noise.Claims); carriedBuilding = @($noise.Flight)
        })
    Write-Host "Wrote $(Get-GeneStreamBoardFile -Repo $full -Kind handoff)." -ForegroundColor Green

    $task = "$global:GeneStreamNightlyPrefix $(Split-Path $full -Leaf)"
    if (Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue) {
        try {
            $dir = Join-Path $global:GeneMachineAI['ScratchRoot'] "stream-move\$(Get-Date -Format yyyyMMdd-HHmmss)"
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Export-ScheduledTask -TaskName $task | Set-Content -LiteralPath (Join-Path $dir 'nightly-task.xml') -Encoding unicode
            Unregister-ScheduledTask -TaskName $task -Confirm:$false -ErrorAction Stop
            Write-Host "  unregistered '$task' (backup $dir\nightly-task.xml)." -ForegroundColor Green
        }
        catch { Write-Warning "${caller}: could not unregister '$task' ($($_.Exception.Message)). In an elevated pwsh: Unregister-ScheduledTask -TaskName '$task'" }
    }
    Write-Host "Handoff ready. On the new host, in a Windows Terminal tab: getStreams -FromHost $env:COMPUTERNAME" -ForegroundColor Green
}

# getStreams -FromHost, on the NEW host: everything to run the board that ran on -FromHost here. Reads the old host's
# repo and AI setup paths from its own machine config over the admin share.
function Invoke-GeneStreamTakeover {
    param([string]$Repo, [Parameter(Mandatory)][string]$FromHost, [string]$FromRepo, [string]$ContainerRoot,
        [switch]$NoHandoff, [switch]$AllowClaims, [switch]$Yes, [switch]$DryRun)
    $caller = 'getStreams -FromHost'
    if ($FromHost -eq $env:COMPUTERNAME) { Write-Error "${caller}: $FromHost is this machine. Nothing was done."; return }
    $full = Resolve-GeneStreamRepoPath -Repo $Repo -Caller $caller
    if (-not $full) { return }
    $scratch = $global:GeneMachineAI['ScratchRoot']
    if (-not $scratch) { Write-Error "${caller}: ScratchRoot is blank in $global:GeneMachineConfigPath (the old board is saved there). Nothing was done."; return }

    try { $src = if ($FromRepo) { $FromRepo.TrimEnd('\') } else { Get-GeneRemoteMachinePath -ComputerName $FromHost -Key 'SpeedyRepo' } }
    catch { Write-Error "${caller}: $($_.Exception.Message). Pass -FromRepo \\$FromHost\<drive>`$\<path>. Nothing was done."; return }
    if (-not (Test-Path -LiteralPath (Join-Path $src '.streams\tasks.json'))) { Write-Error "${caller}: no board at $src\.streams. Nothing was done."; return }
    Write-Host "Takeover: $FromHost $src -> $env:COMPUTERNAME $full" -ForegroundColor Cyan

    # This machine must not be running a board itself.
    if (Test-Path -LiteralPath (Join-Path $full '.streams\tasks.json')) {
        $here = Get-GeneStreamLiveLayout -Repo $full
        if ($here.Authors + $here.Builders + @($here.Tabs).Count + @($here.Sessions).Count) {
            Write-Error "${caller}: this machine still runs its own board ($(Format-GeneStreamLayout $here)). stopStreams -CloseSessions first. Nothing was done."
            return
        }
    }

    # The old host: not already moved, handed off, quiet, kit published.
    $moved = Read-GeneStreamBoardFile -Repo $src -Kind moved
    if ($moved) { Write-Error "${caller}: the board on $FromHost already moved to $($moved.to) on $($moved.at). Nothing was done."; return }
    $handoff = Read-GeneStreamBoardFile -Repo $src -Kind handoff
    if (-not $handoff -and -not $NoHandoff) {
        Write-Error "${caller}: $FromHost has not handed off (no $(Get-GeneStreamBoardFile -Repo $src -Kind handoff)). On ${FromHost}: pushStreams -Handoff. If it cannot run commands any more, add -NoHandoff. Nothing was done."
        return
    }
    if ($handoff) { Write-Host "  handoff by $($handoff.by) at $($handoff.at): $($handoff.authors) author(s), $($handoff.builders) builder(s), tabs $(@($handoff.tabs) -join ', ')" -ForegroundColor DarkCyan }
    try { $noise = Get-GeneStreamBoardNoise -Repo $src }
    catch { Write-Error "${caller}: cannot read the board or repo on ${FromHost}: $($_.Exception.Message). Nothing was done."; return }
    if ($noise.Dirty.Count) { Write-Error "${caller}: $src has $($noise.Dirty.Count) uncommitted entr(ies): $(($noise.Dirty | Select-Object -First 8) -join '; '). That code would be lost. Nothing was done."; return }
    if (($noise.Claims.Count -or $noise.Flight.Count -or $noise.Lock) -and -not $AllowClaims) {
        Write-Error "${caller}: the board on $FromHost is not quiet: claims $($noise.Claims -join ', '); building $($noise.Flight -join ', '); integrator.lock=$($noise.Lock). If everything there is stopped these are orphans: add -AllowClaims. Nothing was done."
        return
    }
    try {
        $srcAi = Get-GeneRemoteMachinePath -ComputerName $FromHost -Key 'AIWorkRoot'
        $kit = Get-GeneCloneState -Dir $srcAi
        if ($kit.Files -or $kit.Ahead) {
            $msg = "the AI setup on $FromHost ($srcAi) has unpublished changes ($($kit.Files) file(s), $($kit.Ahead) commit(s))"
            if (-not $NoHandoff) { Write-Error "${caller}: $msg. On ${FromHost}: pushStreams -NoCode. Nothing was done."; return }
            Write-Warning "${caller}: $msg; they do not come along (see git -C $srcAi status)."
        }
    }
    catch { Write-Warning "${caller}: could not check the AI setup on ${FromHost}: $($_.Exception.Message)" }

    if ($DryRun) {
        @(
            'DryRun: checks passed. Would',
            '  1. getStreams here (install the kit, fast-forward the code) and require the same tree as the old host;',
            "  2. move this machine's .streams (if any) to $scratch\stream-move\<stamp>\;",
            "  3. robocopy /MIR $src\.streams -> $full\.streams (no *.lock files);",
            "  4. add .streams/ to $full\.git\info\exclude if missing;",
            "  5. write .streams\host.json ($env:COMPUTERNAME) here and .streams\MOVED.json on $FromHost;",
            "  6. copy $src\.env if this repo has none; then check this host (Test-StreamHostReady, .env, dev cert, compose, nightly)."
        ) | ForEach-Object { Write-Host $_ }
        return
    }

    if (-not (Invoke-GeneStreamKitGet -Caller $caller -Yes:$Yes)) { return }
    if (-not (Invoke-GeneStreamCodeGet -Repo $full -Caller $caller)) { return }
    try {
        $hereTree = @(Invoke-GeneStreamGit -Dir $full -GitArgs @('rev-parse', 'HEAD^{tree}'))[0]
        $thereTree = @(Invoke-GeneStreamGit -Dir $src -GitArgs @('rev-parse', 'HEAD^{tree}'))[0]
    }
    catch { Write-Error "${caller}: $($_.Exception.Message)"; return }
    if ($hereTree -ne $thereTree) {
        Write-Error "${caller}: the code differs: here tree $hereTree, $FromHost $thereTree. Push it from $FromHost (pushStreams -NoKit), then rerun. The board was not copied."
        return
    }

    $moveDir = Join-Path $scratch "stream-move\$(Get-Date -Format yyyyMMdd-HHmmss)"
    New-Item -ItemType Directory -Path $moveDir -Force | Out-Null
    $log = Join-Path $moveDir 'robocopy.log'
    $board = Join-Path $full '.streams'
    if (Test-Path -LiteralPath $board) {
        $old = Join-Path $moveDir "$(Split-Path $full -Leaf)-streams-old"
        & robocopy $board $old /E /MOVE /R:2 /W:2 /NP /NFL /NDL "/LOG+:$log" | Out-Null
        if ($LASTEXITCODE -ge 8) { Write-Error "${caller}: saving the old board to $old failed (robocopy $LASTEXITCODE, $log). Nothing else was changed."; return }
        if (Test-Path -LiteralPath $board) {
            if (@(Get-ChildItem -LiteralPath $board -Recurse -File -Force).Count) { Write-Error "${caller}: files left in $board after saving it to $old (in use?). Close what holds them and rerun."; return }
            Remove-Item -LiteralPath $board -Recurse -Force
        }
        Write-Host "  saved this machine's old board to $old" -ForegroundColor DarkCyan
    }
    Write-Host "  copying the board from $FromHost (robocopy, log $log) ..." -ForegroundColor DarkCyan
    & robocopy (Join-Path $src '.streams') $board /MIR /XF '*.lock' /R:2 /W:2 /MT:16 /NP /NFL /NDL "/LOG+:$log" | Out-Null
    if ($LASTEXITCODE -ge 8) { Write-Error "${caller}: robocopy of the board failed ($LASTEXITCODE). See $log. $FromHost was not marked moved."; return }
    $files = @(Get-ChildItem -LiteralPath $board -Recurse -File -Force).Count
    Write-Host "  board copied: $files file(s)." -ForegroundColor Green
    Remove-Item -LiteralPath (Get-GeneStreamBoardFile -Repo $full -Kind handoff) -ErrorAction SilentlyContinue

    $exclude = Join-Path $full '.git\info\exclude'
    if ((Test-Path -LiteralPath (Split-Path $exclude)) -and -not (Select-String -LiteralPath $exclude -Pattern '^\s*/?\.streams/?\s*$' -Quiet -ErrorAction SilentlyContinue)) {
        Add-Content -LiteralPath $exclude -Value '.streams/'
        Write-Host "  added .streams/ to $exclude" -ForegroundColor DarkCyan
    }

    $at = (Get-Date).ToUniversalTime().ToString('o')
    Write-GeneStreamBoardFile -Repo $full -Kind host -Data ([ordered]@{ host = $env:COMPUTERNAME; from = $FromHost; at = $at; by = $env:USERNAME })
    try {
        Write-GeneStreamBoardFile -Repo $src -Kind moved -Data ([ordered]@{ to = $env:COMPUTERNAME; at = $at; by = $env:USERNAME })
        Write-Host "  marked the board on $FromHost moved (MOVED.json): stream tabs there now refuse." -ForegroundColor Green
    }
    catch { Write-Warning "${caller}: could not write MOVED.json on ${FromHost} ($($_.Exception.Message)). Nothing stops streams starting there: do not start them." }

    $envFile = Join-Path $full '.env'
    if (-not (Test-Path -LiteralPath $envFile) -and (Test-Path -LiteralPath (Join-Path $src '.env'))) {
        Copy-Item -LiteralPath (Join-Path $src '.env') -Destination $envFile
        Write-Host "  copied .env from $FromHost (it held only channel names there; check it fits this machine)." -ForegroundColor DarkYellow
    }

    Show-GeneStreamHostReadiness -Repo $full -ContainerRoot $ContainerRoot
    Write-Host ''
    Write-Host 'Then start the stream here, in a Windows Terminal tab:' -ForegroundColor Green
    Write-Host '  addStreams'
    if ($handoff -and $handoff.authors) { Write-Host "  addStreamTab -Author -Count $($handoff.authors)" }
    if ($handoff -and $handoff.builders) { Write-Host "  addStreamTab -Builder -Count $($handoff.builders)" }
}

# What a stream host needs that never travels with the board. Prints each check and a LEFT TO DO list; changes nothing.
function Show-GeneStreamHostReadiness {
    param([Parameter(Mandatory)][string]$Repo, [string]$ContainerRoot)
    $todo = [System.Collections.Generic.List[string]]::new()
    $row = { param($ok, $what) Write-Host ("  {0,-4} {1}" -f $(if ($ok) { 'ok' } else { 'TODO' }), $what) -ForegroundColor $(if ($ok) { 'DarkGreen' } else { 'Yellow' }) }
    Write-Host "Host readiness on ${env:COMPUTERNAME}:" -ForegroundColor Cyan

    $ai = $global:GeneMachineAI['AIWorkRoot']
    $dir = $global:GeneMachineAI['StreamHostDir']
    $ready = @($(if ($dir) { Join-Path $dir 'Test-StreamHostReady.ps1' }), $(if ($ai) { Join-Path $ai 'stream-host\Test-StreamHostReady.ps1' })) |
        Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
    if ($ready) {
        if (-not $ContainerRoot) { $ContainerRoot = if (Test-Path -LiteralPath 'D:\RancherDesktop') { 'D:\RancherDesktop' } else { 'C:\' } }
        $wt = if ($global:GeneMachineAI['WorktreesRoot']) { Join-Path $global:GeneMachineAI['WorktreesRoot'] (Split-Path $Repo -Leaf) } else { 'C:\devops\worktrees\speedmerchants' }
        & pwsh -NoProfile -File $ready -Repo $Repo -WorktreeRoot $wt -ContainerRoot $ContainerRoot | Out-Host
        if ($LASTEXITCODE) { $todo.Add("Test-StreamHostReady: fix the FAIL rows above (ContainerRoot $ContainerRoot; pass -ContainerRoot if Rancher keeps its disks elsewhere).") }
    }
    else { $todo.Add('Test-StreamHostReady.ps1 not found (StreamHostDir / AIWorkRoot\stream-host): run install.ps1.') }

    $hasEnv = Test-Path -LiteralPath (Join-Path $Repo '.env')
    & $row $hasEnv "root .env in $Repo"
    if (-not $hasEnv) { $todo.Add("root .env missing in $Repo (the nightly suite refuses without it): copy it from the old host, or write the 11 Channel keys (src\Agent\appsettings.sample.json).") }
    $hasLocal = Test-Path -LiteralPath (Join-Path $Repo '.env.local')
    & $row $hasLocal "$Repo\.env.local"
    if (-not $hasLocal) { $todo.Add("$Repo\.env.local missing: $Repo\scripts\e2e\Write-SpeedyStackEnv.ps1 -RepoRoot $Repo") }
    $channel = Join-Path $env:LOCALAPPDATA 'Speedy\dev-stack\worker-channel'
    $hasChannel = Test-Path -LiteralPath $channel
    & $row $hasChannel "worker-channel certificates ($channel)"
    if (-not $hasChannel) { $todo.Add("worker-channel certificates missing: $Repo\scripts\fleet\New-WorkerChannelCertificates.ps1") }
    if (Get-Command dotnet -ErrorAction SilentlyContinue) {
        $null = & dotnet dev-certs https --check --trust 2>&1
        $trusted = ($LASTEXITCODE -eq 0)
        & $row $trusted 'ASP.NET dev certificate trusted (dotnet dev-certs https --check --trust)'
        if (-not $trusted) { $todo.Add('dev certificate not trusted: dotnet dev-certs https --trust (desktop session, answer Yes)') }
    }
    $compose = Join-Path $Repo 'compose.yaml'
    if ((Get-Command docker -ErrorAction SilentlyContinue) -and (Test-Path -LiteralPath $compose)) {
        $running = @(& docker compose -f $compose ps --status running --services 2>$null)
        $missing = @($global:GeneStreamComposeServices | Where-Object { $_ -notin $running })
        & $row (-not $missing.Count) "compose services running ($($global:GeneStreamComposeServices -join ', '))"
        if ($missing.Count) { $todo.Add("compose services not running: $($missing -join ', '). docker compose -f $compose up -d (Rancher must be up)") }
    }
    else { $todo.Add('docker or compose.yaml not found: Rancher Desktop + the compose stack (SyncStream B1/B3a).') }
    $task = "$global:GeneStreamNightlyPrefix $(Split-Path $Repo -Leaf)"
    $hasTask = [bool](Get-ScheduledTask -TaskName $task -ErrorAction SilentlyContinue)
    & $row $hasTask "nightly task '$task'"
    if (-not $hasTask) {
        $claudeHome = if ($global:GeneMachineAI['ClaudeHome']) { $global:GeneMachineAI['ClaudeHome'] } else { Join-Path $HOME '.claude' }
        $reg = Join-Path $claudeHome 'skills\stream-kit\scripts\Register-NightlySuite.ps1'
        $todo.Add("nightly suite not registered (after the stack is up), elevated: pwsh -NoProfile -File $reg -Repo $Repo")
    }
    if (-not $global:GeneMachineAI['StatusPageDir']) { Write-Host "  info StatusPageDir is blank: the status page goes to $Repo\.streams\status.html" -ForegroundColor DarkGray }

    if ($todo.Count) {
        Write-Host 'LEFT TO DO:' -ForegroundColor Yellow
        $i = 0; foreach ($t in $todo) { $i++; Write-Host "  $i. $t" -ForegroundColor Yellow }
    }
    else { Write-Host 'Host ready: nothing left to do.' -ForegroundColor Green }
}

function getStreams {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [string]$FromHost,
        [string]$FromRepo,
        [string]$ContainerRoot,
        [switch]$NoHandoff,
        [switch]$AllowClaims,
        [switch]$NoKit,
        [switch]$NoCode,
        [switch]$Yes,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'getStreams [-Repo <repo>] [-NoKit] [-NoCode] [-Yes] [-DryRun] [-Help]',
            'getStreams -FromHost <old host> [-FromRepo <unc>] [-NoHandoff] [-AllowClaims] [-ContainerRoot <dir>] [-Yes] [-DryRun]',
            '',
            'Brings this machine up to date. Paths come from the machine config: the kit from AIWorkRoot, the code from',
            'SpeedyRepo (or -Repo).',
            '  1. Kit: refuses over unpublished AI setup changes (offers to publish them first: memory lives in that clone),',
            '     then runs install.ps1 (pull + apply). -Yes skips its confirmation.',
            '  2. Code: fetch, then a fast-forward of the current branch from its upstream (never a merge or rebase).',
            '  3. Says what picks the change up by itself (runner units) and what needs a restart (Planner, Adhoc).',
            'It never touches the board (.streams).',
            '',
            '-FromHost: TAKE OVER the stream that ran on another machine (run pushStreams -Handoff there first). It reads the',
            'old host''s SpeedyRepo and AIWorkRoot from ITS machine config (\\<host>\C$\Deploy\Setup\ProfileMachineConfig.md),',
            'refuses unless that board is handed off, quiet and its kit published, runs steps 1-2 here, requires the same code',
            'tree, saves this machine''s old board under {ScratchRoot}\stream-move\, mirrors the board (no lock files), writes',
            '.streams\host.json here and .streams\MOVED.json there (stream tabs on the old host then refuse), copies .env when',
            'this repo has none, checks this host (Test-StreamHostReady, .env, dev cert, compose, nightly task) and prints',
            'LEFT TO DO plus the addStreams / addStreamTab commands for what ran there.',
            '',
            'Options:',
            '  -Repo           The stream repo here. Default: SpeedyRepo.',
            '  -NoKit/-NoCode  Skip the kit or the code step.',
            '  -FromHost       The old host''s computer name.',
            '  -FromRepo       The old host''s repo as a UNC path, when its machine config cannot be read.',
            '  -NoHandoff      Take over without pushStreams -Handoff (the old host cannot run commands any more).',
            '  -AllowClaims    Carry orphan claims, building tasks and a dead integrator.lock (the watchdog frees them).',
            '  -ContainerRoot  Where Rancher keeps its disks, for Test-StreamHostReady (default D:\RancherDesktop if present, else C:\).',
            '  -Yes            No confirmation from install.ps1.',
            '  -DryRun         Check and print what would happen; change nothing (the code is fetched to count commits).',
            '',
            'See also: pushStreams, updateStreams, addStreams.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    if ($FromHost) {
        Invoke-GeneStreamTakeover -Repo $Repo -FromHost $FromHost -FromRepo $FromRepo -ContainerRoot $ContainerRoot -NoHandoff:$NoHandoff -AllowClaims:$AllowClaims -Yes:$Yes -DryRun:$DryRun
        return
    }
    $full = $null
    if (-not $NoCode) {
        $full = Resolve-GeneStreamRepoPath -Repo $Repo -Caller 'getStreams'
        if (-not $full) { return }
    }
    if (-not $NoKit -and -not (Invoke-GeneStreamKitGet -Caller 'getStreams' -Yes:$Yes -DryRun:$DryRun)) { return }
    if (-not $NoCode -and -not (Invoke-GeneStreamCodeGet -Repo $full -Caller 'getStreams' -DryRun:$DryRun)) { return }
    if (-not $NoKit) { Show-GeneStreamRestartNeeds -Repo $(if ($full) { $full } else { $global:GeneMachine['SpeedyRepo'] }) }
    Write-Host "getStreams done$(if ($DryRun) { ' (DryRun)' })." -ForegroundColor Green
}

function pushStreams {
    [CmdletBinding()]
    param(
        [string]$Message,
        [string]$Repo,
        [switch]$NoKit,
        [switch]$NoCode,
        [switch]$Handoff,
        [switch]$AllowClaims,
        [ValidateRange(1, 600)][int]$TimeoutMinutes = 60,
        [switch]$Yes,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'pushStreams [-Message <text>] [-Repo <repo>] [-NoKit] [-NoCode] [-Yes] [-DryRun] [-Help]',
            'pushStreams -Handoff [-Message <text>] [-AllowClaims] [-TimeoutMinutes <n>] [-Yes] [-DryRun]',
            '',
            'Sends this machine''s changes up. Run it in a Windows Terminal tab, not Claude''s ! box (the GitHub sign-in and',
            'publish.ps1''s questions need a console).',
            '  1. Kit: publish.ps1 in AIWorkRoot (shows the files, secret scan, commit, rebase, push).',
            '  2. Code: git push of the stream repo''s branch (SpeedyRepo, or -Repo) to its upstream, only where this',
            '     machine''s git policy row gives the owner push: the Owner push column, else Push. Never commits product',
            '     code (the integrator does) and never force-pushes; refuses when the upstream has commits this clone lacks.',
            '',
            '-Handoff: on the OLD host, before getStreams -FromHost on the new one: stopStreams -CloseSessions, wait until',
            'every runner finished its unit, drop the dead integrator.lock, require a quiet board (no claims, nothing',
            'building, clean tree), publish + push (the push must be allowed), record what ran in .streams\handoff.json,',
            'and export + unregister this machine''s nightly suite task.',
            '',
            'Options:',
            '  -Message         Commit message for the kit (default: publish.ps1''s "update from <machine>").',
            '  -Repo            The stream repo. Default: SpeedyRepo.',
            '  -NoKit/-NoCode   Skip the kit or the code step.',
            '  -AllowClaims     Handoff: carry orphan claims / building tasks (the new host''s watchdog frees them).',
            '  -TimeoutMinutes  Handoff: how long to wait for runners to finish (default 60).',
            '  -Yes             No confirmation from publish.ps1 (a secret-scan hit still needs a typed yes).',
            '  -DryRun          Print what would be published and pushed; change nothing.',
            '',
            'See also: getStreams, updateStreams.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    if ($Handoff) {
        Invoke-GeneStreamHandoff -Repo $Repo -Message $Message -TimeoutMinutes $TimeoutMinutes -AllowClaims:$AllowClaims -Yes:$Yes -DryRun:$DryRun
        return
    }
    if (Invoke-GeneStreamPush -Repo $Repo -Message $Message -Caller 'pushStreams' -NoKit:$NoKit -NoCode:$NoCode -Yes:$Yes -DryRun:$DryRun) {
        Write-Host "pushStreams done$(if ($DryRun) { ' (DryRun)' })." -ForegroundColor Green
    }
}

function updateStreams {
    [CmdletBinding()]
    param(
        [string]$Repo,
        [switch]$Code,
        [ValidateRange(1, 600)][int]$TimeoutMinutes = 60,
        [switch]$RestartSessions,
        [switch]$AnyHost,
        [switch]$Yes,
        [switch]$DryRun,
        [Alias('h', '?')][switch]$Help
    )
    if ($Help) {
        @(
            'updateStreams [-Repo <repo>] [-Code] [-TimeoutMinutes <n>] [-RestartSessions] [-AnyHost] [-Yes] [-DryRun] [-Help]',
            '',
            'Rolling update of a RUNNING stream on its host, run from a Windows Terminal tab:',
            '  1. records what runs (Integrator/Kit/Coordinator/Status runners, author and builder counts, long sessions);',
            '  2. stopStreams: a STOP file; each runner finishes its unit (never killed mid-unit) and its tab closes;',
            '  3. waits until no runner is live (-TimeoutMinutes, default 60; on timeout the STOP stays, rerun to keep waiting);',
            '  4. getStreams -NoCode: install the kit (with -Code it also fast-forwards the code);',
            '  5. reopens the same runner tabs and counts (addStreamTab);',
            '  6. lists the long sessions (Planner, Adhoc), which keep the old setup until restarted. -RestartSessions closes',
            '     and reopens the Planner tab (ending any turn in progress). Adhoc is yours to restart.',
            'If step 4 fails the runners stay stopped; fix it, then addStreamTab (or rerun updateStreams).',
            '',
            'Options:',
            '  -Repo             The stream repo. Default: SpeedyRepo.',
            '  -Code             Also fast-forward the code from its upstream.',
            '  -RestartSessions  Restart the Planner tab too.',
            '  -AnyHost          Run even when the board says another machine hosts it.',
            '  -Yes              No confirmation from install.ps1.',
            '  -DryRun           Print what runs and what would happen; change nothing.',
            '',
            'See also: getStreams, pushStreams, stopStreams, addStreamTab.'
        ) | ForEach-Object { Write-Host $_ }
        return
    }
    $full = Enter-GeneStreamRepo -Repo $Repo -Caller 'updateStreams'
    if (-not $full) { return }
    if (-not (Test-GeneStreamHost -Repo $full -Caller 'updateStreams' -AnyHost:$AnyHost)) { return }
    if (-not $DryRun -and -not (Test-GeneWt -Caller 'updateStreams')) { return }
    $layout = Get-GeneStreamLiveLayout -Repo $full
    Write-Host "updateStreams $full, running now: $(Format-GeneStreamLayout $layout)." -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host 'DryRun: would stopStreams, wait for every runner to finish its unit, then:' -ForegroundColor Cyan
        $null = Invoke-GeneStreamKitGet -Caller 'updateStreams' -DryRun
        if ($Code) { $null = Invoke-GeneStreamCodeGet -Repo $full -Caller 'updateStreams' -DryRun }
        Write-Host "  then reopen: $(@($layout.Tabs) -join ', ') $(if ($layout.Authors) { "Author x$($layout.Authors)" }) $(if ($layout.Builders) { "Builder x$($layout.Builders)" })" -ForegroundColor Cyan
        if ($RestartSessions -and 'Planner' -in $layout.Sessions) { Write-Host '  and close + reopen the Planner tab.' -ForegroundColor Cyan }
        return
    }

    stopStreams -Repo $full
    if (-not (Wait-GeneStreamRunnersExit -Repo $full -TimeoutMinutes $TimeoutMinutes)) {
        Write-Error "updateStreams: runners still finishing after $TimeoutMinutes min; the STOP file stays. Rerun updateStreams to keep waiting, or addStreamTab -ClearStop to cancel."
        return
    }
    Write-Host '  every runner has stopped.' -ForegroundColor DarkCyan
    if (-not (Invoke-GeneStreamKitGet -Caller 'updateStreams' -Yes:$Yes)) { Write-Warning 'updateStreams: the runners stay stopped; fix the above, then rerun updateStreams or addStreamTab.'; return }
    if ($Code -and -not (Invoke-GeneStreamCodeGet -Repo $full -Caller 'updateStreams')) { Write-Warning 'updateStreams: the kit is installed, the runners stay stopped; fix the code step, then rerun updateStreams or addStreamTab.'; return }
    Open-GeneStreamLayout -Repo $full -Layout $layout -AnyHost:$AnyHost

    foreach ($s in @($layout.Sessions)) {
        if ($s -eq 'Planner' -and $RestartSessions) {
            stopStreams -Repo $full -Role Planner -CloseSessions
            $deadline = (Get-Date).AddSeconds(30)
            while (@(Get-GeneStreamSessions -Repo $full | Where-Object { $_.Tab -eq 'Planner' }).Count -and (Get-Date) -lt $deadline) { Start-Sleep -Seconds 2 }
            addStreamTab -Role Planner -Repo $full -AnyHost:$AnyHost
            continue
        }
        Write-Host "  ${s}: long session, still on the old setup; restart it when it is quiet$(if ($s -eq 'Planner') { ' (or updateStreams -RestartSessions)' })." -ForegroundColor Yellow
    }
    Write-Host 'updateStreams done.' -ForegroundColor Green
}
#endregion Stream sessions -------------------------------------------------------
