# Appends a status event to an inbox item, checked against the item's latest line under the inbox lock.
#   taken     : only when the item is open, or taken but past the role's limit. Otherwise ALREADY, exit 8: skip it.
#   done|declined : by the session that HOLDS it. Another session needs -Steal, and only once the hold is past the
#                   role's limit; the appended line then says it was stolen and from whom. Otherwise NOT-HELD, exit 8.
#                   Before 2026-09-30 any session could close a stale hold with no flag and no record, so a holder's
#                   outcome could be written by someone else - and it was: IN-20260930160722-8b93 was closed `done`
#                   with the note `probe` by a session checking whether the refusal existed (kit item
#                   IN-20260930175245-b92e). A stale hold must still be CLOSABLE or a dead session's items never drain
#                   (kit item IN-20260929001050-1c36), so the flag keeps that path and makes it deliberate and visible.
#   note      : an annotation appended AFTER the fact by the session named on the item's latest status line - the
#               holder, or whoever closed it. The record is append-only, so a wrong or placeholder note could never be
#               corrected: the closing session can now add the real reason. It changes nothing but the record: status,
#               its time and its author all stay as they were.
#   beat      : by the session that holds it, to say the work is still running. It moves the hold's clock and nothing
#               else: the item stays taken, by the same holder. Beat inside any step that can outlast the role's inbox
#               limit - a skeptic round, a long suite - or the watchdog re-opens the item and a second session repeats
#               the work (kit item IN-20260930173837-50cb). Only the holder may beat: NOT-HELD, exit 8, otherwise.
#   forwarded : -ForwardTo <skill>; appends forwarded here and the item as a new open line (same id) in that inbox.
# Exit 2 = no such item.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Skill,
    [Parameter(Mandatory)] [string] $Id,
    [Parameter(Mandatory)] [ValidateSet('taken', 'beat', 'note', 'done', 'declined', 'forwarded')] [string] $Status,
    [Parameter(Mandatory)] [string] $By,
    [string] $Note = '',
    [string] $ForwardTo = '',
    # Closing an item held by ANOTHER session. Allowed only when that hold is already past the role's limit.
    [switch] $Steal
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$path = Get-InboxPath $P $Skill
if ($Status -eq 'forwarded') {
    if (-not $ForwardTo) { 'REFUSED -ForwardTo is required for forwarded'; exit 2 }
    $target = Get-InboxPath $P $ForwardTo
}
$result = $null
$item = $null
[void](Invoke-InboxLocked $path $By {
    $script:item = @(Read-InboxItems $path | Where-Object { $_.id -eq $Id })[0]
    if (-not $script:item) { $script:result = "NO-ITEM $Id in $Skill"; return }
    $it = $script:item
    switch ($Status) {
        'taken' {
            if (-not (Test-InboxOpen $it $Skill)) { $script:result = "ALREADY $Id is $($it.status) by $($it.statusBy) $(Get-InboxAgeMinutes $it)m ago"; return }
        }
        'beat' {
            # Stricter than done/declined on purpose: a stale hold may be CLOSED by another session, but nobody may
            # keep someone else's hold alive, or one session could pin an item it is not working on.
            if ($it.status -ne 'taken' -or $it.statusBy -ne $By) {
                $script:result = "NOT-HELD $Id is $($it.status) by $($it.statusBy), not taken by $By"; return
            }
        }
        'note' {
            # Whoever wrote the item's latest status line owns the record of it, and only they may annotate: the holder
            # while it is taken, the closer afterwards. Nobody may write a note under another session's outcome.
            if ($it.statusBy -ne $By) {
                $script:result = "NOT-HELD $Id was last set by $($it.statusBy), not $($By): only that session may annotate it"; return
            }
        }
        { $_ -in 'done', 'declined' } {
            if ($it.status -ne 'taken') { $script:result = "NOT-HELD $Id is $($it.status) by $($it.statusBy), not taken by $By"; return }
            # A stale hold is no hold, but taking it over is now DELIBERATE: another session closes it only with -Steal,
            # and the line says so. Without the stale path at all a dead session's items never drain (kit item
            # IN-20260929001050-1c36); without the flag a live holder's outcome can be written by anyone
            # (IN-20260930175245-b92e).
            if ($it.statusBy -ne $By) {
                if (-not $Steal) {
                    $script:result = "NOT-HELD $Id is taken by $($it.statusBy) $(Get-InboxAgeMinutes $it)m ago, not by $($By): pass -Steal to close another session's hold, and only once it is past the role's limit"; return
                }
                if (-not (Test-InboxOpen $it $Skill)) {
                    $script:result = "HELD $Id is taken by $($it.statusBy) $(Get-InboxAgeMinutes $it)m ago, inside the ${Skill} limit: a live holder's item is never stolen"; return
                }
            }
        }
        'forwarded' {
            if ($it.status -notin @('open', 'taken') -or ($it.status -eq 'taken' -and $it.statusBy -ne $By -and -not (Test-InboxOpen $it $Skill))) {
                $script:result = "NOT-HELD $Id is $($it.status) by $($it.statusBy)"; return
            }
        }
    }
    $note = if ($Status -eq 'forwarded') { "to $ForwardTo$(if ($Note) { ": $Note" })" }
            elseif ($Status -in @('done', 'declined') -and $it.statusBy -ne $By) { "STOLEN from $($it.statusBy) after $(Get-InboxAgeMinutes $it)m$(if ($Note) { ": $Note" })" }
            else { $Note }
    '- {0} | {1} | {2} | {3} | {4}' -f $Id, (Get-Now), (ConvertTo-InboxField $By), $Status, (ConvertTo-InboxField $note)
})
if ($result) { $result; if ($result -like 'NO-ITEM*') { exit 2 } else { exit 8 } }
if ($Status -eq 'forwarded') {
    $line = '- {0} | {1} | {2} | open | {3} | {4} | {5} | {6}' -f $Id, (Get-Now), (ConvertTo-InboxField "$By (from $Skill)"), $item.kind, $item.task, $item.ask, $item.evidence
    [void](Invoke-InboxLocked $target $By { $line })
}
"ok $Id $Status"
# Explicit, because a .ps1 that just falls off the end leaves $LASTEXITCODE at whatever the LAST script set:
# a caller that read it after an `ok` saw the 8 from its own previous refusal and treated a success as a failure.
exit 0
