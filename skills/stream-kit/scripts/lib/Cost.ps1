# Transcript cost parsing (2026-10-05 priority-focus-design 3.5). Source: the Claude transcripts of the stream account,
# <projects>\<project>\*.jsonl and <projects>\<project>\<sessionId>\subagents\agent-*.jsonl. Verified 2026-10-05 on
# SMVMTR1: every line carries sessionId and timestamp; assistant lines carry message.id, message.model and
# message.usage; a message's usage line REPEATS (10 lines, 6 ids in one sample; 194 lines, 130 ids in the integrator's),
# so summing lines overstates spend 1.5-1.9x. One (file, message.id) counts once, the LAST occurrence wins: the usage of
# a repeat can grow (measured 2026-10-05: output 16, then 190, for one id). So the newest message of a file is held back
# (the cursor stays on its first line) until a later message starts or the caller flushes a quiet file.
# Lines parse with -DateKind String: the default turns the ISO timestamp into a local DateTime, and [string] of that
# loses the zone and the ISO form the ledger sorts and buckets on.
$script:TokenClasses = @('in', 'out', 'cacheRead', 'cacheWrite5m', 'cacheWrite1h')
function Read-Prices([string] $Path) { Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json -AsHashtable }
# A model id with a date suffix (claude-haiku-4-5-20251001) prices by the longest key it starts with.
function Resolve-PriceModel($Prices, [string] $Model) {
    if (-not $Model) { return $null }
    if ($Prices['models'].ContainsKey($Model)) { return $Model }
    $best = $null
    foreach ($k in $Prices.models.Keys) { if ($Model.StartsWith($k) -and (-not $best -or $k.Length -gt $best.Length)) { $best = $k } }
    $best
}
function ConvertTo-Usd($Prices, [string] $Model, $Usage) {
    $m = Resolve-PriceModel $Prices $Model
    if (-not $m) { return $null }
    $p = $Prices.models[$m]; $usd = 0.0
    foreach ($c in $script:TokenClasses) { $usd += [double]$Usage[$c] * [double]$p[$c] }
    [math]::Round($usd / 1e6, 6)
}

# Reads the complete lines of one transcript from byte offset $From, at most $MaxBytes (64 MB) per call. Returns
# @{ offset = <first byte not consumed>; lastMessageId = <last id emitted>; rows }. A line without a trailing newline (a
# session still writing) is left for the next read. The newest message is HELD (not emitted; offset = its first line)
# unless -Flush: its usage may still grow. A chunk that holds nothing but one huge message flushes it, so a read always
# makes progress.
function Read-TranscriptUsage([string] $Path, [long] $From = 0, [string] $SkipMessageId = '', [switch] $Flush, [long] $MaxBytes = 64MB) {
    $rows = [Collections.Generic.List[object]]::new()
    $nothing = @{ offset = $From; lastMessageId = $SkipMessageId; rows = @() }
    $fs = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::ReadWrite)
    try {
        $len = $fs.Length
        if ($From -ge $len) { return $nothing }
        $want = [Math]::Min($len - $From, $MaxBytes)
        $fs.Position = $From
        $buf = [byte[]]::new($want); $n = 0
        while ($n -lt $buf.Length) { $k = $fs.Read($buf, $n, $buf.Length - $n); if ($k -le 0) { break }; $n += $k }
    } finally { $fs.Dispose() }
    if ($n -le 0) { return $nothing }
    $truncated = ($From + $n) -lt $len
    $end = [Array]::LastIndexOf($buf, [byte]10, $n - 1)
    if ($end -lt 0) { return $nothing }
    $last = $SkipMessageId; $pending = $null; $pendingStart = -1L
    $seen = [Collections.Generic.HashSet[string]]::new(); if ($SkipMessageId) { [void]$seen.Add($SkipMessageId) }
    $start = 0
    while ($start -le $end) {
        $nl = [Array]::IndexOf($buf, [byte]10, $start, $end - $start + 1)
        $lineStart = $start; $start = $nl + 1
        # Cheap filter on the bytes before decoding: only assistant lines with usage are parsed.
        $line = [Text.Encoding]::UTF8.GetString($buf, $lineStart, $nl - $lineStart)
        if (-not $line.Contains('"usage"')) { continue }
        try { $o = $line | ConvertFrom-Json -AsHashtable -Depth 30 -DateKind String } catch { continue }
        # Indexers, not dot access: a key a line lacks (agentId outside subagents, cache_creation on older lines) throws
        # under Set-StrictMode, and the indexer reads it as $null.
        if ($o['type'] -ne 'assistant' -or $o['message'] -isnot [hashtable] -or $o['message']['usage'] -isnot [hashtable]) { continue }
        $m = $o['message']; $id = [string]$m['id']
        # A repeat of an id already counted (in this read, or the cursor's id from the previous one) is skipped, except
        # the pending one, whose later line replaces it below (last wins).
        if ($seen.Contains($id) -and -not ($pending -and $pending.messageId -eq $id)) { continue }
        $u = $m['usage']; $cc = $u['cache_creation']
        $row = @{ at = [string]$o['timestamp']; sessionId = [string]$o['sessionId']; agentId = [string]$o['agentId']; messageId = $id; model = [string]$m['model']
            in = [long]$u['input_tokens']; out = [long]$u['output_tokens']; cacheRead = [long]$u['cache_read_input_tokens']
            cacheWrite5m = [long]$(if ($cc -is [hashtable]) { $cc['ephemeral_5m_input_tokens'] } else { 0 })
            cacheWrite1h = [long]$(if ($cc -is [hashtable]) { $cc['ephemeral_1h_input_tokens'] } else { $u['cache_creation_input_tokens'] }) }
        if ($pending -and $pending.messageId -eq $id) { $pending = $row; continue }   # same message again: last wins
        if ($pending) { $rows.Add($pending); $last = $pending.messageId }
        $pending = $row; $pendingStart = $From + $lineStart; [void]$seen.Add($id)
    }
    $offset = $From + $end + 1
    if ($pending) {
        if ($Flush -or ($pendingStart -eq $From -and $truncated)) { $rows.Add($pending); $last = $pending.messageId }
        else { $offset = $pendingStart }
    }
    @{ offset = $offset; lastMessageId = $last; rows = $rows }
}

