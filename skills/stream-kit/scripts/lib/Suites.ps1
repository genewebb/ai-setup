# Tiered group testing (2026-10-05 priority-focus-design 3.3). Dot-source after lib\Streams.ps1.
#   Tier 1 Patch  : each integration (Integrate-Patch.ps1, unchanged).
#   Tier 2 Full   : nightly 01:00 (scheduled task) and once when the focus set's last non-fix row integrates
#                   (Start-SuiteRun.ps1 -Reason nightly|complete|manual).
#   Tier 3 Retest : after a fix task integrates, only the failed tests (Invoke-Retest.ps1 -Mode fix).
# Files, all under .streams\suites\ (the folder New-SuiteSnapshot.ps1 already keeps its snapshot records in; runs live
# in runs\ so Get-SuiteSnapshots never reads one as a snapshot):
#   <group>.run.json                  the run definition the integrator writes once per group (legs, commands)
#   runs\<run>.json                   one record per Tier 2 run (reason, startedAt, head, snapshot, status, legs)
#   runs\<run>\                       leg logs and result files (trx, Playwright json)
#   runs\<run>.results.json           per test: { test, suite, outcome, durationMs, file, project, head }
#   runs\<run>.attribution.json       per failed test: owner row and group, and what became of it
#   runs\<retest>.json                one record per Tier 3 retest or flaky re-run (tier 3, base run, tests, status)
#   flaky.json                        flaky candidates and their later failures (2 of the next 5 Tier 2 runs promote)
#   known-failures.<group>.json       failures owned only by a LATER group, turned into fix tasks at its activation

