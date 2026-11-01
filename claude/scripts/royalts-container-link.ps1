#requires -Version 7
<#
PostToolUse hook (via hook-dispatch.ps1 -Id royalts-container-link).

After mcp__proxmox__create_container succeeds, add a matching SSH connection to
the Royal TS document named by the profile key RoyalTsHomeAILinux (exported as
$env:AI_ROYALTSHOMEAILINUX). The connection uses the static IP when the tool
call gave one, otherwise the container hostname. It reuses the document's
"HomeAI guest key (root)" credential when present (the key every guest gets
in root's authorized_keys at creation; see Add-RoyalTsSshLink.ps1).

Never blocks the tool call: every failure path exits 0 and writes to stderr.
Manual equivalent: Add-RoyalTsSshLink.ps1.
#>
if (-not $HookJson) { $HookJson = [System.Console]::In.ReadToEnd() }

try {
    $payload = $HookJson | ConvertFrom-Json -ErrorAction Stop
    if ($payload.tool_name -ne 'mcp__proxmox__create_container') { exit 0 }

    $resp = $payload.tool_response
    $isError = ($resp.isError -eq $true)
    $text = (@($resp.content) | Where-Object { $_.type -eq 'text' } | ForEach-Object { $_.text }) -join "`n"
    if (-not $text -and $resp -is [string]) { $text = $resp }
    if ($isError -or $text -match '"success"\s*:\s*false' -or $text -match '(?i)^\s*(error|failed|permission denied)') {
        [System.Console]::Error.WriteLine('[royalts-container-link] create_container did not report success; no link added')
        exit 0
    }

    $docPath = $env:AI_ROYALTSHOMEAILINUX
    if (-not $docPath) {
        [System.Console]::Error.WriteLine('[royalts-container-link] profile key RoyalTsHomeAILinux not set; no link added')
        exit 0
    }

    $in = $payload.tool_input
    $vmid = [string]$in.vmid
    $hostname = if ($in.hostname) { [string]$in.hostname } else { "ct-$vmid" }
    $ip = $null
    if ($in.ip -and $in.ip -notin @('dhcp', 'manual', 'auto')) { $ip = ([string]$in.ip -split '/')[0] }
    $uri = if ($ip) { $ip } else { $hostname }
    $node = if ($in.node) { [string]$in.node } else { 'homeai' }

    . (Join-Path $PSScriptRoot 'lib\RoyalTs.ps1')
    $desc = "Proxmox LXC $vmid on $node. Created by Claude Code $(Get-Date -Format 'yyyy-MM-dd HH:mm')." + ($(if (-not $ip) { ' DHCP: URI is the hostname; replace with the IP once known.' } else { '' }))
    $id = Add-RoyalTsSshConnection -DocumentPath $docPath -Name $hostname -Uri $uri -Port 22 -Description $desc -CredentialName 'HomeAI guest key (root)'

    $msg = if ($id) { "Royal TS: added SSH connection '$hostname' -> $uri in $docPath" } else { "Royal TS: connection '$hostname' or URI $uri already exists in $docPath; nothing added" }
    if (Get-Process -Name RoyalTS -ErrorAction SilentlyContinue) { $msg += '. Royal TS is running with this document possibly open; its next save will overwrite the file. Tell the user to reload the document.' }

    @{ hookSpecificOutput = @{ hookEventName = 'PostToolUse'; additionalContext = $msg } } | ConvertTo-Json -Compress
}
catch {
    [System.Console]::Error.WriteLine("[royalts-container-link] $_")
}
exit 0
