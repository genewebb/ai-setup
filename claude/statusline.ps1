# ~/.claude/statusline.ps1 — Claude Code custom status line (PowerShell; single-process, Windows-fast).
# Claude Code pipes a status JSON blob on stdin every refresh (schema:
# https://code.claude.com/docs/en/statusline) and renders whatever this prints. Two-tone styling:
# labels bright white, values bright green, escalation colors override values (yellow/bold red). Three lines
# (line 1 below prints as two rows: the meters, then branch onward, so nothing is cut off on the right):
#   line 1 — model, context (green <50%, yellow 50-74%, bold red ≥75% + "compact!";
#            shows "(NNN left)" once ≥50%), per-model SESSION tokens "Fable ↓in ↑out  Opus ↓in ↑out"
#            (from this session's transcripts incl. subagents — stdin's totals omit subagents; falls back to
#            stdin ↓/↑ until the scan has data), then the SAME THREE QUOTA METERS /usage renders, in
#            its order: "5 Hour" (its "Current session") and "All Models 7d" (its "Current week (all
#            models)"), both from stdin's rate_limits with reset countdown+wall time,
#            then one "<Model> 7d:" segment per model-scoped weekly quota bucket the server publishes
#            (e.g. "Fable 7d:28%") — these are NOT on stdin, see the quota fetcher below — git branch
#            (with `*` when tracked files are dirty), dir, repo owner, Acct: (full OAuth email
#            from ~/.claude.json), session name (≤16 chars, else short session id), session elapsed
#            (⧗ from transcript creation time), +/- lines
#   line 2 — permission mode + effort/thinking/fast/output_style from stdin
# No dollar figures anywhere: this footer is about quota, not spend.
# Why PowerShell and not bash+jq on Windows: this stays ONE process (~1s). The bash variant spawns ~5-7
# processes (jq, tr, git, date×2) and clocks ~1.7s here, because Windows process creation is costly.
#
# Debug: set $env:CLAUDE_STATUSLINE_DEBUG=1 (before launching Claude Code) OR touch
#   $env:TEMP\claude-statusline-debug.on (works on a running session) to dump the latest stdin JSON to
#   $env:TEMP\claude-statusline-last.json  (use this to discover new schema fields).

$ErrorActionPreference = 'SilentlyContinue'
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch { }  # keep the ↓↑→ glyphs intact
# pwsh 7.2+ strips VT escape sequences from redirected output by default (OutputRendering=Host),
# and Claude Code reads this script through a pipe — without this, every color code is silently
# removed and the whole line renders monochrome. 5.1 lacks $PSStyle; the try swallows that.
try { $PSStyle.OutputRendering = 'Ansi' } catch { }

# Config-dir aware. An alternate profile (CLAUDE_CONFIG_DIR, e.g. a personal login under
# ~\.claude-home) keeps its OWN transcripts, caches, credentials and .claude.json, so read those
# instead of ~\.claude's — otherwise session tokens, quota and Acct: describe the wrong profile.
# Unset (the normal work profile) resolves to ~\.claude exactly as before.
$CfgDir   = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $HOME '.claude' }
# .claude.json lives INSIDE the config dir when CLAUDE_CONFIG_DIR is set, next to $HOME otherwise.
$AcctJson = if ($env:CLAUDE_CONFIG_DIR) { Join-Path $CfgDir '.claude.json' } else { Join-Path $HOME '.claude.json' }

# Read stdin once so we can BOTH debug-dump and parse (ConvertFrom-Json is destructive on the pipe).
$stdinRaw = [Console]::In.ReadToEnd()
if ($env:CLAUDE_STATUSLINE_DEBUG -or (Test-Path -LiteralPath "$env:TEMP\claude-statusline-debug.on")) {
    try { Set-Content -LiteralPath "$env:TEMP\claude-statusline-last.json" -Value $stdinRaw -NoNewline } catch { }
}
try { $j = $stdinRaw | ConvertFrom-Json } catch { return }
if (-not $j) { return }

$E = [char]27
function C([string]$code, $t) { "$E[${code}m$t$E[0m" }

# Return first non-null arg (schema-fallback helper; treats 0 and $false as valid values).
function Coalesce { foreach ($v in $args) { if ($null -ne $v) { return $v } } ; return $null }

