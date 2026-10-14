#requires -Version 7
# R23: the pwsh profile's Read-GeneMachineConfig reads only the first table and accepts the AI keys silently.
# Extracts the profile's '#region Machine config' block and runs it against fake config files.
param([string]$ProfilePath = (Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'))
. (Join-Path $PSScriptRoot 'TestHarness.ps1')

$text = [IO.File]::ReadAllText($ProfilePath)
$m = [regex]::Match($text, '(?s)#region Machine config.*?#endregion')
if (-not $m.Success) { throw "No '#region Machine config' block in $ProfilePath" }
# Drop the trailing auto-call so the region only defines things.
$region = $m.Value -replace '(?m)^Read-GeneMachineConfig\s*$', ''
. ([scriptblock]::Create($region))

$root = New-TestRoot 'pp'
try {
    $cfg = Join-Path $root 'p.md'
    New-TestProfile -Path $cfg -Keys ([ordered]@{ ReposRoot = 'X:\repos'; AIWorkRoot = 'X:\corpus'; ScratchRoot = 'X:\tmp' }) -Sections ([ordered]@{
            'Claude access' = "| Path | Access | Note |`n|---|---|---|`n| {ReposRoot} | read, edit | |"
            'Git policy'    = "| Repo | Commit | Push | Worktrees | Note |`n|---|---|---|---|---|`n| SpeedyRepo | yes | yes | yes | |"
        })

    Test-Case 'AI keys and later tables cause no warnings' {
        $w = $null
        Read-GeneMachineConfig -Path $cfg -WarningVariable w -WarningAction SilentlyContinue
        Assert-Equal 0 @($w).Count ($w -join '; ')
    }
    Test-Case 'first-table profile key is read' { Assert-Equal 'X:\repos' $global:GeneMachine['ReposRoot'] }
    Test-Case 'a later table row named like a profile key is ignored' {
        Assert-Equal ([Environment]::ExpandEnvironmentVariables($global:GeneMachineDefaults['SpeedyRepo'])) $global:GeneMachine['SpeedyRepo']
    }
    Test-Case 'an unknown key in the first table still warns' {
        New-TestProfile -Path $cfg -Keys ([ordered]@{ Bogus = 'x' })
        $w = $null
        Read-GeneMachineConfig -Path $cfg -WarningVariable w -WarningAction SilentlyContinue
        Assert-Equal 1 @($w).Count
    }
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
Complete-Tests