# Finds the stream session of a long /loop session from its own transcript, for sessions that predate
# .streams\sessions (on SMVMTR1, 2026-10-06, they held 82.2% of the ledger). Such a session opens with
# '/loop [interval] /stream-<role>' (or '/stream-<role>' itself) and passes '-Session <id>' to every kit script it runs
# (one long author session: 1279 times, one id). The id is the most frequent '-Session' value that looks like an id: a
# role-prefixed one (author-202610011145-1c5f) or a bare hex one (the integrator ran as '4599ecab' on 2026-10-01). Words
# that follow '-Session' in prose ('-Session messages') never count. The role is the id's prefix when it names one, else
# the opening command's. With a role but no id the stream session is '<role>-<first 8 of the Claude session id>', so the
# spend is still charged to its role (no task). Returns $null when the transcript names no role. Reads the whole file
# once; Get-StreamCost.ps1 keeps the answer in .streams\sessions so it is never read again for this.
function Find-TranscriptSession([string] $Path, [string] $SessionId) {
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $cmdRx = [regex]::new('(?:<command-name>|<command-args>[^<]*?)/stream-(author|build|integrate|plan|status|kit|coordinator)\b')
    $sesRx = [regex]::new('-Session\s+(?:\\?["''])?([A-Za-z]+-[A-Za-z0-9._-]*[0-9][A-Za-z0-9._-]*|[A-Za-z]+-[A-Za-z]+-[A-Za-z0-9._-]+|[0-9a-f]{6,})(?![A-Za-z0-9._-])')
    $cmdRole = ''
    $count = @{}
    foreach ($l in [IO.File]::ReadLines($Path)) {
        if (-not $cmdRole -and $l.Contains('/stream-')) { $m = $cmdRx.Match($l); if ($m.Success) { $cmdRole = $m.Groups[1].Value } }
        if ($l.IndexOf('-Session', [StringComparison]::Ordinal) -lt 0) { continue }
        foreach ($m in $sesRx.Matches($l)) { $v = $m.Groups[1].Value; $count[$v] = 1 + [int]$count[$v] }
    }
    $best = ''; $bestN = 0
    foreach ($k in $count.Keys) {
        $pre = ($k -split '-')[0].ToLowerInvariant()
        if ($script:SessionRoleAlias.ContainsKey($pre)) { $pre = $script:SessionRoleAlias[$pre] }
        $known = $pre -in @('author', 'build', 'integrate', 'plan', 'status', 'kit', 'coordinator')
        # A role-prefixed id must name a known role; a bare hex id counts only when the command named the role.
        if (-not $known -and -not ($k -match '^[0-9a-f]{6,}$' -and $cmdRole)) { continue }
        if ($count[$k] -gt $bestN -or ($count[$k] -eq $bestN -and $k -lt $best)) { $best = $k; $bestN = $count[$k] }
    }
    if ($best) {
        $pre = ($best -split '-')[0].ToLowerInvariant()
        if ($script:SessionRoleAlias.ContainsKey($pre)) { $pre = $script:SessionRoleAlias[$pre] }
        $role = if ($pre -in @('author', 'build', 'integrate', 'plan', 'status', 'kit', 'coordinator')) { $pre } else { $cmdRole }
        return @{ streamSession = $best; role = $role }
    }
    if ($cmdRole) { return @{ streamSession = "$cmdRole-$($SessionId.Substring(0, [Math]::Min(8, $SessionId.Length)))"; role = $cmdRole } }
    $null
}