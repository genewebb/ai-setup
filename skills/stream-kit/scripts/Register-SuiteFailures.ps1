# Attributes the failures of one Tier 2 run (2026-10-05 priority-focus-design 3.3). Script only, no model tokens.
#   Register-SuiteFailures.ps1 -Repo <repo> -Session <id> -Run <run> [-DryRun]
# Reads .streams\suites\runs\<run>.results.json AFTER the flaky screen (Invoke-Retest.ps1 -Mode flaky has turned a
# test that passed on the same-snapshot re-run into outcome 'flaky'; a promoted flaky test stays 'failed'). For each
# failed test it finds the owning row the way stream-integrate step B.3 always did: the row on the WHOLE board whose
# write set holds the failing test's file (lib\Suites.ps1 Find-OwnerRow); a 'grader:<task>' failure is owned by <task>.
# Then, by the owner's group against the run's group (groups close in board order, owner ruling IN-20261001193348-5979):
#   fix     : this group or an EARLIER one owns it. A fix task in the run's group (Add-Tasks.ps1 -Role integrate), one
#             per file: failures that share a file are one task. Write set = that file (a grader failure: the graded
#             row's write set); the builder widens it with Update-Task.ps1 -AddWriteSet when the fix needs a product
#             file. It blocks this group's close until a Tier 3 retest passes it (Test-GroupClose.ps1). When the owner
#             is itself a fix row that landed after the run started, no new task: the owner is the fix task
#             (landedAfterRun), and its landing is what the Tier 3 retest checks.
#   later   : only a LATER group's row owns it. NO fix task now: the failure goes to
#             .streams\suites\known-failures.<later group>.json and becomes a fix task at that group's activation
#             (Activate-Group.ps1 step 2). It does not block this close.
#   unowned : no row owns it (a 'leg:<name>' crash, or a file in no write set). One stream-plan inbox item lists them:
#             the planner decides the earliest group whose feature the test covers. It blocks no close by itself.
#   exempt  : the owner ruled this test out of the group's close (.streams\suites\exempt.<run group>.json, written by
#             Test-GroupClose.ps1 -Exempt). No fix task, no known failure; it blocks nothing.
# Writes .streams\suites\runs\<run>.attribution.json { run, group, at, failures: [ { test, suite, file, ownerRow,
# ownerGroup, disposition, fixTask, flakyPromoted } ] } and one decisions.md line. Idempotent: a run that already has
# its attribution prints ALREADY-ATTRIBUTED. SCREEN-PENDING (exit 3, nothing written) while the run's flaky screen still runs. Prints one line per failure, then
# "ATTRIBUTED <run> fix <n> later <n> unowned <n> flaky <n>". -DryRun prints the lines and writes nothing.
# -Retest <id> (kit item IN-20261020141623-c8a3) attributes a Tier 3 fix retest's sweep regressions instead: only the
# record's sweepFailures, read from <id>.sweep.results.json, against its base run's group, groups and head. Fix ids
# continue the base run's numbering (<fixGroup>.R<base n>F<k>, taken ids skipped); it writes <id>.attribution.json,
# never the base run's, so the close rule (which reads the base run's attribution) is unchanged: OPEN-FIX holds the
# close on the new rows. -Run may be omitted with -Retest.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [string] $Run,
    [string] $Retest,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$rd = Get-SuiteRunsDir $P
$rt = $null
if ($Retest) {
    $rt = Read-JsonFile (Join-Path $rd "$Retest.json")
    if (-not $rt -or [string]$rt['tier'] -ne '3') { "NO-RUN $Retest (no Tier 3 retest record)"; exit 2 }
    if (-not $Run) { $Run = [string]$rt['baseRun'] }
} elseif (-not $Run) { "NO-RUN (name -Run or -Retest)"; exit 2 }
$label = if ($Retest) { $Retest } else { $Run }
$attrPath = Join-Path $rd "$label.attribution.json"
if (Test-Path -LiteralPath $attrPath) { "ALREADY-ATTRIBUTED $label ($attrPath)"; exit 0 }
$rec = Read-JsonFile (Join-Path $rd "$Run.json")
$res = if ($Retest) { Read-JsonFile (Join-Path $rd "$Retest.sweep.results.json") } else { Read-JsonFile (Join-Path $rd "$Run.results.json") }
if (-not $rec -or -not $res) { "NO-RUN $label (record or results missing)"; exit 2 }
if ($Retest) {
    # Only the sweep regressions Invoke-Retest.ps1 recorded: a test that also failed in the base run is attributed there.
    $sw = @($rt['sweepFailures'] | Where-Object { $_ } | ForEach-Object { [string]$_ })
    $res = @{ tests = @(@($res['tests']) | Where-Object { $_ -and $_['outcome'] -eq 'failed' -and $sw -contains [string]$_['test'] }) }
} elseif (Test-SuiteScreenPending $rec) { "SCREEN-PENDING $Run (its flaky screen is still running; Invoke-SuiteLegs.ps1 attributes the run after it)"; exit 3 }
$group = [string]$rec['group']
$doc = Read-Tasks $P
$rank = Get-GroupRankMap $doc
$byId = @{}; foreach ($t in $doc.tasks) { $byId[[string]$t.id] = $t }
# A run that counts for several groups (record 'groups', Start-SuiteRun.ps1; kit item IN-20261019130625-ee1d) files each
# fix in the EARLIEST covered group at or after the owner's group, the first close it would otherwise slip past.
$covered = @(Get-SuiteRunGroups $rec | Where-Object { $rank.ContainsKey($_) } | Sort-Object { $rank[$_] })
function Get-FixGroup([string] $og) { @($covered | Where-Object { $rank[$_] -ge $rank[$og] }) | Select-Object -First 1 }
$exemptBy = @{}; foreach ($cg in $covered) { $exemptBy[$cg] = Get-SuiteExemptions $P $cg }
$runN = if ($Run -match '-(\d+)$') { $Matches[1] } else { '0' }
# When the graded code was read: the retest's start for a sweep, else the run's.
$runAt = try { ConvertTo-UtcTime ([string]$(if ($Retest) { $rt['startedAt'] } else { $rec['startedAt'] })) } catch { $null }

