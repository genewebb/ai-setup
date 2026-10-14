# Starts one Tier 2 (full) suite run for a group (2026-10-05 priority-focus-design 3.3). Script only, no model tokens.
#   Start-SuiteRun.ps1 -Repo <repo> -Session <id> [-Group <G>] -Reason nightly|complete|manual [-Wait]
# -Group defaults to the focus group. Reads the run definition .streams\suites\<G>.run.json (written by the integrator
# once per group; shape below), takes a snapshot (New-SuiteSnapshot.ps1), records .streams\suites\runs\<run>.json and
# starts Invoke-SuiteLegs.ps1 DETACHED (or inline with -Wait), so a 1.5-2 h run outlives the session that started it.
# Why: a group close used to run every suite after every fix round, up to three full runs of 1.5-2 h, and the integrator
# spent a unit every 10 minutes on a clock check ($0.41-0.44 each, about $60 a day). The nightly is now a Windows
# scheduled task (Register-NightlySuite.ps1) and failures are retested alone (Invoke-Retest.ps1).
# Rules:
#  - One run at a time per repo: a record still 'running' refuses a new run (RUN-BUSY, exit 4), a nightly included,
#    while its process lives; a record whose process is gone is marked 'abandoned' and printed (ABANDONED <run>).
#  - One nightly per 01:00 window: a nightly whose window (the local date of start time minus 1 h... see $window) already
#    holds a nightly prints SKIP-NIGHTLY and exits 0.
#  - The integrator lock: a session other than the holder never runs. A NIGHTLY that finds the lock held by a live
#    integrator files one stream-integrate inbox item asking it to start the run under its own lock (YIELDED, exit 3);
#    complete and manual runs print LOCK-HELD, exit 5. A free (or stale) lock is taken with Enter-Integrator.ps1.
#  - Reason complete moves the group's integration task to building (the watchdog and Get-TaskSince key off it).
# Run definition (.streams\suites\<G>.run.json):
#   { "group": "G4", "copyIgnored": [".env", ".env.local", "tests\\Tests.E2E\\.auth"],
#     "setup": [ { "name": "npm", "command": "npm ci --prefix tests\\Tests.E2E" }, { "name": "build", "command": "dotnet build" } ],
#     "legs":  [ { "name": "Tests.Unit", "kind": "dotnet", "project": "tests\\Tests.Unit",
#                  "command": "dotnet test tests\\Tests.Unit --no-build --logger trx --results-directory {runDir}\\Tests.Unit" },
#                { "name": "Playwright", "kind": "playwright", "project": "tests\\Tests.E2E",
#                  "command": "$env:PLAYWRIGHT_JSON_OUTPUT_NAME='{runDir}\\Playwright\\results.json'; npx --prefix tests\\Tests.E2E playwright test --reporter=json,line" } ],
#     "after": [ { "name": "web", "command": "docker compose -f compose.yaml up -d --build --wait web", "workDir": "repo" } ] }
#   Placeholders: {repo} {snapshot} {runDir} {run} {group}. dotnet legs write trx under {runDir}\<leg>\, Playwright legs
#   a json report; Export-SuiteResults.ps1 reads both.
# Prints RUN-STARTED <run> snapshot <path> head <sha>.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [string] $Group = '',
    [Parameter(Mandatory)] [ValidateSet('nightly', 'complete', 'manual')] [string] $Reason,
    [switch] $Wait
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$doc = Read-Tasks $P
if (-not $Group) { $Group = Get-FocusGroup $doc }
if (-not $Group) { 'NO-FOCUS every group is closed'; exit 0 }
$defPath = Join-Path $P.Suites "$Group.run.json"
$def = Read-JsonFile $defPath
if (-not $def) { "NO-RUN-DEFINITION $defPath (the integrator writes it once per group, stream-integrate step B)"; exit 2 }

# A 'running' record whose process is gone is marked abandoned first (lib\Suites.ps1 Resolve-RunningSuiteRuns), so a
# reboot or a killed unit never blocks every later run.
$busy = @(Resolve-RunningSuiteRuns $P $Session)
@($busy | Where-Object { $_ -is [string] })
$busy = @($busy | Where-Object { $_ -isnot [string] })
if ($busy.Count) { "RUN-BUSY $($busy[-1]['id']) is still running (started $($busy[-1]['startedAt']))"; exit 4 }
$runs = Get-SuiteRunRecords $P
# The 01:00 window: a nightly started between 01:00 today and 00:59 tomorrow (local) belongs to today's window.
$window = (Get-Date).AddHours(-1).ToString('yyyy-MM-dd')
if ($Reason -eq 'nightly' -and @($runs | Where-Object { $_['reason'] -eq 'nightly' -and $_['window'] -eq $window }).Count) { "SKIP-NIGHTLY a nightly already ran in the $window window"; exit 0 }

