# Role inboxes: <repo>\.streams\inbox\<skill>.md, one per stream skill. Append-only lines, the contract is in each
# file's header (inbox-template.md). Every write here goes through a per-file lock (CreateNew, like tasks.json), so a
# "taken" is checked against the item's latest line and appended in one step: two sessions can never both take it.
#   item : - <id> | <utc> | <from> | open | request|bug | <task or -> | <ask> | <evidence or ->
#   event: - <id> | <utc> | <by> | taken|done|declined|forwarded | <note>

$script:InboxSkills = @('stream-plan', 'stream-author', 'stream-build', 'stream-integrate', 'stream-status', 'stream-kit')
$script:InboxLimitMinutes = @{ 'stream-author' = 30; 'stream-build' = 45; 'stream-integrate' = 20; 'stream-plan' = 30; 'stream-status' = 30; 'stream-kit' = 30 }
$script:InboxHandles = [ordered]@{
    'stream-plan'      = 'new or changed tasks, scope, write sets, dependsOn, revise a released group, answer requirement questions'
    'stream-author'    = 'rewrite a ticket or grader (e.g. a grader-suspect bounce), grader portability, RED-reason disputes'
    'stream-build'     = 'rebuild or resume a task, reuse a kept patch, a builder-side bug in a built-not-integrated patch'
    'stream-integrate' = 'retry/re-apply a patch, requeue a bounced task, suites/fix-task questions, gate follow-ups, commit problems'
    'stream-status'    = 'break or keep a claim, report or page changes, stale-state cleanup notes'
    'stream-kit'       = 'bugs or changes in the shared kit scripts (stream-kit\scripts) and the SKILL.md contracts of any role'
}

function Get-InboxPath($P, [string] $Skill) {
    if ($Skill -notin $script:InboxSkills) { throw "unknown inbox '$Skill' (one of: $($script:InboxSkills -join ', '))" }
    Join-Path $P.Root "inbox\$Skill.md"
}

# Creates the inbox folder, its evidence folder and any missing inbox file from the template. Never overwrites.
function Initialize-Inboxes($P) {
    $dir = Join-Path $P.Root 'inbox'
    foreach ($d in @($dir, (Join-Path $dir 'evidence'))) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d | Out-Null } }
    $tpl = Get-Content -Raw (Join-Path $PSScriptRoot '..\inbox-template.md')
    foreach ($s in $script:InboxSkills) {
        $f = Join-Path $dir "$s.md"
        if (Test-Path $f) { continue }
        Write-AtomicText $f ($tpl.Replace('{{skill}}', $s).Replace('{{handles}}', $script:InboxHandles[$s]))
    }
}

# One field of a line: no pipes, no line breaks.
function ConvertTo-InboxField([string] $s) { if (-not $s) { return '-' }; (($s -replace '[\r\n]+', ' ') -replace '\s*\|\s*', ' / ').Trim() }

# Every item of one inbox, oldest first: its first (open) line's fields plus its latest status.
# The task an item is about when its task field is empty: the id that LEADS the ask, as in "G3.T121: grader C1
# defect". IN-20261001161521-42df named G3.T121 only that way, so Claim-Task's skip-over-held-rows missed it and handed
# the row to a second author twice while the holder rewrote its grader (kit item IN-20261001162407-ee8c). Only a
# leading "<id>:" counts: an ask mentions many ids, and skipping every one of them would starve the sort.
function Get-AskLeadTask([string] $Ask) {
    if ($Ask -match '^\s*([A-Za-z][A-Za-z0-9]*\.[A-Za-z0-9]+)\s*:') { $Matches[1] } else { '' }
}

