#requires -Version 7
<#
Write-AIFile: the one write helper for machine resources (spec R5, R6, D18).

    Write-AIFile -Path <absolute destination> -Source <local file>
    Write-AIFile -Path <absolute destination> -Text '...'

The route comes from the profile's '## Resources' table: 'obsidian' writes through that vault's Local REST API
(a running Obsidian holds vault files open over SMB and only indexes its own writes); 'direct' writes the file.
A path inside an obsidian vault inherits 'obsidian'; a path under no resource is 'direct'.
If the API is unreachable the write STOPS. There is never a fallback to a direct write.
Every write is verified by re-reading the destination and comparing SHA-256.
#>
Set-StrictMode -Version Latest

function Get-AIWriteRoute {
    <# Returns { Route; Key; Root; Endpoint } for a destination path. #>
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][object]$Profile)
    $full = [IO.Path]::GetFullPath($Path)
    $best = $null
    foreach ($r in $Profile.Resources) {
        $root = $Profile.Keys[$r.Key]
        if (-not $root) { continue }
        $rf = [IO.Path]::GetFullPath($root).TrimEnd('\')
        if ($full.StartsWith($rf + '\', [StringComparison]::OrdinalIgnoreCase)) {
            # Obsidian vaults win over anything nested inside them (a path inside a vault inherits obsidian).
            $rank = if ($r.Route -eq 'obsidian') { 100000 + $rf.Length } else { $rf.Length }
            if (-not $best -or $rank -gt $best.Rank) { $best = [pscustomobject]@{ Rank = $rank; Route = $r.Route; Key = $r.Key; Root = $rf; Endpoint = $r.Endpoint } }
        }
    }
    if (-not $best) { return [pscustomobject]@{ Route = 'direct'; Key = $null; Root = $null; Endpoint = $null } }
    return $best
}

function Get-AIObsidianAuth {
    <# The bearer value from the ~\.claude.json MCP entry whose URL matches the endpoint (else 'obsidian'). Never printed. #>
    param([string]$Endpoint, [string]$ClaudeJson = (Join-Path $HOME '.claude.json'))
    $j = Get-Content -LiteralPath $ClaudeJson -Raw | ConvertFrom-Json -AsHashtable
    $authority = ([uri]$Endpoint).GetLeftPart([UriPartial]::Authority)
    $cands = @($j.mcpServers.Keys | Where-Object { $s = $j.mcpServers[$_]; $s.Contains('url') -and ([uri]$s.url).GetLeftPart([UriPartial]::Authority) -eq $authority })
    $name = if ($cands) { $cands[0] } elseif ($j.mcpServers.Contains('obsidian')) { 'obsidian' } else { $null }
    if (-not $name) { throw "No Obsidian MCP entry in $ClaudeJson for $Endpoint." }
    $h = $j.mcpServers[$name]['headers']
    if (-not $h -or -not $h['Authorization']) { throw "The MCP entry '$name' has no Authorization header." }
    return [string]$h['Authorization']
}

function Get-AIContentType([string]$rel) {
    if ($rel -match '\.(html?)$') { return 'text/html; charset=utf-8' }
    if ($rel -match '\.(json|js|mjs|cjs|css|ps1|psm1|psd1|py|txt|yaml|yml|csv|cmd|sh)$') { return 'text/plain; charset=utf-8' }
    if ($rel -match '\.png$') { return 'image/png' }
    if ($rel -match '\.jpe?g$') { return 'image/jpeg' }
    if ($rel -match '\.md$') { return 'text/markdown; charset=utf-8' }
    return 'application/octet-stream'   # binaries must not go as text/*: the API would re-encode them
}

function Write-AIFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Path,
        [string]$Source,
        [string]$Text,
        [object]$Profile,
        [int]$TimeoutSec = 60,
        [string]$ClaudeJson = (Join-Path $HOME '.claude.json')   # where the vault's MCP bearer lives (a test passes its own)
    )
    if (-not $Profile) { $Profile = Get-AIMachineProfile }
    # [byte[]]: an if-expression enumerates a byte array into object[], and Invoke-RestMethod would then send the numbers as text.
    [byte[]]$bytes = if ($Source) { [IO.File]::ReadAllBytes($Source) } elseif ($PSBoundParameters.ContainsKey('Text')) { [Text.UTF8Encoding]::new($false).GetBytes($Text) } else { throw 'Pass -Source or -Text.' }
    $want = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes))
    $full = [IO.Path]::GetFullPath($Path)
    $route = Get-AIWriteRoute -Path $full -Profile $Profile

    if ($route.Route -eq 'obsidian') {
        if (-not $route.Endpoint) { throw "Resource '$($route.Key)' is obsidian but has no endpoint in the profile." }
        $rel = $full.Substring($route.Root.Length + 1)
        $url = $route.Endpoint.TrimEnd('/') + '/vault/' + (($rel -split '\\' | ForEach-Object { [uri]::EscapeDataString($_) }) -join '/')
        $auth = Get-AIObsidianAuth -Endpoint $route.Endpoint -ClaudeJson $ClaudeJson
        $putErr = $null
        try { Invoke-RestMethod -Method Put -Uri $url -Headers @{ Authorization = $auth } -ContentType (Get-AIContentType $rel) -Body $bytes -SkipCertificateCheck -TimeoutSec $TimeoutSec | Out-Null }
        catch { $putErr = $_ }
        # A large PUT can time out after the write landed: the hash decides, not the HTTP outcome.
        $got = $null
        for ($i = 0; $i -lt 10; $i++) {
            if (Test-Path -LiteralPath $full) { try { $got = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash } catch { $got = $null } }
            if ($got -eq $want) { break }
            if ($putErr -and -not ($putErr.Exception -is [System.Threading.Tasks.TaskCanceledException] -or "$putErr" -match '(?i)timeout|timed out')) { break }
            Start-Sleep -Milliseconds 500
        }
        if ($got -ne $want) {
            $resp = if ($putErr) { $putErr.Exception.PSObject.Properties['Response'] } else { $null }   # StrictMode: not every exception has Response
            $why = if ($putErr) { if ($resp -and $resp.Value) { "HTTP $([int]$resp.Value.StatusCode)" } else { "$($putErr.Exception.GetType().Name): $($putErr.Exception.Message)" } } else { 'content mismatch after the write' }
            throw "Obsidian write of $rel failed ($why); no direct-write fallback (R5)."
        }
        return [pscustomobject]@{ Path = $full; Route = 'obsidian'; Hash = $got }
    }

    $dir = Split-Path $full
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $tmp = Join-Path $dir ('.' + (Split-Path $full -Leaf) + '.tmp-' + [guid]::NewGuid().ToString('N').Substring(0, 6))
    [IO.File]::WriteAllBytes($tmp, $bytes)
    Move-Item -LiteralPath $tmp $full -Force
    $got = (Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash
    if ($got -ne $want) { throw "Direct write of $full did not verify." }
    return [pscustomobject]@{ Path = $full; Route = 'direct'; Hash = $got }
}

Export-ModuleMember -Function Write-AIFile, Get-AIWriteRoute
