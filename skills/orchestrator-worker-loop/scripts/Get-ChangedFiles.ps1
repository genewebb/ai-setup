<#
.SYNOPSIS
    Authoritative "what changed" report for the Verifier's diff-shape gate — counts NEW/untracked files, which `git diff --numstat` silently ignores.

.DESCRIPTION
    Used by the orchestrator-worker-loop skill's Verifier gate 4 (diff-shape) and to fill the
    PROGRESS entry's "Files changed" field.

    WHY this exists: `git diff --numstat` and `git diff --name-only` report only tracked
    modifications. An Executor that CREATES a file (a new options class, a new test) shows up
    as +0 -0 and an empty name list, so a runaway new-file diff sailed through the gate and the
    default `git restore` rollback could not remove it. This script uses
    `git status --porcelain -uall` for the file list and counts lines of untracked files
    directly, then falls back to BASELINE.json hashes when the tree isn't a git repo.

    Never trust the Executor's self-reported LINES field — use this.

.PARAMETER RootPath
    Absolute path to the working directory.

.PARAMETER Paths
    Glob patterns restricting the report — typically the iteration's files-allowed list.

    MANDATORY for Verifier gate 4. Omitting it reports the whole tree, which inside a running loop
    is the CUMULATIVE diff across every iteration so far, compared against a PER-ITERATION
    expectation. The script warns on stderr when -Paths is absent and .loop\PROGRESS.md already
    records an iteration. Omit it only for an exploratory "what changed anywhere" call.

.PARAMETER BaselinePath
    BASELINE.json used for the non-git fallback. Defaults to <RootPath>\.loop\BASELINE.json,
    else <RootPath>\BASELINE.json.

.PARAMETER Format
    'json' (default — machine parse) or 'text'.

.EXAMPLE
    pwsh -File Get-ChangedFiles.ps1 -RootPath <repo>

.EXAMPLE
    pwsh -File Get-ChangedFiles.ps1 -RootPath {ScratchRoot}\loop-test -Paths 'docs/**' -Format text

.OUTPUTS
    JSON. "mode" reports which source was used: "git" (repo with a HEAD) or "baseline" (no git, or a
    repo with no commits — see the note above).
    {
      "mode": "git" | "baseline",
      "added_lines": <int>, "removed_lines": <int>,
      "file_count": <int>,
      "files": [ { "path": "src/Foo.cs", "status": "modified|added|deleted|renamed|untracked",
                   "added": <int>, "removed": <int> } ]
    }

.NOTES
    Exit codes: 0 = report produced. 2 = script error (root missing, no git and no baseline).
    Line counts for untracked files count every line as added — that is the honest diff shape
    for a brand-new file.
