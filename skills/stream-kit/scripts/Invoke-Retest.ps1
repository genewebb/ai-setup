# Re-runs only failed tests (2026-10-05 priority-focus-design 3.3).
#   Invoke-Retest.ps1 -Repo <repo> -Session <id> -Run <tier2 run> -Mode flaky
#       The flaky screen: the run's failed tests once more on the SAME snapshot. A test that passes there becomes
#       outcome 'flaky' in the run's results (a candidate in flaky.json, no fix task) unless the flaky record promotes
#       it (2 more failures in the next 5 Tier 2 runs), then it stays 'failed'.
#   Invoke-Retest.ps1 -Repo <repo> -Session <id> -Group <G> -Mode fix [-Run <tier2 run>]
#       Tier 3, after fix tasks integrate: on a NEW snapshot of main, the failures of the group's latest Tier 2 run that
#       Register-SuiteFailures.ps1 attributed to this or an earlier group ('fix') and that no later retest has passed,
#       plus the impact check (artifacts.check) of every fix row integrated after that run started. A failure is
#       retested only when its CURRENT fix row (the attribution's fixTask) integrated, or was retired, after the last
#       retest that ran it (or after the run started): a test whose fix has not landed is not run, so it never strikes
#       (final review I1). A failure the owner exempted (exempt.<G>.json, Test-GroupClose.ps1 -Exempt) is never run.
#       A retested failure that still fails files the next fix attempt (lib\Suites.ps1 Add-FixAttempt, printed
#       "REFIX <test> <id> (attempt n)") until it has failed three retests; then Test-GroupClose.ps1 blocks the group.
#       The new snapshot gets the run definition's "retestSetup" steps, or its "setup" steps when there are none (npm ci,
#       the build): without them a Playwright retest cannot start. A failed setup step ends the retest 'setup-failed',
#       which counts as no retest at all. After its legs (or a failed setup) it runs the run definition's "after" steps,
#       as a Tier 2 run does: a setup that redeploys web from the new snapshot is put back by the after redeploy from
#       main (kit item IN-20261011022936-074c). Refused (RUN-BUSY, exit 4) while another run or retest is running: its
#       snapshot would supersede the running one's, and the watchdog keeps only the newest.
# Filters: a dotnet leg runs `dotnet test <project> --filter "FullyQualifiedName~A|FullyQualifiedName~B"` (contains,
# never =, escaped: lib\Suites.ps1 ConvertTo-DotnetFilterTerm); a Playwright leg runs the failed spec files with an
# end-anchored, regex-escaped --grep of their titles. A leg may override with "retestCommand" in the run definition,
# using {filter} / {grep} / {files} / {runDir} / {leg}. Either way the re-run command starts with the leading
# `$env:NAME = '...';` statements of the leg's own command (all but PLAYWRIGHT_JSON_OUTPUT_NAME), so it runs in the
# environment the leg sets. A failed grader re-runs through Invoke-Grader.ps1.
# Writes .streams\suites\runs\<retest>.json (tier 'flaky' or '3', baseRun, tests, status, outcome pass|fail) and its
# .results.json (Export-SuiteResults.ps1). Prints "RETEST <id> <outcome> passed N failed N" or "RETEST-NOTHING <why>".
# A perf leg waits for a quiet host first; one that never quiets is NOT-MEASURED (outcome 'not-measured' when nothing
# else ran): its tests leave the record's tests list for notMeasured, so they neither pass nor strike.
# A fix retest whose filter or grep matched no test by a failed name (a fix row renamed it) prints NO-MATCH <test>: the
# test leaves tests for noMatch (outcome 'no-match' when nothing else ran), neither passes nor strikes, and one
# stream-plan item asks for the new title. A leg that crashed with no results still counts its tests as failed.
# A fix retest then runs the run definition's "retestSweeps" (whole legs, or a filter of one, gated by whenPaths) on the
# same snapshot; their results go to <retest>.sweep.results.json, and a test failed there but not in the base run (not
# exempt, not flaky) is recorded in sweepFailures and printed SWEEP-NEW <test>. Sweeps never change the outcome.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [string] $Run = '',
    [string] $Group = '',
    [Parameter(Mandatory)] [ValidateSet('flaky', 'fix')] [string] $Mode
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
. "$PSScriptRoot\lib\Activation.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$rd = Get-SuiteRunsDir $P
if ($Mode -eq 'fix') {
    $busy = @(Resolve-RunningSuiteRuns $P $Session)
    $said = @($busy | Where-Object { $_ -is [string] }); $said
    $busy = @($busy | Where-Object { $_ -isnot [string] })
    if ($busy.Count) { "RUN-BUSY $($busy[-1]['id']) is still running (started $($busy[-1]['startedAt'])); retest after it ends"; exit 4 }
}
if (-not $Run) {
    if (-not $Group) { 'REFUSED name -Run or -Group'; exit 2 }
    $last = @(Get-SuiteRunRecords $P $Group '2' | Where-Object { $_['status'] -eq 'done' }) | Select-Object -Last 1
    if (-not $last) { "RETEST-NOTHING no finished Tier 2 run for $Group"; exit 0 }
    $Run = [string]$last['id']
}
$base = Read-JsonFile (Join-Path $rd "$Run.json")
$baseRes = Read-JsonFile (Join-Path $rd "$Run.results.json")
if (-not $base -or -not $baseRes) { "NO-RUN $Run (record or results missing)"; exit 2 }
if (-not $Group) { $Group = [string]$base['group'] }
# The legs are the base run's own (a shared run, record 'groups', ran its 'group''s definition).
$def = Read-JsonFile (Join-Path $P.Suites "$([string]$base['group']).run.json")
$legDef = @{}; foreach ($l in @($def['legs'])) { if ($l) { $legDef[[string]$l['name']] = $l } }

