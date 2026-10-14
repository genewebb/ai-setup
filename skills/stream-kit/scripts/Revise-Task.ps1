# Plan revisions of released tasks, applied as ONE batch under the lock: write-set and dependsOn changes, title, targeted
# tests, and the release of a blocked task. The batch is checked with lib\Board.ps1 BEFORE anything is written: if the
# result would hold an unknown dependsOn id, a cycle, or two open tasks on one path without a dependsOn chain, the whole
# batch is refused (exit 2, nothing written) and each problem is printed. Order the tasks in the same batch that makes
# them share a file (for example "B +writeSet f" together with "C +dependsOn B" when C also owns f).
# addWriteSet splits a comma- or semicolon-joined value into separate paths; removeWriteSet does NOT, so an entry
# stored in that broken shape can be named exactly as it is stored. Pass an array to remove several paths.
#   -File <json>   { "note": "why (inbox ids)", "edits": [ { "task": "G3.T025", "addWriteSet": [], "removeWriteSet": [],
#                    "addDependsOn": [], "removeDependsOn": [], "title": "...", "tests": ["FullyQualifiedName~X"],
#                    "addWhy": [], "removeWhy": [], "estMinutes": 130, "estBasis": "why that many minutes",
#                    "release": "auto|planned|ticketed|keep|block|retire", "note": "..." } ] }
#   or one task inline: -Task -AddWriteSet -RemoveWriteSet -AddDependsOn -RemoveDependsOn -AddWhy -RemoveWhy -Title -Group -EstMinutes -EstBasis -Release -Note
# group: a row's GROUP is the planner's only lever on the claim ORDER, because Claim-Task.ps1:47 sorts fix-first, then
# group rank, then chain depth - so a short row that gates the FIRST group's close can sit almost last while it lives
# in a later group (owner ruling on G3.T149, kit item IN-20260930210139-4afa). A move KEEPS the row's id: G3.T149 in
# G1 is still G3.T149, because an id is a name, and renaming it would orphan every ticket, grader, patch, verdict and
# inbox item that already cites it. The move is refused when: the group id is not on the board; the row is a gate or
# an integration task, whose group IS its identity; the row holds a live claim, because its ticket, grader and
# worktree belong to a run of the old group; the target group is not released or integrating, since Claim-Task.ps1:35
# skips such a row and the move would silently hide it; either group's integration task has already landed, because
# that group's suites ran over a membership this would change; or the batch leaves the integration wiring wrong - the
# old group's integration task must stop depending on the row and the new group's must start, in the SAME batch.
# estMinutes: a released task whose write set or title changes is usually mispriced afterwards, and until 2026-09-30 no
# role could correct it - G2.T97 carried 65 minutes for work measured at 110-150, G2.T36 70 for a seven-file row and
# G2.T99 45 for a row two files wider, so every watchdog line and every group ETA read from them was wrong. A change
# must be a positive whole number and must state its new estBasis in the SAME edit, because the old basis is exactly
# what the new number makes false. estBasis may also be corrected on its own. kind is still not changeable here.
# why ids: a REQ/AC that no task carries is never counted by a group's evidence matrix, and before 2026-09-29 a plan
# session could only give an orphaned AC an owner by creating a task for it (kit item IN-20260929161555-34cc). A task
# always keeps at least one why id: an edit that would empty the list is refused.
# release (default auto): a blocked task goes to ticketed when it holds a ticket and a grader, else to planned; any other
#   state is kept. keep leaves a blocked task blocked (for example "until X is ticketed").
#   An edit that changes NOTHING but its note and names no release keeps the state (it never releases a blocked row).
#   block parks a planned or ticketed row (no live claim) as blocked; it needs a note that names the release condition.
#   retire ends a BLOCKED row the planner withdrew as superseded: state done plus a `retired` record, counted apart
#   from landed work on the board (kit item IN-20261009150944-5bbd). Refused unless the row has a note saying why, no
#   live claim, an empty write set (after this batch's edits) and no open row depending on it - an integration task
#   is a row, so its dependsOn must drop the id in this batch or earlier. Prints RETIRED. A row already DONE as a
#   withdrawal (never integrated, no patch, not a gate or integration task) is marked retired in place: RETIRED
#   (backfill); RETIRE-ALREADY, RETIRE-KIND and RETIRE-LANDED refuse the rest.
# Prints one REVISED line per task (plus RELEASED/KEPT), logs history on each task and one line in decisions.md.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [string] $File = '',
    [string] $Task = '',
    [string[]] $AddWriteSet = @(),
    [string[]] $RemoveWriteSet = @(),
    [string[]] $AddDependsOn = @(),
    [string[]] $RemoveDependsOn = @(),
    [string[]] $AddWhy = @(),
    [string[]] $RemoveWhy = @(),
    [string] $Title = '',
    [string] $Group = '',
    [int] $EstMinutes = 0,
    [string] $EstBasis = '',
    [ValidateSet('auto', 'planned', 'ticketed', 'keep', 'block', 'retire')] [string] $Release = 'auto',
    [string] $Note = ''
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Board.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path

