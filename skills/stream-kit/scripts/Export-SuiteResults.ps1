# Turns one run's result files into per-test rows (2026-10-05 priority-focus-design 3.3):
# .streams\suites\runs\<run>.results.json = { run, group, head, tests: [ { test, suite, outcome, durationMs, file, project, head } ] }
#   Export-SuiteResults.ps1 -Repo <repo> -Run <run>
# Sources, per leg of the run record:
#   dotnet     : every *.trx under <runDir>\<leg>\ (UnitTestResult + TestDefinitions). test = <className>.<method name>,
#                the DataRow arguments cut at '(' (one method = one test; the retest filter is a contains-match).
#                file = the .cs file under the leg's project in the snapshot that declares the class, so attribution by
#                write set works; '' when none is found.
#   playwright : <runDir>\<leg>\results.json (the json reporter). test = the describe chain and title joined by ' > ';
#                file = the spec file, relative to the repo.
#   graders    : the run record's graders list: test 'grader:<task>', outcome by exit code.
# outcome is passed, failed, skipped or not-measured (a perf leg the host never let run). A leg whose command failed but left no result file gets one row
# 'leg:<name>' failed, so a crash before the first test is never read as green. Prints "RESULTS <run> passed N failed N skipped N".
# Skipped tests ([Ignore], or a live test's Assert.Inconclusive: both NotExecuted in a trx) are never passes: when there are any it also
# prints "NOT-RUN <run> N test(s) skipped, not passes: <leg> N, ..." (TestRunFindings-2026-10-25 F6, kit item IN-20261025152845-1d06).
# A live proof whose record (<runDir>\proofs\<name>.json) reads failed or timeout is named on
# "PROOF-FAILED <run> N live proof(s) failed, their tests not run: <name> (<variable>, <status>: <reason>); ..." (kit item IN-20261026151607-13e0).
# -Step sweep reads the record's 'sweep' legs instead (a Tier 3 retest's whole-leg sweeps, Invoke-Retest.ps1
# retestSweeps; kit item IN-20261020141232-7f92) into <run>.sweep.results.json, with no grader rows, so a sweep never
# changes the retest's own results or outcome.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Run,
    [ValidateSet('leg', 'sweep')] [string] $Step = 'leg'
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$rd = Get-SuiteRunsDir $P
$rec = Read-JsonFile (Join-Path $rd "$Run.json")
if (-not $rec) { "NO-RUN $Run"; exit 2 }
$snap = [string]$rec['snapshot']
$rows = [Collections.Generic.List[object]]::new()
$classFile = @{}
function Find-ClassFile([string] $ProjectDir, [string] $Class) {
    $short = ($Class -split '\.')[-1]
    $key = "$ProjectDir|$short"
    if ($classFile.ContainsKey($key)) { return $classFile[$key] }
    $hit = ''
    if ($ProjectDir -and (Test-Path -LiteralPath $ProjectDir)) {
        $m = Get-ChildItem -LiteralPath $ProjectDir -Recurse -File -Filter '*.cs' -ErrorAction SilentlyContinue | Where-Object { $_.FullName -notmatch '\\(bin|obj)\\' } |
            Select-String -Pattern "\b(class|record)\s+$([regex]::Escape($short))\b" -List | Select-Object -First 1
        if ($m) { $hit = ConvertTo-RepoRel ([IO.Path]::GetRelativePath($snap, $m.Path)) }
    }
    $classFile[$key] = $hit
    $hit
}
function ConvertTo-Outcome([string] $o) {
    switch -Regex ($o) { '^(Passed|passed|expected)$' { 'passed' } '^(NotExecuted|skipped|Inconclusive)$' { 'skipped' } default { 'failed' } }
}
foreach ($leg in @($rec['legs'] | Where-Object { $_ -and $_['step'] -eq $Step })) {
    # A batched retest leg (Invoke-Retest, kit item IN-20261010055151-65af) names its own folder in outDir.
    $name = [string]$leg['name']; $dir = if ($leg['outDir']) { [string]$leg['outDir'] } else { Join-Path $rec['runDir'] $name }; $before = $rows.Count
    # A perf leg the host never let run (Invoke-SuiteLegs / Invoke-Retest, kit item IN-20261010212643-92b1) is one
    # 'leg:<name>' row with outcome 'not-measured': no coverage, and never a failure.
    # A leg the run never started because another session took the integrator lock (Invoke-SuiteLegs marks it
    # 'lockLost'; an older record: exit 5 on the last leg of a 'lock-lost' run) is one 'leg:<name>' row with outcome
    # 'not-run': no coverage, never a failure, so Register-SuiteFailures.ps1 files nothing for it (kit item
    # IN-20261020115130-5b6f).
    $lastLeg = @($rec['legs'] | Where-Object { $_ -and $_['step'] -eq $Step })[-1]
    if ($leg['lockLost'] -or ([string]$rec['status'] -eq 'lock-lost' -and [int]$leg['exit'] -eq 5 -and [object]::ReferenceEquals($leg, $lastLeg))) {
        $rows.Add([ordered]@{ test = "leg:$name"; suite = $name; outcome = 'not-run'; durationMs = 0; file = ''; project = [string]$leg['project']; head = $rec['head'] }); continue
    }
    if ($leg['notMeasured']) { $rows.Add([ordered]@{ test = "leg:$name"; suite = $name; outcome = 'not-measured'; durationMs = 0; file = ''; project = [string]$leg['project']; head = $rec['head'] }); continue }
    if ($leg['kind'] -eq 'dotnet') {
        $proj = if ($leg['project']) { Join-Path $snap $leg['project'] } else { $snap }
        foreach ($trx in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.trx' -ErrorAction SilentlyContinue)) {
            [xml]$x = Get-Content -Raw -LiteralPath $trx.FullName
            # By local name: VSTest writes the TeamTest namespace, and a run whose filter matched nothing has no
            # <Results> (or an empty one), where dot access throws under StrictMode (final review I4).
            $defs = @{}
            foreach ($d in @($x.SelectNodes("//*[local-name()='UnitTest']"))) {
                $tm = $d.SelectSingleNode("*[local-name()='TestMethod']")
                $defs[$d.GetAttribute('id')] = if ($tm) { $tm.GetAttribute('className') } else { '' }
            }
            foreach ($r in @($x.SelectNodes("//*[local-name()='UnitTestResult']"))) {
                $cls = [string]$defs[$r.GetAttribute('testId')]; $cls = ($cls -split ',')[0].Trim()
                $method = $r.GetAttribute('testName'); $i = $method.IndexOf('('); if ($i -ge 0) { $method = $method.Substring(0, $i) }; $method = $method.Trim()
                $test = if ($cls -and -not $method.StartsWith("$cls.")) { "$cls.$method" } else { $method }
                $ms = 0; try { $ms = [int]([TimeSpan]::Parse($r.GetAttribute('duration')).TotalMilliseconds) } catch { }
                $rows.Add([ordered]@{ test = $test; suite = $name; outcome = (ConvertTo-Outcome $r.GetAttribute('outcome')); durationMs = $ms; file = (Find-ClassFile $proj $cls); project = [string]$leg['project']; head = $rec['head'] })
            }
        }
    } elseif ($leg['kind'] -eq 'playwright') {
        $jf = Join-Path $dir 'results.json'
        if (Test-Path -LiteralPath $jf) {
            $j = Get-Content -Raw -LiteralPath $jf | ConvertFrom-Json -AsHashtable -Depth 60
            $walk = $null
            $walk = {
                param($suite, [string[]] $chain)
                $t = if ($suite['title'] -and -not ([string]$suite['title']).EndsWith('.ts') -and -not ([string]$suite['title']).EndsWith('.js')) { @($chain) + [string]$suite['title'] } else { @($chain) }
                foreach ($sp in @($suite['specs'])) {
                    if (-not $sp) { continue }
                    foreach ($tt in @($sp['tests'])) {
                        if (-not $tt) { continue }
                        $res = @($tt['results']); $last = if ($res.Count) { $res[-1] } else { $null }
                        $st = if ($tt['status']) { [string]$tt['status'] } elseif ($last) { [string]$last['status'] } else { 'skipped' }
                        $outc = switch ($st) { 'expected' { 'passed' } 'flaky' { 'passed' } 'skipped' { 'skipped' } 'passed' { 'passed' } default { 'failed' } }
                        $ms = 0; foreach ($rr in $res) { if ($rr) { $ms += [int]$rr['duration'] } }
                        # The reporter's spec file is relative to the config's testDir, which this script does not
                        # read: the first candidate that exists in the snapshot wins (project\tests\, project\, root).
                        $sf = ([string]$sp['file']).Replace('/', '\'); $pr = [string]$leg['project']
                        $cands = @((Join-Path $pr "tests\$sf"), (Join-Path $pr $sf), $sf)
                        $file = ConvertTo-RepoRel $cands[1]
                        foreach ($cand in $cands) { if ($sf -and (Test-Path -LiteralPath (Join-Path $snap $cand))) { $file = ConvertTo-RepoRel $cand; break } }
                        # pwProject is the Playwright project the test ran under (project is the leg's folder): a
                        # retest of a teardown project's test needs it (Invoke-Retest.ps1 retestWholeFile, kit item
                        # IN-20261026151817-80e7).
                        $rows.Add([ordered]@{ test = ((@($t) + [string]$sp['title']) -join ' > '); suite = $name; outcome = $outc; durationMs = $ms; file = $file; project = [string]$leg['project']; pwProject = [string]$tt['projectName']; head = $rec['head'] })
                    }
                }
                foreach ($c in @($suite['suites'])) { if ($c) { & $walk $c $t } }
            }
            foreach ($s in @($j['suites'])) { if ($s) { & $walk $s @() } }
        }
    }
    if ($rows.Count -eq $before -and [int]$leg['exit'] -ne 0) {
        $rows.Add([ordered]@{ test = "leg:$name"; suite = $name; outcome = 'failed'; durationMs = 0; file = ''; project = [string]$leg['project']; head = $rec['head'] })
    }
}
foreach ($g in @(if ($Step -eq 'leg') { $rec['graders'] })) {
    if (-not $g) { continue }
    $rows.Add([ordered]@{ test = "grader:$($g['task'])"; suite = 'graders'; outcome = $(if ([int]$g['exit'] -eq 0) { 'passed' } else { 'failed' }); durationMs = 0; file = ''; project = ''; head = $rec['head']; task = [string]$g['task'] })
}
$outName = if ($Step -eq 'sweep') { "$Run.sweep.results.json" } else { "$Run.results.json" }
Write-JsonFile (Join-Path $rd $outName) ([ordered]@{ run = $Run; group = $rec['group']; head = $rec['head']; tests = @($rows) })
$c = @{ passed = 0; failed = 0; skipped = 0 }; foreach ($r in $rows) { $c[$r.outcome]++ }
"RESULTS $Run$(if ($Step -eq 'sweep') { ' sweep' }) passed $($c.passed) failed $($c.failed) skipped $($c.skipped)$(if ($c['not-measured']) { " not-measured $($c['not-measured'])" })$(if ($c['not-run']) { " not-run $($c['not-run'])" })"
$sk = @($rows | Where-Object { $_.outcome -eq 'skipped' } | Group-Object { $_.suite } | ForEach-Object { "$($_.Name) $($_.Count)" })
if ($sk.Count) { "NOT-RUN $Run$(if ($Step -eq 'sweep') { ' sweep' }) $($c.skipped) test(s) skipped, not passes: $($sk -join ', ')" }
# A live proof (setup step .streams\suites\Invoke-Tier2Proof.ps1, record <runDir>\proofs\<name>.json) that failed or
# timed out leaves its tests Inconclusive: name each one, so the NOT-RUN count says why (kit item IN-20261026151607-13e0).
$pdir = if ($Step -eq 'leg' -and $rec['runDir']) { Join-Path ([string]$rec['runDir']) 'proofs' } else { '' }
if ($pdir -and (Test-Path -LiteralPath $pdir)) {
    $pf = @(Get-ChildItem -LiteralPath $pdir -Filter '*.json' -File | Sort-Object Name | ForEach-Object {
        $p = try { Read-JsonFile $_.FullName } catch { $null }
        # A proof's own report may sit beside its record ('<name>.report.json'): only a record names its variable.
        if ($p -and $p['name'] -and $p['variable'] -and [string]$p['status'] -in 'failed', 'timeout') { "$($p['name']) ($($p['variable']), $($p['status']): $($p['reason']))" }
    })
    if ($pf.Count) { "PROOF-FAILED $Run $($pf.Count) live proof(s) failed, their tests not run: $($pf -join '; ')" }
}
exit 0
