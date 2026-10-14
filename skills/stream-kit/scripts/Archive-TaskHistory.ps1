# Shrinks tasks.json and decisions.md without removing a row (2026-10-05 priority-focus-design E2). Script only.
#   Archive-TaskHistory.ps1 -Repo <repo> -Session <id> [-Days 7] [-DryRun]
# Rows never leave tasks.json: 65 open rows depended on closed-group rows on 2026-10-05, Get-Task throws on a missing
# id and Get-BoardProblems would refuse every revision. Only the HISTORY of a `done` row whose last entry is older than
# -Days moves: it is appended to .streams\archive\<group>.history.json ({ "<id>": [entries...] }) and the row keeps a
# stub of at most two entries - its last `integrated` entry (Test-GroupClose.ps1 and the Priority page read the
# integration time) and its last entry, whose note then names the archive. Every reader keeps working: state, write
# set, dependsOn and claim are untouched, and the stub still ends in `done`.
# decisions.md: lines of earlier months move to .streams\archive\decisions-<yyyy-MM>.md (appended); the header line
# and the current month stay. The file is held exclusively while it is rewritten; Add-Decision retries a busy file.
# Prints "ARCHIVED rows <n> entries <n> decisions <n> lines" (or the same after DRY-RUN), exit 0.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [int] $Days = 7,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$arch = Join-Path $P.Root 'archive'
if (-not $DryRun -and -not (Test-Path $arch)) { New-Item -ItemType Directory -Path $arch -Force | Out-Null }
$cut = [datetime]::UtcNow.AddDays(-$Days)
$utc = { param([string] $s) [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal) }

# ---- task history ----
$moved = @{}   # group -> ordered map id -> entries
$nRows = 0; $nEntries = 0
$work = {
    param($doc)
    foreach ($t in $doc.tasks) {
        if ($t.state -ne 'done') { continue }
        $h = @($t.history | Where-Object { $_ })
        if ($h.Count -le 2) { continue }
        $last = $h[-1]
        if (-not $last.Contains('at')) { continue }
        try { if ((& $utc ([string]$last.at)) -gt $cut) { continue } } catch { continue }
        $g = [string]$t.group
        if (-not $moved.ContainsKey($g)) { $moved[$g] = [ordered]@{} }
        $moved[$g][[string]$t.id] = $h
        $integ = @($h | Where-Object { $_.Contains('to') -and $_.to -eq 'integrated' } | Select-Object -Last 1)
        $tail = [ordered]@{}; foreach ($k in $last.Keys) { $tail[$k] = $last[$k] }
        $tail['note'] = "$([string]$last['note']) [history archived: .streams\archive\$g.history.json, $($h.Count) entries]".TrimStart()
        $t.history = @(@($integ) + $tail | Where-Object { $_ })
        $script:nRows++; $script:nEntries += $h.Count
    }
    if ($DryRun -or -not $moved.Count) { return $null }   # nothing moved: tasks.json is not rewritten
    $doc
}
if ($DryRun) { & $work (Read-Tasks $P) | Out-Null }
else {
    # The archive is written BEFORE tasks.json gives the entries up: a crash in between leaves them in both places,
    # never in neither. A row archived twice is appended twice under its id; the newest copy wins on read.
    [void](Invoke-TasksLocked $P $Session {
        param($doc)
        $r = & $work $doc
        foreach ($g in $moved.Keys) {
            $f = Join-Path $arch "$g.history.json"
            $have = [ordered]@{}
            if (Test-Path -LiteralPath $f) { $have = Get-Content -Raw -LiteralPath $f | ConvertFrom-Json -AsHashtable -DateKind String -Depth 50 }
            foreach ($id in $moved[$g].Keys) { $have[$id] = $moved[$g][$id] }
            Write-AtomicText $f ($have | ConvertTo-Json -Depth 50)
        }
        $r
    })
}

# ---- decisions.md ----
$nDec = 0
$month = [datetime]::UtcNow.ToString('yyyy-MM')
if (Test-Path -LiteralPath $P.Decisions) {
    $fs = $null
    for ($i = 0; -not $fs; $i++) {
        try { $fs = [IO.File]::Open($P.Decisions, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
        catch [IO.IOException] { if ($i -ge 50) { throw }; Start-Sleep -Milliseconds 100 }
    }
    try {
        $sr = [IO.StreamReader]::new($fs, [Text.UTF8Encoding]::new($false), $false, 4096, $true)
        $text = $sr.ReadToEnd(); $sr.Dispose()
        $keep = [Collections.Generic.List[string]]::new(); $old = [ordered]@{}
        foreach ($l in ($text -split "`n")) {
            if ($l -match '^- (\d{4}-\d{2})-\d{2}T' -and $Matches[1] -lt $month) {
                if (-not $old.Contains($Matches[1])) { $old[$Matches[1]] = [Collections.Generic.List[string]]::new() }
                $old[$Matches[1]].Add($l); $nDec++
            } else { $keep.Add($l) }
        }
        if ($nDec -and -not $DryRun) {
            foreach ($m in $old.Keys) { [IO.File]::AppendAllText((Join-Path $arch "decisions-$m.md"), (($old[$m] -join "`n") + "`n"), [Text.UTF8Encoding]::new($false)) }
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($keep -join "`n"))
            $fs.SetLength(0); $fs.Write($bytes, 0, $bytes.Length)
        }
    } finally { $fs.Dispose() }
}
$line = "rows $nRows entries $nEntries decisions $nDec lines"
if ($DryRun) { "DRY-RUN ARCHIVED $line"; exit 0 }
if ($nRows -or $nDec) { Add-Decision $P $Session "ARCHIVED $line (older than $Days days / before $month)" }
"ARCHIVED $line"
exit 0
