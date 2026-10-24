# Gene.Profile: the prof hub (long alias manageProfile). Loaded on first use of prof by module autoloading.
# Design: docs\manageprofile-design.md in the ai-setup clone.
# Core files first, then the group files in menu order; a file that is not there is skipped, so a shared copy of the
# hub (prof setup share: no SetupGroup, Target, Sync, Share) loads with just the groups it was given.
$ErrorActionPreference = 'Stop'
$geneProfOrder = 'Target.ps1', 'Sync.ps1', 'Menu.ps1', 'Verbs.ps1', 'StreamsGroup.ps1', 'SetupGroup.ps1', 'GitGroup.ps1', 'BuildGroup.ps1', 'OtherGroup.ps1', 'Share.ps1', 'ShareSkills.ps1'
foreach ($f in $geneProfOrder) { $p = Join-Path $PSScriptRoot $f; if (Test-Path -LiteralPath $p) { . $p } }
foreach ($f in Get-ChildItem -LiteralPath $PSScriptRoot -Filter '*.ps1' | Where-Object { $_.Name -notin $geneProfOrder } | Sort-Object Name) { . $f.FullName }
$geneProfExports = @('Invoke-GeneProf', 'Select-GeneMenu', 'Read-GeneYesNo', 'Read-GeneText', 'Get-GeneMachines', 'Add-GeneMachine', 'Get-GeneHubRoot', 'Resolve-GeneTarget', 'Close-GeneTarget') |
    Where-Object { Get-Command -Name $_ -CommandType Function -ErrorAction SilentlyContinue }
Export-ModuleMember -Function $geneProfExports -Alias prof, manageProfile