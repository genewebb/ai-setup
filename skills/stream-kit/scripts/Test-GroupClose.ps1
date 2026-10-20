# The group close rule (2026-10-05 priority-focus-design 3.3; replaces stream-integrate step B.6 "green, or blocked
# after three full runs"). Script only, no model tokens.
#   Test-GroupClose.ps1 -Repo <repo> [-Group <G>] [-Session <id>] [-DryRun]
# -Group defaults to the focus group. The group set is lib\Activation.ps1 Get-GroupSet (rows whose EFFECTIVE group is
# <G>). A group may close when ALL of these hold:
#   1. every non-fix (origin not integration) code/docs/mockup row of the set is integrated or done;
#   2. the latest finished Tier 2 run of <G> started AFTER the last of those rows integrated, and is attributed
#      (Register-SuiteFailures.ps1 wrote its attribution);
#   3. every row of the set integrated after that run started is a fix row (origin integration) and a Tier 3 retest of
#      that run started after it integrated and passed;
#   4. every failure of that run attributed 'fix' (owned by <G> or an earlier group) passed in a Tier 3 retest of it,
#      and no fix row of the set is still open;
#   5. every gate row of <G> is done (passed);
#   6. no leg of that run crashed: a 'leg:<name>' result (a leg that left no results) means the run gave that leg no
#      coverage at all, so it needs a new Tier 2 run (LEG-CRASHED), not a planner item.
#   7. no perf leg of that run was left NOT-MEASURED (the host never quieted, lib\Suites.ps1 Wait-QuietHost): an
#      unmeasured timing test is no pass, so it needs a new Tier 2 run on a quiet host (NOT-MEASURED), unless the owner
#      exempted the leg (-Exempt 'leg:<name>').
# A late gate-fail fix (Add-Tasks REOPENED) therefore needs a Tier 3 retest, not a new Tier 2 run.
# BLOCKED: the same test failed three Tier 3 retests of the run since the group's unblockedAt. Invoke-Retest.ps1 runs a
# failure only after its current fix attempt lands, so these are three failed fix attempts. The group goes to
# 'blocked' (its state before is kept in blockedFrom) and the test is listed once in owner\questions.md (tag
# CLOSE-BLOCKED); -DryRun reports it and writes nothing.
# -Unblock (the owner, after deciding to try again): restores the group's state from blockedFrom, sets unblockedAt (the
# strikes count again from zero) and files the next fix attempt for each blocked test. Prints UNBLOCKED <G> and one
# REFIX line per test, exit 0. To ACCEPT a failure instead, move it out of the run's attribution (disposition 'later'
# or 'unowned') before unblocking, or exempt it.
# -Exempt <fix row id | test name> -Reason '<the owner's ruling>' (the owner, or a session relaying a recorded owner
# ruling): writes every 'fix' failure of the latest Tier 2 run whose fixTask, or test name, is that value into
# .streams\suites\exempt.<G>.json (lib\Suites.ps1 Get-SuiteExemptions) and logs it in decisions.md. An exempted failure
# no longer counts for rule 4, is never retested, and a later run attributes it 'exempt' with no fix task. Prints one
# EXEMPTED line per test (exit 0), or NO-MATCH (exit 2). The value may also name a perf leg the latest Tier 2 run left
# NOT-MEASURED ('leg:<name>', kit item IN-20261011013141-4283: owner 2026-10-11, a speed-benchmark-only miss is approved
# and a performance row goes at the end of the board): rule 7 then skips that leg for this and later runs of the group.
# A failure whose fix row was RETIRED as environment-only needs no
# exemption: Invoke-Retest.ps1 -Mode fix re-runs it once after the retirement, and a pass there clears it.
# -Exempt <exact test name> -Pending -Reason '<ruling>' (kit item IN-20261020152530-aead) records the exemption BEFORE
# any run has failed the test (the owner rules a test out ahead of a Tier 2 run, e.g. one that needs files this host
# lacks): when no finished run's 'fix' failure or NOT-MEASURED leg matches, it writes { test, fixTask '', run 'pending',
# reason, by, at } and prints EXEMPTED-PENDING <G> <test> (exit 0); a match takes the normal path. A value shaped like
# a row id (<G>.R<n>F.., <G>.KF.., <G>.T..) is REFUSED (exit 2): a pending exemption needs the exact test name.
# Prints CLOSE-OK <G> ... (exit 0), one CLOSE-REFUSED <reason> line per unmet rule (exit 1), or
# CLOSE-BLOCKED <G> <test> lines (exit 3). Closing itself (rows done, group closed) is Close-Group.ps1 (stream-integrate step C).
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string] $Group = '',
    [string] $Session = 'integrate',
    [switch] $DryRun,
    [switch] $Unblock,
    [string] $Exempt = '',
    [string] $Reason = '',
    [switch] $Pending
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
. "$PSScriptRoot\lib\Activation.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$doc = Read-Tasks $P
if (-not $Group) { $Group = Get-FocusGroup $doc }
if (-not $Group) { 'NO-FOCUS every group is closed'; exit 0 }
$rd = Get-SuiteRunsDir $P
$set = Get-GroupSet $doc $Group
$rows = @($doc.tasks | Where-Object { $set.Contains([string]$_.id) })
$groupRow = @($doc.groups | Where-Object { [string]$_.id -eq $Group }) | Select-Object -First 1
function Get-IntegratedAt($t) {
    $h = @($t.history | Where-Object { $_ -and $_.to -eq 'integrated' -and $_.at } | Select-Object -Last 1)
    if ($h.Count) { ConvertTo-UtcTime ([string]$h[0].at) } else { $null }
}
$exempted = Get-SuiteExemptions $P $Group
if ($Exempt) {
    if (-not $Reason.Trim()) { 'REFUSED -Exempt needs -Reason naming the owner ruling'; exit 2 }
    if ($Pending -and $Exempt -match '^[A-Za-z]+\d+\.(R\d+F|KF|T)') { "REFUSED -Pending '$Exempt' looks like a row id: a pending exemption needs the exact test name"; exit 2 }
    $run0 = @(Get-SuiteRunRecords $P $Group '2' | Where-Object { $_['status'] -eq 'done' }) | Select-Object -Last 1
    $attr0 = if ($run0) { Read-JsonFile (Join-Path $rd "$($run0['id']).attribution.json") } else { $null }
    $hit = @(@(if ($attr0) { $attr0['failures'] }) | Where-Object { $_ -and $_['disposition'] -eq 'fix' -and ([string]$_['fixTask'] -eq $Exempt -or [string]$_['test'] -eq $Exempt) })
    if (-not $hit.Count -and $run0) {
        # A perf leg the host never quieted for has no failure to attribute, only a 'not-measured' leg row (rule 7).
        $res0 = Read-JsonFile (Join-Path $rd "$($run0['id']).results.json")
        $hit = @(@(if ($res0) { $res0['tests'] }) | Where-Object { $_ -and $_['outcome'] -eq 'not-measured' -and [string]$_['test'] -eq $Exempt } |
            ForEach-Object { @{ test = [string]$_['test']; fixTask = '' } })
    }
    if (-not $hit.Count -and $Pending) {
        if ($exempted.ContainsKey($Exempt)) { "EXEMPTED-PENDING $Group $Exempt (already)"; exit 0 }
        $pPath = Get-SuiteExemptPath $P $Group
        $pHave = @(if (Test-Path -LiteralPath $pPath) { @(Get-Content -Raw -LiteralPath $pPath | ConvertFrom-Json -AsHashtable -DateKind String) | Where-Object { $_ -is [Collections.IDictionary] } })
        if (-not $DryRun) {
            Write-JsonFile $pPath @(@($pHave) + @([ordered]@{ test = $Exempt; fixTask = ''; run = 'pending'; reason = $Reason.Trim(); by = $Session; at = Get-Now }))
            Add-Decision $P $Session "EXEMPTED-PENDING $Group $Exempt (no run has failed it yet): $($Reason.Trim())"
        }
        "EXEMPTED-PENDING $Group $Exempt"
        exit 0
    }
    if (-not $hit.Count) { "NO-MATCH no 'fix' failure or NOT-MEASURED leg of $(if ($run0) { $run0['id'] } else { "$Group (no finished Tier 2 run)" }) has fixTask or test '$Exempt'"; exit 2 }
    $path = Get-SuiteExemptPath $P $Group
    $have = @(if (Test-Path -LiteralPath $path) { @(Get-Content -Raw -LiteralPath $path | ConvertFrom-Json -AsHashtable -DateKind String) | Where-Object { $_ -is [Collections.IDictionary] } })
    $add = @($hit | Where-Object { -not $exempted.ContainsKey([string]$_['test']) } | ForEach-Object {
        [ordered]@{ test = [string]$_['test']; fixTask = [string]$_['fixTask']; run = [string]$run0['id']; reason = $Reason.Trim(); by = $Session; at = Get-Now } })
    if (-not $DryRun -and $add.Count) {
        Write-JsonFile $path @(@($have) + $add)
        Add-Decision $P $Session "EXEMPTED $Group $($add.Count) failure(s) of $($run0['id']) ($Exempt): $($Reason.Trim())"
    }
    foreach ($h in $hit) { "EXEMPTED $Group $($h['test'])$(if ($exempted.ContainsKey([string]$h['test'])) { ' (already)' })" }
    exit 0
}
$isFix = { param($t) $t.Contains('origin') -and [string]$t['origin'] -eq 'integration' -and $t.kind -ne 'integration' }
$refused = [Collections.Generic.List[string]]::new()

