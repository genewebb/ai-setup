# Builds the token-cost ledger from the Claude transcripts of the stream account (2026-10-05 priority-focus-design 3.5).
#   Get-StreamCost.ps1 -Repo <repo> [-ProjectsRoot <dir>] [-Json]
# Reads <ProjectsRoot>\<project>\*.jsonl and <ProjectsRoot>\<project>\*\subagents\*.jsonl from the byte cursor in
# .streams\cost\cursor.json (one entry per full path), prices each deduplicated assistant message (lib\Cost.ps1) with
# .streams\cost\prices.json (copied from cost-prices.json beside this script on first run), attributes it, appends to
# .streams\cost\ledger.jsonl and rewrites .streams\cost\summary.json. The project folder is the repo path with EACH
# non-alphanumeric character as '-' (D:\devops\repos\speedmerchants -> D--devops-repos-speedmerchants). -ProjectsRoot
# defaults to CLAUDE_CONFIG_DIR\projects (the stream account's own folder), else ~\.claude\projects; a missing project
# folder prints NO-PROJECT <path> instead of a silent zero.
# Attribution:
#   Claude sessionId -> stream session: a runner result (.streams\logs\runner\*\<stamp>-<session>.json, session_id; a
#   headless -p result carries session_id only, so the stream session comes from the file name and the role from its
#   prefix) or a session file (.streams\sessions\<sessionId>.json, written by the owner's tab launcher for long /loop
#   sessions), else the session's own transcript, read once (lib\Cost.ps1 Find-TranscriptSession: its '/stream-<role>'
#   command and the '-Session <id>' it passed most; the find is kept as a session file with source 'transcript'). Rows
#   already in the ledger as unattributed are re-attributed in place when their session resolves (REATTRIBUTED <n>);
#   stream session -> task: the row whose history that session wrote, while the message falls inside that session's
#   span on the row (its first entry minus 30 min to its last entry plus 10 min); the latest such entry at or before
#   the message wins, else the first after it. Outside every span the task is '-': a long session's spend after it
#   left a row is not charged to that row. -> group: the task's group.
# A message no mapping covers is kept with role 'unattributed' and streamSession '-', never dropped: the page shows the
# share. A subagent row (agentId set) carries its parent session's attribution (its lines carry the parent sessionId).
# The newest message of a file is held until a later message starts or the file has been quiet for
# STREAM_COST_QUIET_MINUTES (10): its usage line repeats and grows while it streams, and the last line wins.
# One run at a time: .streams\cost\cost.lock; a second run prints COST-BUSY and exits 4. The cursor records the
# ledger's length, and a ledger tail past it (a crash between the append and the cursor write) is cut back first, so
# no message is counted twice. A file that cannot be read prints SKIP <file> <reason> and the rest are still read.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string] $ProjectsRoot = '',
    [switch] $Json
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Cost.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$costDir = Join-Path $P.Root 'cost'
New-Item -ItemType Directory -Path $costDir -Force | Out-Null
if (-not $ProjectsRoot) {
    $cfg = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
    $ProjectsRoot = Join-Path $cfg 'projects'
}
try { $lock = [IO.File]::Open((Join-Path $costDir 'cost.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
catch [IO.IOException] { 'COST-BUSY another Get-StreamCost run holds .streams\cost\cost.lock'; exit 4 }
$code = 0
try {
$pricesPath = Join-Path $costDir 'prices.json'
if (-not (Test-Path $pricesPath)) { Copy-Item (Join-Path $PSScriptRoot 'cost-prices.json') $pricesPath }
$prices = Read-Prices $pricesPath
$project = Join-Path $ProjectsRoot ($Repo.TrimEnd('\') -replace '[^A-Za-z0-9]', '-')
$cursorPath = Join-Path $costDir 'cursor.json'
$cursor = if (Test-Path $cursorPath) { Get-Content -Raw $cursorPath | ConvertFrom-Json -AsHashtable } else { @{} }
if ($cursor['files'] -isnot [Collections.IDictionary]) { $cursor['files'] = @{} }
$ledgerPath = Join-Path $costDir 'ledger.jsonl'
# Cut back a ledger tail the cursor never recorded (crash between the append and the cursor write).
if ($null -ne $cursor['ledgerBytes'] -and (Test-Path $ledgerPath)) {
    $want = [long]$cursor['ledgerBytes']
    $lf = [IO.File]::Open($ledgerPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read)
    try { if ($lf.Length -gt $want) { $lf.SetLength($want) } } finally { $lf.Dispose() }
}
$utc = { param([string] $s) [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }
$quiet = 10.0
if ($env:STREAM_COST_QUIET_MINUTES) { $quiet = [double]$env:STREAM_COST_QUIET_MINUTES }

function Get-RoleFromSession([string] $Session) {
    $pre = ($Session -split '-')[0].ToLowerInvariant()
    if ($script:SessionRoleAlias.ContainsKey($pre)) { $pre = $script:SessionRoleAlias[$pre] }
    if ($pre -in @('author', 'build', 'integrate', 'plan', 'status', 'kit', 'coordinator')) { return $pre }
    'unknown'
}

# ---- maps ----
$doc = Read-Tasks $P
$sessionOf = @{}    # claude sessionId -> @{ streamSession; role; outcome }
foreach ($f in @(Get-ChildItem (Join-Path $P.Root 'logs\runner') -Recurse -File -Filter '*.json' -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'state.json' -and $_.Name -notlike '*.waiting.json' })) {
    try { $o = Get-Content -Raw $f.FullName | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($o -isnot [Collections.IDictionary] -or -not $o['session_id']) { continue }
    # Start-StreamRunner names a result <stamp>-<session>.json; the session is everything after the first '-'.
    $base = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    $fromName = if ($base.Contains('-')) { $base.Substring($base.IndexOf('-') + 1) } else { '' }
    $ss = if ($o['session']) { [string]$o['session'] } else { $fromName }
    $role = if ($o['role']) { [string]$o['role'] } elseif ($ss) { Get-RoleFromSession $ss } else { '' }
    if ($script:SessionRoleAlias.ContainsKey($role)) { $role = $script:SessionRoleAlias[$role] }
    $sessionOf[[string]$o['session_id']] = @{ streamSession = $ss; role = $role; outcome = (Get-UnitOutcome $o) }
}
foreach ($f in @(Get-ChildItem (Join-Path $P.Root 'sessions') -File -Filter '*.json' -ErrorAction SilentlyContinue)) {
    try { $o = Get-Content -Raw $f.FullName | ConvertFrom-Json -AsHashtable } catch { continue }
    if ($o -isnot [Collections.IDictionary]) { continue }
    $sid = [IO.Path]::GetFileNameWithoutExtension($f.Name)
    if (-not $sessionOf.ContainsKey($sid)) { $sessionOf[$sid] = @{ streamSession = [string]$o['streamSession']; role = [string]$o['role']; outcome = '' } }
}
# A Claude session neither map covers is looked up once in its own transcript (lib\Cost.ps1 Find-TranscriptSession):
# a long /loop session that predates .streams\sessions. A find is kept as a session file (source 'transcript'); a miss
# is kept in the cursor (noSession), so no transcript is scanned twice.
if ($cursor['noSession'] -isnot [Collections.IDictionary]) { $cursor['noSession'] = @{} }
function Get-SessionMap([string] $Sid) {
    if (-not $Sid) { return $null }
    if ($sessionOf.ContainsKey($Sid)) { return $sessionOf[$Sid] }
    if ($cursor['noSession'].Contains($Sid)) { return $null }
    $found = Find-TranscriptSession (Join-Path $project "$Sid.jsonl") $Sid
    if (-not $found) { $cursor['noSession'][$Sid] = Get-Now; return $null }
    $sdir = Join-Path $P.Root 'sessions'; New-Item -ItemType Directory -Path $sdir -Force | Out-Null
    Write-AtomicText (Join-Path $sdir "$Sid.json") ([ordered]@{ streamSession = $found.streamSession; role = $found.role; source = 'transcript'; at = Get-Now } | ConvertTo-Json)
    $sessionOf[$Sid] = @{ streamSession = $found.streamSession; role = $found.role; outcome = '' }
    $sessionOf[$Sid]
}
$spans = @{}        # stream session -> list of @{ task; group; first; last; ats = sorted [datetime[]] }
foreach ($t in @($doc['tasks'])) {
    $mine = @{}
    foreach ($h in @($t['history'])) {
        if ($h -isnot [Collections.IDictionary]) { continue }
        $by = [string]$h['by']; if (-not $by -or -not $h['at']) { continue }
        try { $hat = & $utc ([string]$h['at']) } catch { continue }
        if (-not $mine.ContainsKey($by)) { $mine[$by] = [Collections.Generic.List[datetime]]::new() }
        $mine[$by].Add($hat)
    }
    foreach ($by in $mine.Keys) {
        $ats = @($mine[$by] | Sort-Object)
        if (-not $spans.ContainsKey($by)) { $spans[$by] = [Collections.Generic.List[object]]::new() }
        $spans[$by].Add(@{ task = [string]$t['id']; group = [string]$t['group']; first = $ats[0]; last = $ats[-1]; ats = $ats })
    }
}
function Get-TaskAt([string] $StreamSession, [datetime] $At) {
    $sp = $spans[$StreamSession]; if (-not $sp) { return $null }
    $best = $null; $bestAt = [datetime]::MinValue; $next = $null; $nextAt = [datetime]::MaxValue
    foreach ($s in $sp) {
        if ($At -lt $s.first.AddMinutes(-30) -or $At -gt $s.last.AddMinutes(10)) { continue }
        foreach ($a in $s.ats) {
            if ($a -le $At) { if ($a -gt $bestAt) { $best = $s; $bestAt = $a } }
            elseif ($a -lt $nextAt) { $next = $s; $nextAt = $a }
        }
    }
    if ($best) { $best } else { $next }
}

# ---- read ----
# Subagent folders are listed one by one: Get-ChildItem '<project>\*\subagents' -File returns NOTHING (the wildcard
# matches the folders themselves, and -File then drops them), measured 2026-10-05.
$files = @()
$skipped = [Collections.Generic.List[string]]::new()
if (-not (Test-Path -LiteralPath $project)) { $skipped.Add("NO-PROJECT $project") }
else {
    $files = @(Get-ChildItem -LiteralPath $project -File -Filter '*.jsonl') +
        @(Get-ChildItem -LiteralPath $project -Directory | ForEach-Object { Join-Path $_.FullName 'subagents' } | Where-Object { Test-Path -LiteralPath $_ } |
            ForEach-Object { Get-ChildItem -LiteralPath $_ -File -Filter '*.jsonl' })
}
$added = 0; $addedUsd = 0.0
$sb = [Text.StringBuilder]::new()
$now = [datetime]::UtcNow
foreach ($f in $files) {
    $key = $f.FullName
    $c = $cursor['files'][$key]
    $from = if ($c -is [Collections.IDictionary]) { [long]$c['offset'] } else { 0 }
    $skip = if ($c -is [Collections.IDictionary]) { [string]$c['lastMessageId'] } else { '' }
    if ($from -ge $f.Length) { continue }
    $got = [Collections.Generic.List[object]]::new()
    try {
        # Chunked: read until a read makes no progress, then flush the held newest message once the file is quiet.
        while ($true) {
            $r = Read-TranscriptUsage $key $from $skip
            foreach ($row in $r.rows) { $got.Add($row) }
            if ($r.offset -le $from) { break }
            $from = $r.offset; $skip = $r.lastMessageId
        }
        if (($now - $f.LastWriteTimeUtc).TotalMinutes -ge $quiet) {
            $r = Read-TranscriptUsage $key $from $skip -Flush
            foreach ($row in $r.rows) { $got.Add($row) }
            $from = $r.offset; $skip = $r.lastMessageId
        }
    } catch {
        $skipped.Add("SKIP $key $($_.Exception.Message)")
        continue
    }
    foreach ($row in $got) {
        $map = Get-SessionMap $row.sessionId
        $streamSession = if ($map -and $map.streamSession) { $map.streamSession } else { '-' }
        $role = if ($streamSession -eq '-') { 'unattributed' } elseif ($map.role) { $map.role } else { Get-RoleFromSession $streamSession }
        $at = try { & $utc $row.at } catch { [datetime]::MinValue }
        $ev = if ($streamSession -ne '-') { Get-TaskAt $streamSession $at } else { $null }
        $usd = ConvertTo-Usd $prices $row.model @{ in = $row.in; out = $row.out; cacheRead = $row.cacheRead; cacheWrite5m = $row.cacheWrite5m; cacheWrite1h = $row.cacheWrite1h }
        $line = [ordered]@{ at = $row.at; sessionId = $row.sessionId; agentId = $row.agentId; messageId = $row.messageId; streamSession = $streamSession; role = $role
            task = $(if ($ev) { $ev.task } else { '-' }); group = $(if ($ev) { $ev.group } else { '-' }); model = $row.model
            in = $row.in; out = $row.out; cacheRead = $row.cacheRead; cacheWrite5m = $row.cacheWrite5m; cacheWrite1h = $row.cacheWrite1h
            usd = $usd; unitOutcome = $(if ($map) { $map.outcome } else { '' }) }
        [void]$sb.Append(($line | ConvertTo-Json -Compress)).Append("`n")
        $added++; if ($null -ne $usd) { $addedUsd += $usd }
    }
    $cursor['files'][$key] = @{ offset = $from; lastMessageId = $skip }
}
# Ledger first, then cursor (with the ledger's new length): a crash between the two leaves a tail the next run cuts back.
if ($sb.Length) { [IO.File]::AppendAllText($ledgerPath, $sb.ToString()) }
$cursor['ledgerBytes'] = if (Test-Path $ledgerPath) { (Get-Item $ledgerPath).Length } else { 0 }
Write-AtomicText $cursorPath ($cursor | ConvertTo-Json -Depth 5)

# ---- re-attribute and re-price ----
# A row written unattributed (by a version that had no transcript lookup, or before its session file existed) is
# attributed in place once its session resolves. A row written UNPRICED (usd null: its model had no row in prices.json
# when it was read; on 2026-10-06 claude-opus-5 and claude-sonnet-5 were missing and 1,300 author rows summed to $0)
# is priced in place once prices.json names its model; the token counts are on the row, so no transcript is re-read.
# The ledger is rewritten only when a row changed, then the cursor records its new length.
if (Test-Path $ledgerPath) {
    $rb = [Text.StringBuilder]::new(); $changed = 0; $repriced = 0
    foreach ($l in [IO.File]::ReadLines($ledgerPath)) {
        if (-not $l) { continue }
        $unattributed = $l.Contains('"streamSession":"-"'); $unpriced = $l.Contains('"usd":null')
        if ($unattributed -or $unpriced) {
            $o = $null; try { $o = $l | ConvertFrom-Json -AsHashtable -DateKind String } catch { }
            $rowChanged = $false
            if ($o -and $unattributed) {
                $map = Get-SessionMap ([string]$o['sessionId'])
                if ($map -and $map.streamSession) {
                    $o['streamSession'] = $map.streamSession
                    $o['role'] = if ($map.role) { $map.role } else { Get-RoleFromSession $map.streamSession }
                    $at = try { & $utc ([string]$o['at']) } catch { [datetime]::MinValue }
                    $ev = Get-TaskAt $map.streamSession $at
                    $o['task'] = if ($ev) { $ev.task } else { '-' }; $o['group'] = if ($ev) { $ev.group } else { '-' }
                    $rowChanged = $true
                }
            }
            if ($o -and $unpriced) {
                $usd = ConvertTo-Usd $prices ([string]$o['model']) @{ in = $o['in']; out = $o['out']; cacheRead = $o['cacheRead']; cacheWrite5m = $o['cacheWrite5m']; cacheWrite1h = $o['cacheWrite1h'] }
                if ($null -ne $usd) { $o['usd'] = $usd; $repriced++; $rowChanged = $true }
            }
            if ($rowChanged) { $l = $o | ConvertTo-Json -Compress; $changed++ }
        }
        [void]$rb.Append($l).Append("`n")
    }
    if ($changed) {
        Write-AtomicText $ledgerPath $rb.ToString()
        $cursor['ledgerBytes'] = (Get-Item $ledgerPath).Length
    }
    # The lookups above may have added noSession entries even when no row changed.
    Write-AtomicText $cursorPath ($cursor | ConvertTo-Json -Depth 5)
    if ($changed - $repriced) { $skipped.Add("REATTRIBUTED $($changed - $repriced) rows") }
    if ($repriced) { $skipped.Add("REPRICED $repriced rows") }
}

# ---- summary over the whole ledger ----
$sum = [ordered]@{ at = Get-Now; pricesVersion = [string]$prices['version']; added = $added; addedUsd = [math]::Round($addedUsd, 4); total = 0.0; unattributed = 0.0; unpriced = 0
    byRole = [ordered]@{}; byDay = [ordered]@{}; byGroup = [ordered]@{}; byTask = [ordered]@{}; byOutcome = [ordered]@{}; byModel = [ordered]@{}; rows = 0; skipped = @($skipped)
    byTaskRole = [ordered]@{}; byOutcome24h = [ordered]@{}; bySessionHour = [ordered]@{} }
$acc = { param($d, $k, $v) if (-not $d.Contains($k)) { $d[$k] = 0.0 }; $d[$k] = [math]::Round($d[$k] + $v, 4) }
if (Test-Path $ledgerPath) {
    foreach ($l in [IO.File]::ReadLines($ledgerPath)) {
        if (-not $l) { continue }
        try { $o = $l | ConvertFrom-Json -AsHashtable -DateKind String } catch { continue }
        $sum.rows++
        if ($null -eq $o['usd']) { $sum.unpriced++; continue }
        $v = [double]$o['usd']
        $sum.total = [math]::Round($sum.total + $v, 4)
        if ($o['role'] -eq 'unattributed') { $sum.unattributed = [math]::Round($sum.unattributed + $v, 4) }
        $day = [string]$o['at']; if ($day.Length -ge 10) { $day = $day.Substring(0, 10) }
        & $acc $sum.byRole ([string]$o['role']) $v
        & $acc $sum.byDay $day $v
        & $acc $sum.byGroup ([string]$o['group']) $v
        & $acc $sum.byTask ([string]$o['task']) $v
        & $acc $sum.byModel ([string]$o['model']) $v
        if ($o['unitOutcome']) { & $acc $sum.byOutcome ([string]$o['unitOutcome']) $v }
        # Per task and role (Priority.html stage costs); runner outcomes in the last 24 h (the idle-launch flag);
        # spend per long-session hour (the no-work flag: Build-CostPage.ps1 compares it with the hours the session
        # wrote anything).
        $tk = [string]$o['task']
        if ($tk -and $tk -ne '-') { if (-not $sum.byTaskRole.Contains($tk)) { $sum.byTaskRole[$tk] = [ordered]@{} }; & $acc $sum.byTaskRole[$tk] ([string]$o['role']) $v }
        $rowAt = $null; try { $rowAt = & $utc ([string]$o['at']) } catch { }
        if ($o['unitOutcome'] -and $rowAt -and ($now - $rowAt).TotalHours -le 24) { & $acc $sum.byOutcome24h ([string]$o['unitOutcome']) $v }
        $ssn = [string]$o['streamSession']
        # The last 24 h only, so old hours never flag for ever; never the status role, whose watchdog ticks write
        # nothing by design (final review I8).
        if ($rowAt -and ($now - $rowAt).TotalHours -le 24 -and $ssn -and $ssn -ne '-' -and [string]$o['role'] -in @('plan', 'integrate', 'kit', 'coordinator') -and -not $o['unitOutcome']) {
            if (-not $sum.bySessionHour.Contains($ssn)) { $sum.bySessionHour[$ssn] = [ordered]@{} }
            & $acc $sum.bySessionHour[$ssn] ($rowAt.ToString('yyyy-MM-ddTHH')) $v
        }
    }
}
$sum.unattributedPct = if ($sum.total) { [math]::Round(100.0 * $sum.unattributed / $sum.total, 1) } else { 0 }
Write-AtomicText (Join-Path $costDir 'summary.json') ($sum | ConvertTo-Json -Depth 6)
if ($Json) { $sum | ConvertTo-Json -Depth 6 }
else {
    $skipped
    "COST +$added rows +`$$([math]::Round($addedUsd, 2)) total `$$([math]::Round($sum.total, 2)) unattributed $($sum.unattributedPct)% ($($files.Count) files)"
}
} finally { $lock.Dispose() }
exit $code
