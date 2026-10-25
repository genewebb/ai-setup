#requires -Version 7
# pwsh\Install-Profile.ps1, the coworker's installer that prof setup share copies into <repo>\ai\profile: copies the
# PowerShell\ tree by hash, installs missing PSGallery modules, asks for every blank machine setting and writes the
# machine config (an existing file only gains missing rows). Every case runs the real script in a child pwsh against a
# fixture ai\profile folder, a temp profile folder and a temp config path; answers arrive on stdin (Read-Host).
# Run: pwsh -NoProfile -File InstallProfile.Tests.ps1
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$installer = Join-Path $repoRoot 'pwsh\Install-Profile.ps1'

$root = New-TestRoot 'installprofile'
function Write-File([string]$Path, [string]$Text) { New-Item -ItemType Directory -Force -Path (Split-Path $Path) | Out-Null; Set-Content -LiteralPath $Path -Value $Text -Encoding utf8NoBOM }

# ---- the fixture share folder, as share writes it
$share = Join-Path $root 'ai\profile'
Write-File "$share\PowerShell\x.ps1" '# x'
Write-File "$share\PowerShell\Microsoft.PowerShell_profile.ps1" '# the shared core'
Write-File "$share\PowerShell\profile.d\navigate.ps1" 'function cdevops { }'
Write-File "$share\modules.txt" "# modules`nWindowsPowerShell posh-git"
Write-File "$share\prof-share.json" '{ "version": 1, "files": { "PowerShell/x.ps1": "h1", "PowerShell/profile.d/navigate.ps1": "h2" } }'
$templateLines = @(
    '# PowerShell profile machine config - <MACHINE>'
    ''
    'Read by the PowerShell 7 profile every time it loads. Only this file differs between machines.'
    ''
    '| Key | Value | Used by | Status |'
    '|---|---|---|---|'
    '| ReposRoot |  | cdevops | fill in |'
    '| MarkitdownVenv | %USERPROFILE%\.venvs\markitdown | markitdown | set by Test Owner |'
    ''
)
Write-File "$share\ProfileMachineConfig.md" ($templateLines -join "`n")
Copy-Item -LiteralPath $installer -Destination "$share\Install-Profile.ps1"

$n = 0
function New-Target {
    $script:n++
    [pscustomobject]@{ Pd = (Join-Path $root "pd$script:n"); Cfg = (Join-Path $root "cfg$script:n\ProfileMachineConfig.md") }
}
function Run($Target, [string[]]$More = @(), [string[]]$Answers = @()) {
    $o = $Answers | & pwsh -NoProfile -File "$share\Install-Profile.ps1" -ProfileDir $Target.Pd -ConfigPath $Target.Cfg -SkipModules @More *>&1
    [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($o -join "`n") }
}
function Cfg($Target) { (Get-Content -LiteralPath $Target.Cfg) -join "`n" }

