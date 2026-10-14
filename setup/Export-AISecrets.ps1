#requires -Version 7
<#
.SYNOPSIS
    Writes Claude's own secrets (MCP secret fields + the secret user env vars the manifest names) into ONE
    passphrase-encrypted file for Install-AIMachine.ps1 -SecretsFile on another machine (spec R16).
    Values are never printed. The passphrase is typed twice and never stored.
#>
param(
    [Parameter(Mandatory)][string]$Out,
    [string]$CorpusRoot = (Join-Path $PSScriptRoot '..'),
    [string]$ClaudeJson = (Join-Path $HOME '.claude.json'),
    [securestring]$Passphrase   # tests only; normally typed
)
$ErrorActionPreference = 'Stop'
$lib = @((Join-Path $PSScriptRoot '..\lib'), (Join-Path $PSScriptRoot 'lib')) | Where-Object { Test-Path (Join-Path $_ 'AISecrets.psm1') } | Select-Object -First 1
Import-Module (Join-Path $lib 'AISecrets.psm1') -Force
$tplPath = @((Join-Path $CorpusRoot 'claude\mcp-servers.json'), (Join-Path $CorpusRoot 'machine-config\claude\mcp-servers.json')) | Where-Object { Test-Path $_ } | Select-Object -First 1
$manPath = Join-Path $CorpusRoot 'ai-manifest.json'
$tpl = Get-Content -LiteralPath $tplPath -Raw | ConvertFrom-Json
$secretEnv = if (Test-Path -LiteralPath $manPath) { @((Get-Content -LiteralPath $manPath -Raw | ConvertFrom-Json).secretEnv) } else { @() }
$cj = Get-Content -LiteralPath $ClaudeJson -Raw | ConvertFrom-Json -AsHashtable

$data = [ordered]@{ mcp = [ordered]@{}; env = [ordered]@{} }
$missing = @()
foreach ($id in $tpl.secrets) {
    $v = Get-AIMcpSecretValue -ClaudeJson $cj -Id $id
    if ($null -eq $v -or "$v" -eq '') { $missing += "mcp $id" } else { $data.mcp[$id] = [string]$v }
}
foreach ($n in $secretEnv) {
    $v = [Environment]::GetEnvironmentVariable($n, 'User')
    if ($v) { $data.env[$n] = $v } else { $missing += "env $n" }
}
if (-not $Passphrase) {
    $Passphrase = Read-Host 'Passphrase for the secrets file' -AsSecureString
    $again = Read-Host 'Type it again' -AsSecureString
    $a = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Passphrase))
    $b = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($again))
    if ($a -cne $b) { throw 'The passphrases differ; nothing written.' }
    if ($a.Length -lt 12) { throw 'Use a passphrase of at least 12 characters; nothing written.' }
}
Protect-AISecrets -Data $data -Passphrase $Passphrase -Path $Out
"Wrote $Out : $($data.mcp.Count) MCP secret fields, $($data.env.Count) env vars (names only below)."
$data.mcp.Keys | ForEach-Object { "  mcp $_" }
$data.env.Keys | ForEach-Object { "  env $_" }
if ($missing) { "Not found on this machine (not exported): $($missing -join ', ')" }
'Move the file to the target machine yourself and delete it after the import.'
