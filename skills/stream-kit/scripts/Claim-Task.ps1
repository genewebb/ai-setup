# Atomically claims the next task for a role and prints it as JSON, or prints NONE (exit 0 either way).
# exit 2 = a -Task refusal; exit 6 = REFUSED-DISK, a build claim on a drive under the 5 GB claim floor.
#   author: planned tasks in released groups (gate tasks need no ticket and are advanced to ticketed on the way)
#   build : ticketed code/docs/mockup tasks whose dependencies are built or later; the task moves to building
# Order: integration fix tasks first (origin "integration": a failed suite added them, and the group cannot close until
# they land; ranked by chain alone a one-step fix in a nearly finished group always sorts last and starves), then the
# GROUP's position in tasks.json (the owner's category order: Reference Data, Backup, Steps, Workflows, TestAuto, Dial
# Up and Dial Down; since 2026-10-14 the focus groups first, in the order focus.groups is written - lib\Streams.ps1
# Get-PriorityRankMap), then the longest remaining chain (the critical path) inside that group, then board order.
# The group key was added on 2026-09-30: all six groups were released within four hours, so ranking by chain alone
# spread every session across all six at once and no category ever finished first. It cannot starve a session, because
# the focus rule below bounds it: with no claimable work in the focus group a session reads NONE. It cannot pick an
# illegal task either - dependency readiness is filtered before the sort, not ranked by it.
# For an AUTHOR claim the group key is the row's EFFECTIVE group rank: the earliest group among the row and every row
# that depends on it (owner ruling 2026-10-02, kit item IN-20261002153754-be85), so a later-group root that holds
# earlier-group tickets is authored with that earlier group instead of after it.
# FOCUS (2026-10-05 priority-focus-design 3.1): every role is offered rows from the focus set only, the rows whose
# effective group is the first unclosed group (lib\Streams.ps1 Get-FocusSet). Later groups are frozen until their turn:
# a session with nothing claimable in the focus set reads NONE and sleeps; it never spills into a later group. The
# selector is lib\Streams.ps1 Get-Claimable, shared with the runner gate, the status buffer and Integrate-Patch.ps1.
# Exception, AUTHOR SPILL (owner ruling 2026-10-12): an author with no focus row to take is offered every other
# released group's planned rows (Get-Claimable 'spill'), sorted by the same keys, so group order then ready-first.
# Each spill claim stamps the main commit in the row's 'spill' field; a build claim of a spill ticket whose write-set
# files moved since warns STALE-TICKET. Builders and the integrator never spill.
# The AUTHOR sort always has one more key between the group and the chain, ReadyOnRelease: a planned row whose
# dependencies are all built or later comes first, because a builder can take it the moment it is ticketed, while a
# ticket on a waiting chain only adds to the ticketed-but-blocked pile. Author keys: Fix desc, EffectiveRank asc,
# ReadyOnRelease desc, Chain desc, Order. A ready row therefore beats a not-ready row inside its effective group, and an
# earlier effective group still beats readiness. It is the permanent order, not a mode below a buffer target (owner
# rulings 2026-10-02, kit items IN-20261002160453-9384 and IN-20261002161525-69c9): on 10-02 at 12:12 EDT 18 of 20
# ticketed rows sat on serial chains authored before their roots while 114 planned rows had every dependency landed.
# -Task <id> claims exactly that row, skipping the sort, when it passes the SAME gates the sort applies: released
# group, right state for the role, claimable kind, no live claim, and dependencies built or later for build. It
# exists because a 'ticket this one next' request could be honoured by nobody: an author could write the ticket and
# the grader under -Role status, and then no script could flip planned -> ticketed, since that transition is author
# or build only and both are claim-checked, and Revise-Task.ps1 releases a BLOCKED row only. Measured on G3.T149 on
# 2026-09-30: CLAIM-LOST exit 3 (kit item IN-20260930211404-3356). A refusal names the gate that stopped it and
# exits 2; nothing is written.
# A ROW NAMED BY A LIVE INBOX HOLD IS SKIPPED BY THE SORT. An author works an inbox item about a row WITHOUT
# claiming that row - the contract says so - and the row therefore looks free while its ticket and grader are being
# rewritten. Measured on G3.T140 on 2026-09-30: one session claimed and released it three times in 34 minutes and
# wrote three claim/release pairs that describe nothing but the collision, and an author that did not hash the file
# first would have re-authored a grader on top of a live edit (kit item IN-20260930212238-f58e). Only a TAKEN hold
# inside its inbox's silence limit counts: an OPEN item names a row nobody is editing yet, and a dead hold must not
# park a row for ever. -Task overrides the skip, because the session working the item is exactly the one that may
# claim the row; the hold it overrides is named in a warning.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [ValidateSet('author', 'build')] [string] $Role,
    [Parameter(Mandatory)] [string] $Session,
    [string] $Task = '',
    # A runner pre-stage claim: its session id becomes a unit only if the claim takes a row, so a NONE or a disk
    # refusal must leave no idle beat (the runner state file is that runner's liveness).
    [switch] $NoIdleBeat
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
# Runners started before -NoIdleBeat existed load this script from disk on every claim but never pass the switch:
# their pre-stage NONE left one ghost idle session per runner per idle pass, which the board counted live for the
# role's whole limit (2026-10-08: author 8 live while 5 author runners ran). The runner calls this script in its own
# process from Invoke-PreStage, so that frame on the call stack marks a pre-stage claim from any runner version.
$preStage = $NoIdleBeat -or [bool](Get-PSCallStack | Where-Object { $_.FunctionName -eq 'Invoke-PreStage' -and $_.ScriptName -and (Split-Path -Leaf $_.ScriptName) -eq 'Start-StreamRunner.ps1' })
$writeBeat = -not $preStage
# Every pre-stage claim is marked, so a session that claims and bounces without a unit is not counted live (lib\Streams.ps1 Set-PreStageMark).
if ($preStage) { Set-PreStageMark $P $Session $Role }

