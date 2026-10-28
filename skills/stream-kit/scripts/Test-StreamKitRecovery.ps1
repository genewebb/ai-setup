# Self-test of the kit's recovery paths against throwaway git repos (removed at the end with their worktrees):
# grader identity and since time, grader-suspect vs code-defect on a red main, prior-patch reuse, role inboxes,
# fix tasks after landing, and grader portability. Real scripts, real git; nothing is mocked.
#   pwsh -NoProfile -File Test-StreamKitRecovery.ps1                         every section (about 40 minutes)
#   pwsh -NoProfile -File Test-StreamKitRecovery.ps1 -List                   the section headers, one per line
#   pwsh -NoProfile -File Test-StreamKitRecovery.ps1 -Only '^74\.,^112\.'   only the sections whose header matches
#                                                                            (comma-separated regexes, one argument)
param(
    [string] $Scratch = (Join-Path ([IO.Path]::GetTempPath()) "streamkit-recovery-$PID"),
    [string[]] $Only,
    [switch] $List
)
$ErrorActionPreference = 'Stop'
$S = $PSScriptRoot

# SECTION FILTER (owner 2026-10-17: "why not add a filter to the tests for now and future"). The minutes go into each
# section's setup (throwaway repos, live runners), not into its Case lines, so the filter keeps whole SECTIONS: every
# '    # ---- <id>. <title>' line inside the try block below starts one, which runs to the next. Section ids repeat
# (two 14s, two 22s), so -Only takes regexes matched against the header text after '# ---- ' ('^74\.', 'usage limit').
# The script rebuilds itself from the setup code above the try block, the chosen sections and the cleanup after it,
# and runs that copy BESIDE itself so $PSScriptRoot still finds the kit; the copy is deleted afterwards. A section that
# reuses an earlier section's repo or variables needs that section named too (its cases fail loudly otherwise).
# pwsh -File hands a list over as one string, so commas split it here (a regex therefore cannot contain a comma).
$Only = @($Only | ForEach-Object { "$_" -split ',' } | ForEach-Object { $_.Trim().Trim("'", '"') } | Where-Object { $_ })
if ($Only.Count -or $List) {
    $self = @(Get-Content -LiteralPath $PSCommandPath)
    $tryAt = [Array]::IndexOf($self, 'try {')
    $endAt = [Array]::LastIndexOf($self, '} catch {')
    if ($tryAt -lt 0 -or $endAt -lt $tryAt) { 'FAIL harness: the section filter could not find the try block'; exit 2 }
    $heads = @(for ($i = $tryAt + 1; $i -lt $endAt; $i++) { if ($self[$i] -like '    # ---- *') { $i } })
    $titleOf = { param($at) $self[$at].Trim().Substring('# ---- '.Length) }
    if ($List) { foreach ($h in $heads) { & $titleOf $h }; exit 0 }
    $keep = [Collections.Generic.List[string]]::new()
    $keep.AddRange([string[]]$self[0..$tryAt])
    $picked = 0
    for ($n = 0; $n -lt $heads.Count; $n++) {
        $title = & $titleOf $heads[$n]
        if (-not @($Only | Where-Object { $title -match $_ }).Count) { continue }
        $to = if ($n + 1 -lt $heads.Count) { $heads[$n + 1] - 1 } else { $endAt - 1 }
        $keep.AddRange([string[]]$self[$heads[$n]..$to]); $picked++
        "SECTION $title"
    }
    if (-not $picked) { "FAIL harness: -Only $($Only -join ', ') matched no section header (see -List)"; exit 2 }
    $keep.AddRange([string[]]$self[$endAt..($self.Count - 1)])
    $copy = Join-Path $PSScriptRoot ".recovery-only-$PID.ps1"
    Set-Content -LiteralPath $copy -Value $keep -Encoding utf8
    try { & pwsh -NoProfile -File $copy -Scratch $Scratch; $code = $LASTEXITCODE } finally { Remove-Item -LiteralPath $copy -ErrorAction SilentlyContinue }
    exit $code
}
# The watchdog sweeps the HOST temp folder, so every watchdog run in a self-test is pointed at scratch instead:
# a self-test must never delete a file outside its own scratch (kit item IN-20260929144007-b69a).
$env:STREAM_TEMP_ROOT = Join-Path $Scratch 'hosttemp'
$env:STREAM_SCRATCH_TOP_ROOT = Join-Path $Scratch 'scratchtop-harness'   # the {ScratchRoot} top-level sweep, kept in scratch too
$env:STREAM_WORKTREE_ROOT = Join-Path $Scratch 'wtroot'   # the profile WorktreesRoot stand-in: no host folder is touched
$env:STREAM_SCRATCH_ROOT = Join-Path $Scratch 'streamscratch'   # the {ScratchRoot}\streams stand-in
# Fixtures lay a worktree down and reap it in the same second, so the watchdog's 10-minute quiet period would
# hold every one of them. The cases that test the quiet period set it back themselves.
$env:STREAM_REAP_QUIET_MINUTES = '0'
$env:STREAM_RUNNER_START_JITTER_SECONDS = '0'   # no random start wait for the runner cases
New-Item -ItemType Directory -Path $env:STREAM_TEMP_ROOT -Force | Out-Null
# Integrate-Patch commits and pushes only where the machine profile's Git policy allows it, so every fixture repo gets
# a row in a fixture profile under scratch (AI_MACHINE_CONFIG, the profile module's one input). The Git policy table is
# the file's last table, so a granted row is simply appended to it.
$prevMachineConfig = $env:AI_MACHINE_CONFIG
$env:AI_MACHINE_CONFIG = Join-Path $Scratch 'ProfileMachineConfig.md'
New-Item -ItemType Directory -Path $Scratch -Force | Out-Null
Set-Content -Path $env:AI_MACHINE_CONFIG -Encoding utf8 -Value @"
| Key | Value |
|---|---|
| ScratchRoot | $Scratch |

## Git policy

| Repo | Commit | Push | Worktrees | Note |
|---|---|---|---|---|
"@
Import-Module (Join-Path $S '..\..\..\lib\MachineConfig.psm1') -Force -DisableNameChecking
function Grant-GitPolicy([string] $repo, [string] $commit = 'yes', [string] $push = 'yes') {
    Add-Content -Path $env:AI_MACHINE_CONFIG -Encoding utf8 -Value "| $(Get-AIRepoRoot -Path $repo) | $commit | $push | $commit | fixture |"
}
$fails = 0
function Case([string] $name, [bool] $ok, [string] $detail = '') {
    if ($ok) { "PASS $name" } else { "FAIL $name $detail"; $script:fails++ }
}
function J($repo) { Get-Content -Raw (Join-Path $repo '.streams\tasks.json') | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50 }
function T($repo, $id) { (J $repo).tasks | Where-Object { $_.id -eq $id } }

# A repo with one committed file per task, owner dirt in the main tree, and imported (ticketed) tasks whose graders
# are given as script text.
function New-Repo([string] $name, [Collections.IDictionary] $graders) {
    $repo = Join-Path $Scratch $name
    New-Item -ItemType Directory -Path $repo -Force | Out-Null
    git -C $repo init -q -b main; git -C $repo config user.email t@t; git -C $repo config user.name t; Grant-GitPolicy $repo
    foreach ($id in $graders.Keys) { Set-Content (Join-Path $repo "$id.txt") "$id base" }
    Set-Content (Join-Path $repo 'owner.txt') 'owner base'
    git -C $repo add -A; git -C $repo commit -q -m base
    Set-Content (Join-Path $repo 'owner.txt') 'owner dirty'
    & "$S\Init-Streams.ps1" -Repo $repo | Out-Null
    $tasks = foreach ($id in $graders.Keys) {
        $g = Join-Path $repo ".streams\graders\$id.ps1"; Set-Content -Path $g -Encoding utf8 -Value $graders[$id]
        $k = Join-Path $repo ".streams\tickets\$id.md"; Set-Content $k "ticket $id"
        @{ id = $id; group = 'G1'; title = $id; why = @('AC-1'); kind = 'code'; writeSet = @("$id.txt"); dependsOn = @(); estMinutes = 5
           artifacts = @{ ticket = ".streams\tickets\$id.md"; grader = ".streams\graders\$id.ps1"; patch = $null; verdict = $null } }
    }
    $f = Join-Path $Scratch "$name.json"
    @{ groups = @(@{ id = 'G1'; name = 'R'; state = 'released'; origin = 'import' }); tasks = @($tasks) } | ConvertTo-Json -Depth 10 | Set-Content $f
    & "$S\Add-Tasks.ps1" -Repo $repo -Role plan -Session plan-1 -File $f | Out-Null
    $repo
}
# A timed role (integrate, plan, kit, coordinator, status) launches a unit only when its gate finds work (owner ruling
# 2026-10-17). A case that needs one live unit of such a role opens the gate with one open inbox item; timed roles do
# not take items at launch, so the item stays open for every later launch in the same repo.
function Open-Gate([string] $repo, [string] $to) {
    [void](& "$S\Send-InboxItem.ps1" -Repo $repo -To $to -From test-gate -Kind request -Ask 'test: open the gate for a live unit')
}
# Claims, builds (writes $content into <id>.txt), runs the grader in the worktree, exports and hands off as built.
function Build([string] $repo, [string] $id, [string] $content, [string] $sess) {
    $c = & "$S\Claim-Task.ps1" -Repo $repo -Role build -Session $sess | ConvertFrom-Json
    if ($c.id -ne $id) { throw "expected to claim $id, got $($c.id)" }
    $wt = & "$S\New-TaskWorktree.ps1" -Repo $repo -Task $id -Session $sess -WorktreeRoot (Join-Path $Scratch 'wt') | Select-Object -Last 1
    Set-Content (Join-Path $wt "$id.txt") $content
    & "$S\Invoke-Grader.ps1" -Repo $repo -Task $id -Root $wt -Label wt | Out-Null
    & "$S\Export-TaskPatch.ps1" -Repo $repo -Task $id -Worktree $wt | Out-Null
    & "$S\Update-Task.ps1" -Repo $repo -Task $id -Role build -Session $sess -To built -Release -Artifacts @{ patch = ".streams\patches\$id.patch"; verdict = 'PASS' } | Out-Null
    $wt
}
function ContentGrader([string] $id, [string] $needle) {
    "param([string]`$Root)`nif ((Get-Content -Raw (Join-Path `$Root '$id.txt')) -match '$needle') { 'PASS C1'; exit 0 } else { 'FAIL C1: $id.txt lacks $needle'; exit 1 }"
}

New-Item -ItemType Directory -Path $Scratch -Force | Out-Null
$repos = @()
try {
    # ---- 1. grader identity + since: the log ends with the grader hash and the kit's since time
    $echo = "param([string]`$Root)`n'SINCE=' + `$env:STREAM_SINCE_UTC`n'TASK=' + `$env:STREAM_TASK`nif ((Get-Content -Raw (Join-Path `$Root 'G1.A.txt')) -match 'done') { 'PASS C1'; exit 0 } else { 'FAIL C1: not done'; exit 1 }"
    $r1 = New-Repo 'r1' @{ 'G1.A' = $echo }; $repos += $r1
    & "$S\Invoke-Grader.ps1" -Repo $r1 -Task G1.A -Root $r1 -Label red -ExpectRed | Out-Null
    $log = Get-Content (Join-Path $r1 '.streams\logs\G1.A.grader.red.txt')
    Case 'grader log ends with GRADER sha line' ($log[-1] -match '^GRADER sha [0-9A-F]{16} since -$') ($log[-1])
    Case 'grader sees STREAM_TASK' (($log -join ' ') -match 'TASK=G1\.A')
    $wtA = Build $r1 'G1.A' 'done' 'build-1'
    $wlog = Get-Content (Join-Path $r1 '.streams\logs\G1.A.grader.wt.txt')
    Case 'build-time since is set from the claim' (($wlog -join ' ') -match 'SINCE=\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ' -and $wlog[-1] -match 'since \d{4}-') (($wlog | Where-Object { $_ -like 'SINCE=*' -or $_ -like 'GRADER*' }) -join ' ')

    # ---- 2. green integration still commits exactly the patch paths (live commit feature, untouched by recovery)
    $o = & "$S\Integrate-Patch.ps1" -Repo $r1 -Session integ-1
    Case 'green patch integrates and commits' ($o[0] -eq 'INTEGRATED G1.A' -and $o[1] -like 'COMMITTED G1.A *') ($o -join ' | ')
    Case 'owner dirt stays uncommitted' ((git -C $r1 status --porcelain) -match 'owner\.txt')

    # ---- 3. grader-suspect: red on main only, same clause PASS in the worktree, identical content
    $wtOnly = "param([string]`$Root)`nif (`$Root -like '*\wt\*') { 'PASS C1'; 'PASS C2'; exit 0 } else { 'PASS C1'; 'FAIL C2: tree-local check'; exit 1 }"
    $codeBad = ContentGrader 'G1.C' 'right'
    $r2 = New-Repo 'r2' ([ordered]@{ 'G1.B' = $wtOnly; 'G1.C' = $codeBad }); $repos += $r2
    $wtB = Build $r2 'G1.B' 'B done' 'build-1'
    $before = Get-Content -Raw (Join-Path $r2 'G1.B.txt')
    $o = & "$S\Integrate-Patch.ps1" -Repo $r2 -Session integ-1 -Task G1.B
    $tb = T $r2 'G1.B'
    Case 'grader-only red is SUSPECT' ("$o" -eq 'SUSPECT G1.B') "$o"
    Case 'suspect task goes to planned' ($tb.state -eq 'planned') $tb.state
    Case 'suspect keeps the patch' ($tb.artifacts.patch -eq '.streams\patches\G1.B.patch' -and (Test-Path (Join-Path $r2 '.streams\patches\G1.B.patch')))
    Case 'suspect reverses main' ((Get-Content -Raw (Join-Path $r2 'G1.B.txt')) -eq $before)
    Case 'suspect logs an owner question' ((Get-Content -Raw (Join-Path $r2 '.streams\owner\questions.md')) -match 'G1\.B \| grader red on main only \(C2\)')
    Case 'suspect names the red clause in history' ($tb.history[-1].note -match '^grader-suspect: C2 red on main')

    # ---- 4. code defect: red in the worktree too -> REVERSED to ticketed, patch kept
    $wtC = Build $r2 'G1.C' 'wrong' 'build-2'
    $o = & "$S\Integrate-Patch.ps1" -Repo $r2 -Session integ-1 -Task G1.C
    $tc = T $r2 'G1.C'
    Case 'real defect is REVERSED' ("$o" -eq 'REVERSED G1.C' -and $tc.state -eq 'ticketed') "$o $($tc.state)"
    Case 'reversal says why it is not a grader defect' ($tc.history[-1].note -match 'not a grader defect: clauses C1 did not pass in the worktree')

    # ---- 5. prior-patch reuse: a fresh worktree starts from the kept patch
    $c = & "$S\Claim-Task.ps1" -Repo $r2 -Role build -Session build-3 | ConvertFrom-Json
    $wtC2 = & "$S\New-TaskWorktree.ps1" -Repo $r2 -Task G1.C -Session build-3 -WorktreeRoot (Join-Path $Scratch 'wt') | Select-Object -Last 1
    $x = & "$S\Restore-TaskPatch.ps1" -Repo $r2 -Task G1.C -Worktree $wtC2
    Case 'prior patch APPLIED on a fresh worktree' ($LASTEXITCODE -eq 0 -and "$x" -match '^APPLIED ') "$x"
    Case 'reused change is unstaged, base staged' ((git -C $wtC2 diff --name-only) -contains 'G1.C.txt' -and (Get-Content -Raw (Join-Path $wtC2 'G1.C.txt')).Trim() -eq 'wrong')
    Case 'prior patch copy kept' (@(Get-ChildItem (Join-Path $r2 '.streams\patches') -Filter 'G1.C.prior.*.patch').Count -eq 1)
    Set-Content (Join-Path $wtC2 'G1.C.txt') 'conflicting base'; git -C $wtC2 add -A
    $x = & "$S\Restore-TaskPatch.ps1" -Repo $r2 -Task G1.C -Worktree $wtC2
    Case 'patch that no longer applies is CONFLICT, nothing written' ($LASTEXITCODE -eq 2 -and (Get-Content -Raw (Join-Path $wtC2 'G1.C.txt')).Trim() -eq 'conflicting base') "$x"
    $x = & "$S\Restore-TaskPatch.ps1" -Repo $r1 -Task G1.A -Worktree $wtA
    $doc = J $r1; ($doc.tasks | Where-Object { $_.id -eq 'G1.A' }).artifacts.patch = $null; $doc | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r1 '.streams\tasks.json')
    $x = & "$S\Restore-TaskPatch.ps1" -Repo $r1 -Task G1.A -Worktree $wtA
    Case 'no prior patch is NO-PRIOR' ($LASTEXITCODE -eq 1 -and "$x" -eq 'NO-PRIOR') "$x"

    # ---- 6. inboxes: init creates them, send/list, the take-guard, holder-only close, forward
    $r4 = Join-Path $Scratch 'r4'; New-Item -ItemType Directory -Path $r4 -Force | Out-Null; $repos += $r4
    git -C $r4 init -q -b main; & "$S\Init-Streams.ps1" -Repo $r4 | Out-Null
    $ibx = Join-Path $r4 '.streams\inbox'
    Case 'init creates six inboxes and an evidence folder' (@(Get-ChildItem $ibx -Filter 'stream-*.md').Count -eq 6 -and (Test-Path (Join-Path $ibx 'evidence')))
    Case 'inbox header names its skill' ((Get-Content -Raw (Join-Path $ibx 'stream-build.md')) -match '# Inbox: stream-build' -and (Get-Content -Raw (Join-Path $ibx 'stream-build.md')) -notmatch '\{\{')
    $x = & "$S\Send-InboxItem.ps1" -Repo $r4 -To stream-author -From owner -Kind bug -Task G1.T1 -Ask "fix | the`ngrader"
    $id = ("$x" -split ' ')[1]
    Case 'send prints the new id' ("$x" -match '^SENT IN-\d{14}-[0-9a-f]{4} stream-author$') "$x"
    $line = @(Get-Content (Join-Path $ibx 'stream-author.md') | Where-Object { $_ -like "- $id *" })
    Case 'one item is one line, pipes and breaks flattened' ($line.Count -eq 1 -and $line[0] -match 'fix / the grader') ($line -join ' // ')
    $x = & "$S\Get-InboxItems.ps1" -Repo $r4 -Skill stream-author -Open
    Case 'open item listed' ("$x" -like "$id | open *") "$x"
    $jobs = 1..3 | ForEach-Object { $n = $_; Start-Job -ScriptBlock { param($s, $r, $i, $n) & "$s\Set-InboxItem.ps1" -Repo $r -Skill stream-author -Id $i -Status taken -By "author-$n"; $LASTEXITCODE } -ArgumentList $S, $r4, $id, $n }
    $res = $jobs | Wait-Job | Receive-Job; $jobs | Remove-Job
    $won = @($res | Where-Object { "$_" -like 'ok *' })
    Case 'parallel takes: exactly one wins' ($won.Count -eq 1 -and @($res | Where-Object { "$_" -like 'ALREADY *' }).Count -eq 2) ($res -join ' / ')
    $holder = (@(Get-Content (Join-Path $ibx 'stream-author.md') | Where-Object { $_ -like "- $id * | taken | *" })[0] -split ' \| ')[2]
    $x = & "$S\Set-InboxItem.ps1" -Repo $r4 -Skill stream-author -Id $id -Status done -By 'someone-else' -Note 'x'
    Case 'done by a non-holder is refused' ($LASTEXITCODE -eq 8 -and "$x" -like 'NOT-HELD*') "$x"
    & "$S\Set-InboxItem.ps1" -Repo $r4 -Skill stream-author -Id $id -Status done -By $holder -Note 'fixed' | Out-Null
    $x = & "$S\Set-InboxItem.ps1" -Repo $r4 -Skill stream-author -Id $id -Status taken -By 'late-author'
    Case 'take after done is refused' ($LASTEXITCODE -eq 8 -and "$x" -like 'ALREADY*done*') "$x"
    Case 'done item no longer open' ((& "$S\Get-InboxItems.ps1" -Repo $r4 -Skill stream-author -Open) -eq 'NONE')
    $x = & "$S\Send-InboxItem.ps1" -Repo $r4 -To stream-build -From owner -Kind request -Ask 'needs a grader'
    $id2 = ("$x" -split ' ')[1]
    & "$S\Set-InboxItem.ps1" -Repo $r4 -Skill stream-build -Id $id2 -Status taken -By build-1 | Out-Null
    $x = & "$S\Set-InboxItem.ps1" -Repo $r4 -Skill stream-build -Id $id2 -Status forwarded -By build-1 -ForwardTo stream-author -Note 'grader work'
    $fwd = & "$S\Get-InboxItems.ps1" -Repo $r4 -Skill stream-author -Open
    Case 'forward opens the same id in the target inbox' ($LASTEXITCODE -eq 0 -and "$fwd" -like "$id2 | open *needs a grader*") "$fwd"
    Case 'forwarded item not open at the source' ((& "$S\Get-InboxItems.ps1" -Repo $r4 -Skill stream-build -Open) -eq 'NONE')
    $d = J $r4; $d.groups = @(@{ id = 'G1'; name = 'x'; state = 'released' }); $d | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r4 '.streams\tasks.json')
    $st = & "$S\Get-StreamStatus.ps1" -Repo $r4
    Case 'status shows open inbox counts' (@($st | Where-Object { $_ -like 'inbox: *' }).Count -eq 1 -and ($st -join ' ') -match 'author 1') ($st -join ' / ')

    # ---- 7. fix tasks after landing: chained onto an integrated task, integration task and closed group reopened
    $r3 = New-Repo 'r3' @{ 'G1.D' = (ContentGrader 'G1.D' 'done') }; $repos += $r3
    $d = J $r3
    ($d.tasks | Where-Object { $_.id -eq 'G1.D' }).state = 'integrated'
    $d.tasks = @($d.tasks) + @([ordered]@{ id = 'G1.T9'; group = 'G1'; title = 'suites'; why = @('AC-1'); kind = 'integration'; writeSet = @(); dependsOn = @('G1.D'); estMinutes = 5; state = 'done'; claim = $null; artifacts = @{}; history = @() })
    ($d.groups | Where-Object { $_.id -eq 'G1' }).state = 'closed'
    $d | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r3 '.streams\tasks.json')
    $fx = Join-Path $Scratch 'gatefix.json'
    @{ tasks = @(@{ id = 'G1.F1'; group = 'G1'; title = 'gate fail'; why = @('AC-1'); kind = 'code'; writeSet = @('G1.D.txt'); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $fx
    $x = & "$S\Add-Tasks.ps1" -Repo $r3 -Role integrate -Session integ-1 -File $fx
    $f1 = T $r3 'G1.F1'
    Case 'fix on an integrated task is its own task, chained after it' ($f1 -and $f1.state -eq 'planned' -and @($f1.dependsOn) -contains 'G1.D' -and ($x -join ' ') -match 'CHAINED G1.F1 after G1.D') ($x -join ' / ')
    Case 'done integration task reopened' ((T $r3 'G1.T9').state -eq 'ticketed' -and ($x -join ' ') -match 'REOPENED G1.T9')
    Case 'closed group reopened to integrating' (((J $r3).groups | Where-Object { $_.id -eq 'G1' }).state -eq 'integrating')

    # ---- 8. portability lint
    $callee = Join-Path $Scratch 'callee.ps1'
    Set-Content $callee "param([string]`$Repo, [string] `$Since = '')`n`$t = (Get-Item `$Repo).LastWriteTimeUtc`n`$r = Join-Path `$Repo '.loop\rows\x.json'"
    $shim = Join-Path $Scratch 'shim.ps1'
    Set-Content $shim "param([string]`$Root)`n& pwsh -NoProfile -File '$callee' -Repo `$Root"
    $x = & "$S\Test-GraderPortability.ps1" -Grader $shim
    Case 'lint flags MTIME, LOOP-STATE and SINCE-UNSET' ($LASTEXITCODE -eq 1 -and ($x -join ' ') -match 'FLAG MTIME' -and ($x -join ' ') -match 'FLAG LOOP-STATE' -and ($x -join ' ') -match 'FLAG SINCE-UNSET') ($x -join ' / ')
    Set-Content $shim "param([string]`$Root)`n# portable: MTIME,LOOP-STATE fallback only; -Since is always passed`n& pwsh -NoProfile -File '$callee' -Repo `$Root -Since `$env:STREAM_SINCE_UTC"
    $x = & "$S\Test-GraderPortability.ps1" -Grader $shim
    Case 'waived and fixed grader is PORTABLE' ($LASTEXITCODE -eq 0 -and ($x -join ' ') -match 'WAIVED MTIME' -and ($x -join ' ') -match 'PORTABLE') ($x -join ' / ')

    # ---- 8b. regression: a built task whose base lacks 'at' (builders write {deps, fingerprint, head}) integrates
    $r5 = New-Repo 'r5' @{ 'G1.E' = (ContentGrader 'G1.E' 'done') }; $repos += $r5
    [void](Build $r5 'G1.E' 'E done' 'build-1')
    $d = J $r5; $te = $d.tasks | Where-Object { $_.id -eq 'G1.E' }; $te.base = [ordered]@{ deps = @(); fingerprint = 'x'; head = 'y' }
    $d | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r5 '.streams\tasks.json')
    $o = & "$S\Integrate-Patch.ps1" -Repo $r5 -Session integ-1
    Case 'base without at still integrates' ($o[0] -eq 'INTEGRATED G1.E') ($o -join ' | ')
    # a grader that throws on main is reversed, never left applied
    $r6 = New-Repo 'r6' @{ 'G1.G' = "param([string]`$Root)`nif (`$Root -like '*\wt\*') { 'PASS C1'; exit 0 } else { throw 'boom' }" }; $repos += $r6
    [void](Build $r6 'G1.G' 'G done' 'build-1')
    $o = & "$S\Integrate-Patch.ps1" -Repo $r6 -Session integ-1
    Case 'crashing grader on main: task bounced, main untouched' (((T $r6 'G1.G').state -in 'ticketed', 'planned') -and -not (git -C $r6 status --porcelain -- G1.G.txt)) (($o -join ' | ') + " state=$((T $r6 'G1.G').state)")

    # ---- 8c. widening: a builder may widen onto a landed task's file, never onto an unordered open task's file
    $r7 = New-Repo 'r7' @{ 'G1.H' = (ContentGrader 'G1.H' 'done'); 'G1.I' = (ContentGrader 'G1.I' 'done'); 'G1.J' = (ContentGrader 'G1.J' 'done') }; $repos += $r7
    $c = & "$S\Claim-Task.ps1" -Repo $r7 -Role build -Session build-7 | ConvertFrom-Json
    $landed = $c.id
    $wt7 = & "$S\New-TaskWorktree.ps1" -Repo $r7 -Task $landed -Session build-7 -WorktreeRoot (Join-Path $Scratch 'wt') | Select-Object -Last 1
    Set-Content (Join-Path $wt7 "$landed.txt") "$landed done"
    & "$S\Invoke-Grader.ps1" -Repo $r7 -Task $landed -Root $wt7 -Label wt | Out-Null
    & "$S\Export-TaskPatch.ps1" -Repo $r7 -Task $landed -Worktree $wt7 | Out-Null
    & "$S\Update-Task.ps1" -Repo $r7 -Task $landed -Role build -Session build-7 -To built -Release -Artifacts @{ patch = ".streams\patches\$landed.patch"; verdict = 'PASS' } | Out-Null
    [void](& "$S\Integrate-Patch.ps1" -Repo $r7 -Session integ-7)
    $c2 = & "$S\Claim-Task.ps1" -Repo $r7 -Role build -Session build-8 | ConvertFrom-Json
    $open = @('G1.H', 'G1.I', 'G1.J' | Where-Object { $_ -notin @($landed, $c2.id) })[0]
    $o = & "$S\Update-Task.ps1" -Repo $r7 -Task $c2.id -Role build -Session build-8 -AddWriteSet "$landed.txt"; $code = $LASTEXITCODE
    Case 'widening onto an integrated task''s file is accepted' ($code -eq 0 -and ((T $r7 $c2.id).writeSet -contains "$landed.txt")) ("exit $code $o; landed=$landed state=$((T $r7 $landed).state)")
    $o = & "$S\Update-Task.ps1" -Repo $r7 -Task $c2.id -Role build -Session build-8 -AddWriteSet "$open.txt"; $code = $LASTEXITCODE
    Case 'widening onto an unordered open task''s file is refused' ($code -eq 7 -and -not ((T $r7 $c2.id).writeSet -contains "$open.txt")) ("exit $code $o")

    # ---- 8c2. AUTHOR WIDENING (owner ruling 2026-10-17, "authors widen their own set"): 234 of 291 author blocks on the
    # speedmerchants board were write-set leaks found by the skeptic, each costing a unit and a plan round. An author
    # widens its claimed row the way a builder does, under the same overlap rule; the plan role still has Revise-Task.
    $r7a = New-Repo 'r7a' @{ 'G1.N' = (ContentGrader 'G1.N' 'done'); 'G1.O' = (ContentGrader 'G1.O' 'done') }; $repos += $r7a
    $d7a = J $r7a; foreach ($x in $d7a.tasks) { $x.state = 'planned'; $x.claim = $null }; $d7a | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r7a '.streams\tasks.json')
    $ca = & "$S\Claim-Task.ps1" -Repo $r7a -Role author -Session author-7 | ConvertFrom-Json
    $otherA = @('G1.N', 'G1.O' | Where-Object { $_ -ne $ca.id })[0]
    $o = & "$S\Update-Task.ps1" -Repo $r7a -Task $ca.id -Role author -Session author-7 -AddWriteSet 'docs/new-page.md' -Note 'the ticket needs a help page'; $code = $LASTEXITCODE
    $dec7a = if (Test-Path (Join-Path $r7a '.streams\decisions.md')) { Get-Content (Join-Path $r7a '.streams\decisions.md') -Raw } else { '' }
    Case 'author widening onto a free file is accepted and logged to decisions.md' ($code -eq 0 -and ((T $r7a $ca.id).writeSet -contains 'docs/new-page.md') -and ($dec7a -match 'write set widened \(auto-accepted\): docs/new-page.md')) ("exit $code $o")
    $o = & "$S\Update-Task.ps1" -Repo $r7a -Task $ca.id -Role author -Session author-7 -AddWriteSet "$otherA.txt"; $code = $LASTEXITCODE
    Case 'author widening onto an unordered open task''s file is refused' ($code -eq 7 -and -not ((T $r7a $ca.id).writeSet -contains "$otherA.txt")) ("exit $code $o")
    $o = & "$S\Update-Task.ps1" -Repo $r7a -Task $ca.id -Role plan -Session plan-7 -AddWriteSet 'x.txt'; $code = $LASTEXITCODE
    Case 'widening by the plan role is still refused' ($code -eq 2 -and (($o -join ' ') -match 'REFUSED -AddWriteSet')) ("exit $code $o")

    # ---- 8d. status liveness: a builder seen only through a fresh claim beat, and an integrator only through a fresh
    #          lock beat, are not flagged as absent (history is 2 hours old)
    $r8 = New-Repo 'r8' @{ 'G1.K' = (ContentGrader 'G1.K' 'done'); 'G1.L' = (ContentGrader 'G1.L' 'done'); 'G1.M' = (ContentGrader 'G1.M' 'done') }; $repos += $r8
    $b8 = (& "$S\Claim-Task.ps1" -Repo $r8 -Role build -Session build-9 | ConvertFrom-Json).id
    $wt8 = & "$S\New-TaskWorktree.ps1" -Repo $r8 -Task $b8 -Session build-9 -WorktreeRoot (Join-Path $Scratch 'wt') | Select-Object -Last 1
    Set-Content (Join-Path $wt8 "$b8.txt") "$b8 done"
    & "$S\Export-TaskPatch.ps1" -Repo $r8 -Task $b8 -Worktree $wt8 | Out-Null
    & "$S\Update-Task.ps1" -Repo $r8 -Task $b8 -Role build -Session build-9 -To built -Release -Artifacts @{ patch = ".streams\patches\$b8.patch"; verdict = 'PASS' } | Out-Null
    [void](& "$S\Claim-Task.ps1" -Repo $r8 -Role build -Session build-9)
    $old = (Get-Date).ToUniversalTime().AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $fresh = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $d = J $r8
    foreach ($x in $d.tasks) { foreach ($h in @($x.history)) { $h.at = $old }; if ($x.claim) { $x.claim.at = $old; $x.claim.beat = $fresh } }
    $d | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r8 '.streams\tasks.json')
    $st8 = & "$S\Get-StreamStatus.ps1" -Repo $r8
    Case 'builder with only a fresh claim beat is not flagged absent' (-not (($st8 -join ' ') -match 'no build session seen')) ($st8 -join ' | ')
    Case 'built task and no integrator at all is flagged' (($st8 -join ' ') -match 'no integrate session seen') ($st8 -join ' | ')
    @{ session = 'integ-9'; at = $old; beat = $fresh } | ConvertTo-Json | Set-Content (Join-Path $r8 '.streams\integrator.lock')
    $st8 = & "$S\Get-StreamStatus.ps1" -Repo $r8
    Case 'integrator with a fresh lock beat (integ- session) is not flagged absent' (-not (($st8 -join ' ') -match 'no integrate session seen')) ($st8 -join ' | ')

    # ---- 8e. export: a deleted file and a new LF file under autocrlf both reach the patch, with no false OUTSIDE,
    #          and the deletion lands on main at integration
    $r9 = New-Repo 'r9' @{ 'G1.N' = "param([string]`$Root)`nif (-not (Test-Path (Join-Path `$Root 'G1.N.txt')) -and (Test-Path (Join-Path `$Root 'G1.N.new.txt'))) { 'PASS C1'; exit 0 } else { 'FAIL C1'; exit 1 }" }; $repos += $r9
    $d9 = J $r9; ($d9.tasks | Where-Object { $_.id -eq 'G1.N' }).writeSet = @('G1.N.txt', 'G1.N.new.txt'); $d9 | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r9 '.streams\tasks.json')
    [void](& "$S\Claim-Task.ps1" -Repo $r9 -Role build -Session build-n)
    $wt9 = & "$S\New-TaskWorktree.ps1" -Repo $r9 -Task G1.N -Session build-n -WorktreeRoot (Join-Path $Scratch 'wt') | Select-Object -Last 1
    git -C $wt9 config core.autocrlf true
    Remove-Item (Join-Path $wt9 'G1.N.txt')
    [IO.File]::WriteAllText((Join-Path $wt9 'G1.N.new.txt'), "line1`nline2`n")
    $o = & "$S\Export-TaskPatch.ps1" -Repo $r9 -Task G1.N -Worktree $wt9; $code = $LASTEXITCODE
    $pt = Get-Content -Raw (Join-Path $r9 '.streams\patches\G1.N.patch') -ErrorAction SilentlyContinue
    Case 'export: no false OUTSIDE, exit 0' ($code -eq 0 -and -not (($o -join ' ') -match 'OUTSIDE')) ("exit $code $($o -join ' | ')")
    Case 'export: deleted file is in the patch' ($pt -match 'deleted file mode' -and $pt -match 'b/G1\.N\.txt') ($o -join ' | ')
    Case 'export: new file is in the patch' ($pt -match 'new file mode' -and $pt -match 'b/G1\.N\.new\.txt') ($o -join ' | ')
    & "$S\Invoke-Grader.ps1" -Repo $r9 -Task G1.N -Root $wt9 -Label wt | Out-Null
    & "$S\Update-Task.ps1" -Repo $r9 -Task G1.N -Role build -Session build-n -To built -Release -Artifacts @{ patch = '.streams\patches\G1.N.patch'; verdict = 'PASS' } | Out-Null
    $o = & "$S\Integrate-Patch.ps1" -Repo $r9 -Session integ-n
    Case 'integrate: the deletion lands on main' ($o[0] -eq 'INTEGRATED G1.N' -and -not (Test-Path (Join-Path $r9 'G1.N.txt'))) ($o -join ' | ')

    # ---- 8f. environment failure on main (file lock) is RETRY, task stays built, main untouched; never SUSPECT
    $envG = "param([string]`$Root)`nif (`$Root -like '*\wt\*') { 'PASS C1'; exit 0 } else { 'FAIL C1: error CS2012: Cannot open Tests.Unit.dll for writing -- The process cannot access the file'; 'C2 not run: the build failed (C1)'; exit 1 }"
    $r10 = New-Repo 'r10' @{ 'G1.O' = $envG }; $repos += $r10
    [void](Build $r10 'G1.O' 'O done' 'build-o')
    $o = & "$S\Integrate-Patch.ps1" -Repo $r10 -Session integ-o
    Case 'CS2012 on main: RETRY, not SUSPECT' (@($o)[0] -eq 'RETRY G1.O (environment)') ($o -join ' | ')
    Case 'CS2012 on main: task stays built, main untouched' ((T $r10 'G1.O').state -eq 'built' -and -not (git -C $r10 status --porcelain -- G1.O.txt)) ("state=$((T $r10 'G1.O').state)")
    [void](& "$S\Integrate-Patch.ps1" -Repo $r10 -Session integ-o)
    $o = & "$S\Integrate-Patch.ps1" -Repo $r10 -Session integ-o
    Case 'third environment failure gives up to ticketed' (@($o)[0] -eq 'REVERSED G1.O (environment, 3 tries)' -and (T $r10 'G1.O').state -eq 'ticketed') ($o -join ' | ')

    # ---- 8g. main-tree grader lock: a held lock makes a main run wait, then MAIN-GRADER-BUSY (exit 5); worktree runs never wait
    $r11 = New-Repo 'r11' @{ 'G1.P' = (ContentGrader 'G1.P' 'base') }; $repos += $r11
    $lp = Join-Path $r11 '.streams\main-grader.lock'
    $held = [IO.FileStream]::new($lp, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose)
    try {
        $env:STREAM_MAIN_LOCK_WAIT_SECONDS = '2'
        $o = & "$S\Invoke-Grader.ps1" -Repo $r11 -Task G1.P -Root $r11 -Label main; $code = $LASTEXITCODE
        Case 'main grader waits on a held lock, then MAIN-GRADER-BUSY exit 5' ($code -eq 5 -and ($o -join ' ') -match 'MAIN-GRADER-BUSY') ("exit $code $($o -join ' | ')")
        $wtp = Join-Path $Scratch 'wt-p'; git -C $r11 worktree add -q --detach $wtp HEAD 2>&1 | Out-Null
        $o = & "$S\Invoke-Grader.ps1" -Repo $r11 -Task G1.P -Root $wtp -Label wt; $code = $LASTEXITCODE
        Case 'worktree grader ignores the main lock' ($code -eq 0) ("exit $code $($o -join ' | ')")
    } finally { $held.Dispose(); Remove-Item Env:STREAM_MAIN_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue }
    $o = & "$S\Invoke-Grader.ps1" -Repo $r11 -Task G1.P -Root $r11 -Label main; $code = $LASTEXITCODE
    Case 'main grader runs once the lock is free, and frees it' ($code -eq 0 -and -not (Test-Path $lp)) ("exit $code lock=$(Test-Path $lp)")

    # ---- 8h. claim order: an integration fix task is claimed before a longer critical-path task (author and build)
    $r12 = New-Repo 'r12' @{ 'G1.Q' = (ContentGrader 'G1.Q' 'done'); 'G1.R' = (ContentGrader 'G1.R' 'done') }; $repos += $r12
    $d12 = J $r12
    foreach ($x in $d12.tasks) {
        if ($x.id -eq 'G1.Q') { $x.estMinutes = 500 } else { $x.estMinutes = 5; $x.origin = 'integration' }
    }
    $d12 | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r12 '.streams\tasks.json')
    $c = & "$S\Claim-Task.ps1" -Repo $r12 -Role build -Session build-q | ConvertFrom-Json
    Case 'build claims the integration fix before the longer chain' ($c.id -eq 'G1.R') ("got $($c.id)")
    $d12 = J $r12
    foreach ($x in $d12.tasks) { $x.state = 'planned'; $x.claim = $null }
    $d12 | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r12 '.streams\tasks.json')
    $c = & "$S\Claim-Task.ps1" -Repo $r12 -Role author -Session author-q | ConvertFrom-Json
    Case 'author claims the integration fix before the longer chain' ($c.id -eq 'G1.R') ("got $($c.id)")

    # ---- 8i. coordinator plan edits: Revise-Task refuses an unordered or cyclic board (writes nothing), accepts an
    #          ordered batch, releases a blocked task by its artifacts; Test-BoardOrder reads the same rules
    $r13 = New-Repo 'r13' @{ 'G1.U' = (ContentGrader 'G1.U' 'done'); 'G1.V' = (ContentGrader 'G1.V' 'done'); 'G1.W' = (ContentGrader 'G1.W' 'done') }; $repos += $r13
    $o = & "$S\Test-BoardOrder.ps1" -Repo $r13; Case 'board check: CLEAN on a fresh board' ($LASTEXITCODE -eq 0 -and @($o)[0] -eq 'CLEAN') ($o -join ' | ')
    $before = Get-Content -Raw (Join-Path $r13 '.streams\tasks.json')
    $o = & "$S\Revise-Task.ps1" -Repo $r13 -Session plan-c -Task G1.V -AddWriteSet 'G1.U.txt'; $code = $LASTEXITCODE
    Case 'revise: unordered shared file refused, nothing written' ($code -eq 2 -and ($o -join ' ') -match 'UNORDERED' -and (Get-Content -Raw (Join-Path $r13 '.streams\tasks.json')) -eq $before) ("exit $code $($o -join ' | ')")
    $bf = Join-Path $Scratch 'r13-batch.json'
    @{ note = 'test'; edits = @(@{ task = 'G1.V'; addWriteSet = @('G1.U.txt'); addDependsOn = @('G1.U') }) } | ConvertTo-Json -Depth 5 | Set-Content $bf
    $o = & "$S\Revise-Task.ps1" -Repo $r13 -Session plan-c -File $bf; $code = $LASTEXITCODE
    Case 'revise: ordered batch accepted' ($code -eq 0 -and ((T $r13 'G1.V').writeSet -contains 'G1.U.txt') -and ((T $r13 'G1.V').dependsOn -contains 'G1.U')) ("exit $code $($o -join ' | ')")
    $o = & "$S\Revise-Task.ps1" -Repo $r13 -Session plan-c -Task G1.U -AddDependsOn 'G1.V'; $code = $LASTEXITCODE
    Case 'revise: cycle refused' ($code -eq 2 -and ($o -join ' ') -match 'CYCLE') ("exit $code $($o -join ' | ')")
    $d13 = J $r13; foreach ($x in $d13.tasks) { if ($x.id -eq 'G1.W') { $x.state = 'blocked' } }; $d13 | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r13 '.streams\tasks.json')
    $o = & "$S\Revise-Task.ps1" -Repo $r13 -Session plan-c -Task G1.W -AddWriteSet 'G1.W2.txt' -Release keep; $code = $LASTEXITCODE
    Case 'revise: keep leaves a blocked task blocked' ($code -eq 0 -and (T $r13 'G1.W').state -eq 'blocked') ("exit $code $($o -join ' | ')")
    $o = & "$S\Revise-Task.ps1" -Repo $r13 -Session plan-c -Task G1.W -Release auto -Note 'release'; $code = $LASTEXITCODE
    Case 'revise: auto releases a blocked task with ticket+grader to ticketed' ($code -eq 0 -and (T $r13 'G1.W').state -eq 'ticketed') ("exit $code $($o -join ' | ')")
    $d13 = J $r13; foreach ($x in $d13.tasks) { if ($x.id -eq 'G1.W') { $x.writeSet = @($x.writeSet) + 'G1.U.txt' } }; $d13 | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r13 '.streams\tasks.json')
    $o = & "$S\Test-BoardOrder.ps1" -Repo $r13; Case 'board check: reports a hand-made unordered overlap' ($LASTEXITCODE -eq 2 -and ($o -join ' ') -match 'UNORDERED .*G1\.W') ($o -join ' | ')

    # ---- 9. transition table: integrate may send a built task back to planned
    . "$S\lib\Streams.ps1"
    Case 'built>planned allowed for integrate' ($script:Transitions['built>planned'] -contains 'integrate')
    Case 'planned>built allowed for integrate (false-SUSPECT retry)' ($script:Transitions['planned>built'] -contains 'integrate')
    Case 'done>ticketed allowed for integrate' ($script:Transitions['done>ticketed'] -contains 'integrate')

    # ---- 10. a stray device-name file (NUL from a Git Bash `> NUL`) in the main tree does not break the base
    $r14 = New-Repo 'r14' @{ 'G1.X' = (ContentGrader 'G1.X' 'done') }; $repos += $r14
    [IO.File]::WriteAllText("\\?\$r14\NUL", 'stray')
    Set-Content (Join-Path $r14 'real-untracked.txt') 'u'
    $c14 = & "$S\Claim-Task.ps1" -Repo $r14 -Role build -Session build-nul | ConvertFrom-Json
    if ($c14.id -ne 'G1.X') { throw "expected to claim G1.X, got $($c14.id)" }
    $o =& "$S\New-TaskWorktree.ps1" -Repo $r14 -Task G1.X -Session build-nul -WorktreeRoot (Join-Path $Scratch 'wt14') 2>&1; $code = $LASTEXITCODE
    $wt14 = @($o)[-1]
    Case 'worktree: stray NUL in main tree is skipped, base still built' ($code -eq 0 -and (Test-Path -LiteralPath "$wt14\real-untracked.txt") -and -not [IO.File]::Exists("\\?\$wt14\NUL") -and (T $r14 'G1.X').base.worktree -eq $wt14) ("exit $code $($o -join ' | ')")
    [IO.File]::Delete("\\?\$r14\NUL")

    # ---- 11. an untracked file with a non-ASCII name in the main tree travels into the base under its real name
    $r15 = New-Repo 'r15' @{ 'G1.Y' = (ContentGrader 'G1.Y' 'done') }; $repos += $r15
    $uName = "caf$([char]0xE9)-$([char]0xFC).txt"
    [IO.File]::WriteAllText((Join-Path $r15 $uName), 'accent')
    $c15 = & "$S\Claim-Task.ps1" -Repo $r15 -Role build -Session build-utf | ConvertFrom-Json
    if ($c15.id -ne 'G1.Y') { throw "expected to claim G1.Y, got $($c15.id)" }
    $o = & "$S\New-TaskWorktree.ps1" -Repo $r15 -Task G1.Y -Session build-utf -WorktreeRoot (Join-Path $Scratch 'wt15') 2>&1; $code = $LASTEXITCODE
    $wt15 = @($o)[-1]
    Case 'worktree: non-ASCII untracked file copied under its real name' ($code -eq 0 -and (Test-Path -LiteralPath (Join-Path "$wt15" $uName)) -and (T $r15 'G1.Y').base.worktree -eq $wt15) ("exit $code $($o -join ' | ')")

    # ---- 12. a C# compile error on main (main moved on under the patch) is a code defect: REVERSED, never SUSPECT
    $csG = "param([string]`$Root)`nif (`$Root -like '*\wt\*') { 'PASS C1'; exit 0 } else { 'FAIL C1: Foo.cs(3,5): error CS0103: The name ''Bar'' does not exist in the current context'; exit 1 }"
    $r16 = New-Repo 'r16' @{ 'G1.Z' = $csG }; $repos += $r16
    [void](Build $r16 'G1.Z' 'Z done' 'build-z')
    $o = & "$S\Integrate-Patch.ps1" -Repo $r16 -Session integ-z
    $tz = T $r16 'G1.Z'
    Case 'compile error on main: REVERSED to ticketed, not SUSPECT' (@($o)[0] -eq 'REVERSED G1.Z' -and $tz.state -eq 'ticketed') ("$($o -join ' | ') state=$($tz.state)")
    Case 'compile error on main: note names the compile failure' ($tz.history[-1].note -match 'main build failed to compile \(base unchanged\): error CS0103') $tz.history[-1].note

    # ---- 13. inbox: a hold by a session that has gone silent past the role's limit is no hold
    $r17 = New-Repo 'r17' @{ 'G1.W' = (ContentGrader 'G1.W' 'done') }; $repos += $r17
    & "$S\Send-InboxItem.ps1" -Repo $r17 -To stream-author -From plan-1 -Kind request -Ask 'held by a session that then died' | Out-Null
    $ibox = Join-Path $r17 '.streams\inbox\stream-author.md'
    $iid = ([regex]::Match((Get-Content -Raw $ibox), 'IN-\d{14}-[0-9a-f]{4}')).Value
    $stale = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Add-Content $ibox ("- {0} | {1} | author-dead | taken | claimed" -f $iid, $stale)
    # Since 2026-09-30 taking over a stale hold is DELIBERATE: without -Steal the close is refused, and the refusal
    # names the flag, so a session that meets it can retry at once without reading any skill text (kit item
    # IN-20260930175245-b92e).
    $on17 = & "$S\Set-InboxItem.ps1" -Repo $r17 -Skill stream-author -Id $iid -Status done -By author-live -Note 'work landed elsewhere'; $cn17 = $LASTEXITCODE
    Case 'inbox: a stale hold is NOT closed by another session without -Steal' (($cn17 -eq 8) -and ("$on17" -like 'NOT-HELD*') -and ("$on17" -match '\-Steal')) ("exit $cn17 $on17")
    # try/catch: on a copy without -Steal the parameter binder throws, and one throw would end the harness.
    $o17 = try { & "$S\Set-InboxItem.ps1" -Repo $r17 -Skill stream-author -Id $iid -Status done -By author-live -Steal -Note 'work landed elsewhere' } catch { "THREW $_" }; $c17 = $LASTEXITCODE
    Case 'inbox: a stale hold can be closed by another session with -Steal' ($c17 -eq 0 -and "$o17" -eq "ok $iid done") ("exit $c17 $o17")
    Case 'inbox: and the closing line records the steal and the holder it took it from' (([IO.File]::ReadAllLines($ibox) | Where-Object { $_ -like "- $iid *" } | Select-Object -Last 1) -match 'STOLEN from author-dead after \d+m') ((([IO.File]::ReadAllLines($ibox) | Where-Object { $_ -like "- $iid *" } | Select-Object -Last 1)))
    Case 'inbox: the item reads done afterwards' ((@(& "$S\Get-InboxItems.ps1" -Repo $r17 -All -Open) -join ' ') -notmatch [regex]::Escape($iid))

    # a FRESH hold by another session is still refused
    & "$S\Send-InboxItem.ps1" -Repo $r17 -To stream-author -From plan-1 -Kind request -Ask 'held right now' | Out-Null
    $iid2 = @([regex]::Matches((Get-Content -Raw $ibox), 'IN-\d{14}-[0-9a-f]{4}') | ForEach-Object { $_.Value } | Select-Object -Unique | Where-Object { $_ -ne $iid })[0]
    & "$S\Set-InboxItem.ps1" -Repo $r17 -Skill stream-author -Id $iid2 -Status taken -By author-busy | Out-Null
    $o18 = & "$S\Set-InboxItem.ps1" -Repo $r17 -Skill stream-author -Id $iid2 -Status done -By author-other -Note 'not mine'; $c18 = $LASTEXITCODE
    Case 'inbox: a fresh hold still refuses another session' ($c18 -eq 8 -and "$o18" -like 'NOT-HELD*') ("exit $c18 $o18")


    # ---- 14. the integrator lock survives a long grader, and a lock in another session's name stops the integrator
    $slow = "param([string]`$Root)`nStart-Sleep -Seconds 6`n'PASS C1'`nexit 0"
    $r18 = New-Repo 'r18' @{ 'G1.V' = $slow }; $repos += $r18
    . "$S\lib\Streams.ps1"
    $P18 = Get-StreamPaths $r18
    $stale18 = (Get-Date).ToUniversalTime().AddMinutes(-19).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-AtomicText $P18.IntLock (@{ session = 'integ-beat'; at = $stale18; beat = $stale18 } | ConvertTo-Json)
    $env:STREAM_BEAT_SECONDS = '1'
    $beatErr = ''
    try { & "$S\Invoke-Grader.ps1" -Repo $r18 -Task G1.V -Root $r18 -Label beat -BeatSession integ-beat | Out-Null }
    catch { $beatErr = ("$_" -split "`n")[0].Trim() }
    Remove-Item Env:\STREAM_BEAT_SECONDS -ErrorAction SilentlyContinue
    Case 'grader takes -BeatSession' (-not $beatErr) $beatErr
    $beat18 = (Get-Content -Raw $P18.IntLock | ConvertFrom-Json -AsHashtable -DateKind String).beat
    $age18 = ((Get-Date).ToUniversalTime() - [datetime]::Parse($beat18, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes
    Case 'grader -BeatSession keeps the integrator lock fresh' ($age18 -lt 1) ("beat $beat18 is $([int]$age18) min old")
    $blog = Join-Path $r18 '.streams\logs\G1.V.grader.beat.txt'
    Case 'grader -BeatSession still logs and passes' ((Test-Path $blog) -and @((Get-Content $blog) -match 'PASS C1').Count -gt 0) "log $blog"

    # a lock in ANOTHER session's name: the integrator applies nothing
    $r19 = New-Repo 'r19' @{ 'G1.U' = (ContentGrader 'G1.U' 'done') }; $repos += $r19
    [void](Build $r19 'G1.U' 'U done' 'build-u')
    $P19 = Get-StreamPaths $r19
    $fresh19 = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Write-AtomicText $P19.IntLock (@{ session = 'integ-other'; at = $fresh19; beat = $fresh19 } | ConvertTo-Json)
    $o19 = & "$S\Integrate-Patch.ps1" -Repo $r19 -Session integ-mine; $c19 = $LASTEXITCODE
    $t19 = T $r19 'G1.U'
    Case 'integrate refuses while another session holds the lock' ($c19 -eq 5 -and "$o19" -like 'LOCK-LOST*' -and $t19.state -eq 'built') ("exit $c19 $o19 state=$($t19.state)")
    Case 'integrate left the main tree alone under a foreign lock' ((Get-Content -Raw (Join-Path $r19 'G1.U.txt')).Trim() -eq 'G1.U base') (Get-Content -Raw (Join-Path $r19 'G1.U.txt'))

    # a lock the watchdog broke under this session is retaken, and integration carries on
    Remove-Item $P19.IntLock -Force
    $o20 = & "$S\Integrate-Patch.ps1" -Repo $r19 -Session integ-mine; $c20 = $LASTEXITCODE
    $t20 = T $r19 'G1.U'
    Case 'integrate retakes a broken lock and integrates' ($c20 -eq 0 -and "$o20" -like 'INTEGRATED*' -and $t20.state -eq 'integrated') ("exit $c20 $o20 state=$($t20.state)")
    Case 'retaken lock now names this session' ((Get-Content -Raw $P19.IntLock | ConvertFrom-Json -AsHashtable -DateKind String).session -eq 'integ-mine')


    # ---- 15. a builder's claim is beaten while its grader runs, so the watchdog cannot break a live builder
    $slow2 = "param([string]`$Root)`nStart-Sleep -Seconds 6`n'PASS C1'`nexit 0"
    $r20 = New-Repo 'r20' @{ 'G1.S' = $slow2 }; $repos += $r20
    $c20a = & "$S\Claim-Task.ps1" -Repo $r20 -Role build -Session build-beat | ConvertFrom-Json
    if ($c20a.id -ne 'G1.S') { throw "expected to claim G1.S, got $($c20a.id)" }
    # age the claim to just under the 45-minute build limit, as a long grader would
    $doc20 = Get-Content -Raw (Join-Path $r20 '.streams\tasks.json') | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
    ($doc20.tasks | Where-Object { $_.id -eq 'G1.S' }).claim.beat = (Get-Date).ToUniversalTime().AddMinutes(-44).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Set-Content (Join-Path $r20 '.streams\tasks.json') ($doc20 | ConvertTo-Json -Depth 50)
    $env:STREAM_BEAT_SECONDS = '1'
    $beatErr2 = ''
    try { & "$S\Invoke-Grader.ps1" -Repo $r20 -Task G1.S -Root $r20 -Label beat -BeatSession build-beat -BeatTask G1.S | Out-Null }
    catch { $beatErr2 = ("$_" -split "`n")[0].Trim() }
    Remove-Item Env:\STREAM_BEAT_SECONDS -ErrorAction SilentlyContinue
    Case 'grader takes -BeatTask' (-not $beatErr2) $beatErr2
    $claim20 = (T $r20 'G1.S').claim
    $cAge = if ($claim20) { ((Get-Date).ToUniversalTime() - [datetime]::Parse($claim20.beat, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)).TotalMinutes } else { 999 }
    Case 'grader -BeatTask keeps the build claim fresh' ($cAge -lt 1) ("claim beat $($claim20.beat) is $([int]$cAge) min old")
    Case 'the watchdog leaves that live builder alone' (@(& "$S\Invoke-Watchdog.ps1" -Repo $r20 -Session status-beat) -contains 'QUIET') 'watchdog broke a beaten claim'

    # a claim held by ANOTHER session is never beaten by this one
    $doc21 = Get-Content -Raw (Join-Path $r20 '.streams\tasks.json') | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
    $old21 = (Get-Date).ToUniversalTime().AddMinutes(-44).ToString('yyyy-MM-ddTHH:mm:ssZ')
    ($doc21.tasks | Where-Object { $_.id -eq 'G1.S' }).claim.beat = $old21
    Set-Content (Join-Path $r20 '.streams\tasks.json') ($doc21 | ConvertTo-Json -Depth 50)
    . "$S\lib\Streams.ps1"
    $P20 = Get-StreamPaths $r20
    Case 'a foreign claim is not beaten' (-not (Update-ClaimBeat $P20 'build-other' 'G1.S') -and (T $r20 'G1.S').claim.beat -eq $old21)

    # ---- 22. a reclaimed worktree must not cost the SUSPECT verdict. Integrate-Patch used to require the worktree and
    # called its absence 'builder worktree gone', which forced REVERSED; it now proves main held the patch content from
    # the patch itself, so a grader-only red is still SUSPECT after the worktree has been released.
    $wtOnly22 = "param([string]`$Root)`nif (`$Root -like '*\wt\*') { 'PASS C1'; 'PASS C2'; exit 0 } else { 'PASS C1'; 'FAIL C2: tree-local check'; exit 1 }"
    $r22 = New-Repo 'r22' ([ordered]@{ 'G1.W' = $wtOnly22 }); $repos += $r22
    $wt22 = Build $r22 'G1.W' 'W done' 'build-1'
    $rm22 = & "$S\Remove-TaskWorktree.ps1" -Repo $r22 -Session status-22 -Task G1.W -Reason 'test: released before integration'
    Case 'worktree is released while the task is built' (("$rm22" -like 'REMOVED G1.W *') -and -not (Test-Path $wt22)) "$rm22"
    Case 'release appends a removed line' ((Get-Content -Raw (Join-Path $r22 '.streams\owner\worktrees.md')) -match 'G1\.W \|.*\| removed \(')
    $o22 = & "$S\Integrate-Patch.ps1" -Repo $r22 -Session integ-22 -Task G1.W
    $tw22 = T $r22 'G1.W'
    Case 'SUSPECT survives a released worktree' ("$o22" -eq 'SUSPECT G1.W' -and $tw22.state -eq 'planned') "$o22 state=$($tw22.state)"
    Case 'no verdict blames the missing worktree' ($tw22.history[-1].note -notmatch 'worktree gone') $tw22.history[-1].note

    # ---- 22b. a write-set file the patch never touched, on main but not in the worktree (a dependency landed it after
    # the worktree was cut), is a code difference: REVERSED, never SUSPECT (kit item IN-20261019210040-3dac).
    $r22b = New-Repo 'r22b' ([ordered]@{ 'G1.W' = $wtOnly22 }); $repos += $r22b
    $wt22b = Build $r22b 'G1.W' 'W done' 'build-1'
    $doc22b = Get-Content -Raw (Join-Path $r22b '.streams\tasks.json') | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
    ($doc22b.tasks | Where-Object { $_.id -eq 'G1.W' }).writeSet = @('G1.W.txt', 'sweep22b.ts')
    Set-Content (Join-Path $r22b '.streams\tasks.json') ($doc22b | ConvertTo-Json -Depth 50)
    Set-Content (Join-Path $r22b 'sweep22b.ts') 'landed by a dependency'
    git -C $r22b add sweep22b.ts; git -C $r22b commit -q -m dep
    $o22b = & "$S\Integrate-Patch.ps1" -Repo $r22b -Session integ-22b -Task G1.W
    $tw22b = T $r22b 'G1.W'
    Case 'write-set file absent from the worktree: REVERSED, not SUSPECT' ("$o22b" -eq 'REVERSED G1.W' -and $tw22b.state -eq 'ticketed') "$o22b state=$($tw22b.state)"
    Case 'the reversal names the missing write-set file' ($tw22b.history[-1].note -match 'outside the patch differ.*sweep22b\.ts') $tw22b.history[-1].note

    # ---- 22c. CENSUS GATE (kit item IN-20261023162852-ea21): a repo census named in config runs after the row's grader
    # when the patch touches a census path. G18.T061 passed its own check, integrated, and left a Tests.Architecture
    # census red on main. (a) red only with the patch: REVERSED with a census why, never SUSPECT; (b) census red on main
    # before the patch (baseline): the patch integrates; (d) the patch touches no census path: the census never runs.
    $census22c = "param([string]`$Root)`nif (@(Get-ChildItem `$Root -Filter 'G1.*.txt' | Where-Object { (Get-Content -Raw `$_.FullName) -match 'MARK' }).Count) { 'FAIL CENSUS-Marker: a marked file' } else { 'PASS CENSUS-Marker' }`nif (Test-Path (Join-Path `$Root 'main-red.txt')) { 'FAIL CENSUS-Main: red on main' } else { 'PASS CENSUS-Main' }`nexit ([int](@(Get-ChildItem `$Root -Filter 'G1.*.txt' | Where-Object { (Get-Content -Raw `$_.FullName) -match 'MARK' }).Count -gt 0 -or (Test-Path (Join-Path `$Root 'main-red.txt'))))"
    function Set-Census22c([string] $repo, [string] $paths) {
        New-Item -ItemType Directory -Path (Join-Path $repo '.streams\checks') -Force | Out-Null
        Set-Content (Join-Path $repo '.streams\checks\census.ps1') $census22c
        @{ census = @{ script = '.streams\checks\census.ps1'; paths = $paths } } | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $repo '.streams\config.json')
    }
    $r22c = New-Repo 'r22c' ([ordered]@{ 'G1.X' = (ContentGrader 'G1.X' 'ok') }); $repos += $r22c
    Set-Census22c $r22c '\.txt$'
    [void](Build $r22c 'G1.X' 'X ok MARK' 'build-1')
    $o22c = & "$S\Integrate-Patch.ps1" -Repo $r22c -Session integ-22c -Task G1.X
    $tx22c = T $r22c 'G1.X'
    Case 'census red only with the patch: REVERSED, not SUSPECT' ("$o22c" -eq 'REVERSED G1.X' -and $tx22c.state -eq 'ticketed') "$o22c state=$($tx22c.state)"
    Case 'the reversal names the census' ($tx22c.history[-1].note -match 'census CENSUS-Marker red only with this patch') $tx22c.history[-1].note
    Case 'census joins the grader identity' ((Get-Content (Join-Path $r22c '.streams\logs\G1.X.grader.main.txt'))[-1] -match '^GRADER sha [0-9A-F]+\+census:[0-9A-F]+ ') ((Get-Content (Join-Path $r22c '.streams\logs\G1.X.grader.main.txt'))[-1])
    $r22d = New-Repo 'r22d' ([ordered]@{ 'G1.Y' = (ContentGrader 'G1.Y' 'ok') }); $repos += $r22d
    Set-Census22c $r22d '\.txt$'
    Set-Content (Join-Path $r22d 'main-red.txt') 'already red'
    git -C $r22d add main-red.txt; git -C $r22d commit -q -m red
    [void](Build $r22d 'G1.Y' 'Y ok' 'build-1')
    $o22d = @(& "$S\Integrate-Patch.ps1" -Repo $r22d -Session integ-22d -Task G1.Y)
    $base22d = Get-Content -Raw (Join-Path $r22d '.streams\suites\census-baseline.json') | ConvertFrom-Json
    Case 'census red on main before the patch is a baseline: patch integrates' ($o22d[0] -eq 'INTEGRATED G1.Y') ($o22d -join ' | ')
    Case 'baseline records main''s census red' (@($base22d.fails) -contains 'CENSUS-Main') (@($base22d.fails) -join ',')
    Case 'baseline id is logged BASELINE, not FAIL' ((Get-Content -Raw (Join-Path $r22d '.streams\logs\G1.Y.grader.main.txt')) -match '(?m)^BASELINE CENSUS-Main' -and (Get-Content -Raw (Join-Path $r22d '.streams\logs\G1.Y.grader.main.txt')) -notmatch '(?m)^FAIL CENSUS-')
    $r22e = New-Repo 'r22e' ([ordered]@{ 'G1.V' = (ContentGrader 'G1.V' 'ok') }); $repos += $r22e
    Set-Census22c $r22e '^nomatch/'
    [void](Build $r22e 'G1.V' 'V ok MARK' 'build-1')
    $o22e = @(& "$S\Integrate-Patch.ps1" -Repo $r22e -Session integ-22e -Task G1.V)
    Case 'census path not touched: census not run, patch integrates' ($o22e[0] -eq 'INTEGRATED G1.V' -and (Get-Content -Raw (Join-Path $r22e '.streams\logs\G1.V.grader.main.txt')) -notmatch 'CENSUS-') ($o22e -join ' | ')
    # ---- 23. the reaper: an integrated worktree goes, a live builder's stays, and a refusal never deletes
    $r23 = New-Repo 'r23' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r23
    $wtA23 = Build $r23 'G1.A' 'ok' 'build-1'
    [void](& "$S\Integrate-Patch.ps1" -Repo $r23 -Session integ-23 -Task G1.A)
    Case 'the integrated task is integrated' ((T $r23 'G1.A').state -eq 'integrated') (T $r23 'G1.A').state
    $wtB23 = Build $r23 'G1.B' 'ok' 'build-2'       # left built, with a fresh claim from Build
    $o23 = & "$S\Invoke-Watchdog.ps1" -Repo $r23 -Session status-23
    Case 'reaper removes the integrated worktree' (-not (Test-Path $wtA23)) "$wtA23 survived: $($o23 -join ' | ')"
    Case 'reaper keeps a live builder''s worktree' (Test-Path $wtB23) "$wtB23 was taken while its builder held it"
    # Build releases its claim (-Release), so a live claim has to be put back to test the refusal that protects a
    # builder who IS in the tree. This is the case that must never delete: a claim with a fresh beat.
    $doc23 = Get-Content -Raw (Join-Path $r23 '.streams\tasks.json') | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50
    ($doc23.tasks | Where-Object { $_.id -eq 'G1.B' }).claim = [ordered]@{ role = 'build'; session = 'build-live-23'; at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    Set-Content (Join-Path $r23 '.streams\tasks.json') ($doc23 | ConvertTo-Json -Depth 50)
    $rm23 = & "$S\Remove-TaskWorktree.ps1" -Repo $r23 -Session status-23 -Task G1.B -Reason 'test: must refuse'
    Case 'release refuses a live claim' (("$rm23" -like 'REFUSED G1.B holds a live *') -and (Test-Path $wtB23)) "$rm23"
    Case 'the reaper also leaves it alone' ((Test-Path $wtB23) -and ((& "$S\Invoke-Watchdog.ps1" -Repo $r23 -Session status-23b) -join ' ') -notmatch 'G1\.B')
    Case 'a second reap is idempotent' ((& "$S\Remove-TaskWorktree.ps1" -Repo $r23 -Session status-23 -Task G1.A) -like 'NOTHING*')

    # ---- 24. a task bounced back to ticketed leaks its tree: New-TaskWorktree suffixes -2 rather than reusing one, so
    # the old tree is never built in again. Found on the live board, where a planned G2.T04 and a superseded G2.T33-2
    # were both being kept indefinitely.
    $r24 = New-Repo 'r24' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r24
    $wt24 = Build $r24 'G1.A' 'ok' 'build-1'
    [void](& "$S\Update-Task.ps1" -Repo $r24 -Task G1.A -Role integrate -Session integ-24 -To ticketed -Note 'test: bounced')
    Case 'the bounced task is ticketed' ((T $r24 'G1.A').state -eq 'ticketed') (T $r24 'G1.A').state
    $o24 = & "$S\Invoke-Watchdog.ps1" -Repo $r24 -Session status-24
    Case 'reaper takes a bounced task''s dead tree' (-not (Test-Path $wt24)) "$wt24 survived: $($o24 -join ' | ')"
    # The printed line is REMOVED <task> <path> (<n> MB); the reason is recorded on the worktrees.md line, so that is
    # where an operator reads WHY a tree went.
    Case 'the ledger records why it went' ((Get-Content -Raw (Join-Path $r24 '.streams\owner\worktrees.md')) -match 'removed \(.*\): watchdog: task went back to ticketed') ((Get-Content (Join-Path $r24 '.streams\owner\worktrees.md'))[-1])

    # ---- 25. owner queue reads BOTH line shapes
    # Authors write an owner question as a '- ' bullet or as a bare 'task | question | default | why' line. On
    # 2026-09-29 the live board held 882 question lines of which 706 had no bullet, so a '- *' filter showed the owner
    # 176 of them and hid the rest, side effects addressed to him by name included. An entry is now either shape;
    # prose (which carries no ' | ' separator) is still not an entry, so gates.md's explanatory lines stay out.
    $ownerDir = Join-Path $r24 '.streams\owner'
    Set-Content -Path (Join-Path $ownerDir 'questions.md') -Encoding utf8 -Value @(
        '# questions.md'
        '- G1.Z | bulleted question | default A | because'
        'G1.Y | bare question, no bullet | default B | because'
        'Refreshed by some session; prose, not a question.'
        'RESOLVED - G1.X | bulleted question the owner answered | default C | because'
        'RESOLVED G1.W | bare question the owner answered | default D | because'
    )
    Set-Content -Path (Join-Path $ownerDir 'gates.md') -Encoding utf8 -Value @(
        '# gates.md'
        '- G1.G1 | open the page | pass: /stream-integrate gate G1.G1 pass "note"'
        'Pass or fail one with: /stream-integrate gate <task> pass|fail "<note>"'
    )
    $st = & "$S\Get-StreamStatus.ps1" -Repo $r24
    $ownerLine = @($st | Where-Object { $_ -like 'owner: *' })[0]
    Case 'owner queue counts a bulleted AND a bare question' ($ownerLine -match 'questions 2\b') "$ownerLine"
    Case 'owner queue leaves prose out of the gate list' ($ownerLine -match 'gates 1\b') "$ownerLine"

    # An answered question keeps its text and gains a leading RESOLVED token, so the record stays readable in
    # the file and leaves the owner's queue. Without a retirement token the queue only grows: 882 lines had
    # accumulated by 2026-09-29 with no way to take one off.
    Case 'a RESOLVED question leaves the queue, both shapes' ($ownerLine -match 'questions 2') "$ownerLine"

    # ---- 26. a LIVE claim protects the tree its holder is in, not every copy the task ever had. On the live board
    # G2.T33 was building in G2.T33-3 while G2.T33 and G2.T33-2 (1.2 GB together) were held by the live-claim guard and
    # could never be reclaimed. The safe test is the clock: a tree the current holder laid down cannot predate its own
    # claim, so a non-recorded copy older than claim.at is dead. The removal is labelled with the OWNING task, because
    # logging a known task's superseded copy as an orphan loses the attribution an operator reads.
    $r26 = New-Repo 'r26' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r26
    $dead26 = Build $r26 'G1.A' 'ok' 'build-26a'
    [void](& "$S\Update-Task.ps1" -Repo $r26 -Task G1.A -Role integrate -Session integ-26 -To ticketed -Note 'test: bounced')
    $live26 = Build $r26 'G1.A' 'ok' 'build-26b'
    Case 'the re-build gets a fresh tree' ($live26 -ne $dead26) "$live26"
    # Both copies exist; make the first one plainly older than the live claim, and write that live claim back (Build
    # releases it at -To built), so the reaper sees exactly the live board's shape.
    (Get-Item $dead26).LastWriteTime = (Get-Date).AddHours(-2)
    # Its files too: since kit item IN-20261016125015-6592 the newest FILE decides whether a copy is in use.
    Get-ChildItem $dead26 -Recurse -File -Force | ForEach-Object { $_.LastWriteTime = (Get-Date).AddHours(-2) }
    $doc26 = J $r26
    ($doc26.tasks | Where-Object { $_.id -eq 'G1.A' }).state = 'building'
    ($doc26.tasks | Where-Object { $_.id -eq 'G1.A' }).claim = @{ role = 'build'; session = 'build-26b'
        at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    Set-Content -Path (Join-Path $r26 '.streams\tasks.json') -Encoding utf8 -Value ($doc26 | ConvertTo-Json -Depth 50)
    $o26 = & "$S\Invoke-Watchdog.ps1" -Repo $r26 -Session status-26
    Case 'reaper takes the superseded copy of a LIVE task' (-not (Test-Path $dead26)) "$dead26 survived: $($o26 -join ' | ')"
    Case 'reaper keeps the tree the live holder records' (Test-Path $live26) "$live26 went: $($o26 -join ' | ')"
    $led26 = @(Get-Content (Join-Path $r26 '.streams\owner\worktrees.md') | Where-Object { $_ -match 'removed \(' })[-1]
    Case 'the removal is attributed to the owning task' (($led26 -match '^- G1\.A \|') -and ($led26 -notmatch '\(orphan\)')) "$led26"

    # ---- 26b/26c. a superseded copy somebody is still WRITING to is kept (kit item IN-20261016125015-6592). On
    # 2026-10-16 a build unit recorded G7.T019-2 but kept editing the old G7.T019 tree; the watchdog reaped that tree
    # because only the directory's own mtime was compared with claim.at, and an edit deep in the tree does not move it.
    # The unit's next `cd` failed and its Set-Content wrote an empty file into the main tree. 26b: a file written after
    # the claim keeps the copy. 26c: a file written before the claim but inside the quiet period keeps it too.
    foreach ($k in @('b', 'c')) {
        $rK = New-Repo "r26$k" ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $rK
        $deadK = Build $rK 'G1.A' 'ok' "build-26${k}a"
        [void](& "$S\Update-Task.ps1" -Repo $rK -Task G1.A -Role integrate -Session "integ-26$k" -To ticketed -Note 'test: bounced')
        $liveK = Build $rK 'G1.A' 'ok' "build-26${k}b"
        (Get-Item $deadK).LastWriteTime = (Get-Date).AddHours(-2)
        Get-ChildItem $deadK -Recurse -File -Force | ForEach-Object { $_.LastWriteTime = (Get-Date).AddHours(-2) }
        $deepK = Join-Path $deadK 'src\Deep'; New-Item -ItemType Directory -Path $deepK -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $deepK 'Edit.cs') -Value 'holder still editing here'
        (Get-Item $deepK).LastWriteTime = (Get-Date).AddHours(-2); (Get-Item (Join-Path $deadK 'src')).LastWriteTime = (Get-Date).AddHours(-2)
        (Get-Item $deadK).LastWriteTime = (Get-Date).AddHours(-2)
        $claimK = if ($k -eq 'b') { (Get-Date).AddMinutes(-5) } else { Get-Date }
        if ($k -eq 'c') { (Get-Item (Join-Path $deepK 'Edit.cs')).LastWriteTime = (Get-Date).AddMinutes(-1) }
        if ($k -eq 'c') { $env:STREAM_REAP_QUIET_MINUTES = '10' }
        $docK = J $rK
        ($docK.tasks | Where-Object { $_.id -eq 'G1.A' }).state = 'building'
        ($docK.tasks | Where-Object { $_.id -eq 'G1.A' }).claim = @{ role = 'build'; session = "build-26${k}b"
            at = $claimK.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
        Set-Content -Path (Join-Path $rK '.streams\tasks.json') -Encoding utf8 -Value ($docK | ConvertTo-Json -Depth 50)
        try { $oK = @(& "$S\Invoke-Watchdog.ps1" -Repo $rK -Session "status-26$k") } finally { $env:STREAM_REAP_QUIET_MINUTES = '0' }
        $what = if ($k -eq 'b') { 'written after the claim' } else { 'written inside the quiet period' }
        Case "reaper keeps a superseded copy with a file $what" ((Test-Path (Join-Path $deepK 'Edit.cs')) -and (($oK -join ' ') -match "KEPT G1\.A .*wrong tree")) "$deadK out=$($oK -join ' | ')"
    }

    # ---- 27. an AUTHOR claim must not hold a worktree. A worktree belongs to a build claim: New-TaskWorktree is only
    # ever called by a builder. On the live board G2.T04 sat `planned` with a live author claim writing its next ticket,
    # and that claim kept the task's dead builder tree alive for as long as the author kept beating.
    $r27 = New-Repo 'r27' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r27
    $wt27 = Build $r27 'G1.A' 'ok' 'build-27'
    $doc27 = J $r27
    ($doc27.tasks | Where-Object { $_.id -eq 'G1.A' }).state = 'planned'
    ($doc27.tasks | Where-Object { $_.id -eq 'G1.A' }).claim = @{ role = 'author'; session = 'author-27'
        at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }
    Set-Content -Path (Join-Path $r27 '.streams\tasks.json') -Encoding utf8 -Value ($doc27 | ConvertTo-Json -Depth 50)
    $o27 = & "$S\Invoke-Watchdog.ps1" -Repo $r27 -Session status-27
    Case 'a live author claim does not hold a worktree' (-not (Test-Path $wt27)) "$wt27 survived: $($o27 -join ' | ')"
    Case 'the author claim itself is untouched' ((T $r27 'G1.A').claim.session -eq 'author-27') ((T $r27 'G1.A').claim | ConvertTo-Json -Compress)

    # ---- 28. the worktree ledger is counted by PATH, not by line. worktrees.md is append-only with a status word per
    # line, so one tree gets a line for building, one for built, one for a build-output prune and one for its removal.
    # On 2026-09-29 that read to the owner as "199 worktrees waiting on removal" against 10 real directories, which is a
    # number nobody can act on. Each path counts once, by its LAST line; a path whose last line records a removal is
    # out, and so is a path whose directory is gone (30 trees were removed by hand that day with no ledger line).
    # "build output pruned" KEEPS the tree, so it stays in.
    $r28 = New-Repo 'r28' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r28
    $wtA = Join-Path $r28 'wt-A'; $wtB = Join-Path $r28 'wt-B'
    New-Item -ItemType Directory -Path $wtA, $wtB -Force | Out-Null
    Set-Content -Path (Join-Path $r28 '.streams\owner\worktrees.md') -Encoding utf8 -Value @(
        '# worktrees.md'
        "- G1.A | $wtA | 2026-09-29T10:00:00Z | building"
        "- G1.A | $wtA | 2026-09-29T11:00:00Z | built, patch exported"
        "- G1.A | $wtA | 2026-09-29T12:00:00Z | build output pruned (442 MB): watchdog: built, patch exported"
        "- G1.B | $wtB | 2026-09-29T12:30:00Z | removed (55 MB): watchdog: task is integrated"
    )
    $own28 = @(& "$S\Get-StreamStatus.ps1" -Repo $r28 | Where-Object { $_ -like 'owner: *' })[0]
    Case 'four ledger lines over two paths count as one live worktree' ($own28 -match 'worktrees 1\b') "$own28"
    # G1.B's directory is still there, so the removal line is what takes it out, not the disk check.
    Case 'the removed path is out while its directory still exists' (Test-Path $wtB) "$wtB"
    # A path nothing removed but nobody left on disk is not a worktree an owner can act on.
    Add-Content -Path (Join-Path $r28 '.streams\owner\worktrees.md') -Encoding utf8 -Value "- G1.D | $(Join-Path $r28 'wt-gone') | 2026-09-29T13:10:00Z | building"
    $own28b = @(& "$S\Get-StreamStatus.ps1" -Repo $r28 | Where-Object { $_ -like 'owner: *' })[0]
    Case 'a ledger path whose directory is gone is not counted' ($own28b -match 'worktrees 1\b') "$own28b"
    # ---- 29. every integration commit is pushed to the shared stream branch (owner decision 2026-09-29, kit item
    # IN-20260929001946-67a7 part 1). The branch needs a PR, so the ref is named outright rather than taken from an
    # upstream. A push failure is REPORTED and must never block integration: the commit is already local, and the next
    # integration pushes both.
    $r29 = New-Repo 'r29' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r29
    $bare29 = Join-Path $Scratch 'r29-origin.git'
    git init -q --bare $bare29
    git -C $r29 remote add origin $bare29
    [void](Build $r29 'G1.A' 'ok' 'build-29')
    $o29 = & "$S\Integrate-Patch.ps1" -Repo $r29 -Session integ-29 -PushRef 'refs/heads/stream-test'
    Case 'the integration commit is pushed' (($o29 -join ' ') -match 'PUSHED G1\.A') ($o29 -join ' | ')
    $remoteSha = (& git -C $bare29 rev-parse refs/heads/stream-test 2>&1) | Select-Object -First 1
    $localSha = (& git -C $r29 rev-parse HEAD) | Select-Object -First 1
    Case 'the remote ref holds the integration commit' ($remoteSha -eq $localSha) "remote $remoteSha local $localSha"

    # A broken origin must cost nothing: the task stays integrated and the commit stands.
    $r30 = New-Repo 'r30' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r30
    git -C $r30 remote add origin (Join-Path $Scratch 'no-such-remote.git')
    [void](Build $r30 'G1.A' 'ok' 'build-30')
    $head30 = (& git -C $r30 rev-parse HEAD) | Select-Object -First 1
    $o30 = & "$S\Integrate-Patch.ps1" -Repo $r30 -Session integ-30 -PushRef 'refs/heads/stream-test'
    Case 'a failed push is reported' (($o30 -join ' ') -match 'PUSH FAILED G1\.A') ($o30 -join ' | ')
    Case 'a failed push leaves the task integrated' ((T $r30 'G1.A').state -eq 'integrated') (T $r30 'G1.A').state
    Case 'a failed push leaves the commit in place' (((& git -C $r30 rev-parse HEAD) | Select-Object -First 1) -ne $head30) 'HEAD did not move'
    # An empty -PushRef switches the push off, for a repo that must not publish.
    $r31 = New-Repo 'r31' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r31
    git -C $r31 remote add origin $bare29
    [void](Build $r31 'G1.A' 'ok' 'build-31')
    $o31 = & "$S\Integrate-Patch.ps1" -Repo $r31 -Session integ-31 -PushRef ''
    Case 'an empty push ref pushes nothing' ((($o31 -join ' ') -match 'COMMITTED G1\.A') -and (($o31 -join ' ') -notmatch 'PUSH')) ($o31 -join ' | ')
    # The machine profile's Git policy governs the script's own commit and push: git-guard sees only command text, so
    # it never sees the git Integrate-Patch runs. Each case points AI_MACHINE_CONFIG at its own profile, then back.
    $fixtureProfile = $env:AI_MACHINE_CONFIG
    function Use-Profile([string] $name, [string] $rows) {
        $pf = Join-Path $Scratch "$name.profile.md"
        Set-Content -Path $pf -Encoding utf8 -Value "| Key | Value |`n|---|---|`n| ScratchRoot | $Scratch |`n`n## Git policy`n`n| Repo | Commit | Push | Worktrees | Note |`n|---|---|---|---|---|`n$rows"
        $env:AI_MACHINE_CONFIG = $pf
    }
    # Push = no: the commit lands, the push is skipped and logged, the remote ref is untouched.
    $r31b = New-Repo 'r31b' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r31b
    $bare31b = Join-Path $Scratch 'r31b-origin.git'
    git init -q --bare $bare31b
    git -C $r31b remote add origin $bare31b
    [void](Build $r31b 'G1.A' 'ok' 'build-31b')
    Use-Profile 'r31b' "| $(Get-AIRepoRoot -Path $r31b) | yes | no | yes | push off |"
    $o31b = & "$S\Integrate-Patch.ps1" -Repo $r31b -Session integ-31b -PushRef 'refs/heads/stream-test'
    $env:AI_MACHINE_CONFIG = $fixtureProfile
    Case 'policy Push = no still commits' (($o31b -join ' ') -match 'COMMITTED G1\.A') ($o31b -join ' | ')
    Case 'policy Push = no skips the push' (($o31b -join ' ') -match 'PUSH SKIPPED G1\.A' -and ($o31b -join ' ') -notmatch 'PUSHED') ($o31b -join ' | ')
    & git -C $bare31b rev-parse --verify -q refs/heads/stream-test 2>&1 | Out-Null
    Case 'policy Push = no leaves the remote ref absent' ($LASTEXITCODE -ne 0) 'the remote ref exists'
    Case 'a skipped push is logged in decisions.md' ((Get-Content -Raw (Join-Path $r31b '.streams\decisions.md')) -match 'push of \S+ to origin \S+ skipped') 'no decision line'
    # No row for the repo: nothing is committed, the task stays integrated, and the patch stays in the tree.
    $r31c = New-Repo 'r31c' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r31c
    [void](Build $r31c 'G1.A' 'ok' 'build-31c')
    $head31c = (& git -C $r31c rev-parse HEAD) | Select-Object -First 1
    Use-Profile 'r31c' ''
    $o31c = & "$S\Integrate-Patch.ps1" -Repo $r31c -Session integ-31c
    $env:AI_MACHINE_CONFIG = $fixtureProfile
    Case 'no policy row skips the commit' (($o31c -join ' ') -match 'COMMIT SKIPPED G1\.A' -and ($o31c -join ' ') -notmatch 'COMMITTED') ($o31c -join ' | ')
    Case 'no policy row leaves HEAD where it was' (((& git -C $r31c rev-parse HEAD) | Select-Object -First 1) -eq $head31c) 'HEAD moved'
    Case 'no policy row leaves the task integrated' ((T $r31c 'G1.A').state -eq 'integrated') (T $r31c 'G1.A').state
    Case 'no policy row leaves the patch in the tree' ((Get-Content -Raw (Join-Path $r31c 'G1.A.txt')) -match 'ok') 'patch content missing'
    # A profile that cannot be read fails closed: no commit.
    $r31d = New-Repo 'r31d' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r31d
    [void](Build $r31d 'G1.A' 'ok' 'build-31d')
    $env:AI_MACHINE_CONFIG = Join-Path $Scratch 'no-such-profile.md'
    $o31d = & "$S\Integrate-Patch.ps1" -Repo $r31d -Session integ-31d
    $env:AI_MACHINE_CONFIG = $fixtureProfile
    Case 'an unreadable profile skips the commit' (($o31d -join ' ') -match 'COMMIT SKIPPED G1\.A .*could not be read') ($o31d -join ' | ')

    # ---- 30. a plan session can give an orphaned REQ/AC an owner. Revise-Task could edit a write set, a dependsOn, a
    # title and the targeted tests but not why, so on 2026-09-29 AC-FLEETCHAN-008 could only be owned by inventing a
    # task for it (kit item IN-20260929161555-34cc). A task still keeps at least one why id.
    $r32 = New-Repo 'r32' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r32
    $rv32 = & "$S\Revise-Task.ps1" -Repo $r32 -Session coord-32 -Task G1.A -AddWhy 'AC-NEW-002' -Note 'test: orphaned AC gets an owner'
    Case 'a why id can be added' (@((T $r32 'G1.A').why) -contains 'AC-NEW-002') ((T $r32 'G1.A').why -join ',')
    Case 'the added why id is reported' (($rv32 -join ' ') -match 'why \+AC-NEW-002') ($rv32 -join ' | ')
    $before32 = @((T $r32 'G1.A').why)
    $rv32b = & "$S\Revise-Task.ps1" -Repo $r32 -Session coord-32 -Task G1.A -RemoveWhy $before32 -Note 'test: must refuse'
    Case 'emptying the why list is refused' (($rv32b -join ' ') -match 'EMPTY-WHY') ($rv32b -join ' | ')
    Case 'the refused batch wrote nothing' ((@((T $r32 'G1.A').why) -join ',') -eq ($before32 -join ',')) ((T $r32 'G1.A').why -join ',')


    # ---- 31. the portability lint refuses a grader that pins a commit id or reads a baseline out of git history, one
    # that names an absolute path under the wiped .loop folder, and one that delegates to an absolute .ps1 that is not
    # there. G2.T01 came back grader-suspect after a full build because a history re-import replaced its 909a2f1e11
    # pin, and 19 of G1.T01 21 clauses were delegated to .loop\criteria\rd-25.ps1, wiped on 2026-09-26
    # (kit items IN-20260929130448-5d94 and IN-20260929141819-17fd). A CONTENT pin is what the rule asks for and stays green.
    $pin = Join-Path $Scratch 'pinned.ps1'
    Set-Content $pin @(
        'param([string] $Root)',
        '$BaseCommit = ''909a2f1e1152959819c9c5aa8e6072f522bf1903''',
        '$b = & git cat-file blob ($BaseCommit + ":x.txt")',
        ('& pwsh -NoProfile -File ''{0}'' -Root $Root' -f (Join-Path $Scratch 'wiped-repo\.loop\criteria\rd-25.ps1')))
    $x = & "$S\Test-GraderPortability.ps1" -Grader $pin
    Case 'lint flags a commit pin' ($LASTEXITCODE -eq 1 -and ($x -join ' ') -match 'FLAG COMMIT-PIN') ($x -join ' / ')
    Case 'lint flags an absolute .loop path' (($x -join ' ') -match 'FLAG OUTSIDE-TREE') ($x -join ' / ')
    Case 'lint flags a delegate that is not there' (($x -join ' ') -match 'FLAG DEAD-DELEGATE .*rd-25') ($x -join ' / ')
    $okpin = Join-Path $Scratch 'content-pinned.ps1'
    Set-Content $okpin @(
        'param([string] $Root)',
        '$want = ''0cf4ac13aabbccddeeff00112233445566778899aabbccddeeff001122334455''',
        '$got = (Get-FileHash (Join-Path $Root ''G1.A.txt'') -Algorithm SHA256).Hash',
        'if ($got -eq $want) { ''PASS C1'' } else { ''FAIL C1'' }')
    $x = & "$S\Test-GraderPortability.ps1" -Grader $okpin
    Case 'a content-pinned grader stays PORTABLE' ($LASTEXITCODE -eq 0 -and ($x -join ' ') -match 'PORTABLE') ($x -join ' / ')

    # ---- 32. the watchdog sweeps the host temp folder. A full GetTempFileName name space broke every build on
    # CORPLTR94 on 2026-09-29 with MSB3021 "There is not enough space on the disk" while C: still had 11 GB free, and
    # about 65,535 stale tmp files were the whole cause (kit item IN-20260929144007-b69a). Only stale entries go.
    $r33 = New-Repo 'r33' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r33
    $tmpRoot = Join-Path $Scratch 'tempsweep'
    New-Item -ItemType Directory -Path $tmpRoot -Force | Out-Null
    $oldStamp = (Get-Date).AddHours(-3)
    foreach ($n in 1..3) { $tf = Join-Path $tmpRoot ("tmp{0:0000}.tmp" -f $n); Set-Content $tf 'x'; (Get-Item $tf).LastWriteTime = $oldStamp }
    $freshTmp = Join-Path $tmpRoot 'tmp9999.tmp'; Set-Content $freshTmp 'x'
    $oldDir = Join-Path $tmpRoot 'speedy-abc'; New-Item -ItemType Directory -Path $oldDir -Force | Out-Null
    Set-Content (Join-Path $oldDir 'f.txt') 'x'; (Get-Item $oldDir).LastWriteTime = $oldStamp
    $newDir = Join-Path $tmpRoot 'speedy-live'; New-Item -ItemType Directory -Path $newDir -Force | Out-Null
    $env:STREAM_TEMP_ROOT = $tmpRoot
    $w33 = & "$S\Invoke-Watchdog.ps1" -Repo $r33 -Session status-33
    $env:STREAM_TEMP_ROOT = Join-Path $Scratch 'hosttemp'   # back to the harness default; later cases must not sweep the host
    Case 'the watchdog sweeps stale tmp files' (($w33 -join ' ') -match 'SWEPT 3 of 4 stale tmp') ($w33 -join ' | ')
    Case 'a fresh tmp file survives the sweep' (Test-Path $freshTmp) $freshTmp
    Case 'a stale speedy temp folder is swept' (($w33 -join ' ') -match 'SWEPT 1 stale speedy' -and -not (Test-Path $oldDir)) ($w33 -join ' | ')
    Case 'a fresh speedy temp folder survives' (Test-Path $newDir) $newDir

    # ---- 32b. the watchdog sweeps tool and test leftovers at the scratch root's top level too. Claude's shells set TEMP
    # to {ScratchRoot}, so .NET GetRandomFileName folders, dotnet workload logs and MSBuildTemp folders land there; the
    # tmp*/speedy-* sweep never matched them and SMVMTR1's D:\tmp held 89,249 top-level entries by 2026-10-17. Only   # history
    # those shapes go, only once a day old, at most STREAM_TEMP_SWEEP_MAX per pass; every other name is left alone.
    $topRoot = Join-Path $Scratch 'scratchtop'
    New-Item -ItemType Directory -Path $topRoot -Force | Out-Null
    $dayOld = (Get-Date).AddDays(-2)
    $oldRand = Join-Path $topRoot 'ab12cd34.x9z'; New-Item -ItemType Directory -Path $oldRand -Force | Out-Null; Set-Content (Join-Path $oldRand 'f.txt') 'x'
    $freshRand = Join-Path $topRoot 'zz99yy88.q1w'; New-Item -ItemType Directory -Path $freshRand -Force | Out-Null
    $oldLog = Join-Path $topRoot 'Microsoft.NET.Workload_4720_20261012_203358_207.log'; Set-Content $oldLog 'x'
    $oldMsb = Join-Path $topRoot 'MSBuildTempab1cd2ef.gh3'; New-Item -ItemType Directory -Path $oldMsb -Force | Out-Null
    $oldSpeedy = Join-Path $topRoot 'speedy-run-screens-0f3a'; New-Item -ItemType Directory -Path $oldSpeedy -Force | Out-Null
    $keep = @('claude', 'streams', 'temp', 'g6t307-skeptic') | ForEach-Object { $k = Join-Path $topRoot $_; New-Item -ItemType Directory -Path $k -Force | Out-Null; $k }
    $keepFile = Join-Path $topRoot 'share-vs-corpus.txt'; Set-Content $keepFile 'x'
    foreach ($o in @($oldRand, $oldLog, $oldMsb, $oldSpeedy, $keepFile) + $keep) { $i = Get-Item -LiteralPath $o -Force; $i.LastWriteTime = $dayOld; $i.CreationTime = $dayOld }
    $env:STREAM_TEMP_ROOT = Join-Path $Scratch 'tempsweep-empty'; New-Item -ItemType Directory -Path $env:STREAM_TEMP_ROOT -Force | Out-Null
    $env:STREAM_SCRATCH_TOP_ROOT = $topRoot; $env:STREAM_TEMP_SWEEP_MAX = '2'
    $w33b = & "$S\Invoke-Watchdog.ps1" -Repo $r33 -Session status-33b
    $env:STREAM_TEMP_SWEEP_MAX = ''
    $w33c = & "$S\Invoke-Watchdog.ps1" -Repo $r33 -Session status-33c
    $env:STREAM_SCRATCH_TOP_ROOT = Join-Path $Scratch 'scratchtop-harness'; $env:STREAM_TEMP_ROOT = Join-Path $Scratch 'hosttemp'
    Case 'scratch top: a pass sweeps at most STREAM_TEMP_SWEEP_MAX leftovers and says more are left' (($w33b -join ' ') -match 'SWEPT 2 stale tool/test temp entries' -and ($w33b -join ' ') -match 'LEFT 2') ($w33b -join ' | ')
    Case 'scratch top: the next pass sweeps the rest' (($w33c -join ' ') -match 'SWEPT 2 stale tool/test temp entries' -and -not (Test-Path $oldRand) -and -not (Test-Path $oldLog) -and -not (Test-Path $oldMsb) -and -not (Test-Path $oldSpeedy)) ($w33c -join ' | ')
    Case 'scratch top: a fresh random-name folder survives' (Test-Path $freshRand) $freshRand
    Case 'scratch top: claude, streams, temp, named folders and other files are never swept' (@($keep | Where-Object { -not (Test-Path $_) }).Count -eq 0 -and (Test-Path $keepFile)) (($keep + $keepFile) -join ', ')

    # ---- 33. junk left in the main tree root is REPORTED, never deleted, and never committed. errs.txt appeared in
    # the repo root on 2026-09-29 holding one line of git stderr from an ad-hoc redirect in some session shell, owned
    # by nobody and seen by nobody (kit item IN-20260929135538-c072).
    $r34 = New-Repo 'r34' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r34
    Set-Content (Join-Path $r34 'errs.txt') "fatal: pathspec 'nuget.config' did not match any files"
    $w34 = & "$S\Invoke-Watchdog.ps1" -Repo $r34 -Session status-34
    Case 'the watchdog reports repo-root junk' (($w34 -join ' ') -match 'JUNK untracked file' -and ($w34 -join ' ') -match 'errs') ($w34 -join ' | ')
    Case 'the watchdog never deletes repo-root junk' (Test-Path (Join-Path $r34 'errs.txt'))
    [void](Build $r34 'G1.A' 'ok' 'build-34')
    $o34 = & "$S\Integrate-Patch.ps1" -Repo $r34 -Session integ-34
    Case 'an integration with junk present still commits' (($o34 -join ' ') -match 'COMMITTED G1') ($o34 -join ' | ')
    Case 'repo-root junk is never committed' (-not @(& git -C $r34 ls-files -- 'errs.txt').Count) 'errs.txt got tracked'


    # ---- 34. the reaper must not destroy work. Breaking a stale build claim moves the task to `ticketed`, and the SAME
    # watchdog pass then reaped its worktree: G4.T003 (498 MB) and G4.T044 (273 MB) went at 17:07:50Z on 2026-09-29 with
    # artifacts.patch unset on both, so the next builder would have started over, and G2.T33 lost 691 MB the same way.
    # The content is exported and attached BEFORE the tree goes, and a tree whose work cannot become a patch is kept.
    $r35 = New-Repo 'r35' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r35
    [void](& "$S\Claim-Task.ps1" -Repo $r35 -Role build -Session build-35)
    $wt35 = & "$S\New-TaskWorktree.ps1" -Repo $r35 -Task G1.A -Session build-35 -WorktreeRoot (Join-Path $Scratch 'wt') | Select-Object -Last 1
    Set-Content (Join-Path $wt35 'G1.A.txt') 'half-finished work'
    [void](& "$S\Update-Task.ps1" -Repo $r35 -Task G1.A -Role build -Session build-35 -To ticketed -Release -Note 'test: handed back with work still in the tree')
    Case 'the salvage fixture starts with no patch' (-not (T $r35 'G1.A').artifacts.patch) (T $r35 'G1.A').artifacts.patch
    $w35 = & "$S\Invoke-Watchdog.ps1" -Repo $r35 -Session status-35
    Case 'the reaper salvages before it reaps' (($w35 -join ' ') -match 'SALVAGED G1\.A') ($w35 -join ' | ')
    $p35 = Join-Path $r35 '.streams\patches\G1.A.patch'
    Case 'the salvaged patch is on disk' (Test-Path $p35) $p35
    Case 'the salvaged patch is attached to the task' ((T $r35 'G1.A').artifacts.patch -eq '.streams\patches\G1.A.patch') (T $r35 'G1.A').artifacts.patch
    Case 'the salvaged patch carries the work' ((Test-Path $p35) -and ((Get-Content -Raw $p35) -match 'half-finished work')) 'no patch, or it does not carry the work'
    Case 'the tree goes once its content is a patch' (-not (Test-Path $wt35)) $wt35
    # A tree whose work cannot become a patch is KEPT: nothing is deleted that has nowhere to go.
    $r36 = New-Repo 'r36' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r36
    [void](& "$S\Claim-Task.ps1" -Repo $r36 -Role build -Session build-36)
    $wt36 = & "$S\New-TaskWorktree.ps1" -Repo $r36 -Task G1.A -Session build-36 -WorktreeRoot (Join-Path $Scratch 'wt') | Select-Object -Last 1
    Set-Content (Join-Path $wt36 'owner.txt') 'edited a file this task does not own'
    [void](& "$S\Update-Task.ps1" -Repo $r36 -Task G1.A -Role build -Session build-36 -To ticketed -Release -Note 'test: work outside the write set')
    $w36 = & "$S\Invoke-Watchdog.ps1" -Repo $r36 -Session status-36
    Case 'a tree whose work cannot be a patch is kept' (($w36 -join ' ') -match 'KEPT G1\.A' -and (Test-Path $wt36)) ($w36 -join ' | ')

    # ---- 36. a grader that never ran is not RED. A G3.T022 grader held "$filter:" inside a double-quoted string,
    # which PowerShell reads as a scope-qualified variable: the file did not parse, the log held a ParserError and no
    # clause line at all, and BOTH kit checks accepted it - Invoke-Grader -ExpectRed reported RED (exit 0) because the
    # exit code was non-zero, and Test-GraderPortability printed PORTABLE. An author would have released a task whose
    # grader cannot run (kit item IN-20260929170537-8760). A missing verdict is now NO-VERDICT exit 6, and the lint
    # parses the file before it applies any other rule.
    $unparseable = "param([string]`$Root)`n`$filter = 'x'`nWrite-Output `"value `$filter: done`""
    $r37 = New-Repo 'r37' ([ordered]@{ 'G1.A' = $unparseable }); $repos += $r37
    $red37 = & "$S\Invoke-Grader.ps1" -Repo $r37 -Task G1.A -Root $r37 -Label red -ExpectRed
    $code37 = $LASTEXITCODE
    Case 'a grader that cannot parse is NO-VERDICT, not RED' ($code37 -eq 6) "exit $code37 :: $($red37 -join ' | ')"
    Case 'NO-VERDICT says the grader printed no clause line' (($red37 -join ' ') -match 'NO-VERDICT') ($red37 -join ' | ')
    $lint37 = & "$S\Test-GraderPortability.ps1" -Grader (Join-Path $r37 '.streams\graders\G1.A.ps1')
    $lc37 = $LASTEXITCODE
    Case 'the lint refuses an unparseable grader' ($lc37 -eq 1 -and ($lint37 -join ' ') -match 'PARSE-ERROR') "exit $lc37 :: $($lint37 -join ' | ')"
    # A grader that DOES run still behaves: red with clause lines is RED, and a parsing grader still lints PORTABLE.
    $r38 = New-Repo 'r38' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r38
    $red38 = & "$S\Invoke-Grader.ps1" -Repo $r38 -Task G1.A -Root $r38 -Label red -ExpectRed
    $code38 = $LASTEXITCODE
    Case 'a real red with clause lines is still RED' ($code38 -eq 0 -and ($red38 -join ' ') -match 'FAIL C1') "exit $code38 :: $($red38 -join ' | ')"
    $lint38 = & "$S\Test-GraderPortability.ps1" -Grader (Join-Path $r38 '.streams\graders\G1.A.ps1')
    Case 'a parsing grader still lints PORTABLE' ($LASTEXITCODE -eq 0 -and ($lint38 -join ' ') -match 'PORTABLE') ($lint38 -join ' | ')

    # ---- 37. the lint refuses a grader whose clause-body helper uses a (?s) dot-all attribute prefix. Every grader
    # written from the G5.T031 pattern copied one, and it matches from the class's FIRST attribute down to the method:
    # measured on tests/Tests.Unit/LocalIdentityTests.cs (26825 chars) the prefix ran 514, 1255, 1630, 3312 and 4459
    # characters where the non-spanning form returns the single attribute line (18 chars), so a clause's pins were met
    # by unrelated code elsewhere in the file - 8 of 14 pins on G3.T022 were pre-met (kit item IN-20260929175416-351a).
    $spanning = "param([string]`$Root)`n`$attrs = [regex]::Match(`$pre, '(?s)((?:[ 	]*\[.*\][ 	]*
?
)+)[^
]*`$')`n'PASS C1'`nexit 0"
    $nonspanning = "param([string]`$Root)`n`$attrs = [regex]::Match(`$pre, '((?:[ 	]*\[[^\]
]*\][ 	]*
?
)+)[^
]*`$')`n'PASS C1'`nexit 0"
    $gspan = Join-Path $Scratch 'spanning.ps1'; Set-Content -Path $gspan -Encoding utf8 -Value $spanning
    $gok = Join-Path $Scratch 'nonspanning.ps1'; Set-Content -Path $gok -Encoding utf8 -Value $nonspanning
    $ls = & "$S\Test-GraderPortability.ps1" -Grader $gspan; $lsc = $LASTEXITCODE
    Case 'the lint refuses a dot-all attribute prefix' ($lsc -eq 1 -and ($ls -join ' ') -match 'SPANNING-ATTRS') "exit $lsc :: $($ls -join ' | ')"
    $lo = & "$S\Test-GraderPortability.ps1" -Grader $gok; $loc = $LASTEXITCODE
    Case 'the non-spanning attribute prefix is PORTABLE' ($loc -eq 0 -and ($lo -join ' ') -match 'PORTABLE') "exit $loc :: $($lo -join ' | ')"

    # ---- 38. Add-Tasks must refuse a new task whose write set overlaps an OPEN task with no dependsOn chain, the same
    # condition Revise-Task refuses. On 2026-09-29 it ADDED G2.T95 over src/Web/Secrets/SecretsWorkspace.cs, which three
    # planned tasks already owned, and left a board that the next Revise-Task refused outright (kit item
    # IN-20260929175717-5b24). The refusal writes nothing: the task must not appear.
    $r39 = New-Repo 'r39' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r39
    $clash = Join-Path $Scratch 'r39-clash.json'
    @{ groups = @(); tasks = @(@{ id = 'G1.CLASH'; group = 'G1'; title = 'overlaps G1.A with no chain'; why = @('AC-1'); kind = 'code'
                                  writeSet = @('G1.A.txt'); dependsOn = @(); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $clash
    $addOut = & "$S\Add-Tasks.ps1" -Repo $r39 -Role plan -Session plan-39 -File $clash
    $addCode = $LASTEXITCODE
    Case 'Add-Tasks refuses an overlapping new task' ($addCode -eq 2 -and ($addOut -join ' ') -match 'overlaps G1\.A') "exit $addCode :: $($addOut -join ' | ')"
    Case 'the refused task was not written' (-not (T $r39 'G1.CLASH')) 'G1.CLASH reached tasks.json'
    Case 'the board is still ordered after the refusal' ((& "$S\Test-BoardOrder.ps1" -Repo $r39) -match 'CLEAN') 'board unordered after a refused add'
    # The real G2.T95 shape: the overlap is OFF the diagonal - the new task's SECOND path is the owner's FIRST path.
    # Test-WriteSetOverlap used nested foreach over its two parameters, and on PowerShell 7.6.6 the inner enumeration
    # does not restart for the second element of $A when both are parameter-bound, so this pair was never compared.
    $off = Join-Path $Scratch 'r39-offdiag.json'
    @{ groups = @(); tasks = @(@{ id = 'G1.OFFDIAG'; group = 'G1'; title = 'second path overlaps the owner first path'; why = @('AC-1'); kind = 'code'
                                  writeSet = @('brand-new-file.txt', 'G1.A.txt'); dependsOn = @(); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $off
    $offOut = & "$S\Add-Tasks.ps1" -Repo $r39 -Role plan -Session plan-39 -File $off
    $offCode = $LASTEXITCODE
    Case 'an off-diagonal overlap is refused too' ($offCode -eq 2 -and ($offOut -join ' ') -match 'overlaps G1\.A') "exit $offCode :: $($offOut -join ' | ')"
    Case 'the off-diagonal task was not written' (-not (T $r39 'G1.OFFDIAG')) 'G1.OFFDIAG reached tasks.json'
    # The helper itself, directly: every pair must be compared, not just the diagonal.
    . "$S\lib\Streams.ps1"
    Case 'Test-WriteSetOverlap compares off-diagonal pairs' (Test-WriteSetOverlap @('x/none.cs', 'src/same.cs') @('src/same.cs', 'y/none.cs')) 'A[1] x B[0] was not compared'
    # A new task that DOES chain onto the owner is still accepted.
    $ok39 = Join-Path $Scratch 'r39-ok.json'
    @{ groups = @(); tasks = @(@{ id = 'G1.CHAINED'; group = 'G1'; title = 'shares G1.A.txt but depends on G1.A'; why = @('AC-1'); kind = 'code'
                                  writeSet = @('G1.A.txt'); dependsOn = @('G1.A'); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $ok39
    $okOut = & "$S\Add-Tasks.ps1" -Repo $r39 -Role plan -Session plan-39 -File $ok39
    Case 'a chained overlapping task is still accepted' ((($okOut -join ' ') -match 'ADDED G1\.CHAINED') -and (T $r39 'G1.CHAINED')) ($okOut -join ' | ')

    # ---- 39. the integrator must not write main while a main-tree grader build holds the lock. On 2026-09-29 a G6.T025
    # RED run reported error CS1061 for a member HEAD declares: Tests.Unit had compiled against an Application assembly
    # written before an integrator's apply landed under it, so the author read a phantom defect on a sound ticket
    # (kit item IN-20260929183913-7850). Integrate-Patch now takes the SAME main-grader.lock around every write to main.
    $r40 = New-Repo 'r40' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r40
    [void](Build $r40 'G1.A' 'ok now' 'build-40')
    $lp40 = Join-Path $r40 '.streams\main-grader.lock'
    $held40 = [IO.FileStream]::new($lp40, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose)
    $before40 = (git -C $r40 status --porcelain) -join '|'
    try {
        $env:STREAM_MAIN_LOCK_WAIT_SECONDS = '2'
        $o40 = & "$S\Integrate-Patch.ps1" -Repo $r40 -Session integ-40
        Case 'integrate refuses to write main while the grader lock is held' ((($o40 -join ' ') -match 'RETRY G1\.A') -and (($o40 -join ' ') -match 'main tree busy')) ($o40 -join ' | ')
        Case 'the main tree is untouched while the lock is held' (((git -C $r40 status --porcelain) -join '|') -eq $before40) 'main tree changed under a held lock'
        Case 'the task is still built after the refusal' ((T $r40 'G1.A').state -eq 'built') (T $r40 'G1.A').state
    } finally { $held40.Dispose(); Remove-Item Env:STREAM_MAIN_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue }
    $o40b = & "$S\Integrate-Patch.ps1" -Repo $r40 -Session integ-40
    Case 'integrate lands once the lock is free' ((T $r40 'G1.A').state -eq 'integrated') "state $((T $r40 'G1.A').state) :: $($o40b -join ' | ')"
    Case 'the integrator leaves no main-grader lock behind' (-not (Test-Path $lp40)) $lp40

    # ---- 40. the lint must refuse a ROOTED data path anywhere in a grader, not only one under .loop. G4.T063 line 11
    # read param([string] $Root, [string] $Dir = 'D:\tmp\speedy-mockups\g4\activity-run-state') and linted PORTABLE, so   # history
    # the grader read the D:\tmp copy whatever tree it was handed: 1 failing clause with -Dir under -Root against 4 with   # history
    # -Dir at the D:\tmp copy. Same class as G3.T040 grading green off a D:\tmp leftover and as G1.T01's wiped .loop   # history
    # delegate (kit item IN-20260929192818-8827). An absolute .ps1 delegate stays exempt - DEAD-DELEGATE covers that
    # one, and case 8 above proves a shim still lints PORTABLE.
    $g41 = Join-Path $Scratch 'rooted-default.ps1'
    Set-Content -Path $g41 -Encoding utf8 -Value @(
        ('param([string] $Root, [string] $Dir = ''{0}'')' -f (Join-Path $Scratch 'speedy-mockups\g4\activity-run-state')),
        'if (Test-Path (Join-Path $Dir ''index.html'')) { ''PASS C1'' } else { ''FAIL C1'' }')
    $l41 = & "$S\Test-GraderPortability.ps1" -Grader $g41; $c41 = $LASTEXITCODE
    Case 'the lint refuses a rooted path in a param default' ($c41 -eq 1 -and ($l41 -join ' ') -match 'OUTSIDE-TREE') "exit $c41 :: $($l41 -join ' | ')"
    $g42 = Join-Path $Scratch 'rooted-unc.ps1'
    Set-Content -Path $g42 -Encoding utf8 -Value @(
        'param([string] $Root)',
        '$p = ''\\fixturehost\share\mockups\index.html''',   # example-path: the UNC literal is the lint's input
        'if (Test-Path $p) { ''PASS C1'' } else { ''FAIL C1'' }')
    $l42 = & "$S\Test-GraderPortability.ps1" -Grader $g42; $c42 = $LASTEXITCODE
    Case 'the lint refuses a UNC data path' ($c42 -eq 1 -and ($l42 -join ' ') -match 'OUTSIDE-TREE') "exit $c42 :: $($l42 -join ' | ')"
    # The same grader reading the same folder off $Root is what the rule asks for, and still lints clean.
    $g43 = Join-Path $Scratch 'rooted-fixed.ps1'
    Set-Content -Path $g43 -Encoding utf8 -Value @(
        'param([string] $Root, [string] $Dir = ''.streams\mockups\g4\activity-run-state'')',
        'if (Test-Path (Join-Path $Root (Join-Path $Dir ''index.html''))) { ''PASS C1'' } else { ''FAIL C1'' }')
    $l43 = & "$S\Test-GraderPortability.ps1" -Grader $g43; $c43 = $LASTEXITCODE
    Case 'a $Root-derived path is still PORTABLE' ($c43 -eq 0 -and ($l43 -join ' ') -match 'PORTABLE') "exit $c43 :: $($l43 -join ' | ')"

    # ---- 41. the owner-question number the owner triages by must count ESCALATIONS, not the whole queue. On 2026-09-29
    # the status tile and the terminal line both read 620 while the owner-actionable number was 16: the other 604 lines
    # were '<task> | <question> | <default applied> | <reasoning>' records, decisions already taken under standing owner
    # authority, which need no answer (kit item IN-20260929231435-6f52). Both shapes stay IN the queue, because a bare
    # '- *' filter once hid side effects addressed to the owner by name - the fix is a second count, not a swapped
    # filter. A RESOLVED line of either shape is out of both counts.
    $r41 = New-Repo 'r41' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r41
    Set-Content -Path (Join-Path $r41 '.streams\owner\questions.md') -Encoding utf8 -Value @(
        '- G1.A the owner has to choose the store | recommendation | reasoning',
        'G1.A | which timeout | 30s applied | the donor used 30s',
        'G1.A | which retry count | 3 applied | the donor used 3',
        'G1.A | which page size | 500 applied | measured',
        'RESOLVED - G1.A the owner already chose the host | recommendation | reasoning',
        'RESOLVED G1.A | which port | 8080 applied | the donor used 8080')
    $m41 = & "$S\Get-StreamStatus.ps1" -Repo $r41 -Json | ConvertFrom-Json
    # Read the member defensively: a build that never grew the second count must report FAIL here, not abort the harness.
    $e41 = @(if ($m41.owner.PSObject.Properties.Name -contains 'escalations') { $m41.owner.escalations })
    Case 'the queue still carries both shapes' (@($m41.owner.questions).Count -eq 4) ('queue count is ' + @($m41.owner.questions).Count)
    Case 'the escalations are counted apart from the applied defaults' ($e41.Count -eq 1) ('escalation count is ' + $e41.Count)
    Case 'a RESOLVED escalation is out of both counts' (($e41 -join ' ') -notmatch 'already chose') 'a resolved bullet is still counted'
    $t41 = & "$S\Get-StreamStatus.ps1" -Repo $r41
    Case 'the terminal line carries both numbers' (($t41 -join ' ') -match 'questions 4 \(1 to answer, 3 applied defaults\)') ($t41 -join ' / ')
    $p41 = Join-Path $Scratch 'r41-status.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $r41 -Session status-41 -Out $p41 -MirrorFile (Join-Path $Scratch 'r41-no-mirror.txt'))
    # The page must exist at all: this fixture carries ONE group, and the category table looked its named categories up
    # with [0] on a possibly empty array, which throws under Set-StrictMode and left no page written.
    Case 'the page builds for a board that does not carry every named category' (Test-Path $p41) 'no page was written'
    $h41 = Get-Content -Raw $p41
    Case 'the tile shows the escalation count' ($h41 -match '(?s)<a class="tile owner"[^>]*><b>1</b>') 'tile is not the escalation count'
    Case 'the tile does not show the whole-queue count' ($h41 -notmatch '(?s)<a class="tile owner"[^>]*><b>4</b>') 'tile shows the whole-queue count'
    Case 'the tile still names the applied defaults' ($h41 -match '(?s)<a class="tile owner".*?3 applied') 'tile drops the applied-default number'

    # ---- 42. a grader carrying a CONTROL BYTE must not lint PORTABLE. '\b' written into a double-quoted shell
    # heredoc arrives as 0x08, so a pin like '\bAverage\b' becomes '<BS>Average<BS>' and can never match any C# file:
    # the grader parses, prints FAIL, and its red says nothing about the code. G5.T014 cost a full build cycle this
    # way on 2026-09-29 (grader line 272, five 0x08 bytes; C1-C17 and C19 PASS with 18/18 targeted tests, C18
    # unsatisfiable) and G4.T062 line 278 carried the same byte while ticketed. Measured 2 of 156 live graders, so
    # the rule catches the defect and nothing else. TAB, CR and LF stay legal - a grader is full of all three.
    $g44 = Join-Path $Scratch 'control-byte.ps1'
    $bs = [char]0x08
    Set-Content -Path $g44 -Encoding utf8 -Value @(
        'param([string] $Root)',
        "`$st = Get-Content -Raw (Join-Path `$Root 'src/A.cs')",
        "if (`$st -cnotmatch '(?s)${bs}Average${bs}') { 'FAIL C1' } else { 'PASS C1' }")
    $l44 = & "$S\Test-GraderPortability.ps1" -Grader $g44; $c44 = $LASTEXITCODE
    Case 'the lint refuses a control byte in a clause pin' ($c44 -eq 1 -and ($l44 -join ' ') -match 'CONTROL-BYTE') "exit $c44 :: $($l44 -join ' | ')"
    Case 'the control-byte flag names the line' (($l44 -join ' ') -match 'control-byte\.ps1:3') "no line number :: $($l44 -join ' | ')"
    # The same grader with a real \b, and with tabs and CRLF in it, is still PORTABLE: the rule must not fire on the
    # whitespace every grader carries.
    $g45 = Join-Path $Scratch 'control-byte-clean.ps1'
    Set-Content -Path $g45 -Encoding utf8 -Value @(
        'param([string] $Root)',
        "`t`$st = Get-Content -Raw (Join-Path `$Root 'src/A.cs')",
        "if (`$st -cnotmatch '(?s)\bAverage\b') { 'FAIL C1' } else { 'PASS C1' }")
    $l45 = & "$S\Test-GraderPortability.ps1" -Grader $g45; $c45 = $LASTEXITCODE
    Case 'a real \b with tabs is still PORTABLE' ($c45 -eq 0 -and ($l45 -join ' ') -match 'PORTABLE') "exit $c45 :: $($l45 -join ' | ')"

    # ---- 43. the watchdog must not OVERWRITE a patch a session handed off, and must not harvest a tree something is
    # still writing to. On 2026-09-30 status-79edb8dd found G3.T030's build claim stale (a blind verifier was running
    # long tests, and `dotnet test` does not beat the claim), harvested the tree mid-verification and replaced the good
    # patch with one carrying the verifier's deliberate mutation - an Abandon button that leaves the server context and
    # the candidate authenticator seed alive - with nothing on the board saying the artifact was unverified
    # (kit item IN-20260930005914-aa4d). Two rules: an existing patch is never overwritten (the harvest goes to
    # <task>.salvage.patch and artifacts.patch keeps pointing at the handed-off file), and a tree written to inside the
    # quiet period is neither harvested nor reaped.
    $r43 = New-Repo 'r43' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r43
    Build $r43 'G1.A' 'handed off' 'build-43a'                      # leaves a real patch and a built task
    $good = Join-Path $r43 '.streams\patches\G1.A.patch'
    Case 'the handed-off patch exists' (Test-Path $good) 'no patch after the build'
    $goodHash = (Get-FileHash $good).Hash
    # A second tree for the same task, with a different change in it, and a DEAD claim over it.
    # The claim goes on FIRST: New-TaskWorktree.ps1 writes the base through Update-Task.ps1, which refuses with
    # CLAIM-LOST when the session does not hold the claim, and then no tree is ever created.
    $P43 = Get-StreamPaths $r43
    $live43 = Get-Now
    $j43 = J $r43
    foreach ($t in $j43.tasks) { if ($t.id -eq 'G1.A') {
        $t.state = 'building'
        $t.claim = @{ session = 'build-43b'; role = 'build'; at = $live43; beat = $live43 } } }
    Set-Content -Path (Join-Path $r43 '.streams\tasks.json') -Encoding utf8 -Value ($j43 | ConvertTo-Json -Depth 50)
    $wt43 = & "$S\New-TaskWorktree.ps1" -Repo $r43 -Task 'G1.A' -Session 'build-43b' -WorktreeRoot (Join-Path $Scratch 'wt43') | Select-Object -Last 1
    if (-not (Test-Path -PathType Container $wt43)) { throw "case 43: New-TaskWorktree.ps1 returned '$wt43'" }
    Set-Content (Join-Path $wt43 'G1.A.txt') 'mid-verification mutation'
    # Now the builder dies: a three-hour-old beat, with the tree it was inside still on the task.
    $dead43 = (Get-Date).ToUniversalTime().AddHours(-3).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $j43 = J $r43
    foreach ($t in $j43.tasks) { if ($t.id -eq 'G1.A') {
        $t.claim.at = $dead43; $t.claim.beat = $dead43
        $t.base = @{ worktree = $wt43 } } }
    Set-Content -Path (Join-Path $r43 '.streams\tasks.json') -Encoding utf8 -Value ($j43 | ConvertTo-Json -Depth 50)
    $env:STREAM_REAP_QUIET_MINUTES = '10'                           # this case IS the quiet-period case
    # Freshly written: the quiet-period rule must keep the tree AND the patch.
    $w43 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r43 -Session 'status-43')
    Case 'a tree written to just now is kept, not harvested' ((($w43 -join ' ') -match 'KEPT G1\.A') -and (Test-Path $wt43)) ($w43 -join ' | ')
    Case 'the handed-off patch is untouched by that pass' ((Get-FileHash $good).Hash -eq $goodHash) 'the patch changed while the tree was still being written to'
    # Now age every file in the tree past the quiet period. The harvest may run, and must go ASIDE.
    foreach ($f in @(Get-ChildItem $wt43 -Recurse -File -Force)) { $f.LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-90) }
    (Get-Item $wt43).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-90)
    $w43b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r43 -Session 'status-43')
    Case 'the quiet tree is harvested ASIDE, not over the handed-off patch' (($w43b -join ' ') -match 'SALVAGED-ASIDE G1\.A') ($w43b -join ' | ')
    Case 'the handed-off patch is still byte-identical' ((Get-FileHash $good).Hash -eq $goodHash) 'the watchdog overwrote a handed-off patch'
    Case 'the salvage is written beside it' (Test-Path (Join-Path $r43 '.streams\patches\G1.A.salvage.patch')) 'no salvage file'
    $t43 = T $r43 'G1.A'
    Case 'artifacts.patch still names the handed-off patch' ($t43.artifacts.patch -eq '.streams\patches\G1.A.patch') "artifacts.patch is $($t43.artifacts.patch)"
    $env:STREAM_REAP_QUIET_MINUTES = '0'
$env:STREAM_RUNNER_START_JITTER_SECONDS = '0'   # no random start wait for the runner cases
    Case 'the history says the salvage is UNVERIFIED' ((@($t43.history | ForEach-Object { $_.note }) -join ' ') -match 'UNVERIFIED salvage') 'no unverified note on the task'

    # ---- 43b. a tree git cannot read is KEPT, and the pass goes on (kit item IN-20261018010634-24c4). G9.T010's
    # `git worktree add` died part-way and left an admin folder with no commondir, so `git ls-files` failed inside
    # Export-TaskPatch.ps1, its throw ended the watchdog, and every status tick reported THREW.
    $r43b = New-Repo 'r43b' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r43b
    $now43b = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $j = J $r43b
    foreach ($t in $j.tasks) { if ($t.id -eq 'G1.A') {
        $t.state = 'building'
        $t.claim = @{ session = 'build-43c'; role = 'build'; at = $now43b; beat = $now43b } } }
    Set-Content -Path (Join-Path $r43b '.streams\tasks.json') -Encoding utf8 -Value ($j | ConvertTo-Json -Depth 50)
    $wt43b = & "$S\New-TaskWorktree.ps1" -Repo $r43b -Task 'G1.A' -Session 'build-43c' -WorktreeRoot (Join-Path $Scratch 'wt43b') | Select-Object -Last 1
    if (-not (Test-Path -PathType Container $wt43b)) { throw "case 43b: New-TaskWorktree.ps1 returned '$wt43b'" }
    Set-Content (Join-Path $wt43b 'G1.A.txt') 'half-built'
    $admin43b = ((Get-Content (Join-Path $wt43b '.git') -Raw) -replace '^gitdir:\s*', '').Trim()
    Remove-Item (Join-Path $admin43b 'commondir') -Force
    $j = J $r43b
    foreach ($t in $j.tasks) { if ($t.id -eq 'G1.A') { $t.state = 'ticketed'; $t.claim = $null; $t.base = @{ worktree = $wt43b } } }
    Set-Content -Path (Join-Path $r43b '.streams\tasks.json') -Encoding utf8 -Value ($j | ConvertTo-Json -Depth 50)
    foreach ($f in @(Get-ChildItem $wt43b -Recurse -File -Force)) { $f.LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-90) }
    (Get-Item $wt43b).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-90)
    $threw43b = $null
    try { $w43c = @(& "$S\Invoke-Watchdog.ps1" -Repo $r43b -Session 'status-43b') } catch { $threw43b = $_.Exception.Message }
    Case 'a tree git cannot read does not end the watchdog' (-not $threw43b) "threw: $threw43b"
    Case 'that tree is KEPT and named' ((($w43c -join ' ') -match 'KEPT G1\.A .*export threw') -and (Test-Path (Join-Path $wt43b 'G1.A.txt'))) ($w43c -join ' | ')

    # ---- 44. a FAILED worktree removal must be retried and must never read as QUIET. `git worktree remove --force`
    # drops the registration before the directory delete, so when the delete loses a race with an open file the next
    # pass no longer sees the tree as one of this repo's worktrees and the empty-husk rule skips it in silence:
    # G3.T030's tree sat at 75 MB through two QUIET cycles on 2026-09-30 (kit item IN-20260930004842-422a). The ledger
    # records the intent, so a directory whose last line says the removal FAILED is retried until it is gone.
    $r44 = New-Repo 'r44' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r44
    $root44 = Join-Path $Scratch 'wt44'
    $leaked = Join-Path $root44 'G1.A'
    New-Item -ItemType Directory -Path $leaked -Force | Out-Null
    Set-Content (Join-Path $leaked 'big.txt') ('x' * 4096)          # not empty, so the husk rule cannot touch it
    $P44 = Get-StreamPaths $r44
    Add-LineTo $P44.Worktrees ("- G1.A | {0} | {1} | building" -f $leaked, (Get-Now))
    Add-LineTo $P44.Worktrees ("- G1.A | {0} | {1} | removal FAILED (directory still present)" -f $leaked, (Get-Now))
    $j44 = J $r44
    foreach ($t in $j44.tasks) { if ($t.id -eq 'G1.A') { $t.base = @{ worktree = $leaked } } }
    Set-Content -Path (Join-Path $r44 '.streams\tasks.json') -Encoding utf8 -Value ($j44 | ConvertTo-Json -Depth 50)
    $w44 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r44 -Session 'status-44')
    Case 'the leaked tree is removed on retry' (-not (Test-Path $leaked)) ($w44 -join ' | ')
    Case 'the retry is reported, so the cycle is not QUIET' ((($w44 -join ' ') -match 'REMOVED') -and (($w44 -join ' ') -notmatch '^QUIET$')) ($w44 -join ' | ')
    Case 'the ledger records the retry removal' ((Get-LastWorktreeLedgerStatus $P44 $leaked) -match 'removed \(watchdog retry') (Get-LastWorktreeLedgerStatus $P44 $leaked)

    # ---- 45. a task whose write set is entirely under .streams is delivered IN PLACE. .streams is in
    # .git/info/exclude, so git never reports those files: a worktree base cannot carry them, `git diff` cannot see
    # them and Export-TaskPatch can only answer EMPTY. On 2026-09-30 eight planned tasks were in exactly that shape -
    # two grader repairs and six AC-coverage audits under .streams\plans - and none of them could be built at all
    # (kit item IN-20260930022231-9702). Three rules: the export says IN-PLACE and states the procedure instead of
    # EMPTY, the integrator lands such a task with no tree change the way it lands a mockup, and a worktree whose
    # DEPENDENCY is one of them does not try to git apply the artifact as though it were a patch.
    $r45 = New-Repo 'r45' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r45
    $P45 = Get-StreamPaths $r45
    $now45 = Get-Now
    function T45([string] $id, [string] $state, $ws, $deps, $patch) {
        @{ id = $id; group = 'G1'; title = $id; why = @('AC-1'); kind = 'code'; writeSet = @($ws); dependsOn = @($deps)
           estMinutes = 5; state = $state; claim = $null
           artifacts = @{ ticket = ".streams\tickets\G1.A.md"; grader = ".streams\graders\G1.A.ps1"; patch = $patch; verdict = $(if ($patch) { 'PASS' } else { $null }) }
           history = @(@{ at = $now45; by = 'plan-1'; to = $state; note = 'fixture' }) }
    }
    $j45 = J $r45
    $j45.tasks = @($j45.tasks) + @(
        (T45 'G1.P' 'built' @('.streams/graders/G1.A.ps1') @() '.streams\graders\G1.A.ps1'),  # in place, handed off: artifacts.patch is the ARTIFACT's path, not a patch file
        (T45 'G1.D' 'ticketed' @('G1.D.txt') @('G1.P') $null),                   # depends on the in-place task
        (T45 'G1.N' 'built'    @('G1.N.txt') @() $null),                         # built with NO patch
        (T45 'G1.E' 'ticketed' @('G1.E.txt') @('G1.N') $null))
    Set-Content -Path (Join-Path $r45 '.streams\tasks.json') -Encoding utf8 -Value ($j45 | ConvertTo-Json -Depth 50)
    # (c) a worktree whose dependency delivers in place: the note is printed and the path is still the last line
    $j45 = J $r45
    foreach ($t in $j45.tasks) { if ($t.id -in @('G1.D', 'G1.E')) { $t.state = 'building'; $t.claim = @{ session = 'build-45'; role = 'build'; at = (Get-Now); beat = (Get-Now) } } }
    Set-Content -Path (Join-Path $r45 '.streams\tasks.json') -Encoding utf8 -Value ($j45 | ConvertTo-Json -Depth 50)
    $out45 = @(& "$S\New-TaskWorktree.ps1" -Repo $r45 -Task 'G1.D' -Session 'build-45' -WorktreeRoot (Join-Path $Scratch 'wt45'))
    $wt45 = $out45 | Select-Object -Last 1
    Case 'a worktree names its in-place dependency instead of applying it' ((($out45 -join ' ') -match 'IN-PLACE dependency G1\.P') -and (Test-Path -PathType Container $wt45)) ($out45 -join ' | ')
    # (d) a dependency that is built with NO patch is called out, because its change is not in the base
    $out45b = @(& "$S\New-TaskWorktree.ps1" -Repo $r45 -Task 'G1.E' -Session 'build-45' -WorktreeRoot (Join-Path $Scratch 'wt45'))
    Case 'a built dependency with no patch is reported, not silently skipped' ((($out45b -join ' ') -match 'WARN dependency G1\.N is built with NO patch') -and (Test-Path -PathType Container ($out45b | Select-Object -Last 1))) ($out45b -join ' | ')
    # (a) the export refuses with the procedure, not EMPTY
    $ex45 = @(& "$S\Export-TaskPatch.ps1" -Repo $r45 -Task 'G1.P' -Worktree $wt45); $exc45 = $LASTEXITCODE
    Case 'the export says IN-PLACE, not EMPTY' ($exc45 -eq 2 -and ($ex45 -join ' ') -match 'IN-PLACE G1\.P' -and ($ex45 -join ' ') -notmatch 'EMPTY') "exit $exc45 :: $($ex45 -join ' | ')"
    Case 'the export states where the artifact goes' (($ex45 -join ' ') -match 'set artifacts\.patch to that path') ($ex45 -join ' | ')
    # (b) the integrator lands it with no tree change
    $head45 = (Invoke-Git $r45 @('rev-parse', 'HEAD')) | Select-Object -First 1
    $in45 = @(& "$S\Integrate-Patch.ps1" -Repo $r45 -Session 'integ-45' -Task 'G1.P')
    Case 'the integrator lands an in-place task with no tree change' (($in45 -join ' ') -match 'INTEGRATED G1\.P \(in place\)') ($in45 -join ' | ')
    Case 'the in-place task is integrated' ((T $r45 'G1.P').state -eq 'integrated') (T $r45 'G1.P').state
    Case 'no commit was made for it' (((Invoke-Git $r45 @('rev-parse', 'HEAD')) | Select-Object -First 1) -eq $head45) 'HEAD moved'

    # ---- 46. a released task's estMinutes and estBasis are correctable. Until 2026-09-30 Revise-Task.ps1 could change a
    # write set, a dependsOn, why ids, the title, the targeted tests and the release, and NOTHING could change the estimate:
    # G2.T97 sat at 65 minutes with the basis "read a published gallery back and lay it down, 40 + 25 overhead" after that
    # title was measured false and the work repriced at 110-150, G2.T36 carried 70 for a seven-file row and G2.T99 45 for a
    # row two files wider. Every watchdog line ("building N min, estimate M") and every group ETA then read from a number no
    # role could fix, and the batch form did not even complain: the key was ignored in silence. A change must be a positive
    # whole number AND must restate the basis, because correcting the number is exactly what makes the old basis false.
    $r46 = New-Repo 'r46' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r46
    function Rev46([string] $name, [Collections.IDictionary] $edit) {
        $f = Join-Path $Scratch "$name.json"
        @{ note = "test 46 $name"; edits = @($edit) } | ConvertTo-Json -Depth 10 | Set-Content $f
        $out = @(& "$S\Revise-Task.ps1" -Repo $r46 -Session coord-46 -File $f)
        [pscustomobject]@{ Out = ($out -join ' | '); Code = $LASTEXITCODE; Task = (T $r46 'G1.A') }
    }
    $a46 = Rev46 'a' ([ordered]@{ task = 'G1.A'; estMinutes = 130; estBasis = 'nine pages rebuilt from the built component, 105 + 25 overhead'; note = 'estimate corrected' })
    Case 'an estMinutes correction is applied' ($a46.Code -eq 0 -and [int] $a46.Task['estMinutes'] -eq 130) "exit $($a46.Code) est $($a46.Task['estMinutes']) :: $($a46.Out)"
    Case 'the new estBasis is stored beside it' ([string] $a46.Task['estBasis'] -match 'nine pages rebuilt') "basis '$($a46.Task['estBasis'])'"
    Case 'the estimate change is named in the REVISED line' ($a46.Out -match 'est 5 -> 130') $a46.Out
    # a change with no new basis is refused, and nothing is written
    $b46 = Rev46 'b' ([ordered]@{ task = 'G1.A'; estMinutes = 200; note = 'must refuse' })
    Case 'an estMinutes change with no estBasis is refused' ($b46.Code -eq 2 -and $b46.Out -match 'EST-NO-BASIS G1\.A') "exit $($b46.Code) :: $($b46.Out)"
    Case 'the refused estimate wrote nothing' ([int] $b46.Task['estMinutes'] -eq 130) "est $($b46.Task['estMinutes'])"
    # zero and negative are refused: a row with no estimate at all is worse than a row with a wrong one
    $c46 = Rev46 'c' ([ordered]@{ task = 'G1.A'; estMinutes = -5; estBasis = 'nonsense'; note = 'must refuse' })
    Case 'a non-positive estMinutes is refused' ($c46.Code -eq 2 -and $c46.Out -match 'BAD-EST G1\.A') "exit $($c46.Code) :: $($c46.Out)"
    # the basis alone may be corrected without touching the number
    $d46 = Rev46 'd' ([ordered]@{ task = 'G1.A'; estBasis = 'same 130 minutes, basis reworded'; note = 'basis only' })
    Case 'the estBasis alone is correctable' ($d46.Code -eq 0 -and $d46.Out -match 'estBasis' -and [int] $d46.Task['estMinutes'] -eq 130) "exit $($d46.Code) :: $($d46.Out)"
    # ---- 47. a folder delivered IN PLACE carries a hand-off fingerprint, and the integrator reports a folder that changed
    # since the verdict. An in-place row hands off a PATH, not a patch, so between built and integrated the deliverable is a
    # live directory. On 2026-09-30 build-202609291226-3a11 corrected one prose sentence in
    # .streams/mockups/g2/welcome/RECOVERY.md after G2.T97 went built and its claim was released, and its inbox item reached
    # the integrator FIVE MINUTES AFTER that folder had already been integrated with 'mockup: no tree change'. The edit was
    # right and both graders were re-run green; the board simply could not see it (kit item IN-20260930120446-f9f5).
    $r47 = New-Repo 'r47' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r47
    $dir47 = Join-Path $r47 '.streams\plans\g1audit'
    New-Item -ItemType Directory -Path $dir47 -Force | Out-Null
    Set-Content (Join-Path $dir47 'AUDIT.md') 'the audit as the verifier read it'
    Set-Content (Join-Path $dir47 'NOTES.md') 'notes'
    $j47 = J $r47
    $j47.tasks = @($j47.tasks) + @(
        ([ordered]@{ id = 'G1.IP'; group = 'G1'; title = 'in place'; why = @('AC-1'); kind = 'docs'
                     writeSet = @('.streams/plans/g1audit/'); dependsOn = @(); estMinutes = 5; state = 'building'
                     claim = @{ session = 'build-47'; role = 'build'; at = (Get-Now); beat = (Get-Now) }
                     artifacts = @{ ticket = '.streams\tickets\G1.A.md'; grader = '.streams\graders\G1.A.ps1'; patch = $null; verdict = $null }; history = @() }),
        ([ordered]@{ id = 'G1.IQ'; group = 'G1'; title = 'in place, untouched'; why = @('AC-1'); kind = 'docs'
                     writeSet = @('.streams/plans/g1quiet/'); dependsOn = @(); estMinutes = 5; state = 'building'
                     claim = @{ session = 'build-47'; role = 'build'; at = (Get-Now); beat = (Get-Now) }
                     artifacts = @{ ticket = '.streams\tickets\G1.A.md'; grader = '.streams\graders\G1.A.ps1'; patch = $null; verdict = $null }; history = @() }))
    Set-Content -Path (Join-Path $r47 '.streams\tasks.json') -Encoding utf8 -Value ($j47 | ConvertTo-Json -Depth 50)
    $quiet47 = Join-Path $r47 '.streams\plans\g1quiet'
    New-Item -ItemType Directory -Path $quiet47 -Force | Out-Null
    Set-Content (Join-Path $quiet47 'QUIET.md') 'delivered once and never touched'
    # (a) the hand-off writes the fingerprint and records it in artifacts
    $h47 = @(& "$S\Update-Task.ps1" -Repo $r47 -Task 'G1.IP' -Role build -Session 'build-47' -To built -Release -Artifacts @{ patch = '.streams\plans\g1audit'; verdict = 'PASS' })
    $man47 = Join-Path $r47 '.streams\patches\G1.IP.manifest.json'
    Case 'an in-place hand-off writes a delivery manifest' (Test-Path -LiteralPath $man47) ($h47 -join ' | ')
    Case 'the manifest path is recorded in artifacts' ((T $r47 'G1.IP').artifacts['manifest'] -eq '.streams/patches/G1.IP.manifest.json') "$((T $r47 'G1.IP').artifacts['manifest'])"
    # The read is guarded so that the whole case still reports on a base copy that writes no manifest at all.
    $mj47 = if (Test-Path -LiteralPath $man47) { Get-Content -Raw $man47 | ConvertFrom-Json -AsHashtable -Depth 10 } else { @{ files = @() } }
    Case 'the manifest hashes every delivered file' (@($mj47['files']).Count -eq 2 -and @($mj47['files'] | Where-Object { $_['path'] -eq '.streams/plans/g1audit/AUDIT.md' -and $_['sha256'] -and $_['bytes'] -gt 0 }).Count -eq 1) ($mj47 | ConvertTo-Json -Depth 5 -Compress)
    # (b) a folder edited after hand-off is REPORTED by the integrator, and still integrates
    & "$S\Update-Task.ps1" -Repo $r47 -Task 'G1.IQ' -Role build -Session 'build-47' -To built -Release -Artifacts @{ patch = '.streams\plans\g1quiet'; verdict = 'PASS' } | Out-Null
    Set-Content (Join-Path $dir47 'AUDIT.md') 'the audit AFTER a correction nobody recorded'
    Set-Content (Join-Path $dir47 'EXTRA.md') 'a file that was not there at hand-off'
    Remove-Item -LiteralPath (Join-Path $dir47 'NOTES.md') -Force
    $in47 = @(& "$S\Integrate-Patch.ps1" -Repo $r47 -Session 'integ-47')
    $joined47 = $in47 -join ' | '
    Case 'the integrator reports a changed delivered file' ($joined47 -match 'DELIVERY-CHANGED G1\.IP changed \.streams/plans/g1audit/AUDIT\.md') $joined47
    Case 'the integrator reports an added file' ($joined47 -match 'DELIVERY-CHANGED G1\.IP added \.streams/plans/g1audit/EXTRA\.md') $joined47
    Case 'the integrator reports a removed file' ($joined47 -match 'DELIVERY-CHANGED G1\.IP removed \.streams/plans/g1audit/NOTES\.md') $joined47
    Case 'the changed row is marked on the INTEGRATED line' ($joined47 -match 'INTEGRATED G1\.IP \(in place\) CHANGED SINCE HAND-OFF') $joined47
    Case 'it REPORTS and still integrates, never refuses' ((T $r47 'G1.IP').state -eq 'integrated') (T $r47 'G1.IP').state
    Case 'the history line names what changed' ((((T $r47 'G1.IP').history | Select-Object -Last 1)['note']) -match 'delivered folder changed since hand-off') (((T $r47 'G1.IP').history | Select-Object -Last 1)['note'])
    # (c) an untouched delivery says nothing at all
    Case 'an untouched in-place delivery is not reported' (($joined47 -match 'INTEGRATED G1\.IQ \(in place\)') -and ($joined47 -notmatch 'DELIVERY-CHANGED G1\.IQ')) $joined47


    # ---- the disk flag ----
    # A builder that runs out of disk reports a COMPILE failure, and the author who reads the verdict takes it for a
    # defect in the ticket. On 2026-09-30 this host reached about 1.8 GB free of 126.4 GB with six builders live and
    # nothing on the board said a word, so the threshold now scales with the live build count. The free reading is
    # taken through STREAM_FREE_MB_TEST here, because a self-test cannot fill a disk.
    $r30 = New-Repo 'disk30' @{ 'G1.T1' = 'exit 0'; 'G1.T2' = 'exit 0' }
    & "$S\Claim-Task.ps1" -Repo $r30 -Role build -Session build-d30 | Out-Null

    # The flag names the drive that holds the fixture repo, which is wherever the temp root lives on this host, so the
    # expected letter is read from the fixture path, never written as C: (on 2026-10-01 the host moved to D: and both
    # cases went red with the flag itself correct).
    $drive30 = [regex]::Escape([IO.Path]::GetPathRoot($r30).TrimEnd('\'))
    $env:STREAM_FREE_MB_TEST = '1800'
    $lowLine = @(& "$S\Get-StreamStatus.ps1" -Repo $r30 | Where-Object { $_ -like 'flags: *' })[0]
    # -cmatch, not -match: PowerShell's -match ignores case, so the WARN wording 'disk C:' matches 'DISK C:' and the
    # two levels cannot be told apart by anything but a case-sensitive test.
    Case 'a drive under what the live builds need is flagged, in the words a reader can act on' (($lowLine -cmatch "DISK $drive30") -and ($lowLine -match 'reports a compile failure, not a full disk')) "$lowLine"

    $env:STREAM_FREE_MB_TEST = '4000'
    $warnLine = @(& "$S\Get-StreamStatus.ps1" -Repo $r30 | Where-Object { $_ -like 'flags: *' })[0]
    Case 'twice that figure is a WARN, not a hard flag' (($warnLine -cmatch "disk $drive30") -and ($warnLine -cnotmatch "DISK $drive30") -and ($warnLine -match 'bin/obj is about 450 MB')) "$warnLine"

    $env:STREAM_FREE_MB_TEST = '40000'
    $okLine = @(& "$S\Get-StreamStatus.ps1" -Repo $r30 | Where-Object { $_ -like 'flags: *' })[0]
    Case 'a drive with room says nothing at all' ($okLine -notmatch "(?i)disk $drive30") "$okLine"

    # The repo and the worktree root sit on one drive here, and one drive is one problem however many paths it holds.
    $env:STREAM_FREE_MB_TEST = '1800'
    $dj = & "$S\Get-StreamStatus.ps1" -Repo $r30 -Json | ConvertFrom-Json
    Case 'one entry per drive, naming everything it holds' ((@($dj.disks).Count -eq 1) -and (@($dj.disks)[0].holds -contains 'repo') -and (@($dj.disks)[0].holds -contains 'worktrees')) (($dj.disks | ConvertTo-Json -Compress))
    Case 'the need it was measured against travels with the reading' ((@($dj.disks)[0].needMB -ge 3072) -and (@($dj.disks)[0].state -eq 'low')) (($dj.disks | ConvertTo-Json -Compress))
    Remove-Item Env:\STREAM_FREE_MB_TEST -ErrorAction SilentlyContinue

    # ---- 14. a write set that names a FOLDER, not a file: the row can still be exported and salvaged
    # G1.T12 delivers ten evidence files under evidence/FEAT-REFERENCE-DATA-001/ and its write set is that one folder
    # entry. Test-InWriteSet compared each changed file to the entry with -like only, so an entry ending in / matched
    # NOTHING: Export-TaskPatch.ps1 answered OUTSIDE for every file in the tree and no such row could be handed off or
    # salvaged at all (plan item IN-20260930172851-089f). A folder entry now matches the folder and everything under it.
    $r31 = New-Repo 'wsdir' @{ 'G1.T1' = 'exit 0' }; $repos += $r31
    $rv31 = Join-Path $Scratch 'wsdir-revise.json'
    @{ note = 'the row delivers a folder'; edits = @(@{ task = 'G1.T1'; addWriteSet = @('pack/'); removeWriteSet = @('G1.T1.txt') }) } | ConvertTo-Json -Depth 6 | Set-Content $rv31
    & "$S\Revise-Task.ps1" -Repo $r31 -Session plan-1 -File $rv31 | Out-Null
    $c31 = & "$S\Claim-Task.ps1" -Repo $r31 -Role build -Session build-d31 | ConvertFrom-Json
    $wt31 = & "$S\New-TaskWorktree.ps1" -Repo $r31 -Task $c31.id -Session build-d31 -WorktreeRoot (Join-Path $Scratch 'wt31') | Select-Object -Last 1
    New-Item -ItemType Directory -Path (Join-Path $wt31 'pack\receipts') -Force | Out-Null
    Set-Content (Join-Path $wt31 'pack\README.md') 'evidence'
    Set-Content (Join-Path $wt31 'pack\receipts\axe.json') '{}'
    $ex31 = @(& "$S\Export-TaskPatch.ps1" -Repo $r31 -Task G1.T1 -Worktree $wt31)
    Case 'a folder write set exports every file under the folder' ((@($ex31 | Where-Object { $_ -like 'IN pack/*' }).Count -eq 2) -and ($ex31[-1] -like 'PATCH *') -and (-not @($ex31 | Where-Object { $_ -like 'OUTSIDE*' }).Count)) ($ex31 -join ' | ')
    Case 'and the patch it names is on disk with both files in it' ((Test-Path (Join-Path $r31 '.streams\patches\G1.T1.patch')) -and ((Get-Content -Raw (Join-Path $r31 '.streams\patches\G1.T1.patch')) -match 'pack/receipts/axe\.json')) (@(Get-ChildItem (Join-Path $r31 '.streams\patches') -ErrorAction SilentlyContinue | ForEach-Object { $_.Name }) -join ',')

    # The same matcher decides ownership, so a folder entry must also COLLIDE with a path inside it. Before the fix the
    # two read as disjoint and a second row over evidence/F/README.md could be released beside the row owning evidence/F/.
    $af31 = Join-Path $Scratch 'wsdir-add.json'
    @{ groups = @(@{ id = 'G1'; name = 'R'; state = 'released'; origin = 'import' })
       tasks = @(@{ id = 'G1.T9'; group = 'G1'; title = 'a second row inside the folder the first row owns'; why = @('AC-1'); kind = 'code'; writeSet = @('pack/README.md'); dependsOn = @(); estMinutes = 5 }) } | ConvertTo-Json -Depth 8 | Set-Content $af31
    $ao31 = @(& "$S\Add-Tasks.ps1" -Repo $r31 -Role plan -Session plan-1 -File $af31 2>&1 | ForEach-Object { "$_" })
    Case 'a new row inside that folder is refused as an overlap' ((($ao31 -join ' ') -match 'REFUSED G1\.T9') -and (($ao31 -join ' ') -match 'overlaps G1\.T1')) (($ao31 | Select-Object -Last 3) -join ' | ')

    # ---- 15. A BEAT IS NOT PROGRESS: an author claim on a row that has not moved is broken, and build is exempt
    # G4.T039's author beat every few minutes for 19h14m after writing its ticket and grader, wrote nothing else, and
    # never applied the owner decision written into the row; its last beat was 45 seconds old when the owner released
    # the claim by hand, so the 30 minute beat limit was never close to firing (kit item IN-20260930170751-b5a7).
    $r32 = New-Repo 'noprog' @{ 'G1.T1' = 'exit 0'; 'G1.T2' = 'exit 0' }; $repos += $r32
    $d32 = J $r32
    foreach ($x in $d32.tasks) { if ($x.id -eq 'G1.T1') { $x.state = 'planned' } }
    $d32 | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r32 '.streams\tasks.json')
    $ca32 = & "$S\Claim-Task.ps1" -Repo $r32 -Role author -Session author-np | ConvertFrom-Json
    $cb32 = & "$S\Claim-Task.ps1" -Repo $r32 -Role build -Session build-np | ConvertFrom-Json
    Case 'the no-progress fixture holds one author claim and one build claim' (($ca32.id -eq 'G1.T1') -and ($cb32.id -eq 'G1.T2')) "$($ca32.id) / $($cb32.id)"

    # Both claims are seconds old and both have just moved their row, so the default 60 minutes touches neither.
    $w32a = @(& "$S\Invoke-Watchdog.ps1" -Repo $r32 -Session status-np)
    Case 'a claim that has just moved its row is never broken' ((@($w32a | Where-Object { $_ -like 'BROKE G1.T*' }).Count -eq 0)) ($w32a -join ' | ')

    $env:STREAM_NOPROGRESS_MINUTES = '0'
    $w32b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r32 -Session status-np)
    Remove-Item Env:\STREAM_NOPROGRESS_MINUTES -ErrorAction SilentlyContinue
    $ta32 = T $r32 'G1.T1'; $tb32 = T $r32 'G1.T2'
    $broke32 = "$(@($w32b | Where-Object { $_ -like 'BROKE G1.T1*' } | Select-Object -First 1))"
    Case 'an author claim with a FRESH beat is broken once the row stops moving' (($broke32) -and (-not $ta32.claim) -and ($ta32.state -eq 'planned')) (($w32b -join ' | ') + " state=$($ta32.state) claim=$($ta32.claim)")
    Case 'and the reason says the beat was fresh, so nobody hunts a dead session' (($broke32 -match 'no progress on a live author claim of author-np') -and ($broke32 -match 'although its beat is')) "$broke32"
    Case 'the BUILD claim beside it is exempt: a build writes nothing to the board for a whole suite run' (($tb32.claim) -and ($tb32.claim.session -eq 'build-np')) ($w32b -join ' | ')
    Case 'the row keeps a history line naming the rule, not a silent claim reset' ((@($ta32.history | Where-Object { "$($_.note)" -like 'no progress on a live author claim*' }).Count -eq 1) -and (@($ta32.history)[-1].by -eq 'status-np')) ((@($ta32.history)[-1] | ConvertTo-Json -Compress))

    # ---- 16. AN INBOX HOLD CAN BEAT. A task claim has Update-Task -Beat; an inbox hold had nothing, so a holder inside
    # one long mandated step read exactly like a dead session. On 2026-09-30 a 54-minute skeptic round inside one item
    # let the watchdog re-open it at 89 minutes, and two sessions wrote the same six files inside twenty minutes - the
    # second occurrence that day (kit item IN-20260930173837-50cb).
    $r33 = New-Repo 'inboxbeat' @{ 'G1.T1' = 'exit 0' }; $repos += $r33
    $ib33 = Join-Path $r33 '.streams\inbox\stream-author.md'
    & "$S\Send-InboxItem.ps1" -Repo $r33 -To stream-author -From plan-1 -Kind request -Ask 'a holder inside one long skeptic round' | Out-Null
    $idA = ([regex]::Match((Get-Content -Raw $ib33), 'IN-\d{14}-[0-9a-f]{4}')).Value
    & "$S\Send-InboxItem.ps1" -Repo $r33 -To stream-author -From plan-1 -Kind request -Ask 'a holder that died holding it' | Out-Null
    $idB = @([regex]::Matches((Get-Content -Raw $ib33), 'IN-\d{14}-[0-9a-f]{4}') | ForEach-Object { $_.Value } | Select-Object -Unique | Where-Object { $_ -ne $idA })[0]
    $old33 = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Add-Content $ib33 ("- {0} | {1} | author-slow | taken | claimed" -f $idA, $old33)
    Add-Content $ib33 ("- {0} | {1} | author-dead | taken | claimed" -f $idB, $old33)
    # Only the slow holder beats, and it beats through the script a role would really call.
    # try/catch, because on a copy without the beat status the ValidateSet throws and one throw would take the whole
    # harness down instead of failing this case.
    $ob33 = try { & "$S\Set-InboxItem.ps1" -Repo $r33 -Skill stream-author -Id $idA -Status beat -By author-slow -Note 'skeptic round running' } catch { "THREW $_" }; $cb33 = $LASTEXITCODE
    Case 'inbox: the holder may beat its own item' (($cb33 -eq 0) -and ("$ob33" -eq "ok $idA beat")) ("exit $cb33 $ob33")

    $w33 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r33 -Session status-b1)
    Case 'inbox: a beaten hold 90 min old is NOT released' ((@($w33 | Where-Object { $_ -like "RELEASED $idA*" }).Count -eq 0)) ($w33 -join ' | ')
    Case 'inbox: the unbeaten hold beside it IS released, so the rule still catches a dead holder' ((@($w33 | Where-Object { $_ -like "RELEASED $idB*" }).Count -eq 1)) ($w33 -join ' | ')
    $open33 = @(& "$S\Get-InboxItems.ps1" -Repo $r33 -All -Open) -join ' '
    Case 'inbox: a beaten hold is not offered as overdue work either' (($open33 -notmatch [regex]::Escape($idA)) -and ($open33 -match [regex]::Escape($idB))) "$open33"
    $all33 = @(& "$S\Get-InboxItems.ps1" -Repo $r33 -All | Where-Object { $_ -like "*$idA*" }) -join ' '
    Case 'inbox: the item still reads taken by its holder, with the clock moved to the beat' ($all33 -match 'taken \d+m by author-slow') "$all33"
    $on33 = try { & "$S\Set-InboxItem.ps1" -Repo $r33 -Skill stream-author -Id $idA -Status beat -By author-other -Note 'not mine to keep alive' } catch { "THREW $_" }; $cn33 = $LASTEXITCODE
    Case 'inbox: nobody else may keep a hold alive' (($cn33 -eq 8) -and ("$on33" -like 'NOT-HELD*')) ("exit $cn33 $on33")

    # ---- 17. the inbox record: a LIVE hold is never stolen, and whoever wrote the latest line may correct its note
    # On 2026-09-30 a session checking whether the refusal existed closed IN-20260930160722-8b93, which another author
    # held, with the note 'probe', and then could not replace that note: a closed item was NOT-HELD for everybody, so
    # the wrong reason stood as the record (kit item IN-20260930175245-b92e).
    $r34 = New-Repo 'inboxrec' @{ 'G1.T1' = 'exit 0' }; $repos += $r34
    $ib34 = Join-Path $r34 '.streams\inbox\stream-author.md'
    & "$S\Send-InboxItem.ps1" -Repo $r34 -To stream-author -From plan-1 -Kind request -Ask 'held right now by a working session' | Out-Null
    $id34 = ([regex]::Match((Get-Content -Raw $ib34), 'IN-\d{14}-[0-9a-f]{4}')).Value
    & "$S\Set-InboxItem.ps1" -Repo $r34 -Skill stream-author -Id $id34 -Status taken -By author-busy | Out-Null
    $os34 = try { & "$S\Set-InboxItem.ps1" -Repo $r34 -Skill stream-author -Id $id34 -Status done -By author-nosy -Steal -Note 'probe' } catch { "THREW $_" }; $cs34 = $LASTEXITCODE
    Case 'inbox: a FRESH hold is never stolen, flag or no flag' (($cs34 -eq 8) -and ("$os34" -like 'HELD*') -and ("$os34" -match 'never stolen')) ("exit $cs34 $os34")

    & "$S\Set-InboxItem.ps1" -Repo $r34 -Skill stream-author -Id $id34 -Status done -By author-busy -Note 'probe' | Out-Null
    $oc34 = try { & "$S\Set-InboxItem.ps1" -Repo $r34 -Skill stream-author -Id $id34 -Status note -By author-busy -Note 'the real reason: the ticket was amended at 18:20Z' } catch { "THREW $_" }; $cc34 = $LASTEXITCODE
    Case 'inbox: the session that closed an item may correct its note' (($cc34 -eq 0) -and ("$oc34" -eq "ok $id34 note")) ("exit $cc34 $oc34")
    $items34 = @(& "$S\Get-InboxItems.ps1" -Repo $r34 -All | Where-Object { $_ -like "*$id34*" }) -join ' '
    Case 'inbox: the item still reads done, and the annotation did not become its status' (($items34 -match 'done') -and ($items34 -notmatch ' note ')) "$items34"
    $on34 = try { & "$S\Set-InboxItem.ps1" -Repo $r34 -Skill stream-author -Id $id34 -Status note -By author-other -Note 'not my record to write' } catch { "THREW $_" }; $cn34 = $LASTEXITCODE
    Case 'inbox: nobody writes a note under another session outcome' (($cn34 -eq 8) -and ("$on34" -like 'NOT-HELD*')) ("exit $cn34 $on34")

    # ---- 18. A TREE OUTSIDE EVERY ROOT. The reaper only ever looks inside $roots - the parents of the trees tasks
    # record, plus D:\devops\worktrees\<repo> - so an ad-hoc tree a session laid down by hand in D:\devops\worktrees   # history
    # itself is registered to the repo, owned by no task, and invisible to every rule. Twelve of them were measured on
    # this host on 2026-09-30 at about 520 MB each with 6.1 GB free (kit items IN-20260930172725-6af7 and
    # IN-20260930172832-d7d4). They are reported, never reaped, and their build output goes only under disk pressure.
    $r35 = New-Repo 'oorootdisk' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r35
    [void](Build $r35 'G1.A' 'ok' 'build-35')                      # a recorded tree, so $roots is its parent and nothing else
    $adhoc = Join-Path (Join-Path $Scratch 'adhoc35') 'skeptic-g1a'
    git -C $r35 worktree add -q --detach $adhoc HEAD 2>&1 | Out-Null
    if (-not (Test-Path $adhoc)) { throw 'case 18: the ad-hoc worktree was not created' }
    $binDir = Join-Path $adhoc 'src\bin\Debug'
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    $binFile = Join-Path $binDir 'big.dll'
    Set-Content -Path $binFile -Value ('x' * 2200000)              # 2 MB of build output, which is what a prune reclaims
    $keep = Join-Path $adhoc 'src\keep.cs'
    Set-Content -Path $keep -Value 'keep me'
    # A project file beside the bin, because that is what makes it BUILD output: -BuildOutputOnly now requires the
    # sibling, after matching the name alone deleted packages' own executables under node_modules (case 20).
    Set-Content -Path (Join-Path $adhoc 'src\App.csproj') -Value '<Project />'
    Set-Content -Path (Join-Path $adhoc 'G1.A.txt') -Value 'ad-hoc work no patch carries'   # a real change nothing else holds
    $env:STREAM_REAP_QUIET_MINUTES = '10'
    # Under pressure, but written to a moment ago: a build is in there whatever the board says, so nothing is deleted.
    $env:STREAM_FREE_MB_TEST = '3000'
    $w35 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r35 -Session 'status-35d')
    Case 'outside-root: a tree written to inside the quiet period keeps its build output' ((Test-Path $binFile) -and (($w35 -join ' ') -match 'quiet period')) ($w35 -join ' | ')
    foreach ($f in @(Get-ChildItem $adhoc -Recurse -File -Force)) { $f.LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-90) }
    # Quiet now, but the drive is not under pressure: the tree is REPORTED with its size and nothing is deleted.
    $env:STREAM_FREE_MB_TEST = '100000'
    $w35b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r35 -Session 'status-35a')
    # g6pred belonged to no row at all and held the only copy of two files: a size alone does not say that.
    Case 'outside-root: the report counts the changed files nothing else holds' ((($w35b -join ' ') -match '\d+ changed file\(s\)')) ($w35b -join ' | ')
    Case 'outside-root: the tree no root covers is reported with its size' ((($w35b -join ' ') -match [regex]::Escape($adhoc)) -and (($w35b -join ' ') -match 'OUTSIDE-ROOT')) ($w35b -join ' | ')
    Case 'outside-root: nothing is deleted while the drive is not under pressure' ((Test-Path $binFile) -and (($w35b -join ' ') -notmatch 'PRUNED')) ($w35b -join ' | ')
    Case 'outside-root: the report is a note, so it writes no decision line' ((Get-Content -Raw (Join-Path $r35 '.streams\decisions.md')) -notmatch 'OUTSIDE-ROOT') 'a standing condition appended a decision line'
    # Quiet AND under pressure: bin/obj goes, the tree and its source stay, and the ledger says why.
    $env:STREAM_FREE_MB_TEST = '3000'
    $w35c = @(& "$S\Invoke-Watchdog.ps1" -Repo $r35 -Session 'status-35b')
    Case 'outside-root: build output is pruned under disk pressure' ((-not (Test-Path $binFile)) -and (($w35c -join ' ') -match 'PRUNED')) ($w35c -join ' | ')
    Case 'outside-root: the prune keeps the tree and its source' ((Test-Path $adhoc) -and (Test-Path $keep)) 'the prune took the tree, not only its build output'
    Case 'outside-root: the prune is an action, so the cycle is not QUIET' (($w35c -join ' ') -notmatch '^QUIET') ($w35c -join ' | ')
    Case 'outside-root: the ledger records the prune and the pressure' ((Get-Content -Raw (Join-Path $r35 '.streams\owner\worktrees.md')) -match 'build output pruned \(\d+ MB\): watchdog: registered outside every worktree root') ((Get-Content (Join-Path $r35 '.streams\owner\worktrees.md'))[-1])
    # The repository itself is registered as a worktree too, and it must never be reported or touched as an ad-hoc tree.
    Case 'outside-root: the main tree is never one of them' (($w35c -join ' ') -notmatch "OUTSIDE-ROOT $([regex]::Escape($r35))\b") ($w35c -join ' | ')
    $env:STREAM_REAP_QUIET_MINUTES = '0'
$env:STREAM_RUNNER_START_JITTER_SECONDS = '0'   # no random start wait for the runner cases
    Remove-Item Env:\STREAM_FREE_MB_TEST -ErrorAction SilentlyContinue

    # ---- 20. THE PRUNE TOUCHES BUILD OUTPUT ONLY. -BuildOutputOnly matched every directory NAMED bin or obj at any
    # depth, so it also deleted a package's own executables: the live repo carries 9 of them under
    # tests\Tests.E2E\node_modules (eslint\bin, playwright-core\bin, js-yaml\bin, acorn\bin ...). A pruned tree then
    # fails its Playwright run on a missing binary and the builder reads a product defect (kit item
    # IN-20260930172725-6af7). bin and obj are build output only BESIDE a project file; no tracked file on main sits
    # under such a path (measured 0 of 3397), so the sibling test cannot reach source.
    $r50 = New-Repo 'prune50' @{ 'G1.T1' = 'exit 0' }; $repos += $r50
    $c50 = & "$S\Claim-Task.ps1" -Repo $r50 -Role build -Session build-p50 | ConvertFrom-Json
    $wt50 = & "$S\New-TaskWorktree.ps1" -Repo $r50 -Task $c50.id -Session build-p50 -WorktreeRoot (Join-Path $Scratch 'wt50') | Select-Object -Last 1
    foreach ($d in 'src\App\bin\Debug', 'src\App\obj', 'tests\E2E\node_modules\eslint\bin', 'tools\bin') {
        New-Item -ItemType Directory -Force -Path (Join-Path $wt50 $d) | Out-Null
    }
    Set-Content (Join-Path $wt50 'src\App\App.csproj') '<Project />'
    # 1.5 MB each, because the watchdog suppresses a PRUNED line that rounds to 0 MB and the clause below
    # must read a real report, not a silent success.
    Set-Content (Join-Path $wt50 'src\App\bin\Debug\App.dll') ('x' * 1572864)
    Set-Content (Join-Path $wt50 'src\App\obj\project.assets.json') ('y' * 1572864)
    Set-Content (Join-Path $wt50 'tests\E2E\node_modules\eslint\bin\eslint.js') 'the package own executable'
    Set-Content (Join-Path $wt50 'tools\bin\helper.ps1') 'a bin folder with no project beside it'
    Set-Content (Join-Path $wt50 'G1.T1.txt') 'an uncommitted source edit the patch has not been exported from yet'

    # (a) a tree whose task is BUILDING is never touched, however much build output it holds
    $w50a = @(& "$S\Invoke-Watchdog.ps1" -Repo $r50 -Session status-p50)
    Case 'prune: a building task tree keeps its build output' ((Test-Path (Join-Path $wt50 'src\App\bin\Debug\App.dll')) -and (@($w50a | Where-Object { $_ -like 'PRUNED*' }).Count -eq 0)) ($w50a -join ' | ')

    # (b) the row is built and the claim released, but the drive has ROOM: nothing is deleted. The owner's rule
    # (IN-20260930205046-e104) is that a prune is a disk measure, not housekeeping - a built tree is waiting for an
    # integrator, and a rebuild of it costs the next session minutes it pays for nothing while C: has space.
    & "$S\Export-TaskPatch.ps1" -Repo $r50 -Task $c50.id -Worktree $wt50 | Out-Null
    & "$S\Update-Task.ps1" -Repo $r50 -Task $c50.id -Role build -Session build-p50 -To built -Release -Artifacts @{ verdict = 'PASS' } | Out-Null
    $env:STREAM_FREE_MB_TEST = '100000'
    $w50b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r50 -Session status-p50)
    Case 'prune: a built tree KEEPS its build output while the drive has room' ((Test-Path (Join-Path $wt50 'src\App\bin\Debug\App.dll')) -and (Test-Path (Join-Path $wt50 'src\App\obj\project.assets.json')) -and (@($w50b | Where-Object { $_ -like 'PRUNED*' }).Count -eq 0)) ($w50b -join ' | ')

    # (c) the same tree under pressure loses build output and NOTHING else. 4000 MB free against the 3072 MB floor is
    # `warn`, one band short of `low`: the watchdog prunes at warn, because waiting for low means waiting until a build
    # has already failed somewhere with a message that blames its own ticket.
    $env:STREAM_FREE_MB_TEST = '4000'
    $w50c = @(& "$S\Invoke-Watchdog.ps1" -Repo $r50 -Session status-p50)
    $pr50 = "$(@($w50c | Where-Object { $_ -like 'PRUNED*' } | Select-Object -First 1))"
    Case 'prune: a built tree loses bin and obj beside its project file under pressure' ((-not (Test-Path (Join-Path $wt50 'src\App\bin'))) -and (-not (Test-Path (Join-Path $wt50 'src\App\obj'))) -and $pr50) ($w50c -join ' | ')
    Case 'prune: a package own bin under node_modules SURVIVES' (Test-Path (Join-Path $wt50 'tests\E2E\node_modules\eslint\bin\eslint.js')) ($w50c -join ' | ')
    Case 'prune: a bin folder with no project file beside it SURVIVES' (Test-Path (Join-Path $wt50 'tools\bin\helper.ps1')) ($w50c -join ' | ')
    Case 'prune: the uncommitted source in the tree survives, so a re-export still works' (((Get-Content -Raw (Join-Path $wt50 'G1.T1.txt')) -match 'an uncommitted source edit') -and (Test-Path (Join-Path $wt50 'src\App\App.csproj'))) 'source intact'
    Case 'prune: the worktree itself is KEPT, only its output went' (Test-Path (Join-Path $wt50 '.git')) $wt50
    $led50 = if (Test-Path (Join-Path $r50 '.streams\owner\worktrees.md')) { Get-Content -Raw (Join-Path $r50 '.streams\owner\worktrees.md') } else { '' }
    Case 'prune: the ledger records it with the build output pruned note' ($led50 -match 'build output pruned') "$led50"
    # The band belongs in the ledger, not only in the decision to run: an owner reading worktrees.md must see that the
    # drive is why a tree lost its output, and which reading said so.
    Case 'prune: the ledger names the pressure band and the free space that caused it' ($led50 -match 'disk warn \(\d+ MB free, need \d+ MB\)') "$led50"
    Remove-Item Env:\STREAM_FREE_MB_TEST -ErrorAction SilentlyContinue

    # ---- 21. AN UNDELIVERABLE INBOX ITEM IS REFUSED AT FILING TIME. Claim-Task.ps1 picks by group and chain order, so
    # no author or builder can choose to work a named row: an item addressed to the future holder of a planned,
    # untickted, unclaimed row has no reachable taker, stays open forever and flags on every tick. Three such items
    # were closed by hand on 2026-09-30, one of them 498 minutes old, and the same G4.T039 request was filed FIVE
    # times before its sender folded the substance into the row (kit item IN-20260930173115-9510).
    $r51 = New-Repo 'undeliv51' @{ 'G1.T1' = 'exit 0'; 'G1.T2' = 'exit 0' }; $repos += $r51
    $d51 = J $r51
    foreach ($x in $d51.tasks) { if ($x.id -eq 'G1.T1') { $x.state = 'planned'; $x.artifacts = @{ ticket = $null; grader = $null; patch = $null; verdict = $null } } }
    $d51 | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r51 '.streams\tasks.json')
    $o51 = @(& "$S\Send-InboxItem.ps1" -Repo $r51 -To stream-author -From plan-51 -Kind request -Task 'G1.T1' -Ask 'for whoever authors this row' 2>&1 | ForEach-Object { "$_" }); $c51 = $LASTEXITCODE
    $box51 = if (Test-Path (Join-Path $r51 '.streams\inbox\stream-author.md')) { Get-Content -Raw (Join-Path $r51 '.streams\inbox\stream-author.md') } else { '' }
    Case 'an item to stream-author about a planned untickted row is REFUSED' (($c51 -eq 9) -and (($o51 -join ' ') -match 'REFUSED G1\.T1 is planned with no ticket and no claim')) (($o51 -join ' | ') + " exit=$c51")
    Case 'the refusal writes nothing to the inbox' ($box51 -notmatch 'for whoever authors this row') "$box51"
    Case 'the refusal names the row own history as the way through' ((($o51 -join ' ') -match 'Update-Task\.ps1') -and (($o51 -join ' ') -match '-Note')) (($o51 -join ' | '))
    # try/catch, so a base copy without the switch reports this one case instead of aborting the whole run.
    $of51 = try { @(& "$S\Send-InboxItem.ps1" -Repo $r51 -To stream-author -From plan-51 -Kind request -Task 'G1.T1' -Ask 'filed anyway, deliberately' -Force 2>&1 | ForEach-Object { "$_" }) } catch { @("THREW $_") }; $cf51 = $LASTEXITCODE
    Case 'the sender who means it may still file with -Force' (($cf51 -eq 0) -and (($of51 -join ' ') -like 'SENT *')) (($of51 -join ' | ') + " exit=$cf51")
    $ot51 = @(& "$S\Send-InboxItem.ps1" -Repo $r51 -To stream-author -From plan-51 -Kind request -Task 'G1.T2' -Ask 'this row is ticketed, so an author can take it' 2>&1 | ForEach-Object { "$_" }); $ct51 = $LASTEXITCODE
    Case 'a ticketed row is deliverable and is never refused' (($ct51 -eq 0) -and (($ot51 -join ' ') -like 'SENT *')) (($ot51 -join ' | ') + " exit=$ct51")
    $op51 = @(& "$S\Send-InboxItem.ps1" -Repo $r51 -To stream-plan -From author-51 -Kind request -Task 'G1.T1' -Ask 'a planner acts on any row, so this one is deliverable' 2>&1 | ForEach-Object { "$_" }); $cp51 = $LASTEXITCODE
    Case 'an item to stream-plan about the same row is never refused' (($cp51 -eq 0) -and (($op51 -join ' ') -like 'SENT *')) (($op51 -join ' | ') + " exit=$cp51")

    # ---- 18s. A SCRATCH TREE. {WorktreesRoot}\<repo>-scratch\<task>-<purpose> trees (probes, RED runs, refresh checks)
    # are recorded by no task, so until 2026-10-25 they were only ever REPORTED as OUTSIDE-ROOT, and the owner exported
    # and removed ten of them by hand (kit item IN-20261025140859-22ee). Now one quiet for StreamScratchKeepHours is
    # saved as a patch under .streams\salvage\scratch and removed; a fresh one is left alone.
    $r18s = New-Repo 'scratchreap' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r18s
    $scr18s = Join-Path $env:STREAM_WORKTREE_ROOT ((Split-Path -Leaf $r18s) + '-scratch')
    $t18s = Join-Path $scr18s 'G1.A-probe'
    git -C $r18s worktree add -q --detach $t18s HEAD 2>&1 | Out-Null
    if (-not (Test-Path $t18s)) { throw 'case 18s: the scratch worktree was not created' }
    Set-Content -Path (Join-Path $t18s 'probe18s.txt') -Value 'probe work no patch carries'
    $free18s = $env:STREAM_FREE_MB_TEST; $env:STREAM_FREE_MB_TEST = '100000'
    $w18s = @(& "$S\Invoke-Watchdog.ps1" -Repo $r18s -Session 'status-18s')
    Case '18s scratch: a scratch tree written to inside the keep period is not reaped' ((Test-Path $t18s) -and (($w18s -join ' ') -notmatch 'REAPED-SCRATCH')) ($w18s -join ' | ')
    foreach ($f in @(Get-ChildItem $t18s -Recurse -File -Force)) { $f.LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-25) }
    $w18sb = @(& "$S\Invoke-Watchdog.ps1" -Repo $r18s -Session 'status-18s')
    Case '18s scratch: a scratch tree quiet past the keep period is removed' ((-not (Test-Path $t18s)) -and (($w18sb -join ' ') -match 'REAPED-SCRATCH')) ($w18sb -join ' | ')
    $sal18s = @(Get-ChildItem (Join-Path $r18s '.streams\salvage\scratch') -Filter 'G1.A-probe-*.patch' -ErrorAction SilentlyContinue)
    Case '18s scratch: its changes are saved as a patch before the removal' (($sal18s.Count -eq 1) -and ((Get-Content -Raw $sal18s[0].FullName) -match 'probe18s\.txt')) "patches: $($sal18s.Count)"
    Case '18s scratch: the registration is gone too' (-not ((@(git -C $r18s worktree list) -join ' ') -match 'G1\.A-probe')) (@(git -C $r18s worktree list) -join ' | ')
    if ($free18s) { $env:STREAM_FREE_MB_TEST = $free18s } else { Remove-Item Env:\STREAM_FREE_MB_TEST -ErrorAction SilentlyContinue }

    # ---- 19. A COMMA-JOINED WRITE-SET VALUE. Update-Task.ps1 documents -AddWriteSet <file[,file]> and a shell hands
    # that over as ONE string, which was stored as one entry holding three paths on G3.T100 on 2026-09-30:
    # Export-TaskPatch.ps1 answered OUTSIDE for all three real files, and a builder may never remove a write-set path,
    # so the malformed entry was permanent (kit item IN-20260930184321-a743). Every taker of a path list now splits.
    $r36 = New-Repo 'wscomma' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r36
    $c36 = & "$S\Claim-Task.ps1" -Repo $r36 -Role build -Session 'build-36' | ConvertFrom-Json
    $wt36 = & "$S\New-TaskWorktree.ps1" -Repo $r36 -Task $c36.id -Session 'build-36' -WorktreeRoot (Join-Path $Scratch 'wt36') | Select-Object -Last 1
    [void](& "$S\Update-Task.ps1" -Repo $r36 -Task $c36.id -Role build -Session 'build-36' -AddWriteSet 'extra/one.txt,extra/two.txt' -Note 'test: comma-joined')
    $ws36 = @((T $r36 $c36.id).writeSet)
    Case 'write set: a comma-joined -AddWriteSet becomes separate entries' (($ws36 -contains 'extra/one.txt') -and ($ws36 -contains 'extra/two.txt') -and -not @($ws36 | Where-Object { $_ -like '*,*' }).Count) ($ws36 -join ' | ')
    # The cost the defect actually carried: no widened file could be exported.
    New-Item -ItemType Directory -Path (Join-Path $wt36 'extra') -Force | Out-Null
    Set-Content (Join-Path $wt36 'extra\one.txt') 'one'; Set-Content (Join-Path $wt36 'extra\two.txt') 'two'
    $e36 = @(& "$S\Export-TaskPatch.ps1" -Repo $r36 -Task $c36.id -Worktree $wt36 2>&1); $ce36 = $LASTEXITCODE
    Case 'write set: the widened files export instead of reading OUTSIDE' (($ce36 -eq 0) -and -not (($e36 -join ' ') -match 'OUTSIDE')) ("exit $ce36 $($e36 -join ' | ')")
    # The planner's own path takes the same shape, inline and in a batch file.
    $other36 = @((J $r36).tasks | Where-Object { $_.id -ne $c36.id })[0].id
    $o36 = & "$S\Revise-Task.ps1" -Repo $r36 -Session 'plan-36' -Task $other36 -AddWriteSet 'extra/three.txt,extra/four.txt' -Note 'test: comma-joined revise'; $cr36 = $LASTEXITCODE
    $ws36b = @((T $r36 $other36).writeSet)
    Case 'write set: a comma-joined revise splits too' (($cr36 -eq 0) -and ($ws36b -contains 'extra/three.txt') -and ($ws36b -contains 'extra/four.txt')) ("exit $cr36 $($ws36b -join ' | ')")
    # And a single path with spaces or quotes around it is ONE entry, trimmed - the split must not invent paths.
    [void](& "$S\Revise-Task.ps1" -Repo $r36 -Session 'plan-36' -Task $other36 -AddWriteSet ' extra/five.txt ' -Note 'test: one padded path')
    $ws36c = @((T $r36 $other36).writeSet)
    Case 'write set: a single padded path is one trimmed entry' ((@($ws36c | Where-Object { $_ -like '*five*' }).Count -eq 1) -and ($ws36c -contains 'extra/five.txt')) ($ws36c -join ' | ')
    # A plan file can carry the same shape in one JSON element.
    $f36 = Join-Path $Scratch 'wscomma-add.json'
    @{ tasks = @(@{ id = 'G1.C'; group = 'G1'; title = 'comma import'; why = @('AC-1'); kind = 'code'; writeSet = @('extra/six.txt,extra/seven.txt'); dependsOn = @(); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $f36
    $a36 = & "$S\Add-Tasks.ps1" -Repo $r36 -Role plan -Session 'plan-36' -File $f36; $ca36 = $LASTEXITCODE
    $ws36d = @((T $r36 'G1.C').writeSet)
    Case 'write set: an imported comma-joined entry splits at Add-Tasks' (($ca36 -eq 0) -and ($ws36d -contains 'extra/six.txt') -and ($ws36d -contains 'extra/seven.txt') -and -not @($ws36d | Where-Object { $_ -like '*,*' }).Count) ("exit $ca36 $($a36 -join ' | ') ws=$($ws36d -join ' | ')")

    # ---- 22. AN ALREADY-MALFORMED WRITE-SET ENTRY MUST STILL BE REMOVABLE. Expand-PathList (case 19) splits every
    # comma-joined path value, which is right on the ADD side and wrong on the REMOVE side: the only way to delete an
    # entry that holds three comma-separated paths is to NAME it, and every spelling of it contains commas, so the
    # splitter turned the repair into the removal of the three GOOD paths. Measured on G3.T100 at 21:07Z, restored at
    # 21:09Z (kit item IN-20260930210802-1c51). ADD splits, REMOVE does not.
    $r37 = New-Repo 'wsrepair' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r37
    $bad37 = 'tests/one.cs,tests/two.cs'
    $j37 = J $r37
    foreach ($t in $j37.tasks) { if ($t.id -eq 'G1.A') { $t.writeSet = @('G1.A.txt', $bad37, 'tests/one.cs', 'tests/two.cs') } }
    Set-Content -Path (Join-Path $r37 '.streams\tasks.json') -Encoding utf8 -Value ($j37 | ConvertTo-Json -Depth 50)
    # The board reads CLEAN with it present - it matches no file, so it overlaps nothing - which is why it needs its
    # own report rather than a problem: a problem would refuse the very batch that repairs it.
    $b37 = @(& "$S\Test-BoardOrder.ps1" -Repo $r37); $cb37 = $LASTEXITCODE
    Case 'write set: a malformed entry is REPORTED while the board still reads CLEAN' (($cb37 -eq 0) -and (@($b37)[0] -eq 'CLEAN') -and (($b37 -join ' ') -match 'MALFORMED G1\.A')) ("exit $cb37 $($b37 -join ' | ')")
    # The repair: name it exactly as stored. The three real paths must survive it.
    $o37 = & "$S\Revise-Task.ps1" -Repo $r37 -Session 'plan-37' -Task 'G1.A' -RemoveWriteSet $bad37 -Note 'test: repair the malformed entry'; $cr37 = $LASTEXITCODE
    $ws37 = @((T $r37 'G1.A').writeSet)
    Case 'write set: the malformed entry is removed by naming it exactly' (($cr37 -eq 0) -and ($ws37 -notcontains $bad37)) ("exit $cr37 $($ws37 -join ' | ')")
    Case 'write set: the repair keeps the real paths it holds twice over' (($ws37 -contains 'tests/one.cs') -and ($ws37 -contains 'tests/two.cs') -and ($ws37 -contains 'G1.A.txt')) ($ws37 -join ' | ')
    $b37b = @(& "$S\Test-BoardOrder.ps1" -Repo $r37)
    Case 'write set: the report goes quiet once the entry is gone' ((@($b37b)[0] -eq 'CLEAN') -and (($b37b -join ' ') -notmatch 'MALFORMED')) ($b37b -join ' | ')
    # Removing several paths at once still works - as an ARRAY, which is what the remove side takes now.
    [void](& "$S\Revise-Task.ps1" -Repo $r37 -Session 'plan-37' -Task 'G1.A' -RemoveWriteSet @('tests/one.cs', 'tests/two.cs') -Note 'test: array remove')
    $ws37b = @((T $r37 'G1.A').writeSet)
    Case 'write set: an array still removes several paths' (($ws37b -notcontains 'tests/one.cs') -and ($ws37b -notcontains 'tests/two.cs') -and ($ws37b -contains 'G1.A.txt')) ($ws37b -join ' | ')
    # And the ADD side still splits, because that is what <file[,file]> promises (case 19 covers it end to end).
    [void](& "$S\Revise-Task.ps1" -Repo $r37 -Session 'plan-37' -Task 'G1.A' -AddWriteSet 'tests/three.cs,tests/four.cs' -Note 'test: add still splits')
    $ws37c = @((T $r37 'G1.A').writeSet)
    Case 'write set: the add side still splits after the remove side stopped' (($ws37c -contains 'tests/three.cs') -and ($ws37c -contains 'tests/four.cs')) ($ws37c -join ' | ')
    # tests.targeted must be clearable: an empty 'tests' list is ignored (it reads as "no change"), so a docs or
    # measurement row kept a filter that matches no test (G18.T110, kit item IN-20261023072040-b37a). clearTests
    # empties it; clearTests together with tests is refused, because the two contradict each other.
    $f37t = Join-Path $Scratch 'tests37.json'
    @{ note = 'test: set tests'; edits = @(@{ task = 'G1.A'; tests = @('FullyQualifiedName~Gone') }) } | ConvertTo-Json -Depth 10 | Set-Content $f37t
    [void](& "$S\Revise-Task.ps1" -Repo $r37 -Session 'plan-37' -File $f37t)
    $tg37a = @((T $r37 'G1.A').tests.targeted)
    @{ note = 'test: clear tests'; edits = @(@{ task = 'G1.A'; clearTests = $true }) } | ConvertTo-Json -Depth 10 | Set-Content $f37t
    $o37t = @(& "$S\Revise-Task.ps1" -Repo $r37 -Session 'plan-37' -File $f37t); $c37t = $LASTEXITCODE
    $tg37b = @((T $r37 'G1.A').tests.targeted | Where-Object { $_ })
    Case 'tests: clearTests empties tests.targeted' (($tg37a -contains 'FullyQualifiedName~Gone') -and ($c37t -eq 0) -and ($tg37b.Count -eq 0) -and (($o37t -join ' ') -match 'tests cleared')) ("exit $c37t before=$($tg37a -join ',') after=$($tg37b -join ',') $($o37t -join ' | ')")
    @{ note = 'test: both'; edits = @(@{ task = 'G1.A'; tests = @('FullyQualifiedName~X'); clearTests = $true }) } | ConvertTo-Json -Depth 10 | Set-Content $f37t
    $o37u = @(& "$S\Revise-Task.ps1" -Repo $r37 -Session 'plan-37' -File $f37t); $c37u = $LASTEXITCODE
    Case 'tests: clearTests with tests in one edit is refused' (($c37u -eq 2) -and (($o37u -join ' ') -match 'TESTS-CONFLICT G1\.A') -and -not @((T $r37 'G1.A').tests.targeted | Where-Object { $_ }).Count) ("exit $c37u $($o37u -join ' | ')")
    [void](& "$S\Revise-Task.ps1" -Repo $r37 -Session 'plan-37' -File (& { @{ note = 'test: set again'; edits = @(@{ task = 'G1.A'; tests = @('FullyQualifiedName~Y') }) } | ConvertTo-Json -Depth 10 | Set-Content $f37t; $f37t }))
    $o37v = @(& "$S\Revise-Task.ps1" -Repo $r37 -Session 'plan-37' -Task 'G1.A' -ClearTests -Note 'test: inline clear'); $c37v = $LASTEXITCODE
    Case 'tests: -ClearTests clears inline' (($c37v -eq 0) -and -not @((T $r37 'G1.A').tests.targeted | Where-Object { $_ }).Count) ("exit $c37v $($o37v -join ' | ')")

    # ---- 23. A ROW'S GROUP IS REVISABLE, BECAUSE THE GROUP IS THE CLAIM ORDER. Claim-Task.ps1:47 sorts fix-first, then
    # group rank, then chain depth, so a row that gates the FIRST group's close is claimed almost last while it lives in
    # a later group - and no script could move it: Revise-Task.ps1 edited write sets, dependsOn, title, tests, estimates
    # and the release, and nothing else (owner ruling on G3.T149, kit item IN-20260930210139-4afa). The move keeps the
    # row's ID, and the batch that moves it must also move the integration edge, or a group closes over a row it no
    # longer holds.
    $r38 = New-Repo 'grpmove' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r38
    $j38 = J $r38
    $base38 = @($j38.tasks | Where-Object { $_.id -eq 'G1.A' })[0]
    $mk38 = {
        param($id, $grp, $kind, $ws, $deps)
        $c = (($base38 | ConvertTo-Json -Depth 50) | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50)
        $c.id = $id; $c.group = $grp; $c.kind = $kind; $c.title = "$id ($kind)"; $c.state = 'planned'
        $c.writeSet = @($ws); $c.dependsOn = @($deps); $c.claim = $null
        $c.artifacts = [ordered]@{ ticket = $null; grader = $null; patch = $null; verdict = $null }
        $c
    }
    $base38.state = 'planned'
    $j38.groups = @($j38.groups[0], @{ id = 'G2'; name = 'second'; state = 'released'; origin = 'plan' }, @{ id = 'G3'; name = 'third'; state = 'planned'; origin = 'plan' })
    $j38.tasks = @($base38,
        (& $mk38 'G2.X' 'G2' 'code' 'x.txt' @()),
        (& $mk38 'G2.Y' 'G2' 'code' 'y.txt' @()),
        (& $mk38 'G1.I' 'G1' 'integration' @() @('G1.A')),
        (& $mk38 'G2.I' 'G2' 'integration' @() @('G2.X', 'G2.Y')))
    Set-Content -Path (Join-Path $r38 '.streams\tasks.json') -Encoding utf8 -Value ($j38 | ConvertTo-Json -Depth 50)
    # The board it starts from is ordered, so every refusal below is the group check talking and not a stale board.
    $b38 = @(& "$S\Test-BoardOrder.ps1" -Repo $r38)
    Case 'group move: the fixture board is ordered before anything moves' ((@($b38)[0] -eq 'CLEAN')) ($b38 -join ' | ')
    # The cost the defect carried: G2.Y is claimed after every G1 row and after G2.X, whatever it gates.
    $c38a = & "$S\Claim-Task.ps1" -Repo $r38 -Role author -Session 'author-38a' | ConvertFrom-Json
    Case 'group move: the first author claim is the deepest chain of the first group' ($c38a.id -eq 'G1.A') "claimed $($c38a.id)"
    # The move, with the integration edge moved in the SAME batch.
    $f38 = Join-Path $Scratch 'grpmove.json'
    @{ note = 'test: move G2.Y into G1 with its integration edge'; edits = @(
        @{ task = 'G2.Y'; group = 'G1' },
        @{ task = 'G2.I'; removeDependsOn = @('G2.Y') },
        @{ task = 'G1.I'; addDependsOn = @('G2.Y') }) } | ConvertTo-Json -Depth 10 | Set-Content $f38
    $o38 = @(& "$S\Revise-Task.ps1" -Repo $r38 -Session 'plan-38' -File $f38 2>&1); $cm38 = $LASTEXITCODE
    $y38 = T $r38 'G2.Y'
    Case 'group move: the row moves and KEEPS its id' (($cm38 -eq 0) -and ($null -ne $y38) -and ([string] $y38.group -eq 'G1')) ("exit $cm38 group=$($y38.group) $($o38 -join ' | ')")
    $b38b = @(& "$S\Test-BoardOrder.ps1" -Repo $r38)
    Case 'group move: the moved board is still ordered' ((@($b38b)[0] -eq 'CLEAN')) ($b38b -join ' | ')
    # The point of the whole change: the next author gets G2.Y, which without the move would have been G2.X.
    $c38b = & "$S\Claim-Task.ps1" -Repo $r38 -Role author -Session 'author-38b' | ConvertFrom-Json
    Case 'group move: the moved row is now claimed before the group it left' ($c38b.id -eq 'G2.Y') "claimed $($c38b.id)"
    # A move with no rewire is refused whole, and names both edges it needs.
    $w38 = @(& "$S\Revise-Task.ps1" -Repo $r38 -Session 'plan-38' -Task 'G2.X' -Group 'G1' -Note 'test: no rewire' 2>&1); $cw38 = $LASTEXITCODE
    Case 'group move: a move that leaves the integration wiring behind is refused' (($cw38 -eq 2) -and (($w38 -join ' ') -match 'GROUP-WIRING G2\.X : G2\.I still dependsOn it') -and (($w38 -join ' ') -match 'GROUP-WIRING G2\.X : G1\.I does not dependsOn it') -and ([string] (T $r38 'G2.X').group -eq 'G2')) ("exit $cw38 $($w38 -join ' | ')")
    # The refusals that protect the row's own artifacts and the board's own vocabulary.
    $u38 = @(& "$S\Revise-Task.ps1" -Repo $r38 -Session 'plan-38' -Task 'G2.X' -Group 'G9' -Note 'test: unknown group' 2>&1); $cu38 = $LASTEXITCODE
    Case 'group move: a group id that is not on the board is refused' (($cu38 -eq 2) -and (($u38 -join ' ') -match 'UNKNOWN-GROUP G2\.X -> G9')) ("exit $cu38 $($u38 -join ' | ')")
    $n38 = @(& "$S\Revise-Task.ps1" -Repo $r38 -Session 'plan-38' -Task 'G2.X' -Group 'G3' -Note 'test: unreleased target' 2>&1); $cn38 = $LASTEXITCODE
    Case 'group move: a target group that is not released is refused, since the claim would never see the row' (($cn38 -eq 2) -and (($n38 -join ' ') -match 'GROUP-NOT-RELEASED G2\.X')) ("exit $cn38 $($n38 -join ' | ')")
    $k38 = @(& "$S\Revise-Task.ps1" -Repo $r38 -Session 'plan-38' -Task 'G1.A' -Group 'G2' -Note 'test: live claim' 2>&1); $ck38 = $LASTEXITCODE
    Case 'group move: a row held by a live claim is refused' (($ck38 -eq 2) -and (($k38 -join ' ') -match 'GROUP-CLAIMED G1\.A') -and (($k38 -join ' ') -match 'author-38a') -and ([string] (T $r38 'G1.A').group -eq 'G1')) ("exit $ck38 $($k38 -join ' | ')")
    $i38 = @(& "$S\Revise-Task.ps1" -Repo $r38 -Session 'plan-38' -Task 'G2.I' -Group 'G1' -Note 'test: move an integration task' 2>&1); $ci38 = $LASTEXITCODE
    Case 'group move: an integration task cannot leave its own group' (($ci38 -eq 2) -and (($i38 -join ' ') -match 'GROUP-FIXED G2\.I')) ("exit $ci38 $($i38 -join ' | ')")
    # Once a group's integration task has landed, its suites have run over a membership a move would change.
    $j38b = J $r38
    foreach ($t in $j38b.tasks) { if ($t.id -eq 'G1.I') { $t.state = 'integrated' } }
    Set-Content -Path (Join-Path $r38 '.streams\tasks.json') -Encoding utf8 -Value ($j38b | ConvertTo-Json -Depth 50)
    $f38b = Join-Path $Scratch 'grpmove-landed.json'
    @{ note = 'test: move into a landed group'; edits = @(
        @{ task = 'G2.X'; group = 'G1' },
        @{ task = 'G2.I'; removeDependsOn = @('G2.X') }) } | ConvertTo-Json -Depth 10 | Set-Content $f38b
    $l38 = @(& "$S\Revise-Task.ps1" -Repo $r38 -Session 'plan-38' -File $f38b 2>&1); $cl38 = $LASTEXITCODE
    Case 'group move: a group whose integration task has landed takes no new rows' (($cl38 -eq 2) -and (($l38 -join ' ') -match 'GROUP-LANDED G2\.X') -and (($l38 -join ' ') -match 'G1\.I is already integrated') -and ([string] (T $r38 'G2.X').group -eq 'G2')) ("exit $cl38 $($l38 -join ' | ')")

    # ---- 24. A NAMED ROW CAN BE CLAIMED. "Ticket this one next" could be honoured by nobody: an author wrote G3.T149's
    # ticket and grader under -Role status, which needs no claim, and then no script could flip planned -> ticketed -
    # that transition is author or build only (lib\Streams.ps1:74), both are claim-checked (Update-Task.ps1:37), and
    # Claim-Task.ps1 had no way to choose a row, so the flip answered CLAIM-LOST exit 3. Revise-Task.ps1 releases a
    # BLOCKED row only, so the planner could not reach it either (kit item IN-20260930211404-3356).
    $r39 = New-Repo 'claimbyname' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r39
    $j39 = J $r39
    foreach ($t in $j39.tasks) { $t.state = 'planned' }
    Set-Content -Path (Join-Path $r39 '.streams\tasks.json') -Encoding utf8 -Value ($j39 | ConvertTo-Json -Depth 50)
    # The sort would take G1.A - same group, same chain, board order decides - so naming G1.B proves the sort is skipped.
    $n39 = & "$S\Claim-Task.ps1" -Repo $r39 -Role author -Session 'author-39' -Task 'G1.B' | ConvertFrom-Json
    Case 'claim by name: the named row is claimed although the sort would pick another' ($n39.id -eq 'G1.B') "claimed $($n39.id)"
    # And the dead end itself: with the claim in hand, the row reaches ticketed, which is what the request needed.
    $u39 = @(& "$S\Update-Task.ps1" -Repo $r39 -Task 'G1.B' -Role author -Session 'author-39' -To ticketed -Release -Note 'test: the flip that used to answer CLAIM-LOST' 2>&1); $cu39 = $LASTEXITCODE
    Case 'claim by name: the named row reaches ticketed instead of CLAIM-LOST' (($cu39 -eq 0) -and ((T $r39 'G1.B').state -eq 'ticketed') -and -not (($u39 -join ' ') -match 'CLAIM-LOST')) ("exit $cu39 state=$((T $r39 'G1.B').state) $($u39 -join ' | ')")
    # Every gate the sort applies is applied by name too, and each refusal says which gate stopped it.
    $x39 = @(& "$S\Claim-Task.ps1" -Repo $r39 -Role author -Session 'author-39b' -Task 'G1.B' 2>&1); $cx39 = $LASTEXITCODE
    Case 'claim by name: a row in the wrong state for the role is refused, naming the state' (($cx39 -eq 2) -and (($x39 -join ' ') -match 'REFUSED-TASK G1\.B : author claims a planned row and this one is ticketed')) ("exit $cx39 $($x39 -join ' | ')")
    $y39 = @(& "$S\Claim-Task.ps1" -Repo $r39 -Role author -Session 'author-39b' -Task 'G9.ZZ' 2>&1); $cy39 = $LASTEXITCODE
    Case 'claim by name: an id that is not on the board is refused' (($cy39 -eq 2) -and (($y39 -join ' ') -match 'REFUSED-TASK G9\.ZZ')) ("exit $cy39 $($y39 -join ' | ')")
    $z39 = @(& "$S\Claim-Task.ps1" -Repo $r39 -Role author -Session 'author-39c' -Task 'G1.A' 2>&1); $cz39 = $LASTEXITCODE
    Case 'claim by name: the first free row is still claimable by name' (($cz39 -eq 0) -and (($z39 -join '') -match '"id": "G1.A"')) ("exit $cz39 $(($z39 -join ' ').Substring(0, [Math]::Min(80, ($z39 -join ' ').Length)))")
    $w39 = @(& "$S\Claim-Task.ps1" -Repo $r39 -Role author -Session 'author-39d' -Task 'G1.A' 2>&1); $cw39 = $LASTEXITCODE
    Case 'claim by name: a row under a live claim is refused, naming the holder' (($cw39 -eq 2) -and (($w39 -join ' ') -match 'REFUSED-TASK G1\.A : author author-39c holds it')) ("exit $cw39 $($w39 -join ' | ')")
    # build by name applies the dependency gate, which is the one gate the author path does not have.
    $f39 = Join-Path $Scratch 'claimbyname-add.json'
    @{ tasks = @(@{ id = 'G1.C'; group = 'G1'; title = 'depends on B'; why = @('AC-1'); kind = 'code'; writeSet = @('c.txt'); dependsOn = @('G1.B'); estMinutes = 5
                    artifacts = @{ ticket = '.streams\tickets\G1.A.md'; grader = '.streams\graders\G1.A.ps1'; patch = $null; verdict = $null } }) } | ConvertTo-Json -Depth 10 | Set-Content $f39
    [void](& "$S\Add-Tasks.ps1" -Repo $r39 -Role plan -Session 'plan-39' -File $f39)
    $d39 = @(& "$S\Claim-Task.ps1" -Repo $r39 -Role build -Session 'build-39' -Task 'G1.C' 2>&1); $cd39 = $LASTEXITCODE
    Case 'claim by name: build is refused while a dependency is not built, and the dependency is named' (($cd39 -eq 2) -and (($d39 -join ' ') -match 'REFUSED-TASK G1\.C : a dependency is not built yet \(G1\.B\)') -and ((T $r39 'G1.C').state -eq 'ticketed')) ("exit $cd39 $($d39 -join ' | ')")

    # ---- 25. A ROW NAMED BY A LIVE INBOX HOLD IS SKIPPED BY THE SORT. The contract has an author work an inbox item
    # about a row WITHOUT claiming that row, so the row looks free to Claim-Task.ps1 while its ticket and grader are
    # being rewritten. Measured on G3.T140 on 2026-09-30: one session claimed and released it three times in 34 minutes,
    # its history carrying three claim/release pairs that describe nothing but the collision, and an author that had not
    # hashed the grader first would have re-authored it on top of a live edit (kit item IN-20260930212238-f58e).
    $r40 = New-Repo 'claimchurn' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r40
    # An OPEN item names a row nobody is editing yet, so it must NOT park the row.
    $s40 = @(& "$S\Send-InboxItem.ps1" -Repo $r40 -To stream-build -From 'author-40' -Kind bug -Task 'G1.A' -Ask 'test: open item, nobody is editing the row yet' -Evidence '-')
    $id40 = @($s40 -join ' ' -split ' ' | Where-Object { $_ -like 'IN-*' })[0]
    $o40 = & "$S\Claim-Task.ps1" -Repo $r40 -Role build -Session 'build-40a' -Task '' | ConvertFrom-Json
    Case 'claim churn: an OPEN item naming a row does not park it' ($o40.id -eq 'G1.A') "claimed $($o40.id)"
    [void](& "$S\Update-Task.ps1" -Repo $r40 -Task 'G1.A' -Role build -Session 'build-40a' -To ticketed -Release -Note 'test: back to the queue')
    # Taken, and inside the inbox's silence limit: the sort now steps over it and takes the next row instead.
    [void](& "$S\Set-InboxItem.ps1" -Repo $r40 -Skill stream-build -Id $id40 -Status taken -By 'author-40')
    $t40 = & "$S\Claim-Task.ps1" -Repo $r40 -Role build -Session 'build-40b' | ConvertFrom-Json
    Case 'claim churn: a LIVE hold on a row makes the sort take the next row' ($t40.id -eq 'G1.B') "claimed $($t40.id)"
    # The session working the item is the one that may claim the row, so -Task overrides the skip and says what it rode over.
    $ov40 = @(& "$S\Claim-Task.ps1" -Repo $r40 -Role build -Session 'author-40' -Task 'G1.A' 3>&1 2>&1); $cov40 = $LASTEXITCODE
    Case 'claim churn: -Task overrides the skip and names the hold it rode over' (($cov40 -eq 0) -and (($ov40 -join ' ') -match "$id40 held by author-40 in stream-build") -and ((T $r40 'G1.A').state -eq 'building')) ("exit $cov40 $(($ov40 -join ' ') -replace '\s+', ' ' | ForEach-Object { $_.Substring(0, [Math]::Min(120, $_.Length)) })")
    [void](& "$S\Update-Task.ps1" -Repo $r40 -Task 'G1.A' -Role build -Session 'author-40' -To ticketed -Release -Note 'test: back to the queue again')
    # A DEAD hold must not park a row for ever: past the inbox's silence limit the row is claimable again. The inbox is
    # hand-editable by contract, which is how the fixture ages the hold.
    $ib40 = Join-Path $r40 '.streams\inbox\stream-build.md'
    $old40 = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $lines40 = @([IO.File]::ReadAllLines($ib40) | ForEach-Object { if ($_ -match "^- $id40 \| \S+ \| author-40 \| taken") { ($_ -split ' \| ')[0] + " | $old40 | author-40 | taken" } else { $_ } })
    [IO.File]::WriteAllLines($ib40, $lines40)
    $dd40 = & "$S\Claim-Task.ps1" -Repo $r40 -Role build -Session 'build-40c' | ConvertFrom-Json
    Case 'claim churn: a hold past its inbox limit stops parking the row' ($dd40.id -eq 'G1.A') "claimed $($dd40.id)"
    [void](& "$S\Update-Task.ps1" -Repo $r40 -Task 'G1.A' -Role build -Session 'build-40c' -To ticketed -Release -Note 'test: back once more')
    # And a closed item parks nothing at all.
    [void](& "$S\Set-InboxItem.ps1" -Repo $r40 -Skill stream-build -Id $id40 -Status taken -By 'author-40')
    [void](& "$S\Set-InboxItem.ps1" -Repo $r40 -Skill stream-build -Id $id40 -Status done -By 'author-40' -Note 'test: closed')
    $cl40 = & "$S\Claim-Task.ps1" -Repo $r40 -Role build -Session 'build-40d' | ConvertFrom-Json
    Case 'claim churn: a closed item parks nothing' ($cl40.id -eq 'G1.A') "claimed $($cl40.id)"
    # An OPEN stream-integrate item is different: the integrator, not an author or builder, takes it, and it asks for a
    # state move on the row it names. G13.T056 was released planned by an author for the integrator to undo
    # planned>built, and the next author unit reclaimed it 6 s later, before the integrator took the item (kit item
    # IN-20261018181037-f5b0). Such an item parks its row while it is open too, inside the integrate inbox's limit.
    [void](& "$S\Update-Task.ps1" -Repo $r40 -Task 'G1.A' -Role build -Session 'build-40d' -To ticketed -Release -Note 'test: back for the integrate case')
    $si40 = @(& "$S\Send-InboxItem.ps1" -Repo $r40 -To stream-integrate -From 'author-40' -Kind request -Task 'G1.A' -Ask 'test: undo planned>built' -Evidence '-')
    $ii40 = @($si40 -join ' ' -split ' ' | Where-Object { $_ -like 'IN-*' })[0]
    $ni40 = @(& "$S\Claim-Task.ps1" -Repo $r40 -Role build -Session 'build-40e' 3>&1 2>&1) -join ' '
    Case 'claim churn: an OPEN stream-integrate item naming a row parks it' (($ni40 -match 'NONE') -and ((T $r40 'G1.A').state -eq 'ticketed')) $ni40
    [void](& "$S\Set-InboxItem.ps1" -Repo $r40 -Skill stream-integrate -Id $ii40 -Status taken -By 'integ-40')
    [void](& "$S\Set-InboxItem.ps1" -Repo $r40 -Skill stream-integrate -Id $ii40 -Status done -By 'integ-40' -Note 'test: closed')
    $ci40 = & "$S\Claim-Task.ps1" -Repo $r40 -Role build -Session 'build-40f' | ConvertFrom-Json
    Case 'claim churn: a closed stream-integrate item parks nothing' ($ci40.id -eq 'G1.A') "claimed $($ci40.id)"

    # ---- 26. A NON-GATE ROW THAT DEPENDS ON ITS OWN GROUP'S INTEGRATION TASK DEADLOCKS THE GROUP. stream-integrate
    # claims the integration task once every code, docs and mockup row in the group is integrated, and Claim-Task.ps1
    # only offers a ticketed row whose dependencies are built or later, so the row waits for the integration task and
    # the integration task waits for the row: neither moves and the group can never close. Measured on G1.T12 on
    # 2026-09-30, the Reference Data evidence package, which is built FROM the G1 green run and therefore dependsOn
    # G1.T09 (kit item IN-20260930190112-23e6). Nothing refused the shape at release time and no flag showed it, so a
    # deadlocked group looked exactly like a slow one. Gate rows are exempt, because step B does not wait for a gate.
    $r41 = New-Repo 'deadlock' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r41
    $j41 = J $r41
    $int41 = (($j41.tasks[0] | ConvertTo-Json -Depth 50) | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50)
    $int41.id = 'G1.I'; $int41.kind = 'integration'; $int41.title = 'G1 integration'; $int41.state = 'planned'
    $int41.writeSet = @(); $int41.dependsOn = @(); $int41.claim = $null
    # The integration task must NOT dependsOn the row: the deadlock is the CONTRACT waiting (step B needs every
    # code, docs and mockup row integrated), not an edge, which is why Board.ps1's cycle check never saw it -
    # give it the edge and the board refuses G1.A -> G1.I as a plain two-task cycle instead, testing nothing.
    $int41.artifacts = [ordered]@{ ticket = $null; grader = $null; patch = $null; verdict = $null }
    $j41.tasks = @($j41.tasks) + , $int41
    Set-Content -Path (Join-Path $r41 '.streams\tasks.json') -Encoding utf8 -Value ($j41 | ConvertTo-Json -Depth 50)
    # At release time: the row is refused whole, and the message names the deadlock rather than the edge.
    $f41 = Join-Path $Scratch 'deadlock-add.json'
    @{ tasks = @(@{ id = 'G1.EV'; group = 'G1'; title = 'evidence package built FROM the group green run'; why = @('AC-1'); kind = 'docs'; writeSet = @('evidence.md'); dependsOn = @('G1.I'); estMinutes = 30 }) } | ConvertTo-Json -Depth 10 | Set-Content $f41
    $a41 = @(& "$S\Add-Tasks.ps1" -Repo $r41 -Role plan -Session 'plan-41' -File $f41 2>&1); $ca41 = $LASTEXITCODE
    Case 'deadlock: a new non-gate row that dependsOn its group''s integration task is refused' (($ca41 -eq 2) -and (($a41 -join ' ') -match 'G1\.EV: dependsOn G1\.I, its own group''s integration task, which deadlocks G1') -and ($null -eq (T $r41 'G1.EV'))) ("exit $ca41 $($a41 -join ' | ')")
    # A GATE row carries the same edge safely, and seven of them do on the live board.
    $f41b = Join-Path $Scratch 'deadlock-gate.json'
    @{ tasks = @(@{ id = 'G1.GATE'; group = 'G1'; title = 'owner views the group green run'; why = @('AC-1'); kind = 'gate'; writeSet = @(); dependsOn = @('G1.I'); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $f41b
    $a41b = @(& "$S\Add-Tasks.ps1" -Repo $r41 -Role plan -Session 'plan-41' -File $f41b 2>&1); $ca41b = $LASTEXITCODE
    Case 'deadlock: a GATE row may depend on its group''s integration task' (($ca41b -eq 0) -and ($null -ne (T $r41 'G1.GATE'))) ("exit $ca41b $($a41b -join ' | ')")
    # And the same edge is refused when an EDIT would create it, with the row left exactly as it was.
    $v41 = @(& "$S\Revise-Task.ps1" -Repo $r41 -Session 'plan-41' -Task 'G1.A' -AddDependsOn 'G1.I' -Note 'test: edge that deadlocks' 2>&1); $cv41 = $LASTEXITCODE
    Case 'deadlock: an EDIT that would create the edge is refused' (($cv41 -eq 2) -and (($v41 -join ' ') -match 'GROUP-DEADLOCK G1\.A: G1\.I is its own group''s integration task') -and (@((T $r41 'G1.A').dependsOn) -notcontains 'G1.I')) ("exit $cv41 $($v41 -join ' | ')")
    # An edge already stored is NOT refused, because G1.T12 has a written ruling and its row still has to be editable.
    $j41b = J $r41
    foreach ($t in $j41b.tasks) { if ($t.id -eq 'G1.A') { $t.dependsOn = @('G1.I') } }
    Set-Content -Path (Join-Path $r41 '.streams\tasks.json') -Encoding utf8 -Value ($j41b | ConvertTo-Json -Depth 50)
    $v41b = @(& "$S\Revise-Task.ps1" -Repo $r41 -Session 'plan-41' -Task 'G1.A' -Title 'ruled row, still editable' -Note 'test: a stored edge does not freeze the row' 2>&1); $cv41b = $LASTEXITCODE
    Case 'deadlock: a row that already holds the edge stays editable' (($cv41b -eq 0) -and ((T $r41 'G1.A').title -eq 'ruled row, still editable')) ("exit $cv41b $($v41b -join ' | ')")
    # The status flag is what makes an existing one visible: a deadlocked group looks exactly like a slow one.
    $st41 = @(& "$S\Get-StreamStatus.ps1" -Repo $r41 2>&1)
    Case 'deadlock: the status flags a row that already holds the edge' ((($st41 -join ' ') -match "dependsOn their own group's integration task") -and (($st41 -join ' ') -match 'G1\.A \(ticketed\) -> G1\.I')) (@($st41 | Where-Object { $_ -like 'flags:*' }) -join ' ')
    # And it goes quiet when the edge goes, so the flag measures the board rather than remembering an event.
    [void](& "$S\Revise-Task.ps1" -Repo $r41 -Session 'plan-41' -Task 'G1.A' -RemoveDependsOn 'G1.I' -Note 'test: edge removed')
    $st41b = @(& "$S\Get-StreamStatus.ps1" -Repo $r41 2>&1)
    Case 'deadlock: the flag goes quiet once the edge is removed' ((($st41b -join ' ') -notmatch "dependsOn their own group's integration task")) (@($st41b | Where-Object { $_ -like 'flags:*' }) -join ' ')

    # ---- 62. A LIVE INTEGRATOR'S SUITE RUN IS NOT AN ORPHAN. The integrator sets its integration task building with no
    # claim, and a step-B run lasts 1.5-2 h, so the 45-minute orphan rule freed G2.T90 mid-suite on 2026-10-02 while the
    # integrator held a fresh lock (kit items IN-20261002014307-9bf2, IN-20261002020026-2168).
    $r62 = New-Repo 'r62' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r62
    $old62 = (Get-Date).ToUniversalTime().AddMinutes(-60).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $j62 = J $r62
    $j62.tasks = @($j62.tasks) + , ([ordered]@{ id = 'G1.I'; group = 'G1'; title = 'G1 integration'; why = @('AC-1'); kind = 'integration'; state = 'building'; writeSet = @(); dependsOn = @(); claim = $null; estMinutes = 90
        artifacts = [ordered]@{ ticket = $null; grader = $null; patch = $null; verdict = $null }
        history = @([ordered]@{ at = $old62; by = 'integ-62'; to = 'ticketed'; note = 'added' }, [ordered]@{ at = $old62; by = 'integ-62'; to = 'building'; note = 'step B run 1' }) })
    Set-Content -Path (Join-Path $r62 '.streams\tasks.json') -Encoding utf8 -Value ($j62 | ConvertTo-Json -Depth 50)
    $lock62 = Join-Path $r62 '.streams\integrator.lock'
    Set-Content -Path $lock62 -Value (@{ session = 'integ-62'; at = $old62; beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json)
    $w62 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r62 -Session status-62)
    Case 'suite run: an integration row the LIVE integrator set building is not freed' ((T $r62 'G1.I').state -eq 'building') ($w62 -join ' | ')
    Set-Content -Path $lock62 -Value (@{ session = 'other-62'; at = $old62; beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json)
    $w62b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r62 -Session status-62)
    Case 'suite run: a row set by a session that no longer holds the lock is still freed' ((T $r62 'G1.I').state -eq 'ticketed') ($w62b -join ' | ')

    # ---- 64. A TRX READER THAT DOES NOT TRIM THE TEST NAME IS FLAGGED. MSTest writes 'MyTest ("arg")' for a DataRow
    # result, so the untrimmed split keeps a trailing space and a passing test reads as "did not run" (kit item
    # IN-20260930183248-206d).
    $g64a = Join-Path $Scratch 'g64-untrimmed.ps1'
    Set-Content $g64a "param([string]`$Root)`n`$m = (`$r.Node.testName -split '\(')[0]`n'PASS C1'"
    $l64a = @(& "$S\Test-GraderPortability.ps1" -Grader $g64a); $c64a = $LASTEXITCODE
    Case 'trx name: an untrimmed testName split is flagged' (($c64a -eq 1) -and (($l64a -join ' ') -match 'UNTRIMMED-TESTNAME')) "exit $c64a : $($l64a -join ' | ')"
    $g64b = Join-Path $Scratch 'g64-trimmed.ps1'
    Set-Content $g64b "param([string]`$Root)`n`$m = ((`$r.Node.testName -split '\(')[0]).Trim()`n'PASS C1'"
    $l64b = @(& "$S\Test-GraderPortability.ps1" -Grader $g64b); $c64b = $LASTEXITCODE
    Case 'trx name: a trimmed split is PORTABLE' (($c64b -eq 0) -and (($l64b -join ' ') -match '^PORTABLE')) "exit $c64b : $($l64b -join ' | ')"
    # 64b. A whole-text compare of a reqtools render with the committed view differs between worktree and main on the
    # HEAD stamp alone (kit item IN-20261027041932-62df).
    $g64c = Join-Path $Scratch 'g64-render.ps1'
    Set-Content $g64c "param([string]`$Root)`n`$rt = Join-Path `$Root 'tools\requirements\reqtools.py'`n& python `$rt render `$y `$tmp`nif ((Get-Content -Raw `$tmp) -eq (Get-Content -Raw `$md)) { 'PASS A1' }"
    $l64c = @(& "$S\Test-GraderPortability.ps1" -Grader $g64c); $c64c = $LASTEXITCODE
    Case 'render stamp: an unmasked render compare is flagged' (($c64c -eq 1) -and (($l64c -join ' ') -match 'RENDER-STAMP .*g64-render\.ps1:3')) "exit $c64c : $($l64c -join ' | ')"
    $g64d = Join-Path $Scratch 'g64-render-masked.ps1'
    Set-Content $g64d "param([string]`$Root)`n`$rt = Join-Path `$Root 'tools\requirements\reqtools.py'`n& python `$rt render `$y `$tmp`n`$p = 'Source repository: \S+( \(dirty\))?'`nif (((Get-Content -Raw `$tmp) -replace `$p) -eq ((Get-Content -Raw `$md) -replace `$p)) { 'PASS A1' }"
    $l64d = @(& "$S\Test-GraderPortability.ps1" -Grader $g64d); $c64d = $LASTEXITCODE
    Case 'render stamp: a compare that masks the stamp is PORTABLE' (($c64d -eq 0) -and (($l64d -join ' ') -match '^PORTABLE')) "exit $c64d : $($l64d -join ' | ')"

    # ---- 63. A LONG INTEGRATOR RUN BEATS THE LOCK. Nothing beat integrator.lock during a step-B suite, so the watchdog
    # broke a live integrator's lock twice in one G2 run (kit items IN-20261002014307-9bf2, IN-20261002020026-2168).
    $old63 = (Get-Date).ToUniversalTime().AddMinutes(-15).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Set-Content -Path $lock62 -Value (@{ session = 'integ-62'; at = $old63; beat = $old63 } | ConvertTo-Json)
    $env:STREAM_BEAT_SECONDS = '1'
    try { $o63 = @(& "$S\Invoke-IntegratorRun.ps1" -Repo $r62 -Session integ-62 -Log '.streams\logs\G1.suites.1.unit.txt' -Command "Start-Sleep -Seconds 3; 'suite output'; exit 2"); $x63 = $LASTEXITCODE }
    finally { Remove-Item Env:\STREAM_BEAT_SECONDS -ErrorAction SilentlyContinue }
    $beat63 = [datetime]::Parse((Get-Content -Raw $lock62 | ConvertFrom-Json -AsHashtable -DateKind String).beat, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
    Case 'long run: the lock beat is fresh after the run' ((((Get-Date).ToUniversalTime() - $beat63).TotalMinutes -lt 1)) "beat $beat63"
    Case 'long run: the command''s exit code and output come back' (($x63 -eq 2) -and (($o63 -join ' ') -match 'RUN exit 2') -and ((Get-Content -Raw (Join-Path $r62 '.streams\logs\G1.suites.1.unit.txt')) -match 'suite output')) "exit $x63 : $($o63 -join ' | ')"
    Set-Content -Path $lock62 -Value (@{ session = 'other-62'; at = $old63; beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json)
    $o63b = @(& "$S\Invoke-IntegratorRun.ps1" -Repo $r62 -Session integ-62 -Log '.streams\logs\x.txt' -Command "'should not run'"); $x63b = $LASTEXITCODE
    Case 'long run: refused while another session holds the lock' (($x63b -eq 5) -and (($o63b -join ' ') -match 'LOCK-LOST')) "exit $x63b : $($o63b -join ' | ')"

    # ---- 65. A BROKEN LOCK IS NOT A DEAD INTEGRATOR. The lock beats only while a command runs, so the integrator's
    # analysis after G2 suites run 1 left it 27 min unbeaten; the watchdog broke it and, in the same pass, freed G2.T90
    # to ticketed, 6 s before 4599ecab retook the lock (kit item IN-20261002043357-316b).
    $r65 = New-Repo 'r65' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r65
    $old65 = (Get-Date).ToUniversalTime().AddMinutes(-60).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $stale65 = (Get-Date).ToUniversalTime().AddMinutes(-27).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $j65 = J $r65
    $j65.tasks = @($j65.tasks) + , ([ordered]@{ id = 'G1.I'; group = 'G1'; title = 'G1 integration'; why = @('AC-1'); kind = 'integration'; state = 'building'; writeSet = @(); dependsOn = @(); claim = $null; estMinutes = 90
        artifacts = [ordered]@{ ticket = $null; grader = $null; patch = $null; verdict = $null }
        history = @([ordered]@{ at = $old65; by = 'integ-65'; to = 'ticketed'; note = 'added' }, [ordered]@{ at = $old65; by = 'integ-65'; to = 'building'; note = 'step B run 1' }) })
    Set-Content -Path (Join-Path $r65 '.streams\tasks.json') -Encoding utf8 -Value ($j65 | ConvertTo-Json -Depth 50)
    $lock65 = Join-Path $r65 '.streams\integrator.lock'
    $mark65 = Join-Path $r65 '.streams\integrator.lock.broken'
    Set-Content -Path $lock65 -Value (@{ session = 'integ-65'; at = $old65; beat = $stale65 } | ConvertTo-Json)
    $w65 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r65 -Session status-65)
    Case 'broken lock: the stale lock is broken and the break is recorded' ((-not (Test-Path $lock65)) -and (Test-Path $mark65) -and (($w65 -join ' ') -match 'BROKE integrator lock of integ-65')) ($w65 -join ' | ')
    Case 'broken lock: the setter''s integration row is NOT freed in the pass that breaks its lock' ((T $r65 'G1.I').state -eq 'building') ($w65 -join ' | ')
    $w65b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r65 -Session status-65)
    Case 'broken lock: the row is still kept on the next pass, inside the grace after the break' ((T $r65 'G1.I').state -eq 'building') ($w65b -join ' | ')
    Set-Content -Path $mark65 -Value (@{ session = 'integ-65'; at = (Get-Date).ToUniversalTime().AddMinutes(-50).ToString('yyyy-MM-ddTHH:mm:ssZ'); beat = $stale65 } | ConvertTo-Json)
    $w65c = @(& "$S\Invoke-Watchdog.ps1" -Repo $r65 -Session status-65)
    Case 'broken lock: a setter that never came back loses the row once the grace is over' (((T $r65 'G1.I').state -eq 'ticketed') -and (($w65c -join ' ') -match 'FREED G1\.I')) ($w65c -join ' | ')

    # ---- 61. A COMMIT THAT LANDS WHILE A BASE IS LAID LOSES NOTHING, AND THE RECORDED HEAD IS THE WORKTREE'S. On
    # 2026-10-01 G3.T045 was committed while New-TaskWorktree built G3.T205's base: the worktree sat at the old HEAD, the
    # main diff was taken against the new one, so the base carried G3.T045's untracked test file without its committed
    # ValueEditor.razor edits, and the recorded head named a commit the worktree was not on (kit item
    # IN-20261001203252-2789).
    $r61 = New-Repo 'r61' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r61
    Set-Content (Join-Path $r61 'late.txt') 'untracked, then committed mid-base'
    $hook61 = Join-Path $Scratch 'hook61.ps1'
    Set-Content $hook61 "git -C '$r61' add owner.txt late.txt; git -C '$r61' commit -q -m 'landed while the base was laid'"
    [void](& "$S\Claim-Task.ps1" -Repo $r61 -Role build -Session build-61)
    $env:STREAM_TEST_WORKTREE_HOOK = $hook61
    try { $wt61 = & "$S\New-TaskWorktree.ps1" -Repo $r61 -Task G1.A -Session build-61 -WorktreeRoot (Join-Path $Scratch 'wt61') | Select-Object -Last 1 }
    finally { Remove-Item Env:\STREAM_TEST_WORKTREE_HOOK -ErrorAction SilentlyContinue }
    $own61 = (Get-Content -Raw (Join-Path $wt61 'owner.txt')).Trim()
    Case 'mid-base commit: the committed dirty edit is in the base' ($own61 -eq 'owner dirty') "owner.txt in worktree reads '$own61'"
    $head61 = (git -C $wt61 rev-parse HEAD) | Select-Object -First 1
    Case 'mid-base commit: the recorded head is the commit the worktree sits on' ($head61 -eq (T $r61 'G1.A').base.head) "worktree $head61 recorded $((T $r61 'G1.A').base.head)"

    # ---- 60. A HELD ITEM THAT NAMES ITS ROW ONLY AS THE ASK'S LEADING "<id>:" STILL PARKS THE ROW. IN-20261001161521-42df
    # carried task "-" and an ask starting "G3.T121: grader C1 defect", so the sort handed G3.T121 to a second author
    # twice while the holder rewrote its grader (kit item IN-20261001162407-ee8c).
    $r60 = New-Repo 'r60' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r60
    $ib60 = Join-Path $r60 '.streams\inbox\stream-author.md'
    Add-Content -Path $ib60 -Value "- IN-20261001161521-aaaa | $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) | build-60 | open | bug | - | G1.A: grader C1 defect, rewriting it | -"
    [void](& "$S\Set-InboxItem.ps1" -Repo $r60 -Skill stream-author -Id 'IN-20261001161521-aaaa' -Status taken -By 'author-60a')
    $c60 = & "$S\Claim-Task.ps1" -Repo $r60 -Role build -Session 'build-60' 3>$null | ConvertFrom-Json
    Case 'lead id: a live hold whose ask leads with the row id parks that row' ($c60.id -eq 'G1.B') "claimed $($c60.id)"
    $s60 = @(& "$S\Send-InboxItem.ps1" -Repo $r60 -To stream-plan -From 'author-60b' -Kind request -Ask 'G1.B: widen the write set')
    $id60 = @($s60 -join ' ' -split ' ' | Where-Object { $_ -like 'IN-*' })[0]
    Case 'lead id: Send-InboxItem fills the task field from a leading "<id>:"' ((Get-Content -Raw (Join-Path $r60 '.streams\inbox\stream-plan.md')) -match "$id60 \| \S+ \| author-60b \| open \| request \| G1\.B \|") ($s60 -join ' ')
    $s60b = @(& "$S\Send-InboxItem.ps1" -Repo $r60 -To stream-plan -From 'author-60b' -Kind request -Ask 'Revisit G1.A and G1.B: both widen')
    $id60b = @($s60b -join ' ' -split ' ' | Where-Object { $_ -like 'IN-*' })[0]
    Case 'lead id: an id that does not LEAD the ask is not taken as the task' ((Get-Content -Raw (Join-Path $r60 '.streams\inbox\stream-plan.md')) -match "$id60b \| \S+ \| author-60b \| open \| request \| - \|") ($s60b -join ' ')

    # ---- 59. ONE INTEGRATE-PATCH RUN PER REPO; A LANDED PATCH CAN BE RECORDED FROM BLOCKED; ONE HISTORY LINE PER MOVE.
    # Two drains of one integrator session ran at once on 2026-10-01 and one REBASE-bounced what the other committed;
    # the builder then blocked both rows as already met, and no transition could record them (kit item
    # IN-20261001215631-6eda). Every -To with a -Note was also written to history twice.
    $r59 = New-Repo 'r59' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r59
    [void](Build $r59 'G1.A' 'ok' 'build-59a')
    [void](Build $r59 'G1.B' 'ok' 'build-59b')
    [void](& "$S\Enter-Integrator.ps1" -Repo $r59 -Session integ-59)
    $hold59 = [IO.FileStream]::new((Join-Path $r59 '.streams\integrate-patch.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $o59 = @(& "$S\Integrate-Patch.ps1" -Repo $r59 -Session integ-59 -Task G1.A); $x59 = $LASTEXITCODE
    $hold59.Dispose()
    Case 'drain: a second Integrate-Patch run is refused while one holds the repo' (($x59 -eq 4) -and (($o59 -join ' ') -match '^DRAIN-BUSY') -and ((T $r59 'G1.A').state -eq 'built')) "exit $x59 : $($o59 -join ' | ')"
    $o59b = @(& "$S\Integrate-Patch.ps1" -Repo $r59 -Session integ-59 -Task G1.A)
    $o59c = @(& "$S\Integrate-Patch.ps1" -Repo $r59 -Session integ-59 -Task G1.Z); $x59c = $LASTEXITCODE
    Case 'drain: runs in one process one after another are not refused by each other' (($o59b[0] -eq 'INTEGRATED G1.A') -and ($x59c -eq 0) -and (($o59c -join ' ') -notmatch 'DRAIN-BUSY')) "$($o59b -join ' | ') // exit $x59c $($o59c -join ' | ')"
    $n59 = @((T $r59 'G1.A').history | Where-Object { $_['note'] -eq 'applied; grader PASS on main' }).Count
    Case 'history: a state move with a note is written once' ($n59 -eq 1) "count $n59"
    $doc59 = J $r59
    foreach ($t in $doc59.tasks) { if ($t.id -in @('G1.A', 'G1.B')) { $t.state = 'blocked'; $t.claim = $null } }
    Set-Content -Path (Join-Path $r59 '.streams\tasks.json') -Encoding utf8 -Value ($doc59 | ConvertTo-Json -Depth 50)
    $o59d = @(& "$S\Update-Task.ps1" -Repo $r59 -Task G1.A -Role integrate -Session integ-59 -To integrated -Note 'landed as the committed patch'); $x59d = $LASTEXITCODE
    Case 'landed: blocked -> integrated records a patch that is already on main' (($x59d -eq 0) -and ((T $r59 'G1.A').state -eq 'integrated')) "exit $x59d : $($o59d -join ' | ')"
    $o59e = @(& "$S\Update-Task.ps1" -Repo $r59 -Task G1.B -Role integrate -Session integ-59 -To integrated -Note 'not on main'); $x59e = $LASTEXITCODE
    Case 'landed: blocked -> integrated is refused when the patch is not on main' (($x59e -eq 6) -and (($o59e -join ' ') -match 'reverse-apply clean') -and ((T $r59 'G1.B').state -eq 'blocked')) "exit $x59e : $($o59e -join ' | ')"

    # ---- 58. A SCOPE EDIT NEVER RELEASES A ROW ONTO ITS OLD TICKET, AND THE PLANNER CAN SEND A TICKET BACK. G3.T105 was
    # widened with a test file while blocked and release auto sent it straight to ticketed on the stale ticket, and the
    # plan role had no ticketed>planned to undo it (kit item IN-20261001202016-0019).
    $r58 = New-Repo 'r58' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok'); 'G1.C' = (ContentGrader 'G1.C' 'ok') }); $repos += $r58
    [void](& "$S\Revise-Task.ps1" -Repo $r58 -Session plan-58 -Task G1.A -Release block -Note 'waits for a test file')
    $o58a = @(& "$S\Revise-Task.ps1" -Repo $r58 -Session plan-58 -Task G1.A -AddWriteSet 'tests/G1.A.Tests.cs' -Note 'tests widened with the write set'); $x58a = $LASTEXITCODE
    Case 'stale ticket: a blocked row widened under release auto goes to planned, not ticketed' (($x58a -eq 0) -and ((T $r58 'G1.A').state -eq 'planned')) "exit $x58a : $($o58a -join ' | ') state $((T $r58 'G1.A').state)"
    $o58b = @(& "$S\Revise-Task.ps1" -Repo $r58 -Session plan-58 -Task G1.B -Release planned -Note 're-author: ticket predates the widening'); $x58b = $LASTEXITCODE
    Case 'stale ticket: a NAMED planned sends an unclaimed ticketed row back to an author' (($x58b -eq 0) -and ((T $r58 'G1.B').state -eq 'planned')) "exit $x58b : $($o58b -join ' | ')"
    [void](& "$S\Claim-Task.ps1" -Repo $r58 -Role build -Session build-58 -Task G1.C)
    $o58c = @(& "$S\Revise-Task.ps1" -Repo $r58 -Session plan-58 -Task G1.C -Release planned -Note 'too late'); $x58c = $LASTEXITCODE
    Case 'stale ticket: a row a live session holds is not sent back' (($x58c -eq 2) -and ((T $r58 'G1.C').state -eq 'building')) "exit $x58c : $($o58c -join ' | ')"

    # ---- 57. AN EARLIER GROUP'S INTEGRATION TASK NEVER WAITS ON A LATER GROUP'S ROW. Groups close in the owner's
    # priority order (the board's groups list), and an edge from G1's integration task onto G3.T193 held G1's close
    # hostage to G3 work (owner ruling IN-20261001193348-5979). Add-Tasks and Revise-Task refuse the edge; the reverse
    # edge (a later group waiting on an earlier one) stays legal.
    $r57 = New-Repo 'laterdep' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r57
    $f57 = Join-Path $Scratch 'laterdep-g2.json'
    @{ groups = @(@{ id = 'G2'; name = 'Later'; state = 'released'; origin = 'plan' }); tasks = @(@{ id = 'G2.X'; group = 'G2'; title = 'later row'; why = @('AC-2'); kind = 'code'; writeSet = @('G2.X.txt'); dependsOn = @(); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $f57
    [void](& "$S\Add-Tasks.ps1" -Repo $r57 -Role plan -Session plan-57 -File $f57)
    $j57 = J $r57
    foreach ($gi in @(@('G1.I', 'G1'), @('G2.I', 'G2'))) {
        $it = [ordered]@{ id = $gi[0]; group = $gi[1]; title = "$($gi[1]) integration"; why = @('AC-1'); kind = 'integration'; state = 'planned'; writeSet = @(); dependsOn = @(); claim = $null; estMinutes = 5
            artifacts = [ordered]@{ ticket = $null; grader = $null; patch = $null; verdict = $null }; history = @() }
        $j57.tasks = @($j57.tasks) + , $it
    }
    Set-Content -Path (Join-Path $r57 '.streams\tasks.json') -Encoding utf8 -Value ($j57 | ConvertTo-Json -Depth 50)
    $v57 = @(& "$S\Revise-Task.ps1" -Repo $r57 -Session plan-57 -Task G1.I -AddDependsOn G2.X -Note 'test: earlier close onto later row' 2>&1); $c57 = $LASTEXITCODE
    Case 'later-group dep: an EDIT giving G1''s integration task a G2 row is refused' (($c57 -eq 2) -and (($v57 -join ' ') -match 'LATER-GROUP-DEP G1\.I -> G2\.X') -and (@((T $r57 'G1.I').dependsOn) -notcontains 'G2.X')) ("exit $c57 $($v57 -join ' | ')")
    $v57b = @(& "$S\Revise-Task.ps1" -Repo $r57 -Session plan-57 -Task G2.I -AddDependsOn G1.A -Note 'test: later close onto earlier row' 2>&1); $c57b = $LASTEXITCODE
    Case 'later-group dep: a LATER group''s integration task may wait on an earlier row' (($c57b -eq 0) -and (@((T $r57 'G2.I').dependsOn) -contains 'G1.A')) ("exit $c57b $($v57b -join ' | ')")
    $f57b = Join-Path $Scratch 'laterdep-add.json'
    @{ groups = @(@{ id = 'G3'; name = 'Latest'; state = 'released'; origin = 'plan' }); tasks = @(
        @{ id = 'G3.Y'; group = 'G3'; title = 'latest row'; why = @('AC-3'); kind = 'code'; writeSet = @('G3.Y.txt'); dependsOn = @(); estMinutes = 5 },
        @{ id = 'G2.F'; group = 'G2'; title = 'a G2 row that waits on G3'; why = @('AC-2'); kind = 'code'; writeSet = @('G2.F.txt'); dependsOn = @('G3.Y'); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $f57b
    $a57 = @(& "$S\Add-Tasks.ps1" -Repo $r57 -Role plan -Session plan-57 -File $f57b 2>&1); $ca57 = $LASTEXITCODE
    Case 'later-group dep: an ordinary row may still depend across groups' (($ca57 -eq 0) -and ($null -ne (T $r57 'G2.F'))) ("exit $ca57 $($a57 -join ' | ')")
    $f57c = Join-Path $Scratch 'laterdep-int.json'
    @{ groups = @(@{ id = 'G4'; name = 'Last'; state = 'released'; origin = 'plan' }); tasks = @(
        @{ id = 'G4.Z'; group = 'G4'; title = 'last row'; why = @('AC-4'); kind = 'code'; writeSet = @('G4.Z.txt'); dependsOn = @(); estMinutes = 5 },
        @{ id = 'G3.I'; group = 'G3'; title = 'G3 integration'; why = @('AC-3'); kind = 'integration'; writeSet = @('G3.suites.txt'); dependsOn = @('G3.Y', 'G4.Z'); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $f57c
    $a57c = @(& "$S\Add-Tasks.ps1" -Repo $r57 -Role plan -Session plan-57 -File $f57c 2>&1); $ca57c = $LASTEXITCODE
    Case 'later-group dep: a NEW integration task onto a later group''s row is refused whole' (($ca57c -eq 2) -and (($a57c -join ' ') -match 'G3\.I: LATER-GROUP-DEP G3\.I -> G4\.Z') -and ($null -eq (T $r57 'G3.I')) -and ($null -eq (T $r57 'G4.Z'))) ("exit $ca57c $($a57c -join ' | ')")

    # ---- 27. A NOTED WAIT IS PROGRESS; A BARE BEAT IS NOT, AND THE BREAK SAYS SO. stream-author step 7 hands the
    # finished ticket and grader to a fresh skeptic subagent that may outlast any claim limit, and during that wait there
    # is nothing to write: touching either artifact while a blind reader is inside it invalidates the round. On
    # 2026-09-30 G3.T184's author beat every few minutes through a 72-minute round and lost the claim anyway, throwing
    # away an 11-clause ticket, a PORTABLE grader, a proved RED and two builder probes (kit item IN-20260930224214-efe5).
    # The rule itself is right and stays: G4.T039 beat for 19h14m with both artifacts written and applied nothing, so
    # both-artifacts-set cannot separate a skeptic round from a zombie - the two are identical on disk. What separates
    # them is a NOTE: `Update-Task -Beat -Note` appends history (Update-Task.ps1:65) and history is progress, so a
    # session that says what it is waiting for keeps its claim. stream-author step 7 now requires the note, and the break
    # reason names the remedy for the sessions that were started before that line existed.
    # This case runs at the PRODUCTION 60 minutes, not STREAM_NOPROGRESS_MINUTES=0: at 0 nothing can ever count as
    # progress, so a 0 threshold cannot tell the two waits apart. The wait is aged instead - claim.at, the holder's own
    # history and both artifact mtimes are moved back 90 minutes, which is exactly the state a long round leaves.
    $r42 = New-Repo 'skeptic' @{ 'G1.T1' = 'exit 0' }; $repos += $r42
    $d42 = J $r42
    foreach ($x in $d42.tasks) { if ($x.id -eq 'G1.T1') { $x.state = 'planned' } }
    $d42 | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $r42 '.streams\tasks.json')
    $old42 = (Get-Date).ToUniversalTime().AddMinutes(-90)
    function Age-Claim([string] $repo, [string] $id, [string] $sess, [datetime] $when) {
        $doc = J $repo
        foreach ($x in $doc.tasks) {
            if ($x.id -ne $id) { continue }
            if ($x.claim) { $x.claim.at = $when.ToString('yyyy-MM-ddTHH:mm:ssZ') }
            foreach ($h in @($x.history)) { if ($h.by -eq $sess) { $h.at = $when.ToString('yyyy-MM-ddTHH:mm:ssZ') } }
            foreach ($k in @('ticket', 'grader')) {
                $v = $x.artifacts[$k]
                if ($v) { (Get-Item -LiteralPath (Join-Path $repo $v)).LastWriteTimeUtc = $when }
            }
        }
        $doc | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $repo '.streams\tasks.json')
    }
    $cl42 = & "$S\Claim-Task.ps1" -Repo $r42 -Role author -Session author-sk | ConvertFrom-Json
    Case 'skeptic round: the fixture holds one author claim with its ticket and grader already written' (($cl42.id -eq 'G1.T1') -and ($cl42.artifacts.ticket) -and ($cl42.artifacts.grader)) "$($cl42.id) $($cl42.artifacts.ticket) $($cl42.artifacts.grader)"

    # A BARE beat through a 90-minute wait: the claim goes, because a zombie author beats exactly like a working one.
    Age-Claim $r42 'G1.T1' 'author-sk' $old42
    [void](& "$S\Update-Task.ps1" -Repo $r42 -Task 'G1.T1' -Role author -Session author-sk -Beat)
    $w42 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r42 -Session status-sk)
    $b42 = "$(@($w42 | Where-Object { $_ -like 'BROKE G1.T1*' } | Select-Object -First 1))"
    Case 'skeptic round: a bare beat does not save a claim that is 90 minutes idle' (($b42) -and (-not (T $r42 'G1.T1').claim)) ($w42 -join ' | ')
    Case 'skeptic round: and the reason names the remedy, so the session knows what to do instead' (($b42 -match 'A BARE BEAT IS NOT PROGRESS') -and ($b42 -match 'Update-Task -Beat -Note')) "$b42"

    # The same 90-minute wait, NOTED: the author says what it is waiting for, and the claim survives the same pass.
    $cl42b = & "$S\Claim-Task.ps1" -Repo $r42 -Role author -Session author-sk2 | ConvertFrom-Json
    Age-Claim $r42 'G1.T1' 'author-sk2' $old42
    [void](& "$S\Update-Task.ps1" -Repo $r42 -Task 'G1.T1' -Role author -Session author-sk2 -Beat -Note 'skeptic round: subagent still reading the ticket and grader, nothing to write until it returns')
    $w42b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r42 -Session status-sk)
    $t42b = T $r42 'G1.T1'
    Case 'skeptic round: a NOTED wait keeps the claim through the same pass' ((@($w42b | Where-Object { $_ -like 'BROKE G1.T1*' }).Count -eq 0) -and ($t42b.claim) -and ($t42b.claim.session -eq 'author-sk2')) ($w42b -join ' | ')
    Case 'skeptic round: the note itself is on the row, so the wait is auditable' ((@($t42b.history | Where-Object { "$($_.note)" -like 'skeptic round: subagent still reading*' -and $_.by -eq 'author-sk2' }).Count -eq 1)) ((@($t42b.history)[-1] | ConvertTo-Json -Compress))

    # ---- 52. a recorded path that no longer EXISTS supersedes nothing. When this host's worktrees moved from C: to D:
    # the tasks kept recording C:\devops\worktrees\..., and at 15:35Z on 2026-10-01 the watchdog reaped nine D: trees as
    # "superseded copy; the task records C:\...": the tree it deleted was the task's own. A built task's tree is kept
    # under no disk pressure, so a stale record must leave it exactly where the state rules leave it.
    $r52 = New-Repo 'r52' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r52
    $wt52 = Build $r52 'G1.A' 'ok' 'build-52'
    foreach ($f in @(Get-ChildItem $wt52 -Recurse -File -Force)) { $f.LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-90) }
    $doc52 = J $r52
    ($doc52.tasks | Where-Object { $_.id -eq 'G1.A' }).base = @{ worktree = (Join-Path (Split-Path $wt52) 'G1.A-moved-away') }
    Set-Content -Path (Join-Path $r52 '.streams\tasks.json') -Encoding utf8 -Value ($doc52 | ConvertTo-Json -Depth 50)
    $w52 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r52 -Session status-52)
    Case 'stale record: a built tree is not reaped because the task records a path that is gone' (Test-Path $wt52) ($w52 -join ' | ')
    Case 'stale record: nothing is called a superseded copy of a missing tree' (($w52 -join ' ') -notmatch 'superseded') ($w52 -join ' | ')

    # ---- 53. the quiet period protects an ORPHAN too. Save-BeforeReap returned for a tree no task owns before it read
    # the clock, so a builder's hand-made probe tree was reaped however recently it was written: G3.T106-probe went on
    # 2026-10-01 while a fresh G3.T106 build held a live claim.
    $probe53 = Join-Path (Split-Path $wt52) 'G1.A-probe'
    git -C $r52 worktree add -q --detach $probe53 2>&1 | Out-Null
    Set-Content (Join-Path $probe53 'scratch.txt') 'probe in use'
    $env:STREAM_REAP_QUIET_MINUTES = '10'
    $w53 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r52 -Session status-53)
    Case 'orphan quiet period: a probe tree written to just now is kept' ((Test-Path $probe53) -and (($w53 -join ' ') -match 'KEPT orphan')) ($w53 -join ' | ')
    foreach ($f in @(Get-ChildItem $probe53 -Recurse -File -Force)) { $f.LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-90) }
    $w53b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r52 -Session status-53)
    $env:STREAM_REAP_QUIET_MINUTES = '0'
$env:STREAM_RUNNER_START_JITTER_SECONDS = '0'   # no random start wait for the runner cases
    Case 'orphan quiet period: once quiet, the orphan is reaped as before' (-not (Test-Path $probe53)) ($w53b -join ' | ')



    # ---- the claim-time disk floor (owner ruling IN-20261001160218-2d56) ----
    # On 2026-09-30 C: reached 0 GB with builders live and four G3.T120 clauses read red on a sound patch. A build claim
    # and a new integrator lock are now refused under 5 GB free, by name and with the measured figure, and the page
    # flags it. The reading comes through STREAM_FREE_MB_TEST, because a self-test cannot fill a disk.
    $r54 = New-Repo 'diskfloor' @{ 'G1.T1' = 'exit 0' }; $repos += $r54
    $env:STREAM_FREE_MB_TEST = '4000'
    $o54 = @(& "$S\Claim-Task.ps1" -Repo $r54 -Role build -Session build-df); $x54 = $LASTEXITCODE
    $t54 = T $r54 'G1.T1'
    Case 'disk floor: a build claim under 5 GB is refused with exit 6' ($x54 -eq 6) "exit $x54 : $($o54 -join ' | ')"
    Case 'disk floor: the refusal is named and carries the measured free space' (($o54 -join ' ') -match '^REFUSED-DISK [A-Za-z]: has 3\.91 GB free \(4000 MB\), under the 5 GB floor that build claims need') ($o54 -join ' | ')
    Case 'disk floor: a refused claim writes nothing - the row stays ticketed with no claim' (($t54.state -eq 'ticketed') -and (-not $t54.claim)) (($t54 | ConvertTo-Json -Compress -Depth 5))
    $oi54 = @(& "$S\Enter-Integrator.ps1" -Repo $r54 -Session int-df); $xi54 = $LASTEXITCODE
    Case 'disk floor: a new integrator lock is refused with exit 6, by name, and no lock file is written' (($xi54 -eq 6) -and (($oi54 -join ' ') -match '^REFUSED-DISK .*integrate claims need') -and (-not (Test-Path (Join-Path $r54 '.streams\integrator.lock')))) "exit $xi54 : $($oi54 -join ' | ')"
    $f54 = "$(@(& "$S\Get-StreamStatus.ps1" -Repo $r54 | Where-Object { $_ -like 'flags: *' })[0])"
    Case 'disk floor: the status flags say claims are refused and why' ($f54 -match 'CLAIMS REFUSED on drive [A-Za-z]: - 3\.9 GB free is under the 5 GB claim floor') "$f54"
    $env:STREAM_FREE_MB_TEST = '6000'
    $oi54b = @(& "$S\Enter-Integrator.ps1" -Repo $r54 -Session int-df); $xi54b = $LASTEXITCODE
    $o54b = @(& "$S\Claim-Task.ps1" -Repo $r54 -Role build -Session build-df); $x54b = $LASTEXITCODE
    Case 'disk floor: above the floor the same build claim succeeds' (($x54b -eq 0) -and ((T $r54 'G1.T1').state -eq 'building')) "exit $x54b : $($o54b -join ' | ')"
    Case 'disk floor: above the floor the integrator lock is taken' (($xi54b -eq 0) -and (Test-Path (Join-Path $r54 '.streams\integrator.lock'))) "exit $xi54b : $($oi54b -join ' | ')"
    $f54b = "$(@(& "$S\Get-StreamStatus.ps1" -Repo $r54 | Where-Object { $_ -like 'flags: *' })[0])"
    Case 'disk floor: above the floor nothing is flagged as refused' ($f54b -notmatch 'CLAIMS REFUSED') "$f54b"
    # An integrate already in flight is never cut off: the holder's refresh still succeeds under the floor.
    $env:STREAM_FREE_MB_TEST = '4000'
    $oi54c = @(& "$S\Enter-Integrator.ps1" -Repo $r54 -Session int-df); $xi54c = $LASTEXITCODE
    Case 'disk floor: the lock holder still refreshes under the floor' (($xi54c -eq 0) -and (($oi54c -join ' ') -match 'refreshed')) "exit $xi54c : $($oi54c -join ' | ')"
    Remove-Item Env:\STREAM_FREE_MB_TEST -ErrorAction SilentlyContinue

    # ---- 55. a note-only revise never moves a row, and the planner can park one (kit item IN-20261001191046-5fcc).
    # release defaulted to auto, so 'Revise-Task -Task X -Note ...' with no edit RELEASED a blocked row: G3.T202 went
    # blocked -> planned at 2026-10-01T19:09:46Z, and no role could park it again.
    $r55 = New-Repo 'r55' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r55
    $o55a = @(& "$S\Revise-Task.ps1" -Repo $r55 -Session plan-55 -Task G1.A -Release block); $x55a = $LASTEXITCODE
    Case 'park: block without a note is refused and writes nothing' (($x55a -eq 2) -and (($o55a -join ' ') -match 'BLOCK-NO-NOTE G1\.A') -and ((T $r55 'G1.A').state -eq 'ticketed')) "exit $x55a : $($o55a -join ' | ')"
    $o55b = @(& "$S\Revise-Task.ps1" -Repo $r55 -Session plan-55 -Task G1.A -Release block -Note 'waits for G1.Z ticketed'); $x55b = $LASTEXITCODE
    Case 'park: block with a note moves a ticketed row to blocked' (($x55b -eq 0) -and ((T $r55 'G1.A').state -eq 'blocked')) "exit $x55b : $($o55b -join ' | ')"
    $o55c = @(& "$S\Revise-Task.ps1" -Repo $r55 -Session plan-55 -Task G1.A -Note 'just a note'); $x55c = $LASTEXITCODE
    Case 'note-only: a revise that only adds a note keeps a blocked row blocked' (($x55c -eq 0) -and ((T $r55 'G1.A').state -eq 'blocked') -and ((((T $r55 'G1.A').history | Select-Object -Last 1)['note']) -match 'just a note')) "exit $x55c : $($o55c -join ' | ') state $((T $r55 'G1.A').state)"
    $o55d = @(& "$S\Revise-Task.ps1" -Repo $r55 -Session plan-55 -Task G1.A -Release auto -Note 'G1.Z is ticketed'); $x55d = $LASTEXITCODE
    Case 'release: a NAMED auto still releases (ticket and grader present -> ticketed)' (($x55d -eq 0) -and ((T $r55 'G1.A').state -eq 'ticketed')) "exit $x55d : $($o55d -join ' | ')"
    [void](& "$S\Claim-Task.ps1" -Repo $r55 -Role build -Session build-55 -Task G1.B)
    $o55e = @(& "$S\Revise-Task.ps1" -Repo $r55 -Session plan-55 -Task G1.B -Release block -Note 'park it'); $x55e = $LASTEXITCODE
    Case 'park: a row a live session holds is refused' (($x55e -eq 2) -and (($o55e -join ' ') -match 'BLOCK-CLAIMED G1\.B') -and ((T $r55 'G1.B').state -eq 'building')) "exit $x55e : $($o55e -join ' | ')"

    # ---- 55r. the planner retires a superseded blocked row (kit item IN-20261009150944-5bbd). No role could move a row
    # out of blocked except back into work, so G5.T101, G5.T134, G5.T143 and G2.T114 sat blocked for good and inflated
    # the board's blocked count. retire is guarded: note, no claim, empty write set, no open dependent.
    $r55r = New-Repo 'r55r' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok'); 'G1.C' = (ContentGrader 'G1.C' 'ok') }); $repos += $r55r
    [void](& "$S\Revise-Task.ps1" -Repo $r55r -Session plan-55r -Task G1.B -AddDependsOn G1.A -Release keep -Note 'B waits on A')
    [void](& "$S\Revise-Task.ps1" -Repo $r55r -Session plan-55r -Task G1.A -Release block -Note 'superseded by G1.C')
    $o55ra = @(& "$S\Revise-Task.ps1" -Repo $r55r -Session plan-55r -Task G1.A -Release retire -Note 'superseded by G1.C'); $x55ra = $LASTEXITCODE
    Case 'retire: a row that still owns files is refused' (($x55ra -eq 2) -and (($o55ra -join ' ') -match 'RETIRE-WRITESET G1\.A') -and ((T $r55r 'G1.A').state -eq 'blocked')) "exit $x55ra : $($o55ra -join ' | ')"
    $o55rb = @(& "$S\Revise-Task.ps1" -Repo $r55r -Session plan-55r -Task G1.C -Release retire -Note 'not blocked'); $x55rb = $LASTEXITCODE
    Case 'retire: only a blocked row can be retired' (($x55rb -eq 2) -and (($o55rb -join ' ') -match 'RETIRE-STATE G1\.C') -and ((T $r55r 'G1.C').state -eq 'ticketed')) "exit $x55rb : $($o55rb -join ' | ')"
    $o55rc = @(& "$S\Revise-Task.ps1" -Repo $r55r -Session plan-55r -Task G1.A -RemoveWriteSet 'G1.A.txt' -Release retire); $x55rc = $LASTEXITCODE
    Case 'retire: a retire with no note is refused' (($x55rc -eq 2) -and (($o55rc -join ' ') -match 'RETIRE-NO-NOTE G1\.A')) "exit $x55rc : $($o55rc -join ' | ')"
    $o55rd = @(& "$S\Revise-Task.ps1" -Repo $r55r -Session plan-55r -Task G1.A -RemoveWriteSet 'G1.A.txt' -Release retire -Note 'superseded by G1.C'); $x55rd = $LASTEXITCODE
    $t55rd = T $r55r 'G1.A'
    Case 'retire: an open row that still dependsOn it refuses the batch and nothing is written' (($x55rd -eq 2) -and (($o55rd -join ' ') -match 'RETIRE-DEPENDED G1\.A : open row\(s\) G1\.B') -and ($t55rd.state -eq 'blocked') -and (@($t55rd.writeSet) -contains 'G1.A.txt')) "exit $x55rd : $($o55rd -join ' | ')"
    $f55r = Join-Path $Scratch 'r55r-retire.json'
    @{ note = 'withdraw G1.A'; edits = @(
        @{ task = 'G1.B'; removeDependsOn = @('G1.A'); release = 'keep' },
        @{ task = 'G1.A'; removeWriteSet = @('G1.A.txt'); release = 'retire'; note = 'superseded by G1.C' }) } | ConvertTo-Json -Depth 5 | Set-Content $f55r
    $o55re = @(& "$S\Revise-Task.ps1" -Repo $r55r -Session plan-55r -File $f55r); $x55re = $LASTEXITCODE
    $t55re = T $r55r 'G1.A'
    Case 'retire: with its dependents unwired in the same batch the row goes done, marked retired' (($x55re -eq 0) -and (($o55re -join ' ') -match 'RETIRED G1\.A') -and ($t55re.state -eq 'done') -and ($t55re['retired'] -and $t55re['retired']['note'] -eq 'superseded by G1.C' -and $t55re['retired']['by'] -eq 'plan-55r') -and ((($t55re.history | Select-Object -Last 1)['note']) -match '^RETIRED: ')) "exit $x55re : $($o55re -join ' | ')"
    [void](& "$S\Revise-Task.ps1" -Repo $r55r -Session plan-55r -Task G1.C -Release block -Note 'park')
    $o55rf = @(& "$S\Update-Task.ps1" -Repo $r55r -Task G1.C -Role plan -Session plan-55r -To done -Note 'skip the guards' 2>&1); $x55rf = $LASTEXITCODE
    Case 'retire: Update-Task -Role plan cannot make the blocked>done move without the guards' (($x55rf -ne 0) -and ((T $r55r 'G1.C').state -eq 'blocked')) "exit $x55rf : $($o55rf -join ' | ')"
    $l55r = "$(@(& "$S\Get-StreamStatus.ps1" -Repo $r55r | Where-Object { $_ -like 'tasks: *' })[0])"
    Case 'retire: the tasks line counts the row as retired, not done and not blocked' (($l55r -match '\bdone 0\b') -and ($l55r -match '\bretired 1\b') -and ($l55r -match '\bblocked 1\b')) "$l55r"
    $m55r = & "$S\Get-StreamStatus.ps1" -Repo $r55r -Json | ConvertFrom-Json
    Case 'retire: the model buckets it retired and lists it as nothing to commit' ((@($m55r.tasks | Where-Object { $_.id -eq 'G1.A' })[0].bucket -eq 'retired') -and ($m55r.groups[0].counts.retired -eq 1) -and (@($m55r.owner.uncommitted) -notcontains 'G1.A')) ($m55r.groups[0].counts | ConvertTo-Json -Compress)
    $p55r = Join-Path $Scratch 'r55r-status.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $r55r -Session status-55r -Out $p55r -MirrorFile (Join-Path $Scratch 'r55r-no-mirror.txt'))
    $h55r = if (Test-Path $p55r) { [IO.File]::ReadAllText($p55r) } else { '' }
    Case 'retire: the page draws the row with a styled retired pill' (($h55r -match 'class="pill s-retired">retired<') -and ($h55r -match '\.s-retired\{')) "page $($h55r.Length) chars"
    $c55r = @(& "$S\Test-GroupClose.ps1" -Repo $r55r -Group G1 -DryRun)
    $or55r = "$(@($c55r | Where-Object { $_ -match 'OPEN-ROWS' })[0])"
    Case 'retire: the close rule does not count a retired row as open' (($or55r -match 'G1\.B') -and ($or55r -notmatch 'G1\.A\b')) "$or55r"

    # ---- 55w. dependsWhy: a per-edge reason (kit item IN-20261018144201-44e6, owner request IN-20261018143920-ebda).
    # An unstated edge cannot be told apart from an artificial file-order wait, so the planner states why an edge exists.
    $r55w = New-Repo 'r55w' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok'); 'G1.C' = (ContentGrader 'G1.C' 'ok') }); $repos += $r55w
    $o55wa = @(& "$S\Revise-Task.ps1" -Repo $r55w -Session plan-55w -Task G1.B -DependsWhy @{ 'G1.A' = 'reads the table A adds' } -Note 'why'); $x55wa = $LASTEXITCODE
    Case 'dependsWhy: a reason for an edge the row does not hold is refused and nothing is written' (($x55wa -eq 2) -and (($o55wa -join ' ') -match 'DEPWHY-NO-EDGE G1\.B -> G1\.A') -and -not (@((T $r55w 'G1.B')['dependsWhy'].Keys) -contains 'G1.A')) "exit $x55wa : $($o55wa -join ' | ')"
    $o55wb = @(& "$S\Revise-Task.ps1" -Repo $r55w -Session plan-55w -Task G1.B -AddDependsOn G1.A -DependsWhy @{ 'G1.A' = 'reads the table A adds' } -Release keep -Note 'B waits on A'); $x55wb = $LASTEXITCODE
    $t55wb = T $r55w 'G1.B'
    Case 'dependsWhy: an edge added with its reason stores both' (($x55wb -eq 0) -and (@($t55wb.dependsOn) -contains 'G1.A') -and ($t55wb['dependsWhy']['G1.A'] -eq 'reads the table A adds') -and (($o55wb -join ' ') -match 'depwhy G1\.A')) "exit $x55wb : $($o55wb -join ' | ')"
    $o55wc = @(& "$S\Revise-Task.ps1" -Repo $r55w -Session plan-55w -Task G1.B -DependsWhy @{ 'G1.A' = "two`nlines" }); $x55wc = $LASTEXITCODE
    Case 'dependsWhy: a multi-line reason is refused' (($x55wc -eq 2) -and (($o55wc -join ' ') -match 'DEPWHY-BAD G1\.B -> G1\.A') -and ((T $r55w 'G1.B')['dependsWhy']['G1.A'] -eq 'reads the table A adds')) "exit $x55wc : $($o55wc -join ' | ')"
    [void](& "$S\Revise-Task.ps1" -Repo $r55w -Session plan-55w -Task G1.C -Release block -Note 'park')
    [void](& "$S\Revise-Task.ps1" -Repo $r55w -Session plan-55w -Task G1.C -AddDependsOn G1.A -Release keep -Note 'C waits on A')
    $o55wd = @(& "$S\Revise-Task.ps1" -Repo $r55w -Session plan-55w -Task G1.C -DependsWhy @{ 'G1.A' = 'calls the API A adds' }); $x55wd = $LASTEXITCODE
    Case 'dependsWhy: a reason-only edit keeps a blocked row blocked' (($x55wd -eq 0) -and ((T $r55w 'G1.C').state -eq 'blocked') -and ((T $r55w 'G1.C')['dependsWhy']['G1.A'] -eq 'calls the API A adds')) "exit $x55wd : $($o55wd -join ' | ') state $((T $r55w 'G1.C').state)"
    $o55we = @(& "$S\Revise-Task.ps1" -Repo $r55w -Session plan-55w -Task G1.B -RemoveDependsOn G1.A -Release keep -Note 'flip'); $x55we = $LASTEXITCODE
    $t55we = T $r55w 'G1.B'
    Case 'dependsWhy: dropping the edge keeps its reason for when it comes back' (($x55we -eq 0) -and (@($t55we.dependsOn) -notcontains 'G1.A') -and ($t55we['dependsWhy']['G1.A'] -eq 'reads the table A adds')) "exit $x55we : $($o55we -join ' | ')"
    $f55w = Join-Path $Scratch 'r55w-why.json'
    @{ note = 'clear'; edits = @(@{ task = 'G1.C'; dependsWhy = @{ 'G1.A' = '' }; release = 'keep' }) } | ConvertTo-Json -Depth 5 | Set-Content $f55w
    $o55wf = @(& "$S\Revise-Task.ps1" -Repo $r55w -Session plan-55w -File $f55w); $x55wf = $LASTEXITCODE
    Case 'dependsWhy: an empty reason in a batch file clears it' (($x55wf -eq 0) -and (($o55wf -join ' ') -match 'depwhy -G1\.A') -and -not (@((T $r55w 'G1.C')['dependsWhy'].Keys) -contains 'G1.A')) "exit $x55wf : $($o55wf -join ' | ')"
    # ---- 55s. retire backfill (kit item IN-20261009155410-5b5e): rows moved to done as a withdrawal before retire existed
    # (G5.T101, G5.T134, G5.T143, G2.T114 at 2026-10-09T15:21:48Z) counted as landed work. A done row that never reached
    # integrated and holds no patch is marked retired in place; one that delivered work stays done.
    $r55s = New-Repo 'r55s' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r55s
    [void](& "$S\Update-Task.ps1" -Repo $r55s -Task G1.A -Role integrate -Session int-55s -To done -Note 'withdrawn, no patch')
    [void](& "$S\Update-Task.ps1" -Repo $r55s -Task G1.B -Role integrate -Session int-55s -To done -Artifacts @{ patch = '.streams\patches\G1.B.patch' } -Note 'landed by hand')
    $o55sa = @(& "$S\Revise-Task.ps1" -Repo $r55s -Session plan-55s -Task G1.A -RemoveWriteSet 'G1.A.txt' -Release retire -Note 'withdrawn before retire existed'); $x55sa = $LASTEXITCODE
    $t55sa = T $r55s 'G1.A'
    Case 'retire backfill: a done row that never landed is marked retired in place' (((T $r55s 'G1.A').state -eq 'done') -and ($x55sa -eq 0) -and (($o55sa -join ' ') -match 'RETIRED G1\.A \(backfill\)') -and $t55sa['retired'] -and ((($t55sa.history | Select-Object -Last 1)['note']) -match '^RETIRED \(backfill')) "exit $x55sa : $($o55sa -join ' | ') state $($t55sa.state)"
    $o55sb = @(& "$S\Revise-Task.ps1" -Repo $r55s -Session plan-55s -Task G1.A -Release retire -Note 'again'); $x55sb = $LASTEXITCODE
    Case 'retire backfill: a row already retired is refused' (($x55sb -eq 2) -and (($o55sb -join ' ') -match 'RETIRE-ALREADY G1\.A')) "exit $x55sb : $($o55sb -join ' | ')"
    $o55sc = @(& "$S\Revise-Task.ps1" -Repo $r55s -Session plan-55s -Task G1.B -RemoveWriteSet 'G1.B.txt' -Release retire -Note 'try it'); $x55sc = $LASTEXITCODE
    $t55sc = T $r55s 'G1.B'
    Case 'retire backfill: a done row holding a patch stays done and unmarked' (($x55sc -eq 2) -and (($o55sc -join ' ') -match 'RETIRE-LANDED G1\.B') -and (-not $t55sc['retired']) -and (@($t55sc.writeSet) -contains 'G1.B.txt')) "exit $x55sc : $($o55sc -join ' | ')"
    $l55s = "$(@(& "$S\Get-StreamStatus.ps1" -Repo $r55s | Where-Object { $_ -like 'tasks: *' })[0])"
    Case 'retire backfill: the tasks line moves the backfilled row from done to retired' (($l55s -match '\bdone 1\b') -and ($l55s -match '\bretired 1\b')) "$l55s"

    # ---- 56. an integration task's since counts only patches that CHANGED the tree. Every note on an integrated row
    # (a grader re-author, a plan revise) is stamped to=integrated, so the latest such entry moved G1.T09's since past
    # suite run 4 on 2026-10-01 and its fresh receipts read stale (kit item IN-20261001210748-4ba7).
    . "$S\lib\Recovery.ps1"
    $h54 = { param($at, $to, $note) @{ at = $at; by = 'x'; to = $to; note = $note } }
    $doc54 = @{ tasks = @(
        @{ id = 'G1.A'; group = 'G1'; kind = 'code'; history = @(
            (& $h54 '2026-10-01T10:00:00Z' 'built' 'handoff'),
            (& $h54 '2026-10-01T11:00:00Z' 'integrated' 'applied; grader PASS on main'),
            (& $h54 '2026-10-01T15:00:00Z' 'integrated' 'grader C1 re-authored, patch untouched')) },
        @{ id = 'G1.M'; group = 'G1'; kind = 'mockup'; history = @(
            (& $h54 '2026-10-01T09:00:00Z' 'built' 'handoff'),
            (& $h54 '2026-10-01T14:00:00Z' 'integrated' 'mockup: no tree change')) },
        @{ id = 'G1.I'; group = 'G1'; kind = 'integration'; history = @() }) }
    $since54 = Get-TaskSince $doc54 ($doc54.tasks | Where-Object { $_.id -eq 'G1.I' })
    Case 'integration since: a note-only entry on an integrated row does not move it' ($since54 -eq '2026-10-01T11:00:00Z') $since54
    $doc54.tasks[0].history += @(& $h54 '2026-10-01T16:00:00Z' 'ticketed' 'fix reopened'), (& $h54 '2026-10-01T17:00:00Z' 'built' 'handoff'), (& $h54 '2026-10-01T18:00:00Z' 'integrated' 'applied; grader PASS on main')
    $since54b = Get-TaskSince $doc54 ($doc54.tasks | Where-Object { $_.id -eq 'G1.I' })
    Case 'integration since: a later real apply still moves it' ($since54b -eq '2026-10-01T18:00:00Z') $since54b

    # ---- 57. a worktree whose base fails part-way still has that base STAGED (kit item IN-20261002073838-76a8). A
    # dependency patch that would not apply stopped New-TaskWorktree before its `git add -A`, so the owner's uncommitted
    # files sat unstaged in G3.T235 and G3.T202-2, the export called them OUTSIDE the write set, and the watchdog kept
    # both trees. Fixture: G1.B depends on built G1.A, whose patch no longer applies; owner.txt is the owner's dirt.
    $r57 = New-Repo 'r57' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r57
    [void](Build $r57 'G1.A' 'ok' 'build-57a')
    Set-Content -Path (Join-Path $r57 '.streams\patches\G1.A.patch') -Value "diff --git a/G1.A.txt b/G1.A.txt`n--- a/G1.A.txt`n+++ b/G1.A.txt`n@@ -1 +1 @@`n-no such line`n+ok"
    $doc57 = J $r57
    ($doc57.tasks | Where-Object { $_.id -eq 'G1.B' }).dependsOn = @('G1.A')
    Set-Content -Path (Join-Path $r57 '.streams\tasks.json') -Encoding utf8 -Value ($doc57 | ConvertTo-Json -Depth 50)
    [void](& "$S\Claim-Task.ps1" -Repo $r57 -Role build -Session build-57b -Task G1.B)
    $root57 = Join-Path $Scratch 'wt57'
    $threw57 = $false
    try { [void](& "$S\New-TaskWorktree.ps1" -Repo $r57 -Task G1.B -Session build-57b -WorktreeRoot $root57 2>&1) } catch { $threw57 = $true }
    $wt57 = Join-Path $root57 'G1.B'
    Case 'failed base: New-TaskWorktree still fails when a dependency patch does not apply' ($threw57 -and (Test-Path $wt57)) "threw=$threw57 exists=$(Test-Path $wt57)"
    $cached57 = @(git -C $wt57 diff --cached --name-only)
    $x57 = @(& "$S\Export-TaskPatch.ps1" -Repo $r57 -Task G1.B -Worktree $wt57 -OutFile '.streams\patches\G1.B.probe.patch' 2>&1)
    Case 'failed base: the owner''s dirt that was laid down is staged, not left as a change' ($cached57 -contains 'owner.txt') ($cached57 -join ',')
    Case 'failed base: the export reads EMPTY, never OUTSIDE, so the reaper can release the tree' ((($x57 -join ' ') -match 'EMPTY') -and (($x57 -join ' ') -notmatch 'OUTSIDE')) ($x57 -join ' | ')

    # ---- 58. a beat that cannot get the tasks.json lock is skipped, never fatal (kit item IN-20261003171122-a58c). On
    # 2026-10-03 a planner held the lock past the 15-second wait while G3.T147's grader ran with -BeatTask; the throw ended
    # Invoke-Grader, the child grader ran on as an orphan holding the .part log, and the next run failed on that file.
    # Fixture: another holder keeps tasks.json.lock open for the whole grader run.
    $pid58 = Join-Path $Scratch 'grader58.pid'
    $g58 = "param([string]`$Root)`nSet-Content -LiteralPath '$pid58' -Value `$PID`nStart-Sleep -Seconds 20`n'PASS C1'`nexit 0"
    $r58 = New-Repo 'r58' @{ 'G1.L' = $g58 }; $repos += $r58
    $c58a = & "$S\Claim-Task.ps1" -Repo $r58 -Role build -Session build-58 | ConvertFrom-Json
    if ($c58a.id -ne 'G1.L') { throw "expected to claim G1.L, got $($c58a.id)" }
    . "$S\lib\Streams.ps1"
    $P58 = Get-StreamPaths $r58
    $hold58 = [IO.File]::Open($P58.Lock, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
    $env:STREAM_BEAT_SECONDS = '1'
    $err58 = ''; $c58 = $null
    try { & "$S\Invoke-Grader.ps1" -Repo $r58 -Task G1.L -Root $r58 -Label beat58 -BeatSession build-58 -BeatTask G1.L 3>$null | Out-Null; $c58 = $LASTEXITCODE }
    catch { $err58 = ("$_" -split "`n")[0].Trim() }
    finally { Remove-Item Env:\STREAM_BEAT_SECONDS -ErrorAction SilentlyContinue; $hold58.Dispose(); Remove-Item $P58.Lock -Force -ErrorAction SilentlyContinue }
    $child58 = if (Test-Path $pid58) { Get-Process -Id ([int](Get-Content $pid58)) -ErrorAction SilentlyContinue } else { $null }
    $log58 = Join-Path $r58 '.streams\logs\G1.L.grader.beat58.txt'
    Case 'busy lock: a failed beat does not end the grader run' (-not $err58 -and $c58 -eq 0) "threw '$err58' exit $c58"
    Case 'busy lock: the run still logs the verdict and leaves no .part file' ((Test-Path $log58) -and @((Get-Content $log58) -match 'PASS C1').Count -gt 0 -and -not (Test-Path "$log58.part")) "log=$(Test-Path $log58) part=$(Test-Path "$log58.part")"
    $cpid58 = if ($child58) { $child58.Id } else { '-' }
    Case 'busy lock: no child grader is left running' (-not $child58) "child pid $cpid58 still alive"
    if ($child58) { Stop-Process -Id $cpid58 -Force -ErrorAction SilentlyContinue; Start-Sleep -Milliseconds 500 }

    # ---- 59. a staging folder copied a moment ago is not swept for its files' old write times (kit item
    # IN-20261003174116-0300). Copy-Item keeps the source write times, so on 2026-10-03 the watchdog's scratch sweep took
    # a coordinator's kit-a58c-base mid-copy: every file it held was older than StreamScratchKeepHours. Fixture: a
    # folder made now holding a subfolder and files dated 30 h back; and one that is old all through, which still goes.
    $r59 = New-Repo 'r59' @{ 'G1.W' = (ContentGrader 'G1.W' 'ok') }; $repos += $r59
    $scr59 = Join-Path $env:STREAM_SCRATCH_ROOT (Split-Path -Leaf $r59)
    $old59 = (Get-Date).ToUniversalTime().AddHours(-30)
    $copy59 = Join-Path $scr59 'kit-x-stage'; $gone59 = Join-Path $scr59 'kit-y-stage'
    foreach ($d59 in $copy59, $gone59) {
        New-Item -ItemType Directory -Path (Join-Path $d59 'scripts') -Force | Out-Null
        Set-Content (Join-Path $d59 'scripts\a.ps1') 'a'; Set-Content (Join-Path $d59 'b.txt') 'b'
        Get-ChildItem $d59 -Recurse -File | ForEach-Object { $_.LastWriteTimeUtc = $old59 }
    }
    foreach ($o59 in @(Get-Item $gone59) + @(Get-ChildItem $gone59 -Recurse -Directory)) { $o59.CreationTimeUtc = $old59; $o59.LastWriteTimeUtc = $old59 }
    $w59 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r59 -Session status-59)
    Case 'scratch sweep: a folder copied just now with old files is kept' (Test-Path (Join-Path $copy59 'scripts\a.ps1')) ($w59 -join ' | ')
    Case 'scratch sweep: a folder old all through still goes' (-not (Test-Path $gone59)) ($w59 -join ' | ')

    # ---- 60. a built row with neither a builder's check nor an author's grader is bounced BEFORE the apply (kit item
    # IN-20261003183249-a488). On 2026-10-03 Invoke-Grader answered NO-GRADER (exit 4) and wrote no main log, the red
    # branch threw reading that log, and G3.T268's patch stayed applied, uncommitted, on main.
    $r60 = New-Repo 'r60' @{ 'G1.N' = (ContentGrader 'G1.N' 'done') }; $repos += $r60
    [void](Build $r60 'G1.N' 'N done' 'build-60')
    $j60 = J $r60; foreach ($x60 in $j60.tasks) { if ($x60.id -eq 'G1.N') { $x60.artifacts.grader = $null } }
    Set-Content -LiteralPath (Join-Path $r60 '.streams\tasks.json') -Encoding utf8 -Value ($j60 | ConvertTo-Json -Depth 50)
    $err60 = ''; $o60 = @()
    try { $o60 = @(& "$S\Integrate-Patch.ps1" -Repo $r60 -Session integ-60) } catch { $err60 = ("$_" -split "`n")[0].Trim() }
    $t60 = T $r60 'G1.N'
    Case 'no check, no grader: integrate does not throw' (-not $err60) "threw '$err60'"
    Case 'no check, no grader: main never holds the patch' ((Get-Content -Raw (Join-Path $r60 'G1.N.txt')) -match 'G1.N base') (Get-Content -Raw (Join-Path $r60 'G1.N.txt'))
    Case 'no check, no grader: BOUNCED to ticketed with the patch kept' ((($o60 -join ' ') -match '^BOUNCED G1.N') -and $t60.state -eq 'ticketed' -and $t60.artifacts.patch) "$($o60 -join ' | ') state=$($t60.state)"

    # ---- 61. a throw in any step after the apply reverses the patch and leaves the row built (kit item
    # IN-20261003193026-6efe). On 2026-10-03 G3.T294's grader passed on main, then the -To integrated write threw
    # 'tasks.json lock busy for 15s' (the coordinator held it), the throw ended the drain, and the patch stayed applied
    # with the row still built. Fixture: a fresh tasks.json.lock that another session holds for the whole run, and a
    # 2-second wait (STREAM_TASKS_LOCK_WAIT_SECONDS) so the case is quick.
    $r61 = New-Repo 'r61' @{ 'G1.L' = (ContentGrader 'G1.L' 'done') }; $repos += $r61
    [void](Build $r61 'G1.L' 'L done' 'build-61')
    $lock61 = Join-Path $r61 '.streams\tasks.json.lock'
    Set-Content -LiteralPath $lock61 -Value '{"session":"coord-61","at":"now"}'
    $env:STREAM_TASKS_LOCK_WAIT_SECONDS = '2'
    $head61 = git -C $r61 rev-parse HEAD
    $err61 = ''; $o61 = @()
    try { $o61 = @(& "$S\Integrate-Patch.ps1" -Repo $r61 -Session integ-61) } catch { $err61 = ("$_" -split "`n")[0].Trim() }
    Remove-Item Env:\STREAM_TASKS_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $lock61 -Force -ErrorAction SilentlyContinue
    $t61 = T $r61 'G1.L'
    Case 'post-apply throw: integrate does not throw' (-not $err61) "threw '$err61'"
    Case 'post-apply throw: the patch is reversed on main' ((Get-Content -Raw (Join-Path $r61 'G1.L.txt')) -match 'G1.L base') (Get-Content -Raw (Join-Path $r61 'G1.L.txt'))
    Case 'post-apply throw: RETRY, row stays built, nothing committed' ((($o61 -join ' ') -match 'RETRY G1.L') -and $t61.state -eq 'built' -and (git -C $r61 rev-parse HEAD) -eq $head61) "$($o61 -join ' | ') state=$($t61.state)"
    Case 'post-apply throw: decisions.md names the error' ((Get-Content -Raw (Join-Path $r61 '.streams\decisions.md')) -match 'G1\.L.*lock busy') ''

    # ---- 62. a suite snapshot carries the ignored inputs its legs and graders read (kit item IN-20261003220611-eaac).
    # G2 suites run 5's snapshot had no tests\Tests.E2E\.auth (an ignored folder) and no .streams, so the compose web
    # exited 139 and every grader that reads .streams failed; '-CopyIgnored .env,.env.local' as one string was refused.
    $r62 = New-Repo 'r62' @{ 'G1.S' = (ContentGrader 'G1.S' 'base') }; $repos += $r62
    Set-Content (Join-Path $r62 '.gitignore') "*.env`n.env.local`n.auth/"
    Set-Content (Join-Path $r62 'a.env') 'A=1'; Set-Content (Join-Path $r62 '.env.local') 'L=1'
    New-Item -ItemType Directory -Path (Join-Path $r62 'e2e\.auth') -Force | Out-Null
    Set-Content (Join-Path $r62 'e2e\.auth\dev.pfx') 'pfx'
    New-Item -ItemType Directory -Path (Join-Path $r62 '.streams\mockups\g1') -Force | Out-Null
    Set-Content (Join-Path $r62 '.streams\mockups\g1\m.md') 'mock'
    $o62 = @(); $x62 = -1
    try { $o62 = @(& "$S\New-SuiteSnapshot.ps1" -Repo $r62 -Session integ-62 -Group G1 -Run 1 -CopyIgnored 'a.env,.env.local', 'e2e\.auth' 2>&1); $x62 = $LASTEXITCODE } catch { $o62 = @("threw $_") }
    $s62 = [string]$o62[-1]
    $ok62 = $x62 -eq 0 -and (Test-Path -LiteralPath $s62 -PathType Container)
    Case 'snapshot: a comma-separated -CopyIgnored string and an ignored folder are copied' ($ok62 -and (Test-Path (Join-Path $s62 'a.env')) -and (Test-Path (Join-Path $s62 '.env.local')) -and (Test-Path (Join-Path $s62 'e2e\.auth\dev.pfx'))) "exit $x62 : $($o62 -join ' | ')"
    Case 'snapshot: the grader-read .streams folders and tasks.json are copied' ($ok62 -and (Test-Path (Join-Path $s62 '.streams\tasks.json')) -and (Test-Path (Join-Path $s62 '.streams\graders\G1.S.ps1')) -and (Test-Path (Join-Path $s62 '.streams\mockups\g1\m.md'))) "exit $x62 : $($o62 -join ' | ')"
    Case 'snapshot: the copied .streams and ignored inputs are never staged' ($ok62 -and -not @(git -C $s62 diff --cached --name-only | Where-Object { $_ -match '^\.streams/|\.auth/|\.env' }).Count) (@(git -C $s62 diff --cached --name-only) -join ' | ')

    # ---- 66. a dependency integrated while a worktree is made is already in the base and is not applied twice (kit item
    # IN-20261003225331-626c). G3.T285 was applied to main while G3.T301's tree was made: the dirty diff held it, its row
    # still read built, and re-applying its patch threw "patch does not apply". Fixture: G1.B depends on built G1.A, and
    # G1.A's patch is already applied to the main tree (the integrator's apply before its row leaves built).
    $r66 = New-Repo 'r66' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r66
    [void](Build $r66 'G1.A' 'A done' 'build-66a')
    $doc66 = J $r66
    ($doc66.tasks | Where-Object { $_.id -eq 'G1.B' }).dependsOn = @('G1.A')
    Set-Content -Path (Join-Path $r66 '.streams\tasks.json') -Encoding utf8 -Value ($doc66 | ConvertTo-Json -Depth 50)
    git -C $r66 apply (Join-Path $r66 '.streams\patches\G1.A.patch')
    [void](& "$S\Claim-Task.ps1" -Repo $r66 -Role build -Session build-66b -Task G1.B)
    $root66 = Join-Path $Scratch 'wt66'
    $err66 = ''; $o66 = @()
    try { $o66 = @(& "$S\New-TaskWorktree.ps1" -Repo $r66 -Task G1.B -Session build-66b -WorktreeRoot $root66 2>&1) } catch { $err66 = ("$_" -split "`n")[0].Trim() }
    $wt66 = Join-Path $root66 'G1.B'
    Case 'integrated-while-made dependency: New-TaskWorktree does not throw' (-not $err66) "threw '$err66'"
    Case 'integrated-while-made dependency: the base holds its change once, with a SKIPPED note' ((-not $err66) -and ((Get-Content -Raw (Join-Path $wt66 'G1.A.txt')) -match '^A done\s*$') -and (($o66 -join ' ') -match 'SKIPPED dependency patch G1\.A\.patch')) "$($o66 -join ' | ')"
    Case 'integrated-while-made dependency: the base fingerprint is recorded' ((-not $err66) -and (T $r66 'G1.B').base.head) "base=$((T $r66 'G1.B').base | ConvertTo-Json -Compress)"

    # ---- 66e. an EMPTY untracked main-tree file where a built dependency's patch creates the file is dropped from the
    # new tree, and the patch applies (kit item IN-20261016122702-3601: a 0-byte untracked FamilyFactory.cs failed every
    # G7.T020 pre-stage on G7.T019.patch with "already exists in working directory"). A NON-empty untracked copy may be
    # work, so it still fails, and the main tree's own copy is never touched.
    $v66 = @{}
    foreach ($k in @('e', 'f')) {
        # G1.A's patch CREATES New66.cs (the fixture's G1.A.txt is tracked, so a plain Build only modifies a file).
        $rv = New-Repo "r66$k" ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $rv
        $dv = J $rv
        ($dv.tasks | Where-Object { $_.id -eq 'G1.A' }).writeSet = @('G1.A.txt', 'New66.cs')
        ($dv.tasks | Where-Object { $_.id -eq 'G1.B' }).dependsOn = @('G1.A')
        Set-Content -Path (Join-Path $rv '.streams\tasks.json') -Encoding utf8 -Value ($dv | ConvertTo-Json -Depth 50)
        [void](& "$S\Claim-Task.ps1" -Repo $rv -Role build -Session "build-66${k}a" -Task G1.A)
        $wa = & "$S\New-TaskWorktree.ps1" -Repo $rv -Task G1.A -Session "build-66${k}a" -WorktreeRoot (Join-Path $Scratch "wt66${k}a") | Select-Object -Last 1
        Set-Content (Join-Path $wa 'G1.A.txt') 'A done'; Set-Content (Join-Path $wa 'New66.cs') 'class New66 {}'
        & "$S\Export-TaskPatch.ps1" -Repo $rv -Task G1.A -Worktree $wa | Out-Null
        & "$S\Update-Task.ps1" -Repo $rv -Task G1.A -Role build -Session "build-66${k}a" -To built -Release -Artifacts @{ patch = '.streams\patches\G1.A.patch'; verdict = 'PASS' } | Out-Null
        # The main tree then gains an untracked New66.cs: empty (e) or holding work (f).
        [IO.File]::WriteAllText((Join-Path $rv 'New66.cs'), $(if ($k -eq 'e') { '' } else { 'owner work' }))
        [void](& "$S\Claim-Task.ps1" -Repo $rv -Role build -Session "build-66${k}b" -Task G1.B)
        $rootv = Join-Path $Scratch "wt66$k"
        $ev = ''; $ov = @()
        try { $ov = @(& "$S\New-TaskWorktree.ps1" -Repo $rv -Task G1.B -Session "build-66${k}b" -WorktreeRoot $rootv 2>&1) } catch { $ev = ("$_" -split "`n")[0].Trim() }
        $v66[$k] = @{ repo = $rv; wt = (Join-Path $rootv 'G1.B'); err = $ev; out = ($ov -join ' | ') }
    }
    $e66 = $v66['e']; $f66 = $v66['f']
    Case '66e an empty untracked main copy of a file a dependency patch creates is dropped: the tree is made and holds the patch content' ((-not $e66.err) -and (Test-Path (Join-Path $e66.wt 'New66.cs')) -and ((Get-Content -Raw (Join-Path $e66.wt 'New66.cs')) -match '^class New66 \{\}\s*$') -and ($e66.out -match 'DROPPED empty untracked main-tree copy of New66\.cs')) "err='$($e66.err)' out=$($e66.out)"
    Case '66e the main tree keeps its own empty copy' ((Test-Path (Join-Path $e66.repo 'New66.cs')) -and (Get-Item (Join-Path $e66.repo 'New66.cs')).Length -eq 0) "main copy exists=$(Test-Path (Join-Path $e66.repo 'New66.cs'))"
    Case '66f a NON-empty untracked main copy is never dropped: New-TaskWorktree still fails on it' (($f66.err -match 'already exists') -and ($f66.out -notmatch 'DROPPED')) "err='$($f66.err)' out=$($f66.out)"

    # ---- 66m. Two built dependencies that both APPEND to an id register (ORDERED-BY-MERGE, no edge between them) stack
    # into one base: the second patch is merged by its added lines, as Integrate-Patch merges it on main. G17.T100's
    # pre-stage stacked four G26 patches that all appended to docs/requirements/ids.yaml and died on the second one
    # (kit item IN-20261024234800-fab8). base.deps still records the dependency's own patch, not the merged copy.
    $r66m = New-Repo 'r66m' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok'); 'G1.C' = (ContentGrader 'G1.C' 'ok') }); $repos += $r66m
    New-Item -ItemType Directory -Force (Join-Path $r66m 'docs\requirements') | Out-Null
    [IO.File]::WriteAllText((Join-Path $r66m 'docs\requirements\ids.yaml'), "ids:`n- id: ONE`n- id: TWO`n- id: THREE`n")
    & git -C $r66m add -A 2>&1 | Out-Null; & git -C $r66m commit -q -m 'ids register' 2>&1 | Out-Null
    $d66m = J $r66m
    foreach ($tm in $d66m.tasks) {
        if ($tm.id -in 'G1.A', 'G1.B') { $tm.writeSet = @("$($tm.id).txt", 'docs/requirements/ids.yaml') }
        if ($tm.id -eq 'G1.C') { $tm.dependsOn = @('G1.A', 'G1.B') }
    }
    Set-Content -Path (Join-Path $r66m '.streams\tasks.json') -Encoding utf8 -Value ($d66m | ConvertTo-Json -Depth 50)
    foreach ($km in 'A', 'B') {
        [void](& "$S\Claim-Task.ps1" -Repo $r66m -Role build -Session "build-66m$km" -Task "G1.$km")
        $wm = & "$S\New-TaskWorktree.ps1" -Repo $r66m -Task "G1.$km" -Session "build-66m$km" -WorktreeRoot (Join-Path $Scratch "wt66m$km") | Select-Object -Last 1
        Set-Content (Join-Path $wm "G1.$km.txt") "$km done"
        [IO.File]::AppendAllText((Join-Path $wm 'docs\requirements\ids.yaml'), "- id: ADD-$km`n")
        & "$S\Export-TaskPatch.ps1" -Repo $r66m -Task "G1.$km" -Worktree $wm | Out-Null
        & "$S\Update-Task.ps1" -Repo $r66m -Task "G1.$km" -Role build -Session "build-66m$km" -To built -Release -Artifacts @{ patch = ".streams\patches\G1.$km.patch"; verdict = 'PASS' } | Out-Null
    }
    [void](& "$S\Claim-Task.ps1" -Repo $r66m -Role build -Session 'build-66mC' -Task G1.C)
    $e66m = ''; $o66m = @()
    try { $o66m = @(& "$S\New-TaskWorktree.ps1" -Repo $r66m -Task G1.C -Session 'build-66mC' -WorktreeRoot (Join-Path $Scratch 'wt66mC') 2>&1) } catch { $e66m = ("$_" -split "`n")[0].Trim() }
    $ids66m = if (Test-Path (Join-Path $Scratch 'wt66mC\G1.C\docs\requirements\ids.yaml')) { [IO.File]::ReadAllText((Join-Path $Scratch 'wt66mC\G1.C\docs\requirements\ids.yaml')) } else { '' }
    $deps66m = @((J $r66m).tasks | Where-Object { $_.id -eq 'G1.C' } | ForEach-Object { $_.base.deps })
    Case '66m two built deps appending to ids.yaml stack: the tree is made with both appends and a MERGED note' ((-not $e66m) -and ($ids66m -match 'ADD-A') -and ($ids66m -match 'ADD-B') -and (Test-Path (Join-Path $Scratch 'wt66mC\G1.C\G1.B.txt')) -and (($o66m -join ' ') -match 'MERGED dependency patch G1\.B\.patch')) "err='$e66m' ids='$ids66m' out=$($o66m -join ' | ')"
    Case '66m base.deps records both dependency patches by their own name' ((($deps66m -join ' ') -match '^G1\.A\.patch:\S+ G1\.B\.patch:\S+$')) "deps=$($deps66m -join ' ')"

    # ---- 66g. A BASE IS NEVER LAID WHILE ANOTHER HOLDER HAS THE MAIN TREE. On 2026-10-17 Builder 4's pre-stage listed
    # main's untracked files while the integrator had G9.T010's patch applied for its grader (kit item
    # IN-20261017025015-83de). New-TaskWorktree now reads main under main-grader.lock; a busy lock throws with the text a
    # runner reads as PRESTAGE-BUSY ('lock busy for <n>s'), and no tree is made.
    $r66g = New-Repo 'r66g' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r66g
    [void](& "$S\Claim-Task.ps1" -Repo $r66g -Role build -Session build-66g)
    $root66g = Join-Path $Scratch 'wt66g'
    $held66g = [IO.FileStream]::new((Join-Path $r66g '.streams\main-grader.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose)
    $b66g = [Text.Encoding]::UTF8.GetBytes('integrate G1.X apply pid 1 at test'); $held66g.Write($b66g, 0, $b66g.Length); $held66g.Flush()
    $prevWait66g = $env:STREAM_MAIN_LOCK_WAIT_SECONDS; $env:STREAM_MAIN_LOCK_WAIT_SECONDS = '1'
    $err66g = ''
    try { [void](& "$S\New-TaskWorktree.ps1" -Repo $r66g -Task G1.A -Session build-66g -WorktreeRoot $root66g 2>&1) } catch { $err66g = ("$_" -split "`n")[0].Trim() }
    finally {
        $held66g.Dispose()
        if ($null -eq $prevWait66g) { Remove-Item Env:\STREAM_MAIN_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue } else { $env:STREAM_MAIN_LOCK_WAIT_SECONDS = $prevWait66g }
    }
    Case '66g a held main-grader.lock stops the base: New-TaskWorktree throws the runner''s BUSY text and makes no tree' (($err66g -match 'lock busy for \d+s') -and -not (Test-Path (Join-Path $root66g 'G1.A'))) "err='$err66g' tree=$(Test-Path (Join-Path $root66g 'G1.A'))"

    # ---- 66h. AN UNTRACKED FILE THAT IS GONE BY COPY TIME IS SKIPPED, NOT FATAL. The listed file was removed between the
    # list and the copy ("Could not find file ...ExistingDataInspector.cs", same item). The hook seam deletes it in that
    # window; the tree is made without it, the output names it, and the main-tree lock is free afterwards.
    $r66h = New-Repo 'r66h' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r66h
    Set-Content (Join-Path $r66h 'vanish66.txt') 'listed, then removed before the copy'
    Set-Content (Join-Path $r66h 'stay66.txt') 'listed and still there'
    $hook66h = Join-Path $Scratch 'hook66h.ps1'
    Set-Content $hook66h "Remove-Item -LiteralPath '$(Join-Path $r66h 'vanish66.txt')' -Force"
    [void](& "$S\Claim-Task.ps1" -Repo $r66h -Role build -Session build-66h)
    $err66h = ''; $o66h = @()
    $env:STREAM_TEST_WORKTREE_HOOK = $hook66h
    try { $o66h = @(& "$S\New-TaskWorktree.ps1" -Repo $r66h -Task G1.A -Session build-66h -WorktreeRoot (Join-Path $Scratch 'wt66h') 2>&1) } catch { $err66h = ("$_" -split "`n")[0].Trim() }
    finally { Remove-Item Env:\STREAM_TEST_WORKTREE_HOOK -ErrorAction SilentlyContinue }
    $wt66h = Join-Path $Scratch 'wt66h\G1.A'
    Case '66h a vanished untracked file is skipped with a note and the tree is made' ((-not $err66h) -and (Test-Path (Join-Path $wt66h 'stay66.txt')) -and -not (Test-Path (Join-Path $wt66h 'vanish66.txt')) -and (($o66h -join ' ') -match 'SKIPPED untracked main-tree file\(s\) gone before the copy: vanish66\.txt')) "err='$err66h' out=$($o66h -join ' | ')"
    Case '66h the main-tree lock is released once the base is laid' ((-not $err66h) -and -not (Test-Path (Join-Path $r66h '.streams\main-grader.lock'))) "lock exists=$(Test-Path (Join-Path $r66h '.streams\main-grader.lock'))"

    # ---- 66j. A BASE IS LAID BESIDE AN INTEGRATOR GRADE, WITH THE GRADED PATCH REVERSED OUT. Integrate-Patch's grade of
    # G23.T074 held main-grader.lock 27 min and every builder pre-stage starved (kit item IN-20261024221200-772a). With
    # the holder '<task> main pid ..' and main-pending.json naming that task's patch, New-TaskWorktree reads main unlocked
    # and reverses the patch in its copy, so the tree is main as it was before the apply.
    $r66j = New-Repo 'r66j' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r66j
    Set-Content (Join-Path $r66j 'pend66.txt') 'before'
    & git -C $r66j add pend66.txt; & git -C $r66j commit -q -m pend66 | Out-Null
    Set-Content (Join-Path $r66j 'pend66.txt') 'graded patch'
    Set-Content (Join-Path $r66j 'new66j.txt') 'created by the graded patch'
    & git -C $r66j add -N new66j.txt
    $p66j = Join-Path $Scratch 'pend66j.patch'
    & git -C $r66j diff --binary "--output=$p66j"
    & git -C $r66j reset -q -- new66j.txt
    Set-Content (Join-Path $r66j '.streams\main-pending.json') (@{ task = 'G1.X'; patch = $p66j; at = '2026-10-24T00:00:00Z' } | ConvertTo-Json)
    [void](& "$S\Claim-Task.ps1" -Repo $r66j -Role build -Session build-66j)
    $held66j = [IO.FileStream]::new((Join-Path $r66j '.streams\main-grader.lock'), [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose)
    $b66j = [Text.Encoding]::UTF8.GetBytes('G1.X main pid 1 at 2026-10-24T00:00:00Z'); $held66j.Write($b66j, 0, $b66j.Length); $held66j.Flush()
    $prevWait66j = $env:STREAM_MAIN_LOCK_WAIT_SECONDS; $env:STREAM_MAIN_LOCK_WAIT_SECONDS = '1'
    $err66j = ''; $o66j = @()
    try { $o66j = @(& "$S\New-TaskWorktree.ps1" -Repo $r66j -Task G1.A -Session build-66j -WorktreeRoot (Join-Path $Scratch 'wt66j') 2>&1) } catch { $err66j = ("$_" -split "`n")[0].Trim() }
    finally {
        $held66j.Dispose()
        if ($null -eq $prevWait66j) { Remove-Item Env:\STREAM_MAIN_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue } else { $env:STREAM_MAIN_LOCK_WAIT_SECONDS = $prevWait66j }
    }
    $wt66j = Join-Path $Scratch 'wt66j\G1.A'
    Case '66j a grade-only holder does not stop the base: the tree is made beside it with the graded patch reversed out' ((-not $err66j) -and ((Get-Content -Raw (Join-Path $wt66j 'pend66.txt')) -match '^before\s*$') -and -not (Test-Path (Join-Path $wt66j 'new66j.txt')) -and (($o66j -join ' ') -match 'BASE read beside the main grade of G1\.X')) "err='$err66j' out=$($o66j -join ' | ')"
    Case '66j the main tree keeps the graded patch' (((Get-Content -Raw (Join-Path $r66j 'pend66.txt')) -match 'graded patch') -and (Test-Path (Join-Path $r66j 'new66j.txt'))) "main pend66=$(Get-Content -Raw (Join-Path $r66j 'pend66.txt'))"
    # ---- 66i. A BUILT DEPENDENCY WHOSE OWN DEPENDENCY IS NO LONGER BUILT IS NOT A BASE. A is building again (bounced),
    # B is built on A's old patch, C depends on B. C's base would stack B.patch without A's, so C is not claimable;
    # once A is integrated it is (kit item IN-20261017100037-aa62, G9.T026 over G9.T011 over G9.T010).
    $r66i = New-Repo 'r66i' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok'); 'G1.C' = (ContentGrader 'G1.C' 'ok') }); $repos += $r66i
    $set66i = {
        param([string] $aState)
        $d = J $r66i
        foreach ($t in $d.tasks) {
            if ($t.id -eq 'G1.A') { $t.state = $aState }
            if ($t.id -eq 'G1.B') { $t.state = 'built'; $t.dependsOn = @('G1.A') }
            if ($t.id -eq 'G1.C') { $t.state = 'ticketed'; $t.dependsOn = @('G1.B') }
        }
        Set-Content -LiteralPath (Join-Path $r66i '.streams\tasks.json') -Encoding utf8 -Value ($d | ConvertTo-Json -Depth 50)
    }
    & $set66i 'building'
    $c66i = (@(& "$S\Claim-Task.ps1" -Repo $r66i -Role build -Session build-66i 2>&1) -join ' ')
    $k66i = (@(& "$S\Claim-Task.ps1" -Repo $r66i -Role build -Session build-66i -Task G1.C 2>&1) -join ' ')
    Case '66i a row over a built dependency whose own dependency went back to building is not claimable' (($c66i -match 'NONE') -and ($c66i -notmatch '"G1\.C"') -and ($k66i -match 'REFUSED-TASK G1\.C : a built dependency sits on a dependency that is no longer built')) "claim=$($c66i.Substring(0, [Math]::Min(200, $c66i.Length))) task=$($k66i.Substring(0, [Math]::Min(200, $k66i.Length)))"
    & $set66i 'integrated'
    $c66i2 = (@(& "$S\Claim-Task.ps1" -Repo $r66i -Role build -Session build-66i 2>&1) -join ' ')
    Case '66i once that dependency is integrated the row is claimable again' ($c66i2 -match '"G1\.C"') "claim=$($c66i2.Substring(0, [Math]::Min(200, $c66i2.Length)))"



    # ---- Start-StreamRunner: fresh session per unit of work (owner ruling 2026-10-04) ----
    # The gate must launch a work role only when the kit's own rules give it something to take, and every launch must
    # carry the headless rules (one cycle, no ScheduleWakeup, detach long runs) and a session id of the role's shape.
    $r67 = New-Repo 'runner67' ([ordered]@{ 'G1.R' = (ContentGrader 'G1.R' 'done') }); $repos += $r67
    $b67 = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role build -DryRun)
    Case 'runner: a claimable ticketed row gates a build launch' ((($b67 -join "`n") -match '(?m)^GATE claimable 1 \(G1\.R\)') -and (($b67 -join "`n") -match '(?m)^RUN /stream-build once repo: ')) "$($b67 -join ' | ')"
    Case 'runner: a build launch gets a fresh build-<yyyyMMddHHmm>-<hex4> session' (($b67 -join "`n") -match '(?m)^SESSION build-\d{12}-[0-9a-f]{4}$') "$($b67 -join ' | ')"
    Case 'runner: the headless rules forbid ScheduleWakeup and require detached long runs' ((($b67 -join "`n") -match 'Never call ScheduleWakeup') -and (($b67 -join "`n") -match 'DETACHED: Start-Process pwsh')) "$($b67 -join ' | ')"
    # The host is shared: on 2026-10-09 two builders asked for `pkill -f Invoke-Grader.ps1` and `pkill -f python`, which
    # would have killed every other unit's graders and suites (kit item IN-20261009021255-91b2). Every unit is told to
    # stop only what it started, by PID; the stream-unit mod refuses a kill by name in a -Live unit (its own tests).
    Case 'runner: the rules allow stopping a process only by the PID the unit recorded, never by name' ((($b67 -join "`n") -match 'Stop ONLY processes this unit started, by the PID it recorded') -and (($b67 -join "`n") -match 'NEVER by name or command-line pattern \(pkill')) "$($b67 -join ' | ')"
    $a67 = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role author -DryRun)
    Case 'runner: no planned row and no inbox item leaves an author IDLE' (($a67 -join "`n") -match '(?m)^IDLE nothing to take for author') "$($a67 -join ' | ')"
    [void](& "$S\Claim-Task.ps1" -Repo $r67 -Role build -Session build-67)
    $b67b = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role build -DryRun)
    Case 'runner: a live claim on the only row leaves a builder IDLE' (($b67b -join "`n") -match '(?m)^IDLE nothing to take for build') "$($b67b -join ' | ')"
    # IDLE REPORT (owner request 2026-10-17): an idle runner says what it is offered, why nothing is claimable, what its
    # last unit did and when it looks again, instead of one cryptic line.
    # LOCAL-TIME (owner ruling 2026-10-18): the report's clock times carry the local zone, as the status pages do.
    Case 'runner idle report: the author names the focus and released groups, says no planned row exists, and when it looks again (LOCAL-TIME: with the zone)' ((($a67 -join "`n") -match '(?m)^  priorities : focus G1 \(.*\); released groups: G1') -and (($a67 -join "`n") -match '(?m)^  why idle   : no planned row anywhere on the board') -and (($a67 -join "`n") -match '(?m)^  last unit  : none yet from this runner') -and (($a67 -join "`n") -match '(?m)^  next look  : on any tasks.json or stream-author inbox write \(checked every 5 s\), else at \d\d:\d\d:\d\d [A-Za-z]+ \(300 s\)') -and (($a67 -join "`n") -match '(?m)^  this runner: no unit yet since \d\d:\d\d:\d\d [A-Za-z]+$')) "$($a67 -join ' | ')"
    # A build claim moves the row to 'building': the report says no ticketed row is left AND names the row a live builder is on.
    Case 'runner idle report: the builder says no ticketed row is left and names the row a live builder is building' ((($b67b -join "`n") -match '(?m)^  why idle   : no ticketed build row anywhere on the board: waiting for an author to ticket one') -and (($b67b -join "`n") -match '(?m)^             : 1 row\(s\) being built now by live builders \(G1\.R\)')) "$($b67b -join ' | ')"
    [void](& "$S\Send-InboxItem.ps1" -Repo $r67 -To stream-build -From test-67 -Kind request -Ask 'retry G1.R' -Task G1.R)
    $b67c = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role build -DryRun)
    Case 'runner: an open inbox item gates a build launch even with nothing claimable' (($b67c -join "`n") -match '(?m)^GATE inbox 1 actionable') "$($b67c -join ' | ')"
    # TIMED GATES (owner ruling 2026-10-17, token review): integrate launches only for an actionable item, a built focus
    # row, an integrating group or its own live lock; plan and kit only for an item; status is a script tick with a unit
    # only for an item; the coordinator for items nobody live owns, changed flags, low RAM, its first or periodic review.
    $i67 = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role integrate -DryRun)
    Case 'runner: an integrate runner with no built row, no integrating group and no item is IDLE with the report, and keeps an integ- session' ((($i67 -join "`n") -match '(?m)^IDLE nothing to take for integrate') -and (($i67 -join "`n") -match '(?m)^  why idle   : stream-integrate inbox: no open item') -and (($i67 -join "`n") -match '(?m)^             : no built row in the focus set') -and (($i67 -join "`n") -match '(?m)^             : no group integrating') -and (($i67 -join "`n") -notmatch '(?m)^RUN ') -and (($i67 -join "`n") -match '(?m)^CONFIG ') -and (($i67 -join "`n") -match '(?m)^SESSION integ-\d{12}-[0-9a-f]{4}$')) "$($i67 -join ' | ')"
    $doc67 = J $r67
    foreach ($t in $doc67.tasks) { if ($t.id -eq 'G1.R') { $t.state = 'built'; $t.claim = $null } }
    Set-Content -LiteralPath (Join-Path $r67 '.streams\tasks.json') -Encoding utf8 -Value ($doc67 | ConvertTo-Json -Depth 50)
    $i67b = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role integrate -DryRun)
    Case 'runner: a built focus row gates an integrate launch' ((($i67b -join "`n") -match '(?m)^GATE built 1 \(G1\.R\) focus G1') -and (($i67b -join "`n") -match '(?m)^RUN /stream-integrate once repo: ')) "$($i67b -join ' | ')"
    foreach ($t in $doc67.tasks) { if ($t.id -eq 'G1.R') { $t.state = 'integrated' } }
    foreach ($g in $doc67.groups) { if ($g.id -eq 'G1') { $g.state = 'integrating' } }
    Set-Content -LiteralPath (Join-Path $r67 '.streams\tasks.json') -Encoding utf8 -Value ($doc67 | ConvertTo-Json -Depth 50)
    $i67c = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role integrate -DryRun)
    Case 'runner: an integrating group gates an integrate launch (suites, fix tasks, close)' (($i67c -join "`n") -match '(?m)^GATE group G1 integrating') "$($i67c -join ' | ')"
    foreach ($g in $doc67.groups) { if ($g.id -eq 'G1') { $g.state = 'released' } }
    Set-Content -LiteralPath (Join-Path $r67 '.streams\tasks.json') -Encoding utf8 -Value ($doc67 | ConvertTo-Json -Depth 50)
    $k67 = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role kit -DryRun)
    Case 'runner: a kit runner with an empty inbox is IDLE and says so' ((($k67 -join "`n") -match '(?m)^IDLE nothing to take for kit') -and (($k67 -join "`n") -match '(?m)^  why idle   : stream-kit inbox: no open item') -and (($k67 -join "`n") -match '(?m)^  next look  : on any stream-kit inbox write \(checked every 5 s\), else at \d\d:\d\d:\d\d [A-Za-z]+ \(600 s\)') -and (($k67 -join "`n") -notmatch '(?m)^RUN ')) "$($k67 -join ' | ')"
    $kSent67 = "$(& "$S\Send-InboxItem.ps1" -Repo $r67 -To stream-kit -From test-67 -Kind bug -Ask 'Claim-Task prints a warning twice')"
    $kId67 = ($kSent67 -split ' ')[1]
    $k67b = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role kit -DryRun)
    Case 'runner: an open kit item gates a kit launch' ((($k67b -join "`n") -match '(?m)^GATE inbox 1 actionable \(IN-') -and (($k67b -join "`n") -match '(?m)^RUN /stream-kit inbox repo: ')) "$($k67b -join ' | ')"
    $s67 = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role status -DryRun)
    Case 'runner: the status role is a script tick, and with no open item launches no unit' ((($s67 -join "`n") -match '(?m)^TICK every 900 s, scripts only \(no model call\): Invoke-Watchdog, Get-StreamStatus, Build-StatusPage') -and (($s67 -join "`n") -match '(?m)^IDLE no open stream-status inbox item: no unit') -and (($s67 -join "`n") -notmatch '(?m)^RUN ')) "$($s67 -join ' | ')"
    [void](& "$S\Send-InboxItem.ps1" -Repo $r67 -To stream-status -From test-67 -Kind request -Ask 'keep the claim on G1.R' -Task G1.R)
    $s67b = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role status -DryRun)
    Case 'runner: an open status item gates a status unit that works the inbox only' ((($s67b -join "`n") -match '(?m)^GATE inbox 1 actionable \(IN-') -and (($s67b -join "`n") -match '(?m)^RUN /stream-status inbox repo: ')) "$($s67b -join ' | ')"
    # The coordinator has no inbox of its own: it works the kit inbox and stands in for plan. The kit item filed above
    # is still open and no kit runner is live, so the coordinator stands in for kit; once it is closed, the first review.
    $env:STREAM_RUNNER_FREE_RAM_GB = '32'
    $c67a = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role coordinator -DryRun)
    Case 'runner: a coordinator runner stands in for kit when a kit item is open and no kit runner is live' ((($c67a -join "`n") -match '(?m)^GATE stands in for kit : 1 open stream-kit item\(s\) and no live kit session') -and (($c67a -join "`n") -match '(?m)^RUN /stream-coordinator once repo: ')) "$($c67a -join ' | ')"
    [void](& "$S\Set-InboxItem.ps1" -Repo $r67 -Skill stream-kit -Id $kId67 -By test-67 -Status taken -Note 'test')
    [void](& "$S\Set-InboxItem.ps1" -Repo $r67 -Skill stream-kit -Id $kId67 -By test-67 -Status declined -Note 'test: closed so the coordinator gate moves on')
    $c67 = @(& "$S\Start-StreamRunner.ps1" -Repo $r67 -Role coordinator -DryRun)
    Remove-Item Env:\STREAM_RUNNER_FREE_RAM_GB -ErrorAction SilentlyContinue
    Case 'runner: a coordinator runner takes its first review when it starts' ((($c67 -join "`n") -match '(?m)^GATE first review since the runner started') -and (($c67 -join "`n") -match '(?m)^RUN /stream-coordinator once repo: ')) "$($c67 -join ' | ')"
    # ---- Start-StreamRunner: one planner per repo (kit item IN-20261004133725-ad1f) ----
    # A plan runner must not launch beside a live plan* session. A fresh taken stream-plan hold by another planner
    # makes it IDLE. With no other planner it runs.
    $r68 = New-Repo 'runner68' ([ordered]@{ 'G1.P' = (ContentGrader 'G1.P' 'done') }); $repos += $r68
    $p68h = @(& "$S\Start-StreamRunner.ps1" -Repo $r68 -Role plan -DryRun)
    Case 'runner: fresh plan history (the fixture planner plan-1) keeps a plan runner IDLE' (($p68h -join "`n") -match '(?m)^IDLE live planner plan-1$') "$($p68h -join ' | ')"
    $doc68 = J $r68; $old68 = (Get-Date).ToUniversalTime().AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ssZ')
    foreach ($t68 in $doc68.tasks) { foreach ($h68 in @($t68.history)) { $h68.at = $old68 } }
    Set-Content -Path (Join-Path $r68 '.streams\tasks.json') -Encoding utf8 -Value ($doc68 | ConvertTo-Json -Depth 50)
    $p68a = @(& "$S\Start-StreamRunner.ps1" -Repo $r68 -Role plan -DryRun)
    Case 'runner: with no other planner and no open item a plan runner is IDLE (its gate, not the planner guard)' ((($p68a -join "`n") -match '(?m)^IDLE nothing to take for plan') -and (($p68a -join "`n") -match '(?m)^  why idle   : stream-plan inbox: no open item') -and (($p68a -join "`n") -notmatch 'IDLE live planner')) "$($p68a -join ' | ')"
    $sent68 = @(& "$S\Send-InboxItem.ps1" -Repo $r68 -To stream-plan -From author-68 -Kind request -Ask 'widen G1.P' -Task G1.P) -join ' '
    $id68 = if ($sent68 -match 'SENT (\S+)') { $Matches[1] } else { '' }
    $p68s = @(& "$S\Start-StreamRunner.ps1" -Repo $r68 -Role plan -DryRun)
    Case 'runner: with no other planner an open stream-plan item gates a plan launch' ((($p68s -join "`n") -match "(?m)^GATE inbox 1 actionable \($id68\)") -and (($p68s -join "`n") -match '(?m)^RUN /stream-plan inbox repo: ')) "$($p68s -join ' | ')"
    [void](& "$S\Set-InboxItem.ps1" -Repo $r68 -Skill stream-plan -Id $id68 -Status taken -By plan-x68)
    $p68b = @(& "$S\Start-StreamRunner.ps1" -Repo $r68 -Role plan -DryRun)
    Case 'runner: a fresh taken plan hold by another planner keeps a plan runner IDLE' (($p68b -join "`n") -match '(?m)^IDLE live planner plan-x68$') "$($p68b -join ' | ')"
    $b68 = @(& "$S\Start-StreamRunner.ps1" -Repo $r68 -Role integrate -DryRun)
    Case 'runner: the planner guard does not touch other roles' ((($b68 -join "`n") -match '(?m)^IDLE nothing to take for integrate') -and (($b68 -join "`n") -notmatch 'IDLE live planner')) "$($b68 -join ' | ')"
    # ---- 69. an append to decisions.md waits out a short sharing violation (kit item IN-20261004140930-2c5d). On
    # 2026-10-04 Integrate-Patch's decisions.md append threw "being used by another process" right after a clean apply of
    # G3.T283, and the self-reverse cost a whole apply and grader cycle. Fixture: another process holds the file with
    # FileShare.None for 1.5 s while Add-LineTo appends.
    . "$S\lib\Streams.ps1"
    $f69 = Join-Path $Scratch 'lock69\decisions.md'
    New-Item -ItemType Directory -Force (Split-Path $f69) | Out-Null
    Set-Content -LiteralPath $f69 -Value '- first'
    $ready69 = "$f69.ready"
    $hold69 = "`$fs = [IO.File]::Open('$f69', 'Open', 'ReadWrite', 'None'); Set-Content -LiteralPath '$ready69' -Value x; Start-Sleep -Milliseconds 1500; `$fs.Dispose()"
    $proc69 = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $hold69
    $w69 = 0; while (-not (Test-Path $ready69) -and $w69 -lt 200) { Start-Sleep -Milliseconds 100; $w69++ }
    $err69 = ''; try { Add-LineTo $f69 '- appended under lock' } catch { $err69 = ("$_" -split "`n")[0] }
    [void]$proc69.WaitForExit(15000)
    Case 'append: a line written while another process holds decisions.md waits for it and lands' ((Test-Path $ready69) -and -not $err69 -and ((Get-Content -Raw $f69) -match '- appended under lock')) "ready=$(Test-Path $ready69) err='$err69'"
    # ---- 70. a grader's .part and .err copy waits out a short sharing violation (kit item IN-20261004143050-5968). On
    # 2026-10-04 case 14 failed once with "...G1.V.grader.beat.txt.part ... being used by another process": the copy ran
    # while the child's redirect handle was still closing. (a) Invoke-IoRetry outlasts a 1.5 s FileShare.None hold by
    # another process; (b) a -BeatSession grader's stderr still lands in its log, and no .part or .err is left behind.
    . "$S\lib\Streams.ps1"
    $f70 = Join-Path $Scratch 'lock70\G1.X.grader.t.txt.part'
    New-Item -ItemType Directory -Force (Split-Path $f70) | Out-Null
    Set-Content -LiteralPath $f70 -Value 'PASS C1'
    $ready70 = "$f70.ready"
    $hold70 = "`$fs = [IO.File]::Open('$f70', 'Open', 'ReadWrite', 'None'); Set-Content -LiteralPath '$ready70' -Value x; Start-Sleep -Milliseconds 1500; `$fs.Dispose()"
    $proc70 = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', $hold70
    $w70 = 0; while (-not (Test-Path $ready70) -and $w70 -lt 200) { Start-Sleep -Milliseconds 100; $w70++ }
    $err70 = ''; $got70 = ''
    try { $got70 = Invoke-IoRetry { [IO.File]::ReadAllText($f70) } } catch { $err70 = ("$_" -split "`n")[0] }
    [void]$proc70.WaitForExit(15000)
    Case 'io retry: a .part read while another process holds the file waits for it and returns its text' ((Test-Path $ready70) -and -not $err70 -and $got70 -match 'PASS C1') "ready=$(Test-Path $ready70) err='$err70'"
    $r70 = New-Repo 'r70' @{ 'G1.E' = "param([string]`$Root)`n'PASS C1'`n[Console]::Error.WriteLine('ERRLINE-70')`nexit 0" }; $repos += $r70
    $env:STREAM_BEAT_SECONDS = '1'
    $gErr70 = ''
    try { & "$S\Invoke-Grader.ps1" -Repo $r70 -Task G1.E -Root $r70 -Label err70 -BeatSession integ-70 | Out-Null } catch { $gErr70 = ("$_" -split "`n")[0].Trim() }
    Remove-Item Env:\STREAM_BEAT_SECONDS -ErrorAction SilentlyContinue
    $log70 = Join-Path $r70 '.streams\logs\G1.E.grader.err70.txt'
    $text70 = if (Test-Path $log70) { Get-Content -Raw $log70 } else { '' }
    Case 'beat grader: stdout and stderr both land in the log, and no .part or .err is left' ((-not $gErr70) -and $text70 -match 'PASS C1' -and $text70 -match 'ERRLINE-70' -and -not (Get-ChildItem -Path "$log70.*" -ErrorAction SilentlyContinue)) "err='$gErr70' log='$($text70 -replace '\s+', ' ')'"
    # ---- STATUS TICK (owner ruling 2026-10-17): one status tick runs the watchdog, the terminal lines, the status, cost
    # and priority pages, the daily archive and the focus group's activation as scripts and prints ONE heartbeat line;
    # no Claude unit is launched when the stream-status inbox is empty. -MaxRuns 1 stops after one tick.
    $rST = New-Repo 'runnerST' ([ordered]@{ 'G1.S' = (ContentGrader 'G1.S' 'done') }); $repos += $rST
    $markST = Join-Path $Scratch 'claude-st-called.txt'
    $clST = Join-Path $Scratch 'claude-st.ps1'
    Set-Content -LiteralPath $clST -Encoding utf8 -Value "Set-Content -LiteralPath '$markST' -Value 'called'; '{""type"":""result"",""result"":""UNIT-OUTCOME: idle""}'"
    Remove-Item -LiteralPath $markST -ErrorAction SilentlyContinue
    $savedST = $env:STREAM_RUNNER_CLAUDE; $env:STREAM_RUNNER_CLAUDE = $clST
    $oST = @(); $eST = ''
    try { $oST = @(& "$S\Start-StreamRunner.ps1" -Repo $rST -Role status -IntervalSeconds 1 -MaxRuns 1 2>&1 | ForEach-Object { "$_" }) } catch { $eST = ("$_" -split "`n")[0] }
    finally { if ($null -ne $savedST) { $env:STREAM_RUNNER_CLAUDE = $savedST } else { Remove-Item Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue } }
    $tickST = @($oST | Where-Object { $_ -match '^\S+ STATUS-TICK ' })
    Case 'status tick: one tick prints one STATUS-TICK heartbeat with the watchdog, inbox, page, cost, priority, archive and activation notes' ((-not $eST) -and $tickST.Count -eq 1 -and $tickST[0] -match '^\S+ STATUS-TICK status-\S+ \d+s \| Watchdog QUIET: no stale claim\. \| Own inbox: no open items\. \| page: .+ \| cost: .+ \| priority: .+ \| archive: .+ \| activation: G1 ') "err='$eST' lines=$($oST.Count) tick=$($tickST -join ' || ') out=$(($oST | Select-Object -Last 6) -join ' | ')"
    Case 'status tick: the status page is written, the archive day is recorded, the focus group is activated, and no unit was launched' ((Test-Path (Join-Path $rST '.streams\status.html')) -and (Test-Path (Join-Path $rST '.streams\runners\status-archive.day')) -and (Test-Path (Join-Path $rST '.streams\plans\G1.activation.json')) -and -not (Test-Path -LiteralPath $markST) -and (($oST -join "`n") -notmatch '(?m)^\S+ RUN ')) "page=$(Test-Path (Join-Path $rST '.streams\status.html')) day=$(Test-Path (Join-Path $rST '.streams\runners\status-archive.day')) act=$(Test-Path (Join-Path $rST '.streams\plans\G1.activation.json')) called=$(Test-Path -LiteralPath $markST)"
    $logST = Join-Path $rST '.streams\logs\status-tick.log'; $logTextST = if (Test-Path -LiteralPath $logST) { Get-Content -Raw -LiteralPath $logST } else { '' }
    Case 'status tick: the STATUS-TICK heartbeat is also appended to .streams\logs\status-tick.log (kit item IN-20261023131800-4894)' ($tickST.Count -eq 1 -and $logTextST.Contains($tickST[0])) "log=$(Test-Path -LiteralPath $logST) text=$($logTextST.Trim())"
    Case 'status tick: the runner header says the role is a script tick with a unit only for an inbox item' (($oST -join "`n") -match '(?m)^RUNNER runner-status-\S+ role status mode print every 1 s \(script tick; a unit only for an open inbox item\)') "$(($oST | Select-Object -First 2) -join ' | ')"
    # A tick whose watchdog loses the tasks.json lock race (a live holder past the wait) is BUSY: the heartbeat says so,
    # TICK-BUSY is printed, and no stream-kit bug is filed until it repeats (kit item IN-20261018192923-9972).
    $rSTB = New-Repo 'runnerSTB' ([ordered]@{ 'G1.S' = (ContentGrader 'G1.S' 'done') }); $repos += $rSTB
    $lockSTB = Join-Path $rSTB '.streams\tasks.json.lock'
    Set-Content -LiteralPath $lockSTB -Value '{"session":"build-live-holder","at":"now"}'
    $savedSTB = $env:STREAM_RUNNER_CLAUDE; $env:STREAM_RUNNER_CLAUDE = $clST; $env:STREAM_TASKS_LOCK_WAIT_SECONDS = '1'
    $oSTB = @(); $eSTB = ''
    try { $oSTB = @(& "$S\Start-StreamRunner.ps1" -Repo $rSTB -Role status -IntervalSeconds 1 -MaxRuns 1 2>&1 | ForEach-Object { "$_" }) } catch { $eSTB = ("$_" -split "`n")[0] }
    finally { if ($null -ne $savedSTB) { $env:STREAM_RUNNER_CLAUDE = $savedSTB } else { Remove-Item Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue }; Remove-Item Env:\STREAM_TASKS_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue; Remove-Item -LiteralPath $lockSTB -Force -ErrorAction SilentlyContinue }
    $kitSTB = Join-Path $rSTB '.streams\inbox\stream-kit.md'
    $kitTextSTB = if (Test-Path -LiteralPath $kitSTB) { Get-Content -Raw -LiteralPath $kitSTB } else { '' }
    $tickSTB = @($oSTB | Where-Object { $_ -match '^\S+ STATUS-TICK ' })
    Case 'status tick: a watchdog that loses the tasks.json lock race is BUSY on the heartbeat and TICK-BUSY, and files no kit bug' ((-not $eSTB) -and $tickSTB.Count -eq 1 -and $tickSTB[0] -match '\| Watchdog BUSY \(lock contention; the next tick retries\)\. \|' -and (($oSTB -join "`n") -match '(?m)^\S+ TICK-BUSY Invoke-Watchdog\.ps1 \(1 in a row\): .*lock busy') -and (($oSTB -join "`n") -notmatch 'TICK-FAILED Invoke-Watchdog') -and $kitTextSTB -notmatch 'status runner''s script tick') "err='$eSTB' tick=$($tickSTB -join ' || ') busy=$(@($oSTB | Where-Object { $_ -match 'TICK-(BUSY|FAILED)' }) -join ' || ') kit=$($kitTextSTB.Length)"
    $logSTB = Join-Path $rSTB '.streams\logs\status-tick.log'; $logTextSTB = if (Test-Path -LiteralPath $logSTB) { Get-Content -Raw -LiteralPath $logSTB } else { '' }
    Case 'status tick: a TICK-BUSY line is also appended to .streams\logs\status-tick.log' ($logTextSTB -match '(?m)^\S+ TICK-BUSY Invoke-Watchdog\.ps1 \(1 in a row\)') "text=$($logTextSTB.Trim())"

    # ---- 71. every runner session runs on the applied machine config (kit item IN-20261004143031-d21b), and the check
    # that applies it runs once per -LaunchCheckMinutes, not once per unit (ai's Install-AIMachine.ps1 -Launch took 111 s
    # per launch on SMVMTR1, 2026-10-04). (a) DryRun names the ai launcher's check; (b) two units run the ai launcher once,
    # as `ai.ps1 --version`, and start claude directly with the -p command and session; (c) claude's JSON result is read
    # as a clean run.
    $r71 = New-Repo 'runner71' ([ordered]@{ 'G1.L' = (ContentGrader 'G1.L' 'done') }); $repos += $r71
    # An open integrate item passes the gate (2026-10-17), so DryRun reaches its RUN line.
    [void](& "$S\Send-InboxItem.ps1" -Repo $r71 -To stream-integrate -From test-71 -Kind request -Ask 'drain the built rows now')
    $d71 = @(& "$S\Start-StreamRunner.ps1" -Repo $r71 -Role integrate -DryRun)
    Case 'runner: DryRun names the launch check through the ai launcher under ClaudeHome\bin' (($d71 -join "`n") -match '(?m)^CHECK the launch check runs .+\\bin\\ai\.ps1 --version every 60 min$' -and ($d71 -join "`n") -match '(?m)^RUN /stream-integrate once repo: ') "$($d71 -join ' | ')"
    $ai71 = Join-Path $Scratch 'ai-stub71.ps1'
    $aiLog71 = Join-Path $Scratch 'ai-stub71.calls.txt'
    $cl71 = Join-Path $Scratch 'claude-stub71.ps1'
    $args71 = Join-Path $Scratch 'claude-stub71.args.json'
    Set-Content -LiteralPath $ai71 -Value @("Add-Content -LiteralPath '$aiLog71' -Value (`$args -join ' ')", "'ai: applied revision STUB71'", 'exit 0')
    Set-Content -LiteralPath $cl71 -Value @(
        "`$args | ConvertTo-Json -Compress | Set-Content -LiteralPath '$args71'"
        "'{""type"":""result"",""result"":""stub71 ok"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0}'"
        'exit 0')
    $env:STREAM_RUNNER_AI = $ai71; $env:STREAM_RUNNER_CLAUDE = $cl71
    $o71 = @(); $e71 = ''
    # A runner without the claude override would start a REAL claude here, so the launch runs only when (a) shows support.
    if (($d71 -join "`n") -match '(?m)^CHECK ') {
        try { $o71 = @(& "$S\Start-StreamRunner.ps1" -Repo $r71 -Role integrate -IntervalSeconds 1 -MaxRuns 2) } catch { $e71 = ("$_" -split "`n")[0] }
    } else { $e71 = 'skipped: this runner has no launch check' }
    Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue
    $calls71 = @(if (Test-Path $aiLog71) { Get-Content $aiLog71 })
    $a71 = @(if (Test-Path $args71) { Get-Content -Raw $args71 | ConvertFrom-Json })
    $st71 = Get-ChildItem (Join-Path $r71 '.streams\runners') -Filter 'runner-integrate-*.json' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
    $s71 = if ($st71) { Get-Content -Raw $st71.FullName | ConvertFrom-Json } else { $null }
    Case 'runner: two units run the ai launcher check once (--version), not once per unit' ((-not $e71) -and $calls71.Count -eq 1 -and $calls71[0] -eq '--version') "err='$e71' calls=$($calls71 -join ' / ')"
    Case 'runner: a unit starts claude with the -p command and session' ((-not $e71) -and $a71.Count -gt 0 -and $a71[0] -eq '-p' -and $a71[1] -match '^/stream-integrate once repo: ' -and ($a71 -contains '-n') -and ($a71 -contains '--append-system-prompt-file')) "err='$e71' args=$($a71 -join ' ')"
    Case 'runner: claude''s JSON result is read as a clean run' ($s71 -and $s71.lastResult -eq 'stub71 ok' -and $s71.lastExit -eq 0 -and $s71.runs -eq 2 -and (($o71 -join "`n") -match ' EXIT 0 .* ok -> ')) "state=$($s71 | ConvertTo-Json -Compress) out=$($o71 -join ' | ')"
    # A headless (-p) unit has no unit_done tool, so it reports its outcome as a last 'UNIT-OUTCOME: <outcome>' line;
    # an idle one with an empty inbox backs the next timed unit off (E4), exactly as a -Live 'idle' does.
    $cl71i = Join-Path $Scratch 'claude-stub71i.ps1'
    Set-Content -LiteralPath $cl71i -Value @(
        "'{""type"":""result"",""result"":""nothing open in the kit inbox\nUNIT-OUTCOME: idle"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0,""session_id"":""S71I""}'"
        'exit 0')
    $env:STREAM_RUNNER_AI = $ai71; $env:STREAM_RUNNER_CLAUDE = $cl71i
    Open-Gate $r71 stream-kit
    $o71i = @(); $e71i = ''
    try { $o71i = @(& "$S\Start-StreamRunner.ps1" -Repo $r71 -Role kit -IntervalSeconds 1 -MaxRuns 1) } catch { $e71i = ("$_" -split "`n")[0] }
    Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue
    $rf71i = Get-ChildItem (Join-Path $r71 '.streams\logs\runner') -Recurse -Filter '*-kit-*.json' -ErrorAction SilentlyContinue | Select-Object -First 1
    $oc71i = try { & { . "$S\lib\Streams.ps1"; if ($rf71i) { Get-UnitOutcome (Get-Content -Raw $rf71i.FullName | ConvertFrom-Json -AsHashtable) } } } catch { "threw: $(("$_" -split "`n")[0])" }
    Case 'runner: a headless unit''s UNIT-OUTCOME idle line backs the timed runner off' ((-not $e71i) -and (($o71i -join "`n") -match ' EXIT 0 outcome idle ') -and (($o71i -join "`n") -match 'BACKOFF-IDLE') -and $oc71i -eq 'idle') "err='$e71i' outcome='$oc71i' out=$($o71i -join ' | ')"
    # ---- 72. an empty husk the watchdog cannot delete is reported, never skipped in silence (kit item
    # IN-20261004143725-1735). On 2026-10-04 G3.T283's empty, unregistered husk survived a tick that printed nothing.
    # Fixture: another process holds the empty husk as its working directory, so the delete fails; once it exits, the
    # next tick removes the husk.
    $r72 = New-Repo 'r72' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r72
    $root72 = Join-Path $Scratch 'wt72'
    $husk72 = Join-Path $root72 'G1.A'
    New-Item -ItemType Directory -Path $husk72 -Force | Out-Null
    $j72 = J $r72
    foreach ($t in $j72.tasks) { if ($t.id -eq 'G1.A') { $t.base = @{ worktree = $husk72 } } }
    Set-Content -Path (Join-Path $r72 '.streams\tasks.json') -Encoding utf8 -Value ($j72 | ConvertTo-Json -Depth 50)
    $ready72 = Join-Path $Scratch 'husk72.ready'
    $proc72 = Start-Process pwsh -PassThru -WindowStyle Hidden -WorkingDirectory $husk72 -ArgumentList '-NoProfile', '-Command', "Set-Content -LiteralPath '$ready72' -Value x; Start-Sleep -Seconds 60"
    $w72 = 0; while (-not (Test-Path $ready72) -and $w72 -lt 200) { Start-Sleep -Milliseconds 100; $w72++ }
    $a72 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r72 -Session 'status-72')
    try { $proc72.Kill($true) } catch { }
    [void]$proc72.WaitForExit(15000)
    Case 'watchdog: a held empty husk it cannot delete is reported FAILED, not QUIET' ((Test-Path $ready72) -and (Test-Path $husk72) -and (($a72 -join ' ') -match 'FAILED husk .*G1\.A is still present')) "ready=$(Test-Path $ready72) present=$(Test-Path $husk72) out=$($a72 -join ' | ')"
    $b72 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r72 -Session 'status-72')
    Case 'watchdog: once the holder exits, the next tick removes the husk' ((-not (Test-Path $husk72)) -and (($b72 -join ' ') -match 'REMOVED husk')) "present=$(Test-Path $husk72) out=$($b72 -join ' | ')"
    # ---- 73. Start-StreamRunner -Stream (EnhanceStream A2): the -p session runs with --output-format stream-json, the
    # runner prints one short line per tool call and message as they arrive, keeps every raw event in a .jsonl, and
    # reads the final result event as the unit's result.
    $r73 = New-Repo 'runner73' ([ordered]@{ 'G1.S' = (ContentGrader 'G1.S' 'done') }); $repos += $r73; Open-Gate $r73 stream-status
    $ai73 = Join-Path $Scratch 'ai-stub73.ps1'; Set-Content -LiteralPath $ai73 -Value @('exit 0')
    $cl73 = Join-Path $Scratch 'claude-stub73.ps1'
    $args73 = Join-Path $Scratch 'claude-stub73.args.json'
    Set-Content -LiteralPath $cl73 -Value @(
        "`$args | ConvertTo-Json -Compress | Set-Content -LiteralPath '$args73'"
        "'{""type"":""system"",""subtype"":""init""}'"
        "'{""type"":""assistant"",""message"":{""content"":[{""type"":""tool_use"",""name"":""Bash"",""input"":{""command"":""Get-StreamStatus.ps1 -Repo X""}}]}}'"
        "'{""type"":""assistant"",""message"":{""content"":[{""type"":""text"",""text"":""STREAM73 board read""}]}}'"
        "'{""type"":""result"",""result"":""stub73 ok"",""is_error"":false,""num_turns"":2,""total_cost_usd"":0.01}'"
        'exit 0')
    $env:STREAM_RUNNER_AI = $ai73; $env:STREAM_RUNNER_CLAUDE = $cl73
    $o73 = @(); $e73 = ''
    $d73 = @(& "$S\Start-StreamRunner.ps1" -Repo $r73 -Role status -Stream -DryRun)
    if (($d73 -join "`n") -match '(?m)^MODE stream') {
        try { $o73 = @(& "$S\Start-StreamRunner.ps1" -Repo $r73 -Role status -Stream -IntervalSeconds 1 -MaxRuns 1) } catch { $e73 = ("$_" -split "`n")[0] }
    } else { $e73 = 'skipped: this runner has no -Stream mode' }
    Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue
    $a73 = @(if (Test-Path $args73) { Get-Content -Raw $args73 | ConvertFrom-Json })
    $j73 = @(Get-ChildItem (Join-Path $r73 '.streams\logs\runner') -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue)
    $st73 = Get-ChildItem (Join-Path $r73 '.streams\runners') -Filter 'runner-status-*.json' -ErrorAction SilentlyContinue | Select-Object -Last 1
    $s73 = if ($st73) { Get-Content -Raw $st73.FullName | ConvertFrom-Json } else { $null }
    $txt73 = $o73 -join "`n"
    Case 'runner -Stream: claude gets -p with stream-json and --verbose' ((-not $e73) -and $a73[0] -eq '-p' -and ($a73 -join ' ') -match '--output-format stream-json --verbose') "err='$e73' args=$($a73 -join ' ')"
    Case 'runner -Stream: tool calls and messages print live, one short line each' ($txt73 -match '(?m)^\s+tool\s+Bash Get-StreamStatus\.ps1 -Repo X$' -and $txt73 -match '(?m)^\s+says\s+STREAM73 board read$') "out=$($o73 -join ' | ')"
    Case 'runner -Stream: the result event is the unit result, and the raw events are kept' ($s73 -and $s73.lastResult -eq 'stub73 ok' -and $s73.mode -eq 'stream' -and $j73.Count -eq 1 -and $txt73 -match ' EXIT 0 +turns 2 cost 0\.01 ok -> ') "state=$($s73 | ConvertTo-Json -Compress) jsonl=$($j73.Count)"

    # ---- 74. Start-StreamRunner -Live (EnhanceStream G): an interactive session per unit with Remote Control named
    # after the session, the stream-unit mod, the rules as a file and the command as the starting prompt; the mod's
    # result file (STREAM_UNIT_OUT) is the unit's result. A session that exits without calling unit_done is a failed run.
    $r74 = New-Repo 'runner74' ([ordered]@{ 'G1.V' = (ContentGrader 'G1.V' 'done') }); $repos += $r74; Open-Gate $r74 stream-kit
    $ai74 = Join-Path $Scratch 'ai-stub74.ps1'; Set-Content -LiteralPath $ai74 -Value @('exit 0')
    $cl74 = Join-Path $Scratch 'claude-stub74.ps1'
    $args74 = Join-Path $Scratch 'claude-stub74.args.json'
    $env74 = Join-Path $Scratch 'claude-stub74.env.txt'
    Set-Content -LiteralPath $cl74 -Value @(
        "`$args | ConvertTo-Json -Compress | Set-Content -LiteralPath '$args74'"
        "`"`$env:STREAM_UNIT_SESSION|`$env:STREAM_UNIT_ROLE`" | Set-Content -LiteralPath '$env74'"
        "if (`$env:STUB74_SKIP_RESULT -ne '1') { '{""type"":""result"",""runner"":""stream-unit"",""outcome"":""idle"",""result"":""stub74 idle"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0.02}' | Set-Content -LiteralPath `$env:STREAM_UNIT_OUT }"
        'exit 0')
    $env:STREAM_RUNNER_AI = $ai74; $env:STREAM_RUNNER_CLAUDE = $cl74
    $o74 = @(); $e74 = ''
    $d74 = @(& "$S\Start-StreamRunner.ps1" -Repo $r74 -Role kit -Live -DryRun)
    if (($d74 -join "`n") -match '(?m)^MODE live') {
        try { $o74 = @(& "$S\Start-StreamRunner.ps1" -Repo $r74 -Role kit -Live -Remote -IntervalSeconds 1 -MaxRuns 1) } catch { $e74 = ("$_" -split "`n")[0] }
    } else { $e74 = 'skipped: this runner has no -Live mode' }
    $a74 = @(if (Test-Path $args74) { Get-Content -Raw $args74 | ConvertFrom-Json })
    $v74 = if (Test-Path $env74) { (Get-Content -Raw $env74).Trim() } else { '' }
    $st74 = Get-ChildItem (Join-Path $r74 '.streams\runners') -Filter 'runner-kit-*.json' -ErrorAction SilentlyContinue | Select-Object -Last 1
    $s74 = if ($st74) { Get-Content -Raw $st74.FullName | ConvertFrom-Json } else { $null }
    $rules74 = @(Get-ChildItem (Join-Path $r74 '.streams\logs\runner') -Recurse -Filter '*.rules.txt' -ErrorAction SilentlyContinue | Select-Object -First 1)
    $rt74 = if ($rules74.Count) { Get-Content -Raw $rules74[0].FullName } else { '' }
    $sess74 = if ($s74) { [string]$s74.session } else { '?' }
    Case 'runner -Live -Remote: interactive launch with Remote Control named after the session, the mod and the starting command' ((-not $e74) -and $a74.Count -gt 0 -and $a74 -notcontains '-p' -and $a74[0] -eq '--remote-control' -and $a74[1] -eq $sess74 -and ($a74 -join ' ') -match '--plugin-dir \S*mods\\stream-unit' -and $a74[-1] -match '^/stream-kit inbox repo: ') "err='$e74' session=$sess74 args=$($a74 -join ' ')"
    Case 'runner -Live: the session gets its id and role, and the rules tell it to end with unit_done' ($v74 -eq "$sess74|kit" -and $rt74 -match 'mcp__stream-unit__unit_done exactly once' -and $rt74 -match 'lessons') "env='$v74' rules=$($rt74.Length) chars"
    Case 'runner -Live: the mod''s result file is the unit result' ($s74 -and $s74.lastResult -eq 'stub74 idle' -and $s74.mode -eq 'live' -and (($o74 -join "`n") -match ' EXIT 0 outcome idle turns 1 cost 0\.02 ok -> ')) "state=$($s74 | ConvertTo-Json -Compress) out=$($o74 -join ' | ')"
    $env:STUB74_SKIP_RESULT = '1'
    $o74b = @(); $e74b = ''
    $r74b = New-Repo 'runner74b' ([ordered]@{ 'G1.W' = (ContentGrader 'G1.W' 'done') }); $repos += $r74b; Open-Gate $r74b stream-kit
    if (-not $e74) {
        # MaxRuns 1 stops before the backoff sleep would run: the loop checks MaxRuns first. The backoff is asserted
        # by its BACKOFF line, so the case must not wait 900 s: -UnitTimeoutSeconds keeps the run itself short.
        $job74 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -MaxRuns 1 } -ArgumentList $S, $r74b
        $w74 = 0; while ($w74 -lt 300 -and -not (@(Receive-Job $job74 -Keep) -match 'BACKOFF')) { Start-Sleep -Milliseconds 100; $w74++ }
        $o74b = @(Receive-Job $job74 -Keep); Stop-Job $job74 -ErrorAction SilentlyContinue; Remove-Job $job74 -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:\STUB74_SKIP_RESULT, Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue
    # 74b runs the same stub WITHOUT -Remote (owner 2026-10-20: Remote Control only when asked), so its args file
    # holds that launch's arguments.
    $a74b = @(if (Test-Path $args74) { Get-Content -Raw $args74 | ConvertFrom-Json })
    Case 'runner -Live without -Remote: no Remote Control, the rest of the launch unchanged' ((-not $e74) -and $a74b.Count -gt 0 -and $a74b -notcontains '--remote-control' -and $a74b[0] -eq '--permission-mode' -and ($a74b -join ' ') -match '--plugin-dir \S*mods\\stream-unit' -and $a74b[-1] -match '^/stream-kit inbox repo: ') "args=$($a74b -join ' ')"
    $x74 = @(& "$S\Start-StreamRunner.ps1" -Repo $r74b -Role kit -Remote -DryRun)
    Case 'runner: -Remote without -Live is refused' ((($x74 -join "`n") -match 'REFUSED -Remote') -and $LASTEXITCODE -eq 2) "out=$($x74 -join ' | ')"
    $f74b = @(Get-ChildItem (Join-Path $r74b '.streams\logs\runner') -Recurse -Filter '*-kit-*.json' -ErrorAction SilentlyContinue | Where-Object Name -notlike '*.rules.txt')
    $ft74b = if ($f74b.Count) { Get-Content -Raw $f74b[0].FullName } else { '' }
    Case 'runner -Live: a session that exits without unit_done is a failed run (NO-RESULT, backoff)' ((($o74b -join "`n") -match ' EXIT 0 +FAILED -> ') -and (($o74b -join "`n") -match 'BACKOFF 900 s') -and $ft74b -match '^NO-RESULT ') "out=$($o74b -join ' | ') file='$ft74b'"
    # Owner 2026-10-17 ("This is cryptic ... it should also show the next time it will poll"): tab lines carry LOCAL
    # time, a failed run says what failed in words, and BACKOFF names the clock time of the next try.
    $t74c = $o74b -join "`n"
    Case 'runner tab: local-time prefix, a plain failed line, and BACKOFF with the next try time' (($t74c -match '(?m)^\d\d:\d\d:\d\d EXIT 0 +FAILED -> ') -and ($t74c -match '(?m)^  failed     : the session ended without a usable result') -and ($t74c -match '(?m)^\d\d:\d\d:\d\d BACKOFF 900 s: waiting after a failed run .*; next try at \d\d:\d\d:\d\d$') -and ($t74c -notmatch '(?m)^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ ')) "out=$($o74b -join ' | ')"

    # ---- 75. Start-StreamRunner -Live: a session past -UnitTimeoutSeconds is ended, with everything it started, and
    # logged TIMEOUT. An interactive session can hang (a prompt nobody answers); the -p modes cannot.
    $r75 = New-Repo 'runner75' ([ordered]@{ 'G1.T' = (ContentGrader 'G1.T' 'done') }); $repos += $r75; Open-Gate $r75 stream-kit
    $ai75 = Join-Path $Scratch 'ai-stub75.ps1'; Set-Content -LiteralPath $ai75 -Value @('exit 0')
    $cl75 = Join-Path $Scratch 'claude-stub75.ps1'
    $pid75 = Join-Path $Scratch 'claude-stub75.child.txt'
    # The limit is 45 s, not 6 s, and the stub and its child sleep 300 s. On the 2026-10-17 host at 100% CPU the stub
    # took more than 6 s to start its child and write the pid, so the unit was ended before the pid existed (child=0).
    # Ending well inside 150 s still proves the runner cut the 300 s session short.
    Set-Content -LiteralPath $cl75 -Value @(
        "`$c = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 300'"
        "`$c.Id | Set-Content -LiteralPath '$pid75'"
        'Start-Sleep -Seconds 300')
    $env:STREAM_RUNNER_AI = $ai75; $env:STREAM_RUNNER_CLAUDE = $cl75
    $o75 = @()
    $t75 = Measure-Command {
        $job75 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 45 -MaxRuns 1 } -ArgumentList $S, $r75
        $w75 = 0; while ($w75 -lt 1500 -and -not (@(Receive-Job $job75 -Keep) -match 'BACKOFF')) { Start-Sleep -Milliseconds 100; $w75++ }
        $o75 = @(Receive-Job $job75 -Keep); Stop-Job $job75 -ErrorAction SilentlyContinue; Remove-Job $job75 -Force -ErrorAction SilentlyContinue
    }
    Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue
    $child75 = if (Test-Path $pid75) { [int](Get-Content -Raw $pid75) } else { 0 }
    $alive75 = $child75 -and (Get-Process -Id $child75 -ErrorAction SilentlyContinue)
    if ($alive75) { Stop-Process -Id $child75 -Force -ErrorAction SilentlyContinue }
    Case 'runner -Live: a session past its limit is ended with its children and logged TIMEOUT' ((($o75 -join "`n") -match ' EXIT TIMEOUT +FAILED -> ') -and $child75 -and -not $alive75 -and $t75.TotalSeconds -lt 150) "child=$child75 alive=$([bool]$alive75) seconds=$([int]$t75.TotalSeconds) out=$($o75 -join ' | ')"

    # ---- 75q. Usage limit in a -Live unit (kit item IN-20261010205318-5308). The account's quota rejection is one
    # synthetic transcript line and the session then idles at its prompt; four author units sat to their TIMEOUT and a
    # 1800 s backoff on 2026-10-10. The runner names the transcript (--session-id), reads it while the unit runs, ends the
    # unit at once, and holds EVERY runner of the repo until the stated reset instead of a flat doubling backoff.
    $rej75q = { param([long] $At) '{"type":"assistant","message":{"model":"<synthetic>","role":"assistant","content":[{"type":"text","text":"You''ve hit your session limit - resets 4:50pm (America/New_York)"}]},"quotaLimits":{"status":"rejected","resetsAt":' + $At + ',"rateLimitType":"five_hour","overageStatus":"rejected"},"error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429}' }
    $soft75q = '{"type":"assistant","message":{"content":[{"type":"text","text":"Overloaded"}]},"quotaLimits":{"status":"allowed_warning","resetsAt":1791665400},"error":"rate_limit","isApiErrorMessage":true,"apiErrorStatus":429}'
    $user75q = '{"type":"user","message":{"content":"grep for \"quotaLimits\" and \"isApiErrorMessage\" in the transcript"}}'
    $f75q = try { & { . "$S\lib\Streams.ps1"; @{ hit = Find-QuotaRejection @('{"type":"user"}', (& $rej75q 1791665400), '{oops'); soft = Find-QuotaRejection @($soft75q, $user75q) } } } catch { @{ err = ("$_" -split "`n")[0] } }
    Case 'usage limit: a rejected quota line is found with its reset time and type; a soft 429 and a user line that only mention the fields are not' ($f75q['hit'] -and $f75q.hit.resetsAt -eq [DateTimeOffset]::FromUnixTimeSeconds(1791665400).UtcDateTime -and $f75q.hit.type -eq 'five_hour' -and $f75q.hit.text -match 'session limit' -and -not $f75q['soft'] -and -not $f75q['err']) "hit=$($f75q['hit'] | ConvertTo-Json -Compress) soft=$($f75q['soft'] | ConvertTo-Json -Compress) err=$($f75q['err'])"

    $r75q = New-Repo 'runner75q' ([ordered]@{ 'G1.Q' = (ContentGrader 'G1.Q' 'done') }); $repos += $r75q; Open-Gate $r75q stream-kit
    $proj75q = Join-Path $Scratch 'projects75q'; New-Item -ItemType Directory -Path (Join-Path $proj75q 'D--some-repo') -Force | Out-Null
    $ai75q = Join-Path $Scratch 'ai-stub75q.ps1'; Set-Content -LiteralPath $ai75q -Value @('exit 0')
    $cl75q = Join-Path $Scratch 'claude-stub75q.ps1'
    $args75q = Join-Path $Scratch 'claude-stub75q.args.json'
    $pid75q = Join-Path $Scratch 'claude-stub75q.child.txt'
    $reset75q = [DateTimeOffset]::UtcNow.AddSeconds(200).ToUnixTimeSeconds()
    Set-Content -LiteralPath $cl75q -Value @(
        "`$args | ConvertTo-Json -Compress | Set-Content -LiteralPath '$args75q'"
        "`$i = [array]::IndexOf(`$args, '--session-id'); `$sid = if (`$i -ge 0) { `$args[`$i + 1] } else { 'none' }"
        "`$t = Join-Path '$(Join-Path $proj75q 'D--some-repo')' (`$sid + '.jsonl')"
        "Set-Content -LiteralPath `$t -Value '{""type"":""user"",""message"":{""content"":""go""}}'"
        # The child is started and its pid written BEFORE the rejection line. Written after it, the runner (checking
        # every 1 s) could end the unit before a loaded host had started the child, and the case read child=0
        # (2026-10-17, host at 100% CPU).
        "`$c = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 120'"
        "`$c.Id | Set-Content -LiteralPath '$pid75q'"
        "Start-Sleep -Milliseconds 1500"
        "Add-Content -LiteralPath `$t -Value '$((& $rej75q $reset75q) -replace "'", "''")'"
        'Start-Sleep -Seconds 120')
    $env:STREAM_RUNNER_AI = $ai75q; $env:STREAM_RUNNER_CLAUDE = $cl75q; $env:STREAM_CLAUDE_PROJECTS = $proj75q; $env:STREAM_RUNNER_QUOTA_CHECK_SECONDS = '1'
    $o75q = @()
    $t75q = Measure-Command {
        $job75q = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 90 -MaxRuns 1 } -ArgumentList $S, $r75q
        Wait-Job $job75q -Timeout 60 | Out-Null
        $o75q = @(Receive-Job $job75q -Keep); Stop-Job $job75q -ErrorAction SilentlyContinue; Remove-Job $job75q -Force -ErrorAction SilentlyContinue
    }
    $a75q = @(if (Test-Path $args75q) { Get-Content -Raw $args75q | ConvertFrom-Json })
    $si75q = [array]::IndexOf($a75q, '--session-id')
    $child75q = if (Test-Path $pid75q) { [int](Get-Content -Raw $pid75q) } else { 0 }
    $alive75q = $child75q -and (Get-Process -Id $child75q -ErrorAction SilentlyContinue)
    if ($alive75q) { Stop-Process -Id $child75q -Force -ErrorAction SilentlyContinue }
    $hf75q = Join-Path $r75q '.streams\runners\quota-hold.json'
    $h75q = if (Test-Path $hf75q) { Get-Content -Raw $hf75q | ConvertFrom-Json -AsHashtable } else { $null }
    $hu75q = if ($h75q) { [datetime]::Parse([string]$h75q.until, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) } else { [datetime]::MinValue }
    $rs75q = [DateTimeOffset]::FromUnixTimeSeconds($reset75q).UtcDateTime
    $ot75q = $o75q -join "`n"
    Case 'usage limit: the -Live unit is named by --session-id and ended at once on the rejection, with its children' ($si75q -ge 2 -and $a75q[$si75q + 1] -match '^[0-9a-f-]{36}$' -and $a75q -notcontains '--remote-control' -and $ot75q -match 'EXIT USAGE-LIMIT five_hour' -and $t75q.TotalSeconds -lt 45 -and $child75q -and -not $alive75q) "seconds=$([int]$t75q.TotalSeconds) child=$child75q alive=$([bool]$alive75q) args=$($a75q -join ' ') out=$($o75q -join ' | ')"
    Case 'usage limit: no failed-run backoff; a repo-wide hold runs to the stated reset plus jitter' ($ot75q -notmatch 'BACKOFF' -and $ot75q -notmatch 'FAILED' -and $h75q -and $h75q.type -eq 'five_hour' -and $hu75q -ge $rs75q.AddSeconds(29) -and $hu75q -le $rs75q.AddSeconds(152)) "hold=$($h75q | ConvertTo-Json -Compress) reset=$($rs75q.ToString('o')) out=$($o75q -join ' | ')"

    # A second runner of the repo sees the hold and launches nothing (no claude call) until it lifts.
    Remove-Item -LiteralPath $args75q -ErrorAction SilentlyContinue
    $job75h = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 90 -MaxRuns 1 } -ArgumentList $S, $r75q
    $w75h = 0; while ($w75h -lt 200 -and -not (@(Receive-Job $job75h -Keep) -match 'QUOTA-HOLD')) { Start-Sleep -Milliseconds 100; $w75h++ }
    Start-Sleep -Seconds 2
    $o75h = @(Receive-Job $job75h -Keep); Stop-Job $job75h -ErrorAction SilentlyContinue; Remove-Job $job75h -Force -ErrorAction SilentlyContinue
    $launched75h = Test-Path $args75q
    $c75h = if (Test-Path $pid75q) { [int](Get-Content -Raw $pid75q) } else { 0 }
    if ($launched75h -and $c75h) { Stop-Process -Id $c75h -Force -ErrorAction SilentlyContinue }
    # The owner clears the hold (another account): a runner already waiting on it leaves the wait at its next 15 s
    # step instead of sleeping to the old reset (kit item IN-20261022190804-192f).
    $job75c = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 90 -MaxRuns 1 } -ArgumentList $S, $r75q
    $w75c = 0; while ($w75c -lt 200 -and -not (@(Receive-Job $job75c -Keep) -match 'QUOTA-HOLD until')) { Start-Sleep -Milliseconds 100; $w75c++ }
    $hold75c = Test-Path $hf75q
    Move-Item -LiteralPath $hf75q -Destination "$hf75q.cleared" -Force -ErrorAction SilentlyContinue
    $w75c = 0; while ($w75c -lt 250 -and -not (@(Receive-Job $job75c -Keep) -match 'QUOTA-HOLD lifted')) { Start-Sleep -Milliseconds 100; $w75c++ }
    $o75c = @(Receive-Job $job75c -Keep); Stop-Job $job75c -ErrorAction SilentlyContinue; Remove-Job $job75c -Force -ErrorAction SilentlyContinue
    $c75c = if (Test-Path $pid75q) { [int](Get-Content -Raw $pid75q) } else { 0 }
    if ((Test-Path $args75q) -and $c75c) { Stop-Process -Id $c75c -Force -ErrorAction SilentlyContinue }
    Case 'usage limit: a hold the owner clears ends a runner''s wait within one step' ($hold75c -and (($o75c -join "`n") -match 'QUOTA-HOLD lifted')) "hold=$hold75c out=$($o75c -join ' | ')"
    Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE, Env:\STREAM_CLAUDE_PROJECTS, Env:\STREAM_RUNNER_QUOTA_CHECK_SECONDS -ErrorAction SilentlyContinue
    Case 'usage limit: another runner of the repo waits on the hold and launches nothing' ((($o75h -join "`n") -match 'QUOTA-HOLD until \d\d:\d\d:\d\d [A-Za-z]+ \(\d+ s\): five_hour limit seen by ') -and -not $launched75h) "launched=$launched75h out=$($o75h -join ' | ')"

    # ---- 76. Add-Lesson (EnhanceStream E): one line per lesson in .streams\lessons\<role>.md, at most 40 kept (the
    # oldest dropped and logged in decisions.md), and a multi-line, empty or secret-looking lesson refused with nothing
    # written.
    $r76 = New-Repo 'r76' ([ordered]@{ 'G1.E' = (ContentGrader 'G1.E' 'ok') }); $repos += $r76
    $l76 = Join-Path $r76 '.streams\lessons\build.md'
    $x76 = @(& "$S\Add-Lesson.ps1" -Repo $r76 -Role build -Session 'build-76' -Task 'G1.E' -Text 'run ACL tests through the PowerShell tool' 2>&1); $c76 = $LASTEXITCODE
    $first76 = @(if (Test-Path $l76) { Get-Content $l76 })
    Case 'lessons: a lesson is one dated line with task and session' ($c76 -eq 0 -and $first76.Count -eq 1 -and $first76[0] -match '^\d{4}-\d{2}-\d{2} G1\.E build-76 run ACL tests through the PowerShell tool$') "exit=$c76 file=$($first76 -join ' / ') out=$($x76 -join ' | ')"
    $bad76 = @()
    foreach ($t in @("two`nlines", '   ', 'password=hunter2 for the warehouse')) {
        $null = & "$S\Add-Lesson.ps1" -Repo $r76 -Role build -Session 'build-76' -Task 'G1.E' -Text $t 2>&1; $bad76 += $LASTEXITCODE
    }
    $after76 = @(Get-Content $l76)
    Case 'lessons: multi-line, empty and secret-looking lessons are refused (exit 2) and nothing is written' (($bad76 -join ',') -eq '2,2,2' -and $after76.Count -eq 1) "exits=$($bad76 -join ',') lines=$($after76.Count)"
    for ($i = 2; $i -le 41; $i++) { $null = & "$S\Add-Lesson.ps1" -Repo $r76 -Role build -Session 'build-76' -Task "G1.E" -Text "lesson $i" }
    $full76 = @(Get-Content $l76)
    $dec76 = Get-Content -Raw (Join-Path $r76 '.streams\decisions.md') -ErrorAction SilentlyContinue
    Case 'lessons: the 41st lesson drops the oldest, and the drop is logged' ($full76.Count -eq 40 -and $full76[0] -match ' lesson 2$' -and $full76[-1] -match ' lesson 41$' -and $dec76 -match 'lessons\\build\.md full \(40\): dropped the oldest lesson: .* run ACL tests') "count=$($full76.Count) first='$($full76[0])' last='$($full76[-1])'"
    $p76 = @(& "$S\Add-Lesson.ps1" -Repo $r76 -Role build -Session 'coord-76' -Remove ' lesson 5' -Reason 'superseded'); $pc76 = $LASTEXITCODE
    $n76 = @(& "$S\Add-Lesson.ps1" -Repo $r76 -Role build -Session 'coord-76' -Remove 'no such lesson' -Reason 'x'); $nc76 = $LASTEXITCODE
    $pr76 = @(Get-Content $l76)
    $dec76b = Get-Content -Raw (Join-Path $r76 '.streams\decisions.md')
    Case 'lessons: -Remove prunes every matching lesson and logs it; no match is NO-MATCH (3)' ($pc76 -eq 0 -and $pr76.Count -eq 39 -and -not (@($pr76) -match ' lesson 5$') -and $dec76b -match 'lessons\\build\.md pruned \(superseded\): .* lesson 5' -and $nc76 -eq 3 -and ($n76 -join ' ') -match '^NO-MATCH') "exit=$pc76 count=$($pr76.Count) no-match=$nc76 out=$($p76 -join ' | ')"

    # ---- 77. runner units that ended are not live sessions (kit item IN-20261004184753-9f49). Four builders left fresh
    # idle beats. build-77a was a runner unit with a result and no runner naming it, build-77c is named by a runner whose
    # pid is dead, build-77d by a stopped runner: all ENDED. build-77b is the current session of a live runner, and
    # build-77e is a /loop session with no rules file. The board must count exactly those two.
    $r77 = New-Repo 'r77' ([ordered]@{ 'G1.E' = (ContentGrader 'G1.E' 'ok') }); $repos += $r77
    $idle77 = Join-Path $r77 '.streams\idle'; New-Item -ItemType Directory -Path $idle77 -Force | Out-Null
    $now77 = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    foreach ($u77 in @('build-77a', 'build-77b', 'build-77c', 'build-77d', 'build-77e')) { Set-Content (Join-Path $idle77 "$u77.json") ([ordered]@{ session = $u77; role = 'build'; at = $now77 } | ConvertTo-Json -Compress) }
    $log77 = Join-Path $r77 '.streams\logs\runner\runner-build-77'; New-Item -ItemType Directory -Path $log77 -Force | Out-Null
    foreach ($u77 in @('build-77a', 'build-77b', 'build-77c', 'build-77d')) { Set-Content (Join-Path $log77 "20261004T180000Z-$u77.rules.txt") 'rules' }
    Set-Content (Join-Path $log77 '20261004T180000Z-build-77a.json') '{}'
    $dead77 = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', 'exit 0' -WindowStyle Hidden -PassThru; $dead77.WaitForExit()
    $run77 = Join-Path $r77 '.streams\runners'; New-Item -ItemType Directory -Path $run77 -Force | Out-Null
    Set-Content (Join-Path $run77 'runner-build-77b.json') ([ordered]@{ role = 'build'; pid = $PID; session = 'build-77b'; status = 'running build-77b' } | ConvertTo-Json)
    Set-Content (Join-Path $run77 'runner-build-77c.json') ([ordered]@{ role = 'build'; pid = $dead77.Id; session = 'build-77c'; status = 'running build-77c' } | ConvertTo-Json)
    Set-Content (Join-Path $run77 'runner-build-77d.json') ([ordered]@{ role = 'build'; pid = $PID; session = 'build-77d'; status = 'stopped (STOP file)' } | ConvertTo-Json)
    $m77 = & "$S\Get-StreamStatus.ps1" -Repo $r77 -Json | ConvertFrom-Json
    $ids77 = @($m77.sessions.build.list | ForEach-Object { $_.session }) -join ','
    Case 'runner: ended runner units are not live; the live runner unit and a /loop session are' ($m77.sessions.build.live -eq 2 -and $ids77 -eq 'build-77b,build-77e') "live=$($m77.sessions.build.live) ids=$ids77"
    # ---- 78. Start-StreamRunner -Tab: the runner records the terminal tab it runs in, and stops alone on
    # STOP-tab-<tab> (or STOP-<runner id>), deleting that file as it exits; a runner of another tab is not stopped.
    $r78 = New-Repo 'runner78' ([ordered]@{ 'G1.T' = (ContentGrader 'G1.T' 'done') }); $repos += $r78; Open-Gate $r78 stream-integrate
    $ai78 = Join-Path $Scratch 'ai-stub78.ps1'; $cl78 = Join-Path $Scratch 'claude-stub78.ps1'
    Set-Content -LiteralPath $ai78 -Value @("'ai: applied revision STUB78'", 'exit 0')
    Set-Content -LiteralPath $cl78 -Value @("'{""type"":""result"",""result"":""stub78 ok"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0}'", 'exit 0')
    $d78 = @(& "$S\Start-StreamRunner.ps1" -Repo $r78 -Role integrate -Tab 'Author 9' -DryRun)
    Case 'runner: DryRun names the tab and its stop file' (($d78 -join "`n") -match '(?m)^TAB Author 9 stop file STOP-tab-Author_9$') "$($d78 -join ' | ')"
    $env:STREAM_RUNNER_AI = $ai78; $env:STREAM_RUNNER_CLAUDE = $cl78
    $runners78 = Join-Path $r78 '.streams\runners'
    try {
        $null = @(& "$S\Start-StreamRunner.ps1" -Repo $r78 -Role integrate -IntervalSeconds 1 -MaxRuns 1 -Tab 'Author 9')
        $s78a = Get-ChildItem $runners78 -Filter 'runner-integrate-*.json' | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json } | Select-Object -Last 1
        Set-Content -LiteralPath (Join-Path $runners78 'STOP-tab-Author_9') -Value x
        $o78b = @(& "$S\Start-StreamRunner.ps1" -Repo $r78 -Role integrate -IntervalSeconds 1 -MaxRuns 1 -Tab 'Author 9')
        $stop78Left = Test-Path (Join-Path $runners78 'STOP-tab-Author_9')
        Set-Content -LiteralPath (Join-Path $runners78 'STOP-tab-Author_9') -Value x
        $o78c = @(& "$S\Start-StreamRunner.ps1" -Repo $r78 -Role integrate -IntervalSeconds 1 -MaxRuns 1 -Tab 'Builder 1')
    } finally { Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue }
    Case 'runner: -Tab is recorded in the state file' ($s78a -and $s78a.tab -eq 'Author 9' -and $s78a.runs -eq 1) "state=$($s78a | ConvertTo-Json -Compress)"
    Case 'runner: STOP-tab-<tab> stops that runner before any launch and is deleted as it exits' ((($o78b -join "`n") -match 'STOP file found; runner exits') -and (($o78b -join "`n") -notmatch ' EXIT ') -and -not $stop78Left) "left=$stop78Left out=$($o78b -join ' | ')"
    Case 'runner: another tab''s stop file does not stop this runner, and is left in place' ((($o78c -join "`n") -match ' EXIT 0 .* ok -> ') -and (Test-Path (Join-Path $runners78 'STOP-tab-Author_9'))) "out=$($o78c -join ' | ')"

    # ---- 79. a claim left by a runner unit is freed at once, not after the role's limit (kit item
    # IN-20261004202424-27bf). (a) The watchdog breaks a FRESHLY beaten claim whose session is an ended runner unit (its
    # runner's pid is dead): a build claim sends its building row back to ticketed, an author claim is cleared. The live
    # runner's current unit and a /loop session keep theirs. (b) The runner itself releases the claim its unit left
    # when the unit exits without releasing it.
    $r79 = New-Repo 'r79' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok'); 'G1.C' = (ContentGrader 'G1.C' 'ok'); 'G1.D' = (ContentGrader 'G1.D' 'ok') }); $repos += $r79
    $log79 = Join-Path $r79 '.streams\logs\runner\runner-build-79'; New-Item -ItemType Directory -Path $log79 -Force | Out-Null
    foreach ($u79 in @('build-79dead', 'author-79dead', 'build-79live')) { Set-Content (Join-Path $log79 "20261004T200000Z-$u79.rules.txt") 'rules' }
    $dead79 = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', 'exit 0' -WindowStyle Hidden -PassThru; $dead79.WaitForExit()
    $run79 = Join-Path $r79 '.streams\runners'; New-Item -ItemType Directory -Path $run79 -Force | Out-Null
    Set-Content (Join-Path $run79 'runner-build-79a.json') ([ordered]@{ role = 'build'; pid = $dead79.Id; session = 'build-79dead'; status = 'running build-79dead' } | ConvertTo-Json)
    Set-Content (Join-Path $run79 'runner-author-79b.json') ([ordered]@{ role = 'author'; pid = $dead79.Id; session = 'author-79dead'; status = 'running author-79dead' } | ConvertTo-Json)
    Set-Content (Join-Path $run79 'runner-build-79c.json') ([ordered]@{ role = 'build'; pid = $PID; session = 'build-79live'; status = 'running build-79live' } | ConvertTo-Json)
    $now79 = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $doc79 = J $r79
    $claims79 = @{ 'G1.A' = @('build', 'build-79dead', 'building'); 'G1.B' = @('author', 'author-79dead', 'planned'); 'G1.C' = @('build', 'build-79live', 'building'); 'G1.D' = @('build', 'build-79loop', 'building') }
    foreach ($t in $doc79.tasks) { $c = $claims79[$t.id]; $t.state = $c[2]; $t.claim = @{ role = $c[0]; session = $c[1]; at = $now79; beat = $now79 } }
    Set-Content -Path (Join-Path $r79 '.streams\tasks.json') -Encoding utf8 -Value ($doc79 | ConvertTo-Json -Depth 50)
    $w79 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r79 -Session status-79)
    $a79 = T $r79 'G1.A'; $b79 = T $r79 'G1.B'; $c79 = T $r79 'G1.C'; $d79 = T $r79 'G1.D'
    Case 'watchdog: a fresh build claim of an ended runner unit is broken at once and the row goes back to ticketed' (-not $a79.claim -and $a79.state -eq 'ticketed' -and (($w79 -join "`n") -match 'BROKE G1\.A: build claim of build-79dead, a runner unit that has ended')) "state=$($a79.state) claim=$($a79.claim | ConvertTo-Json -Compress) out=$($w79 -join ' | ')"
    Case 'watchdog: a fresh author claim of an ended runner unit is cleared, the row stays planned' (-not $b79.claim -and $b79.state -eq 'planned') "state=$($b79.state) claim=$($b79.claim | ConvertTo-Json -Compress)"
    Case 'watchdog: the live runner''s current unit and a /loop session keep their fresh claims' ($c79.claim.session -eq 'build-79live' -and $d79.claim.session -eq 'build-79loop') "c=$($c79.claim | ConvertTo-Json -Compress) d=$($d79.claim | ConvertTo-Json -Compress)"

    $r79b = New-Repo 'r79b' ([ordered]@{ 'G1.E' = (ContentGrader 'G1.E' 'ok') }); $repos += $r79b
    $ai79 = Join-Path $Scratch 'ai-stub79.ps1'; $cl79 = Join-Path $Scratch 'claude-stub79.ps1'
    Set-Content -LiteralPath $ai79 -Value @("'ai: applied revision STUB79'", 'exit 0')
    # The stub plays a unit that claims a row and then exits without releasing it, as a killed unit would.
    Set-Content -LiteralPath $cl79 -Value @(
        '$i = [array]::IndexOf($args, ''-n''); $sess = $args[$i + 1]'
        "& '$S\Claim-Task.ps1' -Repo (Get-Location).Path -Role build -Session `$sess | Out-Null"
        "'{""type"":""result"",""result"":""stub79 ok"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0}'"
        'exit 0')
    $env:STREAM_RUNNER_AI = $ai79; $env:STREAM_RUNNER_CLAUDE = $cl79
    try { $o79 = @(& "$S\Start-StreamRunner.ps1" -Repo $r79b -Role build -IntervalSeconds 1 -MaxRuns 1) }
    finally { Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue }
    $e79 = T $r79b 'G1.E'
    $claimed79 = @($e79.history | Where-Object { $_.to -eq 'building' }).Count -gt 0
    Case 'runner: the claim a unit left is released when the unit exits, and the row is claimable again'($claimed79 -and -not $e79.claim -and $e79.state -eq 'ticketed' -and (($o79 -join "`n") -match 'RELEASED G1\.E: claim\(s\) unit build-')) "claimed=$claimed79 state=$($e79.state) claim=$($e79.claim | ConvertTo-Json -Compress) out=$($o79 -join ' | ')"

    # ---- 80. the board reads runner units from their runners (kit item IN-20261004202801-5449). author-80a is in
    # flight with no claim (it just released its ticket), author-80c is in flight holding a claim: both working.
    # author-80b is the last unit of a runner that sleeps ('idle since') and has never written: idle, not quiet and not
    # missing. author-80old is runner A's previous unit with a fresh idle beat: ended. author-80loop is a /loop session
    # silent for 25 min: quiet.
    $r80 = New-Repo 'r80' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r80
    $log80 = Join-Path $r80 '.streams\logs\runner\runner-author-80'; New-Item -ItemType Directory -Path $log80 -Force | Out-Null
    foreach ($u80 in @('author-80a', 'author-80b', 'author-80c', 'author-80old')) { Set-Content (Join-Path $log80 "20261004T200000Z-$u80.rules.txt") 'rules' }
    $run80 = Join-Path $r80 '.streams\runners'; New-Item -ItemType Directory -Path $run80 -Force | Out-Null
    Set-Content (Join-Path $run80 'runner-author-80a.json') ([ordered]@{ role = 'author'; pid = $PID; session = 'author-80a'; status = 'running author-80a' } | ConvertTo-Json)
    Set-Content (Join-Path $run80 'runner-author-80b.json') ([ordered]@{ role = 'author'; pid = $PID; session = 'author-80b'; status = 'idle since 2026-10-04T20:00:00Z' } | ConvertTo-Json)
    Set-Content (Join-Path $run80 'runner-author-80c.json') ([ordered]@{ role = 'author'; pid = $PID; session = 'author-80c'; status = 'running author-80c' } | ConvertTo-Json)
    $idle80 = Join-Path $r80 '.streams\idle'; New-Item -ItemType Directory -Path $idle80 -Force | Out-Null
    $at80 = (Get-Date).ToUniversalTime()
    Set-Content (Join-Path $idle80 'author-80old.json') ([ordered]@{ session = 'author-80old'; role = 'author'; at = $at80.ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json -Compress)
    Set-Content (Join-Path $idle80 'author-80loop.json') ([ordered]@{ session = 'author-80loop'; role = 'author'; at = $at80.AddMinutes(-25).ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json -Compress)
    $doc80 = J $r80; $t80 = $doc80.tasks[0]; $t80.state = 'planned'; $t80.claim = @{ role = 'author'; session = 'author-80c'; at = $at80.ToString('yyyy-MM-ddTHH:mm:ssZ'); beat = $at80.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    Set-Content -Path (Join-Path $r80 '.streams\tasks.json') -Encoding utf8 -Value ($doc80 | ConvertTo-Json -Depth 50)
    $m80 = (& "$S\Get-StreamStatus.ps1" -Repo $r80 -Json | ConvertFrom-Json).sessions.author
    $ids80 = @($m80.list | ForEach-Object { $_.session }) -join ','
    Case 'board: runner units in flight are working, a sleeping runner''s unit is idle, an ended unit is gone, a silent /loop session is quiet'($m80.live -eq 4 -and $m80.working -eq 2 -and $m80.claimed -eq 1 -and $m80.idle -eq 1 -and $m80.quiet -eq 1 -and $ids80 -eq 'author-80a,author-80b,author-80c,author-80loop') "live=$($m80.live) working=$($m80.working) claimed=$($m80.claimed) idle=$($m80.idle) quiet=$($m80.quiet) ids=$ids80"

    # ---- 80w. a runner unit waiting on an owner permission prompt is flagged OWNER-WAIT (kit item
    # IN-20261021114057-5e66). Its runner keeps the claim beat fresh, so the board read it as working and raised only an
    # overrun: on 2026-10-21 three builders sat 7-8 h on unanswered destructive-path-guard prompts. r80 has no such unit.
    $r80w = New-Repo 'r80w' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r80w
    $run80w = Join-Path $r80w '.streams\runners'; New-Item -ItemType Directory -Path $run80w -Force | Out-Null
    $at80w = (Get-Date).ToUniversalTime()
    Set-Content (Join-Path $run80w 'runner-author-80w.json') ([ordered]@{ role = 'author'; pid = $PID; session = 'author-80w'; tab = 'Author 9'; status = "waiting on owner since $($at80w.AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ')): permission prompt (Bash: destructive-path-guard: stub80w)" } | ConvertTo-Json)
    $doc80w = J $r80w; $t80w = $doc80w.tasks[0]; $t80w.state = 'planned'; $t80w.claim = @{ role = 'author'; session = 'author-80w'; at = $at80w.ToString('yyyy-MM-ddTHH:mm:ssZ'); beat = $at80w.ToString('yyyy-MM-ddTHH:mm:ssZ') }
    Set-Content -Path (Join-Path $r80w '.streams\tasks.json') -Encoding utf8 -Value ($doc80w | ConvertTo-Json -Depth 50)
    $f80w = @((& "$S\Get-StreamStatus.ps1" -Repo $r80w -Json | ConvertFrom-Json).flags)
    $f80n = @((& "$S\Get-StreamStatus.ps1" -Repo $r80 -Json | ConvertFrom-Json).flags)
    Case 'board: a runner unit waiting on an owner prompt raises OWNER-WAIT with its task, minutes, tab and prompt; none without one' ((@($f80w | Where-Object { $_ -match '^OWNER-WAIT author-80w G1\.A (29|30|31) min \(tab Author 9\): .*stub80w' }).Count -eq 1 -and -not @($f80n | Where-Object { $_ -like 'OWNER-WAIT*' }).Count)) "w=$($f80w -join ' || ') n=$(@($f80n | Where-Object { $_ -like 'OWNER-WAIT*' }) -join ' || ')"

    # ---- 81. an escalation is classified by its shape, not its bullet (kit item IN-20261004203020-5f5e). Bulleted
    # applied defaults (4 fields, or 'APPLIED DEFAULT' text) are not owner questions; an ESCALATE token, an 'owner decides'
    # line, and a line that carries no default (fewer than 4 fields), bulleted or not, are.
    $r81 = New-Repo 'r81' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r81
    Set-Content -Path (Join-Path $r81 '.streams\owner\questions.md') -Encoding utf8 -Value @(
        '- G1.A | where to trim the slash | inline TrimStart | code-behind is outside the write set',
        '- 2026-10-04T20:11:17Z [plan-81] G1.A: which result set? APPLIED DEFAULT: the last one',
        'G1.A | which timeout | 30s applied | the donor used 30s',
        '- ESCALATE G1.A | ship the store or the host first | no default: both change the release plan | reasoning',
        'G1.A | a timed-out retry sends twice | kept TimedOut; owner decides | 5 tests assert it',
        'G1.A | the owner has to choose the store',
        '- G1.A the owner has to choose the host')
    $m81 = & "$S\Get-StreamStatus.ps1" -Repo $r81 -Json | ConvertFrom-Json
    $e81 = @($m81.owner.escalations)
    Case 'owner queue: bulleted applied defaults are not escalations; ESCALATE, owner-decides and default-less lines are' ($e81.Count -eq 4 -and @($m81.owner.questions).Count -eq 7 -and (($e81 -join "`n") -notmatch 'TrimStart|APPLIED DEFAULT|30s applied')) "escalations=$($e81.Count) questions=$(@($m81.owner.questions).Count) got=$($e81 -join ' || ')"

    # ---- 82. New-TaskWorktree under a busy tasks.json lock (kit item IN-20261004204921-2c98). It made the tree, then its
    # only locked write ran out of the 15 s wait, so the tree was recorded nowhere and the retry made <task>-2. Another
    # process holds the lock for 20 s: one tree, base recorded, a 'building' ledger line, no -2. Then a session that
    # does not hold the claim (exit 3, CLAIM-LOST) leaves its tree marked abandoned in worktrees.md.
    $r82 = New-Repo 'r82' ([ordered]@{ 'G1.K' = (ContentGrader 'G1.K' 'ok') }); $repos += $r82
    $c82 = & "$S\Claim-Task.ps1" -Repo $r82 -Role build -Session build-82 | ConvertFrom-Json
    if ($c82.id -ne 'G1.K') { throw "expected to claim G1.K, got $($c82.id)" }
    . "$S\lib\Streams.ps1"
    $P82 = Get-StreamPaths $r82
    $root82 = Join-Path $Scratch 'wt82'
    $hold82 = Start-Process pwsh -WindowStyle Hidden -PassThru -ArgumentList '-NoProfile', '-Command', "`$f = [IO.File]::Open('$($P82.Lock)', [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read); Start-Sleep -Seconds 20; `$f.Dispose(); Remove-Item -LiteralPath '$($P82.Lock)' -Force"
    $w82 = 0; while (-not (Test-Path $P82.Lock) -and $w82 -lt 100) { Start-Sleep -Milliseconds 100; $w82++ }
    $err82 = ''
    try { $o82 = @(& "$S\New-TaskWorktree.ps1" -Repo $r82 -Task G1.K -Session build-82 -WorktreeRoot $root82); $x82 = $LASTEXITCODE } catch { $err82 = ("$_" -split "`n")[0] }
    $hold82.WaitForExit(30000) | Out-Null
    $t82 = T $r82 'G1.K'
    # Read the base defensively: the unfixed script records none, and that must report FAIL here, not abort the harness.
    $b82 = if ($t82 -and $t82.ContainsKey('base') -and $t82['base']) { [string]$t82['base']['worktree'] } else { '' }
    $led82 = @(Get-Content $P82.Worktrees -ErrorAction SilentlyContinue)
    Case 'worktree: a 20 s lock hold is waited out; one tree, base recorded, building line, no -2' (-not $err82 -and $b82 -eq (Join-Path $root82 'G1.K') -and -not (Test-Path (Join-Path $root82 'G1.K-2')) -and @($led82 -match '^- G1\.K \| .*\| building$').Count -eq 1) "err='$err82' base=$b82 dash2=$(Test-Path (Join-Path $root82 'G1.K-2')) ledger=$($led82 -join ' / ')"
    $o82b = @(& "$S\New-TaskWorktree.ps1" -Repo $r82 -Task G1.K -Session build-82-other -WorktreeRoot $root82); $x82b = $LASTEXITCODE
    $led82b = @(Get-Content $P82.Worktrees)
    Case 'worktree: a claim lost before the tree is recorded leaves it marked abandoned in worktrees.md' ($x82b -eq 3 -and @($led82b -match ('^- G1\.K \| ' + [regex]::Escape((Join-Path $root82 'G1.K-2')) + ' \| .* \| abandoned \(New-TaskWorktree: claim lost')).Count -eq 1) "exit=$x82b ledger=$($led82b -join ' / ')"

    # ---- 83. a -Live unit that wrote its result and then ran past its limit is a TIMEOUT, but NOT a failed run: no
    # backoff (kit item IN-20261004205649-446f, G3.T170 'built' and then 900 s of backoff). The default build unit limit
    # is 5400 s, above the 2700 s that killed two-verifier builds.
    $r83 = New-Repo 'runner83' ([ordered]@{ 'G1.T' = (ContentGrader 'G1.T' 'done') }); $repos += $r83; Open-Gate $r83 stream-kit
    $ai83 = Join-Path $Scratch 'ai-stub83.ps1'; Set-Content -LiteralPath $ai83 -Value @('exit 0')
    $cl83 = Join-Path $Scratch 'claude-stub83.ps1'
    Set-Content -LiteralPath $cl83 -Value @(
        "Set-Content -LiteralPath `$env:STREAM_UNIT_OUT -Value '{""result"":""stub83 built"",""is_error"":false,""num_turns"":3,""total_cost_usd"":0,""outcome"":""built""}'"
        'Start-Sleep -Seconds 120')
    $env:STREAM_RUNNER_AI = $ai83; $env:STREAM_RUNNER_CLAUDE = $cl83
    try {
        # A 60 s unit limit, not 6 s: on a loaded host the stub's pwsh took longer than 6 s to start and write its result,
        # so the unit timed out with no result and the case read FAILED plus a backoff (2026-10-17, host at 100% CPU).
        $job83 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 60 -MaxRuns 1 } -ArgumentList $S, $r83
        $null = Wait-Job $job83 -Timeout 240
        $o83 = @(Receive-Job $job83 -Keep); Stop-Job $job83 -ErrorAction SilentlyContinue; Remove-Job $job83 -Force -ErrorAction SilentlyContinue
        $d83 = @(& "$S\Start-StreamRunner.ps1" -Repo $r83 -Role build -Live -DryRun)
    } finally { Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue }
    $j83 = ($o83 -join "`n")
    Case 'runner -Live: a TIMEOUT unit that wrote its result is ok, with no backoff' (($j83 -match ' EXIT TIMEOUT outcome built .* ok -> ') -and ($j83 -notmatch 'BACKOFF')) "out=$($o83 -join ' | ')"
    Case 'runner -Live: the default build unit limit is 5400 s' (($d83 -join "`n") -match 'timeout 5400 s') "out=$($d83 -join ' | ')"

    # 84. Update-Task under pwsh -File. A hashtable argument arrives there as TEXT, so -Artifacts @{...} failed to bind
    # and an author's release then cleared the claim with artifacts.ticket still null: G3.T369 reached ticketed with no
    # ticket (kit item IN-20261004235456-523e). -Artifacts and -Base now take JSON or @{...} text, and an author's
    # planned -> ticketed is refused while the row has no ticket.
    $r84 = New-Repo 'artifactstext' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r84
    $j84 = J $r84
    foreach ($t in $j84.tasks) { $t.state = 'planned'; $t.artifacts.ticket = $null }
    Set-Content -Path (Join-Path $r84 '.streams\tasks.json') -Encoding utf8 -Value ($j84 | ConvertTo-Json -Depth 50)
    [void](& "$S\Claim-Task.ps1" -Repo $r84 -Role author -Session 'author-84' -Task 'G1.A')
    $x84a = @(& pwsh -NoProfile -File "$S\Update-Task.ps1" -Repo $r84 -Task G1.A -Role author -Session author-84 -To ticketed -Release -Note 'test: no ticket' 2>&1); $c84a = $LASTEXITCODE
    $t84a = T $r84 'G1.A'
    Case 'update -File: an author release to ticketed with no ticket is refused and keeps the claim' (($c84a -eq 6) -and ($t84a.state -eq 'planned') -and ($t84a.claim.session -eq 'author-84') -and (($x84a -join ' ') -match 'TRANSITION-REFUSED G1\.A: .*artifacts\.ticket')) "exit=$c84a state=$($t84a.state) out=$($x84a -join ' | ')"
    $x84b = @(& pwsh -NoProfile -File "$S\Update-Task.ps1" -Repo $r84 -Task G1.A -Role author -Session author-84 -Artifacts '{"grader":".streams\\graders\\G1.A.ps1"}' 2>&1); $c84b = $LASTEXITCODE
    Case 'update -File: -Artifacts takes JSON text' (($c84b -eq 0) -and ((T $r84 'G1.A').artifacts.grader -eq '.streams\graders\G1.A.ps1')) "exit=$c84b out=$($x84b -join ' | ')"
    $x84c = @(& pwsh -NoProfile -File "$S\Update-Task.ps1" -Repo $r84 -Task G1.A -Role author -Session author-84 -Artifacts "@{ ticket = '.streams\tickets\G1.A.md' }" -To ticketed -Release -Note 'test: ticket and release in one call' 2>&1); $c84c = $LASTEXITCODE
    $t84c = T $r84 'G1.A'
    Case 'update -File: -Artifacts takes @{...} text, and the release then goes through' (($c84c -eq 0) -and ($t84c.state -eq 'ticketed') -and ($t84c.artifacts.ticket -eq '.streams\tickets\G1.A.md') -and -not $t84c.claim) "exit=$c84c state=$($t84c.state) out=$($x84c -join ' | ')"
    $x84d = @(& pwsh -NoProfile -File "$S\Update-Task.ps1" -Repo $r84 -Task G1.A -Role plan -Session plan-84 -Artifacts 'ticket=x' 2>&1); $c84d = $LASTEXITCODE
    Case 'update -File: -Artifacts text that is neither JSON nor @{...} is refused, nothing written' (($c84d -eq 2) -and (($x84d -join ' ') -match 'REFUSED -Artifacts') -and ((T $r84 'G1.A').artifacts.ticket -eq '.streams\tickets\G1.A.md')) "exit=$c84d out=$($x84d -join ' | ')"

    # 85. A tree whose removal FAILED is held by a process left running out of it by an ended unit: an orphan
    # speedy-web.dll from G4.T021's bin kept that tree through two ticks (kit item IN-20261005004713-cf76). The retry
    # stops every process whose command line names the tree, names it, and then removes the tree. A sibling tree with a
    # longer name (G1.A-2) is not touched.
    $r85 = New-Repo 'r85' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r85
    $root85 = Join-Path $Scratch 'wt85'
    $leak85 = Join-Path $root85 'G1.A'; $sib85 = Join-Path $root85 'G1.A-2'
    New-Item -ItemType Directory -Path $leak85, $sib85 -Force | Out-Null
    Set-Content (Join-Path $leak85 'big.txt') ('x' * 4096)
    $P85 = Get-StreamPaths $r85
    Add-LineTo $P85.Worktrees ("- G1.A | {0} | {1} | removal FAILED (directory still present)" -f $leak85, (Get-Now))
    $j85 = J $r85
    foreach ($t in $j85.tasks) { if ($t.id -eq 'G1.A') { $t.base = @{ worktree = $leak85 } } }
    Set-Content -Path (Join-Path $r85 '.streams\tasks.json') -Encoding utf8 -Value ($j85 | ConvertTo-Json -Depth 50)
    $ready85 = Join-Path $Scratch 'hold85.ready'; $readySib85 = Join-Path $Scratch 'sib85.ready'
    $proc85 = Start-Process pwsh -PassThru -WindowStyle Hidden -WorkingDirectory $leak85 -ArgumentList '-NoProfile', '-Command', "Set-Content -LiteralPath '$ready85' -Value x; Start-Sleep -Seconds 90 # holds $leak85\big.txt"
    $sibp85 = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', "Set-Content -LiteralPath '$readySib85' -Value x; Start-Sleep -Seconds 90 # works in $sib85\x"
    $w85 = 0; while (-not ((Test-Path $ready85) -and (Test-Path $readySib85)) -and $w85 -lt 200) { Start-Sleep -Milliseconds 100; $w85++ }
    $a85 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r85 -Session 'status-85')
    $sibAlive85 = -not $sibp85.HasExited
    foreach ($pp in @($proc85, $sibp85)) { try { $pp.Kill($true) } catch { }; [void]$pp.WaitForExit(15000) }
    Case 'watchdog: a process running out of a FAILED tree is stopped and named, and the tree is removed' ((-not (Test-Path $leak85)) -and (($a85 -join ' ') -match "KILLED pid $($proc85.Id) pwsh") -and (($a85 -join ' ') -match 'REMOVED .*G1\.A on retry')) "present=$(Test-Path $leak85) out=$($a85 -join ' | ')"
    Case 'watchdog: a process in a sibling tree with a longer name is left alone' ($sibAlive85 -and (($a85 -join ' ') -notmatch "pid $($sibp85.Id)")) "sibAlive=$sibAlive85 out=$($a85 -join ' | ')"

    # 85b. A LIVE session's own tree is never killed out of or reaped, whatever its registration. On 2026-10-09 a builder
    # live on G4.T116 ran a serial Tests.Unit baseline in G4.T116-base; the tree matched no task, the removal failed on
    # its open files, and the retry KILLED dotnet.exe and testhost.exe and removed it (kit item IN-20261009022355-40f9).
    # Same FAILED-removal setup as 85, but G1.A holds a live build claim: G1.A-base is named after it, and baseline85 is
    # named in the holder's own history. Both trees stay, and both processes live.
    $r85b = New-Repo 'r85b' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r85b
    $root85b = Join-Path $Scratch 'wt85b'
    $own85b = Join-Path $root85b 'G1.A-base'; $named85b = Join-Path $root85b 'baseline85'; $rec85b = Join-Path $root85b 'G1.A'
    New-Item -ItemType Directory -Path $own85b, $named85b, $rec85b -Force | Out-Null
    foreach ($dd in @($own85b, $named85b)) { Set-Content (Join-Path $dd 'big.txt') ('x' * 4096) }
    $P85b = Get-StreamPaths $r85b
    foreach ($dd in @($own85b, $named85b)) { Add-LineTo $P85b.Worktrees ("- G1.A | {0} | {1} | removal FAILED (directory still present)" -f $dd, (Get-Now)) }
    $now85b = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $j85b = J $r85b
    foreach ($t in $j85b.tasks) { if ($t.id -eq 'G1.A') {
        $t.state = 'building'; $t.base = @{ worktree = $rec85b }
        $t.claim = @{ role = 'build'; session = 'build-85b'; at = $now85b; beat = $now85b }
        $t.history = @($t.history) + @(@{ at = $now85b; by = 'build-85b'; to = 'building'; note = "Serial Unit baseline running detached in $named85b for A4" }) } }
    Set-Content -Path (Join-Path $r85b '.streams\tasks.json') -Encoding utf8 -Value ($j85b | ConvertTo-Json -Depth 50)
    $rdy85b = @((Join-Path $Scratch 'own85b.ready'), (Join-Path $Scratch 'named85b.ready'))
    $p85b = @(
        Start-Process pwsh -PassThru -WindowStyle Hidden -WorkingDirectory $own85b -ArgumentList '-NoProfile', '-Command', "Set-Content -LiteralPath '$($rdy85b[0])' -Value x; Start-Sleep -Seconds 90 # baseline in $own85b\big.txt"
        Start-Process pwsh -PassThru -WindowStyle Hidden -WorkingDirectory $named85b -ArgumentList '-NoProfile', '-Command', "Set-Content -LiteralPath '$($rdy85b[1])' -Value x; Start-Sleep -Seconds 90 # baseline in $named85b\big.txt")
    $w85b = 0; while (-not ((Test-Path $rdy85b[0]) -and (Test-Path $rdy85b[1])) -and $w85b -lt 200) { Start-Sleep -Milliseconds 100; $w85b++ }
    $a85b = @(& "$S\Invoke-Watchdog.ps1" -Repo $r85b -Session 'status-85b')
    $alive85b = @($p85b | Where-Object { -not $_.HasExited }).Count
    foreach ($pp in $p85b) { try { $pp.Kill($true) } catch { }; [void]$pp.WaitForExit(15000) }
    Case 'watchdog: a tree named after a task with a live build claim is kept, and nothing in it is killed' ((Test-Path $own85b) -and (($a85b -join ' ') -match 'KEPT .*G1\.A-base: G1\.A holds a live build claim') -and (($a85b -join ' ') -notmatch "KILLED pid $($p85b[0].Id)")) "present=$(Test-Path $own85b) out=$($a85b -join ' | ')"
    Case 'watchdog: a tree the live claim holder named in its history is kept, and nothing in it is killed' ((Test-Path $named85b) -and (($a85b -join ' ') -match 'KEPT .*baseline85: build-85b, live on G1\.A, named baseline85') -and (($a85b -join ' ') -notmatch "KILLED pid $($p85b[1].Id)") -and $alive85b -eq 2) "present=$(Test-Path $named85b) alive=$alive85b out=$($a85b -join ' | ')"

    # 85c. Ownership by the task NUMBER in any form, and no kill in a busy tree that names no task. After 85b shipped, the
    # G4.T116 holder re-ran its baseline in T116-serialbase, which the full-id name rule did not own, and the parent
    # chain of a detached run is gone, so only a skipped pass kept it alive (kit item IN-20261009025121-b316).
    $r85c = New-Repo 'r85c' ([ordered]@{ 'G1.T116' = (ContentGrader 'G1.T116' 'ok') }); $repos += $r85c
    $root85c = Join-Path $Scratch 'wt85c'
    $short85c = Join-Path $root85c 'T116-serialbase'; $none85c = Join-Path $root85c 'scratch85c'; $rec85c = Join-Path $root85c 'G1.T116'
    $loose85c = Join-Path $root85c 'loose85c'
    New-Item -ItemType Directory -Path $short85c, $none85c, $rec85c -Force | Out-Null
    git -C $r85c worktree add -q --detach $loose85c HEAD 2>&1 | Out-Null
    foreach ($dd in @($short85c, $none85c, $loose85c)) { Set-Content (Join-Path $dd 'big.txt') ('x' * 4096) }
    $P85c = Get-StreamPaths $r85c
    foreach ($dd in @($short85c, $none85c)) { Add-LineTo $P85c.Worktrees ("- G1.T116 | {0} | {1} | removal FAILED (directory still present)" -f $dd, (Get-Now)) }
    $now85c = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $j85c = J $r85c
    foreach ($t in $j85c.tasks) { if ($t.id -eq 'G1.T116') {
        $t.state = 'building'; $t.base = @{ worktree = $rec85c }
        $t.claim = @{ role = 'build'; session = 'build-85c'; at = $now85c; beat = $now85c } } }
    Set-Content -Path (Join-Path $r85c '.streams\tasks.json') -Encoding utf8 -Value ($j85c | ConvertTo-Json -Depth 50)
    $dirs85c = @($short85c, $none85c, $loose85c)
    $rdy85c = @(0..2 | ForEach-Object { Join-Path $Scratch "p85c-$_.ready" })
    $p85c = @(0..2 | ForEach-Object {
        Start-Process pwsh -PassThru -WindowStyle Hidden -WorkingDirectory $dirs85c[$_] -ArgumentList '-NoProfile', '-Command', "Set-Content -LiteralPath '$($rdy85c[$_])' -Value x; Start-Sleep -Seconds 90 # baseline in $($dirs85c[$_])\big.txt" })
    $w85c = 0; while (@($rdy85c | Where-Object { -not (Test-Path $_) }).Count -and $w85c -lt 200) { Start-Sleep -Milliseconds 100; $w85c++ }
    $a85c = @(& "$S\Invoke-Watchdog.ps1" -Repo $r85c -Session 'status-85c')
    $o85c = $a85c -join ' '
    $alive85c = @(0..2 | ForEach-Object { -not $p85c[$_].HasExited })
    foreach ($pp in $p85c) { try { $pp.Kill($true) } catch { }; [void]$pp.WaitForExit(15000) }
    git -C $r85c worktree prune 2>&1 | Out-Null
    Case 'watchdog: a tree named by the short task number of a live build claim (T116-serialbase for G1.T116) is kept, nothing killed' ((Test-Path $short85c) -and $alive85c[0] -and ($o85c -match 'KEPT .*T116-serialbase: G1\.T116 holds a live build claim') -and ($o85c -notmatch "KILLED pid $($p85c[0].Id)")) "present=$(Test-Path $short85c) alive=$($alive85c[0]) out=$($a85c -join ' | ')"
    Case 'watchdog: a failed-removal tree with a running process whose name points at no task is kept, nothing killed' ((Test-Path $none85c) -and $alive85c[1] -and ($o85c -match "KEPT .*scratch85c: 1 process\(es\) running out of it \(pid $($p85c[1].Id) .*points at no task") -and ($o85c -notmatch "KILLED pid $($p85c[1].Id)")) "present=$(Test-Path $none85c) alive=$($alive85c[1]) out=$($a85c -join ' | ')"
    Case 'watchdog: a registered orphan tree with a running process is kept, not reaped' ((Test-Path (Join-Path $loose85c 'big.txt')) -and $alive85c[2] -and ($o85c -match "KEPT .*loose85c: 1 process\(es\) running out of it \(pid $($p85c[2].Id) .*not reaped")) "present=$(Test-Path $loose85c) alive=$($alive85c[2]) out=$($a85c -join ' | ')"

    # 86. A -Live unit that wrote its result and then sat at the prompt (the mod's /exit swallowed by a background-task
    # notice) idled two builders until the build limit (kit item IN-20261005013311-b5a0). The runner ends it, with what it
    # started, -ResultGraceSeconds after the result lands, logs RESULT-GRACE as an ok run and does not back off.
    $r86 = New-Repo 'runner86' ([ordered]@{ 'G1.T' = (ContentGrader 'G1.T' 'done') }); $repos += $r86; Open-Gate $r86 stream-kit
    $ai86 = Join-Path $Scratch 'ai-stub86.ps1'; Set-Content -LiteralPath $ai86 -Value @('exit 0')
    $cl86 = Join-Path $Scratch 'claude-stub86.ps1'
    $pid86 = Join-Path $Scratch 'claude-stub86.child.txt'
    Set-Content -LiteralPath $cl86 -Value @(
        "`$c = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile','-Command','Start-Sleep -Seconds 120'"
        "`$c.Id | Set-Content -LiteralPath '$pid86'"
        "Set-Content -LiteralPath `$env:STREAM_UNIT_OUT -Value '{""result"":""stub86 built"",""is_error"":false,""num_turns"":3,""total_cost_usd"":0,""outcome"":""built""}'"
        'Start-Sleep -Seconds 120')
    $env:STREAM_RUNNER_AI = $ai86; $env:STREAM_RUNNER_CLAUDE = $cl86
    try {
        $t86 = Measure-Command {
            $job86 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 90 -ResultGraceSeconds 3 -MaxRuns 1 } -ArgumentList $S, $r86
            $null = Wait-Job $job86 -Timeout 60
            $o86 = @(Receive-Job $job86 -Keep 2>&1); Stop-Job $job86 -ErrorAction SilentlyContinue; Remove-Job $job86 -Force -ErrorAction SilentlyContinue
        }
    } finally { Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue }
    $child86 = if (Test-Path $pid86) { [int](Get-Content -Raw $pid86) } else { 0 }
    $alive86 = $child86 -and (Get-Process -Id $child86 -ErrorAction SilentlyContinue)
    if ($alive86) { Stop-Process -Id $child86 -Force -ErrorAction SilentlyContinue }
    $j86 = ($o86 -join "`n")
    Case 'runner -Live: a unit still running after its result is ended at the grace, ok, with no backoff' (($j86 -match ' EXIT RESULT-GRACE outcome built .* ok -> ') -and ($j86 -notmatch 'BACKOFF') -and $t86.TotalSeconds -lt 45) "seconds=$([int]$t86.TotalSeconds) out=$($o86 -join ' | ')"
    Case 'runner -Live: the grace end also stops what the unit started' ($child86 -and -not $alive86) "child=$child86 alive=$([bool]$alive86)"

    # ---- 87. a -Live unit waiting on a permission prompt is waiting on the owner, not hung (2026-10-04: a builder sat 90
    # minutes on a prompt nobody knew about until its timeout killed it). While the stream-unit mod's
    # <result>.waiting.json says waiting, the unit timeout is paused, the Wave block is retitled '<tab> - NEEDS YOU' and badged, the state
    # says 'waiting on owner' and owner\questions.md gets one ESCALATE line; once answered the title goes back and the
    # line is re-written RESOLVED. The unit sees STREAM_UNIT_TAB. The stub waits 8 s on a 4 s limit and still ends ok.
    $r87 = New-Repo 'runner87' ([ordered]@{ 'G1.T' = (ContentGrader 'G1.T' 'done') }); $repos += $r87; Open-Gate $r87 stream-kit
    $ai87 = Join-Path $Scratch 'ai-stub87.ps1'; Set-Content -LiteralPath $ai87 -Value @('exit 0')
    $cl87 = Join-Path $Scratch 'claude-stub87.ps1'; $tab87 = Join-Path $Scratch 'claude-stub87.tab.txt'
    $wz87 = Join-Path $Scratch 'wsh-stub87.ps1'; $wzLog87 = Join-Path $Scratch 'wsh-stub87.log'
    $st87 = Join-Path $Scratch 'claude-stub87.state.txt'
    Set-Content -LiteralPath $wz87 -Value @("Add-Content -LiteralPath '$wzLog87' -Value (`$args -join ' ')")
    Set-Content -LiteralPath $cl87 -Value @(
        "Set-Content -LiteralPath '$tab87' -Value `$env:STREAM_UNIT_TAB"
        'Start-Sleep -Seconds 1'
        "Set-Content -LiteralPath (`$env:STREAM_UNIT_OUT + '.waiting.json') -Value '{""waiting"":true,""since"":1,""count"":1,""tool"":""Bash"",""reason"":""destructive-path-guard: stub87""}'"
        'Start-Sleep -Seconds 20'
        "Get-ChildItem (Join-Path '$r87' '.streams\runners') -Filter 'runner-*.json' | ForEach-Object { Get-Content -Raw `$_.FullName } | Set-Content -LiteralPath '$st87'"
        'Start-Sleep -Seconds 20'
        "Set-Content -LiteralPath (`$env:STREAM_UNIT_OUT + '.waiting.json') -Value '{""waiting"":false,""at"":2}'"
        'Start-Sleep -Seconds 2'
        "Set-Content -LiteralPath `$env:STREAM_UNIT_OUT -Value '{""result"":""stub87 built"",""is_error"":false,""num_turns"":2,""total_cost_usd"":0,""outcome"":""built""}'"
        'exit 0')
    $prevPane87 = $env:WEZTERM_PANE; $prevBlock87 = $env:WAVETERM_BLOCKID; $prevWt87 = $env:WT_SESSION
    Remove-Item Env:\WT_SESSION -ErrorAction SilentlyContinue
    $env:STREAM_RUNNER_AI = $ai87; $env:STREAM_RUNNER_CLAUDE = $cl87; $env:STREAM_RUNNER_WSH = $wz87; $env:WAVETERM_BLOCKID = 'block85'
    Remove-Item Env:\WEZTERM_PANE -ErrorAction SilentlyContinue
    try {
        # 30 s limit against 40 s waiting on the prompt: the wait alone still outlasts the limit, so the case still proves
        # that waiting time is not counted. The old 4 s limit left no room for a cold pwsh start on a loaded host, and the
        # unit ended TIMEOUT before its result (2026-10-17, host at 100% CPU).
        $job87 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 30 -MaxRuns 1 -Tab 'Builder 9' } -ArgumentList $S, $r87
        $null = Wait-Job $job87 -Timeout 300
        $o87 = @(Receive-Job $job87 -Keep); Stop-Job $job87 -ErrorAction SilentlyContinue; Remove-Job $job87 -Force -ErrorAction SilentlyContinue
    } finally {
        Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE, Env:\STREAM_RUNNER_WSH -ErrorAction SilentlyContinue
        if ($null -ne $prevPane87) { $env:WEZTERM_PANE = $prevPane87 } else { Remove-Item Env:\WEZTERM_PANE -ErrorAction SilentlyContinue }
        if ($null -ne $prevBlock87) { $env:WAVETERM_BLOCKID = $prevBlock87 } else { Remove-Item Env:\WAVETERM_BLOCKID -ErrorAction SilentlyContinue }
        if ($null -ne $prevWt87) { $env:WT_SESSION = $prevWt87 }
    }
    $j87 = ($o87 -join "`n")
    $titles87 = if (Test-Path $wzLog87) { @(Get-Content $wzLog87) } else { @() }
    $q87 = @(Get-Content (Join-Path $r87 '.streams\owner\permission-prompts.md') -ErrorAction SilentlyContinue | Where-Object { $_ -match 'ESCALATE kit-' })
    $qq87 = @(Get-Content (Join-Path $r87 '.streams\owner\questions.md') -ErrorAction SilentlyContinue | Where-Object { $_ -match 'ESCALATE kit-' })
    $mid87 = if (Test-Path $st87) { Get-Content -Raw $st87 } else { '' }
    Case 'runner -Live: time on an open permission prompt does not count toward the unit limit' (($j87 -match ' EXIT 0 outcome built .* ok -> ') -and ($j87 -notmatch 'TIMEOUT')) "out=$($o87 -join ' | ')"
    Case 'runner -Live: a prompt retitles the Wave block NEEDS YOU with a bell badge, and the answer puts both back' (($titles87 -join '|') -eq 'setmeta -b this frame:title=Builder 9|setmeta -b this frame:title=Builder 9|setmeta -b this frame:title=Builder 9 - NEEDS YOU|badge bell --color #e5484d --beep|setmeta -b this frame:title=Builder 9|badge --clear|setmeta -b this frame:title=Builder 9') "calls=$($titles87 -join ' | ')"
    Case 'runner -Live: the state says waiting on owner while the prompt is open' ($mid87 -match 'waiting on owner since .*destructive-path-guard: stub87') "state=$mid87"
    Case 'runner -Live: the prompt line goes to permission-prompts.md, never to the owner questions' ($qq87.Count -eq 0) "questions=$($qq87 -join ' | ')"
    Case 'runner -Live: one ESCALATE line in the owner queue, re-written RESOLVED once answered' (($q87.Count -eq 1) -and ($q87[0] -match '^RESOLVED - ESCALATE kit-\S+ \| permission prompt in tab Builder 9 : Bash: destructive-path-guard: stub87 \|.*\(answered ')) "queue=$($q87 -join ' | ')"
    Case 'runner -Live: the RESOLVED stamp is local time with the zone, not UTC' (($q87.Count -eq 1) -and ($q87[0] -match '\(answered \d{4}-\d\d-\d\d \d\d:\d\d [A-Za-z]+\)$')) "queue=$($q87 -join ' | ')"
    Case 'runner -Live: the unit sees STREAM_UNIT_TAB' ((Test-Path $tab87) -and ((Get-Content -Raw $tab87).Trim() -eq 'Builder 9')) "tab=$(if (Test-Path $tab87) { Get-Content -Raw $tab87 })"
    # ---- 88. the same waiting signal in a Windows Terminal tab (WT_SESSION): the runner retitles the tab through the
    # console title: '<tab>' at start and again before and after each unit (every pwsh started in the console, such as the
    # launch check's, retitles it), '<tab> - NEEDS YOU' on a prompt and '<tab>' once answered, whatever Wave or WezTerm env the tab inherited.
    $r88 = New-Repo 'runner88' ([ordered]@{ 'G1.T' = (ContentGrader 'G1.T' 'done') }); $repos += $r88; Open-Gate $r88 stream-kit
    $ai88 = Join-Path $Scratch 'ai-stub88.ps1'; Set-Content -LiteralPath $ai88 -Value @('exit 0')
    $cl88 = Join-Path $Scratch 'claude-stub88.ps1'; $log88 = Join-Path $Scratch 'wt-title88.log'
    Set-Content -LiteralPath $cl88 -Value @(
        "Set-Content -LiteralPath (`$env:STREAM_UNIT_OUT + '.waiting.json') -Value '{""waiting"":true,""since"":1,""count"":1,""tool"":""Bash"",""reason"":""stub88""}'"
        'Start-Sleep -Seconds 3'
        "Set-Content -LiteralPath (`$env:STREAM_UNIT_OUT + '.waiting.json') -Value '{""waiting"":false,""at"":2}'"
        'Start-Sleep -Seconds 2'
        "Set-Content -LiteralPath `$env:STREAM_UNIT_OUT -Value '{""result"":""stub88 built"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0,""outcome"":""built""}'"
        'exit 0')
    $prev88 = @{ WT = $env:WT_SESSION; Block = $env:WAVETERM_BLOCKID; Pane = $env:WEZTERM_PANE }
    $env:STREAM_RUNNER_AI = $ai88; $env:STREAM_RUNNER_CLAUDE = $cl88; $env:STREAM_RUNNER_TITLE_LOG = $log88
    $env:WT_SESSION = 'wt88'; $env:WAVETERM_BLOCKID = 'block88'; $env:WEZTERM_PANE = '88'
    try {
        $job88 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 60 -MaxRuns 1 -Tab 'Author 4' } -ArgumentList $S, $r88
        $null = Wait-Job $job88 -Timeout 90
        $o88 = @(Receive-Job $job88 -Keep); Stop-Job $job88 -ErrorAction SilentlyContinue; Remove-Job $job88 -Force -ErrorAction SilentlyContinue
    } finally {
        Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE, Env:\STREAM_RUNNER_TITLE_LOG -ErrorAction SilentlyContinue
        foreach ($k in @(@('WT_SESSION', 'WT'), @('WAVETERM_BLOCKID', 'Block'), @('WEZTERM_PANE', 'Pane'))) {
            if ($null -ne $prev88[$k[1]]) { Set-Item -Path "Env:$($k[0])" -Value $prev88[$k[1]] } else { Remove-Item -Path "Env:$($k[0])" -ErrorAction SilentlyContinue }
        }
    }
    $t88 = if (Test-Path $log88) { @(Get-Content $log88) } else { @() }
    Case 'runner -Live: in Windows Terminal the runner names its tab at start, a prompt retitles the tab NEEDS YOU and the answer puts the name back' ((($t88 -join '|') -eq 'Author 4|Author 4|Author 4 - NEEDS YOU|Author 4|Author 4') -and (($o88 -join "`n") -match ' EXIT 0 outcome built .* ok -> ')) "titles=$($t88 -join ' | ') out=$($o88 -join ' | ')"
    # 89. Status agrees with the watchdog on an integration row: G3.T900, set building by the integrator f13d2669 while it
    # beat a fresh lock, showed 'orphaned, no watchdog will free it' for 49 min although the watchdog keeps such a row on
    # purpose (case 63; kit item IN-20261005020647-63c2). Kept: not orphaned, no flag, the page names the integrator.
    # Once another session holds the lock, the row is orphaned again, in status as in the watchdog.
    $r89 = New-Repo 'r89' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r89
    $old89 = (Get-Date).ToUniversalTime().AddMinutes(-60).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $j89 = J $r89
    $j89.tasks = @($j89.tasks) + , ([ordered]@{ id = 'G1.I'; group = 'G1'; title = 'G1 integration'; why = @('AC-1'); kind = 'integration'; state = 'building'; writeSet = @(); dependsOn = @(); claim = $null; estMinutes = 90
        artifacts = [ordered]@{ ticket = $null; grader = $null; patch = $null; verdict = $null }
        history = @([ordered]@{ at = $old89; by = 'integ-89'; to = 'ticketed'; note = 'added' }, [ordered]@{ at = $old89; by = 'integ-89'; to = 'building'; note = 'step B run 1' }) })
    Set-Content -Path (Join-Path $r89 '.streams\tasks.json') -Encoding utf8 -Value ($j89 | ConvertTo-Json -Depth 50)
    $lock89 = Join-Path $r89 '.streams\integrator.lock'
    Set-Content -Path $lock89 -Value (@{ session = 'integ-89'; at = $old89; beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json)
    $m89 = & "$S\Get-StreamStatus.ps1" -Repo $r89 -Json | ConvertFrom-Json
    $t89 = @($m89.tasks | Where-Object { $_.id -eq 'G1.I' })[0]
    $page89 = Join-Path $r89 '.streams\status.html'
    $null = & "$S\Build-StatusPage.ps1" -Repo $r89 -Session status-89 -Out $page89 -MirrorFile (Join-Path $Scratch 'no-mirror89.txt')
    $html89 = if (Test-Path $page89) { Get-Content -Raw $page89 } else { '' }
    Case 'status: an integration row its live integrator set building is not orphaned and not flagged' ((-not $t89.orphaned) -and ([string]$t89.integratorHold -match '^integrator integ-89 \(lock beat 0 min\)') -and -not (@($m89.flags) -match 'G1\.I .*orphaned') -and ($html89 -match 'integrator integ-89') -and ($html89 -notmatch '>orphaned<')) "orphaned=$($t89.orphaned) hold='$($t89.integratorHold)' flags=$(@($m89.flags) -join ' / ')"
    Set-Content -Path $lock89 -Value (@{ session = 'other-89'; at = $old89; beat = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json)
    $m89b = & "$S\Get-StreamStatus.ps1" -Repo $r89 -Json | ConvertFrom-Json
    $t89b = @($m89b.tasks | Where-Object { $_.id -eq 'G1.I' })[0]
    Case 'status: the same row is orphaned once another session holds the lock' ($t89b.orphaned -and -not $t89b.integratorHold -and (@($m89b.flags) -match 'G1\.I .*orphaned')) "orphaned=$($t89b.orphaned) flags=$(@($m89b.flags) -join ' / ')"

    # ---- 90. dead runner state files (SMVMTR1 2026-10-05: 60 left behind by consoles closed under their runners). A
    # runner is live only while its pid is a pwsh that started no later than the state's 'started'. A pid now held by
    # another program, or by a pwsh started after the runner, is a recycled pid: that runner is dead, its unit is ended
    # and its claim is broken. The watchdog moves every dead runner's state file to logs\runner\<runner>\state.json and
    # leaves the live runner's file and the STOP file in place.
    $r90 = New-Repo 'r90' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok'); 'G1.B' = (ContentGrader 'G1.B' 'ok') }); $repos += $r90
    $log90 = Join-Path $r90 '.streams\logs\runner\runner-build-90'; New-Item -ItemType Directory -Path $log90 -Force | Out-Null
    foreach ($u90 in @('build-90live', 'build-90recycled')) { Set-Content (Join-Path $log90 "20261005T120000Z-$u90.rules.txt") 'rules' }
    $dead90 = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', 'exit 0' -WindowStyle Hidden -PassThru; $dead90.WaitForExit()
    $other90 = Start-Process cmd -ArgumentList '/c', 'ping -n 60 127.0.0.1 >nul' -WindowStyle Hidden -PassThru
    try {
        $run90 = Join-Path $r90 '.streams\runners'; New-Item -ItemType Directory -Path $run90 -Force | Out-Null
        $now90 = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        Set-Content (Join-Path $run90 'runner-build-90live.json') ([ordered]@{ role = 'build'; pid = $PID; started = $now90; session = 'build-90live'; status = 'running build-90live' } | ConvertTo-Json)
        Set-Content (Join-Path $run90 'runner-build-90dead.json') ([ordered]@{ role = 'build'; pid = $dead90.Id; started = $now90; session = 'build-90dead'; status = 'starting' } | ConvertTo-Json)
        Set-Content (Join-Path $run90 'runner-build-90recycled.json') ([ordered]@{ role = 'build'; pid = $other90.Id; started = $now90; session = 'build-90recycled'; status = 'running build-90recycled' } | ConvertTo-Json)
        Set-Content (Join-Path $run90 'runner-build-90old.json') ([ordered]@{ role = 'build'; pid = $PID; started = '2020-01-01T00:00:00Z'; session = 'build-90old'; status = 'idle since 2020-01-01T00:10:00Z' } | ConvertTo-Json)
        Set-Content (Join-Path $run90 'STOP-build') 'test 90'
        $doc90 = J $r90
        $claims90 = @{ 'G1.A' = 'build-90recycled'; 'G1.B' = 'build-90live' }
        foreach ($t in $doc90.tasks) { $t.state = 'building'; $t.claim = @{ role = 'build'; session = $claims90[$t.id]; at = $now90; beat = $now90 } }
        Set-Content -Path (Join-Path $r90 '.streams\tasks.json') -Encoding utf8 -Value ($doc90 | ConvertTo-Json -Depth 50)
        $w90 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r90 -Session status-90)
    } finally { Stop-Process -Id $other90.Id -Force -ErrorAction SilentlyContinue }
    $left90 = @(Get-ChildItem $run90 -File | ForEach-Object Name | Sort-Object)
    $moved90 = @('runner-build-90dead', 'runner-build-90recycled', 'runner-build-90old' | Where-Object { Test-Path (Join-Path $r90 ".streams\logs\runner\$_\state.json") })
    $a90 = T $r90 'G1.A'; $b90 = T $r90 'G1.B'
    Case 'watchdog: dead runner state files move to logs\runner\<runner>\state.json; the live runner''s file and the STOP file stay' ((($left90 -join ',') -eq 'runner-build-90live.json,STOP-build') -and $moved90.Count -eq 3 -and (($w90 -join "`n") -match 'MOVED 3 dead runner state file')) "left=$($left90 -join ',') moved=$($moved90 -join ',') out=$($w90 -join ' | ')"
    Case 'watchdog: a runner whose pid now belongs to another program is dead: its unit''s claim is broken, the live runner''s claim stays' ((-not $a90.claim) -and $a90.state -eq 'ticketed' -and $b90.claim.session -eq 'build-90live') "a=$($a90.state) $($a90.claim | ConvertTo-Json -Compress) b=$($b90.claim | ConvertTo-Json -Compress)"

    # ---- 91. cost parsing (spec 3.5). Assistant lines repeat per message.id with identical usage (measured 2026-10-05:
    # 10 lines, 6 ids), so one id counts once; a truncated last line is left for the next read; a dated model id prices
    # by prefix; an unknown model prices to null; the timestamp stays the transcript's ISO UTC string.
    . "$S\lib\Cost.ps1"
    $cdir = Join-Path $Scratch 'cost'; New-Item -ItemType Directory -Path $cdir -Force | Out-Null
    $prices = Read-Prices (Join-Path $S 'cost-prices.json')
    $u = @{ in = 1000000; out = 0; cacheRead = 0; cacheWrite5m = 0; cacheWrite1h = 0 }
    Case '91 prices by exact model' ((ConvertTo-Usd $prices 'claude-opus-5-5' $u) -eq 4.0)
    Case '91 prices a dated model id by prefix' ((ConvertTo-Usd $prices 'claude-haiku-4-5-20251001' $u) -eq 1.0)
    Case '91 unknown model prices to null' ($null -eq (ConvertTo-Usd $prices 'claude-unknown-9' $u))
    $line = { param($id, $out) '{"type":"assistant","sessionId":"S1","timestamp":"2026-10-05T01:00:00.000Z","message":{"id":"' + $id + '","model":"claude-opus-5-5","usage":{"input_tokens":2,"output_tokens":' + $out + ',"cache_read_input_tokens":100,"cache_creation_input_tokens":50,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":50}}}}' }
    $tf = Join-Path $cdir 't.jsonl'
    $text = ('{"type":"user","sessionId":"S1","timestamp":"2026-10-05T00:59:00.000Z","message":{"role":"user"}}' + "`n" + (& $line 'm1' 10) + "`n" + (& $line 'm1' 10) + "`n" + (& $line 'm2' 20) + "`n" + '{"type":"assistant","sessionId":"S1","timestamp":"2026-10-05T01:00:05.000Z","message":{"id":"m3","model":"claude-opus-5-5","usage":{"input_tokens":1,"output_tok')
    [IO.File]::WriteAllText($tf, $text)
    # -Flush: these cases are about dedupe and the partial last line; the hold of the newest message is block 94.
    $r1 = Read-TranscriptUsage $tf 0 -Flush
    Case '91 repeated message ids count once' (@($r1.rows).Count -eq 2 -and $r1.rows[0].messageId -eq 'm1' -and $r1.rows[1].out -eq 20) (@($r1.rows).Count)
    Case '91 a truncated last line is left for the next read' ($r1.offset -lt (Get-Item $tf).Length -and $r1.lastMessageId -eq 'm2') "$($r1.offset)"
    [IO.File]::AppendAllText($tf, 'ens":5,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' + "`n" + (& $line 'm2' 20) + "`n")
    $r2 = Read-TranscriptUsage $tf $r1.offset $r1.lastMessageId -Flush
    Case '91 the next read resumes at the cursor and skips the id already counted' (@($r2.rows).Count -eq 1 -and $r2.rows[0].messageId -eq 'm3' -and $r2.offset -eq (Get-Item $tf).Length) (($r2.rows | ForEach-Object { $_.messageId }) -join ',')
    Case '91 token classes are read' ($r1.rows[0].cacheRead -eq 100 -and $r1.rows[0].cacheWrite1h -eq 50 -and $r1.rows[0].cacheWrite5m -eq 0)
    Case '91 the row time is the transcript ISO UTC string, not a local DateTime' ($r1.rows[0].at -eq '2026-10-05T01:00:00.000Z') "$($r1.rows[0].at)"

    # The newest message of a file is held back until the file has been quiet STREAM_COST_QUIET_MINUTES (block 94);
    # 0 flushes at once, so these cases count every message on the first read.
    $env:STREAM_COST_QUIET_MINUTES = '0'
    # ---- 92. cost ledger: incremental, attributed by runner result -> stream session -> task history, unattributed kept.
    # Claude names a project folder by the repo path with EACH non-alphanumeric character as '-' (C:\devops -> C--devops).
    $crp = Join-Path $Scratch 'costrepo'; New-Item -ItemType Directory -Path $crp -Force | Out-Null
    git -C $crp init -q -b main; git -C $crp config user.email t@t; git -C $crp config user.name t
    & "$S\Init-Streams.ps1" -Repo $crp | Out-Null
    $cproot = Join-Path $Scratch 'projects'
    $cproj = Join-Path $cproot ((Resolve-Path $crp).Path -replace '[^A-Za-z0-9]', '-'); New-Item -ItemType Directory -Path "$cproj\S-A\subagents" -Force | Out-Null
    $cdoc = @{ groups = @(@{ id = 'G1'; name = 'g'; state = 'released'; origin = 'plan'; scope = @{ include = @('F') } })
        tasks = @(@{ id = 'G1.T1'; group = 'G1'; title = 't'; why = @('AC'); kind = 'code'; writeSet = @('a.txt'); dependsOn = @(); estMinutes = 5; state = 'built'; claim = $null; artifacts = @{}
            history = @(@{ at = '2026-10-05T01:00:00Z'; by = 'build-1'; to = 'building'; note = 'claimed' }, @{ at = '2026-10-05T01:30:00Z'; by = 'build-1'; to = 'built'; note = 'done' }) }) }
    $cdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $crp '.streams\tasks.json') -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $crp '.streams\logs\runner\runner-build-1') -Force | Out-Null
    '{"type":"result","session":"build-1","role":"build","session_id":"S-A","outcome":"built","total_cost_usd":1.0,"started_at_ms":1791162000000,"ended_at_ms":1791163800000}' | Set-Content (Join-Path $crp '.streams\logs\runner\runner-build-1\u1-build-1.json')
    $mk = { param($sid, $id, $at, $out) '{"type":"assistant","sessionId":"' + $sid + '","timestamp":"' + $at + '","message":{"id":"' + $id + '","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":' + $out + ',"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0}}}}' }
    $mkSub = { param($sid, $id, $at, $out) '{"type":"assistant","isSidechain":true,"agentId":"x","sessionId":"' + $sid + '","timestamp":"' + $at + '","message":{"id":"' + $id + '","model":"claude-opus-5-5","usage":{"input_tokens":0,"output_tokens":' + $out + ',"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}' }
    [IO.File]::WriteAllText("$cproj\S-A.jsonl", (& $mk 'S-A' 'a1' '2026-10-05T01:10:00.000Z' 1000000) + "`n")
    [IO.File]::WriteAllText("$cproj\S-A\subagents\agent-x.jsonl", (& $mkSub 'S-A' 'x1' '2026-10-05T01:12:00.000Z' 500000) + "`n")
    [IO.File]::WriteAllText("$cproj\S-Z.jsonl", (& $mk 'S-Z' 'z1' '2026-10-05T02:00:00.000Z' 100000) + "`n")
    $c1 = & "$S\Get-StreamCost.ps1" -Repo $crp -ProjectsRoot $cproot -Json | ConvertFrom-Json
    $led = @(Get-Content (Join-Path $crp '.streams\cost\ledger.jsonl') -ErrorAction SilentlyContinue | ForEach-Object { $_ | ConvertFrom-Json })
    Case '92 one ledger row per message, subagent folder included' ($led.Count -eq 3) ($led.Count)
    $a1 = $led | Where-Object { $_.sessionId -eq 'S-A' -and -not $_.agentId }
    Case '92 a runner unit is attributed to its stream session, task and group' ($a1.streamSession -eq 'build-1' -and $a1.role -eq 'build' -and $a1.task -eq 'G1.T1' -and $a1.group -eq 'G1' -and $a1.usd -eq 20.0) ($a1 | ConvertTo-Json -Compress)
    $x1 = $led | Where-Object { $_.agentId }
    Case '92 a subagent row carries the parent attribution' ($x1.task -eq 'G1.T1' -and $x1.usd -eq 10.0) ($x1 | ConvertTo-Json -Compress)
    $z1 = $led | Where-Object { $_.sessionId -eq 'S-Z' }
    Case '92 an unknown session is kept as unattributed' ($z1.streamSession -eq '-' -and $z1.role -eq 'unattributed' -and $z1.task -eq '-') ($z1 | ConvertTo-Json -Compress)
    Case '92 summary totals and buckets' ([double]$c1.total -eq 32.0 -and [double]$c1.byRole.build -eq 30.0 -and [double]$c1.unattributed -eq 2.0 -and [double]$c1.byTask.'G1.T1' -eq 30.0) ($c1 | ConvertTo-Json -Compress -Depth 5)
    $c2 = & "$S\Get-StreamCost.ps1" -Repo $crp -ProjectsRoot $cproot -Json | ConvertFrom-Json
    Case '92 a second run adds nothing' ([int]$c2.added -eq 0 -and @(Get-Content (Join-Path $crp '.streams\cost\ledger.jsonl')).Count -eq 3) "$($c2.added)"
    [IO.File]::AppendAllText("$cproj\S-A.jsonl", (& $mk 'S-A' 'a2' '2026-10-05T01:20:00.000Z' 100000) + "`n")
    $c3 = & "$S\Get-StreamCost.ps1" -Repo $crp -ProjectsRoot $cproot -Json | ConvertFrom-Json
    Case '92 a third run adds only the new message' ([int]$c3.added -eq 1 -and [double]$c3.total -eq 34.0) ($c3 | ConvertTo-Json -Compress -Depth 3)

    # ---- 93. cost page: tables from summary.json, no model tokens, flags from the rules.
    $cpg = Join-Path $Scratch 'cost.html'
    $cp = @(& "$S\Build-CostPage.ps1" -Repo $crp -Session status-c -Out $cpg)
    $cph = if (Test-Path $cpg) { Get-Content -Raw $cpg } else { '' }
    Case '93 the page is written and announced' (($cp -join ' ') -match '^COST-PAGE' -and (Test-Path $cpg)) ($cp -join ' | ')
    Case '93 the page shows the total, the notional banner and the price version' ($cph -match 'notional' -and $cph -match '\$34\.00' -and $cph -match '2026-10-06') "notional=$($cph -match 'notional') total=$($cph -match '\$34\.00') version=$(([regex]::Match($cph, 'version[^<]{0,80}')).Value)"
    Case '93 the page lists roles, groups and top tasks' ($cph -match '>build<' -and $cph -match '>G1<' -and $cph -match 'G1\.T1')
    Case '93 unattributed share above 5% raises a flag' ($cph -match 'class="flag[^"]*">unattributed 5\.9%')
    Case '93 the page closes the head''s wrapper' ($cph.TrimEnd().EndsWith('</div></body></html>'))
    # Owner ruling (kit item IN-20261019004254-2880): owner-facing times read in local machine time with the zone.
    $cpMeta = ([regex]::Match($cph, '<h1>Speedy stream cost</h1><p class="muted">[^<]*')).Value
    Case '93 LOCAL-TIME: the page header time is local with the zone, no UTC stamp' ($cpMeta -match '<p class="muted">\d{4}-\d\d-\d\d \d\d:\d\d [A-Za-z]{2,6} &middot; notional' -and $cpMeta -notmatch '\d\d:\d\d(:\d\d)?(\.\d+)?Z') $cpMeta

    # ---- 94. cost ledger hardening (final review I4-I6, M1-M3).
    # I4: a message's usage line repeats and GROWS (measured: output 16 then 190 for one id). The newest message of a
    # file is held back (its first line is the cursor) until a later message starts or the file has been quiet, so the
    # last line of a message always wins, even when its lines straddle two reads.
    $g4 = Join-Path $cdir 'grow.jsonl'
    [IO.File]::WriteAllText($g4, (& $line 'g1' 16) + "`n")
    $q1 = Read-TranscriptUsage $g4 0
    Case '94 the newest message is held while the file may still grow' (@($q1.rows).Count -eq 0 -and $q1.offset -eq 0) "rows=$(@($q1.rows).Count) offset=$($q1.offset)"
    [IO.File]::AppendAllText($g4, (& $line 'g1' 190) + "`n" + (& $line 'g2' 5) + "`n")
    $q2 = Read-TranscriptUsage $g4 $q1.offset $q1.lastMessageId
    Case '94 a message that straddled the cursor counts its LAST usage line' (@($q2.rows).Count -eq 1 -and $q2.rows[0].messageId -eq 'g1' -and $q2.rows[0].out -eq 190) (($q2.rows | ForEach-Object { "$($_.messageId)=$($_.out)" }) -join ',')
    $q3 = Read-TranscriptUsage $g4 $q2.offset $q2.lastMessageId -Flush
    Case '94 a quiet file flushes its held message' (@($q3.rows).Count -eq 1 -and $q3.rows[0].messageId -eq 'g2' -and $q3.offset -eq (Get-Item $g4).Length) (($q3.rows | ForEach-Object { $_.messageId }) -join ',')
    # I5: a message long after the session's last move on its task is not charged to that task.
    [IO.File]::AppendAllText("$cproj\S-A.jsonl", (& $mk 'S-A' 'a3' '2026-10-05T05:00:00.000Z' 100000) + "`n")
    # I6: a headless (-p) result carries session_id only; the stream session comes from the result file name
    # (<stamp>-<session>.json) and the role from its prefix, coord- included.
    New-Item -ItemType Directory -Path (Join-Path $crp '.streams\logs\runner\runner-author-2') -Force | Out-Null
    '{"type":"result","session_id":"S-B","total_cost_usd":0.5}' | Set-Content (Join-Path $crp '.streams\logs\runner\runner-author-2\20261005T030000Z-author-ab12.json')
    New-Item -ItemType Directory -Path (Join-Path $crp '.streams\logs\runner\runner-coordinator-1') -Force | Out-Null
    '{"type":"result","session_id":"S-C","total_cost_usd":0.5}' | Set-Content (Join-Path $crp '.streams\logs\runner\runner-coordinator-1\20261005T030000Z-coord-202610050300.json')
    [IO.File]::WriteAllText("$cproj\S-B.jsonl", (& $mk 'S-B' 'b1' '2026-10-05T03:05:00.000Z' 100000) + "`n")
    [IO.File]::WriteAllText("$cproj\S-C.jsonl", (& $mk 'S-C' 'c1' '2026-10-05T03:05:00.000Z' 100000) + "`n")
    # M2: a file that cannot be opened is skipped and reported; every other file is still read. S-Z gets a new message
    # first, so it has unread bytes while it is locked.
    [IO.File]::AppendAllText("$cproj\S-Z.jsonl", (& $mk 'S-Z' 'z2' '2026-10-05T03:10:00.000Z' 100000) + "`n")
    # A just-written file can be held a moment by the virus scanner or the indexer: retry the exclusive open.
    $lockFs = $null; for ($i = 0; -not $lockFs -and $i -lt 50; $i++) { try { $lockFs = [IO.File]::Open("$cproj\S-Z.jsonl", [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) } catch { Start-Sleep -Milliseconds 200 } }
    try { $c4out = @(& "$S\Get-StreamCost.ps1" -Repo $crp -ProjectsRoot $cproot) } finally { $lockFs.Dispose() }
    $led4 = @(Get-Content (Join-Path $crp '.streams\cost\ledger.jsonl') | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })
    $a3 = $led4 | Where-Object { $_.sessionId -eq 'S-A' -and ([string]$_.at).StartsWith('2026-10-05T05') }
    Case '94 spend long after the session''s last move on its task is not charged to the task' ($a3 -and $a3.task -eq '-' -and $a3.role -eq 'build' -and $a3.streamSession -eq 'build-1') ($a3 | ConvertTo-Json -Compress)
    $b1 = $led4 | Where-Object { $_.sessionId -eq 'S-B' }
    Case '94 a headless result maps its session from the file name and its role from the prefix' ($b1 -and $b1.streamSession -eq 'author-ab12' -and $b1.role -eq 'author') ($b1 | ConvertTo-Json -Compress)
    $c1x = $led4 | Where-Object { $_.sessionId -eq 'S-C' }
    Case '94 a coord- session is the coordinator' ($c1x -and $c1x.role -eq 'coordinator') ($c1x | ConvertTo-Json -Compress)
    Case '94 a locked file is skipped and reported, the rest is read' ((($c4out -join ' ') -match 'SKIP .*S-Z') -and $b1 -and $c1x -and -not ($led4 | Where-Object { $_.messageId -eq 'z2' })) ($c4out -join ' | ')
    # M1: a second run while one holds the ledger lock does nothing; a ledger longer than the cursor recorded (a crash
    # between the append and the cursor write) is cut back before the next append.
    $rows94 = @(Get-Content (Join-Path $crp '.streams\cost\ledger.jsonl')).Count
    $lk = [IO.File]::Open((Join-Path $crp '.streams\cost\cost.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try { $busy94 = @(& "$S\Get-StreamCost.ps1" -Repo $crp -ProjectsRoot $cproot); $busyCode = $LASTEXITCODE } finally { $lk.Dispose() }
    Case '94 a concurrent run prints COST-BUSY and writes nothing' ($busyCode -eq 4 -and ($busy94 -join ' ') -match 'COST-BUSY' -and @(Get-Content (Join-Path $crp '.streams\cost\ledger.jsonl')).Count -eq $rows94) "exit=$busyCode $($busy94 -join ' | ')"
    [IO.File]::AppendAllText((Join-Path $crp '.streams\cost\ledger.jsonl'), (Get-Content (Join-Path $crp '.streams\cost\ledger.jsonl') | Select-Object -First 1) + "`n")
    [void](& "$S\Get-StreamCost.ps1" -Repo $crp -ProjectsRoot $cproot)
    $rows94b = @(Get-Content (Join-Path $crp '.streams\cost\ledger.jsonl')).Count
    Case '94 a ledger tail the cursor never recorded is cut back, not counted twice' ($rows94b -eq $rows94 + 1) "before=$rows94 after=$rows94b (+1 = z2, now readable)"
    # M3: the default projects folder follows CLAUDE_CONFIG_DIR; a missing project folder is reported, not silent.
    $prevCfg = $env:CLAUDE_CONFIG_DIR
    try {
        $env:CLAUDE_CONFIG_DIR = Join-Path $Scratch 'cfg-none'
        $np = @(& "$S\Get-StreamCost.ps1" -Repo $crp)
        Case '94 a missing project folder prints NO-PROJECT' (($np -join ' ') -match 'NO-PROJECT .*cfg-none') ($np -join ' | ')
        $env:CLAUDE_CONFIG_DIR = Join-Path $Scratch 'cfg-real'
        New-Item -ItemType Directory -Path (Join-Path $env:CLAUDE_CONFIG_DIR 'projects') -Force | Out-Null
        Copy-Item -Recurse $cproj (Join-Path $env:CLAUDE_CONFIG_DIR 'projects')
        $cp2 = @(& "$S\Get-StreamCost.ps1" -Repo $crp)
        Case '94 the default projects folder is CLAUDE_CONFIG_DIR\projects' (($cp2 -join ' ') -match '\((\d+) files\)' -and [int]$Matches[1] -gt 0) ($cp2 -join ' | ')
    } finally { if ($null -ne $prevCfg) { $env:CLAUDE_CONFIG_DIR = $prevCfg } else { [Environment]::SetEnvironmentVariable('CLAUDE_CONFIG_DIR', $null) } }
    [Environment]::SetEnvironmentVariable('STREAM_COST_QUIET_MINUTES', $null)
    # ---- 95. group activation (2026-10-05 priority-focus-design 3.2): freshness, known failures, gates up front.
    # Main history: base at 10-01 (a,b,c,d,e,g); at 10-03 a.txt, d.txt and e.txt change. Every ticket was written 10-02.
    # A1.K (b.txt) is fresh; A1.S (a.txt) is stale on its own file; A1.D (c.txt) is stale through its dependency A1.Z
    # (d.txt); A1.C (e.txt) is stale but a live claim holds it.
    $ar = Join-Path $Scratch 'actrepo'; New-Item -ItemType Directory -Path $ar -Force | Out-Null; $repos += $ar
    git -C $ar init -q -b main; git -C $ar config user.email t@t; git -C $ar config user.name t; Grant-GitPolicy $ar
    foreach ($f in 'a', 'b', 'c', 'd', 'e', 'g') { Set-Content (Join-Path $ar "$f.txt") "$f base" }
    $env:GIT_COMMITTER_DATE = '2026-10-01T00:00:00Z'; $env:GIT_AUTHOR_DATE = '2026-10-01T00:00:00Z'
    git -C $ar add -A; git -C $ar commit -q -m base
    foreach ($f in 'a', 'd', 'e') { Set-Content (Join-Path $ar "$f.txt") "$f changed" }
    $env:GIT_COMMITTER_DATE = '2026-10-03T00:00:00Z'; $env:GIT_AUTHOR_DATE = '2026-10-03T00:00:00Z'
    git -C $ar add -A; git -C $ar commit -q -m change
    [Environment]::SetEnvironmentVariable('GIT_COMMITTER_DATE', $null); [Environment]::SetEnvironmentVariable('GIT_AUTHOR_DATE', $null)
    & "$S\Init-Streams.ps1" -Repo $ar | Out-Null
    $tk = @(@{ at = '2026-10-01T12:00:00Z'; by = 'plan-1'; to = 'planned'; note = 'added' }, @{ at = '2026-10-02T00:00:00Z'; by = 'author-1'; to = 'ticketed'; note = 'ticket' })
    $A = { param($id, $g, $st, $ws, $deps, $kind = 'code') @{ id = $id; group = $g; title = $id; why = @('AC-1'); kind = $kind; writeSet = @($ws); dependsOn = @($deps); estMinutes = 5; state = $st; claim = $null; artifacts = @{}; history = @($tk) } }
    $nowIso = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    $ac = & $A 'A1.C' 'A1' 'ticketed' 'e.txt' @(); $ac.claim = @{ session = 'build-c'; role = 'build'; at = $nowIso; beat = $nowIso }
    $adoc = @{
        groups = @(@{ id = 'A1'; name = 'one'; state = 'released'; origin = 'plan'; scope = @{ include = @('F-1') } }, @{ id = 'A2'; name = 'two'; state = 'released'; origin = 'plan'; scope = @{ include = @('F-2') } })
        tasks = @((& $A 'A1.K' 'A1' 'ticketed' 'b.txt' @()), (& $A 'A1.S' 'A1' 'ticketed' 'a.txt' @()), (& $A 'A1.Z' 'A1' 'integrated' 'd.txt' @()),
            (& $A 'A1.D' 'A1' 'ticketed' 'c.txt' @('A1.Z')), $ac, (& $A 'A1.G' 'A1' 'planned' @() @() 'gate'), (& $A 'A2.X' 'A2' 'ticketed' 'a2.txt' @())) }
    $adoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $ar '.streams\tasks.json') -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $ar '.streams\suites') -Force | Out-Null
    ConvertTo-Json -InputObject @(@{ test = 'NS.KTests.K'; suite = 'Tests.Unit'; file = 'g.txt'; ownerRow = 'A1.Z'; writeSet = @('g.txt'); run = 'run-A0-1'; head = 'abc'; fixTask = $null }) -Depth 5 |
        Set-Content (Join-Path $ar '.streams\suites\known-failures.A1.json') -Encoding utf8
    $act1 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session integ-a -Group A1); $actx = $LASTEXITCODE
    $at = $act1 -join ' | '
    Case '95 activation exits 0 and reports its counts' ($actx -eq 0 -and $at -match 'ACTIVATED A1 stale 2 skipped 1 gates 1 fixes 1') $at
    Case '95 an unchanged write set keeps the row ticketed' ((T $ar 'A1.K').state -eq 'ticketed') (T $ar 'A1.K').state
    $as = T $ar 'A1.S'
    Case '95 a changed write-set file sends the row to planned with a STALE: note' ($as.state -eq 'planned' -and (($as.history | Select-Object -Last 1).note -match 'STALE: a\.txt since \w+ by A1\.S')) (($as.history | Select-Object -Last 1) | ConvertTo-Json -Compress)
    $ad = T $ar 'A1.D'
    Case '95 a changed dependency file sends the row to planned, naming the dependency' ($ad.state -eq 'planned' -and (($ad.history | Select-Object -Last 1).note -match 'STALE: d\.txt .*by A1\.Z')) (($ad.history | Select-Object -Last 1) | ConvertTo-Json -Compress)
    Case '95 a claimed stale row is skipped and reported' ((T $ar 'A1.C').state -eq 'ticketed' -and $at -match 'SKIP-CLAIMED A1\.C') $at
    Case '95 a later group is not checked' ((T $ar 'A2.X').state -eq 'ticketed') (T $ar 'A2.X').state
    $kf1 = T $ar 'A1.KF1'
    $kfj = Get-Content -Raw (Join-Path $ar '.streams\suites\known-failures.A1.json') | ConvertFrom-Json
    Case '95 a known failure becomes a fix task at activation' ($kf1 -and $kf1.origin -eq 'integration' -and $kf1.state -eq 'planned' -and @($kf1.writeSet) -contains 'g.txt' -and @($kfj)[0].fixTask -eq 'A1.KF1') (($kf1 | ConvertTo-Json -Compress -Depth 4) + ' ' + ($kfj | ConvertTo-Json -Compress))
    $aq = Get-Content -Raw (Join-Path $ar '.streams\owner\questions.md') -ErrorAction SilentlyContinue
    Case '95 the group''s gates go to the owner queue up front' ($aq -match 'ACTIVATION-GATE A1\.G') $aq
    $arec = Get-Content -Raw (Join-Path $ar '.streams\plans\A1.activation.json') | ConvertFrom-Json
    Case '95 the activation record holds the stale rows and the milestone state' (@($arec.stale).Count -eq 2 -and $null -ne $arec.now -and $arec.now.M1 -eq $false) ($arec | ConvertTo-Json -Compress -Depth 5)
    $act2 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session integ-a -Group A1)
    Case '95 a second activation changes nothing' (($act2 -join ' ') -match '^ALREADY-ACTIVE A1') ($act2 -join ' | ')
    $aq2 = Get-Content -Raw (Join-Path $ar '.streams\owner\questions.md')
    Case '95 the gate line is written once' (([regex]::Matches($aq2, 'ACTIVATION-GATE A1\.G')).Count -eq 1) $aq2
    Case '95 the gate line carries local time with the zone, not UTC' ($aq2 -match '(?m)^- \d{4}-\d\d-\d\d \d\d:\d\d [A-Za-z]+ ACTIVATION-GATE A1\.G') $aq2
    # FRESHNESS TICK (2026-10-18 dependency review F2): -FreshnessOnly runs on an ACTIVE group every status tick. It
    # judges a row by its OWN write set only: A1.F (f.txt, dependsOn A1.Z) stays ticketed when d.txt moves again, while
    # A1.K (b.txt) goes to planned when b.txt moves. A full -Force activation still stales A1.F through its dependency.
    $fdoc = J $ar
    $fdoc.tasks += (& $A 'A1.F' 'A1' 'ticketed' 'f.txt' @('A1.Z'))
    $fdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $ar '.streams\tasks.json') -Encoding utf8
    Set-Content (Join-Path $ar 'd.txt') 'd changed again'; git -C $ar add -A; git -C $ar commit -q -m 'd moves again'
    $fr0 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session status-a -Group A1 -FreshnessOnly)
    Case '95 freshness tick: a dependency''s file moving does not stale a ticketed row (own write set only)' ((T $ar 'A1.F').state -eq 'ticketed' -and (T $ar 'A1.K').state -eq 'ticketed' -and ($fr0 -join ' ') -match 'FRESHNESS A1 stale 0') ($fr0 -join ' | ')
    Set-Content (Join-Path $ar 'b.txt') 'b changed'; git -C $ar add -A; git -C $ar commit -q -m 'b moves'
    $fr1 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session status-a -Group A1 -FreshnessOnly)
    $ak = T $ar 'A1.K'
    Case '95 freshness tick: a row whose OWN file moved since it was ticketed goes to planned with a STALE: note' ($ak.state -eq 'planned' -and (($ak.history | Select-Object -Last 1).note -match 'STALE: b\.txt since \w+ by A1\.K') -and ($fr1 -join ' ') -match 'FRESHNESS A1 stale 1 skipped 1') (($fr1 -join ' | ') + ' :: ' + (($ak.history | Select-Object -Last 1) | ConvertTo-Json -Compress))
    Case '95 freshness tick: the activation record is not changed by it' (@((Get-Content -Raw (Join-Path $ar '.streams\plans\A1.activation.json') | ConvertFrom-Json).stale).Count -eq 2 -and (Test-Path (Join-Path $ar '.streams\plans\A1.freshness-revise.json')))
    Case '95 freshness tick: a stale move is a decision line' ((Get-Content -Raw (Join-Path $ar '.streams\decisions.md')) -match 'FRESHNESS A1 at \w+: 1 ticketed row\(s\) to planned .*A1\.K')
    $fr2 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session status-a -Group A1 -FreshnessOnly)
    Case '95 freshness tick is idempotent' (($fr2 -join ' ') -match 'FRESHNESS A1 stale 0' -and (T $ar 'A1.F').state -eq 'ticketed') ($fr2 -join ' | ')
    # Kit item IN-20261025141723-5621 (F1): a group with no Tier 2 run definition gets the newest other group's, group set.
    $rdSuites95 = Join-Path $ar '.streams\suites'; New-Item -ItemType Directory -Force -Path $rdSuites95 | Out-Null
    Set-Content -LiteralPath (Join-Path $rdSuites95 'Z9.run.json') -Value '{ "group": "Z9", "setup": [], "legs": [ { "name": "u", "kind": "dotnet", "command": "x {group}" } ] }'
    $rdOut95 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session status-a -Group A1 -FreshnessOnly)
    $rdDef95 = Get-Content -Raw -LiteralPath (Join-Path $rdSuites95 'A1.run.json') -ErrorAction SilentlyContinue | ConvertFrom-Json
    Case '95 activation writes a missing run definition from the newest other group''s, group set' ($rdDef95 -and $rdDef95.group -eq 'A1' -and @($rdDef95.legs).Count -eq 1 -and ($rdOut95 -join ' ') -match 'RUN-DEFINITION A1 from Z9\.run\.json') ($rdOut95 -join ' | ')
    Set-Content -LiteralPath (Join-Path $rdSuites95 'A1.run.json') -Value '{ "group": "A1", "keep": 1 }'
    $rdOut95b = @(& "$S\Activate-Group.ps1" -Repo $ar -Session status-a -Group A1 -FreshnessOnly)
    Case '95 an existing run definition is never overwritten' ((Get-Content -Raw -LiteralPath (Join-Path $rdSuites95 'A1.run.json')) -match '"keep"' -and ($rdOut95b -join ' ') -notmatch 'RUN-DEFINITION') ($rdOut95b -join ' | ')
    Remove-Item -LiteralPath (Join-Path $rdSuites95 'A1.run.json'), (Join-Path $rdSuites95 'Z9.run.json') -Force
    $fr3 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session integ-a -Group A1 -Force)
    Case '95 a forced full activation still stales a row through its dependency''s file' ((T $ar 'A1.F').state -eq 'planned' -and (((T $ar 'A1.F').history | Select-Object -Last 1).note -match 'STALE: d\.txt .*by A1\.Z')) ($fr3 -join ' | ')
    # APPEND-ONLY ALLOCATOR (kit item IN-20261022023731-e458): A1.Y (ids.yaml) ticketed after ids.yaml existed stays
    # ticketed when lines are only appended, and goes to planned when an existing line is edited.
    Set-Content (Join-Path $ar 'ids.yaml') "- id: Q-1"
    $env:GIT_COMMITTER_DATE = '2026-12-01T00:00:00Z'; $env:GIT_AUTHOR_DATE = '2026-12-01T00:00:00Z'
    git -C $ar add -A; git -C $ar commit -q -m 'ids base'
    $ydoc = J $ar
    $yrow = & $A 'A1.Y' 'A1' 'ticketed' 'ids.yaml' @(); $yrow.history = @(@{ at = '2026-12-02T00:00:00Z'; by = 'author-1'; to = 'ticketed'; note = 'ticket' })
    $ydoc.tasks += $yrow
    $ydoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $ar '.streams\tasks.json') -Encoding utf8
    Add-Content (Join-Path $ar 'ids.yaml') "- id: Q-2"
    $env:GIT_COMMITTER_DATE = '2026-12-03T00:00:00Z'; $env:GIT_AUTHOR_DATE = '2026-12-03T00:00:00Z'
    git -C $ar add -A; git -C $ar commit -q -m 'ids append'
    $fy1 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session status-a -Group A1 -FreshnessOnly)
    Case '95 freshness tick: an append-only change to an allocator file (ids.yaml) keeps the row ticketed' ((T $ar 'A1.Y').state -eq 'ticketed') ($fy1 -join ' | ')
    Set-Content (Join-Path $ar 'ids.yaml') "- id: Q-1x`n- id: Q-2"
    $env:GIT_COMMITTER_DATE = '2026-12-04T00:00:00Z'; $env:GIT_AUTHOR_DATE = '2026-12-04T00:00:00Z'
    git -C $ar add -A; git -C $ar commit -q -m 'ids edit'
    [Environment]::SetEnvironmentVariable('GIT_COMMITTER_DATE', $null); [Environment]::SetEnvironmentVariable('GIT_AUTHOR_DATE', $null)
    $fy2 = @(& "$S\Activate-Group.ps1" -Repo $ar -Session status-a -Group A1 -FreshnessOnly)
    $ay = T $ar 'A1.Y'
    Case '95 freshness tick: an edited line in an allocator file still stales the row' ($ay.state -eq 'planned' -and (($ay.history | Select-Object -Last 1).note -match 'STALE: ids\.yaml')) (($fy2 -join ' | ') + ' :: ' + (($ay.history | Select-Object -Last 1) | ConvertTo-Json -Compress))

    # ---- 96. tiered testing (3.3): a Tier 2 run, the flaky screen, attribution, Tier 3 retest, the close rule, nightly.
    # The dotnet leg is a fake runner that writes a trx from a control file, so the cases exercise the kit's scripts,
    # not dotnet. Tests: NS.FooTests.Flaky (fails, passes on the re-run), NS.FooTests.Real (fails twice: owned by T1.A,
    # this group: fix task), NS.LaterTests.L (owned by T2.L, a LATER group: known failure), NS.BarTests.Ok (passes).
    $tr = Join-Path $Scratch 'tierrepo'; New-Item -ItemType Directory -Path (Join-Path $tr 'tests') -Force | Out-Null; $repos += $tr
    git -C $tr init -q -b main; git -C $tr config user.email t@t; git -C $tr config user.name t; Grant-GitPolicy $tr
    Set-Content (Join-Path $tr 'tests\FooTests.cs') 'namespace NS { public class FooTests { } }'
    Set-Content (Join-Path $tr 'tests\BarTests.cs') 'namespace NS { public class BarTests { } }'
    Set-Content (Join-Path $tr 'tests\LaterTests.cs') 'namespace NS { public class LaterTests { } }'
    git -C $tr add -A; git -C $tr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $tr | Out-Null
    $fake = Join-Path $Scratch 'fake-test.ps1'
    Set-Content -Path $fake -Encoding utf8 -Value @'
param([string] $Out, [string] $Mode, [string] $Filter = '', [string] $Control)
$c = Get-Content -Raw $Control | ConvertFrom-Json -AsHashtable
$map = $c[$Mode]
$terms = @($Filter -split '\|' | Where-Object { $_ } | ForEach-Object { ($_ -replace '^FullyQualifiedName~', '') -replace '\\(.)', '$1' })
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$defs = ''; $res = ''; $i = 0
foreach ($name in @($map.Keys | Sort-Object)) {
    if ($terms.Count -and -not @($terms | Where-Object { $name.Contains($_) }).Count) { continue }
    $i++; $cls = $name.Substring(0, $name.LastIndexOf('.')); $m = $name.Substring($name.LastIndexOf('.') + 1)
    $defs += "<UnitTest id=`"$i`"><TestMethod className=`"$cls`" name=`"$m`" /></UnitTest>"
    $res += "<UnitTestResult testId=`"$i`" testName=`"$m`" outcome=`"$($map[$name])`" duration=`"00:00:00.1`" />"
}
Set-Content -Path (Join-Path $Out "r$([guid]::NewGuid().ToString('N').Substring(0,6)).trx") -Value "<TestRun><TestDefinitions>$defs</TestDefinitions><Results>$res</Results></TestRun>"
if ($res -match 'Failed') { exit 1 } else { exit 0 }
'@
    $ctl = Join-Path $Scratch 'fake-outcomes.json'
    $setCtl = { param($t2, $rt) @{ tier2 = $t2; retest = $rt } | ConvertTo-Json | Set-Content $ctl -Encoding utf8 }
    & $setCtl @{ 'NS.FooTests.Flaky' = 'Failed'; 'NS.FooTests.Real' = 'Failed'; 'NS.LaterTests.L' = 'Failed'; 'NS.BarTests.Ok' = 'Passed' } @{ 'NS.FooTests.Flaky' = 'Passed'; 'NS.FooTests.Real' = 'Failed'; 'NS.LaterTests.L' = 'Failed'; 'NS.BarTests.Ok' = 'Passed' }
    $legDef = @{ name = 'Tests.Unit'; kind = 'dotnet'; project = 'tests'
        command = "& '$fake' -Out '{runDir}\Tests.Unit' -Mode tier2 -Control '$ctl'"
        retestCommand = "& '$fake' -Out '{runDir}\Tests.Unit' -Mode retest -Filter '{filter}' -Control '$ctl'" }
    New-Item -ItemType Directory -Path (Join-Path $tr '.streams\suites') -Force | Out-Null
    $setupDef = @{ name = 'mark'; command = "Set-Content -LiteralPath 'setup.txt' -Value ok" }
    @{ group = 'T1'; copyIgnored = @(); setup = @($setupDef); legs = @($legDef); graders = $false; after = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $tr '.streams\suites\T1.run.json') -Encoding utf8
    $th = @(@{ at = '2026-10-01T00:00:00Z'; by = 'build-1'; to = 'integrated'; note = 'landed' })
    $Tt = { param($id, $g, $st, $ws, $kind = 'code') @{ id = $id; group = $g; title = $id; why = @('AC-1'); kind = $kind; writeSet = @($ws); dependsOn = @(); estMinutes = 5; state = $st; claim = $null; artifacts = @{}; history = @($th) } }
    $tdoc = @{
        groups = @(@{ id = 'T1'; name = 'one'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-1') } }, @{ id = 'T2'; name = 'two'; state = 'released'; origin = 'plan'; scope = @{ include = @('F-2') } })
        tasks = @((& $Tt 'T1.A' 'T1' 'integrated' 'tests/FooTests.cs'), (& $Tt 'T1.B' 'T1' 'integrated' 'tests/BarTests.cs'), (& $Tt 'T1.G' 'T1' 'done' @() 'gate'),
            (& $Tt 'T1.I' 'T1' 'ticketed' @() 'integration'), (& $Tt 'T2.L' 'T2' 'ticketed' 'tests/LaterTests.cs'),
            # moved into T1 by a plan revision, so its id keeps another group's prefix (G1.T24 / G1.T25 in G3, 2026-10-05)
            (& $Tt 'T0.X' 'T1' 'integrated' 'tests/MovedTests.cs')) }
    $tdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8

    $s1 = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session integ-t -Group T1 -Reason complete -Wait)
    $s1t = $s1 -join ' | '
    $rdir = Join-Path $tr '.streams\suites\runs'
    $run1 = Get-Content -Raw (Join-Path $rdir 'run-T1-1.json') | ConvertFrom-Json -DateKind String
    Case '96 a Tier 2 run starts on a snapshot, runs its legs and ends done' ($s1t -match 'RUN-STARTED run-T1-1' -and $run1.status -eq 'done' -and $s1t -match 'RUN-ENDED run-T1-1 done') $s1t
    Case '96 a completion run moves the integration row to building' ((T $tr 'T1.I').state -eq 'building') (T $tr 'T1.I').state
    $res1 = Get-Content -Raw (Join-Path $rdir 'run-T1-1.results.json') | ConvertFrom-Json
    $o1 = @{}; foreach ($x in $res1.tests) { $o1[$x.test] = $x.outcome }
    Case '96 per-test results carry the test, the outcome and the owning file' ($o1['NS.BarTests.Ok'] -eq 'passed' -and @($res1.tests | Where-Object { $_.test -eq 'NS.FooTests.Real' -and $_.file -eq 'tests/FooTests.cs' }).Count -eq 1) ($res1.tests | ConvertTo-Json -Compress)
    Case '96 a failure that passes the same-snapshot re-run is flaky, not failed' ($o1['NS.FooTests.Flaky'] -eq 'flaky' -and $s1t -match 'FLAKY NS\.FooTests\.Flaky') $s1t
    $rt1 = Get-Content -Raw (Join-Path $rdir 'retest-T1-1.json') | ConvertFrom-Json
    $fcmd = [string]$rt1.legs[0].command
    Case '96 the re-run filter holds exactly the failed tests, contains-match' ($rt1.tier -eq 'flaky' -and $fcmd -match 'FullyQualifiedName~NS\.FooTests\.Flaky' -and $fcmd -match 'FullyQualifiedName~NS\.FooTests\.Real' -and $fcmd -match 'FullyQualifiedName~NS\.LaterTests\.L' -and $fcmd -notmatch 'BarTests' -and $fcmd -notmatch 'FullyQualifiedName=') $fcmd
    $terms = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"; ConvertTo-DotnetFilterTerm 'NS.C.M(1, "a")'; ConvertTo-PlaywrightGrepTerm 'adds (x) item' }
    Case '96 a data-row name filters by method, a Playwright title is escaped and end-anchored' ($terms[0] -eq 'FullyQualifiedName~NS.C.M' -and $terms[1] -eq 'adds \(x\) item( @\S+)*$') ($terms -join ' ; ')
    # One completion run counts for every focus group integrated when it started (kit item IN-20261019130625-ee1d): a
    # record's 'groups' list makes Get-SuiteRunRecords -Group find it for each, and a plain record stays its own group's.
    $sg96 = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"
        $sp = @{ Suites = (Join-Path $Scratch 'sg96') }; New-Item -ItemType Directory -Path (Join-Path $sp.Suites 'runs') -Force | Out-Null
        @{ id = 'run-G9-1'; tier = '2'; group = 'G9'; groups = @('G9', 'G6', 'G7'); startedAt = '2026-10-19T10:00:00Z'; status = 'done' } | ConvertTo-Json | Set-Content (Join-Path $sp.Suites 'runs\run-G9-1.json') -Encoding utf8
        @{ id = 'run-G8-1'; tier = '2'; group = 'G8'; startedAt = '2026-10-19T09:00:00Z'; status = 'done' } | ConvertTo-Json | Set-Content (Join-Path $sp.Suites 'runs\run-G8-1.json') -Encoding utf8
        (@(Get-SuiteRunRecords $sp 'G6' '2') | ForEach-Object { $_['id'] }) -join ','; (@(Get-SuiteRunRecords $sp 'G8' '2') | ForEach-Object { $_['id'] }) -join ','
        (@(Get-SuiteRunRecords $sp 'G5' '2') | ForEach-Object { $_['id'] }) -join ',' }
    Case '96 a run record''s groups list counts it for each listed group, and only those' ($sg96[0] -eq 'run-G9-1' -and $sg96[1] -eq 'run-G8-1' -and $sg96[2] -eq '') ($sg96 -join ' ; ')    # Playwright's CLI --grep runs on the title path PLUS the test's tags (_grepTitleWithTags), so a tagged test must match.
    Case '96 the Playwright grep matches a tagged test and still anchors the title' ('cart adds (x) item @a11y @smoke' -match $terms[1] -and 'cart adds (x) item' -match $terms[1] -and 'cart adds (x) item twice' -notmatch $terms[1]) $terms[1]
    # A shared run end to end: run-S2-1 counts for S2 and the earlier S1. A failure S1 owns is filed in S1 (fixGroup S1),
    # S2's in S2, a later group's (S3) is a known failure; S2's close counts only its own fix, S1's close sees the run.
    $sr96 = Join-Path $Scratch 'sharedrun96'; New-Item -ItemType Directory -Path (Join-Path $sr96 'tests') -Force | Out-Null; $repos += $sr96
    git -C $sr96 init -q -b main; git -C $sr96 config user.email t@t; git -C $sr96 config user.name t; Grant-GitPolicy $sr96
    Set-Content (Join-Path $sr96 'tests\A.cs') 'a'; git -C $sr96 add -A; git -C $sr96 commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $sr96 | Out-Null
    @{ groups = @(@{ id = 'S1'; name = 's1'; state = 'integrating'; origin = 'plan' }, @{ id = 'S2'; name = 's2'; state = 'integrating'; origin = 'plan' }, @{ id = 'S3'; name = 's3'; state = 'released'; origin = 'plan' })
        tasks = @((& $Tt 'S1.A' 'S1' 'integrated' 'tests/A.cs'), (& $Tt 'S1.I' 'S1' 'ticketed' @() 'integration'), (& $Tt 'S2.B' 'S2' 'integrated' 'tests/B.cs'),
            (& $Tt 'S2.I' 'S2' 'ticketed' @() 'integration'), (& $Tt 'S3.C' 'S3' 'ticketed' 'tests/C.cs')) } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $sr96 '.streams\tasks.json') -Encoding utf8
    $srd96 = Join-Path $sr96 '.streams\suites\runs'; New-Item -ItemType Directory -Path $srd96 -Force | Out-Null
    @{ id = 'run-S2-1'; tier = '2'; group = 'S2'; groups = @('S2', 'S1'); reason = 'complete'; startedAt = '2026-10-19T10:00:00Z'; status = 'done'; head = 'abc' } | ConvertTo-Json | Set-Content (Join-Path $srd96 'run-S2-1.json') -Encoding utf8
    $srt96 = { param($n, $f) @{ test = $n; suite = 'Tests.Unit'; outcome = 'failed'; durationMs = 1; file = $f; project = ''; head = 'abc' } }
    @{ tests = @((& $srt96 'NS.A.T' 'tests/A.cs'), (& $srt96 'NS.B.T' 'tests/B.cs'), (& $srt96 'NS.C.T' 'tests/C.cs')) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $srd96 'run-S2-1.results.json') -Encoding utf8
    # A record whose flaky screen is still pending (its process alive) is not attributed yet (kit item IN-20261019153055-2c27).
    $srp96 = Get-Content -Raw (Join-Path $srd96 'run-S2-1.json')
    $srq96 = $srp96 | ConvertFrom-Json -AsHashtable; $srq96['screen'] = 'pending'; $srq96['pid'] = $PID; $srq96['pidStart'] = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o')
    $srq96 | ConvertTo-Json | Set-Content (Join-Path $srd96 'run-S2-1.json') -Encoding utf8
    $srs96 = @(& "$S\Register-SuiteFailures.ps1" -Repo $sr96 -Session integ-t -Run run-S2-1) -join ' | '
    Case '96 a run whose flaky screen still runs is refused SCREEN-PENDING and nothing is written' ($srs96 -match '^SCREEN-PENDING run-S2-1' -and -not (Test-Path (Join-Path $srd96 'run-S2-1.attribution.json'))) $srs96
    $srq96['pid'] = 999999; $srq96 | ConvertTo-Json | Set-Content (Join-Path $srd96 'run-S2-1.json') -Encoding utf8
    $sra96 = @(& "$S\Register-SuiteFailures.ps1" -Repo $sr96 -Session integ-t -Run run-S2-1) -join ' | '
    $srx96 = Get-Content -Raw (Join-Path $srd96 'run-S2-1.attribution.json') -ErrorAction SilentlyContinue | ConvertFrom-Json
    $srf96 = @{}; foreach ($x in @($srx96.failures)) { $srf96[$x.test] = "$($x.disposition)/$($x.fixGroup)/$($x.fixTask)" }
    $srk96 = Get-Content -Raw (Join-Path $sr96 '.streams\suites\known-failures.S3.json') -ErrorAction SilentlyContinue
    Case '96 a shared run files each fix in the earliest covered group at or after its owner, a later group''s as known' ($srf96['NS.A.T'] -eq 'fix/S1/S1.R1F1' -and $srf96['NS.B.T'] -eq 'fix/S2/S2.R1F1' -and $srf96['NS.C.T'] -like 'later/*' -and (T $sr96 'S1.R1F1').group -eq 'S1' -and $srk96 -match 'NS\.C\.T') "$sra96 :: $($srf96 | ConvertTo-Json -Compress)"
    $src2 = @(& "$S\Test-GroupClose.ps1" -Repo $sr96 -Group S2 -DryRun) -join ' | '
    $src1 = @(& "$S\Test-GroupClose.ps1" -Repo $sr96 -Group S1 -DryRun) -join ' | '
    Case '96 each covered group''s close counts only the fixes filed in it, and sees the shared run' ($src2 -match 'UNRETESTED 1 .*NS\.B\.T' -and $src2 -notmatch 'NS\.A\.T' -and $src2 -match 'OPEN-FIX S2\.R1F1$|OPEN-FIX S2\.R1F1 ' -and $src1 -notmatch 'NO-TIER2' -and $src1 -match 'UNRETESTED 1 .*NS\.A\.T' -and $src1 -notmatch 'NS\.B\.T' -and $src1 -match 'OPEN-FIX S1\.R1F1') "S2: $src2 // S1: $src1"
    # An exemption held only in the FIX group's file (S1), not the run group's (S2), is exempt with its reason; the
    # lookup read the run group's table and died 'Cannot index into a null array' (kit item IN-20261020202159-4b5e).
    @{ id = 'run-S2-2'; tier = '2'; group = 'S2'; groups = @('S2', 'S1'); reason = 'manual'; startedAt = '2026-10-19T11:00:00Z'; status = 'done'; head = 'abd' } | ConvertTo-Json | Set-Content (Join-Path $srd96 'run-S2-2.json') -Encoding utf8
    @{ tests = @((& $srt96 'NS.A.T' 'tests/A.cs')) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $srd96 'run-S2-2.results.json') -Encoding utf8
    ConvertTo-Json @(@{ test = 'NS.A.T'; reason = 'owner ruling x1'; run = 'pending'; fixTask = '' }) | Set-Content (Join-Path $sr96 '.streams\suites\exempt.S1.json') -Encoding utf8
    $sre96 = @(& "$S\Register-SuiteFailures.ps1" -Repo $sr96 -Session integ-t -Run run-S2-2 2>&1) -join ' | '
    $srex96 = Get-Content -Raw (Join-Path $srd96 'run-S2-2.attribution.json') -ErrorAction SilentlyContinue | ConvertFrom-Json
    Case '96 a shared run exempts a failure the fix group''s exemption file holds, with its reason' ($sre96 -match 'EXEMPT NS\.A\.T \(owner ruling x1\)' -and $sre96 -match 'ATTRIBUTED run-S2-2 fix 0 .* exempt 1' -and @($srex96.failures)[0].disposition -eq 'exempt') $sre96
    # A failure whose owner is a fix row that landed AFTER the run started is that row's to retest, not a new row's: the
    # run graded the code before it, and G13.R6F2 duplicated landed G13.R6F1 (kit item IN-20261020203944-8aeb). A fix
    # row that landed BEFORE the run still gets a new fix row.
    $srd3 = Get-Content -Raw (Join-Path $sr96 '.streams\tasks.json') | ConvertFrom-Json -AsHashtable
    foreach ($lr in @(@('S2.R1F8', 'tests/E.cs', '2026-10-19T11:30:00Z'), @('S2.R1F9', 'tests/D.cs', '2026-10-19T12:30:00Z'))) {
        $x = & $Tt $lr[0] 'S2' 'integrated' $lr[1]; $x.origin = 'integration'; $x.history = @(@{ at = $lr[2]; by = 'build-1'; to = 'integrated'; note = 'landed' }); $srd3.tasks += $x }
    $srd3 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $sr96 '.streams\tasks.json') -Encoding utf8
    @{ id = 'run-S2-3'; tier = '2'; group = 'S2'; groups = @('S2', 'S1'); reason = 'manual'; startedAt = '2026-10-19T12:00:00Z'; status = 'done'; head = 'abe' } | ConvertTo-Json | Set-Content (Join-Path $srd96 'run-S2-3.json') -Encoding utf8
    @{ tests = @((& $srt96 'NS.D.T' 'tests/D.cs'), (& $srt96 'NS.E.T' 'tests/E.cs')) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $srd96 'run-S2-3.results.json') -Encoding utf8
    $srl96 = @(& "$S\Register-SuiteFailures.ps1" -Repo $sr96 -Session integ-t -Run run-S2-3 2>&1) -join ' | '
    $srlx96 = Get-Content -Raw (Join-Path $srd96 'run-S2-3.attribution.json') -ErrorAction SilentlyContinue | ConvertFrom-Json
    $srlf96 = @{}; foreach ($x in @($srlx96.failures)) { $srlf96[$x.test] = "$($x.disposition)/$($x.fixTask)/$(if ($x.PSObject.Properties['landedAfterRun']) { $x.landedAfterRun })" }
    $srlr96 = @((Get-Content -Raw (Join-Path $sr96 '.streams\tasks.json') | ConvertFrom-Json).tasks | Where-Object { $_.id -like 'S2.R3F*' } | ForEach-Object { "$($_.id):$($_.writeSet -join ',')" })
    Case '96 a fix row that landed after the run is the failure''s fix task; one that landed before gets a new row' ($srlf96['NS.D.T'] -eq 'fix/S2.R1F9/True' -and $srlf96['NS.E.T'] -eq 'fix/S2.R3F1/' -and $srlr96.Count -eq 1 -and $srlr96[0] -eq 'S2.R3F1:tests/E.cs' -and $srl96 -match 'ATTRIBUTED run-S2-3 fix 2 ') "$srl96 :: $($srlf96 | ConvertTo-Json -Compress) :: $($srlr96 -join ';')"
    # A fix that JOINS an unlanded row leaves that row a note naming EVERY failing test (the title keeps three), and the
    # ATTRIBUTED summary and decisions line say which fix joined which row (kit item IN-20261026141829-aeb7).
    $srj3 = Get-Content -Raw (Join-Path $sr96 '.streams\tasks.json') | ConvertFrom-Json -AsHashtable; $srj3.tasks += (& $Tt 'S2.J' 'S2' 'ticketed' 'tests/J.cs')
    $srj3 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $sr96 '.streams\tasks.json') -Encoding utf8
    @{ id = 'run-S2-4'; tier = '2'; group = 'S2'; groups = @('S2', 'S1'); reason = 'manual'; startedAt = '2026-10-19T13:00:00Z'; status = 'done'; head = 'abf' } | ConvertTo-Json | Set-Content (Join-Path $srd96 'run-S2-4.json') -Encoding utf8
    @{ tests = @(foreach ($q in 1..4) { & $srt96 "NS.J.T$q" 'tests/J.cs' }) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $srd96 'run-S2-4.results.json') -Encoding utf8
    $srjo96 = @(& "$S\Register-SuiteFailures.ps1" -Repo $sr96 -Session integ-t -Run run-S2-4 2>&1) -join ' | '
    $srjn96 = @((T $sr96 'S2.J').history | ForEach-Object { $_.note }) -join ' // '
    $srjd96 = Get-Content -Raw (Join-Path $sr96 '.streams\decisions.md') -ErrorAction SilentlyContinue
    Case '96 a joined fix names every failing test on the joined row and in the ATTRIBUTED and decisions lines' ($srjn96 -match 'integration fix joined' -and $srjn96 -match 'NS\.J\.T4' -and $srjo96 -match 'ATTRIBUTED run-S2-4 fix 4 .*joined 1 \(S2\.R4F1 into S2\.J\)' -and $srjd96 -match 'ATTRIBUTED run-S2-4 .*joined 1 \(S2\.R4F1 into S2\.J\)') "$srjo96 :: $srjn96"
    # A later group that is ALREADY active (plans\S3.activation.json) gets its known failures' fix rows at attribution:
    # activation step 2 never runs again for it (ALREADY-ACTIVE), so run-G17-3's 21 G23 failures sat with no fix row
    # (kit item IN-20261026142341-f136). The entry run-S2-1 left (NS.C.T) converts too; both are on tests/C.cs, so the
    # second fix joins the first (one fix row per file) and the attribution names the row that carries it.
    $srk3 = Get-Content -Raw (Join-Path $sr96 '.streams\tasks.json') | ConvertFrom-Json -AsHashtable
    foreach ($x in $srk3.tasks) { if ($x.id -eq 'S3.C') { $x.state = 'integrated' } }
    $srk3 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $sr96 '.streams\tasks.json') -Encoding utf8
    New-Item -ItemType Directory -Path (Join-Path $sr96 '.streams\plans') -Force | Out-Null
    @{ group = 'S3'; at = '2026-10-19T09:00:00Z'; session = 'integ-t'; head = 'abc' } | ConvertTo-Json | Set-Content (Join-Path $sr96 '.streams\plans\S3.activation.json') -Encoding utf8
    @{ id = 'run-S2-5'; tier = '2'; group = 'S2'; groups = @('S2', 'S1'); reason = 'manual'; startedAt = '2026-10-19T14:00:00Z'; status = 'done'; head = 'ab0' } | ConvertTo-Json | Set-Content (Join-Path $srd96 'run-S2-5.json') -Encoding utf8
    @{ tests = @((& $srt96 'NS.C.T2' 'tests/C.cs')) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $srd96 'run-S2-5.results.json') -Encoding utf8
    $srko96 = @(& "$S\Register-SuiteFailures.ps1" -Repo $sr96 -Session integ-t -Run run-S2-5 2>&1) -join ' | '
    $srkx96 = Get-Content -Raw (Join-Path $srd96 'run-S2-5.attribution.json') -ErrorAction SilentlyContinue | ConvertFrom-Json
    $srkf96 = @(Get-Content -Raw (Join-Path $sr96 '.streams\suites\known-failures.S3.json') -ErrorAction SilentlyContinue | ConvertFrom-Json)
    $srkr96 = @((Get-Content -Raw (Join-Path $sr96 '.streams\tasks.json') | ConvertFrom-Json).tasks | Where-Object { $_.id -like 'S3.KF*' } | ForEach-Object { [string]$_.id })
    $srkt96 = if ($srkx96) { [string]@($srkx96.failures)[0].fixTask } else { '' }
    Case '96 a later group already active gets its known failures'' fix rows at attribution' ($srkr96.Count -eq 1 -and $srkr96[0] -eq 'S3.KF1' -and @($srkf96 | Where-Object { -not $_.fixTask }).Count -eq 0 -and $srkt96 -eq 'S3.KF1' -and $srko96 -match 'KNOWN-FAILURES S3 fixes 2' -and $srko96 -match 'JOINED S3\.KF2 into S3\.KF1') "$srko96 :: rows $($srkr96 -join ',') :: kf $($srkf96 | ConvertTo-Json -Compress)"
    # A group every row of which an earlier group pulls forward has an EMPTY group set; its own rows still decide whether
    # a run covers it, and Add-SuiteRunGroup.ps1 counts a finished run for it (kit item IN-20261020100610-6c4b, G11).
    $at96 = Join-Path $Scratch 'attach96'; New-Item -ItemType Directory -Path $at96 -Force | Out-Null; $repos += $at96
    git -C $at96 init -q -b main; git -C $at96 config user.email t@t; git -C $at96 config user.name t; Grant-GitPolicy $at96
    Set-Content (Join-Path $at96 'a.txt') 'a'; git -C $at96 add -A; git -C $at96 commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $at96 | Out-Null
    $atY96 = & $Tt 'A1.Y' 'A1' 'ticketed' 'y.cs'; $atY96.dependsOn = @('A2.X')
    @{ groups = @(@{ id = 'A1'; name = 'a1'; state = 'integrating'; origin = 'plan' }, @{ id = 'A2'; name = 'a2'; state = 'integrating'; origin = 'plan' }, @{ id = 'A3'; name = 'a3'; state = 'released'; origin = 'plan' })
        tasks = @($atY96, (& $Tt 'A2.X' 'A2' 'integrated' 'x.cs'), (& $Tt 'A2.I' 'A2' 'ticketed' @() 'integration'), (& $Tt 'A3.Z' 'A3' 'ticketed' 'z.cs')) } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $at96 '.streams\tasks.json') -Encoding utf8
    $atg96 = & { . "$S\lib\Streams.ps1"; . "$S\lib\Inbox.ps1"; . "$S\lib\Suites.ps1"; . "$S\lib\Activation.ps1"
        $d = Read-Tasks (Get-StreamPaths $at96); "$((Get-GroupSet $d 'A2').Contains('A2.X'))"; (@(Get-GroupBuildRows $d 'A2') | ForEach-Object id) -join ',' }
    Case '96 a pulled-forward group''s own rows decide its run coverage although its group set is empty' ($atg96[0] -eq 'False' -and $atg96[1] -eq 'A2.X') ($atg96 -join ' ; ')
    $atd96 = Join-Path $at96 '.streams\suites\runs'; New-Item -ItemType Directory -Path $atd96 -Force | Out-Null
    @{ id = 'run-A1-1'; tier = '2'; group = 'A1'; groups = @('A1'); reason = 'complete'; startedAt = '2026-10-19T10:00:00Z'; status = 'done'; head = 'abc' } | ConvertTo-Json | Set-Content (Join-Path $atd96 'run-A1-1.json') -Encoding utf8
    @{ id = 'run-A1-2'; tier = '2'; group = 'A1'; groups = @('A1'); reason = 'manual'; startedAt = '2026-10-19T12:00:00Z'; status = 'running'; head = 'abc' } | ConvertTo-Json | Set-Content (Join-Path $atd96 'run-A1-2.json') -Encoding utf8
    $ata96 = @(& "$S\Add-SuiteRunGroup.ps1" -Repo $at96 -Session integ-t -Run run-A1-1 -Group A2) -join ' | '
    $atb96 = @(& "$S\Add-SuiteRunGroup.ps1" -Repo $at96 -Session integ-t -Run run-A1-1 -Group A2) -join ' | '
    $atc96 = @(& "$S\Add-SuiteRunGroup.ps1" -Repo $at96 -Session integ-t -Run run-A1-1 -Group A3) -join ' | '; $atcx96 = $LASTEXITCODE
    $atr96 = @(& "$S\Add-SuiteRunGroup.ps1" -Repo $at96 -Session integ-t -Run run-A1-2 -Group A2) -join ' | '; $atrx96 = $LASTEXITCODE
    $atk96 = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"; (@(Get-SuiteRunRecords (Get-StreamPaths $at96) 'A2' '2') | ForEach-Object { $_['id'] }) -join ',' }
    Case '96 Add-SuiteRunGroup counts a finished run for a landed group once, refuses an unlanded group and a running run' ($ata96 -eq 'ATTACHED run-A1-1 A2' -and $atb96 -match '^ALREADY' -and $atc96 -match '^NOT-COVERED A3\.Z\(ticketed\)' -and $atcx96 -eq 2 -and $atr96 -match '^RUN-RUNNING' -and $atrx96 -eq 4 -and $atk96 -eq 'run-A1-1') "$ata96 // $atb96 // $atc96 ($atcx96) // $atr96 ($atrx96) // $atk96"
    # The owner of a failing file is the LATEST LANDED row that holds it: code on main was broken by a landed row, and
    # an open later-group row on the same file must not turn this group's regression into a 'later' known failure.
    $own = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"
        $h = { param($at) @(@{ at = $at; by = 'x'; to = 'integrated' }) }
        $od = @{ tasks = @(@{ id = 'T1.A'; group = 'T1'; kind = 'code'; state = 'integrated'; writeSet = @('tests/X.cs'); history = (& $h '2026-10-02T00:00:00Z') },
                           @{ id = 'T1.Z'; group = 'T1'; kind = 'code'; state = 'done'; writeSet = @('tests/X.cs'); history = (& $h '2026-10-03T00:00:00Z') },
                           @{ id = 'T1.Y'; group = 'T1'; kind = 'code'; state = 'integrated'; writeSet = @('tests/X.cs'); history = (& $h '2026-10-01T00:00:00Z') },
                           @{ id = 'T2.O'; group = 'T2'; kind = 'code'; state = 'ticketed'; writeSet = @('tests/X.cs'); history = @() },
                           @{ id = 'T2.P'; group = 'T2'; kind = 'code'; state = 'ticketed'; writeSet = @('tests/P.cs'); history = @() }) }
        (Find-OwnerRow $od 'tests/X.cs').id; (Find-OwnerRow $od 'tests/P.cs').id }
    Case '96 a failure is owned by the latest landed row on its file, an open row only when none landed' ($own[0] -eq 'T1.Z' -and $own[1] -eq 'T2.P') ($own -join ' ; ')
    $tasks1 = @((J $tr).tasks)
    $fx = @($tasks1 | Where-Object { $_.id -like 'T1.R1F*' })
    Case '96 a this-group failure becomes one fix task on its file' ($fx.Count -eq 1 -and $fx[0].origin -eq 'integration' -and @($fx[0].writeSet) -contains 'tests/FooTests.cs' -and $fx[0].title -match 'Real' -and $fx[0].title -notmatch 'Flaky') (($fx | ConvertTo-Json -Compress -Depth 4))
    $kft = Get-Content -Raw (Join-Path $tr '.streams\suites\known-failures.T2.json') -ErrorAction SilentlyContinue | ConvertFrom-Json
    Case '96 a later group''s failure lands in its known failures, not a fix task' (@($kft | Where-Object { $_.test -eq 'NS.LaterTests.L' }).Count -eq 1 -and -not @($tasks1 | Where-Object { $_.title -match 'LaterTests' }).Count) ($kft | ConvertTo-Json -Compress)
    $kfd = @(& "$S\Activate-Group.ps1" -Repo $tr -Session integ-t -Group T2 -DryRun)
    Case '96 it becomes a fix task at that group''s activation' (($kfd -join ' ') -match 'KNOWN-FAILURE T2\.KF1 NS\.LaterTests\.L') ($kfd -join ' | ')
    $flk = Get-Content -Raw (Join-Path $tr '.streams\suites\flaky.json') | ConvertFrom-Json
    Case '96 the flaky candidate is recorded' ($null -ne $flk.tests.'NS.FooTests.Flaky' -and $flk.tests.'NS.FooTests.Flaky'.first -eq 'run-T1-1') ($flk | ConvertTo-Json -Compress -Depth 5)
    $c1 = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T1 -DryRun); $c1x = $LASTEXITCODE
    Case '96 the close is refused while the fix is open and the failure unretested' ($c1x -eq 1 -and ($c1 -join ' ') -match 'OPEN-FIX' -and ($c1 -join ' ') -match 'UNRETESTED') ($c1 -join ' | ')
    # A non-fix patch after the run makes the run stale.
    $runStart = [datetime]::Parse([string]$run1.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
    $after = $runStart.AddSeconds(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $d = J $tr; ($d.tasks | Where-Object { $_.id -eq 'T1.B' }).history += @{ at = $after; by = 'integ-t'; to = 'integrated'; note = 'late' }
    $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8
    $c2 = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T1 -DryRun)
    Case '96 the close is refused when the latest Tier 2 predates the last non-fix patch' (($c2 -join ' ') -match 'TIER2-STALE run-T1-1' -and ($c2 -join ' ') -match 'NON-FIX-AFTER-RUN T1\.B') ($c2 -join ' | ')
    $d = J $tr; $tb = $d.tasks | Where-Object { $_.id -eq 'T1.B' }; $tb.history = @($tb.history | Select-Object -First 1)
    # The fix lands after the run; a Tier 3 retest runs only the attributed failure and passes it.
    $tf = $d.tasks | Where-Object { $_.id -eq $fx[0].id }; $tf.state = 'integrated'; $tf.history += @{ at = $after; by = 'integ-t'; to = 'integrated'; note = 'fix landed' }
    $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8
    & $setCtl @{ 'NS.FooTests.Flaky' = 'Failed'; 'NS.FooTests.Real' = 'Failed'; 'NS.LaterTests.L' = 'Failed'; 'NS.BarTests.Ok' = 'Passed' } @{ 'NS.FooTests.Flaky' = 'Passed'; 'NS.FooTests.Real' = 'Passed'; 'NS.LaterTests.L' = 'Failed'; 'NS.BarTests.Ok' = 'Passed' }
    $r3 = @(& "$S\Invoke-Retest.ps1" -Repo $tr -Session integ-t -Group T1 -Mode fix)
    $rt2 = Get-Content -Raw (Join-Path $rdir 'retest-T1-2.json') | ConvertFrom-Json
    $rt2leg = @($rt2.legs | Where-Object { $_.step -eq 'leg' })
    Case '96 a Tier 3 retest runs only this group''s attributed failures and passes' (($r3 -join ' ') -match 'RETEST retest-T1-2 pass passed 1 failed 0' -and $rt2.tier -eq '3' -and @($rt2.tests).Count -eq 1 -and $rt2.tests[0] -eq 'NS.FooTests.Real' -and $rt2leg.Count -eq 1 -and $rt2leg[0].command -notmatch 'LaterTests|Flaky') (($r3 -join ' | ') + ' ' + ($rt2.legs | ConvertTo-Json -Compress))
    # A Tier 3 snapshot is a fresh copy of main: without the run definition's setup (npm ci, the build) a Playwright
    # retest cannot start, so its failures could never pass.
    $rt2setup = @($rt2.legs | Where-Object { $_.step -eq 'setup' -and $_.name -eq 'mark' -and $_.exit -eq 0 })
    Case '96 a Tier 3 retest runs the run definition''s setup on its new snapshot first' ($rt2setup.Count -eq 1 -and (Test-Path (Join-Path ([string]$rt2.snapshot) 'setup.txt'))) ($rt2.legs | ConvertTo-Json -Compress)
    $c3 = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T1 -DryRun); $c3x = $LASTEXITCODE
    Case '96 the close passes with a late fix that has a Tier 3' ($c3x -eq 0 -and ($c3 -join ' ') -match 'CLOSE-OK T1 tier2 run-T1-1 retests 1') ($c3 -join ' | ')
    # Step C as a script (kit item IN-20261006110728-8c21): the close takes its rows by the group FIELD, so a row moved in
    # from another group (T0.X) goes to done with the rest. The coordinator that closed G3 by hand matched 'G3.*' ids.
    $cgd = @(& "$S\Close-Group.ps1" -Repo $tr -Session integ-t -Group T1 -DryRun); $cgdx = $LASTEXITCODE; $cgdt = $cgd -join ' | '
    Case '101 Close-Group dry-run on CLOSE-OK names every row by its group field and writes nothing' ($cgdx -eq 0 -and $cgdt -match 'DONE T0\.X' -and $cgdt -match 'DONE T1\.A' -and $cgdt -match 'DONE T1\.I' -and $cgdt -match 'DRY-RUN close T1 rows \d+; rows whose id prefix is not T1: T0\.X' -and (T $tr 'T0.X').state -eq 'integrated' -and (@((J $tr).groups | Where-Object { $_.id -eq 'T1' }))[0].state -ne 'closed') $cgdt
    $tasksKeep = [IO.File]::ReadAllText((Join-Path $tr '.streams\tasks.json'))
    $cg = @(& "$S\Close-Group.ps1" -Repo $tr -Session integ-t -Group T1); $cgx = $LASTEXITCODE; $cgt = $cg -join ' | '
    $cgOpen = @((J $tr).tasks | Where-Object { $_.group -eq 'T1' -and $_.state -ne 'done' } | ForEach-Object id)
    $cgDec = Get-Content -Raw (Join-Path $tr '.streams\decisions.md')
    Case '101 Close-Group on CLOSE-OK closes the group and moves every row of it to done, id prefix or not' ($cgx -eq 0 -and $cgt -match 'CLOSED T1 rows' -and -not $cgOpen.Count -and (@((J $tr).groups | Where-Object { $_.id -eq 'T1' }))[0].state -eq 'closed' -and $cgDec -match 'GROUP T1 CLOSED by Close-Group\.ps1 .*T0\.X') "$cgt open=$($cgOpen -join ',')"
    [IO.File]::WriteAllText((Join-Path $tr '.streams\tasks.json'), $tasksKeep)
    $cgr = @(& "$S\Close-Group.ps1" -Repo $tr -Session integ-t -Group T2); $cgrx = $LASTEXITCODE
    Case '101 Close-Group refuses a group Test-GroupClose does not pass, and writes nothing' ($cgrx -eq 1 -and ($cgr -join ' ') -match 'NOT-CLOSED T2' -and (@((J $tr).groups | Where-Object { $_.id -eq 'T2' }))[0].state -ne 'closed' -and [IO.File]::ReadAllText((Join-Path $tr '.streams\tasks.json')) -eq $tasksKeep) ($cgr -join ' | ')
    # The integration row's own grader is part of the close (kit item IN-20261009024507-d229): CLOSE-OK never looked at
    # the close-out work G5.T900's ticket asked for, so a failing grader there must refuse the close and write nothing.
    $gd101 = Join-Path $tr '.streams\graders'; New-Item -ItemType Directory -Path $gd101 -Force | Out-Null
    $gp101 = Join-Path $gd101 'T1.I.ps1'
    Set-Content -LiteralPath $gp101 -Encoding utf8 -Value "param([string]`$Root)`n'FAIL C1: evidence matrix missing'; exit 1"
    $d = J $tr; ($d.tasks | Where-Object { $_.id -eq 'T1.I' }).artifacts = @{ grader = '.streams\graders\T1.I.ps1' }
    $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8
    $tasksG = [IO.File]::ReadAllText((Join-Path $tr '.streams\tasks.json'))
    $cgg0 = @(& "$S\Close-Group.ps1" -Repo $tr -Session integ-t -Group T1 -DryRun); $cgg0t = $cgg0 -join ' | '
    Case '101 Close-Group dry-run names the integration row''s grader and does not run it' ($LASTEXITCODE -eq 0 -and $cgg0t -match 'GRADER T1\.I would run' -and -not (Test-Path (Join-Path $tr '.streams\logs\T1.I.grader.close.txt'))) $cgg0t
    $cgg = @(& "$S\Close-Group.ps1" -Repo $tr -Session integ-t -Group T1); $cggx = $LASTEXITCODE; $cggt = $cgg -join ' | '
    Case '101 Close-Group refuses when the integration row''s grader fails, and writes nothing' ($cggx -eq 1 -and $cggt -match 'NOT-CLOSED T1 : the integration task T1\.I''s grader failed' -and $cggt -notmatch 'CLOSED T1 rows' -and [IO.File]::ReadAllText((Join-Path $tr '.streams\tasks.json')) -eq $tasksG) $cggt
    Set-Content -LiteralPath $gp101 -Encoding utf8 -Value "param([string]`$Root)`n'PASS C1: evidence matrix present'; exit 0"
    $cgg2 = @(& "$S\Close-Group.ps1" -Repo $tr -Session integ-t -Group T1); $cgg2x = $LASTEXITCODE; $cgg2t = $cgg2 -join ' | '
    Case '101 Close-Group closes once the integration row''s grader passes' ($cgg2x -eq 0 -and $cgg2t -match 'GRADER T1\.I passed' -and $cgg2t -match 'CLOSED T1 rows' -and (T $tr 'T1.I').state -eq 'done') $cgg2t
    [IO.File]::WriteAllText((Join-Path $tr '.streams\tasks.json'), $tasksKeep); Remove-Item -LiteralPath $gp101 -Force
    # Repair: a group already closed with rows left integrated (the G3 state on 2026-10-06). Integrated rows go to done;
    # a row in another state is reported, never moved.
    $d = J $tr; (@($d.groups | Where-Object { $_.id -eq 'T1' }))[0].state = 'closed'; $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8
    $cgp = @(& "$S\Close-Group.ps1" -Repo $tr -Session integ-t -Group T1); $cgpx = $LASTEXITCODE; $cgpt = $cgp -join ' | '
    Case '101 Close-Group repairs a closed group: integrated rows to done, any other state reported as ANOMALY' ($cgpx -eq 2 -and $cgpt -match 'DONE T0\.X' -and $cgpt -match 'REPAIRED T1 rows' -and $cgpt -match 'ANOMALY T1\.I building' -and (T $tr 'T0.X').state -eq 'done' -and (T $tr 'T1.I').state -eq 'building') $cgpt
    [IO.File]::WriteAllText((Join-Path $tr '.streams\tasks.json'), $tasksKeep)
    # A leg that crashed before writing results is one 'leg:<name>' row with no owner: the run gave that leg no coverage,
    # so the close needs a new Tier 2 run, not a planner item.
    $resPath1 = Join-Path $rdir 'run-T1-1.results.json'; $resKeep1 = [IO.File]::ReadAllText($resPath1)
    $rx1 = $resKeep1 | ConvertFrom-Json -AsHashtable; $rx1.tests += @{ test = 'leg:Playwright'; suite = 'Playwright'; outcome = 'failed'; durationMs = 0; file = ''; project = ''; head = '' }
    $rx1 | ConvertTo-Json -Depth 10 | Set-Content $resPath1 -Encoding utf8
    $cl = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T1 -DryRun); $clx = $LASTEXITCODE
    [IO.File]::WriteAllText($resPath1, $resKeep1)
    Case '96 a leg that crashed in the latest Tier 2 run refuses the close' ($clx -eq 1 -and ($cl -join ' ') -match 'LEG-CRASHED run-T1-1 .*leg:Playwright') ($cl -join ' | ')
    # A gates-only group (review gates plus its integration row, G15; kit item IN-20261020234526-74b6) has no build row a
    # suite could cover, so it closes on its gates with no Tier 2 run; a group that has a build row still needs one.
    $tasksKeep9 = [IO.File]::ReadAllText((Join-Path $tr '.streams\tasks.json'))
    $d = J $tr | ConvertTo-Json -Depth 20 | ConvertFrom-Json -AsHashtable
    $d.groups += @{ id = 'T9'; name = 'gates only'; state = 'released' }
    $d.tasks += @{ id = 'T9.G01'; group = 'T9'; kind = 'gate'; state = 'ticketed'; title = 'owner review'; writeSet = @(); dependsOn = @(); history = @() }
    $d.tasks += @{ id = 'T9.I'; group = 'T9'; kind = 'integration'; state = 'planned'; title = 'close T9'; writeSet = @(); dependsOn = @('T9.G01'); history = @() }
    $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8
    $g9a = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T9 -DryRun); $g9ax = $LASTEXITCODE
    $d = J $tr; ($d.tasks | Where-Object { $_.id -eq 'T9.G01' }).state = 'done'; $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8
    $g9b = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T9 -DryRun); $g9bx = $LASTEXITCODE
    $d = J $tr; ($d.tasks | Where-Object { $_.id -eq 'T9.G01' }).kind = 'code'; $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8
    $g9c = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T9 -DryRun); $g9cx = $LASTEXITCODE
    [IO.File]::WriteAllText((Join-Path $tr '.streams\tasks.json'), $tasksKeep9)
    Case '96 a gates-only group needs no Tier 2: only its open gate refuses, then CLOSE-OK tier2 none; a build row still needs one' ($g9ax -eq 1 -and ($g9a -join ' ') -match 'GATES-OPEN T9\.G01' -and ($g9a -join ' ') -notmatch 'NO-TIER2' -and $g9bx -eq 0 -and ($g9b -join ' ') -match '^CLOSE-OK T9 tier2 none retests 0' -and $g9cx -eq 1 -and ($g9c -join ' ') -match 'NO-TIER2') "$($g9a -join ' | ') // $($g9b -join ' | ') // $($g9c -join ' | ')"

    # Flaky promotion: the flaky test fails in two of the next five Tier 2 runs, and the second makes it a failure.
    & $setCtl @{ 'NS.FooTests.Flaky' = 'Failed'; 'NS.FooTests.Real' = 'Passed'; 'NS.LaterTests.L' = 'Failed'; 'NS.BarTests.Ok' = 'Passed' } @{ 'NS.FooTests.Flaky' = 'Passed'; 'NS.FooTests.Real' = 'Passed'; 'NS.LaterTests.L' = 'Failed'; 'NS.BarTests.Ok' = 'Passed' }
    $s2 = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session integ-t -Group T1 -Reason manual -Wait)
    $o2 = @{}; foreach ($x in (Get-Content -Raw (Join-Path $rdir 'run-T1-2.results.json') | ConvertFrom-Json).tests) { $o2[$x.test] = $x.outcome }
    Case '96 one more flaky failure inside the window stays flaky' ($o2['NS.FooTests.Flaky'] -eq 'flaky') ($s2 -join ' | ')
    $s3 = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session integ-t -Group T1 -Reason manual -Wait)
    $a3 = Get-Content -Raw (Join-Path $rdir 'run-T1-3.attribution.json') | ConvertFrom-Json
    $pf = @($a3.failures | Where-Object { $_.test -eq 'NS.FooTests.Flaky' })
    Case '96 the second failure in five runs promotes it to a fix task' (($s3 -join ' ') -match 'FLAKY-PROMOTED NS\.FooTests\.Flaky' -and $pf.Count -eq 1 -and $pf[0].disposition -eq 'fix' -and $pf[0].flakyPromoted -and $pf[0].fixTask) (($s3 -join ' | ') + ' ' + ($a3 | ConvertTo-Json -Compress -Depth 4))
    $kft3 = @(Get-Content -Raw (Join-Path $tr '.streams\suites\known-failures.T2.json') | ConvertFrom-Json)
    Case '96 a known failure seen again is not recorded twice' (@($kft3 | Where-Object { $_.test -eq 'NS.LaterTests.L' }).Count -eq 1) ($kft3 | ConvertTo-Json -Compress)
    # Tier 3 retests a failure only once a fix for it has landed since its last retest; a failing retest files the next
    # fix attempt; three failed attempts block the group.
    & $setCtl @{ 'NS.FooTests.Flaky' = 'Failed' } @{ 'NS.FooTests.Flaky' = 'Failed' }
    $land = { param($id) Start-Sleep -Seconds 1; $d = J $tr; $t = $d.tasks | Where-Object { $_.id -eq $id }; $t.state = 'integrated'
        $t.history += @{ at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'integ-t'; to = 'integrated'; note = 'fix landed' }
        $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8; Start-Sleep -Seconds 1 }
    $fix3 = [string]$pf[0].fixTask
    $q0 = @(& "$S\Invoke-Retest.ps1" -Repo $tr -Session integ-t -Group T1 -Mode fix)
    Case '96 a failure whose fix has not landed is not retested' (($q0 -join ' ') -match 'RETEST-NOTHING') ($q0 -join ' | ')
    & $land $fix3
    $q1 = @(& "$S\Invoke-Retest.ps1" -Repo $tr -Session integ-t -Group T1 -Mode fix)
    $refix1 = if (($q1 -join ' ') -match 'REFIX NS\.FooTests\.Flaky (\S+)') { $Matches[1] } else { '' }
    $rf1 = if ($refix1) { T $tr $refix1 } else { $null }
    Case '96 a failing Tier 3 files the next fix attempt on the same file' (($q1 -join ' ') -match 'RETEST retest-T1-\d+ fail' -and $rf1 -and $rf1.origin -eq 'integration' -and @($rf1.writeSet) -contains 'tests/FooTests.cs') (($q1 -join ' | ') + ' ' + ($rf1 | ConvertTo-Json -Compress -Depth 4))
    $q2 = @(& "$S\Invoke-Retest.ps1" -Repo $tr -Session integ-t -Group T1 -Mode fix)
    $c4a = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T1 -DryRun); $c4ax = $LASTEXITCODE
    Case '96 no retest runs again until the next attempt lands, and one failure blocks nothing' (($q2 -join ' ') -match 'RETEST-NOTHING' -and $c4ax -eq 1) (($q2 -join ' | ') + ' / ' + ($c4a -join ' | '))
    & $land $refix1
    $q3 = @(& "$S\Invoke-Retest.ps1" -Repo $tr -Session integ-t -Group T1 -Mode fix)
    $refix2 = if (($q3 -join ' ') -match 'REFIX NS\.FooTests\.Flaky (\S+)') { $Matches[1] } else { 'none' }
    & $land $refix2
    $q4 = @(& "$S\Invoke-Retest.ps1" -Repo $tr -Session integ-t -Group T1 -Mode fix)
    Case '96 the third failed attempt files no fourth' (($q4 -join ' ') -match 'RETEST retest-T1-\d+ fail' -and ($q4 -join ' ') -notmatch 'REFIX') (($q3 -join ' | ') + ' / ' + ($q4 -join ' | '))
    $c4 = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T1 -Session integ-t); $c4x = $LASTEXITCODE
    $tq = Get-Content -Raw (Join-Path $tr '.streams\owner\questions.md') -ErrorAction SilentlyContinue
    Case '96 three consecutive failing Tier 3 retests block the group and ask the owner' ($c4x -eq 3 -and ($c4 -join ' ') -match 'CLOSE-BLOCKED T1 NS\.FooTests\.Flaky' -and (@((J $tr).groups | Where-Object { $_.id -eq 'T1' }))[0].state -eq 'blocked' -and $tq -match 'CLOSE-BLOCKED T1 NS\.FooTests\.Flaky') (($c4 -join ' | ') + ' ' + $tq)
    Case '96 the CLOSE-BLOCKED owner line carries local time with the zone, not UTC' ($tq -match '(?m)^- \d{4}-\d\d-\d\d \d\d:\d\d [A-Za-z]+ CLOSE-BLOCKED T1 ') $tq
    # The owner's way out: -Unblock releases the group, starts the strike count again and files the next fix attempt.
    $ub = @(); $ubx = -1; try { $ub = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T1 -Session owner -Unblock); $ubx = $LASTEXITCODE } catch { $ub = @("threw: $(("$_" -split "`n")[0])") }
    $c5 = @(& "$S\Test-GroupClose.ps1" -Repo $tr -Group T1 -DryRun); $c5x = $LASTEXITCODE
    $refix3 = if (($ub -join ' ') -match 'REFIX NS\.FooTests\.Flaky (\S+)') { $Matches[1] } else { '' }
    Case '96 -Unblock restores the group, resets the strikes and files the next attempt' ($ubx -eq 0 -and (@((J $tr).groups | Where-Object { $_.id -eq 'T1' }))[0].state -eq 'integrating' -and $refix3 -and $c5x -eq 1 -and ($c5 -join ' ') -notmatch 'CLOSE-BLOCKED') (($ub -join ' | ') + ' / ' + ($c5 -join ' | '))

    # Nightly: a running run skips it; a live integrator lock makes it yield with one inbox item; one per 01:00 window.
    @{ id = 'run-T1-90'; tier = '2'; group = 'T1'; reason = 'manual'; window = ''; startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); status = 'running' } | ConvertTo-Json | Set-Content (Join-Path $rdir 'run-T1-90.json')
    $n1 = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session suite-nightly -Group T1 -Reason nightly); $n1x = $LASTEXITCODE
    Case '96 a running run makes the nightly skip' ($n1x -eq 4 -and ($n1 -join ' ') -match 'RUN-BUSY run-T1-90') ($n1 -join ' | ')
    # Tier 3 never runs beside a Tier 2 run: its new snapshot would supersede the running one.
    $rb = @(& "$S\Invoke-Retest.ps1" -Repo $tr -Session integ-t -Group T1 -Mode fix); $rbx = $LASTEXITCODE
    Case '96 a Tier 3 retest refuses while a Tier 2 run is running' ($rbx -eq 4 -and ($rb -join ' ') -match 'RUN-BUSY run-T1-90') ($rb -join ' | ')
    Remove-Item (Join-Path $rdir 'run-T1-90.json')
    $n2 = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session suite-nightly -Group T1 -Reason nightly); $n2x = $LASTEXITCODE
    $n3 = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session suite-nightly -Group T1 -Reason nightly)
    $ii = @(Get-Content (Join-Path $tr '.streams\inbox\stream-integrate.md') -ErrorAction SilentlyContinue | Where-Object { $_ -match 'Start the nightly Tier 2 run' })
    Case '96 a live integrator lock makes the nightly yield with one inbox item' ($n2x -eq 3 -and ($n2 -join ' ') -match 'YIELDED .*filed' -and ($n3 -join ' ') -match 'already open' -and $ii.Count -eq 1) (($n2 -join ' | ') + ' / ' + ($n3 -join ' | ') + " items=$($ii.Count)")
    $win = (Get-Date).AddHours(-1).ToString('yyyy-MM-dd')
    @{ id = 'run-T1-91'; tier = '2'; group = 'T1'; reason = 'nightly'; window = $win; startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); status = 'done' } | ConvertTo-Json | Set-Content (Join-Path $rdir 'run-T1-91.json')
    $n4 = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session integ-t -Group T1 -Reason nightly); $n4x = $LASTEXITCODE
    Case '96 one nightly per 01:00 window' ($n4x -eq 0 -and ($n4 -join ' ') -match "SKIP-NIGHTLY .*$win") ($n4 -join ' | ')
    # A run whose process is gone (a reboot, a killed unit) is abandoned, never left blocking every later run.
    $dead = Start-Process pwsh -ArgumentList '-NoProfile', '-Command', 'exit 0' -PassThru -WindowStyle Hidden; $dead.WaitForExit()
    @{ id = 'run-T1-92'; tier = '2'; group = 'T1'; reason = 'manual'; window = ''; startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); status = 'running'
       pid = $dead.Id; pidStart = $dead.StartTime.ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $rdir 'run-T1-92.json')
    $n5 = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session integ-t -Group T1 -Reason nightly); $n5x = $LASTEXITCODE
    $r92 = Get-Content -Raw (Join-Path $rdir 'run-T1-92.json') | ConvertFrom-Json
    Case '96 a running record whose process is gone is abandoned, not RUN-BUSY' ($n5x -eq 0 -and ($n5 -join ' ') -match 'ABANDONED run-T1-92' -and ($n5 -join ' ') -match 'SKIP-NIGHTLY' -and $r92.status -eq 'abandoned') (($n5 -join ' | ') + ' status=' + $r92.status)
    # The scheduled task's own command line, run the way Task Scheduler runs it (CreateProcess with that argument line).
    $rn = @(& "$S\Register-NightlySuite.ps1" -Repo $tr -DryRun)
    $exe = (($rn | Where-Object { $_ -match '^\s+exe: ' }) -replace '^\s+exe: ', '') | Select-Object -First 1
    $argl = (($rn | Where-Object { $_ -match '^\s+args: ' }) -replace '^\s+args: ', '') | Select-Object -First 1
    Case '96 the nightly task runs the nightly wrapper at 01:00' (($rn -join ' ') -match "DRY-RUN task 'Speedy Tier2 nightly tierrepo' daily at 01:00" -and $argl -match 'Invoke-NightlySuite\.ps1') ($rn -join ' | ')
    $nlog = Join-Path $tr '.streams\logs\suite-nightly.txt'; Remove-Item $nlog -ErrorAction SilentlyContinue
    $np = $null
    if ($exe) { $psi = [Diagnostics.ProcessStartInfo]::new([string]$exe, [string]$argl); $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true; $psi.WorkingDirectory = $tr
        $np = [Diagnostics.Process]::Start($psi); [void]$np.WaitForExit(120000) }
    $nl = if (Test-Path $nlog) { Get-Content -Raw $nlog } else { '' }
    Case '96 the nightly command line runs and logs time-stamped output' ($nl -match '(?m)^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2} \S' -and $nl -notmatch 'ParserError') "exit=$(if ($np) { $np.ExitCode }) log=$nl"
    # A registration Task Scheduler refuses (non-elevated pwsh, S4U principal: 'Access is denied') is REFUSED, never
    # REGISTERED. The ScheduledTasks cmdlets live in a module that does not see this script's ErrorActionPreference, so
    # their error is non-terminating unless -ErrorAction Stop is passed. The stand-in prints the error and goes on then.
    # Those cmdlets are CDXML functions, so the stand-ins are imported after the real module, or its autoload shadows them.
    Import-Module ScheduledTasks
    $kitT96 = New-Module -Name kitT96 -ScriptBlock {
        function Register-ScheduledTask { [CmdletBinding()] param($TaskName, $Action, $Trigger, $Principal, $Settings, [switch] $Force)
            if ($env:KIT_T96_REG -eq 'silent') { return }
            if ($PSBoundParameters['ErrorAction'] -eq 'Stop') { throw 'Access is denied.' }
            [Console]::Error.WriteLine('Access is denied.') }
        function Get-ScheduledTask { [CmdletBinding()] param($TaskName) }
    } | Import-Module -PassThru
    $env:KIT_T96_REG = 'deny'; $rd = @(& "$S\Register-NightlySuite.ps1" -Repo $tr 2>&1 | ForEach-Object { "$_" }); $rdx = $LASTEXITCODE
    Case '96 a denied nightly registration is REFUSED, not REGISTERED' ($rdx -ne 0 -and ($rd -join ' ') -match 'REFUSED .*elevated' -and ($rd -join ' ') -notmatch 'REGISTERED') "exit=$rdx $($rd -join ' | ')"
    $env:KIT_T96_REG = 'silent'; $rs = @(& "$S\Register-NightlySuite.ps1" -Repo $tr 2>&1 | ForEach-Object { "$_" }); $rsx = $LASTEXITCODE
    Case '96 a registration that leaves no task is REFUSED' ($rsx -ne 0 -and ($rs -join ' ') -match 'REFUSED .*not found' -and ($rs -join ' ') -notmatch 'REGISTERED') "exit=$rsx $($rs -join ' | ')"
    Remove-Module $kitT96; Remove-Item Env:\KIT_T96_REG
    # An empty trx (a filter that matched nothing) and a namespaced one, as VSTest writes them, export without a throw.
    # These trx-only fixtures have no test project behind them, so their records are not tier 2: only a Tier 2 run's legs
    # are discovered from its build (owner 2026-10-28), which the TX-3 case below covers.
    $rx = Join-Path $rdir 'run-TX-1'; New-Item -ItemType Directory -Path (Join-Path $rx 'Empty'), (Join-Path $rx 'Full') -Force | Out-Null
    $ns = 'http://microsoft.com/schemas/VisualStudio/TeamTest/2010'
    Set-Content (Join-Path $rx 'Empty\e.trx') "<TestRun xmlns=`"$ns`"><Results /></TestRun>"
    Set-Content (Join-Path $rx 'Full\f.trx') "<TestRun xmlns=`"$ns`"><TestDefinitions><UnitTest id=`"1`"><TestMethod className=`"NS.Q`" name=`"M`" /></UnitTest></TestDefinitions><Results><UnitTestResult testId=`"1`" testName=`"M`" outcome=`"Passed`" duration=`"00:00:00.1`" /></Results></TestRun>"
    @{ id = 'run-TX-1'; tier = 'fixture'; group = 'TX'; startedAt = '2026-10-01T00:00:00Z'; status = 'done'; snapshot = $tr; runDir = $rx; head = 'h'
       legs = @(@{ step = 'leg'; name = 'Empty'; kind = 'dotnet'; project = 'tests'; exit = 1 }, @{ step = 'leg'; name = 'Full'; kind = 'dotnet'; project = 'tests'; exit = 0 }) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $rdir 'run-TX-1.json')
    $ex = ''; $xo = @(); try { $xo = @(& "$S\Export-SuiteResults.ps1" -Repo $tr -Run run-TX-1) } catch { $ex = ("$_" -split "`n")[0] }
    Case '96 an empty or namespaced trx exports: the empty leg is one leg: failure' (-not $ex -and ($xo -join ' ') -match 'RESULTS run-TX-1 passed 1 failed 1') "err=$ex out=$($xo -join ' | ')"
    # Skipped tests (an [Ignore], or a live test's Assert.Inconclusive, both NotExecuted in a trx) are counted on their
    # own NOT-RUN line per leg, never as passes (TestRunFindings-2026-10-25 F6, kit item IN-20261025152845-1d06).
    $rx2 = Join-Path $rdir 'run-TX-2'; New-Item -ItemType Directory -Path (Join-Path $rx2 'Live') -Force | Out-Null
    Set-Content (Join-Path $rx2 'Live\l.trx') "<TestRun xmlns=`"$ns`"><TestDefinitions><UnitTest id=`"1`"><TestMethod className=`"NS.L`" name=`"A`" /></UnitTest><UnitTest id=`"2`"><TestMethod className=`"NS.L`" name=`"B`" /></UnitTest><UnitTest id=`"3`"><TestMethod className=`"NS.L`" name=`"C`" /></UnitTest></TestDefinitions><Results><UnitTestResult testId=`"1`" testName=`"A`" outcome=`"Passed`" duration=`"00:00:00.1`" /><UnitTestResult testId=`"2`" testName=`"B`" outcome=`"NotExecuted`" duration=`"00:00:00.1`" /><UnitTestResult testId=`"3`" testName=`"C`" outcome=`"Inconclusive`" duration=`"00:00:00.1`" /></Results></TestRun>"
    @{ id = 'run-TX-2'; tier = 'fixture'; group = 'TX'; startedAt = '2026-10-01T00:00:00Z'; status = 'done'; snapshot = $tr; runDir = $rx2; head = 'h'
       legs = @(@{ step = 'leg'; name = 'Live'; kind = 'dotnet'; project = 'tests'; exit = 0 }) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $rdir 'run-TX-2.json')
    $ex2 = ''; $xo2 = @(); try { $xo2 = @(& "$S\Export-SuiteResults.ps1" -Repo $tr -Run run-TX-2) } catch { $ex2 = ("$_" -split "`n")[0] }
    Case '96 skipped tests are a counted NOT-RUN line per leg, never passes' (-not $ex2 -and ($xo2 -join ' ') -match 'RESULTS run-TX-2 passed 1 failed 0 skipped 2' -and ($xo2 -join ' ') -match 'NOT-RUN run-TX-2 2 test\(s\) skipped, not passes: Live 2') "err=$ex2 out=$($xo2 -join ' | ')"
    # A live proof (.streams\suites\Invoke-Tier2Proof.ps1) that failed or timed out is named on a PROOF-FAILED line, so
    # its Inconclusive tests are read as not run for that reason; an ok proof is not listed (kit item IN-20261026151607-13e0).
    $px = Join-Path $rx2 'proofs'; New-Item -ItemType Directory -Path $px -Force | Out-Null
    @{ name = 'store-change'; variable = 'SM_STORE_CHANGE_OUT'; status = 'failed'; exit = 1; reason = 'exit 1' } | ConvertTo-Json | Set-Content (Join-Path $px 'store-change.json')
    @{ name = 'outage'; variable = 'SM_OUTAGE_OUT'; status = 'timeout'; exit = $null; reason = 'no exit after 1800 s; process tree ended' } | ConvertTo-Json | Set-Content (Join-Path $px 'outage.json')
    @{ name = 'fresh'; variable = 'SM_FRESH_OUT'; status = 'ok'; exit = 0; reason = '' } | ConvertTo-Json | Set-Content (Join-Path $px 'fresh.json')
    $ex3 = ''; $xo3 = @(); try { $xo3 = @(& "$S\Export-SuiteResults.ps1" -Repo $tr -Run run-TX-2) } catch { $ex3 = ("$_" -split "`n")[0] }
    $pf3 = @($xo3 | Where-Object { "$_" -match '^PROOF-FAILED ' })
    Case '96 a failed or timed-out live proof is named on a PROOF-FAILED line, an ok one is not' (-not $ex3 -and $pf3.Count -eq 1 -and $pf3[0] -match '^PROOF-FAILED run-TX-2 2 live proof\(s\) failed' -and $pf3[0] -match 'outage \(SM_OUTAGE_OUT, timeout: no exit after 1800 s' -and $pf3[0] -match 'store-change \(SM_STORE_CHANGE_OUT, failed: exit 1\)' -and $pf3[0] -notmatch 'fresh') "err=$ex3 out=$($xo3 -join ' | ')"
    # A Tier 2 run's total is discovered from its own build, never from another run (owner 2026-10-28). A leg whose build
    # cannot be discovered (here: no project) is a failed 'discover:<leg>' row and a DISCOVERY-FAILED line, never silent.
    $rx4 = Join-Path $rdir 'run-TX-3'; New-Item -ItemType Directory -Path (Join-Path $rx4 'Full') -Force | Out-Null
    Copy-Item (Join-Path $rx 'Full\f.trx') (Join-Path $rx4 'Full\f.trx')
    @{ id = 'run-TX-3'; tier = '2'; group = 'TX'; startedAt = '2026-10-01T00:00:00Z'; status = 'done'; snapshot = $tr; runDir = $rx4; head = 'h'
       legs = @(@{ step = 'leg'; name = 'Full'; kind = 'dotnet'; project = 'no-such-project'; exit = 0 }) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $rdir 'run-TX-3.json')
    $ex4 = ''; $xo4 = @(); try { $xo4 = @(& "$S\Export-SuiteResults.ps1" -Repo $tr -Run run-TX-3) } catch { $ex4 = ("$_" -split "`n")[0] }
    $res4 = Get-Content -Raw (Join-Path $rdir 'run-TX-3.results.json') | ConvertFrom-Json -AsHashtable
    $dr4 = @($res4['tests'] | Where-Object { $_['test'] -eq 'discover:Full' -and $_['outcome'] -eq 'failed' }).Count
    Case '96 a Tier 2 leg that cannot be discovered is a failed discover: row and a DISCOVERY-FAILED line' (-not $ex4 -and $dr4 -eq 1 -and ($xo4 -join ' ') -match 'RESULTS run-TX-3 passed 1 failed 1' -and ($xo4 -join ' ') -match 'DISCOVERY-FAILED run-TX-3 Full \(') "err=$ex4 out=$($xo4 -join ' | ')"
    # A nightly-started run hands the integrator lock back when it ends.
    Remove-Item (Join-Path $tr '.streams\integrator.lock') -ErrorAction SilentlyContinue
    Get-ChildItem $rdir -Filter 'run-T1-9*.json' | Remove-Item
    & $setCtl @{ 'NS.BarTests.Ok' = 'Passed' } @{ 'NS.BarTests.Ok' = 'Passed' }
    # Owner ruling IN-20261005230119-9a3d: a Tier 2 run is the test suites only. A run definition that still says
    # graders: true runs no grader (G3 run 1 spent 7 h 07 m of 10 h on graders, 67 of 71 red ones drift).
    $gdef = Get-Content -Raw (Join-Path $tr '.streams\suites\T1.run.json') | ConvertFrom-Json -AsHashtable; $gdef.graders = $true
    $gdef | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $tr '.streams\suites\T1.run.json') -Encoding utf8
    $gg = Join-Path $tr '.streams\graders\T1.B.ps1'; New-Item -ItemType Directory -Path (Split-Path $gg) -Force | Out-Null; Set-Content $gg 'exit 1'
    $d = J $tr; ($d.tasks | Where-Object { $_.id -eq 'T1.B' }).artifacts = @{ grader = '.streams\graders\T1.B.ps1' }; $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $tr '.streams\tasks.json') -Encoding utf8
    $nr = @(& "$S\Start-SuiteRun.ps1" -Repo $tr -Session suite-nightly -Group T1 -Reason manual -Wait)
    Case '96 a run started by suite-nightly releases the integrator lock when it ends' (($nr -join ' ') -match 'RUN-ENDED run-T1-\d+ done' -and -not (Test-Path (Join-Path $tr '.streams\integrator.lock'))) ($nr -join ' | ')
    $nrId = if (($nr -join ' ') -match 'RUN-ENDED (run-T1-\d+)') { $Matches[1] } else { 'none' }
    $nrRes = Get-Content -Raw (Join-Path $rdir "$nrId.results.json") -ErrorAction SilentlyContinue | ConvertFrom-Json
    Case '96 a Tier 2 run runs the test suites only, never the group''s graders' ($nrRes -and -not @($nrRes.tests | Where-Object { $_.test -like 'grader:*' }).Count) ($nrRes | ConvertTo-Json -Compress -Depth 4)

    # ---- 96p. Perf legs wait for a quiet host (kit item IN-20261010212643-92b1). retest-G4-6 measured canvas drag p95
    # 36.9 ms beside 5 author units, 5 build units and a G6 grader (2.8 ms solo) and counted it as Tier 3 strike 2 of 3.
    # A perf leg now runs only on a quiet host; one that never quiets is NOT-MEASURED: neither a pass nor a strike.
    # The probe is a control file (STREAM_QUIET_PROBE_FILE), so the cases do not depend on this host's load.
    $pr = Join-Path $Scratch 'perfrepo'; New-Item -ItemType Directory -Path (Join-Path $pr 'tests') -Force | Out-Null; $repos += $pr
    git -C $pr init -q -b main; git -C $pr config user.email t@t; git -C $pr config user.name t; Grant-GitPolicy $pr
    Set-Content (Join-Path $pr 'tests\PerfTests.cs') 'namespace NS { public class PerfTests { } }'
    git -C $pr add -A; git -C $pr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $pr | Out-Null
    $ctlP = Join-Path $Scratch 'fake-outcomes-perf.json'
    $setP = { param($t2, $rt) @{ tier2 = $t2; retest = $rt } | ConvertTo-Json | Set-Content $ctlP -Encoding utf8 }
    $probeP = Join-Path $Scratch 'quiet-probe.json'
    $setProbe = { param($cpu, [string[]] $busy) @{ cpu = $cpu; busy = @($busy) } | ConvertTo-Json | Set-Content $probeP -Encoding utf8 }
    $perfLeg = @{ name = 'Tests.Perf'; kind = 'dotnet'; project = 'tests'; solo = $true
        command = "& '$fake' -Out '{runDir}\Tests.Perf' -Mode tier2 -Control '$ctlP'"
        retestCommand = "& '$fake' -Out '{runDir}\Tests.Perf' -Mode retest -Filter '{filter}' -Control '$ctlP'" }
    New-Item -ItemType Directory -Path (Join-Path $pr '.streams\suites') -Force | Out-Null
    @{ group = 'P1'; copyIgnored = @(); setup = @(); legs = @($perfLeg); after = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $pr '.streams\suites\P1.run.json') -Encoding utf8
    @{ groups = @(@{ id = 'P1'; name = 'perf'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-P') } })
       tasks = @((& $Tt 'P1.A' 'P1' 'integrated' 'tests/PerfTests.cs'), (& $Tt 'P1.I' 'P1' 'ticketed' @() 'integration')) } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $pr '.streams\tasks.json') -Encoding utf8
    $env:STREAM_QUIET_PROBE_FILE = $probeP; $env:STREAM_QUIET_WINDOW_SECONDS = '0'; $env:STREAM_QUIET_SAMPLE_SECONDS = '0.2'; $env:STREAM_QUIET_MAX_WAIT_SECONDS = '1'
    try {
        $pl = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"
            (Test-PerfLeg @{ name = 'Playwright.Perf' }); (Test-PerfLeg @{ name = 'Playwright' }); (Test-PerfLeg @{ name = 'X.Perf'; solo = $false }); (Test-PerfLeg @{ name = 'Unit'; solo = $true }) }
        Case '96p a leg is a perf leg by its solo flag, or by Perf in its name when it has no flag' ($pl[0] -and -not $pl[1] -and -not $pl[2] -and $pl[3]) ($pl -join ',')
        $pP = Get-StreamPaths $pr
        & $setProbe 5 @()
        $wq = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"; Wait-QuietHost $pP }
        & $setProbe 5 @('main-grader.lock held (build-x)')
        $wl = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"; Wait-QuietHost $pP }
        & $setProbe 85 @()
        $wc = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"; Wait-QuietHost $pP }
        Case '96p a quiet host is quiet; a held main lock or high CPU is not, and says why' ($wq.quiet -and -not $wl.quiet -and $wl.why -match 'main-grader\.lock' -and -not $wc.quiet -and $wc.why -match 'cpu 85%') "q=$($wq.quiet) l=$($wl.quiet)/$($wl.why) c=$($wc.quiet)/$($wc.why)"
        $real = $null; $realErr = ''
        try { $real = & { $env:STREAM_QUIET_PROBE_FILE = ''; . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"; Get-HostLoadSample $pP } } catch { $realErr = ("$_" -split "`n")[0] } finally { $env:STREAM_QUIET_PROBE_FILE = $probeP }
        Case '96p the real probe reads CPU and the test processes without a throw' (-not $realErr -and $null -ne $real -and $real.cpu -ge 0 -and $null -ne $real.busy) "err=$realErr cpu=$($real.cpu) busy=$(@($real.busy) -join ';')"
        # An idle Visual Studio Test Explorer vstest.console.exe (parent DevHub.exe, 4 s CPU in all) held Playwright.Perf
        # from 09:02 at host CPU 0-6% (kit item IN-20261025141724-a801, F7). A test process under a VS host counts as
        # load only on first sight or when its CPU time grew past STREAM_QUIET_PROC_CPU_SECONDS (0.5) since the last sample.
        $ide = $null; $ideErr = ''
        try {
            $ide = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"
                (Test-IdleIdeTestProcess 'vstest.console.exe' @('DevHub.exe', 'devenv.exe') 4.0 4.0)
                (Test-IdleIdeTestProcess 'vstest.console.exe' @('DevHub.exe') 4.0 $null)
                (Test-IdleIdeTestProcess 'vstest.console.exe' @('DevHub.exe') 6.0 4.0)
                (Test-IdleIdeTestProcess 'vstest.console.exe' @('pwsh.exe', 'explorer.exe') 4.0 4.0)
                (Test-IdleIdeTestProcess 'testhost.exe' @('vstest.console.exe', 'ServiceHub.TestWindowStoreHost.exe') 1.2 1.0)
                (Test-IdleIdeTestProcess 'node.exe' @('devenv.exe') 1.0 1.0) }
        } catch { $ideErr = ("$_" -split "`n")[0] }
        Case '96p an idle test process under a VS host is not load; first sight, CPU growth, or no VS host still is' (-not $ideErr -and @($ide).Count -eq 6 -and $ide[0] -and -not $ide[1] -and -not $ide[2] -and -not $ide[3] -and $ide[4] -and -not $ide[5]) "err=$ideErr r=$(@($ide) -join ',')"

        # A loaded host: the Tier 2 perf leg does not run, and the close waits for a run that measured it.
        & $setP @{ 'NS.PerfTests.P95' = 'Failed' } @{ 'NS.PerfTests.P95' = 'Failed' }
        & $setProbe 70 @('node.exe pid 1')
        $pa = @(& "$S\Start-SuiteRun.ps1" -Repo $pr -Session integ-p -Group P1 -Reason manual -Wait); $pat = $pa -join ' | '
        $paId = if ($pat -match 'RUN-ENDED (run-P1-\d+)') { $Matches[1] } else { 'none' }
        $paRes = Get-Content -Raw (Join-Path $pr ".streams\suites\runs\$paId.results.json") -ErrorAction SilentlyContinue | ConvertFrom-Json
        $paAttr = Get-Content -Raw (Join-Path $pr ".streams\suites\runs\$paId.attribution.json") -ErrorAction SilentlyContinue | ConvertFrom-Json
        Case '96p a Tier 2 perf leg on a loaded host is NOT-MEASURED: no result, no failure, no fix task' ($pat -match 'NOT-MEASURED Tests\.Perf host not quiet' -and @($paRes.tests | Where-Object { $_.test -eq 'leg:Tests.Perf' -and $_.outcome -eq 'not-measured' }).Count -eq 1 -and -not @($paRes.tests | Where-Object { $_.outcome -eq 'failed' }).Count -and -not @($paAttr.failures).Count -and -not @((J $pr).tasks | Where-Object { $_.id -like 'P1.R*' }).Count) "$pat res=$($paRes | ConvertTo-Json -Compress -Depth 4)"
        $pc = @(& "$S\Test-GroupClose.ps1" -Repo $pr -Group P1 -DryRun); $pcx = $LASTEXITCODE
        Case '96p the close is refused while the latest Tier 2 left a perf leg NOT-MEASURED' ($pcx -eq 1 -and ($pc -join ' ') -match "NOT-MEASURED $paId never ran leg:Tests\.Perf") ($pc -join ' | ')
        # An owner ruling exempts the unmeasured leg (kit item IN-20261011013141-4283): rule 7 then skips it.
        $pe0 = @(& "$S\Test-GroupClose.ps1" -Repo $pr -Group P1 -Session integ-p -Exempt 'leg:Tests.Other' -Reason 'OWNER test'); $pe0x = $LASTEXITCODE
        $pe1 = @(& "$S\Test-GroupClose.ps1" -Repo $pr -Group P1 -Session integ-p -Exempt 'leg:Tests.Perf' -Reason 'OWNER 2026-10-11 (fixture): speed-only miss approved'); $pe1x = $LASTEXITCODE
        $peF = Join-Path $pr '.streams\suites\exempt.P1.json'
        $peJ = @(if (Test-Path $peF) { Get-Content -Raw $peF | ConvertFrom-Json })
        $pc1 = @(& "$S\Test-GroupClose.ps1" -Repo $pr -Group P1 -DryRun)
        Case '96p -Exempt leg:<name> records an owner exemption for a NOT-MEASURED leg, and rule 7 then skips it' ($pe0x -eq 2 -and ($pe0 -join ' ') -match 'NO-MATCH' -and $pe1x -eq 0 -and ($pe1 -join ' ') -match 'EXEMPTED P1 leg:Tests\.Perf' -and @($peJ | Where-Object { $_.test -eq 'leg:Tests.Perf' -and $_.run -eq $paId -and $_.reason -match 'OWNER' }).Count -eq 1 -and ($pc1 -join ' ') -notmatch 'NOT-MEASURED') "e0=$pe0x/$($pe0 -join ' ') e1=$pe1x/$($pe1 -join ' ') close=$($pc1 -join ' | ')"
        Remove-Item -LiteralPath $peF -Force -ErrorAction SilentlyContinue

        # A quiet host: the leg runs, its real failure becomes a fix task.
        & $setProbe 3 @()
        $pb = @(& "$S\Start-SuiteRun.ps1" -Repo $pr -Session integ-p -Group P1 -Reason manual -Wait); $pbt = $pb -join ' | '
        $pfx = @((J $pr).tasks | Where-Object { $_.id -like 'P1.R*' })
        Case '96p on a quiet host the perf leg runs and its failure becomes a fix task' ($pbt -match 'QUIET-HOST Tests\.Perf' -and $pfx.Count -eq 1) "$pbt fix=$($pfx.Count)"
        if ($pfx.Count) {
            Start-Sleep -Seconds 1
            $d = J $pr; $tf = $d.tasks | Where-Object { $_.id -eq $pfx[0].id }; $tf.state = 'integrated'
            $tf.history += @{ at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'integ-p'; to = 'integrated'; note = 'fix landed' }
            $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $pr '.streams\tasks.json') -Encoding utf8; Start-Sleep -Seconds 1
        }
        # Tier 3 on a loaded host: NOT-MEASURED, no strike, no next fix attempt.
        & $setProbe 60 @()
        $r1p = @(& "$S\Invoke-Retest.ps1" -Repo $pr -Session integ-p -Group P1 -Mode fix); $r1pt = $r1p -join ' | '
        $r1id = if ($r1pt -match 'RETEST (retest-P1-\d+) ') { $Matches[1] } else { 'none' }
        $r1rec = Get-Content -Raw (Join-Path $pr ".streams\suites\runs\$r1id.json") -ErrorAction SilentlyContinue | ConvertFrom-Json
        $pbId = if ($pbt -match 'RUN-ENDED (run-P1-\d+)') { $Matches[1] } else { 'none' }
        $strk = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"; @(Get-StrikeRetests $pP 'P1' $pbId 'NS.PerfTests.P95' $null).Count }
        Case '96p a Tier 3 perf retest on a loaded host is NOT-MEASURED: no strike and no next fix attempt' ($r1pt -match 'NOT-MEASURED Tests\.Perf 1 test' -and $r1pt -match "RETEST $r1id not-measured passed 0 failed 0" -and $r1pt -notmatch 'REFIX' -and -not @($r1rec.tests).Count -and @($r1rec.notMeasured) -contains 'NS.PerfTests.P95' -and $strk -eq 0) "$r1pt strikes=$strk rec=$($r1rec | ConvertTo-Json -Compress -Depth 4)"
        $pc2 = @(& "$S\Test-GroupClose.ps1" -Repo $pr -Group P1 -DryRun)
        Case '96p an unmeasured retest neither closes the group nor blocks it' (($pc2 -join ' ') -match 'UNRETESTED' -and ($pc2 -join ' ') -match "NO-TIER3 $(if ($pfx.Count) { $pfx[0].id })" -and ($pc2 -join ' ') -notmatch 'CLOSE-BLOCKED|CLOSE-OK') ($pc2 -join ' | ')
        # Quiet again: the same failure is retested with no new fix landing (the unmeasured retest never ran it), and passes.
        & $setP @{ 'NS.PerfTests.P95' = 'Failed' } @{ 'NS.PerfTests.P95' = 'Passed' }
        & $setProbe 2 @()
        $r2p = @(& "$S\Invoke-Retest.ps1" -Repo $pr -Session integ-p -Group P1 -Mode fix); $r2pt = $r2p -join ' | '
        $pc3 = @(& "$S\Test-GroupClose.ps1" -Repo $pr -Group P1 -DryRun); $pc3x = $LASTEXITCODE
        Case '96p on a quiet host the unmeasured failure is retested without a new fix, and its pass closes the group' ($r2pt -match 'QUIET-HOST Tests\.Perf' -and $r2pt -match 'RETEST retest-P1-\d+ pass passed 1 failed 0' -and $pc3x -eq 0 -and ($pc3 -join ' ') -match "CLOSE-OK P1 tier2 $pbId") "$r2pt / $($pc3 -join ' | ')"
    } finally {
        Remove-Item Env:\STREAM_QUIET_PROBE_FILE, Env:\STREAM_QUIET_WINDOW_SECONDS, Env:\STREAM_QUIET_SAMPLE_SECONDS, Env:\STREAM_QUIET_MAX_WAIT_SECONDS -ErrorAction SilentlyContinue
    }

    # ---- 96q. A retest that matches no test is NO-MATCH, never a failure (kit item IN-20261020004435-6e00). G14.R4F63
    # renamed a backup.spec title; retest-G14-3 grepped the old title, matched nothing, counted it as still failing and
    # filed G14.R4F37A2. Now the unmatched test leaves the record's tests for noMatch (no strike, no REFIX), one
    # stream-plan item names it, and a leg that crashed with no results still counts as failed.
    $nmr = Join-Path $Scratch 'nomatchrepo'; New-Item -ItemType Directory -Path (Join-Path $nmr 'tests') -Force | Out-Null; $repos += $nmr
    git -C $nmr init -q -b main; git -C $nmr config user.email t@t; git -C $nmr config user.name t; Grant-GitPolicy $nmr
    Set-Content (Join-Path $nmr 'tests\NmTests.cs') 'namespace NS { public class NmTests { } }'
    git -C $nmr add -A; git -C $nmr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $nmr | Out-Null
    $nmCtl = Join-Path $Scratch 'fake-outcomes-nm.json'
    $nmSet = { param($t2, $rt) @{ tier2 = $t2; retest = $rt } | ConvertTo-Json | Set-Content $nmCtl -Encoding utf8 }
    $nmLeg = @{ name = 'Tests.Unit'; kind = 'dotnet'; project = 'tests'
        command = "& '$fake' -Out '{runDir}\Tests.Unit' -Mode tier2 -Control '$nmCtl'"
        retestCommand = "& '$fake' -Out '{runDir}\Tests.Unit' -Mode retest -Filter '{filter}' -Control '$nmCtl'" }
    New-Item -ItemType Directory -Path (Join-Path $nmr '.streams\suites') -Force | Out-Null
    @{ group = 'Q1'; copyIgnored = @(); setup = @(); legs = @($nmLeg); after = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $nmr '.streams\suites\Q1.run.json') -Encoding utf8
    @{ groups = @(@{ id = 'Q1'; name = 'nomatch'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-Q') } })
       tasks = @((& $Tt 'Q1.A' 'Q1' 'integrated' 'tests/NmTests.cs'), (& $Tt 'Q1.I' 'Q1' 'ticketed' @() 'integration')) } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $nmr '.streams\tasks.json') -Encoding utf8
    & $nmSet @{ 'NS.NmTests.Kept' = 'Failed'; 'NS.NmTests.Old' = 'Failed' } @{}
    $nqa = @(& "$S\Start-SuiteRun.ps1" -Repo $nmr -Session integ-q -Group Q1 -Reason manual -Wait); $nqat = $nqa -join ' | '
    $nqId = if ($nqat -match 'RUN-ENDED (run-Q1-\d+)') { $Matches[1] } else { 'none' }
    $nqFix = @((J $nmr).tasks | Where-Object { $_.id -like 'Q1.R*' })
    if ($nqFix.Count) {
        Start-Sleep -Seconds 1
        $d = J $nmr; foreach ($tf in @($d.tasks | Where-Object { $_.id -like 'Q1.R*' })) { $tf.state = 'integrated'; $tf.history += @{ at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'integ-q'; to = 'integrated'; note = 'fix landed' } }
        $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $nmr '.streams\tasks.json') -Encoding utf8; Start-Sleep -Seconds 1
    }
    # The fix renamed Old to New: the retest's filter finds Kept (now passing) and nothing named Old.
    & $nmSet @{ 'NS.NmTests.Kept' = 'Failed'; 'NS.NmTests.Old' = 'Failed' } @{ 'NS.NmTests.Kept' = 'Passed'; 'NS.NmTests.New' = 'Passed' }
    $nq1 = @(& "$S\Invoke-Retest.ps1" -Repo $nmr -Session integ-q -Group Q1 -Mode fix); $nq1t = $nq1 -join ' | '
    $nq1id = if ($nq1t -match 'RETEST (retest-Q1-\d+) ') { $Matches[1] } else { 'none' }
    $nq1rec = Get-Content -Raw (Join-Path $nmr ".streams\suites\runs\$nq1id.json") -ErrorAction SilentlyContinue | ConvertFrom-Json
    $nqStrk = & { . "$S\lib\Streams.ps1"; . "$S\lib\Suites.ps1"; @(Get-StrikeRetests (Get-StreamPaths $nmr) 'Q1' $nqId 'NS.NmTests.Old' $null).Count }
    $nqPlan = @(& "$S\Get-InboxItems.ps1" -Repo $nmr -Skill stream-plan -Open) -join ' | '
    Case '96q a retest that matches no test by the failed name is NO-MATCH: no failure, no strike, no REFIX, one plan item' ($nqFix.Count -eq 1 -and $nq1t -match 'NO-MATCH NS\.NmTests\.Old' -and $nq1t -match "RETEST $nq1id pass passed 1 failed 0" -and $nq1t -notmatch 'REFIX' -and @($nq1rec.noMatch) -contains 'NS.NmTests.Old' -and @($nq1rec.tests) -notcontains 'NS.NmTests.Old' -and $nqStrk -eq 0 -and $nqPlan -match "NO-MATCH in $nq1id") "$nqat / $nq1t strikes=$nqStrk plan=$nqPlan"
    # A leg that crashes with no results is still a failure, and an already reported name is not filed again.
    Start-Sleep -Seconds 1
    $d = J $nmr; foreach ($tf in @($d.tasks | Where-Object { $_.id -like 'Q1.R*' })) { $tf.history += @{ at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'integ-q'; to = 'integrated'; note = 'fix landed again' } }
    $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $nmr '.streams\tasks.json') -Encoding utf8; Start-Sleep -Seconds 1
    $nmLeg['retestCommand'] = 'exit 3'
    @{ group = 'Q1'; copyIgnored = @(); setup = @(); legs = @($nmLeg); after = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $nmr '.streams\suites\Q1.run.json') -Encoding utf8
    $nq2 = @(& "$S\Invoke-Retest.ps1" -Repo $nmr -Session integ-q -Group Q1 -Mode fix); $nq2t = $nq2 -join ' | '
    $nqPlan2 = @(@(& "$S\Get-InboxItems.ps1" -Repo $nmr -Skill stream-plan -Open) | Where-Object { $_ -match 'NO-MATCH in' }).Count
    Case '96q a crashed retest leg still counts as failed (REFIX), and files no second NO-MATCH item' ($nq2t -match 'RETEST retest-Q1-\d+ fail passed 0 failed 1' -and $nq2t -match 'REFIX NS\.NmTests\.Old' -and $nq2t -notmatch 'NO-MATCH' -and $nqPlan2 -eq 1) "$nq2t plan=$nqPlan2"

    # ---- 97. Priority.html (3.4), Cost.html extras (3.5), history archive (E2).
    # Priority page on the activated board of block 95: milestones, owner queue, matrix order and highlights, footer.
    $ppg = Join-Path $Scratch 'priority.html'
    $pp = @(& "$S\Build-PriorityPage.ps1" -Repo $ar -Session status-p -Out $ppg)
    $pph = if (Test-Path $ppg) { Get-Content -Raw $ppg } else { '' }
    Case '97 the priority page is written for the focus group' (($pp -join ' ') -match '^PRIORITY-PAGE .* focus A1 ' -and $pph -match 'focus A1') ($pp -join ' | ')
    Case '97 it shows the milestones with their state' ($pph -match 'M1 Authored' -and $pph -match 'M2 Claimable' -and $pph -match 'M3 Integrator-ready')
    Case '97 a stale row is highlighted' ($pph -match '<tr class="stale[^"]*"><td class="num">\d+</td><td class="id">A1\.S<') ([regex]::Match($pph, '.{0,80}A1\.S<.{0,40}').Value)
    Case '97 the focus group''s gate is in its owner queue' ($pph -match 'gate A1\.G') ''
    $iOpen = $pph.IndexOf('>A1.K<'); $iLanded = $pph.IndexOf('>A1.Z<')
    Case '97 open rows come before landed rows' ($iOpen -gt 0 -and $iLanded -gt $iOpen) "open $iOpen landed $iLanded"
    Case '97 the footer shows the next group only' ($pph -match 'Next: A2' -and $pph -notmatch '>A2\.X<') ''
    $arec2 = Get-Content -Raw (Join-Path $ar '.streams\plans\A1.activation.json') | ConvertFrom-Json
    Case '97 the tick records the milestone state on the activation record' ($null -ne $arec2.now -and $null -ne $arec2.now.M3) ($arec2.now | ConvertTo-Json -Compress -Depth 4)
    # Owner ruling 2026-10-18 (kit item IN-20261019012533-2cc1): owner-facing times are local machine time with the
    # zone (lib Format-LocalStamp); the activation record keeps its UTC stamps.
    $ppMs = [regex]::Match($pph, '(?s)<div class="ms">.*?</div>').Value
    $ppMeta = [regex]::Match($pph, '<div class="meta">[^<]*</div>').Value
    Case '97 LOCAL-TIME: the priority page header and milestone times are local with the zone, no UTC stamp' ($ppMeta -match '<div class="meta">\d{4}-\d\d-\d\d \d\d:\d\d [A-Za-z]{2,6} &middot;' -and $ppMs -notmatch '\d\d:\d\d(:\d\d)?(\.\d+)?Z' -and ($ppMs -match '&middot; \d{4}-\d\d-\d\d \d\d:\d\d [A-Za-z]{2,6}' -or $ppMs -notmatch '&middot; \d{4}') -and $pph -notmatch 'ETA \d{4}-\d\d-\d\dT') "$ppMeta / $ppMs"    # A closed group's rows are in the CLAIM scope (Get-FocusSet) but not in the focus matrix: on 2026-10-06 the G4
    # page listed 568 rows, 566 of them done rows of G1-G3 (kit item IN-20261006113826-4fb1). A closed group's leftover
    # OPEN row still shows, because the claim offers it.
    $arKeep = [IO.File]::ReadAllText((Join-Path $ar '.streams\tasks.json'))
    $d = J $ar
    $d.groups = @(@{ id = 'A0'; name = 'zero'; state = 'closed'; origin = 'plan'; scope = @{ include = @('F-0') } }) + @($d.groups)
    $d.tasks += @{ id = 'A0.D'; group = 'A0'; title = 'A0.D'; why = @('AC-1'); kind = 'code'; writeSet = @('z.txt'); dependsOn = @(); estMinutes = 5; state = 'done'; claim = $null; artifacts = @{}; history = @(@{ at = '2026-10-01T00:00:00Z'; by = 'i'; to = 'integrated'; note = 'x' }, @{ at = '2026-10-01T00:00:01Z'; by = 'i'; to = 'done'; note = 'x' }) }
    $d.tasks += @{ id = 'A0.B'; group = 'A0'; title = 'A0.B'; why = @('AC-1'); kind = 'code'; writeSet = @('y.txt'); dependsOn = @(); estMinutes = 5; state = 'built'; claim = $null; artifacts = @{}; history = @() }
    $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $ar '.streams\tasks.json') -Encoding utf8
    $pp0 = @(& "$S\Build-PriorityPage.ps1" -Repo $ar -Session status-p -Out $ppg)
    $pph0 = if (Test-Path $ppg) { Get-Content -Raw $ppg } else { '' }
    [IO.File]::WriteAllText((Join-Path $ar '.streams\tasks.json'), $arKeep)
    Case '97 the matrix holds the focus group, not the done rows of closed groups' ($pph0 -match '>A1\.Z<' -and $pph0 -notmatch '>A0\.D<' -and $pph0 -match '>A0\.B<' -and ($pp0 -join ' ') -match 'focus A1 ') ($pp0 -join ' | ')

    # Cost extras: an idle unit inside 24 h flags; a long session spending in hours with no work flags; waste and
    # per-task tables render.
    $env:STREAM_COST_QUIET_MINUTES = '0'
    New-Item -ItemType Directory -Path (Join-Path $crp '.streams\logs\runner\runner-author-9') -Force | Out-Null
    '{"type":"result","session":"author-i1","role":"author","session_id":"S-I","outcome":"idle","total_cost_usd":0.5}' | Set-Content (Join-Path $crp '.streams\logs\runner\runner-author-9\20261005T040000Z-author-i1.json')
    $nowZ = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('yyyy-MM-ddTHH:mm:ss.000Z')
    [IO.File]::WriteAllText("$cproj\S-I.jsonl", (& $mk 'S-I' 'i1' $nowZ 10000) + "`n")
    New-Item -ItemType Directory -Path (Join-Path $crp '.streams\sessions') -Force | Out-Null
    # Three long sessions spending in each of the last three hours: integ-l1 writes nothing (flagged); coord-w1 writes a
    # decisions.md line and an inbox line in each of those hours (work, not flagged); status-s1 is the watchdog, whose
    # ticks write nothing by design (never flagged). Spend older than 24 h is not judged at all (kit-o1).
    $hz = { param($n) (Get-Date).ToUniversalTime().AddHours(-$n).ToString('yyyy-MM-ddTHH:') + '05:00.000Z' }
    $hs = { param($n) (Get-Date).ToUniversalTime().AddHours(-$n).ToString('yyyy-MM-ddTHH:') + '06:00Z' }
    foreach ($sx in @(@('S-L', 'integ-l1', 'integrate'), @('S-W', 'coord-w1', 'coordinator'), @('S-T', 'status-s1', 'status'), @('S-O', 'kit-o1', 'kit'))) {
        "{`"streamSession`":`"$($sx[1])`",`"role`":`"$($sx[2])`"}" | Set-Content (Join-Path $crp ".streams\sessions\$($sx[0]).json")
        $hrs = if ($sx[0] -eq 'S-O') { @(30, 29, 28) } else { @(3, 2, 1) }
        [IO.File]::WriteAllText("$cproj\$($sx[0]).jsonl", ((@($hrs | ForEach-Object { & $mk $sx[0] "$($sx[0])-$_" (& $hz $_) 10000 })) -join "`n") + "`n")
    }
    foreach ($n in 3, 2, 1) {
        Add-Content (Join-Path $crp '.streams\decisions.md') "- $(& $hs $n) [coord-w1] salvaged a stalled row"
        Add-Content (Join-Path $crp '.streams\inbox\stream-kit.md') "- IN-2026100500000$n-ab1$n | $(& $hs $n) | coord-w1 | note | looked at it"
    }
    [void](& "$S\Get-StreamCost.ps1" -Repo $crp -ProjectsRoot $cproot)
    $cpg2 = Join-Path $Scratch 'cost2.html'
    [void](& "$S\Build-CostPage.ps1" -Repo $crp -Session status-c -Out $cpg2)
    $cph2 = Get-Content -Raw $cpg2
    Case '97 an idle launch inside 24 h raises the idle flag' ($cph2 -match 'idle launches cost \$[\d.]+ in the last 24 h') ([regex]::Match($cph2, 'Flags.{0,600}').Value)
    Case '97 a long session spending in hours with no work is flagged' ($cph2 -match 'long session integ-l1 spent in 3 of 3 hours with no work') ([regex]::Match($cph2, 'Flags.{0,900}').Value)
    Case '97 decisions and inbox lines count as work; the watchdog and spend over 24 h old are not judged' ($cph2 -notmatch 'long session (coord-w1|status-s1|kit-o1)') ([regex]::Match($cph2, 'Flags.{0,900}').Value)
    Case '97 the waste and per-task tables render' ($cph2 -match '<h2>Waste</h2>' -and $cph2 -match 'long sessions, hours with no work' -and $cph2 -match '<h2>\$ per integrated task</h2>') ''
    [Environment]::SetEnvironmentVariable('STREAM_COST_QUIET_MINUTES', $null)

    # Archive (E2): a done row's old history moves to the group archive and leaves a stub; every reader keeps working;
    # decisions of an earlier month rotate out.
    $hr = Join-Path $Scratch 'archrepo'; New-Item -ItemType Directory -Path $hr -Force | Out-Null; $repos += $hr
    git -C $hr init -q -b main; git -C $hr config user.email t@t; git -C $hr config user.name t; Grant-GitPolicy $hr
    Set-Content (Join-Path $hr 'x.txt') 'x'; git -C $hr add -A; git -C $hr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $hr | Out-Null
    $old = (Get-Date).ToUniversalTime().AddDays(-10)
    $oh = @(@{ at = $old.AddHours(-3).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'author-1'; to = 'ticketed'; note = 't' }, @{ at = $old.AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'build-1'; to = 'built'; note = 'b' },
        @{ at = $old.AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'integ-1'; to = 'integrated'; note = 'i' }, @{ at = $old.ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'integ-1'; to = 'done'; note = 'closed' })
    $rh = @(@{ at = (Get-Date).ToUniversalTime().AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'a'; to = 'ticketed'; note = '' }, @{ at = (Get-Date).ToUniversalTime().AddDays(-1).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'b'; to = 'built'; note = '' }, @{ at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'c'; to = 'done'; note = '' })
    $H = { param($id, $st, $ws, $deps, $hist) @{ id = $id; group = 'H1'; title = $id; why = @('AC-1'); kind = 'code'; writeSet = @($ws); dependsOn = @($deps); estMinutes = 5; state = $st; claim = $null; artifacts = @{}; history = @($hist) } }
    @{ groups = @(@{ id = 'H1'; name = 'h'; state = 'released'; origin = 'plan'; scope = @{ include = @('F') } })
       tasks = @((& $H 'H1.OLD' 'done' 'o.txt' @() $oh), (& $H 'H1.NEW' 'done' 'n.txt' @() $rh), (& $H 'H1.OPEN' 'planned' 'p.txt' @('H1.OLD') @($oh[0]))) } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $hr '.streams\tasks.json') -Encoding utf8
    $prevMonth = (Get-Date).ToUniversalTime().AddMonths(-1).ToString('yyyy-MM')
    Add-Content (Join-Path $hr '.streams\decisions.md') "- $prevMonth-15T10:00:00Z [x] old line"
    Add-Content (Join-Path $hr '.streams\decisions.md') "- $((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')) [x] new line"
    $dry = @(& "$S\Archive-TaskHistory.ps1" -Repo $hr -Session status-h -DryRun)
    Case '97 a dry run archives nothing' (($dry -join ' ') -match 'DRY-RUN ARCHIVED rows 1 entries 4 decisions 1' -and @((T $hr 'H1.OLD').history).Count -eq 4 -and -not (Test-Path (Join-Path $hr '.streams\archive\H1.history.json'))) ($dry -join ' | ')
    $arc = @(& "$S\Archive-TaskHistory.ps1" -Repo $hr -Session status-h)
    $ho = T $hr 'H1.OLD'
    $hj = Get-Content -Raw (Join-Path $hr '.streams\archive\H1.history.json') | ConvertFrom-Json -AsHashtable
    Case '97 an old done row''s history moves to the group archive' (($arc -join ' ') -match 'ARCHIVED rows 1 entries 4' -and @($hj['H1.OLD']).Count -eq 4) ($arc -join ' | ')
    Case '97 the stub keeps the integration entry and ends done, naming the archive' (@($ho.history).Count -eq 2 -and $ho.history[0].to -eq 'integrated' -and $ho.history[-1].to -eq 'done' -and $ho.history[-1].note -match 'history archived') ($ho.history | ConvertTo-Json -Compress)
    Case '97 a recent done row keeps its history' (@((T $hr 'H1.NEW').history).Count -eq 3) ''
    $bo = @(& "$S\Test-BoardOrder.ps1" -Repo $hr)
    $rv = @(& "$S\Revise-Task.ps1" -Repo $hr -Session plan-h -Task H1.OPEN -AddWriteSet 'p2.txt' -Note 'widen'); $rvx = $LASTEXITCODE
    Case '97 every reader keeps working: board order, revision, the row a dependent names' (($bo -join ' ') -match 'CLEAN' -and $rvx -eq 0 -and ((T $hr 'H1.OLD').state -eq 'done')) (($bo -join ' | ') + ' / ' + ($rv -join ' | '))
    $dm = Get-Content -Raw (Join-Path $hr '.streams\decisions.md')
    $dold = Get-Content -Raw (Join-Path $hr ".streams\archive\decisions-$prevMonth.md") -ErrorAction SilentlyContinue
    Case '97 decisions of an earlier month rotate to the archive' ($dm -notmatch 'old line' -and $dm -match 'new line' -and $dold -match 'old line') "$dm // $dold"
    # ---- 98. a work unit that ends while it holds an inbox item (kit item IN-20261005193358-71ec). On 2026-10-05
    # author-202610051459-b841 took IN-20261005185715-dde9 (re-pin 67 G3 graders), changed 54 of them and was ended at its
    # 1800 s limit; the item stayed taken by a session that never comes back, with nothing saying how far it got. The
    # runner now re-opens such an item at once and writes inbox\evidence\<id>.progress.md naming the work files the unit
    # changed (logs and other bookkeeping left out). An item another session holds is left alone, and the unit's rules
    # say how long it has and to split work that will not fit.
    $r91 = New-Repo 'r91' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }); $repos += $r91
    $id91 = ((& "$S\Send-InboxItem.ps1" -Repo $r91 -To stream-author -From coord-91 -Kind request -Ask 'repin every grader' | Select-Object -Last 1) -split ' ')[1]
    $id91b = ((& "$S\Send-InboxItem.ps1" -Repo $r91 -To stream-author -From coord-91 -Kind request -Ask 'another job' | Select-Object -Last 1) -split ' ')[1]
    & "$S\Set-InboxItem.ps1" -Repo $r91 -Skill stream-author -Id $id91b -Status taken -By author-91other | Out-Null
    $ai91 = Join-Path $Scratch 'ai-stub91.ps1'; $cl91 = Join-Path $Scratch 'claude-stub91.ps1'
    Set-Content -LiteralPath $ai91 -Value @("'ai: applied revision STUB91'", 'exit 0')
    # The stub plays a unit that takes the item, changes a grader and a ticket, writes a log, beats, and is cut off.
    Set-Content -LiteralPath $cl91 -Value @(
        '$i = [array]::IndexOf($args, ''-n''); $sess = $args[$i + 1]; $r = (Get-Location).Path'
        "& '$S\Set-InboxItem.ps1' -Repo `$r -Skill stream-author -Id $id91 -Status taken -By `$sess | Out-Null"
        'Add-Content (Join-Path $r ''.streams\graders\G1.A.ps1'') ''# repinned'''
        'Set-Content (Join-Path $r ''.streams\tickets\G1.A.md'') ''ticket G1.A repinned'''
        'Set-Content (Join-Path $r ''.streams\logs\stub91.log'') ''log line'''
        "& '$S\Set-InboxItem.ps1' -Repo `$r -Skill stream-author -Id $id91 -Status beat -By `$sess -Note 'done: G1.A' | Out-Null"
        "'{""type"":""result"",""result"":""stub91 cut off"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0}'"
        'exit 0')
    $env:STREAM_RUNNER_AI = $ai91; $env:STREAM_RUNNER_CLAUDE = $cl91
    try { $o91 = @(& "$S\Start-StreamRunner.ps1" -Repo $r91 -Role author -IntervalSeconds 1 -MaxRuns 1) }
    finally { Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue }
    . "$S\lib\Streams.ps1"; . "$S\lib\Inbox.ps1"
    $it91 = @(Read-InboxItems (Join-Path $r91 '.streams\inbox\stream-author.md'))
    $a91 = $it91 | Where-Object { $_.id -eq $id91 }; $b91 = $it91 | Where-Object { $_.id -eq $id91b }
    $prog91 = Join-Path $r91 ".streams\inbox\evidence\$id91.progress.md"
    $ptext91 = if (Test-Path $prog91) { Get-Content -Raw $prog91 } else { '' }
    Case 'runner: an inbox item a work unit still held when it ended is re-opened at once, naming the unit' ($a91.status -eq 'open' -and $a91.statusBy -match '^coord-91 \(RUNNER RE-OPEN, unit author-\S+ ended 0, 2 work files changed' -and (($o91 -join "`n") -match "REOPENED $id91 in stream-author")) "status=$($a91.status) by=$($a91.statusBy) out=$($o91 -join ' | ')"
    Case 'runner: the progress file lists the work files the unit changed and the last beat note, not its logs' (($ptext91 -match '(?m)^- graders\\G1\.A\.ps1\r?$') -and ($ptext91 -match '(?m)^- tickets\\G1\.A\.md\r?$') -and ($ptext91 -notmatch 'stub91\.log') -and ($ptext91 -match 'Its last note: done: G1\.A')) $ptext91
    Case 'runner: an item another session holds is left alone' ($b91.status -eq 'taken' -and $b91.statusBy -eq 'author-91other') "status=$($b91.status) by=$($b91.statusBy)"
    $rules91 = @(Get-ChildItem (Join-Path $r91 '.streams\logs\runner') -Recurse -Filter '*.rules.txt' | ForEach-Object { Get-Content -Raw $_.FullName }) -join "`n"
    Case 'runner: the unit rules give the wall-clock limit and say to split work that will not fit' ($rules91 -match 'This unit is ended at 1800 s wall clock' -and $rules91 -match 'CONTINUATION items') $rules91

    # ---- 99. long /loop sessions attributed from their own transcript. On SMVMTR1 (2026-10-06) 82.2% of the ledger was
    # unattributed: the long sessions of 10-01..10-04 predate .streams\sessions, but each one opens with
    # '/loop /stream-<role>' and passes '-Session <id>' to every kit script it runs.
    $env:STREAM_COST_QUIET_MINUTES = '0'
    $r99 = Join-Path $Scratch 'cost99'; New-Item -ItemType Directory -Path $r99 -Force | Out-Null
    git -C $r99 init -q -b main; git -C $r99 config user.email t@t; git -C $r99 config user.name t
    & "$S\Init-Streams.ps1" -Repo $r99 | Out-Null
    $proot99 = Join-Path $Scratch 'projects99'
    $proj99 = Join-Path $proot99 ((Resolve-Path $r99).Path -replace '[^A-Za-z0-9]', '-'); New-Item -ItemType Directory -Path $proj99 -Force | Out-Null
    $doc99 = @{ groups = @(@{ id = 'G1'; name = 'g'; state = 'released'; origin = 'plan'; scope = @{ include = @('F') } })
        tasks = @(
            @{ id = 'G1.T1'; group = 'G1'; title = 't1'; why = @('AC'); kind = 'code'; writeSet = @('a.txt'); dependsOn = @(); estMinutes = 5; state = 'ticketed'; claim = $null; artifacts = @{}
                history = @(@{ at = '2026-10-05T01:00:00Z'; by = 'author-99x'; to = 'planned'; note = 'claimed' }, @{ at = '2026-10-05T01:30:00Z'; by = 'author-99x'; to = 'ticketed'; note = 'ticket' }) },
            @{ id = 'G1.T2'; group = 'G1'; title = 't2'; why = @('AC'); kind = 'code'; writeSet = @('b.txt'); dependsOn = @(); estMinutes = 5; state = 'building'; claim = $null; artifacts = @{}
                history = @(@{ at = '2026-10-05T01:45:00Z'; by = 'build-99y'; to = 'building'; note = 'claimed' }) }) }
    $doc99 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $r99 '.streams\tasks.json') -Encoding utf8
    $usage99 = '"usage":{"input_tokens":0,"output_tokens":1000000,"cache_read_input_tokens":0,"cache_creation_input_tokens":0,"cache_creation":{"ephemeral_5m_input_tokens":0,"ephemeral_1h_input_tokens":0}}'
    $cmd99 = { param($sid, $args99) '{"type":"user","sessionId":"' + $sid + '","timestamp":"2026-10-05T00:50:00.000Z","message":{"role":"user","content":"<command-message>loop</command-message>\n<command-name>/loop</command-name>\n<command-args>' + $args99 + ' repo: d:\\devops\\repos\\x</command-args>"}}' }
    $tool99 = { param($sid, $id, $at, $session) '{"type":"assistant","sessionId":"' + $sid + '","timestamp":"' + $at + '","message":{"id":"' + $id + '","model":"claude-opus-5-5","content":[{"type":"tool_use","name":"PowerShell","input":{"command":"pwsh -NoProfile -File \"C:\\k\\Claim-Task.ps1\" -Repo x -Role r -Session ' + $session + '"}}],' + $usage99 + '}}' }
    $text99 = { param($sid, $id, $at, $text) '{"type":"assistant","sessionId":"' + $sid + '","timestamp":"' + $at + '","message":{"id":"' + $id + '","model":"claude-opus-5-5","content":[{"type":"text","text":"' + $text + '"}],' + $usage99 + '}}' }
    # L1: a long author session; its own -Session id wins over a stray one in prose and a word after -Session.
    $sidA = 'aaaaaaaa-1111-4111-8111-111111111111'
    [IO.File]::WriteAllText("$proj99\$sidA.jsonl", ((& $cmd99 $sidA '/stream-author'), (& $text99 $sidA 'l1t' '2026-10-05T01:05:00.000Z' 'pass -Session messages; e.g. -Session plan-decoy'),
        (& $tool99 $sidA 'l1a' '2026-10-05T01:10:00.000Z' 'author-99x'), (& $tool99 $sidA 'l1b' '2026-10-05T01:20:00.000Z' 'author-99x') -join "`n") + "`n")
    # L2: a long integrate session that never passed -Session: role from its /loop command, no task.
    $sidB = 'bbbbbbbb-2222-4222-8222-222222222222'
    [IO.File]::WriteAllText("$proj99\$sidB.jsonl", ((& $cmd99 $sidB '10m /stream-integrate'), (& $text99 $sidB 'l2a' '2026-10-05T01:10:00.000Z' 'integrating') -join "`n") + "`n")
    # L3: a build session the OLD Get-StreamCost already read and wrote as unattributed (ledger row + cursor at EOF).
    $sidC = 'cccccccc-3333-4333-8333-333333333333'
    [IO.File]::WriteAllText("$proj99\$sidC.jsonl", ((& $cmd99 $sidC '/stream-build'), (& $tool99 $sidC 'l3a' '2026-10-05T01:50:00.000Z' 'build-99y') -join "`n") + "`n")
    # L4: the integrator ran as a bare '-Session 4599ecab' on 2026-10-01 (no role prefix): role from its /loop command.
    $sidE = 'eeeeeeee-5555-4555-8555-555555555555'
    [IO.File]::WriteAllText("$proj99\$sidE.jsonl", ((& $cmd99 $sidE '/stream-integrate'), (& $tool99 $sidE 'l4a' '2026-10-05T01:10:00.000Z' '4599ecab'), (& $tool99 $sidE 'l4b' '2026-10-05T01:11:00.000Z' '4599ecab') -join "`n") + "`n")
    # U: no command and no -Session: stays unattributed.
    $sidU = 'dddddddd-4444-4444-8444-444444444444'
    [IO.File]::WriteAllText("$proj99\$sidU.jsonl", (& $text99 $sidU 'u1' '2026-10-05T02:00:00.000Z' 'hello') + "`n")
    $cost99 = Join-Path $r99 '.streams\cost'; New-Item -ItemType Directory -Path $cost99 -Force | Out-Null
    $old99 = '{"at":"2026-10-05T01:50:00.000Z","sessionId":"' + $sidC + '","agentId":"","messageId":"l3a","streamSession":"-","role":"unattributed","task":"-","group":"-","model":"claude-opus-5-5","in":0,"out":1000000,"cacheRead":0,"cacheWrite5m":0,"cacheWrite1h":0,"usd":20.0,"unitOutcome":""}' + "`n"
    [IO.File]::WriteAllText((Join-Path $cost99 'ledger.jsonl'), $old99)
    $fileC = (Get-Item "$proj99\$sidC.jsonl").FullName
    @{ files = @{ $fileC = @{ offset = (Get-Item $fileC).Length; lastMessageId = 'l3a' } }; ledgerBytes = (Get-Item (Join-Path $cost99 'ledger.jsonl')).Length } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $cost99 'cursor.json')
    $c99 = $null; try { $c99 = & "$S\Get-StreamCost.ps1" -Repo $r99 -ProjectsRoot $proot99 -Json | ConvertFrom-Json } catch { "FAIL 99 Get-StreamCost threw: $_"; $fails++ }
    $led99 = @(Get-Content (Join-Path $cost99 'ledger.jsonl') | Where-Object { $_ } | ForEach-Object { $_ | ConvertFrom-Json -DateKind String })
    $a99 = @($led99 | Where-Object { $_.messageId -eq 'l1a' })
    Case '99 a long session takes its stream session, role and task from the -Session it passed most' ($a99.Count -eq 1 -and $a99[0].streamSession -eq 'author-99x' -and $a99[0].role -eq 'author' -and $a99[0].task -eq 'G1.T1' -and $a99[0].group -eq 'G1') ($a99 | ConvertTo-Json -Compress)
    $b99 = @($led99 | Where-Object { $_.messageId -eq 'l2a' })
    Case '99 a long session with no -Session takes its role from its /loop command' ($b99.Count -eq 1 -and $b99[0].role -eq 'integrate' -and $b99[0].streamSession -eq 'integrate-bbbbbbbb' -and $b99[0].task -eq '-') ($b99 | ConvertTo-Json -Compress)
    $cc99 = @($led99 | Where-Object { $_.messageId -eq 'l3a' })
    Case '99 a row the old version wrote as unattributed is re-attributed in place, not counted twice' ($cc99.Count -eq 1 -and $cc99[0].streamSession -eq 'build-99y' -and $cc99[0].role -eq 'build' -and $cc99[0].task -eq 'G1.T2') ($cc99 | ConvertTo-Json -Compress)
    $u99 = @($led99 | Where-Object { $_.messageId -eq 'u1' })
    Case '99 a session with neither stays unattributed' ($u99.Count -eq 1 -and $u99[0].role -eq 'unattributed' -and $u99[0].streamSession -eq '-') ($u99 | ConvertTo-Json -Compress)
    $e99 = @($led99 | Where-Object { $_.messageId -eq 'l4a' })
    Case '99 a bare -Session id keeps the id and takes its role from the /loop command' ($e99.Count -eq 1 -and $e99[0].streamSession -eq '4599ecab' -and $e99[0].role -eq 'integrate') ($e99 | ConvertTo-Json -Compress)
    Case '99 the summary counts the re-attributed rows' ($c99 -and [double]$c99.unattributed -eq 20.0 -and [double]$c99.byRole.build -eq 20.0 -and [double]$c99.byRole.integrate -eq 60.0) ($c99 | ConvertTo-Json -Compress -Depth 3)
    $sf99 = Join-Path $r99 ".streams\sessions\$sidA.json"
    $sfo99 = if (Test-Path $sf99) { Get-Content -Raw $sf99 | ConvertFrom-Json } else { $null }
    Case '99 the found mapping is kept as a session file, so a transcript is scanned once' ($sfo99 -and $sfo99.streamSession -eq 'author-99x' -and $sfo99.role -eq 'author' -and $sfo99.source -eq 'transcript') "$sf99 $($sfo99 | ConvertTo-Json -Compress)"
    $n99 = @($led99).Count
    $c99b = & "$S\Get-StreamCost.ps1" -Repo $r99 -ProjectsRoot $proot99 -Json | ConvertFrom-Json
    Case '99 a second run adds nothing and keeps the attribution' ([int]$c99b.added -eq 0 -and @(Get-Content (Join-Path $cost99 'ledger.jsonl') | Where-Object { $_ }).Count -eq $n99 -and [double]$c99b.unattributed -eq 20.0) ($c99b | ConvertTo-Json -Compress -Depth 2)
    [Environment]::SetEnvironmentVariable('STREAM_COST_QUIET_MINUTES', $null)
    # ---- 100. PRE-STAGED UNITS (2026-10-06 prestage-runner-design). The runner does the plumbing before Claude starts.
    # (a) a build row with a RED author grader: the runner claims it, lays the worktree, proves RED, launches the unit
    # with a packet naming all of it, and releases the claim after the exit. (b) a row whose author grader is NOT red
    # bounces to planned with evidence and Claude is never started; the bounce counts toward -MaxRuns. (c) an author row
    # is claimed for the unit; the packet carries the lessons and a requirement excerpt; the rules say the work is
    # pre-staged. (d) an open inbox item is taken in the unit's name before any claim, and re-opened when the unit ends
    # holding it. (e) config.json is written empty, and DryRun names the pre-stage and the configured models. (f) a
    # configured model, effort, subagent model and cache TTL reach the launch (args and environment).
    $r100 = New-Repo 'runner100' ([ordered]@{ 'G1.R' = (ContentGrader 'G1.R' 'done'); 'G1.N' = (ContentGrader 'G1.N' 'base') }); $repos += $r100
    $ai100 = Join-Path $Scratch 'ai-stub100.ps1'; Set-Content -LiteralPath $ai100 -Value @('exit 0')
    $args100 = Join-Path $Scratch 'claude-stub100.args.json'
    $board100 = Join-Path $Scratch 'claude-stub100.board.json'
    $env100 = Join-Path $Scratch 'claude-stub100.env.json'
    function New-Stub100([string] $File, [string] $Tasks, [string] $Outcome) {
        Set-Content -LiteralPath $File -Value @(
            "`$args | ConvertTo-Json -Compress | Set-Content -LiteralPath '$args100'"
            "Copy-Item -LiteralPath '$Tasks' -Destination '$board100'"
            "@{ sub = `$env:CLAUDE_CODE_SUBAGENT_MODEL; ttl = `$env:CLAUDE_CODE_PROMPT_CACHE_TTL } | ConvertTo-Json -Compress | Set-Content -LiteralPath '$env100'"
            "'{""type"":""result"",""result"":""stub100 ok\nUNIT-OUTCOME: $Outcome"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0}'"
            'exit 0')
    }
    $tasks100 = Join-Path $r100 '.streams\tasks.json'
    $cl100 = Join-Path $Scratch 'claude-stub100.ps1'; New-Stub100 $cl100 $tasks100 'built'
    $env:STREAM_RUNNER_AI = $ai100; $env:STREAM_RUNNER_CLAUDE = $cl100
    $o100 = @(); $e100 = ''
    try { $o100 = @(& "$S\Start-StreamRunner.ps1" -Repo $r100 -Role build -IntervalSeconds 1 -MaxRuns 1) } catch { $e100 = ("$_" -split "`n")[0] }
    $a100 = @(if (Test-Path $args100) { Get-Content -Raw $args100 | ConvertFrom-Json })
    $cmd100 = if ($a100.Count -gt 1) { [string]$a100[1] } else { '' }
    $pk100 = if ($cmd100 -match 'packet: (.+)$') { $Matches[1].Trim() } else { '' }
    $md100 = if ($pk100 -and (Test-Path -LiteralPath $pk100)) { Get-Content -Raw -LiteralPath $pk100 } else { '' }
    $b100 = if (Test-Path $board100) { Get-Content -Raw $board100 | ConvertFrom-Json } else { $null }
    $rowAt100 = if ($b100) { $b100.tasks | Where-Object { $_.id -eq 'G1.R' } } else { $null }
    $sess100 = if ($md100 -match '(?m)^# Unit (build-\S+) \(build\)') { $Matches[1] } else { '' }
    $short = { param([string] $s, [int] $n) $s = ($s -replace '\s+', ' '); if ($s.Length -gt $n) { $s.Substring(0, $n) } else { $s } }
    Case '100a build pre-stage: the unit is launched with a packet whose unit.md names the row, the worktree and a proved RED' ((-not $e100) -and $pk100 -and $md100 -match '## Task G1\.R \(claim HELD by build-' -and $md100 -match 'Step 3, worktree: `' -and $md100 -match 'RED PROVED' -and $md100 -match 'FAIL C1') "err='$e100' cmd='$cmd100' md=$(& $short $md100 300) out=$($o100 -join ' | ')"
    Case '100a build pre-stage: at launch the row was building, claimed by the unit session, with artifacts.red recorded' ($rowAt100 -and $rowAt100.state -eq 'building' -and $rowAt100.claim.session -eq $sess100 -and $rowAt100.artifacts.red -eq '.streams\logs\G1.R.grader.red.txt' -and (Test-Path (Join-Path $r100 '.streams\logs\G1.R.grader.red.txt'))) "state=$(if ($rowAt100) { $rowAt100.state }) claim=$(if ($rowAt100) { $rowAt100.claim | ConvertTo-Json -Compress }) sess=$sess100"
    Case '100a build pre-stage: task.json sits beside unit.md, and the runner printed the claim' ($pk100 -and (Test-Path (Join-Path (Split-Path $pk100) 'task.json')) -and (($o100 -join "`n") -match 'PRESTAGE build-\S+ claimed G1\.R')) "out=$($o100 -join ' | ')"
    $after100 = T $r100 'G1.R'
    Case '100a build pre-stage: after the unit exits the claim is released; an unchanged tree is not harvested' ($after100.state -eq 'ticketed' -and -not $after100.claim -and (($o100 -join "`n") -match 'HARVEST-(EMPTY|SKIPPED) G1\.R') -and (($o100 -join "`n") -match 'RELEASED G1\.R')) "state=$($after100.state) out=$($o100 -join ' | ')"
    # (b)
    Remove-Item $args100, $board100, $env100 -ErrorAction SilentlyContinue
    $d100 = J $r100; foreach ($t in $d100.tasks) { if ($t.id -eq 'G1.R') { $t.state = 'planned'; $t.claim = $null } }
    Set-Content -Path $tasks100 -Encoding utf8 -Value ($d100 | ConvertTo-Json -Depth 50)
    $o100b = @(); $e100b = ''
    try { $o100b = @(& "$S\Start-StreamRunner.ps1" -Repo $r100 -Role build -IntervalSeconds 1 -MaxRuns 1) } catch { $e100b = ("$_" -split "`n")[0] }
    $n100 = T $r100 'G1.N'
    $hist100 = @($n100.history | ForEach-Object { $_ | ConvertTo-Json -Compress -Depth 5 })
    Case '100b a row whose author grader is not red bounces to planned with evidence, and Claude is never started' ((-not $e100b) -and -not (Test-Path $args100) -and $n100.state -eq 'planned' -and -not $n100.claim -and $n100.artifacts.red -eq '.streams\logs\G1.N.grader.red.txt' -and (($o100b -join "`n") -match 'BOUNCE G1\.N -> planned: NOT-RED') -and @($hist100 | Where-Object { $_ -like '*builder RED refused (origin: runner pre-stage*' }).Count -ge 1) "err='$e100b' state=$($n100.state) red=$($n100.artifacts.red) out=$($o100b -join ' | ')"
    $st100b = Get-ChildItem (Join-Path $r100 '.streams\runners') -Filter 'runner-build-*.json' | Sort-Object LastWriteTime | Select-Object -Last 1
    $s100b = if ($st100b) { Get-Content -Raw $st100b.FullName | ConvertFrom-Json } else { $null }
    Case '100b the bounce counted as a run, so -MaxRuns 1 ended the runner' ($s100b -and $s100b.runs -eq 1 -and $s100b.status -like 'stopped (MaxRuns 1)*') "state=$(if ($s100b) { $s100b | ConvertTo-Json -Compress })"
    # (c)
    $r100c = New-Repo 'runner100c' ([ordered]@{ 'G1.A' = (ContentGrader 'G1.A' 'done') }); $repos += $r100c
    $req100 = Join-Path $r100c 'docs\req.md'; New-Item -ItemType Directory -Path (Split-Path $req100) -Force | Out-Null
    Set-Content -LiteralPath $req100 -Value @('# Requirements', '', 'AC-1: the file G1.A.txt says done.', 'Second line of AC-1 context.')
    $tasks100c = Join-Path $r100c '.streams\tasks.json'
    $d100c = J $r100c; $d100c.requirements = @('docs\req.md'); foreach ($t in $d100c.tasks) { $t.state = 'planned'; $t.claim = $null }
    Set-Content -Path $tasks100c -Encoding utf8 -Value ($d100c | ConvertTo-Json -Depth 50)
    [void](& "$S\Add-Lesson.ps1" -Repo $r100c -Role author -Session author-100 -Task G1.A -Text 'lesson one hundred: read the packet first')
    Remove-Item $args100, $board100, $env100 -ErrorAction SilentlyContinue
    $cl100c = Join-Path $Scratch 'claude-stub100c.ps1'; New-Stub100 $cl100c $tasks100c 'ticketed'
    $env:STREAM_RUNNER_CLAUDE = $cl100c
    $o100c = @(); $e100c = ''
    try { $o100c = @(& "$S\Start-StreamRunner.ps1" -Repo $r100c -Role author -IntervalSeconds 1 -MaxRuns 1) } catch { $e100c = ("$_" -split "`n")[0] }
    $a100c = @(if (Test-Path $args100) { Get-Content -Raw $args100 | ConvertFrom-Json })
    $pk100c = if ($a100c.Count -gt 1 -and [string]$a100c[1] -match 'packet: (.+)$') { $Matches[1].Trim() } else { '' }
    $md100c = if ($pk100c -and (Test-Path -LiteralPath $pk100c)) { Get-Content -Raw -LiteralPath $pk100c } else { '' }
    $b100c = if (Test-Path $board100) { Get-Content -Raw $board100 | ConvertFrom-Json } else { $null }
    $rowAt100c = if ($b100c) { $b100c.tasks | Where-Object { $_.id -eq 'G1.A' } } else { $null }
    Case '100c author pre-stage: the row is claimed by the unit at launch, and the packet carries the lessons and a requirement excerpt' ((-not $e100c) -and $rowAt100c -and $rowAt100c.state -eq 'planned' -and $rowAt100c.claim -and $rowAt100c.claim.role -eq 'author' -and $md100c -match 'lesson one hundred' -and $md100c -match '### AC-1' -and $md100c -match 'the file G1\.A\.txt says done') "err='$e100c' claim=$(if ($rowAt100c -and $rowAt100c.claim) { $rowAt100c.claim | ConvertTo-Json -Compress }) md=$(& $short $md100c 400) out=$($o100c -join ' | ')"
    $rules100c = Get-ChildItem (Join-Path $r100c '.streams\logs\runner') -Recurse -Filter '*.rules.txt' -ErrorAction SilentlyContinue | Select-Object -First 1
    $rt100c = if ($rules100c) { Get-Content -Raw $rules100c.FullName } else { '' }
    Case '100c the rules say the work is pre-staged (task G1.A) and drop the read-the-lessons-first rule' ($rt100c -match 'YOUR WORK IS PRE-STAGED' -and $rt100c -match 'task G1\.A' -and $rt100c -notmatch 'Before you claim or take any work') "rules=$(& $short $rt100c 200)"
    Case '100c after the unit exits the author claim is released and the row stays planned' ((T $r100c 'G1.A').state -eq 'planned' -and -not (T $r100c 'G1.A').claim) "state=$((T $r100c 'G1.A').state)"
    # (d)
    Remove-Item $args100, $board100, $env100 -ErrorAction SilentlyContinue
    $sent100 = @(& "$S\Send-InboxItem.ps1" -Repo $r100 -To stream-build -From test-100 -Kind request -Ask 'G1.R: rebuild from the packet' -Task G1.R) -join ' '
    $id100 = if ($sent100 -match 'SENT (\S+)') { $Matches[1] } else { '' }
    $env:STREAM_RUNNER_CLAUDE = $cl100
    $o100d = @(); $e100d = ''
    try { $o100d = @(& "$S\Start-StreamRunner.ps1" -Repo $r100 -Role build -IntervalSeconds 1 -MaxRuns 1) } catch { $e100d = ("$_" -split "`n")[0] }
    $a100d = @(if (Test-Path $args100) { Get-Content -Raw $args100 | ConvertFrom-Json })
    $pk100d = if ($a100d.Count -gt 1 -and [string]$a100d[1] -match 'packet: (.+)$') { $Matches[1].Trim() } else { '' }
    $md100d = if ($pk100d -and (Test-Path -LiteralPath $pk100d)) { Get-Content -Raw -LiteralPath $pk100d } else { '' }
    $b100d = if (Test-Path $board100) { Get-Content -Raw $board100 | ConvertFrom-Json } else { $null }
    $claimed100d = @(if ($b100d) { $b100d.tasks | Where-Object { $_.claim } })
    . "$S\lib\Streams.ps1"; . "$S\lib\Inbox.ps1"
    $it100d = @(Read-InboxItems (Join-Path $r100 '.streams\inbox\stream-build.md') | Where-Object { $_.id -eq $id100 })
    Case '100d an open inbox item is taken in the unit''s name before any claim: the packet is the item and no row is claimed' ((-not $e100d) -and $id100 -and $md100d -match "## Inbox item $id100 \(TAKEN in your name" -and $md100d -notmatch '## Task ' -and $claimed100d.Count -eq 0 -and (($o100d -join "`n") -match "PRESTAGE build-\S+ took inbox item $id100")) "err='$e100d' sent='$sent100' claimed=$($claimed100d.Count) md=$(& $short $md100d 200) out=$($o100d -join ' | ')"
    Case '100d the item a unit ends holding is re-opened by the runner' ($it100d.Count -eq 1 -and $it100d[0].status -eq 'open' -and (($o100d -join "`n") -match "REOPENED $id100")) "status=$(if ($it100d.Count) { $it100d[0].status }) out=$($o100d -join ' | ')"
    # (e) and (f)
    $cfg100 = Join-Path $r100c '.streams\config.json'
    $cj100 = if (Test-Path $cfg100) { Get-Content -Raw $cfg100 | ConvertFrom-Json -AsHashtable } else { $null }
    Case '100e the runner wrote an empty config.json with defaults and every role' ($cj100 -and $cj100.Contains('defaults') -and $cj100.roles.Contains('author') -and $cj100.roles.author.Contains('subagentModel') -and -not $cj100.roles.author.model) "exists=$(Test-Path $cfg100)"
    if ($cj100) {
        $cj100.defaults.model = 'opus'; $cj100.roles.author.model = 'sonnet'; $cj100.roles.author.subagentModel = 'haiku'; $cj100.roles.author.effort = 'low'; $cj100.roles.author.promptCacheTtl = '5m'
        Set-Content -LiteralPath $cfg100 -Encoding utf8 -Value ($cj100 | ConvertTo-Json -Depth 5)
    }
    $dry100 = @(& "$S\Start-StreamRunner.ps1" -Repo $r100c -Role author -DryRun)
    Case '100e DryRun names the pre-stage and the configured models, and the rules name the subagent model' ((($dry100 -join "`n") -match '(?m)^PRESTAGE on: ') -and (($dry100 -join "`n") -match '(?m)^CONFIG model sonnet subagents haiku effort low cacheTtl 5m \(from roles\.author\)') -and (($dry100 -join "`n") -match '(?m)^ARGS .*--model sonnet --effort low') -and (($dry100 -join "`n") -match 'launched with model: "haiku"')) ($dry100 -join ' | ')
    $dry100b = @(& "$S\Start-StreamRunner.ps1" -Repo $r100c -Role integrate -DryRun -Model fable)
    Case '100f -Model overrides the file; a role with no row of its own reads defaults' (($dry100b -join "`n") -match '(?m)^CONFIG model fable subagents skill choice effort default cacheTtl default \(from -Model \(defaults\)\)') ($dry100b -join ' | ')
    Remove-Item $args100, $board100, $env100 -ErrorAction SilentlyContinue
    $env:STREAM_RUNNER_CLAUDE = $cl100c
    $o100f = @(); $e100f = ''
    try { $o100f = @(& "$S\Start-StreamRunner.ps1" -Repo $r100c -Role author -IntervalSeconds 1 -MaxRuns 1) } catch { $e100f = ("$_" -split "`n")[0] }
    $a100f = @(if (Test-Path $args100) { Get-Content -Raw $args100 | ConvertFrom-Json })
    $ev100f = if (Test-Path $env100) { Get-Content -Raw $env100 | ConvertFrom-Json } else { $null }
    Case '100f a configured model and effort reach the command line, the subagent model and cache TTL the environment, and the runner says so' ((-not $e100f) -and (($a100f -join ' ') -match '--model sonnet --effort low') -and $ev100f -and $ev100f.sub -eq 'haiku' -and $ev100f.ttl -eq '5m' -and (($o100f -join "`n") -match 'RUN author-\S+ \(print\) model sonnet subagents haiku effort low cacheTtl 5m') -and -not $env:CLAUDE_CODE_SUBAGENT_MODEL) "err='$e100f' args=$($a100f -join ' ') env=$(if ($ev100f) { $ev100f | ConvertTo-Json -Compress }) out=$($o100f -join ' | ')"
    # ---- 101. RUNNER LIVENESS AND THE LOCK RACE (2026-10-08, first run after the pre-stage runner). Five builders ran
    # and the board counted ghosts: (a) a gated runner that has not run a unit has no session in its state and was left
    # out; (b) a pre-stage claim that came back NONE left an idle beat for a session id that never became a unit, and
    # that ghost counted live for 45 minutes; (c) Invoke-TasksLocked caught only IOException, but CreateNew on the lock
    # also fails with UnauthorizedAccessException when it races the last holder's delete, and that throw failed a
    # builder's pre-stage into a 900 s backoff (measured: 5 of 1800 lock calls across 12 processes on the old code).
    $r101 = New-Repo 'runner101' ([ordered]@{ 'G1.R' = (ContentGrader 'G1.R' 'done') }); $repos += $r101
    $run101 = Join-Path $r101 '.streams\runners'; New-Item -ItemType Directory -Path $run101 -Force | Out-Null
    $now101 = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    Set-Content (Join-Path $run101 'runner-build-101idle.json') ([ordered]@{ runner = 'runner-build-101idle'; role = 'build'; pid = $PID; started = $now101; session = $null; status = "idle since $now101" } | ConvertTo-Json)
    $m101 = & "$S\Get-StreamStatus.ps1" -Repo $r101 -Json | ConvertFrom-Json
    Case '101a a live gated runner with no unit yet counts as one idle builder' ([int]$m101.sessions.build.live -eq 1 -and [int]$m101.sessions.build.idle -eq 1 -and [int]$m101.sessions.build.working -eq 0) "build=$($m101.sessions.build | ConvertTo-Json -Compress -Depth 4)"
    Remove-Item (Join-Path $run101 'runner-build-101idle.json')
    # (b) the claim is refused for disk (exit 6, an idle beat) on every pass, so the gate passes and the pre-stage finds
    # nothing: the same path as a lost race. The runner is stopped by its STOP file.
    $ai101 = Join-Path $Scratch 'ai-stub101.ps1'; Set-Content -LiteralPath $ai101 -Value @('exit 0')
    $cl101 = Join-Path $Scratch 'claude-stub101.ps1'; Set-Content -LiteralPath $cl101 -Value @('exit 0')
    $env:STREAM_RUNNER_AI = $ai101; $env:STREAM_RUNNER_CLAUDE = $cl101; $env:STREAM_FREE_MB_TEST = '100'
    $p101 = Start-Process pwsh -ArgumentList '-NoProfile', '-File', "$S\Start-StreamRunner.ps1", '-Repo', $r101, '-Role', 'build', '-IntervalSeconds', '1' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $Scratch 'runner101.out.txt')
    # Wait for the runner's first GATE line, not a fixed 8 s: on a loaded host (CPU 100%, 2026-10-17) the runner took
    # longer than 8 s to reach its loop, found the STOP file first and never gated, so 101b failed and the config.json
    # read below threw. The wait ends at 120 s; a runner that never gates still fails 101b.
    $out101File = Join-Path $Scratch 'runner101.out.txt'
    $gateBy101 = (Get-Date).AddSeconds(120)
    while ((Get-Date) -lt $gateBy101 -and -not $p101.HasExited) {
        $seen101 = try { $fs101 = [IO.FileStream]::new($out101File, 'Open', 'Read', 'ReadWrite'); try { [IO.StreamReader]::new($fs101).ReadToEnd() } finally { $fs101.Dispose() } } catch { '' }
        if ($seen101 -match 'GATE ') { break }
        Start-Sleep -Milliseconds 500
    }
    Start-Sleep -Seconds 2
    Set-Content (Join-Path $run101 'STOP-build') 'test 101'
    if (-not $p101.WaitForExit(60000)) { Stop-Process -Id $p101.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item Env:\STREAM_FREE_MB_TEST -ErrorAction SilentlyContinue
    $out101 = Get-Content -Raw (Join-Path $Scratch 'runner101.out.txt') -ErrorAction SilentlyContinue
    $beats101 = @(Get-ChildItem (Join-Path $r101 '.streams\idle') -Filter 'build-*.json' -File -ErrorAction SilentlyContinue)
    $m101b = & "$S\Get-StreamStatus.ps1" -Repo $r101 -Json | ConvertFrom-Json
    Case '101b a pre-stage that claims nothing leaves no idle beat, so no ghost builder is counted' (($out101 -match 'GATE ') -and $beats101.Count -eq 0 -and [int]$m101b.sessions.build.live -eq 0) "beats=$(@($beats101 | ForEach-Object { $_.Name }) -join ',') live=$($m101b.sessions.build.live) out=$(& $short $out101 300)"
    # (c) twelve processes take the tasks lock 120 times each; none may throw.
    # Each racer waits up to 300 s for the lock, not the default 15 s. The case proves the lock never throws access
    # denied; on the 2026-10-17 host at 100% CPU, one racer of twelve waited past 15 s and threw "tasks.json lock busy
    # for 15s", which is the lock working, not the defect this case is about (seen in two kit item 83de suite runs).
    $lk101 = Join-Path $Scratch 'lock101'; New-Item -ItemType Directory -Path $lk101 -Force | Out-Null
    Set-Content (Join-Path $lk101 'tasks.json') '{"tasks":[],"groups":[]}'
    $st101 = Join-Path $Scratch 'lockstress101.ps1'
    Set-Content -LiteralPath $st101 -Value @(
        'param([string] $Lib, [string] $Dir)'
        '$env:STREAM_TASKS_LOCK_WAIT_SECONDS = ''300'''
        '. (Join-Path $Lib ''Streams.ps1'')'
        '$P = @{ Lock = (Join-Path $Dir ''tasks.json.lock''); Tasks = (Join-Path $Dir ''tasks.json''); Decisions = (Join-Path $Dir ''decisions.md'') }'
        '$n = 0; for ($i = 0; $i -lt 120; $i++) { try { [void](Invoke-TasksLocked $P "s$PID" { param($doc) $null }) } catch { $n++; "THREW $($_.Exception.Message)" } }'
        '"DONE $n"')
    $ps101 = @(1..12 | ForEach-Object { Start-Process pwsh -ArgumentList '-NoProfile', '-File', $st101, '-Lib', (Join-Path $S 'lib'), '-Dir', $lk101 -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $lk101 "out$_.txt") })
    foreach ($p in $ps101) { if (-not $p.WaitForExit(300000)) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue } }
    $o101 = @(Get-ChildItem $lk101 -Filter 'out*.txt' | ForEach-Object { Get-Content $_.FullName })
    $threw101 = @($o101 | Where-Object { $_ -like 'THREW *' })
    # (d) a full model id in subagentModel: the Agent tool takes only sonnet|opus|haiku|fable, so the rules name the alias.
    $cfg101 = Join-Path $r101 '.streams\config.json'
    $cj101 = Get-Content -Raw $cfg101 | ConvertFrom-Json -AsHashtable
    # The repo's one row is ticketed, so the build DryRun passes its gate and prints the rules; each id is set in turn.
    $cj101.roles.build.subagentModel = 'claude-opus-5-5'
    Set-Content -LiteralPath $cfg101 -Encoding utf8 -Value ($cj101 | ConvertTo-Json -Depth 5)
    $dry101 = (@(& "$S\Start-StreamRunner.ps1" -Repo $r101 -Role build -DryRun) -join "`n")
    $cj101.roles.build.subagentModel = 'some-custom-model'
    Set-Content -LiteralPath $cfg101 -Encoding utf8 -Value ($cj101 | ConvertTo-Json -Depth 5)
    $dry101b = (@(& "$S\Start-StreamRunner.ps1" -Repo $r101 -Role build -DryRun) -join "`n")
    Case '101d a full subagent model id is passed to Agent calls as its alias, never as the id' (($dry101 -match 'launched with model: "opus"') -and ($dry101 -notmatch 'model: "claude-opus-5-5"') -and ($dry101b -match 'launched with NO model field') -and ($dry101b -notmatch 'model: "some-custom-model"')) "author=$(& $short ([regex]::Match($dry101, 'MODEL CONFIGURATION.{0,160}').Value) 200) build=$(& $short ([regex]::Match($dry101b, 'MODEL CONFIGURATION.{0,160}').Value) 200)"
    Case '101c twelve processes racing the tasks lock never throw access denied' (@($o101 | Where-Object { $_ -eq 'DONE 0' }).Count -eq 12 -and $threw101.Count -eq 0) "done=$(@($o101 | Where-Object { $_ -like 'DONE *' }) -join ',') first=$($threw101 | Select-Object -First 1)"
    # (e) a runner started before Claim-Task.ps1 took -NoIdleBeat still calls it from disk on every pre-stage, so the
    # claim itself must see the pre-stage: author 8 live while 5 author runners ran on 2026-10-08. The stand-in runner
    # below has the runner's script name and pre-stage function and passes no switch, like the old runner.
    $fr101 = Join-Path $Scratch 'oldrunner101'; New-Item -ItemType Directory -Path $fr101 -Force | Out-Null
    $frs101 = Join-Path $fr101 'Start-StreamRunner.ps1'
    Set-Content -LiteralPath $frs101 -Value @(
        'param([string] $S, [string] $Repo)'
        'function Invoke-PreStage([string] $Session) { & "$S\Claim-Task.ps1" -Repo $Repo -Role author -Session $Session }'
        'Invoke-PreStage ''author-pre101e''')
    $idle101 = Join-Path $r101 '.streams\idle'
    $oe101 = (@(& $frs101 -S $S -Repo $r101 3>&1) -join ' ')
    $od101 = (@(& "$S\Claim-Task.ps1" -Repo $r101 -Role author -Session 'author-direct101e' 3>&1) -join ' ')
    $on101 = try { (@(& "$S\Claim-Task.ps1" -Repo $r101 -Role author -Session 'author-switch101e' -NoIdleBeat 3>&1) -join ' ') } catch { "THREW $_" }
    $has101 = { param([string] $s) Test-Path (Join-Path $idle101 "$s.json") }
    Case '101e a pre-stage NONE claim, from an old runner or with -NoIdleBeat, leaves no idle beat; a session''s own NONE still does' (($oe101 -match 'NONE') -and -not (& $has101 'author-pre101e') -and ($od101 -match 'NONE') -and (& $has101 'author-direct101e') -and ($on101 -match 'NONE') -and -not (& $has101 'author-switch101e')) "old=$(& $short $oe101 120) beat=$(& $has101 'author-pre101e') | direct=$(& $short $od101 60) beat=$(& $has101 'author-direct101e') | switch=$(& $short $on101 120) beat=$(& $has101 'author-switch101e')"
    # (f) a pre-stage that claims a row and bounces it without a unit (a build row whose author grader is not red) wrote
    # history under a session no unit ever ran: build 6 live while 5 build runners ran on 2026-10-08. A session with no
    # runner that claims and releases the same way still counts live.
    $r101f = New-Repo 'runner101f' ([ordered]@{ 'G1.R' = (ContentGrader 'G1.R' 'done') }); $repos += $r101f
    $frb101 = Join-Path $Scratch 'oldrunner101f'; New-Item -ItemType Directory -Path $frb101 -Force | Out-Null
    $frbs101 = Join-Path $frb101 'Start-StreamRunner.ps1'
    Set-Content -LiteralPath $frbs101 -Value @(
        'param([string] $S, [string] $Repo)'
        'function Invoke-PreStage([string] $Session) { & "$S\Claim-Task.ps1" -Repo $Repo -Role build -Session $Session }'
        'Invoke-PreStage ''build-pre101f''')
    $cf101 = (@(& $frbs101 -S $S -Repo $r101f 3>&1) -join ' ')
    $bf101 = (@(& "$S\Update-Task.ps1" -Repo $r101f -Task 'G1.R' -Role build -Session 'build-pre101f' -To planned -Release -Note 'test 101f bounce' 3>&1) -join ' ')
    $mf101 = & "$S\Get-StreamStatus.ps1" -Repo $r101f -Json | ConvertFrom-Json
    $liveF101 = [int]$mf101.sessions.build.live
    # The control: the row is ticketed again and a session with no runner claims and releases it.
    $tf101 = Get-Content -Raw (Join-Path $r101f '.streams\tasks.json') | ConvertFrom-Json -AsHashtable
    foreach ($x in $tf101.tasks) { if ($x.id -eq 'G1.R') { $x.state = 'ticketed' } }
    Set-Content -LiteralPath (Join-Path $r101f '.streams\tasks.json') -Encoding utf8 -Value ($tf101 | ConvertTo-Json -Depth 50)
    $cd101 = (@(& "$S\Claim-Task.ps1" -Repo $r101f -Role build -Session 'build-direct101f' 3>&1) -join ' ')
    $rd101 = (@(& "$S\Update-Task.ps1" -Repo $r101f -Task 'G1.R' -Role build -Session 'build-direct101f' -To ticketed -Release -Note 'test 101f release' 3>&1) -join ' ')
    $md101 = & "$S\Get-StreamStatus.ps1" -Repo $r101f -Json | ConvertFrom-Json
    Case '101f a pre-stage session that claims and bounces with no unit is not a live builder; a runnerless session that does the same is' (($cf101 -match '"G1.R"') -and $liveF101 -eq 0 -and ($cd101 -match '"G1.R"') -and [int]$md101.sessions.build.live -eq 1) "prestage claim=$(& $short $cf101 80) bounce=$(& $short $bf101 80) live=$liveF101 | direct claim=$(& $short $cd101 80) release=$(& $short $rd101 80) live=$($md101.sessions.build.live)"

    # ---- 102. Write-AtomicText survives a reader that holds the target open without FILE_SHARE_DELETE.
    # The final Move onto tasks.json threw 'Access to the path is denied' when another process held tasks.json open with
    # no delete sharing: runner Builder 4 lost its pre-stage write twice on 2026-10-09 (17:03 and 17:18 EDT) and left
    # tasks.json.tmp.* files behind (kit item IN-20261009213052-7ec7). (a) a reader in another process that lets go
    # after about a second: the write lands and leaves no tmp. (b) a reader that never lets go: the write throws and
    # still leaves no tmp.
    . "$S\lib\Streams.ps1"
    $d102 = Join-Path $Scratch 'atomic102'; New-Item -ItemType Directory -Path $d102 -Force | Out-Null
    $p102 = Join-Path $d102 'tasks.json'; [IO.File]::WriteAllText($p102, 'old')
    $held102 = Join-Path $d102 'held.txt'
    $hs102 = Join-Path $d102 'hold.ps1'
    Set-Content -LiteralPath $hs102 -Value @(
        'param([string] $P, [string] $Marker)'
        '$fs = [IO.File]::Open($P, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)'
        'Set-Content -LiteralPath $Marker -Value held'
        'Start-Sleep -Milliseconds 1200'
        '$fs.Dispose()')
    $hp102 = Start-Process pwsh -ArgumentList '-NoProfile', '-File', $hs102, '-P', $p102, '-Marker', $held102 -WindowStyle Hidden -PassThru
    for ($i = 0; $i -lt 200 -and -not (Test-Path $held102); $i++) { Start-Sleep -Milliseconds 50 }
    $wa102 = try { Write-AtomicText $p102 'new-a'; 'ok' } catch { "threw: $(("$_" -split "`n")[0])" }
    if (-not $hp102.WaitForExit(30000)) { Stop-Process -Id $hp102.Id -Force -ErrorAction SilentlyContinue }
    $ta102 = @(Get-ChildItem $d102 -Filter 'tasks.json.tmp.*' -File).Count
    Case '102a an atomic write waits out a reader that holds the file without delete sharing, and leaves no tmp' ((Test-Path $held102) -and $wa102 -eq 'ok' -and [IO.File]::ReadAllText($p102) -eq 'new-a' -and $ta102 -eq 0) "held=$(Test-Path $held102) write=$wa102 content=$([IO.File]::ReadAllText($p102)) tmp=$ta102"
    $fs102 = [IO.File]::Open($p102, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try { $wb102 = try { Write-AtomicText $p102 'new-b'; 'ok' } catch { "threw: $(("$_" -split "`n")[0])" } } finally { $fs102.Dispose() }
    $tb102 = @(Get-ChildItem $d102 -Filter 'tasks.json.tmp.*' -File).Count
    Case '102b an atomic write a reader blocks for good throws and leaves no tmp' ($wb102 -like 'threw:*' -and [IO.File]::ReadAllText($p102) -eq 'new-a' -and $tb102 -eq 0) "write=$wb102 content=$([IO.File]::ReadAllText($p102)) tmp=$tb102"

    # 103 (kit item IN-20261009233639-e3a7): a builder started Invoke-Grader detached and hidden without -Repo. pwsh
    # prompted for the mandatory parameter in a window nobody could see, so no grader ran and no beat landed; the watchdog
    # broke the live claim 45 minutes later. A detached run that lacks -Repo, -Task or -Root must end at once, saying so.
    $o103 = Join-Path $Scratch 'grader103.out.txt'
    $p103 = Start-Process pwsh -WindowStyle Hidden -PassThru -RedirectStandardOutput $o103 -ArgumentList @('-NoProfile', '-File', "$S\Invoke-Grader.ps1", '-Task', 'G1.X', '-Root', $Scratch, '-Label', 'p103', '-BeatSession', 'build-103', '-BeatTask', 'G1.X')
    $done103 = $p103.WaitForExit(30000)
    if (-not $done103) { try { $p103.Kill($true) } catch { } }
    $out103 = if (Test-Path $o103) { (Get-Content -Raw $o103) } else { '' }
    Case '103 a detached grader run missing -Repo ends at once with MISSING-PARAM' ($done103 -and $p103.ExitCode -eq 7 -and $out103 -match 'MISSING-PARAM -Repo') "exited=$done103 code=$(if ($done103) { $p103.ExitCode } else { '-' }) out=$("$out103".Trim())"

    # 104 (kit item IN-20261010031237-259d): the runner's pre-stage grade of G4.T131 sat 2.4 hours on a hung node child
    # while its beat kept the claim fresh, so the watchdog never freed the row. A beating run has a wall-clock limit: past
    # it the grader and its whole tree are ended and the run is GRADER-TIMEOUT, exit 8, never RED. Fixture: a grader that
    # prints a FAIL, starts a grandchild, then sleeps 90 s; the limit is 3 s.
    $pid104 = Join-Path $Scratch 'grader104.grandchild.pid'
    $g104 = @'
param([string]$Root)
$c = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 300'
Set-Content -LiteralPath 'PIDFILE' -Value $c.Id
'FAIL C1'
Start-Sleep -Seconds 90
exit 1
'@ -replace 'PIDFILE', $pid104
    $r104 = New-Repo 'r104' @{ 'G1.A' = $g104 }; $repos += $r104
    $env:STREAM_BEAT_SECONDS = '1'; $env:STREAM_GRADER_TIMEOUT_SECONDS = '3'
    $sw104 = [Diagnostics.Stopwatch]::StartNew()
    try { $o104 = @(& "$S\Invoke-Grader.ps1" -Repo $r104 -Task G1.A -Root $r104 -Label red -Only grader -ExpectRed -BeatSession integ-104 3>$null); $c104 = $LASTEXITCODE }
    finally { Remove-Item Env:\STREAM_BEAT_SECONDS, Env:\STREAM_GRADER_TIMEOUT_SECONDS -ErrorAction SilentlyContinue }
    $sw104.Stop()
    Start-Sleep -Milliseconds 500
    $gc104 = if (Test-Path $pid104) { Get-Process -Id ([int](Get-Content $pid104)) -ErrorAction SilentlyContinue } else { $null }
    $log104 = Join-Path $r104 '.streams\logs\G1.A.grader.red.txt'
    Case '104a a hung beating grader ends at its limit as GRADER-TIMEOUT exit 8, not RED' ($c104 -eq 8 -and ($o104 -join ' ') -match 'GRADER-TIMEOUT G1\.A' -and $sw104.Elapsed.TotalSeconds -lt 45) "exit=$c104 secs=$([int]$sw104.Elapsed.TotalSeconds) out=$(($o104 | Select-Object -Last 2) -join ' | ')"
    Case '104b the timeout ends the grader''s whole process tree and logs GRADER-TIMEOUT' (-not $gc104 -and (Test-Path $log104) -and @((Get-Content $log104) -match '^GRADER-TIMEOUT').Count -gt 0 -and -not (Get-ChildItem -Path "$log104.*" -ErrorAction SilentlyContinue)) "grandchild=$(if ($gc104) { $gc104.Id } else { 'gone' }) log=$(Test-Path $log104)"
    if ($gc104) { Stop-Process -Id $gc104.Id -Force -ErrorAction SilentlyContinue }

    # 104c: the grader's stdin is an empty file, so a child that reads input (npx's install prompt, Read-Host) gets
    # end-of-input instead of waiting on a hidden console. Run detached and hidden, the way the runner's units do.
    $g104c = "param([string]`$Root)`n`$in = [Console]::In.ReadToEnd()`n'FAIL C1 read ' + `$in.Length + ' chars'`nexit 1"
    $r104c = New-Repo 'r104c' @{ 'G1.A' = $g104c }; $repos += $r104c
    $o104c = Join-Path $Scratch 'grader104c.out.txt'
    $p104c = Start-Process pwsh -WindowStyle Hidden -PassThru -RedirectStandardOutput $o104c -ArgumentList @('-NoProfile', '-NonInteractive', '-File', "$S\Invoke-Grader.ps1", '-Repo', $r104c, '-Task', 'G1.A', '-Root', $r104c, '-Label', 'red', '-Only', 'grader', '-ExpectRed', '-BeatSession', 'integ-104c')
    $done104c = $p104c.WaitForExit(40000)
    if (-not $done104c) { try { $p104c.Kill($true) } catch { } }
    $out104c = if (Test-Path $o104c) { (Get-Content -Raw $o104c) } else { '' }
    Case '104c a beating grader that reads stdin gets end-of-input at once' ($done104c -and $p104c.ExitCode -eq 0 -and $out104c -match 'FAIL C1 read 0 chars') "exited=$done104c code=$(if ($done104c) { $p104c.ExitCode } else { '-' }) out=$(("$out104c".Trim() -split "`n" | Select-Object -First 3) -join ' | ')"

    # 104d: a grader that hangs on MAIN is an environment failure for the integrator (RETRY, task stays built), never
    # SUSPECT: the timeout says nothing about the code or the grader's clauses.
    $g104d = "param([string]`$Root)`nif (`$Root -like '*\wt\*') { 'PASS C1'; exit 0 } else { 'FAIL C1'; Start-Sleep -Seconds 90; exit 1 }"
    $r104d = New-Repo 'r104d' @{ 'G1.O' = $g104d }; $repos += $r104d
    [void](Build $r104d 'G1.O' 'O done' 'build-104d')
    $env:STREAM_GRADER_TIMEOUT_SECONDS = '3'
    try { $o104d = @(& "$S\Integrate-Patch.ps1" -Repo $r104d -Session integ-104d 3>$null) } finally { Remove-Item Env:\STREAM_GRADER_TIMEOUT_SECONDS -ErrorAction SilentlyContinue }
    Case '104d a grader that times out on main is RETRY, task stays built, main untouched' ($o104d[0] -eq 'RETRY G1.O (environment)' -and (T $r104d 'G1.O').state -eq 'built' -and -not (git -C $r104d status --porcelain -- G1.O.txt)) "$($o104d -join ' | ') state=$((T $r104d 'G1.O').state)"

    # 105 (kit item IN-20261010055151-65af): retest-G4-1 put 170 Playwright titles in one --grep; npx.cmd hands the line
    # to cmd.exe, which refused it ('The command line is too long.'), so no test ran and all 170 still counted failed.
    # The retest batches the titles so each command stays under STREAM_RETEST_CMD_MAX. Fixture: a fake Playwright that
    # refuses a --grep over 1500 characters, as cmd.exe refuses a line over 8191; 40 long titles fail in Tier 2 and pass
    # on the re-run; the limit is 1500.
    $pr = Join-Path $Scratch 'pwrepo'; New-Item -ItemType Directory -Path (Join-Path $pr 'tests') -Force | Out-Null; $repos += $pr
    git -C $pr init -q -b main; git -C $pr config user.email t@t; git -C $pr config user.name t; Grant-GitPolicy $pr
    Set-Content (Join-Path $pr 'tests\x.spec.ts') '// spec'
    git -C $pr add -A; git -C $pr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $pr | Out-Null
    $pwFake = Join-Path $Scratch 'fake-playwright.ps1'
    Set-Content -Path $pwFake -Encoding utf8 -Value @'
param([string] $Out, [string] $Mode, [string] $Grep = '')
if ($Grep.Length -gt 1500) { 'The command line is too long.'; exit 1 }
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$specs = @()
for ($i = 1; $i -le 40; $i++) {
    $title = "opens the long named settings page number $i and checks that every widget renders"
    if ($Mode -eq 'retest' -and $title -notmatch $Grep) { continue }
    $st = if ($Mode -eq 'retest') { 'expected' } else { 'unexpected' }
    $specs += @{ title = $title; file = 'x.spec.ts'; tests = @(@{ status = $st; results = @(@{ duration = 1 }) }) }
}
@{ suites = @(@{ title = 'x.spec.ts'; file = 'x.spec.ts'; specs = $specs; suites = @() }) } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Out 'results.json')
if ($Mode -eq 'retest') { exit 0 } else { exit 1 }
'@
    $pwLeg = @{ name = 'PW'; kind = 'playwright'; project = 'tests'
        command = "& '$pwFake' -Out '{runDir}\PW' -Mode tier2"
        retestCommand = "& '$pwFake' -Out '{runDir}\{leg}' -Mode retest -Grep '{grep}'" }
    New-Item -ItemType Directory -Path (Join-Path $pr '.streams\suites') -Force | Out-Null
    @{ group = 'P1'; copyIgnored = @(); setup = @(); legs = @($pwLeg); graders = $false; after = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $pr '.streams\suites\P1.run.json') -Encoding utf8
    $ph = @(@{ at = '2026-10-01T00:00:00Z'; by = 'build-1'; to = 'integrated'; note = 'landed' })
    @{ groups = @(@{ id = 'P1'; name = 'pw'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-1') } })
       tasks = @(@{ id = 'P1.A'; group = 'P1'; title = 'P1.A'; why = @('AC-1'); kind = 'code'; writeSet = @('tests/x.spec.ts'); dependsOn = @(); estMinutes = 5; state = 'integrated'; claim = $null; artifacts = @{}; history = @($ph) },
                 @{ id = 'P1.I'; group = 'P1'; title = 'P1.I'; why = @('AC-1'); kind = 'integration'; writeSet = @(); dependsOn = @(); estMinutes = 5; state = 'ticketed'; claim = $null; artifacts = @{}; history = @($ph) }) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $pr '.streams\tasks.json') -Encoding utf8
    $env:STREAM_RETEST_CMD_MAX = '1500'
    try { $s105 = @(& "$S\Start-SuiteRun.ps1" -Repo $pr -Session integ-p -Group P1 -Reason complete -Wait) } finally { Remove-Item Env:\STREAM_RETEST_CMD_MAX -ErrorAction SilentlyContinue }
    $prd = Join-Path $pr '.streams\suites\runs'
    $rt105 = if (Test-Path (Join-Path $prd 'retest-P1-1.json')) { Get-Content -Raw (Join-Path $prd 'retest-P1-1.json') | ConvertFrom-Json } else { $null }
    $l105 = @(if ($rt105) { @($rt105.legs | Where-Object { $_.step -eq 'leg' }) })
    $res105 = if (Test-Path (Join-Path $prd 'run-P1-1.results.json')) { @((Get-Content -Raw (Join-Path $prd 'run-P1-1.results.json') | ConvertFrom-Json).tests) } else { @() }
    $flaky105 = @($res105 | Where-Object { $_.outcome -eq 'flaky' }).Count
    Case '105a a long Playwright re-run is split into batches, each command under the limit' ($l105.Count -gt 1 -and -not @($l105 | Where-Object { ([string]$_.command).Length -gt 1500 -or $_.exit -ne 0 }).Count -and @($l105 | Select-Object -ExpandProperty name -Unique).Count -eq 1) "legs=$($l105.Count) lengths=$((@($l105 | ForEach-Object { ([string]$_.command).Length })) -join ',') exits=$((@($l105 | ForEach-Object { $_.exit })) -join ',') run=$($s105 -join ' | ')"
    Case '105b every title of every batch is read back, so all 40 re-run passes count' ($flaky105 -eq 40) "flaky=$flaky105 of $($res105.Count)"

    # 105c (kit item IN-20261026151817-80e7, G17.T122): a test reported under a teardown Playwright project
    # (fleet-stopping) re-run by --grep runs alone, without its dependency chain, and failed 'REFUSED: no CLI
    # credential exists'. Export keeps the Playwright project (pwProject); a leg's retestWholeFile projects re-run their
    # spec files with no grep, in a batch of their own, while a chromium failure keeps its grep. Fixture: the fake fails
    # the fleet test whenever a grep is given.
    $pr2 = Join-Path $Scratch 'pwrepo2'; New-Item -ItemType Directory -Path (Join-Path $pr2 'tests') -Force | Out-Null; $repos += $pr2
    git -C $pr2 init -q -b main; git -C $pr2 config user.email t@t; git -C $pr2 config user.name t; Grant-GitPolicy $pr2
    Set-Content (Join-Path $pr2 'tests\x.spec.ts') '// spec'
    git -C $pr2 add -A; git -C $pr2 commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $pr2 | Out-Null
    $pwFake2 = Join-Path $Scratch 'fake-playwright2.ps1'
    Set-Content -Path $pwFake2 -Encoding utf8 -Value @'
param([string] $Out, [string] $Mode, [string] $Grep = '')
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$specs = @()
foreach ($p in @(@('checks the page', 'chromium'), @('stops the fleet', 'fleet-stopping'))) {
    if ($Mode -eq 'retest' -and $Grep -and $p[0] -notmatch $Grep) { continue }
    $ok = $Mode -eq 'retest' -and ($p[1] -ne 'fleet-stopping' -or -not $Grep)
    $specs += @{ title = $p[0]; file = 'x.spec.ts'; tests = @(@{ projectName = $p[1]; status = $(if ($ok) { 'expected' } else { 'unexpected' }); results = @(@{ duration = 1 }) }) }
}
@{ suites = @(@{ title = 'x.spec.ts'; file = 'x.spec.ts'; specs = $specs; suites = @() }) } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $Out 'results.json')
if ($Mode -eq 'retest') { exit 0 } else { exit 1 }
'@
    $pwLeg2 = @{ name = 'PW'; kind = 'playwright'; project = 'tests'; retestWholeFile = @('fleet-stopping')
        command = "& '$pwFake2' -Out '{runDir}\PW' -Mode tier2"
        retestCommand = "& '$pwFake2' -Out '{runDir}\{leg}' -Mode retest -Grep '{grep}'" }
    New-Item -ItemType Directory -Path (Join-Path $pr2 '.streams\suites') -Force | Out-Null
    @{ group = 'P2'; copyIgnored = @(); setup = @(); legs = @($pwLeg2); graders = $false; after = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $pr2 '.streams\suites\P2.run.json') -Encoding utf8
    @{ groups = @(@{ id = 'P2'; name = 'pw2'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-1') } })
       tasks = @(@{ id = 'P2.A'; group = 'P2'; title = 'P2.A'; why = @('AC-1'); kind = 'code'; writeSet = @('tests/x.spec.ts'); dependsOn = @(); estMinutes = 5; state = 'integrated'; claim = $null; artifacts = @{}; history = @($ph) },
                 @{ id = 'P2.I'; group = 'P2'; title = 'P2.I'; why = @('AC-1'); kind = 'integration'; writeSet = @(); dependsOn = @(); estMinutes = 5; state = 'ticketed'; claim = $null; artifacts = @{}; history = @($ph) }) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $pr2 '.streams\tasks.json') -Encoding utf8
    $s105c = @(& "$S\Start-SuiteRun.ps1" -Repo $pr2 -Session integ-p2 -Group P2 -Reason complete -Wait)
    $prd2 = Join-Path $pr2 '.streams\suites\runs'
    $rt105c = if (Test-Path (Join-Path $prd2 'retest-P2-1.json')) { Get-Content -Raw (Join-Path $prd2 'retest-P2-1.json') | ConvertFrom-Json } else { $null }
    $l105c = @(if ($rt105c) { @($rt105c.legs | Where-Object { $_.step -eq 'leg' }) })
    $res105c = if (Test-Path (Join-Path $prd2 'run-P2-1.results.json')) { @((Get-Content -Raw (Join-Path $prd2 'run-P2-1.results.json') | ConvertFrom-Json).tests) } else { @() }
    $fleet105c = @($res105c | Where-Object { $_.test -like '*stops the fleet' }) | Select-Object -First 1
    Case '105c a Playwright result row keeps the project the test ran under (pwProject)' ($fleet105c -and $fleet105c.PSObject.Properties['pwProject'] -and $fleet105c.pwProject -eq 'fleet-stopping') "row=$($fleet105c | ConvertTo-Json -Compress) run=$($s105c -join ' | ')"
    $noGrep105c = @($l105c | Where-Object { ([string]$_.command) -match "-Grep ''" }).Count
    $grep105c = @($l105c | Where-Object { ([string]$_.command) -match "-Grep 'checks the page\(" }).Count
    $flaky105c = @($res105c | Where-Object { $_.outcome -eq 'flaky' }).Count
    Case '105d a retestWholeFile project re-runs with no grep in its own batch, a chromium failure keeps its grep, both pass' ($l105c.Count -eq 2 -and $noGrep105c -eq 1 -and $grep105c -eq 1 -and $flaky105c -eq 2) "legs=$($l105c.Count) commands=$((@($l105c | ForEach-Object { $_.command })) -join ' || ') flaky=$flaky105c"

    # 106 (kit item IN-20261010093355-b1d5): G4.T131's -Live unit sat on a permission prompt from 09:14Z with its own beat
    # loop stopped, and the watchdog broke its claim at 10:00Z while the session still waited. The runner pauses the
    # unit timeout on a prompt, so it now beats the unit's claims too. Fixture: the stub claims a row, opens a prompt,
    # reads the claim's beat, waits 5 s (beat every 1 s), reads it again, answers and ends.
    $r106 = New-Repo 'runner106' ([ordered]@{ 'G1.T' = (ContentGrader 'G1.T' 'done') }); $repos += $r106; Open-Gate $r106 stream-kit
    $ai106 = Join-Path $Scratch 'ai-stub106.ps1'; Set-Content -LiteralPath $ai106 -Value @('exit 0')
    $cl106 = Join-Path $Scratch 'claude-stub106.ps1'; $b106 = Join-Path $Scratch 'claude-stub106.beats.txt'
    $readBeat106 = "((Get-Content -Raw (Join-Path '$r106' '.streams\tasks.json') | ConvertFrom-Json -DateKind String).tasks | Where-Object { `$_.id -eq 'G1.T' }).claim.beat"
    Set-Content -LiteralPath $cl106 -Value @(
        "& '$S\Claim-Task.ps1' -Repo '$r106' -Role build -Session `$env:STREAM_UNIT_SESSION | Out-Null"
        "Set-Content -LiteralPath (`$env:STREAM_UNIT_OUT + '.waiting.json') -Value '{""waiting"":true,""since"":1,""count"":1,""tool"":""Bash"",""reason"":""Contains simple_expansion""}'"
        'Start-Sleep -Seconds 2'
        "Add-Content -LiteralPath '$b106' -Value ($readBeat106)"
        'Start-Sleep -Seconds 5'
        "Add-Content -LiteralPath '$b106' -Value ($readBeat106)"
        "Set-Content -LiteralPath (`$env:STREAM_UNIT_OUT + '.waiting.json') -Value '{""waiting"":false,""at"":2}'"
        'Start-Sleep -Seconds 2'
        "Set-Content -LiteralPath `$env:STREAM_UNIT_OUT -Value '{""result"":""stub106"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0,""outcome"":""idle""}'"
        'exit 0')
    $prevWt106 = $env:WT_SESSION; $prevBlock106 = $env:WAVETERM_BLOCKID; $prevPane106 = $env:WEZTERM_PANE
    Remove-Item Env:\WT_SESSION, Env:\WAVETERM_BLOCKID, Env:\WEZTERM_PANE -ErrorAction SilentlyContinue
    $env:STREAM_RUNNER_AI = $ai106; $env:STREAM_RUNNER_CLAUDE = $cl106; $env:STREAM_BEAT_SECONDS = '1'
    try {
        $job106 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 60 -MaxRuns 1 } -ArgumentList $S, $r106
        $null = Wait-Job $job106 -Timeout 90
        $o106 = @(Receive-Job $job106 -Keep 3>$null); Stop-Job $job106 -ErrorAction SilentlyContinue; Remove-Job $job106 -Force -ErrorAction SilentlyContinue
    } finally {
        Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE, Env:\STREAM_BEAT_SECONDS -ErrorAction SilentlyContinue
        if ($null -ne $prevWt106) { $env:WT_SESSION = $prevWt106 }
        if ($null -ne $prevBlock106) { $env:WAVETERM_BLOCKID = $prevBlock106 }
        if ($null -ne $prevPane106) { $env:WEZTERM_PANE = $prevPane106 }
    }
    $beats106 = @(if (Test-Path $b106) { Get-Content $b106 | Where-Object { $_ } })
    $moved106 = $beats106.Count -eq 2 -and [string]$beats106[1] -gt [string]$beats106[0]
    Case '106 the runner beats the unit''s claim while it waits on a permission prompt' $moved106 "beats=$($beats106 -join ' -> ') out=$(($o106 | Select-Object -Last 3) -join ' | ')"

    # 107 (kit item IN-20261010145324-4e04): retest-G4-3 built its own Playwright command and dropped the env the leg
    # sets (NODE_USE_SYSTEM_CA), so its preflight died on 'self-signed certificate' and 6 failed tests counted as
    # confirmed failures. The leg here sets STREAM_T107 in its own command and has no retestCommand; the fake npx passes
    # its re-run only when STREAM_T107 reached it.
    $pr7 = Join-Path $Scratch 'pwrepo107'; New-Item -ItemType Directory -Path (Join-Path $pr7 'tests') -Force | Out-Null; $repos += $pr7
    git -C $pr7 init -q -b main; git -C $pr7 config user.email t@t; git -C $pr7 config user.name t; Grant-GitPolicy $pr7
    Set-Content (Join-Path $pr7 'tests\y.spec.ts') '// spec'
    git -C $pr7 add -A; git -C $pr7 commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $pr7 | Out-Null
    $bin107 = Join-Path $Scratch 'npx107'; New-Item -ItemType Directory -Path $bin107 -Force | Out-Null
    Set-Content -Path (Join-Path $bin107 'npx.ps1') -Encoding utf8 -Value @'
$retest = $args[0] -ne 'tier2'
if ($retest) { $args | Set-Content (Join-Path (Split-Path $env:PLAYWRIGHT_JSON_OUTPUT_NAME) 'npx-args.txt') }
$st = if ($retest -and $env:STREAM_T107 -eq 'on-P7') { 'expected' } else { 'unexpected' }
$specs = @(@{ title = 'signs in through the self-signed stack'; file = 'y.spec.ts'; tests = @(@{ status = $st; results = @(@{ duration = 1 }) }) })
@{ suites = @(@{ title = 'y.spec.ts'; file = 'y.spec.ts'; specs = $specs; suites = @() }) } | ConvertTo-Json -Depth 10 | Set-Content $env:PLAYWRIGHT_JSON_OUTPUT_NAME
if ($st -eq 'expected') { exit 0 } else { "STREAM_T107='$env:STREAM_T107'"; exit 1 }
'@
    $pwLeg7 = @{ name = 'PW'; kind = 'playwright'; project = 'tests'
        command = "`$env:STREAM_T107='on-{group}'; `$env:PLAYWRIGHT_JSON_OUTPUT_NAME='{runDir}\PW\results.json'; New-Item -ItemType Directory -Force -Path '{runDir}\PW' | Out-Null; Set-Location -LiteralPath tests; npx tier2" }
    New-Item -ItemType Directory -Path (Join-Path $pr7 '.streams\suites') -Force | Out-Null
    @{ group = 'P7'; copyIgnored = @(); setup = @(); legs = @($pwLeg7); graders = $false; after = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $pr7 '.streams\suites\P7.run.json') -Encoding utf8
    @{ groups = @(@{ id = 'P7'; name = 'pw'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-1') } })
       tasks = @(@{ id = 'P7.A'; group = 'P7'; title = 'P7.A'; why = @('AC-1'); kind = 'code'; writeSet = @('tests/y.spec.ts'); dependsOn = @(); estMinutes = 5; state = 'integrated'; claim = $null; artifacts = @{}; history = @($ph) },
                 @{ id = 'P7.I'; group = 'P7'; title = 'P7.I'; why = @('AC-1'); kind = 'integration'; writeSet = @(); dependsOn = @(); estMinutes = 5; state = 'ticketed'; claim = $null; artifacts = @{}; history = @($ph) }) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $pr7 '.streams\tasks.json') -Encoding utf8
    $prevPath107 = $env:PATH; $env:PATH = "$bin107;$env:PATH"; Remove-Item Env:\STREAM_T107 -ErrorAction SilentlyContinue
    try { $s107 = @(& "$S\Start-SuiteRun.ps1" -Repo $pr7 -Session integ-p7 -Group P7 -Reason complete -Wait) } finally { $env:PATH = $prevPath107 }
    $prd7 = Join-Path $pr7 '.streams\suites\runs'
    $rt107 = if (Test-Path (Join-Path $prd7 'retest-P7-1.json')) { Get-Content -Raw (Join-Path $prd7 'retest-P7-1.json') | ConvertFrom-Json } else { $null }
    $cmd107 = @(if ($rt107) { @($rt107.legs | Where-Object { $_.step -eq 'leg' } | ForEach-Object { [string]$_.command }) })
    $res107 = if (Test-Path (Join-Path $prd7 'run-P7-1.results.json')) { @((Get-Content -Raw (Join-Path $prd7 'run-P7-1.results.json') | ConvertFrom-Json).tests) } else { @() }
    $flaky107 = @($res107 | Where-Object { $_.outcome -eq 'flaky' }).Count
    Case '107 a re-run keeps the env its leg sets, so the failed test re-runs and counts as flaky' ($flaky107 -eq 1 -and $cmd107.Count -eq 1 -and $cmd107[0] -like "`$env:STREAM_T107='on-P7'*" -and @([regex]::Matches($cmd107[0], 'PLAYWRIGHT_JSON_OUTPUT_NAME')).Count -eq 1) "flaky=$flaky107 of $($res107.Count) cmd=$($cmd107 -join ' || ') run=$($s107 -join ' | ')"
    # 107b (kit item IN-20261016100941-a15f): run-G14-2's Playwright retest passed '--reporter=json line' because npx was
    # npx.ps1 and the reporter list was unquoted. The fake npx above is a .ps1 too, and records the args it received.
    $args107 = @(if ($rt107) { $o107 = @($rt107.legs | Where-Object { $_.step -eq 'leg' } | ForEach-Object { [string]$_.outDir })[0]; if ($o107 -and (Test-Path (Join-Path $o107 'npx-args.txt'))) { Get-Content (Join-Path $o107 'npx-args.txt') } })
    Case '107b a Playwright re-run through npx.ps1 receives --reporter=json,line as one argument' ($args107 -contains '--reporter=json,line' -and $cmd107.Count -eq 1 -and $cmd107[0] -like "*'--reporter=json,line'*") "args=$($args107 -join ' | ') cmd=$($cmd107 -join ' || ')"

    # 108 (kit item IN-20261010151453-fc3c): G4 could not close. Two run-G4-3 failures had fix rows that never land:
    # G4.R1F15 was RETIRED (measured green alone) and G4.R1F18 was retired after the OWNER exempted its test. Tier 3
    # retested only failures whose fix row integrated, so both stayed UNRETESTED for ever. Now a retired fix row counts
    # as landed when it is retired, and Test-GroupClose.ps1 -Exempt records an owner exemption the close rule, the
    # retest and later attributions honour. Fixture: Real (fix row retired, re-runs green) and Gone (exempted).
    $er = Join-Path $Scratch 'exemptrepo'; New-Item -ItemType Directory -Path (Join-Path $er 'tests') -Force | Out-Null; $repos += $er
    git -C $er init -q -b main; git -C $er config user.email t@t; git -C $er config user.name t; Grant-GitPolicy $er
    Set-Content (Join-Path $er 'tests\FooTests.cs') 'namespace NS { public class FooTests { } }'
    Set-Content (Join-Path $er 'tests\BarTests.cs') 'namespace NS { public class BarTests { } }'
    git -C $er add -A; git -C $er commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $er | Out-Null
    $ctl108 = Join-Path $Scratch 'fake-outcomes108.json'
    @{ tier2 = @{ 'NS.FooTests.Real' = 'Failed'; 'NS.BarTests.Gone' = 'Failed' }; retest = @{ 'NS.FooTests.Real' = 'Failed'; 'NS.BarTests.Gone' = 'Failed' } } | ConvertTo-Json | Set-Content $ctl108 -Encoding utf8
    $leg108 = @{ name = 'Tests.Unit'; kind = 'dotnet'; project = 'tests'
        command = "& '$fake' -Out '{runDir}\Tests.Unit' -Mode tier2 -Control '$ctl108'"
        retestCommand = "& '$fake' -Out '{runDir}\Tests.Unit' -Mode retest -Filter '{filter}' -Control '$ctl108'" }
    New-Item -ItemType Directory -Path (Join-Path $er '.streams\suites') -Force | Out-Null
    @{ group = 'E1'; copyIgnored = @(); setup = @(); legs = @($leg108); graders = $false; after = @() } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $er '.streams\suites\E1.run.json') -Encoding utf8
    @{ groups = @(@{ id = 'E1'; name = 'one'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-1') } })
       tasks = @((& $Tt 'E1.A' 'E1' 'integrated' 'tests/FooTests.cs'), (& $Tt 'E1.B' 'E1' 'integrated' 'tests/BarTests.cs'), (& $Tt 'E1.I' 'E1' 'ticketed' @() 'integration')) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $er '.streams\tasks.json') -Encoding utf8
    $null = @(& "$S\Start-SuiteRun.ps1" -Repo $er -Session integ-e -Group E1 -Reason complete -Wait)
    $erd = Join-Path $er '.streams\suites\runs'
    $a108 = Get-Content -Raw (Join-Path $erd 'run-E1-1.attribution.json') | ConvertFrom-Json
    $fixReal = [string](@($a108.failures | Where-Object { $_.test -eq 'NS.FooTests.Real' }) | Select-Object -First 1).fixTask
    $fixGone = [string](@($a108.failures | Where-Object { $_.test -eq 'NS.BarTests.Gone' }) | Select-Object -First 1).fixTask
    # Both fix rows are withdrawn the way Revise-Task.ps1 -Release retire leaves them: done plus a retired record.
    Start-Sleep -Seconds 1
    $d = J $er
    foreach ($fid in @($fixReal, $fixGone)) { $ft = $d.tasks | Where-Object { $_.id -eq $fid }; if ($ft) { $ft.state = 'done'; $ft['retired'] = @{ at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'plan-e'; note = 'withdrawn' } } }
    $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $er '.streams\tasks.json') -Encoding utf8
    Start-Sleep -Seconds 1
    $x0 = @(); $x0x = -1; try { $x0 = @(& "$S\Test-GroupClose.ps1" -Repo $er -Group E1 -Session integ-e -Exempt $fixGone); $x0x = $LASTEXITCODE } catch { $x0 = @("threw: $(("$_" -split "`n")[0])") }
    $x1 = @(); $x1x = -1; try { $x1 = @(& "$S\Test-GroupClose.ps1" -Repo $er -Group E1 -Session integ-e -Exempt 'E1.NOPE' -Reason 'OWNER test'); $x1x = $LASTEXITCODE } catch { $x1 = @("threw: $(("$_" -split "`n")[0])") }
    $x2 = @(); $x2x = -1; try { $x2 = @(& "$S\Test-GroupClose.ps1" -Repo $er -Group E1 -Session integ-e -Exempt $fixGone -Reason 'OWNER 2026-10-10 (fixture): mockup files do not exist'); $x2x = $LASTEXITCODE } catch { $x2 = @("threw: $(("$_" -split "`n")[0])") }
    $ex108 = @(if (Test-Path (Join-Path $er '.streams\suites\exempt.E1.json')) { Get-Content -Raw (Join-Path $er '.streams\suites\exempt.E1.json') | ConvertFrom-Json })
    Case '108a -Exempt needs a reason, refuses an unknown fix row, and records the owner exemption' ($x0x -eq 2 -and $x1x -eq 2 -and ($x1 -join ' ') -match 'NO-MATCH' -and $x2x -eq 0 -and ($x2 -join ' ') -match 'EXEMPTED E1 NS\.BarTests\.Gone' -and $ex108.Count -eq 1 -and $ex108[0].test -eq 'NS.BarTests.Gone' -and $ex108[0].reason -match 'OWNER') "noReason=$x0x/$($x0 -join ' ') unknown=$x1x/$($x1 -join ' ') ok=$x2x/$($x2 -join ' ') file=$($ex108 | ConvertTo-Json -Compress)"
    @{ tier2 = @{ 'NS.FooTests.Real' = 'Failed'; 'NS.BarTests.Gone' = 'Failed' }; retest = @{ 'NS.FooTests.Real' = 'Passed'; 'NS.BarTests.Gone' = 'Failed' } } | ConvertTo-Json | Set-Content $ctl108 -Encoding utf8
    $q108 = @(); try { $q108 = @(& "$S\Invoke-Retest.ps1" -Repo $er -Session integ-e -Group E1 -Mode fix) } catch { $q108 = @("threw: $(("$_" -split "`n")[0])") }
    $rt108 = if (Test-Path (Join-Path $erd 'retest-E1-2.json')) { Get-Content -Raw (Join-Path $erd 'retest-E1-2.json') | ConvertFrom-Json } else { $null }
    Case '108b Tier 3 re-runs the failure of a RETIRED fix row, and never the exempted one' ($rt108 -and $rt108.tier -eq '3' -and @($rt108.tests).Count -eq 1 -and $rt108.tests[0] -eq 'NS.FooTests.Real' -and ($q108 -join ' ') -match 'RETEST retest-E1-2 pass') (($q108 -join ' | ') + " tests=$(if ($rt108) { @($rt108.tests) -join ',' })")
    $c108 = @(); $c108x = -1; try { $c108 = @(& "$S\Test-GroupClose.ps1" -Repo $er -Group E1 -DryRun); $c108x = $LASTEXITCODE } catch { $c108 = @("threw: $(("$_" -split "`n")[0])") }
    Case '108c the close passes: the retired row''s failure passed Tier 3, the exempted one is out of the rule' ($c108x -eq 0 -and ($c108 -join ' ') -match 'CLOSE-OK E1 tier2 run-E1-1 retests 1 exempt 1') ($c108 -join ' | ')
    $null = @(& "$S\Start-SuiteRun.ps1" -Repo $er -Session integ-e -Group E1 -Reason manual -Wait)
    $a108b = if (Test-Path (Join-Path $erd 'run-E1-2.attribution.json')) { Get-Content -Raw (Join-Path $erd 'run-E1-2.attribution.json') | ConvertFrom-Json } else { $null }
    $g108 = @(if ($a108b) { @($a108b.failures | Where-Object { $_.test -eq 'NS.BarTests.Gone' }) })
    $newBar = @((J $er).tasks | Where-Object { $_.id -like 'E1.R2F*' -and @($_.writeSet) -contains 'tests/BarTests.cs' })
    Case '108d a later run attributes the exempted failure exempt, with no fix task' ($g108.Count -eq 1 -and $g108[0].disposition -eq 'exempt' -and -not $g108[0].fixTask -and -not $newBar.Count) "attr=$($a108b | ConvertTo-Json -Compress -Depth 4) newBar=$(@($newBar | ForEach-Object id) -join ',')"
    # 108e (kit item IN-20261020152530-aead): the owner rules a test out BEFORE any run fails it; -Pending records it
    # with run 'pending', refuses a row-id-shaped value, and a second call reads (already).
    $y0 = @(); $y0x = -1; try { $y0 = @(& "$S\Test-GroupClose.ps1" -Repo $er -Group E1 -Session integ-e -Exempt 'NS.NewTests.Missing' -Pending -Reason 'OWNER 2026-10-20 (fixture): mockups absent'); $y0x = $LASTEXITCODE } catch { $y0 = @("threw: $(("$_" -split "`n")[0])") }
    $y1 = @(); $y1x = -1; try { $y1 = @(& "$S\Test-GroupClose.ps1" -Repo $er -Group E1 -Session integ-e -Exempt 'E1.R9F1' -Pending -Reason 'OWNER test'); $y1x = $LASTEXITCODE } catch { $y1 = @("threw: $(("$_" -split "`n")[0])") }
    $y2 = @(); $y2x = -1; try { $y2 = @(& "$S\Test-GroupClose.ps1" -Repo $er -Group E1 -Session integ-e -Exempt 'NS.NewTests.Missing' -Pending -Reason 'OWNER again'); $y2x = $LASTEXITCODE } catch { $y2 = @("threw: $(("$_" -split "`n")[0])") }
    $ex108e = @($(if (Test-Path (Join-Path $er '.streams\suites\exempt.E1.json')) { Get-Content -Raw (Join-Path $er '.streams\suites\exempt.E1.json') | ConvertFrom-Json }) | Where-Object { $_.test -eq 'NS.NewTests.Missing' })
    Case '108e -Exempt -Pending records an exemption no run has failed yet, refuses a row id, and is idempotent' ($y0x -eq 0 -and ($y0 -join ' ') -match 'EXEMPTED-PENDING E1 NS\.NewTests\.Missing' -and $y1x -eq 2 -and ($y1 -join ' ') -match 'REFUSED' -and $y2x -eq 0 -and ($y2 -join ' ') -match '\(already\)' -and $ex108e.Count -eq 1 -and $ex108e[0].run -eq 'pending' -and -not $ex108e[0].fixTask -and $ex108e[0].reason -match 'OWNER 2026-10-20') "p=$y0x/$($y0 -join ' ') id=$y1x/$($y1 -join ' ') again=$y2x/$($y2 -join ' ') file=$($ex108e | ConvertTo-Json -Compress)"

    # 109 (kit item IN-20261010152029-7e12): an author holding a stream-author item may rewrite the grader of a row that
    # is ticketed and not yet claimed (stream-author step 0), but could not record the path: Update-Task needed an
    # author claim and Claim-Task refuses a ticketed row to an author. The live taken item now stands in for the claim,
    # for -Artifacts alone, on a ticketed row nobody has claimed.
    $r109 = New-Repo 'r109' ([ordered]@{ 'G1.W' = (ContentGrader 'G1.W' 'done') }); $repos += $r109
    $d = J $r109; $w = $d.tasks | Where-Object { $_.id -eq 'G1.W' }; $w.state = 'ticketed'; $w.claim = $null
    $d | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $r109 '.streams\tasks.json') -Encoding utf8
    $sent109 = @(& "$S\Send-InboxItem.ps1" -Repo $r109 -To stream-author -From build-x -Kind bug -Task G1.W -Ask 'G1.W: the grader misses clause A6; rewrite it')
    $id109 = if (($sent109 -join ' ') -match 'SENT (IN-\S+)') { $Matches[1] } else { '' }
    & "$S\Set-InboxItem.ps1" -Repo $r109 -Skill stream-author -Id $id109 -Status taken -By author-109 | Out-Null
    $u0 = @(& "$S\Update-Task.ps1" -Repo $r109 -Task G1.W -Role author -Session author-other -Artifacts '{"grader":".streams\\graders\\G1.W.v2.ps1"}'); $u0x = $LASTEXITCODE
    $u1 = @(& "$S\Update-Task.ps1" -Repo $r109 -Task G1.W -Role author -Session author-109 -Artifacts '{"grader":".streams\\graders\\G1.W.v2.ps1"}' -To planned); $u1x = $LASTEXITCODE
    $u2 = @(& "$S\Update-Task.ps1" -Repo $r109 -Task G1.W -Role author -Session author-109 -Artifacts '{"grader":".streams\\graders\\G1.W.v2.ps1"}'); $u2x = $LASTEXITCODE
    $w2 = T $r109 'G1.W'
    Case '109 an author holding an item on a ticketed, unclaimed row sets its grader without a claim; nothing else' ($u0x -eq 3 -and $u1x -eq 2 -and $u2x -eq 0 -and [string]$w2.artifacts.grader -eq '.streams\graders\G1.W.v2.ps1' -and $w2.state -eq 'ticketed' -and -not $w2.claim -and [string]$w2.history[-1].note -match "under inbox item $id109") "other=$u0x/$($u0 -join ' ') withTo=$u1x/$($u1 -join ' ') holder=$u2x/$($u2 -join ' ') grader=$($w2.artifacts.grader) state=$($w2.state) note=$($w2.history[-1].note)"

    # 110 (kit item IN-20261010153049-6849): a unit that ran its cycle and reported outcome 'failed' through unit_done
    # (the mod writes is_error=true for it) and exited 0 was treated as a failed LAUNCH: BACKOFF 900 s, so two build
    # runners idled 15 min each with 20 rows claimable. A reported outcome with exit 0 is a run, not a launch failure.
    $r110 = New-Repo 'runner110' ([ordered]@{ 'G1.T' = (ContentGrader 'G1.T' 'done') }); $repos += $r110; Open-Gate $r110 stream-kit
    $ai110 = Join-Path $Scratch 'ai-stub110.ps1'; Set-Content -LiteralPath $ai110 -Value @('exit 0')
    $cl110 = Join-Path $Scratch 'claude-stub110.ps1'
    Set-Content -LiteralPath $cl110 -Value @(
        "Set-Content -LiteralPath `$env:STREAM_UNIT_OUT -Value '{""result"":""verifier FAIL, row back to ticketed"",""is_error"":true,""num_turns"":3,""total_cost_usd"":0,""outcome"":""failed""}'"
        'exit 0')
    $prevWt110 = $env:WT_SESSION; $prevBlock110 = $env:WAVETERM_BLOCKID; $prevPane110 = $env:WEZTERM_PANE
    Remove-Item Env:\WT_SESSION, Env:\WAVETERM_BLOCKID, Env:\WEZTERM_PANE -ErrorAction SilentlyContinue
    $env:STREAM_RUNNER_AI = $ai110; $env:STREAM_RUNNER_CLAUDE = $cl110
    try {
        $job110 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role kit -Live -IntervalSeconds 1 -UnitTimeoutSeconds 60 -MaxRuns 1 } -ArgumentList $S, $r110
        $null = Wait-Job $job110 -Timeout 60
        $o110 = @(Receive-Job $job110 -Keep 3>$null); Stop-Job $job110 -ErrorAction SilentlyContinue; Remove-Job $job110 -Force -ErrorAction SilentlyContinue
    } finally {
        Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue
        if ($null -ne $prevWt110) { $env:WT_SESSION = $prevWt110 }
        if ($null -ne $prevBlock110) { $env:WAVETERM_BLOCKID = $prevBlock110 }
        if ($null -ne $prevPane110) { $env:WEZTERM_PANE = $prevPane110 }
    }
    $exit110 = @($o110 | Where-Object { "$_" -match ' EXIT 0 outcome failed' })
    Case '110 a unit that reported outcome failed and exited 0 is a run, not a failed launch: no backoff' ($exit110.Count -eq 1 -and "$($exit110[0])" -match ' ok -> ' -and -not @($o110 | Where-Object { "$_" -match ' BACKOFF \d+ s' }).Count) "out=$(($o110 | Select-Object -Last 4) -join ' | ')"

    # 111 (kit item IN-20261010161046-9992): a LIVE holder past the 120 s stale age made every waiter spin. Remove-Item
    # failed on the open lock, the waiter logged "broke stale tasks.json lock" anyway and looped with no sleep: 762,555
    # such lines grew decisions.md to 113 MB, and the flood starved decisions.md appends (Integrate-Patch and
    # Invoke-Retest threw after doing their work). Fixture: another process holds an old lock file open. (a) the tasks
    # lock waits and times out with no break line; (b) the inbox lock times out instead of spinning until the holder
    # lets go; (c) an append outlasts a 7 s hold (the old wait was 5 s).
    . "$S\lib\Streams.ps1"; . "$S\lib\Inbox.ps1"
    $d111 = Join-Path $Scratch 'lock111'; New-Item -ItemType Directory -Path $d111 -Force | Out-Null
    Set-Content (Join-Path $d111 'tasks.json') '{"tasks":[],"groups":[]}'
    $P111 = @{ Lock = (Join-Path $d111 'tasks.json.lock'); Tasks = (Join-Path $d111 'tasks.json'); Decisions = (Join-Path $d111 'decisions.md') }
    $holdOld111 = {
        param([string] $File, [int] $Ms, [string] $Share)
        $ready = "$File.ready"; Remove-Item -LiteralPath $ready -ErrorAction SilentlyContinue
        $cmd = "Set-Content -LiteralPath '$File' -Value '{""session"":""holder-111""}'; (Get-Item -LiteralPath '$File').LastWriteTime = (Get-Date).AddMinutes(-10); " +
            "`$fs = [IO.File]::Open('$File', 'Open', 'Read', '$Share'); Set-Content -LiteralPath '$ready' -Value x; Start-Sleep -Milliseconds $Ms; `$fs.Dispose()"
        $p = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-NonInteractive', '-Command', $cmd
        $w = 0; while (-not (Test-Path $ready) -and $w -lt 200) { Start-Sleep -Milliseconds 100; $w++ }
        $p
    }
    # (a)
    $h111a = & $holdOld111 $P111.Lock 8000 'Read'
    $prevWait111 = $env:STREAM_TASKS_LOCK_WAIT_SECONDS; $env:STREAM_TASKS_LOCK_WAIT_SECONDS = '3'
    $sw111 = [Diagnostics.Stopwatch]::StartNew(); $e111a = ''
    try { [void](Invoke-TasksLocked $P111 'waiter-111' { param($doc) $null }) } catch { $e111a = ("$_" -split "`n")[0] }
    $t111a = $sw111.Elapsed.TotalSeconds
    if ($null -ne $prevWait111) { $env:STREAM_TASKS_LOCK_WAIT_SECONDS = $prevWait111 } else { Remove-Item Env:\STREAM_TASKS_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue }
    [void]$h111a.WaitForExit(20000)
    $brk111 = @(if (Test-Path $P111.Decisions) { Get-Content $P111.Decisions | Where-Object { $_ -like '*broke stale*' } }).Count
    Case '111a a live holder of an old tasks lock is waited for: the wait times out and no break is logged' (($e111a -match 'lock busy') -and $t111a -lt 7 -and $brk111 -eq 0) "err='$e111a' secs=$([Math]::Round($t111a,1)) breakLines=$brk111"
    # (b)
    $ib111 = Join-Path $d111 'stream-kit.md'; Set-Content -LiteralPath $ib111 -Value '# inbox'
    $h111b = & $holdOld111 "$ib111.lock" 19000 'Read'
    $sw111.Restart(); $e111b = ''
    try { [void](Invoke-InboxLocked $ib111 'waiter-111' { @() }) } catch { $e111b = ("$_" -split "`n")[0] }
    $t111b = $sw111.Elapsed.TotalSeconds
    [void]$h111b.WaitForExit(30000)
    Case '111b a live holder of an old inbox lock is waited for, and the wait times out at 15 s' (($e111b -match 'inbox lock busy') -and $t111b -lt 18) "err='$e111b' secs=$([Math]::Round($t111b,1))"
    # (c)
    $f111 = Join-Path $d111 'append.md'; Set-Content -LiteralPath $f111 -Value '- first'
    $rd111 = "$f111.ready"
    $h111c = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-NonInteractive', '-Command', "`$fs = [IO.File]::Open('$f111', 'Open', 'ReadWrite', 'None'); Set-Content -LiteralPath '$rd111' -Value x; Start-Sleep -Milliseconds 7000; `$fs.Dispose()"
    $w111 = 0; while (-not (Test-Path $rd111) -and $w111 -lt 200) { Start-Sleep -Milliseconds 100; $w111++ }
    $e111c = ''; try { Add-LineTo $f111 '- appended after 7 s' } catch { $e111c = ("$_" -split "`n")[0] }
    [void]$h111c.WaitForExit(20000)
    Case '111c an append outlasts a 7 s hold on the file' ((Test-Path $rd111) -and -not $e111c -and ((Get-Content -Raw $f111) -match 'appended after 7 s')) "ready=$(Test-Path $rd111) err='$e111c'"
    # (d) a reader never shuts out an append: Build-CostPage held decisions.md for 37.6 s through [IO.File]::ReadLines
    # (FileShare.Read), and every append in that window threw. Read-SharedLines shares write and delete; the cost page
    # reads decisions.md and the inboxes through it.
    $f111d = Join-Path $d111 'shared.md'; Set-Content -LiteralPath $f111d -Value @('- a', '- b', '- c')
    $prevApp111 = $env:STREAM_APPEND_WAIT_SECONDS; $env:STREAM_APPEND_WAIT_SECONDS = '1'
    $e111d = ''; $n111d = 0
    try { Read-SharedLines $f111d | ForEach-Object { if ($n111d -eq 0) { Add-LineTo $f111d '- appended mid-read' }; $n111d++ } } catch { $e111d = ("$_" -split "`n")[0] }
    if ($null -ne $prevApp111) { $env:STREAM_APPEND_WAIT_SECONDS = $prevApp111 } else { Remove-Item Env:\STREAM_APPEND_WAIT_SECONDS -ErrorAction SilentlyContinue }
    $src111 = Get-Content -Raw "$S\Build-CostPage.ps1"
    Case '111d an append lands while a reader walks the file, and the cost page reads through that reader' (-not $e111d -and ((Get-Content -Raw $f111d) -match 'appended mid-read') -and ($src111 -notmatch 'IO\.File\]::ReadLines') -and ($src111 -match 'Read-SharedLines \$P\.Decisions')) "err='$e111d' lines=$n111d"

    # ---- 112. A pre-stage that loses the tasks.json lock race is retried after a short wait, not backed off as a failed
    # run (kit item IN-20261010172833-eff6: 16 runners restarted together on 2026-10-10, 10 lost the race to two
    # holders and slept 900 s). A live holder keeps the lock for 20 s against a 2 s lock wait (5 s was too short on a loaded host: the runner took 8 s from GATE to PRESTAGE and met no lock, kit item IN-20261016112522-9948); the build runner must log
    # BUSY-RETRY, no BACKOFF, and still launch its unit once the lock is free.
    $r112 = New-Repo 'runner112' ([ordered]@{ 'G1.L' = (ContentGrader 'G1.L' 'done') }); $repos += $r112
    $cl112 = Join-Path $Scratch 'claude-stub112.ps1'
    Set-Content -LiteralPath $cl112 -Value @(
        "'{""type"":""result"",""runner"":""stream-unit"",""outcome"":""built"",""result"":""stub112 ok"",""is_error"":false,""num_turns"":1,""total_cost_usd"":0.01}' | Set-Content -LiteralPath `$env:STREAM_UNIT_OUT"
        'exit 0')
    $ai112 = Join-Path $Scratch 'ai-stub112.ps1'; Set-Content -LiteralPath $ai112 -Value @('exit 0')
    $lock112 = Join-Path $r112 '.streams\tasks.json.lock'; $ready112 = "$lock112.ready"
    $cmd112 = "`$fs = [IO.File]::Open('$lock112', 'CreateNew', 'Write', 'Read'); `$b = [Text.Encoding]::UTF8.GetBytes('{""session"":""holder-112""}'); `$fs.Write(`$b, 0, `$b.Length); `$fs.Flush(); " +
        "Set-Content -LiteralPath '$ready112' -Value x; Start-Sleep -Milliseconds 20000; `$fs.Dispose(); Remove-Item -LiteralPath '$lock112' -Force"
    $h112 = Start-Process pwsh -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-NonInteractive', '-Command', $cmd112
    $w112 = 0; while (-not (Test-Path $ready112) -and $w112 -lt 200) { Start-Sleep -Milliseconds 100; $w112++ }
    $env:STREAM_RUNNER_AI = $ai112; $env:STREAM_RUNNER_CLAUDE = $cl112
    $prevWait112 = $env:STREAM_TASKS_LOCK_WAIT_SECONDS; $env:STREAM_TASKS_LOCK_WAIT_SECONDS = '2'
    $env:STREAM_RUNNER_BUSY_RETRY_SECONDS = '2'
    $job112 = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role build -Live -IntervalSeconds 1 -MaxRuns 1 } -ArgumentList $S, $r112
    $done112 = Wait-Job $job112 -Timeout 180
    $o112 = @(Receive-Job $job112 -Keep -ErrorAction SilentlyContinue); Stop-Job $job112 -ErrorAction SilentlyContinue; Remove-Job $job112 -Force -ErrorAction SilentlyContinue
    [void]$h112.WaitForExit(20000)
    if ($null -ne $prevWait112) { $env:STREAM_TASKS_LOCK_WAIT_SECONDS = $prevWait112 } else { Remove-Item Env:\STREAM_TASKS_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue }
    Remove-Item Env:\STREAM_RUNNER_BUSY_RETRY_SECONDS -ErrorAction SilentlyContinue
    $t112 = $o112 -join "`n"
    Case '112 a pre-stage that loses the lock race retries (BUSY-RETRY), never backs off, and launches once the lock is free' ([bool]$done112 -and (Test-Path $ready112) -and $t112 -match 'PRESTAGE-BUSY .*lock busy for 2s' -and $t112 -match 'BUSY-RETRY \d+ s' -and $t112 -notmatch 'BACKOFF' -and $t112 -notmatch 'PRESTAGE-FAILED' -and $t112 -match 'PRESTAGE \S+ claimed G1\.L' -and $t112 -match ' EXIT 0 outcome built .* ok -> ') "finished=$([bool]$done112) out=$($o112 -join ' | ')"
    Case '112b runner tab: a build GATE line is followed by a plain line naming the row it claims' (($t112 -match '(?m)^\d\d:\d\d:\d\d GATE claimable 1 \(G1\.L\)') -and ($t112 -match '(?m)^  doing      : 1 ticketed row\(s\) are ready to build; this runner claims the first \(G1\.L\) and starts a build session$')) "out=$($o112 -join ' | ')"

    # ---- 112c. A runner leaving a usage-limit hold says so in its state file before the pre-stage (kit item
    # IN-20261024091316-c6c2: on 2026-10-24 four build runners still read 'quota hold until ...' for minutes after the hold
    # lifted, while each claimed and RED-checked a row, so the status page and Wake-StreamRunner showed them held). The
    # row's author grader runs inside the pre-stage and records the runner state status it sees.
    $r112c = Join-Path $Scratch 'runner112c'; $cap112c = Join-Path $Scratch 'runner112c.status.txt'
    $g112c = "param([string]`$Root)`nGet-ChildItem -Path '$r112c\.streams\runners' -Filter 'runner-*.json' | ForEach-Object { (Get-Content -Raw `$_.FullName | ConvertFrom-Json).status } | Set-Content -LiteralPath '$cap112c'`nif ((Get-Content -Raw (Join-Path `$Root 'G1.Q.txt')) -match 'done') { 'PASS C1'; exit 0 } else { 'FAIL C1: not done'; exit 1 }"
    $r112c = New-Repo 'runner112c' ([ordered]@{ 'G1.Q' = $g112c }); $repos += $r112c
    $dir112c = Join-Path $r112c '.streams\runners'; New-Item -ItemType Directory -Path $dir112c -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $dir112c 'quota-hold.json') -Value (@{ until = (Get-Date).ToUniversalTime().AddSeconds(4).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'test-112c'; type = 'seven_day'; at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') } | ConvertTo-Json)
    $env:STREAM_RUNNER_AI = $ai112; $env:STREAM_RUNNER_CLAUDE = $cl112
    $job112c = Start-ThreadJob -ScriptBlock { param($s, $r) & "$s\Start-StreamRunner.ps1" -Repo $r -Role build -Live -IntervalSeconds 1 -MaxRuns 1 } -ArgumentList $S, $r112c
    $done112c = Wait-Job $job112c -Timeout 180
    $o112c = @(Receive-Job $job112c -Keep -ErrorAction SilentlyContinue); Stop-Job $job112c -ErrorAction SilentlyContinue; Remove-Job $job112c -Force -ErrorAction SilentlyContinue
    Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue
    $s112c = @(if (Test-Path $cap112c) { Get-Content $cap112c })
    Case '112c after a quota hold lifts, the runner state reads pre-staging, not quota hold, while the pre-stage runs' ([bool]$done112c -and (($o112c -join "`n") -match 'QUOTA-HOLD until') -and $s112c.Count -ge 1 -and ($s112c -join ' ') -notmatch 'quota hold' -and ($s112c -join ' ') -match 'pre-staging build-') "finished=$([bool]$done112c) status=$($s112c -join ' / ') out=$($o112c -join ' | ')"

    # ---- 112d. A quota hold is probed early: one minimal claude call per STREAM_RUNNER_QUOTA_PROBE_SECONDS per repo
    # lifts a hold the account no longer enforces (kit item IN-20261024093536-3be3: a seven_day hold kept every runner
    # out ~3 h after a headless call already worked). Stub seam STREAM_RUNNER_QUOTA_PROBE_CMD (a .ps1).
    $r112d = Join-Path $Scratch 'probe112d'; New-Item -ItemType Directory -Path (Join-Path $r112d '.streams\runners') -Force | Out-Null
    $mk112d = Join-Path $Scratch 'probe112d.called'
    $ok112d = Join-Path $Scratch 'probe112d-ok.ps1'; Set-Content -LiteralPath $ok112d -Value "Set-Content -LiteralPath '$mk112d' 'x'; '{`"type`":`"result`",`"is_error`":false,`"result`":`"OK`"}'"
    $no112d = Join-Path $Scratch 'probe112d-no.ps1'; Set-Content -LiteralPath $no112d -Value "Set-Content -LiteralPath '$mk112d' 'x'; '{`"type`":`"result`",`"is_error`":true,`"result`":`"You''ve hit your weekly limit · resets Oct 25`"}'"
    $hf112d = Join-Path $r112d '.streams\runners\quota-hold.json'
    $res112d = @{}
    foreach ($c112d in @(@{ k = 'a'; cmd = $ok112d; sec = '1'; probed = $null }, @{ k = 'b'; cmd = $no112d; sec = '1'; probed = $null }, @{ k = 'c'; cmd = $ok112d; sec = '1800'; probed = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ') }, @{ k = 'd'; cmd = $ok112d; sec = '0'; probed = $null })) {
        Remove-Item -LiteralPath $mk112d -Force -ErrorAction SilentlyContinue
        Get-ChildItem (Join-Path $r112d '.streams\runners') -Filter 'quota-hold*' | Remove-Item -Force
        $h112d = [ordered]@{ until = (Get-Date).ToUniversalTime().AddHours(1).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'test-112d'; type = 'seven_day'; at = (Get-Date).ToUniversalTime().AddHours(-1).ToString('yyyy-MM-ddTHH:mm:ssZ') }
        if ($c112d.probed) { $h112d.probedAt = $c112d.probed }
        Set-Content -LiteralPath $hf112d -Value ($h112d | ConvertTo-Json)
        $v112d = pwsh -NoProfile -Command "`$env:STREAM_RUNNER_QUOTA_PROBE_CMD='$($c112d.cmd)'; `$env:STREAM_RUNNER_QUOTA_PROBE_SECONDS='$($c112d.sec)'; . '$S\lib\Streams.ps1'; `$P = Get-StreamPaths '$r112d'; Invoke-QuotaProbe `$P 'runner-112d'" 2>&1
        $hd112d = $null; if (Test-Path $hf112d) { $hd112d = Get-Content -Raw $hf112d | ConvertFrom-Json -AsHashtable }
        $res112d[$c112d.k] = @{ v = (@($v112d) -join ' '); called = (Test-Path $mk112d); held = (Test-Path $hf112d); hold = $hd112d; lifted = @(Get-ChildItem (Join-Path $r112d '.streams\runners') -Filter 'quota-hold.lifted-*.json').Count }
    }
    $a112d = $res112d['a']; $b112d = $res112d['b']; $c112d = $res112d['c']; $d112d = $res112d['d']
    Case '112d probe a: a probe that succeeds lifts the hold (moved aside, not deleted)' ($a112d.v -match 'LIFTED' -and -not $a112d.held -and $a112d.lifted -eq 1) "v=$($a112d.v) held=$($a112d.held) lifted=$($a112d.lifted)"
    Case '112d probe b: a probe the limit rejects keeps the hold and stamps probedAt' ($b112d.v -match 'HELD' -and $b112d.held -and $b112d.hold -and [string]$b112d.hold['probedAt'] -and [string]$b112d.hold['probedBy'] -eq 'runner-112d') "v=$($b112d.v) held=$($b112d.held)"
    Case '112d probe c: inside the interval since probedAt no probe call is made' ($c112d.v -match 'SKIP' -and -not $c112d.called -and $c112d.held) "v=$($c112d.v) called=$($c112d.called)"
    Case '112d probe d: STREAM_RUNNER_QUOTA_PROBE_SECONDS=0 never probes' ($d112d.v -match 'OFF' -and -not $d112d.called -and $d112d.held) "v=$($d112d.v) called=$($d112d.called)"
    # ---- 113. Add-Tasks.ps1 on a board-sized release finishes well inside the 120 s lock break limit (kit item
    # IN-20261010174706-ed53: an 81-row release ran 15 min under the lock, because the dependency chain was walked
    # twice, rebuilding an id table over the whole board, for every (new row, open row) pair before the write sets were
    # compared). A 1000-row board shaped like the live one (480 open, four files and up to three dependencies per row, in chains of 10) takes an 81-row batch, as the release that ran 15 min did (84 s on this fixture before the fix, 5 s after); the chain rule must still hold: a
    # shared file on one chain is added, a shared file off any chain is refused.
    $r113 = Join-Path $Scratch 'addtasks113'; New-Item -ItemType Directory -Path $r113 -Force | Out-Null
    git -C $r113 init -q -b main; & "$S\Init-Streams.ps1" -Repo $r113 | Out-Null
    $board113 = foreach ($i in 0..999) {
        $open = $i -lt 480
        [ordered]@{ id = "G1.B$i"; group = 'G1'; title = "b$i"; why = @('AC-1'); kind = 'code'; writeSet = @("src/b$i.cs", "src/b$i.razor", "tests/b$i.cs", "docs/b$i.md")
            dependsOn = @(foreach ($k in 1..3) { if ($i % 10 -ge $k) { "G1.B$($i - $k)" } }); state = $(if ($open) { 'planned' } else { 'done' }); claim = $null; estMinutes = 5
            artifacts = [ordered]@{ ticket = $null; grader = $null; patch = $null; verdict = $null }; history = @() }
    }
    @{ groups = @(@{ id = 'G1'; name = 'R'; state = 'released'; origin = 'plan' }); tasks = @($board113) } | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $r113 '.streams\tasks.json')
    $batch113 = foreach ($i in 0..80) { [ordered]@{ id = "G1.N$i"; group = 'G1'; title = "n$i"; why = @('AC-1'); kind = 'code'; writeSet = @("src/n$i.cs", "src/n$i.razor"); dependsOn = @("G1.B$($i * 10 + 9)"); estMinutes = 5 } }
    # N0 shares b5.cs, and B5 is on N0's chain (N0 -> B9 -> ... -> B5): allowed.
    $batch113[0].writeSet = @('src/n0.cs', 'src/b5.cs')
    $f113 = Join-Path $Scratch 'batch113.json'; @{ tasks = @($batch113) } | ConvertTo-Json -Depth 10 | Set-Content $f113
    $out113 = Join-Path $Scratch 'addtasks113.out.txt'
    $sw113 = [Diagnostics.Stopwatch]::StartNew()
    $p113 = Start-Process pwsh -PassThru -WindowStyle Hidden -RedirectStandardOutput $out113 -ArgumentList '-NoProfile', '-NonInteractive', '-File', "$S\Add-Tasks.ps1", '-Repo', $r113, '-Role', 'plan', '-Session', 'plan-113', '-File', $f113
    $fin113 = $p113.WaitForExit(40000); $t113 = $sw113.Elapsed.TotalSeconds
    if (-not $fin113) { Stop-Process -Id $p113.Id -Force -ErrorAction SilentlyContinue; [void]$p113.WaitForExit(10000); Remove-Item (Join-Path $r113 '.streams\tasks.json.lock') -Force -ErrorAction SilentlyContinue }
    $o113 = @(if (Test-Path $out113) { Get-Content $out113 })
    $added113 = @($o113 | Where-Object { $_ -like 'ADDED G1.N*' }).Count
    Case '113a an 81-row release on a 1000-row board finishes in under 40 s, with a same-chain shared file allowed' ($fin113 -and $p113.ExitCode -eq 0 -and $added113 -eq 81) "finished=$fin113 secs=$([Math]::Round($t113,1)) added=$added113 out=$($o113 | Select-Object -First 3)"
    # N99 shares b15.cs with no chain to B15 (it depends on B9, a different chain): refused, nothing written.
    $f113b = Join-Path $Scratch 'batch113b.json'
    @{ tasks = @([ordered]@{ id = 'G1.N99'; group = 'G1'; title = 'n99'; why = @('AC-1'); kind = 'code'; writeSet = @('src/b15.cs'); dependsOn = @('G1.B9'); estMinutes = 5 }) } | ConvertTo-Json -Depth 10 | Set-Content $f113b
    $o113b = @(& "$S\Add-Tasks.ps1" -Repo $r113 -Role plan -Session plan-113 -File $f113b); $x113b = $LASTEXITCODE
    Case '113b a shared file off any dependency chain is still refused' ($x113b -eq 2 -and ($o113b -join ' ') -match 'REFUSED G1\.N99: write set overlaps G1\.B15') "exit=$x113b out=$($o113b -join ' | ')"

    # ---- 114. The write-set index Add-Tasks.ps1 compares through (kit item IN-20261010181957-2e7f) never drops a pair
    # Test-WriteSetOverlap would find: for every (write set, row) pair over case, backslash, './', wildcard, directory
    # and comma-joined entries, an overlap implies the row is a candidate; and a plain write set gets a short list.
    . "$S\lib\Streams.ps1"
    $rows114 = @(
        @{ id = 'R1'; writeSet = @('src/A.cs') }, @{ id = 'R2'; writeSet = @('src\b.cs', 'docs/x.md') }, @{ id = 'R3'; writeSet = @('./src/c.cs') }
        @{ id = 'R4'; writeSet = @('evidence/F/') }, @{ id = 'R5'; writeSet = @('tests/*.cs') }, @{ id = 'R6'; writeSet = @('src/[ab].razor') }
        @{ id = 'R7'; writeSet = @('src/d.cs,src/e.cs') }, @{ id = 'R8'; writeSet = @('evidence/F') }, @{ id = 'R9'; writeSet = @() })
    $ix114 = New-WriteSetIndex; foreach ($r in $rows114) { Add-WriteSetIndex $ix114 $r }
    $sets114 = @(@('SRC/a.cs'), @('src/b.cs'), @('src/c.cs'), @('evidence/F/README.md'), @('evidence/F'), @('tests/t.cs'), @('src/a.razor'),
        @('src/d.cs,src/e.cs'), @('src/d.cs'), @('other/z.cs'), @('docs/*.md'), @('evidence/'), @('.\docs\x.md'))
    $miss114 = @(); $plain114 = $null
    foreach ($ws in $sets114) {
        $cand = Get-WriteSetCandidates $ix114 $ws
        foreach ($r in $rows114) { if ((Test-WriteSetOverlap $ws $r.writeSet) -and $null -ne $cand -and -not $cand.Contains($r)) { $miss114 += "$($ws -join ',') x $($r.id)" } }
        if (($ws -join ',') -eq 'other/z.cs') { $plain114 = @($cand | ForEach-Object { $_.id }) -join ',' }
    }
    Case '114 the write-set index keeps every overlapping row as a candidate, and a plain write set compares only with pattern rows' ($miss114.Count -eq 0 -and $plain114 -eq 'R4,R5,R6') "missed=$($miss114 -join '; ') plainCandidates=$plain114"

    # ---- 115. The after steps run last (kit item IN-20261011022936-074c). G4's after step redeployed web from main
    # before the flaky screen re-ran Playwright on the run's snapshot, and a Tier 3 retest ran no after step at all, so
    # web was left on whatever its setup deployed. The after step here appends whether the flaky screen's record exists
    # yet; a fix retest must run it too.
    $ar = Join-Path $Scratch 'afterrepo'; New-Item -ItemType Directory -Path (Join-Path $ar 'tests') -Force | Out-Null; $repos += $ar
    git -C $ar init -q -b main; git -C $ar config user.email t@t; git -C $ar config user.name t; Grant-GitPolicy $ar
    Set-Content (Join-Path $ar 'tests\FooTests.cs') 'namespace NS { public class FooTests { } }'
    git -C $ar add -A; git -C $ar commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $ar | Out-Null
    $ctl115 = Join-Path $Scratch 'fake-outcomes115.json'
    @{ tier2 = @{ 'NS.FooTests.Real' = 'Failed' }; retest = @{ 'NS.FooTests.Real' = 'Failed' } } | ConvertTo-Json | Set-Content $ctl115 -Encoding utf8
    $leg115 = @{ name = 'Tests.Unit'; kind = 'dotnet'; project = 'tests'
        command = "& '$fake' -Out '{runDir}\Tests.Unit' -Mode tier2 -Control '$ctl115'"
        retestCommand = "& '$fake' -Out '{runDir}\Tests.Unit' -Mode retest -Filter '{filter}' -Control '$ctl115'" }
    $ard = Join-Path $ar '.streams\suites\runs'; $mark115 = Join-Path $Scratch 'after115.txt'
    $after115 = @{ name = 'web'; workDir = 'repo'; command = "Add-Content -LiteralPath '$mark115' -Value ('{run} screen=' + [string](Test-Path -LiteralPath '$ard\retest-A1-1.json'))" }
    New-Item -ItemType Directory -Path (Join-Path $ar '.streams\suites') -Force | Out-Null
    @{ group = 'A1'; copyIgnored = @(); setup = @(); legs = @($leg115); graders = $false; after = @($after115) } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $ar '.streams\suites\A1.run.json') -Encoding utf8
    @{ groups = @(@{ id = 'A1'; name = 'one'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-1') } })
       tasks = @((& $Tt 'A1.A' 'A1' 'integrated' 'tests/FooTests.cs'), (& $Tt 'A1.I' 'A1' 'ticketed' @() 'integration')) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $ar '.streams\tasks.json') -Encoding utf8
    $s115 = @(& "$S\Start-SuiteRun.ps1" -Repo $ar -Session integ-a -Group A1 -Reason complete -Wait)
    $m115 = @(if (Test-Path $mark115) { Get-Content $mark115 })
    $run115 = Get-Content -Raw (Join-Path $ard 'run-A1-1.json') | ConvertFrom-Json -DateKind String
    Case '115a a Tier 2 run runs its after steps behind the flaky screen' ($m115.Count -eq 1 -and $m115[0] -eq 'run-A1-1 screen=True' -and @($run115.legs | Where-Object { $_.step -eq 'after' -and $_.exit -eq 0 }).Count -eq 1 -and $run115.status -eq 'done') "marks=$($m115 -join ' ; ') run=$($s115 -join ' | ')"
    # The fix lands after the run; the Tier 3 retest must run the after step once its legs end.
    $start115 = [datetime]::Parse([string]$run115.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal).AddSeconds(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $d115 = J $ar; $fx115 = @($d115.tasks | Where-Object { $_.id -like 'A1.R1F*' })
    foreach ($t in $fx115) { $t.state = 'integrated'; $t.history += @{ at = $start115; by = 'integ-a'; to = 'integrated'; note = 'fix landed' } }
    $d115 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $ar '.streams\tasks.json') -Encoding utf8
    $r115 = @(& "$S\Invoke-Retest.ps1" -Repo $ar -Session integ-a -Group A1 -Mode fix)
    $m115b = @(if (Test-Path $mark115) { Get-Content $mark115 })
    $rt115 = if (Test-Path (Join-Path $ard 'retest-A1-2.json')) { Get-Content -Raw (Join-Path $ard 'retest-A1-2.json') | ConvertFrom-Json } else { $null }
    $rt115a = @(if ($rt115) { @($rt115.legs | Where-Object { $_.step -eq 'after' -and $_.exit -eq 0 }) })
    Case '115b a Tier 3 retest runs the run definition''s after steps once its legs end' ($fx115.Count -eq 1 -and $m115b.Count -eq 2 -and $m115b[1] -eq 'retest-A1-2 screen=True' -and $rt115a.Count -eq 1 -and ($r115 -join ' ') -match 'RETEST retest-A1-2 fail') "fix=$($fx115.Count) marks=$($m115b -join ' ; ') out=$($r115 -join ' | ')"

    Remove-Item Env:\STREAM_RUNNER_AI, Env:\STREAM_RUNNER_CLAUDE -ErrorAction SilentlyContinue

    # ---- 116. Commit-AdhocChange (stream-adhoc, owner ruling 2026-10-11 "Adhoc commits itself"): an ad-hoc change
    # lands on main only after the build and its one targeted test pass there; it commits exactly its own paths, takes
    # itself back off main on a red build or test (or a filter that matched nothing), and never runs while an
    # Integrate-Patch run holds the drain lock or while its paths are dirty on main.
    $r116 = New-Repo 'r116' @{ 'G1.A' = (ContentGrader 'G1.A' 'x') }; $repos += $r116
    $stub116 = Join-Path $Scratch 'dotnet116.ps1'
    Set-Content -LiteralPath $stub116 -Encoding utf8 -Value @'
if ($env:STUB116_FAIL -and $args[0] -eq $env:STUB116_FAIL) { "stub $($args[0]) FAILED"; exit 1 }
if ($args[0] -eq 'test' -and $env:STUB116_NOMATCH -eq '1') { 'No test matches the given testcase filter `X` in t.dll'; exit 0 }
"stub $($args[0]) Passed!"; exit 0
'@
    $env:STREAM_ADHOC_DOTNET = $stub116
    function Wt116([string] $name, [hashtable] $files) {
        $w = Join-Path $Scratch $name
        git -C $r116 worktree add -q --detach $w HEAD 2>&1 | Out-Null
        foreach ($k in $files.Keys) { Set-Content -LiteralPath (Join-Path $w $k) -Value $files[$k] }
        $w
    }
    $w116a = Wt116 'w116a' @{ 'G1.A.txt' = 'adhoc x'; 'new116.txt' = 'new file' }
    $o116a = @(& "$S\Commit-AdhocChange.ps1" -Repo $r116 -Session adhoc-116 -Id ADHOC-20261011-1 -Worktree $w116a -Title 'tweak' -TestProject t.csproj -TestFilter 'FullyQualifiedName~T116'); $x116a = $LASTEXITCODE
    $files116a = @(git -C $r116 show --name-only --format= HEAD | Where-Object { $_ })
    Case '116a adhoc: build + targeted test PASS commits exactly the patch paths' ($x116a -eq 0 -and ($o116a -join ' ') -match '^COMMITTED ADHOC-20261011-1 ' -and (git -C $r116 log -1 --format=%s) -eq 'ADHOC-20261011-1: tweak' -and (@($files116a | Sort-Object) -join ',') -eq 'G1.A.txt,new116.txt' -and ((git -C $r116 status --porcelain) -match 'owner\.txt')) "exit=$x116a out=$($o116a -join ' | ') files=$($files116a -join ',')"

    $head116b = git -C $r116 rev-parse HEAD
    $w116b = Wt116 'w116b' @{ 'G1.A.txt' = 'adhoc y' }
    $env:STUB116_FAIL = 'test'
    $o116b = @(& "$S\Commit-AdhocChange.ps1" -Repo $r116 -Session adhoc-116 -Id ADHOC-20261011-2 -Worktree $w116b -Title 'red' -TestProject t.csproj -TestFilter 'T116'); $x116b = $LASTEXITCODE
    Remove-Item Env:\STUB116_FAIL
    Case '116b adhoc: a red targeted test reverses the patch and commits nothing' ($x116b -eq 1 -and ($o116b -join ' ') -match '^REVERSED ADHOC-20261011-2 \(test failed' -and (git -C $r116 rev-parse HEAD) -eq $head116b -and (Get-Content (Join-Path $r116 'G1.A.txt')) -eq 'adhoc x' -and -not ((git -C $r116 status --porcelain) -match 'G1\.A\.txt')) "exit=$x116b out=$($o116b -join ' | ')"

    $env:STUB116_NOMATCH = '1'
    $o116c = @(& "$S\Commit-AdhocChange.ps1" -Repo $r116 -Session adhoc-116 -Id ADHOC-20261011-3 -Worktree $w116b -Title 'nomatch' -TestProject t.csproj -TestFilter 'Nope'); $x116c = $LASTEXITCODE
    Remove-Item Env:\STUB116_NOMATCH
    Case '116c adhoc: a filter that matches no test is a FAIL, reversed' ($x116c -eq 1 -and ($o116c -join ' ') -match 'matched no test' -and (git -C $r116 rev-parse HEAD) -eq $head116b) "exit=$x116c out=$($o116c -join ' | ')"

    $hold116 = [IO.FileStream]::new((Join-Path $r116 '.streams\integrate-patch.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose)
    try { $o116d = @(& "$S\Commit-AdhocChange.ps1" -Repo $r116 -Session adhoc-116 -Id ADHOC-20261011-4 -Worktree $w116b -Title 'busy' -TestProject t.csproj -TestFilter 'T116' -WaitSeconds 1); $x116d = $LASTEXITCODE }
    finally { $hold116.Dispose() }
    Case '116d adhoc: waits out, then refuses, while an Integrate-Patch run holds the drain lock' ($x116d -eq 4 -and ($o116d -join ' ') -match '^ADHOC-BUSY ADHOC-20261011-4' -and (git -C $r116 rev-parse HEAD) -eq $head116b) "exit=$x116d out=$($o116d -join ' | ')"

    Set-Content -LiteralPath (Join-Path $r116 'G1.A.txt') -Value 'integrator dirt'
    $o116e = @(& "$S\Commit-AdhocChange.ps1" -Repo $r116 -Session adhoc-116 -Id ADHOC-20261011-5 -Worktree $w116b -Title 'dirty' -TestProject t.csproj -TestFilter 'T116'); $x116e = $LASTEXITCODE
    Case '116e adhoc: a path already dirty on main is refused and left as it was' ($x116e -eq 3 -and ($o116e -join ' ') -match '^DIRTY ADHOC-20261011-5 G1\.A\.txt' -and (Get-Content (Join-Path $r116 'G1.A.txt')) -eq 'integrator dirt') "exit=$x116e out=$($o116e -join ' | ')"

    # 116g (kit item IN-20261012180815-5151): the export must keep non-ASCII text byte for byte whatever the console
    # code page. ADHOC-20261012-1 deleted lines holding em dashes and read REBASE twice, because the patch went through
    # [Console]::OutputEncoding (ibm437 under pwsh -NoProfile). One change here deletes an em-dash line and adds an arrow.
    $u8 = [Text.UTF8Encoding]::new($false); $em = [string][char]0x2014; $ar116 = [string][char]0x2192
    [IO.File]::WriteAllText((Join-Path $r116 'dash116.txt'), "keep$em this`ndrop $em this`n", $u8)
    git -C $r116 add dash116.txt; git -C $r116 commit -q -m 'dash base' -- dash116.txt
    $w116g = Wt116 'w116g' @{}
    [IO.File]::WriteAllText((Join-Path $w116g 'dash116.txt'), "keep$em this`nadd $ar116 that`n", $u8)
    $enc116 = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [Text.Encoding]::GetEncoding(437)
        $o116g = @(& "$S\Commit-AdhocChange.ps1" -Repo $r116 -Session adhoc-116 -Id ADHOC-20261012-7 -Worktree $w116g -Title 'dash' -TestProject t.csproj -TestFilter 'T116'); $x116g = $LASTEXITCODE
    } finally { [Console]::OutputEncoding = $enc116 }
    # CR stripped: a host with core.autocrlf=true (SMVMTR1's system config) checks the applied file out as CRLF.
    $got116 = [IO.File]::ReadAllText((Join-Path $r116 'dash116.txt'), $u8).Replace("`r", '')
    Case '116g adhoc: a non-ASCII deletion and addition land byte for byte under a non-UTF-8 console' ($x116g -eq 0 -and ($o116g -join ' ') -match '^COMMITTED ADHOC-20261012-7 ' -and $got116 -eq "keep$em this`nadd $ar116 that`n" -and -not ((git -C $r116 status --porcelain) -match 'dash116')) "exit=$x116g out=$($o116g -join ' | ') file=$got116"
    Remove-Item Env:\STREAM_ADHOC_DOTNET -ErrorAction SilentlyContinue
    $o116f = @(& "$S\Add-Lesson.ps1" -Repo $r116 -Role adhoc -Session adhoc-116 -Task ADHOC-20261011-1 -Text 'run the bUnit test from the worktree'); $x116f = $LASTEXITCODE
    Case '116f adhoc: the ad-hoc role keeps a lessons file' ($x116f -eq 0 -and (Test-Path (Join-Path $r116 '.streams\lessons\adhoc.md'))) "exit=$x116f out=$($o116f -join ' | ')"

    # ---- 117. the watchdog keeps a stream-adhoc tree while its request file exists. The tree names no task, so it read
    # as an orphan and was reaped after the quiet period with nothing saved, while its session waited on the owner's
    # approval (ADHOC-20261011-1, 2026-10-11). A tree with the ADHOC name and no request file is still an orphan.
    $r117 = New-Repo 'r117' @{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }; $repos += $r117
    $wt117 = Build $r117 'G1.A' 'ok' 'build-117'
    $keep117 = Join-Path (Split-Path $wt117) 'ADHOC-20261011-7'; $gone117 = Join-Path (Split-Path $wt117) 'ADHOC-20261011-8'
    foreach ($d117 in @($keep117, $gone117)) {
        git -C $r117 worktree add -q --detach $d117 2>&1 | Out-Null
        Set-Content (Join-Path $d117 'tweak.txt') 'adhoc work'
        foreach ($f in @(Get-ChildItem $d117 -Recurse -File -Force)) { $f.LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddMinutes(-90) }
    }
    New-Item -ItemType Directory -Path (Join-Path $r117 '.streams\adhoc') -Force | Out-Null
    Set-Content (Join-Path $r117 '.streams\adhoc\ADHOC-20261011-7.md') 'request'
    $w117 = @(& "$S\Invoke-Watchdog.ps1" -Repo $r117 -Session status-117)
    Case '117a watchdog: a quiet ADHOC tree with a request file is kept, its work intact' (Test-Path (Join-Path $keep117 'tweak.txt')) ($w117 -join ' | ')
    Case '117b watchdog: an ADHOC-named tree with no request file is still an orphan and is reaped' (-not (Test-Path $gone117)) ($w117 -join ' | ')

    # ---- 118. AUTHOR SPILL (owner ruling 2026-10-12): authors have their own queue. With no planned focus row left, an
    # author claim takes a planned row of another released group instead of reading NONE (five authors sat idle on
    # 2026-10-12 with 70 planned rows in G7-G12), stamps the main commit it was written against, and builders stay
    # focus-only. When the group becomes focus and a write-set file moved since, the board and the build claim say
    # STALE-TICKET.
    $r118 = New-Repo 'r118' @{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }; $repos += $r118
    foreach ($n118 in 'G1.P', 'G2.P', 'G2.Q') { Set-Content (Join-Path $r118 "$n118.txt") "$n118 base" }
    git -C $r118 add G1.P.txt G2.P.txt G2.Q.txt; git -C $r118 commit -q -m 'spill files'
    $d118 = J $r118
    $d118.groups += [ordered]@{ id = 'G2'; name = 'S'; state = 'released'; origin = 'import' }
    foreach ($n118 in 'G1.P', 'G2.P', 'G2.Q') {
        Set-Content (Join-Path $r118 ".streams\tickets\$n118.md") "ticket $n118"
        Set-Content (Join-Path $r118 ".streams\graders\$n118.ps1") (ContentGrader $n118 'ok')
        $d118.tasks += [ordered]@{ id = $n118; group = $n118.Substring(0, 2); title = $n118; why = @('AC-1'); kind = 'code'; writeSet = @("$n118.txt"); dependsOn = @(); estMinutes = 5
            artifacts = [ordered]@{ ticket = ".streams\tickets\$n118.md"; grader = ".streams\graders\$n118.ps1"; patch = $null; verdict = $null }; state = 'planned'; claim = $null; history = @() }
    }
    $d118 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $r118 '.streams\tasks.json') -Encoding utf8
    $a118a = & "$S\Claim-Task.ps1" -Repo $r118 -Role author -Session author-118a | ConvertFrom-Json
    Case '118a spill: an author takes the focus planned row first, unstamped' ($a118a.id -eq 'G1.P' -and -not (T $r118 'G1.P').Contains('spill')) "got $($a118a.id)"
    $o118b = & "$S\Claim-Task.ps1" -Repo $r118 -Role author -Session author-118b
    $a118b = if ("$o118b" -ne 'NONE') { $o118b | ConvertFrom-Json } else { [pscustomobject]@{ id = 'NONE' } }
    $head118 = [string](git -C $r118 rev-parse HEAD)
    $t118b = T $r118 'G2.P'
    Case '118b spill: with no focus row left the author takes a later released group row, stamped with main HEAD' ($a118b.id -eq 'G2.P' -and $t118b.Contains('spill') -and $t118b.spill.base -eq $head118 -and ([string]$t118b.history[-1].note) -match 'author spill') "got $($a118b.id) spill=$($t118b['spill'] | ConvertTo-Json -Compress)"
    $a118f = @(& "$S\Claim-Task.ps1" -Repo $r118 -Role author -Session author-118f -Task G2.Q); $x118f = $LASTEXITCODE
    Case '118c spill: -Task takes a non-focus planned row while the focus set offers authors nothing' ($x118f -eq 0 -and (T $r118 'G2.Q').claim.session -eq 'author-118f') "exit=$x118f out=$($a118f -join ' | ')"
    & "$S\Update-Task.ps1" -Repo $r118 -Task G2.P -Role author -Session author-118b -To ticketed -Release -Note 'ticketed' | Out-Null
    $b118a = & "$S\Claim-Task.ps1" -Repo $r118 -Role build -Session build-118a | ConvertFrom-Json
    $b118b = & "$S\Claim-Task.ps1" -Repo $r118 -Role build -Session build-118b
    Case '118d spill: builders stay focus-only, a ticketed spill row waits for its group' ($b118a.id -eq 'G1.A' -and "$b118b" -eq 'NONE' -and (T $r118 'G2.P').state -eq 'ticketed') "b1=$($b118a.id) b2=$b118b"
    Set-Content (Join-Path $r118 'G2.P.txt') 'G2.P moved by focus work'
    git -C $r118 add G2.P.txt; git -C $r118 commit -q -m 'move G2.P.txt'
    Set-Content -LiteralPath (Join-Path $r118 '.streams\config.json') -Encoding utf8 -Value '{ "focus": { "groups": ["G2"] } }'
    $s118 = & "$S\Get-StreamStatus.ps1" -Repo $r118 -Json | ConvertFrom-Json
    Case '118e spill: once its group is focus, a moved write-set file flags STALE-TICKET on the board' (@(@($s118.flags) -match '^STALE-TICKET G2\.P: .*G2\.P\.txt').Count -eq 1) (@($s118.flags) -join ' | ')
    $o118 = @(& "$S\Claim-Task.ps1" -Repo $r118 -Role build -Session build-118c 3>&1)
    $w118 = @($o118 | Where-Object { $_ -is [Management.Automation.WarningRecord] } | ForEach-Object { $_.Message })
    Case '118f spill: the build claim of a drifted spill ticket warns STALE-TICKET' ((T $r118 'G2.P').claim.session -eq 'build-118c' -and ($w118 -join ' ') -match 'STALE-TICKET G2\.P') "warn=$($w118 -join ' | ')"

    # ---- 119. SPILL TICKET INBOX (2026-10-12): an author item about a spill ticket must launch an author unit. The
    # runner gate kept only items about focus rows, so three ticket fixes on G7/G8 spill tickets sat open for hours
    # (IN-20261012144844-f7be, 137 min). A stamped row outside the focus counts for authors; an unstamped one does not.
    $r119 = New-Repo 'r119' @{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }; $repos += $r119
    $d119 = J $r119
    $d119.groups += [ordered]@{ id = 'G2'; name = 'S'; state = 'released'; origin = 'import' }
    foreach ($n119 in 'G2.P', 'G2.Q') {
        Set-Content (Join-Path $r119 ".streams\tickets\$n119.md") "ticket $n119"
        Set-Content (Join-Path $r119 ".streams\graders\$n119.ps1") (ContentGrader $n119 'ok')
        $t119 = [ordered]@{ id = $n119; group = 'G2'; title = $n119; why = @('AC-1'); kind = 'code'; writeSet = @("$n119.txt"); dependsOn = @(); estMinutes = 5
            artifacts = [ordered]@{ ticket = ".streams\tickets\$n119.md"; grader = ".streams\graders\$n119.ps1"; patch = $null; verdict = $null }; state = 'ticketed'; claim = $null; history = @() }
        if ($n119 -eq 'G2.P') { $t119['spill'] = [ordered]@{ base = 'abc'; at = '2026-10-12T14:00:00Z'; by = 'author-119' } }
        $d119.tasks += $t119
    }
    $d119 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $r119 '.streams\tasks.json') -Encoding utf8
    [void](& "$S\Send-InboxItem.ps1" -Repo $r119 -To stream-author -From owner -Kind request -Ask 'reword Q' -Task G2.Q -Force)
    $g119a = @(& "$S\Start-StreamRunner.ps1" -Repo $r119 -Role author -DryRun)
    Case '119a spill inbox: an author item about an unstamped later-group row launches nothing' (($g119a -join "`n") -match '(?m)^IDLE nothing to take for author') ($g119a -join '|')
    [void](& "$S\Send-InboxItem.ps1" -Repo $r119 -To stream-author -From owner -Kind request -Ask 'reword P' -Task G2.P -Force)
    $g119b = @(& "$S\Start-StreamRunner.ps1" -Repo $r119 -Role author -DryRun)
    Case '119b spill inbox: an author item about a spill-stamped ticket is actionable' (($g119b -join "`n") -match '(?m)^GATE inbox 1 actionable') ($g119b -join '|')
    [void](& "$S\Send-InboxItem.ps1" -Repo $r119 -To stream-build -From owner -Kind request -Ask 'rebuild P' -Task G2.P -Force)
    $g119c = @(& "$S\Start-StreamRunner.ps1" -Repo $r119 -Role build -DryRun)
    Case '119c spill inbox: builders still ignore an item about a spill ticket outside the focus' (-not (($g119c -join "`n") -match '(?m)^GATE inbox')) ($g119c -join '|')

    # ---- 120. FOCUS PRIORITY (owner ruling 2026-10-14): focus.groups is a priority order. The owner wrote
    # ["G13","G14","G6"] to put G13 first, but the claim ranked every row by board order, so G6 still went first. With
    # focus ["G2","G1"] a builder and an author take the G2 row ahead of the G1 row; the focus set itself is unchanged.
    $r120 = New-Repo 'r120' @{ 'G1.A' = (ContentGrader 'G1.A' 'ok') }; $repos += $r120
    foreach ($n120 in 'G1.P', 'G2.B', 'G2.P') { Set-Content (Join-Path $r120 "$n120.txt") "$n120 base" }
    git -C $r120 add G1.P.txt G2.B.txt G2.P.txt; git -C $r120 commit -q -m 'priority files'
    $d120 = J $r120
    $d120.groups += [ordered]@{ id = 'G2'; name = 'S'; state = 'released'; origin = 'import' }
    foreach ($n120 in 'G1.P', 'G2.B', 'G2.P') {
        Set-Content (Join-Path $r120 ".streams\tickets\$n120.md") "ticket $n120"
        Set-Content (Join-Path $r120 ".streams\graders\$n120.ps1") (ContentGrader $n120 'ok')
        $d120.tasks += [ordered]@{ id = $n120; group = $n120.Substring(0, 2); title = $n120; why = @('AC-1'); kind = 'code'; writeSet = @("$n120.txt"); dependsOn = @(); estMinutes = 5
            artifacts = [ordered]@{ ticket = ".streams\tickets\$n120.md"; grader = ".streams\graders\$n120.ps1"; patch = $null; verdict = $null }; state = $(if ($n120 -eq 'G2.B') { 'ticketed' } else { 'planned' }); claim = $null; history = @() }
    }
    $d120 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $r120 '.streams\tasks.json') -Encoding utf8
    Set-Content -LiteralPath (Join-Path $r120 '.streams\config.json') -Encoding utf8 -Value '{ "focus": { "groups": ["G2", "G1"] } }'
    $b120 = & "$S\Claim-Task.ps1" -Repo $r120 -Role build -Session build-120 | ConvertFrom-Json
    Case '120a focus priority: a builder takes the first-listed focus group row ahead of an earlier board group' ($b120.id -eq 'G2.B') "got $($b120.id)"
    $a120 = & "$S\Claim-Task.ps1" -Repo $r120 -Role author -Session author-120 | ConvertFrom-Json
    Case '120b focus priority: an author takes the first-listed focus group row ahead of an earlier board group' ($a120.id -eq 'G2.P' -and -not (T $r120 'G2.P').Contains('spill')) "got $($a120.id)"
    $c120 = & "$S\Claim-Task.ps1" -Repo $r120 -Role build -Session build-120b | ConvertFrom-Json
    Case '120c focus priority: the later-listed focus group stays in the focus set' ($c120.id -eq 'G1.A') "got $($c120.id)"

    # ---- 121. A grader's child that outlives it keeps the grader's redirect files open (kit item IN-20261015040606-fb72).
    # On 2026-10-14 MSBuild nodes and a web host started by the G6.R1F2 check held G6.R1F2.grader.wt.txt.part and .in, and
    # three pre-stages of the row threw "being used by another process" on those fixed names. Here the grader starts a
    # child that inherits its handles and sleeps 12 s; two beating runs of the same task and label back to back must both
    # end cleanly with the verdict in the log.
    $pid121 = Join-Path $Scratch 'stray121.pid'
    $g121 = "param([string]`$Root)`n`$s = Start-Process pwsh -PassThru -NoNewWindow -ArgumentList '-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep 12'`nSet-Content -LiteralPath '$pid121' -Value `$s.Id`n'PASS C1'`n[Console]::Error.WriteLine('ERRLINE-121')`nexit 0"
    $r121 = New-Repo 'r121' @{ 'G1.S' = $g121 }; $repos += $r121
    $env:STREAM_BEAT_SECONDS = '1'
    $res121 = foreach ($n121 in 1, 2) {
        $e121 = ''; $o121 = @()
        try { $o121 = @(& "$S\Invoke-Grader.ps1" -Repo $r121 -Task G1.S -Root $r121 -Label wt -BeatSession build-121 -BeatTask G1.S 2>&1) } catch { $e121 = ("$_" -split "`n")[0].Trim() }
        [pscustomobject]@{ code = $LASTEXITCODE; err = $e121; out = ($o121 -join ' ') }
    }
    Remove-Item Env:\STREAM_BEAT_SECONDS -ErrorAction SilentlyContinue
    $log121 = Join-Path $r121 '.streams\logs\G1.S.grader.wt.txt'
    $text121 = if (Test-Path $log121) { Get-Content -Raw $log121 } else { '' }
    Case '121 a stray child holding the grader''s redirect files never fails the next run of that task' (-not $res121[0].err -and -not $res121[1].err -and $res121[1].code -eq 0 -and $res121[1].out -notmatch 'being used by another process' -and $text121 -match 'PASS C1' -and $text121 -match 'ERRLINE-121') "1: code=$($res121[0].code) err='$($res121[0].err)' 2: code=$($res121[1].code) err='$($res121[1].err)' out='$($res121[1].out)' log='$($text121 -replace '\s+', ' ')'"
    foreach ($s121 in @(Get-Content -LiteralPath $pid121 -ErrorAction SilentlyContinue)) { Stop-Process -Id ([int]$s121) -Force -ErrorAction SilentlyContinue }

    # ---- 122. OWNER WAKE FILES (kit item IN-20261020102535-b7f2): Wake-StreamRunner.ps1 writes WAKE / WAKE-<role> /
    # WAKE-<runner id>; Get-WakeRequest reports a write newer than what the runner has seen, never deletes the file (one
    # write wakes every runner of the role), ignores another role's file, and reads 'force' and the reason.
    $r122 = New-Repo 'r122' @{ 'G1.W' = (ContentGrader 'G1.W' 'ok') }; $repos += $r122
    # The suite does not load the lib, so each lookup runs in a child pwsh that dot-sources it.
    function Get-WakeRequest($Px, [string] $Role, [string] $Id, [long] $Seen) { $j = & pwsh -NoProfile -Command ". '$S\lib\Streams.ps1'; `$w = Get-WakeRequest (Get-StreamPaths '$r122') '$Role' '$Id' $Seen; if (`$w) { `$w | ConvertTo-Json -Compress } else { 'NULL' }"; if ("$j".Trim() -eq 'NULL') { $null } else { "$j" | ConvertFrom-Json } }
    $P122 = $null
    $seen122 = [long]("$(& pwsh -NoProfile -Command ". '$S\lib\Streams.ps1'; Get-WakeSeen (Get-StreamPaths '$r122') 'build' 'build-r1'")".Trim())
    Case '122a wake: no wake file, nothing to wake' ($null -eq (Get-WakeRequest $P122 'build' 'build-r1' $seen122)) ''
    $o122 = @(& "$S\Wake-StreamRunner.ps1" -Repo $r122 -Role build -Reason 'test wake' -Session kit-122)
    $w122 = Get-WakeRequest $P122 'build' 'build-r1' $seen122
    $w122b = Get-WakeRequest $P122 'build' 'build-r2' $seen122
    Case '122b wake: WAKE-build wakes every build runner and stays on disk' ($w122 -and $w122b -and $w122.file -eq 'WAKE-build' -and -not $w122.force -and $w122.reason -eq 'test wake' -and (Test-Path (Join-Path $r122 '.streams\runners\WAKE-build')) -and ($o122 -join ' ') -match '^WAKE WAKE-build') "out=$($o122 -join '|') w=$($w122 | ConvertTo-Json -Compress)"
    Case '122c wake: a seen wake does not wake again, another role ignores it' ($null -eq (Get-WakeRequest $P122 'build' 'build-r1' $w122.ticks) -and $null -eq (Get-WakeRequest $P122 'author' 'author-r1' 0)) ''
    Start-Sleep -Milliseconds 50
    [void](& "$S\Wake-StreamRunner.ps1" -Repo $r122 -Runner 'build-r1' -Force -Reason 'force one' -Session kit-122)
    $w122d = Get-WakeRequest $P122 'build' 'build-r1' $w122.ticks
    Case '122d wake: a forced runner-id wake reaches that runner only' ($w122d -and $w122d.force -and $w122d.file -eq 'WAKE-build-r1' -and $null -eq (Get-WakeRequest $P122 'build' 'build-r2' $w122.ticks) -and (Get-Content -Raw (Join-Path $r122 '.streams\decisions.md')) -match 'WAKE WAKE-build-r1 force') "w=$($w122d | ConvertTo-Json -Compress)"
    # 122e-f (kit item IN-20261020104236-1401): -Tab names runners by their terminal tab ('tab' in runner-*.json),
    # case-insensitive, several per call, the live runner only; an unknown tab writes nothing and exits 2.
    $rd122 = Join-Path $r122 '.streams\runners'
    Set-Content -LiteralPath (Join-Path $rd122 'runner-build-old122.json') -Value '{"role":"build","tab":"Builder 2","status":"stopped (STOP)"}'
    Set-Content -LiteralPath (Join-Path $rd122 'runner-build-live122.json') -Value '{"role":"build","tab":"Builder 2","status":"idle since x"}'
    Set-Content -LiteralPath (Join-Path $rd122 'runner-author-a122.json') -Value '{"role":"author","tab":"Author 1","status":"running y"}'
    $o122e = @(& "$S\Wake-StreamRunner.ps1" -Repo $r122 -Tab 'builder 2', 'Author 1' -Reason 'tab wake' -Session kit-122)
    Case '122e wake: -Tab wakes each named live runner by its runner id, never a stopped one' ((Test-Path (Join-Path $rd122 'WAKE-runner-build-live122')) -and (Test-Path (Join-Path $rd122 'WAKE-runner-author-a122')) -and -not (Test-Path (Join-Path $rd122 'WAKE-runner-build-old122')) -and ($o122e -join '|') -match 'WAKE WAKE-runner-build-live122' -and ($o122e -join '|') -match "runner runner-author-a122 role author tab 'Author 1'") "out=$($o122e -join '|')"
    $n122 = @(Get-ChildItem -LiteralPath $rd122 -Filter 'WAKE*').Count
    $o122f = @(& "$S\Wake-StreamRunner.ps1" -Repo $r122 -Tab 'Builder 9' -Session kit-122); $x122f = $LASTEXITCODE
    Case '122f wake: an unknown tab exits 2, lists the live tabs and writes nothing' ($x122f -eq 2 -and ($o122f -join '|') -match 'UNKNOWN-TAB Builder 9' -and ($o122f -join '|') -match 'live tabs: Author 1, Builder 2' -and @(Get-ChildItem -LiteralPath $rd122 -Filter 'WAKE*').Count -eq $n122) "x=$x122f out=$($o122f -join '|')"
    # ---- 123. A SUITE RUN KEEPS ITS LOCK (kit item IN-20261020115130-5b6f): run-G13-3 lost the integrator lock at its
    # last leg when a restarted integrator took over a lock whose beat looked stale; the leg exited 5 and was attributed
    # as a failure. Enter-Integrator must refuse while the holder owns a live 'running' run, and Export-SuiteResults must
    # write a leg that never ran for LOCK-LOST as 'not-run', never 'failed'.
    $r123 = New-Repo 'r123' @{ 'G1.L' = (ContentGrader 'G1.L' 'ok') }; $repos += $r123
    $old123 = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('o')
    Set-Content -LiteralPath (Join-Path $r123 '.streams\integrator.lock') -Value (@{ session = 'integ-old'; at = $old123; beat = $old123 } | ConvertTo-Json)
    $rr123 = Join-Path $r123 '.streams\suites\runs'; New-Item -ItemType Directory -Path $rr123 -Force | Out-Null
    $me123 = Get-Process -Id $PID
    @{ id = 'run-G1-7'; tier = '2'; group = 'G1'; session = 'integ-old'; startedAt = $old123; status = 'running'; pid = $PID; pidStart = $me123.StartTime.ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content (Join-Path $rr123 'run-G1-7.json')
    $o123a = @(& "$S\Enter-Integrator.ps1" -Repo $r123 -Session integ-new); $x123a = $LASTEXITCODE
    Case '123a a stale-beat lock whose holder owns a live suite run is not taken over' ($x123a -eq 5 -and ($o123a -join ' ') -match 'HELD by integ-old \(suite run run-G1-7 pid' -and (Get-Content -Raw (Join-Path $r123 '.streams\integrator.lock')) -match 'integ-old') "x=$x123a out=$($o123a -join ' | ')"
    $rec123 = Get-Content -Raw (Join-Path $rr123 'run-G1-7.json') | ConvertFrom-Json -AsHashtable; $rec123.status = 'done'; $rec123 | ConvertTo-Json | Set-Content (Join-Path $rr123 'run-G1-7.json')
    $o123b = @(& "$S\Enter-Integrator.ps1" -Repo $r123 -Session integ-new); $x123b = $LASTEXITCODE
    Case '123b with that run ended the stale lock is taken over as before' ($x123b -eq 0 -and ($o123b -join ' ') -match 'INTEGRATOR integ-new') "x=$x123b out=$($o123b -join ' | ')"
    $rx123 = Join-Path $rr123 'run-G1-8'; New-Item -ItemType Directory -Path (Join-Path $rx123 'Full') -Force | Out-Null
    Set-Content (Join-Path $rx123 'Full\f.trx') "<TestRun xmlns=`"http://microsoft.com/schemas/VisualStudio/TeamTest/2010`"><TestDefinitions><UnitTest id=`"1`"><TestMethod className=`"NS.Q`" name=`"M`" /></UnitTest></TestDefinitions><Results><UnitTestResult testId=`"1`" testName=`"M`" outcome=`"Passed`" duration=`"00:00:00.1`" /></Results></TestRun>"
    @{ id = 'run-G1-8'; tier = 'fixture'; group = 'G1'; startedAt = $old123; status = 'lock-lost'; snapshot = $r123; runDir = $rx123; head = 'h'
       legs = @(@{ step = 'leg'; name = 'Full'; kind = 'dotnet'; project = 'tests'; exit = 0 }, @{ step = 'leg'; name = 'Gone'; kind = 'dotnet'; project = 'tests'; exit = 5; lockLost = $true }, @{ step = 'leg'; name = 'Perf'; kind = 'dotnet'; project = 'tests'; exit = 5 }) } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $rr123 'run-G1-8.json')
    $o123c = @(& "$S\Export-SuiteResults.ps1" -Repo $r123 -Run run-G1-8)
    $res123 = Get-Content -Raw (Join-Path $rr123 'run-G1-8.results.json') | ConvertFrom-Json -AsHashtable
    $nr123 = @($res123.tests | Where-Object { $_.outcome -eq 'not-run' } | ForEach-Object { $_.test }) -join ','
    Case '123c a lock-lost leg (marked, or the last leg of an older lock-lost record) exports not-run, never failed' (($o123c -join ' ') -match 'RESULTS run-G1-8 passed 1 failed 0 skipped 0 not-run 2' -and $nr123 -eq 'leg:Gone,leg:Perf') "out=$($o123c -join ' | ') notrun=$nr123"

    # ---- 124. RETEST SWEEPS (kit item IN-20261020141232-7f92 part A): a fix row that edits only docs or a test helper
    # turned static sweeps red, and the Tier 3 retest, which re-runs only the failed tests, never saw it. A fix retest
    # runs the run definition's retestSweeps (a whole leg, or a filter gated by whenPaths) on its snapshot, records the
    # sweep's new failures (failed there, not in the base run) as sweepFailures / SWEEP-NEW, and its outcome is unchanged.
    $sw124 = Join-Path $Scratch 'sweeprepo'; New-Item -ItemType Directory -Path (Join-Path $sw124 'tests') -Force | Out-Null; $repos += $sw124
    git -C $sw124 init -q -b main; git -C $sw124 config user.email t@t; git -C $sw124 config user.name t; Grant-GitPolicy $sw124
    Set-Content (Join-Path $sw124 'tests\FooTests.cs') 'namespace NS { public class FooTests { } }'
    git -C $sw124 add -A; git -C $sw124 commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $sw124 | Out-Null
    $fk124 = Join-Path $Scratch 'fake-test124.ps1'
    Set-Content -Path $fk124 -Encoding utf8 -Value @'
param([string] $Out, [string] $Mode, [string] $Filter = '', [string] $Control)
$c = Get-Content -Raw $Control | ConvertFrom-Json -AsHashtable
$map = $c[$Mode]
$terms = @($Filter -split '\|' | Where-Object { $_ } | ForEach-Object { ($_ -replace '^FullyQualifiedName~', '') -replace '\\(.)', '$1' })
New-Item -ItemType Directory -Path $Out -Force | Out-Null
$defs = ''; $res = ''; $i = 0
foreach ($name in @($map.Keys | Sort-Object)) {
    if ($terms.Count -and -not @($terms | Where-Object { $name.Contains($_) }).Count) { continue }
    $i++; $cls = $name.Substring(0, $name.LastIndexOf('.')); $m = $name.Substring($name.LastIndexOf('.') + 1)
    $defs += "<UnitTest id=`"$i`"><TestMethod className=`"$cls`" name=`"$m`" /></UnitTest>"
    $res += "<UnitTestResult testId=`"$i`" testName=`"$m`" outcome=`"$($map[$name])`" duration=`"00:00:00.1`" />"
}
Set-Content -Path (Join-Path $Out "r$([guid]::NewGuid().ToString('N').Substring(0,6)).trx") -Value "<TestRun><TestDefinitions>$defs</TestDefinitions><Results>$res</Results></TestRun>"
if ($res -match 'Failed') { exit 1 } else { exit 0 }
'@
    $cu124 = Join-Path $Scratch 'fake-unit124.json'; $cc124 = Join-Path $Scratch 'fake-crit124.json'
    @{ tier2 = @{ 'NS.FooTests.Real' = 'Failed'; 'NS.BarTests.Ok' = 'Passed' }; retest = @{ 'NS.FooTests.Real' = 'Failed'; 'NS.BarTests.Ok' = 'Failed' } } | ConvertTo-Json | Set-Content $cu124 -Encoding utf8
    @{ tier2 = @{ 'NS.CritTests.Old' = 'Failed'; 'NS.CritTests.Keep' = 'Passed' } } | ConvertTo-Json | Set-Content $cc124 -Encoding utf8
    $lu124 = @{ name = 'Tests.Unit'; kind = 'dotnet'; project = 'tests'
        command = "& '$fk124' -Out '{runDir}\Tests.Unit' -Mode tier2 -Control '$cu124'"
        retestCommand = "& '$fk124' -Out '{runDir}\Tests.Unit' -Mode retest -Filter '{filter}' -Control '$cu124'" }
    $lc124 = @{ name = 'Tests.Criteria'; kind = 'dotnet'; project = 'tests'; command = "& '$fk124' -Out '{runDir}\Tests.Criteria' -Mode tier2 -Control '$cc124'" }
    $sws124 = @(@{ leg = 'Tests.Criteria' }, @{ leg = 'Tests.Unit'; filter = 'FullyQualifiedName~Bar'; whenPaths = @('docs/**') }, @{ leg = 'Tests.Unit'; filter = 'FullyQualifiedName~Bar'; whenPaths = @('tests/**') })
    New-Item -ItemType Directory -Path (Join-Path $sw124 '.streams\suites') -Force | Out-Null
    @{ group = 'A2'; copyIgnored = @(); setup = @(); legs = @($lu124, $lc124); graders = $false; retestSweeps = $sws124 } | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $sw124 '.streams\suites\A2.run.json') -Encoding utf8
    @{ groups = @(@{ id = 'A2'; name = 'two'; state = 'integrating'; origin = 'plan'; scope = @{ include = @('F-1') } })
       tasks = @((& $Tt 'A2.A' 'A2' 'integrated' 'tests/FooTests.cs'), (& $Tt 'A2.I' 'A2' 'ticketed' @() 'integration')) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $sw124 '.streams\tasks.json') -Encoding utf8
    $s124 = @(& "$S\Start-SuiteRun.ps1" -Repo $sw124 -Session integ-w -Group A2 -Reason complete -Wait)
    $rd124 = Join-Path $sw124 '.streams\suites\runs'
    $run124 = Get-Content -Raw (Join-Path $rd124 'run-A2-1.json') | ConvertFrom-Json -DateKind String
    # The fix lands after the run, and it turns a Criteria test that passed in the run red.
    @{ tier2 = @{ 'NS.CritTests.Old' = 'Failed'; 'NS.CritTests.Keep' = 'Failed' } } | ConvertTo-Json | Set-Content $cc124 -Encoding utf8
    $st124 = [datetime]::Parse([string]$run124.startedAt, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal).AddSeconds(1).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $d124 = J $sw124; $fx124 = @($d124.tasks | Where-Object { $_.id -like 'A2.R1F*' })
    foreach ($t in $fx124) { $t.state = 'integrated'; $t.history += @{ at = $st124; by = 'integ-w'; to = 'integrated'; note = 'fix landed' } }
    # 124c: the regressed Criteria class gets a file an integrated row owns, so its sweep regression is attributable.
    Set-Content (Join-Path $sw124 'tests\CritTests.cs') 'namespace NS { public class CritTests { } }'
    git -C $sw124 add -A; git -C $sw124 commit -q -m crit
    $d124.tasks += (& $Tt 'A2.B' 'A2' 'integrated' 'tests/CritTests.cs')
    $d124 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $sw124 '.streams\tasks.json') -Encoding utf8
    $ba124 = Join-Path $rd124 'run-A2-1.attribution.json'; $bh124 = if (Test-Path $ba124) { (Get-FileHash $ba124).Hash } else { '' }
    $r124 =@(& "$S\Invoke-Retest.ps1" -Repo $sw124 -Session integ-w -Group A2 -Mode fix); $r124t = $r124 -join ' | '
    $rt124 = @(Get-ChildItem $rd124 -Filter 'retest-A2-*.json' | Where-Object { $_.Name -match '^retest-A2-\d+\.json$' } | Sort-Object Name | ForEach-Object { Get-Content -Raw $_.FullName | ConvertFrom-Json })
    $fix124 = @($rt124 | Where-Object { $_.tier -eq '3' }) | Select-Object -Last 1
    $sf124 = if ($fix124 -and $fix124.PSObject.Properties['sweepFailures']) { (@($fix124.sweepFailures) | Sort-Object) -join ',' } else { '<none>' }
    $sp124 = if ($fix124) { Join-Path $rd124 "$($fix124.id).sweep.results.json" } else { '' }
    $mainT124 = if ($fix124 -and (Test-Path (Join-Path $rd124 "$($fix124.id).results.json"))) { @((Get-Content -Raw (Join-Path $rd124 "$($fix124.id).results.json") | ConvertFrom-Json).tests | ForEach-Object { $_.test }) -join ',' } else { '' }
    Case '124a a fix retest runs its whole-leg and gated sweeps and records only their new failures' ($fx124.Count -eq 1 -and $sf124 -eq 'NS.BarTests.Ok,NS.CritTests.Keep' -and $sp124 -and (Test-Path $sp124) -and $r124t -match 'SWEEP-NEW NS\.CritTests\.Keep' -and $r124t -match 'SWEEP-SKIP Tests\.Unit \(no fix row landed') "fix=$($fx124.Count) sweepFailures=$sf124 out=$r124t"
    Case '124b sweeps leave the retest''s own tests and outcome alone' ($fix124 -and $fix124.outcome -eq 'fail' -and $mainT124 -eq 'NS.FooTests.Real' -and $r124t -match 'RETEST retest-A2-\d+ fail passed 0 failed 1') "outcome=$(if ($fix124) { $fix124.outcome }) tests=$mainT124 out=$r124t"
    $all124 = @((J $sw124).tasks | Where-Object { $_.id -match '^A2\.R1F\d+$' }); $nw124 = @($all124 | Where-Object { [string]$_.title -match 'Tier 3 sweep' })
    $ra124 = if ($fix124) { Join-Path $rd124 "$($fix124.id).attribution.json" } else { '' }
    $rf124 = if ($ra124 -and (Test-Path $ra124)) { @((Get-Content -Raw $ra124 | ConvertFrom-Json).failures) } else { @() }
    $rs124 = (@($rf124 | ForEach-Object { "$($_.test)=$($_.disposition)" }) | Sort-Object) -join ','
    # The base run's attribution keeps only its own failures (a REFIX may rewrite its fixTask fields, so no hash check).
    $bs124 = [bool]($bh124 -and -not @(@((Get-Content -Raw $ba124 | ConvertFrom-Json).failures) | Where-Object { $_.test -match 'CritTests\.Keep|BarTests\.Ok' }).Count)
    Case '124c a sweep regression files one fix row in the retest''s own attribution, the base run''s untouched' ($all124.Count -eq 2 -and $nw124.Count -eq 1 -and (@($nw124[0].writeSet) -join ',') -eq 'tests/CritTests.cs' -and $rs124 -eq 'NS.BarTests.Ok=unowned,NS.CritTests.Keep=fix' -and $bs124 -and $r124t -match 'ATTRIBUTED retest-A2-\d+ fix 1') "fix=$($all124.Count) new=$(@($nw124 | ForEach-Object { "$($_.id):$(@($_.writeSet) -join ',')" }) -join ';') attr=$rs124 baseSame=$bs124 out=$r124t"
} catch {
    "FAIL harness: $_ at $($_.InvocationInfo.PositionMessage)"; $fails++
} finally {
    foreach ($repo in $repos) {
        if (Test-Path $repo) { foreach ($w in @(git -C $repo worktree list --porcelain | Where-Object { $_ -like 'worktree *' } | Select-Object -Skip 1)) { git -C $repo worktree remove --force ($w.Substring(9)) 2>&1 | Out-Null } }
    }
    Remove-Item Env:\STREAM_TEMP_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:\STREAM_SCRATCH_TOP_ROOT, Env:\STREAM_TEMP_SWEEP_MAX -ErrorAction SilentlyContinue
Remove-Item Env:\STREAM_WORKTREE_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:\STREAM_SCRATCH_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:\STREAM_REAP_QUIET_MINUTES -ErrorAction SilentlyContinue
    if ($null -ne $prevMachineConfig) { $env:AI_MACHINE_CONFIG = $prevMachineConfig } else { Remove-Item Env:\AI_MACHINE_CONFIG -ErrorAction SilentlyContinue }
    Remove-Item Env:\STREAM_FREE_MB_TEST -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue
}
"RESULT fails=$fails"
exit [int]($fails -gt 0)
