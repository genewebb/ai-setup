#requires -Version 7
# setup\Clear-AIScratch.ps1 against a scratch profile whose ScratchRoot is a folder under the test root. Every case runs
# the real script in a child pwsh. Nothing on the machine is swept and no scheduled task is registered (-DryRun only).
# Run: pwsh -NoProfile -File ScratchClean.Tests.ps1
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$script = (Resolve-Path (Join-Path $PSScriptRoot '..\Clear-AIScratch.ps1')).Path

$root = New-TestRoot 'scratchclean'
$oldCfg = $env:AI_MACHINE_CONFIG
try {
    $scratch = Join-Path $root 'scratch'; $home1 = Join-Path $root 'home'; $outside = Join-Path $root 'outside'
    New-Item -ItemType Directory -Force $scratch, (Join-Path $scratch 'temp'), (Join-Path $home1 'bin'), $outside | Out-Null
    $cfg = Join-Path $root 'profile.md'
    New-TestProfile -Path $cfg -Keys ([ordered]@{ AIWorkRoot = $root; ClaudeHome = $home1; ReposRoot = $root; ScratchRoot = $scratch; WorktreesRoot = $root })
    $env:AI_MACHINE_CONFIG = $cfg
    function Run([string[]]$More) { $o = & pwsh -NoProfile -File $script @More *>&1; [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($o -join "`n") } }
    $old = (Get-Date).AddDays(-10); $fresh = Get-Date
    function Make([string]$Rel, [datetime]$When, [string]$Text = 'x') {
        $p = Join-Path $scratch $Rel
        New-Item -ItemType Directory -Force (Split-Path $p) | Out-Null
        Set-Content -LiteralPath $p -Value $Text
        [IO.File]::SetCreationTimeUtc($p, $When.ToUniversalTime()); [IO.File]::SetLastWriteTimeUtc($p, $When.ToUniversalTime())
        $p
    }
    function MakeDir([string]$Rel, [datetime]$When) {
        $p = Join-Path $scratch $Rel
        New-Item -ItemType Directory -Force $p | Out-Null
        [IO.Directory]::SetCreationTimeUtc($p, $When.ToUniversalTime()); [IO.Directory]::SetLastWriteTimeUtc($p, $When.ToUniversalTime())
        $p
    }

    # ---- the root guard ----
    $g1 = Run @('-Root', $outside)
    Test-Case 'a root that is not the profile''s ScratchRoot is refused and nothing under it is touched' {
        Assert-Equal 2 $g1.Code $g1.Out
        Assert-Match $g1.Out 'REFUSED -Root .* is not this machine''s ScratchRoot'
    }
    $g2 = Run @('-Root', (Join-Path $scratch 'temp'))
    Test-Case 'a subfolder of ScratchRoot is refused too: the task is registered on the root, nothing else' {
        Assert-Equal 2 $g2.Code $g2.Out
        Assert-Match $g2.Out 'REFUSED'
    }

    # ---- what goes and what stays ----
    $oldFile = Make 'claude\proj\sess\scratchpad\old.txt' $old
    $oldDeep = Make 'a\b\c\deep.log' $old
    $freshFile = Make 'claude\proj\sess\scratchpad\fresh.txt' $fresh
    $oldWriteFreshCreate = Make 'mixed.txt' $old; [IO.File]::SetCreationTimeUtc($oldWriteFreshCreate, (Get-Date).ToUniversalTime())
    $readOnly = Make 'ro\objects\ab.pack' $old; (Get-Item $readOnly).IsReadOnly = $true
    $held = Make 'held.txt' $old
    $leftover = Make 'ab12cd34.x9z\inner.bin' (Get-Date).AddHours(-30)   # a .NET random-name folder at the top: the one-day rule
    [IO.Directory]::SetCreationTimeUtc((Split-Path $leftover), (Get-Date).AddHours(-30).ToUniversalTime()); [IO.Directory]::SetLastWriteTimeUtc((Split-Path $leftover), (Get-Date).AddHours(-30).ToUniversalTime())
    $emptyOld = MakeDir 'emptyold' $old
    $emptyFresh = MakeDir 'emptyfresh' $fresh
    $tempFile = Make 'temp\tmpA1B2.tmp' $old
    # a junction into a folder OUTSIDE scratch holding an old file: never entered, never removed
    $target = Join-Path $outside 'kept'; New-Item -ItemType Directory -Force $target | Out-Null
    $viaLink = Join-Path $target 'old-through-link.txt'; Set-Content $viaLink 'keep'; [IO.File]::SetLastWriteTimeUtc($viaLink, $old.ToUniversalTime()); [IO.File]::SetCreationTimeUtc($viaLink, $old.ToUniversalTime())
    $link = Join-Path $scratch 'link'; New-Item -ItemType Junction -Path $link -Target $target | Out-Null

    $w = Run @('-Root', $scratch, '-WhatIf')
    Test-Case '-WhatIf reports what would go and removes nothing' {
        Assert-Equal 0 $w.Code $w.Out
        Assert-Match $w.Out 'WOULD-SWEEP files=\d+ dirs=\d+'
        foreach ($p in $oldFile, $oldDeep, $freshFile, $readOnly, $held, $leftover, $tempFile, $viaLink) { Assert-True (Test-Path -LiteralPath $p) "$p should still be there after -WhatIf" }
        Assert-True (Test-Path -LiteralPath $emptyOld) 'emptyold should still be there after -WhatIf'
    }

    $h = [IO.File]::Open($held, 'Open', 'Read', 'Read')
    try { $r = Run @('-Root', $scratch) } finally { $h.Dispose() }
    Test-Case 'files unused for KeepDays go, deep in the tree too, and read-only is no protection' {
        Assert-Equal 0 $r.Code $r.Out
        Assert-Match $r.Out '^.*SWEPT files=\d+ dirs=\d+ MB=[\d.,]+ left=0 in-use=1 root='
        foreach ($p in $oldFile, $oldDeep, $readOnly, $tempFile) { Assert-True (-not (Test-Path -LiteralPath $p)) "$p should be gone" }
    }
    Test-Case 'a fresh file, a file created recently, and a file someone holds open stay' {
        foreach ($p in $freshFile, $oldWriteFreshCreate, $held) { Assert-True (Test-Path -LiteralPath $p) "$p should stay" }
    }
    Test-Case 'a day-old tool leftover at the top goes under the one-day rule even though it is younger than KeepDays' {
        Assert-True (-not (Test-Path -LiteralPath (Split-Path $leftover))) 'ab12cd34.x9z should be gone'
    }
    Test-Case 'an old empty folder goes, a fresh empty one stays, and the root and \temp are always kept' {
        Assert-True (-not (Test-Path -LiteralPath $emptyOld)) 'emptyold should be gone'
        Assert-True (Test-Path -LiteralPath $emptyFresh) 'emptyfresh should stay'
        Assert-True (Test-Path -LiteralPath (Join-Path $scratch 'temp')) 'temp should be kept'
        Assert-True (Test-Path -LiteralPath $scratch) 'the root should be kept'
    }
    Test-Case 'a junction under the root is neither entered nor removed: the old file behind it stays' {
        Assert-True (Test-Path -LiteralPath $link) 'the junction should stay'
        Assert-True (Test-Path -LiteralPath $viaLink) 'the file behind the junction should stay'
    }
    Test-Case 'the run is logged under ai-config-work and the log is never swept' {
        $log = Join-Path $scratch 'ai-config-work\Clear-AIScratch.log'
        Assert-True (Test-Path -LiteralPath $log) 'log missing'
        Assert-Match ((Get-Content -LiteralPath $log) -join "`n") 'SWEPT files='
        [IO.File]::SetLastWriteTimeUtc($log, $old.ToUniversalTime()); [IO.File]::SetCreationTimeUtc($log, $old.ToUniversalTime())
        $r2 = Run @('-Root', $scratch)
        Assert-Equal 0 $r2.Code $r2.Out
        Assert-True (Test-Path -LiteralPath $log) 'the log was swept'
        Assert-Equal 2 @(Get-Content -LiteralPath $log).Count 'two runs, two lines'
    }
    Test-Case 'a missing \temp is re-created so processes whose TEMP points there keep working' {
        Remove-Item -LiteralPath (Join-Path $scratch 'temp') -Recurse -Force
        $r3 = Run @('-Root', $scratch)
        Assert-Equal 0 $r3.Code $r3.Out
        Assert-True (Test-Path -LiteralPath (Join-Path $scratch 'temp')) 'temp not re-created'
    }
    # -Max: the budget stops the run and reports what is left for the next hour
    1..5 | ForEach-Object { Make "many\f$_.txt" $old | Out-Null }
    $m = Run @('-Root', $scratch, '-Max', '2')
    Test-Case '-Max bounds one run and reports the rest as left for the next hour' {
        Assert-Equal 0 $m.Code $m.Out
        Assert-Match $m.Out 'SWEPT files=2 dirs=0 .* left=\d+'
        Assert-Equal 3 @(Get-ChildItem (Join-Path $scratch 'many') -File).Count 'three should be left'
    }

    # ---- register / unregister, dry ----
    $d0 = Run @('-Register', '-Root', $scratch, '-DryRun')
    Test-Case '-Register -DryRun with no installed copy still shows the task, noting the runtime step installs the script' {
        Assert-Equal 0 $d0.Code $d0.Out
        Assert-Match $d0.Out "DRY-RUN task 'AI scratch cleanup' .*the script is not installed yet"
    }
    $d1 = Run @('-Register', '-Root', $scratch)
    Test-Case 'a real -Register refuses while the installed copy is missing: the task would run nothing' {
        Assert-Equal 2 $d1.Code $d1.Out
        Assert-Match $d1.Out 'REFUSED .*is not installed yet'
        Assert-True (-not (Get-ScheduledTask -TaskName 'AI scratch cleanup' -ErrorAction SilentlyContinue)) 'a task was registered'
    }
    Copy-Item $script (Join-Path $home1 'bin\Clear-AIScratch.ps1')
    $d2 = Run @('-Register', '-Root', $scratch, '-KeepDays', '3', '-DryRun')
    Test-Case '-Register -DryRun prints the hourly task, the installed script as its file and the root and KeepDays as its arguments' {
        Assert-Equal 0 $d2.Code $d2.Out
        Assert-Match $d2.Out "DRY-RUN task 'AI scratch cleanup' hourly as \S+ on " + [regex]::Escape($scratch) + ' \(files unused 3 days\)'
        Assert-Match $d2.Out 'exe: .*pwsh'
        Assert-Match $d2.Out ('args: -NoProfile -NonInteractive -File "' + [regex]::Escape((Join-Path $home1 'bin\Clear-AIScratch.ps1')) + '" -Root "' + [regex]::Escape($scratch) + '" -KeepDays 3')
    }
    $d3 = Run @('-Register', '-Root', $outside, '-DryRun')
    Test-Case '-Register on a root that is not ScratchRoot is refused before anything is registered' {
        Assert-Equal 2 $d3.Code $d3.Out
        Assert-Match $d3.Out 'REFUSED -Root'
    }
    $u = Run @('-Unregister', '-DryRun')
    Test-Case '-Unregister -DryRun names the task and does nothing' { Assert-Equal 0 $u.Code $u.Out; Assert-Match $u.Out "DRY-RUN unregister 'AI scratch cleanup'" }
}
finally {
    $env:AI_MACHINE_CONFIG = $oldCfg
    $lnk = Join-Path $root 'scratch\link'; if (Test-Path -LiteralPath $lnk) { (Get-Item -LiteralPath $lnk).Delete() }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
