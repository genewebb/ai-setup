<#
.SYNOPSIS
    Evaluates every stop condition the loop can measure — iterations, wall-clock, consecutive failures, and the no-change thrash detector — from state.json plus PROGRESS.md.

.DESCRIPTION
    Used by the orchestrator-worker-loop skill's RUN step 3e. Call it after each PROGRESS entry
    is appended and BEFORE starting the next Orchestrator turn.

    WHY this exists:
      - Wall-clock caps were unenforceable because nothing recorded when the loop started.
        state.json's started_at (written by Initialize-Loop.ps1) makes "max-duration: 2h" real.
      - A loop can burn its whole budget re-planning without changing a single file. The
        no-change thrash detector stops after N consecutive iterations whose "Files changed"
        was "none".
      - Dollar caps are NOT enforced here. Most CLIs expose no per-subagent cost, so cost is
        advisory only; iterations and wall-clock are the reliable stops.

.PARAMETER RootPath
    Absolute path to the working directory.

.PARAMETER StatePath
    state.json path. Defaults to <RootPath>\.loop\state.json.

.PARAMETER ProgressPath
    PROGRESS.md path. Defaults to <RootPath>\.loop\PROGRESS.md, else <RootPath>\PROGRESS.md.

.PARAMETER MaxIterations
    Override state.json caps.max_iterations for this check.

.PARAMETER MaxDurationMinutes
    Override state.json caps.max_duration_minutes for this check.

.PARAMETER MaxConsecutiveFailures
    Override state.json caps.max_consecutive_failures for this check.

.PARAMETER MaxNoChangeIterations
    Override state.json caps.max_no_change_iterations for this check.

.PARAMETER Format
    'text' (default) or 'json'.

.EXAMPLE
    pwsh -File Test-Budget.ps1 -RootPath <repo> -Format json

.OUTPUTS
    JSON: { "stop": bool, "reason": "<slug|null>", "detail": "...",
            "iterations": N, "elapsed_minutes": N, "consecutive_failures": N,
            "no_change_streak": N, "caps": {...} }
    Reason slugs: max-iterations-hit | max-duration-hit | max-consecutive-failures-hit |
                  no-change-thrash

.NOTES
    Exit codes: 0 = continue, 10 = stop (reason in output), 2 = script error.
    Exit 10 rather than 1 so a stop is never confused with a script failure.
