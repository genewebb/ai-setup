# select-trx.ps1
# Lists all .trx files in the speed-merchants TestResults folder by number,
# shows pass/fail/skip counts and inferred suite (Unit | Integration | Unknown),
# prompts the user to pick one, and emits a structured selection on stdout
# that the calling agent can parse.
#
# Usage (agent / non-interactive — TWO-CALL FLOW):
#   1. List the runs (prints the table + machine-readable CANDIDATE: lines, never prompts):
#        pwsh -NoProfile -File ./select-trx.ps1 -List
#   2. After the user picks a number, re-run with that number:
#        pwsh -NoProfile -File ./select-trx.ps1 -Choice 2
#
# Usage (human at a real terminal — interactive prompt):
#   pwsh -NoProfile -File ./select-trx.ps1
#
# NOTE: Read-Host hangs a -NonInteractive host (the agent shell). Agents MUST use
# -List then -Choice; never invoke the bare interactive form from a tool call.
#
# Exit codes:
#   0 = a TRX file was selected (details printed) OR -List succeeded
#   1 = TestResults folder missing
#   2 = no .trx files found
#   3 = invalid choice / user aborted

[CmdletBinding()]
param(
	# Default: <repo root of the current folder>\TestResults (run it from inside the speed-merchants repo).
	[string]$ResultsDir,
	[int]$Choice = 0,
	# List-only mode: print the table + CANDIDATE: lines and exit 0 without prompting.
	# This is the agent-safe entry point (no Read-Host).
	[switch]$List
)

$ErrorActionPreference = 'Stop'

if (-not $ResultsDir) {
	$top = git rev-parse --show-toplevel 2>$null
	if (-not $? -or -not $top) { Write-Host 'Not inside a git repo: pass -ResultsDir <repo>\TestResults.'; exit 1 }
	$ResultsDir = Join-Path $top 'TestResults'
}

function Get-HumanAge {
	param([datetime]$When)
	$delta = (Get-Date) - $When
	if ($delta.TotalMinutes -lt 1)  { return 'just now' }
	if ($delta.TotalMinutes -lt 60) { return ('{0}m ago' -f [int]$delta.TotalMinutes) }
	if ($delta.TotalHours   -lt 24) { return ('{0}h ago' -f [int]$delta.TotalHours) }
	return ('{0}d ago' -f [int]$delta.TotalDays)
}

function Get-HumanSize {
	param([long]$Bytes)
	if ($Bytes -lt 1KB) { return ('{0} B'  -f $Bytes) }
	if ($Bytes -lt 1MB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
	if ($Bytes -lt 1GB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
	return ('{0:N2} GB' -f ($Bytes / 1GB))
}

function Get-TrxSummary {
	param([string]$Path)

	$result = [pscustomobject]@{
		Suite   = 'Unknown'
		Total   = 0
		Passed  = 0
		Failed  = 0
		Skipped = 0
	}

	try {
		[xml]$xml = Get-Content -Path $Path -ErrorAction Stop
		$ns = 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010'
		$nt = New-Object System.Xml.NameTable
		$nm = New-Object System.Xml.XmlNamespaceManager($nt)
		$nm.AddNamespace('t', $ns)

		$counters = $xml.SelectSingleNode('//t:ResultSummary/t:Counters', $nm)
		if ($counters) {
			$result.Total   = [int]$counters.total
			$result.Passed  = [int]$counters.passed
			$result.Failed  = [int]$counters.failed
			# TRX uses several skip-ish buckets; sum them.
			$result.Skipped = ([int]$counters.notExecuted) + ([int]$counters.notRunnable) + ([int]$counters.disconnected)
		}

		# Infer suite by scanning ALL test class namespaces (not just the first) so a
		# mixed TRX is flagged rather than mislabeled by whichever test happened to run first.
		$sawIntegration = $false
		$sawUnit        = $false
		foreach ($tm in $xml.SelectNodes('//t:UnitTest/t:TestMethod', $nm)) {
			if (-not $tm.className) { continue }
			if     ($tm.className -match '(?i)\.Integration')                  { $sawIntegration = $true }
			elseif ($tm.className -match '(?i)\.Unit|SpeedMerchants\.Unit')    { $sawUnit = $true }
		}
		if     ($sawIntegration -and $sawUnit) { $result.Suite = 'Mixed' }
		elseif ($sawIntegration)               { $result.Suite = 'Integration' }
		elseif ($sawUnit)                      { $result.Suite = 'Unit' }
	} catch {
		# Parsing failed — leave defaults.
	}

	if ($result.Suite -eq 'Unknown') {
		$name = Split-Path -Leaf $Path
		if     ($name -match '(?i)integration') { $result.Suite = 'Integration' }
		elseif ($name -match '(?i)unit')        { $result.Suite = 'Unit' }
	}

	return $result
}

# 1. Validate the results directory.
if (-not (Test-Path -LiteralPath $ResultsDir -PathType Container)) {
	Write-Host "ERROR: TestResults folder not found: $ResultsDir" -ForegroundColor Red
	Write-Host "Create it by running the suites with --results-directory $ResultsDir" -ForegroundColor Yellow
	exit 1
}

# 2. Enumerate TRX files, newest first.
$files = Get-ChildItem -LiteralPath $ResultsDir -Filter *.trx -File -ErrorAction SilentlyContinue |
	Sort-Object LastWriteTime -Descending

if (-not $files -or $files.Count -eq 0) {
	Write-Host "ERROR: No .trx files found in $ResultsDir" -ForegroundColor Red
	Write-Host "Run a suite first, e.g.:" -ForegroundColor Yellow
	Write-Host "  dotnet test Testing.SpeedMerchants.Unit\Testing.SpeedMerchants.Unit.csproj ``" -ForegroundColor DarkGray
	Write-Host "    --logger `"trx;LogFileName=unit-results.trx`" --results-directory $ResultsDir" -ForegroundColor DarkGray
	exit 2
}

# 3. Build the display table.
$rows = @()
for ($i = 0; $i -lt $files.Count; $i++) {
	$f = $files[$i]
	$s = Get-TrxSummary -Path $f.FullName
	$rows += [pscustomobject]@{
		'#'        = $i + 1
		File       = $f.Name
		Suite      = $s.Suite
		Age        = Get-HumanAge -When $f.LastWriteTime
		Size       = Get-HumanSize -Bytes $f.Length
		Passed     = $s.Passed
		Failed     = $s.Failed
		Skipped    = $s.Skipped
		_Path      = $f.FullName
		_Suite     = $s.Suite
		_Counters  = $s
	}
}

# 4. Render the table (hide internal columns).
Write-Host ""
Write-Host "Available TRX runs in $ResultsDir" -ForegroundColor Cyan
Write-Host ("-" * 80) -ForegroundColor DarkGray
$rows | Format-Table '#', File, Suite, Age, Size, Passed, Failed, Skipped -AutoSize | Out-Host
Write-Host ("-" * 80) -ForegroundColor DarkGray

# 4b. List mode (agent-safe): emit machine-readable CANDIDATE: lines and exit WITHOUT prompting.
# The agent presents these to the user, then re-runs this script with -Choice N.
if ($List -and $Choice -le 0) {
	foreach ($r in $rows) {
		Write-Host ("CANDIDATE:#={0};File={1};Suite={2};Failed={3};Passed={4};Skipped={5};Path={6}" -f `
			$r.'#', $r.File, $r._Suite, $r._Counters.Failed, $r._Counters.Passed, $r._Counters.Skipped, $r._Path)
	}
	exit 0
}

