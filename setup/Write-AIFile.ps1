#requires -Version 7
# Script wrapper for lib\AIFile.psm1 Write-AIFile (spec R5): routes a write by the profile's Resources table.
#   Write-AIFile.ps1 -Path <absolute destination> -Source <file>
param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$Source)
$ErrorActionPreference = 'Stop'
$lib = @((Join-Path $PSScriptRoot '..\lib'), (Join-Path $PSScriptRoot 'lib')) | Where-Object { Test-Path (Join-Path $_ 'AIFile.psm1') } | Select-Object -First 1
Import-Module (Join-Path $lib 'MachineConfig.psm1') -Force -DisableNameChecking
Import-Module (Join-Path $lib 'AIFile.psm1') -Force -DisableNameChecking
$r = Write-AIFile -Path $Path -Source $Source
"$($r.Route): $($r.Path) ($($r.Hash.Substring(0,12)))"
