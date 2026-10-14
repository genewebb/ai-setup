# Files a new item in a role's inbox (.streams\inbox\<To>.md) under the inbox lock and prints its id.
# Pipes and line breaks in any field are flattened, so one item is always one line.
# REFUSES (exit 9, nothing written) an UNDELIVERABLE item: one addressed to stream-author or stream-build against a
# task that is `planned`, has no ticket and holds no claim. Guidance for the future holder of such a row has no
# reachable taker, because Claim-Task.ps1 picks by group and chain order and no author can choose to work a named row.
# It stays open forever and flags on every status tick. Measured 2026-09-30: IN-20260930090901-6108 open 498 minutes
# for G3.T018, one of 112 untickted G3 rows; IN-20260930160743-3aa7 open 80 minutes for G6.T109, one of 88 unlanded G6
# rows; and the coordinator filed the same G4.T039 request FIVE times before folding the substance into the row itself
# (kit item IN-20260930173115-9370). The row's own history IS the delivery channel: Update-Task.ps1 -Note travels with
# the task to whoever claims it. -Force files anyway, for the sender who means it.
# Items to stream-plan, stream-kit, stream-status and stream-integrate are never refused: a planner acts on any row,
# and the other three do not work rows at all.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $To,
    [Parameter(Mandatory)] [string] $From,
    [Parameter(Mandatory)] [ValidateSet('request', 'bug')] [string] $Kind,
    [Parameter(Mandatory)] [string] $Ask,
    [string] $Task = '-',
    [string] $Evidence = '-',
    [switch] $Force
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
. "$PSScriptRoot\lib\Recovery.ps1"   # Get-Field, for the artifacts.ticket read in the undeliverable check
$P = Get-StreamPaths (Resolve-Path $Repo).Path
Initialize-Inboxes $P
$path = Get-InboxPath $P $To
# An ask that LEADS with "<task>:" is about that task, so the task field says so (see Get-AskLeadTask).
if (-not $Task -or $Task -eq '-') { $lead = Get-AskLeadTask $Ask; if ($lead) { $Task = $lead } }
if (-not $Force -and $Task -and $Task -ne '-' -and $To -in @('stream-author', 'stream-build')) {
    $t = $null
    try { $t = Get-Task (Read-Tasks $P) $Task } catch { }
    if ($t -and $t.state -eq 'planned' -and -not (Get-Field $t 'artifacts', 'ticket') -and -not ($t.claim -and $t.claim.session)) {
        "REFUSED $Task is planned with no ticket and no claim, so no $To session can take an item about it: Claim-Task.ps1 picks by group and chain order."
        "        Put it in the row instead, where it reaches whoever claims it:"
        "        Update-Task.ps1 -Repo <repo> -Task $Task -Role <your role> -Session $From -Note '<the guidance>'"
        '        Re-run with -Force to file it anyway.'
        exit 9
    }
}
# A row outside the FOCUS SET (2026-10-05 priority-focus-design 3.1) has no author or builder either: later groups are
# frozen until their turn, so the item would rot exactly like the undeliverable one above.
if (-not $Force -and $Task -and $Task -ne '-' -and $To -in @('stream-author', 'stream-build')) {
    $fdoc = Read-Tasks $P
    $ft = $null; try { $ft = Get-Task $fdoc $Task } catch { }
    if ($ft -and -not (Get-FocusSet $fdoc).Contains([string]$ft.id)) {
        "REFUSED $Task is outside the focus group $(Get-FocusLabel $fdoc), so no $To session will take an item about it until its group is focus (NOT-FOCUS)."
        "        Put it in the row instead, where it reaches whoever claims it:"
        "        Update-Task.ps1 -Repo <repo> -Task $Task -Role <your role> -Session $From -Note '<the guidance>'"
        '        Re-run with -Force to file it anyway.'
        exit 9
    }
}
$id = 'IN-{0}-{1}' -f (Get-Date).ToUniversalTime().ToString('yyyyMMddHHmmss'), ([guid]::NewGuid().ToString('N').Substring(0, 4))
$line = '- {0} | {1} | {2} | open | {3} | {4} | {5} | {6}' -f $id, (Get-Now), (ConvertTo-InboxField $From), $Kind, (ConvertTo-InboxField $Task), (ConvertTo-InboxField $Ask), (ConvertTo-InboxField $Evidence)
[void](Invoke-InboxLocked $path $From { $line })
"SENT $id $To"
# Explicit, because the refusal above exits 9: without this the caller reads a STALE $LASTEXITCODE from whatever ran
# before, so a successful send after a refused one looks refused. Found by recovery case 19.
exit 0
