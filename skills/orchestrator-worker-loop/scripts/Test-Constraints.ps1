<#
.SYNOPSIS
    Verifies that only allowed files have changed since the baseline snapshot. Used by the orchestrator-worker-loop skill's Verifier gate 3 (constraint check).

.DESCRIPTION
    Compares current SHA-256 hashes of files under RootPath against BASELINE.json (captured by
    Get-Baseline.ps1). Reports:
      - Files that changed and ARE in the -Allowed list      -> informational
      - Files that changed and are NOT in the -Allowed list  -> CONSTRAINT VIOLATION
      - Files that appeared since baseline, not allowed      -> CONSTRAINT VIOLATION
      - Files that disappeared since baseline, not allowed   -> CONSTRAINT VIOLATION

    The include/exclude/exclude_dirs are read FROM the baseline, so this script enumerates
    exactly the file set the baseline captured. (Previously both scripts hardcoded their own
    exclude list; any custom -Include/-Exclude at capture time produced phantom violations.)

    Pair with Get-Baseline.ps1 -Iteration N after each PASSING iteration. If the baseline is
    never advanced, this gate reports iteration 1's legitimate edits as violations forever.

    Exit codes are the wire protocol back to the Verifier:
      0 = clean (only allowed files changed, or no changes)
      1 = constraint violation (out-of-scope file(s) changed)
      2 = script error (baseline missing, unparseable, etc.)

.PARAMETER RootPath
    Absolute path to the working directory to check.

.PARAMETER BaselinePath
    Path to BASELINE.json. Defaults to <RootPath>\.loop\BASELINE.json if present, else
    <RootPath>\BASELINE.json.

.PARAMETER Allowed
    Glob patterns describing which files ARE allowed to change this iteration. Accepts an
    array, or one comma-separated string. Real glob semantics: '*' stops at '/', '**' spans
    segments, a bare filename matches at any depth.
    Omit (or pass '') to assert NOTHING may change — useful for a read-only/analysis iteration.

.PARAMETER Format
    Output shape: 'text' (default, human readable) or 'json' (machine parse).

.EXAMPLE
    pwsh -File Test-Constraints.ps1 -RootPath {ScratchRoot}\loop-test -Allowed 'docs/file1.md'

.EXAMPLE
    pwsh -File Test-Constraints.ps1 -RootPath <repo> -Allowed 'src/Services/EmailService.cs,src/Options/SmtpOptions.cs' -Format json

.EXAMPLE
    # Analysis-only iteration: assert the Executor changed nothing
    pwsh -File Test-Constraints.ps1 -RootPath <repo>
