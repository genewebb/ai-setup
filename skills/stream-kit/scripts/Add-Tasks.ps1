# Adds groups and tasks from a JSON file ({groups:[...], tasks:[...]}) under the lock.
#   -Role plan      : plan approve / import. Groups are added or updated; tasks enter as planned, or as ticketed when
#                     they arrive with a reviewed ticket and grader (import).
#   -Role integrate : fix tasks (origin integration). A fix whose write set overlaps a task that has not landed yet
#                     (planned..built, blocked) joins that task as a history note instead of becoming a second task on the
#                     same files. A fix on the files of an already integrated task becomes its own task that depends on
#                     it (a gate fail always lands here). A fix added to a group whose integration task is done reopens
#                     that task (done -> ticketed) and a closed group (-> integrating), so the suites run again.
# Refuses the whole file (writes nothing, exit 2) if any task lacks why ids or a write set, or if two open tasks would
# share a file without one depending (transitively) on the other.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [ValidateSet('plan', 'integrate')] [string] $Role,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [string] $File
)
. "$PSScriptRoot\lib\Streams.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$in = Get-Content -Raw $File | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50

$problems = [Collections.Generic.List[string]]::new()
$report = [Collections.Generic.List[string]]::new()
[void](Invoke-TasksLocked $P $Session {
    param($doc)
    $open = @($doc.tasks | Where-Object { $_.state -notin @('done') -and $_.kind -notin @('gate', 'integration') })
    $ids = @($doc.tasks | ForEach-Object { $_.id })
    $new = @()
    # Every task this batch can reach, built once: the old loop rebuilt it, and walked the dependency chain twice, for
    # every (new row, open row) pair before it even looked at the write sets, so an 81-row release held the lock for
    # 15 min (kit item IN-20261010174706-ed53). The chain only matters for a pair that shares a file, so the overlap is
    # tested first. The index holds the batch's own objects, so a CHAINED edge added below is seen by later pairs.
    $known = @($doc.tasks) + @($in['tasks'])
    $byId = Get-TaskIndex $known
    # Write sets indexed once too, so each new row is compared in full only with the rows it can overlap: the pairwise
    # comparison was still ~15 s of an 81-row release's lock hold on the 1016-row board (kit item IN-20261010181957-2e7f).
    $wsIndex = New-WriteSetIndex
    foreach ($o in $open) { Add-WriteSetIndex $wsIndex $o }
    foreach ($t in @($in['tasks'])) {
        if (-not $t) { continue }
        if (-not @($t.why).Count) { $problems.Add("$($t.id): no REQ/AC ids in why") }
        if ($t.kind -notin @('gate', 'integration') -and -not @($t.writeSet).Count) { $problems.Add("$($t.id): no write set") }
        if ($t.id -in $ids) { $problems.Add("$($t.id): id already exists") }
        $cand = if ($t.kind -in @('gate', 'integration')) { $null } else { Get-WriteSetCandidates $wsIndex $t.writeSet }
        foreach ($o in @($open) + @($new)) {
            if ($t.kind -in @('gate', 'integration')) { break }
            if ($null -ne $cand -and -not $cand.Contains($o)) { continue }
            if (Test-WriteSetOverlap $t.writeSet $o.writeSet) {
                if ((Test-DependsOnChain $known $t $o.id $byId) -or (Test-DependsOnChain $known $o $t.id $byId)) { continue }
                if ($Role -eq 'integrate' -and $o.state -eq 'integrated') {
                    # landed already: a history note there would never be acted on; build on top of it instead
                    $t['dependsOn'] = @(@($t['dependsOn']) + $o.id | Where-Object { $_ } | Select-Object -Unique)
                    $report.Add("CHAINED $($t.id) after $($o.id)")
                    continue
                }
                if ($Role -eq 'integrate' -and $o.state -ne 'done') {
                    Add-History $o $Session $o.state "integration fix joined: $($t.title) [$(@($t.writeSet) -join ', ')]"
                    $report.Add("JOINED $($t.id) into $($o.id)")
                    $t = $null; break
                }
                $problems.Add("$($t.id): write set overlaps $($o.id)")
            }
        }
        if (-not $t) { continue }
        foreach ($k in @('dependsOn', 'writeSet', 'why')) { if (-not $t.ContainsKey($k) -or $null -eq $t[$k]) { $t[$k] = @() } }
        # Same rule as -AddWriteSet: one JSON element holding several comma-separated paths becomes several entries,
        # because a joined entry overlaps nothing and exports nothing (see Expand-PathList).
        $t['writeSet'] = @(Expand-PathList $t['writeSet'])
        # Every edge gets its reason (lib\Streams.ps1 Set-DependsWhyDefaults): the planner's own text is kept, the
        # mechanical ones are filled in, the rest read 'unstated' for the DEP-REVIEW board flag.
        [void](Set-DependsWhyDefaults $known $t $byId)
        if (-not $t.ContainsKey('artifacts') -or -not $t.artifacts) { $t.artifacts = [ordered]@{ ticket = $null; grader = $null; patch = $null; verdict = $null } }
        if (-not $t.ContainsKey('origin')) { $t.origin = if ($Role -eq 'integrate') { 'integration' } else { 'plan' } }
        $state = if ($t.artifacts.ticket -and $t.artifacts.grader) { 'ticketed' } else { 'planned' }
        $t.state = $state
        $t.claim = $null
        $t.history = @([ordered]@{ at = (Get-Now); by = $Session; to = $state; note = "added ($($t.origin))" })
        $new += , $t
        Add-WriteSetIndex $wsIndex $t
        $report.Add("ADDED $($t.id) $state")
    }
    $allIds = $ids + @($new | ForEach-Object { $_.id })
    foreach ($t in $new) { foreach ($d in @($t.dependsOn)) { if ($d -and $d -notin $allIds) { $problems.Add("$($t.id): depends on unknown $d") } } }
    # A NON-GATE ROW THAT DEPENDS ON ITS OWN GROUP'S INTEGRATION TASK DEADLOCKS THE GROUP, and nothing else catches
    # it: stream-integrate claims the integration task once every code, docs and mockup row in the group is
    # integrated, while Claim-Task.ps1 only offers a ticketed row whose dependencies are built or later - so the row
    # waits for the integration task and the integration task waits for the row. Measured on G1.T12 on 2026-09-30,
    # the Reference Data evidence package, which is built FROM the G1 green run (kit item IN-20260930190112-23e6).
    # Gate rows are exempt: step B does not wait for a gate, which is why seven of them carry the same edge safely.
    # The escape is a written ruling, not a quiet exception: a row that genuinely needs the shape needs the
    # integrator's step-B precondition amended for that group, as it was for G1.
    $intByGroup = @{}
    foreach ($t in @($doc.tasks) + @($new)) { if ($t['kind'] -eq 'integration') { $intByGroup[[string] $t['group']] = [string] $t['id'] } }
    foreach ($t in $new) {
        if ($t['kind'] -eq 'gate') { continue }
        $own = $intByGroup[[string] $t['group']]
        if ($own -and $own -in @($t.dependsOn)) {
            $problems.Add("$($t.id): dependsOn $own, its own group's integration task, which deadlocks $($t['group']) - the integration task waits for this row to be integrated and this row waits for the integration task to be built. Split the row so the part that needs the group's green run is a gate, or have the integrator's step-B precondition amended for this group first")
        }
    }
    # Groups close in priority order, so an integration task never waits on a row of a later group (owner ruling
    # IN-20261001193348-5979; lib\Streams.ps1 Get-LaterGroupDepProblems). The batch's own groups count, in board order.
    $allGroups = @($doc.groups) + @(@($in['groups']) | Where-Object { $_ -and $_['id'] -notin @($doc.groups | ForEach-Object { $_.id }) })
    foreach ($t in $new) { foreach ($p in (Get-LaterGroupDepProblems $allGroups (@($doc.tasks) + @($new)) $t @($t.dependsOn))) { $problems.Add("$($t.id): $p") } }
    if ($problems.Count) { return $null }
    foreach ($g in @($in['groups'])) {
        if (-not $g) { continue }
        $existing = @($doc.groups | Where-Object { $_.id -eq $g.id })
        if ($existing.Count) { foreach ($k in $g.Keys) { $existing[0][$k] = $g[$k] } } else { $doc.groups = @($doc.groups) + , $g }
        $report.Add("GROUP $($g.id) $($g.state)")
    }
    $doc.tasks = @($doc.tasks) + $new
    if ($Role -eq 'integrate') {
        foreach ($gid in @($new | ForEach-Object { $_.group } | Select-Object -Unique)) {
            $fixIds = @($new | Where-Object { $_.group -eq $gid } | ForEach-Object { $_.id }) -join ', '
            foreach ($it in @($doc.tasks | Where-Object { $_.group -eq $gid -and $_.kind -eq 'integration' -and $_.state -eq 'done' })) {
                Set-TaskState $it 'ticketed' 'integrate' $Session "reopened: fix task(s) $fixIds added after the suites passed; re-run before the group closes"
                $report.Add("REOPENED $($it.id)")
            }
            foreach ($g in @($doc.groups | Where-Object { $_.id -eq $gid -and $_.state -eq 'closed' })) { $g.state = 'integrating'; $report.Add("GROUP $gid integrating (reopened)") }
        }
    }
    $doc
})
if ($problems.Count) { $problems | ForEach-Object { "REFUSED $_" }; exit 2 }
$report
Add-Decision $P $Session ("Add-Tasks ({0}): {1}" -f $Role, ($report -join '; '))
# An explicit 0: every other write script ends with one, and without it a successful batch leaves $LASTEXITCODE at
# whatever a previous refusal in the same pwsh process set (measured 2026-09-30: a valid gate row was added and read
# back as exit 2 because the batch before it was refused).
exit 0
