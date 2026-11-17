#requires -Version 7
<#
.SYNOPSIS
Finds object IDs shared by more than one Royal TS document in a folder and, with -Fix,
gives the copies new IDs.

.DESCRIPTION
Royal TS refuses to load two objects with the same ID ("Duplicate Objects" dialog). That
happens when a document was made by copying another .rtsz. Without -Fix the script only
reports, printing IDs, object types and names (never credential fields).

With -Fix, the document named by -KeepDocument keeps its IDs (then the others in name
order). In every later document, each clashing ID is replaced as plain text across the
whole file, so internal references (ParentID, CredentialId, gateway links) follow it and
encrypted fields stay byte-identical. A .bak-dupids-<stamp> copy is written first.
Refuses to run -Fix while RoyalTS.exe is running (its next save would undo the fix).

.EXAMPLE
.\Repair-RoyalDuplicateIds.ps1 -Directory D:\RemoteDesktops
.\Repair-RoyalDuplicateIds.ps1 -Directory D:\RemoteDesktops -Fix -KeepDocument 'Connections (Gene Webb)'
#>
param(
    [Parameter(Mandatory)] [string] $Directory,
    [switch] $Fix,
    [string] $KeepDocument
)
$ErrorActionPreference = 'Stop'

function Get-RoyalObjectIds([string] $Path) {
    [xml] $x = Get-Content -LiteralPath $Path -Raw
    @($x.DocumentElement.ChildNodes | Where-Object { $_.ID } | ForEach-Object {
        [pscustomobject]@{ Id = $_.ID.ToLowerInvariant(); Type = $_.LocalName; Name = $_.Name }
    })
}

$files = @(Get-ChildItem -LiteralPath $Directory -Filter *.rtsz | Sort-Object Name)
if ($KeepDocument) {
    if (-not ($files | Where-Object BaseName -eq $KeepDocument)) { throw "KeepDocument not found: $KeepDocument" }
    $files = @($files | Where-Object BaseName -eq $KeepDocument) + @($files | Where-Object BaseName -ne $KeepDocument)
}
if ($Fix -and (Get-Process RoyalTS -ErrorAction SilentlyContinue)) { throw 'Royal TS is running. Close it, then rerun with -Fix.' }

$seen = @{}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$total = 0
foreach ($f in $files) {
    $objects = Get-RoyalObjectIds $f.FullName
    $inDoc = @($objects | Group-Object Id | Where-Object Count -gt 1)
    if ($inDoc.Count) { Write-Warning "$($f.BaseName): $($inDoc.Count) IDs repeated inside the document (not touched)" }
    $clash = @($objects | Where-Object { $seen.ContainsKey($_.Id) } | Sort-Object Id -Unique)
    if (-not $clash.Count) {
        $objects | ForEach-Object { $seen[$_.Id] = $f.BaseName }
        "{0}: OK" -f $f.BaseName
        continue
    }
    $total += $clash.Count
    "{0}: {1} IDs already used in {2}" -f $f.BaseName, $clash.Count, (($clash | ForEach-Object { $seen[$_.Id] } | Sort-Object -Unique) -join ', ')
    $clash | Select-Object -First 5 | ForEach-Object { "    {0} {1} '{2}'" -f $_.Id, $_.Type, $_.Name }
    if (-not $Fix) { $objects | ForEach-Object { if (-not $seen.ContainsKey($_.Id)) { $seen[$_.Id] = $f.BaseName } }; continue }

    $enc = [System.Text.UTF8Encoding]::new($true)
    $text = [IO.File]::ReadAllText($f.FullName, $enc)
    Copy-Item -LiteralPath $f.FullName -Destination "$($f.FullName).bak-dupids-$stamp"
    foreach ($c in $clash) {
        $text = [regex]::Replace($text, [regex]::Escape($c.Id), [guid]::NewGuid().ToString(), 'IgnoreCase')
    }
    [xml] $null = $text
    [IO.File]::WriteAllText($f.FullName, $text, $enc)
    Get-RoyalObjectIds $f.FullName | ForEach-Object { $seen[$_.Id] = $f.BaseName }
    "    fixed: new IDs written, backup .bak-dupids-$stamp"
}
if (-not $Fix -and $total) { "Clashing IDs: $total. Rerun with -Fix -KeepDocument <name> to repair." }
