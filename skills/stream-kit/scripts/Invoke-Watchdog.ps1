# stream-status watchdog. Breaks stale claims (author 30 min, build 45 min without a beat) and a stale integrator lock
# (20 min), so a dead session never holds work. A fresh beat is never touched, however long the task has run.
# It also frees ORPHANS: a task left `building` with no claim at all. Breaking a claim is not enough on its own,
# because a session can move a task to `building` and end without ever holding one (an integrator running the group's
# own suites does exactly that), and a claimless task is invisible to every claim rule, so nothing would ever free it.
# The same 45 min the build claim gets applies, measured from the move into `building`, so a live hand-off is safe.
# It also releases a DEAD INBOX HOLD: an item left `taken` by a session that has stopped working. An inbox hold had no
# watchdog at all, so a session that took an item and died held it for good, and the only cure was for a human to spot
# it and take it over by hand. That cure does not hold: IN-20260929001946-67a7 was manually rescued from a dead
# coordinator, and the rescuing coordinator then died holding it too. The item's own inbox limit applies, with one
# reprieve: a holder that has touched tasks.json inside that limit is working, so its hold stands however old the
# `taken` line is. Releasing re-appends the item's ORIGINAL open line with a fresh timestamp, so it returns to the
# queue exactly as first filed; the release itself is recorded in decisions.md.
# It also SWEEPS the host temp folder, because a full GetTempFileName name space breaks every build on the host with a
# message that blames disk space, and REPORTS untracked files left in the repo root, which belong under .streams logs.
# It PRUNES BUILD OUTPUT (bin and obj only) from a tree whose work is already safe as a patch, but ONLY while the drive
# is at `warn` or `low` against Get-DiskNeedMB. With room on the drive nothing is deleted: a rebuild costs the next
# session minutes it pays for nothing. Every prune line names the band and the free space that caused it.
# Prints one line per action, or QUIET.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Recovery.ps1"   # Get-Field, used by the worktree reaper below
. "$PSScriptRoot\lib\Suites.ps1"     # Test-SuiteRunAlive, for the snapshot rule
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$acts = [Collections.Generic.List[string]]::new()
# Reports, not actions: a note is printed after the action lines (or after QUIET) and is never written to decisions.md,
# so a standing condition nobody has cleared does not append a decision line every cycle.
$notes = [Collections.Generic.List[string]]::new()

# The live integrator, if any: an INTEGRATION task the integrator set building carries no claim, and its liveness is the
# integrator lock. A step-B suite run lasts 1.5-2 h, so the orphan rule below freed G2.T90 mid-suite at
# 2026-10-02T01:25:48Z while 4599ecab held a fresh lock and was in Tests.Unit (kit items IN-20261002014307-9bf2,
# IN-20261002020026-2168). A stale lock is broken further down on its own rule, and the row is freed on the next pass.
# Read by Get-IntegratorHold (lib\Streams.ps1), which Get-StreamStatus.ps1 shares so the page agrees with this pass.
$hold = Get-IntegratorHold $P
$liveIntegrator = $hold.live
$staleIntegrator = $hold.stale

# A broken lock is NOT a dead integrator. The lock beats only while a command runs, so the integrator's own analysis
# between step-B runs (attributing failures, writing fix tasks) can outlast it: after G2 suites run 1 ended at
# 2026-10-02T04:04:59Z the lock sat unbeaten for 27 min, this watchdog broke it at 04:31:26Z and, in the same pass,
# freed G2.T90 to ticketed; 4599ecab retook the lock 6 s later (kit item IN-20261002043357-316b). So an integration row
# its setter left building is kept while that setter's lock is stale (it is broken below, in this pass) and for the
# build claim limit after the break, recorded in integrator.lock.broken. A live integrator retakes the lock on its next
# cycle and the row stays its own; a dead one loses the row 45 min after its lock went, not at once.
$brokenMark = $hold.brokenMark