$failures = [Collections.Generic.List[object]]::new()
$fixByFile = [ordered]@{}     # fix group + file (or 'grader:<task>') -> @{ group; key; writeSet; why; tests }
$later = @{}                  # later group -> list of known-failure entries
$unowned = [Collections.Generic.List[string]]::new()
$flaky = @($res['tests'] | Where-Object { $_ -and $_['outcome'] -eq 'flaky' }).Count
$exempt = Get-SuiteExemptions $P $group
foreach ($t in @($res['tests'] | Where-Object { $_ -and $_['outcome'] -eq 'failed' })) {
    $name = [string]$t['test']; $file = [string]$t['file']
    $owner = $null
    if ($name.StartsWith('grader:')) { $owner = $byId[$name.Substring(7)] }
    elseif (-not $name.StartsWith('leg:')) { $owner = Find-OwnerRow $doc $file }
    $og = if ($owner) { [string]$owner.group } else { '' }
    $f = [ordered]@{ test = $name; suite = [string]$t['suite']; file = $file; ownerRow = $(if ($owner) { [string]$owner.id } else { '' }); ownerGroup = $og
        disposition = ''; fixTask = ''; fixGroup = ''; flakyPromoted = [bool]$t['flakyPromoted'] }
    $fg = if ($owner -and $rank.ContainsKey($og)) { Get-FixGroup $og } else { $null }
    if ($exempt.ContainsKey($name) -or ($fg -and $exemptBy[$fg].ContainsKey($name))) {
        $f.disposition = 'exempt'
        # The exemption may sit in the fix group's file only (a shared run, kit item IN-20261020202159-4b5e).
        $ex = if ($exempt.ContainsKey($name)) { $exempt[$name] } else { $exemptBy[$fg][$name] }
        "EXEMPT $name ($([string]$ex['reason']))"
    } elseif (-not $owner -or -not $rank.ContainsKey($og) -or -not $rank.ContainsKey($group)) {
        $f.disposition = 'unowned'; $unowned.Add($name)
        "UNOWNED $name$(if ($file) { " ($file)" })"
    } elseif (-not $fg) {
        $f.disposition = 'later'
        if (-not $later.ContainsKey($og)) { $later[$og] = [Collections.Generic.List[object]]::new() }
        $ws = if ($name.StartsWith('grader:')) { @($owner.writeSet) } else { @($file) }
        $later[$og].Add([ordered]@{ test = $name; suite = [string]$t['suite']; file = $file; ownerRow = [string]$owner.id; writeSet = $ws
            run = $Run; head = [string]$rec['head']; at = Get-Now; fixTask = $null })
        "LATER $name owned by $($owner.id) ($og): known failure, fix task at $og activation"
    } elseif ([string]$owner['origin'] -eq 'integration' -and $runAt -and ($la = Get-FixLandedAt $owner) -and $la -gt $runAt) {
        # The owner is a fix row that landed AFTER this run started, so the run graded the code before it: a new row
        # would duplicate landed work and could never show a builder RED (kit item IN-20261020203944-8aeb, G13.R6F2).
        # The failure stays 'fix' with the owner as its fix task, so the Tier 3 retest re-runs it once and a pass clears it.
        $f.disposition = 'fix'; $f.fixGroup = $fg; $f.fixTask = [string]$owner.id; $f['landedAfterRun'] = $true
        "FIX $name owned by $($owner.id) ($og): landed after the run, retest on it"
    } else {
        $f.disposition = 'fix'; $f.fixGroup = $fg
        $key = if ($name.StartsWith('grader:')) { $name } else { $file }
        $slot = "$fg|$key"
        if (-not $fixByFile.Contains($slot)) {
            $ws = if ($name.StartsWith('grader:')) { @($owner.writeSet) } else { @($file) }
            $fixByFile[$slot] = [ordered]@{ group = $fg; key = $key; writeSet = $ws; why = @($owner.why); owner = [string]$owner.id; tests = [Collections.Generic.List[string]]::new() }
        }
        $fixByFile[$slot].tests.Add($name)
        "FIX $name owned by $($owner.id) ($og)$(if ($f.flakyPromoted) { ' [flaky promoted]' })"
    }
    $failures.Add($f)
}

