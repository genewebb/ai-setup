# Read-only snapshot of the streams (never takes the lock). Default output is the 6-line terminal summary;
# -Json emits the full model the status page is built from.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [switch] $Json
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$doc = Read-Tasks $P
$now = (Get-Date).ToUniversalTime()
$chain = Get-ChainMinutes $doc
$upChain = Get-UpChainMinutes $doc
function Age([string] $at) { if (-not $at) { return $null }; [int]($now - [datetime]::Parse($at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes }

# ---- predicted finish per group ----
# Estimates alone cannot date a group: they say how much work is left, not how fast it lands. The rate is MEASURED
# from this board's own history - the estimated minutes that FIRST reached integrated or done inside a trailing
# window - so it already carries however many sessions are really running, the rework, the reaped worktrees and the
# idle time between them. Only the FOCUS group(s) (Get-FocusGroups) are dated from their own rate: the focus rule
# freezes every other open group, so a frozen group lands almost nothing and its own rate measures the freeze, not
# capacity (G6 read 0.74 min/h, one landing in 168 h, and dated the board 14 Aug 2027). The groups after the focus are
# dated IN FOCUS ORDER instead, see "queued groups" below. The window widens until it holds at least MinDeliveries completions, because a 24 h window over a
# single task prices a whole group off that one task; widening with few completions lowers the rate, so the error
# leans late rather than early. A group with no completion in the widest window gets NO date - "stalled" is the
# honest answer there, not a number from an invented rate.
$DeliveryWindowHours = @(24, 48, 72, 168)
$MinDeliveries = 3

# ---- outages are not delivery time ----
# The rate divides completions by the hours of the window, and an hour in which NO session was alive is not an hour
# the streams could have delivered in. On 2026-10-01 every session went silent at about 23:15Z and nothing ran again
# until 15:35Z, 16 h of a 48 h window, and G1 read "173 min left, finishes in 18 h" at 9.6 min/h: the outage priced
# into every group as if it were going to repeat. So the hours divided by are the window LESS its outages.
# An outage is a gap between two consecutive pieces of board activity longer than $OutageGapMinutes, and only the part
# past that limit is taken off. A builder deep in one `dotnet test` writes no history (beats are not recorded), and a
# board with a few sessions lands roughly hourly, so the limit sits well above the 45 min build claim limit: at 45 min an
# ordinary hourly cadence read as 15 min of outage per hour. Two hours of silence with no history from ANY session is
# not a busy board. Activity is every history entry
# written by a working role, plus every current claim's `at` and `beat` and the integrator lock's beat. The watchdog's
# own lines (`status-*`) are left out, because a status tick during an outage is not delivery capacity.
# The gap from the last activity to NOW is never taken off: whether the current silence is an outage is not known yet,
# and the "no session seen in the last hour" flag already reports it. The gap at the window's start edge is not taken
# off either, because the activity that bounds it lies outside the window and the steady-state case must read the same.
$OutageGapMinutes = 120
$activity = [Collections.Generic.List[datetime]]::new()
function Add-Activity([string] $at) {
    if (-not $at) { return }
    $d = [datetime]::MinValue
    if ([datetime]::TryParse($at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref] $d)) { $activity.Add($d) }
}
foreach ($t in @($doc.tasks)) {
    foreach ($h in @($t.history)) { if ($h -and [string]$h.by -notlike 'status*') { Add-Activity ([string]$h.at) } }
    if ($t.claim) { Add-Activity ([string]$t.claim.at); Add-Activity ([string]$t.claim.beat) }
}
if (Test-Path $P.IntLock) { try { $il = Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String; Add-Activity ([string]$il['beat']) } catch { } }
$activitySorted = @($activity | Sort-Object)
# Hours of outage inside the trailing window of $w hours: the part of each over-limit gap past the limit, clipped to the
# window. Both ends of a counted gap are real activity, so the trailing silence is never one of them.
function Get-OutageHours([double] $w) {
    $start = $now.AddHours(-$w)
    $idle = 0.0
    for ($i = 1; $i -lt $activitySorted.Count; $i++) {
        $a = $activitySorted[$i - 1]; $b = $activitySorted[$i]
        if ($a -lt $start) { continue }                          # straddles the window's start edge, see above
        if (($b - $a).TotalMinutes -le $OutageGapMinutes) { continue }
        $idle += ($b - $a.AddMinutes($OutageGapMinutes)).TotalHours
    }
    [math]::Round($idle, 2)
}

# ---- ticketing: the one piece of work in flight that no STATE records ----
# A task an author is writing the ticket for stays `planned` until the ticket and grader are released, so on the board
# it is indistinguishable from a row nobody has touched. That hid the whole authoring stage: 4 authors working is the
# same picture as 4 authors dead. `ticketing` is that stage, carved OUT of `planned` so the two never double count and
# every total still adds up. It is derived from the claim, not stored: a planned row whose claim is an author's and
# whose beat is inside the author limit. A stale claim is deliberately NOT counted - the watchdog is about to clear it,
# and counting it would report a dead session as work in progress, which is the failure this metric exists to expose.
# `retired` is the same kind of carve-out, from done: a row the planner withdrew with Revise-Task.ps1 -Release retire
# (lib Test-Retired). It is finished but landed nothing, so it is neither blocked nor counted as delivered work.
$StateBuckets = @('planned', 'ticketing', 'ticketed', 'building', 'built', 'integrated', 'done', 'retired', 'blocked')
function Test-Ticketing($t) {
    $t.state -eq 'planned' -and $t.claim -and $t.claim.role -eq 'author' -and (Test-ClaimLive $t)
}
function Bucket($t) { if (Test-Ticketing $t) { 'ticketing' } elseif (Test-Retired $t) { 'retired' } else { $t.state } }
function First-Landed($t) {
    if (Test-Retired $t) { return $null }   # a retired row landed nothing, so it never feeds the delivery rate
    foreach ($h in @($t.history)) { if ($h.to -in @('integrated', 'done')) { return $h.at } }
    $null
}
function Median($values) {
    $v = @($values | Sort-Object)
    if (-not $v.Count) { return 0 }
    if ($v.Count % 2) { return [double]$v[[int](($v.Count - 1) / 2)] }
    ([double]$v[$v.Count / 2 - 1] + [double]$v[$v.Count / 2]) / 2
}
# "Two scales" is a claim about the SHAPE of a set of estimates: two clusters, not one spread. So the test is the
# upper half's median over the lower half's, which is what tells those apart. A percentile ratio does not: with half
# the rows repriced 7.6x, the median falls BETWEEN the two clusters, and p90/median read 1.8 on a board that was
# split down the middle - lower than several single-scale chains. Halving first puts one cluster on each side, and
# one legitimately large row (a suites run, an owner gate) moves the upper MEDIAN barely at all.
function HalfSplit($values) {
    $v = @($values | Sort-Object)
    if ($v.Count -lt $MinSplitRows) { return 0 }
    $half = [int][math]::Floor($v.Count / 2)
    $lo = Median @($v[0..($half - 1)])
    $hi = Median @($v[($v.Count - $half)..($v.Count - 1)])
    if ($lo -le 0) { return 0 }
    [math]::Round($hi / $lo, 2)
}

# ---- is the chain summed from ONE scale? ----
# Only one forecast number is exposed to the scale the estimates are written in: the chain floor, which sums the
# to-go estimates along the longest path. The rate side cancels its own scale (see the comment on $rate below), so
# the floor is the only place a half-finished reprice can produce a confident wrong date.
#
# So the scales are compared ON THAT PATH - the rows the floor is actually summed from - and NOT by holding the
# landed rows against the to-go ones. Three things measured on this board on 2026-09-30 say why:
#   1. Get-UpChainMinutes prices a landed row at 0 (lib\Streams.ps1:267), so NOT ONE landed estimate reaches the
#      floor. The old landed-vs-to-go test suppressed G2's date over a 3.18x gap between the populations, while
#      G2's own 523 min chain held 17 unlanded rows priced 8-30 min plus the 175 min suites row: one scale.
#   2. A floor crosses groups. G2's ran G2 -> G6 -> G5 -> G4 through G2.T91's dependsOn, so the population at risk
#      is not the group's own rows and cannot be judged from the four of them. Walking the path picks up whatever
#      groups it passes through, which is exactly the set of estimates being added together.
#   3. Whole-board is too blunt in the other direction: one group left on an old scale would refuse every group's
#      date, including groups whose own chain is clean.
# The statistic is HalfSplit along that path - see its own comment for why it is a halves ratio and not a
# percentile one. A chain shorter than $MinSplitRows is never called split: two or three rows cannot tell a second
# scale from ordinary variety, and refusing a date on that evidence is the confident wrong answer in the other
# direction. Measured: every real chain on this board reads under 2, and the same board with a random half of its
# to-go rows multiplied by 7.6 (the reprice ratio of 2026-09-30) reads 6 to 8.
$ScaleSplitRatio = 3
$MinSplitRows = 4
$byId = @{}; foreach ($t in $doc.tasks) { $byId[$t.id] = $t }
# The path Get-UpChainMinutes summed: from a task, take the dependency with the largest up-chain, repeatedly.
# Landed rows contribute 0 there, so they are not collected here either.
function Get-UpChainPath([string] $id) {
    $out = New-Object System.Collections.Generic.List[int]
    $seen = New-Object System.Collections.Generic.HashSet[string]
    while ($id -and $seen.Add($id)) {
        $t = $byId[$id]
        if (-not $t) { break }
        if ($t.state -notin @('done', 'integrated')) { $out.Add([int]$t.estMinutes) }
        $next = $null; $best = -1
        foreach ($d in @($t.dependsOn)) {
            if ($d -and $upChain.ContainsKey($d) -and $upChain[$d] -gt $best) { $best = $upChain[$d]; $next = $d }
        }
        $id = $next
    }
    # NOT `, $out.ToArray()`: the caller wraps this in @(), which does not unwrap a comma-wrapped array, so the
    # single element it produced was the int[] itself and Median cast an Int32[] to double. Returning the array
    # plainly lets @() rebuild it flat, and an empty or one-row path still comes back as an array there.
    $out.ToArray()
}

$groupRaw = @{}
$groups = foreach ($g in $doc.groups) {
    $ts = @($doc.tasks | Where-Object { $_.group -eq $g.id })
    $counts = [ordered]@{}; foreach ($s in $StateBuckets) { $counts[$s] = @($ts | Where-Object { (Bucket $_) -eq $s }).Count }
    $eta = ($ts | ForEach-Object { $chain[$_.id] } | Measure-Object -Maximum).Maximum

    # Builder and author work only: an owner gate waits on the owner's time and an integration row on the Tier 2 run,
    # neither is throughput, and each has its own line in the group's phases (below). Counting them here priced them
    # at the builders' rate and moved the date by work no builder can do (kit item IN-20261019192925-bbd8).
    $togo = @($ts | Where-Object { $_.state -notin @('integrated', 'done') -and $_.kind -notin @('gate', 'integration') })
    $heldOpen = @($ts | Where-Object { $_.state -notin @('integrated', 'done') -and $_.kind -in @('gate', 'integration') }).Count
    # What a group with no builder or author work left still waits on, said in place of a bare 'finished': its
    # Progress still counts those rows as to go (kit item IN-20261020100753-48cc).
    $heldLabel = $null
    if ($heldOpen) {
        $openGates = @($ts | Where-Object { $_.state -notin @('integrated', 'done') -and $_.kind -eq 'gate' }).Count
        $runIntegration = @($ts | Where-Object { $_.state -eq 'building' -and $_.kind -eq 'integration' }).Count
        $heldLabel = if ($runIntegration) { 'build done; Tier 2 run in flight' + $(if ($openGates) { "; $openGates gate(s) open" } else { '' }) } else { "build done; $heldOpen integration/gate left" }
    }
    $remain = [int](($togo | ForEach-Object { [int]$_.estMinutes } | Measure-Object -Sum).Sum)
    # The floor: no rate can beat the longest chain of unlanded work this group sits on top of.
    $floor = [int](($togo | ForEach-Object { $upChain[$_.id] } | Measure-Object -Maximum).Maximum)
    # ...and the rows it was summed from, which is the only population a split scale can make the date lie about.
    $floorHead = $togo | Sort-Object { [int]$upChain[$_.id] } -Descending | Select-Object -First 1
    # @( ... ) OUTSIDE the if: an else branch that emits @() sends nothing down the pipeline, so the assignment
    # lands $null and .Count throws on a group with no unlanded row. Wrapping the whole if keeps it an array.
    $floorPath = @(if ($floorHead) { Get-UpChainPath $floorHead.id })
    $pathMedian = Median $floorPath
    $pathSpread = HalfSplit $floorPath
    $landed = @(foreach ($t in $ts) {
            $a = First-Landed $t
            if ($a) { [pscustomobject]@{ hours = ($now - [datetime]::Parse($a, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalHours; est = [int]$t.estMinutes } }
        })
    $win = $null; $delivered = 0; $n = 0
    foreach ($w in $DeliveryWindowHours) {
        $inWin = @($landed | Where-Object { $_.hours -le $w })
        $win = $w; $n = $inWin.Count; $delivered = [int](($inWin | ForEach-Object { $_.est } | Measure-Object -Sum).Sum)
        if ($n -ge $MinDeliveries) { break }
    }
    # THE RATE IS COUNTED IN TASKS, NOT IN ESTIMATED MINUTES, and is then priced at the mean estimate of the rows still
    # TO GO. Summing the landed rows' own estimates made the forecast unit-unsafe: work left comes from the to-go rows
    # and the rate came from the landed ones, so a board-wide reprice put the two sides on different scales and the
    # division was meaningless. On 2026-09-30 this board's to-go rows were repriced about 7.6x smaller than the landed
    # ones (landed n=141 median 145 against to-go n=345 median 19, kit item IN-20260930143416-f635) and every group date
    # pulled in by about 7x - at 10:17 EDT the board read 14 Oct, at 10:20, with nothing landed between the two calls,
    # 2 Oct. Counting completions and pricing them in to-go units cancels the scale on both sides: the arithmetic below
    # reduces to (rows still to go) / (rows landed per hour), whatever unit the estimates are in.
    $togoCount = $togo.Count
    $meanTogo = if ($togoCount -gt 0) { $remain / $togoCount } else { 0 }
    # Divided by the window's LIVE hours, not its wall-clock hours (see Get-OutageHours). A window that was all outage
    # still divides by at least one hour, so a burst of landings right after a restart cannot read as infinite.
    $outage = if ($win -gt 0) { Get-OutageHours $win } else { 0 }
    $liveHours = [math]::Max(1.0, [double]$win - $outage)          # 1.0: Max(int, double) binds the int overload and truncates
    $tasksPerHour = if ($win -gt 0) { $n / $liveHours } else { 0 }
    $rate = [math]::Round($tasksPerHour * $meanTogo, 4)          # estimated minutes of to-go work landed per wall-clock hour
    # The two populations' medians are still REPORTED, because a board whose landed rows are priced many times its
    # to-go ones is worth seeing. They no longer DECIDE anything: nothing a landed row is priced at reaches any
    # forecast number, so this gap cannot make a date wrong. $chainScaleSplit, measured above on the to-go
    # population the floor is actually summed from, is what guards the date.
    $landedMedian = Median @($ts | Where-Object { $_.state -in @('integrated', 'done') -and -not (Test-Retired $_) } | ForEach-Object { [int]$_.estMinutes })
    $togoMedian = Median @($togo | ForEach-Object { [int]$_.estMinutes })
    $skew = if ($landedMedian -gt 0 -and $togoMedian -gt 0) { [math]::Round($landedMedian / $togoMedian, 2) } else { 0 }
    $scaleSplit = $pathSpread -gt $ScaleSplitRatio
    $predicted = $null; $basis = $null; $softDate = $false
    if ($remain -le 0) {
        $predicted = 0; $basis = if ($heldOpen) { "all builder and author work integrated; $heldOpen gate or integration row(s) left, see the phases" } else { 'all tasks integrated' }
    } elseif ($rate -gt 0) {
        $byRate = [int][math]::Round(60 * $remain / $rate)
        $predicted = [math]::Max($byRate, $floor)
        $floorWins = $predicted -eq $floor -and $floor -gt $byRate
        if ($floorWins -and $scaleSplit) {
            # The only path where a split scale can still decide the date. It is DATED, with the doubt stated, not
            # refused. Refusing (NO DATE) was the rule until 2026-10-03, and it fired on ordinary variety: G3's chain
            # ran through G4, G5 and G6 rows priced 8 to 255 min, read 4.48x, and the owner's top-priority group lost
            # its date for hours while nothing was mispriced. A chain that genuinely mixes two scales still dates
            # off the chain sum, which leans LATE when the dearer half is on the old scale - the safe direction - and
            # the flag below names the split so the owner can see the date is soft and reprice if it is real.
            $predicted = $floor; $softDate = $true
            $basis = "dependency chain ($floor min) is longer than the measured rate would take ($byRate min). SOFT DATE: the $($floorPath.Count) unlanded rows the chain is summed from fall into two clusters - the dearer half's median is ${pathSpread}x the cheaper half's, against a ${ScaleSplitRatio}x limit, around a chain median of $pathMedian min. If the dearer rows are on an old pricing scale the date is late; reprice them onto the scale the rest of the chain uses."
        } elseif ($floorWins) {
            $basis = "dependency chain ($floor min) is longer than the measured rate would take ($byRate min)"
        } else {
            $basis = "$remain min of work left at $([math]::Round($rate, 1)) min/h - $n task(s) landed in the last $win h ($([math]::Round($tasksPerHour, 2)) task/h) priced at the $([math]::Round($meanTogo, 1)) min mean of the $togoCount row(s) to go"
            if ($outage -gt 0) { $basis += "; $outage h of outage (no session alive) taken out of the $win h window, so the date assumes sessions keep running" }
            if ($scaleSplit) { $basis += "; the chain's own rows fall in two clusters ${pathSpread}x apart, which the counted rate ignores" }
        }
    } else {
        $basis = "no task landed in the last $($DeliveryWindowHours[-1]) h"
    }
    $groupRaw[[string]$g.id] = @{ tasksPerHour = $tasksPerHour; togoCount = $togoCount; meanTogo = $meanTogo; floor = $floor; remain = $remain; heldOpen = $heldOpen }
    [ordered]@{ id = $g.id; name = $g.name; state = $g.state; counts = $counts; etaMinutes = [int]$eta; planPage = $g['planPage']
        forecast = [ordered]@{ remainingMinutes = $remain; floorMinutes = $floor; windowHours = $win; landedInWindow = $n
            outageHours = $outage; liveHours = [math]::Round($liveHours, 2)
            deliveredMinutes = $delivered; ratePerHour = [math]::Round($rate, 2); predictedMinutes = $predicted; ownPredictedMinutes = $predicted; heldOpen = $heldOpen; heldLabel = $heldLabel
            tasksPerHour = [math]::Round($tasksPerHour, 3); meanTogoMinutes = [math]::Round($meanTogo, 1)
            landedMedianMinutes = $landedMedian; togoMedianMinutes = $togoMedian; scaleSkew = $skew; scaleSplit = $scaleSplit
            chainRows = $floorPath.Count; chainMedianMinutes = $pathMedian; chainSplitRatio = $pathSpread; softDate = $softDate
            predictedAt = if ($null -ne $predicted) { $now.AddMinutes($predicted).ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
            basis = $basis }
    }
}


# ---- what the rate cannot price (kit item IN-20261019191314-2d8f) ----
# The predicted finish divides builder/author work by a measured rate. Three things a group still waits on are not
# throughput, so each is a named line beside the date instead of minutes folded into it: the Tier 2 run (wall clock,
# and it starts only when the integrator gets the go), the owner gates (they wait on the owner's time), and the fix
# round a Tier 2 run files (unknown until that run ends). Read-only: the runs folder is never created here.
$runsDir = Join-Path $P.Suites 'runs'
$tier2Runs = @(if (Test-Path -LiteralPath $runsDir) { Get-SuiteRunRecords $P '' '2' })
$tier2Durations = @($tier2Runs | Where-Object { [string]$_['status'] -eq 'done' -and $_['endedAt'] } |
        ForEach-Object { [int]((ConvertTo-UtcTime $_['endedAt']) - (ConvertTo-UtcTime $_['startedAt'])).TotalMinutes })
$tier2Typical = if ($tier2Durations.Count) { [int](Median $tier2Durations) } else { $null }
# The owner's Tier 2 hold (kit item IN-20261019194753-16ca): the planner relays an owner order such as "no Tier 2 run
# until the G14 fixes land and the owner stops the builders" in .streams\suites\tier2-hold.json
# { since, by, reason, item, groups } and deletes the file at the go. Until 2026-10-19 the hold lived only in the
# words of a stream-integrate item, so the page read "pending" for a run that could not start. An empty or missing
# groups list holds every group. An unreadable file is reported as a hold with that reason, never dropped.
$tier2HoldFile = Join-Path $P.Suites 'tier2-hold.json'
$tier2Hold = $null
if (Test-Path -LiteralPath $tier2HoldFile) {
    try {
        $h = Get-Content -LiteralPath $tier2HoldFile -Raw | ConvertFrom-Json
        $tier2Hold = [ordered]@{ since = [string]$h.since; by = [string]$h.by; reason = [string]$h.reason; item = [string]$h.item; groups = @($h.groups | Where-Object { $_ } | ForEach-Object { [string]$_ }) }
    } catch {
        $tier2Hold = [ordered]@{ since = ''; by = ''; reason = "unreadable tier2-hold.json: $($_.Exception.Message)"; item = ''; groups = @() }
    }
}
foreach ($g in $groups) {
    $gid = [string]$g.id
    $gts = @($doc.tasks | Where-Object { $_.group -eq $gid })
    $openGates = @($gts | Where-Object { $_.kind -eq 'gate' -and $_.state -notin @('integrated', 'done') } | ForEach-Object { [string]$_.id })
    $openFix = @($gts | Where-Object { [string]$_.id -match '\.(R\d+F\d+|KF\d+)$' -and $_.state -notin @('integrated', 'done') } | ForEach-Object { [string]$_.id })
    $runs = @($tier2Runs | Where-Object { (Get-SuiteRunGroups $_) -contains $gid })
    $lastRun = if ($runs.Count) { $runs[-1] } else { $null }
    $t2 = [ordered]@{ state = 'pending'; run = $null; startedAt = $null; endedAt = $null; typicalMinutes = $tier2Typical; leftMinutes = $null }
    if ([string]$g.state -eq 'closed') { $t2.state = 'closed' }
    elseif ($lastRun -and (Test-SuiteRunAlive $lastRun)) {
        $t2.state = 'running'; $t2.run = [string]$lastRun['id']; $t2.startedAt = [string]$lastRun['startedAt']
        if ($null -ne $tier2Typical) { $t2.leftMinutes = [math]::Max(0, $tier2Typical - [int]($now - (ConvertTo-UtcTime $lastRun['startedAt'])).TotalMinutes) }
    } elseif ($lastRun -and [string]$lastRun['status'] -eq 'done') {
        $t2.state = 'ended'; $t2.run = [string]$lastRun['id']; $t2.startedAt = [string]$lastRun['startedAt']; $t2.endedAt = [string]$lastRun['endedAt']
    } elseif ($lastRun) {
        # Not alive and not done: the run died (marked 'abandoned', or a dead 'running' record not yet marked). It
        # filed no fix round, so the round is unknown because of it, not because a run is still to come
        # (kit item IN-20261019194343-5cfc).
        $t2.state = 'abandoned'; $t2.run = [string]$lastRun['id']; $t2.startedAt = [string]$lastRun['startedAt']
    }
    $t2['hold'] = $null
    $lastAbandoned = $t2.state -eq 'abandoned'
    # A hold matters only while no run is going: a running run is shown running, an ended one ended.
    if ($tier2Hold -and $t2.state -in @('pending', 'abandoned') -and (-not $tier2Hold.groups.Count -or $tier2Hold.groups -contains $gid)) {
        $t2.state = 'held'; $t2['hold'] = $tier2Hold
    }
    $fixState = if ($t2.state -in @('pending', 'running', 'abandoned', 'held')) { 'unknown' } elseif ($openFix.Count) { 'open' } else { 'none' }
    $fixReason = if ($lastAbandoned) { 'last run abandoned' } elseif ($fixState -eq 'unknown') { 'until the run ends' } else { '' }
    $g['phases'] = [ordered]@{
        tier2 = $t2
        ownerGates = [ordered]@{ count = $openGates.Count; ids = @($openGates) }
        fixRound = [ordered]@{ state = $fixState; reason = $fixReason; open = $openFix.Count; ids = @($openFix) }
        rateCovers = 'builder and author work only'
    }
}
# ---- queued groups: dated in focus order, at the focus group's live capacity ----
# Only the focus group(s) are worked; every other open group is frozen until the focus moves on, so it is dated as a
# QUEUE: the first one after the focus starts when the last focus group finishes, each later one when the one before
# it finishes, in board order. Its work is priced at the BOARD's live capacity - the focus groups' measured tasks per
# hour, the same task-counted unit the focus date uses - times the queued group's own to-go row count, so the scale of
# its estimates cancels exactly as it does for a focus group. The chain floor (Get-UpChainMinutes) still holds.
# A queued group behind an undated focus group, or behind a focus that landed nothing in the widest window, is
# undated: there is no measured capacity to price it at, and inventing one is the error this replaced.
$focusIds = @((Get-FocusGroups $doc $P).groups)
$focusGroups = @(foreach ($fid in $focusIds) { $groups | Where-Object { $_.id -eq $fid } })
$capacity = 0.0; $poolRows = 0
foreach ($fg in $focusGroups) { $capacity += [double]$groupRaw[[string]$fg.id].tasksPerHour; $poolRows += [int]$groupRaw[[string]$fg.id].togoCount }
# THE FOCUS POOL. The focus groups share one capacity, so the last of them cannot finish later than every focus row to
# go divided by the focus capacity. A group newly ADDED to the focus has the same defect as a frozen one - its own
# window is mostly the time it was frozen (G5 joined G4 on 2026-10-08 at 23:22Z with 3 landings in 168 h and dated
# itself 13 Dec) - so its own date is capped at the pool date, and a focus group with no landing of its own is dated
# from the pool rather than left undated. A focus group whose own rate is faster keeps its own, earlier, date.
$poolMinutes = if ($capacity -gt 0 -and $poolRows -gt 0) { [int][math]::Round(60 * $poolRows / $capacity) } else { $null }
foreach ($fg in $focusGroups) {
    $f = $fg.forecast; $r = $groupRaw[[string]$fg.id]
    if ($null -eq $poolMinutes -or $r.remain -le 0) { continue }
    if ($null -ne $f.predictedMinutes -and [int]$f.predictedMinutes -le [math]::Max($poolMinutes, [int]$r.floor)) { continue }
    $own = if ($null -ne $f.predictedMinutes) { "its own rate ($($f.tasksPerHour) task/h) would say $($f.predictedMinutes) min" } else { 'it has no landing of its own to date it from' }
    $pred = [math]::Max($poolMinutes, [int]$r.floor)
    $f.predictedMinutes = $pred; $f.softDate = $false
    $f.predictedAt = $now.AddMinutes($pred).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $f.basis = "focus pool: the $poolRows row(s) to go across focus group(s) $($focusIds -join '+') at their combined $([math]::Round($capacity, 2)) task/h take $poolMinutes min; $own, which measures the time before it was in focus"
    if ([int]$r.floor -gt $poolMinutes) { $f.basis += "; held to the $($r.floor) min dependency chain, which is longer" }
}
$focusUndated = @($focusGroups | Where-Object { $null -eq $_.forecast.predictedMinutes })
$cursor = $null; $cursorBy = $null
if ($focusGroups.Count -and -not $focusUndated.Count) {
    $last = @($focusGroups | Sort-Object { [int]$_.forecast.predictedMinutes } -Descending)[0]
    $cursor = [int]$last.forecast.predictedMinutes; $cursorBy = [string]$last.id
}
foreach ($g in $groups) {
    $f = $g.forecast
    if ($g.id -in $focusIds) { $f.dating = 'focus'; continue }
    if ([string]$g.state -eq 'closed') { $f.dating = 'closed'; continue }
    $f.dating = 'queued'
    $r = $groupRaw[[string]$g.id]
    $f.ownTasksPerHour = $f.tasksPerHour; $f.ownRatePerHour = $f.ratePerHour
    $f.softDate = $false
    $f.tasksPerHour = [math]::Round($capacity, 3)
    $f.ratePerHour = [math]::Round($capacity * $r.meanTogo, 2)
    if ($r.remain -le 0) {
        $f.predictedMinutes = 0; $f.predictedAt = $now.ToString('yyyy-MM-ddTHH:mm:ssZ')
        $f.basis = if ($r.heldOpen) { "all builder and author work integrated; $($r.heldOpen) gate or integration row(s) left, see the phases" } else { 'all tasks integrated' }
        continue
    }
    if ($null -eq $cursor -or $capacity -le 0) {
        $why = if (-not $focusGroups.Count) { 'there is no focus group' }
        elseif ($focusUndated.Count) { "focus group $(@($focusUndated | ForEach-Object { $_.id }) -join '+') has no date" }
        else { "the focus group(s) $($focusIds -join '+') landed nothing in the last $($DeliveryWindowHours[-1]) h, so there is no measured capacity" }
        $f.predictedMinutes = $null; $f.predictedAt = $null
        $f.basis = "queued behind the focus, not worked until it moves on, and undated: $why"
        continue
    }
    $byRate = [int][math]::Round(60 * $r.togoCount / $capacity)
    $seq = $cursor + $byRate
    $pred = [math]::Max($seq, [int]$r.floor)
    $f.startsAfterMinutes = $cursor; $f.queuedBehind = $cursorBy
    $f.predictedMinutes = $pred
    $f.predictedAt = $now.AddMinutes($pred).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $f.basis = "queued behind $cursorBy (frozen by the focus rule until then): starts in $cursor min when $cursorBy finishes, then $($r.togoCount) row(s) at the focus rate of $([math]::Round($capacity, 2)) task/h = $byRate min"
    if ([int]$r.floor -gt $seq) { $f.basis += "; held to the $($r.floor) min dependency chain, which is longer" }
    $cursor = $pred; $cursorBy = [string]$g.id
}
# An INTEGRATION row its integrator set building has no claim; the integrator lock is its liveness. The watchdog keeps
# such a row (Test-IntegratorKeepsRow), so it is not orphaned here either: G3.T900 showed 'orphaned, no watchdog will
# free it' for 49 min while f13d2669 beat a fresh lock through its suite run (kit item IN-20261005020647-63c2).
$intHold = Get-IntegratorHold $P
$tasks = foreach ($t in $doc.tasks) {
    $last = @($t.history)[-1]
    $started = if ($t.state -eq 'building') { Get-StateEntry $t 'building' } else { $null }
    $elapsed = if ($started) { Age $started.at } else { $null }
    $ticketing = Test-Ticketing $t
    $intKept = ($t.state -eq 'building' -and -not $t.claim -and (Test-IntegratorKeepsRow $intHold $t $started))
    # A ticketing row is timed from when the author CLAIMED it, not from a state move: it has not moved state at all,
    # which is exactly why it was invisible. claim.at is written by Claim-Task.ps1 and never refreshed, unlike beat.
    if ($ticketing -and $t.claim['at']) { $elapsed = Age $t.claim.at }
    [ordered]@{ id = $t.id; group = $t.group; title = $t.title; kind = $t.kind; state = $t.state; est = $t.estMinutes
        # The bucket the page and the counts use: `ticketing` for a planned row a live author holds, else the state.
        bucket = Bucket $t; ticketing = $ticketing
        # claim is the one-line human form. The page needs the parts, so they are carried separately rather than
        # parsed back out of the sentence.
        claim = if ($t.claim) { "$($t.claim.session) (beat $(Age $t.claim.beat) min)" } else { $null }
        claimSession = if ($t.claim) { $t.claim.session } else { $null }
        claimRole = if ($t.claim) { $t.claim.role } else { $null }
        claimBeatMinutes = if ($t.claim) { Age $t.claim.beat } else { $null }
        elapsed = $elapsed; overrun = ($null -ne $elapsed -and $elapsed -gt 2 * [int]$t.estMinutes)
        # A `building` task with no claim is orphaned: the session that set it building ended without a rollback, and
        # the watchdog only ever breaks a CLAIM, so nothing frees it. It is invisible until someone re-states it.
        orphaned = ($t.state -eq 'building' -and -not $t.claim -and -not $intKept)
        integratorHold = if ($intKept) { "integrator $($started.by) (lock beat $(if ($null -ne $intHold.beatAge) { [int]$intHold.beatAge } else { '?' }) min)" } else { $null }
        critical = ($chain[$t.id] -eq (($doc.tasks | Where-Object { $_.group -eq $t.group } | ForEach-Object { $chain[$_.id] } | Measure-Object -Maximum).Maximum) -and $t.state -notin @('done', 'integrated'))
        # The page answers "why is this category not finished yet", which a state alone cannot: a task nobody has
        # claimed may be waiting on another task rather than on a free builder. dependsOn is carried so the page can
        # tell those two apart without opening tasks.json a second time and disagreeing with this model.
        dependsOn = @($t.dependsOn)
        last = "$($last.at) $($last.by): $($last.note)" }
}
# An owner-queue entry is a '- ' bullet OR any line carrying the ' | ' field separator. Authors write both shapes:
# on 2026-09-29, 706 of the 882 lines in owner\questions.md had no leading '- ', so a '- *' filter hid 80% of the
# owner's queue, including side effects addressed to him by name. Prose in gates.md carries no ' | ', so it stays out.
# A line the owner has answered is re-written in place with a leading 'RESOLVED ' token and is then out of the queue.
# The rest of the line is left byte-identical, so the record still reads as written and a diff shows only the token.
function Lines([string] $f) {
    if (-not (Test-Path $f)) { return ,@() }
    ,@(Get-Content $f | Where-Object { $_ -notmatch '^\s*RESOLVED\s' -and ($_ -like '- *' -or $_ -match '\S\s\|\s') })
}
# The two kinds in the queue are NOT the same thing, and one number over both is not actionable: an escalation (below)
# waits on the owner, while a '<task> | <question> | <default applied> | <reasoning>' line, bulleted or not, is a
# decision already taken under standing owner authority and needs no answer. On 2026-09-29 the queue read 620 while the
# owner-actionable number was 16. Both stay in the queue (Lines), because the record is the point; the count the owner
# triages by is this one. RESOLVED is already filtered out by Lines, so a bullet answered in place drops out of both.
# The bullet is NOT the shape. stream-plan's own rule wrote applied defaults as '- ' lines, and authors did too, so on
# 2026-10-04 the tile read '2 owner questions' for '- G3.T359 | <question> | <default> | <why>' decisions already taken
# under standing authority (kit item IN-20261004203020-5f5e). A line is an ESCALATION when it carries an escalate
# token (ESCALATE, OWNER-DECIDES, 'owner decides', 'needs owner sign-off'), or when it carries no default: fewer than
# four ' | ' fields and no 'applied default' / 'default applied' text. Every other line is an applied default.
function Test-Escalation([string] $line) {
    if ($line -cmatch '\bESCALATE\b|\bOWNER-DECIDES\b' -or $line -match '(?i)\bowner decides\b|\bneeds owner sign-off\b') { return $true }
    if ($line -match '(?i)\bapplied default\b|\bdefault applied\b') { return $false }
    @($line -split '\s\|\s').Count -lt 4
}
function Escalations($lines) {
    ,@(@($lines) | Where-Object { Test-Escalation $_ })
}
# worktrees.md is append-only with a status word per line, so ONE tree gets several lines as it moves
# building/built/abandoned/removed. Counting lines told the owner "199 worktrees" on 2026-09-29 against 10 real
# directories. Count each PATH once, by its LAST line, and drop a path whose last line records a removal. A line
# that says "build output pruned" KEEPS the tree, so it stays in the count.
function Worktrees([string] $f) {
    if (-not (Test-Path $f)) { return ,@() }
    $last = [ordered]@{}
    foreach ($l in @(Get-Content $f)) {
        $parts = @($l -split '\s\|\s')
        if ($parts.Count -lt 4) { continue }
        $last[$parts[1].Trim().ToLowerInvariant()] = $parts[3].Trim()
    }
    # A path is also out when the directory is gone: 30 trees were removed by hand on 2026-09-29 without a ledger line,
    # and a number the owner cannot act on is worse than no number. The ledger keeps the history either way.
    ,@($last.Keys | Where-Object { $last[$_] -notmatch '^removed\b' -and (Test-Path $_) })
}

$roles = [ordered]@{}
# A role is seen when any of its sessions wrote history, holds a claim with a fresh beat, or (integrator) refreshed the
# lock. Beats never write history, so history alone makes a builder deep in one task look absent. A session name starts
# with its role, but the same role is spelled several ways across sessions (integ-, int-, builder-), so the prefix is
# resolved through RoleAlias. A claim carries its role outright, and the integrator lock is the integrator by
# definition, so both name the role rather than guessing it from the session id.
$RoleAlias = $script:SessionRoleAlias
function Seen([string] $session, [string] $at, [string] $role) {
    if (-not $at) { return }
    $r = if ($role) { $role } elseif ($session) { ($session -split '-')[0] } else { return }
    if ($RoleAlias.ContainsKey($r)) { $r = $RoleAlias[$r] }
    if (-not $roles[$r] -or $roles[$r] -lt $at) { $roles[$r] = $at }
}
foreach ($t in $doc.tasks) {
    foreach ($h in @($t.history)) { Seen $h.by $h.at }
    $c = $t['claim']; if ($c -is [Collections.IDictionary]) { Seen $c['session'] $c['beat'] $c['role'] }
}
if (Test-Path $P.IntLock) { try { $l = Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String; Seen $l['session'] $l['beat'] 'integrate' } catch { } }
# A claim that came back NONE leaves an idle beat (lib\Streams.ps1 Set-IdleBeat): the session is running, just idle.
$idleBeats = @(Get-IdleBeats $P)
foreach ($b in $idleBeats) { Seen $b['session'] $b['at'] $b['role'] }

# Live sessions per role. The building tile counts TASKS in building, which is not the number of builders running: a
# builder handing a patch to its verifier, releasing a row or claiming the next one holds no building task for a few
# minutes. On 2026-10-01 the board read "building 3" while six builders were working. A session is live when it wrote
# history or beat a claim inside its role's limit (the same limits the watchdog breaks claims on); claimed counts the
# live sessions holding a claim at this moment. Role is resolved the same way Seen resolves it.
# The rule lives in lib\Streams.ps1 (Get-SessionActivity, Get-LiveSessionIds), shared with the claimable buffer below.
$activity = Get-SessionActivity $P $doc $idleBeats
$QuietMinutes = 20
$sessLast = $activity.last; $sessClaim = $activity.claim
$sessions = [ordered]@{}
foreach ($r in @('author', 'build', 'integrate')) {
    $limit = $script:SessionLimitMinutes[$r]
    $ids = @(Get-LiveSessionIds $activity $r $now)
    # working = live and holding a claim now; idle = live with no claim that polled or wrote inside $QuietMinutes (an
    # idle beat, or between tasks); quiet = live with no claim and nothing written for longer than that. A looping
    # session that polls NONE refreshes its idle beat every poll, so a quiet one has stopped claiming: on 2026-10-04 the
    # board read "4 idle" for four builders that had written nothing for 35-45 minutes while 43 rows were claimable (kit
    # item IN-20261004152204-9ede). They stay live until the role limit, so the count still says how many may return.
    # A runner unit reads from its runner's state (lib\Streams.ps1 Get-RunnerUnits): a unit in flight is working with or
    # without a claim (it may have just released its ticket and be finishing), and the current unit of a sleeping runner
    # is idle, never quiet, because its runner polls without writing (kit item IN-20261004202801-5449).
    $units = $activity.units
    $isUnit = { param($s) $units -and $units.ContainsKey($s) }
    $nWork = @($ids | Where-Object { $sessClaim.ContainsKey($_) -or ((& $isUnit $_) -and $units[$_].running) }).Count
    $quietIds = @($ids | Where-Object { -not $sessClaim.ContainsKey($_) -and -not (& $isUnit $_) -and (Age $sessLast[$_]) -gt $QuietMinutes })
    $sessions[$r] = [ordered]@{ live = $ids.Count; claimed = @($ids | Where-Object { $sessClaim.ContainsKey($_) }).Count; working = $nWork; idle = $ids.Count - $nWork - $quietIds.Count; quiet = $quietIds.Count; limitMinutes = $limit
        quietIds = $quietIds
        list = @($ids | ForEach-Object { [ordered]@{ session = $_; ageMinutes = Age $sessLast[$_]; task = $sessClaim[$_] } }) }
}
$flags =[Collections.Generic.List[string]]::new()
foreach ($t in $tasks) {
    if ($t.orphaned) { $flags.Add("$($t.id) building $($t.elapsed) min with NO claim: orphaned, no watchdog will free it") }
    elseif ($t.overrun) { $flags.Add("$($t.id) $($t.bucket) $($t.elapsed) min, estimate $($t.est)") }
}
foreach ($g in $groups) { if ($g.state -eq 'blocked') { $flags.Add("group $($g.id) blocked") } }
# A row an author already holds is not waiting for one, so ticketing rows come out of the author demand. Without that
# the board could read "4 tasks waiting for author" while all four were being written at that moment.
# Demand counts the FOCUS set only, the rows Claim-Task.ps1 and Integrate-Patch.ps1 will offer: a row outside it waits
# for its group by design. At 04:00Z on 2026-10-09 the flag read "69 tasks waiting for author, no author session seen in
# the last hour" while all 69 planned rows were G6, focus was G4 and five authors sat correctly idle (kit item
# IN-20261009040231-3d7c).
$focusSetIds = Get-FocusSet $doc
$needs = @{ author = @($doc.tasks | Where-Object { $_.state -eq 'planned' -and $_.kind -ne 'gate' -and -not (Test-Ticketing $_) -and $focusSetIds.Contains([string]$_.id) }).Count; build = @($doc.tasks | Where-Object { $_.state -eq 'ticketed' -and $_.kind -in $script:BuildKinds -and $focusSetIds.Contains([string]$_.id) }).Count; integrate = @($doc.tasks | Where-Object { $_.state -eq 'built' -and $focusSetIds.Contains([string]$_.id) }).Count }
foreach ($r in $needs.Keys) { if ($needs[$r] -gt 0 -and (-not $roles[$r] -or (Age $roles[$r]) -gt 60)) { $flags.Add("$($needs[$r]) tasks waiting for $r, no $r session seen in the last hour") } }

# ---- claimable build work ----
# A builder that claims NONE writes nothing to tasks.json, so the live-session count above cannot see it: on 2026-10-02
# the board read "build 0 live" while six builders polled an empty queue (kit item IN-20261002130802-14a3). What the
# owner needs to know in that state is not how many builders are alive but whether there is anything for them to take,
# and if not, what the ticketed rows are waiting on. Claimable is computed with Claim-Task.ps1's own gates in its own
# order - released group, no live claim, no live inbox hold, then Test-BuildReady - so the count is exactly the rows a
# build claim would offer now. Dependencies count as ready at built or later, as the claim does: a patch that is built
# but not yet integrated already rides into the next worktree's base.
$releasedIds = @($doc.groups | Where-Object { $_.state -in @('released', 'integrating') } | ForEach-Object { $_.id })
$heldRows = Get-InboxHeldRows $P
$cl = Get-BuildClaimable $P $doc
$buildTicketed = $cl.ticketed; $claimableIds = $cl.ids; $waitingOnDeps = $cl.waiting
$nNotReleased = $cl.notReleased; $nClaimed = $cl.claimed; $nHeld = $cl.held
# What one root needs before the chain above it can move. Only what the board itself says, never a guess at who is
# running: 'needs author' means planned with no live author claim, not that no author exists.
function Get-RootNeed([string] $id) {
    $x = $byId[$id]
    if (-not $x) { return 'not on the board' }
    if ($x.kind -eq 'gate') { return 'owner gate' }
    if ($x.group -notin $releasedIds) { return "group $($x.group) not released" }
    switch ($x.state) {
        'planned' { if (Test-Ticketing $x) { 'being ticketed' } else { 'needs author' } }
        'ticketed' {
            if (Test-ClaimLive $x) { "claimed by $($x.claim.session)" }
            elseif ($heldRows.Contains($id)) { 'held by an inbox item' }
            elseif ($x.kind -eq 'integration') { 'integrator' }
            else { 'needs builder' }
        }
        'building' { if (Test-ClaimLive $x) { 'building' } else { 'building with no live claim' } }
        default { [string] $x.state }
    }
}
# The roots a waiting row's chain bottoms out on: walk the dependencies that are not built yet, through every planned or
# ticketed row that itself still waits, and stop at the first row whose own dependencies are all ready (or that is in
# some other state - building, blocked, a gate). Those are the rows somebody has to move before the chain can.
$rootBlocks = @{}
foreach ($t in $waitingOnDeps) {
    $seen = [Collections.Generic.HashSet[string]]::new()
    $stack = [Collections.Generic.Stack[string]]::new()
    foreach ($d in @($t.dependsOn)) { if ($d) { $stack.Push([string]$d) } }
    $mine = [Collections.Generic.HashSet[string]]::new()
    while ($stack.Count) {
        $d = $stack.Pop()
        if (-not $seen.Add($d)) { continue }
        $x = $byId[$d]
        if ($x -and $x.state -in $script:BuildReadyStates) { continue }
        $unready = @(if ($x) { @($x.dependsOn) | Where-Object { $_ -and -not ($byId[$_] -and $byId[$_].state -in $script:BuildReadyStates) } })
        if ($x -and $unready.Count -and $x.state -in @('planned', 'ticketed') -and $x.kind -ne 'gate') { foreach ($u in $unready) { $stack.Push([string]$u) } }
        else { [void]$mine.Add($d) }
    }
    foreach ($r in $mine) { $rootBlocks[$r] = 1 + [int]$rootBlocks[$r] }
}
$roots = @($rootBlocks.Keys | Sort-Object @{ e = { $rootBlocks[$_] }; Descending = $true }, @{ e = { $_ }; Descending = $false } |
    ForEach-Object { [ordered]@{ id = $_; state = if ($byId[$_]) { [string]$byId[$_].state } else { $null }; need = Get-RootNeed $_; blocks = $rootBlocks[$_] } })
# Why an author claim takes a row when it does: the author sort ranks a planned row by its EFFECTIVE group, the earliest
# group among the row and every row that depends on it (lib\Streams.ps1 Get-EffectiveGroupRank). Listed only for the
# rows that inherit an earlier group, so the planner can see a later-group root sorting with the group it holds.
$effRank = Get-EffectiveGroupRank $doc
$groupAt = @{}; $gix = 0; foreach ($g in $doc.groups) { $groupAt[$gix++] = [string]$g.id }
$authorRank = @($doc.tasks | Where-Object { $_.state -eq 'planned' -and $_.kind -ne 'gate' -and $effRank[$_.id].rank -lt $effRank[$_.id].own } |
    ForEach-Object { [ordered]@{ id = [string]$_.id; group = [string]$_.group; effectiveGroup = $groupAt[$effRank[$_.id].rank]; via = $effRank[$_.id].via } })
$claimable = [ordered]@{ count = $claimableIds.Count; ticketed = $buildTicketed.Count; ids = @($claimableIds); focusGroup = [string]$cl.focusGroup; notFocus = [int]$cl.notFocus
    waitingOnDeps = $waitingOnDeps.Count; heldByInbox = $nHeld; claimedLive = $nClaimed; groupNotReleased = $nNotReleased; roots = @($roots) }
if ($buildTicketed.Count -gt 0 -and $claimableIds.Count -eq 0) {
    $why = [Collections.Generic.List[string]]::new()
    $RootsShown = 8
    if ($roots.Count) {
        $named = @($roots | Select-Object -First $RootsShown | ForEach-Object { "$($_.id) ($($_.need))" }) -join ', '
        if ($roots.Count -gt $RootsShown) { $named += " +$($roots.Count - $RootsShown) more" }
        $why.Add("$($waitingOnDeps.Count) wait on roots $named")
    }
    if ($nHeld) { $why.Add("$nHeld held by a live inbox item") }
    if ($nClaimed) { $why.Add("$nClaimed under a live claim") }
    if ($nNotReleased) { $why.Add("$nNotReleased in groups not released") }
    if ($cl.notFocus) { $why.Add("$($cl.notFocus) outside the focus group $($cl.focusGroup) (frozen until their turn)") }
    $flags.Add("ticketed $($buildTicketed.Count), claimable 0, so every builder polls an empty queue: $($why -join '; ')")
}
# Quiet builders while rows wait: the queue is not the problem, the sessions are. Restart them or start a build runner.
if ($sessions['build'].quiet -gt 0 -and $claimableIds.Count -gt 0) {
    $qs = @($sessions['build'].quietIds | ForEach-Object { "$_ ($(Age $sessLast[$_]) min)" }) -join ', '
    $flags.Add("$($sessions['build'].quiet) build sessions quiet (no claim, nothing written for over $QuietMinutes min) while $($claimableIds.Count) rows are claimable: $qs; restart them or start a build runner")
}
# ---- claimable buffer (owner ruling 2026-10-02, kit item IN-20261002160453-9384) ----
# Target: 2 claimable rows per live builder (lib\Streams.ps1 Get-BuildBuffer). It is a board flag only: the author sort
# is ready-first at all times (Claim-Task.ps1, kit item IN-20261002161525-69c9). Below it the board raises PIPELINE DRY with the reason that holds the most rows back:
#   no author live                    - planned rows wait and no author session is live;
#   RED queue                         - planned rows whose last note queues a RED re-run behind the main-grader lock
#                                       (the pre-2026-10-02 author RED, IN-20261002160453-ce2a);
#   waiting on unticketed dependency  - ticketed rows whose chain bottoms out on a row that is still planned;
#   nothing ready                     - no planned row has every dependency built, so ticketing cannot help yet;
#   authors behind                   - planned rows are ready to ticket and wait for an author;
#   focus group exhausted            - ticketed rows exist only outside the focus set, frozen until their group's turn
#                                       (2026-10-05 priority-focus-design 3.1).
# The reason that holds the most rows wins.
$buffer = Get-BuildBuffer $P $doc $activity $cl
# Planned rows count only inside the focus set (spec 3.1, review F13): a frozen later group's planned rows are not
# work any author may take, so they must not read as "authors behind" or "no author live".
$plannedOpen = @($doc.tasks | Where-Object { $_.state -eq 'planned' -and $_.kind -ne 'gate' -and $_.group -in $releasedIds -and $focusSetIds.Contains([string]$_.id) })
$redQueued = @($plannedOpen | Where-Object { $h = @($_.history); $n = if ($h.Count) { [string]$h[-1].note } else { '' }; $n -match 'RED' -and $n -match 'queued|main-grader' }).Count
$readyPlanned = @($plannedOpen | Where-Object { -not (Test-Ticketing $_) -and (Test-ReadyWhenTicketed $doc $_) }).Count
# A ticketed row waits on an unticketed dependency when any row in its not-yet-built chain is still planned.
function Test-WaitsOnPlanned($t) {
    $seen = [Collections.Generic.HashSet[string]]::new(); $stack = [Collections.Generic.Stack[string]]::new()
    foreach ($d in @($t.dependsOn)) { if ($d) { $stack.Push([string]$d) } }
    while ($stack.Count) {
        $d = $stack.Pop(); if (-not $seen.Add($d)) { continue }
        $x = $byId[$d]
        if (-not $x -or $x.state -in $script:BuildReadyStates) { continue }
        if ($x.state -eq 'planned') { return $true }
        foreach ($e in @($x.dependsOn)) { if ($e) { $stack.Push([string]$e) } }
    }
    $false
}
$waitUnticketed = @($waitingOnDeps | Where-Object { Test-WaitsOnPlanned $_ }).Count
$dryReason = $null
if ($buffer.short) {
    # The reason holding the most rows wins; ties go in the order listed.
    # "focus group exhausted" is a STATE, not a count: it holds only when the focus set has no planned or ticketed
    # row left that nobody holds (a row an author is writing is not supply), and then it wins. Competing on n let the later groups' frozen rows (89 on 2026-10-05) outvote real
    # focus reasons such as "authors behind" (final review I3).
    $focusOpen = @($doc.tasks | Where-Object { $_.state -in @('planned', 'ticketed') -and $_.kind -ne 'gate' -and $focusSetIds.Contains([string]$_.id) -and -not (Test-ClaimLive $_) }).Count
    $why = @(
        [pscustomobject]@{ n = $(if ($focusOpen -eq 0 -and $cl.notFocus) { [int]::MaxValue } else { 0 }); text = "focus group $($cl.focusGroup) exhausted ($($cl.notFocus) ticketed rows wait in later groups)" }
        [pscustomobject]@{ n = $redQueued; text = "RED queue ($redQueued planned rows wait on a queued RED re-run)" }
        [pscustomobject]@{ n = $waitUnticketed; text = "waiting on unticketed dependency ($waitUnticketed ticketed rows wait on a planned row)" }
        [pscustomobject]@{ n = $readyPlanned; text = "authors behind ($readyPlanned planned rows are ready to ticket)" }) |
        Where-Object { $_.n -gt 0 } | Sort-Object -Property n -Descending -Stable | Select-Object -First 1
    $dryReason = if ($plannedOpen.Count -and $sessions['author'].live -eq 0) { "no author live ($($plannedOpen.Count) planned)" }
        elseif ($why) { $why.text }
        else { 'nothing ready (no planned row has every dependency built)' }
    $flags.Insert(0, "PIPELINE DRY: claimable $($buffer.claimable) of target $($buffer.target) (2 x $($buffer.liveBuilders) live builders) - $dryReason")
}
$buffer['dry'] = [bool]$buffer.short; $buffer['reason'] = $dryReason
# ---- stale spill tickets (owner ruling 2026-10-12, AUTHOR SPILL) ----
# A ticket an author wrote outside the focus set records the main commit it was written against. Once its group is
# focus, a write-set file changed on main since then means the ticket may cite moved code: flag it so the builder (who
# also gets a STALE-TICKET warning at claim) or an author re-reads it.
$spillDrift = Get-SpillDrift $P $doc
foreach ($dr in $spillDrift) {
    $flags.Add("STALE-TICKET $($dr.id): author spill ticket written against $($dr.base.Substring(0, [Math]::Min(10, $dr.base.Length))); write-set files changed on main since: $($dr.files -join ', ')")
}
# ---- dependency review flags (2026-10-18 dependency review) ----
# FOCUS-PULL: rows of unlisted groups that are in the focus set because focus work depends on them (lib\Streams.ps1
# Get-FocusClosure, finding F3). Named so the owner sees why a builder is working a group the focus does not list.
$fc = Get-FocusClosure $doc $P
if ($fc.pulled.Count) {
    $pulledNamed = @($fc.pulled.Keys | Select-Object -First 8 | ForEach-Object { $x = $byId[[string]$_]; "$_ ($(if ($x) { "$($x.group) $($x.state)" } else { '?' }), for $($fc.pulled[$_]))" }) -join ', '
    if ($fc.pulled.Count -gt 8) { $pulledNamed += " +$($fc.pulled.Count - 8) more" }
    $flags.Add("FOCUS-PULL $($fc.pulled.Count) row(s) outside the focus groups are in the focus set as dependencies of focus work: $pulledNamed")
}
# DEP-REVIEW is emitted below (root-based, model field depReview), after the deadlock check.
# DEP-MOVED: a building row whose base stacked a dependency that has since left built (lib\Streams.ps1
# Add-DependentBounceNotes, finding F6). Its hand-off meets BASE-STALE at integration unless the dependency lands unchanged.
foreach ($t in @($doc.tasks | Where-Object { $_.state -eq 'building' -and $_.claim -and $_.claim.at })) {
    $moved = @($t.history | Where-Object { $_.note -and ([string]$_.note).StartsWith('DEP-MOVED ') -and $_.at -ge $t.claim.at })
    if ($moved.Count) { $flags.Add("DEP-MOVED $($t.id) is building on a base whose dependency left built: $((([string]$moved[-1].note) -split ':')[0])") }
}
# ---- main tree lock and author release rate (kit item IN-20261002161450-c89b) ----
# One holder of .streams\main-grader.lock for more than 20 minutes starves every author RED re-run and every apply. On
# 2026-10-02 that went unseen for 15 hours, while releases fell from 16-20/h to 0-7/h; both are now on the board.
$mainLock = Get-MainTreeLockState $P
if ($mainLock -and $mainLock.minutes -gt $script:MainLockFlagMinutes) {
    $flags.Add("main tree held $($mainLock.minutes) min by '$($mainLock.holder)': author RED re-runs and applies wait behind main-grader.lock")
}
$releases = Get-ReleasesPerHour $doc 6
$buffer['readyPlanned'] = $readyPlanned; $buffer['redQueued'] = $redQueued; $buffer['waitingOnUnticketed'] = $waitUnticketed
$inbox = [ordered]@{}
foreach ($s in $script:InboxSkills) {
    $its = @(Read-InboxItems (Get-InboxPath $P $s))
    $open = @($its | Where-Object { Test-InboxOpen $_ $s })
    $stuck = @($its | Where-Object { $_.status -in 'open', 'taken' -and (Get-InboxAgeMinutes $_) -ge $script:InboxLimitMinutes[$s] })
    $inbox[$s] = [ordered]@{ open = $open.Count; stuck = @($stuck | ForEach-Object { "$($_.id) $($_.status) $(Get-InboxAgeMinutes $_)m: $($_.ask)" }) }
    foreach ($x in $inbox[$s].stuck) { $flags.Add("inbox $s item $x") }
}
# owner\gates.md is HAND-maintained: no script writes it (Init-Streams only creates its header), and the
# "Refreshed ... by" line is typed. So a gate added to the board between refreshes is simply never listed, and
# the owner cannot act on a gate he cannot see. G6.G91 was added 2026-09-29T16:13Z and sat unlisted because the
# file had last been refreshed at 15:19Z; nothing anywhere noticed. Both directions are a fault: a gate task
# with no line is invisible, and a line naming no gate task cannot be passed, because /stream-integrate gate
# resolves the id against tasks.json. Matching is anchored on the id at the START of a line, never as a
# substring: every gate id also appears inside other gates' prose, which made an earlier substring sweep delete
# a live gate's line.
$gateTasks = @($doc.tasks | Where-Object { $_.kind -eq 'gate' } | ForEach-Object { $_.id })
$gateLines = @(@(Get-Content $P.Gates -ErrorAction SilentlyContinue) |
    Select-String -Pattern '^\s*(?:RESOLVED\s+)?-\s+(\S+?)\s+\|' |
    ForEach-Object { $_.Matches[0].Groups[1].Value })
$gateUnlisted = @($gateTasks | Where-Object { $_ -notin $gateLines })
$gateOrphan = @($gateLines | Where-Object { $_ -notin $gateTasks })
if ($gateUnlisted.Count) { $flags.Add("gates.md is missing $($gateUnlisted.Count) gate task(s) the owner cannot see: $($gateUnlisted -join ', ')") }
if ($gateOrphan.Count) { $flags.Add("gates.md lists $($gateOrphan.Count) id(s) that are not gate tasks, so they cannot be passed: $($gateOrphan -join ', ')") }

# A non-gate row that dependsOn its own group's integration task can never be built: stream-integrate claims that
# task only after every code, docs and mockup row in the group is integrated, and Claim-Task.ps1 only offers a
# ticketed row whose dependencies are built or later. Add-Tasks.ps1 and Revise-Task.ps1 refuse the shape now, so
# what is left is the rows that predate the refusal - G1.T12 on 2026-09-30, which has a written ruling. The flag
# names them, because a deadlocked group looks exactly like a slow one (kit item IN-20260930190112-23e6).
$deadlocks = [Collections.Generic.List[string]]::new()
foreach ($t in @($doc.tasks)) {
    if ($t['kind'] -in @('gate', 'integration')) { continue }
    if ($t.state -in @('integrated', 'done')) { continue }
    $ownInt = @($doc.tasks | Where-Object { $_['kind'] -eq 'integration' -and [string] $_['group'] -eq [string] $t['group'] })
    if ($ownInt.Count -and $ownInt[0].id -in @($t.dependsOn)) { $deadlocks.Add("$($t.id) ($($t.state)) -> $($ownInt[0].id)") }
}
# The flag used to end "so neither can move without a step-B ruling", which stopped being true once the ruling landed:
# stream-integrate step B now claims the integration task while leaving out exactly these rows (SKILL.md section B,
# planner ruling IN-20260930190044-8bf9), so each one is SEQUENCED after its group's green run, not deadlocked. On
# 2026-10-01 the stale wording read as a stall on G1 while G1.T12 was simply third in a serial chain. The row is still
# named, because it finishes after the suites and so the group cannot close before it.
if ($deadlocks.Count) { $flags.Add("$($deadlocks.Count) row(s) dependsOn their own group's integration task, so each builds only after that group's green run (step-B exception, IN-20260930190044-8bf9); the group closes after them: $($deadlocks -join ', ')") }

# DEP-REVIEW (owner request IN-20261018143920-ebda, kit item IN-20261018144658-c28b): a dependsOn edge nobody stated a
# reason for (no entry in the row's dependsWhy map, written by Revise-Task.ps1) can be an order that no longer holds,
# and it costs most when its ROOT - the unmet ancestor with no unmet dependency of its own - holds several ticketed rows
# that have waited for days. Edges with a derived mechanical reason (lib\Streams.ps1 Get-DependsWhy: a gate or integration
# row on either end, a mockup, a shared write-set file) and edges onto a row the dependent's title names count as stated.
# Thresholds: $script:DepReviewMinWaiters waiters, $script:DepReviewMinDays days (STREAM_DEP_REVIEW_MIN_WAITERS / _MIN_DAYS
# override them, for the self-tests). Read only; the plan reviews the edges (never a gate or integration edge without
# the owner's sign-off).
$DepReviewWaitMinutes = [double] $script:DepReviewMinDays * 24 * 60
$depById = @{}; foreach ($t in @($doc.tasks)) { $depById[[string] $t.id] = $t }
function Get-UnmetRoots([string] $id, $seen) {
    if ($seen.Contains($id)) { return @() }; [void] $seen.Add($id)
    $row = $depById[$id]; if (-not $row) { return @() }
    $up = @(@($row.dependsOn) | Where-Object { $depById[[string] $_] -and $depById[[string] $_].state -notin @('built', 'integrated', 'done') })
    if (-not $up.Count) { return @($id) }
    @($up | ForEach-Object { Get-UnmetRoots ([string] $_) $seen })
}
$depRoots = [ordered]@{}
foreach ($t in @($doc.tasks)) {
    if ($t.state -ne 'ticketed') { continue }
    $tAt = $null; foreach ($h in @($t['history'])) { if ($h -and [string] $h.to -eq 'ticketed' -and $h.at) { $tAt = [string] $h.at } }
    $waited = Age $tAt
    if ($null -eq $waited -or $waited -lt $DepReviewWaitMinutes) { continue }
    foreach ($d in @($t.dependsOn)) {
        $d = [string] $d; $dep = $depById[$d]
        if (-not $dep -or $dep.state -in @('built', 'integrated', 'done') -or $dep['kind'] -in @('gate', 'integration')) { continue }
        if ((Get-DependsWhy $t $d $depById) -ne $script:DependsWhyUnstated) { continue }
        if ([string] $t['title'] -match ('(?<![\w.])' + [regex]::Escape($d) + '(?!\w)')) { continue }
        foreach ($root in @(Get-UnmetRoots $d ([Collections.Generic.HashSet[string]]::new()) | Select-Object -Unique)) {
            if (-not $depRoots.Contains($root)) { $depRoots[$root] = [ordered]@{ root = $root; waiters = [Collections.Generic.List[string]]::new(); edges = [Collections.Generic.List[string]]::new() } }
            if (-not $depRoots[$root].waiters.Contains([string] $t.id)) { $depRoots[$root].waiters.Add([string] $t.id) }
            $depRoots[$root].edges.Add("$($t.id)->$d")
        }
    }
}
$depReview = @($depRoots.Values | Where-Object { $_.waiters.Count -ge $script:DepReviewMinWaiters } | Sort-Object { -$_.waiters.Count }, { $_.root } | ForEach-Object { [ordered]@{ root = $_.root; waiters = @($_.waiters); edges = @($_.edges) } })
if ($depReview.Count) { $flags.Add("DEP-REVIEW: $($depReview.Count) root(s) hold $($script:DepReviewMinWaiters)+ ticketed rows waiting $($script:DepReviewMinDays)+ days behind dependsOn edges with no stated reason (dependsWhy); roots by waiters: $(@($depReview | ForEach-Object { "$($_.root) ($($_.waiters.Count): $($_.edges -join ', '))" }) -join '; ') - planner: state the reason or drop the edge") }
# The board finishes when its LAST group does. The focus groups run concurrently and the queued groups one after
# another behind them (see "queued groups"), so the latest group date IS the last queued group's sequential finish:
# the maximum is taken, never a sum of independent dates. A group with no date leaves the board date open, and the
# count of those is carried so the page can say so rather than quietly report the max of the groups that have one.
# The board rate is the FOCUS rate: summing every group's own rate added the frozen groups' noise to it.
$gPred = @($groups | Where-Object { $null -ne $_.forecast.predictedMinutes })
$gNoPred = @($groups | Where-Object { $null -eq $_.forecast.predictedMinutes })
$boardMinutes = if ($gPred.Count) { [int](($gPred | ForEach-Object { $_.forecast.predictedMinutes } | Measure-Object -Maximum).Maximum) } else { $null }
$boardForecast = [ordered]@{
    predictedMinutes = $boardMinutes
    predictedAt = if ($null -ne $boardMinutes) { $now.AddMinutes($boardMinutes).ToString('yyyy-MM-ddTHH:mm:ssZ') } else { $null }
    drivenBy = if ($gPred.Count) { @($gPred | Sort-Object { $_.forecast.predictedMinutes } -Descending)[0].id } else { $null }
    groupsWithoutDate = @($gNoPred | ForEach-Object { $_.id })
    remainingMinutes = [int](($groups | ForEach-Object { $_.forecast.remainingMinutes } | Measure-Object -Sum).Sum)
    ratePerHour = [math]::Round((($focusGroups | ForEach-Object { $_.forecast.ratePerHour } | Measure-Object -Sum).Sum), 2)
    tasksPerHour = [math]::Round($capacity, 3)
    focusGroups = @($focusIds)
    basis = if ($gPred.Count -eq 0) { 'no group could be dated' }
    elseif ($gNoPred.Count) { "dated in focus order ($($focusIds -join '+') first, then the rest one after another at the focus rate); the last group to finish is $(@($gPred | Sort-Object { $_.forecast.predictedMinutes } -Descending)[0].id); $($gNoPred.Count) group(s) have no date and are not covered" }
    else { "dated in focus order ($($focusIds -join '+') first, then the rest one after another at the focus rate); the last group to finish is $(@($gPred | Sort-Object { $_.forecast.predictedMinutes } -Descending)[0].id)" }
}
foreach ($g in $groups) { if ($null -eq $g.forecast.predictedMinutes) { $flags.Add("group $($g.id) has no predicted finish: $($g.forecast.basis)") } }
foreach ($g in $groups) { if ($g.forecast.softDate) { $flags.Add("group $($g.id) has a SOFT predicted finish: its chain rows fall in two clusters $($g.forecast.chainSplitRatio)x apart; reprice them if the dearer half is on an old scale") } }

# ---- free disk, which nothing on the board watched until 2026-09-30 ----
# A builder that runs out of disk does not report a full disk: it reports a compile or test failure, and the author who
# reads the verdict takes it for a defect in the ticket. On 2026-09-30 this host reached about 1.8 GB free of 126.4 GB
# with six builders live and no flag anywhere. New-TaskWorktree.ps1 gives every task its own tree, and a POPULATED tree
# carries its own bin/obj: measured that day, 599, 592, 506 and 505 MB against 57 MB for a source-only tree, so build
# output is roughly 450 MB of each 500 MB. The threshold therefore scales with the number of live build claims rather
# than sitting at a fixed number, with a floor for the trees that already exist and for a restore or a suites run.
# The constants and the three questions live in lib\Streams.ps1, because Invoke-Watchdog.ps1 prunes build output in
# the same 'warn' band this flag reports: a second copy of the arithmetic here would let the two drift apart.
$PerWorktreeMB = $script:PerWorktreeMB
$liveBuilds = @($tasks | Where-Object { $_.bucket -eq 'building' }).Count
$needMB = Get-DiskNeedMB $liveBuilds
$wtRoot = Get-StreamWorktreeRoot $Repo
$disks = [ordered]@{}
foreach ($pair in @(@('repo', $Repo), @('worktrees', $wtRoot))) {
    $qual = try { [IO.Path]::GetPathRoot($pair[1]) } catch { $null }
    if (-not $qual) { continue }
    # GetPathRoot gives 'C:', and Get-PSDrive wants the NAME, so take the letter itself - trimming does not do it,
    # because the trailing character is the separator and not the colon.
    if ($qual -notmatch '^[A-Za-z]:') { continue }
    # Get-DiskFreeMB carries the STREAM_FREE_MB_TEST seam, so the watchdog reads the same number this flag reports.
    $freeMB = Get-DiskFreeMB $pair[1]
    if ($null -eq $freeMB) { continue }
    # One entry per DRIVE, not per path: the repo and the worktree root are usually on the same one, and two flags
    # about one drive would read as two problems.
    if (-not $disks.Contains($qual)) { $disks[$qual] = [ordered]@{ drive = $qual; freeMB = $freeMB; holds = @() } }
    $disks[$qual].holds += $pair[0]
}
$diskReport = @()
foreach ($k in $disks.Keys) {
    $d = $disks[$k]
    # Under the fixed claim floor, Claim-Task.ps1 refuses build claims (worktrees drive) and Enter-Integrator.ps1 refuses
    # a new integrator lock (repo drive) with REFUSED-DISK, exit 6. Flagged here so the page says WHY nothing starts.
    $refused = $d.freeMB -lt $script:ClaimFloorMB
    $diskReport += [ordered]@{ drive = $d.drive; freeMB = $d.freeMB; holds = @($d.holds); needMB = $needMB
        state = Get-DiskState $d.freeMB $needMB; claimFloorMB = $script:ClaimFloorMB; claimsRefused = $refused }
    $what = @($d.holds) -join ' and '
    if ($refused) {
        $who = @(@($d.holds) | ForEach-Object { if ($_ -eq 'worktrees') { 'build' } else { 'integrate' } }) -join ' and '
        $flags.Add("CLAIMS REFUSED on drive $($d.drive.TrimEnd('\')) - $([math]::Round($d.freeMB / 1024, 1)) GB free is under the $([math]::Round($script:ClaimFloorMB / 1024, 0)) GB claim floor, so no new $who claim starts (REFUSED-DISK, exit 6) until space is freed")
    }
    if ($d.freeMB -lt $needMB) {
        $flags.Add("DISK $($d.drive) holds the $what and has $([math]::Round($d.freeMB / 1024, 1)) GB free, under the $([math]::Round($needMB / 1024, 1)) GB $liveBuilds live build(s) need at about $PerWorktreeMB MB of tree each: a build that fills this drive reports a compile failure, not a full disk")
    } elseif ($d.freeMB -lt 2 * $needMB) {
        $flags.Add("disk $($d.drive) holds the $what and has $([math]::Round($d.freeMB / 1024, 1)) GB free against the $([math]::Round($needMB / 1024, 1)) GB $liveBuilds live build(s) need; bin/obj is about 450 MB of each 500 MB tree")
    }
}

# ---- left to plan: scope not yet cut into rows ----
# PLANNED counts rows waiting for a ticket; it says nothing about the goals no row exists for yet. The owner asked for
# that second number over ALL goals, not only the released groups (kit items IN-20261009131901-10e4 and its amendment
# IN-20261009132301-e0a4). A goal is an acceptance clause (`- id: AC-...` under the top-level `acceptance:` key) of a
# READY requirement file under <repo>\docs\requirements. Templates (DRAFT), worked examples (REVIEW) and retired
# features are not goals; every group scope excludes "anything not READY" too. The folder is resolved from the repo
# root first: tasks.json `requirements` held C:\devops\repos\speedmerchants\docs\requirements, which does not exist on  # history
# SMVMTR1, where the corpus is on D:.
# A clause is PLANNED when any board row names its id, in the row's why, title or tests or in the ticket the row
# carries (measured 2026-10-09: row text named 648 of 955 clauses, row text plus tickets 649). `why` is an ARRAY on
# most rows, so each field is flattened item by item: joining the raw field stringified it as 'System.Object[]' and a
# first draft read only 98 named. A longer token names its prefix too, so 'AC-WVC-CANVAS-014-B' plans 'AC-WVC-CANVAS-014'.
# The number is printed only when the matching can be trusted, and the check is measured, not assumed: every clause
# in the scope of a CLOSED group was built, so a closed group with a clause no row names shows the board does not
# name clauses reliably, and any count would be a guess. Then the tile reads unknown, with the reason, and the raw
# counts stay in the model (`unnamed`) for the planner who backfills the ids. On 2026-10-09 closed G1, G2 and G3 named
# all 327 of theirs; the 306 left were the test-data family and FEAT-CLI-001, which no group scope includes.
function Get-LeftToPlan($doc, [string] $repo) {
    $out = [ordered]@{ known = $false; total = $null; reason = $null; root = $null; files = 0; clauses = 0; named = 0
        unnamed = 0; notReadyClauses = 0; byGroup = [ordered]@{}; notInGroup = $null; notInGroupFiles = @(); unnamedIds = [ordered]@{} }
    $cands = @((Join-Path $repo 'docs\requirements'))
    if ($doc.ContainsKey('requirements') -and $doc['requirements']) { $cands += [string]$doc['requirements'] }
    $root = @($cands | Where-Object { Test-Path -LiteralPath $_ -PathType Container }) | Select-Object -First 1
    if (-not $root) { $out.reason = "no requirements folder: $($cands -join ' and ') do not exist"; return $out }
    $out.root = $root
    $named = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    function AddNames([string] $txt) {
        foreach ($m in [regex]::Matches($txt, 'AC-[A-Z0-9]+(?:-[A-Z0-9]+)*')) {
            $v = $m.Value; [void]$named.Add($v)
            while ($v -match '^(AC-.+)-[A-Z0-9]+$') { $v = $Matches[1]; [void]$named.Add($v) }
        }
    }
    foreach ($t in @($doc.tasks)) {
        # A retired row was withdrawn and will deliver nothing, so the clauses it names are still left to plan unless
        # another row names them (kit item IN-20261009150944-5bbd).
        if (Test-Retired $t) { continue }
        $parts = @()
        foreach ($k in 'why', 'title', 'tests') { if ($t.ContainsKey($k) -and $null -ne $t[$k]) { $parts += @($t[$k] | ForEach-Object { [string]$_ }) } }
        AddNames ($parts -join "`n")
        $tix = @(Join-Path $repo ".streams\tickets\$($t.id).md")
        if ($t.ContainsKey('artifacts') -and $t.artifacts -and $t.artifacts.ContainsKey('ticket') -and $t.artifacts['ticket']) {
            $tp = [string]$t.artifacts['ticket']; $tix += $(if ([IO.Path]::IsPathRooted($tp)) { $tp } else { Join-Path $repo $tp })
        }
        foreach ($p in @($tix | Select-Object -Unique)) { if (Test-Path -LiteralPath $p -PathType Leaf) { AddNames ([IO.File]::ReadAllText($p)) } }
    }
    # stream-adhoc builds a clause in a closed group with no board row, by design, and records it in its request file
    # .streams\adhoc\<Id>.md. Such a clause is planned (and built) once that change is COMMITTED, i.e. a commit on HEAD
    # whose subject starts '<Id>:' (Commit-AdhocChange.ps1). A request that was reversed or is still open names nothing:
    # its clause may never be built. ADHOC-20261011-1 added AC-UISTEP-011 and AC-UIWORK-017 to closed G3 and G4 and
    # turned the count unknown (kit item IN-20261012012612-8ef6).
    $adDir = Join-Path $repo '.streams\adhoc'
    if (Test-Path -LiteralPath $adDir -PathType Container) {
        $adFiles = @(Get-ChildItem -LiteralPath $adDir -Filter 'ADHOC-*.md' -File)
        if ($adFiles.Count) {
            $landed = @{}
            foreach ($subj in @(git -C $repo log --format=%s -E --grep '^ADHOC-[0-9]+-[0-9]+:' 2>$null)) { if ([string]$subj -match '^(ADHOC-\d+-\d+):') { $landed[$Matches[1]] = $true } }
            foreach ($f in $adFiles) { if ($landed.ContainsKey($f.BaseName)) { AddNames ([IO.File]::ReadAllText($f.FullName)) } }
        }
    }
    # Clause id -> requirement id. A file's id is its top-level `id:`, which is what group scope.include names.
    $clauseDoc = [ordered]@{}; $docFile = @{}; $bad = @(); $dup = @()
    foreach ($f in @(Get-ChildItem -LiteralPath $root -Recurse -Filter *.yaml -File)) {
        $txt = [IO.File]::ReadAllText($f.FullName)
        $am = [regex]::Match($txt, '(?ms)^acceptance:[ \t]*\r?\n(.*?)(?=^[A-Za-z_][\w-]*:|\z)')
        if (-not $am.Success) { continue }
        $ids = @([regex]::Matches($am.Groups[1].Value, '(?m)^[ \t]*- id:[ \t]*(AC-[A-Za-z0-9-]+)[ \t]*\r?$') | ForEach-Object { $_.Groups[1].Value })
        if ([regex]::Match($txt, '(?m)^status:[ \t]*(\S+)').Groups[1].Value -ne 'READY') { $out.notReadyClauses += $ids.Count; continue }
        $rel = $f.FullName.Substring($root.TrimEnd('\').Length + 1)
        if (-not $ids.Count) { $bad += $rel; continue }
        $did = [regex]::Match($txt, '(?m)^id:[ \t]*(\S+)').Groups[1].Value
        if (-not $did) { $did = $f.BaseName }
        $out.files++; $docFile[$did] = $rel
        foreach ($i in $ids) { if ($clauseDoc.Contains($i)) { $dup += "$i ($($clauseDoc[$i]), $did)" } else { $clauseDoc[$i] = $did } }
    }
    $out.clauses = $clauseDoc.Count
    $unnamed = @($clauseDoc.Keys | Where-Object { -not $named.Contains($_) })
    $out.unnamed = $unnamed.Count; $out.named = $out.clauses - $unnamed.Count
    $inGroup = @{}
    foreach ($g in @($doc.groups)) {
        $inc = @(); if ($g.ContainsKey('scope') -and $g.scope -and $g.scope.ContainsKey('include')) { $inc = @($g.scope['include'] | ForEach-Object { [string]$_ }) }
        foreach ($x in $inc) { $inGroup[$x] = $true }
        $gu = @($unnamed | Where-Object { $clauseDoc[$_] -in $inc })
        $out.byGroup[[string]$g.id] = [ordered]@{ state = [string]$g.state; clauses = @($clauseDoc.Keys | Where-Object { $clauseDoc[$_] -in $inc }).Count; unnamed = $gu.Count; count = $null }
        $out.unnamedIds[[string]$g.id] = @($gu)
    }
    $nu = @($unnamed | Where-Object { -not $inGroup.ContainsKey($clauseDoc[$_]) })
    $out.unnamedIds['none'] = @($nu)
    $out.notInGroupFiles = @($docFile.Keys | Where-Object { -not $inGroup.ContainsKey($_) } | Sort-Object)
    # Why the count cannot be trusted, in the order the owner can act on them.
    $why = @()
    if ($bad.Count) { $why += "$($bad.Count) READY file(s) have an acceptance list with no '- id: AC-' line the reader can parse: $($bad -join ', ')" }
    if ($dup.Count) { $why += "$($dup.Count) clause id(s) appear in two files, so their group is ambiguous: $(@($dup | Select-Object -First 5) -join '; ')" }
    $closedMiss = @($out.byGroup.Keys | Where-Object { $out.byGroup[$_].state -eq 'closed' -and $out.byGroup[$_].unnamed -gt 0 })
    if ($closedMiss.Count) { $why += 'no row names every clause of a closed group, so a clause no row names may still be built: ' + (@($closedMiss | ForEach-Object { "$_ $($out.byGroup[$_].unnamed) of $($out.byGroup[$_].clauses)" }) -join ', ') }
    if (-not $out.clauses -and -not $why.Count) { $why += "no READY requirement file under $root has an acceptance list" }
    if ($why.Count) { $out.reason = $why -join '; '; return $out }
    $out.known = $true; $out.total = $unnamed.Count; $out.notInGroup = $nu.Count
    foreach ($k in @($out.byGroup.Keys)) { $out.byGroup[$k].count = $out.byGroup[$k].unnamed }
    $out
}
$leftToPlan = Get-LeftToPlan $doc $Repo

$model = [ordered]@{
    at = Get-Now; repo = $Repo; groups = @($groups); tasks = @($tasks); flags = @($flags); rolesSeen = $roles; sessions = $sessions; claimable = $claimable; buffer = $buffer; mainLock = $mainLock; releases = $releases; depReview = @($depReview); authorRank = $authorRank; inbox = $inbox; forecast = $boardForecast
    leftToPlan = $leftToPlan
    disks = @($diskReport)
    # The page renders whatever this lists, in this order, so a bucket can never be added here and missed there.
    stateBuckets = @($StateBuckets)
    owner = [ordered]@{ questions = Lines $P.Questions; escalations = Escalations (Lines $P.Questions); gates = Lines $P.Gates; worktrees = Worktrees $P.Worktrees
        uncommitted = @($doc.tasks | Where-Object { $_.state -in 'integrated', 'done' -and -not (Test-Retired $_) } | ForEach-Object { $_.id }) }
}
if ($Json) { $model | ConvertTo-Json -Depth 20; exit 0 }
$all = @($doc.tasks)
function FinText($f) {
    if ($null -eq $f.predictedMinutes) { return 'fin unknown' }
    if ($f.predictedMinutes -le 0) { $hl = if ($f -is [Collections.IDictionary]) { $f['heldLabel'] } else { $($hp = $f.PSObject.Properties['heldLabel']; if ($hp) { $hp.Value }) }; if ($hl) { return [string]$hl }; return 'finished' }
    $m = [int]$f.predictedMinutes
    $in = if ($m -lt 60) { "$m" + 'm' } elseif ($m -lt 1440) { '{0}h{1}m' -f [math]::Floor($m / 60), ($m % 60) } else { '{0}d{1}h' -f [math]::Floor($m / 1440), [math]::Floor(($m % 1440) / 60) }
    'fin ' + (Format-LocalStamp ([datetime]::Parse($f.predictedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)) 'd MMM HH:mm') + " (in $in)"
}
"groups: " + (($groups | ForEach-Object { "$($_.id) $($_.state) $(FinText $_.forecast)" }) -join ' | ') + " || board $(FinText $boardForecast)"
# Sessions ride on the tasks line, not a line of their own: the terminal summary is six lines by contract.
"tasks: " + (($StateBuckets | ForEach-Object { $s = $_; "$s $(@($all | Where-Object { (Bucket $_) -eq $s }).Count)" }) -join ', ') + " | sessions: " + (($sessions.Keys | ForEach-Object { "$_ $($sessions[$_].live) live ($($sessions[$_].working) working, $($sessions[$_].idle) idle$(if ($sessions[$_].quiet) { ", $($sessions[$_].quiet) quiet" })$(if ($_ -eq 'build') { ", $($claimable.count) claimable of $($claimable.ticketed) ticketed" }))" }) -join ', ') +
    $(if ($leftToPlan.known) { " | left to plan $($leftToPlan.total) of $($leftToPlan.clauses) clauses ($($leftToPlan.notInGroup) in no group)" } else { " | left to plan unknown: $($leftToPlan.reason)" })
"owner: questions $(@($model.owner.questions).Count) ($(@($model.owner.escalations).Count) to answer, $(@($model.owner.questions).Count - @($model.owner.escalations).Count) applied defaults), gates $(@($model.owner.gates).Count), worktrees $(@($model.owner.worktrees).Count)"
"inbox: " + (($inbox.Keys | ForEach-Object { "$(($_ -replace '^stream-', '')) $($inbox[$_].open)" }) -join ', ')
"flags: " + $(if ($flags.Count) { $flags -join '; ' } else { 'none' })
"page: " + $(if (Test-Path (Join-Path $P.Root 'status-url.txt')) { (Get-Content (Join-Path $P.Root 'status-url.txt') -Raw).Trim() } else { 'not published yet' })
