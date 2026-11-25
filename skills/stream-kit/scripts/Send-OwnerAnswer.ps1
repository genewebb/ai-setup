# Files one owner answer in .streams\inbox\owner-answers.md, for the coordinator to apply through the existing verb:
# a gate pass or fail for the integrator, a plan inbox item for a questions.md override, a worktree removal confirmation.
# Works from any host that reaches the repo share. Prints SENT <id> (exit 0), DUPLICATE <id> (exit 10: the same target
# already has a live answer), or REFUSED <why> (exit 2, nothing written).
# Target forms: gate:<task id> (answer leads with pass or fail), questions:<line text or id>, worktree:<path or task id>.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Target,
    [Parameter(Mandatory)] [string] $Answer,
    [string] $From = 'owner'
)
$m = [regex]::Match($Target, '^(questions|gate|worktree):(.+)$')
if (-not $m.Success) { "REFUSED target '$Target': use questions:<id>, gate:<task id> or worktree:<path or task id>"; exit 2 }
$kind = $m.Groups[1].Value; $ref = $m.Groups[2].Value.Trim()
if (-not $Answer.Trim()) { 'REFUSED empty answer'; exit 2 }
$task = '-'
if ($kind -eq 'gate') {
    if ($Answer.Trim() -notmatch '^(?i)(pass|fail)\b') { "REFUSED a gate answer leads with pass or fail: '$Answer'"; exit 2 }
    $task = $ref
}
# The key is the target, so a second answer to the same target waits until the first is applied (DUPLICATE).
$out = @(& "$PSScriptRoot\Send-InboxItem.ps1" -Repo $Repo -To owner-answers -From $From -Kind request -Ask "$kind`:$ref => $($Answer.Trim())" -Task $task -Key "$kind`:$ref")
$code = $LASTEXITCODE
$out
exit $code
