<#
.SYNOPSIS
    Deletes the files of the named categories from a Find-SafeCleanup.ps1 manifest, re-validating each one.
.DESCRIPTION
    Allowed roots are recomputed from the drive letter; paths in the manifest are never trusted on their own.
    A file is deleted only if it is still under a category root, matches the pattern, is not hard-excluded,
    is not behind a junction, is old enough, and its size and timestamp still match the scan.
    Regenerable categories run the tool's own clear command instead of deleting files.
.EXAMPLE
    pwsh -NoProfile -File Remove-SafeCleanup.ps1 -ManifestPath <scan.json> -Category UserTemp,CrashDumps -Confirm:$false
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory)][string]$ManifestPath,
    [Parameter(Mandatory)][string[]]$Category,
    [int]$MaxManifestAgeHours = 24
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DiskCleanup.Categories.ps1')

$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$age = [datetime]::UtcNow - ([datetime]::Parse($manifest.CreatedUtc)).ToUniversalTime()
if ($age.TotalHours -gt $MaxManifestAgeHours) { throw "Manifest is $([int]$age.TotalHours)h old. Re-run Find-SafeCleanup.ps1." }

$root = Get-DcDriveRoot $manifest.Drive
$allowed = @{}
foreach ($c in Get-DcCategories $root) { $allowed[$c.Name] = $c }
$freeBefore = [IO.DriveInfo]::new($root).AvailableFreeSpace

# pwsh -File passes "A,B" as one string; accept both forms.
$Category = @($Category | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$unknown = $Category | Where-Object { -not $allowed.ContainsKey($_) }
if ($unknown) { throw "Unknown category: $($unknown -join ', '). Allowed: $($allowed.Keys -join ', ')" }

$logPath = [IO.Path]::ChangeExtension($ManifestPath, ".removed-$(Get-Date -Format 'HHmmss').csv")
$log = [Collections.Generic.List[object]]::new()
$junctionCache = @{}

function Test-NoJunctionBetween([string]$FullPath, [string[]]$Roots) {
    $dir = [IO.Path]::GetDirectoryName($FullPath)
    while ($dir) {
        if ($Roots | Where-Object { $_.TrimEnd('\') -ieq $dir }) { return $true }
        if (-not $junctionCache.ContainsKey($dir)) {
            $di = [IO.DirectoryInfo]::new($dir)
            $junctionCache[$dir] = $di.Exists -and [bool]($di.Attributes -band [IO.FileAttributes]::ReparsePoint)
        }
        if ($junctionCache[$dir]) { return $false }
        $dir = [IO.Path]::GetDirectoryName($dir)
    }
    $false
}

foreach ($name in $Category) {
    $c = $allowed[$name]
    $entry = $manifest.Categories | Where-Object Name -eq $name
    if (-not $entry) { Write-Warning "$name not in manifest; skipped."; continue }

    $running = @($c.ProcessNames | ForEach-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue })
    if ($running) {
        Write-Warning "$name skipped: close $(($running.ProcessName | Select-Object -Unique) -join ', ') first."
        continue
    }

    if ($c.Command) {
        if (-not (Get-Command $c.Command -ErrorAction SilentlyContinue)) { Write-Warning "$name skipped: '$($c.Command)' not found."; continue }
        if ($PSCmdlet.ShouldProcess("$name ($($c.Command) $($c.CommandArgs -join ' '))", 'Run clear command')) {
            & $c.Command @($c.CommandArgs)
            $log.Add([pscustomobject]@{ Category = $name; Path = "$($c.Command) $($c.CommandArgs -join ' ')"; Length = $entry.Bytes; Result = "exit $LASTEXITCODE" })
        }
        continue
    }

    $ok = 0; $okBytes = 0L; $skipped = 0; $failed = 0
    foreach ($f in @($entry.Files)) {
        $full = [IO.Path]::GetFullPath($f.Path)
        $fi = [IO.FileInfo]::new($full)
        $reason = if (-not (Test-DcInCategory $full $c)) { 'outside allowlist' }
            elseif (-not $fi.Exists) { 'gone' }
            elseif ($fi.Attributes -band [IO.FileAttributes]::ReparsePoint) { 'reparse point' }
            elseif ($fi.Length -ne [long]$f.Length -or $fi.LastWriteTimeUtc.Ticks -ne [long]$f.LastWriteUtcTicks) { 'changed since scan' }
            elseif (-not (Test-DcOldEnough $fi.LastWriteTimeUtc $c.MinAgeDays)) { 'too new' }
            elseif (-not (Test-NoJunctionBetween $full $c.Roots)) { 'behind junction' }
            else { $null }
        if ($reason) { $skipped++; $log.Add([pscustomobject]@{ Category = $name; Path = $full; Length = $f.Length; Result = "skip: $reason" }); continue }
        if (-not $PSCmdlet.ShouldProcess($full, 'Delete')) { continue }
        try {
            if ($fi.Attributes -band [IO.FileAttributes]::ReadOnly) { $fi.Attributes = $fi.Attributes -bxor [IO.FileAttributes]::ReadOnly }
            $fi.Delete()
            $ok++; $okBytes += $f.Length
            $log.Add([pscustomobject]@{ Category = $name; Path = $full; Length = $f.Length; Result = 'deleted' })
        }
        catch {
            $failed++
            $log.Add([pscustomobject]@{ Category = $name; Path = $full; Length = $f.Length; Result = "fail: $($_.Exception.Message)" })
        }
    }

    # Remove now-empty subfolders (deepest first). Category roots themselves are kept.
    if (-not $WhatIfPreference) {
        foreach ($r in $c.Roots) {
            $opts = [IO.EnumerationOptions]::new()
            $opts.RecurseSubdirectories = $true; $opts.IgnoreInaccessible = $true
            $opts.AttributesToSkip = [IO.FileAttributes]::ReparsePoint
            $dirs = try { @([IO.DirectoryInfo]::new($r).EnumerateDirectories('*', $opts)) } catch { @() }
            foreach ($d in ($dirs | Sort-Object { $_.FullName.Length } -Descending)) {
                try { if (-not $d.EnumerateFileSystemInfos().GetEnumerator().MoveNext()) { $d.Delete() } } catch { }
            }
        }
    }
    "{0,-22} deleted {1,7} files  {2,10}   skipped {3}  failed (locked/denied) {4}" -f $name, $ok, (Format-DcSize $okBytes), $skipped, $failed
}

if ($log.Count -and -not $WhatIfPreference) { $log | Export-Csv -LiteralPath $logPath -NoTypeInformation -Encoding utf8; "LOG: $logPath" }
$freeAfter = [IO.DriveInfo]::new($root).AvailableFreeSpace
"Free space on ${root}: $(Format-DcSize $freeBefore) -> $(Format-DcSize $freeAfter)  (+$(Format-DcSize ([math]::Max([long]0, $freeAfter - $freeBefore))))"