$endedUnits = Get-EndedRunnerSessions $P
[void](Invoke-TasksLocked $P $Session {
    param($doc)
    # Gates of the focus set advance here too, with no author unit (lib\Streams.ps1 Step-FocusGates, final review I2).
    foreach ($gid in @(Step-FocusGates $doc $Session)) { $acts.Add("GATE $gid ticketed (focus set, no ticket needed)") }
    foreach ($t in $doc.tasks) {
        if (-not $t.claim) {
            if ($t.state -ne 'building') { continue }
            $since = Get-StateEntry $t 'building'
            if (-not $since) { continue }
            if (Test-IntegratorKeepsRow $hold $t $since) { continue }

            $age = ((Get-Date).ToUniversalTime() - [datetime]::Parse($since.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes
            if ($age -lt $script:ClaimLimitMinutes.build) { continue }
            $why = "orphaned: building since $($since.at) ($([int]$age) min) with no claim, set by $($since.by)"
            Set-TaskState $t 'ticketed' 'status' $Session $why
            if ($t.ContainsKey('base') -and $t.base -and $t.base.worktree) { Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | abandoned (orphaned, no claim)" -f $t.id, $t.base.worktree, (Get-Now)) }
            $acts.Add("FREED $($t.id): $why")
            continue
        }
        $c = $t.claim
        # A claim held by a runner unit that has ENDED is dead at once, whatever its beat says. Start-StreamRunner.ps1
        # releases its unit's claims after every exit, but a closed console or a hard kill runs no finally block, so
        # the claim would sit unclaimable for the role's whole limit (kit item IN-20261004202424-27bf). A unit is ended
        # when no runner whose pid is alive names it as its current session (Get-EndedRunnerSessions).
        if ($endedUnits.Contains([string]$c.session)) {
            $why = "$($c.role) claim of $($c.session), a runner unit that has ended (no live runner names it), last beat $($c.beat)"
            Clear-DeadClaim $P $t $Session $why 'runner unit ended'
            $acts.Add("BROKE $($t.id): $why")
            continue
        }
        if (Test-ClaimLive $t) {
            # A fresh beat only says the session is alive. An AUTHOR claim on a row that has not moved for
            # $script:NoProgressMinutes is broken too, because a zombie author beats exactly like a working one; build
            # is exempt by design (see the comment on NoProgressMinutes in lib\Streams.ps1).
            if ($c.role -ne 'author') { continue }
            $prog = Get-ClaimProgressAt $t $P
            if (-not $prog) { continue }
            $idle = ((Get-Date).ToUniversalTime() - $prog.at).TotalMinutes
            if ($idle -lt $script:NoProgressMinutes) { continue }
            # The reason names the REMEDY, because the session that loses the claim is usually working. A beat is not
            # progress, and inside one long mandated step - stream-author step 7 hands the finished ticket and grader
            # to a fresh skeptic subagent that may outlast any claim limit - there is nothing else to write: touching
            # either artifact while a blind reader is inside it invalidates the round. `Update-Task -Beat -Note` DOES
            # record progress (Update-Task.ps1:65 appends the note as history), so a noted wait is safe and a bare
            # beat is not. Measured on G3.T184 on 2026-09-30 (kit item IN-20260930224214-efe5): an 11-clause ticket, a
            # PORTABLE grader, a proved RED and two builder probes were complete, and the claim was taken 72 minutes
            # into the skeptic round with a beat 71 seconds old, because nothing in the round wrote to the board.
            $why = "no progress on a live author claim of $($c.session): nothing has moved since $($prog.at.ToString('yyyy-MM-ddTHH:mm:ssZ')) ($([int]$idle) min, newest was $($prog.what)) although its beat is $($c.beat). A BARE BEAT IS NOT PROGRESS: inside a long step that writes nothing, beat with Update-Task -Beat -Note '<what is running>' and the wait counts"
            $t.claim = $null
            Add-History $t $Session $t.state $why
            $acts.Add("BROKE $($t.id): $why")
            continue
        }
        $why = "stale $($c.role) claim of $($c.session), last beat $($c.beat)"
        Clear-DeadClaim $P $t $Session $why
        $acts.Add("BROKE $($t.id): $why")
    }
    if ($acts.Count) { $doc } else { $null }
})

# Dead runners' state files leave .streams\runners only after the pass above has freed their units' claims, so a claim
# is never left behind by a file moved first. Housekeeping, so a note rather than a decision line.
$movedStates = Move-DeadRunnerStates $P
if ($movedStates.Count) { $notes.Add("MOVED $($movedStates.Count) dead runner state file(s) to logs\runner\<runner>\state.json: $($movedStates -join '; ')") }

if (Test-Path $P.IntLock) {
    $l = Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String
    $age = ((Get-Date).ToUniversalTime() - [datetime]::Parse($l.beat, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes
    if ($age -ge $script:IntegratorLockMinutes) {
        Remove-Item $P.IntLock -Force
        Write-AtomicText $brokenMark (@{ session = [string] $l.session; at = (Get-Now); beat = [string] $l.beat } | ConvertTo-Json)
        $acts.Add("BROKE integrator lock of $($l.session) (beat $([int]$age) min)")
    }
}
# Worktree reaper. Nothing else in the kit ever released a worktree, so they grew until the disk filled: C: reached 0
# bytes free on 2026-09-29 with 37 of them, and at that point every tool call in every session failed. A worktree is
# disposable once its patch exists, because Integrate-Patch now proves main holds the patch's content from the patch
# itself. Reaped OUTSIDE the tasks lock: deleting a 700 MB tree must never hold the board shut.
$doc = Read-Tasks $P
$live = @{}; $state = @{}; $recorded = @{}; $claimAt = @{}
foreach ($t in $doc.tasks) {
    $state[$t.id] = $t.state
    # Only a BUILD claim means someone is inside a worktree; New-TaskWorktree is builder-only. An author claim on a
    # planned task was holding that task's leftover tree open for as long as the author kept beating (G2.T04 on the
    # live board), so the role is recorded and only a build claim protects a tree.
    if ($t.claim -and (Test-ClaimLive $t)) {
        $live[$t.id] = $t.claim.role
        if ($t.claim.at) { $claimAt[$t.id] = [datetime]::Parse($t.claim.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }
    }
    $w = Get-Field $t 'base', 'worktree'
    if ($w) { $recorded[$t.id] = $w }
}
# Roots come from the paths tasks actually recorded, so a -WorktreeRoot override is followed rather than guessed at.
$roots = @(@($recorded.Values | ForEach-Object { Split-Path $_ }) + @(Get-StreamWorktreeRoot $Repo) | Where-Object { $_ } | Select-Object -Unique)
$remove = "$PSScriptRoot\Remove-TaskWorktree.ps1"
# A worktree is disposable only once its content EXISTS as a patch. Until 2026-09-29 the reaper trusted the task state
# alone, so breaking a stale build claim moved the task to `ticketed` and the SAME pass deleted the tree: G4.T003
# (498 MB) and G4.T044 (273 MB) went at 17:07:50Z, and the work survived only because both builders happened to export
# a patch a minute before dying - neither task had artifacts.patch set, so the next builder would have started over.
# G2.T33 lost 691 MB the same way at 16:08:03Z. So: before reaping a tree whose task has not landed, export what is in
# it and attach the patch. Nothing is deleted when the export refuses, because a refusal means work with nowhere to go.
function Save-BeforeReap([string] $Id, [string] $Dir, [string] $State) {
    # A tree somebody is still WRITING to must not be harvested at all. A grader beats the claim but `dotnet test` does
    # not, so a build whose blind verifier is running long tests reads as idle, and on 2026-09-30 G3.T030 was harvested
    # mid-verification: the salvaged patch carried a deliberate verifier mutation that turned CancelAsync's
    # `await DiscardContextAsync()` into `ClearContext(); await Task.CompletedTask;`, which would have shipped an
    # Abandon button that leaves the server context and the candidate seed alive. The clock is the honest test: if
    # anything in the tree changed in the last few minutes, a process is in there whatever the claim says.
    $newest = @(Get-ChildItem $Dir -Recurse -File -Force -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    if ($newest.Count) {
        $quiet = ((Get-Date).ToUniversalTime() - $newest[0].LastWriteTimeUtc).TotalMinutes
        if ($quiet -lt $script:ReapQuietMinutes) {
            $who = if ($Id) { $Id } else { 'orphan' }
            $acts.Add("KEPT $who ${Dir}: written to $([int]$quiet) min ago (quiet period $($script:ReapQuietMinutes) min), so a process is still inside it - not harvested and not reaped")
            return $false
        }
    }
    # The quiet period runs FIRST, for every tree, and only then do the two early outs below apply. They used to come
    # before it, so a tree no task recorded was reaped however recently it was written: on 2026-10-01 a builder's
    # G3.T106-probe (59 MB) was reaped while a fresh G3.T106 build held a live claim, because the task recorded
    # G3.T106-2 and the probe directory's name matched no task, so nothing checked whether it was in use. An orphan has nowhere to put a patch, so the clock is its only protection.
    if (-not $Id) { return $true }                              # an orphan names no task, so no task can own a patch
    if ($State -in @('integrated', 'done')) { return $true }     # the patch is applied and already proven on main
    # NEVER overwrite a patch the task already carries. That file is a handed-off artifact; this harvest is unverified
    # by definition, because the session that owned the tree died without releasing it. The harvest goes beside it as
    # <task>.salvage.patch, artifacts.patch is left pointing at the good one, and the history note says which is which.
    $existing = Join-Path $P.Patches "$Id.patch"
    $aside = (Test-Path $existing)
    $outFile = if ($aside) { ".streams\patches\$Id.salvage.patch" } else { '' }
    # A throw from the export (git cannot read the tree) must keep the tree, never end the pass: on 2026-10-18
    # G9.T010's tree had a git admin folder with no commondir (its `git worktree add` died part-way), `git ls-files`
    # failed, and the throw took the whole watchdog and the status tick with it (kit item IN-20261018010634-24c4).
    try {
        $out = @(& "$PSScriptRoot\Export-TaskPatch.ps1" -Repo $Repo -Task $Id -Worktree $Dir -OutFile $outFile 2>&1)
    } catch {
        $acts.Add("KEPT $Id ${Dir}: the patch export threw, so git cannot read this tree and it stays for a person to inspect ($($_.Exception.Message))")
        return $false
    }
    $line = ($out -join ' ')
    if ($line -match 'EMPTY no change') { return $true }
    if ($out | Where-Object { $_ -like 'OUTSIDE *' }) {
        $acts.Add("KEPT $Id ${Dir}: it holds work outside the write set, so no patch can be written and the tree stays ($line)")
        return $false
    }
    if (-not @($out | Where-Object { $_ -like 'PATCH *' }).Count) {
        $acts.Add("KEPT $Id ${Dir}: the patch export did not finish, so the tree stays ($line)")
        return $false
    }
    if ($aside) {
        # The kept patch stays the task's artifact. The salvage is recorded in history only, and named UNVERIFIED, so an
        # integrator reading the board cannot mistake it for a handed-off patch.
        [void](& "$PSScriptRoot\Update-Task.ps1" -Repo $Repo -Task $Id -Role status -Session $Session -Note "UNVERIFIED salvage of $Dir written to $outFile before the watchdog reaped it. artifacts.patch is UNCHANGED and still points at .streams\patches\$Id.patch, which a session handed off. The salvage may hold a verifier mutation or a half-finished edit: diff the two before using it, and never integrate it as it stands.")
        $acts.Add("SALVAGED-ASIDE $Id -> $outFile (UNVERIFIED; $Id.patch kept as the artifact) before reaping $Dir")
        return $true
    }
    $rel = ".streams\patches\$Id.patch"
    [void](& "$PSScriptRoot\Update-Task.ps1" -Repo $Repo -Task $Id -Role status -Session $Session -Artifacts @{ patch = $rel } -Note "salvaged before the watchdog reaped $Dir")
    $acts.Add("SALVAGED $Id -> $rel before reaping $Dir")
    return $true
}
# Only ever touch a directory THIS repo registers as a worktree, or an empty husk git left behind after dropping the
# registration. A worktree root can hold trees belonging to another repo whose task ids collide with this board's, and
# matching on the directory name alone would reap them. (Found by the r23 reaper test, which shares one scratch root.)
$mine = @{}
foreach ($w in @(& git -C $Repo worktree list --porcelain 2>$null | Where-Object { $_ -like 'worktree *' })) {
    $mine[$w.Substring(9).Replace('/', '\').TrimEnd('\').ToLowerInvariant()] = $true
}
# Free space is read ONCE per cycle, before any rule that deletes, because two rules now decide by it: the built-tree
# prune inside the sweep below and the ad-hoc-tree prune after it. The owner's rule (IN-20260930205046-e104): prune
# build output only under pressure, not on every sweep, and name the band in the ledger line. The measurement behind
# it, on SMVMTR1 2026-09-30: a manual prune of bin and obj across the eight idle probe and skeptic trees removed 18
# directories per tree and reclaimed 3.52 GB, taking C: from 6.21 GB to 9.74 GB free. That is a real reclaim, and it
# is also minutes of rebuild for every tree it touches, so it is worth doing when the drive needs it and not before.
# Suite snapshots (New-SuiteSnapshot.ps1) are not task trees. The NEWEST ready one is a step-B run in progress while
# the session that made it holds a live integrator lock, and is never touched; every other snapshot - older, failed, or
# its session's lock gone - is disposable, because a snapshot is a copy of main that carries no work of its own. It
# still gets the quiet-period clock, so a process writing inside it keeps it. Without this rule a snapshot named
# suite-G2-5 matched no task and was reaped as an orphan the moment the suite stopped writing to it.
$snaps = @{}
$snapAll = @(Get-SuiteSnapshots $P)
$snapNewest = @($snapAll | Where-Object { $_['state'] -eq 'ready' } | Sort-Object { [long]$_['seq'] }, { [string]$_['at'] } -Descending | Select-Object -First 1)
foreach ($s in $snapAll) { $snaps[([string]$s['path']).Replace('/', '\').TrimEnd('\').ToLowerInvariant()] = $s }
# A snapshot that a LIVE suite run or retest names (.streams\suites\runs, status running, its process alive) is kept
# whatever its age: a Tier 3 snapshot taken while a Tier 2 run is going is the newest, and without this rule the running
# Tier 2's snapshot was reaped as superseded under it (final review I5).
$runSnaps = @{}
if (Test-Path -LiteralPath (Join-Path $P.Suites 'runs')) {
    # A 'running' record whose process is gone is marked abandoned on every pass (lib\Suites.ps1
    # Resolve-RunningSuiteRuns), not only when the next run starts: run-G17-10 read 'running' on the test page for 6 h
    # after its process died, and its record hid the last finished run (kit item IN-20261030191146-aba1).
    foreach ($x in @(Resolve-RunningSuiteRuns $P $Session)) { if ($x -is [string]) { $acts.Add($x) } }
    foreach ($r in @(Get-SuiteRunRecords $P | Where-Object { $_['status'] -eq 'running' -and $_['snapshot'] })) {
        if (Test-SuiteRunAlive $r) { $runSnaps[([string]$r['snapshot']).Replace('/', '\').TrimEnd('\').ToLowerInvariant()] = [string]$r['id'] }
    }
}
function Invoke-SnapshotRule([string] $Dir) {
    $s = $snaps[$Dir.TrimEnd('\').ToLowerInvariant()]
    if (-not $s) { return $false }
    if ($runSnaps.ContainsKey($Dir.TrimEnd('\').ToLowerInvariant())) { return $true }
    $isNewest = $snapNewest.Count -and $snapNewest[0]['path'] -eq $s['path']
    if ($isNewest -and $liveIntegrator -and $liveIntegrator -eq [string]$s['session']) { return $true }
    $why = if ($s['state'] -ne 'ready') { "suite snapshot $($s['name']) is $($s['state'])" }
           elseif (-not $isNewest) { "suite snapshot $($s['name']) is superseded by $($snapNewest[0]['name'])" }
           else { "suite snapshot $($s['name']): its session $($s['session']) holds no live integrator lock" }
    if (-not (Save-BeforeReap '' $Dir '')) { return $true }
    $out = & $remove -Repo $Repo -Session $Session -Path $Dir -Label ([string]$s['name']) -Reason "watchdog: $why"
    if ($out -notlike 'NOTHING*') { $acts.Add("$out") }
    $true
}
# Processes whose command line or executable sits inside $Dir (the path itself, then a separator, quote, space or the
# end, so G1.A never matches G1.A-2). This session and its own ancestors are never listed.
function Get-TreeProcesses([string] $Dir) {
    $dirRx = [regex]::Escape($Dir.TrimEnd('\')) + '(?:[\\/"''\s]|$)'
    $all = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    $mine = @{}; $cur = $PID
    while ($cur -and -not $mine[$cur]) {
        $mine[$cur] = $true
        $me = @($all | Where-Object { $_.ProcessId -eq $cur } | Select-Object -First 1)
        $cur = if ($me.Count) { [int]$me[0].ParentProcessId } else { 0 }
    }
    @($all | Where-Object { -not $mine[[int]$_.ProcessId] -and (("$($_.CommandLine)" -match $dirRx) -or ("$($_.ExecutablePath)" -match $dirRx)) })
}
# A tree a LIVE session is working in is never killed out of, reaped or pruned, whatever its git registration and however
# long it has been quiet. Two signs name the owner: the directory is <task> or <task>-<anything> for a task whose BUILD
# claim is live (a builder's own baseline, probe or skeptic tree), or the live claim holder named the directory in its
# own history notes. On 2026-10-09 build-202610082152-34a5, live on G4.T116, ran a serial Tests.Unit baseline detached
# in G4.T116-base for acceptance A4; the tree matched no task, a serial test run writes nothing for minutes, so it was
# reaped as an orphan at 02:10Z, the removal failed on the open files, and the retry at 02:21:44Z KILLED dotnet.exe and
# testhost.exe out of it and removed it (kit item IN-20261009022355-40f9). An author claim does not count by name (see
# $live above), only by naming the tree in its history. Returns why the tree is owned, or '' when it is not.
$liveNotes = @(foreach ($t in $doc.tasks) {
    if (-not $live.ContainsKey([string]$t.id) -or -not $t.claim -or -not $t.claim.session) { continue }
    $sess = [string]$t.claim.session
    foreach ($h in @($t.history)) { if ([string]$h.by -eq $sess -and $h.note) { [pscustomobject]@{ task = [string]$t.id; session = $sess; at = [string]$h.at; note = [string]$h.note } } }
})
# The task number in any form a builder writes it: G4.T116-base, T116-serialbase, g4.t116.probe. The short form (T116)
# alone was enough on 2026-10-09: the G4.T116 holder re-ran its baseline in T116-serialbase after 40f9 shipped, a name
# the first rule did not own, and only a skipped watchdog pass kept it from being killed again (kit item
# IN-20261009025121-b316). A short form can name more than one task (G4.T116, G5.T116); that only ever KEEPS more.
function Get-TaskNumberRx([string] $TaskId) {
    $short = ($TaskId -split '\.')[-1]
    $prefix = if ($TaskId.Contains('.')) { '(?:' + [regex]::Escape($TaskId.Substring(0, $TaskId.LastIndexOf('.') + 1)) + ')?' } else { '' }
    '(?i)(?<![A-Za-z0-9.])' + $prefix + [regex]::Escape($short) + '(?![A-Za-z0-9])'
}
# The board tasks a directory's name points at, by the same rule.
function Get-TreeNamedTasks([string] $Dir) {
    $leaf = Split-Path $Dir.TrimEnd('\') -Leaf
    @($doc.tasks | Where-Object { $_.id -and $leaf -match (Get-TaskNumberRx ([string]$_.id)) })
}
function Get-LiveTreeOwner([string] $Dir) {
    $leaf = Split-Path $Dir.TrimEnd('\') -Leaf
    foreach ($tid in @($live.Keys)) {
        if ($live[$tid] -ne 'build') { continue }
        if ($leaf -match (Get-TaskNumberRx $tid)) { return "$tid holds a live build claim and the tree is named after it" }
    }
    $rx = '(?<![\w.-])' + [regex]::Escape($leaf) + '(?![\w.-])'
    foreach ($h in $liveNotes) {
        if ($h.note -match $rx) { return "$($h.session), live on $($h.task), named $leaf in its history at $($h.at)" }
    }
    ''
}
$liveBuilds = @($live.Values | Where-Object { $_ -eq 'build' }).Count
$needMB = Get-DiskNeedMB $liveBuilds
$freeMB = Get-DiskFreeMB (Get-StreamWorktreeRoot $Repo)
$band = if ($null -eq $freeMB) { 'unknown' } else { Get-DiskState $freeMB $needMB }
$pressure = $band -in @('warn', 'low')
foreach ($root in $roots) {
    if (-not (Test-Path $root)) { continue }
    foreach ($d in @(Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
        if (-not $mine[$d.FullName.ToLowerInvariant()]) {
            # Not ours. Reap it only when it is an empty husk, which belongs to nobody and costs nothing to lose.
            # A husk delete that fails is reported, never skipped in silence: on 2026-10-04 G3.T283's empty, unregistered
            # husk outlived a failed reap and then sat through a tick that printed nothing, so it looked handled (kit
            # item IN-20261004143725-1735). The usual holder is a process whose working directory is inside it. The
            # rule runs every tick, so the delete is retried until that holder lets go.
            if (@(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                $huskErr = ''
                try { Remove-Item -LiteralPath $d.FullName -Recurse -Force -ErrorAction Stop } catch { $huskErr = ("$_" -split "`n")[0].Trim() }
                if (-not (Test-Path -LiteralPath $d.FullName)) { $acts.Add("REMOVED husk $($d.FullName) (empty, no registration)") }
                else { $acts.Add("FAILED husk $($d.FullName) is still present (empty, no registration; a process may hold it, e.g. as its working directory); retried every tick: $huskErr") }
                continue
            }
            # NOT empty and NOT registered, which is what a FAILED removal leaves behind: `git worktree remove --force`
            # drops the registration and then the directory delete loses the race with a file still open, so the next
            # pass no longer recognises the tree as ours and the empty-husk rule skips it in silence. G3.T030's tree sat
            # at 75 MB through two QUIET cycles that way on 2026-09-30 (kit item IN-20260930004842-422a). The ledger is
            # the evidence of intent: when the LAST line for this path records a failed removal, the decision to delete
            # was already taken, so retry it here and keep saying so until the directory is gone.
            if ((Get-LastWorktreeLedgerStatus $P $d.FullName) -match 'removal FAILED') {
                $owner = Get-LiveTreeOwner $d.FullName
                if ($owner) { $acts.Add("KEPT $($d.FullName): $owner, so nothing running out of it is stopped and it is not removed, although an earlier removal failed"); continue }
                # The usual holder is a process left running OUT of the tree by a unit that has ended: on 2026-10-04 an
                # orphan `dotnet ...\G4.T021\src\Web\bin\...\speedy-web.dll` (its parent gone, its runner unit killed on
                # timeout) kept G4.T021's tree through two ticks (kit item IN-20261005004713-cf76). The decision to
                # delete this tree is already taken, so a process whose command line or executable sits inside it is
                # stopped first, and each one is named. A process that only has its working directory there cannot be
                # seen this way; a FAILED line says so.
                # A process is stopped only when the tree names a task and no claim on it is live: that is a dead unit's
                # leftover, as G4.T021's was. A busy tree that names NO task has no owner to ask, and a detached run's
                # parent chain is broken by design (the shell that started it exits: G4.T116's re-run baseline showed
                # testhost -> dotnet -> dotnet -> pwsh -> gone), so the parent cannot tell a live builder's baseline
                # from a leftover. It is kept and named for the owner instead (kit item IN-20261009025121-b316).
                $procs = @(Get-TreeProcesses $d.FullName)
                if ($procs.Count -and -not @(Get-TreeNamedTasks $d.FullName).Count) {
                    $acts.Add("KEPT $($d.FullName): $($procs.Count) process(es) running out of it ($(@($procs | ForEach-Object { "pid $($_.ProcessId) $($_.Name)" }) -join ', ')) and its name points at no task, so nothing is stopped; stop them by PID once nobody needs them")
                    continue
                }
                foreach ($h in $procs) {
                    try { Stop-Process -Id $h.ProcessId -Force -ErrorAction Stop; $acts.Add("KILLED pid $($h.ProcessId) $($h.Name) (parent $($h.ParentProcessId)$(if (-not (Get-Process -Id $h.ParentProcessId -ErrorAction SilentlyContinue)) { ', gone' })) running out of $($d.FullName)") }
                    catch { $acts.Add("WARN could not stop pid $($h.ProcessId) $($h.Name) in $($d.FullName): $(("$_" -split "`n")[0].Trim())") }
                }
                if ($acts | Where-Object { $_ -like "KILLED pid * running out of $($d.FullName)" }) { Start-Sleep -Milliseconds 1500 }
                Remove-Item $d.FullName -Recurse -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $d.FullName)) {
                    Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | removed (watchdog retry after a failed removal)" -f $d.Name, $d.FullName, (Get-Now))
                    $acts.Add("REMOVED $($d.FullName) on retry after an earlier failed removal")
                } else {
                    # Summed by hand: the retry usually deletes every file it can, and Measure-Object over an empty
                    # tree has no Sum under StrictMode, which threw and ended the whole watchdog tick.
                    $bytes = [long]0; foreach ($f in @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue)) { $bytes += $f.Length }
                    $mb = [int]($bytes / 1MB)
                    $held = @(Get-TreeProcesses $d.FullName | ForEach-Object { "pid $($_.ProcessId) $($_.Name)" })
                    $by = if ($held.Count) { "held by $($held -join ', ')" } else { 'no process names it on its command line (a working directory or an open handle may hold it)' }
                    $acts.Add("FAILED $($d.FullName) is STILL present after a retry ($mb MB), $by`: the removal keeps failing and this is not QUIET")
                }
            }
            continue
        }
        if (Invoke-SnapshotRule $d.FullName) { continue }
        # A stream-adhoc tree (ADHOC-<yyyyMMdd>-<n>) names no task, so the rules below read it as an orphan and reap it
        # after the quiet period, with no patch kept. An ad-hoc request sits quiet for as long as the owner takes to
        # approve its requirement or mockup, so on 2026-10-11 ADHOC-20261011-1 was one quiet period from deletion
        # while its session waited on the owner. While its request file .streams\adhoc\<name>.md exists the tree
        # belongs to that request; only stream-adhoc removes it, on the owner's yes.
        if ($d.Name -match '^ADHOC-\d{8}-\d+$' -and (Test-Path -LiteralPath (Join-Path $P.Root "adhoc\$($d.Name).md"))) { continue }
        # "G2.T01-2" is a retry copy of task G2.T01; both belong to that task's lifecycle.
        $id = $d.Name -replace '-\d+$', ''
        if ($live[$id] -eq 'build') {
            # A live claim protects the tree its holder is in, not every copy the task ever had. A SUPERSEDED copy is
            # still reapable, and the safe test is the clock: a tree the current holder created cannot predate its own
            # claim, so only reap a non-recorded copy whose mtime is older than claim.at. New-TaskWorktree also records
            # base AFTER laying the tree down, and this keeps that window safe.
            # A recorded path that no longer exists supersedes nothing (see the stale-record note below), so it is skipped.
            if ($recorded[$id] -eq $d.FullName -or -not $claimAt[$id] -or $d.LastWriteTime.ToUniversalTime() -ge $claimAt[$id]) { continue }
            if (-not (Test-Path -LiteralPath $recorded[$id])) { continue }
            # The directory's own mtime moves only when an entry directly under it is added or removed, so an edit deep
            # in the tree leaves it old. On 2026-10-16 build-202610160434-9e90 recorded G7.T019-2 but kept editing the
            # old G7.T019 tree; the watchdog reaped that tree as a superseded copy 21 s after the unit wrote
            # FamilyFactory.cs in it, the unit's next `cd` into it failed, and its Set-Content ran in the main tree
            # (kit item IN-20261016125015-6592). So the newest FILE decides: any file written after the claim, or
            # inside the quiet period, means a process is working there, even if it is the wrong tree.
            $newest = @(Get-ChildItem $d.FullName -Recurse -File -Force -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
            if ($newest.Count) {
                $wrote = $newest[0].LastWriteTimeUtc
                $quiet = ((Get-Date).ToUniversalTime() - $wrote).TotalMinutes
                if ($wrote -ge $claimAt[$id] -or $quiet -lt $script:ReapQuietMinutes) {
                    $acts.Add("KEPT $id $($d.FullName): superseded copy, but $($newest[0].Name) was written $([int]$quiet) min ago (after the claim or inside the $($script:ReapQuietMinutes) min quiet period); the holder may be working in the wrong tree - not reaped")
                    continue
                }
            }
            $out = & $remove -Repo $Repo -Session $Session -Path $d.FullName -Label $id -Reason "watchdog: superseded copy; $id is live in $($recorded[$id])"
            if ($out -notlike 'NOTHING*') { $acts.Add("$out") }
            continue
        }
        $owner = Get-LiveTreeOwner $d.FullName
        if ($owner) { $acts.Add("KEPT $($d.FullName): $owner - not harvested, not reaped and not pruned"); continue }
        $s = $state[$id]
        $r = $null
        if (-not $s) { $r = 'orphan: no task on the board owns this directory' }
        elseif ($s -in @('integrated', 'done')) { $r = "task is $s" }
        # New-TaskWorktree never reuses a directory, it suffixes -2, so any tree that is not the one the task records is
        # dead the moment it is superseded, and a task that bounced back to planned or ticketed will be given a fresh
        # tree when it is re-claimed. Both were leaking ~500 MB each until the disk filled.
        # A copy is superseded only by a tree that EXISTS. When this host's worktrees moved from C: to D: the trees
        # moved but the tasks kept recording C:\devops\worktrees\..., a path that is gone, and at 15:35Z on  # history
        # 2026-10-01 the watchdog reaped nine D: trees as "superseded copy; the task records C:\...": the tree it
        # deleted WAS the task's tree. Salvage-before-reap kept the content, but a building or built task must not lose
        # its tree to a stale record, so a missing recorded path falls through to the state rules below instead.
        elseif ($recorded[$id] -and $recorded[$id] -ne $d.FullName -and (Test-Path -LiteralPath $recorded[$id])) { $r = "superseded copy; the task records $($recorded[$id])" }
        elseif ($s -in @('planned', 'ticketed', 'blocked', 'failed')) { $r = "task went back to $s; a re-claim builds in a fresh tree" }
        if (-not $r) {
            # Still live work (planned..built). Build output is 92% of a worktree and nothing reads it, so reclaim that
            # much and keep the tree, in case the task is resumed there as G2.T33 was after its session died.
            # Only UNDER PRESSURE, though. A built task is waiting for an integrator, and a rebuild of its tree costs
            # minutes the next session pays for nothing when the drive had room all along. `unknown` is not pressure:
            # Get-DiskFreeMB answers $null for a path whose root it cannot read, and a reading nobody has is not a
            # reason to delete. The band travels into the reason, so `owner\worktrees.md` records WHY each prune ran.
            if ($s -eq 'built' -and $pressure) {
                $out = & $remove -Repo $Repo -Session $Session -Task $id -Path $d.FullName -BuildOutputOnly -Reason "watchdog: built, patch exported; disk $band ($freeMB MB free, need $needMB MB)"
                if ($out -like 'PRUNED*' -and $out -notlike '*(0 MB)*') { $acts.Add("$out") }
            }
            continue
        }
        if (-not $s -and -not @(Get-TreeNamedTasks $d.FullName).Count) {
            # An orphan with a process running out of it is not reaped: the removal fails on the open files, and the
            # retry next tick would then have to decide whether to kill. Same rule as the retry: no task named, no kill.
            $procs = @(Get-TreeProcesses $d.FullName)
            if ($procs.Count) { $acts.Add("KEPT $($d.FullName): $($procs.Count) process(es) running out of it ($(@($procs | ForEach-Object { "pid $($_.ProcessId) $($_.Name)" }) -join ', ')) and its name points at no task - not reaped"); continue }
        }
        if (-not (Save-BeforeReap $(if ($s) { $id } else { '' }) $d.FullName $s)) { continue }
        # An orphan names no task, so -Task is left off: passing an id the board no longer holds is a refusal.
        $out = if ($s) { & $remove -Repo $Repo -Session $Session -Task $id -Path $d.FullName -Reason "watchdog: $r" }
               else { & $remove -Repo $Repo -Session $Session -Path $d.FullName -Reason "watchdog: $r" }
        if ($out -notlike 'NOTHING*') { $acts.Add("$out") }
    }
}

# ---- registered trees no root covers, and build output nobody reads ----
# Every rule above looks only INSIDE $roots: the parents of the trees tasks record, plus {WorktreesRoot}\<repo>. A
# tree a session laid down BY HAND - a skeptic round, a floor probe - sits in {WorktreesRoot} itself, which is not
# a root, so nothing on the board has ever seen it. Measured 2026-09-30 on this host: twelve such trees registered to
# this repo, about 520 MB each once built in, against 6.1 GB free on C:.
# They are NOT reaped. Nothing on the board says whether a person still wants one, and a tree no task owns is exactly
# the tree whose content has nowhere to go. They are REPORTED every cycle as a note, never as a decision line, so a
# standing condition does not append a decision each pass. Their BUILD OUTPUT is pruned once the drive is in the band
# Get-StreamStatus.ps1 already warns about: bin/obj is about 450 MB of each 500 MB tree, a rebuild costs minutes, and a
# drive that fills costs somebody a compile failure that reads as a defect in their ticket. Under no pressure nothing
# is deleted, because an ad-hoc tree with its build output intact is still usable as it stands.
# $band, $freeMB, $needMB and $pressure come from the single reading taken before the sweep loop.
$rootsLower = @($roots | ForEach-Object { $_.ToLowerInvariant().TrimEnd('\') })
$repoLower = $Repo.ToLowerInvariant().TrimEnd('\')
foreach ($path in @($mine.Keys | Sort-Object)) {
    if ($path -eq $repoLower) { continue }                       # git lists the main tree too, and it is not a task tree
    if (-not (Test-Path -LiteralPath $path)) { continue }
    if ($rootsLower -contains (Split-Path $path)) { continue }    # one of the roots above already governs it
    if (Invoke-SnapshotRule $path) { continue }                   # a suite snapshot made under a -WorktreeRoot override
    # A junction or symlink is never followed: on this host {WorktreesRoot} holds links into the live repo, and a
    # recursive delete through one would take repository content.
    $dir = Get-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue
    if (-not $dir) { continue }
    if ($dir.Attributes -band [IO.FileAttributes]::ReparsePoint) { $notes.Add("OUTSIDE-ROOT $path is a reparse point, so it is reported and never followed"); continue }
    $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue)
    $mb = if ($files.Count) { [int]((($files | Measure-Object Length -Sum).Sum) / 1MB) } else { 0 }
    $newest = @($files | Sort-Object LastWriteTimeUtc -Descending | Select-Object -First 1)
    $quiet = if ($newest.Count) { [int](((Get-Date).ToUniversalTime() - $newest[0].LastWriteTimeUtc).TotalMinutes) } else { 0 }
    $binDirs = @(Get-ChildItem -LiteralPath $path -Recurse -Directory -Force -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('bin', 'obj') })
    $bin = @($binDirs | ForEach-Object { Get-ChildItem -LiteralPath $_.FullName -Recurse -File -Force -ErrorAction SilentlyContinue })
    $binMB = if ($bin.Count) { [int]((($bin | Measure-Object Length -Sum).Sum) / 1MB) } else { 0 }
    # An unowned tree can hold the ONLY copy of real work. Measured 2026-09-30: five of these twelve carried changes
    # no patch anywhere held, one of them a new test file that was on no branch, and one (g6pred) belonged to no row at
    # all (kit item IN-20260930184854-4874). So the note counts the changed files: a size alone does not say that.
    $changed = @(& git -C $path status --porcelain 2>$null | Where-Object { $_ }).Count
    $why = "OUTSIDE-ROOT $path ($mb MB, $binMB MB of it build output, $changed changed file(s), last written $quiet min ago) is registered to this repo and no task records it, so no reaper rule reaches it; the drive is $band at $freeMB MB free against $needMB MB needed"
    if ($changed) { $why += "; those changes exist nowhere else unless a patch already carries them, so export before anybody deletes this tree" }
    # A SCRATCH tree ({WorktreesRoot}\<repo>-scratch\<task>-<purpose>, lib Get-StreamScratchRoot's note) is laid down by
    # hand for one probe, RED run or refresh check and recorded by no task, so the report above was all it ever got: on
    # 2026-10-25 ten such trees, 2 to 5 days old and 8 of them dirty, had to be exported and removed by the owner (kit
    # item IN-20261025140859-22ee). The scratch folder rule applies to it instead: once nothing in it has been written for
    # StreamScratchKeepHours, no live session names it and no process runs out of it, its changes are saved as a patch
    # under .streams\salvage\scratch and the tree is removed. A save that fails keeps the tree.
    if ((Split-Path $path) -eq "$((Get-StreamWorktreeRoot $Repo).ToLowerInvariant().TrimEnd('\'))-scratch" -and $quiet -ge ($script:StreamScratchKeepHours * 60)) {
        $owner = Get-LiveTreeOwner $path
        if ($owner) { $notes.Add("SCRATCH $path is quiet $quiet min, but $owner, so it is kept"); continue }
        $procs = @(Get-TreeProcesses $path)
        if ($procs.Count) { $notes.Add("SCRATCH $path is quiet $quiet min, but $($procs.Count) process(es) run out of it ($(@($procs | ForEach-Object { "pid $($_.ProcessId) $($_.Name)" }) -join ', ')), so it is kept"); continue }
        $saved = ''
        if ($changed) {
            $salDir = Join-Path $P.Root 'salvage\scratch'
            New-Item -ItemType Directory -Path $salDir -Force | Out-Null
            $salFile = Join-Path $salDir ("{0}-{1}.patch" -f (Split-Path $path -Leaf), (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'))
            # Untracked files are part of the work, so they are staged first; --output keeps CR bytes a captured stdout drops.
            & git -C $path add -A 2>$null | Out-Null
            $addExit = $LASTEXITCODE
            & git -C $path diff --cached --binary HEAD --output=$salFile 2>$null | Out-Null
            $diffExit = $LASTEXITCODE
            if ($addExit -ne 0 -or $diffExit -ne 0 -or -not (Test-Path -LiteralPath $salFile) -or (Get-Item -LiteralPath $salFile).Length -eq 0) {
                $notes.Add("$why; SCRATCH save failed (git add exit $addExit, diff exit $diffExit), so the tree is kept for a person to export")
                continue
            }
            $saved = "; its $changed changed file(s) were saved to $salFile"
        }
        $out = & $remove -Repo $Repo -Session $Session -Path $path -Label 'scratch' -Reason "watchdog: scratch tree untouched $quiet min, no live owner$saved"
        $acts.Add("REAPED-SCRATCH $path (quiet $quiet min$saved): $out")
        continue
    }
    if ($band -in @('ok', 'unknown')) { $notes.Add("$why, and nothing is deleted while the drive is not under pressure"); continue }
    if ($binMB -lt 1) { $notes.Add("$why, and it holds no build output to prune"); continue }
    $owner = Get-LiveTreeOwner $path
    if ($owner) { $notes.Add("$why, and $owner, so its build output stays"); continue }
    # The same clock the reaper uses: something writing inside the tree means a process is in there, whatever the board
    # says, and a build reads and writes bin/obj all the way through.
    if ($quiet -lt $script:ReapQuietMinutes) { $notes.Add("$why, and it was written to inside the $($script:ReapQuietMinutes) min quiet period, so a process is still inside it and its build output stays"); continue }
    $out = & $remove -Repo $Repo -Session $Session -Path $path -Label 'ad-hoc' -BuildOutputOnly -Reason "watchdog: registered outside every worktree root, untouched $quiet min, drive $band at $freeMB MB free against $needMB MB needed"
    if ($out -like 'PRUNED*') { $acts.Add("$out ad-hoc tree outside every root; the TREE IS KEPT, only bin/obj went") }
    else { $notes.Add("$why, and the prune did nothing: $out") }
}

# Inbox sweep (see the header). The board is the only evidence a session is still alive: an inbox hold writes nothing
# after the `taken` line, so a holder deep in one long item and a holder that died an hour ago read identically from
# the inbox file alone. $seen is the last moment each session touched tasks.json, from history and from claim beats.
$seen = @{}
foreach ($t in $doc.tasks) {
    foreach ($h in @($t.history)) { if ($h.by -and (-not $seen[$h.by] -or $seen[$h.by] -lt $h.at)) { $seen[$h.by] = $h.at } }
    $c = $t['claim']
    if ($c -and $c.session -and $c.beat -and (-not $seen[$c.session] -or $seen[$c.session] -lt $c.beat)) { $seen[$c.session] = $c.beat }
}
# An inbox hold is not the only thing a session does. A holder that has just taken, closed or annotated ANOTHER item
# is demonstrably alive even with nothing written to tasks.json, and a prose-only item - ticket and grader wording over
# rows nobody claims - writes nothing to the board for its whole life. So inbox events count as evidence too. This does
# NOT save a holder whose only event is its own `taken` line: that moment is what the hold's age already measures.
foreach ($sk in $script:InboxSkills) {
    $seenPath = Get-InboxPath $P $sk
    if (-not (Test-Path $seenPath)) { continue }
    foreach ($l in [IO.File]::ReadAllLines($seenPath)) {
        if ($l -notmatch '^- IN-\S+ \| (\S+) \| ([^|]+?) \| ') { continue }
        $seenAt = $Matches[1]; $seenWho = $Matches[2].Trim()
        if ($seenWho -and (-not $seen[$seenWho] -or $seen[$seenWho] -lt $seenAt)) { $seen[$seenWho] = $seenAt }
    }
}
function Test-HolderWorking([string] $Who, [int] $LimitMinutes) {
    $at = $seen[$Who]
    if (-not $at) { return $false }
    ((Get-Date).ToUniversalTime() - [datetime]::Parse($at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes -lt $LimitMinutes
}
foreach ($skill in $script:InboxSkills) {
    $path = Get-InboxPath $P $skill
    if (-not (Test-Path $path)) { continue }
    $limit = $script:InboxLimitMinutes[$skill]
    $stale = @(Read-InboxItems $path | Where-Object {
        $_.status -eq 'taken' -and (Get-InboxAgeMinutes $_) -ge $limit -and -not (Test-HolderWorking $_.statusBy $limit)
    })
    if (-not $stale.Count) { continue }
    [void](Invoke-InboxLocked $path $Session {
        foreach ($it in $stale) {
            $age = Get-InboxAgeMinutes $it
            $acts.Add("RELEASED $($it.id) in ${skill}: taken by $($it.statusBy) $age min ago (limit $limit min), holder silent on the board since $(if ($seen[$it.statusBy]) { $seen[$it.statusBy] } else { 'never' })")
            # A re-opened line used to be a byte copy of the filing, so it read as the FILER re-filing the item moments
            # ago. On 2026-09-30 that cost two author sessions the same work: IN-20260930132935-5281 came back carrying
            # coord-202609291248 in the by column at 14:33:01Z, 39 minutes after author-...-e6ed had already amended all
            # three tickets and their graders, and the next author started writing them again. The line now says what it
            # is and who went silent, in BOTH places a reader looks: the by column, which Get-InboxItems prints, and the
            # ask, which anyone reading the file raw sees. Read-InboxItems takes kind, task, ask and evidence from the
            # FIRST line of an id, so neither string ever accumulates across two releases. No ' | ' inside either, or the
            # line stops parsing.
            $mark = "WATCHDOG RE-OPEN, previous holder $($it.statusBy) silent $age min"
            '- {0} | {1} | {2} | open | {3} | {4} | {5} | {6}' -f $it.id, (Get-Now), "$($it.from) ($mark)", $it.kind, $it.task, ("RE-OPENED BY THE WATCHDOG - $mark, limit $limit min. CHECK the task's ticket, grader and verdict before redoing this: the previous holder may have finished it without writing to tasks.json. " + $it.ask), $it.evidence
        }
    })
}


# Temp sweep. Windows GetTempFileName draws one name out of a 65,536-name space per folder, and when that space is full
# MSBuild reports the failure as "There is not enough space on the disk" (MSB3021) however much space the disk has: on
# 2026-09-29 CORPLTR94 had 11 GB free and both a solution build and Export-TaskPatch.ps1 failed in worktree G4.T006
# until about 65,535 stale tmpNNNN.tmp files were deleted (kit item IN-20260929144007-b69a). Tests also leave speedy-*
# folders behind when their cleanup loses the race. Only the temp folder, only those two shapes, and only entries older
# than the build claim limit, so nothing a live build is holding is touched. A locked file simply stays.
$tempRoot = if ($env:STREAM_TEMP_ROOT) { $env:STREAM_TEMP_ROOT } else { [IO.Path]::GetTempPath() }
if (Test-Path $tempRoot) {
    $tempCut = (Get-Date).AddMinutes(-$script:ClaimLimitMinutes.build)
    $tmpSeen = 0; $tmpGone = 0
    foreach ($tf in [IO.Directory]::EnumerateFiles($tempRoot, 'tmp*.tmp')) {
        $tmpSeen++
        try { if ([IO.File]::GetLastWriteTime($tf) -lt $tempCut) { [IO.File]::Delete($tf); $tmpGone++ } } catch { }
    }
    if ($tmpGone) { $acts.Add("SWEPT $tmpGone of $tmpSeen stale tmp*.tmp files from $tempRoot (a full name space reads as MSB3021 'not enough space on the disk')") }
    $tmpLeft = $tmpSeen - $tmpGone
    if ($tmpLeft -ge 20000) { $notes.Add("WARN $tmpLeft tmp*.tmp files in $tempRoot are newer than the sweep cut; a build that fails with MSB3021 on this host is name-space exhaustion until free space is actually checked") }
    $dirGone = 0
    foreach ($td in @(Get-ChildItem -LiteralPath $tempRoot -Directory -Filter 'speedy-*' -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTime -lt $tempCut })) {
        Remove-Item -LiteralPath $td.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $td.FullName)) { $dirGone++ }
    }
    if ($dirGone) { $acts.Add("SWEPT $dirGone stale speedy-* temp folders from $tempRoot") }
}

# Tool and test leftovers at the top level of the temp folder and of {ScratchRoot} (random-name .NET folders, dotnet
# workload logs, MSBuildTemp, test folders), a day old, at most STREAM_TEMP_SWEEP_MAX (2000) per pass. Claude's shells
# set TEMP to the scratch root, so these piled up there unseen by the sweep above: 89,249 top-level entries on SMVMTR1
# by 2026-10-17. The hourly scheduled task "AI scratch cleanup" (bin\Clear-AIScratch.ps1, registered by install.ps1)
# runs the same sweep (lib\MachineConfig.psm1 Clear-AIScratchLeftovers) and removes every file unused for a week under
# {ScratchRoot}, so a machine with no stream running is kept clean too; this tick-time sweep keeps a busy stream
# host's TEMP short between the hours. STREAM_SCRATCH_TOP_ROOT overrides the root for the self-tests.
try {
    Import-Module (Join-Path $PSScriptRoot '..\..\..\lib\MachineConfig.psm1') -Force -DisableNameChecking
    $topRoot = if ($env:STREAM_SCRATCH_TOP_ROOT) { $env:STREAM_SCRATCH_TOP_ROOT } else { Get-AIPath ScratchRoot }
    $sweepMax = if ($env:STREAM_TEMP_SWEEP_MAX) { [int]$env:STREAM_TEMP_SWEEP_MAX } else { 2000 }
    foreach ($res in @(Clear-AIScratchLeftovers -Root @($tempRoot, $topRoot) -OlderThanHours $script:StreamScratchKeepHours -Max $sweepMax)) {
        if ($res.Swept) { $acts.Add("SWEPT $($res.Swept) stale tool/test temp entries from $($res.Root)") }
        if ($res.Left) { $notes.Add("NOTE LEFT $($res.Left) more stale tool/test temp entries in $($res.Root) for the next pass (at most $sweepMax per pass)") }
    }
} catch { $notes.Add("NOTE scratch leftover sweep skipped: $($_.Exception.Message)") }

# Stream scratch sweep ({ScratchRoot}\streams\<repo>: skeptic rounds, probes, staging copies). A folder goes once nothing
# inside it has been written for StreamScratchKeepHours, so a long skeptic round that still writes is never touched.
# The folder is per repo, so this sweep never reaches another repo's work. An unreadable profile skips the sweep.
$scratchRepo = try { Get-StreamScratchRoot $Repo } catch { $notes.Add("NOTE stream scratch sweep skipped: $($_.Exception.Message)"); $null }
if ($scratchRepo -and (Test-Path -LiteralPath $scratchRepo)) {
    $scratchCut = (Get-Date).ToUniversalTime().AddHours(-$script:StreamScratchKeepHours)
    $scratchGone = 0
    foreach ($sd in @(Get-ChildItem -LiteralPath $scratchRepo -Directory -Force -ErrorAction SilentlyContinue)) {
        # A copy keeps its source files' write times, so a staging folder copied from the kit a second ago holds only
        # old files while the copy runs; it was swept mid-copy on 2026-10-03 (kit item IN-20261003174116-0300). The
        # folder and every subfolder carry their own creation time, which a copy sets to now, so those count too.
        $items = @(Get-ChildItem -LiteralPath $sd.FullName -Recurse -Force -ErrorAction SilentlyContinue)
        $stamps = @($sd.CreationTimeUtc, $sd.LastWriteTimeUtc) + @($items | ForEach-Object { if ($_.PSIsContainer) { $_.CreationTimeUtc } else { $_.LastWriteTimeUtc } })
        $last = ($stamps | Measure-Object -Maximum).Maximum
        if ($last -ge $scratchCut) { continue }
        Remove-Item -LiteralPath $sd.FullName -Recurse -Force -ErrorAction SilentlyContinue
        if (-not (Test-Path -LiteralPath $sd.FullName)) { $scratchGone++ }
    }
    if ($scratchGone) { $acts.Add("SWEPT $scratchGone stale stream scratch folder(s) from $scratchRepo (nothing written for $($script:StreamScratchKeepHours)h)") }
}
# Repo-root junk. errs.txt appeared in the main tree root on 2026-09-29 holding one line of git stderr, written by an
# ad-hoc `... 2> errs.txt` in some session's shell and not by any kit script (kit item IN-20260929135538-c072). It could
# never be committed - Integrate-Patch stages and commits only the paths its own patch names - but nobody owned it and
# nobody saw it. REPORT ONLY: the watchdog never deletes repo content. A log belongs under .streams LOGS, never in the tree.
$junk = @(& git -C $Repo ls-files --others --exclude-standard --directory 2>$null | Where-Object { $_ -and $_ -notmatch '/' })
if ($junk.Count) { $notes.Add("JUNK untracked file(s) in the repo root: $($junk -join ', ') - a log belongs under .streams" + [char]92 + "logs" + [char]92 + ", never in the tree") }

foreach ($a in $acts) { Add-Decision $P $Session "watchdog: $a" }
if ($acts.Count) { $acts } else { 'QUIET' }
foreach ($n in $notes) { $n }
