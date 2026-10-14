$root  = Join-Path $env:USERPROFILE '.claude\projects'
$since = (Get-Date).AddDays(-7)
$files = @(Get-ChildItem $root -Recurse -Filter *.jsonl -ErrorAction SilentlyContinue |
           Where-Object { $_.LastWriteTime -gt $since })

$counts = @{}; $turnsAfter = @{}
$targets = 'testauto-multistep-steps','testauto-matching-scenarios','crewchief-remote-box-prep','crewchief-web-ui','testauto-workflow-execution'

foreach ($f in $files) {
    $turn = 0; $hits = @()
    foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $o = $line | ConvertFrom-Json -ErrorAction Stop } catch { continue }
        if ($o.type -ne 'assistant' -or -not $o.message) { continue }
        if ($o.message.usage) { $turn++ }
        foreach ($blk in $o.message.content) {
            if ($blk.type -eq 'tool_use' -and $blk.name -eq 'Skill') {
                $s = $blk.input.skill
                if ($targets -contains $s) { $hits += [pscustomobject]@{ Skill = $s; Turn = $turn } }
            }
        }
    }
    foreach ($h in $hits) {
        if (-not $counts.ContainsKey($h.Skill)) { $counts[$h.Skill] = 0; $turnsAfter[$h.Skill] = 0 }
        $counts[$h.Skill]++
        $turnsAfter[$h.Skill] += [Math]::Max(0, $turn - $h.Turn)
    }
}

"transcripts scanned (7d): {0}" -f $files.Count
""
"{0,-30} {1,6} {2,12} {3,12}" -f 'skill','calls','turns_after','avg_after'
foreach ($t in $targets) {
    $c = if ($counts.ContainsKey($t)) { $counts[$t] } else { 0 }
    $a = if ($turnsAfter.ContainsKey($t)) { $turnsAfter[$t] } else { 0 }
    $avg = if ($c -gt 0) { [math]::Round($a / $c) } else { 0 }
    "{0,-30} {1,6} {2,12:N0} {3,12:N0}" -f $t, $c, $a, $avg
}
