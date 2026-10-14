$ErrorActionPreference = 'Continue'
$root = Join-Path $env:USERPROFILE '.claude\skills'
$rows = @()

foreach ($d in (Get-ChildItem $root -Directory -ErrorAction SilentlyContinue)) {
    $p = Join-Path $d.FullName 'SKILL.md'
    if (-not (Test-Path $p)) { continue }
    $c = Get-Content $p -Raw
    if (-not $c) { continue }

    $fm = ''
    if ($c -match '(?s)^---\r?\n(.*?)\r?\n---') { $fm = $Matches[1] }

    # description: may be a single line or a folded/continued block until the next top-level key
    $desc = ''
    if ($fm -match '(?sm)^description:\s*(.*?)(?=\r?\n[A-Za-z0-9_-]+:\s|\z)') { $desc = $Matches[1].Trim() }

    $rows += [pscustomobject]@{
        Name       = $d.Name
        DescChars  = $desc.Length
        DescTokens = [math]::Round($desc.Length / 4)
        FmTokens   = [math]::Round($fm.Length / 4)
        BodyTokens = [math]::Round($c.Length / 4)
        Lines      = ($c -split "`n").Count
    }
}

$fat = $rows | Where-Object DescTokens -gt 120 | Sort-Object DescTokens -Descending

Write-Output ("skills={0}  desc_total=~{1:N0} tok   fm_total=~{2:N0} tok" -f `
    $rows.Count,
    ($rows | Measure-Object DescTokens -Sum).Sum,
    ($rows | Measure-Object FmTokens -Sum).Sum)
Write-Output ("fat_count={0}  fat_total=~{1:N0} tok  excess_over_90=~{2:N0} tok" -f `
    $fat.Count,
    ($fat | Measure-Object DescTokens -Sum).Sum,
    (($fat | Measure-Object DescTokens -Sum).Sum - ($fat.Count * 90)))

Write-Output ''
Write-Output '--- descriptions over 120 tokens ---'
foreach ($s in $fat) { Write-Output ("{0,-52} {1,5} tok  {2,6} chars" -f $s.Name, $s.DescTokens, $s.DescChars) }

$fat | ConvertTo-Json -Depth 3 | Set-Content (Join-Path $PSScriptRoot 'fat-descriptions.json')
Write-Output ''
Write-Output ("wrote {0}" -f (Join-Path $PSScriptRoot 'fat-descriptions.json'))