#>
[CmdletBinding()]
param(
    # Position 0 declared so every other parameter is name-only (prevents stray array elements
    # under `pwsh -File` from binding positionally).
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [string]$BaselinePath,

    [string[]]$Allowed = @(),

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

if (-not $BaselinePath) {
    $inLoop = Join-Path (Join-Path $RootPath '.loop') 'BASELINE.json'
    $BaselinePath = if (Test-Path -LiteralPath $inLoop) { $inLoop } else { Join-Path $RootPath 'BASELINE.json' }
}

if (-not (Test-Path -LiteralPath $BaselinePath)) {
    Write-LoopError "BASELINE.json not found: $BaselinePath (run Get-Baseline.ps1 first)"
    exit 2
}

try {
    $baseline = Read-LoopJson -Path $BaselinePath
} catch {
    Write-LoopError "Failed to parse BASELINE.json: $_"
    exit 2
}
if (-not $baseline) {
    Write-LoopError "BASELINE.json is empty: $BaselinePath"
    exit 2
}

# Allow one comma-separated string, or an array, or nothing at all.
$allowedList = @($Allowed | ForEach-Object { "$_".Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$allowedMatchers = @(New-LoopMatcher -Patterns $allowedList)

$baselineProps = $baseline.PSObject.Properties.Name

# --- Enumerate current files using the SAME scope the baseline used ---
$include     = if (($baselineProps -contains 'include')      -and $baseline.include)      { @($baseline.include) }      else { @('**/*') }
$exclude     = if (($baselineProps -contains 'exclude')      -and $baseline.exclude)      { @($baseline.exclude) }      else { (Get-LoopOwnedFilePatterns) }
$excludeDirs = if (($baselineProps -contains 'exclude_dirs') -and $baseline.exclude_dirs) { @($baseline.exclude_dirs) } else { (Get-LoopDefaultExcludeDirs) }

$baselineFiles = @{}
if ($baseline.files) {
    # @() wrapper: an EMPTY files object ({} - a 0-file greenfield baseline) has an empty
    # Properties collection, and member-enumerating .Name on it throws under Set-StrictMode Latest.
    foreach ($p in @($baseline.files.PSObject.Properties)) {
        $baselineFiles[$p.Name] = $p.Value.hash
    }
}

$currentSet = Get-LoopFileSet -RootPath $RootPath -Include $include -Exclude $exclude -ExcludeDirs $excludeDirs

$currentFiles = @{}
foreach ($rel in $currentSet.Keys) {
    $hash = Get-LoopSha256 -Path $currentSet[$rel].FullName
    if ($hash) { $currentFiles[$rel] = $hash }
}

# --- Classify ---
$changed = New-Object System.Collections.ArrayList   # in baseline AND current, hash differs
$added   = New-Object System.Collections.ArrayList   # in current, not in baseline
$removed = New-Object System.Collections.ArrayList   # in baseline, not in current

foreach ($k in $currentFiles.Keys) {
    if ($baselineFiles.ContainsKey($k)) {
        if ($baselineFiles[$k] -ne $currentFiles[$k]) { [void]$changed.Add($k) }
    } else {
        [void]$added.Add($k)
    }
}
foreach ($k in $baselineFiles.Keys) {
    if (-not $currentFiles.ContainsKey($k)) { [void]$removed.Add($k) }
}

$violations     = New-Object System.Collections.ArrayList
$allowedChanged = New-Object System.Collections.ArrayList

foreach ($f in (@($changed) + @($added) + @($removed) | Sort-Object -Unique)) {
    if (Test-LoopGlobMatch -RelativePath $f -Matchers $allowedMatchers) {
        [void]$allowedChanged.Add($f)
    } else {
        [void]$violations.Add($f)
    }
}

# --- Report ---
$baselineIteration = if ($baselineProps -contains 'iteration') { $baseline.iteration } else { $null }

if ($Format -eq 'json') {
    $report = [ordered]@{
        clean                = ($violations.Count -eq 0)
        baseline_iteration   = $baselineIteration
        baseline_captured_at = $baseline.captured_at
        allowed_patterns     = @($allowedList)
        allowed_changes      = @($allowedChanged)
        violations           = @($violations)
        summary              = [ordered]@{
            changed = @($changed)
            added   = @($added)
            removed = @($removed)
        }
    }
    $report | ConvertTo-Json -Depth 5
} else {
    $base = if ($null -ne $baselineIteration) { "iteration $baselineIteration" } else { 'unversioned' }
    if ($violations.Count -eq 0) {
        Write-Host ("[PASS] Constraint gate clean (baseline: {0}). Allowed changes: {1}" -f $base, $allowedChanged.Count) -ForegroundColor Green
        $allowedChanged | ForEach-Object { Write-Host ("         [allowed] {0}" -f $_) -ForegroundColor DarkGreen }
    } else {
        Write-Host ("[FAIL] Constraint gate (baseline: {0}): {1} out-of-scope change(s)" -f $base, $violations.Count) -ForegroundColor Red
        $violations | ForEach-Object { Write-Host ("         [VIOLATION] {0}" -f $_) -ForegroundColor Yellow }
        if ($allowedChanged.Count -gt 0) {
            Write-Host ("Allowed changes ({0}):" -f $allowedChanged.Count) -ForegroundColor DarkGray
            $allowedChanged | ForEach-Object { Write-Host ("         [allowed] {0}" -f $_) -ForegroundColor DarkGreen }
        }
        Write-Host "Hint: if these are edits from EARLIER passing iterations, the baseline was not advanced - run Get-Baseline.ps1 -Iteration N after each PASS." -ForegroundColor DarkGray
    }
}

if ($violations.Count -eq 0) { exit 0 } else { exit 1 }