function Get-SuiteRunsDir($P) { $d = Join-Path $P.Suites 'runs'; if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }; $d }
function Read-JsonFile([string] $Path) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    try { Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -AsHashtable -DateKind String -Depth 30 } catch { $null }
}
function Write-JsonFile([string] $Path, $Value) { Write-AtomicText $Path (ConvertTo-Json -InputObject $Value -Depth 30) }
function ConvertTo-UtcTime([string] $s) { [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }

# The groups a run record counts for: its 'group' plus its 'groups' list (kit item IN-20261019130625-ee1d: one Tier 2
# completion run counts for every focus group whose rows were all integrated when it started, Start-SuiteRun.ps1).
function Get-SuiteRunGroups($Rec) {
    $g = @([string]$Rec['group']); if ($Rec.Contains('groups') -and $Rec['groups']) { $g += @($Rec['groups'] | ForEach-Object { [string]$_ }) }
    @($g | Where-Object { $_ } | Select-Object -Unique)
}
# The non-fix build rows a Tier 2 run must find landed before it counts for a group: the rows whose own 'group' field
# is that group PLUS its group set (Get-GroupSet, lib\Activation.ps1). The set alone was empty for G11, every row of
# which an earlier group's dependents pull forward, so no run ever counted for G11 (kit item IN-20261020100610-6c4b).
function Get-GroupBuildRows($doc, [string] $Group) {
    $gs = Get-GroupSet $doc $Group
    @($doc.tasks | Where-Object { ($gs.Contains([string]$_.id) -or [string]$_.group -eq $Group) -and $_.kind -in $script:BuildKinds -and -not ($_.Contains('origin') -and [string]$_['origin'] -eq 'integration') })
}
# Every run record (Tier 2 runs and Tier 3 retests), oldest first by startedAt; with -Group, those that count for it.
function Get-SuiteRunRecords($P, [string] $Group = '', [string] $Tier = '') {
    $d = Get-SuiteRunsDir $P
    @(Get-ChildItem -LiteralPath $d -File -Filter '*.json' | Where-Object { $_.Name -notmatch '\.(results|attribution)\.json$' } |
        ForEach-Object { Read-JsonFile $_.FullName } |
        Where-Object { $_ -is [Collections.IDictionary] -and $_['id'] -and $_['startedAt'] -and (-not $Group -or (Get-SuiteRunGroups $_) -contains $Group) -and (-not $Tier -or [string]$_['tier'] -eq $Tier) } |
        Sort-Object { ConvertTo-UtcTime $_['startedAt'] })
}

# Fills {repo}, {snapshot}, {runDir}, {leg}, {run} in a run-definition command.
function Expand-SuiteCommand([string] $Command, [hashtable] $Vars) {
    $c = $Command
    foreach ($k in $Vars.Keys) { $c = $c.Replace('{' + $k + '}', [string]$Vars[$k]) }
    $c
}

# A dotnet test name as a FullyQualifiedName~ term: the DataRow arguments are cut at '(' (a contains-match on the
# method covers every row), and the filter's special characters are escaped with '\' (dotnet test --filter syntax).
# Never FullyQualifiedName= : an exact match never equals a data-row name (review F10).
function ConvertTo-DotnetFilterTerm([string] $Test) {
    $name = $Test; $i = $name.IndexOf('('); if ($i -ge 0) { $name = $name.Substring(0, $i) }
    $name = $name.Trim()
    $esc = [regex]::Replace($name, '([\\\(\)&|=!~,])', '\$1')
    "FullyQualifiedName~$esc"
}
# A Playwright title as one alternative of an end-anchored --grep: regex-escaped and anchored at the end. The CLI's
# --grep runs on the title path joined with spaces PLUS the test's tags (Playwright 1.59 _grepTitleWithTags: "<path>
# @tag1 @tag2"), so the anchor lets any run of " @tag" follow the title; a bare '$' matched no tagged test at all.
function ConvertTo-PlaywrightGrepTerm([string] $Title) { [regex]::Escape($Title.Trim()).Replace('\ ', ' ') + '( @\S+)*$' }

# When a row last integrated (UTC), or $null.
function Get-TaskIntegratedAt($t) {
    $h = @($t.history | Where-Object { $_ -and $_.Contains('to') -and $_.to -eq 'integrated' -and $_.Contains('at') -and $_.at } | Select-Object -Last 1)
    if ($h.Count) { try { ConvertTo-UtcTime ([string]$h[0].at) } catch { $null } } else { $null }
}

# When a fix row's work reached main for a Tier 3 retest (UTC), or $null: when it integrated, or, for a RETIRED row
# (withdrawn with no patch, e.g. its failure was measured green alone), when it was retired. A retired row never
# integrates, so without this its failure was never retested and the group could not close (kit item
# IN-20261010151453-fc3c, G4.R1F15).
function Get-FixLandedAt($t) {
    if (-not $t) { return $null }
    if ($t.state -in @('integrated', 'done') -and -not (Test-Retired $t)) { return (Get-TaskIntegratedAt $t) }
    if (Test-Retired $t) { try { return (ConvertTo-UtcTime ([string]$t['retired']['at'])) } catch { return $null } }
    $null
}

# The owner's close exemptions for a group: .streams\suites\exempt.<G>.json, a list of { test, fixTask, reason, by, at }
# written by Test-GroupClose.ps1 -Exempt. An exempted failure is out of the close rule, the Tier 3 retest and new
# attributions (disposition 'exempt', no fix task), for every run of the group. Returns test name -> entry.
function Get-SuiteExemptPath($P, [string] $Group) { Join-Path $P.Suites "exempt.$Group.json" }
function Get-SuiteExemptions($P, [string] $Group) {
    $m = @{}
    $f = Get-SuiteExemptPath $P $Group
    if (Test-Path -LiteralPath $f) {
        foreach ($e in @(Get-Content -Raw -LiteralPath $f | ConvertFrom-Json -AsHashtable -DateKind String)) {
            if ($e -is [Collections.IDictionary] -and $e['test']) { $m[[string]$e['test']] = $e }
        }
    }
    $m
}

# The row on the WHOLE board whose write set holds $File: the LATEST-INTEGRATED landed row, because only landed code
# is on main to break a test. An unlanded row owns it only when no landed row holds the file (a test file no landed row
# touches yet). Preferring an open row turned a completion run's own regression into a 'later' known failure whenever a
# later-group row also listed the file.
function Find-OwnerRow($doc, [string] $File) {
    if (-not $File) { return $null }
    $hits = @($doc.tasks | Where-Object { $_.kind -in @('code', 'docs', 'mockup') -and (Test-InWriteSet $File @($_.writeSet)) })
    if (-not $hits.Count) { return $null }
    $landed = @($hits | Where-Object { $_.state -in @('integrated', 'done') })
    if ($landed.Count) { return @($landed | Sort-Object { $at = Get-TaskIntegratedAt $_; if ($at) { $at } else { [datetime]::MinValue } } | Select-Object -Last 1)[0] }
    $hits[0]
}

# RUN LIVENESS. A run record says 'running' from its start until its script writes the end state; a reboot, a killed
# unit's process tree or a throw before that write left it 'running' for good, and every later run then printed
# RUN-BUSY, so the group could never close (final review C2). Each record carries the pid and start time of the process
# that runs it (Set-SuiteRunProcess); a record whose process is gone is dead. A record with no pid (written before this
# rule) is trusted for 6 h, the nightly task's own limit.
function Set-SuiteRunProcess($rec, [int] $ProcessId = $PID) {
    $rec['pid'] = $ProcessId
    $rec['pidStart'] = try { (Get-Process -Id $ProcessId -ErrorAction Stop).StartTime.ToUniversalTime().ToString('o') } catch { '' }
}
# Whether the process the record names (pid + its start time) still runs; a record with no pid has none.
function Test-SuiteRunProcess($rec) {
    if (-not ($rec.Contains('pid') -and $rec['pid'])) { return $false }
    $p = Get-Process -Id ([int]$rec['pid']) -ErrorAction SilentlyContinue
    if (-not $p) { return $false }
    if ($rec.Contains('pidStart') -and $rec['pidStart']) {
        try { return ([math]::Abs(($p.StartTime.ToUniversalTime() - [datetime]::Parse([string]$rec['pidStart'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalSeconds) -lt 2) } catch { return $true }
    }
    $true
}
function Test-SuiteRunAlive($rec) {
    if ([string]$rec['status'] -ne 'running') { return $false }
    if ($rec.Contains('pid') -and $rec['pid']) { return (Test-SuiteRunProcess $rec) }
    try { ((Get-Date).ToUniversalTime() - (ConvertTo-UtcTime $rec['startedAt'])).TotalHours -lt 6 } catch { $true }
}
# A run whose legs ended 'done' still has its flaky screen ahead (Invoke-SuiteLegs.ps1 writes 'screen' = 'pending' with
# the end state and 'done' once Invoke-Retest.ps1 -Mode flaky returns). Attribution read before then files fix rows for
# tests the screen turns flaky: run-G14-4 was attributed by hand at 14:40:53Z, its screen passed 6 at 14:44:48Z (kit
# item IN-20261019153055-2c27). Pending counts only while the run's process lives: a dead one never finishes it.
function Test-SuiteScreenPending($rec) { [string]$rec['screen'] -eq 'pending' -and (Test-SuiteRunProcess $rec) }
# The live 'running' records; every dead one is marked 'abandoned' (with a decisions.md line). Outputs one
# "ABANDONED <id> (<why>)" string per dead record, then the live records: callers split the two by type.
function Resolve-RunningSuiteRuns($P, [string] $Session) {
    $rd = Get-SuiteRunsDir $P
    $live = [Collections.Generic.List[object]]::new()
    foreach ($r in @(Get-SuiteRunRecords $P | Where-Object { $_['status'] -eq 'running' })) {
        if (Test-SuiteRunAlive $r) { $live.Add($r); continue }
        $r['status'] = 'abandoned'; $r['endedAt'] = Get-Now
        $r['abandonedWhy'] = $(if ($r.Contains('pid') -and $r['pid']) { "process $($r['pid']) is gone" } else { 'no process recorded and older than 6 h' })
        Write-JsonFile (Join-Path $rd "$($r['id']).json") $r
        Add-Decision $P $Session "ABANDONED $($r['id']) ($($r['abandonedWhy'])); it no longer blocks a run"
        "ABANDONED $($r['id']) ($($r['abandonedWhy']))"
    }
    @($live)
}
# Hands the integrator lock back when $Session holds it (a nightly-started run; the integrator's own runs keep theirs).
function Exit-IntegratorLock($P, [string] $Session) {
    if (Test-IntegratorLock $P $Session) { Remove-Item -LiteralPath $P.IntLock -Force -ErrorAction SilentlyContinue; return $true }
    $false
}

# FIX ATTEMPTS (Tier 3). A failing Tier 3 retest of a 'fix' failure files the next attempt: a new integration fix row
# on the previous attempt's write set (Add-Tasks.ps1 -Role integrate chains it after a landed row on the same file), and
# the attribution's fixTask moves to it. The test is retested only after its current attempt lands (Invoke-Retest.ps1),
# so three failed retests are three failed attempts - never three retests of a fix that has not landed yet (final review
# I1). The group's strikes count from its unblockedAt (Test-GroupClose.ps1 -Unblock).
function Get-StrikeRetests($P, [string] $Group, [string] $Run, [string] $Test, $GroupRow) {
    $since = if ($GroupRow -and $GroupRow.Contains('unblockedAt') -and $GroupRow['unblockedAt']) { ConvertTo-UtcTime $GroupRow['unblockedAt'] } else { [datetime]::MinValue }
    @(Get-SuiteRunRecords $P $Group '3' | Where-Object { $_['baseRun'] -eq $Run -and $_['status'] -eq 'done' -and @($_['tests']) -contains $Test -and (ConvertTo-UtcTime $_['startedAt']) -gt $since })
}
# Files the next attempt for $Test of $Run; prints "REFIX <test> <new id> (attempt <n>)". Returns the new id or ''.
function Add-FixAttempt($P, [string] $Repo, [string] $Session, [string] $Run, [string] $Test, [string] $ScriptDir) {
    $rd = Get-SuiteRunsDir $P
    $attrPath = Join-Path $rd "$Run.attribution.json"
    $attr = Read-JsonFile $attrPath
    if (-not $attr) { return '' }
    $f = @($attr['failures'] | Where-Object { $_ -and $_['test'] -eq $Test -and $_['disposition'] -eq 'fix' }) | Select-Object -First 1
    if (-not $f) { return '' }
    $doc = Read-Tasks $P
    $prev = @($doc.tasks | Where-Object { [string]$_.id -eq [string]$f['fixTask'] }) | Select-Object -First 1
    $ws = @(if ($prev) { $prev.writeSet } elseif ($f['file']) { [string]$f['file'] })
    if (-not $ws.Count) { return '' }
    $n = if ($f.Contains('attempts') -and $f['attempts']) { [int]$f['attempts'] + 1 } else { 2 }
    $baseId = ([string]$f['fixTask']) -replace 'A\d+$', ''
    if (-not $baseId) { $baseId = "$($attr['group']).R$(if ($Run -match '-(\d+)$') { $Matches[1] } else { '0' })F" }
    $id = "${baseId}A$n"; $k = $n
    while (@($doc.tasks | Where-Object { [string]$_.id -eq $id }).Count) { $k++; $id = "${baseId}A$k" }
    $task = [ordered]@{ id = $id; group = [string]$attr['group']; title = "Fix attempt $n for Tier 2 failure ${Test}"
        why = $(if ($prev -and @($prev.why).Count) { @($prev.why) } else { @('TIER2-FAILURE') }); kind = 'code'; origin = 'integration'; writeSet = $ws; dependsOn = @()
        estMinutes = 45; estBasis = 'Tier 2 failure fix, sized as a typical fix task'
        note = "Tier 3 retest still fails $Test after $([string]$f['fixTask']) landed (base run $Run): attempt $n" }
    $ff = Join-Path $rd "$Run.refix-$id.json"
    Write-JsonFile $ff ([ordered]@{ groups = @(); tasks = @($task) })
    $out = @(& (Join-Path $ScriptDir 'Add-Tasks.ps1') -Repo $Repo -Role integrate -Session $Session -File $ff)
    if ($LASTEXITCODE) { Write-Warning "REFIX-FAILED $Test : $($out -join ' / ')"; return '' }
    foreach ($l in $out) { if ($l -match '^JOINED (\S+) into (\S+)' -and $Matches[1] -eq $id) { $id = $Matches[2] } }
    $f['fixTask'] = $id; $f['attempts'] = $n
    Write-JsonFile $attrPath $attr
    Add-Decision $P $Session "REFIX $Test $id (attempt $n, base run $Run)"
    $id
}
function Get-GroupRankMap($doc) { $m = @{}; $i = 0; foreach ($g in $doc.groups) { $m[[string]$g.id] = $i++ }; $m }

# FLAKY RECORD. flaky.json = { tests: { <test>: { first: <run>, firstAt, failedRuns: [<run>...], promoted: <run|null> } } }.
# A test that fails and then passes on the same-snapshot re-run is a candidate (no fix task). Every later Tier 2 run in
# which it fails again (flaky or not) is counted while it is inside the 5 Tier 2 runs after the first; the second such
# failure promotes it, and a promoted test is attributed like any failure.
function Update-FlakyRecord($P, [string] $Test, [string] $Run, [string] $RunAt, [string[]] $Tier2RunIdsAfterFirst) {
    $f = Join-Path $P.Suites 'flaky.json'
    $rec = Read-JsonFile $f; if (-not $rec) { $rec = [ordered]@{ tests = [ordered]@{} } }
    $t = $rec['tests'][$Test]
    if (-not $t) { $rec['tests'][$Test] = [ordered]@{ first = $Run; firstAt = $RunAt; failedRuns = @(); promoted = $null }; Write-JsonFile $f $rec; return 'candidate' }
    if ($t['promoted']) { return 'promoted' }
    if ($Run -eq $t['first'] -or @($t['failedRuns']) -contains $Run) { return 'candidate' }
    $window = @($Tier2RunIdsAfterFirst | Select-Object -First 5)
    if ($window -contains $Run) { $t['failedRuns'] = @(@($t['failedRuns']) + $Run) }
    $state = 'candidate'
    if (@($t['failedRuns']).Count -ge 2) { $t['promoted'] = $Run; $state = 'promoted' }
    Write-JsonFile $f $rec
    $state
}

# PERF LEGS (kit item IN-20261010212643-92b1). A timing test measures the host as much as the code: retest-G4-6 ran
# canvas-perf.spec.ts beside 5 author units, 5 build units and a G6 grader and measured drag p95 36.9 ms, where the same
# code measured 2.8 ms solo at 2% CPU, and that loaded run counted as Tier 3 strike 2 of 3. Owner rule 9827: a perf
# failure is a real defect only when it is red ALONE. So a perf leg (a leg flagged "solo": true, or, with no flag, one
# whose name contains "Perf") runs only on a quiet host: main-grader.lock free, no other Playwright or dotnet test
# process, and CPU under STREAM_QUIET_CPU_PCT (20) for STREAM_QUIET_WINDOW_SECONDS (60) in a row, sampled every
# STREAM_QUIET_SAMPLE_SECONDS (5). It waits at most STREAM_QUIET_MAX_WAIT_SECONDS (1800). A host that never quiets
# leaves the leg NOT-MEASURED, which is neither a pass nor a strike. STREAM_QUIET_PROBE_FILE (self-tests only) names a
# JSON file { cpu, busy: [..] } read in place of the real probe.
function Test-PerfLeg($Leg) {
    if (-not $Leg) { return $false }
    if ($Leg -is [Collections.IDictionary] -and $Leg.Contains('solo')) { return [bool]$Leg['solo'] }
    ([string]$Leg['name']) -match 'Perf'
}
function Get-QuietSetting([string] $Name, [double] $Default) {
    $v = [Environment]::GetEnvironmentVariable($Name)
    if ($v -and ($v -as [double]) -ne $null) { [double]$v } else { $Default }
}
# One sample: @{ cpu = <percent>; busy = @(<why>, ...) }.
function Get-HostLoadSample($P) {
    $probe = $env:STREAM_QUIET_PROBE_FILE
    if ($probe) {
        $j = Read-JsonFile $probe
        return @{ cpu = [double]$(if ($j -and $null -ne $j['cpu']) { $j['cpu'] } else { 0 }); busy = @(if ($j) { @($j['busy']) | Where-Object { $_ } }) }
    }
    $busy = [Collections.Generic.List[string]]::new()
    $lock = Get-MainTreeLockState $P
    if ($lock) { $busy.Add("main-grader.lock held ($(Get-MainTreeLockHolder $P))") }
    $mine = @{}; $id = $PID
    # This process and its ancestors are never "another" test process.
    for ($i = 0; $id -and $i -lt 12; $i++) { $mine[[int]$id] = $true; $pp = Get-CimInstance Win32_Process -Filter "ProcessId=$id" -ErrorAction SilentlyContinue; $id = if ($pp) { [int]$pp.ParentProcessId } else { 0 } }
    foreach ($p in @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)) {
        if ($mine.ContainsKey([int]$p.ProcessId)) { continue }
        $n = [string]$p.Name; $c = [string]$p.CommandLine
        $hit = ($n -match '^testhost(\.x86)?\.exe$') -or ($n -match '^vstest\.console\.exe$') -or
               ($n -eq 'dotnet.exe' -and $c -match '(?i)\s(test|vstest)(\s|$)') -or
               ($n -eq 'node.exe' -and $c -match '(?i)playwright' -and $c -match '(?i)\stest(\s|$)')
        if ($hit) { $busy.Add("$n pid $($p.ProcessId)") }
    }
    $cpu = 0
    try { $cpu = [double](Get-CimInstance Win32_PerfFormattedData_PerfOS_Processor -Filter "Name='_Total'" -ErrorAction Stop).PercentProcessorTime } catch { $cpu = 0 }
    @{ cpu = $cpu; busy = @($busy) }
}
# Waits for a quiet host. Beats the integrator lock (every 30 s) while it waits when $Session holds it.
# Returns @{ quiet = $bool; waitedSeconds = <n>; why = <the last reason it was not quiet, or ''> }.
function Wait-QuietHost($P, [string] $Session = '') {
    $pct = Get-QuietSetting 'STREAM_QUIET_CPU_PCT' 20
    $window = Get-QuietSetting 'STREAM_QUIET_WINDOW_SECONDS' 60
    $sample = [Math]::Max(0.2, (Get-QuietSetting 'STREAM_QUIET_SAMPLE_SECONDS' 5))
    $max = Get-QuietSetting 'STREAM_QUIET_MAX_WAIT_SECONDS' 1800
    $start = Get-Date; $quietSince = $null; $why = ''; $beatAt = $start
    while ($true) {
        $s = Get-HostLoadSample $P
        $now = Get-Date
        if (@($s.busy).Count) { $quietSince = $null; $why = (@($s.busy) | Select-Object -First 3) -join '; ' }
        elseif ($s.cpu -ge $pct) { $quietSince = $null; $why = "cpu $([int]$s.cpu)% (limit $pct%)" }
        else {
            if (-not $quietSince) { $quietSince = $now }
            if (($now - $quietSince).TotalSeconds -ge $window) { return @{ quiet = $true; waitedSeconds = [int]($now - $start).TotalSeconds; why = '' } }
        }
        if (($now - $start).TotalSeconds -ge $max) { return @{ quiet = $false; waitedSeconds = [int]($now - $start).TotalSeconds; why = $why } }
        if ($Session -and ($now - $beatAt).TotalSeconds -ge 30) { [void](Update-IntegratorBeat $P $Session); $beatAt = $now }
        Start-Sleep -Milliseconds ([int]($sample * 1000))
    }
}
