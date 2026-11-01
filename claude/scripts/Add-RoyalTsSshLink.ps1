#requires -Version 7
<#
Add an SSH connection to a Royal TS document. Manual twin of the
royalts-container-link hook, for containers created outside Claude Code's
MCP tool (for example through the call_proxmox_mcp.py CLI or the Proxmox UI).

    pwsh -NoProfile -File Add-RoyalTsSshLink.ps1 -Name trading-db -Uri 192.168.8.220 -Description 'Proxmox LXC 200 on homeai'

Document defaults to the profile key RoyalTsHomeAILinux ($env:AI_ROYALTSHOMEAILINUX).
#>
param(
    [Parameter(Mandatory)] [string] $Name,
    [Parameter(Mandatory)] [string] $Uri,
    [int] $Port = 22,
    [string] $Description = '',
    [string] $CredentialName = 'HomeAI guest key (root)',
    [string] $DocumentPath = $env:AI_ROYALTSHOMEAILINUX
)
$ErrorActionPreference = 'Stop'
if (-not $DocumentPath) { throw 'No document: pass -DocumentPath or set profile key RoyalTsHomeAILinux.' }
. (Join-Path $PSScriptRoot 'lib\RoyalTs.ps1')
if (Get-Process -Name RoyalTS -ErrorAction SilentlyContinue) { Write-Warning 'Royal TS is running. If this document is open there, its next save overwrites this change; reload the document in Royal TS afterwards.' }
$id = Add-RoyalTsSshConnection -DocumentPath $DocumentPath -Name $Name -Uri $Uri -Port $Port -Description $Description -CredentialName $CredentialName
if ($id) { "added '$Name' -> ${Uri}:$Port (id $id) to $DocumentPath" } else { "'$Name' or $Uri already present in $DocumentPath; nothing added" }
