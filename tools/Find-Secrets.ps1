#requires -Version 7
<#
.SYNOPSIS
    Pattern scan for credentials in files about to be committed or promoted. Returns one object per hit.

.DESCRIPTION
    A guard, not a proof: it catches the common shapes (tokens, keys, connection-string passwords, private keys).
    Prints nothing and returns nothing when clean. Values are never echoed, only file, line and rule.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Root,
    [string[]]$Files
)
$ErrorActionPreference = 'Stop'

$rules = [ordered]@{
    'github-token'      = 'gh[pousr]_[A-Za-z0-9]{36,}|github_pat_[A-Za-z0-9_]{40,}'
    'anthropic-key'     = 'sk-ant-[A-Za-z0-9_\-]{20,}'
    'aws-access-key'    = 'AKIA[0-9A-Z]{16}'
    'private-key'       = '-----BEGIN [A-Z ]*PRIVATE KEY-----'
    'jwt'               = 'eyJ[A-Za-z0-9_\-]{10,}\.eyJ[A-Za-z0-9_\-]{10,}\.[A-Za-z0-9_\-]{10,}'
    'conn-password'     = '(?i)(password|pwd)\s*=\s*[^;{}\s"''<>]{4,}'
    'storage-key'       = '(?i)AccountKey\s*=\s*[A-Za-z0-9+/=]{20,}'
    'basic-auth-url'    = 'https?://[^/\s:@]+:[^/\s@{}$]{8,}@'
    'ado-pat-assign'    = '(?i)(pat|token|apikey|api_key|secret)\s*[:=]\s*["'']?[A-Za-z0-9+/]{40,}'
}

$paths = if ($Files) { $Files | ForEach-Object { Join-Path $Root $_ } }
         else { Get-ChildItem -LiteralPath $Root -Recurse -File | Where-Object FullName -notmatch '[\\/]\.git[\\/]' | ForEach-Object FullName }

foreach ($p in $paths) {
    if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { continue }   # deleted in this change
    if ([IO.Path]::GetExtension($p) -in '.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.exe', '.dll', '.pdf', '.woff', '.woff2') { continue }
    $n = 0
    foreach ($line in [IO.File]::ReadLines($p)) {
        $n++
        foreach ($r in $rules.GetEnumerator()) {
            if ($line -match $r.Value) {
                [pscustomobject]@{ File = [IO.Path]::GetRelativePath($Root, $p); Line = $n; Rule = $r.Key }
            }
        }
    }
}
