# Shared library for the stream kit. Every stream skill dot-sources this file.
# tasks.json is the single coordination point: writers take a CreateNew lock file for the read-modify-write only
# (milliseconds), write temp + rename so a reader never sees half a file, and readers never lock.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:StaleLockSeconds = 120
$script:ClaimLimitMinutes = @{ author = 30; build = 45 }
# The owner's configuration file of the last repo Get-StreamPaths resolved (.streams\config.json), and its parsed
# copy keyed by write time, for the lib functions that take a board and no paths (Get-FocusGroups).
$script:StreamConfigFile = ''
$script:StreamConfigCache = $null
$script:IntegratorLockMinutes = 20
# How long a worktree must have been untouched before the watchdog may harvest or reap it. A grader beats the claim but
# `dotnet test` does not, so a build whose blind verifier is running long tests looks idle on the board while a process
# writes inside the tree. On 2026-09-30 that cost G3.T030 its patch: the harvest caught a deliberate verifier mutation.
# STREAM_REAP_QUIET_MINUTES overrides it for the self-tests, whose fixtures lay a tree down and reap it in the same
# second; production leaves the variable unset and gets 10.
$script:ReapQuietMinutes = if ($env:STREAM_REAP_QUIET_MINUTES -match '^\d+$') { [int]$env:STREAM_REAP_QUIET_MINUTES } else { 10 }

# A BEAT IS NOT PROGRESS. An author claim is ALSO stale when the row itself has not moved for this long, however fresh
# the beat: on 2026-09-29 author-202609290308-f45a claimed G4.T039 at 20:39:27Z, wrote its ticket and grader by
# 21:10:12Z, then beat every few minutes for 19h14m and wrote nothing else - no artifact, no history line, and it never
# applied the owner decision written into the row at 06:25:23Z. Its last beat was 45 seconds old when the owner released
# the claim by hand, so the 30 minute beat limit was never within hours of firing (kit item IN-20260930170751-b5a7).
# Raising the beat limit cannot separate the two cases: a working author and a zombie author beat identically, and the
# only signal that tells them apart is whether the ROW moved. BUILD IS DELIBERATELY EXEMPT - a build legitimately runs
# for an hour with no board write, which is why stream-build was told to beat during long builds.
# STREAM_NOPROGRESS_MINUTES overrides it for the self-tests; production leaves it unset and gets 60.
$script:NoProgressMinutes = if ($env:STREAM_NOPROGRESS_MINUTES -match '^\d+$') { [int]$env:STREAM_NOPROGRESS_MINUTES } else { 60 }

# ---- free disk, measured in ONE place because two scripts act on the same reading ----
# Get-StreamStatus.ps1 raises the flag and Invoke-Watchdog.ps1 prunes build output under it. Two copies of the
# arithmetic would let the watchdog delete files at a threshold nobody was ever warned about, so the constants and the
# three questions - how much is free, how much is needed, which band is that - live here.
# A POPULATED worktree carries its own bin/obj: measured 2026-09-30, 599, 592, 506 and 505 MB against 57 MB for a
# source-only tree, so build output is roughly 450 MB of each 500 MB and the need scales with live build claims.
$script:PerWorktreeMB = 550
$script:DiskFloorMB = 3072
# STREAM_FREE_MB_TEST stands in for the reading the way STREAM_REAP_QUIET_MINUTES stands in for the reap window: a
# self-test cannot fill a disk, and a threshold nothing exercises is a threshold nobody trusts.
function Get-DiskFreeMB([string] $Path) {
    $qual = try { [IO.Path]::GetPathRoot($Path) } catch { $null }
    # GetPathRoot gives 'C:', and Get-PSDrive wants the NAME, so take the letter itself.
    if (-not $qual -or $qual -notmatch '^[A-Za-z]:') { return $null }
    if ($env:STREAM_FREE_MB_TEST -match '^\d+$') { return [int]$env:STREAM_FREE_MB_TEST }
    try { [int]((Get-PSDrive $qual.Substring(0, 1) -ErrorAction Stop).Free / 1MB) } catch { $null }
}
# ---- where task worktrees live: the machine profile's WorktreesRoot, one folder per repo ----
# The root is a per-machine value (ProfileMachineConfig.md, key WorktreesRoot), read through the MachineConfig lib
# that the AI installer puts at {ClaudeHome}\lib - four folders up from this file in both the installed tree and the
# corpus. STREAM_WORKTREE_ROOT overrides it for the self-tests, which lay trees down under their own temp root.
function Get-StreamWorktreeRoot([string] $Repo) {
    $root = $env:STREAM_WORKTREE_ROOT
    if (-not $root) {
        $lib = Join-Path $PSScriptRoot '..\..\..\..\lib\MachineConfig.psm1'
        if (-not (Test-Path -LiteralPath $lib)) { throw "Stream kit: MachineConfig.psm1 not found at $lib. Run Install-AIMachine.ps1 on this machine." }
        Import-Module $lib -Force
        $root = Get-AIPath WorktreesRoot
    }
    [IO.Path]::Combine($root, (Split-Path -Leaf $Repo))
}
# ---- where a session's throwaway stream work lives: {ScratchRoot}\streams\<repo> (spec D14) ----
# Skeptic rounds, probes and staging copies go to <this>\<task>-<purpose>; the watchdog sweeps folders there once
# nothing in them has been written for StreamScratchKeepHours. A scratch WORKTREE is different: git-guard allows
# worktrees only under {WorktreesRoot}, so those go to {WorktreesRoot}\<repo>-scratch\<task>-<purpose>.
# STREAM_SCRATCH_ROOT overrides the streams folder for the self-tests.
$script:StreamScratchKeepHours = 24
function Get-StreamScratchRoot([string] $Repo) {
    $root = $env:STREAM_SCRATCH_ROOT
    if (-not $root) {
        $lib = Join-Path $PSScriptRoot '..\..\..\..\lib\MachineConfig.psm1'
        if (-not (Test-Path -LiteralPath $lib)) { throw "Stream kit: MachineConfig.psm1 not found at $lib. Run Install-AIMachine.ps1 on this machine." }
        Import-Module $lib -Force
        $root = [IO.Path]::Combine((Get-AIPath ScratchRoot), 'streams')
    }
    [IO.Path]::Combine($root, (Split-Path -Leaf $Repo))
}
function Get-DiskNeedMB([int] $LiveBuilds) { [math]::Max($script:DiskFloorMB, $LiveBuilds * $script:PerWorktreeMB) }
# 'low' is the hard flag: a build that fills the drive reports a compile failure, not a full disk. 'warn' is one
# doubling above it, and it is the band the watchdog prunes in - waiting for 'low' means waiting until a build has
# already failed somewhere.
function Get-DiskState([int] $FreeMB, [int] $NeedMB) {
    if ($FreeMB -lt $NeedMB) { 'low' } elseif ($FreeMB -lt 2 * $NeedMB) { 'warn' } else { 'ok' }
}
# A CLAIM THAT CANNOT COMPILE IS REFUSED BEFORE IT STARTS. On 2026-09-30 C: reached 0 GB with builders live, csc
# answered CS8104 and four grader clauses on G3.T120 read red with nothing wrong in the patch (kit items
# IN-20260930231357-8af6 and IN-20260930230701-ae9b). The owner ruled on 2026-10-01 (IN-20261001160218-2d56): a build
# or integrate claim is refused when the drive it builds on has under 5 GB free, with a named refusal that carries the
# measured figure, and the status page flags the same condition. The flag above scales with live builds and warns;
# this floor is the fixed line under which no new build starts at all. An unreadable drive ($null) is not refused:
# a reading nobody has is not evidence of a full disk.
$script:ClaimFloorMB = 5120
function Get-ClaimDiskRefusal([string] $Path, [string] $What) {
    $free = Get-DiskFreeMB $Path
    if ($null -eq $free -or $free -ge $script:ClaimFloorMB) { return $null }
    $drive = ([IO.Path]::GetPathRoot($Path)).TrimEnd('\')
    "REFUSED-DISK $drive has $([math]::Round($free / 1024, 2)) GB free ($free MB), under the $([math]::Round($script:ClaimFloorMB / 1024, 0)) GB floor that $What claims need: a build on a full drive reports compile failures as grader clauses. Free space on $drive, then claim again."
}

# A WRITE SET IS A LIST OF PATHS, and every caller that takes one - a shell argument, a JSON file - can hand over a
# single string holding several. Update-Task.ps1 documents -AddWriteSet <file[,file]>, so a builder that passed
# "a.cs,b.cs,c.cs" had every reason to expect three entries; what it got on 2026-09-30 was ONE entry holding the
# literal three-path string on G3.T100. Export-TaskPatch.ps1 then answered OUTSIDE for all three real files, and a
# builder may never remove a path from a write set, so the malformed entry was permanent (kit item
# IN-20260930184321-a743). Splitting is what the documented spelling already promises. Semicolon splits too, because
# that is the other separator a PowerShell caller reaches for, and surrounding quotes and spaces come off: a quoted
# path that keeps its quotes matches no file on disk.
function Expand-PathList($Values) {
    $out = [Collections.Generic.List[string]]::new()
    foreach ($v in @($Values)) {
        if ($null -eq $v) { continue }
        foreach ($piece in ([string]$v -split '[,;]')) {
            $one = $piece.Trim().Trim('"').Trim("'").Trim()
            if ($one) { [void]$out.Add($one) }
        }
    }
    @($out)
}

# Legal state moves, keyed "from>to", valued with the roles allowed to make them. One table so no skill can invent a
# move the others do not expect.
$script:Transitions = @{
    'planned>ticketed'     = @('author')
    # plan: Revise-Task.ps1 -Release block parks a row whose dependency is not ready, or one released by mistake
    # (kit item IN-20261001191046-5fcc: G3.T202 was released by a note-only edit and no role could park it again).
    'planned>blocked'      = @('author', 'build', 'plan')
    'ticketed>blocked'     = @('plan')
    'ticketed>building'    = @('build', 'integrate')
    'ticketed>planned'     = @('build', 'integrate', 'plan')   # plan: Revise-Task -Release planned, a stale ticket re-authored
    'ticketed>done'        = @('integrate')
    'building>built'       = @('build')
    'building>blocked'     = @('build')
    'building>ticketed'    = @('build', 'status')
    'building>planned'     = @('build')
    'building>done'        = @('integrate')
    'building>ticketed#i'  = @('integrate')
    'built>integrated'     = @('integrate')
    'built>ticketed'       = @('integrate')
    'built>planned'        = @('integrate')   # grader-suspect: new grader, verified patch kept
    'planned>built'        = @('integrate')   # undo a false SUSPECT: retry the kept, verified patch
    'done>ticketed'        = @('integrate')   # an integration task reopened by a fix task added after it passed
    'integrated>done'      = @('integrate')
    'blocked>planned'      = @('plan')
    'blocked>ticketed'     = @('plan')
    'blocked>integrated'   = @('integrate')   # a verified patch already on main; Update-Task requires a clean reverse-apply
    # Retire: Revise-Task.ps1 -Release retire ends a row the planner withdrew as superseded. Before this no role could
    # move a row out of blocked except back into work, so G5.T101, G5.T134, G5.T143 and G2.T114 sat blocked for good and
    # inflated the board's blocked count (kit item IN-20261009150944-5bbd). The role is 'plan-retire', not 'plan', so
    # only Revise-Task's guarded path can make the move; Update-Task -Role plan -To done stays refused.
    'blocked>done#retire'  = @('plan-retire')
}

# A retired row is state done with a `retired` record ({ at, by, note }). Every close and claim rule already treats done
# as finished; the board counts it apart (bucket `retired`) and never as landed work.
function Test-Retired($Task) {
    $Task.state -eq 'done' -and ($Task -is [Collections.IDictionary] -and $Task.Contains('retired') -and $Task['retired'])
}

function Get-StreamPaths([string] $Repo) {
    $root = Join-Path $Repo '.streams'
    $script:StreamConfigFile = Join-Path $root 'config.json'
    [pscustomobject]@{
        Repo      = $Repo
        Root      = $root
        Config    = Join-Path $root 'config.json'
        Tasks     = Join-Path $root 'tasks.json'
        Lock      = Join-Path $root 'tasks.json.lock'
        IntLock   = Join-Path $root 'integrator.lock'
        Decisions = Join-Path $root 'decisions.md'
        Plans     = Join-Path $root 'plans'
        Tickets   = Join-Path $root 'tickets'
        Graders   = Join-Path $root 'graders'
        Patches   = Join-Path $root 'patches'
        Logs      = Join-Path $root 'logs'
        Verdicts  = Join-Path $root 'verdicts'
        Owner     = Join-Path $root 'owner'
        Questions = Join-Path $root 'owner\questions.md'
        Prompts   = Join-Path $root 'owner\permission-prompts.md'
        Gates     = Join-Path $root 'owner\gates.md'
        Worktrees = Join-Path $root 'owner\worktrees.md'
        Idle      = Join-Path $root 'idle'
        PreStage  = Join-Path $root 'prestage'
        Suites    = Join-Path $root 'suites'
    }
}

# THE MAIN TREE AS A BASE: HEAD, then its uncommitted tracked diff, then its untracked non-ignored files. Shared by
# New-TaskWorktree.ps1 (a builder's tree) and New-SuiteSnapshot.ps1 (a group's suite run), so both see main the same way.
# List the untracked files BEFORE the worktree is added: a worktree root inside the repo would otherwise list itself.
# -z with core.quotePath=false gives raw UTF-8 names, never C-quoted ("\303\251"), so a non-ASCII file name resolves to
# the real file. .streams is excluded, so it never travels. A file named after a Windows device (NUL, CON, PRN, AUX,
# COM1-9, LPT1-9, with or without an extension) is a stray from a shell redirect such as `> NUL` in Git Bash: it cannot
# be opened by that name, so it is skipped rather than failing the whole base.
function Get-MainUntracked([string] $Repo) {
    $enc = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.UTF8Encoding]::new($false)
        $raw = (& git -C $Repo -c core.quotePath=false ls-files --others --exclude-standard -z) -join "`n"
        if ($LASTEXITCODE -ne 0) { throw "git ls-files --others failed in $Repo" }
    } finally { [Console]::OutputEncoding = $enc }
    ,@($raw -split "`0" | ForEach-Object { $_.Trim("`n") } | Where-Object { $_ -and (Split-Path -Leaf $_) -notmatch '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(\..*)?$' })
}
# Lays the main tree's diff against $BaseSha (saved to $DiffFile) and the listed untracked files onto worktree $Wt.
# Diffing against the pinned commit carries anything committed after it as part of the dirty diff, so nothing is lost.
# Returns the listed untracked files that were gone by copy time. A file listed and then removed before the copy is not
# main's any more: on 2026-10-17 Builder 4's pre-stage died "Could not find file ...ExistingDataInspector.cs" when the
# integrator reversed G9.T010's patch between the list and the copy (kit item IN-20261017025015-83de). It is skipped,
# not copied, so the base matches main as it now stands.
function Add-MainBase([string] $Repo, [string] $Wt, [string] $BaseSha, [string] $DiffFile, [string[]] $Untracked) {
    & git -C $Repo diff $BaseSha --binary --output=$DiffFile
    if ($LASTEXITCODE -ne 0) { throw "git diff $BaseSha failed in $Repo" }
    if ((Get-Item $DiffFile).Length -gt 0) { [void](Invoke-Git $Wt @('apply', '--binary', '--whitespace=nowarn', $DiffFile)) }
    $gone = [Collections.Generic.List[string]]::new()
    foreach ($u in @($Untracked)) {
        $dst = Join-Path $Wt $u
        $dir = Split-Path $dst
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        try { [IO.File]::Copy((Join-Path $Repo $u), $dst, $true) }
        catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] { $gone.Add($u) }
    }
    # No leading comma: callers wrap the result in @(), which does not unwrap a comma-wrapped array.
    $gone.ToArray()
}
# An EXISTING write-set file of the task under a gitignored path (docs/audit/, .gitignore:98) is not untracked in
# ls-files' sense, so Get-MainUntracked never lists it and the builder's tree lacked it (G18.T001, kit item
# IN-20261021163758-c162). Each exact write-set file that exists on main, is absent from the tree and is ignored there is
# copied in and staged with `git add -f`, so it is part of the base: unstaged, Export-TaskPatch's intent-add would show
# the whole file as new. Wildcard and directory entries are skipped. Returns the paths copied.
function Add-IgnoredWriteSetBase([string] $Repo, [string] $Wt, [string[]] $WriteSet) {
    $copied = [Collections.Generic.List[string]]::new()
    foreach ($w in @($WriteSet)) {
        if (-not $w -or $w -match '[*?]' -or $w -match '[\\/]$') { continue }
        $rel = $w -replace '\\', '/'
        $src = Join-Path $Repo $rel
        $dst = Join-Path $Wt $rel
        if (-not (Test-Path -LiteralPath $src -PathType Leaf) -or (Test-Path -LiteralPath $dst)) { continue }
        & git -C $Repo check-ignore -q -- $rel 2>$null
        if ($LASTEXITCODE -ne 0) { continue }
        $dir = Split-Path $dst
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        [IO.File]::Copy($src, $dst, $true)
        [void](Invoke-Git $Wt @('add', '-f', '--', $rel))
        $copied.Add($rel)
    }
    $copied.ToArray()
}