# 1. non-fix rows landed
$work = @($rows | Where-Object { $_.kind -in $script:BuildKinds -and -not (& $isFix $_) })
$open = @($work | Where-Object { $_.state -notin @('integrated', 'done') })
if ($open.Count) { $refused.Add("OPEN-ROWS $($open.Count) row(s) not integrated: $((@($open | Select-Object -First 8 | ForEach-Object id)) -join ', ')") }
$lastPatch = [datetime]::MinValue
foreach ($t in $work) { $at = Get-IntegratedAt $t; if ($at -and $at -gt $lastPatch) { $lastPatch = $at } }

# 2. a Tier 2 run after the last non-fix patch
$run = @(Get-SuiteRunRecords $P $Group '2' | Where-Object { $_['status'] -eq 'done' }) | Select-Object -Last 1
$runStart = $null; $attr = $null; $retests = @()
if (-not $run) { $refused.Add("NO-TIER2 no finished Tier 2 run for $Group") }
else {
    $runStart = ConvertTo-UtcTime $run['startedAt']
    if ($runStart -le $lastPatch) { $refused.Add("TIER2-STALE $($run['id']) started $($run['startedAt']), before the last non-fix patch at $($lastPatch.ToString('yyyy-MM-ddTHH:mm:ssZ'))") }
    $attr = Read-JsonFile (Join-Path $rd "$($run['id']).attribution.json")
    if (-not $attr) { $refused.Add("NOT-ATTRIBUTED $($run['id']) (Register-SuiteFailures.ps1 has not run)") }
    $retests = @(Get-SuiteRunRecords $P $Group '3' | Where-Object { $_['baseRun'] -eq $run['id'] -and $_['status'] -eq 'done' })
    $resAll = Read-JsonFile (Join-Path $rd "$($run['id']).results.json")
    $crashed = @(@($resAll['tests']) | Where-Object { $_ -and ([string]$_['test']).StartsWith('leg:') -and $_['outcome'] -eq 'failed' } | ForEach-Object { [string]$_['test'] })
    if ($crashed.Count) { $refused.Add("LEG-CRASHED $($run['id']) left no results for $($crashed -join ', '): start a new Tier 2 run once the leg runs") }
    $unmeasured = @(@($resAll['tests']) | Where-Object { $_ -and $_['outcome'] -eq 'not-measured' -and -not $exempted.ContainsKey([string]$_['test']) } | ForEach-Object { [string]$_['test'] })
    if ($unmeasured.Count) { $refused.Add("NOT-MEASURED $($run['id']) never ran $($unmeasured -join ', '): the host was not quiet; start a new Tier 2 run when it can be") }
}

