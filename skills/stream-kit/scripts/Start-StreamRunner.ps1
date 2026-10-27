# Runs one stream role as a series of FRESH Claude sessions, one per unit of work, so every ticket, build or timed
# review starts with a clean context instead of inheriting a long /loop session's history (owner ruling 2026-10-04:
# "everytime an author or a builder takes a new ticket they get a clean context", extended the same night to the
# coordinator, integrator, planner, status and kit roles).
#
#   Start-StreamRunner.ps1 -Repo <repo> -Role author|build|integrate|plan|status|kit|coordinator [-Live [-Remote] | -Stream]
#                          [-IntervalSeconds N] [-UnitTimeoutSeconds N] [-Model <alias>] [-MaxRuns N] [-Tab <name>] [-DryRun]
#
# Three launch modes (the EnhanceStream design, options A2, G and E):
#   (default)  A: `claude -p` per unit, headless; the JSON result is logged when the session ends.
#   -Stream    A2: the same `-p` session with --output-format stream-json; the runner prints one short line per message
#              and tool call as it happens, so the runner's tab shows the unit live as text.
#   -Live      G: a normal INTERACTIVE session per unit in the runner's own terminal, the stream-unit mod loaded from
#              ..\mods\stream-unit, and the command as its starting prompt. The skill ends its cycle by calling the mod's
#              unit_done tool, which writes the unit's result file and exits the session; the runner then logs it and
#              starts the next unit in a new process. Needs a subscription login, and a repo folder Claude already trusts.
#   -Remote    with -Live only: also turn Remote Control on, named after the session id, so claude.ai/code and the
#              mobile app list the unit. Off unless asked (owner 2026-10-20).
#
# WORK roles (author, build) are gated: before each launch the runner checks, with the kit's own rules and no model
# call, whether the role has anything to take (an actionable inbox item, or a claimable row). Nothing to take = WATCH
# tasks.json and the role's inbox file (a stat every 5 s, zero tokens) and re-check the gate when either is written, or
# every -IntervalSeconds (default 300) as a fallback; something to take = PRE-STAGE and launch, and launch again as soon
# as that session exits. While it watches, the tab shows an IDLE report (owner request 2026-10-17): the focus groups in
# the owner's order and the released groups, why no row is claimable (claimed, held, waiting on which dependency, not
# released, outside the focus), the last unit's session, outcome, row, minutes and cost, this runner's tally, and when
# it looks again; the block repeats when the reason changes and a one-line "still idle" every -IntervalSeconds. The
# same report is in the state file (idle, lastUnit, tally). TIMED roles (integrate 600 s, plan 600 s, kit 600 s,
# status 900 s, coordinator 1200 s) launch once per interval, measured start to start.
#
# PRE-STAGE (2026-10-06 prestage-runner-design 3.2). A work unit used to start with 10 to 20 tool calls of board
# plumbing - inbox list and take, lessons read, claim, worktree, kept-patch restore, author-grader RED - each paid at
# the whole context (measured 10/1-10/5: 30-64% of an author unit's calls, 15-17% of a builder's), and 64 author units
# on 10/5 launched into NONE ($36). Nobody needs judgment for any of that, so the runner now does it in PowerShell
# before Claude starts: it takes the oldest actionable inbox item in the unit's name, or claims the next row with
# Claim-Task.ps1 (the same selector as the gate, so a gate that says work and a claim that says NONE cannot disagree;
# a NONE is a lost race and launches nothing); for a build it lays the worktree (New-TaskWorktree.ps1), proves the
# author grader RED on the fresh tree (Invoke-Grader.ps1 -Only grader -ExpectRed) and bounces a row that is not red
# back to planned WITHOUT a launch, then restores a kept patch (Restore-TaskPatch.ps1) and grades it. Everything the
# unit needs is written as a PACKET under .streams\units\<session>\ (task.json and unit.md: the row, the held item,
# the lessons, requirement excerpts, the worktree and RED results), and Claude is launched with "packet: <unit.md>" in
# its command and the packet named in its rules. One unit does one item OR one row. After the unit exits, a build row
# still claimed by it (the unit died mid-build) has its worktree exported to a patch before the claim is released, so
# no work is lost. -NoPreStage keeps the 2026-10-04 behaviour (Claude does the plumbing) for a comparison run.
#
# Every launch has bypassPermissions (an unattended session must never wait on a prompt; -p modes also pass
# --permission-prompts none) and appended rules naming the session id, one cycle, no ScheduleWakeup, detach long runs,
# and the role's lessons file. Author and build get a new session id per launch; the timed roles keep one id for the
# runner's life, because the integrator lock and the planner's inbox holds are keyed by session. Hooks still run, so
# git-guard still applies.
#
# Machine configuration: every session must run on the applied install, with CLAUDE_CODE_TMPDIR, AI_LAUNCH_REVISION
# and the installed AI_* env, as the ai launcher ({ClaudeHome}\bin\ai.ps1) gives an interactive start (kit item
# IN-20261004143031-d21b). ai runs Install-AIMachine.ps1 -Launch before claude, and that check took 111 s on SMVMTR1
# (measured 2026-10-04), so launching every unit through ai cost about two minutes per unit. The runner instead runs the
# check through ai itself (`ai.ps1 --version`) when it starts and again once the last check is -LaunchCheckMinutes old
# (default 60), sets the same environment ai sets, and starts claude directly. An invalid machine config (ai exit 2)
# refuses the launch and backs off.
#
# Each unit has a wall-clock limit, -UnitTimeoutSeconds (default author 1800, build 5400,
# integrate 1200, others 1200). A -Live session past it is ended and logged TIMEOUT; -p modes are not timed (they
# cannot wait on a prompt). A -Live session still running -ResultGraceSeconds (default 120) after it wrote its result
# file is ended too and logged RESULT-GRACE, an ok run: its /exit was swallowed, its work is done. Time a live session spends on an open permission prompt does not count: the stream-unit
# mod writes <result>.waiting.json while one is open, and the runner then retitles its tab '<tab> - NEEDS YOU', rings
# the bell, sets its state to 'waiting on owner' and files an ESCALATE line in owner\permission-prompts.md, never owner\questions.md (re-written RESOLVED
# once answered). The console modes are put back after every live unit, so a killed session never leaves the tab dead.
#
# Output: one result per launch under .streams\logs\runner\<runner>\ (<stamp>-<session>.json; -Stream adds .jsonl with
# every raw event), and a state file .streams\runners\<runner>.json (pid, role, mode, session, unitPid under -Live,
# runs, last start/exit/result). After every unit, whatever its outcome, the runner releases any claim the unit's
# session still holds (Clear-SessionClaims), so a killed or timed-out unit never leaves a row unclaimable. Stop a runner with Ctrl+C or by creating .streams\runners\STOP-<role> (stops every runner of that
# role) or .streams\runners\STOP (stops all); the runner checks between launches, never killing a live session. One runner
# alone stops on STOP-<runner id>, or on STOP-tab-<tab> when it was started with -Tab (the terminal tab it runs in, e.g.
# 'Author 2', recorded in the state file; each run of other characters becomes _), and deletes those two files as it
# exits. It also
# stops when every group is closed.
# A failed launch (non-zero exit, is_error with no unit outcome, no result, a TIMEOUT with no result, or a usage/rate-limit
# result) backs off 900 s, doubling to 3600 s, and resets on the next clean run. A unit that REPORTED its outcome and
# exited 0 ran its cycle, whatever the outcome: the stream-unit mod writes is_error=true for outcome 'failed', and two
# build runners idled 15 min each on a verifier FAIL with 20 rows claimable (kit item IN-20261010153049-6849).
# A plan runner never launches beside another live plan* session (Get-LivePlanner); it prints LIVE-PLANNER and waits.
# -DryRun runs the gate once and prints "RUN <prompt>" or "IDLE <reason>" (plus "PRESTAGE", "SESSION <id>", "MODE",
# "ARGS" and "RULES"), and launches nothing and stages nothing.
# -MaxRuns counts launches AND pre-stage bounces (a unit of runner work that cost no launch), so a self-test with a
# not-red grader ends.
# STREAM_RUNNER_AI and STREAM_RUNNER_CLAUDE override the ai launcher and the claude command (a self-test points them at
# stubs; a .ps1 is run with pwsh).
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [ValidateSet('author', 'build', 'integrate', 'plan', 'status', 'kit', 'coordinator')] [string] $Role,
    [switch] $Live,
    [switch] $Remote,
    [switch] $Stream,
    [int] $IntervalSeconds = 0,
    [int] $UnitTimeoutSeconds = 0,
    [int] $ResultGraceSeconds = 120,
    [int] $LaunchCheckMinutes = 60,
    [string] $Model = '',
    [int] $MaxRuns = 0,
    [string] $Tab = '',
    [switch] $DryRun,
    [switch] $NoPreStage
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
if ($Live -and $Stream) { 'REFUSED -Live and -Stream are separate modes; pick one'; exit 2 }
if ($Remote -and -not $Live) { 'REFUSED -Remote turns Remote Control on for a -Live unit; add -Live'; exit 2 }
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$mode = if ($Live) { 'live' } elseif ($Stream) { 'stream' } else { 'print' }

# author and build: the FALLBACK gate re-check while the runner watches the board files (Wait-ForBoardChange); a write
# to tasks.json or the role's inbox re-checks the gate within seconds whatever this says.
$defaults = @{ author = 300; build = 300; integrate = 600; plan = 600; kit = 600; status = 900; coordinator = 1200 }
if ($IntervalSeconds -le 0) { $IntervalSeconds = $defaults[$Role] }
# A build unit is limited to 90 minutes, not the 45-minute build CLAIM limit: the claim limit is about beats, and a
# live unit beats. A build with two verifier rounds outruns 45 minutes, and on 2026-10-04 units were killed mid-build at
# 2700 s (G3.T162, kit item IN-20261004205649-446f).
$unitLimits = @{ author = 1800; build = 5400; integrate = 1200; plan = 1200; kit = 1200; status = 1200; coordinator = 1200 }
if ($UnitTimeoutSeconds -le 0) { $UnitTimeoutSeconds = $unitLimits[$Role] }
$exitGrace = [Math]::Max(1, $ResultGraceSeconds)
$gated = $Role -in @('author', 'build')
# Timed roles with a GATE (owner ruling 2026-10-17, token review): integrate, plan, kit and coordinator launch a Claude
# unit only when a script finds work (Get-TimedGate); status is a pure script tick (Invoke-StatusTick) and launches a
# unit only for an open inbox item. Before this every interval launched a unit to find nothing, about $115 a day.
$timedGated = $Role -in @('integrate', 'plan', 'kit', 'coordinator')
$statusTick = $Role -eq 'status'
$skill = @{ author = 'stream-author'; build = 'stream-build'; integrate = 'stream-integrate'; plan = 'stream-plan'
    status = 'stream-status'; kit = 'stream-kit'; coordinator = 'stream-coordinator' }[$Role]
# The inbox this role is woken by and works. The coordinator has no inbox of its own: it works the kit inbox
# (stream-coordinator SKILL.md) and stands in for plan, so its gate reads stream-kit and stream-plan (Get-TimedGate).
$inboxSkill = if ($Role -eq 'coordinator') { 'stream-kit' } else { $skill }
$command = @{
    author      = "/stream-author once repo: $Repo"
    build       = "/stream-build once repo: $Repo"
    integrate   = "/stream-integrate once repo: $Repo"
    plan        = "/stream-plan inbox repo: $Repo"
    status      = "/stream-status inbox repo: $Repo"   # the tick itself is scripts (Invoke-StatusTick); the unit works the inbox only
    kit         = "/stream-kit inbox repo: $Repo"
    coordinator = "/stream-coordinator once repo: $Repo"
}[$Role]
$idPrefix = @{ author = 'author'; build = 'build'; integrate = 'integ'; plan = 'plan'; status = 'status'; kit = 'kit'; coordinator = 'coord' }[$Role]
$runnerId = New-SessionId "runner-$Role"
$tabToken = if ($Tab) { ($Tab -replace '[^A-Za-z0-9]+', '_').Trim('_') } else { '' }
$stableSession = New-SessionId $idPrefix
$lessonsFile = Join-Path $P.Root "lessons\$Role.md"
$modDir = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\mods\stream-unit'))
$preStage = $gated -and -not $NoPreStage
$unitsDir = Join-Path $P.Root 'units'

