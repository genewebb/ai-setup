<#
.SYNOPSIS
    Runs the GOAL's "Done when" criteria commands, records exit codes to CRITERIA.json, and flags criteria that already pass at baseline. Run once with -Preflight BEFORE iteration 1, then every iteration.

.DESCRIPTION
    Two jobs:

    1. PREFLIGHT (run before iteration 1). Executes every criterion once and stores the result
       as its baseline. This catches, before a single token is spent:
         - Commands that don't run at all (typo, missing tool, wrong cwd)
         - Commands whose exit-code polarity is inverted. `rg -c 'pattern' src/` exits 1 when
           there are ZERO matches, so "zero occurrences remain" expressed as "exit 0" can never
           pass. Wrap those (see .EXAMPLE) so exit 0 means satisfied.
         - Criteria ALREADY satisfied at baseline (already_passing = true). Those are not
           acceptance criteria, they are no-ops — the loop would declare victory having done
           nothing. Fix the criterion before running.

    2. PER-ITERATION (gate 5 / gate 6 / stop-condition check). Re-runs the stored commands and
       records the latest result per criterion. Exit code tells the Verifier whether the GOAL is
       met, so the loop's stop condition is a measurement rather than a judgement call.

    Each command runs in a child `pwsh -NoProfile` with RootPath as cwd, so exit codes are
    captured cleanly and a criterion cannot pollute the caller's session.

.PARAMETER RootPath
    Absolute path to the working directory. Commands run with this as cwd.

.PARAMETER CriteriaFile
    PREFERRED for more than one criterion. JSON file holding an array of criteria, or an object
    with a "criteria" array. Each element: { "label": "...", "command": "...", "expect_exit": 0 }
    ("label" and "expect_exit" optional). A file sidesteps the quoting and array-binding traps of
    passing several shell commands as command-line arguments.