& "$PSScriptRoot\Enter-Integrator.ps1" -Repo $Repo -Session $Session | Out-Null
if ($LASTEXITCODE -eq 5) {
    $holder = Get-IntegratorLockHolder $P
    if ($Reason -ne 'nightly') { "LOCK-HELD by $holder; only the lock holder starts a run"; exit 5 }
    $ask = "Start the nightly Tier 2 run for ${Group}: Start-SuiteRun.ps1 -Repo <repo> -Session <you> -Group $Group -Reason nightly (the scheduled task found your lock live)"
    $open = @(Read-InboxItems (Get-InboxPath $P 'stream-integrate') | Where-Object { (Test-InboxOpen $_ 'stream-integrate') -and $_.ask -like 'Start the nightly Tier 2 run*' })
    if (-not $open.Count) { & "$PSScriptRoot\Send-InboxItem.ps1" -Repo $Repo -To stream-integrate -From $Session -Kind request -Ask $ask -Evidence "window $window" | Out-Null }
    "YIELDED integrator lock held by $holder; inbox item $(if ($open.Count) { 'already open' } else { 'filed' })"
    exit 3
}

$n = 1; $rd = Get-SuiteRunsDir $P
while (Test-Path (Join-Path $rd "run-$Group-$n.json")) { $n++ }
$id = "run-$Group-$n"
$runDir = Join-Path $rd $id; New-Item -ItemType Directory -Path $runDir -Force | Out-Null
$snapOut = @(& "$PSScriptRoot\New-SuiteSnapshot.ps1" -Repo $Repo -Session $Session -Group $Group -Run $n -CopyIgnored @($def['copyIgnored'] | Where-Object { $_ }) -Log (Join-Path $runDir 'snapshot.txt'))
if ($LASTEXITCODE -eq 5) { "MAIN-GRADER-BUSY snapshot not taken; try again in a few minutes"; exit 5 }
if ($LASTEXITCODE) { "SNAPSHOT-FAILED exit $LASTEXITCODE`n$($snapOut -join "`n")"; exit 6 }
$snap = [string]($snapOut | Select-Object -Last 1)
$headLine = @($snapOut | Where-Object { $_ -match '^SNAPSHOT ' }) | Select-Object -First 1
$head = if ($headLine -match ' HEAD (\S+)') { $Matches[1] } else { '' }
$rec = [ordered]@{ id = $id; tier = '2'; group = $Group; reason = $Reason; window = $(if ($Reason -eq 'nightly') { $window } else { '' })
    session = $Session; startedAt = Get-Now; endedAt = $null; head = $head; snapshot = $snap; runDir = $runDir; status = 'running'; legs = @() }
Set-SuiteRunProcess $rec
Write-JsonFile (Join-Path $rd "$id.json") $rec
if ($Reason -eq 'complete') {
    $it = @($doc.tasks | Where-Object { [string]$_.group -eq $Group -and $_.kind -eq 'integration' -and $_.state -in @('ticketed', 'planned') } | Select-Object -First 1)
    if ($it.Count) { & "$PSScriptRoot\Update-Task.ps1" -Repo $Repo -Task $it[0].id -Role integrate -Session $Session -To building -Note "Tier 2 completion run $id" | Out-Null }
}
Add-Decision $P $Session "TIER2 $id started ($Reason) for $Group at $head in $snap"
"RUN-STARTED $id snapshot $snap head $head"
$legsArgs = @('-NoProfile', '-File', (Join-Path $PSScriptRoot 'Invoke-SuiteLegs.ps1'), '-Repo', $Repo, '-Session', $Session, '-Run', $id)
if ($Wait) { & pwsh @legsArgs; exit $LASTEXITCODE }
$child = Start-Process -FilePath 'pwsh' -ArgumentList $legsArgs -WindowStyle Hidden -PassThru
# The record names the detached process from here on (Invoke-SuiteLegs.ps1 writes its own pid again when it starts).
$r = Read-JsonFile (Join-Path $rd "$id.json"); if ($r -and $r['pid'] -eq $PID) { Set-SuiteRunProcess $r $child.Id; Write-JsonFile (Join-Path $rd "$id.json") $r }
exit 0
