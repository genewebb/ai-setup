#requires -Version 7
<#
Passphrase-protected secrets file for moving Claude's own secrets between machines (spec R16).

    Protect-AISecrets   -Data <hashtable> -Passphrase <SecureString> -Path <file>
    Unprotect-AISecrets -Path <file> -Passphrase <SecureString>      # returns the hashtable

AES-256-GCM, key from PBKDF2-SHA256 (600,000 iterations, 16-byte salt). The passphrase is typed and never stored.
The file holds { mcp = { '<server>/<field>' = value }; env = { NAME = value } }.
#>
Set-StrictMode -Version Latest
$script:Iterations = 600000

function ConvertFrom-AISecure([securestring]$s) {
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
}

function Get-AIKey([securestring]$Passphrase, [byte[]]$Salt, [int]$Iterations) {
    $pw = [Text.Encoding]::UTF8.GetBytes((ConvertFrom-AISecure $Passphrase))
    try { return [Security.Cryptography.Rfc2898DeriveBytes]::Pbkdf2($pw, $Salt, $Iterations, [Security.Cryptography.HashAlgorithmName]::SHA256, 32) }
    finally { [Array]::Clear($pw, 0, $pw.Length) }
}

function Protect-AISecrets {
    param([Parameter(Mandatory)][System.Collections.IDictionary]$Data, [Parameter(Mandatory)][securestring]$Passphrase, [Parameter(Mandatory)][string]$Path)
    $salt = [Security.Cryptography.RandomNumberGenerator]::GetBytes(16)
    $nonce = [Security.Cryptography.RandomNumberGenerator]::GetBytes(12)
    $key = Get-AIKey $Passphrase $salt $script:Iterations
    $plain = [Text.Encoding]::UTF8.GetBytes(($Data | ConvertTo-Json -Depth 10 -Compress))
    $cipher = [byte[]]::new($plain.Length); $tag = [byte[]]::new(16)
    $gcm = [Security.Cryptography.AesGcm]::new($key, 16)
    try { $gcm.Encrypt($nonce, $plain, $cipher, $tag) } finally { $gcm.Dispose(); [Array]::Clear($key, 0, $key.Length); [Array]::Clear($plain, 0, $plain.Length) }
    $doc = [ordered]@{
        format = 'ai-secrets/1'; created = (Get-Date).ToString('o'); machine = $env:COMPUTERNAME; iterations = $script:Iterations
        salt = [Convert]::ToBase64String($salt); nonce = [Convert]::ToBase64String($nonce); tag = [Convert]::ToBase64String($tag); cipher = [Convert]::ToBase64String($cipher)
    }
    [IO.File]::WriteAllText($Path, ($doc | ConvertTo-Json))
}

function Unprotect-AISecrets {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][securestring]$Passphrase)
    $doc = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
    if ($doc.format -ne 'ai-secrets/1') { throw "$Path is not an ai-secrets/1 file." }
    $key = Get-AIKey $Passphrase ([Convert]::FromBase64String($doc.salt)) ([int]$doc.iterations)
    $cipher = [Convert]::FromBase64String($doc.cipher); $plain = [byte[]]::new($cipher.Length)
    $gcm = [Security.Cryptography.AesGcm]::new($key, 16)
    try { $gcm.Decrypt([Convert]::FromBase64String($doc.nonce), $cipher, [Convert]::FromBase64String($doc.tag), $plain) }
    catch { throw 'Wrong passphrase, or the secrets file was changed.' }
    finally { $gcm.Dispose(); [Array]::Clear($key, 0, $key.Length) }
    try { return ([Text.Encoding]::UTF8.GetString($plain) | ConvertFrom-Json -AsHashtable) } finally { [Array]::Clear($plain, 0, $plain.Length) }
}

function Get-AIMcpSecretValue {
    <# Reads one secret field ('<server>/headers.X' | '/env.X' | '/args.N') from a ~\.claude.json hashtable. #>
    param([System.Collections.IDictionary]$ClaudeJson, [string]$Id)
    if ($Id -notmatch '^(.+)/(headers|env|args)\.(.+)$') { throw "Bad secret id '$Id'." }
    $s = $ClaudeJson.mcpServers[$Matches[1]]
    if (-not $s) { return $null }
    switch ($Matches[2]) {
        'headers' { if ($s.Contains('headers')) { return $s.headers[$Matches[3]] } }
        'env' { if ($s.Contains('env')) { return $s.env[$Matches[3]] } }
        'args' { $i = [int]$Matches[3]; if ($s.Contains('args') -and $i -lt @($s.args).Count) { return @($s.args)[$i] } }
    }
    return $null
}

Export-ModuleMember -Function Protect-AISecrets, Unprotect-AISecrets, Get-AIMcpSecretValue
