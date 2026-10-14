#requires -Version 7
<#
.SYNOPSIS
    MCP servers and Claude's secrets for this machine (spec R15, R16). Called by Install-AIMachine.ps1.

    For each '## MCP servers' row with Install = yes:
      - present in ~\.claude.json  -> left as it is (reported);
      - missing                     -> rendered from claude\mcp-servers.json ({Key}, %VAR%, {secret:id} from -SecretsFile).
        A server whose secrets are not all available is NOT written; its missing secret names are listed.
    With -SecretsFile, the secret user env vars in it are set (only when absent or different).
    Rows with Install = no are reported if present; nothing is removed.
#>
param(
    [Parameter(Mandatory)][string]$TemplatePath,
    [string]$ConfigPath,
    [string]$SecretsFile,
    [string[]]$SecretEnv = @(),
    [string]$ClaudeJson = (Join-Path $HOME '.claude.json'),
    [securestring]$Passphrase,   # tests only; normally typed
    [switch]$RemoveSecretsFile
)
$ErrorActionPreference = 'Stop'
$lib = @((Join-Path $PSScriptRoot '..\lib'), (Join-Path $PSScriptRoot 'lib')) | Where-Object { Test-Path (Join-Path $_ 'MachineConfig.psm1') } | Select-Object -First 1
Import-Module (Join-Path $lib 'MachineConfig.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $lib 'AISecrets.psm1') -Force -DisableNameChecking
$pa = @{}; if ($ConfigPath) { $pa.Path = $ConfigPath }
$prof = Get-AIMachineProfile @pa
if (-not (Test-Path -LiteralPath $TemplatePath)) { Write-Host "MCP: no template at $TemplatePath; skipped."; return }
$tpl = Get-Content -LiteralPath $TemplatePath -Raw | ConvertFrom-Json -AsHashtable -Depth 20

$secrets = $null
if ($SecretsFile) {
    if (-not $Passphrase) { $Passphrase = Read-Host "Passphrase for $SecretsFile" -AsSecureString }
    $secrets = Unprotect-AISecrets -Path $SecretsFile -Passphrase $Passphrase
}

$cj = if (Test-Path -LiteralPath $ClaudeJson) { Get-Content -LiteralPath $ClaudeJson -Raw | ConvertFrom-Json -AsHashtable -Depth 50 } else { [ordered]@{} }
if (-not $cj.Contains('mcpServers')) { $cj['mcpServers'] = [ordered]@{} }
$changed = $false

function Expand-McpValue($v, [ref]$missing) {
    if ($v -is [string]) {
        $s = [Environment]::ExpandEnvironmentVariables($v)
        foreach ($m in [regex]::Matches($s, '\{secret:([^}]+)\}')) {
            $id = $m.Groups[1].Value
            $val = if ($secrets -and $secrets.mcp -and $secrets.mcp.Contains($id)) { [string]$secrets.mcp[$id] } else { $null }
            if ($null -eq $val) { $missing.Value += $id; continue }
            $s = $s.Replace($m.Value, $val)
        }
        foreach ($m in [regex]::Matches($s, '\{([A-Za-z][A-Za-z0-9]*)\}')) {
            $k = $m.Groups[1].Value
            if ($prof.Keys.Contains($k) -and $prof.Keys[$k]) { $s = $s.Replace($m.Value, [string]$prof.Keys[$k]) } else { $missing.Value += "key $k" }
        }
        return $s
    }
    if ($v -is [System.Collections.IDictionary]) { $o = [ordered]@{}; foreach ($k in $v.Keys) { $o[$k] = Expand-McpValue $v[$k] $missing }; return $o }
    if ($v -is [System.Collections.IList]) { return , @(foreach ($x in $v) { Expand-McpValue $x $missing }) }
    return $v
}

foreach ($row in $prof.Mcp) {
    $name = $row.Server
    $present = $cj.mcpServers.Contains($name)
    if ($row.Install -ne 'yes') { if ($present) { Write-Host "MCP: $name is installed but the profile says Install = no (left in place; remove it yourself if wanted)." }; continue }
    if ($present -and -not $SecretsFile) { Write-Host "MCP: $name present."; continue }
    if (-not $tpl.servers.Contains($name)) { Write-Host "MCP: $name has no template in $TemplatePath; skipped." -ForegroundColor Yellow; continue }
    $missing = @()
    $def = Expand-McpValue $tpl.servers[$name] ([ref]$missing)
    if ($missing) { Write-Host "MCP: $name NOT written; missing: $($missing -join ', ')." -ForegroundColor Yellow; continue }
    if ($present -and (($cj.mcpServers[$name] | ConvertTo-Json -Depth 20 -Compress) -eq ($def | ConvertTo-Json -Depth 20 -Compress))) { Write-Host "MCP: $name present and current."; continue }
    $cj.mcpServers[$name] = $def; $changed = $true
    Write-Host "MCP: $name $(if ($present) { 'updated' } else { 'installed' })."
}
if ($changed) {
    if (Test-Path -LiteralPath $ClaudeJson) { Copy-Item -LiteralPath $ClaudeJson "$ClaudeJson.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')" }
    $tmp = "$ClaudeJson.tmp"
    [IO.File]::WriteAllText($tmp, ($cj | ConvertTo-Json -Depth 50))
    Move-Item -LiteralPath $tmp $ClaudeJson -Force
}

if ($secrets -and $secrets.env) {
    foreach ($n in $secrets.env.Keys) {
        if ($SecretEnv.Count -and $n -notin $SecretEnv) { Write-Host "Secret env $n is not in the manifest's secretEnv list; skipped."; continue }
        $cur = [Environment]::GetEnvironmentVariable($n, 'User')
        if ($cur -ceq [string]$secrets.env[$n]) { Write-Host "Secret env $n already set."; continue }
        [Environment]::SetEnvironmentVariable($n, [string]$secrets.env[$n], 'User')
        Write-Host "Secret env $n set (User)."
    }
    foreach ($n in $SecretEnv) { if (-not $secrets.env.Contains($n)) { Write-Host "Secret env $n is not in the secrets file (missing, not guessed)." -ForegroundColor Yellow } }
}
if ($SecretsFile) {
    if ($RemoveSecretsFile) { Remove-Item -LiteralPath $SecretsFile -Force; Write-Host "Deleted $SecretsFile." }
    else { Write-Host "The secrets file $SecretsFile was kept. Delete it when you are done (or rerun with -RemoveSecretsFile)." -ForegroundColor Yellow }
}

# App secret exports (R24): remind, never automate the apps' own imports.
$sd = $prof.Keys['SecretsDir']
if ($sd -and (Test-Path -LiteralPath $sd)) {
    $apps = @(Get-ChildItem -LiteralPath $sd -Filter '*.json' -File -ErrorAction SilentlyContinue)
    if ($apps.Count -and $SecretsFile) { Write-Host "App secret exports in ${sd}: $($apps.Name -join ', '). Import each in its app (TestAuto /secrets, CrewChief) with the master password from 1Password." }
}
