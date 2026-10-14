# Read-only check that the board is ordered (lib\Board.ps1): no unknown dependsOn ids, no dependsOn cycle, and no two
# open tasks sharing a write-set path without a dependsOn chain between them. Prints CLEAN (exit 0), or one line per
# problem (CYCLE / UNKNOWN-DEP / UNORDERED a / b : path) and exits 2. Run it after any plan edit that did not go through
# Add-Tasks.ps1 or Revise-Task.ps1 (both refuse to write an unordered board).
param([Parameter(Mandatory)] [string] $Repo)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Board.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$doc = Read-Tasks $P
$problems = Get-BoardProblems $doc.tasks
# A write-set entry holding a separator is a path that matches no file: it overlaps nothing, so the ordering check
# reads CLEAN with it present and only Export-TaskPatch notices, by answering OUTSIDE for a file the row does own
# (kit items IN-20260930184321-a743 and IN-20260930210802-1c51, both measured on G3.T100). REPORTED, never a
# problem: Get-BoardProblems is what Add-Tasks.ps1 and Revise-Task.ps1 refuse a whole batch on, so making this a
# problem would block every plan edit until somebody repaired the row - including the edit that repairs it.
$malformed = [Collections.Generic.List[string]]::new()
foreach ($t in @($doc.tasks)) {
    foreach ($w in @($t['writeSet'])) {
        if ("$w" -match '[,;"'']') { $malformed.Add("MALFORMED $($t['id']) write-set entry, remove it by naming it exactly: $w") }
    }
}
if (-not $problems.Count) { 'CLEAN'; $malformed; exit 0 }
$problems
$malformed
exit 2
