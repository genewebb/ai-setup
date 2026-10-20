# Renders .streams\status.html from the Get-StreamStatus.ps1 model. The page markup lives in status-page-head.html
# beside this script, so the design can be edited without touching the renderer.
#
# It also MIRRORS the finished page to every path listed in .streams\status-mirror.txt, one per line. The mirror is
# what gives the board a permanent address. A published artifact is private to the account that published it, so the
# link dies the moment the owner's account changes: two artifact URLs were lost that way on 2026-09-29 while the page
# itself was healthy. A file served by IIS belongs to the host, not to an account, so its URL never expires. Copying
# is the last step and never fails the render: a mirror that is unreachable is reported and the local file stands.
#
# The machine profile's StatusPageDir row (the IIS folder on a stream host; spec D17) is a mirror target too:
# {StatusPageDir}\status.html. It applies to the real board only - a caller that names its own -MirrorFile (the
# self-tests) gets exactly the targets in that file. A blank row means the page in .streams\ is the only copy.
param(
  [Parameter(Mandatory)][string]$Repo,
  [Parameter(Mandatory)][string]$Session,
  [string]$WatchdogLine = 'Watchdog QUIET: no stale claim.',
  [string]$InboxLine = 'Own inbox: no open items.',
  [string]$HeadFile,
  [string]$Out,
  [string]$MirrorFile,
  [int]$NextUpdateSeconds = 900
)
$ErrorActionPreference = 'Stop'
$scripts = $PSScriptRoot
$Repo = (Resolve-Path $Repo).Path
$streams = Join-Path $Repo '.streams'
if (-not $HeadFile) { $HeadFile = Join-Path $PSScriptRoot 'status-page-head.html' }
if (-not $Out) { $Out = Join-Path $streams 'status.html' }
$targets = [System.Collections.Generic.List[string]]::new()
if (-not $MirrorFile) {
  $MirrorFile = Join-Path $streams 'status-mirror.txt'
  try {
    $lib = Join-Path $PSScriptRoot '..\..\..\lib\MachineConfig.psm1'
    if (Test-Path -LiteralPath $lib) {
      Import-Module $lib -Force
      $pageDir = Get-AIPath StatusPageDir -Optional
      if ($pageDir) { $targets.Add((Join-Path $pageDir 'status.html')) }
    }
  } catch { Write-Output ("STATUS PAGE DIR UNREADABLE: {0}" -f $_.Exception.Message) }
}

