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
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Run
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
foreach ($leg in @($rec['legs'] | Where-Object { $_ -and $_['step'] -eq 'leg' })) {
    # A batched retest leg (Invoke-Retest, kit item IN-20261010055151-65af) names its own folder in outDir.
    $name = [string]$leg['name']; $dir = if ($leg['outDir']) { [string]$leg['outDir'] } else { Join-Path $rec['runDir'] $name }; $before = $rows.Count
    # A perf leg the host never let run (Invoke-SuiteLegs / Invoke-Retest, kit item IN-20261010212643-92b1) is one
    # 'leg:<name>' row with outcome 'not-measured': no coverage, and never a failure.
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
                        $rows.Add([ordered]@{ test = ((@($t) + [string]$sp['title']) -join ' > '); suite = $name; outcome = $outc; durationMs = $ms; file = $file; project = [string]$leg['project']; head = $rec['head'] })
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
foreach ($g in @($rec['graders'])) {
    if (-not $g) { continue }
    $rows.Add([ordered]@{ test = "grader:$($g['task'])"; suite = 'graders'; outcome = $(if ([int]$g['exit'] -eq 0) { 'passed' } else { 'failed' }); durationMs = 0; file = ''; project = ''; head = $rec['head']; task = [string]$g['task'] })
}
Write-JsonFile (Join-Path $rd "$Run.results.json") ([ordered]@{ run = $Run; group = $rec['group']; head = $rec['head']; tests = @($rows) })
$c = @{ passed = 0; failed = 0; skipped = 0 }; foreach ($r in $rows) { $c[$r.outcome]++ }
"RESULTS $Run passed $($c.passed) failed $($c.failed) skipped $($c.skipped)$(if ($c['not-measured']) { " not-measured $($c['not-measured'])" })"
exit 0