# SUITE SNAPSHOTS (New-SuiteSnapshot.ps1). One record per snapshot in .streams\suites\<name>.json. The watchdog keeps
# the NEWEST ready snapshot while its session holds a live integrator lock and reaps every other one.
function Get-SuiteSnapshots($P) {
    if (-not (Test-Path $P.Suites)) { return }
    @(foreach ($f in @(Get-ChildItem $P.Suites -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try { $s = Get-Content -Raw $f.FullName | ConvertFrom-Json -AsHashtable -DateKind String } catch { continue }
        if ($s -is [Collections.IDictionary] -and $s['path'] -and $s['at']) { $s }
    })
}

# IDLE BEATS. A session whose claim comes back NONE writes nothing to tasks.json, so the board could not see it: on
# 2026-10-02 the page read "build 2 live" while the owner ran six builders (kit item IN-20261002150214-6ee3). Each
# NONE now leaves .streams\idle\<session>.json ({session, role, at}) and a successful claim removes it, so
# Get-StreamStatus.ps1 counts the session live-idle inside its role's limit. The beat lives OUTSIDE tasks.json on
# purpose: an empty poll every few minutes per builder would otherwise take the board lock and rewrite the board.
function Get-IdleBeatPath($P, [string] $Session) {
    Join-Path $P.Idle (($Session -replace '[^A-Za-z0-9._-]', '_') + '.json')
}
function Set-IdleBeat($P, [string] $Session, [string] $Role) {
    try {
        if (-not (Test-Path $P.Idle)) { New-Item -ItemType Directory -Path $P.Idle -Force | Out-Null }
        Write-AtomicText (Get-IdleBeatPath $P $Session) ([ordered]@{ session = $Session; role = $Role; at = (Get-Now) } | ConvertTo-Json -Compress)
        # One file per session ever seen; a day-old beat counts for nothing, so drop it here rather than in a sweep.
        $cut = (Get-Date).ToUniversalTime().AddDays(-1)
        Get-ChildItem $P.Idle -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -lt $cut } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { Write-Warning "idle beat not written for ${Session}: $_" }
}
function Clear-IdleBeat($P, [string] $Session) {
    Remove-Item -LiteralPath (Get-IdleBeatPath $P $Session) -Force -ErrorAction SilentlyContinue
}
function Get-IdleBeats($P) {
    if (-not (Test-Path $P.Idle)) { return }
    @(foreach ($f in @(Get-ChildItem $P.Idle -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try { $b = Get-Content -Raw $f.FullName | ConvertFrom-Json -AsHashtable -DateKind String } catch { continue }
        if ($b -is [Collections.IDictionary] -and $b['session'] -and $b['role'] -and $b['at']) { $b }
    })
}

# PRE-STAGE MARKS. A runner's pre-stage (Start-StreamRunner.ps1 Invoke-PreStage) claims under a NEW session id, and that
# id becomes a unit, with a <stamp>-<session>.rules.txt, only when the pre-stage launches one. A pre-stage that claims a
# row and then bounces it (a build row whose author grader is not red goes back to planned) writes history under that id
# and no unit ever runs it, so the board counted it live for the role's whole limit: on 2026-10-08 it read build 6 live
# while 5 build runners ran (G4.T119 bounced by build-202610081926-e405). Claim-Task.ps1 marks every pre-stage claim in
# .streams\prestage\<session>.json; Get-SessionActivity drops a marked session that never got a rules file from the live
# count (the runner itself is counted through its state file). The mark changes no claim: the watchdog never reads it,
# so a pre-stage that holds a claim while it proves RED keeps that claim.
function Set-PreStageMark($P, [string] $Session, [string] $Role) {
    try {
        if (-not (Test-Path $P.PreStage)) { New-Item -ItemType Directory -Path $P.PreStage -Force | Out-Null }
        Write-AtomicText (Join-Path $P.PreStage (($Session -replace '[^A-Za-z0-9._-]', '_') + '.json')) ([ordered]@{ session = $Session; role = $Role; at = (Get-Now) } | ConvertTo-Json -Compress)
        $cut = (Get-Date).ToUniversalTime().AddDays(-1)
        Get-ChildItem $P.PreStage -Filter '*.json' -File -ErrorAction SilentlyContinue | Where-Object { $_.LastWriteTimeUtc -lt $cut } | Remove-Item -Force -ErrorAction SilentlyContinue
    } catch { Write-Warning "pre-stage mark not written for ${Session}: $_" }
}
# The marked sessions that never became a runner unit (no <stamp>-<session>.rules.txt under .streams\logs\runner).
function Get-PreStageOnlySessions($P) {
    $only = [Collections.Generic.HashSet[string]]::new()
    $dir = $P.PreStage
    if (-not $dir -or -not (Test-Path $dir)) { return , $only }
    $rules = [Collections.Generic.HashSet[string]]::new()
    $logRoot = Join-Path $P.Root 'logs\runner'
    if (Test-Path $logRoot) {
        foreach ($r in @(Get-ChildItem $logRoot -Recurse -Filter '*.rules.txt' -File -ErrorAction SilentlyContinue)) { if ($r.Name -match '^[0-9TZ]+-(.+)\.rules\.txt$') { [void]$rules.Add($Matches[1]) } }
    }
    foreach ($f in @(Get-ChildItem $dir -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try { $m = Get-Content -Raw $f.FullName | ConvertFrom-Json -AsHashtable -DateKind String } catch { continue }
        if ($m -is [Collections.IDictionary] -and $m['session'] -and -not $rules.Contains([string]$m['session'])) { [void]$only.Add([string]$m['session']) }
    }
    , $only
}
function Get-Now { (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
# A nightly Tier 2 that YIELDED (Start-SuiteRun.ps1: the integrator lock was held) writes no run record, so nothing
# showed that the night's run never happened (kit item IN-20261025145313-3448, TestRunFindings F1). When the last
# stamped entry of logs\suite-nightly.txt (local 's' stamps) is YIELDED and no run record started after it by 07:00
# local, one 'NIGHTLY-YIELDED <yield date>' line goes to the owner queue, once per yield date. The status tick calls
# it. Returns a short note for the tick line.
function Add-NightlyYieldNotice($P, $Now = $null) {
    $nowAt = if ($null -eq $Now) { Get-Date } else { [datetime]$Now }
    $log = Join-Path $P.Root 'logs\suite-nightly.txt'
    if (-not (Test-Path -LiteralPath $log)) { return 'no nightly log' }
    $last = $null
    foreach ($l in [IO.File]::ReadAllLines($log)) { if ($l -match '^(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d) (\S+)\s*(.*)$') { $last = @($Matches[1], $Matches[2], $Matches[3]) } }
    if (-not $last -or $last[1] -ne 'YIELDED') { return 'last nightly did not yield' }
    $at = [datetime]::ParseExact($last[0], 's', [Globalization.CultureInfo]::InvariantCulture)
    $due = $at.Date.AddHours(7); if ($at -ge $due) { $due = $due.AddDays(1) }
    if ($nowAt -lt $due) { return "yield $($last[0]) not due before $($due.ToString('yyyy-MM-dd HH:mm'))" }
    $atUtc = [datetime]::SpecifyKind($at, [DateTimeKind]::Local).ToUniversalTime()
    $runs = Join-Path $P.Suites 'runs'
    foreach ($rf in @(if (Test-Path -LiteralPath $runs) { Get-ChildItem -LiteralPath $runs -File | Where-Object { $_.Name -match '^(run|retest)-.+-\d+\.json$' } })) {
        try { $r = Get-Content -LiteralPath $rf.FullName -Raw | ConvertFrom-Json -AsHashtable } catch { continue }
        if ($r -isnot [Collections.IDictionary] -or -not $r['startedAt']) { continue }
        $sa = $r['startedAt']
        try { $saUtc = if ($sa -is [datetime]) { $sa.ToUniversalTime() } else { [datetime]::Parse([string]$sa, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) } } catch { continue }
        if ($saUtc -gt $atUtc) { return "yield $($last[0]) followed by $($r['id'])" }
    }
    $tag = "NIGHTLY-YIELDED $($at.ToString('yyyy-MM-dd'))"
    $qText = if (Test-Path -LiteralPath $P.Questions) { [IO.File]::ReadAllText($P.Questions) } else { '' }
    if ($qText.Contains($tag)) { return "$tag already queued" }
    Add-LineTo $P.Questions "- $(Format-LocalStamp) ${tag}: the nightly Tier 2 at $(Format-LocalStamp $at 'HH:mm') yielded ($($last[2].Trim())) and no run record started since, so no Tier 2 ran that night. Start one with Start-SuiteRun.ps1 -Reason manual, or let the integrator work its yield inbox item."
    "$tag queued"
}
# Owner-facing display time (owner ruling 2026-10-18, kit item IN-20261019000559-20fa): local machine time with the
# zone's initials, e.g. '2026-10-18 19:43 EDT'. Display only: stored stamps stay Get-Now's UTC Z form.
function Format-LocalStamp($At = $null, [string] $Format = 'yyyy-MM-dd HH:mm') {
    $d = if ($null -eq $At) { Get-Date } elseif (([datetime]$At).Kind -eq [DateTimeKind]::Utc) { ([datetime]$At).ToLocalTime() } else { [datetime]$At }
    $tz = [TimeZoneInfo]::Local
    $name = if ($tz.IsDaylightSavingTime($d)) { $tz.DaylightName } else { $tz.StandardName }
    $abbr = if ($name -match '\s') { -join @($name -split '\s+' | Where-Object { $_ } | ForEach-Object { $_[0] }) } else { $name }
    '{0} {1}' -f $d.ToString($Format), $abbr
}

function New-SessionId([string] $Role) {
    '{0}-{1}-{2}' -f $Role, (Get-Date).ToString('yyyyMMddHHmm'), ([guid]::NewGuid().ToString('N').Substring(0, 4))
}

# The Move onto $Path is retried for about 5 s: a reader that holds the target open without FILE_SHARE_DELETE makes
# it throw 'Access to the path is denied' (UnauthorizedAccessException) or a sharing IOException. Runner Builder 4 lost
# its pre-stage tasks.json write to that twice on 2026-10-09 and left tasks.json.tmp.* behind, so a write that still
# fails deletes its tmp before it throws (kit item IN-20261009213052-7ec7).
function Write-AtomicText([string] $Path, [string] $Text) {
    $tmp = '{0}.tmp.{1}.{2}' -f $Path, $PID, ([guid]::NewGuid().ToString('N').Substring(0, 6))
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($Text -replace "`r`n", "`n"))
    try {
        $fs = [IO.File]::Open($tmp, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
        try { $fs.Write($bytes, 0, $bytes.Length); $fs.Flush($true) } finally { $fs.Dispose() }
        for ($i = 0; ; $i++) {
            try { [IO.File]::Move($tmp, $Path, $true); return }
            catch [IO.IOException], [UnauthorizedAccessException] { if ($i -ge 50) { throw }; Start-Sleep -Milliseconds 100 }
        }
    } catch {
        Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
        throw
    }
}

# Copies a folder that other sessions are writing, file by file. Copy-Item -Recurse threw 'Could not find file' on
# 2026-10-10 when an author's atomic-write temp (tickets\G6.T304.md.tmp.23472.aceb1561309b) vanished between the
# listing and the copy, and the G4 Tier 3 retest exited 1 before any test ran (kit item IN-20261010211022-8ba5).
# A writer's temp (<name>.tmp.<pid>.<hex>, as Write-AtomicText names it) is never copied, and a file or folder that
# disappears during the copy is skipped: the reader gets the folder as it was a moment ago. Returns the skipped paths.
function Copy-TreeTolerant([string] $Source, [string] $Destination) {
    $skipped = [Collections.Generic.List[string]]::new()
    if (-not (Test-Path -LiteralPath $Source -PathType Container)) { return , $skipped.ToArray() }
    # A sub-folder removed mid-listing can throw; list again (three tries) rather than fail the copy.
    $dirs = @(); $files = @()
    for ($i = 1; ; $i++) {
        try {
            $dirs = @([IO.Directory]::EnumerateDirectories($Source, '*', [IO.SearchOption]::AllDirectories))
            $files = @([IO.Directory]::EnumerateFiles($Source, '*', [IO.SearchOption]::AllDirectories)); break
        } catch [IO.DirectoryNotFoundException], [IO.FileNotFoundException] { if ($i -ge 3) { throw }; Start-Sleep -Milliseconds 200 }
    }
    $root = $Source.TrimEnd('\', '/')
    [void][IO.Directory]::CreateDirectory($Destination)
    foreach ($d in $dirs) { [void][IO.Directory]::CreateDirectory((Join-Path $Destination $d.Substring($root.Length).TrimStart('\', '/'))) }
    Copy-FilesTolerant $Source $Destination $files $skipped
    , $skipped.ToArray()
}

function Copy-FilesTolerant([string] $Source, [string] $Destination, [string[]] $Files, $Skipped) {
    if (-not (Test-Path -LiteralPath $Destination)) { [void][IO.Directory]::CreateDirectory($Destination) }
    $root = $Source.TrimEnd('\', '/')
    foreach ($f in $Files) {
        $rel = $f.Substring($root.Length).TrimStart('\', '/')
        if ((Split-Path $f -Leaf) -match '\.tmp\.\d+\.[0-9a-fA-F]+$') { $Skipped.Add($rel); continue }
        $to = Join-Path $Destination $rel
        try {
            [void][IO.Directory]::CreateDirectory((Split-Path $to))
            [IO.File]::Copy($f, $to, $true)
        } catch [IO.FileNotFoundException], [IO.DirectoryNotFoundException] { $Skipped.Add($rel) }
    }
}

# Appends one line, retrying a sharing violation for up to 15 s before it throws. Several sessions append to
# decisions.md and the ledgers at once, and on 2026-10-04 one such collision threw inside Integrate-Patch right after a
# clean apply of G3.T283: the self-reverse caught it, but one transient lock cost a whole apply and grader cycle (kit
# item IN-20261004140930-2c5d). The inbox append (lib\Inbox.ps1) already retries the same way.
# Runs $Do and retries an IOException (a sharing violation) the same way, for the file steps that are not one-line
# appends. Invoke-Grader.ps1 copies a child grader's .part log right after the child exits, and on 2026-10-04 that copy
# hit "being used by another process" once in Test-StreamKitRecovery's -BeatSession case (kit item
# IN-20261004143050-5968). $Do must use .NET file calls: a cmdlet error is not an IOException and is never retried.
function Invoke-IoRetry([scriptblock] $Do) {
    for ($i = 0; ; $i++) {
        try { return (& $Do) }
        catch [IO.IOException] { if ($i -ge 50) { throw }; Start-Sleep -Milliseconds 100 }
    }
}

# The wait is 15 s (STREAM_APPEND_WAIT_SECONDS), backing off from 100 ms to 500 ms: on 2026-10-10 a 5 s wait was not
# enough and the append threw after Integrate-Patch had committed G6.T208 and after Invoke-Retest had written
# retest-G4-5, so both scripts exited non-zero after doing their work (kit item IN-20261010161046-9992).
function Add-LineTo([string] $Path, [string] $Line) {
    $dir = Split-Path $Path
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir | Out-Null }
    $waitSeconds = if ("$env:STREAM_APPEND_WAIT_SECONDS" -match '^\d+$') { [int]$env:STREAM_APPEND_WAIT_SECONDS } else { 15 }
    $deadline = (Get-Date).AddSeconds($waitSeconds)
    for ($i = 0; ; $i++) {
        try { [IO.File]::AppendAllText($Path, ($Line + "`n"), [Text.UTF8Encoding]::new($false)); return }
        catch [IO.IOException] { if ((Get-Date) -gt $deadline) { throw }; Start-Sleep -Milliseconds ([Math]::Min(500, 100 * ($i + 1))) }
    }
}

# Reads a text file's lines without blocking writers. [IO.File]::ReadLines opens with FileShare.Read, so a loop over a
# shared append-only file shuts out every append for as long as the loop runs: Build-CostPage's pass over decisions.md
# took 37.6 s over its 113 MB on 2026-10-10, and appends from Integrate-Patch and Invoke-Retest threw inside that window
# (kit item IN-20261010161046-9992).
function Read-SharedLines([string] $Path) {
    $fs = [IO.FileStream]::new($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, ([IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete))
    $sr = [IO.StreamReader]::new($fs, [Text.UTF8Encoding]::new($false))
    try { while ($null -ne ($l = $sr.ReadLine())) { $l } } finally { $sr.Dispose() }
}

# The LAST status worktrees.md records for one directory, or '' when the ledger never mentions it. The ledger is
# append-only with one line per event ("- <label> | <path> | <utc> | <status>"), so the last line for a path is the
# current truth about it - which is how the watchdog knows a directory it no longer recognises as a git worktree was
# one it had already decided to delete (a failed removal drops the registration and leaves the files).
function Get-LastWorktreeLedgerStatus($Paths, [string] $Dir) {
    if (-not (Test-Path $Paths.Worktrees)) { return '' }
    $key = $Dir.Replace('/', '\').TrimEnd('\').ToLowerInvariant()
    $status = ''
    foreach ($l in @(Get-Content $Paths.Worktrees)) {
        $parts = @($l -split '\s\|\s')
        if ($parts.Count -lt 4) { continue }
        if ($parts[1].Trim().Replace('/', '\').TrimEnd('\').ToLowerInvariant() -eq $key) { $status = $parts[3].Trim() }
    }
    $status
}

# The integrator lock is refreshed only when a session calls Enter-Integrator, so a long grader run on main lets the
# watchdog break it (20 min) under a LIVE integrator: on 9/28 a 39-minute grader lost the lock and integration carried
# on holding nothing, which a second /stream-integrate could have joined. Work that runs long beats the lock, and every
# apply/commit checks the lock is still this session's first.
function Test-IntegratorLock($P, [string] $Session) {
    if (-not (Test-Path $P.IntLock)) { return $false }
    try { ((Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String).session -eq $Session) } catch { $false }
}
# Writes a fresh beat when the lock is this session's. $true = still ours.
function Update-IntegratorBeat($P, [string] $Session) {
    if (-not (Test-IntegratorLock $P $Session)) { return $false }
    try {
        $l = Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String
        $l.beat = (Get-Now); Write-AtomicText $P.IntLock ($l | ConvertTo-Json); $true
    } catch { $false }
}
# ours | retaken (the lock was gone - the watchdog broke it under us - so this session takes it again) | lost.
function Assert-IntegratorLock($P, [string] $Session) {
    if (Test-IntegratorLock $P $Session) { return 'ours' }
    if (Test-Path $P.IntLock) { return 'lost' }
    $now = Get-Now
    Write-AtomicText $P.IntLock (@{ session = $Session; at = $now; beat = $now } | ConvertTo-Json)
    'retaken'
}
# A claim has the same problem as the integrator lock: nothing refreshes it while a grader or a verifier runs, so the
# watchdog breaks a LIVE builder at 45 minutes (kit item IN-20260929034738-6371). Beats the claim when it is this
# session's; $true = still ours.
function Update-ClaimBeat($P, [string] $Session, [string] $TaskId) {
    $script:ClaimBeatOurs = $false
    [void](Invoke-TasksLocked $P $Session {
        param($doc)
        $t = @($doc.tasks | Where-Object { $_.id -eq $TaskId })
        if ($t.Count -ne 1 -or -not $t[0].claim -or $t[0].claim.session -ne $Session) { return $null }
        $t[0].claim.beat = (Get-Now); $script:ClaimBeatOurs = $true; $doc
    })
    $script:ClaimBeatOurs
}

function Get-IntegratorLockHolder($P) {
    try { (Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String).session } catch { '?' }
}

function Add-Decision($P, [string] $By, [string] $Text) {
    Add-LineTo $P.Decisions ('- {0} [{1}] {2}' -f (Get-Now), $By, $Text)
}

function Read-Tasks($P) {
    if (-not (Test-Path $P.Tasks)) { throw "no tasks.json at $($P.Tasks); run Init-Streams.ps1 first" }
    Get-Content -Raw $P.Tasks | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
}

# Runs $Action against the parsed document under the lock and writes back whatever it returns.
# $Action gets ($doc) and must return $doc (possibly changed). Return $null to write nothing.
# The wait for the lock is 15 seconds, or STREAM_TASKS_LOCK_WAIT_SECONDS: Integrate-Patch raises it for its own run,
# because a throw there lands between a write to main and the row's state (kit item IN-20261003193026-6efe).
function Invoke-TasksLocked($P, [string] $Session, [scriptblock] $Action) {
    $waitSeconds = if ("$env:STREAM_TASKS_LOCK_WAIT_SECONDS" -match '^\d+$') { [int]$env:STREAM_TASKS_LOCK_WAIT_SECONDS } else { 15 }
    $deadline = (Get-Date).AddSeconds($waitSeconds)
    $fs = $null
    while (-not $fs) {
        try {
            $fs = [IO.File]::Open($P.Lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
            $b = [Text.Encoding]::UTF8.GetBytes((@{ session = $Session; at = (Get-Now) } | ConvertTo-Json -Compress))
            $fs.Write($b, 0, $b.Length); $fs.Flush($true)
        } catch [IO.IOException], [UnauthorizedAccessException] {
            # Access denied is the lock too: the last holder's Remove-Item leaves the file delete-pending for a moment,
            # and CreateNew on a delete-pending file fails with UnauthorizedAccessException, not IOException. Ten runners
            # starting at once on 2026-10-08 hit it, and the throw failed a builder's pre-stage into a 900 s backoff.
            $fs = $null
            $age = try { ((Get-Date) - (Get-Item $P.Lock).LastWriteTime).TotalSeconds } catch { 0 }
            if ($age -gt $script:StaleLockSeconds) {
                # An old lock file is stale only when it can be deleted. A live holder keeps it open without delete
                # sharing, so Remove-Item fails and the file stays: that holder is slow, not dead, and the caller waits
                # for it like any other holder. The old code logged a break and looped with no sleep whether or not the
                # delete worked, so every waiter spun: 762,555 "broke stale" lines (113 MB of decisions.md, 397,751 for
                # one 10-minute hold) starved decisions.md appends and the holder itself (kit item IN-20261010161046-9992).
                $holder = try { Get-Content -Raw $P.Lock } catch { '?' }
                Remove-Item $P.Lock -Force -ErrorAction SilentlyContinue
                if (-not (Test-Path $P.Lock)) {
                    Add-Decision $P $Session "broke stale tasks.json lock ($([int]$age)s old): $holder"
                    continue
                }
            }
            if ((Get-Date) -gt $deadline) { throw "tasks.json lock busy for ${waitSeconds}s: $(Get-Content -Raw $P.Lock -ErrorAction SilentlyContinue)" }
            Start-Sleep -Milliseconds 100
        }
    }
    try {
        $doc = Read-Tasks $P
        $out = & $Action $doc
        if ($null -ne $out) { Write-AtomicText $P.Tasks ($out | ConvertTo-Json -Depth 50) }
        $out
    } finally {
        $fs.Dispose()
        Remove-Item $P.Lock -Force -ErrorAction SilentlyContinue
    }
}

function Get-Task($doc, [string] $Id) {
    $t = @($doc.tasks | Where-Object { $_.id -eq $Id })
    if ($t.Count -ne 1) { throw "task $Id not found (matches: $($t.Count))" }
    $t[0]
}

function Add-History($Task, [string] $By, [string] $To, [string] $Note) {
    $h = [ordered]@{ at = (Get-Now); by = $By; to = $To; note = $Note }
    $Task.history = @($Task.history) + @($h)
}

# The only code that changes a task's state. Refuses moves the table does not name.
function Set-TaskState($Task, [string] $To, [string] $Role, [string] $By, [string] $Note) {
    $from = $Task.state
    $allowed = @()
    foreach ($k in $script:Transitions.Keys) {
        if (($k -split '#')[0] -eq "$from>$To") { $allowed += $script:Transitions[$k] }
    }
    if ($Role -notin $allowed) { throw "TRANSITION-REFUSED $($Task.id): $from -> $To by role '$Role'" }
    $Task.state = $To
    Add-History $Task $By $To $Note
}

# Who holds the integrator's place, read once per pass: live (fresh integrator.lock), stale (lock past its limit, broken
# by the watchdog in this pass) and the session and age of the last break (integrator.lock.broken). An INTEGRATION row
# the integrator set building carries no claim; this is its liveness (kit items IN-20261002014307-9bf2,
# IN-20261002043357-316b). The watchdog and Get-StreamStatus.ps1 both read it, so a row the watchdog keeps is never
# flagged orphaned on the page (kit item IN-20261005020647-63c2).
function Get-IntegratorHold($P) {
    $hold = @{ live = ''; stale = ''; beatAge = $null; brokenBy = ''; brokenAge = [double]::MaxValue
        brokenMark = (Join-Path (Split-Path $P.IntLock) 'integrator.lock.broken') }
    $utc = { param($s) [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }
    if (Test-Path $P.IntLock) {
        try {
            $il = Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String
            $hold.beatAge = ((Get-Date).ToUniversalTime() - (& $utc $il.beat)).TotalMinutes
            if ($hold.beatAge -lt $script:IntegratorLockMinutes) { $hold.live = [string] $il.session } else { $hold.stale = [string] $il.session }
        } catch { }
    }
    if (Test-Path $hold.brokenMark) {
        try {
            $bm = Get-Content -Raw $hold.brokenMark | ConvertFrom-Json -AsHashtable -DateKind String
            $hold.brokenBy = [string] $bm.session
            $hold.brokenAge = ((Get-Date).ToUniversalTime() - (& $utc $bm.at)).TotalMinutes
        } catch { }
    }
    $hold
}

# True when an unclaimed INTEGRATION row in `building` still belongs to its integrator: its setter ($Since.by, from
# Get-StateEntry) holds a fresh lock, or a stale one (broken this pass), or broke within the build claim limit.
function Test-IntegratorKeepsRow($Hold, $Task, $Since) {
    if ($Task.kind -ne 'integration' -or -not $Since) { return $false }
    if ($Hold.live) { return ($Since.by -eq $Hold.live) }
    if ($Hold.stale) { return ($Since.by -eq $Hold.stale) }
    [bool]($Hold.brokenBy -and $Since.by -eq $Hold.brokenBy -and $Hold.brokenAge -lt $script:ClaimLimitMinutes.build)
}

# The history entry that BEGAN the task's current run in $State, not the most recent entry stamped with it. Every
# note written while a task sits in a state repeats that state, so the last match is usually a plan revise from
# minutes ago and would make a task stuck for days look young, and credit the wrong session for putting it there.
function Get-StateEntry($Task, [string] $State) {
    $h = @($Task.history)
    $entry = $null
    for ($i = $h.Count - 1; $i -ge 0; $i--) {
        if ($h[$i].to -ne $State) { break }
        $entry = $h[$i]
    }
    $entry
}

function Test-ClaimLive($Task) {
    if (-not $Task.claim) { return $false }
    $limit = $script:ClaimLimitMinutes[$Task.claim.role]
    if (-not $limit) { $limit = 30 }
    $beat = [datetime]::Parse($Task.claim.beat, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
    ((Get-Date).ToUniversalTime() - $beat).TotalMinutes -lt $limit
}

# The last moment the CLAIM HOLDER moved the row: the newest of its artifact files' write times and the newest history
# line the holder itself wrote, falling back to the moment of the claim. Used with $script:NoProgressMinutes; returns
# @{ at = <utc datetime>; what = '<what was newest>' }. Only the holder's own history counts, because a coordinator or
# an owner writing into the row says nothing about whether the holder is working.
function Get-ClaimProgressAt($Task, $Paths) {
    $best = $null; $what = ''
    if ($Task.claim -and $Task.claim.at) {
        $best = [datetime]::Parse($Task.claim.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
        $what = 'the claim itself'
    }
    $session = if ($Task.claim) { $Task.claim.session } else { '' }
    foreach ($h in @($Task.history)) {
        if (-not $h.at -or $h.by -ne $session) { continue }
        $at = [datetime]::Parse($h.at, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
        if (-not $best -or $at -gt $best) { $best = $at; $what = 'its own history line' }
    }
    if ($Task.artifacts) {
        foreach ($k in @('ticket', 'grader', 'patch', 'verdict')) {
            $v = $Task.artifacts[$k]
            if (-not $v -or -not $Paths) { continue }
            $f = if ([IO.Path]::IsPathRooted($v)) { $v } else { Join-Path $Paths.Repo $v }
            if (-not (Test-Path -LiteralPath $f)) { continue }
            $at = (Get-Item -LiteralPath $f).LastWriteTimeUtc
            if (-not $best -or $at -gt $best) { $best = $at; $what = "artifacts.$k" }
        }
    }
    if (-not $best) { return $null }
    @{ at = $best; what = $what }
}

# Longest remaining estimate chain from each task; the critical path is the tasks on the longest chain.
function Get-ChainMinutes($doc) {
    $memo = @{}
    $byId = @{}; foreach ($t in $doc.tasks) { $byId[$t.id] = $t }
    $dependents = @{}
    foreach ($t in $doc.tasks) { foreach ($d in @($t.dependsOn)) { if ($d) { if (-not $dependents[$d]) { $dependents[$d] = @() }; $dependents[$d] += $t.id } } }
    $calc = $null
    $calc = {
        param($id, $seen)
        if ($memo.ContainsKey($id)) { return $memo[$id] }
        if ($seen -contains $id) { throw "DEPENDENCY CYCLE at $id" }
        $t = $byId[$id]
        $own = if ($t.state -in @('done', 'integrated')) { 0 } else { [int]$t.estMinutes }
        $best = 0
        foreach ($n in @($dependents[$id])) { if ($n) { $v = & $calc $n (@($seen) + $id); if ($v -gt $best) { $best = $v } } }
        $memo[$id] = $own + $best
        $memo[$id]
    }
    foreach ($t in $doc.tasks) { [void](& $calc $t.id @()) }
    $memo
}

# EFFECTIVE GROUP RANK, the author sort's group key. A row's rank is the MINIMUM board-order group rank over the row
# itself and every row that depends on it, transitively, so a row in a later group that blocks earlier-group work is
# ticketed with that earlier group. Group-first order alone ticketed it with its own group: on 2026-10-02 G3.T210 was
# ticketed on 10-01 but waited on G5.T061, still planned, and G5.T004 (ticketed 09-29) waited on G4.T077, first
# touched by an author on 10-02 - 17 ticketed rows, 0 claimable for over 2 h (owner ruling, kit item
# IN-20261002153754-be85). A dependent that has already landed (integrated or done) waits on nothing and lends no rank.
# Returns id -> @{ rank = <int>; own = <int>; via = <dependent id whose group set the rank, or ''> }.
# -RankMap (group id -> rank) replaces board order as the group rank; the claim sort passes Get-PriorityRankMap so the
# owner's focus.groups order decides. Without it the rank is the board index, which Get-FocusSet and Activation read.
function Get-EffectiveGroupRank($doc, $RankMap = $null) {
    $grank = @{}; $gi = 0
    if ($RankMap) { $grank = $RankMap } else { foreach ($g in $doc.groups) { $grank[$g.id] = $gi++ } }
    $byId = @{}; foreach ($t in $doc.tasks) { $byId[$t.id] = $t }
    $dependents = @{}
    foreach ($t in $doc.tasks) {
        if ($t.state -in @('integrated', 'done')) { continue }
        foreach ($d in @($t.dependsOn)) { if ($d) { if (-not $dependents[$d]) { $dependents[$d] = [Collections.Generic.List[string]]::new() }; $dependents[$d].Add($t.id) } }
    }
    $memo = @{}
    $calc = $null
    $calc = {
        param($id, $seen)
        if ($memo.ContainsKey($id)) { return $memo[$id] }
        $t = $byId[$id]
        $own = if ($t -and $grank.ContainsKey($t.group)) { $grank[$t.group] } else { [int]::MaxValue }
        $r = @{ rank = $own; own = $own; via = '' }
        if ($seen -notcontains $id) {
            foreach ($n in @($dependents[$id])) {
                if (-not $n) { continue }
                $v = & $calc $n (@($seen) + $id)
                if ($v.rank -lt $r.rank) { $r = @{ rank = $v.rank; own = $own; via = $(if ($v.via) { $v.via } else { $n }) } }
            }
        }
        $memo[$id] = $r
        $r
    }
    foreach ($t in $doc.tasks) { [void](& $calc $t.id @()) }
    $memo
}

# The mirror of Get-ChainMinutes: the longest chain of REMAINING work that has to land BEFORE each task can finish,
# the task itself included. Get-ChainMinutes looks DOWNSTREAM, so a group's maximum over it answers "how long until
# everything that depends on this group is done"; it is inflated by other groups' work and cannot date the group. On
# 2026-09-29 that made all six groups read the same 4295 min while G1 had 1065 min of work left. This one looks
# UPSTREAM, so a group's maximum is the earliest that group can possibly finish however many sessions run, its
# dependencies in other groups included. Work already integrated or done costs 0 in both. A dependsOn naming a task
# that is not on the board costs 0 rather than throwing: a dangling edge must not take the whole page down.
function Get-UpChainMinutes($doc) {
    $memo = @{}
    $byId = @{}; foreach ($t in $doc.tasks) { $byId[$t.id] = $t }
    $calc = $null
    $calc = {
        param($id, $seen)
        if ($memo.ContainsKey($id)) { return $memo[$id] }
        if ($seen -contains $id) { throw "DEPENDENCY CYCLE at $id" }
        $t = $byId[$id]
        if (-not $t) { return 0 }
        $own = if ($t.state -in @('done', 'integrated')) { 0 } else { [int]$t.estMinutes }
        $best = 0
        foreach ($d in @($t.dependsOn)) { if ($d) { $v = & $calc $d (@($seen) + $id); if ($v -gt $best) { $best = $v } } }
        $memo[$id] = $own + $best
        $memo[$id]
    }
    foreach ($t in $doc.tasks) { [void](& $calc $t.id @()) }
    $memo
}

function Test-DepsAt($doc, $Task, [string[]] $States) {
    foreach ($d in @($Task.dependsOn)) {
        if (-not $d) { continue }
        if ((Get-Task $doc $d).state -notin $States) { return $false }
    }
    $true
}

# The row itself is ready for a build claim: ticketed, a kind a builder claims, and every dependency built or later.
# The other build-claim gates - released group, no live claim, no live inbox hold - are about the board around the row
# and are checked by the caller. Claim-Task.ps1 and Get-StreamStatus.ps1 both read this one rule, so the board's
# claimable count is exactly the rows a build claim would offer.
$script:BuildKinds = @('code', 'docs', 'mockup')
$script:BuildReadyStates = @('built', 'integrated', 'done')
# A BUILT dependency counts only while its own base is whole: every dependency of it is integrated or done, or is
# itself built on a whole base. A built row's patch was cut on top of its own built dependencies' patches, and
# New-TaskWorktree.ps1 stacks only the dependencies that are still built. On 2026-10-17 G9.T010 was bounced
# grader-suspect and went back to building, so G9.T026's base stacked G9.T011.patch without G9.T010's, and every
# pre-stage failed "patch does not apply" at MutationRunOrchestrator.cs:84 (kit item IN-20261017100037-aa62).
function Test-DepsBaseReady($doc, $Task, $Seen = @()) {
    foreach ($d in @($Task.dependsOn)) {
        if (-not $d -or $Seen -contains $d) { continue }
        $dt = Get-Task $doc $d
        if ($dt.state -in @('integrated', 'done')) { continue }
        if ($dt.state -ne 'built') { return $false }
        if (-not (Test-DepsBaseReady $doc $dt (@($Seen) + $d))) { return $false }
    }
    $true
}
function Test-BuildReady($doc, $Task) {
    $Task.state -eq 'ticketed' -and $Task.kind -in $script:BuildKinds -and (Test-DepsBaseReady $doc $Task)
}

# ---- dependency base drift (2026-10-18 dependency review, finding F1) ----
# New-TaskWorktree.ps1 records base.deps as '<patch leaf>:<16-hex sha256>' for every built dependency patch it stacked,
# and until this check nothing ever READ it. A dependency that bounced after the dependent was built (REBASE, REVERSED;
# 6 of 25 in-flight bounces on the live board by 10/18) lands a DIFFERENT patch, the dependent's own patch usually still
# applies, and its verifier graded against code that never landed. Returns one entry per stacked dependency whose
# current patch is not the one the base was laid on: @{ dep; leaf; recorded; now } (now = 'gone' when the file is
# missing). Empty when the row has no base.deps, or every hash matches. A SUSPECT bounce keeps the patch unchanged, so
# it does not drift here.
function Get-FileHash16([string] $Path) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash([IO.File]::ReadAllBytes($Path))).Replace('-', '').Substring(0, 16) } finally { $sha.Dispose() }
}
function Get-DependencyBaseDrift($P, $doc, $Task) {
    $out = [Collections.Generic.List[object]]::new()
    $base = if ($Task -is [Collections.IDictionary] -and $Task.Contains('base')) { $Task['base'] } else { $null }
    if ($base -isnot [Collections.IDictionary] -or -not $base.Contains('deps')) { return , $out }
    $leafToId = @{}
    foreach ($t in $doc.tasks) {
        $a = if ($t -is [Collections.IDictionary] -and $t.Contains('artifacts')) { $t['artifacts'] } else { $null }
        $pp = if ($a -is [Collections.IDictionary] -and $a.Contains('patch') -and $a['patch']) { [string]$a['patch'] } else { '' }
        if ($pp) { $leafToId[(Split-Path -Leaf $pp)] = [string]$t.id }
    }
    foreach ($e in @($base['deps'])) {
        $s = [string]$e; $i = $s.LastIndexOf(':')
        if ($i -lt 1) { continue }
        $leaf = $s.Substring(0, $i); $recorded = $s.Substring($i + 1)
        $dep = if ($leafToId.ContainsKey($leaf)) { $leafToId[$leaf] } else { $leaf -replace '\.patch$', '' }
        $f = Join-Path $P.Patches $leaf
        $now = if (Test-Path -LiteralPath $f) { Get-FileHash16 $f } else { 'gone' }
        if ($now -ne $recorded) { $out.Add([ordered]@{ dep = $dep; leaf = $leaf; recorded = $recorded; now = $now }) }
    }
    , $out
}

# ---- dependsWhy (2026-10-18 dependency review, finding F3) ----
# dependsOn says THAT a row waits; nothing said WHY. On the live board 1,550 of 5,740 edges shared no write-set file, and
# nobody could tell a real "B uses A's new type" edge from a cautious one. dependsWhy is a sibling map id -> reason.
# Add-Tasks.ps1 and Revise-Task.ps1 fill the mechanical reasons; the planner writes the rest; an edge with no stated
# reason reads 'unstated', which is what the DEP-REVIEW board flag looks for. A stated reason outlives its edge
# (Revise-Task.ps1 removeDependsOn keeps it, so a file-order flip that drops and re-adds the edge keeps the why).
#   shared file   the two write sets overlap, so the edge orders edits to one file (Board.ps1 UNORDERED rule)
#   group order   the dependency is a group's integration task or a gate, or the row is an integration task
#   mockup first  the dependency is a mockup row (its code row follows it by rule)
#   unstated      none of the above and the planner gave no reason
$script:DependsWhyUnstated = 'unstated'
# DEP-REVIEW board flag thresholds: an unstated edge whose target has held at least MinWaiters ticketed rows for at
# least MinDays is a planner question (state the reason or drop the edge). Env overrides exist for the self-tests.
$script:DepReviewMinWaiters = if ("$env:STREAM_DEP_REVIEW_MIN_WAITERS" -match '^\d+$') { [int]$env:STREAM_DEP_REVIEW_MIN_WAITERS } else { 2 }
$script:DepReviewMinDays = if ("$env:STREAM_DEP_REVIEW_MIN_DAYS" -match '^\d+(\.\d+)?$') { [double]$env:STREAM_DEP_REVIEW_MIN_DAYS } else { 2 }
$script:DependsWhyMechanical = @('shared file', 'group order', 'mockup first')
function Set-DependsWhyDefaults($Tasks, $Row, [hashtable] $ById = $null) {
    <# Normalizes a row's dependsWhy map to PLANNER TEXT ONLY: the mechanical classes and 'unstated' are derived by
       Get-DependsWhy, never stored, so "an entry exists" means "the planner stated it" for every reader (Get-StreamStatus
       DEP-REVIEW, Find-ArtificialBlockers, Find-TestBlockers). A stated reason outlives its edge (Revise-Task.ps1
       removeDependsOn keeps it), so a file-order flip that drops an edge and puts it back keeps the why. #>
    $why = if ($Row -is [Collections.IDictionary] -and $Row.Contains('dependsWhy') -and $Row['dependsWhy'] -is [Collections.IDictionary]) { $Row['dependsWhy'] } else { [ordered]@{} }
    $kept = [ordered]@{}
    foreach ($k in @($why.Keys)) {
        $v = "$($why[$k])".Trim()
        if ($v -and $v -ne $script:DependsWhyUnstated -and $v -notin $script:DependsWhyMechanical) { $kept[[string]$k] = $v }
    }
    if ($Row -is [Collections.IDictionary]) { $Row['dependsWhy'] = $kept } else { $Row | Add-Member -NotePropertyName dependsWhy -NotePropertyValue $kept -Force }
    $kept
}
function Get-DependsWhy($Row, [string] $Dep, $Tasks = $null) {
    <# The reason an edge exists: the planner's stated text; else the mechanical class when $Tasks (a list or a
       Get-TaskIndex map) is given - 'group order' (a gate or integration row on either end), 'mockup first', 'shared file'
       (the write sets overlap); else 'unstated'. #>
    $why = if ($Row -is [Collections.IDictionary]) { if ($Row.Contains('dependsWhy')) { $Row['dependsWhy'] } } elseif ($Row.PSObject.Properties['dependsWhy']) { $Row.dependsWhy }
    if ($why -is [Collections.IDictionary]) { if ($why.Contains($Dep) -and "$($why[$Dep])".Trim()) { return "$($why[$Dep])".Trim() } }
    elseif ($why -and $why.PSObject.Properties[$Dep] -and "$($why.PSObject.Properties[$Dep].Value)".Trim()) { return "$($why.PSObject.Properties[$Dep].Value)".Trim() }
    if ($null -eq $Tasks) { return $script:DependsWhyUnstated }
    $byId = if ($Tasks -is [Collections.IDictionary]) { $Tasks } else { Get-TaskIndex $Tasks }
    $dt = $byId[$Dep]
    if (-not $dt) { return $script:DependsWhyUnstated }
    $rowKind = [string]$(if ($Row -is [Collections.IDictionary]) { $Row['kind'] } else { $Row.kind })
    $rowWs = $(if ($Row -is [Collections.IDictionary]) { $Row['writeSet'] } else { $Row.writeSet })
    $depKind = [string]$(if ($dt -is [Collections.IDictionary]) { $dt['kind'] } else { $dt.kind })
    $depWs = $(if ($dt -is [Collections.IDictionary]) { $dt['writeSet'] } else { $dt.writeSet })
    if ($rowKind -eq 'integration' -or $depKind -in @('integration', 'gate')) { return 'group order' }
    if ($depKind -eq 'mockup') { return 'mockup first' }
    if (Test-WriteSetOverlap $rowWs $depWs) { return 'shared file' }
    $script:DependsWhyUnstated
}

# ---- dependency bounce cascade (2026-10-18 dependency review, finding F6) ----
# When a BUILT row leaves built for anything but landed, every row still BUILDING whose base stacked it is told so with
# one history line, so the builder (which beats the row and the status page both read it) knows its base holds a patch
# that may change. Call inside Invoke-TasksLocked after the state move. Returns the dependents noted.
function Add-DependentBounceNotes($doc, $Task, [string] $By, [string] $From, [string] $To, [string] $Note = '') {
    $out = [Collections.Generic.List[string]]::new()
    if ($From -ne 'built' -or $To -in @('integrated', 'done')) { return , $out }
    $id = [string]$Task.id
    $byId = Get-TaskIndex $doc.tasks
    foreach ($o in $doc.tasks) {
        if ([string]$o.state -ne 'building' -or [string]$o.id -eq $id) { continue }
        if (-not (Test-DependsOnChain $doc.tasks $o $id $byId)) { continue }
        Add-History $o $By 'building' "DEP-MOVED $id built -> ${To}: a dependency this base stacked left built$(if ($Note) { " ($Note)" }); the base may hold a patch that will change, so expect BASE-STALE at integration unless $id lands unchanged"
        $out.Add([string]$o.id)
    }
    , $out
}

# Session liveness, shared by Get-StreamStatus.ps1 (the board and its claimable buffer) and any script that counts
# live builders, so they never disagree about how many builders are live. A session is live when it wrote history, beat a claim, beat
# the integrator lock or left an idle beat inside its role's limit (the limits the watchdog breaks claims on). A role
# named outright (claim role, integrator lock, idle beat) wins over the session-id prefix, because some sessions carry
# no role prefix at all (the integrator ran as a bare '4599ecab' on 2026-10-01).
$script:SessionLimitMinutes = @{ author = 30; build = 45; integrate = 20 }
$script:SessionRoleAlias = @{ integ = 'integrate'; int = 'integrate'; integrator = 'integrate'; builder = 'build'; planner = 'plan'; coord = 'coordinator' }
function Get-SessionActivity($P, $doc, $IdleBeats = $null) {
    $last = @{}; $role = @{}; $named = @{}; $claim = @{}
    $note = {
        param([string] $session, [string] $at, [string] $r)
        if (-not $session -or -not $at) { return }
        if ($r) { $named[$session] = $r }
        elseif (-not $role[$session]) { $x = ($session -split '-')[0]; if ($script:SessionRoleAlias.ContainsKey($x)) { $x = $script:SessionRoleAlias[$x] }; $role[$session] = $x }
        if (-not $last[$session] -or $last[$session] -lt $at) { $last[$session] = $at }
    }
    foreach ($t in $doc.tasks) {
        foreach ($h in @($t.history)) { & $note $h.by $h.at '' }
        $c = $t['claim']; if ($c -is [Collections.IDictionary]) {
            & $note $c['session'] $c['beat'] $c['role']
            if (Test-ClaimLive $t) { $claim[[string]$c['session']] = [string]$t.id }
        }
    }
    if (Test-Path $P.IntLock) { try { $l = Get-Content -Raw $P.IntLock | ConvertFrom-Json -AsHashtable -DateKind String; & $note $l['session'] $l['beat'] 'integrate' } catch { } }
    if ($null -eq $IdleBeats) { $IdleBeats = @(Get-IdleBeats $P) }
    foreach ($b in @($IdleBeats)) { & $note $b['session'] $b['at'] $b['role'] }
    foreach ($k in @($named.Keys)) { $role[$k] = $named[$k] }
    $units = Get-RunnerUnits $P
    @{ last = $last; role = $role; claim = $claim; units = $units; ended = (Get-EndedRunnerSessions $P $units); prestage = (Get-PreStageOnlySessions $P) }
}
# Fresh-context runner units (Start-StreamRunner.ps1) end when their one unit of work ends, but the history, beats and
# idle beats they left keep them inside the role limit for up to 45 minutes, so each finished unit counted as an idle
# session: on 2026-10-04 the board read author 12 live and build 7 live while 3 author and 5 build runners ran (kit item
# IN-20261004184753-9f49). A runner unit is named by its <stamp>-<session>.rules.txt under .streams\logs\runner\<runner>\.
# It stays live only while a runner state file (.streams\runners\<runner>.json) whose runner pid is alive names it as
# its current session and is not stopped: a gated runner keeps its last unit's id while it sleeps, and a timed runner
# keeps one id for every unit, so each live runner counts as exactly one session. Every other runner unit is ENDED.
# Sessions not started by a runner (/loop sessions) have no rules file and keep the activity rule.
function Get-EndedRunnerSessions($P, $Units = $null) {
    $ended = [Collections.Generic.HashSet[string]]::new()
    $logRoot = Join-Path $P.Root 'logs\runner'
    if (-not (Test-Path $logRoot)) { return , $ended }
    if ($null -eq $Units) { $Units = Get-RunnerUnits $P }
    foreach ($r in @(Get-ChildItem $logRoot -Recurse -Filter '*.rules.txt' -File -ErrorAction SilentlyContinue)) {
        if ($r.Name -notmatch '^[0-9TZ]+-(.+)\.rules\.txt$') { continue }
        if (-not $Units.ContainsKey($Matches[1])) { [void]$ended.Add($Matches[1]) }
    }
    , $ended
}

# True when a process is a pwsh: its name is pwsh, or its image path ends in pwsh.exe. The name alone is not enough: a
# PowerShell update replaces pwsh.exe under running processes, which then report the renamed image as their name
# ('2ae27b44.rbf') while Path still reads ...\pwsh.exe. On 2026-10-23 every runner started the evening before read dead,
# so the watchdog broke the claims of live units at every tick and moved the live runners' state files away (kit item
# IN-20261023121821-8738).
function Test-PwshProcess($Process) {
    if ([string]$Process.ProcessName -eq 'pwsh') { return $true }
    $path = ''
    try { $path = [string]$Process.Path } catch { }
    return [bool]($path -and [IO.Path]::GetFileName($path) -eq 'pwsh.exe')
}

# True while the runner process a state file names still runs. A pid alone is not enough: a runner killed with its
# console runs no finally block, so its state file stays behind naming a pid Windows hands out again, and any process
# that later gets that pid made the dead runner read live, kept its last unit off the ended list and its claims held
# (60 such files on SMVMTR1 on 2026-10-05). So the process must be pwsh and must have started no later than the state's
# 'started' (2 min of slack for clock skew). A state with no 'started' is judged on the pid alone, and a process whose
# start time cannot be read counts as the runner, so a claim is never freed on a guess.
function Test-RunnerProcess($State) {
    $id = 0
    if (-not [int]::TryParse([string]$State['pid'], [ref]$id) -or $id -le 0) { return $false }
    $p = Get-Process -Id $id -ErrorAction SilentlyContinue
    if (-not $p -or -not (Test-PwshProcess $p)) { return $false }
    $started = [string]$State['started']
    if (-not $started) { return $true }
    try {
        $at = [datetime]::Parse($started, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
        return $p.StartTime.ToUniversalTime() -le $at.AddMinutes(2)
    } catch { return $true }
}

# Moves the state file of every runner whose process has gone (Test-RunnerProcess) out of .streams\runners into that
# runner's own log folder, .streams\logs\runner\<runner>\state.json, so runners\ holds only runners that still run and
# the record of a dead one sits next to its unit logs. Invoke-Watchdog.ps1 calls it after it has freed the claims of
# ended runner units. Returns one line per file moved.
function Move-DeadRunnerStates($P) {
    $moved = [Collections.Generic.List[string]]::new()
    foreach ($f in @(Get-ChildItem (Join-Path $P.Root 'runners') -Filter 'runner-*.json' -File -ErrorAction SilentlyContinue)) {
        try { $s = Get-Content -Raw $f.FullName | ConvertFrom-Json -AsHashtable -DateKind String } catch { continue }
        if ($s -isnot [Collections.IDictionary] -or (Test-RunnerProcess $s)) { continue }
        $dir = Join-Path $P.Root "logs\runner\$($f.BaseName)"
        try {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Move-Item -LiteralPath $f.FullName -Destination (Join-Path $dir 'state.json') -Force -ErrorAction Stop
            $moved.Add("$($f.BaseName) (pid $($s['pid']) gone, last status: $($s['status']))")
        } catch { }
    }
    , $moved
}

# The CURRENT unit of every live runner: session -> @{ role; running }. A runner is live when its state file is not
# stopped and its pid is alive. running = the state reads 'running <that session>' (a unit is in flight); otherwise the
# runner is between units, idle or in backoff, and keeps its last unit's id. A unit that has just released its claim is
# still running until it exits, and a runner that sleeps writes nothing to the board, so the board's working, idle and
# quiet split reads these states rather than claims and write ages alone: on 2026-10-04 it read '1 author idle' while
# all three author runners were running units (kit item IN-20261004202801-5449).
# A live gated runner that has not run a unit yet (idle, or in backoff after a failed pre-stage) has no session in its
# state, so it is keyed by its runner id: on 2026-10-08 the board left two such builders out and counted three ghost
# sessions in their place (see Start-StreamRunner.ps1, the lost-race idle beat).
function Get-RunnerUnits($P) {
    $units = @{}
    foreach ($f in @(Get-ChildItem (Join-Path $P.Root 'runners') -Filter '*.json' -File -ErrorAction SilentlyContinue)) {
        try { $s = Get-Content -Raw $f.FullName | ConvertFrom-Json -AsHashtable -DateKind String } catch { continue }
        if ($s -isnot [Collections.IDictionary] -or -not $s['pid']) { continue }
        $status = [string]$s['status']
        if ($status -like 'stopped*') { continue }
        if (-not (Test-RunnerProcess $s)) { continue }
        $sess = if ($s['session']) { [string]$s['session'] } elseif ($s['runner']) { [string]$s['runner'] } else { $f.BaseName }
        $r = [string]$s['role']; if ($script:SessionRoleAlias.ContainsKey($r)) { $r = $script:SessionRoleAlias[$r] }
        # A unit stopped on an unanswered permission prompt (Start-StreamRunner.ps1 sets 'waiting on owner since <utc>:
        # ...') still holds its claim and its runner keeps the claim beat fresh, so it read as working: on 2026-10-21
        # three builders sat 7-8 h on destructive-path-guard prompts under 'build 3 working' (kit item
        # IN-20261021114057-5e66). ownerWait carries the since time and the prompt, tab the runner's tab name.
        $u = @{ role = $r; running = ($status -eq "running $sess"); tab = [string]$s['tab'] }
        if ($status -match '^waiting on owner since (\S+?):?\s+(.*)$') { $u.ownerWait = $Matches[1]; $u.ownerWhat = $Matches[2] }
        $units[$sess] = $u
    }
    $units
}
# The current unit of a live runner of this role is live whatever its write age: a gated runner sleeps for up to its
# interval with nothing to take and writes nothing to the board meanwhile.
function Get-LiveSessionIds($Activity, [string] $Role, [datetime] $Now) {
    $limit = $script:SessionLimitMinutes[$Role]
    $ids = @($Activity.last.Keys | Where-Object {
        $Activity.role[$_] -eq $Role -and -not ($Activity.ended -and $Activity.ended.Contains($_)) -and
        -not ($Activity['prestage'] -and $Activity['prestage'].Contains($_)) -and
        [int]($Now - [datetime]::Parse($Activity.last[$_], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes -le $limit
    })
    if ($Activity.units) { $ids += @($Activity.units.Keys | Where-Object { $Activity.units[$_].role -eq $Role }) }
    @($ids | Sort-Object -Unique)
}

# Frees a claim whose holder is gone, inside an Invoke-TasksLocked action. A build claim on a building row sends the
# row back to ticketed and records its worktree as abandoned, so the reaper exports and attaches the patch before it
# removes the tree; any other claim is cleared with a history line. Invoke-Watchdog.ps1 (stale beats, ended runner
# units) and Start-StreamRunner.ps1 (its own unit, after every exit) share it, so a claim is freed one way.
function Clear-DeadClaim($P, $Task, [string] $By, [string] $Why, [string] $Label = 'stale claim') {
    $c = $Task.claim
    $Task.claim = $null
    if ($c.role -eq 'build' -and $Task.state -eq 'building') {
        Set-TaskState $Task 'ticketed' 'status' $By $Why
        if ($Task.ContainsKey('base') -and $Task.base -and $Task.base.worktree) { Add-LineTo $P.Worktrees ("- {0} | {1} | {2} | abandoned ({3})" -f $Task.id, $Task.base.worktree, (Get-Now), $Label) }
    } else { Add-History $Task $By $Task.state $Why }
}

# Releases every claim held by one runner unit's session, under the tasks lock. Start-StreamRunner.ps1 calls it after
# each unit exits, whatever the outcome, because a unit that is killed, times out or exits without unit_done never
# releases its own claim, and the row then sat unclaimable for the role's whole limit (30 min author, 45 min build):
# six rows on 2026-10-04 when the owner closed a runner batch at about 19:54Z (kit item IN-20261004202424-27bf).
# Returns the ids it freed (nothing when none). The action reads $unitSession, $unitBy and $unitWhy, never $Session:
# the action runs inside Invoke-TasksLocked, whose own -Session parameter would shadow a $Session here.
function Clear-SessionClaims($P, [string] $Session, [string] $By, [string] $Why) {
    $unitSession = $Session; $unitBy = $By; $unitWhy = $Why
    $unitFreed = [Collections.Generic.List[string]]::new()
    [void](Invoke-TasksLocked $P $By {
        param($doc)
        foreach ($t in $doc.tasks) {
            if (-not $t.claim -or [string]$t.claim.session -ne $unitSession) { continue }
            Clear-DeadClaim $P $t $unitBy "$unitWhy ($($t.claim.role) claim of $unitSession)" 'runner unit ended'
            $unitFreed.Add([string]$t.id)
        }
        if ($unitFreed.Count) { $doc } else { $null }
    })
    $unitFreed.ToArray()
}

# ONE SELECTOR for the claim, the runner gate, the status buffer and the integrator (2026-10-05 priority-focus-design
# 3.1, E1). On 2026-10-05 an author unit ended idle at $0.55 because the "G3 only" rule lived in a lessons file, not in
# the gate, and the runner's author gate counted gate-kind rows the claim never offers. The rows come back unsorted;
# the claim sorts them. Gates, in this order: right state and kind for the role, in the FOCUS SET (Get-FocusSet),
# released or integrating group, no live claim and no live inbox hold (author and build), dependencies built or later
# (build: Test-BuildReady).
#   author   : planned code/mockup/docs/integration rows
#   build    : ticketed code/docs/mockup rows
#   integrate: built code/docs/mockup rows
# $Held is Get-InboxHeldRows $P (the caller loads lib\Inbox.ps1); pass @{} to skip the hold check. `ticketed` is every
# ticketed build-kind row on the board, for the "claimable N of M ticketed" tile.
function Get-Claimable($P, $doc, [string] $Role, $Held = $null) {
    $want = @{ author = 'planned'; build = 'ticketed'; integrate = 'built' }[$Role]
    if (-not $want) { throw "Get-Claimable: unknown role '$Role'" }
    $kinds = if ($Role -eq 'author') { @('code', 'mockup', 'docs', 'integration') } else { $script:BuildKinds }
    if ($null -eq $Held) { $Held = Get-InboxHeldRows $P }
    $released = @($doc.groups | Where-Object { $_.state -in @('released', 'integrating') } | ForEach-Object { $_.id })
    $focus = Get-FocusSet $doc $P
    $fg = Get-FocusGroups $doc $P
    $r = [ordered]@{ focusGroup = $(if ($fg.groups.Count) { $fg.groups -join '+' } else { $null }); focusSource = $fg.source; ids = [Collections.Generic.List[string]]::new(); rows = [Collections.Generic.List[object]]::new()
        waiting = [Collections.Generic.List[object]]::new(); heldIds = [Collections.Generic.List[string]]::new()
        held = 0; claimed = 0; notReleased = 0; notFocus = 0
        ticketed = @($doc.tasks | Where-Object { $_.state -eq 'ticketed' -and $_.kind -in $script:BuildKinds }) }
    foreach ($t in $doc.tasks) {
        if ($t.state -ne $want -or $t.kind -notin $kinds) { continue }
        if (-not $focus.Contains([string]$t.id)) { $r.notFocus++; continue }
        # The integrator lands a closed group's leftover built row (Get-FocusSet: final review I1); claims stay released-only.
        if ($Role -ne 'integrate' -and $t.group -notin $released) { $r.notReleased++; continue }
        if ($Role -ne 'integrate') {
            if (Test-ClaimLive $t) { $r.claimed++; continue }
            if ($Held.Contains([string]$t.id)) { $r.held++; $r.heldIds.Add([string]$t.id); continue }
        }
        if ($Role -eq 'build' -and -not (Test-BuildReady $doc $t)) { $r.waiting.Add($t); continue }
        $r.ids.Add([string]$t.id); $r.rows.Add($t)
    }
    # AUTHOR SPILL (owner ruling 2026-10-12): authors have their own queue. When the focus set offers an author nothing,
    # the author queue spills into every other released group's planned rows instead of reading NONE, so tickets are
    # ready when those groups become focus. Builders and the integrator stay focus-only. On 2026-10-12 five authors sat
    # idle with 70 planned rows in G7-G12 while the focus groups had no planned row left. The claim sorts the spill rows
    # by group order, then ready-first (Claim-Task.ps1), and stamps each with the main commit it was written against so
    # drift can be flagged when its group becomes focus (Get-SpillDrift).
    $r['spill'] = $false
    if ($Role -eq 'author' -and $r.ids.Count -eq 0) {
        foreach ($t in $doc.tasks) {
            if ($t.state -ne 'planned' -or $t.kind -notin $kinds -or $focus.Contains([string]$t.id)) { continue }
            if ($t.group -notin $released -or (Test-ClaimLive $t) -or $Held.Contains([string]$t.id)) { continue }
            $r.ids.Add([string]$t.id); $r.rows.Add($t)
        }
        $r['spill'] = $r.ids.Count -gt 0
    }
    $r
}

# A spill ticket (Get-Claimable author spill) records the main commit it was written against in its 'spill' field.
# Once the row is in the focus set and still ticketed, any write-set file changed on main since that commit means the
# ticket may cite code that has moved. Returns one entry per such row: @{ id; base; files }. Read-only; git only.
# -Id checks that one row whatever its state (the build claim asks after it has moved the row to building).
function Get-SpillDrift($P, $doc, [string] $Id = '') {
    $out = [Collections.Generic.List[object]]::new()
    $focus = Get-FocusSet $doc $P
    foreach ($t in $doc.tasks) {
        if ($Id) { if ([string]$t.id -ne $Id) { continue } }
        elseif ($t.state -ne 'ticketed' -or -not $focus.Contains([string]$t.id)) { continue }
        $s = if ($t -is [Collections.IDictionary] -and $t.Contains('spill')) { $t['spill'] } else { $null }
        if (-not $s -or -not $s['base']) { continue }
        $ws = @($t.writeSet | Where-Object { $_ })
        if (-not $ws.Count) { continue }
        $changed = @(git -C $P.Repo diff --name-only "$($s['base'])" HEAD -- @ws 2>$null | Where-Object { $_ })
        if ($changed.Count) { $out.Add([ordered]@{ id = [string]$t.id; base = [string]$s['base']; files = $changed }) }
    }
    , $out
}
# CLAIM ORDER (kit item IN-20261024221545-7b45): Get-Claimable's rows in the order Claim-Task.ps1 takes them, integration
# fix rows first, then group rank (an author's effective group), ready-on-release (author), chain minutes, board order.
# The runner GATE line names the first of these, so it names the row the claim takes, not Get-Claimable's board order.
function Get-ClaimOrder($P, $doc, [string] $Role, $Rows) {
    $chain = Get-ChainMinutes $doc
    $grank = Get-PriorityRankMap $doc $P
    $erank = if ($Role -eq 'author') { Get-EffectiveGroupRank $doc $grank } else { @{} }
    $boardOrder = @{}; $o = 0; foreach ($x in $doc.tasks) { $boardOrder[[string]$x.id] = ++$o }
    $cands = foreach ($t in @($Rows)) {
        if (-not $t) { continue }
        $fix = [int]($t.Contains('origin') -and $t['origin'] -eq 'integration')
        $rank = if ($Role -eq 'author') { $erank[$t.id].rank } else { $grank[$t.group] }
        $ready = [int]($Role -eq 'author' -and (Test-ReadyWhenTicketed $doc $t))
        [pscustomobject]@{ Task = $t; Fix = $fix; Rank = $rank; Ready = $ready; Chain = $chain[$t.id]; Order = $boardOrder[[string]$t.id] }
    }
    @(@($cands | Sort-Object @{ e = 'Fix'; Descending = $true }, @{ e = 'Rank'; Descending = $false }, @{ e = 'Ready'; Descending = $true }, @{ e = 'Chain'; Descending = $true }, @{ e = 'Order'; Descending = $false }) | ForEach-Object { $_.Task })
}
# The build selector, kept by name for its callers (Get-StreamStatus.ps1, Start-StreamRunner.ps1).
function Get-BuildClaimable($P, $doc) { Get-Claimable $P $doc 'build' }

# The claimable BUFFER (owner ruling 2026-10-02, kit item IN-20261002160453-9384): builders should always find work, so
# the target is two claimable rows per live builder (working + idle). Below it Get-StreamStatus.ps1 raises 'PIPELINE
# DRY'. The author sort does not read it: ready-first is the permanent author order (Claim-Task.ps1, kit item
# IN-20261002161525-69c9). No live builder means a target of 0: nothing
# is short when nobody would take the work.
$script:BufferPerBuilder = 2
function Get-BuildBuffer($P, $doc, $Activity = $null, $Claimable = $null) {
    if (-not $Activity) { $Activity = Get-SessionActivity $P $doc }
    if (-not $Claimable) { $Claimable = Get-BuildClaimable $P $doc }
    $live = @(Get-LiveSessionIds $Activity 'build' (Get-Date).ToUniversalTime()).Count
    $target = $script:BufferPerBuilder * $live
    [ordered]@{ claimable = $Claimable.ids.Count; liveBuilders = $live; target = $target; short = ($Claimable.ids.Count -lt $target) }
}
# A planned row that a builder could claim as soon as it is ticketed: every dependency is built or later.
function Test-ReadyWhenTicketed($doc, $Task) { Test-DepsAt $doc $Task $script:BuildReadyStates }

# TIMED-ROLE BACKOFF (2026-10-05 priority-focus-design E4). A timed runner (plan, status, kit, coordinator) whose
# last unit ended 'idle' with no open item in its inbox waits twice as long each time, capped at 20 minutes - under the
# 30-minute planner liveness rule and every inbox limit - and an inbox write wakes it at once (Start-StreamRunner.ps1
# polls the file, no tokens). integrate never backs off: its 600 s cadence holds in every state. Measured before:
# long sessions spent on ticks that found nothing to do.
$script:TimedBackoffCap = @{ plan = 1200; status = 1200; kit = 1200; coordinator = 1200 }
function Get-RunnerWait([string] $Role, [int] $Interval, [int] $IdleStreak) {
    if (-not $script:TimedBackoffCap.ContainsKey($Role) -or $IdleStreak -le 0) { return $Interval }
    $cap = [Math]::Max($Interval, $script:TimedBackoffCap[$Role])
    [int][Math]::Min($cap, $Interval * [Math]::Pow(2, [Math]::Min($IdleStreak, 10)))
}
# A unit's outcome from its runner result: the 'outcome' field a -Live unit writes through unit_done, else the last
# "UNIT-OUTCOME: <outcome>" line a headless (-p) unit ends its text with (it has no unit_done tool). Without the line,
# headless units never reported 'idle', so the E4 backoff and the cost page's idle-launch flag never fired for them
# (final review I7). '' when neither is there. $Result is a hashtable or a PSCustomObject.
function Get-UnitOutcome($Result) {
    if (-not $Result) { return '' }
    $get = { param($n) if ($Result -is [Collections.IDictionary]) { if ($Result.Contains($n)) { $Result[$n] } else { $null } } elseif ($Result.PSObject.Properties[$n]) { $Result.$n } else { $null } }
    $o = & $get 'outcome'; if ($o) { return [string]$o }
    $text = [string](& $get 'result')
    $m = [regex]::Matches($text, '(?m)^\s*UNIT-OUTCOME:\s*([a-z]+)\s*$')
    if ($m.Count) { $m[$m.Count - 1].Groups[1].Value } else { '' }
}

# USAGE LIMIT (kit item IN-20261010205318-5308). When the account's quota is spent, claude writes one synthetic
# assistant line to the session transcript and the interactive session then sits at its prompt. Measured 2026-10-10
# 20:07:18Z (transcript 899e3877-...jsonl): "isApiErrorMessage":true, "error":"rate_limit", "apiErrorStatus":429,
# "quotaLimits":{"status":"rejected","resetsAt":1791665400,"rateLimitType":"five_hour",...}, text "You've hit your
# session limit · resets 4:50pm (America/New_York)". Only a REJECTED quota counts: a transient 429 has no quotaLimits
# rejection and claude retries it itself. Returns the last hit in $Lines as @{ resetsAt = UTC [datetime] or $null;
# type; text }, or $null.
function Find-QuotaRejection([string[]] $Lines) {
    $hit = $null
    foreach ($l in $Lines) {
        if (-not $l -or -not $l.Contains('"quotaLimits"') -or -not $l.Contains('"isApiErrorMessage"')) { continue }
        try { $o = $l | ConvertFrom-Json -AsHashtable -Depth 20 -ErrorAction Stop } catch { continue }
        if ($o -isnot [Collections.IDictionary] -or $o['isApiErrorMessage'] -ne $true) { continue }
        $q = $o['quotaLimits']
        if ($q -isnot [Collections.IDictionary] -or [string]$q['status'] -ne 'rejected') { continue }
        $at = $null; $s = [long]0
        if ([long]::TryParse([string]$q['resetsAt'], [ref]$s) -and $s -gt 0) { $at = [DateTimeOffset]::FromUnixTimeSeconds($s).UtcDateTime }
        $text = ''
        $m = $o['message']
        if ($m -is [Collections.IDictionary] -and $m['content']) { $text = (@($m['content']) | Where-Object { $_ -is [Collections.IDictionary] -and $_['type'] -eq 'text' } | ForEach-Object { [string]$_['text'] }) -join ' ' }
        $type = [string]$q['rateLimitType']; if (-not $type) { $type = 'usage' }
        $hit = @{ resetsAt = $at; type = $type; text = $text }
    }
    $hit
}

# Where claude keeps session transcripts: STREAM_CLAUDE_PROJECTS (a self-test's scratch), else
# <CLAUDE_CONFIG_DIR or ~\.claude>\projects.
function Get-ClaudeProjectsRoot {
    if ($env:STREAM_CLAUDE_PROJECTS) { return $env:STREAM_CLAUDE_PROJECTS }
    $base = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
    Join-Path $base 'projects'
}

# When a runner may launch again after a rejection: the stated reset plus a random 30..150 s (runners that hit the limit
# together must not restart together), at least 60 s from now and at most STREAM_RUNNER_QUOTA_MAX_WAIT_SECONDS (21600)
# away, so a weekly limit is re-tried every 6 h rather than waited out blind. No reset time = 900 s, the old backoff.
function Get-QuotaResumeTime($ResetsAt) {
    $now = (Get-Date).ToUniversalTime()
    $max = 21600; $n = 0
    if ([int]::TryParse([string]$env:STREAM_RUNNER_QUOTA_MAX_WAIT_SECONDS, [ref]$n) -and $n -gt 0) { $max = $n }
    $wait = if ($ResetsAt) { ([datetime]$ResetsAt - $now).TotalSeconds + (Get-Random -Minimum 30 -Maximum 151) } else { 900 }
    $now.AddSeconds([Math]::Min($max, [Math]::Max(60, $wait)))
}

# The account-wide hold, .streams\runners\quota-hold.json { until, by, type }: the limit is the account's, so the first
# runner that sees it keeps every runner from launching (and pre-staging claims) until it lifts. A later 'until' never
# shortens a hold already set. Get-QuotaHold returns @{ until = UTC [datetime]; by; type } while the hold is in force,
# else $null (an unreadable file is no hold).
function Get-QuotaHold($P) {
    $f = Join-Path $P.Root 'runners\quota-hold.json'
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { $h = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { return $null }
    $u = [datetime]::MinValue
    if (-not [datetime]::TryParse([string]$h['until'], [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$u)) { return $null }
    if ($u -le (Get-Date).ToUniversalTime()) { return $null }
    @{ until = $u; by = [string]$h['by']; type = [string]$h['type'] }
}
function Set-QuotaHold($P, [datetime] $Until, [string] $By, [string] $Type) {
    $cur = Get-QuotaHold $P
    if ($cur -and $cur.until -ge $Until) { return }
    $dir = Join-Path $P.Root 'runners'
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $doc = [ordered]@{ until = $Until.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); by = $By; type = $Type; at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    Write-AtomicText (Join-Path $dir 'quota-hold.json') ($doc | ConvertTo-Json)
}

# THE EARLY-LIFT PROBE (kit item IN-20261024093536-3be3): a weekly hold is capped at 6 h, but the account can lift
# sooner (re-login, extra usage). While a hold is in force one runner per repo makes one minimal claude call every
# STREAM_RUNNER_QUOTA_PROBE_SECONDS (1800; 0 = off), on the units' model (another model's bucket could lift falsely).
# probedAt/probedBy in quota-hold.json, written under runners\quota-probe.lock before the call, pick the one prober.
# A success moves the hold aside to quota-hold.lifted-<stamp>.json (audit) and ends every runner's wait; a rejection
# keeps it; anything else (timeout, no JSON) is UNKNOWN and changes nothing. A false lift corrects itself: the next
# unit meets the rejection and re-sets the hold. STREAM_RUNNER_QUOTA_PROBE_CMD names a .ps1 that replaces the claude
# call (self-tests). Returns OFF, NONE (no hold), SKIP, BUSY, LIFTED, HELD or UNKNOWN.
function Invoke-QuotaProbe($P, [string] $Session, [string] $Model = '') {
    $every = 1800; $n = 0
    if ($null -ne $env:STREAM_RUNNER_QUOTA_PROBE_SECONDS -and [int]::TryParse([string]$env:STREAM_RUNNER_QUOTA_PROBE_SECONDS, [ref]$n)) { $every = $n }
    if ($every -le 0) { return 'OFF' }
    $dir = Join-Path $P.Root 'runners'; $f = Join-Path $dir 'quota-hold.json'
    $hold = Get-QuotaHold $P
    if (-not $hold) { return 'NONE' }
    $lock = Join-Path $dir 'quota-probe.lock'
    try {
        if ((Test-Path -LiteralPath $lock) -and ((Get-Date) - (Get-Item -LiteralPath $lock).LastWriteTime).TotalSeconds -gt 300) { Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
        $fs = [IO.File]::Open($lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    } catch { return 'BUSY' }
    try {
        try { $doc = Get-Content -LiteralPath $f -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop } catch { return 'NONE' }
        # A hold with no time of its own starts the interval now, never with a call.
        if (-not $doc['probedAt'] -and -not $doc['at']) { $doc['probedAt'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); Write-AtomicText $f ($doc | ConvertTo-Json); return 'SKIP' }
        $last = [datetime]::MinValue; $since = if ($doc['probedAt']) { [string]$doc['probedAt'] } else { [string]$doc['at'] }
        if ($since -and [datetime]::TryParse($since, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal, [ref]$last) -and ((Get-Date).ToUniversalTime() - $last).TotalSeconds -lt $every) { return 'SKIP' }
        $doc['probedAt'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); $doc['probedBy'] = $Session
        Write-AtomicText $f ($doc | ConvertTo-Json)
    } finally { $fs.Dispose(); Remove-Item -LiteralPath $lock -Force -ErrorAction SilentlyContinue }
    $in = [IO.Path]::GetTempFileName(); $out = "$in.out"; $err = "$in.err"
    try {
        if ($env:STREAM_RUNNER_QUOTA_PROBE_CMD) { $exe = 'pwsh'; $argv = @('-NoProfile', '-NonInteractive', '-File', $env:STREAM_RUNNER_QUOTA_PROBE_CMD) }
        else { $exe = 'claude'; $argv = @('-p', '"Reply with OK."', '--output-format', 'json', '--max-turns', '1'); if ($Model) { $argv += @('--model', $Model) } }
        $proc = Start-Process -FilePath $exe -ArgumentList $argv -NoNewWindow -PassThru -RedirectStandardInput $in -RedirectStandardOutput $out -RedirectStandardError $err
        if (-not $proc.WaitForExit(120000)) { & taskkill.exe /PID $proc.Id /T /F | Out-Null; return 'UNKNOWN' }
        $lines = @(Get-Content -LiteralPath $out -ErrorAction SilentlyContinue)
    } catch { return 'UNKNOWN' } finally { Remove-Item -LiteralPath $in, $out, $err -Force -ErrorAction SilentlyContinue }
    $rej = Find-QuotaRejection $lines
    $res = $null
    foreach ($l in $lines) { try { $o = $l | ConvertFrom-Json -AsHashtable -ErrorAction Stop; if ($o -is [Collections.IDictionary] -and $o.Contains('is_error')) { $res = $o } } catch { } }
    if ($rej -or ($res -and $res['is_error'] -eq $true -and [string]$res['result'] -match 'limit')) {
        if ($rej -and $rej.resetsAt) { Set-QuotaHold $P (Get-QuotaResumeTime $rej.resetsAt) $Session $rej.type }
        return 'HELD'
    }
    if (-not $res -or $res['is_error'] -ne $false) { return 'UNKNOWN' }
    if (-not (Test-Path -LiteralPath $f)) { return 'LIFTED' }
    $dest = Join-Path $dir ("quota-hold.lifted-{0}.json" -f (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ'))
    Move-Item -LiteralPath $f -Destination $dest -Force
    Add-Decision $P $Session "QUOTA-PROBE lifted $($hold.type) hold early (until was $($hold.until.ToString('yyyy-MM-ddTHH:mm:ssZ')))"
    'LIFTED'
}
# THE OWNER'S CONFIGURATION, .streams\config.json: a hand-edited file, read by the lib through the paths of the repo in
# hand ($P) or of the last repo Get-StreamPaths resolved, and re-parsed only when its write time or length changes.
# Missing or unreadable = @{} (every default applies). Start-StreamRunner.ps1 writes it with empty fields the first
# time it finds it missing, and reads its model fields itself.
function Get-StreamConfig($P = $null) {
    $file = if ($P) { Join-Path $P.Root 'config.json' } else { $script:StreamConfigFile }
    if (-not $file -or -not (Test-Path -LiteralPath $file)) { return @{} }
    $fi = Get-Item -LiteralPath $file
    $stamp = "$($fi.LastWriteTimeUtc.Ticks):$($fi.Length)"
    if ($script:StreamConfigCache -and $script:StreamConfigCache.file -eq $file -and $script:StreamConfigCache.stamp -eq $stamp) { return $script:StreamConfigCache.doc }
    $doc = @{}
    try { $doc = Get-Content -LiteralPath $file -Raw | ConvertFrom-Json -AsHashtable -Depth 10; if ($doc -isnot [Collections.IDictionary]) { $doc = @{} } } catch { $doc = @{} }
    $script:StreamConfigCache = @{ file = $file; stamp = $stamp; doc = $doc }
    $doc
}

# FOCUS (2026-10-05 priority-focus-design 3.1; owner-set since 2026-10-06). The focus groups are the groups every work
# role is offered rows from. By default there is ONE: the first group in board order whose state is not closed,
# computed from the board every time and never stored, so it cannot disagree with the groups list. Measured before
# this rule: G3-G6 were released together on 2026-09-28, and G4 saw 203 ticket events for 119 rows, because later
# groups were ticketed and built against earlier-group code that was still moving.
# THE OWNER SETS THE FOCUS BY HAND (owner ruling 2026-10-06) in .streams\config.json:
#     "focus": { "groups": ["G4"] }          one group        "focus": { "groups": ["G4", "G6"] }   more than one
# The list is read in the order it is WRITTEN, which is the owner's priority order (owner ruling 2026-10-14: focus
# ["G14","G13","G6"] is worked G14 first and shown in that order on the status page; until then the list was re-sorted
# into board order and the written order was lost). `groups` and `priority` both hold that order (`priority` is kept for
# callers that read it). A listed group that is closed or not on the board is dropped, a repeat is listed once; an empty
# list, or a list with nothing left in it, means the automatic rule, and `source` says which applied.
# Returns @{ groups = [string[]]; source = 'config' | 'auto' | 'auto (config focus.groups [...] ...)' }.
function Get-FocusGroups($doc, $P = $null) {
    $closed = @{}; foreach ($g in $doc.groups) { if ([string]$g.state -eq 'closed') { $closed[[string]$g.id] = $true } }
    $auto = @(foreach ($g in $doc.groups) { if (-not $closed.ContainsKey([string]$g.id)) { [string]$g.id; break } })
    $cfg = Get-StreamConfig $P
    $want = @()
    if ($cfg.Contains('focus') -and $cfg.focus -is [Collections.IDictionary] -and $cfg.focus.Contains('groups') -and $null -ne $cfg.focus.groups) {
        $want = @($cfg.focus.groups | ForEach-Object { [string]$_ } | Where-Object { $_ })
    }
    if ($want.Count) {
        $onBoard = @{}; foreach ($g in $doc.groups) { $onBoard[[string]$g.id] = $true }
        $chosen = @($want | Where-Object { $onBoard.ContainsKey($_) -and -not $closed.ContainsKey($_) } | Select-Object -Unique)
        if ($chosen.Count) { return @{ groups = $chosen; priority = $chosen; source = 'config' } }
        return @{ groups = $auto; source = "auto (config focus.groups [$($want -join ', ')] are all closed or not on the board)" }
    }
    @{ groups = $auto; source = 'auto' }
}
# The first focus group (the one a suite run or a close check means by "the focus group"); $null when every group is closed.
function Get-FocusGroup($doc, $P = $null) { $f = Get-FocusGroups $doc $P; if ($f.groups.Count) { $f.groups[0] } else { $null } }
# The focus groups as one label for messages and tiles: 'G4', or 'G4+G6'; $null when every group is closed.
function Get-FocusLabel($doc, $P = $null) { $f = Get-FocusGroups $doc $P; if ($f.groups.Count) { $f.groups -join '+' } else { $null } }
# The FOCUS SET: every row whose OWN group is a focus group, or whose EFFECTIVE group (Get-EffectiveGroupRank: the
# earliest group among the row and its unlanded dependents) is a focus group or a CLOSED group. One rule for author,
# build and integrate, so a later-group root that holds focus-group tickets is authored, built and integrated with the
# focus group. A per-role "own group only" rule deadlocked the 3 open G5 rows that wait on G6 roots (review F4). Closed
# groups count too: a row ranked there is leftover work a closed group still holds (G3 closed with rows not done, spec
# E6), or a focus row such a leftover waits on. Excluding them froze both for ever and the focus group could never close
# (final review I1). Claims stay safe: a closed group is not released, so its own rows are never claimed; the integrator
# lands a leftover built row. With the automatic focus (the first unclosed group) this is exactly the 2026-10-05 rule
# "effective rank at or before the focus group's". With an owner-set focus a row of an OPEN group that is not listed is
# frozen, even when a listed group's row waits on it: list that group too if its work should run. Empty when every group
# is closed.
function Get-FocusSet($doc, $P = $null) { , (Get-FocusClosure $doc $P).set }
# The focus set with its DEPENDENCY CLOSURE (2026-10-18 dependency review, finding F3). The effective-rank rule above
# pulls in a LATER group's root that a focus row waits on, but not an EARLIER open group's: a focus G13 row waiting on
# an open G6 row read G6's rank, G6 was not listed, and the row was frozen for ever while the board named only "wait on
# roots G6.T307" with no word that the root was outside the focus. So every unlanded row a focus row depends on,
# transitively, is in the set too, whatever its group - a dependency is work the focus cannot finish without, and the
# owner who listed the focus group asked for that group to finish. Only dependencies are pulled, never dependents: an
# unlisted group's row that merely waits on focus work stays frozen, as the owner-focus rule says. Claims stay safe: a
# pulled row of a group that is not released is still refused by the released gate.
# Returns @{ set = HashSet of ids; pulled = [ordered] id -> via (the focus row whose chain pulled it) }.
function Get-FocusClosure($doc, $P = $null) {
    $set = [Collections.Generic.HashSet[string]]::new()
    $pulled = [ordered]@{}
    $f = Get-FocusGroups $doc $P
    if (-not $f.groups.Count) { return @{ set = $set; pulled = $pulled } }
    $groupAt = @(foreach ($g in $doc.groups) { [string]$g.id })
    $in = @{}; foreach ($id in $f.groups) { $in[$id] = $true }
    foreach ($g in $doc.groups) { if ([string]$g.state -eq 'closed') { $in[[string]$g.id] = $true } }
    $erank = Get-EffectiveGroupRank $doc
    $byId = @{}; foreach ($t in $doc.tasks) { $byId[[string]$t.id] = $t }
    foreach ($t in $doc.tasks) {
        if ($in.ContainsKey([string]$t.group)) { [void]$set.Add([string]$t.id); continue }
        if ($erank[$t.id] -and $in.ContainsKey($groupAt[$erank[$t.id].rank])) { [void]$set.Add([string]$t.id) }
    }
    # Dependency closure: walk dependsOn from every UNLANDED row already in the set (a row that is integrated or done needs
    # nothing, so its edges pull nothing); an unlanded row not yet in the set is pulled.
    $stack = [Collections.Generic.Stack[object]]::new()
    foreach ($id in @($set)) { $stack.Push(@($id, $id)) }
    while ($stack.Count) {
        $frame = $stack.Pop(); $id = [string]$frame[0]; $via = [string]$frame[1]
        $t = $byId[$id]; if (-not $t) { continue }
        if ([string]$t.state -in @('integrated', 'done')) { continue }
        foreach ($d in @($t.dependsOn)) {
            if (-not $d) { continue }
            $d = [string]$d
            if ($set.Contains($d)) { continue }
            $dt = $byId[$d]; if (-not $dt) { continue }
            if ([string]$dt.state -in @('integrated', 'done')) { continue }
            [void]$set.Add($d); $pulled[$d] = $via
            $stack.Push(@($d, $via))
        }
    }
    @{ set = $set; pulled = $pulled }
}
# FOCUS PRIORITY (owner ruling 2026-10-14, coordinator-13c4c8a7): the claim sort's group rank. The owner wrote focus
# ["G13","G14","G6"] to put G13 first, but every rank read board order, so G6 still sorted first. Focus groups rank
# 0..k-1 in the order focus.groups is WRITTEN; every other group ranks after them in board order. The focus SET is
# unchanged (Get-FocusSet); only the order of rows inside it moves. Returns group id -> int.
function Get-PriorityRankMap($doc, $P = $null) {
    $first = @((Get-FocusGroups $doc $P).groups)
    $m = @{}; $i = 0
    foreach ($id in $first) { if (-not $m.ContainsKey([string]$id)) { $m[[string]$id] = $i++ } }
    foreach ($g in $doc.groups) { if (-not $m.ContainsKey([string]$g.id)) { $m[[string]$g.id] = $i++ } }
    $m
}

# GATE ROWS need no ticket: a planned gate of the focus set (its own group, or a later group a focus row waits on)
# moves to ticketed with no claim. Both the author claim and the status watchdog call this, so gates advance even when
# no author unit runs: the runner gate launches authors only for claimable planned rows, and a group can become focus
# with nothing planned but its gates (final review I2). Call inside Invoke-TasksLocked. Returns the ids advanced.
function Step-FocusGates($doc, [string] $Session) {
    $released = @($doc.groups | Where-Object { $_.state -in @('released', 'integrating') } | ForEach-Object { [string]$_.id })
    $focusSet = Get-FocusSet $doc
    @(foreach ($g in @($doc.tasks | Where-Object { $_.kind -eq 'gate' -and $_.state -eq 'planned' -and $focusSet.Contains([string]$_.id) -and [string]$_.group -in $released })) {
        Set-TaskState $g 'ticketed' 'author' $Session 'gate: no ticket needed'
        [string]$g.id
    })
}

# An EARLIER group's integration task must never wait on a LATER group's row. Groups close in the owner's priority
# order, which is the order of the board's groups list (G1 Reference Data > G2 Backup and Restore > G3 Steps > G4
# Workflows > G5 TestAuto > G6 Dial), and a later group's row is built in that later group's turn, so such an edge holds
# the earlier close hostage to later work. That shape pulled G1.T24, G1.T25 and G3.T193 into G1's close (owner ruling
# IN-20261001193348-5979). Returns one LATER-GROUP-DEP line per offending edge in $Deps; $Tasks holds every row the
# deps can name (board plus the batch). A group missing from the list has no rank and is not judged.
function Get-LaterGroupDepProblems($Groups, $Tasks, $IntegrationTask, $Deps) {
    if ($IntegrationTask['kind'] -ne 'integration') { return @() }
    $rank = @{}; $i = 0
    foreach ($g in @($Groups)) { if ($g) { $rank[[string] $g['id']] = $i++ } }
    $own = [string] $IntegrationTask['group']
    if (-not $rank.ContainsKey($own)) { return @() }
    $out = @()
    foreach ($d in @($Deps | Where-Object { $_ })) {
        $dt = @($Tasks | Where-Object { $_ -and [string] $_['id'] -eq [string] $d })
        if (-not $dt.Count) { continue }
        $dg = [string] $dt[0]['group']
        if ($rank.ContainsKey($dg) -and $rank[$dg] -gt $rank[$own]) {
            $out += "LATER-GROUP-DEP $($IntegrationTask['id']) -> $d : $own's integration task would wait on a row of $dg, a LATER group, so $own could not close until $dg's work lands. File the failure as a fix row in $dg instead and record it in $own's close-out evidence"
        }
    }
    $out
}

function ConvertTo-RepoRel([string] $Path) { ($Path -replace '\\', '/') -replace '^\./', '' }

# A task whose write set lies ENTIRELY under .streams\ is delivered IN PLACE: no patch and no tree change. .streams is
# in .git/info/exclude, so git never reports those files - `git ls-files --others --exclude-standard` skips them and
# `git diff` cannot see them - which means a worktree base never carries them and Export-TaskPatch.ps1 can only ever
# answer EMPTY. Before 2026-09-30 eight such tasks were planned as code or docs and none of them could be built at all:
# two grader repairs (G1.T22, G1.T23) and the six AC-coverage audits under .streams\plans (kit item
# IN-20260930022231-9702). The builder writes the artifact where the grader reads it, exactly as a mockup task does.
function Test-InPlaceWriteSet($WriteSet) {
    $w = @(@($WriteSet) | Where-Object { $_ })
    if (-not $w.Count) { return $false }
    foreach ($f in $w) { if ((ConvertTo-RepoRel $f) -notlike '.streams/*') { return $false } }
    $true
}

# A delivered folder under .streams has NO patch to hand off: artifacts.patch is the artifact's own path, so between
# `built` and `integrated` the deliverable is a live directory and nothing records what the verifier actually graded.
# On 2026-09-30 build-202609291226-3a11 corrected one prose sentence in .streams/mockups/g2/welcome/RECOVERY.md AFTER
# G2.T97 went built and its claim was released, and its inbox item reached the integrator FIVE MINUTES AFTER that folder
# had already been integrated with `mockup: no tree change` (kit item IN-20260930120446-f9f5). The edit was right and
# well documented; the board simply had no way to see it. So the hand-off writes a fingerprint and the integrator
# compares it, and REPORTS a difference rather than refusing it: a correction after hand-off can be correct.
function Get-DeliveredFiles([string] $Repo, $WriteSet) {
    $out = [Collections.Generic.List[string]]::new()
    foreach ($w in @(@($WriteSet) | Where-Object { $_ })) {
        $rel = ConvertTo-RepoRel $w
        $full = Join-Path $Repo ($rel -replace '/', '\')
        if ($rel -like '*[*]*') {
            foreach ($f in @(Get-ChildItem -Path $full -File -Recurse -ErrorAction SilentlyContinue)) { $out.Add($f.FullName) }
        } elseif (Test-Path -LiteralPath $full -PathType Container) {
            foreach ($f in @(Get-ChildItem -LiteralPath $full -File -Recurse -ErrorAction SilentlyContinue)) { $out.Add($f.FullName) }
        } elseif (Test-Path -LiteralPath $full -PathType Leaf) {
            $out.Add((Resolve-Path -LiteralPath $full).Path)
        }
    }
    @($out | Sort-Object -Unique)
}

function New-DeliveredManifest([string] $Repo, $WriteSet) {
    $rows = [Collections.Generic.List[object]]::new()
    foreach ($f in (Get-DeliveredFiles $Repo $WriteSet)) {
        $rel = ConvertTo-RepoRel ($f.Substring($Repo.TrimEnd('\').Length).TrimStart('\'))
        $rows.Add([ordered]@{ path = $rel; sha256 = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash; bytes = (Get-Item -LiteralPath $f).Length })
    }
    [ordered]@{ at = (Get-Now); files = @($rows | Sort-Object { $_.path }) }
}

function Write-DeliveredManifest($P, [string] $Task, $WriteSet) {
    New-Item -ItemType Directory -Path $P.Patches -Force | Out-Null
    $file = Join-Path $P.Patches "$Task.manifest.json"
    Set-Content -Path $file -Encoding utf8 -Value ((New-DeliveredManifest $P.Repo $WriteSet) | ConvertTo-Json -Depth 5)
    ConvertTo-RepoRel (".streams/patches/$Task.manifest.json")
}

# Every difference between the manifest written at hand-off and the folder as it stands now, as `added`, `removed` or
# `changed` lines. An absent or unreadable manifest answers NO-MANIFEST, which is not a difference: rows handed off
# before this shipped have none.
function Compare-DeliveredManifest($P, [string] $Task, $WriteSet) {
    $file = Join-Path $P.Patches "$Task.manifest.json"
    if (-not (Test-Path -LiteralPath $file)) { return @('NO-MANIFEST') }
    try { $m = Get-Content -Raw -LiteralPath $file | ConvertFrom-Json -AsHashtable -Depth 10 } catch { return @('NO-MANIFEST') }
    $was = @{}
    foreach ($r in @($m['files'])) { $was[[string] $r['path']] = [string] $r['sha256'] }
    $now = @{}
    foreach ($f in (Get-DeliveredFiles $P.Repo $WriteSet)) {
        $rel = ConvertTo-RepoRel ($f.Substring($P.Repo.TrimEnd('\').Length).TrimStart('\'))
        $now[$rel] = (Get-FileHash -LiteralPath $f -Algorithm SHA256).Hash
    }
    $diff = [Collections.Generic.List[string]]::new()
    foreach ($k in @($was.Keys | Sort-Object)) {
        if (-not $now.ContainsKey($k)) { $diff.Add("removed $k") }
        elseif ($now[$k] -ne $was[$k]) { $diff.Add("changed $k") }
    }
    foreach ($k in @($now.Keys | Sort-Object)) { if (-not $was.ContainsKey($k)) { $diff.Add("added $k") } }
    @($diff)
}

# A write-set entry that ends in a separator is a DIRECTORY, and every file under it belongs to the task. Until
# 2026-09-30 this compared the file against the entry with -like alone, so a directory entry matched nothing at all:
# G1.T12 owns `evidence/FEAT-REFERENCE-DATA-001/` and Export-TaskPatch.ps1 answered `OUTSIDE` for all ten files of a
# five-suite evidence package that existed in no other place (kit item IN-20260930172851-089f). A task whose write set
# is a folder could not be salvaged, and could not be exported by its own builder either.
function Test-UnderWriteSetEntry([string] $File, [string] $Entry) {
    $f = ConvertTo-RepoRel $File
    $e = ConvertTo-RepoRel $Entry
    if (-not $e) { return $false }
    if ($e.EndsWith('/')) { return $f -eq $e.TrimEnd('/') -or $f.StartsWith($e, [StringComparison]::OrdinalIgnoreCase) }
    $f -like $e
}
function Test-InWriteSet([string] $File, $WriteSet) {
    foreach ($w in @($WriteSet)) { if (Test-UnderWriteSetEntry $File $w) { return $true } }
    $false
}

# INDEX loops, never nested foreach over the parameters. On PowerShell 7.6.6 a nested `foreach ($b in @($B))` inside
# `foreach ($a in @($A))` does NOT restart the inner enumeration for the second and later elements of $A when both
# are parameter-bound: @('p','q') x @('r','s') yields pr, ps, qs - qr is never compared. So this function silently
# missed every overlap that was not on the diagonal. G2.T95 was added on 2026-09-29 over a path three planned tasks
# already owned, because the match was A[1] x B[0], and the board was left UNORDERED (kit item IN-20260929175717-5b24).
# The paths are normalised once per call and Test-UnderWriteSetEntry's rule is written inline (same result): this runs
# for every (new row, open row) pair of an Add-Tasks.ps1 release under the tasks.json lock, and four function calls
# per path pair were most of an 81-row release's time once the chain walk was moved behind it (kit item
# IN-20261010174706-ed53).
function Test-WriteSetOverlap($A, $B) {
    $as = @(@($A) | ForEach-Object { ([string]$_ -replace '\\', '/') -replace '^\./', '' })
    $bs = @(@($B) | ForEach-Object { ([string]$_ -replace '\\', '/') -replace '^\./', '' })
    for ($i = 0; $i -lt $as.Count; $i++) {
        $x = $as[$i]
        for ($j = 0; $j -lt $bs.Count; $j++) {
            $y = $bs[$j]
            if ($x -eq $y -or $x -like $y -or $y -like $x) { return $true }
            # A directory entry overlaps every path under it, in either direction: without this, one task owning
            # `evidence/F/` and another owning `evidence/F/README.md` read as disjoint and both could be released.
            if ($y.EndsWith('/') -and ($x -eq $y.TrimEnd('/') -or $x.StartsWith($y, [StringComparison]::OrdinalIgnoreCase))) { return $true }
            if ($x.EndsWith('/') -and ($y -eq $x.TrimEnd('/') -or $y.StartsWith($x, [StringComparison]::OrdinalIgnoreCase))) { return $true }
        }
    }
    $false
}

# ORDERED-BY-MERGE (owner ruling 2026-10-18, kit item IN-20261018133755-8c9f): two rows may share a composition /
# registration file with no dependsOn chain, because each only appends registration lines there and the merge orders
# them. True only when A and B overlap and EVERY overlapping pair is the same exact path (no wildcard, no directory
# entry) matching $script:CompositionFileRx; any other shared path still needs an order. Same regex as
# Find-ArtificialBlockers.ps1's 'composition' kind.
# The append-only id register docs/requirements/ids.yaml is in the set too (kit item IN-20261023221543-c537): rows that
# only append allocate events there need no order, and an edit of an existing line is still refused at export
# (COMPOSITION-EDIT); two rows that allocate the same id in parallel are caught at integration (Get-AllocatorDuplicates).
$script:AllocatorFileRx = '(^|/)ids\.yaml$'
$script:CompositionFileRx = '(^|/)src/Composition/|(^|/)Program\.cs$|Module\.cs$|ServiceCollectionExtensions\.cs$|(^|/)Routes\.razor$|(^|/)ids\.yaml$'
function Test-MergeOrderedOverlap($A, $B) {
    $as = @(@($A) | Where-Object { $_ } | ForEach-Object { ([string]$_ -replace '\\', '/') -replace '^\./', '' })
    $bs = @(@($B) | Where-Object { $_ } | ForEach-Object { ([string]$_ -replace '\\', '/') -replace '^\./', '' })
    $found = $false
    for ($i = 0; $i -lt $as.Count; $i++) {
        for ($j = 0; $j -lt $bs.Count; $j++) {
            if (-not (Test-WriteSetOverlap @($as[$i]) @($bs[$j]))) { continue }
            $x = $as[$i]; $y = $bs[$j]
            if ($x -ne $y -or $x -match '[\*\?\[]' -or $x.EndsWith('/') -or $x -notmatch $script:CompositionFileRx) { return $false }
            $found = $true
        }
    }
    $found
}

# The builder's side of ORDERED-BY-MERGE (kit item IN-20261018134209-b23c): a row that shares an exact composition
# file with another open row and no dependsOn path between them (either way) may only APPEND lines there, because the
# integrator merges such patches by their added lines. Returns one 'COMPOSITION-EDIT <path> ...' line per changed
# composition file of $Changed whose diff in $Worktree removes or changes a line while such a peer exists; empty when
# the patch is add-only there, or the file is the row's alone, or every sharer is ordered with it or already on main.
function Get-CompositionEditRefusals($Tasks, [string] $Task, [string] $Worktree, [string[]] $Changed) {
    $rows = @($Tasks | Where-Object { $_ })
    $byId = @{}; foreach ($r in $rows) { $byId[[string]$r['id']] = $r }
    $me = $byId[$Task]; if (-not $me) { return }
    $ancOf = {
        param($id)
        $seen = [Collections.Generic.HashSet[string]]::new(); $stack = [Collections.Generic.Stack[string]]::new(); $stack.Push($id)
        while ($stack.Count) { $c = $stack.Pop(); $r = $byId[$c]; if (-not $r) { continue }
            foreach ($d in @($r['dependsOn'])) { if ($d -and $seen.Add([string]$d)) { $stack.Push([string]$d) } } }
        , $seen
    }
    $myAnc = & $ancOf $Task
    foreach ($p in @($Changed)) {
        $n = ([string]$p -replace '\\', '/') -replace '^\./', ''
        if ($n -notmatch $script:CompositionFileRx) { continue }
        $peers = @(foreach ($r in $rows) {
            $id = [string]$r['id']
            # An integrated or done sharer is already on main, so in this row's base: no merge peer (IN-20261023051312-f824).
            if ($id -eq $Task -or [string]$r['state'] -in @('done', 'integrated')) { continue }
            $hit = @(@($r['writeSet']) | Where-Object { (([string]$_ -replace '\\', '/') -replace '^\./', '') -ieq $n })
            if (-not $hit.Count -or $myAnc.Contains($id) -or (& $ancOf $id).Contains($Task)) { continue }
            $id })
        if (-not $peers.Count) { continue }
        $ns = @(& git -C $Worktree -c core.safecrlf=false diff --numstat -- $p | Where-Object { $_ })
        $del = 0; foreach ($l in $ns) { $c = ($l -split "`t")[1]; if ($c -match '^\d+$') { $del += [int]$c } elseif ($c -eq '-') { $del++ } }
        if ($del -gt 0) { "COMPOSITION-EDIT $n removes or changes $del line(s); shared with $($peers -join ', ') (no dependsOn order): append registration lines only, or ask the plan for an order" }
    }
}
# The integrator's side of ORDERED-BY-MERGE (kit item IN-20261018134210-ede5): a patch whose `git apply --check` fails
# on the main tree may still land when every failing section is a composition file (lib $script:CompositionFileRx)
# whose hunks only ADD lines. Each added run is re-inserted after the unchanged lines that preceded it in the patch
# (up to 3), or before the ones that followed it when it opened its hunk, at the one place those lines appear in main
# now; a run already there is skipped. The result is one new patch, $OutPath: the untouched sections plus a fresh diff
# of each merged file against main, so the apply, the reverse and the commit all work on that one patch. Returns
# @{ Ok; Path; Files; Reason }. Not Ok (main untouched) when another file conflicts, a failing composition section
# removes or changes a line, creates, deletes or renames a file, or an anchor is missing or not unique.
function New-CompositionMergedPatch([string] $Repo, [string] $PatchPath, [string] $OutPath) {
    $no = { param($why) [pscustomobject]@{ Ok = $false; Path = $null; Files = @(); Reason = $why } }
    $raw = [IO.File]::ReadAllText($PatchPath)
    $sections = @([regex]::Split($raw, '(?m)^(?=diff --git )') | Where-Object { $_ -match '^diff --git ' })
    if (-not $sections.Count) { return (& $no 'no file sections in the patch') }
    $tmp = Join-Path ([IO.Path]::GetTempPath()) ('speedy-merge-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Force $tmp | Out-Null
    try {
        $check = {
            param([string] $text)
            $f = Join-Path $tmp ('check-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.patch')
            [IO.File]::WriteAllText($f, $text)
            & git -C $Repo apply --check --binary --whitespace=nowarn $f 2>&1 | Out-Null
            $LASTEXITCODE -eq 0
        }
        $keep = [Collections.Generic.List[string]]::new(); $toMerge = [Collections.Generic.List[object]]::new()
        foreach ($sec in $sections) {
            $path = if ($sec -match '^diff --git a/(.+?) b/(.+?)\r?\n') { $Matches[2] } else { '' }
            $plain = $sec -notmatch '(?m)^(new file mode|deleted file mode|rename from|copy from|Binary files|GIT binary patch)'
            if ($path -match $script:CompositionFileRx -and $plain -and -not (& $check $sec)) { $toMerge.Add([pscustomobject]@{ Path = $path; Text = $sec }) }
            else { $keep.Add($sec) }
        }
        if (-not $toMerge.Count) { return (& $no 'the conflict is not in a composition file') }
        if ($keep.Count -and -not (& $check ($keep -join ''))) { return (& $no 'a file outside the composition files does not apply') }
        foreach ($m in $toMerge) {
            $full = Join-Path $Repo $m.Path
            if (-not (Test-Path -LiteralPath $full)) { return (& $no "$($m.Path) is missing on main") }
            $bytes = [IO.File]::ReadAllBytes($full)
            $bom = $bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF
            $text = [Text.UTF8Encoding]::new($false).GetString($bytes, $(if ($bom) { 3 } else { 0 }), $bytes.Length - $(if ($bom) { 3 } else { 0 }))
            $nl = if ($text.Contains("`r`n")) { "`r`n" } else { "`n" }
            $lines = [Collections.Generic.List[string]]::new()
            foreach ($l in [regex]::Split($text, '(?<=\n)')) { if ($l -ne '') { $lines.Add($l) } }
            $key = { param($s) $s.TrimEnd("`r", "`n") }
            $hunks = [Collections.Generic.List[object]]::new(); $cur = $null
            foreach ($pl in ($m.Text -split "`n")) {
                $pl = $pl.TrimEnd("`r")
                if ($pl -match '^@@ ') { $cur = [Collections.Generic.List[object]]::new(); $hunks.Add($cur); continue }
                if ($null -eq $cur -or $pl.Length -eq 0 -or $pl[0] -eq '\') { continue }
                if ($pl[0] -eq '-') { return (& $no "$($m.Path) removes or changes a line (not add-only)") }
                if ($pl[0] -in ' ', '+') { $cur.Add([pscustomobject]@{ T = $pl[0]; S = $pl.Substring(1) }) }
            }
            foreach ($h in $hunks) {
                for ($i = 0; $i -lt $h.Count; $i++) {
                    if ($h[$i].T -ne '+' -or ($i -gt 0 -and $h[$i - 1].T -eq '+')) { continue }
                    $run = @(); $j = $i; while ($j -lt $h.Count -and $h[$j].T -eq '+') { $run += $h[$j].S; $j++ }
                    $before = @(); $k = $i - 1; while ($k -ge 0 -and $h[$k].T -eq ' ' -and $before.Count -lt 3) { $before = @($h[$k].S) + $before; $k-- }
                    $after = @(); $k = $j; while ($k -lt $h.Count -and $h[$k].T -eq ' ' -and $after.Count -lt 3) { $after += $h[$k].S; $k++ }
                    $anchor = if ($before.Count) { $before } else { $after }
                    if (-not $anchor.Count) { return (& $no "$($m.Path) has an added run with no unchanged line around it") }
                    $at = @(for ($p = 0; $p -le $lines.Count - $anchor.Count; $p++) {
                        $ok = $true; for ($q = 0; $q -lt $anchor.Count; $q++) { if ((& $key $lines[$p + $q]) -cne $anchor[$q]) { $ok = $false; break } }
                        if ($ok) { $p } })
                    if ($at.Count -ne 1) { return (& $no "$($m.Path): the lines around an added run appear $($at.Count) times on main (need exactly 1)") }
                    $ins = if ($before.Count) { $at[0] + $anchor.Count } else { $at[0] }
                    $there = $ins + $run.Count -le $lines.Count
                    for ($q = 0; $there -and $q -lt $run.Count; $q++) { if ((& $key $lines[$ins + $q]) -cne $run[$q]) { $there = $false } }
                    if ($there) { continue }
                    if ($ins -gt 0 -and -not $lines[$ins - 1].EndsWith("`n")) { $lines[$ins - 1] += $nl }
                    $lines.InsertRange($ins, [string[]]@($run | ForEach-Object { $_ + $nl }))
                }
            }
            foreach ($side in 'a', 'b') { New-Item -ItemType Directory -Force (Split-Path (Join-Path $tmp "$side/$($m.Path)")) | Out-Null }
            [IO.File]::WriteAllBytes((Join-Path $tmp "a/$($m.Path)"), $bytes)
            $pre = if ($bom) { [byte[]](0xEF, 0xBB, 0xBF) } else { [byte[]]@() }
            [IO.File]::WriteAllBytes((Join-Path $tmp "b/$($m.Path)"), [byte[]]($pre + [Text.UTF8Encoding]::new($false).GetBytes(($lines -join ''))))
            $out = Join-Path $tmp ('diff-' + [guid]::NewGuid().ToString('N').Substring(0, 8) + '.patch')
            & git -C $tmp -c core.autocrlf=false diff --no-index --binary --src-prefix= --dst-prefix= "--output=$out" -- "a/$($m.Path)" "b/$($m.Path)" 2>&1 | Out-Null
            if (-not (Test-Path -LiteralPath $out) -or (Get-Item -LiteralPath $out).Length -eq 0) { continue }
            $keep.Add([IO.File]::ReadAllText($out))
        }
        $merged = $keep -join ''
        if (-not (& $check $merged)) { return (& $no 'the merged patch does not apply') }
        [IO.File]::WriteAllText($OutPath, $merged)
        [pscustomobject]@{ Ok = $true; Path = $OutPath; Files = @($toMerge | ForEach-Object { $_.Path }); Reason = '' }
    } finally { Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue }
}
# The id register's side of ORDERED-BY-MERGE (kit item IN-20261023221543-c537): the ids a patch's added lines allocate
# in an id register file ($script:AllocatorFileRx: 'event: allocate' ... 'id: <id>') that main's copy of that file
# already allocates, or that the patch allocates twice. Two rows numbering the same next id in parallel both append
# cleanly, so this is checked before the apply; Integrate-Patch.ps1 sends such a row back to rebase (re-number).
function Get-AllocatorDuplicates([string] $Repo, [string] $PatchPath) {
    $rx = '^\s*-\s*\{\s*event:\s*allocate\b.*?\bid:\s*([^,}\s]+)'
    $raw = [IO.File]::ReadAllText($PatchPath)
    $dups = [Collections.Generic.List[string]]::new()
    foreach ($sec in @([regex]::Split($raw, '(?m)^(?=diff --git )') | Where-Object { $_ -match '^diff --git ' })) {
        $path = if ($sec -match '^diff --git a/(.+?) b/(.+?)\r?\n') { $Matches[2] } else { '' }
        if ($path -notmatch $script:AllocatorFileRx) { continue }
        $have = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $full = Join-Path $Repo $path
        if (Test-Path -LiteralPath $full) { foreach ($l in [IO.File]::ReadAllLines($full)) { if ($l -match $rx) { [void]$have.Add($Matches[1]) } } }
        foreach ($pl in ($sec -split "`n")) {
            if (-not $pl.StartsWith('+') -or $pl.StartsWith('+++')) { continue }
            if ($pl.Substring(1).TrimEnd("`r") -match $rx -and -not $have.Add($Matches[1]) -and -not $dups.Contains($Matches[1])) { $dups.Add($Matches[1]) }
        }
    }
    $dups.ToArray()
}# A write-set index for comparing many rows at once (Add-Tasks.ps1: every new row against every open row). An entry
# with no wildcard character and no trailing '/' overlaps another such entry only when the two are equal ignoring case,
# which is all Test-WriteSetOverlap can find for that pair, so those go in a dictionary; a row with any pattern or
# directory entry is kept aside and always compared in full. Get-WriteSetCandidates returns the rows a write set can
# overlap (a superset: the caller still runs Test-WriteSetOverlap on each), or $null when the write set itself holds a
# pattern and every row must be compared. An 81-row release on the 1016-row board spent ~15 s of its lock hold in the
# full pairwise comparison (kit item IN-20261010181957-2e7f).
function Test-WriteSetPatternEntry([string] $Normalised) { $Normalised.EndsWith('/') -or $Normalised -match '[*?\[\]`]' }
function New-WriteSetIndex {
    @{ Exact = [Collections.Generic.Dictionary[string, Collections.Generic.List[object]]]::new([StringComparer]::OrdinalIgnoreCase)
       Pattern = [Collections.Generic.List[object]]::new() }
}
function Add-WriteSetIndex($Index, $Row) {
    $isPattern = $false
    foreach ($w in @($Row.writeSet)) {
        $n = ([string]$w -replace '\\', '/') -replace '^\./', ''
        if (Test-WriteSetPatternEntry $n) { $isPattern = $true; continue }
        if (-not $Index.Exact.ContainsKey($n)) { $Index.Exact[$n] = [Collections.Generic.List[object]]::new() }
        $Index.Exact[$n].Add($Row)
    }
    if ($isPattern) { $Index.Pattern.Add($Row) }
}
function Get-WriteSetCandidates($Index, $WriteSet) {
    $set = [Collections.Generic.HashSet[object]]::new([Collections.Generic.ReferenceEqualityComparer]::Instance)
    foreach ($w in @($WriteSet)) {
        $n = ([string]$w -replace '\\', '/') -replace '^\./', ''
        if (Test-WriteSetPatternEntry $n) { return $null }
        if ($Index.Exact.ContainsKey($n)) { foreach ($r in $Index.Exact[$n]) { [void]$set.Add($r) } }
    }
    foreach ($r in $Index.Pattern) { [void]$set.Add($r) }
    , $set
}

# True when task $From reaches task $ToId through dependsOn (transitively). $Tasks is every known task, new ones included.
# Two tasks on one dependency chain may share files: the later one builds on the earlier one's patch and the
# integrator applies them in dependency order, so their edits never race.
# The main tree is single-writer. .streams\main-grader.lock is held for the whole of any main-tree build AND for any
# write to main, so a grader never compiles a tree that is being rewritten under it: on 2026-09-29 a G6.T025 RED run
# read error CS1061 for a member HEAD declares, because Tests.Unit compiled against an Application assembly that
# predated an integrator's apply (kit item IN-20260929183913-7850). Returns the held FileStream, or $null when the
# lock could not be taken inside $WaitSeconds; the caller decides what a busy tree means. Opened DeleteOnClose, so a
# crashed holder frees it. Dispose the stream to release.
function Enter-MainTreeLock($P, [string] $Holder, [int] $WaitSeconds = 3600) {
    $lockPath = Join-Path $P.Root 'main-grader.lock'
    if ($env:STREAM_MAIN_LOCK_WAIT_SECONDS) { $WaitSeconds = [int]$env:STREAM_MAIN_LOCK_WAIT_SECONDS }
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    while ($true) {
        try {
            $fs = [IO.FileStream]::new($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose)
            $b = [Text.Encoding]::UTF8.GetBytes("$Holder pid $PID at $(Get-Now)"); $fs.Write($b, 0, $b.Length); $fs.Flush()
            return $fs
        } catch [IO.IOException] {
            if ((Get-Date) -gt $deadline) { return $null }
            Start-Sleep -Seconds 5
        }
    }
}

# The holder text of main-grader.lock. The holder opens it DeleteOnClose with FileShare.Read, so the reader must share
# Write and Delete back: Get-Content shares ReadWrite only and fails on a held lock, which printed 'held by: ?'.
function Read-MainTreeLockText($P) {
    $fs = [IO.FileStream]::new((Join-Path $P.Root 'main-grader.lock'), [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete)
    try { ([IO.StreamReader]::new($fs)).ReadToEnd().Trim() } finally { $fs.Dispose() }
}
function Get-MainTreeLockHolder($P) { try { Read-MainTreeLockText $P } catch { '?' } }

# The patch an integrator grade holds on main, when the main-grader.lock holder is exactly that grade: the holder text
# reads '<task> main pid <n> at <t>' (Invoke-Grader -Label main) and .streams\main-pending.json (Integrate-Patch, written
# after the apply) names the same task and a patch that exists. Returns @{ task; patch; holder }, or $null for any other
# holder. A grade writes no tracked file, so main can be read beside it with that patch reversed out of the copy (kit
# item IN-20261024221200-772a); the caller re-reads the holder after its read and gives up if it changed.
function Get-GradePendingPatch($P) {
    $holder = Get-MainTreeLockHolder $P
    if ($holder -notmatch '^(\S+) main pid \d+ at \S+$') { return $null }
    $task = $Matches[1]
    $mf = Join-Path $P.Root 'main-pending.json'
    if (-not (Test-Path -LiteralPath $mf)) { return $null }
    try { $m = Get-Content -LiteralPath $mf -Raw | ConvertFrom-Json -AsHashtable } catch { return $null }
    if ($m['task'] -ne $task -or -not $m['patch'] -or -not (Test-Path -LiteralPath $m['patch'])) { return $null }
    @{ task = $task; patch = [string]$m['patch']; holder = $holder }
}

# Who holds the main-grader lock and for how long, or $null when it is free. The lock is opened with FileShare.Read, so
# the holder text ('<holder> pid <n> at <utc>') can be read while it is held. Age comes from that 'at', or from the
# file's creation time when the text has none. On 2026-10-02 G2 suite runs held the lock about 9 of 15 hours and author
# releases fell from 16-20/h to 0-7/h with nothing on the board showing either (kit item IN-20261002161450-c89b).
$script:MainLockFlagMinutes = 20
function Get-MainTreeLockState($P, [datetime] $Now = (Get-Date).ToUniversalTime()) {
    $path = Join-Path $P.Root 'main-grader.lock'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $text = ''
    try { $text = Read-MainTreeLockText $P } catch { }
    $since = $null
    $m = [regex]::Match($text, ' at (\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ)$')
    if ($m.Success) { $since = [datetime]::Parse($m.Groups[1].Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }
    else { try { $since = (Get-Item -LiteralPath $path).CreationTimeUtc } catch { return $null } }
    [ordered]@{ holder = $(if ($text) { $text } else { '?' }); since = $since.ToString('yyyy-MM-ddTHH:mm:ssZ'); minutes = [int][math]::Floor(($Now - $since).TotalMinutes) }
}

# Author releases (planned -> ticketed) per hour over the last $Hours hours, oldest hour first. A release is a history
# entry that moves a non-gate row to ticketed straight after an entry that left it planned; a gate row advanced with no
# ticket is not authoring and does not count. Windows are whole hours back from $Now, not clock hours. Returns a dictionary,
# not a bare array, so a caller's @() cannot nest it.
function Get-ReleasesPerHour($doc, [int] $Hours = 6, [datetime] $Now = (Get-Date).ToUniversalTime()) {
    $counts = [int[]]::new($Hours)
    foreach ($t in $doc.tasks) {
        if ($t.kind -eq 'gate') { continue }
        $h = @($t.history)
        for ($i = 1; $i -lt $h.Count; $i++) {
            if ($h[$i].to -ne 'ticketed' -or $h[$i - 1].to -ne 'planned') { continue }
            $raw = $h[$i].at
            $at = if ($raw -is [datetime]) { $raw.ToUniversalTime() } else { [datetime]::Parse([string]$raw, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }
            $ago = ($Now - $at).TotalHours
            if ($ago -lt 0 -or $ago -ge $Hours) { continue }
            $counts[$Hours - 1 - [int][math]::Floor($ago)]++
        }
    }
    [ordered]@{ hours = $Hours; perHour = $counts; total = [int]($counts | Measure-Object -Sum).Sum }
}

# $ById (from Get-TaskIndex) skips rebuilding the id table over the whole board on every call: Add-Tasks.ps1 asks this
# for many pairs under the tasks.json lock, and an 81-row release ran 15 min there (kit item IN-20261010174706-ed53).
# The table holds the task objects themselves, so a dependsOn edit made after it was built is still seen.
function Get-TaskIndex($Tasks) {
    $byId = @{}; foreach ($x in @($Tasks)) { if ($x) { $byId[[string]$x['id']] = $x } }
    $byId
}

function Test-DependsOnChain($Tasks, $From, [string] $ToId, [hashtable] $ById = $null) {
    # tasks arrive as hashtables that may lack a dependsOn key, and strict mode refuses a missing key via dot access
    function DepsOf($x) { if ($x -is [Collections.IDictionary]) { if ($x.Contains('dependsOn')) { @($x['dependsOn']) } else { @() } } else { @($x.dependsOn) } }
    $byId = if ($null -ne $ById) { $ById } else { Get-TaskIndex $Tasks }
    $seen = @{}; $stack = [Collections.Generic.Stack[string]]::new()
    foreach ($d in DepsOf $From) { if ($d) { $stack.Push($d) } }
    while ($stack.Count) {
        $id = $stack.Pop()
        if ($id -eq $ToId) { return $true }
        if ($seen[$id]) { continue }; $seen[$id] = $true
        if ($byId[$id]) { foreach ($d in DepsOf $byId[$id]) { if ($d) { $stack.Push($d) } } }
    }
    $false
}

function Invoke-Git([string] $Dir, [string[]] $GitArgs) {
    $out = & git -C $Dir @GitArgs 2>&1
    if ($LASTEXITCODE -ne 0) { throw "git $($GitArgs -join ' ') failed in ${Dir}: $($out -join "`n")" }
    $out
}

# OWNER WAKE FILES (kit item IN-20261020102535-b7f2), beside the STOP files: .streams\runners\WAKE (every runner),
# WAKE-<role> and WAKE-<runner id>. A wake is never deleted when seen: each runner keeps the newest write time it has
# acted on ($Seen, ticks), so one touch wakes every runner of the role. A runner starts with $Seen at the newest file
# already there, so a wake older than the runner wakes nothing. A file whose first line is 'force' also skips the gate
# once; its second line is the reason. Get-WakeRequest returns @{ file; force; reason; ticks } for the newest wake past
# $Seen, else $null.
function Get-WakeFiles($P, [string] $Role, [string] $RunnerId) {
    $dir = Join-Path $P.Root 'runners'
    Join-Path $dir 'WAKE'
    Join-Path $dir "WAKE-$Role"
    if ($RunnerId) { Join-Path $dir "WAKE-$RunnerId" }
}
function Get-WakeRequest($P, [string] $Role, [string] $RunnerId, [long] $Seen) {
    $best = $null
    foreach ($f in @(Get-WakeFiles $P $Role $RunnerId)) {
        if (-not (Test-Path -LiteralPath $f)) { continue }
        $t = (Get-Item -LiteralPath $f).LastWriteTimeUtc.Ticks
        if ($t -le $Seen -or ($best -and $t -le $best.ticks)) { continue }
        $lines = @(try { Get-Content -LiteralPath $f -ErrorAction Stop } catch { @() })
        $best = @{ file = (Split-Path -Leaf $f); force = ([string]($lines | Select-Object -First 1)).Trim() -eq 'force'; reason = ([string]($lines | Select-Object -Skip 1 -First 1)).Trim(); ticks = $t }
    }
    $best
}
function Get-WakeSeen($P, [string] $Role, [string] $RunnerId) {
    $m = 0L
    foreach ($f in @(Get-WakeFiles $P $Role $RunnerId)) { if (Test-Path -LiteralPath $f) { $t = (Get-Item -LiteralPath $f).LastWriteTimeUtc.Ticks; if ($t -gt $m) { $m = $t } } }
    $m
}
