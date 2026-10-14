# Changes one task under the lock: beat, state move, artifact/base fields, write-set widening, claim release.
# author/build callers must still hold the claim; if it was taken over the call writes nothing and exits 3
# (CLAIM-LOST), so a session that slept past its limit stops instead of overwriting the new owner's work. One exception:
# an author holding a live taken stream-author item that names a ticketed, unclaimed row may set that row's -Artifacts
# (alone) without a claim; anything else on such a row is REFUSED (exit 2).
# -AddWriteSet (build only): the builder's auto-accepted widening of its own write set. Refused whole (exit 7,
# WRITESET-OVERLAP, nothing written) when a new path overlaps the write set of another task that could still collide at
# integration. A task that has landed (integrated or done) or is on this task's dependsOn chain (either way) is already
# ordered against it and never refuses the widening. Each widening is logged in decisions.md.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Task,
    [Parameter(Mandatory)] [ValidateSet('plan', 'author', 'build', 'integrate', 'status')] [string] $Role,
    [Parameter(Mandatory)] [string] $Session,
    [string] $To = '',
    [string] $Note = '',
    [object] $Artifacts = @{},
    [object] $Base = @{},
    [string[]] $AddWriteSet = @(),
    [switch] $Beat,
    [switch] $Release
)
. "$PSScriptRoot\lib\Streams.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path

if ($AddWriteSet.Count -and $Role -ne 'build') { Write-Output "REFUSED -AddWriteSet is for the build role only"; exit 2 }
# <file[,file]> is what this script's own help promises, and a shell hands that over as ONE string, so split it here
# rather than storing a path that matches nothing (see Expand-PathList).
$AddWriteSet = @(Expand-PathList $AddWriteSet)

# -Artifacts and -Base take a hashtable, or the same thing as TEXT: JSON ('{"ticket":"..."}') or a literal
# ('@{ ticket = "..." }'). Under `pwsh -File` every argument arrives as text, so a [hashtable] parameter refused to bind,
# and an author whose -Artifacts call failed that way then released G3.T369 with artifacts.ticket still null (kit item
# IN-20261004235456-523e). A literal is read by the parser as constant data only (SafeGetValue), never run.
function ConvertTo-ArgTable($Value, [string] $Name) {
    if ($null -eq $Value) { return @{} }
    if ($Value -is [Collections.IDictionary]) { return $Value }
    $text = "$Value".Trim()
    if ($text.StartsWith('{')) {
        try { return ($text | ConvertFrom-Json -AsHashtable -Depth 20) } catch { throw "REFUSED -$Name is not valid JSON: $($_.Exception.Message)" }
    }
    if ($text.StartsWith('@{')) {
        $tokens = $null; $errs = $null
        $ast = [Management.Automation.Language.Parser]::ParseInput($text, [ref] $tokens, [ref] $errs)
        $h = $ast.Find({ param($a) $a -is [Management.Automation.Language.HashtableAst] }, $true)
        if (-not $errs.Count -and $h -and $h.Extent.Text.Trim() -eq $text) {
            try { return $h.SafeGetValue() } catch { throw "REFUSED -$Name must hold constant values only: $($_.Exception.Message)" }
        }
    }
    throw "REFUSED -$Name takes a hashtable, JSON text or @{...} text, and got: $text"
}
try { $Artifacts = ConvertTo-ArgTable $Artifacts 'Artifacts'; $Base = ConvertTo-ArgTable $Base 'Base' }
catch { Write-Output "$($_.Exception.Message)"; exit 2 }

