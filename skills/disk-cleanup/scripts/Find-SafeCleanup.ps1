<#
.SYNOPSIS
    Read-only scan: sizes every safe-cleanup category on a drive and lists the drive's largest files with a verdict.
.DESCRIPTION
    Deletes nothing. Writes a manifest JSON that Remove-SafeCleanup.ps1 consumes.
.EXAMPLE
    pwsh -NoProfile -File Find-SafeCleanup.ps1 -Drive D -Top 30
#>
[CmdletBinding()]
param(
    [string]$Drive = 'C',
    [ValidateRange(1, 500)][int]$Top = 25,
    [switch]$SkipLargest,
    [string]$OutDir = (Join-Path $env:LOCALAPPDATA 'DiskCleanup')
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'DiskCleanup.Categories.ps1')

$root = Get-DcDriveRoot $Drive
$isAdmin = Test-DcIsAdmin
$categories = @(Get-DcCategories $root)
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

$catResults = foreach ($c in $categories) {
    $files = [Collections.Generic.List[object]]::new()
    $bytes = 0L; $tooNewBytes = 0L; $tooNewCount = 0
    foreach ($r in $c.Roots) {
        foreach ($f in Get-DcFiles $r $c.Pattern $c.Recurse) {
            if (-not $seen.Add($f.FullName)) { continue }       # first category wins on overlap
            if (-not (Test-DcInCategory $f.FullName $c)) { continue }
            if (-not (Test-DcOldEnough $f.LastWriteTimeUtc $c.MinAgeDays)) {
                $tooNewBytes += $f.Length; $tooNewCount++; continue
            }
            $bytes += $f.Length
            if (-not $c.Command) {
                $files.Add([pscustomobject]@{ Path = $f.FullName; Length = $f.Length; LastWriteUtcTicks = $f.LastWriteTimeUtc.Ticks })
            }
        }
    }
    $cmdAvailable = if ($c.Command) { [bool](Get-Command $c.Command -ErrorAction SilentlyContinue) } else { $null }
    [pscustomobject]@{
        Name             = $c.Name
        Tier             = $c.Tier
        Description      = $c.Description
        MinAgeDays       = $c.MinAgeDays
        Roots            = $c.Roots
        Bytes            = $bytes
        Count            = if ($c.Command) { $null } else { $files.Count }
        TooNewBytes      = $tooNewBytes
        TooNewCount      = $tooNewCount
        Command          = if ($c.Command) { "$($c.Command) $($c.CommandArgs -join ' ')" } else { $null }
        CommandAvailable = $cmdAvailable
        Files            = $files
    }
}

# Hints for large files that are NOT deletable by this skill. Advice only.
$hints = @(
    @{ Re = '\\(pagefile|swapfile)\.sys$'; Hint = 'Page file. Never delete; resize in System Properties > Advanced > Performance.' }
    @{ Re = '\\hiberfil\.sys$'; Hint = 'Hibernation file. Owner may run "powercfg /h off" (admin) if hibernation is not needed.' }
    @{ Re = '\\Windows\\WinSxS\\'; Hint = 'Component store. Use "Dism.exe /Online /Cleanup-Image /StartComponentCleanup" (admin).' }
    @{ Re = '\\Windows\\Installer\\'; Hint = 'Never delete: breaks repair and uninstall of installed products.' }
    @{ Re = '\.(vhdx?|avhdx)$'; Hint = 'Virtual disk. Remove the VM, checkpoint or WSL distro through its own tool, not the file.' }
    @{ Re = '\.(mdf|ndf|ldf)$'; Hint = 'SQL Server database file. Never delete; detach, back up or shrink through SQL Server.' }
    @{ Re = '\\Downloads\\'; Hint = 'User download. Owner decides.' }
    @{ Re = '\.(iso|zip|7z|rar|msi|bak)$'; Hint = 'Archive, installer or backup. Owner decides.' }
    @{ Re = '\.log$'; Hint = 'Log file outside the allowlist. Owner may truncate it or fix rotation in the app that writes it.' }
)

$largest = @()
if (-not $SkipLargest) {
    $pq = [Collections.Generic.PriorityQueue[IO.FileInfo, long]]::new()
    foreach ($f in Get-DcFiles $root '*' $true) {
        $pq.Enqueue($f, $f.Length)
        if ($pq.Count -gt $Top) { [void]$pq.Dequeue() }
    }
    $topFiles = while ($pq.Count -gt 0) { $pq.Dequeue() }
    $largest = foreach ($f in ($topFiles | Sort-Object Length -Descending)) {
        $verdict = 'Keep'; $hint = $null
        foreach ($c in $categories) {
            if (Test-DcInCategory $f.FullName $c) {
                $verdict = if (Test-DcOldEnough $f.LastWriteTimeUtc $c.MinAgeDays) { "$($c.Tier):$($c.Name)" } else { "TooNew:$($c.Name)" }
                break
            }
        }
        if ($verdict -eq 'Keep') {
            foreach ($h in $hints) { if ($f.FullName -match $h.Re) { $hint = $h.Hint; break } }
        }
        [pscustomobject]@{ Path = $f.FullName; Length = $f.Length; LastWriteUtc = $f.LastWriteTimeUtc.ToString('u'); Verdict = $verdict; Hint = $hint }
    }
}

$driveInfo = [IO.DriveInfo]::new($root)
$manifest = [pscustomobject]@{
    Drive      = $root
    CreatedUtc = [datetime]::UtcNow.ToString('o')
    IsAdmin    = $isAdmin
    FreeBytes  = $driveInfo.AvailableFreeSpace
    TotalBytes = $driveInfo.TotalSize
    Categories = @($catResults)
    Largest    = @($largest)
    Warnings   = @($script:DcWarnings | Select-Object -Unique)
}
[void](New-Item -ItemType Directory -Force -Path $OutDir)
$manifestPath = Join-Path $OutDir ("scan-{0}-{1}.json" -f $root[0], (Get-Date -Format 'yyyyMMdd-HHmmss'))
$manifest | ConvertTo-Json -Depth 6 -Compress | Set-Content -LiteralPath $manifestPath -Encoding utf8

# Console report
"Drive $root  free $(Format-DcSize $driveInfo.AvailableFreeSpace) of $(Format-DcSize $driveInfo.TotalSize)  elevated=$isAdmin"
''
'== Safe-cleanup categories (eligible = old enough to delete) =='
$catResults | Sort-Object Bytes -Descending | Format-Table -AutoSize @(
    'Name', 'Tier',
    @{ n = 'Eligible'; e = { Format-DcSize $_.Bytes } },
    @{ n = 'Files'; e = { if ($null -ne $_.Count) { $_.Count } else { 'via cmd' } } },
    @{ n = 'TooNew'; e = { Format-DcSize $_.TooNewBytes } },
    @{ n = 'Notes'; e = { if ($_.Command) { if ($_.CommandAvailable) { $_.Command } else { "$($_.Command) (tool missing)" } } else { $_.Description } } }
) | Out-String -Width 220
$total = ($catResults | Measure-Object Bytes -Sum).Sum
"Total eligible: $(Format-DcSize $total)"
if (-not $SkipLargest) {
    ''
    "== Largest $Top files on $root =="
    $largest | Format-Table -AutoSize @(
        @{ n = 'Size'; e = { Format-DcSize $_.Length } }, 'Verdict', 'Path', 'Hint'
    ) | Out-String -Width 300
}
if ($manifest.Warnings.Count) { ''; '== Warnings =='; $manifest.Warnings | Select-Object -First 20 }
''
"MANIFEST: $manifestPath"