# 3. patches after the run: fix rows with a passing Tier 3 after them
if ($runStart) {
    foreach ($t in $rows) {
        if ($t.kind -notin $script:BuildKinds) { continue }
        $at = Get-IntegratedAt $t
        if (-not $at -or $at -le $runStart) { continue }
        if (-not (& $isFix $t)) { $refused.Add("NON-FIX-AFTER-RUN $($t.id) integrated after $($run['id']) started; it needs a new Tier 2 run"); continue }
        $ok = @($retests | Where-Object { $_['outcome'] -eq 'pass' -and (ConvertTo-UtcTime $_['startedAt']) -gt $at }).Count
        if (-not $ok) { $refused.Add("NO-TIER3 $($t.id) integrated after $($run['id']) with no passing Tier 3 retest after it") }
    }
}

# 4. every 'fix' failure retested green; no fix row open
$blocked = [Collections.Generic.List[string]]::new()
if ($attr) {
    $unpassed = [Collections.Generic.List[string]]::new()
    # A shared run (record 'groups') files each fix in one covered group, attribution 'fixGroup'; only this group's count.
    foreach ($f in @($attr['failures'] | Where-Object { $_ -and $_['disposition'] -eq 'fix' -and (-not $_['fixGroup'] -or [string]$_['fixGroup'] -eq $Group) })) {
        $name = [string]$f['test']
        if ($exempted.ContainsKey($name)) { continue }
        $ran = @($retests | Where-Object { @($_['tests']) -contains $name })
        $passed = @($ran | Where-Object { $_['perTest'] -is [Collections.IDictionary] -and [string]$_['perTest'][$name] -eq 'passed' }).Count
        if ($passed) { continue }
        $unpassed.Add($name)
        if (@(Get-StrikeRetests $P $Group ([string]$run['id']) $name $groupRow).Count -ge 3) { $blocked.Add($name) }
    }
    if ($unpassed.Count) { $refused.Add("UNRETESTED $($unpassed.Count) Tier 2 failure(s) of $($run['id']) without a passing Tier 3: $((@($unpassed | Select-Object -First 5)) -join '; ')") }
}
$openFix = @($rows | Where-Object { (& $isFix $_) -and $_.state -notin @('integrated', 'done') })
if ($openFix.Count) { $refused.Add("OPEN-FIX $((@($openFix | ForEach-Object id)) -join ', ')") }

