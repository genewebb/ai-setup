# Finds the READY acceptance clauses no row names in a CLOSED group (the only cause of 'left to plan unknown' that a row
# can fix) and, with -Apply, cuts ONE audit row in an open group that names them all, so the status tile reads a number
# again in the same planner cycle (kit item IN-20261107230646-ea2e: the '?' came back four times, each after a requirements
# row re-READYed a file or added clause ids in a closed group and nothing named the new ids).
#   -IncludeNoGroup : also name the clauses no group scope includes (they never make the count unknown).
#   -Group          : the group the audit row goes into; default the first focus group, else the first unclosed group.
# Output: 'UNNAMED <group> <n>: <ids>' per group, then 'CLEAN' (nothing to name), 'DRY <n> clause(s)' (no -Apply), or
# 'CUT <id> <n> clause(s) in <group>'. Exit 0; 2 when -Apply cannot place the row (no open group, Add-Tasks refused).
# An audit row names the clauses in its why, so a second run finds nothing: the script is safe to run every cycle.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string] $Session,
    [string] $Group,
    [switch] $IncludeNoGroup,
    [switch] $Apply
)
. "$PSScriptRoot\lib\Streams.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
if ($Apply -and -not $Session) { Write-Output 'REFUSED -Apply needs -Session'; exit 2 }

$model = & "$PSScriptRoot\Get-StreamStatus.ps1" -Repo $P.Repo -Json | ConvertFrom-Json -AsHashtable -Depth 50
$ltp = $model['leftToPlan']
if (-not $ltp -or -not $ltp['root']) { Write-Output "NO-REQUIREMENTS $(if ($ltp) { $ltp['reason'] })"; exit 0 }
$doc = Read-Tasks $P
$closed = @($doc.groups | Where-Object { $_.state -eq 'closed' } | ForEach-Object { [string]$_.id })
$keys = @($closed); if ($IncludeNoGroup) { $keys += 'none' }
$picked = [ordered]@{}
foreach ($k in $keys) {
    if (-not $ltp['unnamedIds'] -or -not $ltp['unnamedIds'].Contains($k)) { continue }
    $ids = @($ltp['unnamedIds'][$k] | Where-Object { $_ })
    if ($ids.Count) { $picked[$k] = $ids; Write-Output "UNNAMED $k $($ids.Count): $($ids -join ', ')" }
}
$all = @($picked.Values | ForEach-Object { $_ })
if (-not $all.Count) { Write-Output 'CLEAN'; exit 0 }
if (-not $Apply) { Write-Output "DRY $($all.Count) clause(s)"; exit 0 }

if (-not $Group) { $Group = Get-FocusGroup $doc $P }
if (-not $Group) { $Group = @($doc.groups | Where-Object { $_.state -ne 'closed' } | ForEach-Object { [string]$_.id }) | Select-Object -First 1 }
$g = @($doc.groups | Where-Object { [string]$_.id -eq $Group }) | Select-Object -First 1
if (-not $g -or $g.state -eq 'closed') { Write-Output "REFUSED no open group to hold the audit row ($Group)"; exit 2 }
$n = 0
foreach ($t in @($doc.tasks)) { if ([string]$t.id -match "^$([regex]::Escape($Group))\.T(\d+)$") { $n = [Math]::Max($n, [int]$Matches[1]) } }
$id = '{0}.T{1:D3}' -f $Group, ($n + 1)
$doc2 = "docs/audit/$id-UNNAMED-CLAUSES.md"
$list = (@($picked.Keys | ForEach-Object { "$_$(if ($_ -eq 'none') { ' (no group)' } else { ' (closed)' }): $(@($picked[$_]) -join ', ')" }) -join '; ')
$title = "LEFT-TO-PLAN AUDIT (Find-UnnamedClauses.ps1). These READY acceptance clauses are named by no row, so the status " +
    "page cannot count left to plan: $list. For each clause: read it at the file's current revision and find the shipped " +
    "test that proves it (file and test name) and the code that meets it (file:line). Write $doc2 with one line per " +
    "clause: id | built+tested / built-untested / partial / contradicts-text / missing | test | code. Send stream-plan " +
    "one inbox item listing every clause that is not built+tested, grouped by write set, for fix or test rows. No code, " +
    "no requirement edit."
$row = [ordered]@{ id = $id; group = $Group; kind = 'docs'; origin = 'plan'; title = $title; why = @($all)
    writeSet = @($doc2); dependsOn = @(); tests = [ordered]@{ targeted = @() }; estMinutes = [Math]::Min(120, 30 + 2 * $all.Count) }
$tmp = Join-Path $P.Root "tmp-unnamed-$id.json"
[ordered]@{ tasks = @($row) } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $tmp -Encoding utf8
try { $r = @(& "$PSScriptRoot\Add-Tasks.ps1" -Repo $P.Repo -Role plan -Session $Session -File $tmp 2>&1); $x = $LASTEXITCODE }
finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
$r | ForEach-Object { Write-Output "  $_" }
if ($x -ne 0 -or -not ($r -match "ADDED $([regex]::Escape($id))")) { Write-Output "REFUSED Add-Tasks exit $x"; exit 2 }
Write-Output "CUT $id $($all.Count) clause(s) in $Group"
exit 0
