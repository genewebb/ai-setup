# Gene.Profile: the prof hub (long alias manageProfile). Loaded on first use of prof by module autoloading.
# Design: docs\manageprofile-design.md in the ai-setup clone.
$ErrorActionPreference = 'Stop'
foreach ($f in 'Target.ps1', 'Sync.ps1', 'Menu.ps1', 'Verbs.ps1') { . (Join-Path $PSScriptRoot $f) }
Export-ModuleMember -Function Invoke-GeneProf, Select-GeneMenu, Read-GeneYesNo, Read-GeneText, Get-GeneMachines, Add-GeneMachine, Get-GeneHubRoot, Resolve-GeneTarget, Close-GeneTarget -Alias prof, manageProfile
