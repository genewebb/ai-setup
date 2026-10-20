# Counts a finished Tier 2 run for one more group (kit item IN-20261020100610-6c4b). Script only, no model tokens.
#   Add-SuiteRunGroup.ps1 -Repo <repo> -Session <id> -Run <run id> -Group <G> [-DryRun]
# Why: Start-SuiteRun.ps1 lists in a run's 'groups' every focus group whose non-fix build rows were all integrated when
# it started, but it read the group SET only, which was empty for G11 (every row pulled into an earlier group), so
# run-G13-3 ran every test and still did not count for G11. This adds the group to a finished run's record under the
# same rule, judged at the run's start: every non-fix build row of the group (lib\Suites.ps1 Get-GroupBuildRows) is
# integrated or done and its last 'integrated' entry is no later than the run's startedAt.
# The run's attribution is not redone: a failure it filed elsewhere stays filed there.
# Prints ATTACHED <run> <group>, ALREADY (0), NOT-COVERED <row ids> (2), NO-RUN / NOT-TIER2 / NO-GROUP (2) or
# RUN-RUNNING (4: wait for the run to end; Invoke-SuiteLegs.ps1 still rewrites its record).
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [string] $Run,
    [Parameter(Mandatory)] [string] $Group,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Suites.ps1"
. "$PSScriptRoot\lib\Activation.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$doc = Read-Tasks $P
$recPath = Join-Path (Get-SuiteRunsDir $P) "$Run.json"
$rec = Read-JsonFile $recPath
if (-not $rec) { "NO-RUN $recPath"; exit 2 }
if ([string]$rec['tier'] -ne '2') { "NOT-TIER2 $Run is tier $($rec['tier'])"; exit 2 }
if (-not @($doc.groups | Where-Object { [string]$_.id -eq $Group }).Count) { "NO-GROUP $Group is not on the board"; exit 2 }
if ((Get-SuiteRunGroups $rec) -contains $Group) { "ALREADY $Run counts for $Group"; exit 0 }
if ([string]$rec['status'] -eq 'running') { "RUN-RUNNING $Run has not ended; attach it once it has"; exit 4 }
$start = ConvertTo-UtcTime ([string]$rec['startedAt'])
$rows = @(Get-GroupBuildRows $doc $Group)
$late = foreach ($t in $rows) {
    if ($t.state -notin @('integrated', 'done')) { "$($t.id)($($t.state))"; continue }
    $at = $null; foreach ($h in @($t.history)) { if ($h -and [string]$h.to -eq 'integrated' -and $h.at) { $at = [string]$h.at } }
    if ($at -and (ConvertTo-UtcTime $at) -gt $start) { "$($t.id)(integrated $at)" }
}
if (-not $rows.Count) { "NOT-COVERED $Group has no build rows"; exit 2 }
if (@($late).Count) { "NOT-COVERED $(@($late) -join ', ') not landed when $Run started ($($rec['startedAt']))"; exit 2 }
if ($DryRun) { "DRY-RUN would attach $Run to $Group ($($rows.Count) rows landed)"; exit 0 }
$rec['groups'] = @(@(Get-SuiteRunGroups $rec) + $Group)
Write-JsonFile $recPath $rec
Add-Decision $P $Session "TIER2 $Run attached to $Group ($($rows.Count) build rows landed before it started)"
"ATTACHED $Run $Group"
