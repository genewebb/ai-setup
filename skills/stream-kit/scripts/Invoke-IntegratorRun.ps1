# Runs one long integrator command (a step-B build or suite) in a child process and beats .streams\integrator.lock
# every 30 seconds (STREAM_BEAT_SECONDS overrides) while it runs, the way Invoke-Grader.ps1 -BeatSession does for a
# grader. A step-B suite takes 1.5-2 h (G1 Tests.Unit alone took 24 min), and nothing beat the lock in that time: the
# watchdog broke 4599ecab's lock at 2026-10-02T01:35:38Z and 02:13:40Z mid-run, and freed the G2.T90 integration row as
# an orphan (kit items IN-20261002014307-9bf2, IN-20261002020026-2168).
#   Invoke-IntegratorRun.ps1 -Repo <repo> -Session <integrator> -Log .streams\logs\G2.suites.1.unit.txt -Command 'dotnet test tests\Tests.Unit'
# Output (stdout and stderr) goes to -Log, written as it runs and read after completion. Prints one line,
# "RUN exit <code> log <log>", and exits with the command's code. LOCK-LOST, exit 5, before starting when another
# session holds the lock; a lock that is simply gone is retaken and noted, as Integrate-Patch.ps1 does.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [string] $Log,
    [Parameter(Mandatory)] [string] $Command,
    # The folder the command runs in. A step-B suite runs in its New-SuiteSnapshot.ps1 tree, never in the main tree.
    [string] $WorkDir = ''
)
. "$PSScriptRoot\lib\Streams.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$lockState = Assert-IntegratorLock $P $Session
if ($lockState -eq 'lost') { "LOCK-LOST integrator lock is held by $(Get-IntegratorLockHolder $P)"; exit 5 }
if ($lockState -eq 'retaken') { Add-Decision $P $Session 'integrator lock was gone (broken under a live integrator); retaken before a long run' }
if (-not [IO.Path]::IsPathRooted($Log)) { $Log = Join-Path $Repo $Log }
$dir = Split-Path $Log
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
$err = "$Log.err"
if (-not $WorkDir) { $WorkDir = $Repo }
if (-not (Test-Path -LiteralPath $WorkDir -PathType Container)) { "REFUSED -WorkDir $WorkDir is not a folder"; exit 2 }
$proc = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-Command', $Command) -WorkingDirectory $WorkDir -PassThru -NoNewWindow -RedirectStandardOutput $Log -RedirectStandardError $err
$every = if ($env:STREAM_BEAT_SECONDS) { [int]$env:STREAM_BEAT_SECONDS } else { 30 }
[void](Update-IntegratorBeat $P $Session)
while (-not $proc.HasExited) {
    if ($proc.WaitForExit($every * 1000)) { break }
    [void](Update-IntegratorBeat $P $Session)
}
$proc.WaitForExit()
$code = $proc.ExitCode
[void](Update-IntegratorBeat $P $Session)
# The child's redirect handles can still be closing when it reports its exit (kit item IN-20261004143050-5968).
if ((Test-Path $err) -and (Get-Item $err).Length -gt 0) { Invoke-IoRetry { [IO.File]::AppendAllText($Log, [IO.File]::ReadAllText($err) + [Environment]::NewLine) } }
if (Test-Path $err) { try { Invoke-IoRetry { [IO.File]::Delete($err) } } catch { } }
"RUN exit $code log $Log"
exit $code