try {
    $t1 = New-Target
    $r1 = Run $t1 @('-NonInteractive')
    Test-Case 'copies PowerShell\ into -ProfileDir and reports the count' {
        Assert-Equal 0 $r1.Code $r1.Out
        Assert-True (Test-Path -LiteralPath (Join-Path $t1.Pd 'x.ps1')) 'x.ps1 not copied'
        Assert-True (Test-Path -LiteralPath (Join-Path $t1.Pd 'profile.d\navigate.ps1')) 'profile.d\navigate.ps1 not copied'
        Assert-Match $r1.Out '3 file\(s\) updated'
    }
    $r1b = Run $t1 @('-NonInteractive')
    Test-Case 'second run: 0 updated, config kept' {
        Assert-Equal 0 $r1b.Code $r1b.Out
        Assert-Match $r1b.Out '0 file\(s\) updated'
        Assert-Match $r1b.Out 'kept 2 row\(s\), added 0'
    }

    $t2 = New-Target
    $r2 = Run $t2 @() @('D:\repos')
    $installer = [regex]::Escape("$env:USERDOMAIN\$env:USERNAME")
    Test-Case 'asks for every blank key, keeps a set one, writes the config with this machine name and the installer as the setter' {
        Assert-Equal 0 $r2.Code $r2.Out
        Assert-Match $r2.Out 'ReposRoot \(cdevops\)'
        $c = Cfg $t2
        Assert-Match $c "^# PowerShell profile machine config - $env:COMPUTERNAME"
        Assert-Match $c ('\| ReposRoot \| D:\\repos \| cdevops \| set by ' + $installer + ' \|')
        Assert-Match $c ('\| MarkitdownVenv \| %USERPROFILE%\\\.venvs\\markitdown \| markitdown \| set by ' + $installer + ' \|')
        Assert-NoMatch $c 'Test Owner|set by you'
        Assert-NoMatch $c '<MACHINE>'
    }

    $t3 = New-Target
    $r3 = Run $t3 @() @('Q:\nope\x')
    Test-Case 'a typed folder that does not exist warns and is kept' {
        Assert-Equal 0 $r3.Code $r3.Out
        Assert-Match $r3.Out 'WARNING.*Q:\\nope\\x.*does not exist'
        Assert-Match (Cfg $t3) ('\| ReposRoot \| Q:\\nope\\x \| cdevops \| set by ' + $installer + ' \|')
    }

    $t4 = New-Target
    Write-File $t4.Cfg (@('# mine', '', '| Key | Value | Used by | Status |', '|---|---|---|---|', '| ReposRoot |  | cdevops | fill in |', '| Foo | bar | x | y |', '') -join "`n")
    $r4 = Run $t4 @() @('never-used')
    Test-Case 'existing config: missing keys appended, present rows (blank or not) untouched, no duplicates' {
        Assert-Equal 0 $r4.Code $r4.Out
        Assert-Match $r4.Out 'kept 2 row\(s\), added 1'
        $c = Cfg $t4
        Assert-Match $c '^# mine'
        Assert-Match $c '\| ReposRoot \|\s*\| cdevops \| fill in \|'
        Assert-Match $c '\| Foo \| bar \| x \| y \|'
        Assert-Equal 1 ([regex]::Matches($c, 'MarkitdownVenv')).Count 'MarkitdownVenv row count'
        Assert-Match $c ('\| MarkitdownVenv \| [^|]+ \| markitdown \| set by ' + $installer + ' \|')
        Assert-NoMatch $c 'never-used|Test Owner'
    }

    $t5 = New-Target
    Write-File $t5.Cfg (@('| Key | Value | Used by | Status |', '|---|---|---|---|', '| Foo | bar | x | y |', '') -join "`n")
    $r5 = Run $t5 @('-Force', '-NonInteractive')
    Test-Case '-Force replaces the config after a backup' {
        Assert-Equal 0 $r5.Code $r5.Out
        Assert-Match $r5.Out 'old copy in'
        Assert-NoMatch (Cfg $t5) 'Foo'
        Assert-Match (Cfg $t5) '\| MarkitdownVenv \|'
    }

    $t6 = New-Target
    $r6 = Run $t6 @('-NonInteractive')
    Test-Case '-NonInteractive writes the template as is (blank stays blank, asks nothing)' {
        Assert-Equal 0 $r6.Code $r6.Out
        Assert-NoMatch $r6.Out 'ReposRoot \(cdevops\)'
        Assert-Match (Cfg $t6) '\| ReposRoot \|\s*\| cdevops \| fill in \|'
    }

    $t7 = New-Target
    $r7 = Run $t7 @('-WhatIf')
    Test-Case '-WhatIf says what it would do and writes nothing' {
        Assert-Equal 0 $r7.Code $r7.Out
        Assert-Match $r7.Out 'would'
        Assert-True (-not (Test-Path -LiteralPath $t7.Pd)) 'profile folder was created'
        Assert-True (-not (Test-Path -LiteralPath $t7.Cfg)) 'config was written'
    }

    # An earlier install leaves prof-share-installed.json in the profile folder: the files it put there, with hashes.
    function Write-Record($Target, [hashtable]$Files) {
        Write-File "$($Target.Pd)\prof-share-installed.json" (@{ version = 1; files = $Files } | ConvertTo-Json)
    }

    $t8 = New-Target
    Write-File "$($t8.Pd)\profile.d\build.ps1" 'function dpspeed { }'
    Write-File "$($t8.Pd)\profile.d\mytools.ps1" 'function mine { }'
    Write-File "$($t8.Pd)\Modules\Gene.Profile\GitGroup.ps1" '# old group'
    Write-File "$($t8.Pd)\mine.ps1" '# the coworker''s own file'
    Write-Record $t8 @{ 'profile.d\build.ps1' = 'h' }
    $r8 = Run $t8 @('-NonInteractive')
    Test-Case 'stale shared files (recorded by an earlier install, or a Gene.* module file) are removed to the backup folder; the coworker''s own files stay, in profile.d too' {
        Assert-Equal 0 $r8.Code $r8.Out
        Assert-True (-not (Test-Path -LiteralPath "$($t8.Pd)\profile.d\build.ps1")) 'build.ps1 still installed'
        Assert-True (-not (Test-Path -LiteralPath "$($t8.Pd)\Modules\Gene.Profile\GitGroup.ps1")) 'GitGroup.ps1 still installed'
        Assert-True (Test-Path -LiteralPath "$($t8.Pd)\profile.d\mytools.ps1") 'the coworker''s own profile.d file was removed'
        Assert-True (Test-Path -LiteralPath "$($t8.Pd)\mine.ps1") 'the coworker''s own file was removed'
        Assert-Match $r8.Out 'removed 2 file\(s\) the share no longer has'
    }
    Test-Case 'the install records what it put in the profile folder, with hashes' {
        $rec = Get-Content -LiteralPath "$($t8.Pd)\prof-share-installed.json" -Raw | ConvertFrom-Json -AsHashtable
        Assert-Equal @('Microsoft.PowerShell_profile.ps1', 'profile.d\navigate.ps1', 'x.ps1') @($rec.files.Keys | Sort-Object)
        Assert-Equal (Get-FileHash -LiteralPath "$($t8.Pd)\x.ps1").Hash $rec.files['x.ps1']
    }
    $t9 = New-Target
    Write-File "$($t9.Pd)\profile.d\build.ps1" 'function dpspeed { }'
    Write-Record $t9 @{ 'profile.d\build.ps1' = 'h' }
    $r9 = Run $t9 @('-WhatIf')
    Test-Case '-WhatIf lists a stale file and keeps it, and writes no record' {
        Assert-Match $r9.Out 'would remove .*profile\.d\\build\.ps1'
        Assert-True (Test-Path -LiteralPath "$($t9.Pd)\profile.d\build.ps1") 'removed under -WhatIf'
        Assert-Equal 'h' ((Get-Content -LiteralPath "$($t9.Pd)\prof-share-installed.json" -Raw | ConvertFrom-Json -AsHashtable).files['profile.d\build.ps1'])
    }

    # ---- the coworker's own $PROFILE: asked, M = move to profile.d (default), R = replace, A = abort
    $own = '# Darias''s own profile'
    $t10 = New-Target
    Write-File "$($t10.Pd)\Microsoft.PowerShell_profile.ps1" $own
    $r10 = Run $t10 @() @('M', 'D:\repos')
    Test-Case 'own profile, M: moved to profile.d\zz-mine.ps1 (still loads), the shared core installed, a backup kept' {
        Assert-Equal 0 $r10.Code $r10.Out
        Assert-Match $r10.Out 'did not put there'
        Assert-Equal $own (Get-Content -LiteralPath "$($t10.Pd)\profile.d\zz-mine.ps1" -Raw).Trim()
        Assert-Equal '# the shared core' (Get-Content -LiteralPath "$($t10.Pd)\Microsoft.PowerShell_profile.ps1" -Raw).Trim()
        Assert-Match $r10.Out 'moved .*zz-mine\.ps1'
        Assert-NoMatch (Get-Content -LiteralPath "$($t10.Pd)\prof-share-installed.json" -Raw) 'zz-mine'
    }
    $r10b = Run $t10 @('-NonInteractive')
    Test-Case 'own profile moved: the next install neither asks again nor sweeps zz-mine.ps1' {
        Assert-Equal 0 $r10b.Code $r10b.Out
        Assert-NoMatch $r10b.Out 'did not put there'
        Assert-True (Test-Path -LiteralPath "$($t10.Pd)\profile.d\zz-mine.ps1") 'zz-mine.ps1 swept'
    }
    $t11 = New-Target
    Write-File "$($t11.Pd)\Microsoft.PowerShell_profile.ps1" $own
    $r11 = Run $t11 @() @('A')
    Test-Case 'own profile, A: aborts with exit 1 and writes nothing' {
        Assert-Equal 1 $r11.Code $r11.Out
        Assert-Equal $own (Get-Content -LiteralPath "$($t11.Pd)\Microsoft.PowerShell_profile.ps1" -Raw).Trim()
        Assert-True (-not (Test-Path -LiteralPath "$($t11.Pd)\x.ps1")) 'files copied after abort'
        Assert-True (-not (Test-Path -LiteralPath $t11.Cfg)) 'config written after abort'
    }
    $t12 = New-Target
    Write-File "$($t12.Pd)\Microsoft.PowerShell_profile.ps1" $own
    $r12 = Run $t12 @() @('R', 'D:\repos')
    Test-Case 'own profile, R: replaced, the old one only in the backup folder' {
        Assert-Equal 0 $r12.Code $r12.Out
        Assert-Equal '# the shared core' (Get-Content -LiteralPath "$($t12.Pd)\Microsoft.PowerShell_profile.ps1" -Raw).Trim()
        Assert-True (-not (Test-Path -LiteralPath "$($t12.Pd)\profile.d\zz-mine.ps1")) 'moved although R'
        $bak = [regex]::Match($r12.Out, 'backups of replaced files\s*:\s*(\S+)').Groups[1].Value
        Assert-Equal $own (Get-Content -LiteralPath "$bak\PowerShell\Microsoft.PowerShell_profile.ps1" -Raw).Trim()
    }
    $t13 = New-Target
    Write-File "$($t13.Pd)\Microsoft.PowerShell_profile.ps1" $own
    Write-File "$($t13.Pd)\profile.d\zz-mine.ps1" '# moved before'
    $r13 = Run $t13 @('-NonInteractive')
    Test-Case 'own profile, -NonInteractive: moved without asking; an existing zz-mine.ps1 is not overwritten' {
        Assert-Equal 0 $r13.Code $r13.Out
        Assert-Equal '# moved before' (Get-Content -LiteralPath "$($t13.Pd)\profile.d\zz-mine.ps1" -Raw).Trim()
        $moved = @(Get-ChildItem -LiteralPath "$($t13.Pd)\profile.d" -Filter 'zz-mine-*.ps1')
        Assert-Equal 1 $moved.Count 'zz-mine-<stamp>.ps1'
        Assert-Equal $own (Get-Content -LiteralPath $moved[0].FullName -Raw).Trim()
    }
    $t14 = New-Target
    Write-File "$($t14.Pd)\Microsoft.PowerShell_profile.ps1" $own
    $r14 = Run $t14 @('-WhatIf')
    Test-Case 'own profile, -WhatIf: says it would ask, moves nothing' {
        Assert-Equal 0 $r14.Code $r14.Out
        Assert-Match $r14.Out 'would ask what to do with .*Microsoft\.PowerShell_profile\.ps1'
        Assert-Equal $own (Get-Content -LiteralPath "$($t14.Pd)\Microsoft.PowerShell_profile.ps1" -Raw).Trim()
    }
    $t15 = New-Target
    Write-File "$($t15.Pd)\Microsoft.PowerShell_profile.ps1" '# an older shared core'
    Write-Record $t15 @{ 'Microsoft.PowerShell_profile.ps1' = (Get-FileHash -LiteralPath "$($t15.Pd)\Microsoft.PowerShell_profile.ps1").Hash }
    $r15 = Run $t15 @('-NonInteractive')
    Test-Case 'a profile an earlier install put there (recorded hash matches) is replaced without asking' {
        Assert-Equal 0 $r15.Code $r15.Out
        Assert-NoMatch $r15.Out 'did not put there'
        Assert-Equal '# the shared core' (Get-Content -LiteralPath "$($t15.Pd)\Microsoft.PowerShell_profile.ps1" -Raw).Trim()
        Assert-True (-not (Test-Path -LiteralPath "$($t15.Pd)\profile.d\zz-mine.ps1")) 'moved although ours'
    }
    Test-Case 'never mentions WindowsPowerShell' {
        Assert-NoMatch ($r1.Out + $r2.Out + $r6.Out) 'WindowsPowerShell'
        Assert-NoMatch (Get-Content -LiteralPath $installer -Raw) 'SkipWindowsPowerShell'
    }
}
finally { Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue }
Complete-Tests
