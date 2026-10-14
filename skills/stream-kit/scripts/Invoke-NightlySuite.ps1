# The nightly Tier 2 run as the scheduled task starts it (Register-NightlySuite.ps1). Script only, no model tokens.
#   Invoke-NightlySuite.ps1 -Repo <repo>
# Runs Start-SuiteRun.ps1 -Repo <repo> -Session suite-nightly -Reason nightly -Wait and appends every output line, time
# stamped, to <repo>\.streams\logs\suite-nightly.txt. A file of its own because the task's command line cannot carry
# this inline: Task Scheduler starts pwsh through CreateProcess, whose argument parser ate the doubled quotes of the old
# one-line -Command, so every 01:00 run died on a ParserError before it wrote a log line (final review C1).
# Exits with Start-SuiteRun.ps1's exit code.
param([Parameter(Mandatory)] [string] $Repo)
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path $Repo).Path
$logDir = Join-Path $Repo '.streams\logs'
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
$log = Join-Path $logDir 'suite-nightly.txt'
$code = 0
try {
    & "$PSScriptRoot\Start-SuiteRun.ps1" -Repo $Repo -Session suite-nightly -Reason nightly -Wait *>&1 |
        ForEach-Object { [IO.File]::AppendAllText($log, "$((Get-Date).ToString('s')) $_`n", [Text.UTF8Encoding]::new($false)) }
    $code = $LASTEXITCODE
} catch {
    [IO.File]::AppendAllText($log, "$((Get-Date).ToString('s')) NIGHTLY-ERROR $(("$_" -split "`n")[0])`n", [Text.UTF8Encoding]::new($false))
    $code = 1
}
exit $code
