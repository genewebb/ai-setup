@{
    RootModule        = 'Gene.Profile.psm1'
    ModuleVersion     = '1.0.0'
    GUID              = '0282bce5-edc8-4bc7-985c-36b6ac9376ae'
    Author            = 'Gene'
    Description       = 'prof: one command for the PowerShell profile, the AI runtime and the machines that run them (pwsh 7).'
    PowerShellVersion = '7.2'
    FunctionsToExport = @('Invoke-GeneProf', 'Select-GeneMenu', 'Read-GeneYesNo', 'Read-GeneText', 'Get-GeneMachines', 'Add-GeneMachine', 'Get-GeneHubRoot', 'Resolve-GeneTarget', 'Close-GeneTarget')
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @('prof', 'manageProfile')
}
