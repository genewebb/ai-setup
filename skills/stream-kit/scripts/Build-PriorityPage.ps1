# Renders .streams\priority.html: the focus group as one matrix, row by row in the order work will be taken
# (2026-10-05 priority-focus-design 3.4). Script only, no model tokens. stream-status runs it every tick after
# Build-StatusPage.ps1; it also records the focus group's milestones (lib\Activation.ps1 Update-ActivationMilestones).
#   Build-PriorityPage.ps1 -Repo <repo> -Session <id> [-Out <path>]
# Content:
#   header : focus group, milestones M1 Authored / M2 Claimable / M3 Integrator-ready with the time each was first
#            reached, the ETA from the status model's forecast (measured rate, up-chain floor), focus spend so far;
#   owner  : open owner-queue lines (owner\questions.md) that name the focus group or one of its rows, and its open gates;
#   matrix : the focus groups' rows (own rows plus Get-GroupSet), and any other open row of the claim scope. Open rows in claim order (integration fixes first, effective group, ready
#            first, longest chain, board order: Claim-Task.ps1's sort); landed rows after them by integration time.
#            Columns: order, id, group, title, depends on, Author, Build, Integrate, Test, est min, actual min, $.
#            A stage cell is the stage's state, the session that did it and that stage's spend (ledger role).
#            Highlighted: stale (a STALE: note), blocked (with its cause: write set, requirement, skeptic, gate,
#            other), owner-gated (a gate row not done). "blocked: write set" rows are counted per group: the planner
#            fixes write sets;
#   footer : the next group's counts.
# The page is mirrored to {StatusPageDir}\priority.html like the status page (the real board only; -Out names exactly
# one file). .streams\priority-url.txt is written once from status-url.txt (status.html -> priority.html).
param([Parameter(Mandatory)][string]$Repo, [Parameter(Mandatory)][string]$Session, [string]$Out)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
. "$PSScriptRoot\lib\Activation.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$mirror = -not $Out
if (-not $Out) { $Out = Join-Path $P.Root 'priority.html' }
function Enc([string] $t) { [Net.WebUtility]::HtmlEncode($t) }
function Money([double] $v) { '$' + $v.ToString('N2', [Globalization.CultureInfo]::InvariantCulture) }
$doc = Read-Tasks $P
$focus = Get-FocusGroup $doc
$head = Get-Content -Raw (Join-Path $PSScriptRoot 'status-page-head.html')
$b = [Text.StringBuilder]::new()
[void]$b.Append($head.TrimEnd().Replace('<title>Speedy Pit Wall</title>', '<title>Speedy Priority</title>'))
[void]$b.Append('<style>tr.stale td{background:var(--warn-bg)}tr.blocked td{background:color-mix(in srgb,var(--blocked) 12%,transparent)}tr.gated td.id{color:var(--accent)}td.stage{min-width:120px;font-size:12px}td.stage b{display:block;font-weight:600}td.stage span{color:var(--muted)}.ms{display:flex;flex-wrap:wrap;gap:8px}.ms .chip.on{border-color:var(--integrated);color:var(--integrated)}</style>')
if (-not $focus) {
    [void]$b.Append('<header><h1>Speedy priority</h1></header><p class="empty">Every group is closed.</p></div></body></html>')
    Write-AtomicText $Out $b.ToString(); "PRIORITY-PAGE $Out (no focus group)"; exit 0
}
# The matrix is the focus GROUPS' work: each focus group's own rows plus its group set (rows whose EFFECTIVE group is
# that group, lib\Activation.ps1 Get-GroupSet). Get-FocusSet is the CLAIM scope and also holds every row of every
# closed group, so a leftover built row there can still land; read as the page's rows it put 566 done rows of G1-G3
# into the G4 matrix beside G4's 119 (kit item IN-20261006113826-4fb1). An OPEN row of the claim scope outside the
# focus groups still shows, because it is work the claim will offer next; a landed one does not.
$set = Get-FocusSet $doc
$own = [Collections.Generic.HashSet[string]]::new()
foreach ($fg in @((Get-FocusGroups $doc $P).groups)) {
    foreach ($t in $doc.tasks) { if ([string]$t.group -eq $fg) { [void]$own.Add([string]$t.id) } }
    foreach ($id in (Get-GroupSet $doc $fg)) { [void]$own.Add($id) }
}
$byId = @{}; foreach ($t in $doc.tasks) { $byId[[string]$t.id] = $t }
$rows = @($doc.tasks | Where-Object { $own.Contains([string]$_.id) -or ($set.Contains([string]$_.id) -and $_.state -notin @('integrated', 'done')) })

# ---- milestones (recorded on the activation record, first time reached) ----
$act = Update-ActivationMilestones $P $doc $focus
$ms = Get-GroupMilestones $P $doc $focus