# ---- which tests ----
$want = [Collections.Generic.List[object]]::new()
$checks = [Collections.Generic.List[string]]::new()
$notLanded = [Collections.Generic.List[string]]::new()
$fixPaths = [Collections.Generic.List[string]]::new()
if ($Mode -eq 'flaky') {
    foreach ($t in @($baseRes['tests'] | Where-Object { $_['outcome'] -eq 'failed' -and -not ([string]$_['test']).StartsWith('leg:') })) { $want.Add($t) }
} else {
    $attr = Read-JsonFile (Join-Path $rd "$Run.attribution.json")
    $doc = Read-Tasks $P
    $passedLater = @{}; $lastRanAt = @{}
    foreach ($r in @(Get-SuiteRunRecords $P $Group '3' | Where-Object { $_['baseRun'] -eq $Run -and $_['status'] -eq 'done' })) {
        $res = Read-JsonFile (Join-Path $rd "$($r['id']).results.json")
        foreach ($t in @($res['tests'])) { if ($t -and $t['outcome'] -eq 'passed') { $passedLater[[string]$t['test']] = $true } }
        foreach ($n in @($r['tests'])) { if ($n) { $lastRanAt[[string]$n] = ConvertTo-UtcTime $r['startedAt'] } }
    }
    $baseAt = ConvertTo-UtcTime $base['startedAt']
    $exempt = Get-SuiteExemptions $P $Group
    foreach ($a in @($attr['failures'] | Where-Object { $_ -and $_['disposition'] -eq 'fix' -and (-not $_['fixGroup'] -or [string]$_['fixGroup'] -eq $Group) })) {
        $name = [string]$a['test']
        if ($passedLater[$name] -or $name.StartsWith('leg:') -or $exempt.ContainsKey($name)) { continue }
        # Its current fix must have landed since the last retest that ran it; a retired fix row "lands" when it is
        # retired (lib\Suites.ps1 Get-FixLandedAt), so a failure withdrawn as environment-only re-runs once after it.
        $fixRow = @($doc.tasks | Where-Object { [string]$_.id -eq [string]$a['fixTask'] }) | Select-Object -First 1
        $since = if ($lastRanAt.ContainsKey($name)) { $lastRanAt[$name] } else { $baseAt }
        $landedAt = Get-FixLandedAt $fixRow
        if (-not $landedAt -or $landedAt -le $since) { $notLanded.Add("$name (waits on $([string]$a['fixTask']))"); continue }
        $orig = @($baseRes['tests'] | Where-Object { $_['test'] -eq $a['test'] }) | Select-Object -First 1
        if ($orig) { $want.Add($orig) }
    }
    $set = Get-GroupSet $doc $Group
    $startedAt = ConvertTo-UtcTime $base['startedAt']
    foreach ($t in @($doc.tasks | Where-Object { $set.Contains([string]$_.id) -and $_.Contains('origin') -and $_['origin'] -eq 'integration' -and $_.kind -eq 'code' -and $_.state -in @('integrated', 'done') })) {
        $ia = @($t.history | Where-Object { $_ -and $_.to -eq 'integrated' } | Select-Object -Last 1)
        if ($ia.Count -and (ConvertTo-UtcTime ([string]$ia[0].at)) -gt $startedAt) { foreach ($w in @($t.writeSet)) { if ($w) { $fixPaths.Add(([string]$w).Replace('\', '/')) } } }
        if ($ia.Count -and (ConvertTo-UtcTime ([string]$ia[0].at)) -gt $startedAt -and $t.Contains('artifacts') -and $t['artifacts'] -is [Collections.IDictionary] -and $t['artifacts']['check']) { $checks.Add([string]$t.id) }
    }
}
if (-not $want.Count -and -not $checks.Count) {
    $why = if ($Mode -eq 'fix' -and $notLanded.Count) { "no fix landed since the last retest: $((@($notLanded | Select-Object -First 5)) -join '; ')" } else { 'no failed test left to retest' }
    "RETEST-NOTHING $Mode for $Run ($why)"; exit 0
}

# ---- where ----
$k = 1; while (Test-Path (Join-Path $rd "retest-$Group-$k.json")) { $k++ }
$id = "retest-$Group-$k"
$runDir = Join-Path $rd $id; New-Item -ItemType Directory -Path $runDir -Force | Out-Null
if ($Mode -eq 'flaky') { $snap = [string]$base['snapshot']; $head = [string]$base['head'] }
else {
    $snapOut = @(& "$PSScriptRoot\New-SuiteSnapshot.ps1" -Repo $Repo -Session $Session -Group $Group -Run (1000 + $k) -CopyIgnored @($def['copyIgnored'] | Where-Object { $_ }) -Log (Join-Path $runDir 'snapshot.txt'))
    if ($LASTEXITCODE) { "SNAPSHOT-FAILED exit $LASTEXITCODE"; exit 5 }
    $snap = [string]($snapOut | Select-Object -Last 1)
    $headLine = @($snapOut | Where-Object { $_ -match '^SNAPSHOT ' }) | Select-Object -First 1
    $head = if ($headLine -match ' HEAD (\S+)') { $Matches[1] } else { '' }
}
if (-not (Test-Path -LiteralPath $snap)) { "SNAPSHOT-GONE $snap"; exit 5 }
$rec = [ordered]@{ id = $id; tier = $(if ($Mode -eq 'flaky') { 'flaky' } else { '3' }); group = $Group; baseRun = $Run; session = $Session
    startedAt = Get-Now; endedAt = $null; head = $head; snapshot = $snap; runDir = $runDir; status = 'running'
    tests = @($want | ForEach-Object { [string]$_['test'] }); checks = @($checks); legs = @(); graders = @() }
Set-SuiteRunProcess $rec
$recPath = Join-Path $rd "$id.json"; Write-JsonFile $recPath $rec

# ---- setup, on a new snapshot only (the flaky screen reuses the Tier 2 snapshot, which ran setup already) ----
$legs = [Collections.Generic.List[object]]::new(); $gr = [Collections.Generic.List[object]]::new()
$notMeasured = [Collections.Generic.List[string]]::new()
# The run definition's after steps, on a new snapshot only: the flaky screen runs inside a Tier 2 run, which runs them
# itself once the screen ends.
$runAfter = {
    if ($Mode -ne 'fix' -or -not $def) { return }
    foreach ($s in @($def['after'] | Where-Object { $_ })) {
        $sn = [string]$s['name']; $log = Join-Path $runDir "after.$sn.txt"
        $cmd = Expand-SuiteCommand ([string]$s['command']) @{ repo = $Repo; snapshot = $snap; runDir = $runDir; leg = $sn; run = $id; group = $Group }
        $wd = if ($s['workDir'] -eq 'repo') { $Repo } else { $snap }
        [void](& "$PSScriptRoot\Invoke-IntegratorRun.ps1" -Repo $Repo -Session $Session -Log $log -Command $cmd -WorkDir $wd)
        $legs.Add([ordered]@{ step = 'after'; name = $sn; kind = ''; project = ''; exit = $LASTEXITCODE; log = $log; command = $cmd })
        $rec['legs'] = @($legs); Write-JsonFile $recPath $rec
    }
}
if ($Mode -eq 'fix') {
    $setup = if ($def -and $def.Contains('retestSetup')) { @($def['retestSetup']) } elseif ($def) { @($def['setup']) } else { @() }
    foreach ($s in @($setup | Where-Object { $_ })) {
        $sn = [string]$s['name']; $log = Join-Path $runDir "setup.$sn.txt"
        $cmd = Expand-SuiteCommand ([string]$s['command']) @{ repo = $Repo; snapshot = $snap; runDir = $runDir; leg = $sn; run = $id; group = $Group }
        $wd = if ($s['workDir'] -eq 'repo') { $Repo } else { $snap }
        [void](& "$PSScriptRoot\Invoke-IntegratorRun.ps1" -Repo $Repo -Session $Session -Log $log -Command $cmd -WorkDir $wd)
        $code = $LASTEXITCODE
        $legs.Add([ordered]@{ step = 'setup'; name = $sn; kind = ''; project = ''; exit = $code; log = $log; command = $cmd })
        $rec['legs'] = @($legs); Write-JsonFile $recPath $rec
        if ($code) {
            & $runAfter
            $rec['status'] = 'setup-failed'; $rec['endedAt'] = Get-Now; Write-JsonFile $recPath $rec
            Add-Decision $P $Session "RETEST $id setup-failed ($sn exit $code); it counts as no retest"
            "RETEST $id setup-failed ($sn exit $code, log $log)"; exit 6
        }
    }
}

# ---- run, one leg at a time ----
$sq = { param([string] $s) "'" + $s.Replace("'", "''") + "'" }
# The leading `$env:NAME = '...';` statements of a leg's own command, as one prefix for its re-run command. A re-run
# builds its own command, so without them it ran without the environment the leg sets: retest-G4-3 lost
# NODE_USE_SYSTEM_CA, its Playwright preflight died on 'self-signed certificate', and its 6 failed tests counted as
# confirmed failures instead of flaky candidates (kit item IN-20261010145324-4e04). PLAYWRIGHT_JSON_OUTPUT_NAME is left
# out: the re-run names its own results file.
$legEnv = {
    param([string] $c)
    $parts = [Collections.Generic.List[string]]::new()
    $rx = [regex]'^\s*\$env:([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(''(?:[^'']|'''')*''|"[^"]*")\s*;'
    for ($m = $rx.Match($c); $m.Success; $m = $rx.Match($c)) {
        if ($m.Groups[1].Value -ne 'PLAYWRIGHT_JSON_OUTPUT_NAME') { $parts.Add($m.Value.Trim()) }
        $c = $c.Substring($m.Length)
    }
    if ($parts.Count) { ($parts -join ' ') + ' ' } else { '' }
}
foreach ($suite in @($want | Where-Object { -not ([string]$_['test']).StartsWith('grader:') } | Group-Object { [string]$_['suite'] })) {
    $name = $suite.Name; $ld = $legDef[$name]; $kind = if ($ld) { [string]$ld['kind'] } else { '' }
    # A perf leg runs only on a quiet host (lib\Suites.ps1 Wait-QuietHost). Measured on a loaded host it is no evidence
    # (owner rule 9827), so its tests are NOT-MEASURED: out of this retest's tests, so they are neither a pass nor a
    # strike, and the next retest runs them again (kit item IN-20261010212643-92b1).
    if (Test-PerfLeg $ld) {
        $q = Wait-QuietHost $P $Session
        if (-not $q.quiet) {
            foreach ($nm in @($suite.Group | ForEach-Object { [string]$_['test'] })) { $notMeasured.Add($nm) }
            $legs.Add([ordered]@{ step = 'leg'; name = $name; kind = $kind; project = [string]$ld['project']; exit = 0; log = ''; command = ''; notMeasured = $true; reason = "host not quiet after $($q.waitedSeconds) s: $($q.why)" })
            $rec['legs'] = @($legs); Write-JsonFile $recPath $rec
            "NOT-MEASURED $name $($suite.Count) test(s): host not quiet after $($q.waitedSeconds) s: $($q.why)"
            continue
        }
        "QUIET-HOST $name after $($q.waitedSeconds) s"
    }
    $proj = if ($ld) { [string]$ld['project'] } else { [string]$suite.Group[0]['project'] }
    $out = Join-Path $runDir $name; New-Item -ItemType Directory -Path $out -Force | Out-Null
    $vars = @{ repo = $Repo; snapshot = $snap; runDir = $runDir; leg = $name; run = $id; group = $Group }
    $envPre = if ($ld -and $ld['command']) { Expand-SuiteCommand (& $legEnv ([string]$ld['command'])) $vars } else { '' }
    if ($kind -eq 'playwright') {
        # npx is npx.cmd, so the command reaches cmd.exe, whose line limit is 8191 characters. retest-G4-1 put 170 titles
        # in one --grep and its leg logged only 'The command line is too long.', so every title still counted as failed
        # (kit item IN-20261010055151-65af). The titles go in batches whose command stays under STREAM_RETEST_CMD_MAX
        # (7000); batch 1 keeps the leg's own log and folder, batch n uses leg.<name>.<n>.txt and <runDir>\<name>.<n>,
        # and every batch is one legs entry under the leg's name, so Export-SuiteResults reads them all.
        $max = if ($env:STREAM_RETEST_CMD_MAX) { [int]$env:STREAM_RETEST_CMD_MAX } else { 7000 }
        $items = @($suite.Group | ForEach-Object {
            $f = [string]$_['file']
            [pscustomobject]@{ term = (ConvertTo-PlaywrightGrepTerm (([string]$_['test']) -split ' > ')[-1]); file = $(if ($f) { & $sq ([IO.Path]::GetRelativePath((Join-Path $snap $proj), (Join-Path $snap $f)).Replace('\', '/')) } else { '' }) }
        })
        $cmdFor = {
            param($batch, [string] $bOut, [string] $bLeg)
            $grep = (@($batch | ForEach-Object { $_.term }) | Select-Object -Unique) -join '|'
            $files = (@($batch | ForEach-Object { $_.file } | Where-Object { $_ } | Select-Object -Unique)) -join ' '
            $v = $vars.Clone(); $v['grep'] = $grep; $v['files'] = $files; $v['leg'] = $bLeg; $v['out'] = $bOut
            if ($ld -and $ld['retestCommand']) { $envPre + (Expand-SuiteCommand ([string]$ld['retestCommand']) $v) }
            # The reporter list is quoted: where npx resolves to npx.ps1, PowerShell reads a bare json,line as an array and
            # passes '--reporter=json line', and Playwright stops on "Cannot find module 'json line'" (run-G14-2; kit item
            # IN-20261016100941-a15f).
            else { "$envPre`$env:PLAYWRIGHT_JSON_OUTPUT_NAME = $(& $sq (Join-Path $bOut 'results.json')); Set-Location -LiteralPath $(& $sq (Join-Path $snap $proj)); npx playwright test $files '--reporter=json,line' --grep $(& $sq $grep)" }
        }
        $batches = [Collections.Generic.List[object]]::new(); $cur = [Collections.Generic.List[object]]::new()
        foreach ($it in $items) {
            $cur.Add($it)
            if ($cur.Count -gt 1 -and (& $cmdFor $cur $out $name).Length -gt $max) { $cur.RemoveAt($cur.Count - 1); $batches.Add(@($cur)); $cur = [Collections.Generic.List[object]]::new(); $cur.Add($it) }
        }
        if ($cur.Count) { $batches.Add(@($cur)) }
        for ($b = 1; $b -le $batches.Count; $b++) {
            $bName = if ($b -eq 1) { $name } else { "$name.$b" }
            $bOut = if ($b -eq 1) { $out } else { Join-Path $runDir $bName }
            New-Item -ItemType Directory -Path $bOut -Force | Out-Null
            $cmd = & $cmdFor $batches[$b - 1] $bOut $bName
            $log = Join-Path $runDir "leg.$bName.txt"
            [void](& "$PSScriptRoot\Invoke-IntegratorRun.ps1" -Repo $Repo -Session $Session -Log $log -Command $cmd -WorkDir $snap)
            $legs.Add([ordered]@{ step = 'leg'; name = $name; kind = $kind; project = $proj; exit = $LASTEXITCODE; log = $log; command = $cmd; outDir = $bOut; batch = $b; batches = $batches.Count })
            $rec['legs'] = @($legs); Write-JsonFile $recPath $rec
        }
        continue
    } else {
        $filter = (@($suite.Group | ForEach-Object { ConvertTo-DotnetFilterTerm ([string]$_['test']) }) | Select-Object -Unique) -join '|'
        $vars['filter'] = $filter
        $cmd = if ($ld -and $ld['retestCommand']) { $envPre + (Expand-SuiteCommand ([string]$ld['retestCommand']) $vars) }
               else { "${envPre}dotnet test $(& $sq $proj) --filter $(& $sq $filter) --logger trx --results-directory $(& $sq $out)" }
        $kind = 'dotnet'
    }
    $log = Join-Path $runDir "leg.$name.txt"
    [void](& "$PSScriptRoot\Invoke-IntegratorRun.ps1" -Repo $Repo -Session $Session -Log $log -Command $cmd -WorkDir $snap)
    $legs.Add([ordered]@{ step = 'leg'; name = $name; kind = $kind; project = $proj; exit = $LASTEXITCODE; log = $log; command = $cmd })
    $rec['legs'] = @($legs); Write-JsonFile $recPath $rec
}
# ---- sweeps: whole legs (or a filter of one) the run definition names in "retestSweeps" = [{ leg, filter?, whenPaths? }],
# on the same snapshot. A fix row that only edits docs or a test helper can turn a static sweep red, and a retest that
# re-runs only the failed tests never sees it (kit item IN-20261020141232-7f92). whenPaths runs the sweep only when a
# fix row integrated since the base run started has a write-set path like one of them. A sweep is a 'sweep' step, read
# by Export-SuiteResults.ps1 -Step sweep into its own results file, so it never changes this retest's outcome or strikes.
if ($Mode -eq 'fix' -and $def -and $def.Contains('retestSweeps')) {
    foreach ($sw in @($def['retestSweeps'] | Where-Object { $_ })) {
        $ln = [string]$sw['leg']; $ld = $legDef[$ln]
        if (-not $ld) { "SWEEP-SKIP $ln (no such leg in $([string]$base['group']).run.json)"; continue }
        $when = @($sw['whenPaths'] | Where-Object { $_ } | ForEach-Object { ([string]$_).Replace('\', '/') -replace '\*\*', '*' })
        if ($when.Count -and -not @($fixPaths | Where-Object { $fp = $_; @($when | Where-Object { $fp -like $_ }).Count }).Count) {
            "SWEEP-SKIP $ln (no fix row landed since $Run writes $($when -join ', '))"; continue
        }
        $sRoot = Join-Path $runDir 'sweep'; $out = Join-Path $sRoot $ln; New-Item -ItemType Directory -Path $out -Force | Out-Null
        $proj = [string]$ld['project']
        # The leg's own command with {runDir} at <runDir>\sweep, so its results never mix with the re-run of that leg's
        # failed tests in <runDir>\<leg>. A filter goes through the leg's retestCommand ({filter}) when it has one.
        $vars = @{ repo = $Repo; snapshot = $snap; runDir = $sRoot; leg = $ln; run = $id; group = $Group; filter = [string]$sw['filter'] }
        $envPre = Expand-SuiteCommand (& $legEnv ([string]$ld['command'])) $vars
        $cmd = if ($sw['filter'] -and $ld['retestCommand']) { $envPre + (Expand-SuiteCommand ([string]$ld['retestCommand']) $vars) }
        elseif ($sw['filter']) {
            "${envPre}dotnet test $(& $sq $proj)$(if ([string]$ld['command'] -match '--no-build') { ' --no-build' }) --filter $(& $sq ([string]$sw['filter'])) --logger trx --results-directory $(& $sq $out)"
        } else { Expand-SuiteCommand ([string]$ld['command']) $vars }
        $log = Join-Path $runDir "leg.sweep.$ln.txt"
        [void](& "$PSScriptRoot\Invoke-IntegratorRun.ps1" -Repo $Repo -Session $Session -Log $log -Command $cmd -WorkDir $snap)
        $legs.Add([ordered]@{ step = 'sweep'; name = $ln; kind = [string]$ld['kind']; project = $proj; exit = $LASTEXITCODE; log = $log; command = $cmd; outDir = $out; filter = [string]$sw['filter'] })
        $rec['legs'] = @($legs); Write-JsonFile $recPath $rec
    }
}
foreach ($t in @($want | Where-Object { ([string]$_['test']).StartsWith('grader:') })) {
    $task = ([string]$t['test']).Substring(7)
    [void](& "$PSScriptRoot\Invoke-Grader.ps1" -Repo $Repo -Task $task -Root $snap -Label $id -BeatSession $Session)
    $gr.Add([ordered]@{ task = $task; exit = $LASTEXITCODE })
}
foreach ($task in $checks) {
    [void](& "$PSScriptRoot\Invoke-Grader.ps1" -Repo $Repo -Task $task -Root $snap -Label $id -Only check -BeatSession $Session)
    $gr.Add([ordered]@{ task = $task; exit = $LASTEXITCODE; check = $true })
}
$rec['graders'] = @($gr); Write-JsonFile $recPath $rec
& $runAfter
# The record turns 'done' only once its results are read: a throw there must not leave a 'done' retest with no
# outcome, which the close rule would count as a failed attempt.
$swept = @($legs | Where-Object { $_['step'] -eq 'sweep' }).Count
try {
    [void](& "$PSScriptRoot\Export-SuiteResults.ps1" -Repo $Repo -Run $id)
    if ($swept) { [void](& "$PSScriptRoot\Export-SuiteResults.ps1" -Repo $Repo -Run $id -Step sweep) }
}
catch {
    $rec['status'] = 'error'; $rec['error'] = ("$_" -split "`n")[0]; $rec['endedAt'] = Get-Now; Write-JsonFile $recPath $rec
    Add-Decision $P $Session "RETEST $id error: $($rec['error'])"
    "RETEST-ERROR $id $($rec['error'])"; exit 7
}
$rec['status'] = 'done'; $rec['endedAt'] = Get-Now
if ($notMeasured.Count) { $rec['tests'] = @(@($rec['tests']) | Where-Object { $notMeasured -notcontains $_ }); $rec['notMeasured'] = @($notMeasured) }
$res = Read-JsonFile (Join-Path $rd "$id.results.json")
# A sweep's new failures: failed there, not failed in the base run, not exempt and not a known flaky test. They are
# kept on the record (sweepFailures) for attribution; they do not count in this retest's outcome.
$sweepNew = [Collections.Generic.List[string]]::new()
if ($swept) {
    $sres = Read-JsonFile (Join-Path $rd "$id.sweep.results.json")
    $baseFailed = @{}; foreach ($t in @($baseRes['tests'])) { if ($t -and $t['outcome'] -eq 'failed') { $baseFailed[[string]$t['test']] = $true } }
    $flk = Read-JsonFile (Join-Path $P.Suites 'flaky.json')
    foreach ($t in @($sres['tests'])) {
        if (-not $t -or $t['outcome'] -ne 'failed') { continue }
        $n = [string]$t['test']
        if ($baseFailed[$n] -or $exempt.ContainsKey($n) -or $sweepNew -contains $n -or ($flk -and $flk['tests'] -and $flk['tests'].Contains($n))) { continue }
        $sweepNew.Add($n)
    }
    $rec['sweeps'] = @($legs | Where-Object { $_['step'] -eq 'sweep' } | ForEach-Object { [string]$_['name'] })
    $rec['sweepFailures'] = @($sweepNew)
}
# A retested test that left no row (filtered out, or its leg crashed) counts as failed.
$byTest = @{}; foreach ($t in @($res['tests'])) { if ($t) { $byTest[[string]$t['test']] = [string]$t['outcome'] } }
foreach ($g in $gr) { if ($g['check']) { $byTest["check:$($g['task'])"] = $(if ([int]$g['exit'] -eq 0) { 'passed' } else { 'failed' }) } }
# A fix retest whose filter or grep matched no test at all is NO-MATCH, never a failure: a fix row that renames the test
# (G14.R4F63 renamed a backup.spec title) leaves the base run's title matching nothing, and counting that as still
# failing filed a pointless next attempt (G14.R4F37A2; kit item IN-20261020004435-6e00). The test left no row while its
# leg did run: the leg reported other tests (no failed 'leg:<suite>' row), or every failing batch of it logged
# Playwright's 'No tests found'. Like NOT-MEASURED it leaves the record's tests for noMatch, so it neither passes nor
# strikes; the planner names the new title (one stream-plan item), and a crashed leg still counts as failed.
$noMatch = [Collections.Generic.List[string]]::new()
if ($Mode -eq 'fix') {
    $legRow = @{}; foreach ($t in @($res['tests'])) { if ($t -and ([string]$t['test']).StartsWith('leg:') -and $t['outcome'] -eq 'failed') { $legRow[([string]$t['test']).Substring(4)] = $true } }
    foreach ($t in @($want | Where-Object { -not ([string]$_['test']).StartsWith('grader:') })) {
        $w = [string]$t['test']; $sn = [string]$t['suite']
        if ($byTest.ContainsKey($w) -or $notMeasured -contains $w -or @($rec['tests']) -notcontains $w) { continue }
        $ran = @($legs | Where-Object { $_['step'] -eq 'leg' -and $_['name'] -eq $sn -and -not $_['notMeasured'] })
        if (-not $ran.Count) { continue }
        $none = -not $legRow[$sn]
        if (-not $none) {
            $bad = @($ran | Where-Object { [int]$_['exit'] -ne 0 })
            $none = $bad.Count -and -not @($bad | Where-Object { -not $_['log'] -or -not (Test-Path -LiteralPath $_['log']) -or -not (Select-String -LiteralPath $_['log'] -Pattern 'No tests found' -SimpleMatch -Quiet) }).Count
        }
        if ($none) { $noMatch.Add($w) }
    }
    if ($noMatch.Count) {
        $rec['tests'] = @(@($rec['tests']) | Where-Object { $noMatch -notcontains $_ }); $rec['noMatch'] = @($noMatch)
        foreach ($w in $noMatch) { "NO-MATCH $w (the retest matched no test by this name; renamed? the planner names the new title)" }
    }
}
$passed = 0; $failed = 0
foreach ($w in @($rec['tests']) + @($checks | ForEach-Object { "check:$_" })) { if ($byTest[$w] -eq 'passed') { $passed++ } else { $failed++ } }
$rec['outcome'] = $(if ($failed) { 'fail' } elseif (-not $passed -and $noMatch.Count) { 'no-match' } elseif (-not $passed -and $notMeasured.Count) { 'not-measured' } else { 'pass' }); $rec['perTest'] = $byTest; Write-JsonFile $recPath $rec

if ($Mode -eq 'flaky') {
    $tier2 = @(Get-SuiteRunRecords $P '' '2')
    $flakyNow = Read-JsonFile (Join-Path $P.Suites 'flaky.json')
    $changed = $false
    foreach ($t in @($baseRes['tests'])) {
        if (-not $t -or $t['outcome'] -ne 'failed') { continue }
        $name = [string]$t['test']
        $known = $flakyNow -and $flakyNow['tests'] -and $flakyNow['tests'].Contains($name)
        if ($byTest[$name] -ne 'passed' -and -not $known) { continue }
        $first = if ($known) { $flakyNow['tests'][$name]['firstAt'] } else { $base['startedAt'] }
        $after = @($tier2 | Where-Object { (ConvertTo-UtcTime $_['startedAt']) -gt (ConvertTo-UtcTime $first) } | ForEach-Object { [string]$_['id'] })
        $state = Update-FlakyRecord $P $name $Run $base['startedAt'] $after
        $flakyNow = Read-JsonFile (Join-Path $P.Suites 'flaky.json')
        if ($byTest[$name] -eq 'passed' -and $state -eq 'candidate') { $t['outcome'] = 'flaky'; $changed = $true; "FLAKY $name (candidate; no fix task)" }
        elseif ($state -eq 'promoted') { $t['flakyPromoted'] = $true; $changed = $true; "FLAKY-PROMOTED $name (failed again inside 5 Tier 2 runs: attributed as a failure)" }
    }
    if ($changed) { Write-JsonFile (Join-Path $rd "$Run.results.json") $baseRes }
}
Add-Decision $P $Session "RETEST $id ($Mode, base $Run): $($rec['outcome']) passed $passed failed $failed"
"RETEST $id $($rec['outcome']) passed $passed failed $failed"
foreach ($n in $sweepNew) { "SWEEP-NEW $n (failed in a $id sweep, not in $Run)" }
# The sweep regressions become fix rows now (Register-SuiteFailures.ps1 -Retest, kit item IN-20261020141623-c8a3): they
# continue the base run's fix numbering and hold the close through OPEN-FIX; the base run's attribution is untouched.
if ($sweepNew.Count) { @(& "$PSScriptRoot\Register-SuiteFailures.ps1" -Repo $Repo -Session $Session -Retest $id) | ForEach-Object { "  $_" } }
if ($Mode -eq 'fix') {
    # The next fix attempt for each retested failure that still fails, up to three failed retests (then the close
    # rule blocks the group and the owner decides).
    $grp = @((Read-Tasks $P).groups | Where-Object { [string]$_.id -eq $Group }) | Select-Object -First 1
    foreach ($w in @($rec['tests'])) {
        if ($byTest[$w] -eq 'passed') { continue }
        $strikes = @(Get-StrikeRetests $P $Group $Run $w $grp).Count
        if ($strikes -ge 3) { continue }
        $nid = Add-FixAttempt $P $Repo $Session $Run $w $PSScriptRoot
        if ($nid) { "REFIX $w $nid (attempt $($strikes + 1))" }
    }
    # One stream-plan item per newly unmatched test: an earlier retest of this base run that already reported it
    # filed it then.
    $told = @{}
    foreach ($r in @(Get-SuiteRunRecords $P $Group '3' | Where-Object { $_['baseRun'] -eq $Run -and [string]$_['id'] -ne $id })) { foreach ($n in @($r['noMatch'])) { if ($n) { $told[[string]$n] = $true } } }
    $new = @($noMatch | Where-Object { -not $told[$_] })
    if ($new.Count) {
        $ask = "NO-MATCH in $id (base $Run): the Tier 3 retest matched no test named $(($new | ForEach-Object { "'$_'" }) -join ', '). A fix row probably renamed it. Name the new title (or exempt it with Test-GroupClose.ps1 -Exempt) so the retest can run it; until then it neither passes nor strikes and the close reads UNRETESTED."
        [void](& "$PSScriptRoot\Send-InboxItem.ps1" -Repo $Repo -To stream-plan -From $Session -Kind bug -Ask $ask -Evidence $recPath)
    }
}
exit 0
