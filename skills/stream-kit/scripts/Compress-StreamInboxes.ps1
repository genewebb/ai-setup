# Moves closed inbox items out of the live role inboxes so a session that reads an inbox pays only for live work
# (kit item IN-20261123164855-93f4: stream-plan.md reached 5.2 MB on 2026-11-23).
#   An item moves when its latest status is done or declined and that status is older than -KeepDays. All of its lines
#   move together, in their order, to .streams\inbox\archive\<skill>-<yyyy-MM>.md, the month of its closing line.
#   Open, taken, forwarded and any other item stays with its whole history.
#   Each inbox is rewritten under its own per-file lock (Invoke-InboxLocked), the lock Send-InboxItem.ps1 and
#   Set-InboxItem.ps1 append under, so a send or status line racing the rewrite is never lost.
#   The archive is appended before the inbox is rewritten: a crash between the two leaves an item in both, never in
#   neither.
# Prints one "COMPRESSED <skill> items <n> lines <n> bytes <before> -> <after>" line per inbox (WOULD-COMPRESS with
# -DryRun, nothing written), then "COMPRESS-DONE items <n> lines <n>". Exit 0.
param(
    [Parameter(Mandatory)] [string] $Repo,
    [int] $KeepDays = 14,
    [string] $Session = 'compress-inboxes',
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Inbox.ps1"
$P = Get-StreamPaths (Resolve-Path $Repo).Path
$cutoff = (Get-Date).ToUniversalTime().AddDays(-$KeepDays)
$archDir = Join-Path $P.Root 'inbox\archive'
$enc = [Text.UTF8Encoding]::new($false)
$totItems = 0; $totLines = 0

function ConvertFrom-InboxTime([string] $s) {
    [datetime]::Parse($s, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AdjustToUniversal)
}

foreach ($skill in $script:InboxSkills) {
    $path = Get-InboxPath $P $skill
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $result = $null
    $work = {
        $before = (Get-Item -LiteralPath $path).Length
        $move = @{}
        foreach ($it in @(Read-InboxItems $path)) {
            if ($it.status -notin @('done', 'declined')) { continue }
            $at = try { ConvertFrom-InboxTime $it.statusAt } catch { continue }
            if ($at -lt $cutoff) { $move[$it.id] = $at.ToString('yyyy-MM') }
        }
        $keep = [Collections.Generic.List[string]]::new()
        $out = [ordered]@{}
        $nLines = 0
        foreach ($l in [IO.File]::ReadAllLines($path)) {
            if ($l -match '^- (IN-\S+) \| ' -and $move.ContainsKey($Matches[1])) {
                $m = $move[$Matches[1]]
                if (-not $out.Contains($m)) { $out[$m] = [Collections.Generic.List[string]]::new() }
                $out[$m].Add($l); $nLines++
            } else { $keep.Add($l) }
        }
        $after = $before
        if ($move.Count -and -not $DryRun) {
            if (-not (Test-Path $archDir)) { New-Item -ItemType Directory -Path $archDir -Force | Out-Null }
            foreach ($m in $out.Keys) {
                $af = Join-Path $archDir "$skill-$m.md"
                if (-not (Test-Path -LiteralPath $af)) { [IO.File]::WriteAllText($af, "# Inbox archive: $skill $m`n`nClosed items moved whole by Compress-StreamInboxes.ps1. Same line format as the live inbox.`n`n", $enc) }
                [IO.File]::AppendAllText($af, (($out[$m] -join "`n") + "`n"), $enc)
            }
            Write-AtomicText $path (($keep -join "`n") + "`n")
            $after = (Get-Item -LiteralPath $path).Length
        } elseif ($move.Count) {
            $after = $before - ((@($out.Values | ForEach-Object { $_ }) | ForEach-Object { $enc.GetByteCount($_) + 1 }) | Measure-Object -Sum).Sum
        }
        $script:result = @{ items = $move.Count; lines = $nLines; before = $before; after = $after }
        @()
    }
    if ($DryRun) { & $work | Out-Null } else { [void](Invoke-InboxLocked $path $Session $work) }
    $r = $script:result
    $totItems += $r.items; $totLines += $r.lines
    '{0} {1} items {2} lines {3} bytes {4} -> {5}' -f $(if ($DryRun) { 'WOULD-COMPRESS' } else { 'COMPRESSED' }), $skill, $r.items, $r.lines, $r.before, $r.after
}
"COMPRESS-DONE items $totItems lines $totLines$(if ($DryRun) { ' (dry run)' })"
exit 0
