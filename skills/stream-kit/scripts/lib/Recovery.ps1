# Recovery helpers for the stream kit: grader identity, patch file lists, content comparison and the kit-supplied
# "since" time. Dot-sourced after Streams.ps1 by Integrate-Patch and Invoke-Grader.

# Reads a nested field of a task (hashtables from ConvertFrom-Json -AsHashtable) without tripping strict mode, which
# throws on a missing key read through dot access. Returns $null when any step is missing.
#   Get-Field $task 'base', 'at'
function Get-Field($Obj, [string[]] $Path) {
    $cur = $Obj
    foreach ($k in $Path) {
        if ($null -eq $cur) { return $null }
        if ($cur -is [Collections.IDictionary]) { if (-not $cur.Contains($k)) { return $null }; $cur = $cur[$k] }
        else { $p = $cur.PSObject.Properties[$k]; if (-not $p) { return $null }; $cur = $p.Value }
    }
    $cur
}

function Get-Hash16([byte[]] $Bytes) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { [BitConverter]::ToString($sha.ComputeHash($Bytes)).Replace('-', '').Substring(0, 16) } finally { $sha.Dispose() }
}

# Identity of a grader: its own bytes plus the bytes of every .ps1 it names by absolute path (an import shim calls the
# real grader elsewhere), so a change to either changes the hash.
function Get-GraderHash([string] $Grader) {
    $text = Get-Content -Raw $Grader
    $parts = [Collections.Generic.List[byte]]::new()
    $parts.AddRange([IO.File]::ReadAllBytes($Grader))
    foreach ($m in [regex]::Matches($text, "['""]([A-Za-z]:\\[^'""]+?\.ps1)['""]")) {
        $p = $m.Groups[1].Value
        if (Test-Path -LiteralPath $p) { $parts.AddRange([IO.File]::ReadAllBytes($p)) }
    }
    Get-Hash16 $parts.ToArray()
}

# Repo-relative paths a patch writes (new side of each diff; deletions keep the old path).
function Get-PatchPaths([string] $Patch) {
    $out = [Collections.Generic.List[string]]::new()
    foreach ($l in [IO.File]::ReadLines($Patch)) {
        if ($l -match '^diff --git a/(.+?) b/(.+)$') { $out.Add($Matches[2]) }
    }
    @($out | Select-Object -Unique)
}

# True when every path has the same content in both trees, line endings ignored (autocrlf re-stamps checkouts).
function Test-SameContent([string] $TreeA, [string] $TreeB, [string[]] $Paths) {
    foreach ($p in $Paths) {
        $a = Join-Path $TreeA $p; $b = Join-Path $TreeB $p
        $ea = Test-Path -LiteralPath $a -PathType Leaf; $eb = Test-Path -LiteralPath $b -PathType Leaf
        if ($ea -ne $eb) { return $false }
        if (-not $ea) { continue }
        $ta = ([IO.File]::ReadAllText($a)) -replace "`r`n", "`n"
        $tb = ([IO.File]::ReadAllText($b)) -replace "`r`n", "`n"
        if ($ta -ne $tb) { return $false }
    }
    $true
}

# Clause ids from grader output lines "PASS C1" / "FAIL C1: why".
function Get-ClauseIds($Lines, [string] $Verdict) {
    @($Lines | ForEach-Object { if ("$_" -match "^$Verdict\s+([^\s:]+)") { $Matches[1] } } | Select-Object -Unique)
}

# The kit's "since" for a grader run, exported as STREAM_SINCE_UTC: evidence a grader demands must be newer than this.
#   integration task : the latest patch that CHANGED the tree in its group (its suites must run after it landed)
#   any other task   : when the current claim started, else the base was laid, else empty (no freshness demand)
# Only a built>integrated move counts, and not one the integrator records as "no tree change" (mockup, in place).
# Every note written on an integrated row repeats to=integrated (a grader re-author, a plan revise), and counting
# those moved G1.T09's since past suite run 4 on 2026-10-01 (kit item IN-20261001210748-4ba7).
function Get-TaskSince($doc, $Task) {
    $times = @()
    if ($Task.kind -eq 'integration') {
        foreach ($o in @($doc.tasks | Where-Object { $_.group -eq $Task.group })) {
            $prev = $null
            foreach ($h in @($o.history)) {
                if ($h.to -eq 'integrated' -and $prev -eq 'built' -and "$($h.note)" -notmatch 'no tree change') { $times += [string]$h.at }
                $prev = $h.to
            }
        }
    }
    if (-not $times.Count) {
        $claimAt = Get-Field $Task 'claim', 'at'
        $baseAt = Get-Field $Task 'base', 'at'
        if ($claimAt) { $times += [string]$claimAt }
        elseif ($baseAt) { $times += [string]$baseAt }
    }
    if (-not $times.Count) { return '' }
    @($times | Sort-Object)[-1]
}
