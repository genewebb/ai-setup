<#
Split-Skill.ps1 — move line ranges out of a SKILL.md into references/*.md,
leaving a stub pointer in place. Ranges are 1-based inclusive and are applied
bottom-up so earlier line numbers stay valid.

$Extractions entries:
  Start   first line of the section (the header line)
  End     last line of the section
  File    references/<File>  (no path, no .md)
  Title   H1 for the reference file
  Stub    markdown inserted in place of the removed range
#>
param(
    [Parameter(Mandatory)][string]$Skill,
    [Parameter(Mandatory)][array]$Extractions,
    [switch]$WhatIf
)

# The skills corpus is {AIWorkRoot}\skills; writes go through Write-AIFile (the vault route).
foreach ($m in 'MachineConfig', 'AIFile') { Import-Module (Join-Path $PSScriptRoot "..\lib\$m.psm1") -Force }
$root  = Join-Path (Get-AIPath AIWorkRoot) 'skills'
$skDir = Join-Path $root $Skill
$sk    = Join-Path $skDir 'SKILL.md'
if (-not (Test-Path $sk)) { throw "no SKILL.md at $sk" }

$refDir = Join-Path $skDir 'references'   # Write-AIFile creates it (a vault PUT makes parents; a direct write too)

$nl    = "`r`n"
$lines = [System.IO.File]::ReadAllLines($sk)
$orig  = $lines.Count

# ---- validation pass -------------------------------------------------------
$sorted = @($Extractions | Sort-Object Start)
for ($i = 0; $i -lt $sorted.Count; $i++) {
    $e = $sorted[$i]
    if ($e.Start -lt 1 -or $e.End -gt $orig -or $e.Start -gt $e.End) {
        throw "bad range $($e.Start)-$($e.End) for $($e.File)"
    }
    if ($i -gt 0 -and $e.Start -le $sorted[$i-1].End) {
        throw "overlapping ranges: $($sorted[$i-1].File) and $($e.File)"
    }
    $seg = $lines[($e.Start-1)..($e.End-1)]
    $fences = @($seg | Where-Object { $_ -match '^\s*```' }).Count
    if ($fences % 2 -ne 0) { throw "unbalanced code fence in $($e.File) ($($e.Start)-$($e.End))" }
    if ($lines[$e.Start-1] -notmatch '^#{1,4} ') { throw "range for $($e.File) does not start on a header: '$($lines[$e.Start-1])'" }
}

# ---- extract bottom-up -----------------------------------------------------
$out = [System.Collections.Generic.List[string]]::new()
$out.AddRange([string[]]$lines)

foreach ($e in ($Extractions | Sort-Object Start -Descending)) {
    $seg  = $out.GetRange($e.Start-1, $e.End - $e.Start + 1)
    $body = ($seg -join $nl).TrimEnd()

    $refPath = Join-Path $refDir "$($e.File).md"
    $header  = "# $($e.Title)$nl$nl" +
               "Reference for the ``$Skill`` skill. Loaded on demand — see ``SKILL.md`` for" +
               " the decision rules and gotchas that decide whether you need this file.$nl$nl---$nl"
    if (-not $WhatIf) { Write-AIFile -Path $refPath -Text ($header + $nl + $body + $nl) }

    $stub = @($e.Stub -split "\r?\n")
    $out.RemoveRange($e.Start-1, $e.End - $e.Start + 1)
    $out.InsertRange($e.Start-1, [string[]]$stub)

    "  extracted {0,5} lines -> references/{1}.md" -f $seg.Count, $e.File
}

if (-not $WhatIf) { Write-AIFile -Path $sk -Text (($out.ToArray() -join $nl) + $nl) }

$newText = ($out -join $nl)
$allFences = ([regex]::Matches($newText, '(?m)^\s*```')).Count
"  SKILL.md {0} -> {1} lines, ~{2:N0} -> ~{3:N0} tok, fences={4} ({5})" -f `
    $orig, $out.Count,
    [math]::Round((($lines -join $nl).Length)/4),
    [math]::Round($newText.Length/4),
    $allFences, $(if ($allFences % 2 -eq 0) { 'balanced' } else { 'UNBALANCED' })
