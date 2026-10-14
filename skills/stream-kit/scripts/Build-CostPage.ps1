# Renders .streams\cost.html from .streams\cost\summary.json (2026-10-05 priority-focus-design 3.5): spend by role, day,
# group and model, the ten most expensive tasks, runner-unit outcomes, waste buckets (idle and blocked units,
# re-authors, refreshes, rebuilds, bounced patches, long-session hours with no work; suite runs as machine time), $ per
# integrated task per group against its estimate, and rule flags. Script only, no model tokens.
# Rule flags (spec 3.5): idle launches in the last 24 h; blocked-unit share > 10%; unattributed > 5%; a long session
# spending in > 50% of its hours with no work; a task above 2x its group's median
# (groups with 4+ priced tasks). Prices are list prices and the stream account is a subscription, so the page says
# 'notional'.
#   Build-CostPage.ps1 -Repo <repo> -Session <id> [-Out <path>]
# The machine profile's StatusPageDir row gets a copy as cost.html, the same rule as the status page: the real board
# only (a caller that names -Out, such as the self-tests, gets exactly that file), and a blank row means no copy.
param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Session, [string]$Out)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$sumPath = Join-Path $P.Root 'cost\summary.json'
if (-not (Test-Path $sumPath)) { "NO-SUMMARY run Get-StreamCost.ps1 first"; exit 2 }
$s = Get-Content -Raw $sumPath | ConvertFrom-Json -AsHashtable -DateKind String
$mirror = -not $Out
if (-not $Out) { $Out = Join-Path $P.Root 'cost.html' }
# Not H: H is the built-in alias of Get-History, and an alias wins over a function of the same name.
function Enc([string] $t) { [Net.WebUtility]::HtmlEncode($t) }
function Money([double] $v) { '$' + $v.ToString('N2', [Globalization.CultureInfo]::InvariantCulture) }
function Table([string] $title, $dict, [int] $top = 0) {
    $rows = @($dict.GetEnumerator() | Sort-Object { [double]$_.Value } -Descending)
    if ($top) { $rows = @($rows | Select-Object -First $top) }
    $w = [Text.StringBuilder]::new()
    [void]$w.Append("<section><h2>$(Enc $title)</h2><table><tr><th>key</th><th>usd</th><th>share</th></tr>")
    foreach ($r in $rows) {
        $pct = if ([double]$s['total']) { [math]::Round(100.0 * [double]$r.Value / [double]$s['total'], 1) } else { 0 }
        [void]$w.Append("<tr><td class=`"id`">$(Enc ([string]$r.Key))</td><td class=`"num`">$(Money ([double]$r.Value))</td><td class=`"num`">$pct%</td></tr>")
    }
    if (-not $rows.Count) { [void]$w.Append('<tr><td colspan="3" class="muted">none yet</td></tr>') }
    [void]$w.Append('</table></section>')
    $w.ToString()
}
# ---- rule flags ----
$flags = [Collections.Generic.List[string]]::new()
if ([double]$s['unattributedPct'] -gt 5) { $flags.Add("unattributed $($s['unattributedPct'])% of spend has no stream session: check .streams\sessions and the runner results") }
$byOutcome = $s['byOutcome']
$blocked = [double]$byOutcome['blocked']; $unitTotal = 0.0; foreach ($v in $byOutcome.Values) { $unitTotal += [double]$v }
if ($unitTotal -and $blocked / $unitTotal -gt 0.10) { $flags.Add("blocked units are $([math]::Round(100 * $blocked / $unitTotal, 1))% of runner spend ($(Money $blocked)): planner-side causes, see the status page") }
# Idle launches: the last 24 h only (spec 3.5), so one old idle unit does not flag for ever.
$o24 = if ($s['byOutcome24h'] -is [Collections.IDictionary]) { $s['byOutcome24h'] } else { @{} }
if ([double]$o24['idle'] -gt 0) { $flags.Add("idle launches cost $(Money ([double]$o24['idle'])) in the last 24 h: the gate launched a unit into NONE") }
$doc = Read-Tasks $P
$groupOf = @{}; foreach ($t in @($doc['tasks'])) { $groupOf[[string]$t['id']] = [string]$t['group'] }
$byTask = $s['byTask']
$byGroupTasks = @{}
foreach ($k in @($byTask.Keys)) {
    if ($k -eq '-') { continue }; $g = $groupOf[$k]; if (-not $g) { continue }
    if (-not $byGroupTasks.ContainsKey($g)) { $byGroupTasks[$g] = [Collections.Generic.List[double]]::new() }
    $byGroupTasks[$g].Add([double]$byTask[$k])
}
foreach ($g in @($byGroupTasks.Keys)) {
    $vals = @($byGroupTasks[$g] | Sort-Object); if ($vals.Count -lt 4) { continue }
    $med = $vals[[int][math]::Floor($vals.Count / 2)]
    foreach ($k in @($byTask.Keys)) { if ($groupOf[$k] -eq $g -and [double]$byTask[$k] -gt 2 * $med) { $flags.Add("$k cost $(Money ([double]$byTask[$k])), over 2x the $g median $(Money $med)") } }
}
# ---- waste buckets, $ per integrated task, long-session no-work (spec 3.5) ----
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
$taskRole = if ($s['byTaskRole'] -is [Collections.IDictionary]) { $s['byTaskRole'] } else { @{} }
$roleUsd = { param([string] $id, [string] $r) $x = $taskRole[$id]; if ($x -is [Collections.IDictionary] -and $x.Contains($r)) { [double]$x[$r] } else { 0.0 } }
$waste = [ordered]@{ 'idle launches' = [double]$byOutcome['idle']; 'units ended blocked' = [double]$byOutcome['blocked'] }
$reauthor = 0.0; $refresh = 0.0; $rebuild = 0.0; $bounced = 0.0; $nRe = 0; $nRf = 0; $nRb = 0; $nBo = 0
$workHours = @{}   # stream session -> hours (yyyy-MM-ddTHH) in which it wrote task history
foreach ($t in @($doc['tasks'])) {
    $id = [string]$t['id']; $h = @($t['history'] | Where-Object { $_ -is [Collections.IDictionary] })
    $kt = @($h | Where-Object { $_['to'] -eq 'ticketed' }).Count
    $kb = @($h | Where-Object { $_['to'] -eq 'built' }).Count
    if ($kt -gt 1) { $reauthor += (& $roleUsd $id 'author') * ($kt - 1) / $kt; $nRe++ }
    if (@($h | Where-Object { ([string]$_['note'] -match '(^|-- )STALE: ') }).Count) { $refresh += (& $roleUsd $id 'author') / [math]::Max(1, $kt); $nRf++ }
    if ($kb -gt 1) { $rebuild += (& $roleUsd $id 'build') * ($kb - 1) / $kb; $nRb++ }
    for ($i = 1; $i -lt $h.Count; $i++) { if ($h[$i]['to'] -in @('ticketed', 'planned') -and $h[$i - 1]['to'] -eq 'built') { $nBo++; $bounced += (& $roleUsd $id 'build') / [math]::Max(1, $kb); break } }
    foreach ($e in $h) {
        if (-not $e['by'] -or -not $e['at']) { continue }
        try { $hk = ([datetime]::Parse([string]$e['at'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).ToString('yyyy-MM-ddTHH') } catch { continue }
        $by = [string]$e['by']; if (-not $workHours.ContainsKey($by)) { $workHours[$by] = @{} }; $workHours[$by][$hk] = $true
    }
}
# Work is any line a session wrote: task history above, decisions.md ("- <utc> [<session>] ..."), and inbox lines
# ("- IN-... | <utc> | <session> | ..."). Task history alone flagged the kit and coordinator sessions on every page,
# because their work is inbox items and decisions, not task moves (final review I8).
$addWork = { param([string] $by, [string] $at)
    try { $hk = ([datetime]::Parse($at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).ToString('yyyy-MM-ddTHH') } catch { return }
    if (-not $workHours.ContainsKey($by)) { $workHours[$by] = @{} }; $workHours[$by][$hk] = $true }
if (Test-Path -LiteralPath $P.Decisions) { foreach ($l in @(Read-SharedLines $P.Decisions)) { if ($l -match '^- (\S+Z) \[([^\]]+)\]') { & $addWork $Matches[2] $Matches[1] } } }
foreach ($ib in @(Get-ChildItem (Join-Path $P.Root 'inbox') -Filter '*.md' -File -ErrorAction SilentlyContinue)) {
    foreach ($l in @(Read-SharedLines $ib.FullName)) { if ($l -match '^- IN-\S+ \| (\S+) \| (\S+) \|') { & $addWork $Matches[2] $Matches[1] } }
}
$waste["re-authors ($nRe rows)"] = $reauthor; $waste["refreshes ($nRf rows)"] = $refresh; $waste["rebuilds ($nRb rows)"] = $rebuild; $waste["bounced patches ($nBo rows)"] = $bounced
# Tier 2 / Tier 3 / flaky runs are scripts (no model tokens): their cost is machine time, shown as run counts and hours.
$runsTxt = [Collections.Generic.List[string]]::new()
if (Test-Path -LiteralPath $P.Suites) {
    $recs = @(Get-SuiteRunRecords $P)
    foreach ($tier in '2', '3', 'flaky') {
        $rs = @($recs | Where-Object { [string]$_['tier'] -eq $tier }); $hrs = 0.0
        foreach ($r in $rs) { if ($r['endedAt']) { $hrs += ((ConvertTo-UtcTime $r['endedAt']) - (ConvertTo-UtcTime $r['startedAt'])).TotalHours } }
        $runsTxt.Add("Tier $tier`: $($rs.Count) runs, $([math]::Round($hrs, 1)) h")
    }
}
# Long sessions: spend in hours in which the session wrote no task history, decision or inbox line is "no work"; > 50%
# of its spending hours flags it (spec 3.5 rule flag). bySessionHour holds the last 24 h and no status session.
$noWork = 0.0
$sh = if ($s['bySessionHour'] -is [Collections.IDictionary]) { $s['bySessionHour'] } else { @{} }
foreach ($ss in @($sh.Keys)) {
    $hours = $sh[$ss]; $idleH = 0; $idleUsd = 0.0
    foreach ($hk in @($hours.Keys)) { if (-not ($workHours.ContainsKey($ss) -and $workHours[$ss].ContainsKey($hk))) { $idleH++; $idleUsd += [double]$hours[$hk] } }
    $noWork += $idleUsd
    if ($hours.Count -ge 2 -and $idleH / $hours.Count -gt 0.5) { $flags.Add("long session $ss spent in $idleH of $($hours.Count) hours with no work ($(Money $idleUsd)): back it off or stop it") }
}
$waste['long sessions, hours with no work'] = $noWork
# $ per integrated task, per group, against its estimate.
$perTask = [Text.StringBuilder]::new()
[void]$perTask.Append('<section><h2>$ per integrated task</h2><table><tr><th>group</th><th>tasks</th><th>usd</th><th>$/task</th><th>est h</th><th>$/est h</th></tr>')
foreach ($g in @($doc['groups'])) {
    $gid = [string]$g['id']
    $ts = @($doc['tasks'] | Where-Object { [string]$_['group'] -eq $gid -and $_['state'] -in @('integrated', 'done') -and $_['kind'] -in @('code', 'docs', 'mockup') })
    if (-not $ts.Count) { continue }
    $u = 0.0; $est = 0.0; foreach ($t in $ts) { if ($byTask.Contains([string]$t['id'])) { $u += [double]$byTask[[string]$t['id']] }; $est += [double]$t['estMinutes'] }
    $estH = $est / 60
    [void]$perTask.Append("<tr><td class=`"id`">$(Enc $gid)</td><td class=`"num`">$($ts.Count)</td><td class=`"num`">$(Money $u)</td><td class=`"num`">$(Money ($u / $ts.Count))</td><td class=`"num`">$([math]::Round($estH, 1))</td><td class=`"num`">$(if ($estH) { Money ($u / $estH) } else { '-' })</td></tr>")
}
[void]$perTask.Append('</table></section>')

# ---- page ----
$head = Get-Content -Raw (Join-Path $PSScriptRoot 'status-page-head.html')
$b = [Text.StringBuilder]::new()
[void]$b.Append($head.TrimEnd())
[void]$b.Append('<style>.flag.ok{background:var(--panel);color:var(--muted)}</style>')
[void]$b.Append("<h1>Speedy stream cost</h1><p class=`"muted`">$(Enc ([string]$s['at'])) &middot; notional: list prices ($(Enc ([string]$s['pricesVersion']))); the stream account is a subscription &middot; $($s['rows']) ledger rows &middot; unpriced rows $($s['unpriced'])</p>")
[void]$b.Append("<div class=`"tiles`"><div class=`"tile`"><b>$(Money ([double]$s['total']))</b><span>total</span></div><div class=`"tile`"><b>$(Money ([double]$s['unattributed']))</b><span>unattributed &middot; $($s['unattributedPct'])%</span></div><div class=`"tile`"><b>$(Money ([double]$s['addedUsd']))</b><span>added last tick</span></div></div>")
[void]$b.Append('<section id="flags"><h2>Flags</h2>')
if ($flags.Count) { foreach ($f in $flags) { [void]$b.Append("<div class=`"flag warn`">$(Enc $f)</div>") } } else { [void]$b.Append('<div class="flag ok">none</div>') }
[void]$b.Append('</section>')
[void]$b.Append((Table 'Waste' $waste))
if ($runsTxt.Count) { [void]$b.Append("<p class=`"mono muted`">suite runs (machine time, no tokens): $($runsTxt -join ' &middot; ')</p>") }
[void]$b.Append($perTask.ToString())
[void]$b.Append((Table 'By role' $s['byRole']))
[void]$b.Append((Table 'By day' $s['byDay']))
[void]$b.Append((Table 'By group' $s['byGroup']))
[void]$b.Append((Table 'Top 10 tasks' $byTask 10))
[void]$b.Append((Table 'Runner units by outcome' $byOutcome))
[void]$b.Append((Table 'By model' $s['byModel']))
[void]$b.Append('</div></body></html>')
Write-AtomicText $Out $b.ToString()
if ($mirror) {
    try {
        $lib = Join-Path $PSScriptRoot '..\..\..\lib\MachineConfig.psm1'
        if (Test-Path -LiteralPath $lib) {
            Import-Module $lib -Force
            $pageDir = Get-AIPath StatusPageDir -Optional
            if ($pageDir) { Copy-Item -LiteralPath $Out (Join-Path $pageDir 'cost.html') -Force }
        }
    } catch { "MIRROR-FAILED $($_.Exception.Message)" }
}
"COST-PAGE $Out"
exit 0
