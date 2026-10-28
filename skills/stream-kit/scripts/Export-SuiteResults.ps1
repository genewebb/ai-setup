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
# A Tier 2 run's total is DISCOVERED from its own build (owner 2026-10-28; never taken from another run): every test a
# leg's build holds under the leg's own filter or grep (dotnet vstest /ListFullyQualifiedTests, playwright --list) that the
# leg reported no result for is a 'not-run' row, so a crashed, lock-lost or unmeasured leg still counts its tests. Per-leg
# discovered counts go to the file's 'discovered' map. A leg that cannot be discovered is a failed 'discover:<name>' row
# and a "DISCOVERY-FAILED" line; not-run rows are printed on "NOT-STARTED <run> N discovered test(s) with no result: ...".
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
# The rows of one Playwright json report (a run's results.json, or a --list report), one per test and project.
function Get-PlaywrightRows($j, $leg, [string] $name) {
    $out = [Collections.Generic.List[object]]::new()
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
                $out.Add([ordered]@{ test = ((@($t) + [string]$sp['title']) -join ' > '); suite = $name; outcome = $outc; durationMs = $ms; file = $file; project = [string]$leg['project']; pwProject = [string]$tt['projectName']; head = $rec['head'] })
            }
        }
        foreach ($c in @($suite['suites'])) { if ($c) { & $walk $c $t } }
    }
    foreach ($s in @($j['suites'])) { if ($s) { & $walk $s @() } }
    , $out
}
# A dotnet display name as a comparison key: every run of whitespace (a data row's argument may hold a line break, which
# the test list and the trx write differently) is one space.
function ConvertTo-DisplayKey([string] $Name) { ([regex]::Replace($Name, '\s+', ' ')).Trim() }
# The words of a PowerShell command line after $From, single or double quotes removed ('' inside single quotes is ').
function Get-CommandWords([string] $Command, [string] $From) {
    $i = $Command.IndexOf($From); if ($i -lt 0) { return @() }
    $rest = $Command.Substring($i + $From.Length)
    $cut = $rest.IndexOf(';'); if ($cut -ge 0) { $rest = $rest.Substring(0, $cut) }
    @([regex]::Matches($rest, "'(?:[^']|'')*'|`"[^`"]*`"|\S+") | ForEach-Object {
        $w = $_.Value
        if ($w.StartsWith("'")) { $w.Substring(1, $w.Length - 2).Replace("''", "'") } elseif ($w.StartsWith('"')) { $w.Trim('"') } else { $w }
    })
}
# Every test one leg of a Tier 2 run holds in the run's own build (owner 2026-10-28: the total is discovered, never taken
# from another run). dotnet: dotnet vstest /ListFullyQualifiedTests on the leg project's built assembly with the leg's own
# --filter (a literal, or a $variable the command assigns a literal). playwright: playwright test --list with the leg's own
# spec files, --grep, --grep-invert and --project. Returns @{ keys = test names (playwright 'name|project') ; error = '' }.
# True when $Text is the start of (or all of) one of the sorted, ordinal $Keys.
function Test-KeyPrefix([string[]] $Keys, [string] $Text) {
    if (-not $Keys -or -not $Keys.Count) { return $false }
    $i = [array]::BinarySearch($Keys, $Text, [StringComparer]::Ordinal)
    if ($i -ge 0) { return $true }
    $i = -bnot $i
    $i -lt $Keys.Count -and $Keys[$i].StartsWith($Text, [StringComparison]::Ordinal)
}
# $Reported: the leg's reported display keys, sorted ordinal; they tell a data row's own indented line from a new entry.
function Get-DiscoveredTests($leg, [string[]] $Reported = @()) {
    $cmd = [string]$leg['command']
    $proj = if ($leg['project']) { Join-Path $snap $leg['project'] } else { $snap }
    try {
        if ($leg['kind'] -eq 'dotnet') {
            $csproj = Get-ChildItem -LiteralPath $proj -Filter '*.csproj' -File | Select-Object -First 1
            if (-not $csproj) { return @{ keys = @(); error = "no .csproj in $proj" } }
            $an = ([xml](Get-Content -Raw -LiteralPath $csproj.FullName)).SelectNodes("//*[local-name()='AssemblyName']") | Select-Object -First 1
            $asm = if ($an -and $an.InnerText) { $an.InnerText } else { $csproj.BaseName }
            $dll = Get-ChildItem -LiteralPath (Join-Path $proj 'bin') -Recurse -File -Filter "$asm.dll" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if (-not $dll) { return @{ keys = @(); error = "no built $asm.dll under $proj\bin" } }
            $filter = ''
            $w = @(Get-CommandWords $cmd 'dotnet test'); $fi = [array]::IndexOf($w, '--filter')
            if ($fi -ge 0 -and $fi + 1 -lt $w.Count) {
                $filter = $w[$fi + 1]
                if ($filter -match '^\$(\w+)$') {
                    $m = [regex]::Match($cmd, '\$' + $Matches[1] + "\s*=\s*'((?:[^']|'')*)'")
                    if (-not $m.Success) { return @{ keys = @(); error = "filter $filter is not assigned a literal in the command" } }
                    $filter = $m.Groups[1].Value.Replace("''", "'")
                }
            }
            # Two listings of the same build and filter: dotnet test --list-tests has one entry per test result the leg
            # reports (a data row is its own entry, under its display name), which is what is counted (vstest /ListTests
            # rejects a filter); /ListFullyQualifiedTests has one namespace.class.method per test method, which names an
            # entry whose display name is its method's.
            $lf = @(if ($filter) { '--filter'; $filter })
            # dotnet writes UTF-8; read with the console's OEM code page, an em dash in a display name became "ΓÇö" and
            # matched no result (run-G17-7)
            $enc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try { $o = @(& dotnet test $proj --no-build --list-tests @lf 2>&1 | ForEach-Object { "$_" }) } finally { [Console]::OutputEncoding = $enc }
            if ($LASTEXITCODE -ne 0) { return @{ keys = @(); error = "dotnet test --list-tests exit $LASTEXITCODE $(@($o) | Select-Object -Last 1)" } }
            $at = [array]::FindIndex([string[]]$o, [Predicate[string]] { param($l) $l -match 'Tests are available' })
            if ($at -lt 0) { return @{ keys = @(); error = "dotnet test --list-tests printed no test list ($(@($o) | Select-Object -Last 1))" } }
            # an entry starts with four spaces; a display name holding a line break goes on over the lines that do not. A
            # data row's own text can hold lines indented four spaces too (a PowerShell script argument), so such a line
            # also goes on the entry before it when the two together still begin a display name the leg reported; read as
            # entries of their own, they were 699 tests that never existed, all "not run" (run-G17-7)
            $entries = [Collections.Generic.List[string]]::new()
            foreach ($l in @($o | Select-Object -Skip ($at + 1))) {
                $last = $entries.Count - 1
                if ($l -match '^    \S' -and -not ($last -ge 0 -and (Test-KeyPrefix $Reported (ConvertTo-DisplayKey "$($entries[$last]) $l")))) { $entries.Add($l.Substring(4)) }
                elseif ($last -ge 0 -and $l) { $entries[$last] += "`n$l" }
            }
            $entries = @($entries | ForEach-Object { ConvertTo-DisplayKey $_ })
            $f = @(if ($filter) { "/TestCaseFilter:$filter" })
            $list = Join-Path ([IO.Path]::GetTempPath()) "discover-$([guid]::NewGuid().ToString('N')).txt"
            $o = @(& dotnet vstest $dll.FullName /ListFullyQualifiedTests "/ListTestsTargetPath:$list" @f 2>&1)
            if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $list)) { return @{ keys = @(); error = "dotnet vstest /ListFullyQualifiedTests exit $LASTEXITCODE $((@($o) | Select-Object -Last 1))" } }
            $fqns = @(Get-Content -LiteralPath $list | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim().Replace('+', '.') })
            Remove-Item -LiteralPath $list -Force -ErrorAction SilentlyContinue
            return @{ keys = $entries; fqns = $fqns; error = '' }
        }
        if ($leg['kind'] -eq 'playwright') {
            $w = @(Get-CommandWords $cmd 'playwright test')
            $a = [Collections.Generic.List[string]]::new(); foreach ($x in 'playwright', 'test') { $a.Add($x) }
            for ($i = 0; $i -lt $w.Count; $i++) {
                if ($w[$i] -in '--grep', '-g', '--grep-invert', '--project') { if ($i + 1 -lt $w.Count) { $a.Add($w[$i]); $a.Add($w[$i + 1]); $i++ } }
                elseif ($w[$i] -match '^--(grep|grep-invert|project)=') { $a.Add($w[$i]) }
                elseif (-not $w[$i].StartsWith('-')) { $a.Add($w[$i]) }
            }
            $a.Add('--list'); $a.Add('--reporter=json')
            $saved = $env:PLAYWRIGHT_JSON_OUTPUT_NAME; $env:PLAYWRIGHT_JSON_OUTPUT_NAME = $null
            Push-Location -LiteralPath $proj
            # npx.cmd, not npx.ps1: the PowerShell shim would run under this script's preferences
            $enc = [Console]::OutputEncoding; [Console]::OutputEncoding = [Text.Encoding]::UTF8
            try { $o = @(& npx.cmd @a 2>$null) } finally { Pop-Location; $env:PLAYWRIGHT_JSON_OUTPUT_NAME = $saved; [Console]::OutputEncoding = $enc }
            $text = $o -join "`n"; $at = $text.IndexOf('{')
            if ($at -lt 0) { return @{ keys = @(); error = "playwright --list wrote no json (exit $LASTEXITCODE)" } }
            $j = $text.Substring($at) | ConvertFrom-Json -AsHashtable -Depth 60
            $keys = @((Get-PlaywrightRows $j $leg ([string]$leg['name'])) | ForEach-Object { "$($_.test)|$($_.pwProject)|$($_.file)" })
            return @{ keys = $keys; error = '' }
        }
    } catch { return @{ keys = @(); error = ("$_" -split "`n")[0] } }
    @{ keys = @(); error = "kind $($leg['kind']) is not discoverable" }
}
# A Tier 2 run's legs are discovered; a retest's are not (its legs are filtered re-runs, counted against their base run).
$discover = $Step -eq 'leg' -and [string]$rec['tier'] -eq '2' -and $snap -and (Test-Path -LiteralPath $snap)
$discovered = [ordered]@{}
$discoveryFailed = [Collections.Generic.List[string]]::new()
$notDiscovered = [Collections.Generic.List[string]]::new()
$runDef = if ($discover -and $rec['group']) { Read-JsonFile (Join-Path $P.Suites "$($rec['group']).run.json") } else { $null }
# Adds a 'not-run' row for every test the leg's build holds that the leg reported no result for.
function Add-NotRunRows($leg, [string] $name, [int] $from) {
    if (-not $discover -or $leg['kind'] -notin 'dotnet', 'playwright') { return }
    # A leg whose command runs no discoverable test project (a stand-in runner) says "discover": false; it is named on the
    # NOT-DISCOVERED line, so a total without it is never silent.
    # The flag is the run definition's (<group>.run.json): the run record's leg rows do not carry it.
    $defLeg = @(@(if ($runDef) { $runDef['legs'] }) | Where-Object { $_ -and [string]$_['name'] -eq $name }) | Select-Object -First 1
    if (($leg.Contains('discover') -and $leg['discover'] -eq $false) -or ($defLeg -and $defLeg.Contains('discover') -and $defLeg['discover'] -eq $false)) { $notDiscovered.Add($name); return }
    # Multiset difference: each reported result takes one discovered entry with its key (a playwright test+project+file,
    # a dotnet display name); the entries left over are the leg's tests that reported nothing.
    $have = [Collections.Generic.Dictionary[string, int]]::new([StringComparer]::Ordinal)
    $reportedFqn = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    for ($i = $from; $i -lt $rows.Count; $i++) {
        $r = $rows[$i]
        if (([string]$r.test) -match '^(leg|discover):') { continue }
        $k = if ($leg['kind'] -eq 'playwright') { "$($r.test)|$($r.pwProject)|$($r.file)" } else { ConvertTo-DisplayKey ([string]$r['display']) }
        $have[$k] = 1 + $(if ($have.ContainsKey($k)) { $have[$k] } else { 0 })
        if ($r['fqn']) { [void]$reportedFqn.Add([string]$r['fqn']) }
    }
    [string[]] $sorted = @($have.Keys); [array]::Sort($sorted, [StringComparer]::Ordinal)
    $d = Get-DiscoveredTests $leg $sorted
    if ($d.error) {
        $discoveryFailed.Add("$name ($($d.error))")
        $rows.Add([ordered]@{ test = "discover:$name"; suite = $name; outcome = 'failed'; durationMs = 0; file = ''; project = [string]$leg['project']; head = $rec['head'] })
        return
    }
    $discovered[$name] = $d.keys.Count
    # A not-run dotnet entry is named by its method's namespace.class.method when its display name (cut at '(') is the
    # name of exactly one method that reported nothing; otherwise by its display name.
    $byMethod = @{}
    foreach ($q in @($d['fqns'])) { if ($q -and -not $reportedFqn.Contains($q)) { $m = ($q -split '\.')[-1]; $byMethod[$m] = @($byMethod[$m]) + $q | Where-Object { $_ } } }
    # A data-driven method whose rows cannot be serialized at discovery (a [DataRow(typeof(...))]) is listed once under its
    # bare name and expands into its rows only when it runs: that entry is covered by any reported row of the method.
    $expanded = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($hk in $have.Keys) { $pi = $hk.IndexOf(' ('); if ($pi -gt 0) { [void]$expanded.Add($hk.Substring(0, $pi)) } }
    $unmatched = [Collections.Generic.List[string]]::new()
    foreach ($k in $d.keys) {
        if ($have.ContainsKey($k) -and $have[$k] -gt 0) { $have[$k]--; continue }
        $unmatched.Add($k)
    }
    # A data row whose argument holds a control character, a tab or a surrogate pair is spelled one way by the test list
    # and another by the trx, so its two keys never meet (19 rows in run-G17-7, every one of them run). A reported row
    # of the same method that took no discovered entry covers it, one for one.
    $spare = @{}
    if ($leg['kind'] -ne 'playwright') {
        foreach ($hk in $have.Keys) { if ($have[$hk] -gt 0) { $pi = $hk.IndexOf(' ('); if ($pi -gt 0) { $m = $hk.Substring(0, $pi); $spare[$m] = $have[$hk] + $(if ($spare.ContainsKey($m)) { $spare[$m] } else { 0 }) } } }
    }
    foreach ($k in $unmatched) {
        if ($leg['kind'] -ne 'playwright') {
            $pi = $k.IndexOf(' ('); if ($pi -gt 0) { $m = $k.Substring(0, $pi); if ($spare.ContainsKey($m) -and $spare[$m] -gt 0) { $spare[$m]--; continue } }
        }
        if ($leg['kind'] -ne 'playwright' -and $k.IndexOf('(') -lt 0 -and $expanded.Contains($k)) { continue }
        if ($leg['kind'] -eq 'playwright') {
            $p = $k.Split('|')
            $rows.Add([ordered]@{ test = $p[0]; suite = $name; outcome = 'not-run'; durationMs = 0; file = $p[2]; project = [string]$leg['project']; pwProject = $p[1]; head = $rec['head'] })
        } else {
            $cut = $k; $ci = $cut.IndexOf('('); if ($ci -ge 0) { $cut = $cut.Substring(0, $ci) }; $cut = $cut.Trim()
            $owner = @($byMethod[$cut] | Select-Object -Unique)
            $test = if ($owner.Count -eq 1) { $owner[0] } else { $k }
            $rows.Add([ordered]@{ test = $test; suite = $name; outcome = 'not-run'; durationMs = 0; file = ''; project = [string]$leg['project']; head = $rec['head']; display = $k })
        }
    }
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
        $rows.Add([ordered]@{ test = "leg:$name"; suite = $name; outcome = 'not-run'; durationMs = 0; file = ''; project = [string]$leg['project']; head = $rec['head'] })
        Add-NotRunRows $leg $name $rows.Count; continue
    }
    if ($leg['notMeasured']) {
        $rows.Add([ordered]@{ test = "leg:$name"; suite = $name; outcome = 'not-measured'; durationMs = 0; file = ''; project = [string]$leg['project']; head = $rec['head'] })
        Add-NotRunRows $leg $name $rows.Count; continue
    }
    if ($leg['kind'] -eq 'dotnet') {
        $proj = if ($leg['project']) { Join-Path $snap $leg['project'] } else { $snap }
        foreach ($trx in @(Get-ChildItem -LiteralPath $dir -Recurse -File -Filter '*.trx' -ErrorAction SilentlyContinue)) {
            [xml]$x = Get-Content -Raw -LiteralPath $trx.FullName
            # By local name: VSTest writes the TeamTest namespace, and a run whose filter matched nothing has no
            # <Results> (or an empty one), where dot access throws under StrictMode (final review I4).
            $defs = @{}; $methods = @{}
            foreach ($d in @($x.SelectNodes("//*[local-name()='UnitTest']"))) {
                $tm = $d.SelectSingleNode("*[local-name()='TestMethod']")
                $defs[$d.GetAttribute('id')] = if ($tm) { $tm.GetAttribute('className') } else { '' }
                $methods[$d.GetAttribute('id')] = if ($tm) { $tm.GetAttribute('name') } else { '' }
            }
            foreach ($r in @($x.SelectNodes("//*[local-name()='UnitTestResult']"))) {
                $cls = [string]$defs[$r.GetAttribute('testId')]; $cls = ($cls -split ',')[0].Trim()
                # fqn is the declaring method, the name discovery lists: a data row with a DisplayName reports that
                # display name as its testName, so the test column alone cannot be matched to the build's test list.
                $fqn = "$cls.$([string]$methods[$r.GetAttribute('testId')])".Replace('+', '.')
                $method = $r.GetAttribute('testName'); $i = $method.IndexOf('('); if ($i -ge 0) { $method = $method.Substring(0, $i) }; $method = $method.Trim()
                $test = if ($cls -and -not $method.StartsWith("$cls.")) { "$cls.$method" } else { $method }
                $ms = 0; try { $ms = [int]([TimeSpan]::Parse($r.GetAttribute('duration')).TotalMilliseconds) } catch { }
                $rows.Add([ordered]@{ test = $test; suite = $name; outcome = (ConvertTo-Outcome $r.GetAttribute('outcome')); durationMs = $ms; file = (Find-ClassFile $proj $cls); project = [string]$leg['project']; head = $rec['head']; fqn = $fqn; display = $r.GetAttribute('testName') })
            }
        }
    } elseif ($leg['kind'] -eq 'playwright') {
        $jf = Join-Path $dir 'results.json'
        if (Test-Path -LiteralPath $jf) {
            $j = Get-Content -Raw -LiteralPath $jf | ConvertFrom-Json -AsHashtable -Depth 60
            foreach ($r in (Get-PlaywrightRows $j $leg $name)) { $rows.Add($r) }
        }
    }
    if ($rows.Count -eq $before -and [int]$leg['exit'] -ne 0) {
        $rows.Add([ordered]@{ test = "leg:$name"; suite = $name; outcome = 'failed'; durationMs = 0; file = ''; project = [string]$leg['project']; head = $rec['head'] })
    }
    Add-NotRunRows $leg $name $before
}
foreach ($g in @(if ($Step -eq 'leg') { $rec['graders'] })) {
    if (-not $g) { continue }
    $rows.Add([ordered]@{ test = "grader:$($g['task'])"; suite = 'graders'; outcome = $(if ([int]$g['exit'] -eq 0) { 'passed' } else { 'failed' }); durationMs = 0; file = ''; project = ''; head = $rec['head']; task = [string]$g['task'] })
}
$outName = if ($Step -eq 'sweep') { "$Run.sweep.results.json" } else { "$Run.results.json" }
$doc = [ordered]@{ run = $Run; group = $rec['group']; head = $rec['head']; tests = @($rows) }
if ($discover) { $doc['discovered'] = $discovered }
Write-JsonFile (Join-Path $rd $outName) $doc
$c = @{ passed = 0; failed = 0; skipped = 0 }; foreach ($r in $rows) { $c[$r.outcome]++ }
"RESULTS $Run$(if ($Step -eq 'sweep') { ' sweep' }) passed $($c.passed) failed $($c.failed) skipped $($c.skipped)$(if ($c['not-measured']) { " not-measured $($c['not-measured'])" })$(if ($c['not-run']) { " not-run $($c['not-run'])" })"
$sk = @($rows | Where-Object { $_.outcome -eq 'skipped' } | Group-Object { $_.suite } | ForEach-Object { "$($_.Name) $($_.Count)" })
if ($sk.Count) { "NOT-RUN $Run$(if ($Step -eq 'sweep') { ' sweep' }) $($c.skipped) test(s) skipped, not passes: $($sk -join ', ')" }
$nr = @($rows | Where-Object { $_.outcome -eq 'not-run' -and -not ([string]$_.test).StartsWith('leg:') } | Group-Object { $_.suite } | ForEach-Object { "$($_.Name) $($_.Count)" })
if ($nr.Count) { "NOT-STARTED $Run $(($nr | ForEach-Object { [int]($_ -split ' ')[-1] } | Measure-Object -Sum).Sum) discovered test(s) with no result: $($nr -join ', ')" }
if ($discoveryFailed.Count) { "DISCOVERY-FAILED $Run $($discoveryFailed -join '; ')" }
if ($notDiscovered.Count) { "NOT-DISCOVERED $Run $($notDiscovered -join ', ') (discover: false): only what the leg reported is counted" }
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
