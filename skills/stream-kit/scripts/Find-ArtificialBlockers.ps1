# Read-only critical view of the dependsOn waits of every open focus-set row (kit item IN-20261018044413-259b, owner
# request 2026-10-18: builders and authors sat idle with 0 claimable of 180 ticketed behind waits nobody needed).
# Each unmet edge X -> d is classed:
#   logical     d is a named prerequisite hub (-Hubs), X's title names d, X and d share no write-set file, or an earlier
#               -Apply wrote the edge ('applied order', so the pair is never flipped back): kept.
#   landing     d is building or claimed: the wait is real and ends when d lands; never jumped, directly or as an ancestor.
#   gate        d is a gate or integration row: kept.
#   file-order  X and d share a write-set file and d is still ticketed or planned with no live claim. 'composition'
#               when every shared file is a registration / composition file, else 'review'.
# A row is a CANDIDATE when every unmet ancestor (walked through file-order edges only) is file-order: flipping those
# edges makes it claimable. Nothing is changed here unless -Apply is given.
# -Session writes one summary line to decisions.md. Output: one line per candidate, then 'SUMMARY ...'; -Json the model.
# -Apply (needs -Session; kit item IN-20261018051443-4d10) flips the candidates through Revise-Task.ps1, one batch per
# candidate X, re-scanning after each: X drops its waits on the rows it jumps, every jumped row it waited on directly
# gains X as a dependency (the shared files stay ordered, X first), and every open row that waited on X gains X's old
# waits, so each order that ran through X is kept as an explicit edge. A row moved earlier in the run is never jumped
# again (two candidates ahead of one row would otherwise trade places for ever). A refused batch (REFUSED UNORDERED,
# a cycle) is printed SKIPPED and the next candidate is tried. Prints APPLIED / SKIPPED lines, then 'APPLY ...' with
# the build-claimable count before and after, which also goes to decisions.md.
param([Parameter(Mandatory)] [string] $Repo, [string[]] $Hubs = @(), [string] $Session, [switch] $Json, [switch] $Apply)
$ErrorActionPreference = 'Stop'
function Get-DepWhy($x, [string] $d) { $w = if ($x -is [Collections.IDictionary]) { if ($x.Contains('dependsWhy')) { $x['dependsWhy'] } } elseif ($x.PSObject.Properties['dependsWhy']) { $x.dependsWhy }; if (-not $w) { return '' }; if ($w -is [Collections.IDictionary]) { if ($w.Contains($d)) { return [string]$w[$d] }; return '' }; $p = $w.PSObject.Properties[$d]; if ($p) { [string]$p.Value } else { '' } }
. (Join-Path $PSScriptRoot 'lib\Streams.ps1')
$P = Get-StreamPaths $Repo
if ($Apply -and -not $Session) { 'REFUSED -Apply needs -Session'; exit 2 }
$landed = @('built', 'integrated', 'done')
$compRx = '(^|/)src/Composition/|(^|/)Program\.cs$|Module\.cs$|ServiceCollectionExtensions\.cs$|(^|/)Routes\.razor$|(^|/)ids\.yaml$'
$fileOrderWhyRx = '^\s*(file[- ]order\b|shared[- ]file\b|orders?\s+(the\s+)?(edits?|writes?)\s+(to|of|on|in)\b|both\s+(rows?\s+)?(write|edit|touch)\b)'
function Test-AppliedEdge($x, [string] $d) {
    $aRx = "Find-ArtificialBlockers -Apply: $([regex]::Escape($d)) ahead of ([^\s(]+)"
    foreach ($h in @($x.history)) { $m = [regex]::Match([string]$h.note, $aRx); if ($m.Success -and @($m.Groups[1].Value -split ',') -contains [string]$x.id) { return $true } }
    $false
}
function Get-EdgeKind($x, [string] $d) {
    $dt = $by[$d]
    if (-not $dt) { return @{ kind = 'logical'; reason = 'unknown row'; files = @() } }
    if ($d -in $Hubs) { return @{ kind = 'logical'; reason = 'hub'; files = @() } }
    # A reason in the row's dependsWhy map states the order (plan item IN-20261018143920-ebda, kit IN-20261018144659-fdff).
    # A reason that only states the shared-file order ('file order: both write X', 'orders edits to shared X') is not a
    # logical prerequisite: the edge is still classed by its files below (kit item IN-20261018194608-2617).
    $why = Get-DepWhy $x $d
    if ($why -and $why -notmatch $fileOrderWhyRx) { return @{ kind = 'logical'; reason = 'stated'; files = @() } }
    if ([string]$dt.kind -in @('gate', 'integration')) { return @{ kind = 'gate'; reason = [string]$dt.kind; files = @() } }
    if ([string]$dt.state -eq 'building' -or (Test-ClaimLive $dt)) { return @{ kind = 'landing'; reason = [string]$dt.state; files = @() } }
    # A title that names d states the order itself (G13.T012 'extends G13.T011 ...'): kit item IN-20261018071721-f123.
    if ([string]$x.title -match "(?<![\w.])$([regex]::Escape($d))(?![\w])") { return @{ kind = 'logical'; reason = 'named in title'; files = @() } }
    # An edge an earlier -Apply wrote (x after d, its history note 'Find-ArtificialBlockers -Apply: d ahead of ...x...')
    # is an order already chosen: offering x ahead of d again would flip the pair back on every run (kit item
    # IN-20261021154436-6273).
    if (Test-AppliedEdge $x $d) { return @{ kind = 'logical'; reason = 'applied order'; files = @() } }
    $sh = @(@($dt.writeSet) | Where-Object { @($x.writeSet) -contains $_ })
    if (-not $sh.Count) { return @{ kind = 'logical'; reason = 'no shared file'; files = @() } }
    if ([string]$dt.state -notin @('ticketed', 'planned')) { return @{ kind = 'logical'; reason = [string]$dt.state; files = $sh } }
    $sub = if (@($sh | Where-Object { $_ -notmatch $compRx }).Count) { 'review' } else { 'composition' }
    @{ kind = 'file-order'; reason = $sub; files = $sh }
}
# One scan of the board as it is now; -Apply calls it again after every batch it writes.
function Get-Scan {
    $script:doc = Read-Tasks $P
    $script:focus = Get-FocusSet $script:doc $P
    $script:by = @{}; foreach ($t in $script:doc.tasks) { $script:by[[string]$t.id] = $t }
    $rows = @(); $counts = [ordered]@{ logical = 0; landing = 0; gate = 0; 'file-order' = 0 }
    foreach ($x in $doc.tasks) {
        if ([string]$x.state -notin @('ticketed', 'planned') -or -not $focus.Contains([string]$x.id) -or (Test-ClaimLive $x)) { continue }
        $unmet = @(@($x.dependsOn) | Where-Object { $_ -and ([string]$by[$_].state) -notin $landed })
        if (-not $unmet.Count) { continue }
        $edges = @(foreach ($d in $unmet) { $e = Get-EdgeKind $x $d; $counts[$e.kind]++; [pscustomobject]@{ dep = $d; kind = $e.kind; reason = $e.reason; files = @($e.files) } })
        # Ancestors reached through a file-order edge must be file-order too: X may jump only rows it shares a file with,
        # so it inherits no logical prerequisite through the row it moves ahead of.
        $flip = @(); $files = @(); $bad = $null
        $seen = [Collections.Generic.HashSet[string]]::new(); $q = [Collections.Generic.Queue[string]]::new()
        foreach ($d in $unmet) { if ($seen.Add($d)) { $q.Enqueue($d) } }
        while ($q.Count) {
            $d = $q.Dequeue(); $e = Get-EdgeKind $x $d
            if ($e.kind -ne 'file-order') { $bad = "$d $($e.kind) ($($e.reason))"; break }
            $flip += $d; $files += $e.files
            # An order an earlier -Apply chose inside the chain (d after a) is kept: jumping it undoes that choice.
            foreach ($a in @($by[$d].dependsOn)) { if ($a -and ([string]$by[$a].state) -notin $landed -and (Test-AppliedEdge $by[$d] $a)) { $bad = "$d after $a logical (applied order)"; break } }
            if ($bad) { break }
            foreach ($a in @($by[$d].dependsOn)) { if ($a -and ([string]$by[$a].state) -notin $landed -and $seen.Add($a)) { $q.Enqueue($a) } }
        }
        $files = @($files | Select-Object -Unique)
        $sub = if (-not $files.Count) { $null } elseif (@($files | Where-Object { $_ -notmatch $compRx }).Count) { 'review' } else { 'composition' }
        $rows += [pscustomobject]@{ id = [string]$x.id; group = [string]$x.group; state = [string]$x.state; candidate = (-not $bad); kind = $sub; flipAhead = $flip; files = $files; keptBecause = $bad; edges = $edges }
    }
    @{ rows = $rows; counts = $counts }
}
# The build-claimable count, read in a child process: Get-Claimable reads inbox holds through lib state
# ($script:InboxSkills) that is missing when this script runs inside a session that loaded the lib already.
function Get-ClaimableCount {
    $lib = Join-Path $PSScriptRoot 'lib\Streams.ps1'; $ibx = Join-Path $PSScriptRoot 'lib\Inbox.ps1'
    $n = @(pwsh -NoProfile -Command ". '$($lib -replace "'", "''")'; . '$($ibx -replace "'", "''")'; `$p = Get-StreamPaths '$($Repo -replace "'", "''")'; (Get-Claimable `$p (Read-Tasks `$p) 'build').ids.Count" 2>&1)
    if ($LASTEXITCODE -ne 0 -or "$($n[-1])" -notmatch '^\d+$') { return '?' }
    [int]"$($n[-1])"
}
if ($Apply) {
    $before = Get-ClaimableCount
    $moved = [Collections.Generic.HashSet[string]]::new(); $tried = [Collections.Generic.HashSet[string]]::new()
    $applied = @(); $skipped = @()
    while ($true) {
        $sc = Get-Scan
        $c = @($sc.rows | Where-Object { $_.candidate -and -not $tried.Contains($_.id) }) | Select-Object -First 1
        if (-not $c) { break }
        [void]$tried.Add($c.id)
        $hit = @(@($c.id) + @($c.flipAhead) | Where-Object { $moved.Contains($_) })
        if ($hit.Count) { $skipped += "$($c.id) (moved this run: $($hit -join ','))"; "SKIPPED $($c.id) : ahead of $($hit -join ',') moved this run"; continue }
        $x = $by[$c.id]
        $direct = @(@($x.dependsOn) | Where-Object { $_ -in $c.flipAhead })
        $why = "Find-ArtificialBlockers -Apply: $($c.id) ahead of $($c.flipAhead -join ',') (file-order $($c.kind): $($c.files -join ', '))"
        $edits = @(@{ task = $c.id; removeDependsOn = $direct; release = 'keep'; note = $why })
        foreach ($d in $direct) { $edits += @{ task = $d; addDependsOn = @($c.id); release = 'keep'; note = $why } }
        foreach ($y in $doc.tasks) {
            if (@($y.dependsOn) -notcontains $c.id -or [string]$y.state -in $landed) { continue }
            $add = @($direct | Where-Object { @($y.dependsOn) -notcontains $_ })
            if ($add.Count) {
                # A moved edge takes its stated reason with it (kit item IN-20261018144659-fdff).
                $dw = @{}; foreach ($a in $add) { if (Get-DepWhy $x $a) { $dw[$a] = Get-DepWhy $x $a } }
                $edits += @{ task = [string]$y.id; addDependsOn = $add; dependsWhy = $dw; release = 'keep'; note = "$why; keeps $($y.id) after $($add -join ',')" }
            }
        }
        $bf = Join-Path ([IO.Path]::GetTempPath()) "speedy-artblk-$PID-$([guid]::NewGuid().ToString('N').Substring(0, 8)).json"
        @{ note = $why; edits = $edits } | ConvertTo-Json -Depth 6 | Set-Content $bf -Encoding utf8
        # A child process: called in-process, Revise-Task.ps1's lib load sees this script's functions and skips the
        # state its own script scope needs ($script:InboxSkills).
        try { $out = @(pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Revise-Task.ps1') -Repo $Repo -Session $Session -File $bf 2>&1); $code = $LASTEXITCODE }
        finally { Remove-Item $bf -ErrorAction SilentlyContinue }
        if ($code -eq 0) {
            [void]$moved.Add($c.id); foreach ($d in $c.flipAhead) { [void]$moved.Add($d) }
            $applied += "$($c.id) ahead of $($c.flipAhead -join '+')"; "APPLIED $($c.id) ahead of $($c.flipAhead -join ',')"
        } else {
            $ref = @($out | Where-Object { "$_" -like 'REFUSED*' } | ForEach-Object { "$_" }) -join '; '
            $skipped += "$($c.id) ($ref)"; "SKIPPED $($c.id) : $ref"
        }
    }
    $after = Get-ClaimableCount
    $line = "APPLY applied $($applied.Count) skipped $($skipped.Count) claimable before $before after $after"
    Add-Decision $P $Session "Find-ArtificialBlockers: $line; applied: $($applied -join '; '); skipped: $($skipped -join '; ')"
    $line
    return
}
$sc = Get-Scan; $rows = $sc.rows; $counts = $sc.counts
$cand = @($rows | Where-Object candidate)
$summary = "SUMMARY waiting $($rows.Count) candidates $($cand.Count) (composition $(@($cand | Where-Object kind -eq 'composition').Count), review $(@($cand | Where-Object kind -eq 'review').Count)) edges logical $($counts.logical) landing $($counts.landing) gate $($counts.gate) file-order $($counts['file-order'])"
if ($Session) { Add-Decision $P $Session "Find-ArtificialBlockers: $summary; candidates: $(@($cand | ForEach-Object { "$($_.id) ahead of $($_.flipAhead -join '+')" }) -join '; ')" }
if ($Json) { @{ rows = $rows; counts = $counts; summary = $summary } | ConvertTo-Json -Depth 6; return }
foreach ($c in $cand) { "CANDIDATE $($c.kind)`t$($c.id) ahead of $($c.flipAhead -join ',') | $($c.files -join ', ')" }
$summary
