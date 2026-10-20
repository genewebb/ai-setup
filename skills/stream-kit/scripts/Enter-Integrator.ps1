# One integrator per repo. Takes or refreshes .streams\integrator.lock for this session.
# exit 0 = this session is the integrator (lock taken, taken over from a stale holder, or refreshed)
# exit 5 = another live integrator holds it; this session only prints status
# exit 6 = REFUSED-DISK: no lock is taken while the repo drive is under the 5 GB claim floor (a session that already
#          holds the lock still refreshes it, so an integrate in flight is never cut off by this check)
# A lock whose holder still owns a LIVE suite run (a 'running' record of that session whose pid lives) is never taken
# over, however old its beat: run-G13-3 went lock-lost at its last leg when a restarted integrator took the lock from it
# (kit item IN-20261020115130-5b6f). Exit 5, "HELD by <s> (suite run <id> pid <n> live)".
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$now = Get-Now
$l = $null
if (Test-Path $P.IntLock) {
    $l = Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String
    $age = ((Get-Date).ToUniversalTime() - [datetime]::Parse($l.beat, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes
    if ($l.session -eq $Session) { $l.beat = $now; Write-AtomicText $P.IntLock ($l | ConvertTo-Json); "INTEGRATOR $Session (refreshed)"; exit 0 }
    if ($age -lt $script:IntegratorLockMinutes) { "HELD by $($l.session), beat $([int]$age) min ago"; exit 5 }
    $liveRun = @(Get-SuiteRunRecords $P | Where-Object { [string]$_['session'] -eq [string]$l.session -and (Test-SuiteRunAlive $_) }) | Select-Object -First 1
    if ($liveRun) { "HELD by $($l.session) (suite run $($liveRun['id']) pid $($liveRun['pid']) live), beat $([int]$age) min ago"; exit 5 }
}
# The integrator applies patches and runs graders and suites in the main tree, so the repo drive is the one that must
# have room (owner ruling IN-20261001160218-2d56; lib\Streams.ps1 Get-ClaimDiskRefusal). Checked before a takeover is
# recorded, so a refused session leaves no decision line claiming a lock it never took.
$diskWhy = Get-ClaimDiskRefusal (Resolve-Path $Repo).Path 'integrate'
if ($diskWhy) { $diskWhy; exit 6 }
if ($l) { Add-Decision $P $Session "took over stale integrator lock from $($l.session) (beat $([int]$age) min)" }
Write-AtomicText $P.IntLock (@{ session = $Session; at = $now; beat = $now } | ConvertTo-Json)
"INTEGRATOR $Session"
# An explicit 0, as in Claim-Task.ps1: without it a lock taken after a refusal left $LASTEXITCODE at 6 for the caller.
exit 0