# Truncating integer division for h/m breakdown — [int] would banker-round .5 (e.g. 5400s → 2h00m).
function Remaining([double]$epoch) {
    $r = [int64]($epoch - [DateTimeOffset]::UtcNow.ToUnixTimeSeconds())
    if ($r -le 0) { return 'now' }
    $d = [int][Math]::Floor($r / 86400)
    $h = [int][Math]::Floor(($r % 86400) / 3600)
    $m = [int][Math]::Floor(($r % 3600) / 60)
    if ($d -ge 1) { '{0}d{1:00}h' -f $d, $h } else { '{0}h{1:00}m' -f $h, $m }
}
function Clock([double]$epoch) {
    $lt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$epoch).ToLocalTime()
    if ($lt.Date -eq (Get-Date).Date) { $lt.ToString('h:mmtt').ToLower() }
    else { $lt.ToString('ddd h:mmtt').ToLower() }
}
function TokFmt([long]$n) {
    if ($n -ge 1000000) { '{0:N1}M' -f ($n / 1000000.0) }
    elseif ($n -ge 1000) { '{0:N1}K' -f ($n / 1000.0) }
    else { "$n" }
}
# Compact elapsed formatter: <60m → "12m", <24h → "1h32m", else "2d05h".
function ElapsedFmt([TimeSpan]$ts) {
    if ($ts.TotalDays -ge 1)   { '{0}d{1:00}h' -f [int]$ts.TotalDays, $ts.Hours }
    elseif ($ts.TotalHours -ge 1) { '{0}h{1:00}m' -f [int]$ts.TotalHours, $ts.Minutes }
    else { '{0}m' -f [int][Math]::Max(1, $ts.TotalMinutes) }
}
# Two-tone scheme: every label renders bright white (97); every value renders bright green (92)
# unless a semantic escalation color overrides it (ctx/rate thresholds below: yellow=warn,
# bold red=critical). Both tones are bright so label and value each stand out, while staying
# visually distinct from each other.
$LblC = '97'   # labels — bright white
$ValC = '92'   # values — bright green (default)

# Rate-limit segment: value green <70%, yellow 70-89%, red ≥90%.
# Always shows the reset countdown+wall-time when resets_at is a valid future epoch;
# suppresses the parenthetical only when the timestamp is missing/in the past (which
# would otherwise render as the meaningless "now→…").
function RateSeg([string]$label, $rl) {
    if (-not $rl) { return $null }
    $pct    = [int][Math]::Floor([double](Coalesce $rl.used_percentage 0))
    $resets = [double](Coalesce $rl.resets_at 0)
    $color  = if ($pct -ge 90) { '91' } elseif ($pct -ge 70) { '93' } else { $ValC }
    $nowEp  = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $val = if ($resets -le $nowEp) { '{0}%' -f $pct }
           else { '{0}% ({1}{2}{3})' -f $pct, (Remaining $resets), [char]0x2192, (Clock $resets) }
    (C $LblC "${label}:") + (C $color $val)
}

# ── per-model usage aggregator ───────────────────────────────────────────────────
# stdin gives session-wide token totals (main agent only, no subagents) and the unified rate-limit
# percentages. Neither says WHICH MODEL is consuming. The append-only transcripts under
# ~/.claude/projects do: every assistant line carries "model" + "usage", and subagent turns live in
# <session>/subagents/agent-*.jsonl, so an incremental scan can attribute usage per model family for
# the current session (tokens, incl. Executors dispatched on another model).
#
# This scan is deliberately NOT used for the 5h/7d meters. It once also rendered each family's share
# of the weighted usage in those windows ("[Fable 61% Opus 37%]"); that was removed because with a
# single model in play it read as a bare "Opus 100%" sitting next to real percentages, and was taken
# — reasonably — for an exhausted Opus limit. Quota now comes only from stdin and the server, which
# see every device; this scan only ever saw local transcripts.
#
# Cost control — a full scan is ~170 MB / ~20s, which would hang the footer:
#   * only files modified in the last 8 days are considered (a file older than that cannot
#     hold an entry inside the 7-day window),
#   * each file records the byte offset already scanned; .jsonl is append-only, so a refresh
#     reads only what was appended since,
#   * a per-invocation byte budget caps a cold/backfilling cache at ~1s, resuming next refresh,
#   * results are cached and only recomputed every $UsageRefreshSec.
# Cache lives at ~/.claude/statusline-usage.json and is disposable — delete it to rebuild.

$UsageRefreshSec = 60
$UsageByteBudget = 8MB

