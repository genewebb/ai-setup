#requires -Version 7
<#
Royal TS document helpers built on the official RoyalDocument.PowerShell module
(PSGallery, Royal Apps GmbH). Dot-source this file. See skills\royalts\SKILL.md.

    Install-Module RoyalDocument.PowerShell -Scope CurrentUser -Repository PSGallery

Every function opens the document, changes it, writes it back and closes it, so
a caller never holds a document handle. A timestamped backup is written beside
the document before each save; the last 5 are kept.

Royal TS keeps an open document in memory: a write made here while the document
is open in Royal TS is lost at its next save. Warn when RoyalTS.exe is running.

Numeric modes (verified, see skills\royalts\REFERENCE.md):
  connection CredentialMode 3 = use an existing credential (CredentialId)
  credential PrivateKeyMode  0 = path to a key file
#>

function Import-RoyalTsModule {
    if (-not (Get-Module RoyalDocument.PowerShell)) {
        if (-not (Get-Module -ListAvailable RoyalDocument.PowerShell)) {
            throw 'RoyalDocument.PowerShell not installed. Run: Install-Module RoyalDocument.PowerShell -Scope CurrentUser -Repository PSGallery'
        }
        Import-Module RoyalDocument.PowerShell -ErrorAction Stop
    }
}

function Backup-RoyalTsDocument {
    param([Parameter(Mandatory)] [string] $Path, [int] $KeepBackups = 5)
    $full = (Resolve-Path -LiteralPath $Path).Path
    Copy-Item -LiteralPath $full -Destination "$full.bak-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
    Get-ChildItem -LiteralPath (Split-Path $full) -Filter ((Split-Path $full -Leaf) + '.bak-*') |
        Sort-Object Name -Descending | Select-Object -Skip $KeepBackups | Remove-Item -Force
}

function Invoke-RoyalTsDocument {
    <# Opens $Path, runs $Action with the document, saves when $Action returns $true, always closes. #>
    param(
        [Parameter(Mandatory)] [string] $Path,
        [Parameter(Mandatory)] [scriptblock] $Action
    )
    Import-RoyalTsModule
    if (-not (Test-Path -LiteralPath $Path)) { throw "Royal TS document not found: $Path" }
    $full = (Resolve-Path -LiteralPath $Path).Path
    $doc = Open-RoyalDocument -Store (New-RoyalStore -UserName $env:USERNAME) -FileName $full
    try {
        $result = & $Action $doc
        if ($result.Save) {
            Backup-RoyalTsDocument -Path $full
            Out-RoyalDocument -Document $doc -FileName $full
        }
        return $result.Value
    }
    finally { Close-RoyalDocument -Document $doc }
}

function Set-RoyalTsValues {
    param([Parameter(Mandatory)] $Object, [Parameter(Mandatory)] [hashtable] $Values)
    foreach ($k in $Values.Keys) { Set-RoyalObjectValue -Object $Object -Property $k -Value $Values[$k] | Out-Null }
}

function Find-RoyalTsCredential {
    param([Parameter(Mandatory)] $Document, [Parameter(Mandatory)] [string] $Name)
    return @(Get-RoyalObject -Folder $Document -Type RoyalCredential | Where-Object Name -eq $Name) | Select-Object -First 1
}

function Test-RoyalTsConnectionExists {
    param([Parameter(Mandatory)] $Document, [string] $Name, [string] $Uri)
    foreach ($type in 'RoyalSSHConnection', 'RoyalRDSConnection', 'RoyalWebConnection') {
        # One type per Get-RoyalObject call: a list of types silently returns only one.
        foreach ($c in @(Get-RoyalObject -Folder $Document -Type $type)) {
            if ($Name -and $c.Name -eq $Name) { return $true }
            if ($Uri -and $c.URI -eq $Uri) { return $true }
        }
    }
    return $false
}

function Add-RoyalTsKeyCredential {
    <#
    Adds a RoyalCredential that logs in with a private key file. Returns the
    credential ID; an existing credential with the same Name is returned unchanged.
    #>
    param(
        [Parameter(Mandatory)] [string] $DocumentPath,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $UserName,
        [Parameter(Mandatory)] [string] $PrivateKeyPath,
        [string] $Description = ''
    )
    Invoke-RoyalTsDocument -Path $DocumentPath -Action {
        param($doc)
        $existing = Find-RoyalTsCredential -Document $doc -Name $Name
        if ($existing) { return @{ Save = $false; Value = "$($existing.ID)" } }
        $cred = New-RoyalObject -Folder $doc -Type RoyalCredential -Name $Name -Description $Description
        Set-RoyalTsValues $cred @{ UserName = $UserName; PrivateKeyMode = 0; PrivateKeyPath = $PrivateKeyPath }
        return @{ Save = $true; Value = "$($cred.ID)" }
    }
}

function Add-RoyalTsSshConnection {
    <#
    Adds a RoyalSSHConnection at document top level. Returns the new ID, or $null
    when a connection with the same Name or URI already exists. CredentialName
    names an existing RoyalCredential; when omitted or not found the connection
    is created without one and Royal TS prompts on connect.
    #>
    param(
        [Parameter(Mandatory)] [string] $DocumentPath,
        [Parameter(Mandatory)] [string] $Name,
        [Parameter(Mandatory)] [string] $Uri,
        [int] $Port = 22,
        [string] $Description = '',
        [string] $CredentialName
    )
    Invoke-RoyalTsDocument -Path $DocumentPath -Action {
        param($doc)
        if (Test-RoyalTsConnectionExists -Document $doc -Name $Name -Uri $Uri) { return @{ Save = $false; Value = $null } }
        $conn = New-RoyalObject -Folder $doc -Type RoyalSSHConnection -Name $Name -Description $Description
        $values = @{ URI = $Uri; Port = $Port }
        $cred = if ($CredentialName) { Find-RoyalTsCredential -Document $doc -Name $CredentialName } else { $null }
        if ($cred) { $values.CredentialMode = 3; $values.CredentialId = $cred.ID }
        Set-RoyalTsValues $conn $values
        return @{ Save = $true; Value = "$($conn.ID)" }
    }
}
