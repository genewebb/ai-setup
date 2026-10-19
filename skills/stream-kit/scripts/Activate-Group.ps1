# Activates a group when it becomes the focus group (2026-10-05 priority-focus-design 3.2). Script only, no model tokens.
#   Activate-Group.ps1 -Repo <repo> -Session <id> -Group <G> [-DryRun] [-Force]
# The integrator runs it right after it closes a group (stream-integrate step C); the coordinator runs it when the focus
# group has no activation record. Idempotent: a group with .streams\plans\<G>.activation.json prints ALREADY-ACTIVE
# and changes nothing, unless -Force (a re-check after a long pause).
# Why: G3-G6 were all released on 2026-09-28 and ticketed against earlier-group code that was still moving, so G4 saw
# 203 ticket events for 119 rows. A ticket written before its files changed on main is stale; activation finds those
# rows and sends them back to an author, before any builder spends an hour on them.
# Steps, in order:
#  1. FRESHNESS, per ticketed row of the group set (lib\Activation.ps1 Get-GroupSet: the rows whose EFFECTIVE group is
#     <G>): ticketedAt = the latest history entry with to = ticketed; since = git rev-list -1 --before=<ticketedAt>
#     HEAD (the integrator commits every patch, so main's history is the record of change); changed = git diff
#     --name-only <since> HEAD, intersected with the row's write set and its dependsOn rows' write sets. Tickets are
#     prose; the paths they mention are not parsed. A hit goes back to planned through Revise-Task.ps1 -Release planned
#     with a note "STALE: <files> since <sha> by <rows>" (Revise-Task.ps1 writes it after "plan revise: ... -- "; the author refresh mode, Build-PriorityPage.ps1 and Build-CostPage.ps1 match "STALE: " there). A row
#     with a live claim is skipped and reported (SKIP-CLAIMED). A row with no ticket time is reported (NO-TICKET-TIME).
#  2. KNOWN FAILURES: each entry of .streams\suites\known-failures.<G>.json that has no fixTask yet becomes a fix task
#     (Add-Tasks.ps1 -Role integrate, id <G>.KF<n>), and the entry records its id.
#  3. OWNER GATES UP FRONT: every gate row of <G> that is not done gets one line in owner\questions.md (once per gate).
#  4. Writes the activation record (stale, skipped, gates, known failures, milestones) and one decisions.md line.
# Prints one line per action, then "ACTIVATED <G> stale <n> skipped <n> gates <n> fixes <n>". -DryRun prints the same
# lines and writes nothing. Exit 2 = unknown group.
#  -FreshnessOnly (2026-10-18 dependency review, finding F2): step 1 alone, run by the status tick EVERY cycle for each
#     focus group that is already active. Activation ran once per group, so the 174 write-set widenings and every
#     integration commit after it drifted tickets with no re-check until a planner noticed by hand. The continuous
#     check judges a row by its OWN write set only, not its dependencies': a dependency landing its own files is the
#     expected order of work and the stacked base carries it into the builder's tree, while another row's commit into
#     MY files is real staleness. Prints "FRESHNESS <G> stale <n> skipped <n>", writes no activation record, logs a
#     decision line only when a row moved. It needs no activation record and never prints ALREADY-ACTIVE.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [string] $Group,
    [switch] $DryRun,
    [switch] $Force,
    [switch] $FreshnessOnly
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Activation.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$doc = Read-Tasks $P
if (-not @($doc.groups | Where-Object { [string]$_.id -eq $Group }).Count) { "REFUSED unknown group $Group"; exit 2 }
$actPath = Get-ActivationPath $P $Group
if ((Test-Path -LiteralPath $actPath) -and -not $Force -and -not $FreshnessOnly) { "ALREADY-ACTIVE $Group ($actPath)"; exit 0 }

$set = Get-GroupSet $doc $Group
$byId = @{}; foreach ($t in $doc.tasks) { $byId[[string]$t.id] = $t }
$head = (Invoke-Git $Repo @('rev-parse', 'HEAD') | Select-Object -Last 1).Trim()