# A build claim on a drive under the claim floor is refused before the board is touched: exit 6, one REFUSED-DISK
# line with the measured free space, nothing written (owner ruling IN-20261001160218-2d56; lib\Streams.ps1
# Get-ClaimDiskRefusal). An author claim writes a ticket and a grader, not a build, so it is not gated.
if ($Role -eq 'build') {
    $diskWhy = Get-ClaimDiskRefusal (Get-StreamWorktreeRoot (Resolve-Path $Repo).Path) 'build'
    if ($diskWhy) { if ($writeBeat) { Set-IdleBeat $P $Session $Role }; $diskWhy; exit 6 }
}

# AUTHOR SPILL (owner ruling 2026-10-12, lib\Streams.ps1 Get-Claimable): a spill claim stamps the main commit the
# ticket is written against; a focus claim drops an old stamp, because its ticket is rewritten against current code.
# Returns the history-note suffix.
$mainHead = ''
function Set-SpillStamp($t, [bool] $IsSpill) {
    if (-not $IsSpill) {
        if ($t.Contains('spill')) { $t.Remove('spill'); return ' (focus claim; spill stamp cleared)' }
        return ''
    }
    if (-not $script:mainHead) { $script:mainHead = [string](git -C $P.Repo rev-parse HEAD 2>$null) }
    $t['spill'] = [ordered]@{ base = $script:mainHead; at = (Get-Now); by = $Session }
    " (author spill: focus set has no planned row for authors; written against main $($script:mainHead.Substring(0, [Math]::Min(10, $script:mainHead.Length))))"
}

