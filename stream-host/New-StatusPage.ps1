# Renders .streams\status.html (the Speedy Pit Wall) from Get-StreamStatus.ps1 -Json.
# Used by /stream-status so each tick is a script run, not a hand-built page.
[CmdletBinding()]
param(
  [Parameter(Mandatory)][string]$Repo,
  [string[]]$Action = @(),
  [string]$Session = ''
)
$ErrorActionPreference = 'Stop'
$kit = Join-Path $HOME '.claude\skills\stream-kit\scripts\Get-StreamStatus.ps1'
$model = (& $kit -Repo $Repo -Json) | ConvertFrom-Json

function E([string]$s) {
  if ($null -eq $s) { return '' }
  $s.Replace('&', '&amp;').Replace('<', '&lt;').Replace('>', '&gt;').Replace('"', '&quot;')
}
function Dur([int]$m) {
  if ($m -lt 60) { return "$m min" }
  $h = [math]::Floor($m / 60); $r = $m % 60
  if ($h -lt 24) { return ("{0}h {1:00}m" -f $h, $r) }
  $d = [math]::Floor($h / 24); $rh = $h % 24
  return ("{0}d {1}h" -f $d, $rh)
}
function AsUtc($v) {
  # The -Json model's task claims carry no beat, so callers can hand this $null.
  if ($null -eq $v) { return $null }
  if ($v -is [string] -and -not $v.Trim()) { return $null }
  # tasks.json / -Json values come back as [datetime] Kind=Utc. Re-parsing their
  # ToString() drops the Z and shifts by the local offset, so never round-trip them.
  if ($v -is [datetime]) {
    if ($v.Kind -eq [System.DateTimeKind]::Utc) { return $v }
    if ($v.Kind -eq [System.DateTimeKind]::Local) { return $v.ToUniversalTime() }
    return [datetime]::SpecifyKind($v, [System.DateTimeKind]::Utc)
  }
  return [datetime]::Parse([string]$v, [System.Globalization.CultureInfo]::InvariantCulture,
    [System.Globalization.DateTimeStyles]::AdjustToUniversal -bor [System.Globalization.DateTimeStyles]::AssumeUniversal)
}
function Utc([datetime]$d) { $d.ToString("yyyy-MM-ddTHH:mm:ssZ") }
function LinkUp([string]$s) {
  $e = E $s
  [regex]::Replace($e, 'https?://[^\s"<]+', { param($m) '<a href="' + $m.Value + '" target="_blank" rel="noopener">' + $m.Value + '</a>' })
}

$states = 'planned', 'ticketed', 'building', 'built', 'integrated', 'done', 'blocked'
$now = [datetime]::UtcNow
$sb = [System.Text.StringBuilder]::new()
function W([string]$s) { [void]$sb.AppendLine($s) }

$genLocal = (Get-Date).ToString('ddd d MMM yyyy HH:mm')
$totals = @{}
foreach ($s in $states) { $totals[$s] = @($model.tasks | Where-Object { $_.state -eq $s }).Count }
$taskTotal = $model.tasks.Count

W '<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">'
W '<title>Speedy Pit Wall</title>'
W '<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>'
W '<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@600;700&family=Source+Sans+3:wght@400;600&family=JetBrains+Mono:wght@400;600&display=swap">'
W '<style>'
W @'
:root{
  --bg:#f3f5f8; --panel:#ffffff; --ink:#18202b; --muted:#5a6778; --line:#d9dfe7;
  --accent:#d9480f; --planned:#9aa6b5; --ticketed:#3b6fd6; --building:#e0a100; --built:#7c4dd6;
  --integrated:#1b9e77; --done:#137a5b; --blocked:#c92a2a; --warn-bg:#fff4e0; --warn-ink:#8a5200;
  color-scheme:light;
}
@media (prefers-color-scheme:dark){:root:not([data-theme="light"]){
  --bg:#0f141b; --panel:#171e28; --ink:#e6ebf2; --muted:#93a0b1; --line:#2a3442;
  --accent:#ff7a3d; --planned:#6b7787; --ticketed:#6c9bff; --building:#f2c14e; --built:#a98bff;
  --integrated:#3fc79a; --done:#2fae83; --blocked:#ff6b6b; --warn-bg:#33270f; --warn-ink:#f2c14e;
  color-scheme:dark;}}