# ---- 1. freshness ----
$stale = [Collections.Generic.List[object]]::new(); $skipped = [Collections.Generic.List[object]]::new()
$edits = [Collections.Generic.List[object]]::new()
$diffCache = @{}
foreach ($t in @($doc.tasks | Where-Object { $_.state -eq 'ticketed' -and $set.Contains([string]$_.id) })) {
    $id = [string]$t.id
    $at = Get-TicketedAt $t
    if (-not $at) { "NO-TICKET-TIME $id (no history entry to ticketed; left as it is)"; $skipped.Add([ordered]@{ id = $id; why = 'no ticket time' }); continue }
    $since = (& git -C $Repo rev-list -1 "--before=$at" HEAD 2>$null | Select-Object -First 1)
    if (-not $since) { $since = (& git -C $Repo rev-list --max-parents=0 HEAD | Select-Object -Last 1) }
    $since = ([string]$since).Trim()
    if ($since -eq $head) { continue }
    if (-not $diffCache.ContainsKey($since)) { $diffCache[$since] = @(Invoke-Git $Repo @('-c', 'core.quotePath=false', 'diff', '--name-only', $since, 'HEAD') | Where-Object { $_ }) }
    $changed = $diffCache[$since]
    if (-not $changed.Count) { continue }
    # Whose write set each changed file hits: the row's own, then each dependency's. Index loops (lib\Streams.ps1
    # Test-WriteSetOverlap: nested foreach over bound arrays skips pairs on PowerShell 7.6.6).
    $owners = [ordered]@{ $id = @($t.writeSet) }
    if (-not $FreshnessOnly) { foreach ($d in @($t.dependsOn)) { if ($d -and $byId[[string]$d]) { $owners[[string]$d] = @($byId[[string]$d].writeSet) } } }
    $hitFiles = [Collections.Generic.List[string]]::new(); $hitBy = [Collections.Generic.List[string]]::new()
    for ($i = 0; $i -lt $changed.Count; $i++) {
        foreach ($k in @($owners.Keys)) {
            if (Test-InWriteSet $changed[$i] $owners[$k]) {
                if (-not $hitFiles.Contains($changed[$i])) { $hitFiles.Add($changed[$i]) }
                if (-not $hitBy.Contains($k)) { $hitBy.Add($k) }
            }
        }
    }
    if (-not $hitFiles.Count) { continue }
    if (Test-ClaimLive $t) { "SKIP-CLAIMED $id stale ($($hitFiles -join ', ')) but held by $($t.claim.session)"; $skipped.Add([ordered]@{ id = $id; why = "claimed by $($t.claim.session)"; files = @($hitFiles) }); continue }
    $sha = $since.Substring(0, [Math]::Min(10, $since.Length))
    $files = @($hitFiles | Select-Object -First 8); $more = if ($hitFiles.Count -gt 8) { " (+$($hitFiles.Count - 8) more)" } else { '' }
    $note = "STALE: $($files -join ', ')$more since $sha by $($hitBy -join ',')"
    "STALE $id $note"
    $stale.Add([ordered]@{ id = $id; since = $since; ticketedAt = $at; files = @($hitFiles); by = @($hitBy) })
    $edits.Add([ordered]@{ task = $id; release = 'planned'; note = $note })
}

if ($FreshnessOnly) {
    if ($DryRun) { "DRY-RUN FRESHNESS $Group stale $($stale.Count) skipped $($skipped.Count)"; exit 0 }
    if ($edits.Count) {
        $bf = Join-Path $P.Plans "$Group.freshness-revise.json"
        if (-not (Test-Path $P.Plans)) { New-Item -ItemType Directory -Path $P.Plans -Force | Out-Null }
        Write-AtomicText $bf ([ordered]@{ note = "freshness tick of $Group (own write-set files changed on main since ticketed)"; edits = @($edits) } | ConvertTo-Json -Depth 6)
        $out = @(& "$PSScriptRoot\Revise-Task.ps1" -Repo $Repo -Session $Session -File $bf)
        $out | ForEach-Object { "  $_" }
        if ($LASTEXITCODE) { "REVISE-FAILED exit $LASTEXITCODE (nothing released; see the lines above)"; exit 3 }
        Add-Decision $P $Session "FRESHNESS $Group at $($head.Substring(0, 10)): $($stale.Count) ticketed row(s) to planned (own files changed on main since ticketed): $(@($stale | ForEach-Object { $_.id }) -join ', ')"
    }
    "FRESHNESS $Group stale $($stale.Count) skipped $($skipped.Count)"
    exit 0
}

# ---- 2. known failures ----
$kfPath = Join-Path $P.Suites "known-failures.$Group.json"
$kf = if (Test-Path -LiteralPath $kfPath) { @(Get-Content -Raw -LiteralPath $kfPath | ConvertFrom-Json -AsHashtable -DateKind String) } else { @() }
$fixTasks = [Collections.Generic.List[object]]::new()
$n = 1; while ($byId.ContainsKey("$Group.KF$n")) { $n++ }
$groupIntegration = @($doc.tasks | Where-Object { [string]$_.group -eq $Group -and $_.kind -eq 'integration' } | Select-Object -First 1)
foreach ($e in $kf) {
    if ($e -isnot [Collections.IDictionary] -or $e['fixTask']) { continue }
    $ws = @($e['writeSet'] | Where-Object { $_ })
    $owner = if ($e['ownerRow'] -and $byId[[string]$e['ownerRow']]) { $byId[[string]$e['ownerRow']] } else { $null }
    $why = if ($owner) { @($owner.why) } else { @('KNOWN-FAILURE') }
    if (-not $ws.Count) { "KNOWN-FAILURE-SKIPPED $($e['test']) (no write set recorded)"; continue }
    $fid = "$Group.KF$n"; $n++
    $fixTasks.Add([ordered]@{ id = $fid; group = $Group; title = "Fix known failure: $($e['test'])"; why = $why; kind = 'code'; origin = 'integration'
        writeSet = $ws; dependsOn = @(); estMinutes = 45; estBasis = 'known failure from an earlier group run, sized as a typical fix task'
        note = "known failure from run $($e['run']) at $($e['head']): $($e['test']) ($($e['suite']))" })
    $e['fixTask'] = $fid
    "KNOWN-FAILURE $fid $($e['test'])"
}

