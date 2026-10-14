<#
.SYNOPSIS
    One-command loop setup: creates .loop\, records started_at and caps in state.json, seeds PROGRESS.md and PLAN.md, captures the baseline, preflights the Done-when criteria, and prints the permission allow-list an unattended run needs.

.DESCRIPTION
    Run this once after GOAL.md is approved and BEFORE iteration 1. It replaces the old
    hand-rolled setup (create files, run Get-Baseline) and closes the gaps that setup left:

      - state.json records started_at, so wall-clock caps are enforceable (Test-Budget.ps1)
      - Criteria are preflighted, so an inverted exit-code criterion or an already-passing
        no-op criterion is caught before any tokens are spent (Test-Criteria.ps1 -Preflight)
      - Loop state lives in .loop\ instead of the repo root, so it never pollutes `git status`
        in a repo where commits are made by hand
      - Prints every command the loop will need permission to run, so an overnight run does not
        stall on the first approval prompt

.PARAMETER RootPath
    Absolute path to the target repo / working directory.

.PARAMETER GoalPath
    Path to the GOAL.md to use. Copied to .loop\GOAL.md (immutable for the run). If omitted and
    .loop\GOAL.md or <RootPath>\GOAL.md already exists, that file is used.

.PARAMETER GoalName
    Short slug recorded in state.json. Defaults to the GOAL frontmatter's goal-name, else the folder name.

.PARAMETER CriteriaFile
    PREFERRED for more than one criterion. Path to a JSON file holding either an array of
    criteria or an object with a "criteria" array:
      [ { "label": "build clean",  "command": "dotnet build --no-restore", "expect_exit": 0 },
        { "label": "no GetValue<", "command": "rg -q 'GetValue<' src/; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }" } ]
    A file avoids the quoting and array-binding traps of passing many commands on a command line.

.PARAMETER Criterion
    One or more "Done when" commands to preflight. Each must exit 0 IFF satisfied.
    For absence checks, invert explicitly:
      'rg -q "GetValue<" src/; if ($LASTEXITCODE -eq 1) { exit 0 } else { exit 1 }'
    NOTE: with `pwsh -File`, each array element is a separate token and can mis-bind. Either use
    -CriteriaFile, or invoke via `pwsh -Command "& '<script>' -Criterion @('a','b')"`.

.PARAMETER CriterionLabel
    Optional labels, positionally matched to -Criterion.

.PARAMETER Include
    Baseline include globs. Narrow to the GOAL's "Files in scope" on large repos.

.PARAMETER Exclude
    Extra baseline exclude globs.

.PARAMETER MaxIterations
    Iteration cap. Default 10.

.PARAMETER MaxDurationMinutes
    Wall-clock cap in minutes. Default 120.

.PARAMETER MaxConsecutiveFailures
    Consecutive-failure cap. Default 3.

.PARAMETER MaxNoChangeIterations
    Thrash detector: stop after this many consecutive iterations that changed no files. Default 2.

.PARAMETER MaxCostUsd
    Advisory only — recorded, never enforced (most CLIs expose no per-subagent cost).

.PARAMETER OrchestratorModel
    Concrete slug recorded for the report and auto-upgrade bookkeeping.

.PARAMETER ExecutorModel
    Concrete slug recorded for the report and auto-upgrade bookkeeping.

.PARAMETER VerifierMode
    'same-session' (default) or 'separate-agent'.

.PARAMETER Mode
    'dry-run' (default — one iteration then stop for review), 'full', or 'plan-only'.

.PARAMETER ExcludeLocally
    RECOMMENDED. Append '.loop/' to .git\info\exclude — a local-only, untracked ignore file. Nothing
    shows up in `git status`, nothing needs committing, and the user's repo is left exactly as found.
    This is the right default for a repo where the user hand-commits.

.PARAMETER AddGitIgnore
    Append '.loop/' to the repo's TRACKED .gitignore if not already ignored. Prefer -ExcludeLocally:
    this switch dirties a tracked file, so the user then has to commit a change the loop made on their
    behalf. Use it only when the ignore rule genuinely should be shared with the team.

.PARAMETER SkipPreflight
    Skip the criteria preflight (not recommended — it is the cheapest bug-catcher in the loop).