:root[data-theme="dark"]{
  --bg:#0f141b; --panel:#171e28; --ink:#e6ebf2; --muted:#93a0b1; --line:#2a3442;
  --accent:#ff7a3d; --planned:#6b7787; --ticketed:#6c9bff; --building:#f2c14e; --built:#a98bff;
  --integrated:#3fc79a; --done:#2fae83; --blocked:#ff6b6b; --warn-bg:#33270f; --warn-ink:#f2c14e;
  color-scheme:dark;}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font:15px/1.5 "Source Sans 3",system-ui,sans-serif;padding:0 16px}
.wrap{max-width:1180px;margin:0 auto;padding-block:26px 56px;display:grid;gap:22px}
h1,h2{font-family:"Barlow Condensed","Arial Narrow",sans-serif;font-weight:700;margin:0;letter-spacing:.01em;text-wrap:balance}
h1{font-size:2.1rem}
h2{font-size:1.2rem;text-transform:uppercase;letter-spacing:.07em;color:var(--muted)}
header{display:flex;flex-wrap:wrap;justify-content:space-between;align-items:end;gap:10px;border-bottom:3px solid var(--accent);padding-bottom:10px}
header .meta{color:var(--muted);font-size:.85rem;font-family:"JetBrains Mono",monospace}
section{display:grid;gap:10px}
.panel{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:14px 16px;display:grid;gap:8px}
.mono{font-family:"JetBrains Mono",ui-monospace,monospace;font-variant-numeric:tabular-nums}
.muted{color:var(--muted)}
.tiles{display:grid;grid-template-columns:repeat(auto-fit,minmax(118px,1fr));gap:10px}
.tile{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:10px 12px;display:grid;gap:2px}
.tile b{font-family:"Barlow Condensed",sans-serif;font-size:1.9rem;line-height:1;font-variant-numeric:tabular-nums}
.tile span{font-size:.72rem;text-transform:uppercase;letter-spacing:.07em;color:var(--muted)}
.bar{display:flex;height:13px;border-radius:3px;overflow:hidden;background:var(--line)}
.bar i{display:block;height:100%}
.legend{display:flex;flex-wrap:wrap;gap:6px 14px;font-size:.78rem;color:var(--muted)}
.legend em{font-style:normal}
.legend s{text-decoration:none;display:inline-block;width:10px;height:10px;border-radius:2px;margin-right:5px;vertical-align:-1px}
.groups{display:grid;gap:12px}
.grp .top{display:flex;flex-wrap:wrap;gap:6px 14px;justify-content:space-between;align-items:baseline}
.grp .name{font-weight:600}
.eta{font-family:"Barlow Condensed",sans-serif;font-size:1.45rem;font-weight:700}
.eta small{font-family:"Source Sans 3",sans-serif;font-size:.75rem;font-weight:400;color:var(--muted)}
.pill{display:inline-block;padding:1px 7px;border-radius:3px;font:600 11px "JetBrains Mono",monospace;color:#fff;text-transform:uppercase;letter-spacing:.04em;white-space:nowrap}
.s-planned{background:var(--planned)}.s-ticketed{background:var(--ticketed)}.s-building{background:var(--building);color:#1a1300}
.s-built{background:var(--built)}.s-integrated{background:var(--integrated)}.s-done{background:var(--done)}.s-blocked{background:var(--blocked)}
.s-released{background:var(--accent)}.s-closed{background:var(--done)}.s-planning{background:var(--planned)}
.scroll{overflow-x:auto;background:var(--panel);border:1px solid var(--line);border-radius:6px}
table{border-collapse:collapse;width:100%;font-size:13px}
th,td{text-align:left;vertical-align:top;padding:6px 9px;border-bottom:1px solid var(--line)}
th{font-size:11px;letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}
td.id{font-family:"JetBrains Mono",monospace;white-space:nowrap}
td.num{font-family:"JetBrains Mono",monospace;white-space:nowrap;font-variant-numeric:tabular-nums}
tr.crit td.id::before{content:"";display:inline-block;width:6px;height:6px;border-radius:50%;background:var(--accent);margin-right:6px;vertical-align:2px}
tr.over td.num{color:var(--blocked);font-weight:600}
.note{color:var(--muted);font-size:12px;max-width:52ch}
.flag{background:var(--warn-bg);color:var(--warn-ink);border-radius:4px;padding:8px 12px;font-weight:600;font-size:.9rem}
ul.q{list-style:none;margin:0;padding:0;display:grid;gap:8px}
ul.q li{border-left:3px solid var(--line);padding-left:10px;font-size:.9rem}
ul.q li.warn{border-left-color:var(--building)}
.cols{display:grid;grid-template-columns:repeat(auto-fit,minmax(320px,1fr));gap:18px;align-items:start}
.chips{display:flex;flex-wrap:wrap;gap:6px}
.chip{font:600 12px "JetBrains Mono",monospace;border:1px solid var(--line);border-radius:3px;padding:2px 7px}
.empty{color:var(--muted);font-style:italic}
a{color:var(--ticketed)}
a:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
details>summary{cursor:pointer;color:var(--muted);font-size:.85rem}
@media (max-width:640px){h1{font-size:1.6rem}.wrap{padding-block:18px 40px}}
'@
W '</style></head><body><div class="wrap">'

# ---------- header ----------
W '<header><div><h1>Speedy Pit Wall</h1>'
W ('<div class="meta">' + (E $model.repo) + '</div></div>')
W ('<div class="meta">generated ' + (E $genLocal) + ' &middot; ' + (E $model.at) + '</div></header>')

# ---------- tiles ----------
W '<section><div class="tiles">'
W ('<div class="tile"><b>' + $taskTotal + '</b><span>tasks</span></div>')
foreach ($s in $states) { W ('<div class="tile"><b>' + $totals[$s] + '</b><span>' + $s + '</span></div>') }
W '</div></section>'

# ---------- this tick ----------
W '<section><h2>This tick</h2><div class="panel">'
if ($Action.Count -eq 0) { W '<div class="empty">Watchdog quiet. No claim broken, no inbox item taken.</div>' }
else { W '<ul class="q">'; foreach ($a in $Action) { W ('<li>' + (LinkUp $a) + '</li>') }; W '</ul>' }
if (@($model.flags).Count -gt 0) {
  W ('<div class="muted mono">' + @($model.flags).Count + ' flags</div>')
  foreach ($f in $model.flags) { W ('<div class="flag">' + (LinkUp $f) + '</div>') }
}
else { W '<div class="empty">No flags.</div>' }
W '</div></section>'

# ---------- groups ----------
W '<section><h2>Groups</h2><div class="groups">'
foreach ($g in $model.groups) {
  $c = $g.counts
  $tot = 0; foreach ($s in $states) { $tot += [int]$c.$s }
  if ($tot -eq 0) { $tot = 1 }
  W '<div class="panel grp">'
  W ('<div class="top"><div><span class="name">' + (E $g.id) + ' &middot; ' + (E $g.name) + '</span> <span class="pill s-' + (E $g.state) + '">' + (E $g.state) + '</span></div>')
  $eta = if ($null -ne $g.etaMinutes) { (Dur ([int]$g.etaMinutes)) } else { 'n/a' }
  W ('<div class="eta">' + $eta + ' <small>critical path</small></div></div>')
  W '<div class="bar">'
  foreach ($s in $states) {
    $n = [int]$c.$s
    if ($n -gt 0) { W ('<i class="s-' + $s + '" style="width:' + [math]::Round(100.0 * $n / $tot, 3) + '%" title="' + $s + ' ' + $n + '"></i>') }
  }
  W '</div>'
  $leg = foreach ($s in $states) { if ([int]$c.$s -gt 0) { '<em><s class="s-' + $s + '"></s>' + $s + ' ' + [int]$c.$s + '</em>' } }
  W ('<div class="legend">' + ($leg -join '') + '</div>')
  if ($g.planPage) { W ('<div class="mono"><a href="' + (E $g.planPage) + '" target="_blank" rel="noopener">plan page</a></div>') }
  W '</div>'
}
W '</div></section>'

# ---------- owner queue ----------
$o = $model.owner
W '<section><h2>Owner queue</h2><div class="cols">'
W ('<div class="panel"><h2>Gates waiting (' + @($o.gates).Count + ')</h2>')
if (@($o.gates).Count) { W '<ul class="q">'; foreach ($x in $o.gates) { W ('<li class="warn">' + (LinkUp ($x -replace '^\-\s*', '')) + '</li>') }; W '</ul>' } else { W '<div class="empty">none</div>' }
W '</div>'
W ('<div class="panel"><h2>Uncommitted integrated (' + @($o.uncommitted).Count + ')</h2>')
if (@($o.uncommitted).Count) { W ('<div class="chips">' + ((@($o.uncommitted) | ForEach-Object { '<span class="chip">' + (E $_) + '</span>' }) -join '') + '</div>') } else { W '<div class="empty">none</div>' }
W '</div></div>'
W ('<div class="panel"><h2>Open questions (' + @($o.questions).Count + ')</h2>')
if (@($o.questions).Count) {
  W '<details open><summary>show all</summary><ul class="q">'
  foreach ($x in $o.questions) { W ('<li>' + (LinkUp ($x -replace '^\-\s*', '')) + '</li>') }
  W '</ul></details>'
}
else { W '<div class="empty">none</div>' }
W '</div>'
W ('<div class="panel"><h2>Worktrees ready to remove (' + @($o.worktrees).Count + ')</h2>')
if (@($o.worktrees).Count) {
  W '<details><summary>show all</summary><ul class="q">'
  foreach ($x in $o.worktrees) { W ('<li class="mono">' + (E ($x -replace '^\-\s*', '')) + '</li>') }
  W '</ul></details>'
}
else { W '<div class="empty">none</div>' }
W '</div></section>'

# ---------- inboxes ----------
W '<section><h2>Inboxes</h2>'
$limits = @{ 'stream-author' = 30; 'stream-build' = 45; 'stream-integrate' = 20; 'stream-plan' = 30; 'stream-status' = 30; 'stream-kit' = 30 }
$order6 = 'stream-plan', 'stream-author', 'stream-build', 'stream-integrate', 'stream-status', 'stream-kit'
W '<div class="tiles">'
foreach ($k in $order6) {
  $n = [int]$model.inbox.$k.open
  W ('<div class="tile"><b>' + $n + '</b><span>' + $k.Replace('stream-', '') + ' &middot; ' + $limits[$k] + 'm</span></div>')
}
W '</div>'
$rows = @()
foreach ($k in $order6) {
  foreach ($s in @($model.inbox.$k.stuck)) {
    if (-not $s) { continue }
    $m = [regex]::Match($s, '^(?<id>\S+)\s+(?<st>\w+)\s+(?<age>\d+)m:\s*(?<ask>.*)$')
    if ($m.Success) { $rows += [pscustomobject]@{ inbox = $k; id = $m.Groups['id'].Value; st = $m.Groups['st'].Value; age = [int]$m.Groups['age'].Value; limit = $limits[$k]; ask = $m.Groups['ask'].Value } }
    else { $rows += [pscustomobject]@{ inbox = $k; id = '-'; st = '-'; age = 0; limit = $limits[$k]; ask = $s } }
  }
}
if ($rows.Count) {
  W ('<div class="muted mono">' + $rows.Count + ' item(s) past their limit</div>')
  W '<div class="scroll"><table><thead><tr><th>Item</th><th>Inbox</th><th>Status</th><th>Age / limit</th><th>Ask</th></tr></thead><tbody>'
  foreach ($r in ($rows | Sort-Object -Property @{e = { $_.age }; Descending = $true })) {
    $sp = if ($r.st -eq 'taken') { 'building' } else { 'ticketed' }
    W ('<tr><td class="id">' + (E $r.id) + '</td><td class="mono">' + (E $r.inbox.Replace('stream-', '')) + '</td><td><span class="pill s-' + $sp + '">' + (E $r.st) + '</span></td><td class="num">' + (Dur $r.age) + ' / ' + $r.limit + 'm</td><td class="note">' + (E $r.ask) + '</td></tr>')
  }
  W '</tbody></table></div>'
}
else { W '<div class="panel"><div class="empty">No inbox item past its limit.</div></div>' }
W '</section>'

# ---------- sessions ----------
# One row per SESSION, not per role: the fleet runs several authors and builders at once,
# and rolesSeen keeps only the newest beat per role, so it cannot show them.
$doc = Get-Content (Join-Path $Repo '.streams\tasks.json') -Raw | ConvertFrom-Json
$sessions = [ordered]@{}
function Note([string]$sid, [string]$role, $beat, [string]$holds) {
  if (-not $sid) { return }
  if ($null -eq $beat -or ($beat -is [string] -and -not $beat.Trim())) { return }
  $b = AsUtc $beat
  if ($sessions.Contains($sid)) {
    $e = $sessions[$sid]
    if ($b -gt $e.beat) { $e.beat = $b }
    if ($holds) { $e.holds += $holds }
    if ($role -and -not $e.role) { $e.role = $role }
  }
  else {
    $sessions[$sid] = [pscustomobject]@{ sid = $sid; role = $role; beat = $b; holds = @($holds | Where-Object { $_ }) }
  }
}
$claimOf = @{}
foreach ($t in $doc.tasks) { if ($t.claim) { $claimOf[$t.id] = $t.claim; Note $t.claim.session $t.claim.role $t.claim.beat $t.id } }
$lockPath = Join-Path $Repo '.streams\integrator.lock'
if (Test-Path $lockPath) {
  $lk = Get-Content $lockPath -Raw | ConvertFrom-Json
  Note $lk.session 'integrate' $lk.beat 'main tree'
}
foreach ($p in $model.rolesSeen.PSObject.Properties) {
  if (-not $sessions.Contains($p.Name)) { Note $p.Name $p.Name $p.Value '' }
}
$live = @($sessions.Values | Where-Object { ($now - $_.beat).TotalMinutes -le 20 })
$byRole = $live | Group-Object role | Sort-Object Name
W ('<section><h2>Sessions (' + $live.Count + ' live)</h2>')
if ($byRole) { W ('<div class="chips">' + (($byRole | ForEach-Object { '<span class="chip">' + (E $_.Name) + ' &times;' + $_.Count + '</span>' }) -join '') + '</div>') }
W '<div class="scroll"><table><thead><tr><th>Session</th><th>Role</th><th>Holding</th><th>Last beat (UTC)</th><th>Age</th><th></th></tr></thead><tbody>'
foreach ($s in ($sessions.Values | Sort-Object beat -Descending)) {
  $age = [int]($now - $s.beat).TotalMinutes
  $cls = if ($age -le 20) { 'integrated' } elseif ($age -le 60) { 'building' } else { 'planned' }
  $word = if ($age -le 20) { 'live' } elseif ($age -le 60) { 'idle' } else { 'gone' }
  $h = if ($s.holds.Count) { (E ($s.holds -join ', ')) } else { '<span class="muted">&mdash;</span>' }
  W ('<tr><td class="id">' + (E $s.sid) + '</td><td class="mono">' + (E $s.role) + '</td><td class="mono">' + $h + '</td><td class="num">' + (Utc $s.beat) + '</td><td class="num">' + (Dur $age) + '</td><td><span class="pill s-' + $cls + '">' + $word + '</span></td></tr>')
}
W '</tbody></table></div></section>'

# ---------- tasks ----------
W ('<section><h2>Tasks (' + $taskTotal + ')</h2>')
W '<div class="scroll"><table><thead><tr><th>Id</th><th>Title</th><th>State</th><th>Claim</th><th>Est / elapsed</th><th>Latest</th></tr></thead><tbody>'
$order = @{}; $i = 0; foreach ($s in 'blocked', 'building', 'built', 'ticketed', 'integrated', 'planned', 'done') { $order[$s] = $i; $i++ }
foreach ($t in ($model.tasks | Sort-Object @{e = { $order[$_.state] } }, @{e = { $_.id } })) {
  $cls = @(); if ($t.critical) { $cls += 'crit' }; if ($t.overrun) { $cls += 'over' }
  # The -Json model's claim has no beat; the real one is in tasks.json ($claimOf).
  $cl = if ($t.claim) { $t.claim } else { $claimOf[$t.id] }
  $claim = if ($cl) {
    $cb = AsUtc $cl.beat
    $bt = if ($cb) { ' &middot; beat ' + (Dur ([int]($now - $cb).TotalMinutes)) } else { '' }
    (E $cl.session) + ' <span class="muted">' + (E $cl.role) + $bt + '</span>'
  }
  else { '<span class="muted">&mdash;</span>' }
  $el = if ($null -ne $t.elapsed) { (Dur ([int]$t.elapsed)) } else { '&mdash;' }
  $est = if ($null -ne $t.est) { (Dur ([int]$t.est)) } else { '&mdash;' }
  W ('<tr class="' + ($cls -join ' ') + '"><td class="id">' + (E $t.id) + '</td><td>' + (E $t.title) + '</td><td><span class="pill s-' + (E $t.state) + '">' + (E $t.state) + '</span></td><td class="mono">' + $claim + '</td><td class="num">' + $est + ' / ' + $el + '</td><td class="note">' + (E $t.last) + '</td></tr>')
}
W '</tbody></table></div></section>'
$foot = '<footer class="muted mono">stream-status'
if ($Session) { $foot += ' &middot; ' + (E $Session) }
W ($foot + '</footer></div></body></html>')

$out = Join-Path $Repo '.streams\status.html'
[System.IO.File]::WriteAllText($out, $sb.ToString(), (New-Object System.Text.UTF8Encoding($false)))
Write-Output $out
