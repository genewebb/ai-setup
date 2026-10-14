# Board ordering rules shared by Test-BoardOrder.ps1 and Revise-Task.ps1 (dot-source after lib\Streams.ps1).
# The board is ordered when:
#   - every dependsOn id exists and the dependsOn graph has no cycle;
#   - no two OPEN tasks (not integrated/done, not gate/integration) share a write-set path (same path, or a wildcard
#     entry matching it, as Test-WriteSetOverlap reads them) unless one depends on the other, directly or transitively.
# Two unordered open tasks on one file are built on different bases and collide at integration.

function Get-BoardProblems($Tasks) {
    $problems = [Collections.Generic.List[string]]::new()
    $byId = @{}
    foreach ($t in @($Tasks)) { if ($t) { $byId[[string]$t['id']] = $t } }
    function DepsOf($t) { if ($t -is [Collections.IDictionary]) { if ($t.Contains('dependsOn')) { @($t['dependsOn'] | Where-Object { $_ }) } else { @() } } else { @($t.dependsOn | Where-Object { $_ }) } }

    foreach ($t in $byId.Values) { foreach ($d in DepsOf $t) { if (-not $byId.ContainsKey([string]$d)) { $problems.Add("UNKNOWN-DEP $($t['id']) -> $d") } } }

    # ancestors (transitive dependsOn) per task, iterative, with cycle detection
    $anc = @{}; $state = @{}   # state: 1 = on the stack, 2 = done
    foreach ($root in @($byId.Keys)) {
        if ($state[$root] -eq 2) { continue }
        $stack = [Collections.Generic.Stack[object]]::new()
        $stack.Push(@($root, 0))
        while ($stack.Count) {
            $frame = $stack.Pop(); $id = $frame[0]; $i = $frame[1]
            $deps = @(DepsOf $byId[$id] | Where-Object { $byId.ContainsKey([string]$_) })
            if ($i -eq 0) { $state[$id] = 1 }
            if ($i -lt $deps.Count) {
                $stack.Push(@($id, ($i + 1)))
                $d = [string]$deps[$i]
                if ($state[$d] -eq 1) { $problems.Add("CYCLE $id -> $d") }
                elseif ($state[$d] -ne 2) { $stack.Push(@($d, 0)) }
                continue
            }
            $set = [Collections.Generic.HashSet[string]]::new()
            foreach ($d in $deps) { [void]$set.Add([string]$d); if ($anc.ContainsKey([string]$d)) { $set.UnionWith($anc[[string]$d]) } }
            $anc[$id] = $set; $state[$id] = 2
        }
    }
    if (@($problems | Where-Object { $_ -like 'CYCLE*' }).Count) { return , $problems }

    # unordered write-set overlaps among open tasks
    $open = @($byId.Values | Where-Object { $_['state'] -notin @('integrated', 'done') -and $_['kind'] -notin @('gate', 'integration') })
    $exact = @{}; $wild = [Collections.Generic.List[object]]::new(); $all = [Collections.Generic.List[object]]::new()
    foreach ($t in $open) {
        foreach ($w in @($t['writeSet'])) {
            if (-not $w) { continue }
            $p = ConvertTo-RepoRel ([string]$w)
            $all.Add(@($t['id'], $p))
            if ($p -match '[\*\?\[]') { $wild.Add(@($t['id'], $p)) }
            else { if (-not $exact.ContainsKey($p)) { $exact[$p] = [Collections.Generic.List[string]]::new() }; $exact[$p].Add([string]$t['id']) }
        }
    }
    $seen = [Collections.Generic.HashSet[string]]::new()
    function Pair($a, $b, $file) {
        if ($a -eq $b) { return }
        $key = if ($a -lt $b) { "$a|$b" } else { "$b|$a" }
        if (-not $seen.Add("$key|$file")) { return }
        if ($anc[$a].Contains($b) -or $anc[$b].Contains($a)) { return }
        $problems.Add("UNORDERED $a / $b : $file")
    }
    foreach ($p in $exact.Keys) { $ids = @($exact[$p] | Select-Object -Unique); for ($i = 0; $i -lt $ids.Count; $i++) { for ($j = $i + 1; $j -lt $ids.Count; $j++) { Pair $ids[$i] $ids[$j] $p } } }
    foreach ($w in $wild) { foreach ($o in $all) { if ($o[1] -like $w[1] -or $w[1] -like $o[1]) { Pair $w[0] $o[0] $w[1] } } }
    , $problems
}