.PARAMETER Command
    One or more criterion commands. Required with -Preflight unless -CriteriaFile is used;
    ignored afterwards (the stored commands in CRITERIA.json are authoritative so the loop
    can't drift).

.PARAMETER Label
    Optional human labels, positionally matched to -Command. Defaults to the command text.

.PARAMETER ExpectExit
    Expected exit code for every criterion. Default 0.

.PARAMETER CriteriaPath
    Path to CRITERIA.json. Defaults to <RootPath>\.loop\CRITERIA.json, else <RootPath>\CRITERIA.json.

.PARAMETER Preflight
    Create/overwrite CRITERIA.json from -Command and record baseline results.

.PARAMETER Iteration
    Iteration number to stamp on this run's results. Ignored with -Preflight.

.PARAMETER TimeoutSeconds
    Per-criterion timeout. Default 900 (15 min). A criterion that hangs is a failed criterion.

.PARAMETER Format
    'text' (default) or 'json'.

.EXAMPLE
    # Preflight. Note the inverted wrapper for an "absence" criterion.
    pwsh -File Test-Criteria.ps1 -RootPath <repo> -Preflight -Command 'dotnet build --no-restore', 'rg -q "GetValue<" src/; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }'

.EXAMPLE
    pwsh -File Test-Criteria.ps1 -RootPath <repo> -Iteration 7 -Format json

.OUTPUTS
    CRITERIA.json:
    {
      "version": 1, "root": "<abs>", "preflight_at": "<ISO UTC>", "expect_exit": 0,
      "criteria": [ { "id": 1, "label": "...", "command": "...", "expect_exit": 0,
                      "baseline": { "exit": 1, "passed": false, "at": "<ISO UTC>", "already_passing": false },
                      "latest":   { "iteration": 7, "exit": 0, "passed": true, "at": "<ISO UTC>",
                                    "duration_s": 12.4, "output_tail": "..." } } ]
    }

.NOTES
    Exit codes: 0 = all criteria pass. 1 = at least one fails. 2 = script/config error.
    With -Preflight, exit 0 means every command RAN; inspect already_passing warnings regardless.
#>
[CmdletBinding()]
param(
    # Position 0 declared explicitly so every other parameter is name-only — otherwise a stray
    # array element under `pwsh -File` binds positionally to whatever comes next.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [string]$CriteriaFile,

    [string[]]$Command = @(),

    [string[]]$Label = @(),

    [int]$ExpectExit = 0,

    [string]$CriteriaPath,

    [switch]$Preflight,

    [int]$Iteration = 0,

    [int]$TimeoutSeconds = 900,

    [ValidateSet('text', 'json')]
    [string]$Format = 'text'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LoopCommon.ps1"

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-Error "RootPath not found: $RootPath"
    exit 2
}
$RootPath = (Get-Item -LiteralPath $RootPath).FullName.TrimEnd('\', '/')

if (-not $CriteriaPath) {
    $loopDir = Join-Path $RootPath '.loop'
    $CriteriaPath = if (Test-Path -LiteralPath $loopDir) {
        Join-Path $loopDir 'CRITERIA.json'
    } else {
        Join-Path $RootPath 'CRITERIA.json'
    }
}

function Invoke-Criterion {
    <#
        Run one criterion in a child pwsh with RootPath as cwd. Returns exit code, tail of
        combined output, and duration.
    #>
    param([string]$CommandText, [int]$TimeoutSec)

    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $started = Get-Date
    $exit = $null
    $timedOut = $false

    try {
        $proc = Start-Process -FilePath 'pwsh' `
            -ArgumentList @('-NoProfile', '-NonInteractive', '-Command', $CommandText) `
            -WorkingDirectory $RootPath -PassThru -WindowStyle Hidden `
            -RedirectStandardOutput $outFile -RedirectStandardError $errFile

        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $timedOut = $true
            try { $proc.Kill($true) } catch { }
            $proc.WaitForExit()
        }
        $exit = $proc.ExitCode
    } catch {
        Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue
        return [pscustomobject]@{ Exit = 127; Tail = "Failed to launch: $_"; Duration = 0.0; TimedOut = $false }
    }

    $duration = [math]::Round(((Get-Date) - $started).TotalSeconds, 1)
    $tailLines = @()
    foreach ($f in @($outFile, $errFile)) {
        try {
            $c = Get-Content -LiteralPath $f -ErrorAction Stop -Tail 12
            if ($c) { $tailLines += @($c) }
        } catch { }
    }
    Remove-Item $outFile, $errFile -Force -ErrorAction SilentlyContinue

    $tail = (@($tailLines) | Where-Object { $_ } | Select-Object -Last 12) -join "`n"
    if ($timedOut) {
        $tail = "TIMED OUT after ${TimeoutSec}s. " + $tail
        $exit = 124
    }

    return [pscustomobject]@{ Exit = $exit; Tail = $tail; Duration = $duration; TimedOut = $timedOut }
}

# --- Load or build the criteria set ---
if ($Preflight) {
    $spec = New-Object System.Collections.ArrayList   # entries: @{ command; label; expect }

    if ($CriteriaFile) {
        if (-not (Test-Path -LiteralPath $CriteriaFile)) {
            Write-LoopError "CriteriaFile not found: $CriteriaFile"
            exit 2
        }
        $parsed = Read-LoopJson -Path $CriteriaFile
        if (-not $parsed) {
            Write-LoopError "CriteriaFile is empty or not valid JSON: $CriteriaFile"
            exit 2
        }
        $items = if ($parsed -is [array]) { $parsed } elseif ($parsed.PSObject.Properties.Name -contains 'criteria') { @($parsed.criteria) } else { @($parsed) }
        foreach ($it in $items) {
            if (-not $it.command) {
                Write-LoopError "Every criterion in $CriteriaFile needs a 'command' field."
                exit 2
            }
            $exp = if (($it.PSObject.Properties.Name -contains 'expect_exit') -and $null -ne $it.expect_exit) { [int]$it.expect_exit } else { $ExpectExit }
            $lbl = if ($it.PSObject.Properties.Name -contains 'label' -and $it.label) { [string]$it.label } else { [string]$it.command }
            [void]$spec.Add(@{ command = [string]$it.command; label = $lbl; expect = $exp })
        }
    } else {
        $cmdList = @($Command | Where-Object { $_ })
        if ($cmdList.Count -eq 0) {
            Write-LoopError "-Preflight requires -CriteriaFile or at least one -Command."
            exit 2
        }
        for ($i = 0; $i -lt $cmdList.Count; $i++) {
            $lbl = if ($i -lt $Label.Count -and $Label[$i]) { $Label[$i] } else { $cmdList[$i] }
            [void]$spec.Add(@{ command = $cmdList[$i]; label = $lbl; expect = $ExpectExit })
        }
    }

    $criteria = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $spec.Count; $i++) {
        [void]$criteria.Add([pscustomobject][ordered]@{
            id          = ($i + 1)
            label       = $spec[$i].label
            command     = $spec[$i].command
            expect_exit = $spec[$i].expect
            baseline    = $null
            latest      = $null
        })
    }

    $doc = [pscustomobject][ordered]@{
        version      = 1
        root         = $RootPath
        preflight_at = Get-LoopUtcStamp
        expect_exit  = $ExpectExit
        criteria     = @($criteria)
    }
} else {
    $doc = Read-LoopJson -Path $CriteriaPath
    if (-not $doc -or -not $doc.criteria) {
        Write-LoopError "No usable CRITERIA.json at $CriteriaPath - run with -Preflight first."
        exit 2
    }
}

# --- Run every criterion ---
$results = New-Object System.Collections.ArrayList
$failCount = 0
$alreadyPassing = New-Object System.Collections.ArrayList

foreach ($c in $doc.criteria) {
    $expect = if ($null -ne $c.expect_exit) { [int]$c.expect_exit } else { $ExpectExit }
    $run = Invoke-Criterion -CommandText $c.command -TimeoutSec $TimeoutSeconds
    $passed = ($run.Exit -eq $expect)
    if (-not $passed) { $failCount++ }

    $entry = [ordered]@{
        exit        = $run.Exit
        passed      = $passed
        at          = Get-LoopUtcStamp
        duration_s  = $run.Duration
        output_tail = $run.Tail
    }

    if ($Preflight) {
        $entry['already_passing'] = $passed
        $c.baseline = [pscustomobject]$entry
        if ($passed) { [void]$alreadyPassing.Add($c.label) }
    } else {
        $entry['iteration'] = $Iteration
        $c.latest = [pscustomobject]$entry
    }

    [void]$results.Add([pscustomobject][ordered]@{
        id = $c.id; label = $c.label; exit = $run.Exit; passed = $passed; duration_s = $run.Duration
    })
}

Write-LoopJson -Object $doc -Path $CriteriaPath -Depth 8

# --- Report ---
if ($Format -eq 'json') {
    [ordered]@{
        mode            = if ($Preflight) { 'preflight' } else { 'iteration' }
        iteration       = $Iteration
        all_passed      = ($failCount -eq 0)
        failed_count    = $failCount
        already_passing = @($alreadyPassing)
        criteria_path   = $CriteriaPath
        results         = @($results)
    } | ConvertTo-Json -Depth 5
} else {
    $header = if ($Preflight) { 'Criteria preflight' } else { "Criteria check (iteration $Iteration)" }
    Write-Host $header
    foreach ($r in $results) {
        $tag = if ($r.passed) { '[PASS]' } else { '[FAIL]' }
        $color = if ($r.passed) { 'Green' } else { 'Red' }
        Write-Host ("  {0} exit={1,-4} {2,6}s  {3}" -f $tag, $r.exit, $r.duration_s, $r.label) -ForegroundColor $color
    }
    if ($Preflight) {
        if ($alreadyPassing.Count -gt 0) {
            Write-Host ""
            Write-Host ("WARNING: {0} criterion/criteria ALREADY pass at baseline:" -f $alreadyPassing.Count) -ForegroundColor Yellow
            $alreadyPassing | ForEach-Object { Write-Host ("  - {0}" -f $_) -ForegroundColor Yellow }
            Write-Host "Those are no-ops, not acceptance criteria. Either the criterion is wrong (check exit-code" -ForegroundColor Yellow
            Write-Host "polarity: rg exits 1 on zero matches) or the work is already done. Fix before running the loop." -ForegroundColor Yellow
        } else {
            Write-Host "All criteria currently FAIL at baseline - correct for a goal that has real work to do." -ForegroundColor DarkGreen
        }
    } else {
        Write-Host ("Result: {0}/{1} passing" -f ($results.Count - $failCount), $results.Count)
    }
    Write-Host ("Recorded to: {0}" -f $CriteriaPath) -ForegroundColor DarkGray
}

if ($Preflight) { exit 0 }
if ($failCount -eq 0) { exit 0 } else { exit 1 }