.EXAMPLE
    pwsh -File Initialize-Loop.ps1 -RootPath {ScratchRoot}\loop-test -GoalPath {ScratchRoot}\loop-test\GOAL.md -MaxIterations 5 -MaxDurationMinutes 30 -Mode dry-run -ExcludeLocally

.NOTES
    Exit codes: 0 = ready. 1 = ready but preflight raised warnings (already-passing criteria, or
    no criteria supplied) — read them before starting. 2 = setup error.
#>
[CmdletBinding()]
param(
    # Position 0 is declared explicitly so EVERY other parameter is name-only. Without this,
    # PowerShell assigns implicit positions in declaration order and a stray array element
    # (e.g. a second -Criterion value under `pwsh -File`) silently binds to -GoalPath.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [string]$GoalPath,

    [string]$GoalName,

    [string]$CriteriaFile,

    [string[]]$Criterion = @(),

    [string[]]$CriterionLabel = @(),

    [string[]]$Include = @('**/*'),

    [string[]]$Exclude = @(),

    [int]$MaxIterations = 10,

    [int]$MaxDurationMinutes = 120,

    [int]$MaxConsecutiveFailures = 3,

    [int]$MaxNoChangeIterations = 2,

    [double]$MaxCostUsd = 0,

    [string]$OrchestratorModel = '',

    [string]$ExecutorModel = '',

    [string]$VerifierMode = 'same-session',

    [ValidateSet('dry-run', 'full', 'plan-only')]
    [string]$Mode = 'dry-run',

    [switch]$ExcludeLocally,

    [switch]$AddGitIgnore,

    [switch]$SkipPreflight
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LoopCommon.ps1"

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-Error "RootPath not found: $RootPath"
    exit 2
}
$RootPath = (Get-Item -LiteralPath $RootPath).FullName.TrimEnd('\', '/')
$loopDir = Join-Path $RootPath '.loop'

if (-not (Test-Path -LiteralPath $loopDir)) {
    New-Item -ItemType Directory -Path $loopDir -Force | Out-Null
}

# --- Resolve and stage GOAL.md ---
$loopGoal = Join-Path $loopDir 'GOAL.md'
if ($GoalPath) {
    if (-not (Test-Path -LiteralPath $GoalPath)) {
        Write-Error "GoalPath not found: $GoalPath"
        exit 2
    }
    $resolvedGoal = (Get-Item -LiteralPath $GoalPath).FullName
    if ($resolvedGoal -ne $loopGoal) {
        Copy-Item -LiteralPath $resolvedGoal -Destination $loopGoal -Force
    }
} elseif (-not (Test-Path -LiteralPath $loopGoal)) {
    $rootGoal = Join-Path $RootPath 'GOAL.md'
    if (Test-Path -LiteralPath $rootGoal) {
        Move-Item -LiteralPath $rootGoal -Destination $loopGoal -Force
        Write-Host "Moved GOAL.md into .loop\ (loop state stays out of the repo root)." -ForegroundColor DarkGray
    } else {
        Write-Error "No GOAL.md found. Pass -GoalPath, or place GOAL.md in the repo root / .loop\."
        exit 2
    }
}

# --- goal-name from frontmatter when not supplied ---
if (-not $GoalName) {
    $fm = Select-String -LiteralPath $loopGoal -Pattern '^goal-name:\s*(.+)$' | Select-Object -First 1
    $GoalName = if ($fm) { $fm.Matches[0].Groups[1].Value.Trim() } else { Split-Path $RootPath -Leaf }
}

# --- state.json (started_at is what makes wall-clock caps real) ---
$statePath = Join-Path $loopDir 'state.json'
$costCap = if ($MaxCostUsd -gt 0) { $MaxCostUsd } else { $null }
$state = [pscustomobject][ordered]@{
    version     = 1
    goal_name   = $GoalName
    root        = $RootPath
    loop_dir    = $loopDir
    started_at  = Get-LoopUtcStamp
    mode        = $Mode
    caps        = [pscustomobject][ordered]@{
        max_iterations           = $MaxIterations
        max_duration_minutes     = $MaxDurationMinutes
        max_consecutive_failures = $MaxConsecutiveFailures
        max_no_change_iterations = $MaxNoChangeIterations
        max_cost_usd             = $costCap
    }
    models      = [pscustomobject][ordered]@{
        orchestrator = $OrchestratorModel
        executor     = $ExecutorModel
        verifier     = $VerifierMode
    }
    checkpoints = @()
}
Write-LoopJson -Object $state -Path $statePath -Depth 8
Write-Host ("state.json written: started_at = {0}" -f $state.started_at) -ForegroundColor DarkGray

# --- PROGRESS.md header ---
$progressPath = Join-Path $loopDir 'PROGRESS.md'
if (-not (Test-Path -LiteralPath $progressPath)) {
    $header = @"
# Progress - $GoalName

started_at: $($state.started_at)
mode: $Mode
caps: iterations=$MaxIterations, duration=${MaxDurationMinutes}m, consecutive-failures=$MaxConsecutiveFailures, no-change=$MaxNoChangeIterations

<!-- The Verifier appends one entry per iteration below. Do not edit past entries. -->
"@
    Set-Content -LiteralPath $progressPath -Value $header -Encoding utf8
    Write-Host "PROGRESS.md seeded." -ForegroundColor DarkGray
}

# --- PLAN.md placeholder (Orchestrator rewrites it every iteration) ---
$planPath = Join-Path $loopDir 'PLAN.md'
if (-not (Test-Path -LiteralPath $planPath)) {
    Set-Content -LiteralPath $planPath -Encoding utf8 -Value @"
# Plan

## Strategy

(not yet planned - Orchestrator writes this at the start of iteration 1)

## Next actions (queue)
"@
}

# --- Ignore rules for .loop/ ---
# Two ways to keep loop state out of the user's commits, and they are NOT equivalent:
#   -ExcludeLocally -> .git\info\exclude : local-only, untracked, invisible to `git status`, nothing
#                      to commit. Correct default in a repo where the user hand-commits.
#   -AddGitIgnore   -> .gitignore        : TRACKED, so the loop dirties a file the user must then
#                      commit on the loop's behalf. Only right when the team should share the rule.
$needle = '.loop/'

function Add-LoopIgnoreLine {
    param([string]$Path, [string]$Line, [string]$Label)
    $already = $false
    if (Test-Path -LiteralPath $Path) {
        $already = (@(Get-Content -LiteralPath $Path) -contains $Line)
    }
    if ($already) { return $false }
    $dir = Split-Path -Parent $Path
    if ($dir -and -not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    Add-Content -LiteralPath $Path -Value $Line -Encoding utf8
    Write-Host "Added '$Line' to $Label (loop state should never be committed)." -ForegroundColor DarkGray
    return $true
}

if ($ExcludeLocally) {
    # Resolve via git rather than assuming <root>\.git is a directory — in a worktree or submodule
    # it is a FILE pointing at the real gitdir, and writing into it would corrupt the pointer.
    $gitDirProbe = Invoke-LoopGit -RootPath $RootPath -Arguments @('rev-parse', '--absolute-git-dir')
    $gitDir = if ($gitDirProbe.ExitCode -eq 0) { @($gitDirProbe.Lines | Where-Object { $_ })[0] } else { $null }
    if ($gitDir) {
        [void](Add-LoopIgnoreLine -Path (Join-Path $gitDir 'info\exclude') -Line $needle -Label '.git\info\exclude (local only)')
    } else {
        Write-Host "-ExcludeLocally skipped: not a git repository (nothing to exclude from)." -ForegroundColor DarkGray
    }
}

if ($AddGitIgnore) {
    [void](Add-LoopIgnoreLine -Path (Join-Path $RootPath '.gitignore') -Line $needle -Label '.gitignore (TRACKED - you will need to commit it)')
}

# --- Baseline ---
# Args are built conditionally: passing an EMPTY array to `pwsh -File` supplies the switch name
# with no value, which PowerShell rejects with "Missing an argument for parameter".
$baselineScript = Join-Path $PSScriptRoot 'Get-Baseline.ps1'
$baselineArgs = @('-NoProfile', '-File', $baselineScript, '-RootPath', $RootPath, '-Iteration', '0')
if (@($Include | Where-Object { $_ }).Count -gt 0) { $baselineArgs += @('-Include') + @($Include) }
if (@($Exclude | Where-Object { $_ }).Count -gt 0) { $baselineArgs += @('-Exclude') + @($Exclude) }
& pwsh @baselineArgs
if ($LASTEXITCODE -ne 0) {
    Write-Error "Baseline capture failed."
    exit 2
}

# --- Criteria preflight ---
$preflightWarned = $false
$criteriaPath = Join-Path $loopDir 'CRITERIA.json'

if (-not $SkipPreflight) {
    if ($CriteriaFile) {
        if (-not (Test-Path -LiteralPath $CriteriaFile)) {
            Write-Error "CriteriaFile not found: $CriteriaFile"
            exit 2
        }
        Write-Host ""
        $criteriaScript = Join-Path $PSScriptRoot 'Test-Criteria.ps1'
        & pwsh -NoProfile -File $criteriaScript -RootPath $RootPath -Preflight -CriteriaFile $CriteriaFile
        $doc = Read-LoopJson -Path $criteriaPath
        if ($doc -and $doc.criteria) {
            foreach ($c in $doc.criteria) {
                if ($c.baseline -and $c.baseline.already_passing) { $preflightWarned = $true }
            }
        }
    } elseif (@($Criterion | Where-Object { $_ }).Count -eq 0) {
        Write-Host ""
        Write-Host "WARNING: no -Criterion supplied, so the Done-when commands were NOT preflighted." -ForegroundColor Yellow
        Write-Host "         Run Test-Criteria.ps1 -Preflight before iteration 1 - it is the cheapest bug-catcher" -ForegroundColor Yellow
        Write-Host "         in the loop (it finds inverted exit codes and criteria that already pass)." -ForegroundColor Yellow
        $preflightWarned = $true
    } else {
        Write-Host ""
        $criteriaScript = Join-Path $PSScriptRoot 'Test-Criteria.ps1'
        $childArgs = @('-NoProfile', '-File', $criteriaScript, '-RootPath', $RootPath, '-Preflight', '-Command') + @($Criterion)
        if (@($CriterionLabel | Where-Object { $_ }).Count -gt 0) {
            $childArgs += @('-Label') + @($CriterionLabel)
        }
        & pwsh @childArgs
        $doc = Read-LoopJson -Path $criteriaPath
        if ($doc -and $doc.criteria) {
            foreach ($c in $doc.criteria) {
                if ($c.baseline -and $c.baseline.already_passing) { $preflightWarned = $true }
            }
        }
    }
}

# --- Permission allow-list for unattended runs ---
Write-Host ""
Write-Host "Commands this loop will run (allow-list these BEFORE an unattended run, or it will stall on approval prompts):" -ForegroundColor Cyan
Write-Host ("  pwsh -File {0}\*.ps1        (baseline, constraints, criteria, budget, checkpoint, rollback)" -f $PSScriptRoot)
Write-Host  "  git status / git diff / git stash create / git restore / git clean -f -- <paths>"
if (Test-Path -LiteralPath $criteriaPath) {
    $doc = Read-LoopJson -Path $criteriaPath
    if ($doc -and $doc.criteria) {
        foreach ($c in $doc.criteria) { Write-Host ("  {0}" -f $c.command) }
    }
}
Write-Host  "  ...plus whatever the GOAL's regression-command runs."
Write-Host ""

$criteriaNote = if (Test-Path -LiteralPath $criteriaPath) { ', CRITERIA.json' } else { '' }
Write-Host ("Loop initialized: {0}" -f $loopDir) -ForegroundColor Green
Write-Host ("  GOAL.md, PLAN.md, PROGRESS.md, BASELINE.json{0}" -f $criteriaNote)
Write-Host ("  mode = {0}   caps: {1} iterations / {2} min / {3} consecutive fails / {4} no-change" -f $Mode, $MaxIterations, $MaxDurationMinutes, $MaxConsecutiveFailures, $MaxNoChangeIterations)

if ($preflightWarned) { exit 1 } else { exit 0 }
