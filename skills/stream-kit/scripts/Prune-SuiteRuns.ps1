# Deletes the bulky per-run output folders under .streams\suites\runs (leg logs, trx, Playwright output, proofs,
# coverage) once nothing reads them any more (kit item IN-20261126203801-9b5e: 152 folders held ~19.8 GB on D: on
# 2026-11-26 with the drive at its 5 GB floor).
#   Only a folder runs\<run>\ is deleted. The run record <run>.json, <run>.results.json, <run>.attribution.json,
#   <run>.fixes.json and every other file beside the folders are never touched: they are what Test-GroupClose.ps1,
#   Invoke-Retest.ps1 and the status page read after a run's export.
#   A folder goes only when all of these hold:
#     - its record <run>.json exists and parses, and its status is not 'running';
#     - the record ended (endedAt, else startedAt for an abandoned run) more than -KeepDays ago;
#     - <run>.results.json exists, or the record's status is 'abandoned' (an abandoned run exported nothing);
#     - every group the record names (group and groups) is closed on the board.
#   A folder with no record is left alone and reported as ORPHAN.
# Prints "PRUNED <run> <MB> MB" (WOULD-PRUNE with -DryRun, nothing deleted) per folder, "ORPHAN <dir>" per folder with
# no record, then "PRUNE-DONE runs <n> MB <n> kept <n>". A folder that cannot be deleted whole (a file still held) is
# "PRUNE-PARTIAL <run> <reason>" and does not fail the run. Exit 0.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [int] $KeepDays = 7,
    [string] $Session = 'prune-suite-runs',
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$rd = Join-Path $P.Root 'suites\runs'
$n = 0; $mb = 0.0; $kept = 0
if (-not (Test-Path -LiteralPath $rd)) { "PRUNE-DONE runs 0 MB 0 kept 0"; exit 0 }
$doc = Read-Tasks $P
$closed = @{}; foreach ($g in @($doc.groups)) { if ([string]$g.state -eq 'closed') { $closed[[string]$g.id] = $true } }
$cutoff = (Get-Date).ToUniversalTime().AddDays(-$KeepDays)

function ConvertTo-UtcTime($v) {
    if ($null -eq $v -or "$v" -eq '') { return $null }
    if ($v -is [datetime]) { return $v.ToUniversalTime() }
    [datetime]::Parse([string]$v, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
}

foreach ($dir in @(Get-ChildItem -LiteralPath $rd -Directory | Sort-Object Name)) {
    $id = $dir.Name
    $recFile = Join-Path $rd "$id.json"
    if (-not (Test-Path -LiteralPath $recFile)) { "ORPHAN $id"; $kept++; continue }
    $rec = try { Get-Content -LiteralPath $recFile -Raw | ConvertFrom-Json -AsHashtable -DateKind String } catch { $null }
    if ($null -eq $rec) { $kept++; continue }
    $status = [string]$rec['status']
    if ($status -eq 'running' -or $status -eq '') { $kept++; continue }
    $end = ConvertTo-UtcTime $rec['endedAt']
    if ($null -eq $end) { $end = ConvertTo-UtcTime $rec['startedAt'] }
    if ($null -eq $end -or $end -gt $cutoff) { $kept++; continue }
    if ($status -ne 'abandoned' -and -not (Test-Path -LiteralPath (Join-Path $rd "$id.results.json"))) { $kept++; continue }
    $groups = @(@([string]$rec['group']) + @($rec['groups'] | ForEach-Object { [string]$_ }) | Where-Object { $_ } | Select-Object -Unique)
    if ($groups.Count -eq 0 -or @($groups | Where-Object { -not $closed[$_] }).Count -gt 0) { $kept++; continue }
    $size = [double](@([IO.Directory]::EnumerateFiles($dir.FullName, '*', [IO.SearchOption]::AllDirectories) | ForEach-Object { ([IO.FileInfo]::new($_)).Length }) | Measure-Object -Sum).Sum
    $m = [math]::Round($size / 1MB, 1)
    if ($DryRun) { "WOULD-PRUNE $id $m MB"; $n++; $mb += $m; continue }
    try {
        Remove-Item -LiteralPath $dir.FullName -Recurse -Force
        "PRUNED $id $m MB"; $n++; $mb += $m
    } catch {
        "PRUNE-PARTIAL $id $((("$_" -split "`n")[0]))"; $kept++
    }
}
if (-not $DryRun -and $n -gt 0) {
    try { Add-Content -LiteralPath ($P.Decisions) -Value "- $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) $Session Prune-SuiteRuns: deleted $n run output folder(s), $([math]::Round($mb,1)) MB (closed groups, ended over $KeepDays days ago; records and results kept)" } catch { }
}
"PRUNE-DONE runs $n MB $([math]::Round($mb,1)) kept $kept"
exit 0