# ---- spend (ledger summary) ----
$sum = Read-JsonFile (Join-Path $P.Root 'cost\summary.json')
$taskRole = if ($sum -and $sum['byTaskRole'] -is [Collections.IDictionary]) { $sum['byTaskRole'] } else { @{} }
$taskUsd = if ($sum -and $sum['byTask'] -is [Collections.IDictionary]) { $sum['byTask'] } else { @{} }
$focusUsd = 0.0; foreach ($t in $rows) { if ($taskUsd.Contains([string]$t.id)) { $focusUsd += [double]$taskUsd[[string]$t.id] } }

# ---- ETA from the status model ----
# Owner-facing times are local machine time with the zone (owner ruling 2026-10-18, kit item IN-20261019012533-2cc1);
# a stamp that does not parse is shown as written.
function Get-LocalAt([string] $s) { try { Format-LocalStamp (ConvertTo-UtcTime $s) } catch { $s } }
$model = $null
try { $model = (& "$PSScriptRoot\Get-StreamStatus.ps1" -Repo $Repo -Json) -join "`n" | ConvertFrom-Json -AsHashtable -DateKind String } catch { }
$gm = if ($model) { @($model['groups'] | Where-Object { $_ -and $_['id'] -eq $focus }) | Select-Object -First 1 } else { $null }
$eta = '-'
if ($gm -and $gm['forecast'] -is [Collections.IDictionary]) {
    $f = $gm['forecast']
    $eta = if ($f['predictedAt']) { "$(Get-LocalAt ([string]$f['predictedAt'])) (rate $($f['ratePerHour']) min/h, chain floor $($f['floorMinutes']) min)" } else { "no forecast yet (chain floor $($f['floorMinutes']) min)" }
}

