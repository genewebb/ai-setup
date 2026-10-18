# End-to-end self-test of the stream kit scripts against a throwaway git repo (created under -Scratch, removed at the
# end together with its worktrees). Exercises the real scripts, real git and real processes; nothing is mocked.
# Prints PASS/FAIL per case and exits non-zero when any case fails.
param([string] $Scratch = (Join-Path ([IO.Path]::GetTempPath()) "streamkit-test-$PID"))
$ErrorActionPreference = 'Stop'
$S = $PSScriptRoot
# The watchdog sweeps the HOST temp folder, so every watchdog run in a self-test is pointed at scratch instead:
# a self-test must never delete a file outside its own scratch (kit item IN-20260929144007-b69a).
$env:STREAM_TEMP_ROOT = Join-Path $Scratch 'hosttemp'
$env:STREAM_SCRATCH_TOP_ROOT = Join-Path $Scratch 'scratchtop-harness'   # the {ScratchRoot} top-level sweep, kept in scratch too
$env:STREAM_WORKTREE_ROOT = Join-Path $Scratch 'wtroot'   # the profile WorktreesRoot stand-in: no host folder is touched
$env:STREAM_SCRATCH_ROOT = Join-Path $Scratch 'streamscratch'   # the {ScratchRoot}\streams stand-in
# This suite lays a worktree down and reaps it in the same second, so the watchdog's 10-minute quiet period would
# hold every case. The quiet period itself is covered by Test-StreamKitRecovery.ps1 case 43.
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
function Grader([string] $path, [string] $file, [string] $needle) {
    Set-Content -Path $path -Encoding utf8 -Value @"
param([string]`$Root)
`$f = Join-Path `$Root '$file'
if ((Test-Path `$f) -and ((Get-Content -Raw `$f) -match '$needle')) { 'PASS C1'; exit 0 } else { 'FAIL C1: $file lacks $needle'; exit 1 }
"@
}

$repo = Join-Path $Scratch 'repo'; $wtRoot = Join-Path $Scratch 'wt'
New-Item -ItemType Directory -Path $repo -Force | Out-Null
try {
    git -C $repo init -q -b main; git -C $repo config user.email t@t; git -C $repo config user.name t; Grant-GitPolicy $repo
    Set-Content (Join-Path $repo 'a.txt') 'a0'; Set-Content (Join-Path $repo 'b.txt') 'b0'; Set-Content (Join-Path $repo 'c.txt') 'c0'
    git -C $repo add -A; git -C $repo commit -q -m base
    # owner's uncommitted work in the main tree must travel into every worktree
    Set-Content (Join-Path $repo 'a.txt') 'a0 dirty'
    Set-Content (Join-Path $repo 'new-untracked.txt') 'u'

    $r = & "$S\Init-Streams.ps1" -Repo $repo
    Case 'init creates tasks.json' (Test-Path (Join-Path $repo '.streams\tasks.json'))
    Case 'init excludes .streams' ((Get-Content (Join-Path $repo '.git\info\exclude')) -contains '.streams/')
    & "$S\Init-Streams.ps1" -Repo $repo | Out-Null
    Case 'init is idempotent' (@((Get-Content (Join-Path $repo '.git\info\exclude')) | Where-Object { $_ -eq '.streams/' }).Count -eq 1)

    # plan: T1 (a.txt) -> T2 (b.txt) depends on T1; T3 (c.txt) independent; integration task
    $plan = @{
        groups = @(@{ id = 'G1'; name = 'Test'; state = 'released'; scope = @{ include = @('FEAT-X') }; origin = 'plan' })
        tasks  = @(
            @{ id = 'G1.T1'; group = 'G1'; title = 'a'; why = @('AC-1'); kind = 'code'; writeSet = @('a.txt'); dependsOn = @(); estMinutes = 30 }
            @{ id = 'G1.T2'; group = 'G1'; title = 'b'; why = @('AC-2'); kind = 'code'; writeSet = @('b.txt'); dependsOn = @('G1.T1'); estMinutes = 30 }
            @{ id = 'G1.T3'; group = 'G1'; title = 'c'; why = @('AC-3'); kind = 'code'; writeSet = @('c.txt'); dependsOn = @(); estMinutes = 20 }
            @{ id = 'G1.T9'; group = 'G1'; title = 'suites'; why = @('AC-1'); kind = 'integration'; writeSet = @(); dependsOn = @('G1.T2', 'G1.T3'); estMinutes = 25 }
        ) }
    $pf = Join-Path $Scratch 'plan.json'; $plan | ConvertTo-Json -Depth 10 | Set-Content $pf
    & "$S\Add-Tasks.ps1" -Repo $repo -Role plan -Session plan-1 -File $pf | Out-Null
    Case 'plan adds 4 planned tasks' (@((J $repo).tasks | Where-Object { $_.state -eq 'planned' }).Count -eq 4)

    $bad = @{ tasks = @(@{ id = 'G1.T4'; group = 'G1'; title = 'x'; why = @('AC-9'); kind = 'code'; writeSet = @('a.txt'); estMinutes = 5 }) }
    $bf = Join-Path $Scratch 'bad.json'; $bad | ConvertTo-Json -Depth 10 | Set-Content $bf
    $out = & "$S\Add-Tasks.ps1" -Repo $repo -Role plan -Session plan-1 -File $bf
    Case 'plan refuses overlapping write set' ($LASTEXITCODE -eq 2 -and ($out -join ' ') -match 'overlaps G1.T1')
    $nowhy = @{ tasks = @(@{ id = 'G1.T5'; group = 'G1'; title = 'x'; why = @(); kind = 'code'; writeSet = @('z.txt'); estMinutes = 5 }) }
    $nf = Join-Path $Scratch 'nowhy.json'; $nowhy | ConvertTo-Json -Depth 10 | Set-Content $nf
    & "$S\Add-Tasks.ps1" -Repo $repo -Role plan -Session plan-1 -File $nf | Out-Null
    Case 'plan refuses task without why' ($LASTEXITCODE -eq 2)

    # author: critical path first (T1 heads the 30+30+25 chain), parallel claims never collide
    $jobs = 1..3 | ForEach-Object { $n = $_; Start-Job -ScriptBlock { param($s, $r, $n) & "$s\Claim-Task.ps1" -Repo $r -Role author -Session "author-x-$n" } -ArgumentList $S, $repo, $n }
    $claims = $jobs | Wait-Job | Receive-Job; $jobs | Remove-Job
    $got = @($claims | Where-Object { $_ -ne 'NONE' } | ForEach-Object { ($_ | ConvertFrom-Json).id })
    Case 'parallel author claims are distinct' ($got.Count -eq 3 -and @($got | Sort-Object -Unique).Count -eq 3) ($got -join ',')
    $holder = { param($id) (T $repo $id).claim.session }
    foreach ($id in 'G1.T1', 'G1.T2', 'G1.T3') {
        $sess = & $holder $id
        $g = Join-Path $repo ".streams\graders\$id.ps1"
        $file = @{ 'G1.T1' = 'a.txt'; 'G1.T2' = 'b.txt'; 'G1.T3' = 'c.txt' }[$id]
        Grader $g $file "DONE-$id"
        Set-Content (Join-Path $repo ".streams\tickets\$id.md") "ticket $id"
        & "$S\Update-Task.ps1" -Repo $repo -Task $id -Role author -Session $sess -Artifacts @{ ticket = ".streams\tickets\$id.md"; grader = ".streams\graders\$id.ps1" } | Out-Null
        & "$S\Invoke-Grader.ps1" -Repo $repo -Task $id -Root $repo -Label red -ExpectRed | Out-Null
        Case "RED check $id" ($LASTEXITCODE -eq 0)
        & "$S\Update-Task.ps1" -Repo $repo -Task $id -Role author -Session $sess -To ticketed -Release -Note 'ticketed' | Out-Null
    }
    & "$S\Update-Task.ps1" -Repo $repo -Task 'G1.T1' -Role author -Session 'author-other' -Beat | Out-Null
    Case 'foreign session gets CLAIM-LOST' ($LASTEXITCODE -eq 3)

    # build: T2 waits on T1; T1 and T3 are buildable
    $b1 = & "$S\Claim-Task.ps1" -Repo $repo -Role build -Session build-1 | ConvertFrom-Json
    $b2 = & "$S\Claim-Task.ps1" -Repo $repo -Role build -Session build-2 | ConvertFrom-Json
    $b3 = & "$S\Claim-Task.ps1" -Repo $repo -Role build -Session build-3
    Case 'build claims T1 first (critical path)' ($b1.id -eq 'G1.T1') $b1.id
    Case 'build claims T3 second' ($b2.id -eq 'G1.T3') $b2.id
    Case 'T2 not claimable before T1 built' ($b3 -eq 'NONE') "$b3"

    $wt1 = & "$S\New-TaskWorktree.ps1" -Repo $repo -Task G1.T1 -Session build-1 -WorktreeRoot $wtRoot | Select-Object -Last 1
    Case 'worktree carries dirty main diff' ((Get-Content (Join-Path $wt1 'a.txt') -Raw) -match 'dirty')
    Case 'worktree carries untracked file' (Test-Path (Join-Path $wt1 'new-untracked.txt'))
    Case 'worktree has no .streams' (-not (Test-Path (Join-Path $wt1 '.streams')))
    Case 'no branch created' (@(git -C $repo branch --format '%(refname:short)').Count -eq 1)
    Set-Content (Join-Path $wt1 'a.txt') 'a0 dirty DONE-G1.T1'
    Set-Content (Join-Path $wt1 'b.txt') 'leak'
    $x = & "$S\Export-TaskPatch.ps1" -Repo $repo -Task G1.T1 -Worktree $wt1
    Case 'export refuses write-set leak' ($LASTEXITCODE -eq 2 -and ($x -join ' ') -match 'OUTSIDE b.txt')
    git -C $wt1 checkout -q -- b.txt
    # auto-accepted widening: refused onto an unordered open task's file (T3; T2 depends on T1, so b.txt would be
    # allowed), refused to a foreign session, else added and logged
    $x = & "$S\Update-Task.ps1" -Repo $repo -Task G1.T1 -Role build -Session build-1 -AddWriteSet 'c.txt'
    Case 'widen refuses overlap with unordered open task' ($LASTEXITCODE -eq 7 -and ($x -join ' ') -match 'c.txt overlaps G1.T3') ($x -join ' ')
    & "$S\Update-Task.ps1" -Repo $repo -Task G1.T1 -Role build -Session build-2 -AddWriteSet 'e.txt' | Out-Null
    Case 'widen by foreign session gets CLAIM-LOST' ($LASTEXITCODE -eq 3)
    & "$S\Update-Task.ps1" -Repo $repo -Task G1.T1 -Role build -Session build-1 -AddWriteSet 'e.txt' -Note 'needs e' | Out-Null
    Case 'widen adds path and logs decision' ($LASTEXITCODE -eq 0 -and (@((T $repo 'G1.T1').writeSet) -contains 'e.txt') -and ((Get-Content -Raw (Join-Path $repo '.streams\decisions.md')) -match 'G1.T1 write set widened')) ("exit $LASTEXITCODE ws=$(@((T $repo 'G1.T1').writeSet) -join ',')")
    $x = & "$S\Export-TaskPatch.ps1" -Repo $repo -Task G1.T1 -Worktree $wt1
    Case 'export writes patch' ($LASTEXITCODE -eq 0 -and (Test-Path (Join-Path $repo '.streams\patches\G1.T1.patch')))
    & "$S\Invoke-Grader.ps1" -Repo $repo -Task G1.T1 -Root $wt1 -Label wt | Out-Null
    Case 'grader passes in worktree' ($LASTEXITCODE -eq 0)
    Case 'main tree untouched by build' ((Get-Content (Join-Path $repo 'a.txt') -Raw) -notmatch 'DONE')
    & "$S\Update-Task.ps1" -Repo $repo -Task G1.T1 -Role build -Session build-1 -To built -Release -Artifacts @{ patch = '.streams\patches\G1.T1.patch'; verdict = 'PASS' } | Out-Null

    # T2 now claimable and its worktree includes T1's built-not-integrated patch
    $b4 = & "$S\Claim-Task.ps1" -Repo $repo -Role build -Session build-4 | ConvertFrom-Json
    Case 'T2 claimable after T1 built' ($b4.id -eq 'G1.T2')
    $wt2 = & "$S\New-TaskWorktree.ps1" -Repo $repo -Task G1.T2 -Session build-4 -WorktreeRoot $wtRoot | Select-Object -Last 1
    Case 'dependency patch in T2 base' ((Get-Content (Join-Path $wt2 'a.txt') -Raw) -match 'DONE-G1.T1')
    Set-Content (Join-Path $wt2 'b.txt') 'b0 DONE-G1.T2'
    $x = & "$S\Export-TaskPatch.ps1" -Repo $repo -Task G1.T2 -Worktree $wt2
    Case 'T2 patch holds only b.txt' (($x -join ' ') -match 'IN b.txt' -and ($x -join ' ') -notmatch 'IN a.txt')
    & "$S\Update-Task.ps1" -Repo $repo -Task G1.T2 -Role build -Session build-4 -To built -Release -Artifacts @{ patch = '.streams\patches\G1.T2.patch'; verdict = 'PASS' } | Out-Null

    # integrate: single integrator, dependency order
    & "$S\Enter-Integrator.ps1" -Repo $repo -Session integ-1 | Out-Null; $e1 = $LASTEXITCODE
    & "$S\Enter-Integrator.ps1" -Repo $repo -Session integ-2 | Out-Null; $e2 = $LASTEXITCODE
    Case 'one integrator per repo' ($e1 -eq 0 -and $e2 -eq 5)
    $i1 = & "$S\Integrate-Patch.ps1" -Repo $repo -Session integ-1
    Case 'integrates T1 first' ($i1[0] -eq 'INTEGRATED G1.T1' -and $i1[1] -like 'COMMITTED G1.T1 *') ($i1 -join ' | ')
    Case 'main tree has T1 and kept dirty work' ((Get-Content (Join-Path $repo 'a.txt') -Raw) -match 'a0 dirty DONE-G1.T1')
    $c1 = @(git -C $repo show --name-only --format='%s' HEAD) | Where-Object { $_ }
    Case 'T1 commit holds only its patch paths' ($c1[0] -like 'G1.T1:*' -and ((@($c1 | Select-Object -Skip 1)) -join ',') -eq 'a.txt') ($c1 -join ',')
    $i2 = & "$S\Integrate-Patch.ps1" -Repo $repo -Session integ-1
    Case 'integrates T2 next' ($i2[0] -eq 'INTEGRATED G1.T2' -and $i2[1] -like 'COMMITTED G1.T2 *') ($i2 -join ' | ')

    # rebase bounce: T3 built against old c.txt, then the owner edits c.txt in the main tree
    $wt3 = & "$S\New-TaskWorktree.ps1" -Repo $repo -Task G1.T3 -Session build-2 -WorktreeRoot $wtRoot | Select-Object -Last 1
    Set-Content (Join-Path $wt3 'c.txt') 'c0 DONE-G1.T3'
    & "$S\Export-TaskPatch.ps1" -Repo $repo -Task G1.T3 -Worktree $wt3 | Out-Null
    & "$S\Update-Task.ps1" -Repo $repo -Task G1.T3 -Role build -Session build-2 -To built -Release -Artifacts @{ patch = '.streams\patches\G1.T3.patch' } | Out-Null
    Set-Content (Join-Path $repo 'c.txt') 'owner rewrote c'
    $before = Get-Content -Raw (Join-Path $repo 'c.txt')
    $i3 = & "$S\Integrate-Patch.ps1" -Repo $repo -Session integ-1
    Case 'moved base bounces to rebase' ($i3 -eq 'REBASE G1.T3' -and (T $repo 'G1.T3').state -eq 'ticketed') "$i3"
    Case 'bounced patch left main tree alone' ((Get-Content -Raw (Join-Path $repo 'c.txt')) -eq $before)

    # grader red on main: patch reversed
    Set-Content (Join-Path $repo 'c.txt') 'c0'
    $b5 = & "$S\Claim-Task.ps1" -Repo $repo -Role build -Session build-5 | ConvertFrom-Json
    $wt5 = & "$S\New-TaskWorktree.ps1" -Repo $repo -Task G1.T3 -Session build-5 -WorktreeRoot $wtRoot | Select-Object -Last 1
    Set-Content (Join-Path $wt5 'c.txt') 'c0 wrong'
    & "$S\Export-TaskPatch.ps1" -Repo $repo -Task G1.T3 -Worktree $wt5 | Out-Null
    & "$S\Update-Task.ps1" -Repo $repo -Task G1.T3 -Role build -Session build-5 -To built -Release -Artifacts @{ patch = '.streams\patches\G1.T3.patch' } | Out-Null
    $i4 = & "$S\Integrate-Patch.ps1" -Repo $repo -Session integ-1
    Case 'red grader on main reverses patch' ($i4 -eq 'REVERSED G1.T3' -and (Get-Content -Raw (Join-Path $repo 'c.txt')).Trim() -eq 'c0') "$i4"
    Case 'worktree names do not collide' ($wt5 -like '*G1.T3-2')

    # watchdog: stale build claim goes back to ticketed; fresh claim untouched
    $b6 = & "$S\Claim-Task.ps1" -Repo $repo -Role build -Session build-6 | ConvertFrom-Json
    $doc = J $repo; $t = $doc.tasks | Where-Object { $_.id -eq 'G1.T3' }; $t.claim.beat = (Get-Date).ToUniversalTime().AddMinutes(-50).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $doc | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $repo '.streams\tasks.json')
    $w = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'watchdog breaks stale build claim' (($w -join ' ') -match 'BROKE G1.T3' -and (T $repo 'G1.T3').state -eq 'ticketed' -and -not (T $repo 'G1.T3').claim) ($w -join ' ')
    $w2 = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'watchdog quiet when nothing stale' (@($w2) -contains 'QUIET') "$w2"

    # Stream scratch ({ScratchRoot}\streams\<repo>): a folder nothing has written to for a day goes; a fresh one stays.
    $scr = Join-Path $env:STREAM_SCRATCH_ROOT (Split-Path -Leaf $repo)
    $oldProbe = Join-Path $scr 'G1.T9-probe'; $newProbe = Join-Path $scr 'G1.T9-skeptic'
    New-Item -ItemType Directory -Path $oldProbe, $newProbe -Force | Out-Null
    Set-Content (Join-Path $oldProbe 'x.txt') 'old'; Set-Content (Join-Path $newProbe 'x.txt') 'new'
    (Get-Item (Join-Path $oldProbe 'x.txt')).LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-30)
    # the folder's own times count too (a fresh copy holds old files), so a truly stale folder is old all through
    $od = Get-Item $oldProbe; $od.CreationTimeUtc = (Get-Date).ToUniversalTime().AddHours(-30); $od.LastWriteTimeUtc = (Get-Date).ToUniversalTime().AddHours(-30)
    $ws = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'watchdog sweeps a day-old stream scratch folder and keeps a fresh one' ((-not (Test-Path $oldProbe)) -and (Test-Path $newProbe) -and (($ws -join ' ') -match 'SWEPT 1 stale stream scratch')) ($ws -join ' | ')
    Remove-Item -LiteralPath $newProbe -Recurse -Force

    # orphan: `building` with no claim at all. A young orphan is a live hand-off and is left alone; an old one is freed.
    $doc = J $repo; $t = $doc.tasks | Where-Object { $_.id -eq 'G1.T3' }
    $t.state = 'building'; $t.claim = $null
    $t.history = @($t.history) + @(@{ at = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'integ-1'; to = 'building'; note = 'suites' })
    $doc | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $repo '.streams\tasks.json')
    $w3 = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'watchdog leaves a young claimless building task' (@($w3) -contains 'QUIET' -and (T $repo 'G1.T3').state -eq 'building') "$w3"
    # Age runs from the move INTO building, not from the newest note stamped `building`: a plan revise written while
    # the task sits there must not reset the clock or take the blame.
    $doc = J $repo; $t = $doc.tasks | Where-Object { $_.id -eq 'G1.T3' }
    $t.history[-1].at = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
    $t.history = @($t.history) + @(@{ at = (Get-Date).ToUniversalTime().AddMinutes(-1).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'coord-1'; to = 'building'; note = 'plan revise: deps +G1.T2' })
    $doc | ConvertTo-Json -Depth 50 | Set-Content (Join-Path $repo '.streams\tasks.json')
    $w4 = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'watchdog frees an orphaned building task' (($w4 -join ' ') -match 'FREED G1.T3' -and (T $repo 'G1.T3').state -eq 'ticketed') ($w4 -join ' ')
    Case 'orphan age and blame come from the move into building' (($w4 -join ' ') -match 'building since .* \(9\d min\) with no claim, set by integ-1') ($w4 -join ' ')

    # inbox sweep: an item left `taken` by a session that stopped working returns to the queue. Nothing released one
    # before, so a dead hold was permanent and only a human taking it over by hand could clear it.
    $ib = Join-Path $repo '.streams\inbox\stream-kit.md'
    function LastLine($file, $id) { @(@(Get-Content $file) | Where-Object { $_ -like "- $id | *" })[-1] }
    function LastField($file, $id, [int] $n) { (((LastLine $file $id).Substring(2)) -split ' \| ')[$n] }
    function AgeHold($file, $id, $who, [int] $min) {
        $old = (Get-Date).ToUniversalTime().AddMinutes(-$min).ToString('yyyy-MM-ddTHH:mm:ssZ')
        # The pattern is built into a variable first. Inline, the comma binds tighter than the +, so
        # `-replace 'a' + $x + 'b', $new` hands -replace ONE array operand and no replacement, and the line is gutted.
        $pat = '\| \S+ \| ' + [regex]::Escape($who) + ' \| taken'
        $new = "| $old | $who | taken"
        Set-Content $file (@(Get-Content $file) | ForEach-Object {
            if ($_ -like "- $id | *" -and $_ -match "\| $who \| taken") { $_ -replace $pat, $new } else { $_ } })
    }
    $inId = ((& "$S\Send-InboxItem.ps1" -Repo $repo -To stream-kit -From owner -Kind request -Ask 'sweep probe | with a pipe' -Task G1.T3 -Evidence 'ev1') -split ' ')[1]
    # integ-1 has just driven this board, so it is working: its hold stands however old the `taken` line is.
    & "$S\Set-InboxItem.ps1" -Repo $repo -Skill stream-kit -Id $inId -Status taken -By integ-1 | Out-Null
    AgeHold $ib $inId 'integ-1' 40
    $w5 = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'watchdog keeps an old inbox hold whose holder still works the board' (($w5 -join ' ') -notmatch "RELEASED $inId" -and (LastField $ib $inId 3) -eq 'taken') ($w5 -join ' ')
    # ghost-1 has never touched tasks.json, so there is no evidence it is alive and its hold is past the limit.
    & "$S\Set-InboxItem.ps1" -Repo $repo -Skill stream-kit -Id $inId -Status taken -By ghost-1 | Out-Null
    AgeHold $ib $inId 'ghost-1' 40
    $w6 = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'watchdog releases an inbox hold whose holder went silent' (($w6 -join ' ') -match "RELEASED $inId in stream-kit" -and (LastField $ib $inId 3) -eq 'open') ($w6 -join ' ')
    # The released line still carries the filing, so the next taker reads the same kind, task, ask and evidence - and it
    # now also says, in the two fields a reader sees, that the WATCHDOG re-opened it and who went silent. Before
    # 2026-09-30 the line was a byte copy of the filing, so it read as the filer re-filing the item moments ago and two
    # authors wrote the same amendment.
    Case 'released inbox item keeps its filer, kind, task, ask and evidence' (
        (LastField $ib $inId 2) -like 'owner (WATCHDOG RE-OPEN*' -and (LastField $ib $inId 4) -eq 'request' -and (LastField $ib $inId 5) -eq 'G1.T3' -and
        (LastField $ib $inId 6) -like '*sweep probe / with a pipe' -and (LastField $ib $inId 7) -eq 'ev1') (LastLine $ib $inId)
    Case 'a re-opened item names the watchdog and the silent holder where a reader sees it' (
        (LastField $ib $inId 2) -like '*(WATCHDOG RE-OPEN, previous holder ghost-1 silent 4* min)' -and
        (LastField $ib $inId 6) -like 'RE-OPENED BY THE WATCHDOG - WATCHDOG RE-OPEN, previous holder ghost-1 silent 4* min, limit 30 min. CHECK*') (LastLine $ib $inId)
    Case 'the re-opened item is what Get-InboxItems shows, watchdog marker and all' (
        ((& "$S\Get-InboxItems.ps1" -Repo $repo -Skill stream-kit -Open) -join ' ') -like "*$inId*WATCHDOG RE-OPEN, previous holder ghost-1*") (
        ((& "$S\Get-InboxItems.ps1" -Repo $repo -Skill stream-kit -Open) -join ' '))
    Case 'inbox release is recorded in decisions.md' ((Get-Content -Raw (Join-Path $repo '.streams\decisions.md')) -match "RELEASED $inId")
    # A prose-only item writes nothing to tasks.json for its whole life, so the board cannot show its holder is alive.
    # An inbox event by the same session is evidence too: here prose-1 holds one aged item and has just taken another.
    $inId2 = ((& "$S\Send-InboxItem.ps1" -Repo $repo -To stream-kit -From owner -Kind request -Ask 'prose only, no board write' -Task G1.T3 -Evidence 'ev2') -split ' ')[1]
    & "$S\Set-InboxItem.ps1" -Repo $repo -Skill stream-kit -Id $inId2 -Status taken -By prose-1 | Out-Null
    AgeHold $ib $inId2 'prose-1' 40
    $inId3 = ((& "$S\Send-InboxItem.ps1" -Repo $repo -To stream-kit -From owner -Kind request -Ask 'the second item this holder touched' -Task G1.T3 -Evidence 'ev3') -split ' ')[1]
    & "$S\Set-InboxItem.ps1" -Repo $repo -Skill stream-kit -Id $inId3 -Status taken -By prose-1 | Out-Null
    $w7 = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'a holder alive only through its inbox events keeps its hold' (($w7 -join ' ') -notmatch "RELEASED $inId2" -and (LastField $ib $inId2 3) -eq 'taken') ($w7 -join ' ')
    # A released item is open, so the next session may simply take it; no human takeover step is needed.
    & "$S\Set-InboxItem.ps1" -Repo $repo -Skill stream-kit -Id $inId -Status taken -By kit-2 | Out-Null
    Case 'a released inbox item can be taken again' ((LastField $ib $inId 3) -eq 'taken' -and (LastField $ib $inId 2) -eq 'kit-2') (LastLine $ib $inId)
    # These files are hand-editable and the watchdog reads all six every tick, so a truncated line is skipped rather
    # than thrown on: one bad line must not take the claim breaking and the worktree reaper down with it.
    Add-Content $ib "- IN-truncated-0000 | -"
    $w7 = & "$S\Invoke-Watchdog.ps1" -Repo $repo -Session status-1
    Case 'a truncated inbox line is skipped, not thrown on' ($null -ne $w7) "$w7"

    # stale tasks.json lock is broken, not waited on forever
    Set-Content (Join-Path $repo '.streams\tasks.json.lock') '{"session":"dead"}'
    (Get-Item (Join-Path $repo '.streams\tasks.json.lock')).LastWriteTime = (Get-Date).AddMinutes(-5)
    & "$S\Update-Task.ps1" -Repo $repo -Task G1.T3 -Role integrate -Session integ-1 -Note 'after stale lock' | Out-Null
    Case 'stale lock broken and logged' ($LASTEXITCODE -eq 0 -and (Get-Content -Raw (Join-Path $repo '.streams\decisions.md')) -match 'broke stale tasks.json lock')

    # integration fix task joins an open task on the same file
    $fix = @{ tasks = @(@{ id = 'G1.F1'; group = 'G1'; title = 'fix c'; why = @('AC-3'); kind = 'code'; writeSet = @('c.txt'); estMinutes = 10 }) }
    $ff = Join-Path $Scratch 'fix.json'; $fix | ConvertTo-Json -Depth 10 | Set-Content $ff
    $o = & "$S\Add-Tasks.ps1" -Repo $repo -Role integrate -Session integ-1 -File $ff
    Case 'fix on open task file joins it' (($o -join ' ') -match 'JOINED G1.F1 into G1.T3' -and -not ((J $repo).tasks | Where-Object { $_.id -eq 'G1.F1' }))
    $fix2 = @{ tasks = @(@{ id = 'G1.F2'; group = 'G1'; title = 'fix d'; why = @('AC-1'); kind = 'code'; writeSet = @('d.txt'); estMinutes = 10 }) }
    $ff2 = Join-Path $Scratch 'fix2.json'; $fix2 | ConvertTo-Json -Depth 10 | Set-Content $ff2
    & "$S\Add-Tasks.ps1" -Repo $repo -Role integrate -Session integ-1 -File $ff2 | Out-Null
    Case 'new fix task enters planned with origin integration' ((T $repo 'G1.F2').state -eq 'planned' -and (T $repo 'G1.F2').origin -eq 'integration')

    # illegal transition refused
    & "$S\Update-Task.ps1" -Repo $repo -Task G1.T3 -Role integrate -Session integ-1 -To integrated 2>&1 | Out-Null
    Case 'illegal transition refused' ($LASTEXITCODE -ne 0 -and (T $repo 'G1.T3').state -eq 'ticketed')

    $st = & "$S\Get-StreamStatus.ps1" -Repo $repo
    Case 'status prints 6 lines' (@($st).Count -eq 6) ($st -join ' / ')
    $sj = & "$S\Get-StreamStatus.ps1" -Repo $repo -Json | ConvertFrom-Json
    Case 'status json lists all tasks' (@($sj.tasks).Count -eq 5)

    # The status page carries the PENDING owner-question count as a top tile. It was only in the Owner queue panel four
    # sections down, so a queue of 442 was invisible at a glance (2026-09-29). RESOLVED lines must not be counted: an
    # answered question is rewritten in place with a leading RESOLVED token and Get-StreamStatus already skips it.
    # The tile's big number is the ESCALATION count ('- ' bullets), NOT the whole queue: the '<task> | <question> |
    # <default applied> | <reasoning>' lines are decisions already taken under standing owner authority, and on
    # 2026-09-29 they were 604 of 620, so one number over both was useless for triage. The fixture holds both shapes
    # plus a resolved one of each, so these clauses fail if the tile ever counts the queue again.
    $qf = Join-Path $repo '.streams\owner\questions.md'
    Set-Content $qf @(
        '- G1.T1 escalation one | the owner has to choose',
        '- G1.T2 escalation two | the owner has to choose',
        'RESOLVED - G1.T3 escalation answered | the owner chose',
        'G1.T1 | applied default one | rec | why',
        'G1.T1 | applied default two | rec | why',
        'RESOLVED G1.T1 | answered already | rec | why',
        'G1.T2 | applied default three | rec | why')
    $sq = & "$S\Get-StreamStatus.ps1" -Repo $repo -Json | ConvertFrom-Json
    Case 'status json counts the whole owner queue' (@($sq.owner.questions).Count -eq 5) ('queue count is ' + @($sq.owner.questions).Count)
    Case 'status json counts the escalations apart' (@($sq.owner.escalations).Count -eq 2) ('escalation count is ' + @($sq.owner.escalations).Count)
    $pg = Join-Path $Scratch 'status-tile.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $repo -Session status-tile -Out $pg -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    $html = Get-Content -Raw $pg
    Case 'the status page carries an owner-questions tile' ($html -match '<span>owner questions') 'no owner-questions tile'
    Case 'the tile counts only the escalation bullets' ($html -match '(?s)<a class="tile owner"[^>]*><b>2</b>') 'tile count is not 2'
    Case 'the tile does NOT count the whole queue' ($html -notmatch '(?s)<a class="tile owner"[^>]*><b>5</b>') 'tile shows the whole-queue count'
    Case 'the tile names the applied defaults as the second number' ($html -match '(?s)<a class="tile owner".*?3 applied') 'tile does not name the applied defaults'
    Case 'the tile links to the question list' ($html -match 'href="#owner-questions"' -and $html -match '<div class="panel" id="owner-questions">') 'tile link or panel anchor missing'
    Case 'the question list itself keeps both shapes and drops the resolved lines' (($html -match 'applied default three') -and ($html -match 'escalation two') -and ($html -notmatch 'answered already') -and ($html -notmatch 'escalation answered')) 'resolved line leaked into the page or a shape was dropped'
    # The real board (no -MirrorFile) also mirrors to the machine profile's StatusPageDir (spec D17); a blank row
    # leaves the page in .streams\ alone. A throwaway profile stands in for ProfileMachineConfig.md.
    $iis = Join-Path $Scratch 'iis-speedy'
    $prof = Join-Path $Scratch 'profile-statuspage.md'
    Set-Content -LiteralPath $prof -Encoding utf8NoBOM -Value @('| Key | Value | Used by | Status |', '|---|---|---|---|', "| StatusPageDir | $iis | test | |")
    $gitPolicyProfile = $env:AI_MACHINE_CONFIG
    $env:AI_MACHINE_CONFIG = $prof
    $spOut = @(& "$S\Build-StatusPage.ps1" -Repo $repo -Session status-dir)
    Case 'the board mirrors to {StatusPageDir}\status.html' ((Test-Path (Join-Path $iis 'status.html')) -and (($spOut -join ' ') -match 'mirrored to')) ($spOut -join ' | ')
    Set-Content -LiteralPath $prof -Encoding utf8NoBOM -Value @('| Key | Value | Used by | Status |', '|---|---|---|---|', '| StatusPageDir |  | test | |')
    $spOut2 = @(& "$S\Build-StatusPage.ps1" -Repo $repo -Session status-dir2)
    Case 'a blank StatusPageDir mirrors nowhere' (($spOut2 -join ' ') -notmatch 'mirrored to|MIRROR FAILED') ($spOut2 -join ' | ')
    $env:AI_MACHINE_CONFIG = $gitPolicyProfile   # back to the fixture Git policy profile

    # ---- predicted finish per group ----
    # The owner's question of this board is WHEN each priority group lands, and the answer must come from measured
    # delivery, not from an assumed number of builders. A second throwaway board is used because the histories have
    # to be exact: F1 delivers steadily, F2 has never delivered anything, F3 delivers fast but sits behind a long
    # serial chain. Those are the three cases the forecast has to get right, and each one failed a different way
    # while it was being written: a board rate split six ways dated every group the same, a group with no history
    # got a date out of a zero rate, and the downstream chain (Get-ChainMinutes) dated groups by OTHER groups' work.
    $fr = Join-Path $Scratch 'fcrepo'
    New-Item -ItemType Directory -Path $fr -Force | Out-Null
    git -C $fr init -q -b main; git -C $fr config user.email t@t; git -C $fr config user.name t; Grant-GitPolicy $fr
    Set-Content (Join-Path $fr 'x.txt') 'x'; git -C $fr add -A; git -C $fr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $fr | Out-Null
    $utc = (Get-Date).ToUniversalTime()
    function Landed([string] $id, [string] $g, [int] $est, [double] $hoursAgo) {
        @{ id = $id; group = $g; title = $id; why = @('AC-1'); kind = 'code'; writeSet = @("$id.txt"); dependsOn = @()
            estMinutes = $est; state = 'integrated'; claim = $null
            history = @(@{ at = $utc.AddHours(-$hoursAgo).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'integ-1'; to = 'integrated'; note = 'applied' }) }
    }
    function Togo([string] $id, [string] $g, [int] $est, [string[]] $deps) {
        @{ id = $id; group = $g; title = $id; why = @('AC-1'); kind = 'code'; writeSet = @("$id.txt"); dependsOn = @($deps)
            estMinutes = $est; state = 'planned'; claim = $null
            history = @(@{ at = $utc.AddHours(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'plan-1'; to = 'planned'; note = 'added' }) }
    }
    $fdoc = @{
        groups = @(
            @{ id = 'F1'; name = 'steady'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-X') } }
            @{ id = 'F2'; name = 'silent'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-Y') } }
            @{ id = 'F3'; name = 'chained'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-Z') } }
            @{ id = 'F4'; name = 'repriced'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-R') } }
            @{ id = 'F5'; name = 'repriced and chained'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-S') } }
            @{ id = 'F6'; name = 'one big row'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-T') } })
        tasks = @(
            # F1: 400 est-min landed inside 24 h over 4 tasks, so the 24 h window is used as is: 16.67 min/h
            # against 100 min of work left = 360 min, and the 100 min floor does not bind.
            (Landed 'F1.T1' 'F1' 100 2), (Landed 'F1.T2' 'F1' 100 4), (Landed 'F1.T3' 'F1' 100 6), (Landed 'F1.T4' 'F1' 100 8),
            (Togo 'F1.T5' 'F1' 100 @()),
            # F2: nothing has ever landed, so there is no rate and the honest answer is no date at all.
            (Togo 'F2.T1' 'F2' 50 @()), (Togo 'F2.T2' 'F2' 50 @()),
            # F3: 3000 est-min landed in 24 h = 125 min/h, which would take 864 min for the 1800 left, but the three
            # tasks are strictly serial, so 1800 min of chain is the earliest it can finish and the floor wins.
            (Landed 'F3.T1' 'F3' 600 3), (Landed 'F3.T2' 'F3' 600 5), (Landed 'F3.T3' 'F3' 600 7),
            (Landed 'F3.T4' 'F3' 600 9), (Landed 'F3.T5' 'F3' 600 11),
            (Togo 'F3.T6' 'F3' 600 @()), (Togo 'F3.T7' 'F3' 600 @('F3.T6')), (Togo 'F3.T8' 'F3' 600 @('F3.T7')),
            # F4: the REPRICED board. Five landed rows at 600 and three parallel to-go rows at 80, which is the 7.5x
            # split this board really had on 2026-09-30. Summing the landed estimates gives 125 min/h against 240 min
            # left = 115 min, a date inside two hours for three untouched tasks. Counting completions gives
            # 5/24 = 0.208 task/h, so three rows take 14.4 h = 864 min however the estimates are priced.
            (Landed 'F4.T1' 'F4' 600 3), (Landed 'F4.T2' 'F4' 600 5), (Landed 'F4.T3' 'F4' 600 7),
            (Landed 'F4.T4' 'F4' 600 9), (Landed 'F4.T5' 'F4' 600 11),
            (Togo 'F4.T6' 'F4' 80 @()), (Togo 'F4.T7' 'F4' 80 @()), (Togo 'F4.T8' 'F4' 80 @()),
            # F5: the chain DECIDES the date and is itself summed from two scales - half its rows at 80 and half at
            # 600, the shape a reprice that stopped halfway leaves behind. That is the one case the date can be wrong,
            # so it is dated off the chain but marked soft and flagged. 20 landed in 24 h is 0.833 task/h priced at
            # the 340 min mean of the eight rows to go = 283 min/h, so the rate would say 576 min while the chain says 2720.
            # The landed rows are all at 600 here as they are in F4, which no longer decides anything: nothing a
            # landed row is priced at reaches the floor, so F4 - whose to-go rows are one scale - keeps its date.
            (Landed 'F5.T1' 'F5' 600 1), (Landed 'F5.T2' 'F5' 600 2), (Landed 'F5.T3' 'F5' 600 3),
            (Landed 'F5.T4' 'F5' 600 4), (Landed 'F5.T5' 'F5' 600 5), (Landed 'F5.T6' 'F5' 600 6),
            (Landed 'F5.T7' 'F5' 600 7), (Landed 'F5.T8' 'F5' 600 8), (Landed 'F5.T9' 'F5' 600 9),
            (Landed 'F5.T10' 'F5' 600 10), (Landed 'F5.T11' 'F5' 600 11), (Landed 'F5.T12' 'F5' 600 12),
            (Landed 'F5.T13' 'F5' 600 13), (Landed 'F5.T14' 'F5' 600 14), (Landed 'F5.T15' 'F5' 600 15),
            (Landed 'F5.T16' 'F5' 600 16), (Landed 'F5.T17' 'F5' 600 17), (Landed 'F5.T18' 'F5' 600 18),
            (Landed 'F5.T19' 'F5' 600 19), (Landed 'F5.T20' 'F5' 600 20),
            (Togo 'F5.T21' 'F5' 80 @()), (Togo 'F5.T22' 'F5' 80 @('F5.T21')), (Togo 'F5.T23' 'F5' 80 @('F5.T22')),
            (Togo 'F5.T24' 'F5' 80 @('F5.T23')), (Togo 'F5.T25' 'F5' 600 @('F5.T24')),
            (Togo 'F5.T26' 'F5' 600 @('F5.T25')), (Togo 'F5.T27' 'F5' 600 @('F5.T26')),
            (Togo 'F5.T28' 'F5' 600 @('F5.T27')),
            # F6: a chain of three rows, one of them 7.5x the others. Too short to tell a second scale from a row
            # that is genuinely bigger - a suites run or an owner gate - so it is dated rather than refused.
            (Landed 'F6.T1' 'F6' 600 3), (Landed 'F6.T2' 'F6' 600 5), (Landed 'F6.T3' 'F6' 600 7),
            (Togo 'F6.T4' 'F6' 80 @()), (Togo 'F6.T5' 'F6' 600 @('F6.T4')), (Togo 'F6.T6' 'F6' 80 @('F6.T5')))
    }
    $fdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $fr '.streams\tasks.json') -Encoding utf8
    # All six in focus, so each is worked and dated from its own history: the cases below test that per-group rate.
    # The focus-order cases further down narrow the focus and re-read the same board.
    $fcfg = Join-Path $fr '.streams\config.json'
    function Set-FcFocus([string[]] $ids) { @{ focus = @{ groups = @($ids) } } | ConvertTo-Json -Depth 5 | Set-Content $fcfg -Encoding utf8 }
    Set-FcFocus @('F1', 'F2', 'F3', 'F4', 'F5', 'F6')
    $fj = & "$S\Get-StreamStatus.ps1" -Repo $fr -Json | ConvertFrom-Json
    $f1 = @($fj.groups | Where-Object { $_.id -eq 'F1' })[0].forecast
    $f2 = @($fj.groups | Where-Object { $_.id -eq 'F2' })[0].forecast
    $f3 = @($fj.groups | Where-Object { $_.id -eq 'F3' })[0].forecast
    Case 'a group is dated from its own measured delivery' ([math]::Abs([int]$f1.predictedMinutes - 360) -le 2) "F1 predicted $($f1.predictedMinutes), expected 360"
    Case 'the predicted date is the predicted minutes from now' ([math]::Abs((([datetime]::Parse($f1.predictedAt, $null, [Globalization.DateTimeStyles]::AdjustToUniversal)) - $utc).TotalMinutes - [int]$f1.predictedMinutes) -le 2) "F1 predictedAt $($f1.predictedAt)"
    Case 'focus groups are dated separately, not off one board rate' ([int]$f1.predictedMinutes -ne [int]$f3.predictedMinutes) 'F1 and F3 got the same date'
    # F2 is in focus but has never landed anything. Its own rate cannot date it, so the FOCUS POOL does: the 20 focus
    # rows to go at the six groups' combined 37/24 task/h = 778 min. Before the pool it was undated.
    Case 'a focus group with no landing of its own is dated from the focus pool' ($null -eq $f2.ownPredictedMinutes -and [math]::Abs([int]$f2.predictedMinutes - 778) -le 2 -and [string]$f2.basis -match '^focus pool') "F2 own $($f2.ownPredictedMinutes) predicted $($f2.predictedMinutes) basis '$($f2.basis)'"
    Case 'the dependency chain floors the date' ([int]$f3.predictedMinutes -eq 1800 -and [string]$f3.basis -match 'dependency chain') "F3 predicted $($f3.predictedMinutes) basis '$($f3.basis)'"
    Case 'work left counts only unlanded tasks' ([int]$f1.remainingMinutes -eq 100 -and [int]$f3.remainingMinutes -eq 1800) "F1 $($f1.remainingMinutes) F3 $($f3.remainingMinutes)"
    $f4 = @($fj.groups | Where-Object { $_.id -eq 'F4' })[0].forecast
    $f5 = @($fj.groups | Where-Object { $_.id -eq 'F5' })[0].forecast
    # F4's OWN date: the focus pool (778) then caps it, which is the next case.
    Case 'a reprice does not pull the date in: the rate is counted in tasks' ([math]::Abs([int]$f4.ownPredictedMinutes - 864) -le 20) "F4 own $($f4.ownPredictedMinutes), expected about 864 (summing landed estimates gives 115)"
    Case 'a focus group is never dated later than the focus pool' ([math]::Abs([int]$f4.predictedMinutes - 778) -le 2 -and [string]$f4.basis -match 'focus pool') "F4 predicted $($f4.predictedMinutes) basis '$($f4.basis)'"
    Case 'the counted rate and the mean it is priced at are both reported' ([math]::Abs([double]$f4.tasksPerHour - 0.208) -le 0.01 -and [math]::Abs([double]$f4.meanTogoMinutes - 80) -le 0.1) "F4 $($f4.tasksPerHour) task/h at $($f4.meanTogoMinutes) min"
    Case 'a landed-to-to-go gap is still reported with both medians' ([double]$f4.scaleSkew -ge 7 -and [int]$f4.landedMedianMinutes -eq 600 -and [int]$f4.togoMedianMinutes -eq 80) "F4 skew $($f4.scaleSkew) landed $($f4.landedMedianMinutes) togo $($f4.togoMedianMinutes)"
    # A landed row is priced at 0 in the chain, so a landed-to-to-go gap CANNOT make the date wrong and must not
    # suppress it. F4's own to-go rows are all 80: one scale, and it keeps its date despite a 7.5x skew.
    Case 'a landed-to-to-go gap alone does not suppress the date' (-not $f4.scaleSplit -and $null -ne $f4.predictedMinutes) "F4 split $($f4.scaleSplit) predicted $($f4.predictedMinutes)"
    # Until 2026-10-03 F5 got NO date. That refusal fired on ordinary variety on the live board (G3's chain, 8-255 min
    # rows, 4.48x) and left the owner's top group undated, so a split chain is now DATED off the chain sum and
    # marked soft, with a flag naming the split.
    Case 'a chain summed from two scales is dated off the chain, marked SOFT' ([int]$f5.predictedMinutes -eq 2720 -and $f5.softDate -eq $true -and [string]$f5.basis -match 'SOFT DATE' -and [string]$f5.basis -match 'two clusters' -and [double]$f5.chainSplitRatio -ge 7) "F5 predicted $($f5.predictedMinutes) soft $($f5.softDate) ratio $($f5.chainSplitRatio) basis '$($f5.basis)'"
    Case 'a soft date is flagged, not silent' (@($fj.flags | Where-Object { $_ -match '^group F5 has a SOFT predicted finish' }).Count -eq 1 -and @($fj.flags | Where-Object { $_ -match '^group F[1346] has a SOFT' }).Count -eq 0) "flags: $(@($fj.flags) -join ' | ')"
    Case 'the split is measured on the chain rows, not on the whole group' ([int]$f5.chainRows -eq 8) "F5 chainRows $($f5.chainRows), expected the 8 unlanded rows on the chain"
    Case 'one scale still gets its date, so the refusal is not blanket' ($null -ne $f1.predictedMinutes -and -not $f1.scaleSplit -and $null -ne $f3.predictedMinutes) "F1 $($f1.predictedMinutes) split $($f1.scaleSplit), F3 $($f3.predictedMinutes)"
    $f6 = @($fj.groups | Where-Object { $_.id -eq 'F6' })[0].forecast
    Case 'a chain too short to tell a scale from a big row is dated, not refused' ($null -ne $f6.predictedMinutes -and -not $f6.scaleSplit) "F6 predicted $($f6.predictedMinutes) split $($f6.scaleSplit) rows $($f6.chainRows)"
    # F5 (soft, 2720, its chain floor) is the latest dated group, ahead of F3 (1800): focus groups run concurrently,
    # so the board takes the max, never the sum.
    Case 'with every group in focus the board date is the latest group date, not a sum' ([int]$fj.forecast.predictedMinutes -eq [int]$f5.predictedMinutes -and $fj.forecast.drivenBy -eq 'F5' -and [int]$f5.predictedMinutes -gt [int]$f3.predictedMinutes) "board $($fj.forecast.predictedMinutes) by $($fj.forecast.drivenBy)"
    # FOCUS ORDER (kit item IN-20261009005127-d504). The focus rule freezes every open group that is not in focus, so its
    # own rate measures the freeze: on 2026-10-08 G6 read 0.74 min/h and dated the board 14 Aug 2027. Same board, focus
    # F1 alone: F1 lands 4/24 task/h and finishes in 360 min; F2..F6 queue behind it in board order, each priced at that
    # rate times its own rows to go: F2 2 rows = +720 -> 1080 (it has never landed, and is dated, not left undated or
    # priced at its own zero rate); F3 3 rows -> 2160 (its 1800 chain floor no longer binds); F4 -> 3240; F5 8 rows ->
    # 6120; F6 -> 7200. The board date is F6's sequential finish.
    Set-FcFocus @('F1')
    $qj = & "$S\Get-StreamStatus.ps1" -Repo $fr -Json | ConvertFrom-Json
    $q = @{}; foreach ($g in $qj.groups) { $q[[string]$g.id] = $g.forecast }
    Case 'a frozen group with no landing is queued after the focus at the focus rate' ($q['F2'].dating -eq 'queued' -and [math]::Abs([int]$q['F2'].predictedMinutes - 1080) -le 3 -and [string]$q['F2'].basis -match '^queued behind F1') "F2 $($q['F2'].dating) $($q['F2'].predictedMinutes) '$($q['F2'].basis)'"
    Case 'queued groups finish one after another in board order' (([int]$q['F3'].predictedMinutes - 2160) -in -3..3 -and ([int]$q['F4'].predictedMinutes - 3240) -in -3..3 -and ([int]$q['F5'].predictedMinutes - 6120) -in -3..3 -and ([int]$q['F6'].predictedMinutes - 7200) -in -3..3) "F3 $($q['F3'].predictedMinutes) F4 $($q['F4'].predictedMinutes) F5 $($q['F5'].predictedMinutes) F6 $($q['F6'].predictedMinutes)"
    Case 'a queued group is priced at the focus rate, not its own' ([math]::Abs([double]$q['F6'].tasksPerHour - 0.167) -le 0.002 -and [math]::Abs([double]$q['F6'].ownTasksPerHour - 0.125) -le 0.002) "F6 $($q['F6'].tasksPerHour) task/h own $($q['F6'].ownTasksPerHour)"
    Case 'the board date is the last queued group, and the board rate is the focus rate' ([int]$qj.forecast.predictedMinutes -eq [int]$q['F6'].predictedMinutes -and $qj.forecast.drivenBy -eq 'F6' -and [math]::Abs([double]$qj.forecast.ratePerHour - [double]$q['F1'].ratePerHour) -le 0.01) "board $($qj.forecast.predictedMinutes) by $($qj.forecast.drivenBy) rate $($qj.forecast.ratePerHour)"
    # A focus that has never landed anything gives no capacity to price the queue at, so the queue is undated and named.
    Set-FcFocus @('F2')
    $uj = & "$S\Get-StreamStatus.ps1" -Repo $fr -Json | ConvertFrom-Json
    $u2 = @($uj.groups | Where-Object { $_.id -eq 'F2' })[0].forecast; $u3 = @($uj.groups | Where-Object { $_.id -eq 'F3' })[0].forecast
    Case 'a focus that has never delivered gets no date' ($null -eq $u2.predictedMinutes -and [string]$u2.basis -match '168') "F2 basis '$($u2.basis)'"
    Case 'groups queued behind an undated focus are undated and named' ($null -eq $u3.predictedMinutes -and [string]$u3.basis -match 'F2 has no date' -and @($uj.forecast.groupsWithoutDate) -contains 'F2' -and @($uj.forecast.groupsWithoutDate) -contains 'F6') "F3 basis '$($u3.basis)' undated $(@($uj.forecast.groupsWithoutDate) -join ',')"
    # The no-session demand counts the focus set only (kit item IN-20261009040231-3d7c): 20 rows are planned on this
    # board but only F2's 2 can be taken, so "20 tasks waiting for author" was a false alarm about frozen groups.
    $wa = @($uj.flags | Where-Object { "$_" -match 'tasks waiting for author' })
    Case 'the waiting-for-author flag counts only the focus set''s planned rows' ($wa.Count -eq 1 -and "$($wa[0])" -match '^2 tasks waiting for author') ($uj.flags -join ' | ')
    # The focus stays on F2 (undated) for the page cases below, which need an undated group on the page.
    # An OUTAGE is not delivery time. On 2026-10-01 every session was silent from about 23:15Z to 15:35Z, 16 h of a 48 h
    # window, and G1 read 18 h for 173 min of work. Own board, because activity is read board-wide: four landings at
    # 22, 21.5, 2 and 1.5 h ago leave a 19.5 h gap, of which 19.5 - 2 = 17.5 h is outage (the two 30 min gaps are under
    # the 120 min limit), so the rate divides by 6.5 live hours, not 24. Three parallel rows of 100 min to go: 4 / 6.5
    # task/h at 100 min = 292.5 min, where the wall-clock rate said 1800. Parallel so the 100 min chain floor does not bind. A status tick inside the
    # gap is not a session delivering, so it must not split the outage.
    $orr = Join-Path $Scratch 'outrepo'
    New-Item -ItemType Directory -Path $orr -Force | Out-Null
    git -C $orr init -q -b main; git -C $orr config user.email t@t; git -C $orr config user.name t
    Set-Content (Join-Path $orr 'x.txt') 'x'; git -C $orr add -A; git -C $orr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $orr | Out-Null
    $oTogo = Togo 'O1.T5' 'O1' 100 @()
    $oTogo.history += @{ at = $utc.AddHours(-10).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'status-o'; to = 'planned'; note = 'watchdog note' }
    $odoc = @{ groups = @(@{ id = 'O1'; name = 'outage'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-O') } })
        tasks = @((Landed 'O1.T1' 'O1' 100 22), (Landed 'O1.T2' 'O1' 100 21.5), (Landed 'O1.T3' 'O1' 100 2), (Landed 'O1.T4' 'O1' 100 1.5), $oTogo, (Togo 'O1.T6' 'O1' 100 @()), (Togo 'O1.T7' 'O1' 100 @())) }
    $odoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $orr '.streams\tasks.json') -Encoding utf8
    $o1 = @((& "$S\Get-StreamStatus.ps1" -Repo $orr -Json | ConvertFrom-Json).groups)[0].forecast
    Case 'an outage is taken out of the window the rate divides by' ([math]::Abs([double]$o1.outageHours - 17.5) -le 0.05 -and [math]::Abs([double]$o1.liveHours - 6.5) -le 0.05) "O1 outage $($o1.outageHours) live $($o1.liveHours)"
    Case 'the date comes from live hours, not wall-clock hours' ([math]::Abs([int]$o1.predictedMinutes - 292) -le 3 -and [string]$o1.basis -match 'outage') "O1 predicted $($o1.predictedMinutes), expected about 292; basis '$($o1.basis)'"
    Case 'a steady board has no outage to take out' ([double]$f1.outageHours -eq 0 -and [double]$f1.liveHours -eq 24) "F1 outage $($f1.outageHours) live $($f1.liveHours)"
    $fst = & "$S\Get-StreamStatus.ps1" -Repo $fr
    Case 'the forecast keeps the terminal at 6 lines' (@($fst).Count -eq 6) ($fst -join ' / ')
    # One 'fin ' per group plus one for the board, counted from the fixture rather than hardcoded: the assertion used to
    # read -eq 5, which was three groups plus the board, so adding a forecast fixture group failed a case about nothing.
    Case 'the terminal groups line carries a finish per group' ((([string]$fst[0] -split 'fin ').Count - 1) -eq (@($fj.groups).Count + 1)) ([string]$fst[0])
    $fpg = Join-Path $Scratch 'status-forecast.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $fr -Session status-fc -Out $fpg -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    $fhtml = Get-Content -Raw $fpg
    Case 'the page has a predicted finish column' ($fhtml -match '<th>Predicted finish</th>') 'no Predicted finish column'
    Case 'the page shows the undated group as undated' ($fhtml -match 'no date') 'undated group not shown as undated'
    Case 'the page says how the prediction is made' ($fhtml -match 'How the predicted finish is worked out') 'method panel missing'
    Case 'the page says the categories are dated in focus order' ($fhtml -match 'In focus order' -and $fhtml -match 'last queued category') 'focus-order notes missing'
    Remove-Item $fcfg
    # Category order: a session claims from the OWNER'S group order first, and only falls to a later group when the
    # earlier one has nothing it can take. Before 2026-09-30 the only keys were integration-fix, longest chain and
    # board order, so with all six groups released at once every session spread across all six and no category ever
    # finished first. A third throwaway board is used because the order has to be exact: C1 holds two small tasks,
    # C2 holds a long serial chain (the old critical-path key would take C2 first) plus one integration fix.
    $cr = Join-Path $Scratch 'catrepo'
    New-Item -ItemType Directory -Path $cr -Force | Out-Null
    git -C $cr init -q -b main; git -C $cr config user.email t@t; git -C $cr config user.name t; Grant-GitPolicy $cr
    Set-Content (Join-Path $cr 'x.txt') 'x'; git -C $cr add -A; git -C $cr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $cr | Out-Null
    function CTask([string] $id, [string] $g, [string] $state, [int] $est, [string[]] $deps, [string] $origin) {
        $t = @{ id = $id; group = $g; title = $id; why = @('AC-1'); kind = 'code'; writeSet = @("$id.txt"); dependsOn = @($deps)
                estMinutes = $est; state = $state; claim = $null
                artifacts = @{ ticket = ".streams\tickets\$id.md"; grader = ".streams\graders\$id.ps1"; patch = $null; verdict = $null }
                history = @(@{ at = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'plan-1'; to = $state; note = 'fixture' }) }
        if ($origin) { $t.origin = $origin }
        $t
    }
    $cdoc = @{
        groups = @(
            @{ id = 'C1'; name = 'first category'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-1') } }
            @{ id = 'C2'; name = 'second category'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-2') } })
        tasks = @(
            (CTask 'C1.S1' 'C1' 'ticketed' 5 @() ''),
            (CTask 'C1.S2' 'C1' 'ticketed' 5 @() ''),
            (CTask 'C1.P'  'C1' 'planned'  5 @() ''),
            (CTask 'C2.L1' 'C2' 'ticketed' 60 @() ''),
            (CTask 'C2.L2' 'C2' 'ticketed' 60 @('C2.L1') ''),
            (CTask 'C2.FIX' 'C2' 'ticketed' 10 @() 'integration'),
            (CTask 'C2.P'  'C2' 'planned' 100 @() ''))
    }
    $cdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cr '.streams\tasks.json') -Encoding utf8
    # FOCUS (spec 2026-10-05 3.1): C1 is the focus group, so C2's fix row and its long chain wait for C2's turn.
    $cb1 = & "$S\Claim-Task.ps1" -Repo $cr -Role build -Session build-c1 | ConvertFrom-Json
    Case 'build claims the focus group first; a later-group fix waits for its group' ($cb1.id -eq 'C1.S1') $cb1.id
    $cb2 = & "$S\Claim-Task.ps1" -Repo $cr -Role build -Session build-c2 | ConvertFrom-Json
    Case 'the focus group is drained in order' ($cb2.id -eq 'C1.S2') $cb2.id
    $cb3 = & "$S\Claim-Task.ps1" -Repo $cr -Role build -Session build-c3
    Case 'a later category is NOT taken while the earlier one is open (focus)' ($cb3 -eq 'NONE') "$cb3"
    $ca1 = & "$S\Claim-Task.ps1" -Repo $cr -Role author -Session author-c1 | ConvertFrom-Json
    Case 'the author tickets in category order too' ($ca1.id -eq 'C1.P') $ca1.id

    # Focus (spec 3.1): the focus group is the first unclosed group in board order; the focus SET is every row whose
    # effective group rank (Get-EffectiveGroupRank) is the focus group's. A later-group root that an earlier-group
    # row depends on is in the set; a later-group row nobody earlier needs is not.
    . "$S\lib\Streams.ps1"
    $fdoc = J $cr
    Case 'focus group is the first unclosed group' ((Get-FocusGroup $fdoc) -eq 'C1')
    $fset = Get-FocusSet $fdoc
    Case 'focus set holds the focus group rows and not later rows' ($fset.Contains('C1.S1') -and $fset.Contains('C1.P') -and -not $fset.Contains('C2.L1') -and -not $fset.Contains('C2.P')) ($fset -join ',')
    $fdoc2 = J $cr
    $fdoc2.tasks += (CTask 'C1.D' 'C1' 'planned' 5 @('C2.P') '')
    $fdoc2 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cr '.streams\tasks.json') -Encoding utf8
    $fset2 = Get-FocusSet (J $cr)
    Case 'a later-group root an earlier row depends on is in the focus set' ($fset2.Contains('C2.P') -and -not $fset2.Contains('C2.L1')) ($fset2 -join ',')
    $fdoc3 = J $cr; foreach ($g in $fdoc3.groups) { $g.state = 'closed' }
    Case 'every group closed: no focus group, empty focus set' ($null -eq (Get-FocusGroup $fdoc3) -and (Get-FocusSet $fdoc3).Count -eq 0)
    # OWNER-SET FOCUS (owner ruling 2026-10-06): .streams\config.json focus.groups names the focus group(s). C1 is open,
    # yet the owner names C2: C2's rows are the set (C2.P too, although frozen C1.D waits on it), every C1 row is frozen,
    # and the build selector offers C2 only. Two groups read in board order. An empty list, or a list whose groups are
    # all closed or unknown, is the automatic rule, and the source says so.
    . "$S\lib\Inbox.ps1"
    $cP = Get-StreamPaths $cr
    $cfgF = Join-Path $cr '.streams\config.json'
    Set-Content -LiteralPath $cfgF -Encoding utf8 -Value '{ "focus": { "groups": ["C2"] } }'
    $fo = Get-FocusGroups (J $cr) $cP
    $fsetC = Get-FocusSet (J $cr) $cP
    Case 'owner focus: config names C2 while C1 is open, so C2 is the focus and every C1 row is frozen' ($fo.source -eq 'config' -and (@($fo.groups) -join ',') -eq 'C2' -and $fsetC.Contains('C2.L1') -and $fsetC.Contains('C2.P') -and $fsetC.Contains('C2.FIX') -and -not $fsetC.Contains('C1.S1') -and -not $fsetC.Contains('C1.P') -and -not $fsetC.Contains('C1.D')) "src=$($fo.source) groups=$($fo.groups -join ',') set=$($fsetC -join ',')"
    $clC = Get-Claimable $cP (J $cr) 'build'
    Case 'owner focus: the build selector offers the named group only, labelled from the config' ((@($clC.ids) -contains 'C2.FIX') -and (@($clC.ids) -contains 'C2.L1') -and -not (@($clC.ids) | Where-Object { $_ -like 'C1.*' }) -and $clC.focusGroup -eq 'C2' -and $clC.focusSource -eq 'config') "ids=$($clC.ids -join ',') focus=$($clC.focusGroup) src=$($clC.focusSource)"
    Set-Content -LiteralPath $cfgF -Encoding utf8 -Value '{ "focus": { "groups": ["C2", "C1"] } }'
    $fo2 = Get-FocusGroups (J $cr) $cP
    # Owner ruling 2026-10-14: the list is read in the order it is WRITTEN (the priority order), not re-sorted to board order.
    Case 'owner focus: two groups are read in written order and labelled C2+C1' ((@($fo2.groups) -join ',') -eq 'C2,C1' -and (Get-FocusLabel (J $cr) $cP) -eq 'C2+C1' -and (Get-FocusGroup (J $cr) $cP) -eq 'C2' -and (Get-FocusSet (J $cr) $cP).Contains('C1.S1')) "groups=$($fo2.groups -join ',')"
    $pr2 = Get-PriorityRankMap (J $cr) $cP
    Case 'owner focus: priority rank puts the written-first group ahead of the board-first one' ($pr2['C2'] -eq 0 -and $pr2['C1'] -eq 1) "C2=$($pr2['C2']) C1=$($pr2['C1'])"
    Set-Content -LiteralPath $cfgF -Encoding utf8 -Value '{ "focus": { "groups": ["C2", "C1", "C2"] } }'
    Case 'owner focus: a group written twice is listed once' ((@((Get-FocusGroups (J $cr) $cP).groups) -join ',') -eq 'C2,C1') "groups=$((Get-FocusGroups (J $cr) $cP).groups -join ',')"
    Set-Content -LiteralPath $cfgF -Encoding utf8 -Value '{ "focus": { "groups": ["ZZ"] } }'
    $fo3 = Get-FocusGroups (J $cr) $cP
    Case 'owner focus: a list with no open board group in it falls back to the automatic rule and says so' ((@($fo3.groups) -join ',') -eq 'C1' -and $fo3.source.StartsWith('auto (config focus.groups [ZZ] are all closed')) "groups=$($fo3.groups -join ',') src=$($fo3.source)"
    Set-Content -LiteralPath $cfgF -Encoding utf8 -Value '{ "focus": { "groups": [] } }'
    $fo4 = Get-FocusGroups (J $cr) $cP
    Case 'owner focus: an empty list is the automatic rule' ((@($fo4.groups) -join ',') -eq 'C1' -and $fo4.source -eq 'auto') "groups=$($fo4.groups -join ',') src=$($fo4.source)"
    Remove-Item -LiteralPath $cfgF -Force

    # Focus claims (spec 3.1, E1). Close C1: C2 becomes focus and its fix row sorts first.
    $gdoc = J $cr; foreach ($g in $gdoc.groups) { if ($g.id -eq 'C1') { $g.state = 'closed' } }
    foreach ($t in $gdoc.tasks) { $t.claim = $null; if ($t.id -like 'C1.*') { $t.state = 'done' } }
    $gdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cr '.streams\tasks.json') -Encoding utf8
    $gb1 = & "$S\Claim-Task.ps1" -Repo $cr -Role build -Session build-g1 | ConvertFrom-Json
    Case 'when the earlier group closes the next group is focus and its fix row is first' ($gb1.id -eq 'C2.FIX') $gb1.id
    $gb2 = & "$S\Claim-Task.ps1" -Repo $cr -Role build -Session build-g2 | ConvertFrom-Json
    Case 'then the focus group order' ($gb2.id -eq 'C2.L1') $gb2.id
    # -Task on a non-focus row is refused by name.
    $hdoc = J $cr; foreach ($g in $hdoc.groups) { $g.state = 'released' }; foreach ($t in $hdoc.tasks) { $t.claim = $null; if ($t.id -like 'C1.*') { $t.state = 'ticketed' } }
    $hdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cr '.streams\tasks.json') -Encoding utf8
    $hr = & "$S\Claim-Task.ps1" -Repo $cr -Role build -Session build-h1 -Task C2.L2
    Case '-Task refuses a row outside the focus set' ($LASTEXITCODE -eq 2 -and ($hr -join ' ') -match 'REFUSED-TASK C2.L2 : not-focus') ($hr -join '|')
    # Cross-group chain: C1.D (ticketed, C1) depends on C2.P (planned, C2). The author tickets C2.P with C1, a builder
    # claims it, and the integrator selector lists it once built (review F4). The other C1 rows are done, so the
    # builder's only focus choice is the root.
    $idoc = J $cr; foreach ($t in $idoc.tasks) { if ($t.id -in @('C1.S1', 'C1.S2', 'C1.P')) { $t.state = 'done' } }
    $idoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cr '.streams\tasks.json') -Encoding utf8
    $ia = & "$S\Claim-Task.ps1" -Repo $cr -Role author -Session author-i1 | ConvertFrom-Json
    Case 'the author tickets a later-group root the focus group depends on' ($ia.id -eq 'C2.P') $ia.id
    & "$S\Update-Task.ps1" -Repo $cr -Task C2.P -Role author -Session author-i1 -To ticketed -Release -Note 'ticketed' | Out-Null
    $ib = & "$S\Claim-Task.ps1" -Repo $cr -Role build -Session build-i1 | ConvertFrom-Json
    Case 'a builder claims that root with the focus group' ($ib.id -eq 'C2.P') $ib.id
    $jdoc = J $cr; foreach ($t in $jdoc.tasks) { if ($t.id -eq 'C2.P') { $t.state = 'built'; $t.claim = $null } }
    $jdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cr '.streams\tasks.json') -Encoding utf8
    . "$S\lib\Inbox.ps1"
    $ic = Get-Claimable (Get-StreamPaths $cr) (J $cr) 'integrate'
    Case 'the integrate selector lists the built root' (@($ic.ids) -contains 'C2.P' -and -not (@($ic.ids) -contains 'C2.L1')) ($ic.ids -join ',')

    # Gate, inbox and integrator read the same selector (E1). Board: C1 released and focus (its rows planned, C1.D done
    # so no C2 row is in the effective set), C2 released and frozen with every row ticketed.
    $kdoc = J $cr; foreach ($g in $kdoc.groups) { $g.state = 'released' }
    foreach ($t in $kdoc.tasks) { $t.claim = $null; $t.state = if ($t.id -eq 'C1.D') { 'done' } elseif ($t.id -like 'C1.*') { 'planned' } else { 'ticketed' } }
    $kdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cr '.streams\tasks.json') -Encoding utf8
    $gate = @(& "$S\Start-StreamRunner.ps1" -Repo $cr -Role build -DryRun)
    Case 'the build gate reads IDLE while only frozen-group rows are ticketed' (($gate -join "`n") -match '(?m)^IDLE nothing to take for build') ($gate -join '|')
    $gateA = @(& "$S\Start-StreamRunner.ps1" -Repo $cr -Role author -DryRun)
    Case 'the author gate reads GATE planned for the focus group' (($gateA -join "`n") -match '(?m)^GATE planned 3 \(C1\.\S+\) focus C1') ($gateA -join '|')
    $snd = & "$S\Send-InboxItem.ps1" -Repo $cr -To stream-build -From owner -Kind request -Ask 'rebuild' -Task C2.L1
    Case 'an inbox item to a builder about a frozen-group row is refused' ($LASTEXITCODE -eq 9 -and ($snd -join ' ') -match 'outside the focus group C1') ($snd -join '|')
    $snd2 = & "$S\Send-InboxItem.ps1" -Repo $cr -To stream-build -From owner -Kind request -Ask 'rebuild' -Task C2.L1 -Force
    Case '-Force files it anyway' ($LASTEXITCODE -eq 0 -and ($snd2 -join ' ') -match '^SENT') ($snd2 -join '|')
    # Review M9: an open item about a frozen row (filed with -Force, or before the focus rule) launches no paid unit.
    $gate2 = @(& "$S\Start-StreamRunner.ps1" -Repo $cr -Role build -DryRun)
    Case 'the build gate ignores an open inbox item about a frozen-group row' (($gate2 -join "`n") -match '(?m)^IDLE nothing to take for build') ($gate2 -join '|')
    $ldoc = J $cr; foreach ($t in $ldoc.tasks) { if ($t.id -eq 'C2.L1') { $t.state = 'built'; $t.artifacts.patch = '.streams\patches\C2.L1.patch'; $t.artifacts.check = '.streams\checks\C2.L1.ps1' } }
    $ldoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $cr '.streams\tasks.json') -Encoding utf8
    & "$S\Enter-Integrator.ps1" -Repo $cr -Session integ-focus | Out-Null
    $ip = @(& "$S\Integrate-Patch.ps1" -Repo $cr -Session integ-focus -NoCommit)
    Case 'the integrator leaves a built frozen-group row alone' (($ip -join ' ') -match 'NOT-FOCUS C2.L1' -and ($ip -join ' ') -match 'NONE' -and (T $cr 'C2.L1').state -eq 'built') ($ip -join '|')
    # The status model and page name the focus group (spec 3.1, review F13).
    $fpg = Join-Path $Scratch 'focus-status.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $cr -Session status-focus -Out $fpg -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    $fph = Get-Content -Raw $fpg
    Case 'the claimable tile names the focus group' ($fph -match 'claimable &middot; of \d+ ticketed[^<]*focus C1') (([regex]::Match($fph, '.{0,60}claimable &middot;.{0,80}')).Value)
    $fj = & "$S\Get-StreamStatus.ps1" -Repo $cr -Json | ConvertFrom-Json
    Case 'the model carries focusGroup and notFocus' ($fj.claimable.focusGroup -eq 'C1' -and [int]$fj.claimable.notFocus -ge 1) ($fj.claimable | ConvertTo-Json -Compress)

    # Focus edges (final review I1-I3). F1 is closed but still holds rows that have not landed: F1.B (blocked) waits on
    # F2.Y, and F1.A (built) is what F2.X waits on. Both F2.Y and F1.A must stay workable or F2 can never close (I1).
    # F2.Z waits on F3.G, a later-group gate, and F2.G is F2's own gate: gates advance with no author claim (I2).
    # F3 holds five ticketed rows; a short buffer with ready F2 work must not read "focus group exhausted" (I3).
    $xr = Join-Path $Scratch 'focusedge'
    New-Item -ItemType Directory -Path $xr -Force | Out-Null
    git -C $xr init -q -b main; git -C $xr config user.email t@t; git -C $xr config user.name t; Grant-GitPolicy $xr
    Set-Content (Join-Path $xr 'x.txt') 'x'; git -C $xr add -A; git -C $xr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $xr | Out-Null
    $xg = { param($id, $g, $st, $deps) $t = CTask $id $g $st 5 $deps ''; $t.kind = 'gate'; $t.writeSet = @(); $t }
    $xdoc = @{
        groups = @(
            @{ id = 'F1'; name = 'closed'; state = 'closed'; origin = 'plan'; scope = @{ include = @('F-1') } }
            @{ id = 'F2'; name = 'focus'; state = 'released'; origin = 'plan'; scope = @{ include = @('F-2') } }
            @{ id = 'F3'; name = 'later'; state = 'released'; origin = 'plan'; scope = @{ include = @('F-3') } })
        tasks = @(
            (CTask 'F1.A' 'F1' 'built' 5 @() ''), (CTask 'F1.B' 'F1' 'blocked' 5 @('F2.Y') ''),
            (CTask 'F2.X' 'F2' 'ticketed' 5 @('F1.A') ''), (CTask 'F2.Y' 'F2' 'ticketed' 5 @() ''),
            (CTask 'F2.P' 'F2' 'planned' 5 @() ''), (CTask 'F2.Z' 'F2' 'planned' 5 @('F3.G') ''),
            (& $xg 'F2.G' 'F2' 'planned' @('F2.X')), (& $xg 'F3.G' 'F3' 'planned' @()),
            (CTask 'F3.T1' 'F3' 'ticketed' 5 @() ''), (CTask 'F3.T2' 'F3' 'ticketed' 5 @() ''), (CTask 'F3.T3' 'F3' 'ticketed' 5 @() ''),
            (CTask 'F3.T4' 'F3' 'ticketed' 5 @() ''), (CTask 'F3.T5' 'F3' 'ticketed' 5 @() ''))
    }
    $xdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $xr '.streams\tasks.json') -Encoding utf8
    $xP = Get-StreamPaths $xr
    $xset = Get-FocusSet (J $xr)
    Case 'focus: a row a closed group''s open row waits on stays in the focus set' ($xset.Contains('F2.Y') -and $xset.Contains('F2.X')) ($xset -join ',')
    Case 'focus: a closed group''s built row a focus row needs is in the focus set' ($xset.Contains('F1.A')) ($xset -join ',')
    $xbc = Get-Claimable $xP (J $xr) 'build'
    Case 'focus: that row is build-claimable' (@($xbc.ids) -contains 'F2.Y') ($xbc.ids -join ',')
    $xic = Get-Claimable $xP (J $xr) 'integrate'
    Case 'focus: the integrator may land the closed group''s built row' (@($xic.ids) -contains 'F1.A') ($xic.ids -join ',')
    # Gates: one status watchdog pass advances every planned gate of the focus set, the later-group one included.
    [void](& "$S\Invoke-Watchdog.ps1" -Repo $xr -Session status-x)
    Case 'focus: the watchdog advances the focus group''s own gate with no author unit' ((T $xr 'F2.G').state -eq 'ticketed') (T $xr 'F2.G').state
    Case 'focus: and a later-group gate a focus row waits on' ((T $xr 'F3.G').state -eq 'ticketed') (T $xr 'F3.G').state
    # DRY reason: two live builders and one live author (idle beats), 2 claimable (F2.X, F2.Y) against a target of 4.
    $now = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
    New-Item -ItemType Directory -Path (Join-Path $xr '.streams\idle') -Force | Out-Null
    Set-Content (Join-Path $xr '.streams\idle\build-x1.json') (@{ session = 'build-x1'; role = 'build'; at = $now } | ConvertTo-Json)
    Set-Content (Join-Path $xr '.streams\idle\build-x2.json') (@{ session = 'build-x2'; role = 'build'; at = $now } | ConvertTo-Json)
    Set-Content (Join-Path $xr '.streams\idle\author-x1.json') (@{ session = 'author-x1'; role = 'author'; at = $now } | ConvertTo-Json)
    $xj = & "$S\Get-StreamStatus.ps1" -Repo $xr -Json | ConvertFrom-Json
    $xdry = @($xj.flags | Where-Object { $_ -match 'PIPELINE DRY' })
    Case 'focus: a short buffer with ready focus work does not read "focus group exhausted"' ($xdry.Count -eq 1 -and $xdry[0] -notmatch 'exhausted') ($xdry -join '|')
    $ydoc = J $xr; foreach ($t in $ydoc.tasks) { if ($t.group -eq 'F2' -or $t.id -like 'F1.*') { $t.state = 'integrated'; $t.claim = $null } }
    $ydoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $xr '.streams\tasks.json') -Encoding utf8
    $yj = & "$S\Get-StreamStatus.ps1" -Repo $xr -Json | ConvertFrom-Json
    $ydry = @($yj.flags | Where-Object { $_ -match 'PIPELINE DRY' })
    Case 'focus: with no focus work left it reads "focus group F2 exhausted"' ($ydry.Count -eq 1 -and $ydry[0] -match 'focus group F2 exhausted') ($ydry -join '|')

    # Claimable build work. A builder that claims NONE writes nothing, so on 2026-10-02 the board read "build 0 live"
    # while six builders polled an empty queue (kit item IN-20261002130802-14a3). The board now counts the ticketed rows
    # a build claim would offer and, when that is 0, names the rows the waiting chains bottom out on. K1.C waits on K1.B,
    # which waits on the planned K1.A, so the root is K1.A and K1.B is not named; K1.D waits on an owner gate; K2.X is
    # ticketed and ready but its group is not released.
    $kr = Join-Path $Scratch 'stallrepo'
    New-Item -ItemType Directory -Path $kr -Force | Out-Null
    git -C $kr init -q -b main; git -C $kr config user.email t@t; git -C $kr config user.name t; Grant-GitPolicy $kr
    Set-Content (Join-Path $kr 'x.txt') 'x'; git -C $kr add -A; git -C $kr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $kr | Out-Null
    $kGate = CTask 'K1.G' 'K1' 'ticketed' 5 @() ''; $kGate.kind = 'gate'
    $kdoc = @{
        groups = @(
            @{ id = 'K1'; name = 'stalled'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-K') } }
            @{ id = 'K2'; name = 'unreleased'; state = 'planned'; origin = 'plan'; scope = @{ include = @('FEAT-K2') } })
        tasks = @(
            (CTask 'K1.A' 'K1' 'planned' 5 @() ''),
            (CTask 'K1.B' 'K1' 'ticketed' 5 @('K1.A') ''),
            (CTask 'K1.C' 'K1' 'ticketed' 5 @('K1.B') ''),
            $kGate,
            (CTask 'K1.D' 'K1' 'ticketed' 5 @('K1.G') ''),
            (CTask 'K2.X' 'K2' 'ticketed' 5 @() ''))
    }
    $kdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $kr '.streams\tasks.json') -Encoding utf8
    $kj = & "$S\Get-StreamStatus.ps1" -Repo $kr -Json | ConvertFrom-Json
    $kFlag = @($kj.flags | Where-Object { $_ -match 'claimable 0' })
    Case 'the board counts claimable build rows with the claim''s own gates' ([int]$kj.claimable.count -eq 0 -and [int]$kj.claimable.ticketed -eq 4 -and [int]$kj.claimable.waitingOnDeps -eq 3 -and [int]$kj.claimable.groupNotReleased -eq 0 -and [int]$kj.claimable.notFocus -eq 1) "claimable $($kj.claimable | ConvertTo-Json -Compress)"
    Case 'ticketed with nothing claimable is flagged' ($kFlag.Count -eq 1 -and $kFlag[0] -match '^ticketed 4, claimable 0') ($kj.flags -join ' / ')
    Case 'the flag names the roots the chains bottom out on, not the rows between' ($kFlag.Count -eq 1 -and $kFlag[0] -match 'K1\.A \(needs author\)' -and $kFlag[0] -match 'K1\.G \(owner gate\)' -and $kFlag[0] -notmatch 'K1\.B \(' -and $kFlag[0] -match '1 outside the focus group K1') ([string]$kFlag)
    Case 'a root that blocks more chains is named first' (@($kj.claimable.roots)[0].id -eq 'K1.A' -and [int]@($kj.claimable.roots)[0].blocks -eq 2) (($kj.claimable.roots | ForEach-Object { "$($_.id)=$($_.blocks)" }) -join ',')
    $kst = & "$S\Get-StreamStatus.ps1" -Repo $kr
    Case 'the terminal puts claimable beside the build sessions and stays 6 lines' (@($kst).Count -eq 6 -and [string]$kst[1] -match 'build 0 live \(0 working, 0 idle, 0 claimable of 4 ticketed\)') ([string]$kst[1])
    $kpg = Join-Path $Scratch 'status-stall.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $kr -Session status-k -Out $kpg -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    Case 'the page shows the claimable tile, marked when the queue is stalled' ((Get-Content -Raw $kpg) -match '<a class="tile stall" href="#flags"><b>0</b><span>claimable &middot; of 4 ticketed') 'no stalled claimable tile'
    # Land the root: K1.B becomes claimable, the stall flag goes, and the row the board counts is the row a claim takes.
    $kdoc.tasks[0].state = 'built'
    $kdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $kr '.streams\tasks.json') -Encoding utf8
    $kj2 = & "$S\Get-StreamStatus.ps1" -Repo $kr -Json | ConvertFrom-Json
    Case 'a built dependency makes the row claimable and clears the flag' ([int]$kj2.claimable.count -eq 1 -and @($kj2.claimable.ids) -contains 'K1.B' -and -not @($kj2.flags | Where-Object { $_ -match 'claimable 0' }).Count) "claimable $($kj2.claimable | ConvertTo-Json -Compress)"
    $kc = & "$S\Claim-Task.ps1" -Repo $kr -Role build -Session build-k1 | ConvertFrom-Json
    Case 'the row counted claimable is the row a build claim takes' ($kc.id -eq 'K1.B') $kc.id

    # Idle builders. A claim that comes back NONE wrote nothing, so the page read "build 2 live" while the owner ran six
    # builders (kit item IN-20261002150214-6ee3). Now each NONE leaves an idle beat and a claim clears it: two pollers
    # find nothing (K1.C still waits on K1.B), one is working K1.B, and the board reads 3 live, 1 working, 2 idle.
    $ki1 = & "$S\Claim-Task.ps1" -Repo $kr -Role build -Session build-idle1
    $ki2 = & "$S\Claim-Task.ps1" -Repo $kr -Role build -Session build-idle2
    Case 'a NONE claim leaves an idle beat for its session' ([string]$ki1 -eq 'NONE' -and [string]$ki2 -eq 'NONE' -and (Test-Path (Join-Path $kr '.streams\idle\build-idle1.json')) -and -not (Test-Path (Join-Path $kr '.streams\idle\build-k1.json'))) "$ki1 / $ki2 ; idle: $(@(Get-ChildItem (Join-Path $kr '.streams\idle') -ErrorAction SilentlyContinue).Name -join ',')"
    $kj3 = & "$S\Get-StreamStatus.ps1" -Repo $kr -Json | ConvertFrom-Json
    Case 'idle pollers count as live-idle builders' ([int]$kj3.sessions.build.live -eq 3 -and [int]$kj3.sessions.build.working -eq 1 -and [int]$kj3.sessions.build.idle -eq 2) "build $($kj3.sessions.build | ConvertTo-Json -Compress)"
    $kst3 = & "$S\Get-StreamStatus.ps1" -Repo $kr
    Case 'the terminal reads live, working, idle and claimable for build' ([string]$kst3[1] -match 'build 3 live \(1 working, 2 idle, 0 claimable of 3 ticketed\)') ([string]$kst3[1])
    $kpg3 = Join-Path $Scratch 'status-idle.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $kr -Session status-k -Out $kpg3 -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    Case 'the page builders tile shows working and idle' ((Get-Content -Raw $kpg3) -match '<b>3</b><span>builders live &middot; 1 working &middot; 2 idle</span>') 'no working/idle builders tile'
    # An idle beat older than the build limit no longer counts, and a later claim by that session clears its file.
    $oldBeat = (Get-Date).ToUniversalTime().AddMinutes(-90).ToString('yyyy-MM-ddTHH:mm:ssZ')
    Set-Content (Join-Path $kr '.streams\idle\build-idle2.json') (@{ session = 'build-idle2'; role = 'build'; at = $oldBeat } | ConvertTo-Json -Compress)
    $kj4 = & "$S\Get-StreamStatus.ps1" -Repo $kr -Json | ConvertFrom-Json
    Case 'an idle beat past the role limit stops counting' ([int]$kj4.sessions.build.live -eq 2 -and [int]$kj4.sessions.build.idle -eq 1) "build $($kj4.sessions.build | ConvertTo-Json -Compress)"
    $kdoc2 = Get-Content -Raw (Join-Path $kr '.streams\tasks.json') | ConvertFrom-Json -AsHashtable
    ($kdoc2.tasks | Where-Object { $_.id -eq 'K1.B' }).state = 'built'
    $kdoc2 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $kr '.streams\tasks.json') -Encoding utf8
    $ki5 = & "$S\Claim-Task.ps1" -Repo $kr -Role build -Session build-idle1 | ConvertFrom-Json
    Case 'a claim clears the session''s idle beat' ($ki5.id -eq 'K1.C' -and -not (Test-Path (Join-Path $kr '.streams\idle\build-idle1.json'))) "claimed $($ki5.id)"
    # Quiet builders (kit item IN-20261004152204-9ede). Four builders that had written nothing for 35-45 minutes read as
    # "4 idle" while 43 rows were claimable, so nobody restarted them. A live session with no claim that wrote nothing
    # for over 20 minutes is now quiet, and quiet builders beside claimable rows raise a flag. One that wrote 5 minutes
    # ago is still idle (between tasks).
    $kdoc3 = Get-Content -Raw (Join-Path $kr '.streams\tasks.json') | ConvertFrom-Json -AsHashtable
    $kq = CTask 'K1.E' 'K1' 'ticketed' 5 @() ''
    $kq.history = @(@{ at = (Get-Date).ToUniversalTime().AddMinutes(-60).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'plan-1'; to = 'ticketed'; note = 'fixture' },
        @{ at = (Get-Date).ToUniversalTime().AddMinutes(-30).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'build-gone'; to = 'ticketed'; note = 'released' },
        @{ at = (Get-Date).ToUniversalTime().AddMinutes(-5).ToString('yyyy-MM-ddTHH:mm:ssZ'); by = 'build-between'; to = 'ticketed'; note = 'released' })
    $kdoc3.tasks = @($kdoc3.tasks) + @($kq)
    $kdoc3 | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $kr '.streams\tasks.json') -Encoding utf8
    $kj6 = & "$S\Get-StreamStatus.ps1" -Repo $kr -Json | ConvertFrom-Json
    Case 'a claimless builder silent past 20 min is quiet, one 5 min ago is idle' ([int]$kj6.sessions.build.quiet -eq 1 -and @($kj6.sessions.build.quietIds) -contains 'build-gone' -and @($kj6.sessions.build.quietIds) -notcontains 'build-between') "build $($kj6.sessions.build | ConvertTo-Json -Compress -Depth 5)"
    Case 'quiet builders beside claimable rows raise a flag' (@($kj6.flags | Where-Object { $_ -match '^1 build sessions quiet .* while 1 rows are claimable: build-gone' }).Count -eq 1) ($kj6.flags -join ' / ')
    $kst6 = & "$S\Get-StreamStatus.ps1" -Repo $kr
    Case 'the terminal names quiet builders' (@($kst6).Count -eq 6 -and [string]$kst6[1] -match 'idle, 1 quiet, 1 claimable of') ([string]$kst6[1])
    $kpg6 = Join-Path $Scratch 'status-quiet.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $kr -Session status-k -Out $kpg6 -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    Case 'the page builders tile shows quiet' ((Get-Content -Raw $kpg6) -match 'builders live &middot; \d+ working &middot; \d+ idle &middot; 1 quiet</span>') 'no quiet on the builders tile'

    # Suite snapshots. G2 suites run 4 held main-grader.lock from its build to the end of its browser legs, so every
    # author RED re-run queued behind it for hours (kit item IN-20261002150859-0d59). A step-B run now tests a snapshot
    # of main, and the lock is held only while the snapshot is read.
    $sr = Join-Path $Scratch 'suiterepo'
    New-Item -ItemType Directory -Path $sr -Force | Out-Null
    git -C $sr init -q -b main; git -C $sr config user.email t@t; git -C $sr config user.name t; Grant-GitPolicy $sr
    Set-Content (Join-Path $sr 'a.txt') 'base'; Set-Content (Join-Path $sr '.gitignore') '.env'
    git -C $sr add -A; git -C $sr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $sr | Out-Null
    Set-Content (Join-Path $sr 'a.txt') 'dirty'; Set-Content (Join-Path $sr 'new.txt') 'untracked'; Set-Content (Join-Path $sr '.env') 'SECRET=1'
    $srHead = (git -C $sr rev-parse HEAD)
    $srLock = Join-Path $sr '.streams\main-grader.lock'
    $env:STREAM_MAIN_LOCK_WAIT_SECONDS = '1'
    $hold = [IO.FileStream]::new($srLock, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose)
    $o0 = @(& "$S\New-SuiteSnapshot.ps1" -Repo $sr -Session integ-s -Group S1 -Run 1); $x0 = $LASTEXITCODE
    $hold.Dispose()
    Remove-Item Env:\STREAM_MAIN_LOCK_WAIT_SECONDS -ErrorAction SilentlyContinue
    Case 'a snapshot waits for the main-grader lock and creates nothing when it stays busy' ($x0 -eq 5 -and ($o0 -join ' ') -match 'MAIN-GRADER-BUSY' -and -not @(Get-ChildItem (Join-Path $sr '.streams\suites') -ErrorAction SilentlyContinue).Count) "exit $x0 : $($o0 -join ' | ')"
    & "$S\Enter-Integrator.ps1" -Repo $sr -Session integ-s | Out-Null
    # An author's atomic-write temp vanished mid-copy and Copy-Item -Recurse failed the G4 Tier 3 retest (kit item
    # IN-20261010211022-8ba5): a writer's temp is not copied, and a file gone before its copy is skipped.
    $srTk = Join-Path $sr '.streams\tickets'; New-Item -ItemType Directory -Path (Join-Path $srTk 'sub') -Force | Out-Null
    Set-Content (Join-Path $srTk 'T1.md') 'ticket'; Set-Content (Join-Path $srTk 'T1.md.tmp.23472.aceb1561309b') 'half'
    Set-Content (Join-Path $srTk 'sub\T2.md') 'nested'
    . "$S\lib\Streams.ps1"
    $ctSkip = [Collections.Generic.List[string]]::new(); $ctDst = Join-Path $Scratch 'tolerant-copy'; $ctErr = ''
    try { Copy-FilesTolerant $srTk $ctDst @((Join-Path $srTk 'T1.md'), (Join-Path $srTk 'gone.md'), (Join-Path $srTk 'gonedir\x.md')) $ctSkip } catch { $ctErr = "$_" }
    Case 'a file that vanished before its copy is skipped, not thrown' (-not $ctErr -and (Test-Path (Join-Path $ctDst 'T1.md')) -and ($ctSkip -join ',') -eq 'gone.md,gonedir\x.md') "err '$ctErr' skipped '$($ctSkip -join ',')'"
    $o1 = @(& "$S\New-SuiteSnapshot.ps1" -Repo $sr -Session integ-s -Group S1 -Run 1 -CopyIgnored '.env' -Log '.streams\logs\S1.suites.1.txt'); $x1 = $LASTEXITCODE
    $snap1 = [string]$o1[-1]
    Case 'the snapshot is main HEAD plus its dirty diff, untracked files and the named ignored file' ($x1 -eq 0 -and (git -C $snap1 rev-parse HEAD) -eq $srHead -and (Get-Content (Join-Path $snap1 'a.txt')) -eq 'dirty' -and (Test-Path (Join-Path $snap1 'new.txt')) -and (Get-Content (Join-Path $snap1 '.env')) -eq 'SECRET=1') "exit $x1 : $($o1 -join ' | ')"
    $snTk = Join-Path $snap1 '.streams\tickets'
    Case 'the snapshot copies .streams inputs, nested too, but never a writer temp file' ((Test-Path (Join-Path $snTk 'T1.md')) -and (Test-Path (Join-Path $snTk 'sub\T2.md')) -and -not (Test-Path (Join-Path $snTk 'T1.md.tmp.23472.aceb1561309b'))) (@(Get-ChildItem $snTk -Recurse -Name -ErrorAction SilentlyContinue) -join ', ')
    Case 'the suite log records the snapshot HEAD sha' ((Get-Content -Raw (Join-Path $sr '.streams\logs\S1.suites.1.txt')) -match "SNAPSHOT .+ HEAD $srHead dirty \d+") (Get-Content -Raw (Join-Path $sr '.streams\logs\S1.suites.1.txt'))
    $free = $null; try { $free = [IO.FileStream]::new($srLock, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose) } catch { }
    Case 'the main-grader lock is free as soon as the snapshot exists' ($null -ne $free) 'lock still held after the snapshot'
    if ($free) { $free.Dispose() }
    Set-Content (Join-Path $sr 'a.txt') 'main moved on'
    Case 'a write to main after the snapshot does not reach the snapshot' ((Get-Content (Join-Path $snap1 'a.txt')) -eq 'dirty') (Get-Content (Join-Path $snap1 'a.txt'))
    [void](& "$S\Invoke-IntegratorRun.ps1" -Repo $sr -Session integ-s -Log '.streams\logs\S1.cwd.txt' -Command '(Get-Location).Path' -WorkDir $snap1)
    Case 'Invoke-IntegratorRun -WorkDir runs the command in the snapshot' ((Get-Content -Raw (Join-Path $sr '.streams\logs\S1.cwd.txt')) -match [regex]::Escape($snap1)) (Get-Content -Raw (Join-Path $sr '.streams\logs\S1.cwd.txt'))
    [void](& "$S\Invoke-Watchdog.ps1" -Repo $sr -Session status-s)
    Case 'the watchdog keeps the newest snapshot while its session holds a live integrator lock' (Test-Path $snap1) 'snapshot reaped under a live lock'
    $o2 = @(& "$S\New-SuiteSnapshot.ps1" -Repo $sr -Session integ-s -Group S1 -Run 2); $snap2 = [string]$o2[-1]
    # A Tier 2 run still running in the older snapshot keeps it: a Tier 3 snapshot taken meanwhile must not get it reaped.
    $srRuns = Join-Path $sr '.streams\suites\runs'; New-Item -ItemType Directory -Path $srRuns -Force | Out-Null
    $srRec = Join-Path $srRuns 'run-S1-1.json'
    @{ id = 'run-S1-1'; tier = '2'; group = 'S1'; startedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ'); status = 'running'; snapshot = $snap1; pid = $PID
       pidStart = (Get-Process -Id $PID).StartTime.ToUniversalTime().ToString('o') } | ConvertTo-Json | Set-Content $srRec
    $wdr = @(& "$S\Invoke-Watchdog.ps1" -Repo $sr -Session status-s)
    Case 'the watchdog keeps a snapshot that a running suite run names, even when superseded' ((Test-Path $snap1) -and (Test-Path $snap2)) ($wdr -join ' | ')
    $sx = Get-Content -Raw $srRec | ConvertFrom-Json -AsHashtable; $sx.status = 'done'; $sx | ConvertTo-Json | Set-Content $srRec
    $wds = @(& "$S\Invoke-Watchdog.ps1" -Repo $sr -Session status-s)
    Case 'a superseded snapshot is reaped and the newest kept' (-not (Test-Path $snap1) -and (Test-Path $snap2)) ($wds -join ' | ')
    Remove-Item (Join-Path $sr '.streams\integrator.lock') -Force
    $wde = @(& "$S\Invoke-Watchdog.ps1" -Repo $sr -Session status-s)
    Case 'with no live integrator lock the newest snapshot is reaped too' (-not (Test-Path $snap2)) ($wde -join ' | ')

    # Effective group rank. Group-first author order ticketed a later-group root AFTER the earlier group it holds: on
    # 2026-10-02 G3.T210 sat ticketed for a day on G5.T061, still planned (kit item IN-20261002153754-be85). E1.A
    # depends on E2.M, which depends on E3.R, so both inherit E1 and Chain puts the root first; E2.X and E3.Z are
    # unrelated and keep their own groups. The build sort keeps the row's own group: E3.Q, which E1.C waits on, does
    # not jump E2.B.
    $er = Join-Path $Scratch 'rankrepo'
    New-Item -ItemType Directory -Path $er -Force | Out-Null
    git -C $er init -q -b main; git -C $er config user.email t@t; git -C $er config user.name t; Grant-GitPolicy $er
    Set-Content (Join-Path $er 'x.txt') 'x'; git -C $er add -A; git -C $er commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $er | Out-Null
    $edoc = @{
        groups = @(
            @{ id = 'E1'; name = 'first'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-E1') } }
            @{ id = 'E2'; name = 'second'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-E2') } }
            @{ id = 'E3'; name = 'third'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-E3') } })
        tasks = @(
            (CTask 'E1.A' 'E1' 'planned' 5 @('E2.M') ''),
            (CTask 'E1.B' 'E1' 'planned' 1 @() ''),
            (CTask 'E2.M' 'E2' 'planned' 5 @('E3.R') ''),
            (CTask 'E2.X' 'E2' 'planned' 50 @() ''),
            (CTask 'E3.R' 'E3' 'planned' 5 @() ''),
            (CTask 'E3.Z' 'E3' 'planned' 99 @() ''),
            (CTask 'E1.C' 'E1' 'planned' 5 @('E3.Q') ''),
            (CTask 'E2.B' 'E2' 'ticketed' 5 @() ''),
            (CTask 'E3.Q' 'E3' 'ticketed' 5 @() ''))
    }
    $edoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $er '.streams\tasks.json') -Encoding utf8
    $ea1 = & "$S\Claim-Task.ps1" -Repo $er -Role author -Session author-e1 | ConvertFrom-Json
    Case 'a later-group root that blocks earlier-group work is authored with that earlier group' ($ea1.id -eq 'E3.R') $ea1.id
    # Ready-first is the permanent author key after the effective group (kit item IN-20261002161525-69c9): E1.B, whose
    # ticket a builder could take at once, comes before E2.M, E1.A and E1.C, which all wait on unbuilt rows; the chain
    # then orders those three, the inherited root E2.M first.
    $ea2 = & "$S\Claim-Task.ps1" -Repo $er -Role author -Session author-e2 | ConvertFrom-Json
    Case 'a ready row beats a not-ready row inside its effective group' ($ea2.id -eq 'E1.B') $ea2.id
    $ea3 = & "$S\Claim-Task.ps1" -Repo $er -Role author -Session author-e3 | ConvertFrom-Json
    $ea4 = & "$S\Claim-Task.ps1" -Repo $er -Role author -Session author-e4 | ConvertFrom-Json
    $ea5 = & "$S\Claim-Task.ps1" -Repo $er -Role author -Session author-e5 | ConvertFrom-Json
    $ea6 = & "$S\Claim-Task.ps1" -Repo $er -Role author -Session author-e6
    Case 'the inherited rank is transitive and the chain puts the root ahead of its dependents' ((@($ea3.id, $ea4.id, $ea5.id) -join ',') -eq 'E2.M,E1.A,E1.C') "$($ea3.id),$($ea4.id),$($ea5.id)"
    # AUTHOR SPILL (owner ruling 2026-10-12): with nothing left for authors in the focus set, the author queue spills into
    # the next released group: E2.X (group E2) before E3.Z (E3). Builders never spill (next case).
    $ea6j = if ("$ea6" -ne 'NONE') { ($ea6 -join "`n") | ConvertFrom-Json } else { [pscustomobject]@{ id = 'NONE' } }
    Case 'with the focus set exhausted for authors, the next group''s row is an author spill' ($ea6j.id -eq 'E2.X') "$($ea6j.id) (E2.X is outside E1's effective set)"
    $eb1 = & "$S\Claim-Task.ps1" -Repo $er -Role build -Session build-e1 | ConvertFrom-Json
    Case 'the build sort offers only the effective set: E2.B waits, E3.Q (holds E1.C) is taken (focus)' ($eb1.id -eq 'E3.Q') $eb1.id
    $edoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $er '.streams\tasks.json') -Encoding utf8
    $ej = & "$S\Get-StreamStatus.ps1" -Repo $er -Json | ConvertFrom-Json
    $eR = @($ej.authorRank | Where-Object { $_.id -eq 'E3.R' })
    Case 'the page model names the inherited group and the row it comes through' ($eR.Count -eq 1 -and $eR[0].effectiveGroup -eq 'E1' -and $eR[0].via -eq 'E1.A' -and -not @($ej.authorRank | Where-Object { $_.id -in @('E3.Z', 'E2.X', 'E1.A') }).Count) (($ej.authorRank | ConvertTo-Json -Compress))

    # Claimable buffer (owner ruling 2026-10-02, kit item IN-20261002160453-9384, amended by IN-20261002161525-69c9).
    # Target = 2 claimable rows per live builder; below it the board raises PIPELINE DRY with the dominant reason, and
    # the page marks the tile and the flag. The AUTHOR sort puts planned rows whose dependencies are all built ahead of
    # longer chains that still wait, after the group key, ALWAYS: with no live builder as well as with one.
    $br = Join-Path $Scratch 'bufrepo'
    New-Item -ItemType Directory -Path $br -Force | Out-Null
    git -C $br init -q -b main; git -C $br config user.email t@t; git -C $br config user.name t; Grant-GitPolicy $br
    Set-Content (Join-Path $br 'x.txt') 'x'; git -C $br add -A; git -C $br commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $br | Out-Null
    $bq = CTask 'B1.Q' 'B1' 'building' 1 @() ''
    $bdoc = @{
        groups = @(
            @{ id = 'B0'; name = 'zero'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-B0') } }
            @{ id = 'B1'; name = 'one'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-B1') } })
        tasks = @(
            (CTask 'B0.U' 'B0' 'planned' 5 @('B1.Q') ''),
            $bq,
            (CTask 'B1.D' 'B1' 'planned' 99 @('B1.Q') ''),
            (CTask 'B1.E' 'B1' 'planned' 3 @() ''),
            (CTask 'B1.W' 'B1' 'ticketed' 5 @('B1.D') ''))
    }
    $bdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $br '.streams\tasks.json') -Encoding utf8
    $bn1 = @(& "$S\Claim-Task.ps1" -Repo $br -Role author -Session author-b1 | ConvertFrom-Json)
    $bn2 = @(& "$S\Claim-Task.ps1" -Repo $br -Role author -Session author-b2)
    Remove-Item (Join-Path $br '.streams\idle\author-b2.json') -ErrorAction SilentlyContinue   # its NONE beat would make an author live
    $bn2j = if ($bn2[-1] -ne 'NONE') { ($bn2 -join "`n") | ConvertFrom-Json } else { [pscustomobject]@{ id = 'NONE' } }
    Case 'no live builder: the focus row is taken first, then the author spills to the ready later-group row' ($bn1[0].id -eq 'B0.U' -and $bn2j.id -eq 'B1.E') "$($bn1[0].id),$($bn2j.id)"
    $bdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $br '.streams\tasks.json') -Encoding utf8
    $bnone = @(& "$S\Claim-Task.ps1" -Repo $br -Role build -Session build-b1)
    $bj0 = & "$S\Get-StreamStatus.ps1" -Repo $br -Json | ConvertFrom-Json
    Case 'one idle builder sets target 2 and the buffer is short' ($bnone[-1] -eq 'NONE' -and $bj0.buffer.liveBuilders -eq 1 -and $bj0.buffer.target -eq 2 -and $bj0.buffer.claimable -eq 0 -and $bj0.buffer.dry) (($bj0.buffer | ConvertTo-Json -Compress) + ' ' + ($bnone -join '|'))
    Case 'PIPELINE DRY names no author live first when planned rows wait on nobody' ([string]$bj0.flags[0] -like 'PIPELINE DRY: claimable 0 of target 2 (2 x 1 live builders) - no author live*') ([string]$bj0.flags[0])
    $bs1 = @(& "$S\Claim-Task.ps1" -Repo $br -Role author -Session author-b3 | ConvertFrom-Json)
    $bs2 = @(& "$S\Claim-Task.ps1" -Repo $br -Role author -Session author-b4)
    $bs2j = if ($bs2[-1] -ne 'NONE') { ($bs2 -join "`n") | ConvertFrom-Json } else { [pscustomobject]@{ id = 'NONE' } }
    Case 'with a builder live the author order is the same (focus, then spill)' ($bs1[0].id -eq 'B0.U' -and $bs2j.id -eq 'B1.E') "$($bs1[0].id),$($bs2j.id)"
    $bj1 = & "$S\Get-StreamStatus.ps1" -Repo $br -Json | ConvertFrom-Json
    Case 'with authors live the reason is the exhausted focus group (focus)' ([string]$bj1.flags[0] -like 'PIPELINE DRY:*focus group B0 exhausted (1 ticketed*' -and $bj1.buffer.waitingOnUnticketed -eq 0) ([string]$bj1.flags[0])
    $bpg = Join-Path $Scratch 'buf-status.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $br -Session status-buf -Out $bpg -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    $bph = Get-Content -Raw $bpg
    Case 'the page marks the claimable tile and the PIPELINE DRY flag' ($bph -match 'class="tile stall"[^>]*><b>0</b><span>claimable &middot; of 1 ticketed &middot; target 2' -and $bph -match 'class="flag dry">PIPELINE DRY') (([regex]::Match($bph, '.{0,80}claimable &middot;.{0,80}')).Value)
    # An integration fix that is NOT ready still comes before a ready row of an earlier group.
    $bdoc.tasks += (CTask 'B0.F' 'B0' 'planned' 1 @('B1.Q') 'integration')   # inside the focus group (spec 3.1)
    $bdoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $br '.streams\tasks.json') -Encoding utf8
    $bf = @(& "$S\Claim-Task.ps1" -Repo $br -Role author -Session author-b5 | ConvertFrom-Json)
    Case 'an integration fix still comes first, ready or not' ($bf[0].id -eq 'B0.F') $bf[0].id

    # Main tree held and author releases per hour (kit item IN-20261002161450-c89b). On 2026-10-02 G2 suite runs held
    # main-grader.lock about 9 of 15 hours and releases fell to 0-7/h with nothing on the board showing it. L1.R was
    # released 2.5 h ago and L1.S 0.2 h ago; the gate L1.G advanced with no ticket and L1.T arrived ticketed from the
    # plan, so neither counts. The lock is held for real (DeleteOnClose, FileShare.Read, as Enter-MainTreeLock holds it),
    # because a plain read of a held lock fails and printed 'held by: ?'.
    $lr = Join-Path $Scratch 'lockrepo'
    New-Item -ItemType Directory -Path $lr -Force | Out-Null
    git -C $lr init -q -b main; git -C $lr config user.email t@t; git -C $lr config user.name t; Grant-GitPolicy $lr
    Set-Content (Join-Path $lr 'x.txt') 'x'; git -C $lr add -A; git -C $lr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $lr | Out-Null
    $ago = { param([double] $h) (Get-Date).ToUniversalTime().AddHours(-$h).ToString('yyyy-MM-ddTHH:mm:ssZ') }
    $tkR = CTask 'L1.R' 'L1' 'ticketed' 5 @() ''; $tkR.history = @(@{ at = (& $ago 5); by = 'plan-1'; to = 'planned'; note = 'plan' }, @{ at = (& $ago 2.5); by = 'author-1'; to = 'ticketed'; note = 'ticket' })
    $tkS = CTask 'L1.S' 'L1' 'ticketed' 5 @() ''; $tkS.history = @(@{ at = (& $ago 5); by = 'plan-1'; to = 'planned'; note = 'plan' }, @{ at = (& $ago 1); by = 'author-1'; to = 'planned'; note = 'claimed by author' }, @{ at = (& $ago 0.2); by = 'author-1'; to = 'ticketed'; note = 'ticket' })
    $tkG = CTask 'L1.G' 'L1' 'ticketed' 5 @() ''; $tkG.kind = 'gate'; $tkG.history = @(@{ at = (& $ago 5); by = 'plan-1'; to = 'planned'; note = 'plan' }, @{ at = (& $ago 0.1); by = 'author-1'; to = 'ticketed'; note = 'gate: no ticket needed' })
    $tkT = CTask 'L1.T' 'L1' 'ticketed' 5 @() ''
    @{ groups = @(@{ id = 'L1'; name = 'lock'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-L') } }); tasks = @($tkR, $tkS, $tkG, $tkT) } | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $lr '.streams\tasks.json') -Encoding utf8
    $lLock = Join-Path $lr '.streams\main-grader.lock'
    $holdLock = { param([string] $text) $fs = [IO.FileStream]::new($lLock, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::Read, 4096, [IO.FileOptions]::DeleteOnClose); $b = [Text.Encoding]::UTF8.GetBytes($text); $fs.Write($b, 0, $b.Length); $fs.Flush(); $fs }
    $lh1 = & $holdLock "suite G2.suites.4 pid 4242 at $(& $ago 0.5)"
    $lj = & "$S\Get-StreamStatus.ps1" -Repo $lr -Json | ConvertFrom-Json
    $lFlag = @($lj.flags | Where-Object { $_ -like 'main tree held*' })
    Case 'a main-grader lock held past 20 minutes is flagged with its holder and age' ($lFlag.Count -eq 1 -and $lFlag[0] -match "^main tree held (29|30|31) min by 'suite G2\.suites\.4 pid 4242 at ") ($lj.flags -join ' / ')
    Case 'releases per hour count only planned-to-ticketed authoring, oldest hour first' ((@($lj.releases.perHour) -join ' ') -eq '0 0 0 1 0 1' -and [int]$lj.releases.total -eq 2) (($lj.releases | ConvertTo-Json -Compress))
    $lpg = Join-Path $Scratch 'lock-status.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $lr -Session status-l -Out $lpg -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    $lph = Get-Content -Raw $lpg
    Case 'the page shows releases per hour beside the claimable tile and the held flag' ($lph -match 'claimable &middot;[^<]*</span></a>\s*<div class="tile"><b>1</b><span>released last hour &middot; per hour, last 6 h: 0 0 0 1 0 1' -and $lph -match 'main tree held') (([regex]::Match($lph, 'claimable &middot;.{0,200}')).Value)
    $lh1.Dispose(); $lh2 = & $holdLock "integ-1 apply G1.T1 pid 1 at $(& $ago 0.1)"
    $lj2 = & "$S\Get-StreamStatus.ps1" -Repo $lr -Json | ConvertFrom-Json
    $lh2.Dispose()
    $lj3 = & "$S\Get-StreamStatus.ps1" -Repo $lr -Json | ConvertFrom-Json
    Case 'a short hold and a free lock raise no flag' (-not @($lj2.flags | Where-Object { $_ -like 'main tree held*' }).Count -and [int]$lj2.mainLock.minutes -le 7 -and $null -eq $lj3.mainLock) "$($lj2.flags -join ' / ') | $($lj3.mainLock | ConvertTo-Json -Compress)"

    # Builder check plus author grader. The RED moved from the author to the builder's worktree and the builder now
    # records its own check (clause tests plus impact tests); a row's author grader stays as one more check (kit items
    # IN-20261002160453-ce2a, IN-20261002160643-741d). Invoke-Grader runs both into one log and fails when either does.
    $gr = Join-Path $Scratch 'chkrepo'
    New-Item -ItemType Directory -Path $gr -Force | Out-Null
    git -C $gr init -q -b main; git -C $gr config user.email t@t; git -C $gr config user.name t; Grant-GitPolicy $gr
    Set-Content (Join-Path $gr 'x.txt') 'x'; git -C $gr add -A; git -C $gr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $gr | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $gr '.streams\checks') -Force | Out-Null
    Set-Content (Join-Path $gr '.streams\graders\H1.G.ps1') @'
param([string]$Root)
if (Test-Path (Join-Path $Root 'impl.txt')) { 'PASS A1'; exit 0 } else { 'FAIL A1: impl.txt missing'; exit 1 }
'@
    Set-Content (Join-Path $gr '.streams\checks\H1.G.ps1') @'
param([string]$Root)
'PASS I1'
if (Test-Path (Join-Path $Root 'impl.txt')) { 'PASS A2'; exit 0 } else { 'FAIL A2: impl.txt missing'; exit 1 }
'@
    $hT = CTask 'H1.G' 'H1' 'building' 5 @() ''; $hT.artifacts.check = '.streams\checks\H1.G.ps1'
    $hN = CTask 'H1.N' 'H1' 'building' 5 @() ''; $hN.artifacts.grader = $null
    $hO = CTask 'H1.O' 'H1' 'building' 5 @() ''; $hO.artifacts.grader = '.streams\graders\H1.G.ps1'
    @{ groups = @(@{ id = 'H1'; name = 'checks'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-H') } }); tasks = @($hT, $hN, $hO) } |
        ConvertTo-Json -Depth 20 | Set-Content (Join-Path $gr '.streams\tasks.json') -Encoding utf8
    $hwt = Join-Path $Scratch 'chk-wt'; New-Item -ItemType Directory -Path $hwt -Force | Out-Null
    $hr1 = @(& "$S\Invoke-Grader.ps1" -Repo $gr -Task H1.G -Root $hwt -Only grader -Label red -ExpectRed); $hx1 = $LASTEXITCODE
    $hl1 = Get-Content -Raw (Join-Path $gr '.streams\logs\H1.G.grader.red.txt')
    Case 'builder RED on a fresh tree runs ONLY the author grader' ($hx1 -eq 0 -and $hl1 -match 'FAIL A1' -and $hl1 -notmatch '(?m)^(PASS|FAIL) (A2|I1)\b') "exit $hx1 : $hl1"
    $hr2 = @(& "$S\Invoke-Grader.ps1" -Repo $gr -Task H1.G -Root $hwt -Only check -Label red-check -ExpectRed); $hx2 = $LASTEXITCODE
    $hl2 = Get-Content -Raw (Join-Path $gr '.streams\logs\H1.G.grader.red-check.txt')
    Case 'the clause-test RED runs only the builder check' ($hx2 -eq 0 -and $hl2 -match 'FAIL A2' -and $hl2 -match 'PASS I1' -and $hl2 -notmatch '(?m)^(PASS|FAIL) A1\b') "exit $hx2 : $hl2"
    $hr3 = @(& "$S\Invoke-Grader.ps1" -Repo $gr -Task H1.G -Root $hwt -Label wt); $hx3 = $LASTEXITCODE
    $hl3 = Get-Content -Raw (Join-Path $gr '.streams\logs\H1.G.grader.wt.txt')
    Case 'a default run grades check AND grader into one log and fails when either fails' ($hx3 -ne 0 -and $hl3 -match 'FAIL A2' -and $hl3 -match 'FAIL A1' -and $hl3 -match '(?m)^GRADER sha \S+\+\S+ ') "exit $hx3 : $hl3"
    Set-Content (Join-Path $hwt 'impl.txt') 'done'
    $hr4 = @(& "$S\Invoke-Grader.ps1" -Repo $gr -Task H1.G -Root $hwt -Label wt); $hx4 = $LASTEXITCODE
    Case 'check and grader both green is a PASS' ($hx4 -eq 0 -and ($hr4 -join ' ') -match 'PASS A1' -and ($hr4 -join ' ') -match 'PASS A2') "exit $hx4 : $($hr4 -join ' | ')"
    $hr5 = @(& "$S\Invoke-Grader.ps1" -Repo $gr -Task H1.N -Root $hwt -Label wt); $hx5 = $LASTEXITCODE
    Case 'a row with neither a check nor a grader is NO-GRADER' ($hx5 -eq 4 -and ($hr5 -join ' ') -match 'NO-GRADER H1\.N') "exit $hx5 : $($hr5 -join ' | ')"
    $hr6 = @(& "$S\Invoke-Grader.ps1" -Repo $gr -Task H1.O -Root $hwt -Only check -Label red-check -ExpectRed); $hx6 = $LASTEXITCODE
    Case '-Only check on a row with only an author grader is NO-GRADER' ($hx6 -eq 4) "exit $hx6 : $($hr6 -join ' | ')"
    $hr7 = @(& "$S\Invoke-Grader.ps1" -Repo $gr -Task H1.O -Root $hwt -Label wt); $hx7 = $LASTEXITCODE
    $hl7 = Get-Content -Raw (Join-Path $gr '.streams\logs\H1.O.grader.wt.txt')
    Case 'a row with only an author grader grades as before, one hash, no section header' ($hx7 -eq 0 -and $hl7 -match '(?m)^GRADER sha [0-9A-Fa-f]+ ' -and $hl7 -notmatch '\+' -and $hl7 -notmatch '(?m)^== ') "exit $hx7 : $hl7"

    # Left to plan (kit items IN-20261009131901-10e4, IN-20261009132301-e0a4): the acceptance clauses of READY requirement
    # files that no row names, over ALL requirements, with a per-group count and a 'not in any group' count. The folder is
    # found from the repo root although tasks.json points elsewhere; a DRAFT template is not a goal; a row names a clause
    # in its why (an array), its tests (a longer token names its prefix) or its ticket. A closed group with a clause no row
    # names makes the count untrustworthy, so it reads unknown with the reason, never a number.
    $pr = Join-Path $Scratch 'planrepo'
    New-Item -ItemType Directory -Path (Join-Path $pr 'docs\requirements\features'), (Join-Path $pr 'docs\requirements\templates') -Force | Out-Null
    git -C $pr init -q -b main; git -C $pr config user.email t@t; git -C $pr config user.name t; Grant-GitPolicy $pr
    Set-Content (Join-Path $pr 'x.txt') 'x'; git -C $pr add -A; git -C $pr commit -q -m base
    & "$S\Init-Streams.ps1" -Repo $pr | Out-Null
    Set-Content (Join-Path $pr 'docs\requirements\features\FEAT-A-001.yaml') "id: FEAT-A-001`nstatus: READY`nacceptance:`n- id: AC-A-001`n  given:`n  - a`n- id: AC-A-002`n- id: AC-A-003`ntraceability:`n  - AC-A-009`n"
    Set-Content (Join-Path $pr 'docs\requirements\features\FEAT-B-001.yaml') "id: FEAT-B-001`nstatus: READY`nacceptance:`n- id: AC-B-001`n- id: AC-B-002`n"
    Set-Content (Join-Path $pr 'docs\requirements\templates\target.yaml') "id: FEAT-TEMPLATE-000`nstatus: DRAFT`nacceptance:`n- id: AC-T-001`n"
    $pT1 = CTask 'P1.T1' 'P1' 'ticketed' 5 @() ''; $pT1.why = @('builds the A loader', 'AC-A-001')
    $pT2 = CTask 'P1.T2' 'P1' 'planned' 5 @() ''; $pT2.why = @('x'); $pT2.tests = @('AC-A-002-B covers the refusal')
    $pT3 = CTask 'P1.T3' 'P1' 'planned' 5 @() ''; $pT3.why = @('x')
    New-Item -ItemType Directory -Path (Join-Path $pr '.streams\tickets') -Force | Out-Null
    Set-Content (Join-Path $pr '.streams\tickets\P1.T3.md') "# P1.T3`nProves AC-B-001 end to end."
    $pDoc = @{ requirements = 'C:\no-such-root\docs\requirements\'; groups = @(@{ id = 'P1'; name = 'plan'; state = 'released'; origin = 'plan'; scope = @{ include = @('FEAT-A-001') } }); tasks = @($pT1, $pT2, $pT3) }
    $pDoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $pr '.streams\tasks.json') -Encoding utf8
    $pj = (& "$S\Get-StreamStatus.ps1" -Repo $pr -Json | ConvertFrom-Json).leftToPlan
    Case 'left to plan counts READY clauses no row names, per group and in no group' ($pj.known -and [int]$pj.total -eq 2 -and [int]$pj.clauses -eq 5 -and [int]$pj.byGroup.P1.count -eq 1 -and [int]$pj.notInGroup -eq 1 -and (@($pj.unnamedIds.P1) -join ',') -eq 'AC-A-003' -and (@($pj.unnamedIds.none) -join ',') -eq 'AC-B-002' -and [int]$pj.notReadyClauses -eq 1 -and $pj.root -eq (Join-Path $pr 'docs\requirements')) ($pj | ConvertTo-Json -Compress -Depth 6)
    $pst = @(& "$S\Get-StreamStatus.ps1" -Repo $pr)
    Case 'the terminal tasks line carries left to plan and stays six lines' ($pst.Count -eq 6 -and ($pst | Where-Object { $_ -like 'tasks:*' }) -match '\| left to plan 2 of 5 clauses \(1 in no group\)$') ($pst -join ' / ')
    $ppg = Join-Path $Scratch 'plan-status.html'
    [void](& "$S\Build-StatusPage.ps1" -Repo $pr -Session status-p -Out $ppg -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    $pph = Get-Content -Raw $ppg
    Case 'the page shows the left to plan tile right after ready to author and left to author, the column and the no-group row' ($pph -match '<span>ready to author</span></div>\s*<div class="tile"[^>]*><b>\d+</b><span>left to author[^<]*</span></div>\s*<a class="tile" href="#left-to-plan"[^>]*><b>2</b><span>left to plan &middot; of 5 clauses' -and $pph -match '<th id="left-to-plan">Left to plan</th>' -and $pph -match '(?s)Not in any group.{0,600}?<td class="num" title="AC-B-002">1</td>' -and $pph -match '(?s)P1</span></td>.{0,1500}?<td class="num" title="AC-A-003">1</td>') (([regex]::Match($pph, 'planned</span>.{0,300}')).Value)
    # Totals line (owner ask 2026-10-16, lost with the CORPVM17 kit copy and restored 2026-10-17): one line under the
    # Priority categories title, before the table, labelled like the columns and summing the All categories row.
    $ptl = [regex]::Match($pph, '(?s)<h2>Priority categories</h2>\s*<div class="cat-totals"[^>]*>(.*?)</div>\s*<style>.*?<table class="cats">')
    $ptv = [ordered]@{}; foreach ($m in [regex]::Matches($ptl.Groups[1].Value, '<span class="muted">([^<]+)</span> <b>([^<]+)</b>')) { $ptv[$m.Groups[1].Value] = $m.Groups[2].Value }
    $ptr = [regex]::Matches([regex]::Match($pph, '(?s)<tr class="total">.*?</tr>').Value, '<td class="num[^"]*"[^>]*>([^<]*)<') | ForEach-Object { $_.Groups[1].Value }
    Case 'the categories totals line sits under the title, labelled like the columns, and equals the All categories row' ($ptl.Success -and (@($ptv.Keys) -join ',') -eq 'Done,To go,Waiting,Free,Authoring,Ticketed,Building,Built,Blocked,Left to plan' -and (@($ptv.Values)[0..8] -join ',') -eq (@($ptr)[0..8] -join ',') -and $ptv['Left to plan'] -eq '2') "line: $(@($ptv.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ' ') row: $(@($ptr) -join ',')"
    $pDoc.groups[0].state = 'closed'
    $pDoc | ConvertTo-Json -Depth 20 | Set-Content (Join-Path $pr '.streams\tasks.json') -Encoding utf8
    $pj2 =(& "$S\Get-StreamStatus.ps1" -Repo $pr -Json | ConvertFrom-Json).leftToPlan
    $pst2 = @(& "$S\Get-StreamStatus.ps1" -Repo $pr)
    [void](& "$S\Build-StatusPage.ps1" -Repo $pr -Session status-p -Out $ppg -MirrorFile (Join-Path $Scratch 'no-mirror.txt'))
    $pph2 = Get-Content -Raw $ppg
    Case 'a closed group with a clause no row names makes left to plan unknown, with the reason, never a number' (-not $pj2.known -and $null -eq $pj2.total -and $pj2.reason -match 'closed group.*P1 1 of 3' -and ($pst2 | Where-Object { $_ -like 'tasks:*' }) -match '\| left to plan unknown: no row names every clause of a closed group' -and $pph2 -match '<a class="tile stall" href="#left-to-plan" title="[^"]*P1 1 of 3[^"]*"><b>\?</b>') "$($pj2 | ConvertTo-Json -Compress -Depth 6) | $($pst2 -join ' / ')"
    # A clause stream-adhoc built in a closed group has no row; its request file names it, and it counts as planned only
    # once a commit '<Id>: ...' is on HEAD (kit item IN-20261012012612-8ef6).
    New-Item -ItemType Directory -Path (Join-Path $pr '.streams\adhoc') -Force | Out-Null
    Set-Content (Join-Path $pr '.streams\adhoc\ADHOC-20261011-1.md') "# ADHOC-20261011-1`n- REQ-A-003 + AC-A-003 (FEAT-A-001)"
    $pj3 = (& "$S\Get-StreamStatus.ps1" -Repo $pr -Json | ConvertFrom-Json).leftToPlan
    git -C $pr commit -q --allow-empty -m 'ADHOC-20261011-1: adds AC-A-003'
    $pj4 = (& "$S\Get-StreamStatus.ps1" -Repo $pr -Json | ConvertFrom-Json).leftToPlan
    Case 'a clause named by a COMMITTED stream-adhoc request counts as planned; an uncommitted request names nothing' (-not $pj3.known -and $pj3.reason -match 'P1 1 of 3' -and $pj4.known -and [int]$pj4.total -eq 1 -and [int]$pj4.byGroup.P1.count -eq 0 -and (@($pj4.unnamedIds.none) -join ',') -eq 'AC-B-002') "before=$($pj3 | ConvertTo-Json -Compress -Depth 6) after=$($pj4 | ConvertTo-Json -Compress -Depth 6)"
    $pn = (& "$S\Get-StreamStatus.ps1" -Repo $lr -Json | ConvertFrom-Json).leftToPlan
    Case 'a repo with no requirements folder reads left to plan unknown' (-not $pn.known -and $pn.reason -match '^no requirements folder: ') ($pn | ConvertTo-Json -Compress -Depth 6)

    # E4 timed-role backoff: an idle streak doubles the wait up to 20 minutes; integrate never backs off; no streak
    # keeps the interval.
    $bw = @((Get-RunnerWait 'plan' 300 0), (Get-RunnerWait 'plan' 300 1), (Get-RunnerWait 'plan' 300 3), (Get-RunnerWait 'status' 900 1), (Get-RunnerWait 'integrate' 600 5), (Get-RunnerWait 'coordinator' 1200 2))
    Case 'E4: an idle streak doubles a timed role''s wait up to 20 min; integrate keeps its cadence' (($bw -join ',') -eq '300,600,1200,1200,600,1200') ($bw -join ',')

} catch {
    "FAIL harness: $_ at $($_.InvocationInfo.PositionMessage)`n$($_.ScriptStackTrace)"; $fails++
} finally {
    if (Test-Path $repo) { foreach ($w in @(git -C $repo worktree list --porcelain | Where-Object { $_ -like 'worktree *' } | Select-Object -Skip 1)) { git -C $repo worktree remove --force ($w.Substring(9)) 2>&1 | Out-Null } }
    Remove-Item Env:\STREAM_TEMP_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:\STREAM_SCRATCH_TOP_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:\STREAM_WORKTREE_ROOT -ErrorAction SilentlyContinue
Remove-Item Env:\STREAM_SCRATCH_ROOT -ErrorAction SilentlyContinue
    Remove-Item Env:\STREAM_REAP_QUIET_MINUTES -ErrorAction SilentlyContinue
    if ($null -ne $prevMachineConfig) { $env:AI_MACHINE_CONFIG = $prevMachineConfig } else { Remove-Item Env:\AI_MACHINE_CONFIG -ErrorAction SilentlyContinue }
    Remove-Item -Recurse -Force $Scratch -ErrorAction SilentlyContinue
}
"RESULT fails=$fails"
exit [int]($fails -gt 0)