function Read-InboxItems([string] $Path) {
    $items = [ordered]@{}
    if (-not (Test-Path $Path)) { return @() }
    foreach ($l in [IO.File]::ReadAllLines($Path)) {
        if ($l -notmatch '^- (IN-\S+) \| ') { continue }
        $f = @(($l.Substring(2)) -split ' \| ')
        # A line too short to carry a status is skipped, not read. These files are hand-editable, and the watchdog now
        # reads all six every tick: one truncated line must not throw there, or it takes the claim breaking and the
        # worktree reaper down with it.
        if ($f.Count -lt 4) { continue }
        $id = $f[0]
        if (-not $items.Contains($id)) {
            $items[$id] = [ordered]@{ id = $id; at = $f[1]; from = $f[2]
                kind = if ($f.Count -gt 4) { $f[4] } else { 'request' }; task = if ($f.Count -gt 5) { $f[5] } else { '-' }
                ask = if ($f.Count -gt 6) { $f[6] } else { '' }; evidence = if ($f.Count -gt 7) { $f[7] } else { '-' }
                status = $f[3]; statusAt = $f[1]; statusBy = $f[2]; note = '' }
            if ($items[$id].task -eq '-') { $lead = Get-AskLeadTask $items[$id].ask; if ($lead) { $items[$id].task = $lead } }
            continue
        }
        $it = $items[$id]
        # A `beat` is a HEARTBEAT UNDER THE HOLD, not a status of its own. An inbox item has nothing else to beat - a
        # task claim has Update-Task -Beat - so a holder inside one long step looked exactly like a holder that died:
        # stream-author step 7 mandates one skeptic round, one such round ran 54 minutes on 2026-09-30, and at 89
        # minutes the watchdog re-opened the item under a session that was working. Two sessions then wrote the same six
        # files inside twenty minutes, and it was the second occurrence that day (kit item IN-20260930173837-50cb).
        # It moves the hold's clock and changes nothing else, and only the holder's own beat counts.
        # A `note` line is an annotation appended after the fact, by the session that wrote the latest status line. The
        # record is append-only, so without it a wrong or placeholder note could never be corrected (kit item
        # IN-20260930175245-b92e). It leaves the status, its time and its author exactly as they were.
        if ($f[3] -eq 'note') {
            if ($f.Count -gt 4) { $it.note = ($f[4..($f.Count - 1)] -join ' | ') }
            continue
        }
        if ($f[3] -eq 'beat') {
            if ($it.status -eq 'taken' -and $it.statusBy -eq $f[2]) { $it.statusAt = $f[1] }
            continue
        }
        $it.status = $f[3]; $it.statusAt = $f[1]; $it.statusBy = $f[2]; $it.note = if ($f.Count -gt 4) { ($f[4..($f.Count - 1)] -join ' | ') } else { '' }
    }
    @($items.Values)
}

