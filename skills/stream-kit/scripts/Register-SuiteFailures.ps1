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
#             file. It blocks this group's close until a Tier 3 retest passes it (Test-GroupClose.ps1).
#   later   : only a LATER group's row owns it. NO fix task now: the failure goes to
#             .streams\suites\known-failures.<later group>.json and becomes a fix task at that group's activation
#             (Activate-Group.ps1 step 2). It does not block this close.
#   unowned : no row owns it (a 'leg:<name>' crash, or a file in no write set). One stream-plan inbox item lists them:
#             the planner decides the earliest group whose feature the test covers. It blocks no close by itself.
#   exempt  : the owner ruled this test out of the group's close (.streams\suites\exempt.<run group>.json, written by
#             Test-GroupClose.ps1 -Exempt). No fix task, no known failure; it blocks nothing.
# Writes .streams\suites\runs\<run>.attribution.json { run, group, at, failures: [ { test, suite, file, ownerRow,
# ownerGroup, disposition, fixTask, flakyPromoted } ] } and one decisions.md line. Idempotent: a run that already has
# its attribution prints ALREADY-ATTRIBUTED. Prints one line per failure, then
# "ATTRIBUTED <run> fix <n> later <n> unowned <n> flaky <n>". -DryRun prints the lines and writes nothing.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [string] $Run,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$rd = Get-SuiteRunsDir $P
$attrPath = Join-Path $rd "$Run.attribution.json"
if (Test-Path -LiteralPath $attrPath) { "ALREADY-ATTRIBUTED $Run ($attrPath)"; exit 0 }
$rec = Read-JsonFile (Join-Path $rd "$Run.json")
$res = Read-JsonFile (Join-Path $rd "$Run.results.json")
if (-not $rec -or -not $res) { "NO-RUN $Run (record or results missing)"; exit 2 }
$group = [string]$rec['group']
$doc = Read-Tasks $P
$rank = Get-GroupRankMap $doc
$byId = @{}; foreach ($t in $doc.tasks) { $byId[[string]$t.id] = $t }
$runN = if ($Run -match '-(\d+)$') { $Matches[1] } else { '0' }

$failures = [Collections.Generic.List[object]]::new()
$fixByFile = [ordered]@{}     # file (or 'grader:<task>') -> @{ writeSet; why; tests }
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
        disposition = ''; fixTask = ''; flakyPromoted = [bool]$t['flakyPromoted'] }
    if ($exempt.ContainsKey($name)) {
        $f.disposition = 'exempt'
        "EXEMPT $name ($([string]$exempt[$name]['reason']))"
    } elseif (-not $owner -or -not $rank.ContainsKey($og) -or -not $rank.ContainsKey($group)) {
        $f.disposition = 'unowned'; $unowned.Add($name)
        "UNOWNED $name$(if ($file) { " ($file)" })"
    } elseif ($rank[$og] -gt $rank[$group]) {
        $f.disposition = 'later'
        if (-not $later.ContainsKey($og)) { $later[$og] = [Collections.Generic.List[object]]::new() }
        $ws = if ($name.StartsWith('grader:')) { @($owner.writeSet) } else { @($file) }
        $later[$og].Add([ordered]@{ test = $name; suite = [string]$t['suite']; file = $file; ownerRow = [string]$owner.id; writeSet = $ws
            run = $Run; head = [string]$rec['head']; at = Get-Now; fixTask = $null })
        "LATER $name owned by $($owner.id) ($og): known failure, fix task at $og activation"
    } else {
        $f.disposition = 'fix'
        $key = if ($name.StartsWith('grader:')) { $name } else { $file }
        if (-not $fixByFile.Contains($key)) {
            $ws = if ($name.StartsWith('grader:')) { @($owner.writeSet) } else { @($file) }
            $fixByFile[$key] = [ordered]@{ writeSet = $ws; why = @($owner.why); owner = [string]$owner.id; tests = [Collections.Generic.List[string]]::new() }
        }
        $fixByFile[$key].tests.Add($name)
        "FIX $name owned by $($owner.id) ($og)$(if ($f.flakyPromoted) { ' [flaky promoted]' })"
    }
    $failures.Add($f)
}

$fixTasks = [Collections.Generic.List[object]]::new()
$k = 1
foreach ($key in $fixByFile.Keys) {
    $e = $fixByFile[$key]
    $id = "$group.R$($runN)F$k"; while ($byId.ContainsKey($id)) { $k++; $id = "$group.R$($runN)F$k" }
    $k++
    $tests = @($e.tests)
    $fixTasks.Add([ordered]@{ id = $id; group = $group; title = "Fix Tier 2 failure$(if ($tests.Count -gt 1) { 's' }) in ${key}: $(($tests | Select-Object -First 3) -join '; ')$(if ($tests.Count -gt 3) { " (+$($tests.Count - 3))" })"
        why = $(if (@($e.why).Count) { @($e.why) } else { @('TIER2-FAILURE') }); kind = 'code'; origin = 'integration'; writeSet = @($e.writeSet); dependsOn = @()
        estMinutes = 45; estBasis = 'Tier 2 failure fix, sized as a typical fix task'
        note = "Tier 2 run $Run at $($rec['head']): $($tests -join '; ') (owner row $($e.owner))" })
    foreach ($f in $failures) { if ($f.disposition -eq 'fix' -and $tests -contains $f.test) { $f.fixTask = $id } }
}

$summary = "ATTRIBUTED $Run fix $(@($failures | Where-Object { $_.disposition -eq 'fix' }).Count) later $(@($failures | Where-Object { $_.disposition -eq 'later' }).Count) unowned $($unowned.Count) flaky $flaky$(if ($exempt.Count) { " exempt $(@($failures | Where-Object { $_.disposition -eq 'exempt' }).Count)" })"
if ($DryRun) { "DRY-RUN $summary"; exit 0 }

if ($fixTasks.Count) {
    $ff = Join-Path $rd "$Run.fixes.json"
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
    $ask = "Tier 2 run $Run ($group) has $($unowned.Count) failure(s) no row owns: $(($unowned | Select-Object -First 10) -join '; '). Decide the earliest group whose feature each covers and add the fix task there (stream-integrate B.3)."
    & "$PSScriptRoot\Send-InboxItem.ps1" -Repo $Repo -To stream-plan -From $Session -Kind request -Ask $ask -Evidence $attrPath | Out-Null
}
Write-JsonFile $attrPath ([ordered]@{ run = $Run; group = $group; at = Get-Now; failures = @($failures) })
Add-Decision $P $Session $summary
$summary
exit 0