$fixTasks = [Collections.Generic.List[object]]::new()
$kBy = @{}                    # fix group -> next F number, so each group's fixes count from F1
foreach ($slot in $fixByFile.Keys) {
    $e = $fixByFile[$slot]; $key = $e.key; $fg = $e.group
    $k = if ($kBy.ContainsKey($fg)) { $kBy[$fg] } else { 1 }
    $id = "$fg.R$($runN)F$k"; while ($byId.ContainsKey($id)) { $k++; $id = "$fg.R$($runN)F$k" }
    $kBy[$fg] = $k + 1
    $tests = @($e.tests)
    $fixTasks.Add([ordered]@{ id = $id; group = $fg; title = "Fix $(if ($Retest) { "Tier 3 sweep ($Retest)" } else { 'Tier 2' }) failure$(if ($tests.Count -gt 1) { 's' }) in ${key}: $(($tests | Select-Object -First 3) -join '; ')$(if ($tests.Count -gt 3) { " (+$($tests.Count - 3))" })"
        why = $(if (@($e.why).Count) { @($e.why) } else { @('TIER2-FAILURE') }); kind = 'code'; origin = 'integration'; writeSet = @($e.writeSet); dependsOn = @()
        estMinutes = 45; estBasis = 'Tier 2 failure fix, sized as a typical fix task'
        note = "$(if ($Retest) { "Tier 3 retest $Retest sweep, base run" } else { 'Tier 2 run' }) $Run at $($rec['head']): $($tests -join '; ') (owner row $($e.owner))" })
    foreach ($f in $failures) { if ($f.disposition -eq 'fix' -and $f.fixGroup -eq $fg -and $tests -contains $f.test) { $f.fixTask = $id } }
}

$summary = "ATTRIBUTED $label fix $(@($failures | Where-Object { $_.disposition -eq 'fix' }).Count) later $(@($failures | Where-Object { $_.disposition -eq 'later' }).Count) unowned $($unowned.Count) flaky $flaky$(if ($exempt.Count -or @($failures | Where-Object { $_.disposition -eq 'exempt' }).Count) { " exempt $(@($failures | Where-Object { $_.disposition -eq 'exempt' }).Count)" })"
if ($DryRun) { "DRY-RUN $summary"; exit 0 }

if ($fixTasks.Count) {
    $ff = Join-Path $rd "$label.fixes.json"
    Write-JsonFile $ff ([ordered]@{ groups = @(); tasks = @($fixTasks) })
    $out = @(& "$PSScriptRoot\Add-Tasks.ps1" -Repo $Repo -Role integrate -Session $Session -File $ff)
    $code = $LASTEXITCODE
    $out | ForEach-Object { "  $_" }
    if ($code) { "ADD-FAILED exit $code (attribution not written; fix the refusal and run again)"; exit 3 }
    # A fix that joined an unlanded row is carried by that row.
    foreach ($l in $out) {
        if ($l -match '^JOINED (\S+) into (\S+)') { $a = $Matches[1]; $b = $Matches[2]; foreach ($f in $failures) { if ($f.fixTask -eq $a) { $f.fixTask = $b } } }
    }
}
foreach ($g in $later.Keys) {
    $kp = Join-Path $P.Suites "known-failures.$g.json"
    $have = @(); if (Test-Path -LiteralPath $kp) { $have = @(Get-Content -Raw -LiteralPath $kp | ConvertFrom-Json -AsHashtable -DateKind String) }
    $names = @($have | Where-Object { $_ -is [Collections.IDictionary] -and -not $_['fixTask'] } | ForEach-Object { [string]$_['test'] })
    $add = @($later[$g] | Where-Object { $names -notcontains $_.test })
    Write-JsonFile $kp @(@($have) + $add)
}
if ($unowned.Count) {
    $ask = "$(if ($Retest) { "Tier 3 retest $Retest sweep (base $Run)" } else { "Tier 2 run $Run" }) ($group) has $($unowned.Count) failure(s) no row owns: $(($unowned | Select-Object -First 10) -join '; '). Decide the earliest group whose feature each covers and add the fix task there (stream-integrate B.3)."
    & "$PSScriptRoot\Send-InboxItem.ps1" -Repo $Repo -To stream-plan -From $Session -Kind request -Ask $ask -Evidence $attrPath | Out-Null
}
Write-JsonFile $attrPath ([ordered]@{ run = $label; baseRun = $Run; group = $group; groups = @($covered); at = Get-Now; failures = @($failures) })
Add-Decision $P $Session $summary
$summary
exit 0