# Relative weights per MTok, lifted from the baked model catalog's pricing_tiers. Used ONLY to weight
# tokens so that a cache-read token and an output token are not counted alike when attributing a
# window across models. Nothing renders these as money.
$Weight = @{
    tier_3_15  = @{ i = 3.0;  o = 15.0; r = 0.30; w5 = 3.75;  w1 = 6.0  }
    tier_5_25  = @{ i = 5.0;  o = 25.0; r = 0.50; w5 = 6.25;  w1 = 10.0 }
    tier_10_50 = @{ i = 10.0; o = 50.0; r = 1.00; w5 = 12.50; w1 = 20.0 }
    tier_15_75 = @{ i = 15.0; o = 75.0; r = 1.50; w5 = 18.75; w1 = 30.0 }
    haiku_45   = @{ i = 1.0;  o = 5.0;  r = 0.10; w5 = 1.25;  w1 = 2.0  }
    haiku_35   = @{ i = 0.8;  o = 4.0;  r = 0.08; w5 = 1.00;  w1 = 1.6  }
}
$WeightTier = @{
    'claude-opus-5'     = 'tier_5_25';  'claude-opus-4-8'   = 'tier_5_25'
    'claude-opus-4-7'   = 'tier_5_25';  'claude-opus-4-6'   = 'tier_5_25'
    'claude-opus-4-5'   = 'tier_5_25'
    'claude-opus-4-1'   = 'tier_15_75'; 'claude-opus-4-0'   = 'tier_15_75'
    # Fable/Mythos 5.1 ship under their own wire ids (the "-1" is not a date suffix, so the
    # normalizer keeps it). Same 10/50 input/output rate as Fable 5; the 5.1 cache-read rate is
    # documented lower ($0.25 vs $1.00/MTok) but left on the shared tier until verified.
    'claude-fable-5-1'  = 'tier_10_50'; 'claude-mythos-5-1' = 'tier_10_50'
    'claude-fable-5'    = 'tier_10_50'; 'claude-mythos-5'   = 'tier_10_50'
    'claude-sonnet-5'   = 'tier_3_15';  'claude-sonnet-4-6' = 'tier_3_15'
    'claude-sonnet-4-5' = 'tier_3_15';  'claude-sonnet-4-0' = 'tier_3_15'
    'claude-3-7-sonnet' = 'tier_3_15';  'claude-3-5-sonnet' = 'tier_3_15'
    'claude-haiku-4-5'  = 'haiku_45';   'claude-3-5-haiku'  = 'haiku_35'
}

# Normalize a wire model id ("claude-opus-5[1m]", "claude-sonnet-4-5-20250929") to a catalog
# id, then to its weight row. Unknown models weigh zero (their tokens are still counted).
function ModelWeights([string]$model, [string]$speed) {
    if (-not $model) { return $null }
    $m = $model -replace '\[[^\]]*\]', '' -replace '-\d{8}$', '' -replace '-fast$', ''
    $t = $WeightTier[$m]
    if (-not $t) { return $null }
    if ($speed -eq 'fast' -and $t -eq 'tier_5_25') { $t = 'tier_10_50' }  # Opus fast mode weighs 10/50
    $Weight[$t]
}

# Display family for a wire model id. Mythos shares the Fable bucket server-side, so it is folded in.
$FamilyOrder = @('Fable', 'Opus', 'Sonnet', 'Haiku', 'Other')
function Family([string]$model) {
    if (-not $model) { return 'Other' }
    if ($model -match 'fable|mythos') { 'Fable' }
    elseif ($model -match 'opus')     { 'Opus' }
    elseif ($model -match 'sonnet')   { 'Sonnet' }
    elseif ($model -match 'haiku')    { 'Haiku' }
    else                              { 'Other' }
}