# ---- order: open rows in claim order, then landed rows by integration time ----
$chain = Get-ChainMinutes $doc
$erank = Get-EffectiveGroupRank $doc (Get-PriorityRankMap $doc $P)
$boardOrder = @{}; $o = 0; foreach ($x in $doc.tasks) { $boardOrder[[string]$x.id] = ++$o }
function Get-LastAt($t, [string] $To) { $h = @($t.history | Where-Object { $_ -and $_.to -eq $To -and $_.at } | Select-Object -Last 1); if ($h.Count) { [string]$h[0].at } else { '' } }
function Get-LastBy($t, [string] $To) { $h = @($t.history | Where-Object { $_ -and $_.to -eq $To } | Select-Object -Last 1); if ($h.Count) { [string]$h[0].by } else { '' } }
$open = @($rows | Where-Object { $_.state -notin @('integrated', 'done') } | Sort-Object `
    @{ e = { [int]($_.Contains('origin') -and $_['origin'] -eq 'integration') }; Descending = $true },
    @{ e = { $erank[[string]$_.id].rank }; Descending = $false },
    @{ e = { [int](Test-ReadyWhenTicketed $doc $_) }; Descending = $true },
    @{ e = { $chain[[string]$_.id] }; Descending = $true },
    @{ e = { $boardOrder[[string]$_.id] }; Descending = $false })
$landed = @($rows | Where-Object { $_.state -in @('integrated', 'done') -and -not (Test-Retired $_) } | Sort-Object { Get-LastAt $_ 'integrated' })

# ---- Tier 2 test state ----
$lastRun = @(Get-SuiteRunRecords $P $focus '2' | Where-Object { $_['status'] -eq 'done' }) | Select-Object -Last 1
$attr = if ($lastRun) { Read-JsonFile (Join-Path (Get-SuiteRunsDir $P) "$($lastRun['id']).attribution.json") } else { $null }
$failOwner = @{}; if ($attr) { foreach ($f in @($attr['failures'])) { if ($f -and $f['ownerRow']) { $failOwner[[string]$f['ownerRow']] = [string]$(if ($f['fixTask']) { "fix $($f['fixTask'])" } else { $f['disposition'] }) } } }

# [0] on an empty array throws under Set-StrictMode, so the latest note is read through a guard.
function Get-LastNote($t) { $h = @($t.history | Where-Object { $_ }); if ($h.Count -and $h[-1].Contains('note')) { [string]$h[-1].note } else { '' } }
function Get-BlockCause($t) {
    $n = (Get-LastNote $t)
    switch -Regex ($n) { 'write ?set|WRITESET|OUTSIDE' { 'write set'; break } 'REQ|requirement|\bAC\b|why' { 'requirement'; break } 'skeptic' { 'skeptic'; break } 'gate' { 'gate'; break } default { 'other' } }
}
function Stage([string] $state, [string] $by, $usd) {
    $u = if ($null -ne $usd) { " &middot; $(Money ([double]$usd))" } else { '' }
    "<td class=`"stage`"><b>$(Enc $state)</b><span>$(Enc $by)$u</span></td>"
}
$wsBlocked = @{}
$tb = [Text.StringBuilder]::new()
[void]$tb.Append('<div class="scroll"><table><tr><th>#</th><th>id</th><th>group</th><th>title</th><th>depends on</th><th>Author</th><th>Build</th><th>Integrate</th><th>Test</th><th>est min</th><th>actual min</th><th>$</th></tr>')
$i = 0
foreach ($t in @($open) + @($landed)) {
    $i++; $id = [string]$t.id
    $tr = $taskRole[$id]; $rc = { param($r) if ($tr -is [Collections.IDictionary] -and $tr.Contains($r)) { $tr[$r] } else { $null } }
    $last = (Get-LastNote $t)
    $cls = @()
    if (($last -match '(^|-- )STALE: ')) { $cls += 'stale' }
    $cause = ''
    if ($t.state -eq 'blocked') { $cls += 'blocked'; $cause = Get-BlockCause $t; if ($cause -eq 'write set') { $wsBlocked[[string]$t.group] = 1 + [int]$wsBlocked[[string]$t.group] } }
    if ($t.kind -eq 'gate' -and $t.state -ne 'done') { $cls += 'gated' }
    $claim = $t.claim
    $aState = switch ($t.state) { 'planned' { if ($claim -and $claim.role -eq 'author') { 'authoring' } elseif (($last -match '(^|-- )STALE: ')) { 'stale' } else { 'planned' } } 'blocked' { "blocked: $cause" } default { 'ticketed' } }
    $aBy = if ($claim -and $claim.role -eq 'author') { [string]$claim.session } else { Get-LastBy $t 'ticketed' }
    $bState = switch ($t.state) { 'building' { 'building' } { $_ -in @('built', 'integrated', 'done') } { 'built' } default { '-' } }
    $bBy = if ($t.state -eq 'building' -and $claim) { [string]$claim.session } else { Get-LastBy $t 'built' }
    $iState = if ($t.state -in @('integrated', 'done')) { $t.state } else { '-' }
    $iBy = Get-LastBy $t 'integrated'
    $test = if ($failOwner.ContainsKey($id)) { "fail: $($failOwner[$id])" }
            elseif ($lastRun -and $t.state -in @('integrated', 'done') -and (Get-LastAt $t 'integrated') -and (ConvertTo-UtcTime (Get-LastAt $t 'integrated')) -lt (ConvertTo-UtcTime $lastRun['startedAt'])) { "pass $($lastRun['id'])" } else { '-' }
    $bs = Get-LastAt $t 'building'; $bd = Get-LastAt $t 'built'
    $actual = if ($bs -and $bd) { [int]((ConvertTo-UtcTime $bd) - (ConvertTo-UtcTime $bs)).TotalMinutes } else { '' }
    $usd = if ($taskUsd.Contains($id)) { Money ([double]$taskUsd[$id]) } else { '' }
    [void]$tb.Append("<tr class=`"$($cls -join ' ')`"><td class=`"num`">$i</td><td class=`"id`">$(Enc $id)</td><td>$(Enc ([string]$t.group))</td><td class=`"note`">$(Enc ([string]$t.title))</td><td class=`"id`">$(Enc ((@($t.dependsOn) | Where-Object { $_ }) -join ', '))</td>")
    [void]$tb.Append((Stage $aState $aBy (& $rc 'author'))); [void]$tb.Append((Stage $bState $bBy (& $rc 'build'))); [void]$tb.Append((Stage $iState $iBy (& $rc 'integrate')))
    [void]$tb.Append("<td class=`"stage`">$(Enc $test)</td><td class=`"num`">$($t.estMinutes)</td><td class=`"num`">$actual</td><td class=`"num`">$usd</td></tr>")
}
if (-not $i) { [void]$tb.Append('<tr><td colspan="12" class="empty">the focus set is empty</td></tr>') }
[void]$tb.Append('</table></div>')

# ---- page ----
$at = Format-LocalStamp
[void]$b.Append("<header><h1>Speedy priority &middot; focus $(Enc $focus)</h1><div class=`"meta`">$(Enc $at) &middot; $($rows.Count) rows in the focus set</div></header>")
[void]$b.Append('<section><div class="ms">')
foreach ($k in 'M1', 'M2', 'M3') {
    $label = @{ M1 = 'Authored'; M2 = 'Claimable'; M3 = 'Integrator-ready' }[$k]
    $when = if ($act -and $act['milestones'] -is [Collections.IDictionary] -and $act['milestones'][$k]) { " &middot; $(Enc (Get-LocalAt ([string]$act['milestones'][$k])))" } else { '' }
    $why = if (-not $ms[$k] -and $ms.detail[$k]) { " &middot; $(Enc $ms.detail[$k])" } else { '' }
    [void]$b.Append("<span class=`"chip$(if ($ms[$k]) { ' on' })`">$k $label$when$why</span>")
}
if (-not $act) { [void]$b.Append('<span class="chip">not activated: Activate-Group.ps1</span>') }
[void]$b.Append("</div><div class=`"tiles`"><div class=`"tile`"><b>$(Money $focusUsd)</b><span>focus spend so far</span></div><div class=`"tile`"><b>$(@($open).Count)</b><span>open rows</span></div><div class=`"tile`"><b>$(@($landed).Count)</b><span>landed</span></div></div><p class=`"muted`">ETA $(Enc $eta)</p></section>")
# owner queue
$q = if (Test-Path -LiteralPath $P.Questions) { @([IO.File]::ReadAllLines($P.Questions)) } else { @() }
$ids = @($rows | ForEach-Object { [string]$_.id })
# A line belongs to the focus group when it names the group or one of its rows as a whole word.
$pat = '\b(' + ((@($focus) + $ids | ForEach-Object { [regex]::Escape($_) }) -join '|') + ')\b'
$mine = @($q | Where-Object { $_ -match '^- ' -and $_ -notmatch 'RESOLVED' -and $_ -match $pat })
$gates = @($rows | Where-Object { $_.kind -eq 'gate' -and $_.state -ne 'done' })
[void]$b.Append('<section><h2>Owner queue</h2>')
if ($mine.Count -or $gates.Count) {
    [void]$b.Append('<ul class="q">')
    foreach ($g in $gates) { [void]$b.Append("<li class=`"warn`">gate $(Enc ([string]$g.id)) ($(Enc ([string]$g.state))): $(Enc ([string]$g.title))</li>") }
    foreach ($l in @($mine | Select-Object -Last 15)) { [void]$b.Append("<li>$(Enc $l.Substring(2))</li>") }
    [void]$b.Append('</ul>')
} else { [void]$b.Append('<p class="empty">nothing waits on the owner for this group</p>') }
[void]$b.Append('</section>')
if ($wsBlocked.Count) {
    [void]$b.Append('<section>')
    foreach ($g in @($wsBlocked.Keys | Sort-Object)) { [void]$b.Append("<div class=`"flag`">blocked: write set &middot; $(Enc $g) $($wsBlocked[$g]) row(s): route to the planner (Revise-Task.ps1)</div>") }
    [void]$b.Append('</section>')
}
[void]$b.Append("<section><h2>Matrix</h2><p class=`"muted`">open rows in claim order, then landed rows by integration time &middot; <span class=`"chip`">stale</span> amber &middot; blocked red &middot; gated id in accent</p>")
[void]$b.Append($tb.ToString())
[void]$b.Append('</section>')
# footer: the next group's counts only
$gi = [array]::IndexOf(@($doc.groups | ForEach-Object { [string]$_.id }), $focus)
$next = if ($gi -ge 0 -and $gi + 1 -lt @($doc.groups).Count) { @($doc.groups)[$gi + 1] } else { $null }
if ($next) {
    $nc = [ordered]@{}; foreach ($t in @($doc.tasks | Where-Object { [string]$_.group -eq [string]$next.id -and -not $set.Contains([string]$_.id) })) { $nc[[string]$t.state] = 1 + [int]$nc[[string]$t.state] }
    [void]$b.Append("<section><h2>Next: $(Enc ([string]$next.id))</h2><p class=`"mono muted`">$(Enc ((@($nc.Keys | ForEach-Object { "$_ $($nc[$_])" })) -join ' &middot; '))</p></section>")
}
[void]$b.Append('</div></body></html>')
Write-AtomicText $Out $b.ToString()
if ($mirror) {
    try {
        $lib = Join-Path $PSScriptRoot '..\..\..\lib\MachineConfig.psm1'
        if (Test-Path -LiteralPath $lib) {
            Import-Module $lib -Force
            $pageDir = Get-AIPath StatusPageDir -Optional
            if ($pageDir) { Copy-Item -LiteralPath $Out (Join-Path $pageDir 'priority.html') -Force }
        }
    } catch { "MIRROR-FAILED $($_.Exception.Message)" }
    $su = Join-Path $P.Root 'status-url.txt'; $pu = Join-Path $P.Root 'priority-url.txt'
    if ((Test-Path -LiteralPath $su) -and -not (Test-Path -LiteralPath $pu)) {
        $u = ([IO.File]::ReadAllText($su)).Trim()
        if ($u -match 'status\.html$') { Write-AtomicText $pu ($u -replace 'status\.html$', 'priority.html') }
    }
}
"PRIORITY-PAGE $Out focus $focus rows $($rows.Count) M1 $($ms.M1) M2 $($ms.M2) M3 $($ms.M3)"
exit 0