#>
[CmdletBinding()]
param(
    # Position 0 declared so every other parameter is name-only.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [string[]]$Paths = @(),

    [string]$BaselinePath,

    [ValidateSet('json', 'text')]
    [string]$Format = 'json'
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LoopCommon.ps1"

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-LoopError "RootPath not found: $RootPath"
    exit 2
}
$RootPath = (Get-Item -LiteralPath $RootPath).FullName.TrimEnd('\', '/')

$pathList = @($Paths | ForEach-Object { "$_".Split(',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$pathMatchers = @(New-LoopMatcher -Patterns $pathList)

# --- Footgun detector: -Paths omitted while a loop is under way ---
# Gate 4 compares this report against the PLAN's PER-ITERATION expected diff. With no -Paths filter
# the report covers the WHOLE TREE, which inside a running loop is the CUMULATIVE diff of every
# iteration so far. The Verifier's "more than ~5x expected" rule then fires spuriously and gets worse
# each iteration, and it reads as Executor runaway rather than the measurement error it is. Warn only
# once PROGRESS.md records an iteration — a bare exploratory call is legitimate. stderr only: stdout
# stays pure JSON and the exit code is unaffected.
if (@($pathList).Count -eq 0) {
    $progressPath = Join-Path (Join-Path $RootPath '.loop') 'PROGRESS.md'
    if (Test-Path -LiteralPath $progressPath) {
        $iterCount = @(Select-String -LiteralPath $progressPath -Pattern '^##\s+Iteration\s+\d+').Count
        if ($iterCount -ge 1) {
            [Console]::Error.WriteLine(
                ("WARNING: -Paths was omitted, so this report covers the WHOLE TREE and is CUMULATIVE " +
                 "across all {0} recorded iteration(s). Verifier gate 4 expects a PER-ITERATION diff - " +
                 "pass -Paths '<files-allowed-csv>' or the diff-shape gate will fail spuriously." -f $iterCount))
        }
    }
}

function Test-InScope {
    param([string]$Rel)
    if (@($pathMatchers).Count -eq 0) { return $true }   # no -Paths filter => everything is in scope
    return (Test-LoopGlobMatch -RelativePath $Rel -Matchers $pathMatchers)
}

function Measure-FileLines {
    param([string]$FullPath)
    try {
        $content = Get-Content -LiteralPath $FullPath -ErrorAction Stop
        return @($content).Count
    } catch {
        return 0
    }
}

$files = New-Object System.Collections.ArrayList
$mode = 'git'

# A repo with no commits (fresh `git init`) has no HEAD, so git has no committed state to diff
# against and reports every staged file as a brand-new addition — which would make gate 4 see the
# whole repo as this iteration's diff. BASELINE.json hashes are the honest answer there.
$useGit = (Test-LoopGitRepo -RootPath $RootPath) -and (Test-LoopGitHasHead -RootPath $RootPath)

if ($useGit) {
    # --- File list: porcelain sees untracked files; git diff does not ---
    $status = Invoke-LoopGit -RootPath $RootPath -Arguments @('status', '--porcelain', '-uall')
    if ($status.ExitCode -ne 0) {
        Write-Error ("git status failed: {0}" -f ($status.Lines -join '; '))
        exit 2
    }

    # --- Line counts for tracked changes (worktree + staged) ---
    $numstat = @{}
    foreach ($argSet in @(, @('diff', '--numstat')) + @(, @('diff', '--numstat', '--cached'))) {
        $ns = Invoke-LoopGit -RootPath $RootPath -Arguments $argSet
        foreach ($line in $ns.Lines) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $parts = $line -split "`t"
            if ($parts.Count -lt 3) { continue }
            $rel = $parts[2].Replace('\', '/')
            $a = 0; $r = 0
            [void][int]::TryParse($parts[0], [ref]$a)   # '-' for binary => stays 0
            [void][int]::TryParse($parts[1], [ref]$r)
            if (-not $numstat.ContainsKey($rel)) { $numstat[$rel] = @{ added = 0; removed = 0 } }
            if ($a -gt $numstat[$rel].added)   { $numstat[$rel].added = $a }
            if ($r -gt $numstat[$rel].removed) { $numstat[$rel].removed = $r }
        }
    }

    foreach ($line in $status.Lines) {
        if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
        $code = $line.Substring(0, 2)
        $rest = $line.Substring(3).Trim()

        # Renames appear as "old -> new"; report the destination.
        if ($rest -match '^(?<old>.+?)\s->\s(?<new>.+)$') { $rest = $Matches['new'] }
        $rel = $rest.Trim('"').Replace('\', '/')
        if (-not (Test-InScope -Rel $rel)) { continue }

        $statusName = 'modified'
        if ($code -eq '??')            { $statusName = 'untracked' }
        elseif ($code -match '^R')     { $statusName = 'renamed' }
        elseif ($code -match '^A|^.A') { $statusName = 'added' }
        elseif ($code -match '^D|^.D') { $statusName = 'deleted' }

        $added = 0; $removed = 0
        if ($numstat.ContainsKey($rel)) {
            $added = $numstat[$rel].added
            $removed = $numstat[$rel].removed
        } elseif ($statusName -eq 'untracked' -or $statusName -eq 'added') {
            $full = Join-Path $RootPath ($rel -replace '/', '\')
            if (Test-Path -LiteralPath $full) { $added = Measure-FileLines -FullPath $full }
        }

        [void]$files.Add([ordered]@{
            path    = $rel
            status  = $statusName
            added   = $added
            removed = $removed
        })
    }
} else {
    # --- Fallback: compare hashes against the baseline (no git, or git with no HEAD) ---
    $mode = 'baseline'
    if (-not $BaselinePath) {
        $inLoop = Join-Path (Join-Path $RootPath '.loop') 'BASELINE.json'
        $BaselinePath = if (Test-Path -LiteralPath $inLoop) { $inLoop } else { Join-Path $RootPath 'BASELINE.json' }
    }
    $baseline = Read-LoopJson -Path $BaselinePath
    if (-not $baseline) {
        Write-LoopError "No usable git history (no HEAD) and no readable BASELINE.json at $BaselinePath - cannot compute changed files. Run Get-Baseline.ps1 first."
        exit 2
    }

    $baselineProps = $baseline.PSObject.Properties.Name
    $include     = if (($baselineProps -contains 'include')      -and $baseline.include)      { @($baseline.include) }      else { @('**/*') }
    $exclude     = if (($baselineProps -contains 'exclude')      -and $baseline.exclude)      { @($baseline.exclude) }      else { (Get-LoopOwnedFilePatterns) }
    $excludeDirs = if (($baselineProps -contains 'exclude_dirs') -and $baseline.exclude_dirs) { @($baseline.exclude_dirs) } else { (Get-LoopDefaultExcludeDirs) }

    $baseFiles = @{}
    if ($baseline.files) {
        # @() wrapper: empty files object ({} - 0-file greenfield baseline) throws on .Name under StrictMode Latest
        foreach ($p in @($baseline.files.PSObject.Properties)) { $baseFiles[$p.Name] = $p.Value.hash }
    }

    $currentSet = Get-LoopFileSet -RootPath $RootPath -Include $include -Exclude $exclude -ExcludeDirs $excludeDirs

    foreach ($rel in ($currentSet.Keys | Sort-Object)) {
        if (-not (Test-InScope -Rel $rel)) { continue }
        $hash = Get-LoopSha256 -Path $currentSet[$rel].FullName
        if ($baseFiles.ContainsKey($rel)) {
            if ($baseFiles[$rel] -ne $hash) {
                [void]$files.Add([ordered]@{ path = $rel; status = 'modified'; added = 0; removed = 0 })
            }
        } else {
            [void]$files.Add([ordered]@{
                path  = $rel
                status = 'added'
                added = (Measure-FileLines -FullPath $currentSet[$rel].FullName)
                removed = 0
            })
        }
    }
    foreach ($rel in ($baseFiles.Keys | Sort-Object)) {
        if (-not (Test-InScope -Rel $rel)) { continue }
        if (-not $currentSet.ContainsKey($rel)) {
            [void]$files.Add([ordered]@{ path = $rel; status = 'deleted'; added = 0; removed = 0 })
        }
    }
}

$totalAdded = 0
$totalRemoved = 0
foreach ($f in $files) { $totalAdded += $f.added; $totalRemoved += $f.removed }

if ($Format -eq 'json') {
    [ordered]@{
        mode          = $mode
        added_lines   = $totalAdded
        removed_lines = $totalRemoved
        file_count    = $files.Count
        files         = @($files)
    } | ConvertTo-Json -Depth 5
} else {
    Write-Host ("Changed files ({0} mode): {1} file(s), +{2} -{3}" -f $mode, $files.Count, $totalAdded, $totalRemoved)
    foreach ($f in $files) {
        Write-Host ("  {0,-10} +{1,-5} -{2,-5} {3}" -f $f.status, $f.added, $f.removed, $f.path)
    }
}

exit 0