# Session id a transcript belongs to: "<proj>\<sid>.jsonl" or "<proj>\<sid>\subagents\agent-*.jsonl".
function SessionOf([System.IO.FileInfo]$f) {
    if ($f.Directory.Name -eq 'subagents' -and $f.Directory.Parent) { return $f.Directory.Parent.Name }
    [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
}

# Fold one usage record into a per-family accumulator: i/o/r/w = input/output/cache-read/cache-write
# tokens, c = weighted units.
function Fold([hashtable]$acc, [string]$fam, [double]$i, [double]$o, [double]$r, [double]$w, [double]$c) {
    $f = $acc[$fam]
    if (-not $f) { $f = @{ i = 0.0; o = 0.0; r = 0.0; w = 0.0; c = 0.0 } ; $acc[$fam] = $f }
    $f.i = [double]$f.i + $i ; $f.o = [double]$f.o + $o ; $f.r = [double]$f.r + $r
    $f.w = [double]$f.w + $w ; $f.c = [double]$f.c + $c
}

# Scan one transcript from $fromOffset to EOF, folding usage into $hrs keyed by LOCAL hour then family.
# Returns the offset of the last complete line so a half-written trailing line is re-read next
# time rather than parsed as truncated JSON.
function UsageScanFile([string]$path, [long]$fromOffset, [hashtable]$hrs) {
    $fs = $null
    $consumed = $fromOffset
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        if ($fromOffset -gt 0) { [void]$fs.Seek($fromOffset, 'Begin') }
        $sr = New-Object System.IO.StreamReader($fs, [System.Text.Encoding]::UTF8, $false)
        while ($null -ne ($line = $sr.ReadLine())) {
            # +1 for the newline. A trailing line with no newline is not counted as consumed.
            $lineBytes = [System.Text.Encoding]::UTF8.GetByteCount($line) + 1
            if ($fs.Position -ge $fs.Length -and -not $line.EndsWith('}')) { break }
            $consumed += $lineBytes

            $u = $line.IndexOf('"usage":{')
            if ($u -lt 0) { continue }
            if ($line -notmatch '"timestamp":"(\d{4}-\d{2}-\d{2}T[0-9:.]+Z)"') { continue }
            $ts = [DateTimeOffset]::Parse($Matches[1]).ToLocalTime()
            $model = if ($line -match '"model":"([^"]+)"') { $Matches[1] } else { $null }
            # The usage object is the FIRST "usage":{ on the line; its nested `iterations`
            # array repeats the same field names, so bound the window and take first matches.
            $seg   = $line.Substring($u, [Math]::Min(700, $line.Length - $u))
            $speed = if ($seg -match '"speed":"([a-z]+)"') { $Matches[1] } else { 'standard' }
            $in = if ($seg -match '"input_tokens":(\d+)')              { [double]$Matches[1] } else { 0 }
            $ou = if ($seg -match '"output_tokens":(\d+)')             { [double]$Matches[1] } else { 0 }
            $rd = if ($seg -match '"cache_read_input_tokens":(\d+)')   { [double]$Matches[1] } else { 0 }
            $c5 = if ($seg -match '"ephemeral_5m_input_tokens":(\d+)') { [double]$Matches[1] } else { 0 }
            $c1 = if ($seg -match '"ephemeral_1h_input_tokens":(\d+)') { [double]$Matches[1] } else { 0 }
            $wt = ModelWeights $model $speed
            $c  = if ($wt) { ($in * $wt.i + $ou * $wt.o + $rd * $wt.r + $c5 * $wt.w5 + $c1 * $wt.w1) / 1000000.0 } else { 0.0 }

            # Bucket by LOCAL hour ("yyyyMMddHH"): fixed-width keys keep the aged-out-hour sweep in
            # GetUsage a plain string comparison. Hour granularity is a holdover from the rate-limit
            # window folds this once fed; the session total it now feeds needs no bucketing at all.
            $k = $ts.ToString('yyyyMMddHH')
            $h = $hrs[$k]
            if (-not $h) { $h = @{} ; $hrs[$k] = $h }
            Fold $h (Family $model) $in $ou $rd ($c5 + $c1) $c
        }
        $sr.Dispose()
    } catch { }
    finally { if ($fs) { $fs.Dispose() } }
    return $consumed
}

# Returns @{ partial; session = <fam→acc> } or $null.
function GetUsage([string]$sessionId) {
    $cachePath = Join-Path $CfgDir 'statusline-usage.json'
    $now       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $cache     = $null
    if (Test-Path -LiteralPath $cachePath) {
        try { $cache = Get-Content -Raw -LiteralPath $cachePath | ConvertFrom-Json -AsHashtable } catch { }
    }
    if (-not ($cache -and $cache.v -eq 3 -and $cache.files)) { $cache = $null }

    $files   = if ($cache) { $cache.files } else { @{} }
    $partial = $false

    # Serve the cached file table without rescanning when it is fresh AND complete — a backfilling
    # cache keeps working every refresh instead of stalling a whole throttle window per 8 MB step.
    $rescan = -not ($cache -and -not $cache.partial -and ($now - [long]$cache.ts) -lt $UsageRefreshSec)
    if ($rescan) {
        $root = Join-Path $CfgDir 'projects'
        if (-not (Test-Path -LiteralPath $root)) { return $null }

        $today   = (Get-Date).Date
        $cutoff  = $today.AddDays(-8)
        $keepKey = [System.Collections.Generic.HashSet[string]]::new()
        $budget  = $UsageByteBudget

        foreach ($f in (Get-ChildItem -LiteralPath $root -Recurse -Filter *.jsonl -File -ErrorAction SilentlyContinue)) {
            if ($f.LastWriteTime -lt $cutoff) { continue }
            [void]$keepKey.Add($f.FullName)

            $entry = $files[$f.FullName]
            if (-not $entry) { $entry = @{ off = 0L; sid = (SessionOf $f); hrs = @{} } ; $files[$f.FullName] = $entry }
            if (-not $entry.hrs) { $entry.hrs = @{} }
            $off = [long]$entry.off
            # Shrunk on disk means the file was rotated or rewritten — its cached hours no longer
            # correspond to its contents, so drop them and rescan rather than double-count.
            # Persist off=0 on the entry too: if the byte budget runs out before this file is
            # rescanned, the cleared hours + stale offset would otherwise leave its usage missing
            # from totals until a later full pass.
            if ($f.Length -lt $off) { $off = 0L; $entry.off = 0L; $entry.hrs = @{} }
            if ($f.Length -le $off) { continue }

            if ($budget -le 0) { $partial = $true; continue }
            $newOff = UsageScanFile $f.FullName $off $entry.hrs
            $budget -= ($newOff - $off)
            $entry.off = $newOff
        }

        # Forget files that aged out of the window, and hour buckets that aged out of the report.
        foreach ($k in @($files.Keys)) { if (-not $keepKey.Contains($k)) { $files.Remove($k) } }
        $oldest = $today.AddDays(-9).ToString('yyyyMMdd') + '00'
        foreach ($k in @($files.Keys)) {
            $h = $files[$k].hrs
            if ($h) { foreach ($hk in @($h.Keys)) { if ($hk -lt $oldest) { $h.Remove($hk) } } }
        }

        # Atomic replace so a concurrent statusline never reads a half-written cache.
        try {
            $tmp = "$cachePath.tmp$PID"
            @{ v = 3; ts = $now; partial = $partial; files = $files } |
                ConvertTo-Json -Depth 8 -Compress | Set-Content -LiteralPath $tmp -NoNewline
            Move-Item -LiteralPath $tmp -Destination $cachePath -Force
        } catch { }
    } else {
        $partial = [bool]$cache.partial
    }

    # Fold this session's hours only — every other file in the cache belongs to another session.
    # No window folds: the 5h/7d numbers are stdin's and the server's, not ours to reconstruct.
    $sess = @{}
    foreach ($path in $files.Keys) {
        $entry = $files[$path]
        $h = $entry.hrs
        if (-not $h) { continue }
        if (-not ($sessionId -and ($entry.sid -eq $sessionId))) { continue }
        foreach ($hk in $h.Keys) {
            $fams = $h[$hk]
            foreach ($fam in $fams.Keys) {
                $a = $fams[$fam]
                Fold $sess $fam $a.i $a.o $a.r $a.w $a.c
            }
        }
    }
    @{ partial = $partial; session = $sess }
}

