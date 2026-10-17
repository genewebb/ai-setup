<#
.SYNOPSIS
    Prints the connection-relevant settings of every credential, Secure Gateway, SSH and RDP object in
    a Royal TS document. Never prints passwords, passphrases or embedded key content: only whether a
    password is stored (EffectiveHasPassword) and the key FILE path.

.EXAMPLE
    .\Show-RoyalDocument.ps1 -Path '<documents folder>\Linux Droplet.rtsz'
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [string]$StoreUser = $env:USERNAME
)

$ErrorActionPreference = 'Stop'
Import-Module RoyalDocument.PowerShell
$doc = Open-RoyalDocument -Store (New-RoyalStore -UserName $StoreUser) -FileName $Path
try {
    $names = @{}
    # -Type takes one type per call (a list silently returns only one of them).
    foreach ($t in 'RoyalCredential', 'RoyalSecureGateway') { Get-RoyalObject -Folder $doc -Type $t | ForEach-Object { $names["$($_.ID)"] = $_.Name } }
    $ref = { param($id) if ($names.ContainsKey("$id")) { $names["$id"] } elseif ("$id" -match '^0{8}-') { '-' } else { "MISSING $id" } }

    Get-RoyalObject -Folder $doc -Type RoyalCredential | ForEach-Object {
        'CRED  {0} | user={1} keyMode={2} keyFile={3} hasPassword={4}' -f $_.Name, $_.UserName, $_.PrivateKeyMode, $_.PrivateKeyPath, $_.EffectiveHasPassword }
    Get-RoyalObject -Folder $doc -Type RoyalSecureGateway | ForEach-Object {
        'GW    {0} | {1}:{2} credMode={3} cred={4} user={5}' -f $_.Name, $_.SecureGatewayHost, $_.SecureGatewayPort, $_.SecureGatewayCredentialMode, (& $ref $_.SecureGatewayCredentialID), $_.SecureGatewayUsername }
    Get-RoyalObject -Folder $doc -Type RoyalSSHConnection | ForEach-Object {
        'SSH   {0} | {1}:{2} credMode={3} cred={4} user={5} keyFile={6}' -f $_.Name, $_.URI, $_.Port, $_.CredentialMode, (& $ref $_.CredentialId), $_.CredentialUsername, $_.PrivateKeyPath }
    Get-RoyalObject -Folder $doc -Type RoyalRDSConnection | ForEach-Object {
        'RDP   {0} | {1}:{2} gwUsage={3} gwFromParent={4} gw={5} credMode={6} cred={7} user={8}' -f $_.Name, $_.URI, $_.RDPPort, $_.SecureGatewayUsageMode, $_.SecureGatewayFromParent, (& $ref $_.SecureGatewayID), $_.CredentialMode, (& $ref $_.CredentialId), $_.CredentialUsername }
}
finally { Close-RoyalDocument -Document $doc }
