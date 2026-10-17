<#
.SYNOPSIS
    Creates a NEW Royal TS document for one Linux host reached over SSH: a key credential, an SSH
    Secure Gateway, an SSH terminal connection and (optionally) an RDP connection tunnelled through
    the gateway. No passwords are written; the RDP credential is created with only a username.

.EXAMPLE
    .\New-RoyalSshTunnelDocument.ps1 -Path '<documents folder>\Linux Droplet.rtsz' -HostAddress 159.223.100.95 `
        -User gene -KeyFile '{SecretsDir}\do_droplet\do_droplet_ed25519' -Rdp
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)][string]$HostAddress,
    [Parameter(Mandatory)][string]$User,
    [Parameter(Mandatory)][string]$KeyFile,
    [string]$Name = 'Linux',
    [int]$SshPort = 22,
    [switch]$Rdp,
    [int]$RdpPort = 3389,
    [string]$StoreUser = $env:USERNAME
)

$ErrorActionPreference = 'Stop'
if (Test-Path -LiteralPath $Path) { throw "Refusing to overwrite existing document: $Path" }
if (-not (Get-Module -ListAvailable RoyalDocument.PowerShell)) {
    throw 'RoyalDocument.PowerShell not installed. Run: Install-Module RoyalDocument.PowerShell -Scope CurrentUser -Repository PSGallery'
}
Import-Module RoyalDocument.PowerShell

function Set-Values($Object, [hashtable]$Values) {
    foreach ($k in $Values.Keys) { Set-RoyalObjectValue -Object $Object -Property $k -Value $Values[$k] | Out-Null }
}

$store = New-RoyalStore -UserName $StoreUser
$doc = New-RoyalDocument -Store $store -Name ([IO.Path]::GetFileNameWithoutExtension($Path)) -FileName $Path

# Credential Mode on connections: 3 = use an existing credential. PrivateKeyMode 0 = path to file.
$keyCred = New-RoyalObject -Folder $doc -Type RoyalCredential -Name "$Name SSH key ($User)"
Set-Values $keyCred @{ UserName = $User; PrivateKeyMode = 0; PrivateKeyPath = $KeyFile }

$ssh = New-RoyalObject -Folder $doc -Type RoyalSSHConnection -Name "$Name Terminal"
Set-Values $ssh @{ URI = $HostAddress; Port = $SshPort; CredentialMode = 3; CredentialId = $keyCred.ID }

if ($Rdp) {
    $rdpCred = New-RoyalObject -Folder $doc -Type RoyalCredential -Name "$Name desktop ($User)" -Description 'Add the desktop password here.'
    Set-Values $rdpCred @{ UserName = $User }

    # SecureGatewayCredentialMode 2 = use an existing credential.
    $gw = New-RoyalObject -Folder $doc -Type RoyalSecureGateway -Name "$Name SSH gateway"
    Set-Values $gw @{ SecureGatewayHost = $HostAddress; SecureGatewayPort = $SshPort; SecureGatewayCredentialMode = 2; SecureGatewayCredentialID = $keyCred.ID }

    # URI is resolved on the gateway side, so 127.0.0.1 = the Linux host itself. SecureGatewayUsageMode 1 = Always.
    $rdpConn = New-RoyalObject -Folder $doc -Type RoyalRDSConnection -Name "$Name Desktop"
    Set-Values $rdpConn @{ URI = '127.0.0.1'; RDPPort = $RdpPort; SecureGatewayFromParent = $false; SecureGatewayUsageMode = 1;
        SecureGatewayID = $gw.ID; CredentialMode = 3; CredentialId = $rdpCred.ID }
}

Out-RoyalDocument -Document $doc -FileName $Path
Close-RoyalDocument -Document $doc
Get-Item -LiteralPath $Path
