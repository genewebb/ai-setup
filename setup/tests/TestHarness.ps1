#requires -Version 7
# Minimal assertion harness shared by the setup tests (no Pester dependency: the machines carry Pester 3.4).
# Dot-source it, call Test-Case for each case, then Complete-Tests (exits 1 on any failure).

$script:TestResults = [System.Collections.Generic.List[object]]::new()

function Test-Case {
    param([Parameter(Mandatory)][string]$Name, [Parameter(Mandatory)][scriptblock]$Body)
    try {
        & $Body
        $script:TestResults.Add([pscustomobject]@{ Name = $Name; Pass = $true; Error = '' })
        Write-Host "  PASS  $Name" -ForegroundColor Green
    }
    catch {
        $script:TestResults.Add([pscustomobject]@{ Name = $Name; Pass = $false; Error = "$_" })
        Write-Host "  FAIL  $Name`n        $_" -ForegroundColor Red
    }
}

function Assert-True { param($Condition, [string]$Message = 'expected true') if (-not $Condition) { throw $Message } }
function Assert-Equal {
    param($Expected, $Actual, [string]$Message = '')
    if ($Expected -is [array] -or $Actual -is [array]) {
        $e = @($Expected) -join '|'; $a = @($Actual) -join '|'
        if ($e -cne $a) { throw "expected [$e] got [$a] $Message" }
        return
    }
    if ($Expected -cne $Actual) { throw "expected [$Expected] got [$Actual] $Message" }
}
function Assert-Throws {
    param([scriptblock]$Body, [string]$Like = '*')
    try { & $Body } catch { if ("$_" -notlike $Like) { throw "threw [$_], expected like [$Like]" }; return }
    throw "expected a throw like [$Like]"
}
function Assert-Match { param([string]$Text, [string]$Pattern) if ($Text -notmatch $Pattern) { throw "[$Text] does not match /$Pattern/" } }
function Assert-NoMatch { param([string]$Text, [string]$Pattern) if ($Text -match $Pattern) { throw "text matches /$Pattern/ but must not: $($Matches[0])" } }

function New-TestRoot {
    param([string]$Name = 'aitest')
    $root = Join-Path ([IO.Path]::GetTempPath()) ("$Name-" + [guid]::NewGuid().ToString('N').Substring(0, 8))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    return $root
}

function New-TestProfile {
    <# Writes a fake ProfileMachineConfig.md. $Keys = ordered key=>value; $Sections = name => markdown table text. #>
    param([string]$Path, [System.Collections.IDictionary]$Keys, [System.Collections.IDictionary]$Sections = @{})
    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine('# Test machine config')
    [void]$sb.AppendLine('')
    [void]$sb.AppendLine('| Key | Value | Used by | Status |')
    [void]$sb.AppendLine('|---|---|---|---|')
    foreach ($k in $Keys.Keys) { [void]$sb.AppendLine("| $k | $($Keys[$k]) | test | |") }
    foreach ($s in $Sections.Keys) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine("## $s")
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine($Sections[$s].Trim())
    }
    Set-Content -LiteralPath $Path -Value $sb.ToString() -Encoding utf8NoBOM
}

function Complete-Tests {
    $fail = @($script:TestResults | Where-Object { -not $_.Pass })
    Write-Host ("{0} passed, {1} failed" -f ($script:TestResults.Count - $fail.Count), $fail.Count)
    if ($fail.Count) { exit 1 }
    exit 0
}