# ── per-model plan quota buckets ─────────────────────────────────────────────────
# stdin rate_limits carries only the unified five_hour / seven_day windows (verified against a live
# dump and the docs). The account-level view that /usage renders comes from
# GET https://api.anthropic.com/api/oauth/usage and ALSO carries model-scoped weekly buckets in its
# limits[] array (kind "weekly_scoped", scope.model.display_name e.g. "Fable"), plus legacy fixed
# keys seven_day_opus / seven_day_sonnet (null on accounts without those buckets). This fetcher:
#   * reuses the CLI's OAuth access token from ~/.claude/.credentials.json (the CLI refreshes it;
#     this script never does — on 401 the segment simply goes stale until the CLI rotates it),
#   * calls the endpoint at most every $QuotaRefreshSec, 3s timeout, result cached at
#     ~/.claude/statusline-quota.json (disposable),
#   * on any failure serves the last cached buckets marked stale ("~") and backs off a full
#     refresh window rather than retrying every repaint,
#   * emits every bucket the server publishes, labelled by the server's display name, so a new
#     bucket (e.g. Opus) appears without a script change. Buckets are measured server-side quota.
$QuotaRefreshSec = 60

function IsoToEpoch($s) {
    if (-not $s) { return 0 }
    try { [double]([DateTimeOffset]::Parse([string]$s).ToUnixTimeSeconds()) } catch { 0 }
}

