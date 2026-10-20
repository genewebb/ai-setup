# Runs the legs of one Tier 2 run (started by Start-SuiteRun.ps1, normally detached) in its snapshot, in order, never
# in parallel: setup steps, then each leg (no graders: owner ruling IN-20261005230119-9a3d). Every command goes through
# Invoke-IntegratorRun.ps1, which beats integrator.lock while it runs. Then it exports the per-test results
# (Export-SuiteResults.ps1), re-runs the failed set once on the SAME snapshot (Invoke-Retest.ps1 -Mode flaky: a test
# that passes there is a flaky candidate, not a failure), attributes what is left (Register-SuiteFailures.ps1) and runs
# the after steps last.
#   Invoke-SuiteLegs.ps1 -Repo <repo> -Session <id> -Run <run>
# The run record (.streams\suites\runs\<run>.json) gets each leg's exit code and log, and ends 'done' (every leg ran;
# the results say what passed) or 'lock-lost' (another session took the integrator lock: the run stops there).
# A setup step that fails stops the run as 'setup-failed': no leg can be trusted on a tree that did not build.
# The record carries this process's pid and start time, so a run whose process died (a reboot, a killed unit) is seen as
# abandoned instead of 'running' for good (lib\Suites.ps1 Test-SuiteRunAlive). Graders beat the integrator lock. A
# record reads screen = pending from the end of the legs until the flaky screen returns, and Register-SuiteFailures.ps1 refuses
# to attribute while it does (SCREEN-PENDING; kit item IN-20261019153055-2c27). A
# throw in the export, flaky screen or attribution is recorded as attributionError on the record (the close rule then
# reads NOT-ATTRIBUTED and the integrator sees why) instead of killing the process silently. A run started by the
# nightly task (session suite-nightly) hands the integrator lock back when it ends.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [string] $Run
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
. "$PSScriptRoot\lib\Activation.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$recPath = Join-Path (Get-SuiteRunsDir $P) "$Run.json"
$rec = Read-JsonFile $recPath
if (-not $rec) { "NO-RUN $Run"; exit 2 }
$def = Read-JsonFile (Join-Path $P.Suites "$($rec['group']).run.json")
Set-SuiteRunProcess $rec; Write-JsonFile $recPath $rec
$vars = @{ repo = $Repo; snapshot = $rec['snapshot']; runDir = $rec['runDir']; run = $Run; group = $rec['group'] }
$legs = [Collections.Generic.List[object]]::new()
$said = [Collections.Generic.List[string]]::new()
$status = 'done'
$step = {
    param($kind, $s)
    $name = [string]$s['name']
    $vars['leg'] = $name
    $wd = if ($s['workDir'] -eq 'repo') { $Repo } else { $rec['snapshot'] }
    $log = Join-Path $rec['runDir'] "$kind.$name.txt"
    # A perf leg runs only on a quiet host (lib\Suites.ps1 Wait-QuietHost, kit item IN-20261010212643-92b1); a host that
    # never quiets leaves it NOT-MEASURED: no result, never a failure.
    if ($kind -eq 'leg' -and (Test-PerfLeg $s)) {
        $q = Wait-QuietHost $P $Session
        if (-not $q.quiet) {
            $legs.Add([ordered]@{ step = $kind; name = $name; kind = [string]$s['kind']; project = [string]$s['project']; exit = 0; log = $log; command = ''; notMeasured = $true; reason = "host not quiet after $($q.waitedSeconds) s: $($q.why)" })
            $rec['legs'] = @($legs); Write-JsonFile $recPath $rec
            Add-Decision $P $Session "TIER2 $Run leg $name NOT-MEASURED (host not quiet after $($q.waitedSeconds) s: $($q.why))"
            $said.Add("NOT-MEASURED $name host not quiet after $($q.waitedSeconds) s: $($q.why)")
            return 'ok'
        }
        $said.Add("QUIET-HOST $name after $($q.waitedSeconds) s")
    }
    if ($s['kind'] -in @('dotnet', 'playwright')) { New-Item -ItemType Directory -Path (Join-Path $rec['runDir'] $name) -Force | Out-Null }
    $cmd = Expand-SuiteCommand ([string]$s['command']) $vars
    $out = @(& "$PSScriptRoot\Invoke-IntegratorRun.ps1" -Repo $Repo -Session $Session -Log $log -Command $cmd -WorkDir $wd)
    $code = $LASTEXITCODE
    $legs.Add([ordered]@{ step = $kind; name = $name; kind = [string]$s['kind']; project = [string]$s['project']; exit = $code; log = $log; command = $cmd })
    $rec['legs'] = @($legs); Write-JsonFile $recPath $rec
    if (($out -join ' ') -match 'LOCK-LOST') { return 'lock-lost' }
    if ($code -ne 0) { return 'failed' }
    'ok'
}
foreach ($s in @($def['setup'])) { if (-not $s) { continue }; $r = & $step 'setup' $s; if ($r -ne 'ok') { $status = $(if ($r -eq 'lock-lost') { 'lock-lost' } else { 'setup-failed' }); break } }
if ($status -eq 'done') {
    foreach ($s in @($def['legs'])) { if (-not $s) { continue }; $r = & $step 'leg' $s; if ($r -eq 'lock-lost') { $status = 'lock-lost'; break } }
}
# No grader pass (owner ruling IN-20261005230119-9a3d, 2026-10-05): a Tier 2 run is the test suites only. Graders run at
# integration time (Integrate-Patch.ps1); at close they cost G3 run 1 7 h 07 m of 10 h, and 67 of its 71 red graders were
# drift, not regressions. A run definition's "graders" key is ignored.
$rec['status'] = $status; $rec['endedAt'] = Get-Now; if ($status -eq 'done') { $rec['screen'] = 'pending' }; Write-JsonFile $recPath $rec
$said
if ($status -eq 'done') {
    try {
        & "$PSScriptRoot\Export-SuiteResults.ps1" -Repo $Repo -Run $Run | ForEach-Object { $_ }
        & "$PSScriptRoot\Invoke-Retest.ps1" -Repo $Repo -Session $Session -Run $Run -Mode flaky | ForEach-Object { $_ }
        $rec = Read-JsonFile $recPath; $rec['screen'] = 'done'; Write-JsonFile $recPath $rec
        & "$PSScriptRoot\Register-SuiteFailures.ps1" -Repo $Repo -Session $Session -Run $Run | ForEach-Object { $_ }
    } catch {
        $rec = Read-JsonFile $recPath; $rec['attributionError'] = ("$_" -split "`n")[0]; Write-JsonFile $recPath $rec
        Add-Decision $P $Session "TIER2 $Run attribution failed: $($rec['attributionError'])"
        "ATTRIBUTION-ERROR $Run $($rec['attributionError'])"
    }
}
# The after steps run last, behind the flaky screen: that re-run reuses this snapshot, so it must still find the build
# the legs ran against. An after step that redeploys web from main ran before it, so the re-run tested main's build
# while its record named this snapshot (kit item IN-20261011022936-074c). Export and attribution write the record, so
# it is read again first.
if ($status -ne 'lock-lost') {
    $rec = Read-JsonFile $recPath
    foreach ($s in @($def['after'])) { if (-not $s) { continue }; [void](& $step 'after' $s) }
}
Add-Decision $P $Session "TIER2 $Run ended $status"
if ($Session -eq 'suite-nightly' -and (Exit-IntegratorLock $P $Session)) { "LOCK-RELEASED $Session" }
"RUN-ENDED $Run $status"
exit 0