# An author working a stream-author inbox item may rewrite the ticket or grader of a row that is ticketed and not yet
# claimed by a builder (stream-author step 0), but it holds no claim on that row, so it could not record a new grader
# path: Claim-Task refuses a ticketed row to an author, and every author call here needed the claim (kit item
# IN-20261010152029-7e12, G6.T019). The live taken item stands in for the claim, for -Artifacts alone and only while
# the row is ticketed with no claim at all.
$authorHold = $null
if ($Role -eq 'author') {
    . "$PSScriptRoot\lib\Inbox.ps1"
    $authorHold = @(Read-InboxItems (Get-InboxPath $P 'stream-author') | Where-Object {
        $_.status -eq 'taken' -and $_.statusBy -eq $Session -and [string]$_.task -eq $Task -and
        (Get-InboxAgeMinutes $_) -lt $script:InboxLimitMinutes['stream-author'] }) | Select-Object -Last 1
}
$holdOnly = $Artifacts.Count -and -not ($To -or $Note -or $Base.Count -or $AddWriteSet.Count -or $Beat -or $Release)
$lost = $false
$holdRefused = ''
$manifest = ''
$overlap = @()
$added = @()
trap { if ("$_" -like 'TRANSITION-REFUSED*') { Write-Output "$_"; exit 6 } else { break } }
[void](Invoke-TasksLocked $P $Session {
    param($doc)
    $t = Get-Task $doc $Task
    if ($Role -in @('author', 'build')) {
        if (-not $t.claim -or $t.claim.session -ne $Session) {
            if (-not $authorHold) { $script:lost = $true; return $null }
            if ($t.state -ne 'ticketed' -or $t.claim) { $script:holdRefused = "row is $($t.state)$(if ($t.claim) { ", claimed by $($t.claim.session)" }); an inbox hold covers only a ticketed row nobody has claimed"; return $null }
            if (-not $holdOnly) { $script:holdRefused = 'an inbox hold covers -Artifacts alone (no -To, -Note, -Base, -AddWriteSet, -Beat or -Release)'; return $null }
            foreach ($k in $Artifacts.Keys) { $t.artifacts[$k] = $Artifacts[$k] }
            Add-History $t $Session $t.state "artifacts $(@($Artifacts.Keys) -join ', ') set by author under inbox item $($authorHold.id) (no claim)"
            return $doc
        }
    }
    if ($AddWriteSet.Count) {
        $new = @($AddWriteSet | ForEach-Object { ConvertTo-RepoRel $_ } | Where-Object { $_ -and -not (Test-InWriteSet $_ $t.writeSet) } | Sort-Object -Unique)
        $others = @($doc.tasks | Where-Object { $_.id -ne $t.id -and $_.state -notin @('integrated', 'done') -and $_.kind -notin @('gate', 'integration') })
        foreach ($o in $others) {
            if ((Test-DependsOnChain $doc.tasks $t $o.id) -or (Test-DependsOnChain $doc.tasks $o $t.id)) { continue }
            foreach ($f in $new) { if (Test-WriteSetOverlap @($f) $o.writeSet) { $script:overlap += "$f overlaps $($o.id) ($($o.state))" } }
        }
        if ($script:overlap.Count) { return $null }
        if ($new.Count) {
            $t.writeSet = @($t.writeSet) + $new
            $script:added = $new
            Add-History $t $Session $t.state "write set widened (auto-accepted): $($new -join ', ')$(if ($Note) { " -- $Note" })"
        }
    }
    if ($Beat -and $t.claim) { $t.claim.beat = Get-Now }
    foreach ($k in $Artifacts.Keys) { $t.artifacts[$k] = $Artifacts[$k] }
    if ($Base.Count) { $t['base'] = [ordered]@{}; foreach ($k in $Base.Keys) { $t.base[$k] = $Base[$k] } }
    # blocked>integrated records a verified patch that is ALREADY on main (two drains of one integrator landed G3.T019 and
    # G3.T026 while the other bounced them, and the builder then blocked them as already met; kit item
    # IN-20261001215631-6eda). It is legal only when the kept patch reverse-applies clean on the main tree, which is
    # the proof that every line of it is there.
    if ($To -eq 'integrated' -and $t.state -eq 'blocked') {
        $kept = [string] $t.artifacts['patch']
        if ($kept -and -not [IO.Path]::IsPathRooted($kept)) { $kept = Join-Path $P.Repo $kept }
        if (-not $kept -or -not (Test-Path -LiteralPath $kept)) { throw "TRANSITION-REFUSED $($t.id): blocked -> integrated needs the kept patch, and the task has none" }
        & git -C $P.Repo apply -R --check --binary --whitespace=nowarn $kept 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "TRANSITION-REFUSED $($t.id): blocked -> integrated needs the kept patch to reverse-apply clean on the main tree, and it does not, so the work is not all on main" }
    }
    # An author hands a row to the builders only WITH its ticket: the builder reads artifacts.ticket, and a null there
    # left G3.T369 ticketed with nothing to build from. Refused before anything is written, so the claim survives.
    if ($To -eq 'ticketed' -and $Role -eq 'author' -and -not ($t.artifacts -and [string] $t.artifacts['ticket'])) {
        throw "TRANSITION-REFUSED $($t.id): planned -> ticketed by an author needs artifacts.ticket, and the row has none (pass -Artifacts in the same call or before it)"
    }
    if ($To) { Set-TaskState $t $To $Role $Session $Note }
    # Hand-off of a folder delivered in place carries a fingerprint, because there is no patch to carry it: without one
    # the integrator cannot tell the folder it lands from the folder the verifier graded. Written only AFTER the state
    # move is accepted, so a refused transition leaves no manifest claiming a hand-off that did not happen.
    if ($To -eq 'built' -and (Test-InPlaceWriteSet $t.writeSet)) {
        $script:manifest = Write-DeliveredManifest $P $t.id $t.writeSet
        $t.artifacts['manifest'] = $script:manifest
    }
    # A state move already wrote its note through Set-TaskState; writing it again doubled every moved row's history
    # entry (G3.T019 and G1.T12 carry each one twice).
    elseif ($Note -and -not $To -and -not $script:added.Count) { Add-History $t $Session $t.state $Note }
    if ($Release) { $t.claim = $null }
    $doc
})
if ($lost) { Write-Output "CLAIM-LOST $Task (no longer held by $Session)"; exit 3 }
if ($holdRefused) { Write-Output "REFUSED $Task : $holdRefused"; exit 2 }
if ($overlap.Count) { $overlap | ForEach-Object { "WRITESET-OVERLAP $_" }; exit 7 }
if ($manifest) { "MANIFEST $manifest" }
if ($added.Count) { Add-Decision $P $Session "$Task write set widened (auto-accepted): $($added -join ', ')$(if ($Note) { " -- $Note" })" }
"ok $Task"
exit 0
