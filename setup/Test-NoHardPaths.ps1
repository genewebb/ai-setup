#requires -Version 7
<#
.SYNOPSIS
    Gate: no absolute machine path in any shared corpus file (spec 4.6, D10).

.DESCRIPTION
    Fails on a drive path (C:\x, c:/x), a UNC path (\\server\share) or a Git Bash drive path (/c/x) in a text file
    under -Root. Allowed:
      - the one config-location convention string (ConfigConvention below);
      - a line marked '<!-- history -->' (md/html) or '# history' (ps1/sh/yaml): it records what happened;
      - a line marked '<!-- example-path -->' or '# example-path': an illustrative path in a parser comment or test
        fixture, or a product's default install location (not this machine's layout);
      - a fenced code block whose fence directly follows a '<!-- example-paths -->' line (same meaning, whole block);
      - files and folders matched by setup\hardpaths-allowlist.txt (glob per line, '#' comments);
      - .bak* files, .git, the synced\ vendor skill folders.
    Prints file:line: path. Exit 0 = clean.
#>
param(
    [string]$Root = (Join-Path $PSScriptRoot '..'),
    [switch]$Summary,
    [string]$CsvOut
)
$ErrorActionPreference = 'Stop'
$Root = (Resolve-Path -LiteralPath $Root).ProviderPath.TrimEnd('\')
$ConfigConvention = 'C:\Deploy\Setup\ProfileMachineConfig.md'
$textExt = '.md', '.ps1', '.psm1', '.psd1', '.json', '.yaml', '.yml', '.js', '.mjs', '.cjs', '.ts', '.py', '.sh', '.cmd', '.bat', '.txt', '.html', '.htm', '.css', '.toml', '.xml', '.csv', '.cs'

$allowGlobs = @('*.bak*', '.git\*', '*\synced\*')
foreach ($f in @((Join-Path $Root 'setup\hardpaths-allowlist.txt'), (Join-Path $PSScriptRoot 'hardpaths-allowlist.txt')) | Select-Object -Unique) {
    if (Test-Path -LiteralPath $f) {
        $allowGlobs += Get-Content -LiteralPath $f | ForEach-Object { ($_ -split '#')[0].Trim() } | Where-Object { $_ }
    }
}

$drive = '(?<![A-Za-z0-9_$%\\])[A-Za-z]:(?:\\|/(?!/))[^\s"''`<>|*?,;)\]]*'
$unc = '(?<![\\A-Za-z0-9%}])\\\\(?:\\\\)?[A-Za-z0-9][A-Za-z0-9._-]+(?:\\\\?|/)[A-Za-z0-9$._-]{2,}[^\s"''`<>|*?,;)\]]*'
$bash = '(?<=^|[\s"''(=:])/(?:[a-zA-Z])/(?:Users|devops|tmp|Tmp|repos|Deploy|Work|Personal|PowershellScripts|Secrets|Documentation|devopslocal|inetpub|Program Files)\b[^\s"''`<>|*?,;)\]]*'
$rx = [regex]::new("$drive|$unc|$bash", 'Compiled')

$hits = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
    if ($textExt -notcontains $file.Extension.ToLowerInvariant()) { continue }
    $rel = $file.FullName.Substring($Root.Length + 1)
    if ($allowGlobs | Where-Object { $rel -like $_ }) { continue }
    $n = 0
    $blockArmed = $false; $inBlock = $false
    foreach ($line in [IO.File]::ReadLines($file.FullName)) {
        $n++
        # '<!-- example-paths -->' on the line before a code fence exempts that whole fenced block.
        if ($inBlock) { if ($line -match '^\s*(```|~~~)') { $inBlock = $false }; continue }
        if ($line -match '<!--\s*example-paths\s*-->') { $blockArmed = $true; continue }
        if ($blockArmed) { $blockArmed = $false; if ($line -match '^\s*(```|~~~)') { $inBlock = $true; continue } }
        if ($line -match '<!--\s*(history|example-path)\s*-->|#\s*(history|example-path)\b') { continue }
        foreach ($m in $rx.Matches($line)) {
            $v = $m.Value.TrimEnd('.', ':', "'", '"')
            if ($v -eq $ConfigConvention -or $line.Contains($ConfigConvention) -and $ConfigConvention.StartsWith($v)) { continue }
            if ($v.Length -lt 4) { continue }   # 'C:\' alone, or a regex fragment
            $hits.Add([pscustomobject]@{ File = $rel; Line = $n; Path = $v })
        }
    }
}
if ($CsvOut) { $hits | Export-Csv -LiteralPath $CsvOut -NoTypeInformation -Encoding utf8NoBOM }
if ($Summary) {
    "Hard-path gate: $($hits.Count) path(s) in $(@($hits | Select-Object -Expand File -Unique).Count) file(s) under $Root."
}
else {
    foreach ($h in $hits) { "$($h.File):$($h.Line): $($h.Path)" }
    "Hard-path gate: $($hits.Count) path(s)."
}
if ($hits.Count) { exit 1 }
exit 0