function E([string]$s) {
  if ($null -eq $s) { return '' }
  $s = $s -replace '&','&amp;' -replace '<','&lt;' -replace '>','&gt;' -replace '"','&quot;'
  return $s
}
function Dur($m) {
  # Untyped on purpose: a [double] parameter coerces $null to 0, so a missing duration would print "0 min".
  if ($null -eq $m -or $m -eq '') { return '&mdash;' }
  $m = [math]::Round([double]$m)
  if ($m -lt 60) { return "$m min" }
  if ($m -lt 1440) { return "{0}h {1}m" -f [math]::Floor($m/60), ($m % 60) }
  return "{0}d {1}h" -f [math]::Floor($m/1440), [math]::Floor(($m % 1440)/60)
}
function Ago([string]$utc) {
  if (-not $utc) { return $null }
  return ([datetime]::UtcNow - [datetime]::Parse($utc, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)).TotalMinutes
}
# The predicted finish, as the owner reads it: a wall-clock date first, the distance from now under it. Both come
# from the model's forecast block and nothing is recomputed here, so the page and the terminal line can never
# disagree. A group the model could not date says so and shows why instead of borrowing a number from somewhere else.
function FinDate($f) {
  if ($null -eq $f -or $null -eq $f.predictedMinutes) { return $null }
  return [datetime]::Parse($f.predictedAt, $null, [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal).ToLocalTime()
}
function FinCell($f) {
  if ($null -eq $f) { return '<span class="muted">&mdash;</span>' }
  if ($null -eq $f.predictedMinutes) {
    return '<span class="pill s-blocked">no date</span><div class="muted mono">' + (E ([string]$f.basis)) + '</div>'
  }
  if ([int]$f.predictedMinutes -le 0) { return '<span class="pill s-integrated">finished</span>' }
  $d = FinDate $f
  return '<b>' + (Format-LocalStamp $d 'ddd dd MMM HH:mm') + '</b><div class="muted mono" title="' + (E ([string]$f.basis)) + '">in ' + (Dur $f.predictedMinutes) + '</div>'
}
function Linkify([string]$s) {
  $e = E $s
  return [regex]::Replace($e, '(https?://[^\s|<]+)', '<a href="$1" target="_blank" rel="noopener">$1</a>')
}
# Left to plan (the model's leftToPlan block): the acceptance clauses of READY requirement files that no row names.
# A count is shown only when the model says it is known; otherwise the reason is, so an untrusted match never reads as a number.
function LeftToPlanTile($l) {
  if ($null -eq $l) { return '<div class="tile"><b>?</b><span>left to plan &middot; unknown: no model</span></div>' }
  if (-not $l.known) { return '<a class="tile stall" href="#left-to-plan" title="' + (E ([string]$l.reason)) + '"><b>?</b><span>left to plan &middot; unknown &middot; hover for why</span></a>' }
  return '<a class="tile" href="#left-to-plan" title="' + $l.total + ' of ' + $l.clauses + ' acceptance clauses in ' + $l.files + ' READY requirement files are named by no row"><b>' + $l.total + '</b><span>left to plan &middot; of ' + $l.clauses + ' clauses</span></a>'
}
function LeftToPlanCell($l, [string] $key) {
  if ($null -eq $l) { return '<td class="num muted">?</td>' }
  $ids = @(); if ($l.unnamedIds -and $l.unnamedIds.PSObject.Properties[$key]) { $ids = @($l.unnamedIds.$key) }
  if (-not $l.known) { return '<td class="num muted" title="unknown: ' + (E ([string]$l.reason)) + '">?</td>' }
  if ($key -ne 'none' -and -not $l.byGroup.PSObject.Properties[$key]) { return '<td class="num muted">?</td>' }
  $n = if ($key -eq 'none') { [int]$l.notInGroup } else { [int]$l.byGroup.$key.count }
  if ($n -eq 0) { return '<td class="num muted">0</td>' }
  '<td class="num" title="' + (E (($ids | Sort-Object) -join ', ')) + '">' + $n + '</td>'
}

$model = & (Join-Path $scripts 'Get-StreamStatus.ps1') -Repo $Repo -Json | ConvertFrom-Json
$board = Get-Content (Join-Path $streams 'tasks.json') -Raw | ConvertFrom-Json
$inbox = & (Join-Path $scripts 'Get-InboxItems.ps1') -Repo $Repo -All -Json | ConvertFrom-Json

$now = Get-Date
$sb = [System.Text.StringBuilder]::new()
function W([string]$s) { [void]$sb.AppendLine($s) }

W (Get-Content $HeadFile -Raw).TrimEnd()
W ('<header><div><h1>Speedy Pit Wall</h1>')
W ('<div class="meta">' + (E $Repo) + '</div></div>')
# Owner ruling 2026-10-18 (kit items IN-20261019000952-12f5, IN-20261019001501-706e): the header shows local machine
# time only, and when the next status tick should rebuild the page. The page is static, so the overdue check runs in
# the viewer's browser against the UTC instant in data-next.
. "$PSScriptRoot\lib\Streams.ps1"
$nextAt = $now.AddSeconds([Math]::Max(60, $NextUpdateSeconds))
W ('<div class="meta">generated ' + $now.ToString('ddd dd MMM yyyy ') + (Format-LocalStamp $now).Substring(11) + ' &middot; <span id="next-update" data-next="' + $nextAt.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') + '">next update ' + (Format-LocalStamp $nextAt).Substring(11) + '</span></div></header>')
W '<script>(function(){var e=document.getElementById("next-update");if(e&&Date.now()>Date.parse(e.dataset.next)+60000){e.textContent+=" \u00b7 update overdue";e.style.color="var(--bad,#c33)";}})();</script>'

# ---- tiles ----
# The buckets come from the model, in the model's order, so the page can never show a different set from the counts
# it draws. `ticketing` is a bucket and not a state: it is a planned row a live author is writing the ticket for,
# carved out of `planned` so the tiles, the bars and the totals all still add up to the task count.
$states = @($model.stateBuckets)
$byState = @{}
foreach ($s in $states) { $byState[$s] = @($model.tasks | Where-Object { $_.bucket -eq $s }).Count }
W '<section><div class="tiles">'
W ('<div class="tile"><b>' + $model.tasks.Count + '</b><span>tasks</span></div>')
foreach ($s in $states) {
  # The planned tile reads 'ready to author' (owner 2026-10-12): it names who takes the work next, beside 'ticketing'.
  $tileLabel = if ($s -eq 'planned') { 'ready to author' } else { $s }
  W ('<div class="tile"><b>' + $byState[$s] + '</b><span>' + $tileLabel + '</span></div>')
  # LEFT TO AUTHOR (owner 2026-10-12): every row that still has no ticket, whoever holds it - ready to author, ticketing
  # (a planned row under a live author claim) and blocked rows parked before their ticket - across all groups, with the
  # part in the focus groups named, because only that part is built while the other groups are paused.
  if ($s -eq 'planned') {
    $focusIds = @($model.forecast.focusGroups | ForEach-Object { [string]$_ } | Where-Object { $_ })
    # By STATE, not by artifacts.ticket: a planned row always needs a ticket written (G9 rows were released with the ticket
    # path already filled in, and a row sent back to planned keeps its old path), so only a blocked row is read by its path.
    $noTicket = @($board.tasks | Where-Object { $_.state -eq 'planned' -or ($_.state -eq 'blocked' -and -not $_.artifacts.ticket) })
    $noTicketFocus = @($noTicket | Where-Object { $focusIds -contains [string]$_.group }).Count
    W ('<div class="tile" title="rows with no ticket yet: ready to author + ticketing + blocked before a ticket; ' + $noTicketFocus + ' of them in the focus groups"><b>' + $noTicket.Count + '</b><span>left to author &middot; ' + $noTicketFocus + ' in focus</span></div>')
  }
  # LEFT TO PLAN sits right after PLANNED (kit items IN-20261009131901-10e4, IN-20261009132301-e0a4): planned counts rows
  # waiting for a ticket, this counts the acceptance clauses no row exists for yet. Get-StreamStatus computes it, so the
  # terminal tasks line and this tile read one number; when the matching cannot be trusted the tile says so, never a guess.
  if ($s -eq 'planned') { W (LeftToPlanTile $model.leftToPlan) }
}
# The pending owner questions belong at the TOP, not only in the Owner queue panel further down: they are the one
# number on this page that nothing but the owner can move, and on 2026-09-29 there were 442 of them while the page
# showed the count only after four sections of scrolling. It counts what Get-StreamStatus already filters, so a
# question rewritten in place with a leading RESOLVED token drops out of it. The tile links to the panel that lists them.
# The big number is the ESCALATION count, not the whole queue: the queue also holds applied-default records, which are
# decisions already taken under standing owner authority and need no answer, and on 2026-09-29 they were 604 of 620.
# A tile reading 620 tells the owner nothing he can act on. The applied defaults stay on the tile as the second, smaller
# number, and the panel below still lists every line, so nothing is hidden by counting the two apart.
$pendingQs = @($model.owner.escalations).Count
$appliedQs = @($model.owner.questions).Count - $pendingQs
W ('<a class="tile owner" href="#owner-questions"><b>' + $pendingQs + '</b><span>owner questions &middot; ' + $appliedQs + ' applied</span></a>')
# The board's predicted finish is the other number the owner comes to this page for, so it sits in the tiles rather
# than only inside the category table. The date is the headline; the distance from now is the label under it.
$bfTile = $model.forecast
$bfDate = FinDate $bfTile
if ($bfDate) { W ('<div class="tile"><b>' + $bfDate.ToString('dd MMM') + '</b><span>all done &middot; in ' + (Dur $bfTile.predictedMinutes) + '</span></div>') }
else { W ('<div class="tile"><b>&mdash;</b><span>all done &middot; no date</span></div>') }
W '</div></section>'
# Live SESSIONS per role, beside the task buckets. The building tile counts tasks, and a builder between tasks (verifier
# handoff, release, next claim) holds none, so "building 3" read as three builders while six were running.
if ($model.sessions) {
  W '<section><div class="tiles">'
  foreach ($rp in @($model.sessions.PSObject.Properties)) {
    $label = @{ author = 'authors'; build = 'builders'; integrate = 'integrators' }[$rp.Name]; if (-not $label) { $label = $rp.Name }
    # working holds a claim; idle polled NONE (an idle beat, kit item IN-20261002150214-6ee3) or sits between tasks;
    # quiet holds no claim and wrote nothing for over 20 minutes (kit item IN-20261004152204-9ede), shown only when present.
    $wk = if ($null -ne $rp.Value.working) { $rp.Value.working } else { $rp.Value.claimed }
    $id = if ($null -ne $rp.Value.idle) { $rp.Value.idle } else { [int]$rp.Value.live - [int]$wk }
    $qt = if ([int]$rp.Value.quiet -gt 0) { ' &middot; ' + $rp.Value.quiet + ' quiet' } else { '' }
    W ('<a class="tile" href="#sessions"><b>' + $rp.Value.live + '</b><span>' + $label + ' live &middot; ' + $wk + ' working &middot; ' + $id + ' idle' + $qt + '</span></a>')
    # Beside the builders: whether there is anything for them to take. A builder that claims NONE writes nothing, so
    # it never counts as live, and "0 builders" alone cannot tell an empty queue from dead sessions.
    if ($rp.Name -eq 'build' -and $model.claimable) {
      $cl = $model.claimable
      # Red below the claimable buffer (2 per live builder): the PIPELINE DRY flag says why (kit item IN-20261002160453-9384).
      $dry = $model.buffer -and $model.buffer.dry
      $cls = if ($dry -or ($cl.ticketed -gt 0 -and $cl.count -eq 0)) { ' stall' } else { '' }
      $tgt = if ($model.buffer) { ' &middot; target ' + $model.buffer.target } else { '' }
      # The focus group the count is taken from (2026-10-05 priority-focus-design 3.1): later groups are frozen.
      $foc = if ($cl.focusGroup) { ' &middot; focus ' + $cl.focusGroup } else { '' }
      W ('<a class="tile' + $cls + '" href="#flags"><b>' + $cl.count + '</b><span>claimable &middot; of ' + $cl.ticketed + ' ticketed' + $tgt + $foc + '</span></a>')
      # Author releases (planned -> ticketed) per hour, oldest hour first, so a falling feed shows before claimable hits 0.
      if ($model.releases) {
        $rph = @($model.releases.perHour)
        W ('<div class="tile"><b>' + $rph[-1] + '</b><span>released last hour &middot; per hour, last ' + $model.releases.hours + ' h: ' + ($rph -join ' ') + '</span></div>')
      }
    }
  }
  W '</div></section>'
}

# ---- priority categories ----
# The owner reads the build as priority categories and asks one question of each: how many are done and how many are
# still to go. Those categories are the groups, so the counts come from the same model the Groups section draws rather
# than a second tally that could disagree with it. Done means integrated or done: a task the owner can no longer be asked
# about. Everything else is still to go, blocked included, because a blocked task is not finished.
# ORDER (owner ruling 2026-10-11): the table reads as the priority list. On top, the open groups of the current priority
# list (.streams\config.json focus.groups, read through Get-FocusGroups, so in the order the kit works them), numbered
# 1..n. Under them the completed (closed) groups, in board order (owner: keep the completed ones above the line). Then
# one heavy separator line, and below it the open groups left out of the focus (paused until the owner adds them), in
# board order. A hard-coded list (G1..G6 with
# their names) stood here until then and went stale as soon as groups closed and new ones were added.
$focusIdsTop = @($model.forecast.focusGroups | ForEach-Object { [string]$_ } | Where-Object { $_ })
$doneStates = @('integrated','done')
# "Waiting" answers the owner's standing question about this table: the categories do NOT finish in his priority order,
# so the table must say what actually holds each one back. A to-go task is WAITING when at least one task it dependsOn
# is not yet integrated or done; otherwise it is FREE and only a builder's time stands between it and being built.
# Measured, never asserted: on 2026-09-29 the graph carried 213 cross-group dependency edges pointing BOTH ways
# (G2 on G3 41 times, G3 on G2 twice; G1 on G3 and on G6), so no category can be drained before the next one starts.
$taskState = @{}
foreach ($t in $model.tasks) { $taskState[[string]$t.id] = [string]$t.state }
function IsWaiting($t) {
  foreach ($d in @($t.dependsOn)) {
    if (-not $d) { continue }
    $ds = $taskState[[string]$d]
    if ($null -eq $ds -or $ds -notin $doneStates) { return $true }
  }
  return $false
}
$catRows = @(); $catBelow = @(); $n = 0
foreach ($fid in $focusIdsTop) {
  # Select-Object, not [0]: a focus id the board does not carry returns an EMPTY array here, and under Set-StrictMode
  # (which a caller can impose on this script) [0] on an empty array throws and no page is written at all.
  $cg = @($model.groups | Where-Object { $_.id -eq $fid -and $_.state -ne 'closed' }) | Select-Object -First 1
  if ($cg) { $n++; $catRows += @{ g = $cg; label = "$n. " + (E $cg.name) } }
}
# A blue separator row ("Goals completed", styled like the red below-the-line row) sits between the in-progress list and the completed groups.
$doneAt = $catRows.Count
foreach ($cg in $model.groups) {
  if ($cg.state -eq 'closed') { $catRows += @{ g = $cg; label = (E $cg.name) + ' <span class="muted">(completed)</span>' } }
}
foreach ($cg in $model.groups) {
  if ($cg.state -ne 'closed' -and $focusIdsTop -notcontains [string]$cg.id) { $catBelow += @{ g = $cg; label = (E $cg.name) + ' <span class="muted">(paused)</span>' } }
}
$lineAt = $catRows.Count
$catRows += $catBelow
$catDoneAll = 0; $catTogoAll = 0; $catWaitAll = 0; $catFreeAll = 0
# Where the to-go work sits in the pipeline, per category: authoring (a live author is writing the ticket), ticketed
# (ready for a builder), building, built (waiting for the integrator) and blocked. The owner asked to see what each
# category has in flight, not only how much is left; hover a number for the task ids.
$pipeBuckets = @('ticketing', 'ticketed', 'building', 'built', 'blocked')
$pipeLabels = @{ ticketing = 'authoring'; ticketed = 'ticketed'; building = 'building'; built = 'built'; blocked = 'blocked' }
$pipeAll = @{}; foreach ($b in $pipeBuckets) { $pipeAll[$b] = 0 }
function PipeCell([object[]] $ts, [string] $cls) {
  $n = $ts.Count
  if ($n -eq 0) { return '<td class="num muted">0</td>' }
  '<td class="num ' + $cls + '" title="' + (E ((@($ts | ForEach-Object { [string]$_.id }) | Sort-Object) -join ', ')) + '">' + $n + '</td>'
}
W '<section><h2>Priority categories</h2>'
# Totals line (owner ask 2026-10-16): the All categories sums in one line under the title, before the table, so the
# board's whole position reads without scrolling to the table's last row. It counts EVERY category, the paused ones
# below the line included, exactly as the All categories row does. The sums are known only once the rows are drawn, so
# the line is inserted at this offset afterwards. Its labels are the table's column names.
$catTotLineAt = $sb.Length
W '<style>table.cats tr.prio-line td{border-top:5px solid var(--accent);border-bottom:1px solid var(--accent);padding:8px 10px;font-weight:700;color:var(--accent);text-transform:uppercase;letter-spacing:.04em;font-size:12px}table.cats tr.below td{opacity:.72}table.cats tr.prio-done td{border-top:5px solid var(--ticketed);border-bottom:1px solid var(--ticketed);padding:8px 10px;font-weight:700;color:var(--ticketed);text-transform:uppercase;letter-spacing:.04em;font-size:12px}</style>'
W ('<div class="scroll"><table class="cats"><thead><tr><th>Category</th><th>Done</th><th>To go</th><th>&mdash; waiting</th><th>&mdash; free</th>' + (($pipeBuckets | ForEach-Object { '<th>' + $pipeLabels[$_] + '</th>' }) -join '') + '<th>Total</th><th id="left-to-plan">Left to plan</th><th>Progress</th><th>Work left</th><th>Rate</th><th>Predicted finish</th></tr></thead><tbody>')
$rowIx = 0
foreach ($r in $catRows) {
  if ($rowIx -eq $doneAt -and $doneAt -lt $lineAt) {
    W ('<tr class="prio-done"><td colspan="' + (11 + $pipeBuckets.Count) + '">Goals completed</td></tr>')
  }
  if ($rowIx -eq $lineAt) {
    $belowIds = @($catBelow | ForEach-Object { [string]$_.g.id })
    W ('<tr class="prio-line"><td colspan="' + (11 + $pipeBuckets.Count) + '">Below the line &mdash; not on the priority list, not being worked' +
       $(if ($belowIds.Count) { ': ' + (E ($belowIds -join ', ')) } else { '' }) + '</td></tr>')
  }
  $rowIx++
  $cg = $r.g
  $rowClass = if ($rowIx -gt $lineAt) { ' class="below"' } else { '' }
  $cDone = 0; foreach ($s in $doneStates) { $cDone += [int]$cg.counts.$s }
  # Retired rows (withdrawn, landed nothing) are neither done nor to go, so they stay out of the total and the progress.
  $cTot = 0;  foreach ($s in $states)     { if ($s -ne 'retired') { $cTot  += [int]$cg.counts.$s } }
  $cTogo = $cTot - $cDone
  $cTogoTasks = @($model.tasks | Where-Object { $_.group -eq $cg.id -and $_.state -notin $doneStates })
  $cWait = @($cTogoTasks | Where-Object { IsWaiting $_ }).Count
  $cFree = $cTogo - $cWait
  $catDoneAll += $cDone; $catTogoAll += $cTogo; $catWaitAll += $cWait; $catFreeAll += $cFree
  $cPct = if ($cTot -gt 0) { [int][math]::Round(100 * $cDone / $cTot) } else { 0 }
  W ('<tr' + $rowClass + '>')
  W ('<td class="name">' + $r.label + ' <span class="muted mono">' + (E $cg.id) + '</span></td>')
  W ('<td class="num">' + $cDone + '</td>')
  W ('<td class="num">' + $cTogo + '</td>')
  W ('<td class="num muted">' + $cWait + '</td>')
  W ('<td class="num muted">' + $cFree + '</td>')
  foreach ($b in $pipeBuckets) { $bt = @($cTogoTasks | Where-Object { $_.bucket -eq $b }); $pipeAll[$b] += $bt.Count; W (PipeCell $bt '') }
  W ('<td class="num">' + $cTot + '</td>')
  W (LeftToPlanCell $model.leftToPlan ([string]$cg.id))
  W ('<td class="bar-cell"><div class="bar"><i class="s-done" style="width:' + $cPct + '%" title="done ' + $cDone + ' of ' + $cTot + '"></i></div><span class="pct">' + $cPct + '%</span></td>')
  $cf = $cg.forecast
  W ('<td class="num">' + (Dur $cf.remainingMinutes) + '</td>')
  W ('<td class="num">' + $cf.ratePerHour + ' <small class="muted">min/h</small><div class="muted mono">' + $cf.landedInWindow + ' in ' + $cf.windowHours + 'h' + $(if ([double]$cf.outageHours -gt 0) { ', ' + $cf.outageHours + 'h outage out' } else { '' }) + '</div></td>')
  W ('<td>' + (FinCell $cf) + '</td>')
  W '</tr>'
}
$catTotAll = $catDoneAll + $catTogoAll
$catPctAll = if ($catTotAll -gt 0) { [int][math]::Round(100 * $catDoneAll / $catTotAll) } else { 0 }
# Requirements no group's scope.include names have no category of their own, but they are goals too (kit item
# IN-20261009132301-e0a4), so they get a row here that carries only the Left to plan count.
$ltpNone = $model.leftToPlan
W '<tr>'
W ('<td class="name">Not in any group' + $(if ($ltpNone -and @($ltpNone.notInGroupFiles).Count) { ' <span class="muted mono" title="' + (E (@($ltpNone.notInGroupFiles) -join ', ')) + '">' + @($ltpNone.notInGroupFiles).Count + ' requirements</span>' } else { '' }) + '</td>')
foreach ($i in 1..(4 + $pipeBuckets.Count + 1)) { W '<td class="num muted">&mdash;</td>' }
W (LeftToPlanCell $ltpNone 'none')
foreach ($i in 1..4) { W '<td class="muted">&mdash;</td>' }
W '</tr>'
W '<tr class="total">'
W '<td class="name">All categories</td>'
W ('<td class="num">' + $catDoneAll + '</td>')
W ('<td class="num">' + $catTogoAll + '</td>')
W ('<td class="num">' + $catWaitAll + '</td>')
W ('<td class="num">' + $catFreeAll + '</td>')
foreach ($b in $pipeBuckets) { W ('<td class="num">' + $pipeAll[$b] + '</td>') }
W ('<td class="num">' + $catTotAll + '</td>')
W $(if ($ltpNone -and $ltpNone.known) { '<td class="num">' + $ltpNone.total + '</td>' } else { '<td class="num muted" title="' + (E $(if ($ltpNone) { 'unknown: ' + [string]$ltpNone.reason } else { 'unknown' })) + '">?</td>' })
W ('<td class="bar-cell"><div class="bar"><i class="s-done" style="width:' + $catPctAll + '%" title="done ' + $catDoneAll + ' of ' + $catTotAll + '"></i></div><span class="pct">' + $catPctAll + '%</span></td>')
$bf = $model.forecast
W ('<td class="num">' + (Dur $bf.remainingMinutes) + '</td>')
W ('<td class="num">' + $bf.ratePerHour + ' <small class="muted">min/h</small></td>')
W ('<td>' + (FinCell $bf) + '</td>')
W '</tr>'
W '</tbody></table></div>'
$ltpTot = if ($ltpNone -and $ltpNone.known) { [string]$ltpNone.total } else { '?' }
$catTotItems = @(
  @('Done', $catDoneAll), @('To go', $catTogoAll), @('Waiting', $catWaitAll), @('Free', $catFreeAll),
  @('Authoring', $pipeAll['ticketing']), @('Ticketed', $pipeAll['ticketed']), @('Building', $pipeAll['building']),
  @('Built', $pipeAll['built']), @('Blocked', $pipeAll['blocked']), @('Left to plan', $ltpTot))
[void]$sb.Insert($catTotLineAt, ('<div class="cat-totals" style="display:flex;flex-wrap:wrap;gap:6px 18px;margin:0 0 10px;font-size:13px">' +
  (($catTotItems | ForEach-Object { '<span><span class="muted">' + $_[0] + '</span> <b>' + $_[1] + '</b></span>' }) -join '') + '</div>' + [Environment]::NewLine))
W '<div class="note">Done counts tasks that are integrated or done. To go counts everything else, blocked included. Waiting is the part of To go held by a dependency that has not landed yet; free is the rest, which needs only a builder. Authoring, ticketed, building, built and blocked split To go by pipeline stage: authoring is a row a live author is writing the ticket for, built is a row waiting for the integrator. Hover a number for its task ids. Above the line: the priority list (<code>.streams\config.json</code> focus.groups), numbered in the order it is worked, then the completed groups. Below the line: open groups left out of the priority list, paused until the owner adds them.</div>'
W ('<div class="note"><b>Left to plan</b> counts goals no row exists for yet: the acceptance clauses of READY requirement files under docs\requirements that no row names in its why, title, tests or ticket. A category counts the requirements its scope includes; Not in any group counts the ones no scope includes. ' +
   'It is shown only when the match can be trusted: a closed group was built in full, so if a closed group has clauses no row names, a clause no row names may still be built, and the count reads ? with the reason on hover. Hover a number for the clause ids.' +
   $(if ($model.leftToPlan -and -not $model.leftToPlan.known) { ' <b>Now unknown:</b> ' + (E ([string]$model.leftToPlan.reason)) + '.' } else { '' }) + '</div>')
# The forecast is the one column on this table that is a PREDICTION rather than a count, so the page says in full
# where every figure in it came from. An unexplained date invites the owner to plan against it as if it were a
# commitment; these numbers are a measurement of the last day or so of this board, and they move when it moves.
$fWin = @($model.groups | ForEach-Object { [int]$_.forecast.windowHours } | Sort-Object -Unique) -join '/'
$bDate = FinDate $bf
W '<details class="panel"><summary>How the predicted finish is worked out</summary>'
W ('<div class="note"><b>Work left / rate.</b> Work left is the sum of the estimates on every task in the category that is not integrated or done. ' +
   'The rate is measured from this board, not assumed: the estimated minutes that first reached <code>integrated</code> or <code>done</code> inside a trailing ' +
   'window, divided by that window. It therefore already carries the number of sessions actually running, the rework, the reaped worktrees and the idle gaps ' +
   'between them &mdash; nothing about capacity is entered by hand.</div>')
W ('<div class="note"><b>In focus order.</b> Only the focus categories (' + (E (@($bf.focusGroups) -join ', ')) + ') are worked; every other open category is frozen until the focus moves on, ' +
   'so its own landing rate measures the freeze, not capacity. A focus category is dated from its own recent history, but never later than all the focus rows to go at the ' +
   'focus categories&rsquo; combined rate. The categories after the focus are queued: each starts when the one before it finishes and is priced at that same focus rate. ' +
   'The window starts at 24 h and widens (48, 72, 168 h) until it holds at least 3 completions, because a 24 h window over a ' +
   'single task prices a whole category off that one task. Widening with few completions lowers the rate, so the error leans late rather than early. ' +
   'Windows in use this tick: ' + $fWin + ' h.</div>')
W ('<div class="note"><b>Floor.</b> No rate can beat the dependency graph. Each date is held at or after the longest chain of unlanded work the category sits on ' +
   'top of, its dependencies in other categories included. Where that floor is what sets the date, the hover text on the row says so.</div>')
W ('<div class="note"><b>The board date is the last queued category&rsquo;s finish</b> &mdash; the focus categories run concurrently and the rest one after another behind them. ' +
   $(if ($bDate) { 'It is set by ' + (E ([string]$bf.drivenBy)) + ', which finishes last.' } else { 'No category could be dated this tick, so the board has no date.' }) +
   $(if (@($bf.groupsWithoutDate).Count) { ' Undated categories, which the board date does not cover: ' + (E (@($bf.groupsWithoutDate) -join ', ')) + '.' } else { '' }) + '</div>')
W ('<div class="note"><b>What it is not.</b> It is not a commitment and it assumes today&rsquo;s sessions keep running at today&rsquo;s speed on today&rsquo;s estimates. ' +
   'Stopping the sessions, re-estimating, or a plan revise that adds tasks all move it, and it is re-measured from scratch every tick.</div>')
W '</details>'
# The owner set this order and the board does not follow it. That is a real answer, not a defect to hide, and the page
# is where he reads it, so it is stated here with the numbers this same tick measured rather than left to be asked again.
$xEdges = 0; $xPairs = @{}
foreach ($t in $model.tasks) {
  foreach ($d in @($t.dependsOn)) {
    if (-not $d) { continue }
    $dg = ([string]$d).Split('.')[0]
    if ($dg -ne [string]$t.group) { $xEdges++; $xPairs[$dg + '>' + $t.group] = 1 }
  }
}
W '<details class="panel"><summary>Why the categories are not finished in priority order</summary>'
W ('<div class="note">Two reasons, both measured this tick.</div>')
W ('<div class="note"><b>1. Dependencies cross the categories in both directions, so no category can be drained before the next one starts.</b> ' +
   $xEdges + ' of the dependency edges on this board point from one category into another, over ' + $xPairs.Count +
   ' ordered category pairs. They are not layered 1&rarr;6: later categories are needed BY earlier ones as well as the other way round, ' +
   'so finishing category 1 to 100% before category 2 begins is not reachable on this graph. The <em>waiting</em> column is that effect per category: ' +
   $catWaitAll + ' of the ' + $catTogoAll + ' remaining tasks cannot start yet whoever is free.</div>')
W ('<div class="note"><b>2. The scheduler does not rank by category at all.</b> A builder claims from every <code>released</code> group at once, ' +
   'and <code>Claim-Task.ps1</code> ranks candidates by integration fix first, then the longest remaining dependency chain (the critical path), then board order. ' +
   'Category is not one of those keys. All six groups were released within four hours on 2026-09-27 and 2026-09-28, four of them at the same timestamp, ' +
   'so nothing held the later categories back. Work spreads across all six by design, to keep the critical path moving.</div>')
W ('<div class="note">To make the board follow the priority order instead, the change belongs in <code>Claim-Task.ps1</code> ' +
   '(add category rank ahead of the chain key), or in release timing (hold later groups at <code>planned</code> until the earlier ones close). ' +
   'Neither is a status-page change, and neither has been made.</div>')
W '</details>'
W '</section>'

# ---- this tick ----
W '<section id="flags"><h2>This tick</h2><div class="panel">'
W ('<div class="flag">' + (E $WatchdogLine) + '</div>')
W ('<div class="flag">' + (E $InboxLine) + '</div>')
# The model already flags every stuck inbox item. This page must not re-derive them: it spelled the same item a second
# way ("inbox author item ... 41 min" against the model's "inbox stream-author item ... 41m"), which -Unique cannot
# collapse, so six items read as twelve flags. $stuckItems stays, but only to draw the Inboxes panel below.
$flags = @($model.flags)
$stuckItems = @($inbox | Where-Object { $_.status -in @('open','taken') -and $_.ageMinutes -gt $_.limitMinutes })
W ('<div class="muted mono">' + $flags.Count + ' flag' + $(if ($flags.Count -ne 1) { 's' } else { '' }) + '</div>')
if ($flags.Count -eq 0) { W '<div class="empty">No flags.</div>' }
foreach ($f in $flags) {
  $t = [string]$f
  if ($t.Length -gt 320) { $t = $t.Substring(0,320) + '&hellip;' }
  $fc = if ([string]$f -like 'PIPELINE DRY:*') { 'flag dry' } else { 'flag' }
  W ('<div class="' + $fc + '">' + (E $t) + '</div>')
}
W '</div></section>'

# ---- groups ----
W '<section><h2>Groups</h2><div class="groups">'
foreach ($g in $model.groups) {
  $tot = 0; foreach ($s in $states) { $tot += [int]$g.counts.$s }
  if ($tot -eq 0) { $tot = 1 }
  W '<div class="panel grp">'
  W ('<div class="top"><div><span class="name">' + (E $g.id) + ' &middot; ' + (E $g.name) + '</span> <span class="pill s-' + (E $g.state) + '">' + (E $g.state) + '</span></div>')
  # The old single number here was Get-ChainMinutes, which looks DOWNSTREAM: it is the chain from this group through
  # everything that depends on it, so all six groups read the same 4295 min on 2026-09-29 and it never dated a group.
  # The finish date leads now; the downstream chain stays, labelled for what it is.
  $gf = $g.forecast
  $fd = FinDate $gf
  $etaTxt = if ($fd) { '<b>' + (Format-LocalStamp $fd 'ddd dd MMM HH:mm') + '</b> <small>predicted finish &middot; in ' + (Dur $gf.predictedMinutes) + '</small>' }
            else { '<b>no date</b> <small>' + (E ([string]$gf.basis)) + '</small>' }
  W ('<div class="eta">' + $etaTxt + '</div></div>')
  # Kit item IN-20261019191314-2d8f: the date above is builder/author work by rate; what the rate cannot price is
  # listed by name, from the model's phases block, never as minutes added to the date.
  $ph = $g.phases
  if ($ph -and [string]$g.state -ne 'closed') {
    $t2 = $ph.tier2
    $t2Txt = switch ([string]$t2.state) {
      'running' { 'running ' + (E ([string]$t2.run)) + ' since ' + (Format-LocalStamp ([datetime]::Parse([string]$t2.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)) 'HH:mm') + $(if ($null -ne $t2.leftMinutes) { ' &middot; ~' + (Dur $t2.leftMinutes) + ' left' } else { '' }) }
      'ended' { 'ended (' + (E ([string]$t2.run)) + ')' }
      'abandoned' { 'last run ' + (E ([string]$t2.run)) + ' abandoned &middot; the next starts on the integrator''s go' }
      'held' { 'held by the owner' + $(if ([string]$t2.hold.since) { ' since ' + (Format-LocalStamp ([datetime]::Parse([string]$t2.hold.since, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)) 'HH:mm') } else { '' }) + $(if ([string]$t2.hold.reason) { ' (' + (E ([string]$t2.hold.reason)) + ')' } else { '' }) + $(if ($t2.run) { ' &middot; last run ' + (E ([string]$t2.run)) + ' abandoned' } else { '' }) + ' &middot; starts on the planner''s go' }
      default { 'pending' + $(if ($null -ne $t2.typicalMinutes) { ' &middot; typical run ' + (Dur $t2.typicalMinutes) } else { '' }) + ' &middot; starts on the integrator''s go' }
    }
    $fx = $ph.fixRound
    $fxTxt = switch ([string]$fx.state) { 'unknown' { if ([string]$fx.reason -eq 'last run abandoned') { 'unknown (last run abandoned; ' + [int]$fx.open + ' earlier fix row(s) open)' } else { 'unknown until the run ends' + $(if ([int]$fx.open) { ' (' + [int]$fx.open + ' open from earlier runs)' } else { '' }) } } 'open' { [string][int]$fx.open + ' fix row(s) open' } default { 'none open' } }
    W ('<div class="muted mono"><small>date covers builder and author work only &middot; Tier 2 run: ' + $t2Txt + ' &middot; waiting on owner: ' + [int]$ph.ownerGates.count + ' gate(s) &middot; fix round: ' + $fxTxt + '</small></div>')
  }
  W '<div class="bar">'
  foreach ($s in $states) {
    $c = [int]$g.counts.$s
    if ($c -gt 0) { W ('<i class="s-' + $s + '" style="width:' + ('{0:F3}' -f (100*$c/$tot)) + '%" title="' + $s + ' ' + $c + '"></i>') }
  }
  W '</div>'
  $leg = ''
  foreach ($s in $states) { $c = [int]$g.counts.$s; if ($c -gt 0) { $leg += '<em><s class="s-' + $s + '"></s>' + $s + ' ' + $c + '</em>' } }
  W ('<div class="legend">' + $leg + '</div>')
  W ('<div class="note">' + (Dur $gf.remainingMinutes) + ' of work left &middot; ' + $gf.ratePerHour + ' min/h measured over ' +
     $gf.windowHours + 'h (' + $gf.landedInWindow + ' landed' + $(if ([double]$gf.outageHours -gt 0) { ', ' + $gf.outageHours + 'h of outage taken out' } else { '' }) + ') &middot; earliest possible ' + (Dur $gf.floorMinutes) +
     ' on the dependency chain &middot; ' + (Dur $g.etaMinutes) + ' downstream chain</div>')
  if ($g.planPage) { W ('<div class="mono"><a href="' + (E $g.planPage) + '" target="_blank" rel="noopener">plan page</a></div>') }
  W '</div>'
}
W '</div></section>'

# ---- owner queue ----
$gates = @($model.owner.gates); $qs = @($model.owner.questions); $wts = @($model.owner.worktrees); $unc = @($model.owner.uncommitted)
W '<section><h2>Owner queue</h2><div class="cols">'
W ('<div class="panel"><h2>Gates waiting (' + $gates.Count + ')</h2>')
if ($gates.Count -eq 0) { W '<div class="empty">None.</div>' } else {
  W '<ul class="q">'
  foreach ($x in $gates) { W ('<li class="warn">' + (Linkify ([string]$x -replace '^\-\s*','')) + '</li>') }
  W '</ul>'
}
W '</div>'
W ('<div class="panel"><h2>Uncommitted integrated (' + $unc.Count + ')</h2>')
if ($unc.Count -eq 0) { W '<div class="empty">None.</div>' } else {
  W ('<div class="chips">' + (($unc | ForEach-Object { '<span class="chip">' + (E ([string]$_)) + '</span>' }) -join '') + '</div>')
}
W '</div>'
function WriteListPanel([string]$title, $items, [string]$Id = '') {
  $items = @($items)
  W ('<div class="panel"' + $(if ($Id) { ' id="' + $Id + '"' }) + '><h2>' + $title + ' (' + $items.Count + ')</h2>')
  if ($items.Count -eq 0) { W '<div class="empty">None.</div>' } else {
    $show = @($items | Select-Object -First 40)
    W ('<details open><summary class="mono muted">showing ' + $show.Count + ' of ' + $items.Count + '</summary><ul class="q">')
    foreach ($x in $show) { W ('<li>' + (Linkify ([string]$x -replace '^\-\s*','')) + '</li>') }
    W '</ul></details>'
  }
  W '</div>'
}
WriteListPanel 'Open questions' $qs 'owner-questions'
WriteListPanel 'Worktrees ready to remove' $wts
W '</div></section>'

# ---- inboxes ----
$limits = [ordered]@{ 'stream-plan'=30; 'stream-author'=30; 'stream-build'=45; 'stream-integrate'=20; 'stream-status'=30; 'stream-kit'=30 }
W '<section><h2>Inboxes</h2>'
W '<div class="tiles">'
foreach ($k in $limits.Keys) {
  $short = $k -replace '^stream-',''
  $open = [int]$model.inbox.$k.open
  W ('<div class="tile"><b>' + $open + '</b><span>' + $short + ' &middot; ' + $limits[$k] + 'm</span></div>')
}
W '</div>'
W ('<div class="muted mono">' + $stuckItems.Count + ' item(s) past their limit</div>')
if ($stuckItems.Count -gt 0) {
  W '<div class="scroll"><table><thead><tr><th>Item</th><th>Inbox</th><th>Status</th><th>Age / limit</th><th>Ask</th></tr></thead><tbody>'
  foreach ($it in ($stuckItems | Sort-Object -Property @{E={$_.ageMinutes}} -Descending)) {
    $ask = [string]$it.ask; if ($ask.Length -gt 200) { $ask = $ask.Substring(0,200) + '...' }
    W ('<tr><td class="id">' + (E $it.id) + '</td><td class="mono">' + (E ($it.inbox -replace '^stream-','')) + '</td><td><span class="pill s-ticketed">' + (E $it.status) + '</span></td><td class="num">' + (Dur $it.ageMinutes) + ' / ' + $it.limitMinutes + 'm</td><td class="note">' + (E $ask) + '</td></tr>')
  }
  W '</tbody></table></div>'
}
W '</section>'

# ---- sessions ----
$sessions = @{}
foreach ($t in $board.tasks) {
  if ($t.claim -and $t.claim.session) {
    $s = $t.claim.session
    $age = Ago $t.claim.beat
    if (-not $sessions.ContainsKey($s) -or $sessions[$s].age -gt $age) {
      $sessions[$s] = [pscustomobject]@{ id = $s; role = $t.claim.role; holding = $t.id; age = $age }
    }
  }
}
# A live session between tasks holds no claim, so the claim walk above misses it: add every live session the model
# found from history or beats, with the age of its last write.
foreach ($rp in @($model.sessions.PSObject.Properties)) {
  foreach ($x in @($rp.Value.list)) {
    if ($x.session -and -not $sessions.ContainsKey($x.session)) {
      $sessions[$x.session] = [pscustomobject]@{ id = $x.session; role = $rp.Name; holding = $x.task; age = $x.ageMinutes }
    }
  }
}
foreach ($p in $model.rolesSeen.PSObject.Properties) {
  if (-not $sessions.ContainsKey($p.Name)) {
    $sessions[$p.Name] = [pscustomobject]@{ id = $p.Name; role = $p.Name; holding = $null; age = (Ago $p.Value) }
  }
}
$rows = @($sessions.Values | Sort-Object age)
$live = @($rows | Where-Object { $_.age -le 60 })
W ('<section id="sessions"><h2>Sessions (' + $live.Count + ' live)</h2>')
$chips = $live | Group-Object role | Sort-Object Name | ForEach-Object { '<span class="chip">' + (E $_.Name) + ' &times;' + $_.Count + '</span>' }
W ('<div class="chips">' + ($chips -join '') + '</div>')
W '<div class="scroll"><table><thead><tr><th>Session</th><th>Role</th><th>Holding</th><th>Beat age</th><th></th></tr></thead><tbody>'
foreach ($r in $rows) {
  $hold = if ($r.holding) { '<span class="mono">' + (E $r.holding) + '</span>' } else { '<span class="muted">&mdash;</span>' }
  $pill = if ($r.age -le 60) { '<span class="pill s-integrated">live</span>' } else { '<span class="pill s-planned">stale</span>' }
  W ('<tr><td class="id">' + (E $r.id) + '</td><td class="mono">' + (E $r.role) + '</td><td class="mono">' + $hold + '</td><td class="num">' + (Dur $r.age) + '</td><td>' + $pill + '</td></tr>')
}
W '</tbody></table></div></section>'

# ---- tasks ----
# Sorted by how much attention the row needs, not by pipeline order. `ticketing` sits with the other work in flight,
# above the planned rows it is drawn from: a row an author is writing right now is not one of the 280 nobody has read.
$order = @{ blocked=0; building=1; built=2; ticketing=3; ticketed=4; planned=5; integrated=6; done=7; retired=8 }
$tsorted = @($model.tasks | Sort-Object @{E={$order[[string]$_.bucket]}}, @{E={$_.id}})
W ('<section><h2>Tasks (' + $model.tasks.Count + ')</h2>')
W '<div class="scroll"><table><thead><tr><th>Id</th><th>Title</th><th>State</th><th>Claim</th><th>Est / elapsed</th><th>Latest note</th></tr></thead><tbody>'
foreach ($t in $tsorted) {
  $cls = @()
  if ($t.critical) { $cls += 'crit' }
  if ($t.overrun -or $t.orphaned) { $cls += 'over'; $cls += 'warn' }
  $claim = if ($t.claimSession) { (E ([string]$t.claimSession)) + ' <span class="muted">beat ' + (Dur $t.claimBeatMinutes) + '</span>' }
           elseif ($t.orphaned) { '<span class="pill s-blocked">orphaned</span>' }
           elseif ($t.integratorHold) { '<span class="muted">' + (E ([string]$t.integratorHold)) + '</span>' }
           else { '<span class="muted">&mdash;</span>' }
  $el = if ($null -ne $t.elapsed) { Dur $t.elapsed } else { '&mdash;' }
  $est = if ($null -ne $t.est) { Dur $t.est } else { '&mdash;' }
  $note = [string]$t.last; if ($note.Length -gt 260) { $note = $note.Substring(0,260) + '...' }
  W ('<tr class="' + ($cls -join ' ') + '"><td class="id">' + (E $t.id) + '</td><td>' + (E $t.title) + '</td><td><span class="pill s-' + (E $t.bucket) + '">' + (E $t.bucket) + '</span></td><td class="mono">' + $claim + '</td><td class="num">' + $est + ' / ' + $el + '</td><td class="note">' + (E $note) + '</td></tr>')
}
W '</tbody></table></div></section>'

W ('<footer class="muted mono">stream-status &middot; ' + (E $Session) + '</footer></div></body></html>')

[System.IO.File]::WriteAllText($Out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ("wrote {0} ({1} bytes); flags {2}; stuck inbox {3}; live sessions {4}" -f $Out, (Get-Item $Out).Length, $flags.Count, $stuckItems.Count, $live.Count)

# Mirror last, and never let it fail the tick: the page on disk is the product, a copy of it is a convenience. A
# comment or a blank line is skipped so the file can say where each target is served from.
if (Test-Path $MirrorFile) {
  foreach ($line in [IO.File]::ReadAllLines($MirrorFile)) {
    $t = $line.Trim()
    if ($t -and -not $t.StartsWith('#') -and -not ($targets -contains $t)) { $targets.Add($t) }
  }
}
foreach ($t in $targets) {
  try {
    $dir = Split-Path $t
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Copy-Item $Out $t -Force
    Write-Output ("mirrored to {0}" -f $t)
  } catch {
    Write-Output ("MIRROR FAILED {0}: {1}" -f $t, $_.Exception.Message)
  }
}
