# RoyalDocument.PowerShell reference

Verified against RoyalDocument.PowerShell 7.3.50415.0 (PSGallery, Royal Apps GmbH) with Royal TS V7
(default install `C:\Program Files\Royal TS V7\RoyalTS.exe`). The module is NOT shipped in the Royal TS install folder; <!-- example-path -->
install it from PSGallery.

## Discover, do not guess

Every value below came from these two commands. Use them for any property not listed:

```powershell
$o = New-RoyalObject -Folder $doc -Type RoyalRDSConnection -Name probe
$o | Get-Member -MemberType Property | Where-Object Name -match 'Gateway|Credential|Port'
Get-RoyalPropertyHelp -ClassName RoyalRDSConnection -PropertyName SecureGatewayUsageMode   # Summary lists the int values
```

Object types (`New-RoyalObject -Type`): RoyalFolder, RoyalCredential, RoyalRDSConnection, RoyalSSHConnection,
RoyalSecureGateway, RoyalRDSGateway, RoyalVNCConnection, RoyalFileTransferConnection, RoyalWebConnection,
RoyalPowerShellConnection, RoyalCommandTask, ... (full list: `[Enum]::GetNames((Get-Command New-RoyalObject).Parameters['Type'].ParameterType)`).

## Document lifecycle

```powershell
$store = New-RoyalStore -UserName $env:USERNAME
$doc   = New-RoyalDocument -Store $store -Name 'X' -FileName $path       # or Open-RoyalDocument -Store $store -FileName $path
$obj   = New-RoyalObject -Folder $doc -Type RoyalSSHConnection -Name 'Y'
Set-RoyalObjectValue -Object $obj -Property URI -Value '10.0.0.5' | Out-Null
Out-RoyalDocument -Document $doc -FileName $path
Close-RoyalDocument -Document $doc
```

Gotcha: `Get-RoyalObject -Type A, B` silently returns only one type. Call once per type.

## Properties used

| Class | Property | Values |
|---|---|---|
| RoyalCredential | UserName, PrivateKeyPath | |
| RoyalCredential | PrivateKeyMode | 0 = path to file, 1 = embedded |
| RoyalSecureGateway | SecureGatewayHost, SecureGatewayPort (default 22) | |
| RoyalSecureGateway | SecureGatewayCredentialMode | 0 none, 1 specify username+password, 2 existing credential, 3 credential name |
| RoyalSecureGateway | SecureGatewayCredentialID | credential `.ID` (Guid) |
| RoyalSSHConnection | URI, Port (default 22), PrivateKeyPath | |
| RoyalRDSConnection | URI, RDPPort (default 3389) | |
| RoyalRDSConnection | SecureGatewayUsageMode | 0 never, 1 always, 2 on demand |
| RoyalRDSConnection | SecureGatewayID, SecureGatewayFromParent | gateway `.ID`; set FromParent `$false` |
| connections | CredentialMode | 0 none, 1 from parent folder, 2 specify username+password, 3 existing credential, 4 credential name |
| connections | CredentialId | credential `.ID` |
| RoyalRDSConnection | GatewayCredentialMode | belongs to the Microsoft RD Gateway (RoyalRDSGateway), NOT the SSH Secure Gateway |

Secret-bearing properties (never print): Password, Passphrase, PrivateKeyContent, CredentialPassword,
CredentialPassphrase, CredentialKeyContent, SecureGatewayPassword, GatewayPassword, ProxyPassword, and all
`Effective*` password/key-content properties. `EffectiveHasPassword` (Yes/No) is safe.