if ($File) { $in = Get-Content -Raw $File | ConvertFrom-Json -AsHashtable -Depth 20 }
elseif ($Task) {
    $in = @{ note = $Note; edits = @(@{ task = $Task; addWriteSet = $AddWriteSet; removeWriteSet = $RemoveWriteSet; addDependsOn = $AddDependsOn; removeDependsOn = $RemoveDependsOn; addWhy = $AddWhy; removeWhy = $RemoveWhy; title = $Title; group = $Group; estMinutes = $EstMinutes; estBasis = $EstBasis; release = $(if ($PSBoundParameters.ContainsKey('Release')) { $Release } else { '' }); note = $Note }) }
} else { 'REFUSED give -File or -Task'; exit 2 }
function Arr($h, $k) { if ($h.Contains($k) -and $null -ne $h[$k]) { @($h[$k] | Where-Object { $_ }) } else { @() } }

$problems = [Collections.Generic.List[string]]::new()
$report = [Collections.Generic.List[string]]::new()
$moved = @{}   # id -> @(from, to), so the integration wiring is checked after every edit in the batch is applied
$retired = [Collections.Generic.List[string]]::new()   # checked for open dependents after every edit in the batch is applied
trap { if ("$_" -like 'TRANSITION-REFUSED*') { "REFUSED $_"; exit 2 } else { break } }
[void](Invoke-TasksLocked $P $Session {
    param($doc)
    foreach ($e in @($in['edits'])) {
        $t = @($doc.tasks | Where-Object { $_.id -eq $e['task'] })
        if ($t.Count -ne 1) { $problems.Add("UNKNOWN-TASK $($e['task'])"); continue }
        $t = $t[0]; $parts = @()
        # Expand-PathList first: an inline -AddWriteSet a.cs,b.cs arrives as one string, and a batch file can carry
        # the same shape in one JSON element.
        # ADD splits, REMOVE does not, and the asymmetry is deliberate. Expand-PathList exists because a shell hands
        # <file[,file]> over as one string, so an ADD must split or it stores a path that matches no file. But an
        # entry already stored in that broken shape can only be removed by NAMING it, and every spelling of it holds
        # a comma: splitting the remove side turned the repair into the removal of the three GOOD paths instead, on
        # G3.T100 at 21:07Z (kit item IN-20260930210802-1c51). A caller removing several paths passes an array.
        $add = @(Expand-PathList (Arr $e 'addWriteSet') | ForEach-Object { ConvertTo-RepoRel $_ }); $rem = @(Arr $e 'removeWriteSet' | Where-Object { $_ } | ForEach-Object { ConvertTo-RepoRel $_ })
        if ($add.Count -or $rem.Count) {
            $t.writeSet = @(@($t.writeSet | Where-Object { (ConvertTo-RepoRel $_) -notin $rem }) + $add | Select-Object -Unique)
            if ($add.Count) { $parts += "ws +$($add -join ', +')" }; if ($rem.Count) { $parts += "ws -$($rem -join ', -')" }
        }
        $ad = @(Arr $e 'addDependsOn'); $rd = @(Arr $e 'removeDependsOn')
        # The same deadlock Add-Tasks.ps1 refuses at creation, refused when an EDIT creates it: a non-gate row that
        # dependsOn its own group's integration task can never be built, because that task is claimed only after
        # every code, docs and mockup row in the group is integrated (kit item IN-20260930190112-23e6, measured on
        # G1.T12). An edge that is already stored is left alone - G1.T12 has a written ruling - so this refuses only
        # what this batch adds.
        if ($ad.Count -and $t['kind'] -ne 'gate') {
            $ownInt = @($doc.tasks | Where-Object { $_['kind'] -eq 'integration' -and [string] $_['group'] -eq [string] $t['group'] })
            if ($ownInt.Count -and $ownInt[0].id -in $ad) {
                $problems.Add("GROUP-DEADLOCK $($t.id): $($ownInt[0].id) is its own group's integration task, so the row would wait for the group and the group for the row. Make the row a gate, or have the integrator's step-B precondition amended for $($t['group']) first")
                continue
            }
        }
        # An integration task never gains an edge onto a LATER group's row (owner ruling IN-20261001193348-5979). Only the
        # edges this batch adds are judged; one already stored predates the rule and is the planner's to remove.
        $lg = @(Get-LaterGroupDepProblems $doc.groups $doc.tasks $t $ad)
        if ($lg.Count) { foreach ($p in $lg) { $problems.Add($p) }; continue }
        if ($ad.Count -or $rd.Count) {
            $t.dependsOn = @(@($t.dependsOn | Where-Object { $_ -and $_ -notin $rd }) + $ad | Select-Object -Unique)
            if ($ad.Count) { $parts += "deps +$($ad -join ', +')" }; if ($rd.Count) { $parts += "deps -$($rd -join ', -')" }
        }
        $aw = @(Arr $e 'addWhy'); $rw = @(Arr $e 'removeWhy')
        if ($aw.Count -or $rw.Count) {
            $left = @(@($t.why | Where-Object { $_ -and $_ -notin $rw }) + $aw | Select-Object -Unique)
            if (-not $left.Count) { $problems.Add("EMPTY-WHY $($t.id): a task keeps at least one REQ/AC id"); continue }
            $t.why = $left
            if ($aw.Count) { $parts += "why +$($aw -join ', +')" }; if ($rw.Count) { $parts += "why -$($rw -join ', -')" }
        }
        $g = if ($e.Contains('group') -and $e['group']) { [string] $e['group'] } else { '' }
        if ($g -and $g -ne [string] $t['group']) {
            $from = [string] $t['group']
            $src = @($doc.groups | Where-Object { $_.id -eq $from }); $dst = @($doc.groups | Where-Object { $_.id -eq $g })
            if (-not $dst.Count) { $problems.Add("UNKNOWN-GROUP $($t.id) -> $g : no group with that id is on the board"); continue }
            if ($t['kind'] -in @('gate', 'integration')) { $problems.Add("GROUP-FIXED $($t.id): a $($t['kind']) task belongs to its group by definition, so moving it would leave the old group without one"); continue }
            if ($t.claim -and (Test-ClaimLive $t)) { $problems.Add("GROUP-CLAIMED $($t.id): $($t.claim.role) $($t.claim.session) holds it, and its ticket, grader and worktree belong to a run of $from - the claim is released first"); continue }
            if ($dst[0].state -notin @('released', 'integrating')) { $problems.Add("GROUP-NOT-RELEASED $($t.id): $g is $($dst[0].state), and Claim-Task.ps1 only offers rows of a released or integrating group, so the move would hide the row instead of hurrying it"); continue }
            if ($src.Count -and $src[0].state -eq 'closed') { $problems.Add("GROUP-CLOSED $($t.id): $from is closed, so its evidence is already signed off - reopen the group first or leave the row where its evidence sits"); continue }
            # A landed integration task means that group's suites have already run over its membership. Moving a row in
            # or out afterwards makes the evidence claim something that was never tested.
            $landed = $false
            foreach ($side in @(@{ id = $from; dir = 'out of' }, @{ id = $g; dir = 'into' })) {
                $it = @($doc.tasks | Where-Object { $_['kind'] -eq 'integration' -and [string] $_['group'] -eq $side.id })
                if ($it.Count -and $it[0].state -in @('integrated', 'done')) {
                    $problems.Add("GROUP-LANDED $($t.id): it cannot move $($side.dir) $($side.id), whose integration task $($it[0].id) is already $($it[0].state) - that group's suites ran over a membership this would change")
                    $landed = $true
                }
            }
            if ($landed) { continue }
            $t['group'] = $g
            $parts += "group $from -> $g (the id keeps its original prefix)"
            $script:moved[$t.id] = @($from, $g)
        }
        if ($e['title']) { $t.title = $e['title']; $parts += 'title' }
        $tests = @(Arr $e 'tests'); if ($tests.Count) { $t['tests'] = [ordered]@{ targeted = $tests }; $parts += "tests $($tests -join ' / ')" }
        $em = if ($e.Contains('estMinutes') -and $null -ne $e['estMinutes']) { $e['estMinutes'] } else { 0 }
        $eb = if ($e.Contains('estBasis') -and $e['estBasis']) { [string] $e['estBasis'] } else { '' }
        if ("$em" -ne '0') {
            $n = 0
            if (-not [int]::TryParse("$em", [ref] $n) -or $n -lt 1) { $problems.Add("BAD-EST $($t.id): estMinutes is a positive whole number of minutes, got '$em'"); continue }
            $was = if ($null -ne $t['estMinutes']) { [int] $t['estMinutes'] } else { 0 }
            if ($n -ne $was) {
                if (-not $eb) { $problems.Add("EST-NO-BASIS $($t.id): an estMinutes change states its new estBasis in the same edit, because the old basis is what the new number makes false"); continue }
                $parts += "est $was -> $n"; $t['estMinutes'] = $n
            }
        }
        if ($eb -and $eb -ne [string] $t['estBasis']) { $t['estBasis'] = $eb; $parts += 'estBasis' }
        $why = "plan revise: $($parts -join '; ')$(if ($e['note']) { " -- $($e['note'])" } elseif ($in['note']) { " -- $($in['note'])" })"
        # A NOTE-ONLY edit never moves a row. release defaulted to auto, so an edit that changed nothing but its note
        # RELEASED a blocked row: G3.T202 went blocked -> planned at 2026-10-01T19:09:46Z on 'plan revise:  -- tests
        # widened with the write set', and no role could park it again (kit item IN-20261001191046-5fcc). auto now
        # applies only when the edit changed something or named its release; a named release always applies.
        $named = [bool] $e['release']
        $rel = if ($named) { $e['release'] } elseif ($parts.Count) { 'auto' } else { 'keep' }
        $to = $null
        if ($rel -eq 'retire') {
            $why0 = if ($e['note']) { [string] $e['note'] } elseif ($in['note']) { [string] $in['note'] } else { '' }
            if (-not $why0) { $problems.Add("RETIRE-NO-NOTE $($t.id): -Release retire needs a -Note saying why the row is withdrawn"); continue }
            if ($t.claim -and (Test-ClaimLive $t)) { $problems.Add("RETIRE-CLAIMED $($t.id): $($t.claim.role) $($t.claim.session) holds it; the holder releases it first"); continue }
            # BACKFILL: a row already moved to done as a withdrawal, before retire existed, is marked retired in place.
            # G5.T101, G5.T134, G5.T143 and G2.T114 went blocked -> done at 2026-10-09T15:21:48Z with no patch, so they
            # counted as landed work (kit item IN-20261009155410-5b5e). Only a row that never reached integrated and holds
            # no patch qualifies: anything else delivered real work and stays done. Gates and integration tasks finish
            # without integrated by design, so they are refused outright.
            $backfill = $t.state -eq 'done'
            if ($backfill) {
                if (Test-Retired $t) { $problems.Add("RETIRE-ALREADY $($t.id): it is already retired"); continue }
                if ($t['kind'] -in @('gate', 'integration')) { $problems.Add("RETIRE-KIND $($t.id): a $($t['kind']) task finishes without integrated by design, so done is its real outcome"); continue }
                $landed = @(@($t.history) | Where-Object { $_ -and $_['to'] -eq 'integrated' }).Count
                $a = $t['artifacts']; $patch = if ($a -is [Collections.IDictionary] -and $a.Contains('patch')) { [string] $a['patch'] } else { '' }
                if ($landed -or $patch) { $problems.Add("RETIRE-LANDED $($t.id): it $(if ($landed) { 'reached integrated' } else { "holds patch $patch" }), so it delivered work and stays done"); continue }
            }
            elseif ($t.state -ne 'blocked') { $problems.Add("RETIRE-STATE $($t.id): only a blocked row (or a done row that never landed) can be retired, and this one is $($t.state) - park it with -Release block first"); continue }
            $ws = @($t.writeSet | Where-Object { $_ })
            if ($ws.Count) { $problems.Add("RETIRE-WRITESET $($t.id): its write set still holds $($ws -join ', '); remove it in this batch so no file is left owned by a finished row"); continue }
            $t.claim = $null
            $t['retired'] = [ordered]@{ at = (Get-Now); by = $Session; note = $why0 }
            if ($backfill) { Add-History $t $Session 'done' "RETIRED (backfill, already done): $why" }
            else { Set-TaskState $t 'done' 'plan-retire' $Session "RETIRED: $why" }
            $retired.Add([string] $t.id)
            $report.Add("RETIRED $($t.id)$(if ($backfill) { ' (backfill)' }) ($($parts -join '; '))")
            continue
        }
        if ($rel -eq 'block') {
            # block parks a planned or ticketed row; the reason is mandatory, because a parked row with no stated release
            # condition is a row nobody will ever release. A row a live session holds is refused: its claim owns it.
            $why0 = if ($e['note']) { [string] $e['note'] } elseif ($in['note']) { [string] $in['note'] } else { '' }
            if (-not $why0) { $problems.Add("BLOCK-NO-NOTE $($t.id): -Release block needs a -Note naming the release condition"); continue }
            if ($t.claim -and (Test-ClaimLive $t)) { $problems.Add("BLOCK-CLAIMED $($t.id): $($t.claim.role) $($t.claim.session) holds it; the holder blocks it, not the planner"); continue }
            if ($t.state -notin @('planned', 'ticketed')) { $problems.Add("BLOCK-STATE $($t.id): only a planned or ticketed row can be parked, and this one is $($t.state)"); continue }
            $t.claim = $null
            $to = 'blocked'
        }
        elseif ($t.state -eq 'blocked' -and $rel -ne 'keep') {
            # auto releases to ticketed only when the ticket still describes the row. An edit to the write set, tests or
            # dependsOn makes the ticket and grader stale, so the row goes back to an author: G3.T105 was widened with a
            # test file and released straight to ticketed on its old ticket at 2026-10-01 20:26Z (kit item
            # IN-20261001202016-0019). A NAMED ticketed still means ticketed.
            $a = $t['artifacts']; $ready = [bool]($a -and $a['ticket'] -and $a['grader'])
            $scope = [bool]($parts | Where-Object { $_ -match '^(ws|deps|tests) ' })
            $to = switch ($rel) { 'auto' { if ($ready -and -not $scope) { 'ticketed' } else { 'planned' } } default { $rel } }
        }
        elseif ($named -and $rel -eq 'planned' -and $t.state -ne 'planned') {
            # The planner sends a ticketed row back for a re-author (a stale ticket after a scope change). A row a live
            # session holds belongs to its claim, as for block; any later state is past re-authoring. Both are refused
            # rather than ignored, so a named release never silently does nothing.
            if ($t.claim -and (Test-ClaimLive $t)) { $problems.Add("REAUTHOR-CLAIMED $($t.id): $($t.claim.role) $($t.claim.session) holds it; the holder releases it, not the planner"); continue }
            if ($t.state -ne 'ticketed') { $problems.Add("REAUTHOR-STATE $($t.id): only a ticketed (or blocked) row can be sent back to planned, and this one is $($t.state)"); continue }
            $t.claim = $null
            $to = 'planned'
        }
        if ($to) { Set-TaskState $t $to 'plan' $Session $why; $report.Add("REVISED $($t.id) -> $to ($($parts -join '; '))") }
        else { Add-History $t $Session $t.state $why; $report.Add("REVISED $($t.id) [$($t.state)$(if ($t.state -eq 'blocked') { ', kept blocked' })] ($($parts -join '; '))") }
    }
    if ($problems.Count) { return $null }
    # A retired row is finished without landing anything, so a row still waiting on it would wait on nothing real.
    foreach ($id in $retired) {
        $deps = @($doc.tasks | Where-Object { $_.state -notin @('integrated', 'done') -and @($_.dependsOn) -contains $id } | ForEach-Object { $_.id })
        if ($deps.Count) { $problems.Add("RETIRE-DEPENDED $id : open row(s) $($deps -join ', ') still dependsOn it - remove those edges in this batch") }
    }
    if ($problems.Count) { return $null }
    # A group's integration task waits on that group's rows, and nothing else on the board records membership, so the
    # edge moves WITH the row, in this same batch: a half-moved board either closes a group over a row it no longer
    # holds, or never closes it at all.
    foreach ($id in @($moved.Keys)) {
        $from = $moved[$id][0]; $to = $moved[$id][1]
        $old = @($doc.tasks | Where-Object { $_['kind'] -eq 'integration' -and [string] $_['group'] -eq $from })
        if ($old.Count -and @($old[0].dependsOn) -contains $id) { $problems.Add("GROUP-WIRING $id : $($old[0].id) still dependsOn it, so $from would wait for a row it no longer holds - remove that edge in this batch") }
        $new = @($doc.tasks | Where-Object { $_['kind'] -eq 'integration' -and [string] $_['group'] -eq $to })
        if ($new.Count -and $new[0].state -notin @('integrated', 'done') -and @($new[0].dependsOn) -notcontains $id) { $problems.Add("GROUP-WIRING $id : $($new[0].id) does not dependsOn it, so $to could close without it - add that edge in this batch") }
    }
    if ($problems.Count) { return $null }
    foreach ($p in (Get-BoardProblems $doc.tasks)) { $problems.Add($p) }
    if ($problems.Count) { return $null }
    $doc
})
if ($problems.Count) { $problems | ForEach-Object { "REFUSED $_" }; exit 2 }
$report
Add-Decision $P $Session ("Revise-Task: {0}{1}" -f ($report -join '; '), $(if ($in['note']) { " -- $($in['note'])" }))
exit 0
