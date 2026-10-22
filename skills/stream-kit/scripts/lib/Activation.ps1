# Group activation and milestones (2026-10-05 priority-focus-design 3.2). Dot-source after lib\Streams.ps1 and
# lib\Inbox.ps1.

# The rows a group works when it is the focus group: every row whose EFFECTIVE group rank (Get-EffectiveGroupRank) is
# that group's rank. Get-FocusSet is this set for the focus group.
function Get-GroupSet($doc, [string] $Group) {
    $set = [Collections.Generic.HashSet[string]]::new()
    $grank = @{}; $gi = 0
    foreach ($g in $doc.groups) { $grank[[string]$g.id] = $gi++ }
    if (-not $grank.ContainsKey($Group)) { return , $set }
    $want = $grank[$Group]
    $erank = Get-EffectiveGroupRank $doc
    foreach ($t in $doc.tasks) { if ($erank[$t.id] -and $erank[$t.id].rank -eq $want) { [void]$set.Add([string]$t.id) } }
    , $set
}

# When a row was last ticketed: the `at` of its latest history entry with to = ticketed. $null when it has none.
function Get-TicketedAt($Task) {
    $at = $null
    foreach ($h in @($Task.history)) { if ($h -and [string]$h.to -eq 'ticketed' -and $h.at) { $at = [string]$h.at } }
    $at
}

function Get-ActivationPath($P, [string] $Group) { Join-Path $P.Plans "$Group.activation.json" }
function Read-Activation($P, [string] $Group) {
    $f = Get-ActivationPath $P $Group
    if (-not (Test-Path -LiteralPath $f)) { return $null }
    try { Get-Content -Raw -LiteralPath $f | ConvertFrom-Json -AsHashtable -DateKind String } catch { $null }
}

# MILESTONES (3.2 step 5), recomputed every status tick; tracked, never gating.
#   M1 Authored: no row of the group set is planned.
#   M2 Claimable: every ticketed row of the set passes Test-BuildReady, or waits only on dependencies that are
#      ticketed or later INSIDE the set.
#   M3 Integrator-ready: every gate row of the group is ticketed or later; no open stream-integrate inbox item names a
#      row of the set; the group's Tier 2 run definition (.streams\suites\<group>.run.json) exists.
# Returns [ordered]@{ M1; M2; M3; detail = @{ M1; M2; M3 } } with booleans and a short reason for each false one.
function Get-GroupMilestones($P, $doc, [string] $Group) {
    $set = Get-GroupSet $doc $Group
    $byId = @{}; foreach ($t in $doc.tasks) { $byId[[string]$t.id] = $t }
    $rows = @($doc.tasks | Where-Object { $set.Contains([string]$_.id) })
    $planned = @($rows | Where-Object { $_.state -eq 'planned' })
    $m2bad = [Collections.Generic.List[string]]::new()
    foreach ($t in @($rows | Where-Object { $_.state -eq 'ticketed' -and $_.kind -in $script:BuildKinds })) {
        if (Test-BuildReady $doc $t) { continue }
        foreach ($d in @($t.dependsOn)) {
            if (-not $d) { continue }
            $dt = $byId[[string]$d]
            $ok = $dt -and ($dt.state -in @('ticketed', 'building', 'built', 'integrated', 'done')) -and ($set.Contains([string]$d) -or $dt.state -in $script:BuildReadyStates)
            if (-not $ok) { $m2bad.Add("$($t.id)<-$d"); break }
        }
    }
    $gates = @($doc.tasks | Where-Object { [string]$_.group -eq $Group -and $_.kind -eq 'gate' -and $_.state -in @('planned', 'blocked') })
    $openInt = @()
    if (Test-Path -LiteralPath (Get-InboxPath $P 'stream-integrate')) {
        $openInt = @(Read-InboxItems (Get-InboxPath $P 'stream-integrate') | Where-Object { (Test-InboxOpen $_ 'stream-integrate') -and $_.task -and $set.Contains([string]$_.task) })
    }
    $runDef = Test-Path -LiteralPath (Join-Path $P.Suites "$Group.run.json")
    $m3why = @()
    if ($gates.Count) { $m3why += "gates not ticketed: $(($gates | ForEach-Object id) -join ',')" }
    if ($openInt.Count) { $m3why += "$($openInt.Count) open integrate item(s)" }
    if (-not $runDef) { $m3why += 'no run definition' }
    [ordered]@{
        M1 = ($planned.Count -eq 0); M2 = ($m2bad.Count -eq 0); M3 = ($m3why.Count -eq 0)
        detail = [ordered]@{
            M1 = $(if ($planned.Count) { "$($planned.Count) planned" } else { '' })
            M2 = $(if ($m2bad.Count) { "$($m2bad.Count) waiting outside the set: $(($m2bad | Select-Object -First 5) -join ' ')" } else { '' })
            M3 = ($m3why -join '; ')
        }
    }
}

# Records the FIRST time each milestone is reached in the group's activation file. A group with no activation file is
# not touched (activation writes it). Returns the activation record (or $null).
function Update-ActivationMilestones($P, $doc, [string] $Group) {
    $a = Read-Activation $P $Group
    if (-not $a) { return $null }
    $m = Get-GroupMilestones $P $doc $Group
    if ($a['milestones'] -isnot [Collections.IDictionary]) { $a['milestones'] = [ordered]@{} }
    $changed = $false
    foreach ($k in 'M1', 'M2', 'M3') {
        if ($m[$k] -and -not $a['milestones'][$k]) { $a['milestones'][$k] = Get-Now; $changed = $true }
    }
    $a['now'] = [ordered]@{ M1 = $m.M1; M2 = $m.M2; M3 = $m.M3; detail = $m.detail }
    Write-AtomicText (Get-ActivationPath $P $Group) ($a | ConvertTo-Json -Depth 8)
    $a
}

# APPEND-ONLY ALLOCATOR FILES (kit item IN-20261022023731-e458). A serial id allocator such as
# docs/requirements/ids.yaml only ever gains lines at its end, and the rows that write it are already ordered on it by
# dependsOn; the builder's base carries the new lines in. Staling every ticket that holds it on each append re-ticketed
# 12 and then 14 rows on 2026-10-21 with no clause change. A change to a file matching $script:AppendOnlyFileRx
# (STREAM_APPEND_ONLY_FILES overrides the regex) is no staleness when the file at HEAD starts with every line it had at
# <since>; an edit, a removal or a new file still stales.
$script:AppendOnlyFileRx = if ($env:STREAM_APPEND_ONLY_FILES) { $env:STREAM_APPEND_ONLY_FILES } else { '(^|/)ids\.yaml$' }
function Test-AppendOnlyChange([string] $Repo, [string] $Since, [string] $Head, [string] $File) {
    if ($File -notmatch $script:AppendOnlyFileRx) { return $false }
    $old = @(& git -C $Repo -c core.quotePath=false show "${Since}:$File" 2>$null); if ($LASTEXITCODE -ne 0) { return $false }
    $new = @(& git -C $Repo -c core.quotePath=false show "${Head}:$File" 2>$null); if ($LASTEXITCODE -ne 0) { return $false }
    if ($new.Count -lt $old.Count) { return $false }
    for ($i = 0; $i -lt $old.Count; $i++) { if ([string]$new[$i] -cne [string]$old[$i]) { return $false } }
    $true
}
