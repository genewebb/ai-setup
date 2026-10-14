<#
.SYNOPSIS
    Captures a SHA-256 hash snapshot of every in-scope file under a root, writing it to BASELINE.json for the constraint gate. Re-run after every PASSING iteration to advance the reference state.

.DESCRIPTION
    Used by the orchestrator-worker-loop skill's Verifier gate 3 (constraint check).

    CRITICAL — the baseline must ADVANCE. The -Allowed list handed to Test-Constraints.ps1 is
    per-iteration, so a baseline captured only once before iteration 1 makes iteration 1's
    legitimate edits look like out-of-scope violations from iteration 2 onward (the gate then
    rolls back good work). The Verifier therefore re-runs this script with -Iteration N after
    every iteration it PASSES. Never re-baseline after a FAIL — that would launder the very
    changes the gate is meant to catch.

    Advantages over `git diff --name-only`:
      - Immune to pre-loop Orchestrator edits (writing GOAL/PLAN/PROGRESS doesn't false-flag)
      - Works even when the working tree isn't a git repo
      - Captures binary and non-text file changes
      - Sees untracked new files, which `git diff` does not

    The include/exclude/exclude_dirs actually used are persisted INTO BASELINE.json so
    Test-Constraints.ps1 enumerates exactly the same file set. Hardcoding that list in two
    places silently produced phantom "added file" violations.

.PARAMETER RootPath
    Absolute path to the working directory to snapshot.

.PARAMETER OutputPath
    Where to write the JSON snapshot. Defaults to <RootPath>\.loop\BASELINE.json when a .loop
    directory exists, else <RootPath>\BASELINE.json.

.PARAMETER Include
    Glob patterns of files to include. Default: '**/*' (every file at any depth). Real glob
    semantics: '*' does not cross '/', '**' does. Narrow this to the GOAL's "Files in scope"
    on large repos to keep the gate fast.

.PARAMETER Exclude
    Extra glob patterns to exclude, on top of -ExcludeDirs and the loop's own memory files.

.PARAMETER ExcludeDirs
    Directory NAMES excluded at any depth (segment match). Default: .git .loop node_modules
    bin obj .vs .vscode TestResults packages .idea — pruned during enumeration, so large
    build trees are never walked.

.PARAMETER Iteration
    Iteration number this snapshot represents. 0 (default) = pre-loop baseline.

.PARAMETER Quiet
    Suppress the summary line to stdout.

.EXAMPLE
    pwsh -File Get-Baseline.ps1 -RootPath {ScratchRoot}\loop-test

.EXAMPLE
    # Advance the baseline after iteration 4 passed all gates
    pwsh -File Get-Baseline.ps1 -RootPath <repo> -Iteration 4 -Quiet

.EXAMPLE
    # Narrow the snapshot to the goal's scope on a large repo
    pwsh -File Get-Baseline.ps1 -RootPath <repo> -Include 'src/TestAuto.Web/**/*.cs'

.OUTPUTS
    JSON file at OutputPath, shape:
    {
      "version": 2,
      "root": "<absolute path>",
      "captured_at": "<ISO 8601 UTC>",
      "iteration": <int>,
      "include": ["**/*"],
      "exclude": ["GOAL.md", ...],
      "exclude_dirs": [".git", ".loop", "bin", "obj", ...],
      "file_count": <int>,
      "files": { "docs/file1.md": { "hash": "<sha256 hex>", "size": <bytes> } }
    }
    Keys are root-relative paths using forward slashes.

.NOTES
    Exit codes: 0 = success. 1 = RootPath missing or unreadable.
#>
[CmdletBinding()]
param(
    # Position 0 declared so every other parameter is name-only (prevents stray array elements
    # under `pwsh -File` from binding positionally).
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [string]$OutputPath,

    [string[]]$Include = @('**/*'),

    [string[]]$Exclude = @(),

    [string[]]$ExcludeDirs,

    [int]$Iteration = 0,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LoopCommon.ps1"

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-LoopError "RootPath not found: $RootPath"
    exit 1
}

$RootPath = (Get-Item -LiteralPath $RootPath).FullName.TrimEnd('\', '/')

if (-not $OutputPath) {
    $loopDir = Join-Path $RootPath '.loop'
    $OutputPath = if (Test-Path -LiteralPath $loopDir) {
        Join-Path $loopDir 'BASELINE.json'
    } else {
        Join-Path $RootPath 'BASELINE.json'
    }
}

if (-not $ExcludeDirs) { $ExcludeDirs = Get-LoopDefaultExcludeDirs }

# The loop's own memory files are never part of the gate — the Orchestrator and Verifier
# rewrite PLAN/PROGRESS every iteration, and the Executor may write ARTIFACT.md by design.
$effectiveExclude = @(@($Exclude) + (Get-LoopOwnedFilePatterns) | Where-Object { $_ } | Select-Object -Unique)

$files = Get-LoopFileSet -RootPath $RootPath -Include $Include -Exclude $effectiveExclude -ExcludeDirs $ExcludeDirs

$fileEntries = [ordered]@{}
$count = 0
$skipped = 0

foreach ($rel in ($files.Keys | Sort-Object)) {
    $hash = Get-LoopSha256 -Path $files[$rel].FullName
    if (-not $hash) {
        Write-Warning "Skipping unreadable file: $rel"
        $skipped++
        continue
    }
    $fileEntries[$rel] = [ordered]@{
        hash = $hash
        size = $files[$rel].Length
    }
    $count++
}

$baseline = [ordered]@{
    version      = 2
    root         = $RootPath
    captured_at  = Get-LoopUtcStamp
    iteration    = $Iteration
    include      = @($Include)
    exclude      = @($effectiveExclude)
    exclude_dirs = @($ExcludeDirs)
    file_count   = $count
    files        = $fileEntries
}

Write-LoopJson -Object $baseline -Path $OutputPath -Depth 6

if (-not $Quiet) {
    Write-Host ("Baseline captured (iteration {0}): {1} files -> {2}" -f $Iteration, $count, $OutputPath)
    if ($skipped -gt 0) {
        Write-Host ("  {0} unreadable file(s) skipped" -f $skipped) -ForegroundColor DarkYellow
    }
}

exit 0
