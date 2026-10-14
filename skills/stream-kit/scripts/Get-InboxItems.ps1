# Lists the items of one role's inbox, oldest first, each with its latest status. Read-only (no lock).
#   -Open : only items this role should act on: open, or taken but silent past the role's limit
#   -All  : every inbox (-Skill ignored); -Json : machine-readable
# Line form: <id> | <status> <age>m by <who> | <kind> | <task> | <ask> | <evidence>
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string] $Skill = '',
    [switch] $Open,
    [switch] $All,
    [switch] $Json
)
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$skills = if ($All) { $script:InboxSkills } elseif ($Skill) { @($Skill) } else { throw 'give -Skill <stream-...> or -All' }
$out = foreach ($s in $skills) {
    foreach ($it in Read-InboxItems (Get-InboxPath $P $s)) {
        if ($Open -and -not (Test-InboxOpen $it $s)) { continue }
        $it['inbox'] = $s; $it['ageMinutes'] = Get-InboxAgeMinutes $it; $it['limitMinutes'] = $script:InboxLimitMinutes[$s]
        $it
    }
}
if ($Json) { ConvertTo-Json -Depth 5 -InputObject @($out); exit 0 }
if (-not @($out).Count) { 'NONE'; exit 0 }
foreach ($it in $out) {
    $pre = if ($All) { "$($it.inbox) | " } else { '' }
    '{0}{1} | {2} {3}m by {4} | {5} | {6} | {7} | {8}' -f $pre, $it.id, $it.status, $it.ageMinutes, $it.statusBy, $it.kind, $it.task, $it.ask, $it.evidence
}
