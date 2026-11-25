# Lists the items of one role's inbox, oldest first, each with its latest status. Read-only (no lock).
#   -Open : only items this role should act on: open or woken, held with its condition met (Set-InboxItem.ps1 held), or
#           taken but silent past the role's limit
#   -All  : every inbox (-Skill ignored); -Json : machine-readable
#   -Wake -By <session> : instead of listing, append a `woken` line, under each inbox's lock, to every held item whose
#           condition is met, printing `WOKEN <skill> <id>` per item and `WAKE-DONE <n>`; the status tick runs it
#   -IncludeArchive : also the closed items Compress-StreamInboxes.ps1 moved to inbox\archive\<skill>-<yyyy-MM>.md (field archived)
# Line form: <id> | <status> <age>m by <who> | <kind> | <task> | <ask> | <evidence>
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string] $Skill = '',
    [switch] $Open,
    [switch] $All,
    [switch] $Json,
    [switch] $IncludeArchive,
    [switch] $Wake,
    [string] $By = 'status-tick'
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$skills = if ($All) { $script:InboxSkills } elseif ($Skill) { @($Skill) } else { throw 'give -Skill <stream-...> or -All' }
if ($Wake) {
    $woken = [Collections.Generic.List[string]]::new()
    foreach ($s in $skills) {
        $path = Get-InboxPath $P $s
        if (-not (Test-Path -LiteralPath $path)) { continue }
        [void](Invoke-InboxLocked $path $By {
            foreach ($it in @(Read-InboxItems $path | Where-Object { $_.status -eq 'held' })) {
                if (-not (Test-InboxHoldMet $it $P)) { continue }
                $woken.Add("WOKEN $s $($it.id)")
                '- {0} | {1} | {2} | woken | {3}' -f $it.id, (Get-Now), (ConvertTo-InboxField $By), (ConvertTo-InboxField "met: $($it.note)")
            }
        })
    }
    $woken
    "WAKE-DONE $($woken.Count)"
    exit 0
}$out = foreach ($s in $skills) {
    foreach ($it in Read-InboxItems (Get-InboxPath $P $s)) {
        if ($Open -and -not (Test-InboxOpen $it $s $P)) { continue }
        $it['inbox'] = $s; $it['ageMinutes'] = Get-InboxAgeMinutes $it; $it['limitMinutes'] = $script:InboxLimitMinutes[$s]
        $it
    }
    if (-not $IncludeArchive -or $Open) { continue }
    foreach ($af in @(Get-ChildItem -LiteralPath (Join-Path $P.Root 'inbox\archive') -Filter "$s-*.md" -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        foreach ($it in Read-InboxItems $af.FullName) {
            $it['inbox'] = $s; $it['ageMinutes'] = Get-InboxAgeMinutes $it; $it['limitMinutes'] = $script:InboxLimitMinutes[$s]; $it['archived'] = $af.Name
            $it
        }
    }
}
if ($Json) { ConvertTo-Json -Depth 5 -InputObject @($out); exit 0 }
if (-not @($out).Count) { 'NONE'; exit 0 }
foreach ($it in $out) {
    $pre = if ($All) { "$($it.inbox) | " } else { '' }
    '{0}{1} | {2} {3}m by {4} | {5} | {6} | {7} | {8}' -f $pre, $it.id, $it.status, $it.ageMinutes, $it.statusBy, $it.kind, $it.task, $it.ask, $it.evidence
}
