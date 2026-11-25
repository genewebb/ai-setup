# Applies each open owner-answers item (Send-OwnerAnswer.ps1) through the verb that already owns it, then closes it:
#   gate:<task>      -> one stream-integrate item 'gate <task> pass|fail "<note>"', so the integrator stays the only
#                       writer of a gate's end state (pass: the gate done; fail: a fix task, as the session command).
#   questions:<ref>  -> one stream-plan item carrying the answer, so the planner applies the override.
#   worktree:<ref>   -> Remove-TaskWorktree.ps1 (-Task for a task id, else -Path) when the answer leads with yes,
#                       remove or ok; any other answer keeps the tree and declines the item.
# Prints one APPLIED <id> <what> or DECLINED <id> <why> line per item, then APPLY-DONE <n>. Exit 0; exit 2 when an
# item could not be forwarded (it stays taken by -Session, so the next run or the holder retries it).
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
$items = @(& "$PSScriptRoot\Get-InboxItems.ps1" -Repo $Repo -Skill owner-answers -Open -Json | ConvertFrom-Json)
$n = 0; $failed = $false
foreach ($it in $items) {
    if (-not $it -or -not $it.id) { continue }
    $m = [regex]::Match([string] $it.ask, '^(questions|gate|worktree):(.+?) => (.+?)(?: key=\S+)?$')
    if ($DryRun) { "WOULD-APPLY $($it.id) $($it.ask)"; continue }
    $t = @(& "$PSScriptRoot\Set-InboxItem.ps1" -Repo $Repo -Skill owner-answers -Id $it.id -Status taken -By $Session)
    if ($LASTEXITCODE -ne 0) { "SKIPPED $($it.id) $($t -join ' ')"; continue }
    if (-not $m.Success) {
        & "$PSScriptRoot\Set-InboxItem.ps1" -Repo $Repo -Skill owner-answers -Id $it.id -Status declined -By $Session -Note "not an owner answer shape (questions|gate|worktree:<ref> => <answer>)" | Out-Null
        "DECLINED $($it.id) bad shape"; $n++; continue
    }
    $kind = $m.Groups[1].Value; $ref = $m.Groups[2].Value.Trim(); $ans = $m.Groups[3].Value.Trim()
    $what = $null; $why = $null; $skip = $false
    switch ($kind) {
        'gate' {
            $v = [regex]::Match($ans, '^(?i)(pass|fail)\b[\s:,-]*(.*)$')
            if (-not $v.Success) { $why = "a gate answer leads with pass or fail: '$ans'"; break }
            $verdict = $v.Groups[1].Value.ToLowerInvariant(); $note = $v.Groups[2].Value.Trim()
            if (-not $note) { $note = "owner answer $($it.id)" }
            $s = @(& "$PSScriptRoot\Send-InboxItem.ps1" -Repo $Repo -To stream-integrate -From $Session -Kind request -Task $ref -Ask "gate $ref $verdict `"$note`" (owner answer $($it.id): run /stream-integrate gate $ref $verdict with this note)")
            if ($LASTEXITCODE -ne 0) { "FAILED $($it.id) $($s -join ' ')"; $failed = $true; $skip = $true; break }
            $what = "forwarded gate $ref $verdict to stream-integrate as $(($s[-1] -split ' ')[1])"
        }
        'questions' {
            $s = @(& "$PSScriptRoot\Send-InboxItem.ps1" -Repo $Repo -To stream-plan -From $Session -Kind request -Ask "Owner answer $($it.id) to questions.md '$ref': $ans. Apply it as the owner's decision.")
            if ($LASTEXITCODE -ne 0) { "FAILED $($it.id) $($s -join ' ')"; $failed = $true; $skip = $true; break }
            $what = "forwarded question '$ref' to stream-plan as $(($s[-1] -split ' ')[1])"
        }
        'worktree' {
            if ($ans -notmatch '^(?i)(yes|remove|ok)\b') { $why = "answer '$ans' does not confirm removal; tree kept"; break }
            $args2 = @{ Repo = $Repo; Session = $Session; Reason = "owner answer $($it.id)" }
            if ($ref -match '^G\d+\.') { $args2.Task = $ref } else { $args2.Path = $ref }
            $r = @(& "$PSScriptRoot\Remove-TaskWorktree.ps1" @args2 2>&1)
            if ($LASTEXITCODE -ne 0) { "FAILED $($it.id) $($r -join ' ')"; $failed = $true; $skip = $true; break }
            $what = "removed worktree $ref ($(($r | Select-Object -Last 1)))"
        }
    }
    # continue inside a switch only leaves the switch, so a failed forward is flagged and skipped here.
    if ($skip) { continue }
    if ($why) {
        & "$PSScriptRoot\Set-InboxItem.ps1" -Repo $Repo -Skill owner-answers -Id $it.id -Status declined -By $Session -Note $why | Out-Null
        "DECLINED $($it.id) $why"
    } else {
        & "$PSScriptRoot\Set-InboxItem.ps1" -Repo $Repo -Skill owner-answers -Id $it.id -Status done -By $Session -Note $what | Out-Null
        "APPLIED $($it.id) $what"
    }
    $n++
}
"APPLY-DONE $n"
if ($failed) { exit 2 }
exit 0
