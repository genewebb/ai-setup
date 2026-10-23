#requires -Version 7
# Profile split (design: vault 99_Frequent\Profile\Share Design.md, section 4): the core profile plus profile.d\<category>.ps1
# define exactly what the one-file profile defined, category files hold only definitions and never call across files, and a
# fresh pwsh loads the result. -WriteBaseline regenerates the census fixture from the CURRENT files (done once, before the split).
param([switch]$WriteBaseline)
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
. (Join-Path $PSScriptRoot 'ProfileAst.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$pwshDir = Join-Path $repoRoot 'pwsh\PowerShell'
$core = Join-Path $pwshDir 'Microsoft.PowerShell_profile.ps1'
$baseline = Join-Path $PSScriptRoot 'fixtures\profile-names.baseline.txt'
$astHelper = Join-Path $PSScriptRoot 'ProfileAst.ps1'

function Get-ProfileFiles { @($core) + @(Get-ChildItem -LiteralPath (Join-Path $pwshDir 'profile.d') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object FullName) }
function Get-CategoryFiles { @(Get-ChildItem -LiteralPath (Join-Path $pwshDir 'profile.d') -Filter '*.ps1' -ErrorAction SilentlyContinue | Sort-Object Name) }
function Get-CensusNames {
    $defs = @(Get-ProfileFiles | ForEach-Object { Get-GeneProfileDefinitions -Path $_ })
    @($defs.Functions | ForEach-Object { "function $_" }) + @($defs.Aliases | ForEach-Object { "alias $_" }) + @($defs.Globals | ForEach-Object { "global $_" }) | Sort-Object -Unique
}

if ($WriteBaseline) {
    New-Item -ItemType Directory -Force -Path (Split-Path $baseline) | Out-Null
    Set-Content -LiteralPath $baseline -Value (Get-CensusNames) -Encoding utf8NoBOM
    Write-Host "baseline written: $baseline ($((Get-Content $baseline).Count) names)"
    exit 0
}

Test-Case 'census: the split defines exactly the names the one-file profile defined' {
    Assert-Equal @(Get-Content -LiteralPath $baseline | Sort-Object -Unique) @(Get-CensusNames)
}

Test-Case 'structure: profile.d exists with the eight category files' {
    Assert-Equal @('board', 'build', 'claude', 'git', 'navigate', 'profile', 'tabs', 'tools') @(Get-CategoryFiles | ForEach-Object BaseName)
}

Test-Case 'structure: profile.d files hold only definitions' {
    foreach ($f in Get-CategoryFiles) { Assert-Equal @() @((Get-GeneProfileDefinitions -Path $f.FullName).OtherTopLevel) "in $($f.Name)" }
}

Test-Case 'structure: no profile.d file calls a function another profile.d file defines' {
    $owner = @{}
    foreach ($f in Get-CategoryFiles) { foreach ($n in (Get-GeneProfileDefinitions -Path $f.FullName).Functions) { $owner[$n] = $f.Name } }
    $bad = foreach ($f in Get-CategoryFiles) {
        foreach ($c in (Get-GeneProfileDefinitions -Path $f.FullName).Calls) { if ($owner.ContainsKey($c) -and $owner[$c] -ne $f.Name) { "$($f.Name) calls $c (defined in $($owner[$c]))" } }
    }
    Assert-Equal @() @($bad)
}

Test-Case 'structure: core dot-sources profile.d in name order' {
    Assert-True ((Get-Content -LiteralPath $core -Raw) -match 'Get-ChildItem[^\r\n]*profile\.d[^\r\n]*\.ps1[^\r\n]*Sort-Object[^\r\n]*Name') 'core has no profile.d loader line'
}

Test-Case 'load: a fresh pwsh loads the split profile and defines every baseline function and alias' {
    $out = @(pwsh -NoProfile -Command ". '$core'; (Get-Command -CommandType Function).Name | ForEach-Object { 'function ' + `$_ }; (Get-Alias).Name | ForEach-Object { 'alias ' + `$_ }")
    $nested = @(Get-ProfileFiles | ForEach-Object { (Get-GeneProfileDefinitions -Path $_).Nested } | ForEach-Object { "function $_" })
    $missing = @(Get-Content -LiteralPath $baseline | Where-Object { $_ -notlike 'global *' -and $_ -notin $nested } | Where-Object { $out -notcontains $_ })
    Assert-Equal @() $missing 'missing after a fresh load'
}

Test-Case 'load: script-scope state survives dot-sourcing (Get-GeneAiGitPaths)' {
    Assert-Equal '6' ([string](pwsh -NoProfile -Command ". '$core'; (Get-GeneAiGitPaths).Count" | Select-Object -Last 1))
}

Complete-Tests