$picked = $null
$refusals =[Collections.Generic.List[string]]::new()
$held = [Collections.Generic.List[string]]::new()
[void](Invoke-TasksLocked $P $Session {
    param($doc)
    $released = @($doc.groups | Where-Object { $_.state -in @('released', 'integrating') } | ForEach-Object { $_.id })
    $focusGroup = Get-FocusLabel $doc $P
    $focusSet = Get-FocusSet $doc $P
    # Gate rows of the focus set advance to ticketed with no claim (lib\Streams.ps1 Step-FocusGates).
    if ($Role -eq 'author') { [void](Step-FocusGates $doc $Session) }
    # Which rows a live inbox hold is working on. One read per inbox, no new state on the board.
    $busy = Get-InboxHeldRows $P
    $chain = Get-ChainMinutes $doc
    # Group rank = the owner's focus.groups order first, then board order (lib\Streams.ps1 Get-PriorityRankMap).
    $grank = Get-PriorityRankMap $doc $P
    $erank = if ($Role -eq 'author') { Get-EffectiveGroupRank $doc $grank } else { @{} }
    if ($Task) {
        $one = @($doc.tasks | Where-Object { $_.id -eq $Task })
        if ($one.Count -ne 1) { $refusals.Add("REFUSED-TASK $Task : no task with that id is on the board"); return $null }
        $t = $one[0]
        $want = if ($Role -eq 'author') { 'planned' } else { 'ticketed' }
        $kinds = if ($Role -eq 'author') { @('code', 'mockup', 'docs', 'integration') } else { @('code', 'docs', 'mockup') }
        if ($t.group -notin $released) { $refusals.Add("REFUSED-TASK $Task : its group $($t.group) is not released or integrating") }
        elseif (-not $focusSet.Contains([string]$t.id) -and -not ($Role -eq 'author' -and $t.state -eq 'planned' -and (Get-Claimable $P $doc 'author' $busy).spill)) { $refusals.Add("REFUSED-TASK $Task : not-focus, the focus group is $focusGroup and this row is not in its effective set (spec 3.1)") }
        elseif ($t.state -ne $want) { $refusals.Add("REFUSED-TASK $Task : $Role claims a $want row and this one is $($t.state)") }
        elseif ($t.kind -notin $kinds) { $refusals.Add("REFUSED-TASK $Task : $Role does not claim a $($t.kind) task$(if ($t.kind -eq 'gate') { ' - a gate row is advanced to ticketed with no claim by any author claim' })") }
        elseif (Test-ClaimLive $t) { $refusals.Add("REFUSED-TASK $Task : $($t.claim.role) $($t.claim.session) holds it, beat $($t.claim.beat)") }
        elseif ($Role -eq 'build' -and -not (Test-DepsAt $doc $t @('built', 'integrated', 'done'))) { $refusals.Add("REFUSED-TASK $Task : a dependency is not built yet ($($t.dependsOn -join ', '))") }
        elseif ($Role -eq 'build' -and -not (Test-DepsBaseReady $doc $t)) { $refusals.Add("REFUSED-TASK $Task : a built dependency sits on a dependency that is no longer built, so its patch cannot be stacked ($($t.dependsOn -join ', '))") }
        if ($refusals.Count) { return $null }
        if ($busy.Contains($t.id)) { $script:held.Add("$Task is named by $($busy[$t.id]); -Task overrides that skip, so re-read the item and the row's artifacts before writing") }
        $now = Get-Now
        $prior = if ($t.claim) { " (took over stale claim of $($t.claim.session), beat $($t.claim.beat))" } else { '' }
        $t.claim = [ordered]@{ session = $Session; role = $Role; at = $now; beat = $now }
        if ($Role -eq 'build') { Set-TaskState $t 'building' 'build' $Session "claimed by name$prior" }
        else { Add-History $t $Session $t.state "claimed by author by name$prior$(Set-SpillStamp $t (-not $focusSet.Contains([string]$t.id)))" }
        $script:picked = $t
        return $doc
    }
    # The candidates are exactly Get-Claimable's rows (lib\Streams.ps1), the selector the runner gate, the status buffer
    # and Integrate-Patch.ps1 read too, so a gate that says "work" and a claim that says NONE cannot disagree.
    $sel = Get-Claimable $P $doc $Role $busy
    foreach ($h in $sel.heldIds) { $script:held.Add("$h skipped: $($busy[$h])") }
    $boardOrder = @{}; $o = 0; foreach ($x in $doc.tasks) { $boardOrder[[string]$x.id] = ++$o }
    $cands = foreach ($t in $sel.rows) {
        $order = $boardOrder[[string]$t.id]
        $fix = [int]($t.Contains('origin') -and $t['origin'] -eq 'integration')
        # The AUTHOR sort ranks a row by its effective group (lib\Streams.ps1 Get-EffectiveGroupRank): a later-group row
        # that blocks earlier-group work is ticketed with that earlier group, and Chain then puts it ahead of its
        # dependents. The build sort keeps the row's own group, because dependency readiness already filters it.
        $rank = if ($Role -eq 'author') { $erank[$t.id].rank } else { $grank[$t.group] }
        # ReadyOnRelease (author only): the ticket would be claimable the moment it is released.
        $ready = [int]($Role -eq 'author' -and (Test-ReadyWhenTicketed $doc $t))
        [pscustomobject]@{ Task = $t; Fix = $fix; Rank = $rank; Ready = $ready; Chain = $chain[$t.id]; Order = $order }
    }
    $best = @($cands | Sort-Object @{ e = 'Fix'; Descending = $true }, @{ e = 'Rank'; Descending = $false }, @{ e = 'Ready'; Descending = $true }, @{ e = 'Chain'; Descending = $true }, @{ e = 'Order'; Descending = $false }) | Select-Object -First 1
    if (-not $best) { return $doc }
    $t = $best.Task
    $now = Get-Now
    $prior = if ($t.claim) { " (took over stale claim of $($t.claim.session), beat $($t.claim.beat))" } else { '' }
    $t.claim = [ordered]@{ session = $Session; role = $Role; at = $now; beat = $now }
    if ($Role -eq 'build') { Set-TaskState $t 'building' 'build' $Session "claimed$prior" }
    else { Add-History $t $Session $t.state "claimed by author$prior$(Set-SpillStamp $t $sel.spill)" }
    $script:picked = $t
    $doc
})
# A build claim of a spill ticket whose write-set files moved on main since it was written: say so, so the builder
# re-reads the ticket against the current code before coding (lib\Streams.ps1 Get-SpillDrift).
if ($picked -and $Role -eq 'build') {
    $drift = Get-SpillDrift $P (Read-Tasks $P) ([string]$picked.id)
    foreach ($dr in $drift) {
        Write-Warning "STALE-TICKET $($dr.id): written against $($dr.base) as an author spill; write-set files changed on main since: $($dr.files -join ', '). Re-read the ticket against the current code before coding."
    }
}
# The stdout contract is unchanged - the task as JSON, or exactly NONE - so every caller that parses it still works.
# Skips and overrides go to the warning stream, where a session sees them and a capture of stdout does not.
foreach ($h in $held) { Write-Warning $h }
# A claim clears the session's idle beat (the claim itself is now its beat); a NONE from the sort writes one, so an idle
# poller still counts as live on the board. A -Task refusal is a request for one row, not a poll, so it writes nothing.
if ($picked) { Clear-IdleBeat $P $Session } elseif (-not $Task -and $writeBeat) { Set-IdleBeat $P $Session $Role }
if ($refusals.Count) { $refusals; exit 2 }
if ($picked) { $picked | ConvertTo-Json -Depth 50 } else { 'NONE' }
# An explicit 0: without it a successful claim left $LASTEXITCODE at whatever the last refusal set, so a caller that
# checks the exit code read a claim that worked as a failure.
exit 0
