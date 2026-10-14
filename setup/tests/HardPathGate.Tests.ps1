#requires -Version 7
# Spec 4.6 / D10: Test-NoHardPaths.ps1 flags machine paths in shared files and honours only the documented exemptions
# (history and example-path line markers, the example-paths block marker, the allowlist, the config convention).
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$gate = Join-Path $PSScriptRoot '..\Test-NoHardPaths.ps1'

function Invoke-Gate([string]$Root) {
    $csv = Join-Path $Root '..\gate.csv'
    & pwsh -NoProfile -File $gate -Root $Root -CsvOut $csv | Out-Null
    $code = $LASTEXITCODE
    $hits = if (Test-Path $csv) { @(Import-Csv $csv) } else { @() }
    [pscustomobject]@{ Code = $code; Hits = $hits }
}
$script:Roots = [System.Collections.Generic.List[string]]::new()
function New-Corpus([hashtable]$Files) {
    $outer = New-TestRoot 'gate'; $script:Roots.Add($outer)
    $root = Join-Path $outer 'corpus'
    foreach ($k in $Files.Keys) {
        $p = Join-Path $root $k
        New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
        [IO.File]::WriteAllText($p, ($Files[$k] -join "`n"))
    }
    $root
}

Test-Case 'a drive path in prose is flagged' {
    $r = Invoke-Gate (New-Corpus @{ 'a.md' = @('see C:\devops\repos\x for it') })
    Assert-Equal 1 $r.Code; Assert-Equal 1 $r.Hits.Count
}
Test-Case 'history and example-path line markers exempt only their line' {
    $r = Invoke-Gate (New-Corpus @{ 'a.md' = @('on 9/26 C:\tmp held it <!-- history -->', 'default `C:\Deploy\App` <!-- example-path -->', 'but D:\tmp\x is not marked'); 'b.ps1' = @('# example-path: C:\a\b -> //c/a/b') })
    Assert-Equal 1 $r.Hits.Count; Assert-Equal 'D:\tmp\x' $r.Hits[0].Path
}
Test-Case 'the example-paths marker exempts the fenced block right after it, and only that block' {
    $r = Invoke-Gate (New-Corpus @{ 'a.md' = @('<!-- example-paths -->', '```', 'C:\Deploy\App\app.exe', '```', '```', 'C:\other\x', '```') })
    Assert-Equal 1 $r.Hits.Count; Assert-Equal 'C:\other\x' $r.Hits[0].Path
}
Test-Case 'the example-paths marker does nothing when a line separates it from the fence' {
    $r = Invoke-Gate (New-Corpus @{ 'a.md' = @('<!-- example-paths -->', '', '```', 'C:\Deploy\App\app.exe', '```') })
    Assert-Equal 1 $r.Hits.Count
}
Test-Case 'a key-relative JSON path and a regex fragment are not paths; a UNC share is' {
    $r = Invoke-Gate (New-Corpus @{ 'a.md' = @('"req": ["{SpeedyRepo}\\docs\\requirements\\"]', '-match ''\d{4}-\d\dT\d\d:\d\d:\d\dZ''', 'copy to \\server\share\drop') })
    Assert-Equal 1 $r.Hits.Count; Assert-Match $r.Hits[0].Path '^\\\\server\\share'
}
Test-Case 'the allowlist exempts a matching file and the config convention string is allowed' {
    $r = Invoke-Gate (New-Corpus @{
            'setup\hardpaths-allowlist.txt' = @('vendor\*   # vendored data')
            'vendor\data.csv'               = @('C:/images/logo.png')
            'a.md'                          = @('The profile is C:\Deploy\Setup\ProfileMachineConfig.md on every machine.')
        })
    Assert-Equal 0 $r.Code ($r.Hits | ForEach-Object { "$($_.File):$($_.Line) $($_.Path)" } | Out-String)
}
Test-Case 'Git Bash drive paths are flagged' {
    $r = Invoke-Gate (New-Corpus @{ 'a.sh' = @('cd /c/devops/repos/x') })
    Assert-Equal 1 $r.Hits.Count
}
foreach ($r in $script:Roots) { Remove-Item -LiteralPath $r -Recurse -Force -ErrorAction SilentlyContinue }
Complete-Tests
