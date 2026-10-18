# Read-only test-blocker review of the open focus-set rows (kit item IN-20261018051443-6c23, part 3 of owner request
# IN-20261018044413-259b): a row whose grader or test clause cannot pass for a reason outside the row waits for ever,
# whatever its dependsOn says. Each open, unclaimed ticketed / planned / blocked row is flagged when:
#   main-red    its notes say a test it needs is red on main already (red only on main, pre-existing red): route plan.
#   live-stack  its ticket or grader needs the live stack (docker, compose, dev cert, Tests.E2E, Playwright, *Live*):
#               route owner (the stack or certificate is an owner prerequisite).
#   guard-test  its ticket or grader cites a test file that another open row's write set owns and its own does not,
#               and no dependsOn path puts the owner first: the pair is 'unordered' (no path either way) or 'owner
#               after waiter'. A waiter already ordered after the owner is not flagged. Route plan (order the rows, or
#               move the file). Kit item IN-20261018063247-abde: 40 of 63 first-run pairs were already ordered.
#   stale-pin   an unresolved STALE marker (a note starting 'STALE:' or 'STALE-TICKET', or Revise-Task's
#               'plan revise: ... -- STALE:') with no later re-ticket or 'refresh' note, or it was spilled at a commit
#               after which a write-set file changed on main: route author (refresh the ticket's pins). The bare word
#               is not a marker: an author refresh line, a 'stale order edge' revise and a ticket naming a 'stale
#               alert' feature were all flagged by the first run (same kit item).
# It also lists every unmet dependsOn edge on a row the waiter shares no write-set file with ('logical: no shared
# file' in Find-ArtificialBlockers.ps1) as an EDGE line for plan review. Nothing is changed here.
# Output: 'FLAG <signal>\t<id> -> <route> | <detail>' lines, 'EDGE no-shared-file\t<id> -> <dep> (<state>) -> plan'
# lines, then 'SUMMARY ...'; -Json the model; -Session logs the summary to decisions.md.
param([Parameter(Mandatory)] [string] $Repo, [string] $Session, [switch] $Json)
$ErrorActionPreference = 'Stop'
function Get-DepWhy($x, [string] $d) { $w = if ($x -is [Collections.IDictionary]) { if ($x.Contains('dependsWhy')) { $x['dependsWhy'] } } elseif ($x.PSObject.Properties['dependsWhy']) { $x.dependsWhy }; if (-not $w) { return '' }; if ($w -is [Collections.IDictionary]) { if ($w.Contains($d)) { return [string]$w[$d] }; return '' }; $p = $w.PSObject.Properties[$d]; if ($p) { [string]$p.Value } else { '' } }
. (Join-Path $PSScriptRoot 'lib\Streams.ps1')
$P = Get-StreamPaths $Repo
$doc = Read-Tasks $P
$focus = Get-FocusSet $doc $P
$by = @{}; foreach ($t in $doc.tasks) { $by[[string]$t.id] = $t }
$landed = @('built', 'integrated', 'done')
$mainRedRx = '(?i)red only on main|already red on main|red on main (already|before)|pre-?existing (red|fail)|fails on main without'
$liveRx = '(?i)\bdocker\b|compose stack|dev-?certs?|Tests\.E2E|\bplaywright\b|\*Live\*|live stack'
$testRx = 'tests[/\\][\w.\-/\\]+\.(cs|ts|ps1)'
# Rows are ordered hashtables (Read-Tasks); a key a row never had reads as null.
function Get-Field($o, [string] $k) { if ($o -is [Collections.IDictionary]) { if ($o.Contains($k)) { $o[$k] } } elseif ($o -and $o.PSObject.Properties[$k]) { $o.$k } }
function Read-Artifact([string] $rel) {
    if (-not $rel) { return '' }
    $f = Join-Path $Repo $rel
    if (Test-Path -LiteralPath $f) { Get-Content -Raw -LiteralPath $f } else { '' }
}
# Owner of each test path among the open rows' write sets.
$owners = @{}
foreach ($t in $doc.tasks) {
    if ([string]$t.state -in $landed) { continue }
    foreach ($w in @($t.writeSet)) { if ($w) { $owners[($w -replace '\\', '/')] = [string]$t.id } }
}
$staleRx = '^\s*STALE(:|-TICKET)|--\s*STALE:'
$refreshRx = '(?i)^\s*refresh\b'
# True when $from reaches $to through dependsOn (any state).
function Test-DependsPath([string] $from, [string] $to) {
    $seen = @{}; $stack = [Collections.Generic.Stack[string]]::new(); $stack.Push($from)
    while ($stack.Count) {
        $n = $stack.Pop()
        if ($seen.ContainsKey($n)) { continue }
        $seen[$n] = $true
        $t = $by[$n]; if (-not $t) { continue }
        foreach ($d in @($t.dependsOn)) { if (-not $d) { continue }; if ([string]$d -eq $to) { return $true }; $stack.Push([string]$d) }
    }
    $false
}
$changedSince = @{}
function Get-ChangedSince([string] $sha) {
    if (-not $changedSince.ContainsKey($sha)) {
        $out = @(git -C $Repo diff --name-only $sha HEAD 2>$null)
        $changedSince[$sha] = if ($LASTEXITCODE -eq 0) { @($out | ForEach-Object { $_ -replace '\\', '/' }) } else { @() }
    }
    $changedSince[$sha]
}
$flags = @(); $edges = @(); $rowsSeen = 0
foreach ($x in $doc.tasks) {
    $id = [string]$x.id
    if ([string]$x.state -notin @('ticketed', 'planned', 'blocked') -or -not $focus.Contains($id) -or (Test-ClaimLive $x)) { continue }
    $rowsSeen++
    $own = @(@($x.writeSet) | ForEach-Object { $_ -replace '\\', '/' })
    $notes = (@($x.history) | Select-Object -Last 5 | ForEach-Object { [string]$_.note }) -join "`n"
    $hist = @($x.history)
    $text = (@('ticket', 'grader', 'check') | ForEach-Object { Read-Artifact ([string](Get-Field (Get-Field $x 'artifacts') $_)) }) -join "`n"
    if ($notes -match $mainRedRx) { $flags += [pscustomobject]@{ signal = 'main-red'; id = $id; route = 'plan'; detail = "note: $($Matches[0])" } }
    if ($text -match $liveRx) { $flags += [pscustomobject]@{ signal = 'live-stack'; id = $id; route = 'owner'; detail = "cites $($Matches[0])" } }
    $guard = @([regex]::Matches($text, $testRx) | ForEach-Object { $_.Value -replace '\\', '/' } | Select-Object -Unique |
        Where-Object { $own -notcontains $_ -and $owners.ContainsKey($_) -and $owners[$_] -ne $id })
    foreach ($g in $guard) {
        $o = $owners[$g]
        if (Test-DependsPath $id $o) { continue }
        $order = $(if (Test-DependsPath $o $id) { 'owner after waiter' } else { 'unordered' })
        $flags += [pscustomobject]@{ signal = 'guard-test'; id = $id; route = 'plan'; detail = "$g owned by $o; $order" }
    }
    $stale = $null
    $mark = -1; for ($i = $hist.Count - 1; $i -ge 0; $i--) { if ([string]$hist[$i].note -match $staleRx) { $mark = $i; break } }
    if ($mark -ge 0 -and -not @($hist | Select-Object -Skip ($mark + 1) | Where-Object { [string]$_.to -eq 'ticketed' -or [string]$_.note -match $refreshRx }).Count) {
        $stale = "unresolved STALE note at $($hist[$mark].at)"
    }
    elseif (Get-Field $x 'spill') {
        $sha = $(if ($x.spill -is [string]) { $x.spill } else { [string](Get-Field $x.spill 'commit') })
        if ($sha) { $hit = @(Get-ChangedSince $sha | Where-Object { $own -contains $_ }); if ($hit.Count) { $stale = "spilled at $sha; changed since: $($hit -join ', ')" } }
    }
    if ($stale) { $flags += [pscustomobject]@{ signal = 'stale-pin'; id = $id; route = 'author'; detail = $stale } }
    foreach ($d in @($x.dependsOn)) {
        $dt = $by[[string]$d]
        if (-not $d -or -not $dt -or [string]$dt.state -in $landed -or [string]$dt.kind -in @('gate', 'integration')) { continue }
        if ([string]$dt.state -eq 'building' -or (Test-ClaimLive $dt)) { continue }
        if (Get-DepWhy $x $d) { continue }
        if (@(@($dt.writeSet) | Where-Object { @($x.writeSet) -contains $_ }).Count) { continue }
        $edges += [pscustomobject]@{ id = $id; dep = [string]$d; depState = [string]$dt.state }
    }
}
$c = @{}; foreach ($s in 'main-red', 'live-stack', 'guard-test', 'stale-pin') { $c[$s] = @($flags | Where-Object signal -eq $s).Count }
$flagged = @($flags | Select-Object -ExpandProperty id -Unique).Count
$summary = "SUMMARY rows $rowsSeen flagged $flagged (main-red $($c['main-red']), live-stack $($c['live-stack']), guard-test $($c['guard-test']), stale-pin $($c['stale-pin'])) edges-no-shared-file $($edges.Count)"
if ($Session) { Add-Decision $P $Session "Find-TestBlockers: $summary" }
if ($Json) { @{ flags = $flags; edges = $edges; summary = $summary } | ConvertTo-Json -Depth 5; return }
foreach ($f in $flags) { "FLAG $($f.signal)`t$($f.id) -> $($f.route) | $($f.detail)" }
foreach ($e in $edges) { "EDGE no-shared-file`t$($e.id) -> $($e.dep) ($($e.depState)) -> plan" }
$summary
