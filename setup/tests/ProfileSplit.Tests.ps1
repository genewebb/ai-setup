#requires -Version 7
# Profile split (design: vault 99_Frequent\Profile\Share Design.md, section 4): the core profile plus profile.d\<category>.ps1
# define every name the one-file profile defined (fixtures\profile-names.baseline.txt), category files hold only definitions
# and never call across files, and a fresh pwsh loads the result. New names are fine; a baseline name that disappears fails
# the census. When a command is retired on purpose, rerun with -WriteBaseline in the same commit (it rewrites the fixture
# from the current files).
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

Test-Case 'census: every name the one-file profile defined is still defined (new names are allowed)' {
    $now = @(Get-CensusNames)
    $lost = @(Get-Content -LiteralPath $baseline | Sort-Object -Unique | Where-Object { $_ -notin $now })
    Assert-Equal @() $lost 'baseline names no longer defined (retired on purpose? rerun with -WriteBaseline in the same commit)'
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

Test-Case 'load: sp and rp are the profile functions, not the built-in aliases (Set-ItemProperty, Remove-ItemProperty)' {
    $out = @(pwsh -NoProfile -Command ". '$core'; foreach (`$n in 'sp', 'rp') { `$n + '=' + (Get-Command `$n).CommandType }")
    Assert-True ($out -contains 'sp=Function') "sp resolves to: $($out -join ' | ')"
    Assert-True ($out -contains 'rp=Function') "rp resolves to: $($out -join ' | ')"
}

Test-Case 'load: script-scope state survives dot-sourcing ($script:ClaudeAccountDirs read by Get-ClaudeAccount)' {
    Assert-Equal '2' ([string](pwsh -NoProfile -Command ". '$core'; @(Get-ClaudeAccount).Count" | Select-Object -Last 1))
}

Test-Case 'retired 10/24: ccursor, pushrules, dpAI and Get-GeneAiGitPaths are gone (Cursor-era; D3/D13 left them nothing to do)' {
    $now = @(Get-CensusNames)
    foreach ($n in 'function ccursor', 'function pushrules', 'function dpAI', 'function Get-GeneAiGitPaths', 'function Load-DpAIToolsConfig') {
        Assert-True ($now -notcontains $n) "$n is still defined"
    }
}

Test-Case 'load: core + tabs alone defines addtab, and New-GeneTab / addtab resolve every command they call' {
    $tmp = New-TestRoot 'split'; Copy-Item -LiteralPath $core -Destination $tmp
    New-Item -ItemType Directory -Path (Join-Path $tmp 'profile.d') | Out-Null
    Copy-Item -LiteralPath (Join-Path $pwshDir 'profile.d\tabs.ps1') -Destination (Join-Path $tmp 'profile.d') -ErrorAction Stop
    $script = ". '$astHelper'; . '$tmp\Microsoft.PowerShell_profile.ps1'; " +
        "`$calls = @(Get-GeneProfileCalls -Ast (Get-Command New-GeneTab).ScriptBlock.Ast) + @(Get-GeneProfileCalls -Ast (Get-Command addtab).ScriptBlock.Ast); " +
        "'MISSING:' + ((`$calls | Sort-Object -Unique | Where-Object { -not (Get-Command `$_ -ErrorAction SilentlyContinue) }) -join ',')"
    $out = @(pwsh -NoProfile -Command $script)
    $line = [string]($out | Where-Object { $_ -like 'MISSING:*' } | Select-Object -Last 1)
    Assert-True ($line -ne '') "child pwsh gave no MISSING line: $($out -join ' | ')"
    Assert-Equal 'MISSING:' $line
}

Complete-Tests