# 5. gates
$gates = @($doc.tasks | Where-Object { [string]$_.group -eq $Group -and $_.kind -eq 'gate' -and $_.state -ne 'done' })
if ($gates.Count) { $refused.Add("GATES-OPEN $((@($gates | ForEach-Object id)) -join ', ')") }

if ($Unblock) {
    $was = if ($groupRow -and $groupRow.Contains('blockedFrom') -and $groupRow['blockedFrom']) { [string]$groupRow['blockedFrom'] } else { 'released' }
    [void](Invoke-TasksLocked $P $Session { param($d) foreach ($g in @($d.groups | Where-Object { [string]$_.id -eq $Group })) { if ($g.state -eq 'blocked') { $g.state = $was }; $g['unblockedAt'] = Get-Now; [void]$g.Remove('blockedFrom') }; $d })
    Add-Decision $P $Session "UNBLOCKED $Group (state $was; Tier 3 strikes count again from now)"
    "UNBLOCKED $Group state $was"
    foreach ($b in $blocked) { $nid = Add-FixAttempt $P $Repo $Session ([string]$run['id']) $b $PSScriptRoot; if ($nid) { "REFIX $b $nid" } }
    exit 0
}
if ($blocked.Count) {
    foreach ($b in $blocked) { "CLOSE-BLOCKED $Group $b failed 3 consecutive Tier 3 retests of $($run['id'])" }
    if (-not $DryRun) {
        [void](Invoke-TasksLocked $P $Session { param($d) foreach ($g in @($d.groups | Where-Object { [string]$_.id -eq $Group -and $_.state -notin @('closed', 'blocked') })) { $g['blockedFrom'] = [string]$g.state; $g.state = 'blocked' }; $d })
        $q = if (Test-Path -LiteralPath $P.Questions) { [IO.File]::ReadAllText($P.Questions) } else { '' }
        $lines = @($blocked | Where-Object { -not $q.Contains("CLOSE-BLOCKED $Group $_") } | ForEach-Object { "- $(Format-LocalStamp) CLOSE-BLOCKED $Group $_ : failed 3 Tier 3 fix attempts of $($run['id']); $Group is blocked until you decide: try again with Test-GroupClose.ps1 -Repo <repo> -Group $Group -Unblock (it files the next fix attempt), or accept the failure by moving it out of the run's attribution first." })
        if ($lines.Count) { if (-not (Test-Path $P.Owner)) { New-Item -ItemType Directory -Path $P.Owner -Force | Out-Null }; [IO.File]::AppendAllText($P.Questions, (($lines -join "`n") + "`n")) }
        Add-Decision $P $Session "CLOSE-BLOCKED $Group : $($blocked -join '; ')"
    }
    exit 3
}
if ($refused.Count) { foreach ($r in $refused) { "CLOSE-REFUSED $r" }; exit 1 }
"CLOSE-OK $Group tier2 $($run['id']) retests $($retests.Count)$(if ($exempted.Count) { " exempt $($exempted.Count)" })"
exit 0