# ---- 3. owner gates ----
$gateLines = [Collections.Generic.List[string]]::new()
$qText = if (Test-Path -LiteralPath $P.Questions) { [IO.File]::ReadAllText($P.Questions) } else { '' }
foreach ($g in @($doc.tasks | Where-Object { [string]$_.group -eq $Group -and $_.kind -eq 'gate' -and $_.state -ne 'done' })) {
    $tag = "ACTIVATION-GATE $($g.id)"
    "GATE $($g.id) $($g.state): $($g.title)"
    if (-not $qText.Contains($tag)) { $gateLines.Add("- $(Format-LocalStamp) $tag ($Group is the focus group): $($g.title). Run /stream-integrate gate $($g.id) pass|fail when its evidence is ready.") }
}

$m = Get-GroupMilestones $P $doc $Group
"MILESTONES M1 $($m.M1) M2 $($m.M2) M3 $($m.M3)"
if ($DryRun) { "DRY-RUN $Group stale $($stale.Count) skipped $($skipped.Count) gates $($gateLines.Count) fixes $($fixTasks.Count)"; exit 0 }

# ---- write ----
if ($edits.Count) {
    $bf = Join-Path $P.Plans "$Group.activation-revise.json"
    if (-not (Test-Path $P.Plans)) { New-Item -ItemType Directory -Path $P.Plans -Force | Out-Null }
    Write-AtomicText $bf ([ordered]@{ note = "activation of $Group (freshness check)"; edits = @($edits) } | ConvertTo-Json -Depth 6)
    $out = @(& "$PSScriptRoot\Revise-Task.ps1" -Repo $Repo -Session $Session -File $bf)
    $out | ForEach-Object { "  $_" }
    if ($LASTEXITCODE) { "REVISE-FAILED exit $LASTEXITCODE (nothing released; see the lines above)"; exit 3 }
}
if ($fixTasks.Count) {
    $ff = Join-Path $P.Plans "$Group.activation-fixes.json"
    Write-AtomicText $ff ([ordered]@{ groups = @(); tasks = @($fixTasks) } | ConvertTo-Json -Depth 6)
    $out = @(& "$PSScriptRoot\Add-Tasks.ps1" -Repo $Repo -Role integrate -Session $Session -File $ff)
    $out | ForEach-Object { "  $_" }
    if ($LASTEXITCODE) { "ADD-FAILED exit $LASTEXITCODE (known failures kept for the next activation)"; exit 3 }
    Write-AtomicText $kfPath (ConvertTo-Json -InputObject @($kf) -Depth 6)
}
if ($gateLines.Count) { if (-not (Test-Path $P.Owner)) { New-Item -ItemType Directory -Path $P.Owner -Force | Out-Null }; [IO.File]::AppendAllText($P.Questions, (($gateLines -join "`n") + "`n")) }
$rec = [ordered]@{ group = $Group; at = Get-Now; session = $Session; head = $head
    stale = @($stale); skipped = @($skipped); gates = @($doc.tasks | Where-Object { [string]$_.group -eq $Group -and $_.kind -eq 'gate' -and $_.state -ne 'done' } | ForEach-Object { [string]$_.id })
    knownFailureFixes = @($fixTasks | ForEach-Object { $_.id }); milestones = [ordered]@{ M1 = $null; M2 = $null; M3 = $null } }
if (-not (Test-Path $P.Plans)) { New-Item -ItemType Directory -Path $P.Plans -Force | Out-Null }
Write-AtomicText $actPath ($rec | ConvertTo-Json -Depth 8)
$doc2 = Read-Tasks $P
[void](Update-ActivationMilestones $P $doc2 $Group)
Add-Decision $P $Session "ACTIVATED $Group at $($head.Substring(0, 10)): stale $($stale.Count) to planned, skipped $($skipped.Count), gates $($rec.gates.Count), known-failure fixes $($fixTasks.Count)"
"ACTIVATED $Group stale $($stale.Count) skipped $($skipped.Count) gates $($rec.gates.Count) fixes $($fixTasks.Count)"
exit 0