# $Packet is the pre-stage result for this unit (Invoke-PreStage), or $null for a unit that does its own plumbing.
function Get-RunnerRules([string] $Session, $Packet = $null, $Cfg = $null) {
    $addLesson = "Add a lesson only for something a later unit of this role needs and cannot read from .streams\: pwsh -NoProfile -File `"$PSScriptRoot\Add-Lesson.ps1`" -Repo `"$Repo`" -Role $Role -Session $Session -Task <task id> -Text `"<one line>`". Never put ticket detail or a secret in it."
    $rules = @(
        "STREAM RUNNER UNIT. This is a fresh, unattended session started by Start-StreamRunner.ps1$(if ($Live) { '; the owner may be watching it live' + $(if ($Remote) { ' or through Remote Control' }) + ', but nobody will answer a question' } else { '; nobody is watching it' })."
        "Your session id is $Session. Use exactly this id wherever the skill asks for one; do not mint another."
    )
    if ($Packet) {
        $what = if ($Packet.task) { "task $($Packet.task): its claim is HELD BY YOUR SESSION (Claim-Task.ps1 ran in your name)" } else { "inbox item $($Packet.item): it is TAKEN IN YOUR NAME (Set-InboxItem.ps1 -Status taken ran for you); close it with -Status done or declined -By $Session when the work is finished" }
        $rules += "YOUR WORK IS PRE-STAGED. The runner already did the skill's inbox, lessons and claim steps, so SKIP THEM. Your work is $what. Read the packet FIRST: $($Packet.packet). It holds the row as task.json, the lessons of this role, the held item, requirement excerpts$(if ($Role -eq 'build') { ', the worktree path, the kept-patch restore result and the author-grader RED result' }). Do not list the inbox, do not read the lessons file, do not run Claim-Task.ps1, do not take or claim anything else in this unit: ONE item or ONE row per unit, and the runner starts the next unit the moment this one ends. The runner chose this row under the owner's focus rule (lib\Streams.ps1 Get-Claimable): a lesson or a note never vetoes it. $addLesson"
    } else {
        $rules += "Before you claim or take any work, read the role's lessons file $lessonsFile when it exists: one lesson per line from earlier units of this role. $addLesson"
    }
    $rules += @(
        "Run ONE cycle of the skill. Never call ScheduleWakeup, CronCreate or /loop: the runner starts the next cycle in a new session."
        "Never end your turn while work you started is still running inside this session: the process exits when the unit ends and its background tasks die with it. Wait for a background command with Monitor, or run it in the foreground."
        "A command that must outlive this session (an integrator suite or build through Invoke-IntegratorRun.ps1, a patch drain) is started DETACHED: Start-Process pwsh -WindowStyle Hidden -ArgumentList '-NoProfile','-File',<script>,<args> with its output in a .streams\logs file. Record the log path in the task history or decisions.md, so the next cycle polls it instead of starting a second run."
        "Never use AskUserQuestion; take the recommended option as the skill says."
        "Stop ONLY processes this unit started, by the PID it recorded (Start-Process -PassThru then Stop-Process -Id; taskkill /PID). NEVER by name or command-line pattern (pkill, killall, pgrep | kill, taskkill /IM or /FI, Stop-Process -Name, Get-Process <name> | Stop-Process, wmic process where name=...): the host is shared, and such a kill takes other units' graders and the integrator's suites with it. A hung process you did not record is not yours: let the unit limit end it or name it in an inbox item."
        $(if ($Cfg -and $Cfg.subagentModel) { $alias = Get-AgentModelAlias $Cfg.subagentModel; if ($alias) { "MODEL CONFIGURATION (.streams\config.json): every Agent call in this unit (the skeptic, the verifier, any other subagent) is launched with model: `"$alias`", whatever the skill text names (the Agent tool takes only sonnet, opus, haiku or fable; the configured $($Cfg.subagentModel) reaches the subagent through the environment); the owner changes it in that file." } else { "MODEL CONFIGURATION (.streams\config.json): every Agent call in this unit is launched with NO model field, whatever the skill text names: the configured $($Cfg.subagentModel) reaches the subagent through the environment, and the Agent tool takes only sonnet, opus, haiku or fable; the owner changes it in that file." } } else { "MODEL CONFIGURATION (.streams\config.json): subagents use the model the skill names; the owner can set roles.$Role.subagentModel in that file." })
        "This unit is ended at $UnitTimeoutSeconds s wall clock ($([int]($UnitTimeoutSeconds / 60)) min), finished or not. Before you start an inbox item or task, judge whether it fits well inside that. If it does not, do a part that fits and send the rest as CONTINUATION items (Send-InboxItem.ps1, naming exactly what is left), then close yours with what you did. Every beat note on a held item says what is DONE so far (ids or files), not just what you are doing, so a holder cut off at the limit leaves a trail the next one continues from."
    )
    if ($Live) {
        $rules += "END OF THE UNIT: when every result of this cycle is written under .streams\ (task state, inbox items, history), call the tool mcp__stream-unit__unit_done exactly once with outcome built | ticketed | planned | integrated | done | idle | blocked | failed and a one-line note, then end your turn with one short line. The session exits by itself; do not call anything after unit_done."
    } else {
        $rules += "When the cycle is done, end your turn. Your LAST line is exactly 'UNIT-OUTCOME: <outcome>', one of built | ticketed | planned | integrated | done | idle | blocked | failed ('idle' when the cycle found nothing to do); the runner reads it to pace the next unit."
    }
    $rules -join "`n"
}

# The gate for the work roles: an actionable inbox item, or the claim's own selector (lib\Streams.ps1 Get-Claimable),
# read without the lock. Before 2026-10-05 the author half re-implemented the claim loosely: it counted gate-kind rows
# the claim never offers and every released group, so an author unit launched into NONE at $0.55 while the "G3 only"
# rule lived in a lessons file (2026-10-05 priority-focus-design E1).
# The open items of the role's inbox this role may act on now, oldest first. An author or build item about a row
# outside the focus set (filed with -Force, or before the focus rule) is not work this role may do now: it launches no
# paid unit (final review M9, the Send-InboxItem.ps1 NOT-FOCUS rule).
function Get-ActionableInboxItems($doc) {
    $open = @(Read-InboxItems (Get-InboxPath $P $inboxSkill) | Where-Object { Test-InboxOpen $_ $inboxSkill })
    if ($Role -in @('author', 'build')) {
        $fs = Get-FocusSet $doc
        $known = [Collections.Generic.HashSet[string]]::new(); foreach ($t in $doc.tasks) { [void]$known.Add([string]$t.id) }
        # SPILL TICKET (2026-10-12): an author spilled this row outside the focus, so an author fixes its ticket outside
        # the focus too. Builders never spill, so their items about it still wait for its group.
        $spilled = [Collections.Generic.HashSet[string]]::new()
        if ($Role -eq 'author') { foreach ($t in $doc.tasks) { if ($t -is [Collections.IDictionary] -and $t.Contains('spill') -and $t['spill'] -and [string]$t.state -in @('planned', 'ticketing', 'ticketed')) { [void]$spilled.Add([string]$t.id) } } }
        # An item naming no row, or a row not on the board, is kept: nothing says it is frozen.
        $open = @($open | Where-Object { -not $_.task -or $_.task -eq '-' -or -not $known.Contains([string]$_.task) -or $fs.Contains([string]$_.task) -or $spilled.Contains([string]$_.task) })
    }
    $open
}

function Get-WorkGate {
    $doc = Read-Tasks $P
    $open = @(Get-ActionableInboxItems $doc)
    if ($open.Count -gt 0) { return "inbox $($open.Count) actionable ($($open[0].id))" }
    $cl = Get-Claimable $P $doc $Role
    # The row named is the one the claim takes (lib Get-ClaimOrder), not Get-Claimable's board order (kit item IN-20261024221545-7b45).
    if ($cl.ids.Count -gt 0) { $first = @(Get-ClaimOrder $P $doc $Role $cl.rows)[0].id; return "$(if ($Role -eq 'build') { 'claimable' } else { 'planned' }) $($cl.ids.Count) ($first) focus $($cl.focusGroup) ($($cl.focusSource))$(if ($cl['spill']) { ' AUTHOR SPILL outside focus' })" }
    $null
}

# A gated runner with nothing to take WATCHES instead of sleeping: a stat of tasks.json and the role's inbox file every
# 5 s, and the gate runs again when either is written (a claim released, a row ticketed, an item filed) or after
# -IntervalSeconds, whichever comes first. A stale claim expires by time alone, but the watchdog frees it with a write,
# so the fallback is rarely what wakes the runner. Checks are at least 10 s apart: every live unit beats tasks.json
# every 30 s. Returns 'change', 'interval' or 'stop'.
function Wait-ForBoardChange {
    # Roles whose gate reads the board (a claimable or built row) watch tasks.json too; plan, kit and coordinator are
    # woken by their inbox alone (every live unit beats tasks.json every 30 s, which is no news to them).
    $files = @(if ($script:watchTasks) { $P.Tasks }; (Get-InboxPath $P $inboxSkill); if ($Role -eq 'coordinator') { Get-InboxPath $P 'stream-plan' })
    $stamp = { (@($files | ForEach-Object { if (Test-Path -LiteralPath $_) { (Get-Item -LiteralPath $_).LastWriteTimeUtc.Ticks } else { 0 } })) -join ',' }
    $before = & $stamp
    $deadline = (Get-Date).AddSeconds($IntervalSeconds)
    $floor = (Get-Date).AddSeconds(10)
    while ((Get-Date) -lt $deadline) {
        $left = ($deadline - (Get-Date)).TotalMilliseconds
        Start-Sleep -Milliseconds ([int][Math]::Max(100, [Math]::Min(5000, $left)))
        if (Test-StopRequested) { return 'stop' }
        if (Test-WakeRequested) { return 'wake' }
        if ((Get-Date) -ge $floor -and (& $stamp) -ne $before) { return 'change' }
    }
    'interval'
}

# ---- IDLE REPORT (owner request 2026-10-17: an idle work runner's tab said only "IDLE nothing to take; watching
# tasks.json and the inbox", once, and then nothing for hours). While a work runner polls it shows, with no model call:
# the priorities it is offered (the focus groups in the owner's order, and the released groups), WHY no row is
# claimable right now (from Get-Claimable, the gate's own selector, so the two never disagree), what its last unit did
# (session, outcome, row or item, minutes, cost), this runner's tally since it started, and when it looks again. The
# whole block is printed when the runner turns idle and whenever the reason changes; between those, one line every
# -IntervalSeconds. The same block follows IDLE in -DryRun. The tab reads '<tab> - idle' until the next launch.
$script:runnerStarted = (Get-Date).ToUniversalTime()
$script:lastUnit = $null
$script:tally = [ordered]@{ units = 0; cost = 0.0; outcomes = [ordered]@{} }
$script:idleSince = $null; $script:idleLastWhy = $null; $script:idleLastPrint = $null
function Get-WaitingDeps($doc, $Task) {
    $open = @(foreach ($d in @($Task.dependsOn)) { if (-not $d) { continue }; $dt = Get-Task $doc $d; if ($dt.state -notin $script:BuildReadyStates) { "$d [$($dt.state)]" } })
    if ($open.Count) { $open -join ', ' } else { 'a built dependency whose own base is no longer whole' }
}
# Idle report clock times carry the local zone (owner ruling 2026-10-18: owner-facing times in local machine time).
function Format-Local([datetime] $Utc) { Format-LocalStamp ([datetime]::SpecifyKind($Utc, [DateTimeKind]::Utc)) 'HH:mm:ss' }
# TAB LINES IN PLAIN WORDS (owner 2026-10-17: "This is cryptic ... it should also show the next time it will poll").
# Every line the tab prints starts with LOCAL time (the idle report already spoke local time, so one tab showed two
# clocks), each code line (GATE, START-JITTER, EXIT ... FAILED, BACKOFF) is followed by an indented line saying what it
# means, and every wait says the clock time of the next look. The codes stay first on their line: the suites and the
# owner grep for them.
function Get-TabNow { (Get-Date).ToString('HH:mm:ss') }
function Get-TabAt([int] $Seconds) { (Get-Date).AddSeconds($Seconds).ToString('HH:mm:ss') }
function Get-GatePlain([string] $Why) {
    switch -Regex ($Why) {
        '^claimable (\d+) \(([^)]+)\)' { return "$($Matches[1]) ticketed row(s) are ready to build; this runner claims the first ($($Matches[2])) and starts a build session" }
        '^planned (\d+) \(([^)]+)\)' { return "$($Matches[1]) planned row(s) need a ticket; this runner claims the first ($($Matches[2])) and starts an author session" }
        '^inbox (\d+) actionable \(([^)]+)\)' { return "$($Matches[1]) open $inboxSkill inbox item(s); a session works them, $($Matches[2]) first" }
        '^built (\d+) \(([^)]+)\)' { return "$($Matches[1]) built row(s) wait to be applied to main; a session integrates them, $($Matches[2]) first" }
        '^group .* integrating' { return 'a group is in its integration phase (suites, fix tasks, close); a session drives it' }
        '^integrator lock live' { return "this integrator's own run is still in flight; a session follows it up" }
        '^stands in for' { return 'nobody is serving that inbox, so the coordinator stands in' }
        '^free RAM' { return 'the machine is low on memory; the coordinator checks what to stop' }
        '^status flags changed' { return 'the status page raised new flags; the coordinator reviews them' }
        '^periodic review' { return 'scheduled review of the whole board' }
        '^first review' { return 'first review since this runner started' }
        default { return 'work found; starting a session' }
    }
}
function Get-IdleReport {
    $doc = Read-Tasks $P
    $fg = Get-FocusGroups $doc $P
    $released = @($doc.groups | Where-Object { $_.state -in @('released', 'integrating') } | ForEach-Object { [string]$_.id })
    # A timed role's reasons come from its gate (Get-TimedGate sets $script:timedWhy on every pass that found nothing).
    if (-not $gated) { return New-IdleReport $fg $released $(if (@($script:timedWhy).Count) { @($script:timedWhy) } else { @('nothing to take') }) }
    $cl = Get-Claimable $P $doc $Role
    $want = @{ author = 'planned'; build = 'ticketed' }[$Role]
    $kinds = if ($Role -eq 'author') { @('code', 'mockup', 'docs', 'integration') } else { $script:BuildKinds }
    $cands = @($doc.tasks | Where-Object { $_.state -eq $want -and $_.kind -in $kinds })
    $focusSet = Get-FocusSet $doc $P
    $inFocus = @($cands | Where-Object { $focusSet.Contains([string]$_.id) }).Count
    $who = if ($Role -eq 'author') { 'authors' } else { 'builders' }
    # A build claim moves its row to 'building', so a row another builder holds is never a 'ticketed' candidate; name
    # those rows too, so the idle runner says what the live builders are on. (An author claim keeps its row 'planned'
    # and Get-Claimable counts it as 'claimed'.)
    # @( ) around the whole if: an if-expression's one-element output unrolls to a scalar.
    $inFlight = @(if ($Role -eq 'build') { $doc.tasks | Where-Object { $_.state -eq 'building' -and $_.kind -in $kinds -and (Test-ClaimLive $_) } | ForEach-Object { [string]$_.id } })
    $why = [Collections.Generic.List[string]]::new()
    if ($cands.Count -eq 0) { $why.Add("no $want $(if ($Role -eq 'author') { 'row' } else { 'build row' }) anywhere on the board$(if ($Role -eq 'build') { ': waiting for an author to ticket one' })") }
    else {
        $parts = @()
        if ($cl.claimed) { $parts += "$($cl.claimed) claimed by live $who" }
        if ($cl.held) { $parts += "$($cl.held) held by an inbox item ($($cl.heldIds -join ', '))" }
        if ($cl.waiting.Count) { $parts += "$($cl.waiting.Count) waiting on dependencies ($((@($cl.waiting | Select-Object -First 3 | ForEach-Object { "$($_.id) needs $(Get-WaitingDeps $doc $_)" })) -join '; ')$(if ($cl.waiting.Count -gt 3) { '; ...' }))" }
        if ($cl.notReleased) { $parts += "$($cl.notReleased) in a group not released yet" }
        $why.Add("$want rows in the focus: $inFocus$(if ($parts.Count) { ', ' + ($parts -join ', ') } elseif ($inFocus) { ' (none passes the claim gates)' })")
        if ($cl.notFocus) { $why.Add("$($cl.notFocus) $want row(s) in other groups$(if ($Role -eq 'author') { ': the author spill found none free (claimed, held or in an unreleased group)' } else { ': builders take focus rows only' })") }
    }
    if ($inFlight.Count) { $why.Add("$($inFlight.Count) row(s) being built now by live builders ($(($inFlight | Select-Object -First 6) -join ', ')$(if ($inFlight.Count -gt 6) { ', ...' }))") }
    $open = @(Read-InboxItems (Get-InboxPath $P $inboxSkill) | Where-Object { Test-InboxOpen $_ $inboxSkill }).Count
    if ($open) { $why.Add("$open open item(s) in the $inboxSkill inbox, none actionable now (about rows outside the focus or already held)") }
    New-IdleReport $fg $released @($why)
}
function New-IdleReport($fg, $released, [string[]] $why) {
    [pscustomobject]@{
        Focus    = "focus $(if ($fg.groups.Count) { $fg.groups -join ' then ' } else { 'none: every group is closed' }) ($($fg.source)); released groups: $(if ($released.Count) { $released -join ' ' } else { 'none' })"
        Why      = @($why)
        Short    = $(if ($why.Count) { $why[0] } else { 'nothing to take' })
        LastUnit = $(if ($script:lastUnit) { $u = $script:lastUnit; "$($u.session) -> $($u.outcome)$(if ($u.task) { " $($u.task)" }) ($($u.minutes) min, `$$('{0:N2}' -f $u.cost), ended $(Format-Local $u.ended))" } else { 'none yet from this runner' })
        Tally    = $(if ($script:tally.units) { "$($script:tally.units) unit(s) since $(Format-Local $script:runnerStarted): $((@($script:tally.outcomes.GetEnumerator() | ForEach-Object { "$($_.Key) $($_.Value)" })) -join ', '); `$$('{0:N2}' -f $script:tally.cost)" } else { "no unit yet since $(Format-Local $script:runnerStarted)" })
    }
}
function Format-IdleReport($Rep, [datetime] $Fallback) {
    "  priorities : $($Rep.Focus)"
    $first = $true
    foreach ($w in $Rep.Why) { "  $(if ($first) { 'why idle   ' } else { '           ' }): $w"; $first = $false }
    "  last unit  : $($Rep.LastUnit)"
    "  this runner: $($Rep.Tally)"
    "  next look  : on any $(if ($script:watchTasks) { 'tasks.json or ' })$inboxSkill$(if ($Role -eq 'coordinator') { ' or stream-plan' }) inbox write (checked every 5 s), else at $(Format-Local $Fallback.ToUniversalTime()) ($IntervalSeconds s)"
}
# Called on every gate pass that found nothing. Prints the block on entering idle and on a changed reason, one line per
# -IntervalSeconds otherwise (the board is written every 30 s by live units' beats, so the gate re-runs that often).
function Show-IdleStatus {
    $now = Get-Date
    if (-not $script:idleSince) { $script:idleSince = $now }
    $rep = Get-IdleReport
    $key = $rep.Why -join '|'
    $fallback = $now.AddSeconds($IntervalSeconds)
    $state.idle = [ordered]@{ since = $script:idleSince.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); why = @($rep.Why); nextLook = $fallback.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); lastUnit = $rep.LastUnit; tally = $rep.Tally }
    if ($state.status -notlike 'idle since*') { $state.status = "idle since $(Format-LocalStamp)" }
    Write-RunnerState $state
    if ($key -ne $script:idleLastWhy -or -not $script:idleLastPrint) {
        "$(Get-TabNow) IDLE nothing to take for $Role$(if ($script:idleLastPrint) { " (reason changed; idle since $(Format-Local $script:idleSince.ToUniversalTime()))" })"
        Format-IdleReport $rep $fallback
        $script:idleLastWhy = $key; $script:idleLastPrint = $now
        if ($Tab) { Set-RunnerTabTitle "$Tab - idle" }
    } elseif (($now - $script:idleLastPrint).TotalSeconds -ge $IntervalSeconds) {
        "$(Get-TabNow) still idle since $(Format-Local $script:idleSince.ToUniversalTime()) ($([int]($now - $script:idleSince).TotalMinutes) min): $($rep.Short); next look by $(Format-Local $fallback.ToUniversalTime())"
        $script:idleLastPrint = $now
    }
}
function Clear-IdleStatus {
    if ($script:idleSince -and $Tab) { Set-RunnerTabTitle $Tab }
    $script:idleSince = $null; $script:idleLastWhy = $null; $script:idleLastPrint = $null
    if ($state.Contains('idle')) { $state.Remove('idle') }
}
# Remembers what the unit that just ended did, for the idle report and the runner state file.
function Record-Unit([string] $Session, $Packet, [string] $Outcome, $Res, $Code, [datetime] $StartUtc) {
    $f = { param($n) if ($Res -and $Res.PSObject.Properties[$n]) { $Res.$n } else { $null } }
    $o = if ($Outcome) { $Outcome } elseif ($null -ne $Code -and "$Code" -ne '0') { "exit $Code" } else { 'no outcome' }
    $what = if ($Packet -is [Collections.IDictionary]) { if ($Packet['task']) { [string]$Packet['task'] } elseif ($Packet['item']) { "item $($Packet['item'])" } else { '' } } else { '' }
    $cost = 0.0; [void][double]::TryParse([string](& $f 'total_cost_usd'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$cost)
    $script:lastUnit = [ordered]@{ session = $Session; outcome = $o; task = $what; cost = $cost; minutes = [int][Math]::Round(((Get-Date).ToUniversalTime() - $StartUtc).TotalMinutes); ended = (Get-Date).ToUniversalTime() }
    $script:tally.units++; $script:tally.cost += $cost
    $script:tally.outcomes[$o] = 1 + $(if ($script:tally.outcomes.Contains($o)) { [int]$script:tally.outcomes[$o] } else { 0 })
    $state.lastUnit = [ordered]@{ session = $Session; outcome = $o; task = $what; cost = $cost; minutes = $script:lastUnit.minutes; ended = $script:lastUnit.ended.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $state.tally = [ordered]@{ units = $script:tally.units; cost = [Math]::Round($script:tally.cost, 4); outcomes = $script:tally.outcomes }
}

# ---- TIMED-ROLE GATES (owner ruling 2026-10-17, token review). Before this the integrate, plan, kit and coordinator
# runners launched a Claude unit every interval whatever the board held: on the quiet night of 2026-10-16/17 those idle
# launches cost about $5 an hour ($115 a day) to find nothing. Each role now has a script gate, read without the lock,
# and launches only when the gate finds work; with nothing to take it shows the IDLE report and watches the board.
#   integrate   an actionable stream-integrate item; a built row in the focus set (Get-Claimable integrate, the drain's
#               own selector); a group 'integrating' (suites, fix tasks, close); or this session's own integrator lock
#               still beating (a detached run of its own is in flight and must be polled).
#   plan, kit   an actionable item in the role's inbox (plan still waits out a live planner).
#   coordinator an actionable stream-coordinator item; open stream-plan or stream-kit items with no live session of that
#               role (it stands in); the status page's flags changed since its last unit; free RAM below 6 GB; its
#               first unit after the runner started; or STREAM_COORDINATOR_REVIEW_SECONDS (7200) since its last unit.
$script:watchTasks = $Role -in @('author', 'build', 'integrate')
$script:timedWhy = @()
$script:lastTimedLaunch = $null
$script:flags = @{ hash = $null; last = $null; count = 0; first = ''; checkedAt = [datetime]::MinValue }
$script:coordinatorReviewSeconds = if ("$env:STREAM_COORDINATOR_REVIEW_SECONDS" -match '^\d+$') { [int]$env:STREAM_COORDINATOR_REVIEW_SECONDS } else { 7200 }
$script:coordinatorRamGb = 6.0

# A runner of $ForRole on this repo whose process is alive and whose state file was written inside 30 minutes (an idle
# runner rewrites it on every idle pass, a status runner on every tick). This runner's own file does not count.
function Test-LiveRunner([string] $ForRole) {
    $dir = Join-Path $P.Root 'runners'
    if (-not (Test-Path -LiteralPath $dir)) { return $false }
    foreach ($f in @(Get-ChildItem -LiteralPath $dir -Filter 'runner-*.json' -ErrorAction SilentlyContinue)) {
        if ($f.BaseName -eq $runnerId) { continue }
        $s = $null
        try { $s = Get-Content -LiteralPath $f.FullName -Raw | ConvertFrom-Json -AsHashtable } catch { continue }
        if (-not ($s -is [Collections.IDictionary]) -or [string]$s['role'] -ne $ForRole -or [string]$s['status'] -like 'stopped*') { continue }
        if (((Get-Date) - $f.LastWriteTime).TotalMinutes -gt 30) { continue }
        if ($s['pid'] -and -not (Get-Process -Id ([int]$s['pid']) -ErrorAction SilentlyContinue)) { continue }
        return $true
    }
    $false
}
# Free physical memory in GB (STREAM_RUNNER_FREE_RAM_GB overrides it for a self-test), or $null when unreadable.
function Get-FreeRamGb {
    if ("$env:STREAM_RUNNER_FREE_RAM_GB" -match '^\d+(\.\d+)?$') { return [double]$env:STREAM_RUNNER_FREE_RAM_GB }
    try { [Math]::Round(((Get-CimInstance Win32_OperatingSystem -ErrorAction Stop).FreePhysicalMemory / 1MB), 1) } catch { $null }
}
# The status page's flags (Get-StreamStatus.ps1 -Json, run in this process), read at most once per -IntervalSeconds.
# Returns @{ changed; count; first; hash }; changed is against the flags the coordinator last launched on (the first
# read is the baseline: the first launch is gated by 'first review').
function Get-StatusFlags {
    $now = Get-Date
    if ($null -ne $script:flags.last -and ($now - $script:flags.checkedAt).TotalSeconds -lt $IntervalSeconds) {
        return @{ changed = ($script:flags.last -ne $script:flags.hash); count = $script:flags.count; first = $script:flags.first; hash = $script:flags.last }
    }
    $script:flags.checkedAt = $now
    $list = @()
    try {
        $r = Invoke-KitScript 'Get-StreamStatus.ps1' @{ Repo = $Repo; Json = $true }
        $m = ($r.Text -join "`n") | ConvertFrom-Json -AsHashtable -Depth 20
        $list = @($m['flags'] | ForEach-Object { [string]$_ } | Where-Object { $_ } | Sort-Object)
    } catch { Write-Warning "FLAGS-UNREAD $(("$_" -split "`n")[0])" }
    $hash = if ($list.Count) { (Get-FileHash -InputStream ([IO.MemoryStream]::new([Text.Encoding]::UTF8.GetBytes(($list -join "`n")))) -Algorithm SHA256).Hash.Substring(0, 12) } else { 'none' }
    $script:flags.last = $hash; $script:flags.count = $list.Count; $script:flags.first = $(if ($list.Count) { $list[0] } else { '' })
    if ($null -eq $script:flags.hash) { $script:flags.hash = $hash }
    @{ changed = ($hash -ne $script:flags.hash); count = $list.Count; first = $script:flags.first; hash = $hash }
}
# The gate of a timed role: a reason string to launch now, or $null (and $script:timedWhy says why not, for the report).
function Get-TimedGate($doc) {
    $why = [Collections.Generic.List[string]]::new()
    if ($Role -ne 'coordinator') {
        # The coordinator reads the kit and plan inboxes with the owner's liveness rule below, not as its own.
        $open = @(Get-ActionableInboxItems $doc)
        if ($open.Count) { $script:timedWhy = @(); return "inbox $($open.Count) actionable ($($open[0].id))" }
        $why.Add("$inboxSkill inbox: no open item")
    }
    if ($Role -eq 'integrate') {
        $cl = Get-Claimable $P $doc 'integrate'
        if ($cl.ids.Count) { $script:timedWhy = @(); return "built $($cl.ids.Count) ($($cl.ids[0])) focus $($cl.focusGroup) ($($cl.focusSource))" }
        $integrating = @($doc.groups | Where-Object { [string]$_.state -eq 'integrating' } | ForEach-Object { [string]$_.id })
        if ($integrating.Count) { $script:timedWhy = @(); return "group $($integrating -join ', ') integrating (suites, fix tasks, close)" }
        if (Test-IntegratorLock $P $stableSession) {
            $beat = $null
            try { $beat = [datetime]::Parse([string](Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable)['beat'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) } catch { }
            if ($beat -and ((Get-Date).ToUniversalTime() - $beat).TotalMinutes -lt 20) { $script:timedWhy = @(); return "integrator lock live for $stableSession (a run of its own is in flight)" }
        }
        $why.Add("no built row in the focus set$(if ($cl.notFocus) { " ($($cl.notFocus) built row(s) in other groups wait for their group)" })")
        $why.Add('no group integrating')
    } elseif ($Role -eq 'coordinator') {
        foreach ($other in 'plan', 'kit') {
            $os = "stream-$other"
            $n = @(Read-InboxItems (Get-InboxPath $P $os) | Where-Object { Test-InboxOpen $_ $os }).Count
            $live = if ($other -eq 'plan') { [bool](Get-LivePlanner $stableSession) -or (Test-LiveRunner 'plan') } else { Test-LiveRunner 'kit' }
            if ($n -and -not $live) { $script:timedWhy = @(); return "stands in for $other : $n open $os item(s) and no live $other session" }
            $why.Add("$os : $n open item(s)$(if ($n) { ', its own session is live' })")
        }
        $gb = Get-FreeRamGb
        if ($null -ne $gb -and $gb -lt $script:coordinatorRamGb) { $script:timedWhy = @(); return "free RAM $gb GB below $($script:coordinatorRamGb) GB" }
        $fl = Get-StatusFlags
        if ($fl.changed) { $script:timedWhy = @(); return "status flags changed ($($fl.count))$(if ($fl.first) { ": $($fl.first)" })" }
        if (-not $script:lastTimedLaunch) { $script:timedWhy = @(); return 'first review since the runner started' }
        $since = ((Get-Date).ToUniversalTime() - $script:lastTimedLaunch).TotalSeconds
        if ($since -ge $script:coordinatorReviewSeconds) { $script:timedWhy = @(); return "periodic review ($([int]($since / 60)) min since the last unit)" }
        $why.Add("free RAM $(if ($null -ne $gb) { "$gb GB" } else { 'unknown' }); status flags unchanged ($($fl.count)); next periodic review at $(Format-Local $script:lastTimedLaunch.AddSeconds($script:coordinatorReviewSeconds))")
    }
    $script:timedWhy = @($why)
    $null
}
# A timed gate passed: the launch time and the coordinator's flag baseline move to now.
function Set-TimedLaunch { $script:lastTimedLaunch = (Get-Date).ToUniversalTime(); if ($null -ne $script:flags.last) { $script:flags.hash = $script:flags.last } }

# ---- STATUS TICK (owner ruling 2026-10-17, "status role becomes a pure PowerShell tick"). The status cycle's steps 2
# and 4 to 7 (stream-status SKILL.md) are scripts already: the watchdog, the terminal lines, the status, cost and
# priority pages, the daily archive and a focus group's activation. The runner runs them itself every -IntervalSeconds
# and prints ONE heartbeat line (STATUS-TICK; the owner's 2026-10-10 "report every tick" ruling, 2026-10-17 "the runner
# line is enough"), so a status tick costs no tokens. A Claude unit (/stream-status inbox) is launched only when the
# stream-status inbox has an open item. A step that fails is reported on the tick line and, once per script per runner,
# as a stream-kit bug item.
$script:ticks = 0
$script:tickFailures = @{}
$script:tickBusy = @{}
$tickBusyReport = if ("$env:STREAM_TICK_BUSY_REPORT" -match '^\d+$') { [Math]::Max(1, [int]$env:STREAM_TICK_BUSY_REPORT) } else { 3 }
function Invoke-TickStep([string] $Script, [hashtable] $ScriptArgs) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $r = $null
    try { $r = Invoke-KitScript $Script $ScriptArgs } catch { $r = [pscustomobject]@{ Text = @(("$_" -split "`n")[0]); Warnings = @(); Code = 'THREW' } }
    $ok = ($null -eq $r.Code -or "$($r.Code)" -eq '0')
    # A step that lost a lock race (tasks.json or an inbox held past its wait, or a file another process holds) is BUSY,
    # not broken: the next tick runs it again. A builder held tasks.json past the watchdog's 15 s on 2026-10-18 and the
    # tick filed it as a kit bug (kit item IN-20261018192923-9972).
    $busy = (-not $ok) -and ((@(@($r.Text) + @($r.Warnings)) -join "`n") -match 'lock busy for \d+s|being used by another process')
    [pscustomobject]@{ Script = $Script; Text = @($r.Text); Warnings = @($r.Warnings); Code = $r.Code; Ok = $ok; Busy = $busy; Seconds = [int]$sw.Elapsed.TotalSeconds }
}
function Get-TickNote($Step, [string] $Skipped = 'skipped') {
    if (-not $Step) { return $Skipped }
    if ($Step.Busy) { return 'BUSY (lock contention; the next tick retries)' }
    if (-not $Step.Ok) { return "FAILED exit $($Step.Code)" }
    $last = @($Step.Text | Where-Object { "$_".Trim() }) | Select-Object -Last 1
    $t = if ($last) { ("$last" -replace '\s+', ' ').Trim() } else { 'ok' }
    if ($t.Length -gt 100) { $t.Substring(0, 100) + '...' } else { $t }
}
# Every TICK-BUSY, TICK-FAILED and STATUS-TICK line also goes to .streams\logs\status-tick.log, so a session outside the
# runner's tab (the planner, the coordinator) can see what the last ticks did (kit item IN-20261023131800-4894).
function Write-TickLog([string] $Line) {
    try {
        $tl = Join-Path $P.Root 'logs\status-tick.log'
        if (-not (Test-Path -LiteralPath (Split-Path $tl))) { New-Item -ItemType Directory -Path (Split-Path $tl) -Force | Out-Null }
        Add-Content -LiteralPath $tl -Value $Line -Encoding utf8
    } catch { }
    $Line
}
function Invoke-StatusTick([string] $Session) {
    $sw = [Diagnostics.Stopwatch]::StartNew()
    $steps = [Collections.Generic.List[object]]::new()
    $wd = Invoke-TickStep 'Invoke-Watchdog.ps1' @{ Repo = $Repo; Session = $Session }; $steps.Add($wd)
    foreach ($l in $wd.Text) { "  watchdog  $l" }
    $acts = @($wd.Text | Where-Object { "$_".Trim() -and $_ -notmatch '^(QUIET|JUNK|WARN)\b' })
    $wdLine = if ($wd.Busy) { "Watchdog $(Get-TickNote $wd)." } elseif (-not $wd.Ok) { "Watchdog FAILED (exit $($wd.Code)): $(Get-TickNote $wd)" } elseif ($acts.Count) { "Watchdog: $($acts -join '; ')" } else { 'Watchdog QUIET: no stale claim.' }
    if ($wdLine.Length -gt 400) { $wdLine = $wdLine.Substring(0, 400) + '...' }
    $openItems = @(Read-InboxItems (Get-InboxPath $P $inboxSkill) | Where-Object { Test-InboxOpen $_ $inboxSkill })
    $inboxLine = if ($openItems.Count) { "Own inbox: $($openItems.Count) open item(s) ($((@($openItems | Select-Object -First 3 | ForEach-Object { $_.id })) -join ', ')); a status unit is launched for them." } else { 'Own inbox: no open items.' }
    $st = Invoke-TickStep 'Get-StreamStatus.ps1' @{ Repo = $Repo }; $steps.Add($st)
    foreach ($l in $st.Text) { "  $l" }
    $pg = Invoke-TickStep 'Build-StatusPage.ps1' @{ Repo = $Repo; Session = $Session; WatchdogLine = $wdLine; InboxLine = $inboxLine; NextUpdateSeconds = $IntervalSeconds }; $steps.Add($pg)
    $gc = Invoke-TickStep 'Get-StreamCost.ps1' @{ Repo = $Repo }; $steps.Add($gc)
    $cp = $null
    if ($gc.Ok) { $cp = Invoke-TickStep 'Build-CostPage.ps1' @{ Repo = $Repo; Session = $Session }; $steps.Add($cp) }
    $pr = Invoke-TickStep 'Build-PriorityPage.ps1' @{ Repo = $Repo; Session = $Session }; $steps.Add($pr)
    # Archive once a day (the first tick after 00:00 UTC; SKILL.md 6d). The day is kept beside the runner states, so a
    # restarted runner does not archive twice.
    $dayFile = Join-Path $P.Root 'runners\status-archive.day'
    $today = (Get-Date).ToUniversalTime().ToString('yyyy-MM-dd')
    $lastDay = if (Test-Path -LiteralPath $dayFile) { (Get-Content -LiteralPath $dayFile -Raw).Trim() } else { '' }
    $archiveNote = 'done today'
    if ($lastDay -ne $today) {
        $ar = Invoke-TickStep 'Archive-TaskHistory.ps1' @{ Repo = $Repo; Session = $Session }; $steps.Add($ar)
        if ($ar.Ok) { Write-AtomicText $dayFile $today }
        $archiveNote = Get-TickNote $ar
    }
    # A nightly Tier 2 that yielded and was never started again goes to the owner queue by 07:00 (kit item
    # IN-20261025145313-3448).
    $nightlyNote = try { Add-NightlyYieldNotice $P } catch { "FAILED: $(("$_" -split "`n")[0])" }
    # A focus group with no activation record is activated (Activate-Group.ps1: stale tickets back to planned, known
    # failures to fix tasks, owner gates up front), which the coordinator used to do when it happened to notice.
    $actNotes = @(); $freshNotes = @()
    try {
        $doc = Read-Tasks $P
        foreach ($g in @((Get-FocusGroups $doc $P).groups)) {
            if (-not (Test-Path -LiteralPath (Join-Path $P.Root "plans\$g.activation.json"))) {
                $ac = Invoke-TickStep 'Activate-Group.ps1' @{ Repo = $Repo; Session = $Session; Group = $g }; $steps.Add($ac)
                foreach ($l in $ac.Text) { "  activate  $l" }
                $actNotes += "$g $(Get-TickNote $ac)"
                continue
            }
            # An ACTIVE focus group gets the freshness check every tick (Activate-Group.ps1 -FreshnessOnly, 2026-10-18
            # dependency review F2): a ticketed row whose own files changed on main since it was ticketed goes back to
            # an author now, not when the group is next activated.
            $fr = Invoke-TickStep 'Activate-Group.ps1' @{ Repo = $Repo; Session = $Session; Group = $g; FreshnessOnly = $true }; $steps.Add($fr)
            foreach ($l in @($fr.Text | Where-Object { $_ -match '^(STALE|SKIP-CLAIMED|REVISE-FAILED|  )' })) { "  freshness $l" }
            $frLine = [string](@($fr.Text | Where-Object { $_ -like 'FRESHNESS *' }) | Select-Object -Last 1)
            if ($frLine -match 'stale (\d+) skipped (\d+)' -and ([int]$Matches[1] -gt 0 -or [int]$Matches[2] -gt 0)) { $freshNotes += "$g stale $($Matches[1]) skipped $($Matches[2])" }
            elseif (-not $fr.Ok) { $freshNotes += "$g $(Get-TickNote $fr)" }
        }
    } catch { $actNotes += "FAILED to read the board: $(("$_" -split "`n")[0])" }
    foreach ($s in $steps) {
        if ($s.Ok) { $script:tickBusy[$s.Script] = 0; continue }
        $detail = [string](@(@($s.Text) + @($s.Warnings) | Where-Object { "$_".Trim() }) | Select-Object -Last 1)
        if ($s.Busy) {
            # Lock contention files a bug only when it repeats on STREAM_TICK_BUSY_REPORT (3) ticks in a row: that is a
            # lock nobody lets go, not a slow holder.
            $script:tickBusy[$s.Script] = 1 + [int]$script:tickBusy[$s.Script]
            Write-TickLog "$(Get-TabNow) TICK-BUSY $($s.Script) ($($script:tickBusy[$s.Script]) in a row): $detail"
            if ($script:tickBusy[$s.Script] -lt $tickBusyReport) { continue }
        } else {
            Write-TickLog "$(Get-TabNow) TICK-FAILED $($s.Script) exit $($s.Code): $detail"
        }
        if (-not $script:tickFailures.ContainsKey($s.Script)) {
            $script:tickFailures[$s.Script] = Get-Now
            try { [void](Invoke-KitScript 'Send-InboxItem.ps1' @{ Repo = $Repo; To = 'stream-kit'; From = $Session; Kind = 'bug'; Ask = "$($s.Script) failed in the status runner's script tick (exit $($s.Code)): $(($detail -replace '\s+', ' ').Trim())"; Evidence = $logDir }) } catch { }
        }
    }
    $script:ticks++
    Write-TickLog "$(Get-TabNow) STATUS-TICK $Session $([int]$sw.Elapsed.TotalSeconds)s | $wdLine | $inboxLine | page: $(Get-TickNote $pg) | cost: $(Get-TickNote $cp) | priority: $(Get-TickNote $pr) | archive: $archiveNote | activation: $(if ($actNotes.Count) { $actNotes -join '; ' } else { 'none needed' }) | freshness: $(if ($freshNotes.Count) { $freshNotes -join '; ' } else { 'clean' }) | nightly: $nightlyNote | next tick at $(Get-TabAt $IntervalSeconds)"
    $state.lastTick = Get-Now; $state.ticks = $script:ticks
    $state.status = "ticked $(Format-LocalStamp); next tick in $IntervalSeconds s$(if ($openItems.Count) { "; $($openItems.Count) open inbox item(s): launching a unit" })"
    Write-RunnerState $state
    # The open count goes through a script variable, never the pipeline: every line this function prints IS its output,
    # so a caller that assigned the call would read the heartbeat and status lines as the count (recovery case STATUS TICK).
    $script:tickOpenCount = $openItems.Count
}
# The status runner's wait between ticks: -IntervalSeconds, cut short by a STOP file or a write to its inbox.
function Wait-ForTick([int] $Seconds) {
    $inboxFile = Get-InboxPath $P $inboxSkill
    $stamp = { if (Test-Path -LiteralPath $inboxFile) { (Get-Item -LiteralPath $inboxFile).LastWriteTimeUtc.Ticks } else { 0 } }
    $before = & $stamp
    $deadline = (Get-Date).AddSeconds($Seconds)
    while ((Get-Date) -lt $deadline) {
        $left = ($deadline - (Get-Date)).TotalMilliseconds
        Start-Sleep -Milliseconds ([int][Math]::Max(100, [Math]::Min(5000, $left)))
        if (Test-StopRequested) { return 'stop' }
        if (Test-WakeRequested) { return 'wake' }
        if ((& $stamp) -ne $before) { return 'inbox' }
    }
    'interval'
}

# ---- PRE-STAGE (2026-10-06 prestage-runner-design 3.2): the unit's plumbing, in this process, before any launch ----
# Kit scripts run in-process (as Invoke-Watchdog.ps1 runs Export-TaskPatch.ps1): `exit N` inside one ends that script
# and sets $LASTEXITCODE here. Output is captured whole (*>&1) so a warning (Claim-Task's held-row skips) reaches the
# packet and never the console alone. $ScriptArgs is a HASHTABLE (named splatting): an array splatted at a .ps1 passes
# '-Repo' as a positional VALUE, and the first run of this code put the repo path on -Role (recovery self-test, 10/6).
function Invoke-KitScript([string] $Name, [hashtable] $ScriptArgs) {
    $out = @(& "$PSScriptRoot\$Name" @ScriptArgs *>&1)
    $code = $LASTEXITCODE
    $text = @($out | Where-Object { $_ -is [string] })
    $warn = @($out | Where-Object { $_ -isnot [string] } | ForEach-Object { ("$_" -replace '\s+', ' ').Trim() } | Where-Object { $_ })
    [pscustomobject]@{ Text = $text; Warnings = $warn; Code = $code }
}

# Reads a field of the row the claim printed (a hashtable from ConvertFrom-Json -AsHashtable) without a StrictMode throw.
function Get-RowField($Row, [string] $Name) { if ($Row -is [Collections.IDictionary] -and $Row.Contains($Name)) { $Row[$Name] } else { $null } }
function Get-RowArtifact($Row, [string] $Name) { $a = Get-RowField $Row 'artifacts'; if ($a -is [Collections.IDictionary] -and $a.Contains($Name) -and $a[$Name]) { [string]$a[$Name] } else { '' } }

# Takes the oldest actionable item in the unit's name. ALREADY (exit 8: another unit took it first) moves to the next.
function Reserve-InboxItem([string] $Session, $doc) {
    foreach ($it in @(Get-ActionableInboxItems $doc)) {
        $r = Invoke-KitScript 'Set-InboxItem.ps1' @{ Repo = $Repo; Skill = $inboxSkill; Id = [string]$it.id; Status = 'taken'; By = $Session; Note = 'taken by the runner for this unit (pre-stage)' }
        if ($r.Code -eq 0) { return $it }
    }
    $null
}

# Requirement excerpts for an author: the lines of the board's requirement paths that name each `why` id, with four
# lines of context, as grep hits (the unit reads the file for the whole clause). Capped so the packet stays small.
function Get-RequirementExcerpts($doc, $Row) {
    $lines = [Collections.Generic.List[string]]::new()
    $why = @(Get-RowField $Row 'why'); if (-not $why.Count) { return $lines }
    $paths = @(if ($doc -is [Collections.IDictionary] -and $doc.Contains('requirements')) { $doc.requirements } elseif ($doc.PSObject.Properties['requirements']) { $doc.requirements })
    $files = [Collections.Generic.List[string]]::new()
    foreach ($p in $paths) {
        $full = if ([IO.Path]::IsPathRooted($p)) { $p } else { Join-Path $Repo $p }
        if (Test-Path -LiteralPath $full -PathType Container) { Get-ChildItem -LiteralPath $full -Recurse -File -Filter '*.md' -ErrorAction SilentlyContinue | ForEach-Object { $files.Add($_.FullName) } }
        elseif (Test-Path -LiteralPath $full -PathType Leaf) { $files.Add($full) }
    }
    if (-not $files.Count) { return $lines }
    $total = 0
    foreach ($id in $why) {
        $id = [string]$id; if (-not $id) { continue }
        $hits = @(Select-String -LiteralPath $files -SimpleMatch -Pattern $id -Context 0, 4 -ErrorAction SilentlyContinue | Select-Object -First 3)
        if (-not $hits.Count) { $lines.Add("### $id"); $lines.Add("(no line names $id under the requirement paths; read the ticket and the plan)"); continue }
        $lines.Add("### $id")
        foreach ($h in $hits) {
            $rel = $h.Path; if ($rel.StartsWith($Repo, [StringComparison]::OrdinalIgnoreCase)) { $rel = $rel.Substring($Repo.Length).TrimStart('\') }
            $lines.Add("``$rel`:$($h.LineNumber)``"); $lines.Add('```')
            $lines.Add($h.Line); foreach ($c in @($h.Context.PostContext)) { $lines.Add($c) }
            $lines.Add('```'); $total += 6
        }
        if ($total -gt 240) { $lines.Add('(more why ids: read them from the requirement paths)'); break }
    }
    $lines
}

# Writes .streams\units\<session>\task.json and unit.md and returns the unit.md path.
function Write-UnitPacket([string] $Session, $doc, $Row, $Item, [string[]] $Stage) {
    $dir = Join-Path $unitsDir $Session
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $md = [Collections.Generic.List[string]]::new()
    $md.Add("# Unit $Session ($Role)"); $md.Add('')
    $md.Add("Staged by Start-StreamRunner.ps1 ($runnerId) at $(Get-Now). This file is the unit's brief: the runner already did the inbox read, the lessons read and the claim$(if ($Role -eq 'build' -and $Row) { ', the worktree and the RED check' }). Do not repeat them; one item or one row per unit."); $md.Add('')
    if ($Item) {
        $md.Add("## Inbox item $($Item.id) (TAKEN in your name; close it with Set-InboxItem.ps1 -Skill $inboxSkill -Id $($Item.id) -By $Session -Status done|declined)"); $md.Add('')
        $md.Add("- From: $($Item.from) at $($Item.at); kind: $($Item.kind); task: $($Item.task)")
        $md.Add("- Ask: $($Item.ask)")
        $md.Add("- Evidence: $($Item.evidence)")
        $md.Add("- The item's row, when it names one, is NOT claimed: the skill's inbox step says how to work it (``Claim-Task.ps1 -Task <id>`` when the row must move).")
        $md.Add('')
    }
    if ($Row) {
        Write-AtomicText (Join-Path $dir 'task.json') (($Row | ConvertTo-Json -Depth 50) + "`n")
        $id = [string](Get-RowField $Row 'id')
        $md.Add("## Task $id (claim HELD by $Session; the row is task.json beside this file)"); $md.Add('')
        $md.Add("- Title: $(Get-RowField $Row 'title')")
        $md.Add("- Group $(Get-RowField $Row 'group'), kind $(Get-RowField $Row 'kind'), state $(Get-RowField $Row 'state'), estMinutes $(Get-RowField $Row 'estMinutes')")
        $md.Add("- Why: $(@(Get-RowField $Row 'why') -join ', ')")
        $md.Add("- Write set: $(@(Get-RowField $Row 'writeSet') -join ', ')")
        $md.Add("- Depends on: $(@(Get-RowField $Row 'dependsOn') -join ', ')")
        foreach ($k in @('ticket', 'grader', 'check', 'patch', 'red', 'verdict', 'testRecord')) { $v = Get-RowArtifact $Row $k; if ($v) { $md.Add("- artifacts.${k}: ``$v``") } }
        $hist = @(Get-RowField $Row 'history')
        if ($hist.Count) {
            $last = $hist[-1]
            $note = if ($last -is [Collections.IDictionary] -and $last.Contains('note')) { [string]$last['note'] } else { '' }
            $md.Add("- Latest history note: $note")
            if ($note -match 'STALE:') { $md.Add('- **REFRESH MODE** (stream-author step 2): the STALE note above names the files and the sha; update only the clauses and checks those changes touch.') }
        }
        $md.Add('')
        if ($Row -and $Role -eq 'author') {
            $ex = @(Get-RequirementExcerpts $doc $Row)
            if ($ex.Count) { $md.Add('## Requirement excerpts (grep hits for each why id; read the file for the whole clause)'); $md.Add(''); foreach ($l in $ex) { $md.Add($l) }; $md.Add('') }
        }
    }
    if ($Stage.Count) { $md.Add("## Pre-stage results (build steps 3, 3b and 4a, run by the runner)"); $md.Add(''); foreach ($l in $Stage) { $md.Add($l) }; $md.Add('') }
    $md.Add("## Lessons of this role ($lessonsFile)"); $md.Add('')
    if (Test-Path -LiteralPath $lessonsFile) { foreach ($l in @(Get-Content -LiteralPath $lessonsFile | Where-Object { $_.Trim() })) { $md.Add($l) } } else { $md.Add('(no lessons yet)') }
    $md.Add('')
    $path = Join-Path $dir 'unit.md'
    Write-AtomicText $path (($md -join "`n") + "`n")
    $path
}

# The build half of the pre-stage: worktree, author-grader RED on the fresh tree, kept patch, and a grade of a restored
# patch. Returns @{ ok; bounce; worktree; lines }. A row whose author grader is not red is sent back to planned here,
# with the evidence, and the unit is never launched (stream-build step 4a, moved into the runner).
function Invoke-BuildPreStage([string] $Session, $Row) {
    $id = [string](Get-RowField $Row 'id')
    $lines = [Collections.Generic.List[string]]::new()
    $r = @{ ok = $true; bounce = ''; worktree = ''; lines = $lines }
    $wt = Invoke-KitScript 'New-TaskWorktree.ps1' @{ Repo = $Repo; Task = $id; Session = $Session }
    $path = [string](@($wt.Text) | Select-Object -Last 1)
    if ($wt.Code -ne 0 -or -not $path -or -not (Test-Path -LiteralPath $path)) { $r.ok = $false; $r.bounce = "WORKTREE-FAILED $id : $(($wt.Text + $wt.Warnings) -join ' | ')"; return $r }
    $r.worktree = $path
    $lines.Add("- Step 3, worktree: ``$path`` (base laid and staged in its index; your change is exactly what is unstaged).")
    foreach ($w in $wt.Warnings) { $lines.Add("  - note: $w") }
    $grader = Get-RowArtifact $Row 'grader'; $red = Get-RowArtifact $Row 'red'
    if ($grader -and -not $red) {
        $g = Invoke-KitScript 'Invoke-Grader.ps1' @{ Repo = $Repo; Task = $id; Root = $path; Only = 'grader'; Label = 'red'; ExpectRed = $true; BeatSession = $Session; BeatTask = $id }
        $log = ".streams\logs\$id.grader.red.txt"
        $verdicts = @($g.Text | Where-Object { $_ -match '^(PASS|FAIL)\s' })
        if ($g.Code -eq 0) {
            [void](Invoke-KitScript 'Update-Task.ps1' @{ Repo = $Repo; Task = $id; Role = 'build'; Session = $Session; Beat = $true; Artifacts = @{ red = $log } })
            $lines.Add("- Step 4a, RED PROVED on the fresh tree: every clause of the author grader fails before any edit. Log ``$log`` (recorded as artifacts.red). Verdicts:")
            foreach ($v in $verdicts) { $lines.Add("    $v") }
        } elseif ($g.Code -eq 4) {
            $lines.Add("- Step 4a: NO-GRADER (artifacts.grader names a file that is not there); step 4b is yours.")
        } else {
            $why = if ($g.Code -eq 6) { 'NO-VERDICT: the grader produced no clause verdict (a parse error or a missing file, so it never ran)' } elseif ($g.Code -eq 8) { 'GRADER-TIMEOUT: the grader ran past its limit on the fresh tree and was ended with its process tree (a hung child, e.g. npx waiting on a package the worktree lacks); make it fail fast or bound its own waits' } else { 'NOT-RED: a clause passes before any edit, or fails for another reason' }
            $note = "builder RED refused (origin: runner pre-stage, IN-20261002160453-ce2a): $why - $((@($verdicts | Select-Object -First 6) + @($g.Text | Where-Object { $_ -match '^(NOT-RED|NO-VERDICT|GRADER)' } | Select-Object -First 2)) -join '; ') - evidence $log"
            $u = Invoke-KitScript 'Update-Task.ps1' @{ Repo = $Repo; Task = $id; Role = 'build'; Session = $Session; To = 'planned'; Release = $true; Artifacts = @{ red = $log }; Note = $note }
            $rm = Invoke-KitScript 'Remove-TaskWorktree.ps1' @{ Repo = $Repo; Session = $runnerId; Task = $id; Reason = 'runner pre-stage: the author grader is not red, row sent back to planned' }
            $r.ok = $false
            $r.bounce = "BOUNCE $id -> planned: $why; evidence $log; board $(($u.Text -join ' ')); worktree $(($rm.Text -join ' '))"
            return $r
        }
    } elseif ($grader) {
        $lines.Add("- Step 4a: RED is already on record (artifacts.red ``$red``); not re-run.")
    } else {
        $lines.Add('- Step 4a does not apply: the row has no author grader. Step 4b (your clause tests, RED before implementing) is yours.')
    }
    $rs = Invoke-KitScript 'Restore-TaskPatch.ps1' @{ Repo = $Repo; Task = $id; Worktree = $path }
    switch ($rs.Code) {
        0 {
            $lines.Add("- Step 3b, kept patch: APPLIED ($(($rs.Text -join ' '))). The earlier work is now this build's change.")
            $g2 = Invoke-KitScript 'Invoke-Grader.ps1' @{ Repo = $Repo; Task = $id; Root = $path; Label = 'wt'; BeatSession = $Session; BeatTask = $id }
            $v2 = @($g2.Text | Where-Object { $_ -match '^(PASS|FAIL)\s' })
            if ($g2.Code -eq 0) { $lines.Add("- Grade of the restored patch (``Invoke-Grader -Label wt``): PASS, exit 0. Go to step 6 (patch, test record) and verify; log ``.streams\logs\$id.grader.wt.txt``.") }
            elseif ($g2.Code -eq 4) { $lines.Add('- Grade of the restored patch: NO-GRADER (no check and no grader); write the check (step 4b) and continue at step 5.') }
            elseif ($g2.Code -eq 8) { $lines.Add("- Grade of the restored patch: GRADER-TIMEOUT, exit 8: it ran past its limit and was ended with its process tree, so there is no verdict. Find what the grader waits on (log ``.streams\logs\$id.grader.wt.txt``) before you grade again.") }
            else { $lines.Add("- Grade of the restored patch: FAIL, exit $($g2.Code). Continue at step 5 on top of it; log ``.streams\logs\$id.grader.wt.txt``. Verdicts:"); foreach ($v in $v2) { $lines.Add("    $v") } }
        }
        1 { $lines.Add('- Step 3b, kept patch: NO-PRIOR (the row has no earlier patch). Build from step 4b.') }
        2 { $lines.Add("- Step 3b, kept patch: CONFLICT, nothing applied ($(($rs.Text -join ' '))). Build from step 4b; the kept patch stays in .streams\patches\ for reference.") }
        default { $lines.Add("- Step 3b, kept patch: Restore-TaskPatch exit $($rs.Code): $(($rs.Text + $rs.Warnings) -join ' | ')") }
    }
    $r
}

# The whole pre-stage for one unit. Returns @{ packet; task; item; worktree; bounce; none; lines }: packet is the
# unit.md path when a unit should launch; bounce names a row sent back without a launch; none means a lost race
# (another unit took the item or the row between the gate and here) and nothing to do.
function Invoke-PreStage([string] $Session) {
    $lines = [Collections.Generic.List[string]]::new()
    $r = @{ packet = ''; task = ''; item = ''; worktree = ''; bounce = ''; none = ''; lines = $lines }
    $doc = Read-Tasks $P
    $item = Reserve-InboxItem $Session $doc
    if ($item) {
        $r.item = $item.id
        $ask = [string]$item.ask -replace '\s+', ' '; if ($ask.Length -gt 100) { $ask = $ask.Substring(0, 100) + '...' }
        $lines.Add("PRESTAGE $Session took inbox item $($item.id) ($($item.kind) from $($item.from): $ask)")
        $r.packet = Write-UnitPacket $Session $doc $null $item @()
        return $r
    }
    $c = Invoke-KitScript 'Claim-Task.ps1' @{ Repo = $Repo; Role = $Role; Session = $Session; NoIdleBeat = $true }
    $text = ($c.Text -join "`n").Trim()
    if ($c.Code -eq 6) { $r.none = "DISK $text"; return $r }
    if ($c.Code -ne 0 -or -not $text.StartsWith('{')) { $r.none = "NONE the claim found nothing ($(if ($text) { $text } else { "exit $($c.Code)" })): another unit took it first"; return $r }
    $row = $text | ConvertFrom-Json -AsHashtable -Depth 50
    $id = [string](Get-RowField $row 'id')
    $r.task = $id
    $lines.Add("PRESTAGE $Session claimed $id ($(Get-RowField $row 'kind'), group $(Get-RowField $row 'group'))$(if ($c.Warnings.Count) { ": $($c.Warnings -join '; ')" })")
    $stage = @()
    if ($Role -eq 'build') {
        $b = Invoke-BuildPreStage $Session $row
        foreach ($l in $b.lines) { $lines.Add("PRESTAGE $l") }
        $r.worktree = $b.worktree
        if (-not $b.ok) { $r.bounce = $b.bounce; return $r }
        $stage = @($b.lines)
    }
    $r.packet = Write-UnitPacket $Session $doc $row $null $stage
    $r
}

# Invoke-PreStage with its failure modes turned into runner lines: @{ Packet; Lines; Failed }. Packet is the record
# when a unit should launch; Failed is set when the pre-stage itself threw (the claim and any hold it made are released
# here, so a broken pre-stage never parks a row; the runner treats it as a failed run). A bounce counts as a run; a
# lost race does not.
function Invoke-PreStageGuarded([string] $Session) {
    $lines = [Collections.Generic.List[string]]::new()
    $g = [pscustomobject]@{ Packet = $null; Lines = $lines; Failed = ''; Busy = $false }
    $ps = $null
    try { $ps = Invoke-PreStage $Session } catch {
        $first = ("$_" -split "`n")[0]
        # A lock wait that timed out (tasks.json or an inbox) is contention, not a broken pre-stage: 16 runners restarted
        # together on 2026-10-10 and 10 of them lost the tasks.json race and backed off 900 s (kit item
        # IN-20261010172833-eff6). The caller retries it after a short jittered wait instead.
        # A file another process holds open ("being used by another process") is contention too: on 2026-10-14 three
        # pre-stages of G6.R1F2 threw on a grader log a stray MSBuild node held, and two builders sat out 900 s and
        # 1800 s backoffs beside 7 claimable rows (kit item IN-20261015040606-fb72).
        $g.Busy = $first -match 'lock busy for \d+s|being used by another process'
        $g.Failed = "$(if ($g.Busy) { 'PRESTAGE-BUSY' } else { 'PRESTAGE-FAILED' }) $Session : $first"
        $lines.Add($g.Failed)
        try { foreach ($f in @(Clear-SessionClaims $P $Session $runnerId "released by the runner: pre-stage of $Session failed")) { $lines.Add("RELEASED $f") } } catch { }
        try { foreach ($l in @(Open-UnitInboxHolds $P $Session (Get-Date).ToUniversalTime().AddMinutes(-5) 'pre-stage failed')) { $lines.Add($l) } } catch { }
        return $g
    }
    foreach ($l in $ps.lines) { $lines.Add($l) }
    if ($ps.bounce) {
        $lines.Add($ps.bounce)
        $state.runs++; $state.status = "bounced $($ps.task) at $(Get-Now)"; Write-RunnerState $state
        return $g
    }
    if (-not $ps.packet) { $lines.Add($ps.none); return $g }
    $g.Packet = $ps
    $g
}

# After a BUILD unit exits: a row this session still claims is a unit that died mid-build (a clean unit hands off or
# bounces and holds nothing). Its worktree is exported to a patch and attached while the claim is still live, before
# Clear-SessionClaims frees the row, so the next builder starts from the work instead of from scratch. A patch the row
# already carries is never overwritten (the watchdog's rule): the export goes beside it as <task>.salvage.patch. A tree
# written to in the last 30 s is left to the watchdog, which harvests under its own quiet period.
function Save-UnitWork([string] $Session, [string] $Task, [string] $Worktree, $ExitCode) {
    if (-not $Task -or -not $Worktree -or -not (Test-Path -LiteralPath $Worktree)) { return @() }
    $t = @((Read-Tasks $P).tasks | Where-Object { [string]$_.id -eq $Task })
    if (-not $t.Count -or -not $t[0].claim -or [string]$t[0].claim.session -ne $Session) { return @() }
    $newest = @(Get-ChildItem -LiteralPath $Worktree -Recurse -File -Force -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '[\\/]\.git([\\/]|$)' } | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    if ($newest.Count -and ((Get-Date).ToUniversalTime() - $newest[0].LastWriteTimeUtc).TotalSeconds -lt 30) { return @("HARVEST-SKIPPED $Task : $Worktree was written to in the last 30 s; the watchdog harvests it after its quiet period") }
    $existing = Join-Path $P.Patches "$Task.patch"
    $aside = Test-Path -LiteralPath $existing
    $outFile = if ($aside) { ".streams\patches\$Task.salvage.patch" } else { '' }
    $e = Invoke-KitScript 'Export-TaskPatch.ps1' @{ Repo = $Repo; Task = $Task; Worktree = $Worktree; OutFile = $outFile }
    $line = ($e.Text -join ' ')
    if ($line -match 'EMPTY no change') { return @("HARVEST-EMPTY $Task : the unit changed nothing in $Worktree") }
    if ($e.Code -ne 0 -or -not ($e.Text | Where-Object { $_ -like 'PATCH *' })) { return @("HARVEST-REFUSED $Task : $line (the tree stays; the watchdog reports it)") }
    if ($aside) {
        [void](Invoke-KitScript 'Update-Task.ps1' @{ Repo = $Repo; Task = $Task; Role = 'build'; Session = $Session; Note = "UNVERIFIED salvage of $Worktree written to $outFile by the runner: unit $Session ended ($ExitCode) mid-build. artifacts.patch is UNCHANGED (a handed-off patch); diff the two before using the salvage." })
        return @("HARVESTED-ASIDE $Task -> $outFile (UNVERIFIED; $Task.patch kept as the artifact)")
    }
    $rel = ".streams\patches\$Task.patch"
    [void](Invoke-KitScript 'Update-Task.ps1' @{ Repo = $Repo; Task = $Task; Role = 'build'; Session = $Session; Artifacts = @{ patch = $rel }; Note = "patch salvaged by the runner from $Worktree : unit $Session ended ($ExitCode) mid-build; the next build restores it (Restore-TaskPatch)" })
    @("HARVESTED $Task -> $rel (unit $Session ended $ExitCode mid-build)")
}

# One planner per repo: two planners editing one task was a real failure on 9/28 and again on 10/4 (b77). Another
# plan* session is live when it wrote task history, or holds or closed a stream-plan inbox item, inside the planner
# limit (30 min, the coordinator's rule). This runner's own session is never counted against itself. Measured on
# 2026-10-04: a planner silent for 10 h took three items at 13:36:23Z and a plan runner launched beside it 21 s later
# (kit item IN-20261004133725-ad1f).
function Get-LivePlanner([string] $Own) {
    $now = (Get-Date).ToUniversalTime(); $limit = 30
    $fresh = { param([string] $at) $at -and [int]($now - [datetime]::Parse($at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes -le $limit }
    foreach ($it in @(Read-InboxItems (Get-InboxPath $P 'stream-plan'))) {
        $by = [string]$it.statusBy
        if ($by -like 'plan*' -and $by -ne $Own -and (& $fresh $it.statusAt)) { return $by }
    }
    $doc = Read-Tasks $P
    foreach ($t in $doc.tasks) { foreach ($h in @($t.history)) {
        $by = [string]$h.by
        if ($by -like 'plan*' -and $by -ne $Own -and (& $fresh $h.at)) { return $by }
    } }
    $null
}

function Get-AiLauncher {
    if ($env:STREAM_RUNNER_AI) { return $env:STREAM_RUNNER_AI }
    [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\bin\ai.ps1'))
}

function Get-ClaudeCommand {
    if ($env:STREAM_RUNNER_CLAUDE) { return $env:STREAM_RUNNER_CLAUDE }
    $c = Get-Command claude -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($c) { return $c.Source }
    $null
}

# The launch check (see the header): ai.ps1 --version applies a changed install and starts nothing that lasts. Exit 2 =
# invalid machine config: REFUSED. Exit 3 = drift: ai starts on the previous install, so the runner goes on and says so.
# Any other non-zero = FAILED. After a good check, the environment ai would give claude is set in this process, so every
# claude the runner starts inherits it.
$script:lastLaunchCheck = [datetime]::MinValue

# Runs pwsh -NoProfile -File <script> <args> in a console of its own (hidden), output captured. A pwsh started in this
# console retitles it while it runs (elevated: 'Administrator: ...'), and in Windows Terminal the console title is the
# tab title, so the launch check renamed every runner tab it ran in (SMVMTR1 2026-10-05).
function Invoke-HiddenPwsh([string] $File, [string[]] $Arguments) {
    $psi = [Diagnostics.ProcessStartInfo]::new((Join-Path $PSHOME 'pwsh.exe'))
    foreach ($a in @('-NoProfile', '-File', $File) + @($Arguments)) { $psi.ArgumentList.Add($a) }
    $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $proc = [Diagnostics.Process]::Start($psi)
    $errTask = $proc.StandardError.ReadToEndAsync()
    $text = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()
    [pscustomobject]@{ Out = $text + $errTask.GetAwaiter().GetResult(); Code = $proc.ExitCode }
}

function Sync-LaunchEnvironment {
    if (((Get-Date) - $script:lastLaunchCheck).TotalMinutes -lt $LaunchCheckMinutes) { return 'CURRENT' }
    $ai = Get-AiLauncher
    if (-not (Test-Path -LiteralPath $ai)) { return "FAILED the ai launcher is not at $ai; run /machine-config apply" }
    $check = Invoke-HiddenPwsh $ai @('--version')
    $out = $check.Out; $code = $check.Code
    if ($code -eq 2) { return "REFUSED ai: the machine configuration is invalid: $(($out -replace '\s+', ' ').Trim())" }
    if ($code -ne 0 -and $code -ne 3) { return "FAILED ai exit $code`: $(($out -replace '\s+', ' ').Trim())" }
    $lib = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..\lib\MachineConfig.psm1'))
    if (Test-Path -LiteralPath $lib) {
        Import-Module $lib -Force -DisableNameChecking
        $prof = Get-AIMachineProfile
        $home2 = $prof.Keys['ClaudeHome']
        $sEnv = @{}
        $settings = Join-Path $home2 'settings.json'
        if (Test-Path -LiteralPath $settings) {
            $s = Get-Content -LiteralPath $settings -Raw | ConvertFrom-Json -AsHashtable -Depth 30
            if ($s.Contains('env') -and $s.env) { $sEnv = $s.env }
        }
        foreach ($name in @(Get-ChildItem Env: | Where-Object Name -like 'AI_*' | ForEach-Object Name)) {
            if ($name -in 'AI_MACHINE_CONFIG', 'AI_LAUNCH_REVISION' -or $name -like 'AI_TEST_*') { continue }
            if (-not $sEnv.Contains($name)) { Remove-Item -LiteralPath "Env:\$name" }
        }
        foreach ($k in $sEnv.Keys) { if ($k -like 'AI_*') { Set-Item -LiteralPath "Env:\$k" -Value ([string]$sEnv[$k]) } }
        if ($prof.Keys['ScratchRoot']) { $env:CLAUDE_CODE_TMPDIR = $prof.Keys['ScratchRoot'] }
        $statePath = Join-Path $home2 'machine-config.state.json'
        if (Test-Path -LiteralPath $statePath) {
            $st = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -AsHashtable -Depth 30
            $env:AI_LAUNCH_REVISION = [string]$st.identity
        }
    }
    $script:lastLaunchCheck = Get-Date
    if ($code -eq 3) { return 'DRIFT ai: installed files were edited outside the applicator; running on the previous install' }
    'CHECKED'
}

# claude's -p json result: the last line of the output that starts a JSON object, or under -Stream the last event of
# type result.
function ConvertFrom-RunnerOutput([string] $Raw) {
    try { return ($Raw | ConvertFrom-Json -ErrorAction Stop) } catch { }
    $lines = @($Raw -split "\r?\n")
    for ($i = $lines.Count - 1; $i -ge 0; $i--) {
        if ($lines[$i] -notmatch '^\s*\{') { continue }
        try { return (($lines[$i..($lines.Count - 1)] -join "`n") | ConvertFrom-Json -ErrorAction Stop) } catch { }
    }
    $null
}

# One short line per stream-json event worth seeing: the model's text, each tool call (name and a short input), each
# tool error, and the result. Everything else (system, partial chunks) prints nothing.
function Format-StreamEvent($Ev) {
    # Events carry only the fields they need, and StrictMode throws on a missing one, so every read goes through $get.
    $get = { param($o, $n) if ($null -ne $o -and $o.PSObject.Properties[$n]) { $o.$n } else { $null } }
    $clip = { param([string] $s, [int] $n) $s = ($s -replace '\s+', ' ').Trim(); if ($s.Length -gt $n) { $s.Substring(0, $n) + '...' } else { $s } }
    switch ([string](& $get $Ev 'type')) {
        'assistant' {
            foreach ($b in @(& $get (& $get $Ev 'message') 'content')) {
                if ((& $get $b 'type') -eq 'text' -and (& $get $b 'text')) { "  says  $(& $clip (& $get $b 'text') 160)" }
                elseif ((& $get $b 'type') -eq 'tool_use') {
                    $in = & $get $b 'input'
                    $brief = ''; foreach ($k in 'command', 'file_path', 'pattern', 'description') { $v = & $get $in $k; if ($v) { $brief = $v; break } }
                    if (-not $brief) { $brief = $in | ConvertTo-Json -Compress -Depth 3 }
                    "  tool  $(& $get $b 'name') $(& $clip ([string]$brief) 140)"
                }
            }
        }
        'user' {
            foreach ($b in @(& $get (& $get $Ev 'message') 'content')) {
                if ((& $get $b 'type') -eq 'tool_result' -and (& $get $b 'is_error')) { "  error $(& $clip ([string]((& $get $b 'content') | Out-String)) 160)" }
            }
        }
        'result' { "  result $(& $clip ([string](& $get $Ev 'result')) 160)" }
    }
}

function Test-AllClosed {
    $doc = Read-Tasks $P
    $g = @($doc.groups)
    $g.Count -gt 0 -and -not ($g | Where-Object { $_.state -ne 'closed' })
}

function Test-StopRequested {
    $dir = Join-Path $P.Root 'runners'
    (Test-Path (Join-Path $dir 'STOP')) -or (Test-Path (Join-Path $dir "STOP-$Role")) -or
        @(Get-OwnStopFile | Where-Object { Test-Path -LiteralPath $_ }).Count -gt 0
}

# An owner wake (Wake-StreamRunner.ps1; lib\Streams.ps1 Get-WakeRequest): WAKE, WAKE-<role> or WAKE-<runner id> written
# since this runner last acted on one. Every wait checks it; the main loop prints the WAKE line, resets the idle streak
# and the failure backoff, and a 'force' wake skips the gate once.
function Test-WakeRequested {
    $w = Get-WakeRequest $P $Role $runnerId $script:wakeSeen
    if (-not $w) { return $false }
    $script:wakeSeen = $w.ticks; $script:wakeHit = $w
    $true
}

# This runner's own stop files: STOP-<runner id>, and STOP-tab-<tab> under -Tab.
function Get-OwnStopFile {
    $dir = Join-Path $P.Root 'runners'
    Join-Path $dir "STOP-$runnerId"
    if ($tabToken) { Join-Path $dir "STOP-tab-$tabToken" }
}

function Write-RunnerState([hashtable] $State) {
    $dir = Join-Path $P.Root 'runners'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Write-AtomicText (Join-Path $dir "$runnerId.json") ($State | ConvertTo-Json -Depth 5)
}

# $Cmd is the unit's command (the role command, plus "packet: <unit.md>" for a pre-staged unit); $Cfg the role's
# model configuration (Get-RoleConfig): model and effort go on the command line, the rest as environment (Set-LaunchConfig).
# $ClaudeSession (-Live only) is the unit's Claude session UUID (--session-id), so the runner knows the transcript file
# to watch for a usage-limit rejection (Watch-UnitQuota).
function Get-CliArgs([string] $Session, [string] $RulesFile, [string] $Cmd = $command, $Cfg = $null, [string] $ClaudeSession = '') {
    if ($Live) {
        # Remote Control only on -Remote (owner 2026-10-20); it used to be on for every unit.
        $a = @(if ($Remote) { '--remote-control', $Session }) + @('--permission-mode', 'bypassPermissions', '-n', $Session,
            '--plugin-dir', $modDir, '--append-system-prompt-file', $RulesFile)
        if ($ClaudeSession) { $a += @('--session-id', $ClaudeSession) }
    } else {
        $fmt = if ($Stream) { @('--output-format', 'stream-json', '--verbose') } else { @('--output-format', 'json') }
        $a = @('-p', $Cmd, '--permission-mode', 'bypassPermissions', '--permission-prompts', 'none') + $fmt +
            @('-n', $Session, '--append-system-prompt-file', $RulesFile)
    }
    if ($Cfg -and $Cfg.model) { $a += @('--model', $Cfg.model) }
    if ($Cfg -and $Cfg.effort) { $a += @('--effort', $Cfg.effort) }
    if ($Live) { $a += $Cmd }
    $a
}

# ---- MODEL CONFIGURATION (owner ruling 2026-10-06: "configurable at all levels; update configuration and restart") ----
# .streams\config.json, read before EVERY unit (an edit takes effect at the next unit; a restart is never needed):
#   { "defaults": { model, subagentModel, effort, promptCacheTtl }, "roles": { author: {...}, build: {...}, ... } }
# model          : the unit's main-thread model alias or id (--model). '' = claude's own default.
# subagentModel  : the model the unit's Agent calls use (skeptic, verifier): CLAUDE_CODE_SUBAGENT_MODEL for the unit, and
#                  the rules tell the unit to put it on every Agent call; '' = the skill's own choice.
# effort         : --effort low|medium|high; '' = claude's default (medium).
# promptCacheTtl : CLAUDE_CODE_PROMPT_CACHE_TTL 5m|1h; '' = the account's default. 5m writes cost 1.25x input, 1h 2x;
#                  a unit whose calls are never more than 5 min apart pays less at 5m, one that waits on a long test
#                  misses the cache and re-writes its whole context.
# Precedence: the -Model switch, then roles.<role>, then defaults. The file is written with every field empty when it
# is missing, so the owner edits a file that already has the right shape.
function Get-RoleConfig {
    $file = Join-Path $P.Root 'config.json'
    $keys = @('model', 'subagentModel', 'effort', 'promptCacheTtl')
    $cfg = [ordered]@{ model = ''; subagentModel = ''; effort = ''; promptCacheTtl = ''; source = 'none'; note = '' }
    if (-not (Test-Path -LiteralPath $file) -and -not $DryRun) {
        $blank = { $o = [ordered]@{}; foreach ($k in $keys) { $o[$k] = '' }; $o }
        $roles = [ordered]@{}; foreach ($r in @('author', 'build', 'integrate', 'plan', 'status', 'kit', 'coordinator')) { $roles[$r] = & $blank }
        $doc = [ordered]@{
            _help = 'Owner configuration of the stream kit, read before every unit. focus.groups = the group(s) every work role is offered rows from, e.g. ["G4"] or ["G4","G6"]; empty = the first unclosed group in board order. Model fields: model = --model alias or id (opus, sonnet, haiku, or a full id); subagentModel = the model for Agent calls inside the unit (skeptic, verifier); effort = low|medium|high; promptCacheTtl = 5m|1h. Empty = the default. roles.<role> overrides defaults; the -Model switch overrides both.'
            focus = [ordered]@{ groups = @() }
            defaults = (& $blank); roles = $roles }
        try { Write-AtomicText $file (($doc | ConvertTo-Json -Depth 5) + "`n") } catch { }
    }
    $doc = $null
    try { $doc = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable -Depth 10 } catch { $cfg.source = "unreadable ($file)" }
    if ($doc) {
        $cfg.source = 'defaults'
        $d = if ($doc.Contains('defaults') -and $doc.defaults -is [Collections.IDictionary]) { $doc.defaults } else { @{} }
        $r = if ($doc.Contains('roles') -and $doc.roles -is [Collections.IDictionary] -and $doc.roles.Contains($Role) -and $doc.roles[$Role] -is [Collections.IDictionary]) { $doc.roles[$Role] } else { @{} }
        foreach ($k in $keys) {
            if ($d.Contains($k) -and $d[$k]) { $cfg[$k] = [string]$d[$k] }
            if ($r.Contains($k) -and $r[$k]) { $cfg[$k] = [string]$r[$k]; $cfg.source = "roles.$Role" }
        }
    }
    if ($Model) { $cfg.model = $Model; $cfg.source = "-Model ($($cfg.source))" }
    foreach ($k in @('effort', 'promptCacheTtl')) {
        $ok = if ($k -eq 'effort') { $cfg[$k] -in @('', 'low', 'medium', 'high') } else { $cfg[$k] -in @('', '5m', '1h') }
        if (-not $ok) { $cfg.note = "CONFIG-IGNORED $k '$($cfg[$k])' is not a value claude accepts; using the default"; $cfg[$k] = '' }
    }
    $cfg
}
# The environment half of the configuration, set for the unit's process and removed after it (Clear-LaunchConfig).
function Set-LaunchConfig($Cfg) {
    if ($Cfg.subagentModel) { $env:CLAUDE_CODE_SUBAGENT_MODEL = $Cfg.subagentModel }
    if ($Cfg.promptCacheTtl) { $env:CLAUDE_CODE_PROMPT_CACHE_TTL = $Cfg.promptCacheTtl }
}
# The value an Agent call may carry in its model field. The Agent tool takes ONLY the aliases sonnet, opus, haiku and
# fable: on 2026-10-08 every author unit configured with subagentModel "claude-opus-5-5" was told to pass that id, its
# skeptic call failed InputValidationError ('expected one of "sonnet"|"opus"|"haiku"|"fable"') and the unit had to
# retry. A full id maps to its family's alias; the exact id still reaches the subagent through
# CLAUDE_CODE_SUBAGENT_MODEL (Set-LaunchConfig). An id of no known family returns '' (omit the field).
$script:AgentModelAliases = @('sonnet', 'opus', 'haiku', 'fable')
function Get-AgentModelAlias([string] $Model) {
    $m = $Model.Trim().ToLowerInvariant()
    if (-not $m) { return '' }
    if ($m -in $script:AgentModelAliases) { return $m }
    foreach ($a in $script:AgentModelAliases) { if ($m -match "(^|[-._/:])$a([-._/:\[]|$)") { return $a } }
    ''
}
function Clear-LaunchConfig { Remove-Item Env:\CLAUDE_CODE_SUBAGENT_MODEL, Env:\CLAUDE_CODE_PROMPT_CACHE_TTL -ErrorAction SilentlyContinue }
function Format-Config($Cfg) { "model $(if ($Cfg.model) { $Cfg.model } else { 'default' }) subagents $(if ($Cfg.subagentModel) { $Cfg.subagentModel } else { 'skill choice' }) effort $(if ($Cfg.effort) { $Cfg.effort } else { 'default' }) cacheTtl $(if ($Cfg.promptCacheTtl) { $Cfg.promptCacheTtl } else { 'default' }) (from $($Cfg.source))" }

# The console as the runner left it, put back after every live unit. A session killed at its limit cannot restore what
# it changed: on 2026-10-04 a timed-out builder left its tab with Ctrl+C and every key dead (input mode without
# processed input, keyboard protocols still on). Saving the Win32 modes covers the first; the VT reset covers what the
# session asked of the terminal itself (alternate screen, hidden cursor, mouse, bracketed paste, focus, kitty keyboard,
# modifyOtherKeys). Neither applies when this runner's console is redirected (a self-test's thread job).
$script:ConsoleApi = $null
function Test-ConsoleApi {
    if ($null -eq $script:ConsoleApi) {
        $script:ConsoleApi = $false
        if ($IsWindows) {
            try {
                Add-Type -Namespace StreamKit -Name ConsoleMode -MemberDefinition @'
[DllImport("kernel32.dll", SetLastError = true)] public static extern IntPtr GetStdHandle(int n);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool GetConsoleMode(IntPtr h, out uint m);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool SetConsoleMode(IntPtr h, uint m);
[DllImport("kernel32.dll", SetLastError = true)] public static extern bool FlushConsoleInputBuffer(IntPtr h);
'@
                $script:ConsoleApi = $true
            } catch { }
        }
    }
    $script:ConsoleApi
}

function Save-ConsoleMode {
    $saved = @{}
    if (-not (Test-ConsoleApi)) { return $saved }
    foreach ($n in @(-10, -11)) {
        $m = [uint32]0
        if ([StreamKit.ConsoleMode]::GetConsoleMode([StreamKit.ConsoleMode]::GetStdHandle($n), [ref]$m)) { $saved[$n] = $m }
    }
    $saved
}

function Restore-ConsoleMode([hashtable] $Saved) {
    if (-not [Console]::IsOutputRedirected) {
        [Console]::Write("`e[0m`e[?25h`e[?1049l`e[?2004l`e[?1004l`e[?1000l`e[?1002l`e[?1003l`e[?1006l`e[<u`e[>4m`r`n")
    }
    if (-not $Saved.Count) { return }
    foreach ($n in @($Saved.Keys)) { [void][StreamKit.ConsoleMode]::SetConsoleMode([StreamKit.ConsoleMode]::GetStdHandle($n), $Saved[$n]) }
    if ($Saved.ContainsKey(-10)) { [void][StreamKit.ConsoleMode]::FlushConsoleInputBuffer([StreamKit.ConsoleMode]::GetStdHandle(-10)) }
}

# <unit result>.waiting.json, written by the stream-unit mod: @{ ok; w } where ok is false when the file was mid-write
# (keep the last answer) and w is the record while a permission prompt is open, else $null.
function Read-UnitWaiting([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return @{ ok = $true; w = $null } }
    try { $w = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { return @{ ok = $false; w = $null } }
    @{ ok = $true; w = $(if ($w -and $w.PSObject.Properties['waiting'] -and $w.waiting) { $w } else { $null }) }
}

# Runs a terminal CLI (a .ps1 stub through pwsh), output discarded: out of band, nothing drawn into the session's screen.
function Invoke-TerminalCli([string] $Exe, [string[]] $CliArgs) {
    try { if ($Exe -like '*.ps1') { $null = & pwsh -NoProfile -File $Exe @CliArgs 2>&1 } else { $null = & $Exe @CliArgs 2>&1 } } catch { }
}

# Retitles the terminal tab or block this runner runs in, and with -Needs raises (or with -Clear drops) a badge with
# the bell. Windows Terminal (WT_SESSION): the console title is the tab title; the owner's stream tabs set
# CLAUDE_CODE_DISABLE_TERMINAL_TITLE so the session does not overwrite it; the bell is Enter-OwnerWait's BEL. Wave
# Terminal: a shell block has WAVETERM_BLOCKID and wsh (frame:title, wsh badge). WezTerm: WEZTERM_PANE (set-tab-title).
# STREAM_RUNNER_TITLE_LOG (Windows Terminal), STREAM_RUNNER_WSH and STREAM_RUNNER_WEZTERM point a self-test at stubs.
$script:RunnerTabTitle = $null
function Set-RunnerTabTitle([string] $Title, [switch] $Needs, [switch] $Clear) {
    if ($env:WT_SESSION) {
        if ($env:STREAM_RUNNER_TITLE_LOG) { Add-Content -LiteralPath $env:STREAM_RUNNER_TITLE_LOG -Value $Title; return }
        $script:RunnerTabTitle = $Title
        try { [Console]::Title = $Title } catch { }
        return
    }
    if ($env:WAVETERM_BLOCKID) {
        $wsh = if ($env:STREAM_RUNNER_WSH) { $env:STREAM_RUNNER_WSH } else { Get-Command wsh -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object Source }
        if (-not $wsh) { return }
        Invoke-TerminalCli $wsh @('setmeta', '-b', 'this', "frame:title=$Title")
        if ($Needs) { Invoke-TerminalCli $wsh @('badge', 'bell', '--color', '#e5484d', '--beep') }
        if ($Clear) { Invoke-TerminalCli $wsh @('badge', '--clear') }
        return
    }
    $wz = if ($env:STREAM_RUNNER_WEZTERM) { $env:STREAM_RUNNER_WEZTERM } else { Get-Command wezterm -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1 | ForEach-Object Source }
    if (-not $wz -or -not $env:WEZTERM_PANE) { return }
    Invoke-TerminalCli $wz @('cli', '--no-auto-start', 'set-tab-title', '--pane-id', $env:WEZTERM_PANE, $Title)
}

# An elevated pwsh that exits in this console (the unit's hooks, this runner's own children) leaves the title as
# 'Administrator: <title>'; put the tab's title back whenever something else changed it (Windows Terminal only).
function Restore-RunnerTabTitle {
    if (-not $script:RunnerTabTitle -or -not $env:WT_SESSION -or $env:STREAM_RUNNER_TITLE_LOG) { return }
    try { if ([Console]::Title -ne $script:RunnerTabTitle) { [Console]::Title = $script:RunnerTabTitle } } catch { }
}

# A permission prompt opened in the unit: say so everywhere the owner looks without drawing over the dialog (the
# session owns the screen): the tab title, the bell, the runner state and one ESCALATE line in owner\permission-prompts.md. A prompt is not an owner question (owner
# 2026-10-25, kit item IN-20261025224420-209f): the status page counts that file as 'owner prompts' and the planner shows them in chat.
function Enter-OwnerWait($W, [string] $Session, [string] $Token) {
    $where = if ($Tab) { "tab $Tab" } else { "runner $runnerId" }
    $what = ("$($W.tool): $($W.reason)" -replace '\s+', ' ').Trim(' ', ':')
    if ($what.Length -gt 200) { $what = $what.Substring(0, 200) }
    $state.status = "waiting on owner since $(Get-Now): permission prompt ($what)"; Write-RunnerState $state
    Set-RunnerTabTitle "$(if ($Tab) { $Tab } else { $Session }) - NEEDS YOU" -Needs
    if (-not [Console]::IsOutputRedirected) { [Console]::Write([char]7) }
    try { Add-LineTo $P.Prompts "- ESCALATE $Session | permission prompt in $where : $what | the session waits on the owner; its unit timeout is paused | answer the prompt in that tab [$Token]" } catch { }
}

# The prompt was answered (or the unit ended): title back, and the queue line re-written in place as RESOLVED, the way
# the owner answers one by hand.
function Exit-OwnerWait([string] $Session, [string] $Token, [string] $How) {
    $state.status = "running $Session"; Write-RunnerState $state
    Set-RunnerTabTitle $(if ($Tab) { $Tab } else { $Session }) -Clear
    try {
        Invoke-IoRetry {
            if (-not (Test-Path -LiteralPath $P.Prompts)) { return }
            $lines = [IO.File]::ReadAllLines($P.Prompts)
            $hit = $false
            for ($i = 0; $i -lt $lines.Count; $i++) {
                if ($lines[$i] -like "- ESCALATE *``[$Token``]") { $lines[$i] = "RESOLVED $($lines[$i]) ($How $(Format-LocalStamp))"; $hit = $true }
            }
            if ($hit) { Write-AtomicText $P.Prompts (($lines -join "`n") + "`n") }
        }
    } catch { }
}

# Starts the interactive session in this console (no new window, no redirection: it draws its own UI here) and waits
# up to the unit limit. Time spent on an open permission prompt (<Out>.waiting.json says waiting) does not count: the
# session is waiting on the owner, not hung. Returns the exit code, 'TIMEOUT' after ending the session and everything
# it started, or 'RESULT-GRACE' when the session wrote its result (STREAM_UNIT_OUT) and was still running $exitGrace
# seconds later. The mod's /exit can be swallowed: a background-task notice arriving after it left two builders idle at
# the prompt until the build limit on 2026-10-04 (kit item IN-20261005013311-b5a0), so the result file, not the exit,
# ends a unit. The console modes are put back however it ends.
# A usage-limit rejection (the account's session or weekly quota, not a transient 429) leaves an interactive session
# idle at its prompt: on 2026-10-10 at 20:07Z four author units sat to their 1800 s TIMEOUT and then a 1800 s backoff,
# and a build unit sat 61 min without beats until the watchdog broke its claim (kit item IN-20261010205318-5308). So
# every $quotaCheckSeconds the loop reads what the unit's transcript (<projects>\*\<ClaudeSession>.jsonl) gained and ends
# the unit as 'USAGE-LIMIT' on a rejection line; $script:unitQuota then holds what Find-QuotaRejection found.
function Invoke-LiveUnit([string] $Claude, [string[]] $CliArgs, [string] $Out, [string] $Session, [string] $ClaudeSession = '') {
    $psi = [Diagnostics.ProcessStartInfo]::new()
    if ($Claude -like '*.ps1') {
        $psi.FileName = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
        foreach ($x in @('-NoProfile', '-File', $Claude)) { $psi.ArgumentList.Add($x) }
    } else { $psi.FileName = $Claude }
    foreach ($x in $CliArgs) { $psi.ArgumentList.Add($x) }
    $psi.UseShellExecute = $false
    $psi.WorkingDirectory = $Repo
    $saved = Save-ConsoleMode
    # Every pwsh started in this console (the launch check's 'pwsh ai.ps1 --version', elevated on SMVMTR1) retitles it
    # 'Administrator: <path>' (seen 2026-10-05), so the tab name is put back before each unit and again after it.
    if ($Tab) { Set-RunnerTabTitle $Tab }
    $waitFile = "$Out.waiting.json"
    $token = "prompt-$runnerId-$([IO.Path]::GetFileNameWithoutExtension($Out))"
    $waiting = $false
    $resultAt = $null
    $usedMs = [long]0
    $limitMs = [long]$UnitTimeoutSeconds * 1000
    $lastWaitBeat = $null
    $waitBeatEvery = if ($env:STREAM_BEAT_SECONDS) { [int]$env:STREAM_BEAT_SECONDS } else { 60 }
    $script:unitQuota = $null
    $tail = @{ path = $null; offset = [long]0; rest = ''; lastCheck = [datetime]::MinValue; started = Get-Date; warned = $false }
    try {
        $proc = [Diagnostics.Process]::Start($psi)
        $state.unitPid = $proc.Id; Write-RunnerState $state
        $clock = [Diagnostics.Stopwatch]::StartNew()
        while (-not $proc.WaitForExit(1000)) {
            Restore-RunnerTabTitle
            $tick = $clock.ElapsedMilliseconds; $clock.Restart()
            if (-not $waiting) { $usedMs += $tick }
            $r = Read-UnitWaiting $waitFile
            if ($r.ok) {
                if ($r.w -and -not $waiting) { $waiting = $true; Enter-OwnerWait $r.w $Session $token }
                elseif (-not $r.w -and $waiting) { $waiting = $false; Exit-OwnerWait $Session $token 'answered' }
            }
            # The unit timeout is paused while the owner owes an answer, so the unit's claims are kept fresh too: on
            # 2026-10-10 G4.T131's unit sat on a prompt from 09:14Z, its own beat loop had stopped, and the watchdog broke
            # the claim at 10:00Z with the session still waiting (kit item IN-20261010093355-b1d5).
            if ($waiting -and ((-not $lastWaitBeat) -or ((Get-Date) - $lastWaitBeat).TotalSeconds -ge $waitBeatEvery)) {
                $lastWaitBeat = Get-Date
                Update-WaitingClaims $Session
            }
            $end = $null
            if ($ClaudeSession -and ((Get-Date) - $tail.lastCheck).TotalSeconds -ge $quotaCheckSeconds) {
                $tail.lastCheck = Get-Date
                $hit = Watch-UnitQuota $tail $ClaudeSession
                if ($hit) { $script:unitQuota = $hit; $end = 'USAGE-LIMIT' }
            }
            if (-not $end -and -not $waiting -and $usedMs -ge $limitMs) { $end = 'TIMEOUT' }
            elseif (-not $end) {
                if (-not $resultAt -and (Test-UnitResult $Out)) { $resultAt = Get-Date }
                if ($resultAt -and -not $waiting -and ((Get-Date) - $resultAt).TotalSeconds -ge $exitGrace) { $end = 'RESULT-GRACE' }
            }
            if ($end) {
                try { $proc.Kill($true) } catch { }
                [void]$proc.WaitForExit(15000)
                return $end
            }
        }
        $proc.WaitForExit()
        $proc.ExitCode
    } finally {
        if ($waiting) { Exit-OwnerWait $Session $token 'unit ended' }
        Restore-ConsoleMode $saved
        if ($Tab -and -not $waiting) { Set-RunnerTabTitle $Tab }
    }
}

# Beats every claim the unit session holds while it waits on the owner. A beat that cannot get the tasks.json lock is
# skipped; the next tick tries again.
function Update-WaitingClaims([string] $Session) {
    try {
        $doc = Read-Tasks $P
        foreach ($t in @($doc.tasks | Where-Object { $_.claim -and [string]$_.claim.session -eq $Session })) {
            try { [void](Update-ClaimBeat $P $Session ([string]$t.id)) } catch { Write-Warning "WAIT-BEAT-SKIPPED $($t.id): $(("$_" -split "`n")[0])" }
        }
    } catch { Write-Warning "WAIT-BEAT-SKIPPED: $(("$_" -split "`n")[0])" }
}

# True once the unit's result file holds a JSON result (the mod writes it whole, but a half-read file is not one).
function Test-UnitResult([string] $Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path)) { return $false }
    try { $null = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop; $true } catch { $false }
}

# Reads what the unit's transcript gained since the last call and returns Find-QuotaRejection's hit, or $null. The file
# is found by name under every project folder (claude names the folder after the working directory). A transcript not
# found within 120 s is reported once: the check is then off for this unit, and the TIMEOUT still ends it.
function Watch-UnitQuota([hashtable] $Tail, [string] $ClaudeSession) {
    if (-not $Tail.path) {
        $root = Get-ClaudeProjectsRoot
        if (Test-Path -LiteralPath $root) {
            foreach ($d in @(Get-ChildItem -LiteralPath $root -Directory -ErrorAction SilentlyContinue)) {
                $f = Join-Path $d.FullName "$ClaudeSession.jsonl"
                if (Test-Path -LiteralPath $f) { $Tail.path = $f; break }
            }
        }
        if (-not $Tail.path) {
            if (-not $Tail.warned -and ((Get-Date) - $Tail.started).TotalSeconds -ge 120) {
                $Tail.warned = $true
                Write-Warning "QUOTA-WATCH-OFF no transcript $ClaudeSession.jsonl under $root; a usage limit in this unit ends it only at its TIMEOUT"
            }
            return $null
        }
    }
    try {
        $fs = [IO.FileStream]::new($Tail.path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
        try {
            if ($fs.Length -le $Tail.offset) { return $null }
            [void]$fs.Seek($Tail.offset, [IO.SeekOrigin]::Begin)
            $sr = [IO.StreamReader]::new($fs, [Text.Encoding]::UTF8)
            $chunk = $sr.ReadToEnd()
            $Tail.offset = $fs.Length
        } finally { $fs.Dispose() }
    } catch { return $null }
    $text = $Tail.rest + $chunk
    $cut = $text.LastIndexOf("`n")
    if ($cut -lt 0) { $Tail.rest = $text; return $null }
    $Tail.rest = $text.Substring($cut + 1)
    Find-QuotaRejection ($text.Substring(0, $cut) -split "`r?`n")
}

if ($DryRun) {
    $session = if ($gated) { New-SessionId $idPrefix } else { $stableSession }
    if ($Role -eq 'plan') { $lp = Get-LivePlanner $session; if ($lp) { "IDLE live planner $lp"; "SESSION $session"; exit 0 } }
    $dryIdle = {
        param([string] $Line)
        $Line
        Format-IdleReport (Get-IdleReport) (Get-Date).AddSeconds($IntervalSeconds)
        "CONFIG $(Format-Config (Get-RoleConfig))"
        "CHECK the launch check runs $(Get-AiLauncher) --version every $LaunchCheckMinutes min"
        "SESSION $session"
    }
    if ($timedGated) {
        $why = Get-TimedGate (Read-Tasks $P)
        if (-not $why) { & $dryIdle "IDLE nothing to take for $Role"; exit 0 }
        "GATE $why"
    }
    if ($statusTick) {
        "TICK every $IntervalSeconds s, scripts only (no model call): Invoke-Watchdog, Get-StreamStatus, Build-StatusPage, Get-StreamCost + Build-CostPage, Build-PriorityPage, Archive-TaskHistory (first tick of each UTC day), Activate-Group (a focus group without plans\<G>.activation.json; -FreshnessOnly every tick for an active one); one STATUS-TICK heartbeat line per tick"
        $openStatus = @(Get-ActionableInboxItems (Read-Tasks $P))
        if (-not $openStatus.Count) { $script:timedWhy = @("$skill inbox: no open item (the tick itself needs no unit)"); & $dryIdle "IDLE no open $skill inbox item: no unit"; exit 0 }
        "GATE inbox $($openStatus.Count) actionable ($($openStatus[0].id))"
    }
    if ($gated) {
        $why = Get-WorkGate
        if (-not $why) { & $dryIdle "IDLE nothing to take for $Role"; exit 0 }
        "GATE $why"
        "PRESTAGE $(if ($preStage) { "on: the runner takes the item or claims the row (Claim-Task.ps1), writes .streams\units\<session>\unit.md$(if ($Role -eq 'build') { ', lays the worktree and proves the author grader RED (a not-red row bounces to planned with no launch)' }), then launches with 'packet: <unit.md>'" } else { 'off (-NoPreStage): the unit does its own inbox, lessons and claim steps' })"
    }
    $cfg = Get-RoleConfig
    $fg = Get-FocusGroups (Read-Tasks $P) $P
    "FOCUS $(if ($fg.groups.Count) { $fg.groups -join '+' } else { 'none: every group is closed' }) ($($fg.source)); set it in $(Join-Path $P.Root 'config.json') as focus.groups"
    "RUN $command$(if ($preStage) { ' packet: <unit.md>' })"
    "MODE $mode$(if ($Live) { " mod $modDir timeout $UnitTimeoutSeconds s grace $exitGrace s" })"
    "CONFIG $(Format-Config $cfg)"
    "CHECK the launch check runs $(Get-AiLauncher) --version every $LaunchCheckMinutes min"
    "SESSION $session"
    if ($Tab) { "TAB $Tab stop file STOP-tab-$tabToken" }
    "ARGS $((Get-CliArgs $session '<rules file>' $command $cfg) -join ' ')"
    "RULES $((Get-RunnerRules $session $null $cfg) -replace "`n", ' | ')"
    exit 0
}

$claude = Get-ClaudeCommand
if (-not $claude) { 'NO-CLAUDE claude is not on PATH'; exit 2 }
if ($Live -and -not $env:STREAM_RUNNER_CLAUDE -and -not (Test-Path -LiteralPath (Join-Path $modDir 'hooks\register.ts'))) {
    "NO-MOD the stream-unit mod is not at $modDir; run /machine-config apply"; exit 2
}
$logDir = Join-Path $P.Root "logs\runner\$runnerId"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$state = @{ runner = $runnerId; role = $Role; mode = $mode; pid = $PID; repo = $Repo; interval = $IntervalSeconds; runs = 0; started = Get-Now
    tab = $(if ($Tab) { $Tab } else { $null }); session = $(if ($gated) { $null } else { $stableSession }); lastStart = $null; lastExit = $null; lastResult = $null; status = 'starting' }
Write-RunnerState $state
"RUNNER $runnerId role $Role mode $mode every $IntervalSeconds s$(if ($statusTick) { ' (script tick; a unit only for an open inbox item)' } else { ' when idle (a unit only when the gate finds work)' }) log $logDir"
# This runner's own pwsh retitled the console as it started (an elevated one to 'Administrator: <pwsh path>', seen on
# SMVMTR1 2026-10-05), and in Windows Terminal the console title is the tab title, so the tab name is set back here.
if ($Tab) { Set-RunnerTabTitle $Tab }
$backoff = 0
$idleStreak = 0
# A wake file already there when the runner starts is old news (Get-WakeSeen); only a later write wakes it.
$script:wakeSeen = Get-WakeSeen $P $Role $runnerId
$script:wakeHit = $null
$wakeForce = $false
# Runners started together finish their first launch check together and race for the tasks.json lock (kit item
# IN-20261010172833-eff6), so the first unit waits a random 0..STREAM_RUNNER_START_JITTER_SECONDS (30) after it, and a
# pre-stage that lost a lock race retries after a random wait up to STREAM_RUNNER_BUSY_RETRY_SECONDS (30, at least a
# sixth of it) instead of backing off as a failed run.
$envSeconds = { param([string] $Name, [int] $Default) $v = [Environment]::GetEnvironmentVariable($Name); $n = 0; if ([int]::TryParse([string]$v, [ref]$n) -and $n -ge 0) { $n } else { $Default } }
$startJitter = & $envSeconds 'STREAM_RUNNER_START_JITTER_SECONDS' 30
$busyRetryMax = & $envSeconds 'STREAM_RUNNER_BUSY_RETRY_SECONDS' 30
# A -Live unit's transcript is read every STREAM_RUNNER_QUOTA_CHECK_SECONDS (10) for a usage-limit rejection.
$quotaCheckSeconds = [Math]::Max(1, (& $envSeconds 'STREAM_RUNNER_QUOTA_CHECK_SECONDS' 10))
$firstTick = $true
while ($true) {
    if (Test-StopRequested) {
        $state.status = 'stopped (STOP file)'; Write-RunnerState $state
        Get-OwnStopFile | Where-Object { Test-Path -LiteralPath $_ } | ForEach-Object { Remove-Item -LiteralPath $_ -ErrorAction SilentlyContinue }
        "STOP file found; runner exits"; break
    }
    if (Test-AllClosed) { $state.status = 'stopped (all groups closed)'; Write-RunnerState $state; "every group is closed; runner exits"; break }
    # For the status role -MaxRuns counts script ticks as well as units (a self-test runs one tick and stops).
    if ($MaxRuns -gt 0 -and ($state.runs -ge $MaxRuns -or ($statusTick -and $script:ticks -ge $MaxRuns))) { $state.status = "stopped (MaxRuns $MaxRuns)"; Write-RunnerState $state; break }
    # A wake seen while waiting (or now, between waits) re-runs the gate at once with the idle streak and failure
    # backoff reset; a forced one launches a unit without asking the gate (a work runner still claims in its pre-stage,
    # so with nothing claimable it goes back to the gate, no failed run).
    if ($script:wakeHit -or (Test-WakeRequested)) {
        $wh = $script:wakeHit; $script:wakeHit = $null
        "$(Get-TabNow) WAKE owner $($wh.file)$(if ($wh.force) { ' force' }) $($wh.reason)"
        $idleStreak = 0; $backoff = 0; $wakeForce = [bool]$wh.force
    }
    $tickStart = Get-Date
    if ($gated -and $wakeForce) {
        $wakeForce = $false
        "$(Get-TabNow) GATE skipped: a forced owner wake launches this unit"
    } elseif ($statusTick -and $wakeForce) {
        # A forced status wake is an owner asking for a fresh page: it runs the script tick now (the pages are rebuilt),
        # then launches the /stream-status unit. It used to launch the unit alone, so the page stayed as old as the last
        # tick and the idle unit's backoff kept it so for up to 20 min more (kit item IN-20261023131800-4894).
        $wakeForce = $false
        $script:tickOpenCount = 0
        try { Invoke-StatusTick $stableSession } catch { Write-TickLog "$(Get-TabNow) TICK-FAILED the status tick threw: $(("$_" -split "`n")[0])" }
        "$(Get-TabNow) GATE skipped: a forced owner wake ran the tick and launches a /stream-status inbox unit"
    } elseif ($timedGated -and $wakeForce) {
        $wakeForce = $false
        Clear-IdleStatus
        Set-TimedLaunch
        "$(Get-TabNow) GATE skipped: a forced owner wake launches this unit"
    } elseif ($gated) {
        $why = Get-WorkGate
        if (-not $why) {
            try { Show-IdleStatus } catch { "$(Get-TabNow) IDLE nothing to take for $Role (report failed: $(("$_" -split "`n")[0]))" }
            [void](Wait-ForBoardChange); continue
        }
        Clear-IdleStatus
        "$(Get-TabNow) GATE $why"
        "  doing      : $(Get-GatePlain $why)"
    } elseif ($statusTick) {
        $script:tickOpenCount = 0
        try { Invoke-StatusTick $stableSession } catch { Write-TickLog "$(Get-TabNow) TICK-FAILED the status tick threw: $(("$_" -split "`n")[0])" }
        $openCount = [int]$script:tickOpenCount
        if (-not $openCount) { [void](Wait-ForTick $IntervalSeconds); continue }
        "$(Get-TabNow) GATE inbox $openCount open $skill item(s): a unit works them"
    } elseif ($timedGated) {
        $why = Get-TimedGate (Read-Tasks $P)
        if (-not $why) {
            try { Show-IdleStatus } catch { "$(Get-TabNow) IDLE nothing to take for $Role (report failed: $(("$_" -split "`n")[0]))" }
            [void](Wait-ForBoardChange); continue
        }
        Clear-IdleStatus
        Set-TimedLaunch
        "$(Get-TabNow) GATE $why"
        "  doing      : $(Get-GatePlain $why)"
    }
    $session = if ($gated) { New-SessionId $idPrefix } else { $stableSession }
    if ($Role -eq 'plan') {
        $lp = Get-LivePlanner $session
        if ($lp) {
            $state.status = "waiting: live planner $lp"; Write-RunnerState $state
            "$(Get-TabNow) LIVE-PLANNER $lp; next check at $(Get-TabAt $IntervalSeconds) ($IntervalSeconds s)"
            "  waiting    : another planner session is live; one planner at a time"
            Start-Sleep -Seconds $IntervalSeconds; continue
        }
    }
    # The usage limit is the account's, so a hold one runner recorded keeps every runner from launching (and claiming)
    # into it until the stated reset (lib\Streams.ps1 Get-QuotaHold).
    $hold = Get-QuotaHold $P
    if ($hold) {
        $holdWait = [Math]::Max(1, [int]($hold.until - (Get-Date).ToUniversalTime()).TotalSeconds)
        $state.status = "quota hold until $($hold.until.ToString('yyyy-MM-ddTHH:mm:ssZ')) ($($hold.type), set by $($hold.by))"; Write-RunnerState $state
        "$(Get-TabNow) QUOTA-HOLD until $(Format-Local $hold.until) ($holdWait s): $($hold.type) limit seen by $($hold.by)"
        "  waiting    : the Claude usage limit was reached; no runner launches before $(Format-Local $hold.until)"
        # Re-read the hold every step: a hold the owner cleared (a re-login to another account, the file moved aside)
        # or one already past its time ends the wait at once, and an owner wake ends it too (the gate then re-checks).
        while ($holdWait -gt 0 -and -not (Test-StopRequested) -and -not $script:wakeHit) {
            Start-Sleep -Seconds ([Math]::Min(15, $holdWait)); $holdWait -= 15; [void](Test-WakeRequested)
            # One runner per repo probes the account every STREAM_RUNNER_QUOTA_PROBE_SECONDS; a success lifts the
            # hold early for every runner (lib\Streams.ps1 Invoke-QuotaProbe, kit item IN-20261024093536-3be3).
            $probeCfg = Get-RoleConfig; $probe = Invoke-QuotaProbe $P $runnerId ([string]$(if ($probeCfg) { $probeCfg.model }))
            if ($probe -in @('LIFTED', 'HELD', 'UNKNOWN')) { "$(Get-TabNow) QUOTA-PROBE $probe" }
            if (-not (Get-QuotaHold $P)) { "$(Get-TabNow) QUOTA-HOLD lifted: the hold file is gone or past its time"; break }
        }
        # The state file is what Wake-StreamRunner and the status page read: say the hold is over at once, or a lifted
        # runner reads as held through its whole pre-stage (kit item IN-20261024091316-c6c2).
        if (-not (Get-QuotaHold $P)) { $state.status = "quota hold lifted $(Format-LocalStamp); back to the gate"; Write-RunnerState $state }
        continue
    }
    $check = Sync-LaunchEnvironment
    Restore-RunnerTabTitle
    if ($check -notin @('CURRENT', 'CHECKED')) { "$(Get-TabNow) LAUNCH-CHECK $check" }
    if ($firstTick -and $startJitter -gt 0) {
        $j = Get-Random -Minimum 0 -Maximum ($startJitter + 1)
        "$(Get-TabNow) START-JITTER $j s: a random start delay so tabs opened together do not all claim at once; starts at $(Get-TabAt $j)"
        if ($j -gt 0) { Start-Sleep -Seconds $j }
    }
    $firstTick = $false
    $stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
    $out = Join-Path $logDir "$stamp-$session.json"
    $failed = $false; $res = $null; $code = $null; $text = ''
    $packet = $null; $pre = $null
    $cfg = Get-RoleConfig
    if ($cfg.note) { "$(Get-TabNow) $($cfg.note)" }
    $checkFailed = $check -like 'REFUSED*' -or $check -like 'FAILED*'
    if ($preStage -and -not $checkFailed) {
        $state.status = "pre-staging $session (claim, worktree, RED check)"; Write-RunnerState $state
        $pre = Invoke-PreStageGuarded $session
        foreach ($l in $pre.Lines) { "$(Get-TabNow) $l" }
        # A NONE claim in the pre-stage left an idle beat for this new session id, which never becomes a unit, so it
        # counted as one more live session for the role's whole limit; the runner state file is this runner's liveness.
        if (-not $pre.Packet) { Clear-IdleBeat $P $session }
        # Nothing to launch and nothing failed: a bounce (counted as a run) or a lost race. Back to the gate.
        if (-not $pre.Failed -and -not $pre.Packet) { continue }
        if ($pre.Busy) {
            # Lock contention: no run, no backoff. The claim and any hold were released by the guard; try again soon.
            $j = if ($busyRetryMax -gt 0) { Get-Random -Minimum ([Math]::Max(1, [int]($busyRetryMax / 6))) -Maximum ($busyRetryMax + 1) } else { 0 }
            $state.status = "retry in $j s: pre-stage lost a lock race"; Write-RunnerState $state
            "$(Get-TabNow) BUSY-RETRY $j s (lock contention is not a failed run)"
            if ($j -gt 0) { Start-Sleep -Seconds $j }
            continue
        }
        $packet = $pre.Packet
    }
    if ($checkFailed) {
        $failed = $true; $code = 'LAUNCH-CHECK'; $text = $check
        Set-Content -LiteralPath $out -Value $check -Encoding utf8
    } elseif ($pre -and $pre.Failed) {
        $failed = $true; $code = 'PRESTAGE'; $text = $pre.Failed
        Set-Content -LiteralPath $out -Value $text -Encoding utf8
    } else {
        $rulesFile = Join-Path $logDir "$stamp-$session.rules.txt"
        Set-Content -LiteralPath $rulesFile -Value (Get-RunnerRules $session $packet $cfg) -Encoding utf8
        $unitCommand = if ($packet) { "$command packet: $($packet.packet)" } else { $command }
        $claudeSession = if ($Live) { [guid]::NewGuid().ToString() } else { '' }
        $cliArgs = Get-CliArgs $session $rulesFile $unitCommand $cfg $claudeSession
        $unitStartUtc = (Get-Date).ToUniversalTime().AddSeconds(-2)
        $state.lastStart = Get-Now; $state.status = "running $session"; $state.session = $session; $state.unitPid = $null; Write-RunnerState $state
        "$(Get-TabNow) RUN $session ($mode) $(Format-Config $cfg)$(if ($packet) { " packet $($packet.packet)" })"
        Set-LaunchConfig $cfg
        # Whatever way the unit ends (a clean exit, TIMEOUT, NO-RESULT, a failed launch, or Ctrl+C on this runner), any
        # claim its session still holds is released here, so the row is claimable at once instead of after the role's
        # limit. A console closed under the runner runs no finally block; the watchdog frees that claim on its next
        # pass, because the unit's runner pid is gone (kit item IN-20261004202424-27bf).
        try {
        if ($Live) {
            $env:STREAM_UNIT_OUT = $out; $env:STREAM_UNIT_SESSION = $session; $env:STREAM_UNIT_ROLE = $Role
            if ($Tab) { $env:STREAM_UNIT_TAB = $Tab }
            try { $code = Invoke-LiveUnit $claude $cliArgs $out $session $claudeSession }
            finally { Remove-Item Env:\STREAM_UNIT_OUT, Env:\STREAM_UNIT_SESSION, Env:\STREAM_UNIT_ROLE, Env:\STREAM_UNIT_TAB -ErrorAction SilentlyContinue }
            if (Test-Path -LiteralPath $out) { try { $res = Get-Content -LiteralPath $out -Raw | ConvertFrom-Json -ErrorAction Stop } catch { } }
            if ($code -eq 'USAGE-LIMIT') {
                $q = $script:unitQuota
                $text = "USAGE-LIMIT the account hit its $($q.type) limit$(if ($q.resetsAt) { "; resets $($q.resetsAt.ToString('yyyy-MM-ddTHH:mm:ssZ'))" }): $($q.text)"
                if (-not $res) { Set-Content -LiteralPath $out -Value $text -Encoding utf8 }
            } elseif ($code -eq 'TIMEOUT') {
                # A unit that wrote its result before the limit DID its work; only the exit was late (it ran on after
                # unit_done). Backing it off cost a builder 900 s after a real 'built' on 2026-10-04 (G3.T170, kit item
                # IN-20261004205649-446f), so only a TIMEOUT with no result is a failed run.
                $text = "TIMEOUT the session passed its $UnitTimeoutSeconds s limit and was ended"
                if (-not $res) { Set-Content -LiteralPath $out -Value $text -Encoding utf8; $failed = $true }
            } elseif ($code -eq 'RESULT-GRACE') {
                # The unit's work is done and its result is on disk; only its exit hung. Not a failed run.
                "$(Get-TabNow) RESULT-GRACE $session wrote its result and was still running $exitGrace s later; ended it"
                if (-not $res) { $text = 'RESULT-GRACE the result file could not be read back'; $failed = $true }
            } elseif (-not $res) {
                $text = "NO-RESULT the session exited ($code) without calling unit_done"
                Set-Content -LiteralPath $out -Value $text -Encoding utf8
                $failed = $true
            }
        } else {
            Push-Location $Repo
            try {
                $events = Join-Path $logDir "$stamp-$session.jsonl"
                $lines = [Collections.Generic.List[string]]::new()
                $run = if ($claude -like '*.ps1') { { & pwsh -NoProfile -File $claude @cliArgs 2>&1 } } else { { & $claude @cliArgs 2>&1 } }
                & $run | ForEach-Object {
                    $l = [string]$_
                    $lines.Add($l)
                    if ($Stream -and $l -match '^\s*\{') {
                        try { $ev = $l | ConvertFrom-Json -ErrorAction Stop; Format-StreamEvent $ev } catch { }
                    }
                }
                $code = $LASTEXITCODE
            } finally { Pop-Location }
            $raw = $lines -join "`n"
            if ($Stream) {
                Set-Content -LiteralPath $events -Value $raw -Encoding utf8
                $resLine = @($lines | Where-Object { $_ -match '"type"\s*:\s*"result"' }) | Select-Object -Last 1
                if ($resLine) { try { $res = $resLine | ConvertFrom-Json -ErrorAction Stop } catch { } }
                Set-Content -LiteralPath $out -Value $(if ($resLine) { $resLine } else { $raw }) -Encoding utf8
            } else {
                Set-Content -LiteralPath $out -Value $raw -Encoding utf8
                $res = ConvertFrom-RunnerOutput $raw
            }
            if (-not $res) { $text = $raw; $failed = $true }
        }
        } finally {
            Clear-LaunchConfig
            # A build unit that died holding its claim: export its worktree to a patch BEFORE the claim goes (3.3).
            if ($packet -and $packet.worktree) {
                try { Save-UnitWork $session $packet.task $packet.worktree $(if ($null -eq $code) { 'interrupted' } else { [string]$code }) | ForEach-Object { "$(Get-TabNow) $_" } }
                catch { "$(Get-TabNow) HARVEST-FAILED $($packet.task) : $_ (the watchdog harvests the tree under its quiet period)" }
            }
            try {
                $freed = @(Clear-SessionClaims $P $session $runnerId "released by the runner: unit $session exited ($(if ($null -eq $code) { 'interrupted' } else { $code }))")
                if ($freed.Count) { "$(Get-TabNow) RELEASED $($freed -join ', '): claim(s) unit $session left" }
            } catch { "$(Get-TabNow) RELEASE-FAILED $session : $_ (the watchdog frees it once the claim is stale)" }
            # A work unit's session never comes back, so an inbox item it still holds is re-opened now with a progress
            # file, not left taken until the role's limit and then restarted from scratch (kit item IN-20261005193358-71ec).
            # Timed roles keep one session across units, so their next unit still holds the item and goes on with it.
            if ($gated) {
                try { Open-UnitInboxHolds $P $session $unitStartUtc $(if ($null -eq $code) { 'interrupted' } else { [string]$code }) | ForEach-Object { "$(Get-TabNow) $_" } }
                catch { "$(Get-TabNow) REOPEN-FAILED $session : $_ (the watchdog re-opens the item once its hold is stale)" }
            }
        }
        $state.runs++
    }
    $state.lastExit = $code
    # A result can lack any field (an older claude, a hand-written stub, a cut-short session); StrictMode throws on a missing one.
    $field = { param($n) if ($res -and $res.PSObject.Properties[$n]) { $res.$n } else { $null } }
    if (& $field 'result') { $text = [string](& $field 'result') }
    $state.lastResult = (($text -replace '\s+', ' ').Trim()); if ($state.lastResult.Length -gt 300) { $state.lastResult = $state.lastResult.Substring(0, 300) }
    if ($code -eq 'USAGE-LIMIT') {
        # Not a failed run and no doubling backoff: the claim and any inbox hold were released above, and the runner
        # waits for the stated reset (plus jitter, so runners do not restart together), then goes back to the gate.
        $q = $script:unitQuota
        $until = Get-QuotaResumeTime $q.resetsAt
        Set-QuotaHold $P $until $session $q.type
        "$(Get-TabNow) EXIT USAGE-LIMIT $($q.type) -> $out"
        $backoff = 0
        continue
    }
    $unitOutcome = Get-UnitOutcome $res
    if (($code -is [int] -and $code -ne 0) -or ((& $field 'is_error') -and -not $unitOutcome) -or ($text -match '(?i)usage limit|rate limit|overloaded|limit reached')) { $failed = $true }
    $outcome = if ($unitOutcome) { " outcome $unitOutcome" } else { '' }
    "$(Get-TabNow) EXIT $code$outcome $(if ($res) { "turns $(& $field 'num_turns') cost $(& $field 'total_cost_usd')" }) $(if ($failed) { 'FAILED' } else { 'ok' }) -> $out"
    # The scoped-autoapprove hook (claude\scripts, PermissionRequest) answers a prompt about work inside the repo /
    # scratch roots itself and logs each yes beside the unit result; the owner sees the count here, the lines there.
    if (Test-Path -LiteralPath "$out.approvals.log") { try { "$(Get-TabNow) APPROVED $(@(Get-Content -LiteralPath "$out.approvals.log").Count) in-scope permission prompt(s) answered by the scoped-autoapprove hook -> $out.approvals.log" } catch { } }
    try { Record-Unit $session $packet $unitOutcome $res $code $unitStartUtc } catch { }
    if ($failed) {
        $backoff = if ($backoff -eq 0) { 900 } else { [math]::Min(3600, $backoff * 2) }
        $state.status = "backoff $backoff s after a failed run; next try at $(Get-TabAt $backoff)"; Write-RunnerState $state
        "  failed     : $(if ("$code" -eq 'PRESTAGE') { 'the set-up before Claude (claim, worktree, base, RED check) failed, so no Claude session ran; the reason is on the PRESTAGE-FAILED line above' } else { 'the session ended without a usable result; the log named on the EXIT line has the detail' })"
        "$(Get-TabNow) BACKOFF $backoff s: waiting after a failed run (doubles on each failure in a row, up to 1 h); next try at $(Get-TabAt $backoff)"
        # Waited in 15 s steps so a STOP file or an owner wake (Wake-StreamRunner.ps1) cuts the backoff short.
        $bw = $backoff
        while ($bw -gt 0 -and -not (Test-StopRequested) -and -not $script:wakeHit) { Start-Sleep -Seconds ([Math]::Min(15, $bw)); $bw -= 15; [void](Test-WakeRequested) }
        continue
    }
    $backoff = 0
    $state.status = "ran $session"; Write-RunnerState $state
    if (-not $gated) {
        # E4 backoff (lib\Streams.ps1 Get-RunnerWait): an idle unit with an empty inbox doubles the next wait up to
        # 20 min for plan/status/kit/coordinator; an inbox write wakes the runner early.
        $openNow = @(Read-InboxItems (Get-InboxPath $P $inboxSkill) | Where-Object { Test-InboxOpen $_ $inboxSkill }).Count
        # A gated timed role launched because its gate found work; a unit that still says idle found nothing it could do
        # (an item it cannot act on, a built row another drain holds), and the gate would fire again at once. Its idle
        # counts whatever the inbox holds, so the backoff spaces those relaunches out; an inbox write still wakes it.
        $idleStreak = if ($unitOutcome -eq 'idle' -and ($timedGated -or -not $openNow)) { $idleStreak + 1 } else { 0 }
        # A gated timed role goes back to its gate after a short floor: the gate, not the clock, decides the next launch.
        # After an idle unit (the gate said work, the unit found none) it waits the interval, backed off as before.
        $every = if ($idleStreak -or $statusTick) { Get-RunnerWait $Role $IntervalSeconds $idleStreak } else { [Math]::Min($IntervalSeconds, 30) }
        if ($idleStreak -and $every -ne $IntervalSeconds) { "$(Get-TabNow) BACKOFF-IDLE next unit in $every s (idle streak $idleStreak); an inbox write wakes it" }
        $wait = $every - [int]((Get-Date) - $tickStart).TotalSeconds
        if ($wait -gt 0) { "  next look  : $(Get-TabAt $wait), or sooner when the $inboxSkill inbox is written" }
        $inboxFile = Get-InboxPath $P $inboxSkill
        $stamp = if (Test-Path -LiteralPath $inboxFile) { (Get-Item -LiteralPath $inboxFile).LastWriteTimeUtc } else { [datetime]::MinValue }
        while ($wait -gt 0) {
            Start-Sleep -Seconds ([Math]::Min(15, $wait)); $wait -= 15
            if ((Test-StopRequested) -or (Test-WakeRequested)) { break }
            if ($idleStreak -and (Test-Path -LiteralPath $inboxFile) -and (Get-Item -LiteralPath $inboxFile).LastWriteTimeUtc -ne $stamp) {
                "$(Get-TabNow) WAKE inbox written"; $idleStreak = 0; break
            }
        }
    }
}
