# Closes a group: stream-integrate step C as a script, so no session picks the rows by hand.
#   Close-Group.ps1 -Repo <repo> -Session <id> -Group <G> [-DryRun]
# Step C used to be done by the model, and on 2026-10-05 the coordinator that closed G3 moved every row whose id began
# 'G3.' to done. G1.T24 and G1.T25 had been moved into G3 by a plan revision (owner ruling 5ad8: "the id keeps its
# original prefix"), so they stayed integrated in a closed group (kit item IN-20261006110728-8c21). A row's group is its
# `group` field, never its id prefix, and here the rows are the group's own rows plus its group set
# (lib\Activation.ps1 Get-GroupSet: rows whose EFFECTIVE group is <G>), the same set Test-GroupClose.ps1 judged.
#
# An open group closes only on `Test-GroupClose.ps1 -DryRun` answering CLOSE-OK; anything else is printed and the script
# exits 1 with nothing written. When the group's integration row has a grader (artifacts.grader), that grader then runs
# on the main tree (`Invoke-Grader.ps1 -Label close`), and a non-zero exit is NOT-CLOSED, exit 1, nothing written.
# Then, under the tasks lock, in one write:
#   - every integrated row of the set goes to done, and so does the integration row (ticketed or building);
#   - a row in any other state refuses the whole close (ROW-STATE <id> <state>, exit 2, nothing written);
#   - the group goes to closed (closedAt set).
# Then the close is logged in decisions.md and each row's recorded worktree that still exists gets a 'ready to remove'
# line in owner\worktrees.md (the owner validates removal; nothing here removes a tree).
# A group that is ALREADY closed is repaired instead: its integrated rows go to done (REPAIRED), a row in any other
# non-done state is reported (ANOMALY, exit 2) and left as it is.
# Prints DONE <id> per row moved, then CLOSED <G> rows <n> (or REPAIRED <G> rows <n>, or NOTHING <G>), exit 0.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [string] $Group,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Activation.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo

$doc0 = Read-Tasks $P
$g0 = @($doc0.groups | Where-Object { [string]$_.id -eq $Group }) | Select-Object -First 1
if (-not $g0) { "UNKNOWN-GROUP $Group"; exit 2 }
$repair = ([string]$g0.state -eq 'closed')
if (-not $repair) {
    $chk = @(& "$PSScriptRoot\Test-GroupClose.ps1" -Repo $Repo -Group $Group -Session $Session -DryRun)
    $chkx = $LASTEXITCODE
    if ($chkx -ne 0 -or -not @($chk | Where-Object { "$_" -like "CLOSE-OK $Group*" }).Count) {
        $chk | ForEach-Object { "$_" }
        "NOT-CLOSED $Group : Test-GroupClose did not answer CLOSE-OK, nothing written"
        exit 1
    }
    # The integration row's own grader is part of the close. CLOSE-OK judges the suites and the rows, not the close-out
    # deliverables an integration ticket can ask for (G5.T900's per-AC evidence matrix and saved CLOSE-OK record), so
    # without this a close went through with that work undone and no script noticed (kit item IN-20261009024507-d229).
    # It runs against the main tree, beating the integrator lock for the session closing the group. A dry run names it
    # and does not run it.
    $its = @($doc0.tasks | Where-Object { $_.kind -eq 'integration' -and [string]$_.group -eq $Group -and [string]$_.state -ne 'done' -and $_.ContainsKey('artifacts') -and $_.artifacts -and $_.artifacts.ContainsKey('grader') -and $_.artifacts['grader'] })
    foreach ($it in $its) {
        if ($DryRun) { "GRADER $($it.id) would run (-Label close) before the close"; continue }
        $gout = @(& "$PSScriptRoot\Invoke-Grader.ps1" -Repo $Repo -Task ([string]$it.id) -Root $Repo -Label close -BeatSession $Session)
        $gx = $LASTEXITCODE
        if ($gx -ne 0) {
            $gout | ForEach-Object { "$_" }
            "NOT-CLOSED $Group : the integration task $($it.id)'s grader failed (exit $gx, log .streams\logs\$($it.id).grader.close.txt), nothing written"
            exit 1
        }
        "GRADER $($it.id) passed (-Label close)"
    }
}