# 5. Get the user's choice (param or interactive prompt).
if ($Choice -le 0) {
	# Read-Host hangs a non-interactive host; only reachable via the bare human form.
	$choiceInput = Read-Host "Enter the number of the TRX to analyse (1-$($rows.Count)), or blank to cancel"
	if ([string]::IsNullOrWhiteSpace($choiceInput)) {
		Write-Host "Cancelled." -ForegroundColor Yellow
		exit 3
	}
	if (-not [int]::TryParse($choiceInput, [ref]$Choice)) {
		Write-Host "ERROR: '$choiceInput' is not a number." -ForegroundColor Red
		exit 3
	}
}

if ($Choice -lt 1 -or $Choice -gt $rows.Count) {
	Write-Host "ERROR: Choice $Choice is out of range (1-$($rows.Count))." -ForegroundColor Red
	exit 3
}

$picked = $rows[$Choice - 1]

# 6. Emit the structured selection. Agents can grep these SELECTED:* lines.
Write-Host ""
Write-Host "Selected:" -ForegroundColor Green
Write-Host "SELECTED:Path=$($picked._Path)"
Write-Host "SELECTED:File=$($picked.File)"
Write-Host "SELECTED:Suite=$($picked._Suite)"
Write-Host "SELECTED:Total=$($picked._Counters.Total)"
Write-Host "SELECTED:Passed=$($picked._Counters.Passed)"
Write-Host "SELECTED:Failed=$($picked._Counters.Failed)"
Write-Host "SELECTED:Skipped=$($picked._Counters.Skipped)"

# 7. Emit the top failure clusters (class :: first-line-of-message) so the agent can start
#    the loop on the largest shared root cause without a second parsing pass.
if ($picked._Counters.Failed -gt 0) {
	try {
		[xml]$ft = Get-Content -LiteralPath $picked._Path -ErrorAction Stop
		$fnm = New-Object System.Xml.XmlNamespaceManager((New-Object System.Xml.NameTable))
		$fnm.AddNamespace('t', 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010')
		$idToClass = @{}
		foreach ($u in $ft.SelectNodes('//t:UnitTest', $fnm)) { $idToClass[$u.id] = $u.TestMethod.className }
		$clusters = $ft.SelectNodes('//t:UnitTestResult[@outcome="Failed"]', $fnm) | ForEach-Object {
			$cls  = (($idToClass[$_.testId] -split ',')[0] -split '\.')[-1]
			$msg  = $_.Output.ErrorInfo.Message
			$line = if ($msg) { ($msg -split [char]10)[0].Trim() } else { '' }
			'[' + $cls + '] ' + $line.Substring(0, [Math]::Min(110, $line.Length))
		} | Group-Object | Sort-Object Count -Descending

		Write-Host ""
		Write-Host "Top failure clusters (largest shared root cause first):" -ForegroundColor Yellow
		foreach ($g in $clusters) { Write-Host ("CLUSTER:Count={0};{1}" -f $g.Count, $g.Name) }
	} catch {
		Write-Host "WARN: could not cluster failures ($($_.Exception.Message))" -ForegroundColor DarkYellow
	}
}

exit 0