#>
[CmdletBinding()]
param(
    # Position 0 declared so every other parameter is name-only.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [string]$StatePath,

    [string]$ProgressPath,

    [int]$MaxIterations = 0,

    [int]$MaxDurationMinutes = 0,

    [int]$MaxConsecutiveFailures = 0,

    [int]$MaxNoChangeIterations = 0,

    [ValidateSet('text', 'json')]
    [string]$Format = 'text'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LoopCommon.ps1"

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-LoopError "RootPath not found: $RootPath"
    exit 2
}
$RootPath = (Get-Item -LiteralPath $RootPath).FullName.TrimEnd('\', '/')
$loopDir = Join-Path $RootPath '.loop'

if (-not $StatePath)    { $StatePath = Join-Path $loopDir 'state.json' }
if (-not $ProgressPath) {
    $inLoop = Join-Path $loopDir 'PROGRESS.md'
    $ProgressPath = if (Test-Path -LiteralPath $inLoop) { $inLoop } else { Join-Path $RootPath 'PROGRESS.md' }
}

$state = Read-LoopJson -Path $StatePath
if (-not $state) {
    Write-LoopError "state.json not found or unreadable at $StatePath - run Initialize-Loop.ps1 first (it records started_at, without which wall-clock caps cannot be enforced)."
    exit 2
}

$stateProps = $state.PSObject.Properties.Name

function Resolve-Cap {
    param([int]$Override, [string]$Key, [int]$Default)
    if ($Override -gt 0) { return $Override }
    if (($stateProps -contains 'caps') -and $state.caps) {
        if ($state.caps.PSObject.Properties.Name -contains $Key) {
            $v = $state.caps.$Key
            if ($null -ne $v -and [int]$v -gt 0) { return [int]$v }
        }
    }
    return $Default
}

$capIterations = Resolve-Cap -Override $MaxIterations          -Key 'max_iterations'           -Default 10
$capMinutes    = Resolve-Cap -Override $MaxDurationMinutes     -Key 'max_duration_minutes'     -Default 120
$capFailures   = Resolve-Cap -Override $MaxConsecutiveFailures -Key 'max_consecutive_failures' -Default 3
$capNoChange   = Resolve-Cap -Override $MaxNoChangeIterations  -Key 'max_no_change_iterations' -Default 2

# --- Elapsed wall-clock ---
$elapsedMinutes = 0
if (($stateProps -contains 'started_at') -and $state.started_at) {
    try {
        $started = [datetime]::Parse(
            $state.started_at,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [System.Globalization.DateTimeStyles]::AdjustToUniversal
        )
        $elapsedMinutes = [math]::Round(((Get-Date).ToUniversalTime() - $started).TotalMinutes, 1)
    } catch {
        Write-Warning "Could not parse started_at '$($state.started_at)' - wall-clock cap not enforced this check."
    }
}

# --- Parse PROGRESS.md entries (oldest first) ---
$iterations = 0
$results = New-Object System.Collections.ArrayList      # 'pass' | 'fail' | 'partial' | 'unknown'
$changedFlags = New-Object System.Collections.ArrayList # $true if files changed

if (Test-Path -LiteralPath $ProgressPath) {
    $lines = Get-Content -LiteralPath $ProgressPath
    $currentResult = $null
    $currentChanged = $false

    foreach ($line in $lines) {
        if ($line -match '^##\s+Iteration\s+(\d+)') {
            if ($null -ne $currentResult) {
                [void]$results.Add($currentResult)
                [void]$changedFlags.Add([bool]$currentChanged)
            }
            $iterations++
            $currentResult = 'unknown'
            $currentChanged = $false
            continue
        }
        if ($line -match '^\*\*Result\*\*:\s*(pass|fail|partial)') {
            $currentResult = $Matches[1].ToLowerInvariant()
            continue
        }
        if ($line -match '^\*\*Files changed\*\*:\s*(.*)$') {
            $val = $Matches[1].Trim()
            $currentChanged = -not ([string]::IsNullOrWhiteSpace($val) -or $val -ieq 'none' -or $val -ieq '(none)')
            continue
        }
    }
    if ($null -ne $currentResult) {
        [void]$results.Add($currentResult)
        [void]$changedFlags.Add([bool]$currentChanged)
    }
}

# --- Streaks (counted from the newest entry backwards) ---
$consecutiveFailures = 0
for ($i = $results.Count - 1; $i -ge 0; $i--) {
    if ($results[$i] -eq 'fail') { $consecutiveFailures++ } else { break }
}

$noChangeStreak = 0
for ($i = $changedFlags.Count - 1; $i -ge 0; $i--) {
    if (-not $changedFlags[$i]) { $noChangeStreak++ } else { break }
}

# --- Decide ---
$stop = $false
$reason = $null
$detail = 'All measurable caps within limits.'

if ($iterations -ge $capIterations) {
    $stop = $true; $reason = 'max-iterations-hit'
    $detail = "$iterations iteration(s) recorded, cap is $capIterations."
} elseif ($capMinutes -gt 0 -and $elapsedMinutes -ge $capMinutes) {
    $stop = $true; $reason = 'max-duration-hit'
    $detail = "$elapsedMinutes min elapsed, cap is $capMinutes min."
} elseif ($consecutiveFailures -ge $capFailures) {
    $stop = $true; $reason = 'max-consecutive-failures-hit'
    $detail = "$consecutiveFailures consecutive failure(s), cap is $capFailures."
} elseif ($noChangeStreak -ge $capNoChange) {
    $stop = $true; $reason = 'no-change-thrash'
    $detail = "$noChangeStreak consecutive iteration(s) changed no files (cap $capNoChange). The plan is thrashing - re-scope or stop."
}

$report = [ordered]@{
    stop                 = $stop
    reason               = $reason
    detail               = $detail
    iterations           = $iterations
    elapsed_minutes      = $elapsedMinutes
    consecutive_failures = $consecutiveFailures
    no_change_streak     = $noChangeStreak
    caps                 = [ordered]@{
        max_iterations           = $capIterations
        max_duration_minutes     = $capMinutes
        max_consecutive_failures = $capFailures
        max_no_change_iterations = $capNoChange
    }
    cost_note            = 'Dollar caps are advisory only - most CLIs do not expose per-subagent cost.'
}

if ($Format -eq 'json') {
    $report | ConvertTo-Json -Depth 4
} else {
    Write-Host ("Iterations: {0}/{1}   Elapsed: {2}/{3} min   Consecutive fails: {4}/{5}   No-change streak: {6}/{7}" -f `
        $iterations, $capIterations, $elapsedMinutes, $capMinutes, $consecutiveFailures, $capFailures, $noChangeStreak, $capNoChange)
    if ($stop) {
        Write-Host ("[STOP] {0} - {1}" -f $reason, $detail) -ForegroundColor Yellow
    } else {
        Write-Host "[CONTINUE] No stop condition met." -ForegroundColor Green
    }
}

if ($stop) { exit 10 } else { exit 0 }