function Get-InboxAgeMinutes($Item) {
    [int]((Get-Date).ToUniversalTime() - [datetime]::Parse($Item.statusAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes
}

# Actionable here: open, or taken but silent past the inbox's limit. A forwarded item is owned by the target inbox.
function Test-InboxOpen($Item, [string] $Skill) {
    if ($Item.status -eq 'open') { return $true }
    ($Item.status -eq 'taken' -and (Get-InboxAgeMinutes $Item) -ge $script:InboxLimitMinutes[$Skill])
}

# The rows a live inbox hold is working on, as id -> "<item> held by <session> in <inbox>". Claim-Task.ps1 skips these
# rows in its sort and Get-StreamStatus.ps1 counts them out of the claimable rows, so both read them from here: two
# copies of the rule would let the board call a row claimable that no claim will ever take. Only a TAKEN hold inside its
# inbox's silence limit counts: an open item names a row nobody is editing yet, and a dead hold must not park a row.
# The one exception is an OPEN stream-integrate item: the integrator takes it, not an author or builder, and it asks for
# a state move on the row it names, so the row is parked from the moment it is filed. G13.T056 was released planned for
# the integrator to undo planned>built, and the next author unit reclaimed it 6 s later, before the integrator took
# the item (kit item IN-20261018181037-f5b0). It parks the row only inside the integrate inbox's limit, like a hold.
function Get-InboxHeldRows($P) {
    $busy = @{}
    foreach ($skill in $script:InboxSkills) {
        foreach ($it in @(Read-InboxItems (Get-InboxPath $P $skill))) {
            if ($it.status -ne 'taken' -and -not ($it.status -eq 'open' -and $skill -eq 'stream-integrate')) { continue }
            if ((Get-InboxAgeMinutes $it) -ge $script:InboxLimitMinutes[$skill]) { continue }
            $id = [string] $it.task
            if (-not $id -or $id -eq '-') { continue }
            if (-not $busy.Contains($id)) { $busy[$id] = if ($it.status -eq 'open') { "$($it.id) open for $skill" } else { "$($it.id) held by $($it.statusBy) in $skill" } }
        }
    }
    $busy
}

# The work files a unit changed under .streams\ since it started (tickets, graders, checks, verdicts, patches, plans),
# relative to .streams\. Bookkeeping folders and files are left out: they change on every cycle and say nothing about
# how far the work got.
function Get-StreamWorkFilesSince($P, [datetime] $SinceUtc) {
    $skip = @('logs', 'inbox', 'runners', 'idle', 'lessons', 'owner', 'suites', 'units')
    $rootLen = $P.Root.TrimEnd('\').Length + 1
    @(Get-ChildItem -LiteralPath $P.Root -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
        $rel = $_.FullName.Substring($rootLen)
        $top = ($rel -split '[\\/]')[0]
        $_.LastWriteTimeUtc -ge $SinceUtc -and $top -notin $skip -and $rel -notlike 'tasks.json*' -and
            $rel -notlike '*.lock' -and $rel -ne 'decisions.md' -and $rel -ne 'config.json'
    } | Sort-Object FullName | ForEach-Object { $_.FullName.Substring($rootLen) })
}

# A runner unit of a WORK role (author, build) has its own session id, and that session never comes back once the unit
# ends. An inbox item it still holds then sat taken until the role's silence limit, and the next holder started it from
# scratch: author-202610051459-b841 took IN-20261005185715-dde9 (re-pin 67 G3 graders), re-pinned 54 of them, was ended
# at its 1800 s limit at 19:29Z, and nothing on the item said how far it got (kit item IN-20261005193358-71ec). The
# runner now re-opens each such item at once and writes a progress file in inbox\evidence\ naming the work files the
# unit changed, so the next holder CONTINUES. Returns one line per re-opened item.
function Open-UnitInboxHolds($P, [string] $Session, [datetime] $SinceUtc, [string] $How) {
    $done = [Collections.Generic.List[string]]::new()
    $files = @(Get-StreamWorkFilesSince $P $SinceUtc)
    $evDir = Join-Path $P.Root 'inbox\evidence'
    foreach ($skill in $script:InboxSkills) {
        $path = Get-InboxPath $P $skill
        if (-not (Test-Path $path)) { continue }
        $held = @(Read-InboxItems $path | Where-Object { $_.status -eq 'taken' -and $_.statusBy -eq $Session })
        if (-not $held.Count) { continue }
        [void](Invoke-InboxLocked $path $Session {
            foreach ($it in @(Read-InboxItems $path | Where-Object { $_.status -eq 'taken' -and $_.statusBy -eq $Session })) {
                if (-not (Test-Path $evDir)) { New-Item -ItemType Directory -Path $evDir -Force | Out-Null }
                $prog = Join-Path $evDir "$($it.id).progress.md"
                # The progress a holder reports lives in its beat notes, which Read-InboxItems keeps no copy of.
                $last = @([IO.File]::ReadAllLines($path) | Where-Object { $_ -like "- $($it.id) | *" } | ForEach-Object { , @($_.Substring(2) -split ' \| ') } |
                    Where-Object { $_.Count -ge 5 -and $_[2] -eq $Session -and $_[3] -in @('taken', 'beat', 'note') -and $_[4] -ne '-' } | ForEach-Object { $_[4..($_.Count - 1)] -join ' | ' }) | Select-Object -Last 1
                $body = @("## $(Get-Now) unit $Session ended ($How) holding $($it.id)", '',
                    "Unit started $($SinceUtc.ToString('yyyy-MM-ddTHH:mm:ssZ')). Its last note: $(if ($last) { $last } else { '(none)' })", '',
                    "Work files under .streams\ changed since then ($($files.Count)):")
                $body += if ($files.Count) { @($files | ForEach-Object { "- $_" }) } else { @('- (none)') }
                Add-Content -LiteralPath $prog -Value ($body + '') -Encoding utf8
                $rel = "inbox\evidence\$($it.id).progress.md"
                $mark = "RUNNER RE-OPEN, unit $Session ended $How, $($files.Count) work files changed, see $rel"
                $done.Add("REOPENED $($it.id) in ${skill}: unit $Session ended ($How); progress in $rel")
                '- {0} | {1} | {2} | open | {3} | {4} | {5} | {6}' -f $it.id, (Get-Now), (ConvertTo-InboxField "$($it.from) ($mark)"), $it.kind, $it.task, (ConvertTo-InboxField ("RE-OPENED BY THE RUNNER - $mark. CONTINUE from that file, do not restart: the files it lists were already changed by the ended unit, so check each against the ask before redoing it. " + $it.ask)), $it.evidence
            }
        })
    }
    $done.ToArray()
}

# Runs $Action under the inbox file's lock; the action appends through the returned lines (a string array).
function Invoke-InboxLocked([string] $Path, [string] $Session, [scriptblock] $Action) {
    $lock = "$Path.lock"
    $deadline = (Get-Date).AddSeconds(15)
    $fs = $null
    while (-not $fs) {
        try {
            $fs = [IO.File]::Open($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $b = [Text.Encoding]::UTF8.GetBytes((@{ session = $Session; at = (Get-Now) } | ConvertTo-Json -Compress))
            $fs.Write($b, 0, $b.Length); $fs.Flush($true)
        } catch [IO.IOException] {
            $fs = $null
            $age = try { ((Get-Date) - (Get-Item $lock).LastWriteTime).TotalSeconds } catch { 0 }
            # Stale only when the delete works: a live holder keeps the file open and it stays, and then this waits
            # (and times out) like any other wait instead of spinning with no sleep (kit item IN-20261010161046-9992).
            if ($age -gt $script:StaleLockSeconds) { Remove-Item $lock -Force -ErrorAction SilentlyContinue; if (-not (Test-Path $lock)) { continue } }
            if ((Get-Date) -gt $deadline) { throw "inbox lock busy for 15s: $lock" }
            Start-Sleep -Milliseconds 100
        }
    }
    try {
        $lines = @(& $Action)
        foreach ($l in $lines) {
            if (-not $l) { continue }
            for ($i = 0; ; $i++) {
                try { [IO.File]::AppendAllText($Path, ($l + "`n"), [Text.UTF8Encoding]::new($false)); break }
                catch [IO.IOException] { if ($i -ge 50) { throw }; Start-Sleep -Milliseconds 100 }
            }
        }
        $lines
    } finally {
        $fs.Dispose()
        Remove-Item $lock -Force -ErrorAction SilentlyContinue
    }
}