# Returns @{ buckets = @(@{ label; used_percentage; resets_at }, ...); stale = <bool> } or $null.
function GetQuotaBuckets {
    $cachePath = Join-Path $CfgDir 'statusline-quota.json'
    $now       = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $cache     = $null
    if (Test-Path -LiteralPath $cachePath) {
        try { $cache = Get-Content -Raw -LiteralPath $cachePath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop } catch { }
    }
    if ($cache -and ($now - [long]$cache.ts) -lt $QuotaRefreshSec) {
        return @{ buckets = @($cache.buckets); stale = [bool]$cache.stale }
    }

    $buckets = [System.Collections.Generic.List[hashtable]]::new()
    $seen    = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $ok      = $false
    try {
        $credPath = Join-Path $CfgDir '.credentials.json'
        $tok = (Get-Content -Raw -LiteralPath $credPath -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop).claudeAiOauth.accessToken
        if ($tok) {
            $hdr = @{ Authorization = "Bearer $tok"; 'anthropic-beta' = 'oauth-2025-04-20' }
            $r = Invoke-RestMethod -Uri 'https://api.anthropic.com/api/oauth/usage' -Headers $hdr -Method Get `
                                   -TimeoutSec 3 -ErrorAction Stop
            foreach ($l in @($r.limits)) {
                if ($l.kind -ne 'weekly_scoped') { continue }
                $name = $l.scope.model.display_name
                if (-not $name -or $null -eq $l.percent) { continue }
                if ($seen.Add($name)) {
                    $buckets.Add(@{ label = "$name 7d"; used_percentage = [double]$l.percent; resets_at = (IsoToEpoch $l.resets_at) })
                }
            }
            # Legacy fixed keys — only when populated and not already covered by limits[].
            foreach ($pair in @(@('seven_day_opus', 'Opus'), @('seven_day_sonnet', 'Sonnet'))) {
                $w = $r.($pair[0])
                if ($w -and $null -ne $w.utilization -and $seen.Add($pair[1])) {
                    $buckets.Add(@{ label = "$($pair[1]) 7d"; used_percentage = [double]$w.utilization; resets_at = (IsoToEpoch $w.resets_at) })
                }
            }
            $ok = $true
        }
    } catch { }

    $stale = $false
    if (-not $ok) {
        if (-not $cache) { return $null }
        $buckets = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($b in @($cache.buckets)) { $buckets.Add(@{ label = $b.label; used_percentage = $b.used_percentage; resets_at = $b.resets_at }) }
        $stale = $true
    }

    # Atomic replace; a failed fetch is cached too (stale=true) so we back off for a full window.
    try {
        $tmp = "$cachePath.tmp$PID"
        @{ ts = $now; stale = $stale; buckets = @($buckets) } |
            ConvertTo-Json -Depth 4 -Compress | Set-Content -LiteralPath $tmp -NoNewline
        Move-Item -LiteralPath $tmp -Destination $cachePath -Force
    } catch { }

    @{ buckets = @($buckets); stale = $stale }
}

# ── line 1 ───────────────────────────────────────────────────────────────────────
$cwd    = $j.workspace.current_dir
$dir    = if ($cwd) { Split-Path -Leaf $cwd } else { '' }
$owner  = $j.workspace.repo.owner

# Single git call gives us BOTH branch and dirty-tracked-files state.
# `--porcelain=v1 -uno -b` → line 1 is "## <branch>..." (upstream info truncated by our regex);
# any additional lines mean tracked files are modified/staged.
$branch = $null
$dirty  = $false
if ($cwd) {
    $gitOut = @(& git -C $cwd status --porcelain=v1 -uno -b 2>$null)
    if ($gitOut.Count -gt 0) {
        if ($gitOut[0] -match '^##\s+([^\s\.]+)') { $branch = $Matches[1] }
        $dirty = $gitOut.Count -gt 1
    }
}

# Schema-fallback so Anthropic field renames don't silently zero out the dashboard.
$ctxPct = Coalesce $j.context_window.used_percentage `
                   $j.context_window.current_context_used_percentage `
                   $(if ($j.exceeds_200k_tokens) { 100 } else { 0 })
$ctxPct = [int][Math]::Floor([double]$ctxPct)
$inTok  = [long](Coalesce $j.context_window.total_input_tokens  0)
$outTok = [long](Coalesce $j.context_window.total_output_tokens 0)

# Full OAuth login email from ~/.claude.json → e.g. joe@profisee.com.
$account = $null
$acctPath = $AcctJson
if (Test-Path -LiteralPath $acctPath) {
    try {
        # -AsHashtable: ~\.claude.json holds project keys differing only in case (C:/ vs c:/), which
        # makes plain ConvertFrom-Json throw and silently drop the Acct: segment.
        $email = (Get-Content -Raw -LiteralPath $acctPath | ConvertFrom-Json -AsHashtable).oauthAccount.emailAddress
        if ($email) { $account = $email }
    } catch { }
}

$sid = if ($j.session_id -and $j.session_id.Length -ge 8) { $j.session_id.Substring(0, 8) } else { $j.session_id }
# Prefer the session name over the opaque short id — but only when it's short enough to be a
# deliberate label. Claude Code auto-names sessions with sentence-length topic summaries
# ("Check Claude monthly limit availability"), which read as status text, not identity.
if ($j.session_name -and $j.session_name.Length -le 16) { $sid = $j.session_name }

# Session elapsed from transcript file creation time (no extra process — file already touched below).
$elapsed = $null
if ($j.transcript_path -and (Test-Path -LiteralPath $j.transcript_path)) {
    try { $elapsed = ElapsedFmt ((Get-Date) - (Get-Item -LiteralPath $j.transcript_path).CreationTime) } catch { }
}

# Total context window for "tokens-left" hint. Try JSON fields first, then parse model display name
# (e.g. "Opus 5 (1M context)" → 1_000_000). Falls to 0 (badge suppressed) if neither works.
$ctxTotal = [long](Coalesce $j.context_window.total_tokens $j.context_window.max_tokens 0)
if ($ctxTotal -le 0 -and $j.model.display_name -match '\((\d+)\s*([MK])\s*context\)') {
    $ctxTotal = [long]$Matches[1] * $(if ($Matches[2] -eq 'M') { 1000000 } else { 1000 })
}

# Color escalation for context (auto-compaction risk).
# ctx value, conservative thresholds: green (<50, fine) → yellow (50-74, wrap up) → bold red (≥75, compact NOW).
$ctxColor = if ($ctxPct -ge 75) { '1;91' } elseif ($ctxPct -ge 50) { '93' } else { $ValC }

# Compose ctx value — append "(NNN left)" once ctx is meaningful and we know the total,
# and an explicit "compact!" prompt at ≥75% so the reset cue is text, not color alone.
$ctxVal = '{0}%' -f $ctxPct
if ($ctxPct -ge 50 -and $ctxTotal -gt 0) {
    $left = [long]($ctxTotal * (100 - $ctxPct) / 100)
    $ctxVal += ' ({0} left)' -f (TokFmt $left)
}
if ($ctxPct -ge 75) { $ctxVal += ' compact!' }

# Per-model SESSION tokens (transcript scan — stdin's totals omit subagents). A trailing "~" marks a
# cache still backfilling (first run after install, or after deleting the cache), so the totals read low.
$usage = GetUsage ([string]$j.session_id)
$usageMark = if ($usage -and $usage.partial) { (C $LblC '~') } else { '' }

$seg = [System.Collections.Generic.List[string]]::new()
$seg.Add((C '1;95' $j.model.display_name))
$seg.Add((C $LblC 'ctx:') + (C $ctxColor $ctxVal))

# Session tokens per model family: ↓ = everything fed in (input + cache read + cache write), ↑ = output.
# Includes subagent transcripts, which stdin's totals omit. Falls back to stdin's main-agent ↓/↑
# until the scan has data for this session.
$sessParts = [System.Collections.Generic.List[string]]::new()
if ($usage -and $usage.session.Count -gt 0) {
    foreach ($fam in $FamilyOrder) {
        if (-not $usage.session.ContainsKey($fam)) { continue }
        $a  = $usage.session[$fam]
        $dn = [long]([double]$a.i + [double]$a.r + [double]$a.w)
        $up = [long]$a.o
        if ($dn -le 0 -and $up -le 0) { continue }
        $sessParts.Add((C $LblC $fam) + ' ' + (C $LblC ([char]0x2193)) + (C $ValC (TokFmt $dn)) + ' ' + (C $LblC ([char]0x2191)) + (C $ValC (TokFmt $up)))
    }
}
if ($sessParts.Count -gt 0) { $seg.Add(($sessParts -join '  ') + $usageMark) }
else { $seg.Add((C $LblC ([char]0x2193)) + (C $ValC (TokFmt $inTok)) + ' ' + (C $LblC ([char]0x2191)) + (C $ValC (TokFmt $outTok))) }

# Shared rate-limit windows, labelled the way /usage labels them: five_hour is its "Current session",
# seven_day its "Current week (all models)". "All Models 7d" therefore pairs with the "<Model> 7d"
# buckets appended just below, and the two weekly numbers read as the matched pair they are.
$s = RateSeg '5 Hour' $j.rate_limits.five_hour
if ($s) { $seg.Add($s) }
$s = RateSeg 'All Models 7d' $j.rate_limits.seven_day
if ($s) { $seg.Add($s) }

# Per-model weekly quota buckets (server-side, not on stdin). Only rendered when the plan has any;
# a trailing "~" on the value means the last fetch failed and this is the cached reading.
$quota = GetQuotaBuckets
if ($quota) {
    foreach ($b in @($quota.buckets)) {
        $s = RateSeg $b.label $b
        if ($s) { if ($quota.stale) { $s += (C $LblC '~') } ; $seg.Add($s) }
    }
}

$line1a = $seg -join '  '

# Where-am-I segments go on a row of their own: on one row with the meters, the right quarter of the
# footer was cut off at normal terminal widths.
$seg = [System.Collections.Generic.List[string]]::new()
if ($branch)  { $seg.Add((C '94' ($branch + $(if ($dirty) { '*' } else { '' })))) }
if ($dir)     { $seg.Add((C $ValC $dir)) }
if ($owner)   { $seg.Add((C $LblC '@') + (C $ValC $owner)) }
# Acct: = which Claude login this session bills to (full OAuth email from ~/.claude.json).
if ($account) { $seg.Add((C $LblC 'Acct:') + (C $ValC $account)) }
if ($sid)     { $seg.Add((C $ValC $sid)) }
if ($elapsed) { $seg.Add((C $LblC ([char]0x29D7)) + (C $ValC $elapsed)) }
$seg.Add((C '92' ("+{0}" -f [int]$j.cost.total_lines_added)) + ' ' + (C '91' ("-{0}" -f [int]$j.cost.total_lines_removed)))
$line1 = $line1a + "`n" + ($seg -join '  ')

# ── line 2 ───────────────────────────────────────────────────────────────────────
# Only the permission MODE is taken from the transcript — it's the one line-2 element that's both absent
# from stdin AND reliably recoverable (the last permission-mode event IS the current mode). Read only the
# last ~1 MB via a FileStream seek (O(tail-size); never scans the whole file, so it cannot hang the footer
# the way Get-Content -Tail did). Try/finally guarantees the handle is released even if Read/Seek throws.
# NOTE: if a future Claude Code release exposes permission_mode on stdin, delete this whole block —
# use the debug dump to inspect the JSON for a top-level permission_mode field.
#
# The screenshot's "N shell / N agent" counters are deliberately NOT here: reconstructing live background
# counts from an append-only transcript is unstable — the count swings with the read-window size (0 vs 1 vs
# 18 for the same true state of zero) because completions arrive as async notifications that may fall
# outside any bounded window. A confidently-wrong count is worse than none. See the writeup.
$mode = $null
$tp = $j.transcript_path
if ($tp -and (Test-Path -LiteralPath $tp)) {
    $fs = $null
    try {
        $fs = [System.IO.File]::Open($tp, 'Open', 'Read', 'ReadWrite')
        $take = [Math]::Min(1MB, $fs.Length)
        [void]$fs.Seek(-$take, 'End')
        $buf = New-Object byte[] $take
        [void]$fs.Read($buf, 0, $take)
        $lines = [System.Text.Encoding]::UTF8.GetString($buf) -split "`n"
        for ($i = $lines.Count - 1; $i -ge 0; $i--) {
            if ($lines[$i] -match '"permissionMode":"([^"]+)"') { $mode = $Matches[1]; break }
        }
    } catch { }
    finally { if ($fs) { $fs.Dispose() } }
}

$seg2 = [System.Collections.Generic.List[string]]::new()
if ($mode)        { $seg2.Add((C '1;92' "++ $mode mode")) }
if ($j.fast_mode) { $seg2.Add((C '93' 'fast')) }
if ($j.effort.level) { $seg2.Add((C $LblC 'effort:') + (C $ValC $j.effort.level)) }
if ($j.thinking.enabled) { $seg2.Add((C $ValC 'thinking')) }
if ($j.output_style.name -and $j.output_style.name -ne 'default') { $seg2.Add((C $ValC $j.output_style.name)) }

# ── memory ───────────────────────────────────────────────────────────────────────
# "Claude" = working set of THIS session's claude.exe; "All Claude" = working sets of every claude.exe
# in this Windows logon session; "RAM" = system physical memory load. claude.exe is a single native
# binary (no separate bun/node child), so matching on its install path excludes MCP-server node.exe,
# VS Code and pwsh. This script is a descendant of its session's claude.exe (claude → [shell] → pwsh),
# so the nearest claude.exe ancestor IS the current session; Process.Parent is a native
# NtQueryInformationProcess call, not WMI. "All Claude" also counts the background-session daemon and
# pty host (claude.exe daemon run / --bg-pty-host). Working set = physical RAM in use now, the same
# basis as the RAM %; it counts claude.exe's shared image pages once per process, so the sum reads
# slightly high. Each metric fails independently to "?" — memory never breaks the footer.
function MemFmt([double]$bytes) {
    $mb = $bytes / 1MB
    if ($mb -ge 1024) { '{0:N1} GB' -f ($mb / 1024) } else { '{0:N0} MB' -f $mb }
}
$claudeExe = Join-Path $HOME '.local\bin\claude.exe'
function IsClaudeExe($p) { try { $p.ProcessName -eq 'claude' -and $p.Path -eq $claudeExe } catch { $false } }

$memCur = $null
try {
    $p = [System.Diagnostics.Process]::GetCurrentProcess().Parent
    for ($hop = 0; $p -and $hop -lt 8; $hop++) {
        if (IsClaudeExe $p) { $memCur = MemFmt $p.WorkingSet64; break }
        $p = $p.Parent
    }
} catch { }
$seg2.Add((C $LblC 'Claude ') + (C $ValC $(if ($memCur) { $memCur } else { '?' })))

$memAll = $null
try {
    $logon = [System.Diagnostics.Process]::GetCurrentProcess().SessionId
    $sum = 0L
    foreach ($p in [System.Diagnostics.Process]::GetProcessesByName('claude')) {
        if ($p.SessionId -eq $logon -and (IsClaudeExe $p)) { $sum += $p.WorkingSet64 }
    }
    if ($sum -gt 0) { $memAll = MemFmt $sum }
} catch { }
$seg2.Add((C $LblC 'All Claude ') + (C $ValC $(if ($memAll) { $memAll } else { '?' })))

# GCMemoryInfo.MemoryLoadBytes is the OS memory load (GlobalMemoryStatusEx) sampled at the last GC;
# a gen-0 collect in this tiny process refreshes it in ~10 ms, vs ~200-600 ms to Add-Type a P/Invoke.
try {
    [GC]::Collect(0)
    $gi = [GC]::GetGCMemoryInfo()
    if ($gi.TotalAvailableMemoryBytes -gt 0) {
        $ramPct = [int][Math]::Round(100.0 * $gi.MemoryLoadBytes / $gi.TotalAvailableMemoryBytes)
        $ramC   = if ($ramPct -ge 85) { '91' } elseif ($ramPct -ge 70) { '93' } else { $ValC }
        $seg2.Add((C $LblC 'RAM ') + (C $ramC "$ramPct%"))
    }
} catch { }

$line2 = $seg2 -join '  '

if ($line2) { "$line1`n$line2" } else { $line1 }