# The rows: own group by field, plus the group set. Computed inside the lock, on the document that is written.
function Get-CloseRows($doc) {
    $set = Get-GroupSet $doc $Group
    @($doc.tasks | Where-Object { [string]$_.group -eq $Group -or $set.Contains([string]$_.id) })
}
function Get-CloseMoves($rows) {
    $moves = [Collections.Generic.List[object]]::new(); $bad = [Collections.Generic.List[string]]::new()
    foreach ($t in $rows) {
        $st = [string]$t.state
        if ($st -eq 'done') { continue }
        if ($st -eq 'integrated') { $moves.Add($t); continue }
        if (-not $repair -and $t.kind -eq 'integration' -and $st -in @('ticketed', 'building')) { $moves.Add($t); continue }
        $bad.Add("$($t.id) $st")
    }
    @{ moves = $moves; bad = $bad }
}

$moved = @(); $bad = @(); $trees = @()
if ($DryRun) {
    $plan = Get-CloseMoves (Get-CloseRows $doc0)
    $moved = @($plan.moves | ForEach-Object { [string]$_.id }); $bad = @($plan.bad)
} else {
    $res = @{ moved = @(); bad = @(); trees = @() }
    [void](Invoke-TasksLocked $P $Session {
        param($d)
        $g = @($d.groups | Where-Object { [string]$_.id -eq $Group }) | Select-Object -First 1
        $plan = Get-CloseMoves (Get-CloseRows $d)
        $res.bad = @($plan.bad)
        if ($res.bad.Count -and -not $repair) { return $null }      # refuse the whole close: nothing written
        foreach ($t in $plan.moves) {
            $note = if ($repair) { "group $Group was closed with this row left $($t.state); Close-Group repair" } else { "group $Group closed (Close-Group.ps1)" }
            Set-TaskState $t 'done' 'integrate' $Session $note
            $res.moved += [string]$t.id
            if ($t.ContainsKey('base') -and $t.base -and $t.base.worktree -and (Test-Path -LiteralPath ([string]$t.base.worktree))) { $res.trees += , @([string]$t.id, [string]$t.base.worktree) }
        }
        if (-not $repair) { $g.state = 'closed'; $g['closedAt'] = (Get-Now) }
        if ($repair -and -not $res.moved.Count) { return $null }   # a repair with nothing to move writes nothing
        $d
    })
    $moved = @($res.moved); $bad = @($res.bad); $trees = @($res.trees)
}

$moved | ForEach-Object { "DONE $_" }
if ($bad.Count) {
    $tag = if ($repair) { 'ANOMALY' } else { 'ROW-STATE' }
    $bad | ForEach-Object { "$tag $_" }
    if (-not $repair) { "NOT-CLOSED $Group : $($bad.Count) row(s) neither integrated nor done, nothing written"; exit 2 }
}
$prefixOff = @($moved | Where-Object { $_ -notlike "$Group.*" })
$offNote = if ($prefixOff.Count) { "; rows whose id prefix is not ${Group}: $($prefixOff -join ', ')" } else { '' }
if ($DryRun) {
    "DRY-RUN $(if ($repair) { 'repair' } else { 'close' }) $Group rows $($moved.Count)$offNote"
    if ($bad.Count) { exit 2 }; exit 0
}
if ($repair) {
    if (-not $moved.Count) { "NOTHING $Group : already closed and every row is done"; if ($bad.Count) { exit 2 }; exit 0 }
    Add-Decision $P $Session "GROUP $Group REPAIRED by Close-Group.ps1: $($moved.Count) row(s) of the closed group moved integrated -> done ($($moved -join ', '))$offNote"
} else {
    Add-Decision $P $Session "GROUP $Group CLOSED by Close-Group.ps1 on CLOSE-OK: $($moved.Count) row(s) moved to done$offNote"
}
foreach ($tr in $trees) { Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | ready to remove (group {3} closed; the owner validates removal)" -f $tr[0], $tr[1], (Get-Now), $Group) }
"$(if ($repair) { 'REPAIRED' } else { 'CLOSED' }) $Group rows $($moved.Count)$offNote"
if ($bad.Count) { exit 2 }
exit 0
