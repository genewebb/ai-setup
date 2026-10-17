#requires -Version 7
# Spec 5.1 resolver tests. Run: pwsh -NoProfile -File MachineConfig.Tests.ps1
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
Import-Module (Join-Path $PSScriptRoot '..\..\lib\MachineConfig.psm1') -Force

$root = New-TestRoot 'mc'
try {
    $scratch = Join-Path $root 'scratch'; $wt = Join-Path $root 'wt'; $repos = Join-Path $root 'repos'
    New-Item -ItemType Directory $scratch, $wt, $repos | Out-Null
    $cfg = Join-Path $root 'profile.md'
    $base = [ordered]@{
        ReposRoot     = $repos
        AIWorkRoot    = Join-Path $root 'corpus'
        ScratchRoot   = $scratch
        WorktreesRoot = $wt
        SecretsDir    = ''
        HomeThing     = '%USERPROFILE%\x'
    }
    New-TestProfile -Path $cfg -Keys $base -Sections ([ordered]@{
            'Claude access' = "| Path | Access | Note |`n|---|---|---|`n| {ReposRoot} | read, edit | |`n| {SecretsDir} | read | |"
            'Git policy'    = "| Repo | Commit | Push | Worktrees | Note |`n|---|---|---|---|---|`n| {ReposRoot}\a | yes | no | yes | |"
            'Unrelated'     = "| Foo | Bar |`n|---|---|`n| ScratchRoot | IGNORED |"
        })

    Test-Case 'profile value is returned' { Assert-Equal $scratch (Get-AIPath ScratchRoot -ConfigPath $cfg) }

    Test-Case 'profile wins over AI_* env var (R3)' {
        $env:AI_SCRATCHROOT = 'Z:\nope'
        try { Assert-Equal $scratch (Get-AIPath ScratchRoot -ConfigPath $cfg) } finally { Remove-Item Env:AI_SCRATCHROOT }
    }

    Test-Case 'only the first table supplies keys' { Assert-Equal $scratch (Get-AIPath ScratchRoot -ConfigPath $cfg) }

    Test-Case 'TestOverride applies only when passed' {
        Assert-Equal 'Y:\o' (Get-AIPath ScratchRoot -ConfigPath $cfg -TestOverride @{ ScratchRoot = 'Y:\o' })
    }

    Test-Case 'missing key throws naming key and file' {
        Assert-Throws { Get-AIPath NoSuchKey -ConfigPath $cfg } "*'NoSuchKey' is not set. Add a row to $cfg*"
    }

    Test-Case '-Optional with a blank value returns $null' { Assert-True ($null -eq (Get-AIPath SecretsDir -Optional -ConfigPath $cfg)) }

    Test-Case 'blank value without -Optional throws' { Assert-Throws { Get-AIPath SecretsDir -ConfigPath $cfg } '*blank*' }

    Test-Case '%VAR% expansion' { Assert-Equal "$env:USERPROFILE\x" (Get-AIPath HomeThing -ConfigPath $cfg) }

    Test-Case 'ClaudeHome is derived when absent' {
        Assert-Equal (Join-Path $HOME '.claude') (Get-AIPath ClaudeHome -ConfigPath $cfg)
        Assert-Equal 'derived' ((Get-AIConfig -ConfigPath $cfg | Where-Object Key -eq ClaudeHome).Source)
    }

    Test-Case 'missing WorktreesRoot is a validation error, no fallback' {
        $c2 = Join-Path $root 'p2.md'; $k = [ordered]@{} + $base; $k.Remove('WorktreesRoot')
        New-TestProfile -Path $c2 -Keys $k
        Assert-Throws { Get-AIPath WorktreesRoot -ConfigPath $c2 } '*not set*'
        $v = Test-AIMachineProfile -Profile (Get-AIMachineProfile -Path $c2)
        Assert-True (@($v | Where-Object { $_.Level -eq 'error' -and $_.Message -like "*'WorktreesRoot' is missing*" }).Count -eq 1)
    }

    Test-Case 'ScratchRoot inside ReposRoot is refused unless AllowTempInRepo' {
        $c3 = Join-Path $root 'p3.md'; $k = [ordered]@{} + $base; $k['ScratchRoot'] = Join-Path $repos 'tmp'
        New-TestProfile -Path $c3 -Keys $k
        $v = Test-AIMachineProfile -Profile (Get-AIMachineProfile -Path $c3)
        Assert-True (@($v | Where-Object { $_.Level -eq 'error' -and $_.Message -like 'ScratchRoot*inside a repo*' }).Count -ge 1)
        $k['AllowTempInRepo'] = 'yes'; New-TestProfile -Path $c3 -Keys $k
        $v = Test-AIMachineProfile -Profile (Get-AIMachineProfile -Path $c3)
        Assert-True (@($v | Where-Object { $_.Level -eq 'error' }).Count -eq 0) ($v | Out-String)
    }

    Test-Case 'ScratchRoot and WorktreesRoot inside each other is refused' {
        $c4 = Join-Path $root 'p4.md'; $k = [ordered]@{} + $base; $k['WorktreesRoot'] = Join-Path $scratch 'wt'
        New-TestProfile -Path $c4 -Keys $k
        $v = Test-AIMachineProfile -Profile (Get-AIMachineProfile -Path $c4)
        Assert-True (@($v | Where-Object { $_.Message -like '*must not be inside each other*' }).Count -eq 1)
    }

    Test-Case 'Worktrees=yes with Commit=no fails validation (R18)' {
        $c5 = Join-Path $root 'p5.md'
        New-TestProfile -Path $c5 -Keys $base -Sections @{ 'Git policy' = "| Repo | Commit | Push | Worktrees | Note |`n|---|---|---|---|---|`n| {ReposRoot}\a | no | no | yes | |" }
        $v = Test-AIMachineProfile -Profile (Get-AIMachineProfile -Path $c5)
        Assert-True (@($v | Where-Object { $_.Message -like '*R18*' }).Count -eq 1)
    }

    Test-Case 'access rows: {Key} expansion, blank key skipped and reported' {
        $p = Get-AIMachineProfile -Path $cfg
        Assert-Equal $repos ($p.Access | Where-Object PathSpec -eq '{ReposRoot}').Path
        Assert-Equal 'read|edit' (($p.Access | Where-Object PathSpec -eq '{ReposRoot}').Access)
        Assert-True ($null -eq ($p.Access | Where-Object PathSpec -eq '{SecretsDir}').Path)
        $v = Test-AIMachineProfile -Profile $p
        Assert-True (@($v | Where-Object { $_.Level -eq 'info' -and $_.Message -like '*{SecretsDir}*skipped*' }).Count -eq 1)
    }

    Test-Case 'unparseable access value is an error' {
        $c6 = Join-Path $root 'p6.md'
        New-TestProfile -Path $c6 -Keys $base -Sections @{ 'Claude access' = "| Path | Access | Note |`n|---|---|---|`n| {ReposRoot} | write | |" }
        $v = Test-AIMachineProfile -Profile (Get-AIMachineProfile -Path $c6)
        Assert-True (@($v | Where-Object { $_.Level -eq 'error' -and $_.Message -like '*invalid Access*' }).Count -eq 1)
    }

    Test-Case 'delete is valid with edit and an error without it' {
        $c7 = Join-Path $root 'p7.md'
        New-TestProfile -Path $c7 -Keys $base -Sections @{ 'Claude access' = "| Path | Access | Note |`n|---|---|---|`n| {ReposRoot} | read, edit, delete | |`n| {ScratchRoot} | read, delete | |" }
        $v = @(Test-AIMachineProfile -Profile (Get-AIMachineProfile -Path $c7) | Where-Object Level -eq 'error')
        Assert-Equal 1 $v.Count ($v.Message -join ' | ')
        Assert-Match $v[0].Message 'ScratchRoot.*delete without edit'
    }

    Test-Case 'disconnected UNC is reported, not crashed on' {
        Assert-Equal 'share (disconnected)' (Get-AILocationKind -Path '\\ai-config-no-such-host-1\share\x')
    }

    Test-Case 'missing drive letter is reported as missing' {
        $free = [char[]](70..90) | Where-Object { -not (Get-PSDrive -Name $_ -ErrorAction SilentlyContinue) -and -not ((net use) -match "$($_):") } | Select-Object -Last 1
        Assert-Equal 'missing' (Get-AILocationKind -Path "$($free):\x")
    }

    Test-Case 'missing config file throws with the path' {
        Assert-Throws { Get-AIPath ScratchRoot -ConfigPath (Join-Path $root 'nope.md') } '*not found*nope.md*'
    }

    Test-Case 'git policy: repo without a row gets nothing; worktree maps to main repo' {
        $a = Join-Path $repos 'a'; $b = Join-Path $repos 'b'
        foreach ($r in $a, $b) { git init -q $r; git -C $r -c user.email=t@t -c user.name=t commit -q --allow-empty -m init }
        $wtp = Join-Path $wt 'a\w1'; git -C $a worktree add -q --detach $wtp 2>$null
        $p = Get-AIMachineProfile -Path $cfg
        $pa = Get-AIGitPolicy -Path $a -Profile $p
        Assert-True ($pa.Commit -and -not $pa.Push -and $pa.Worktrees)
        $pb = Get-AIGitPolicy -Path $b -Profile $p
        Assert-True (-not $pb.Commit -and -not $pb.Push -and -not $pb.Worktrees)
        $pw = Get-AIGitPolicy -Path $wtp -Profile $p
        Assert-True ($pw.Commit) "worktree should follow main repo, root=$($pw.RepoRoot)"
        $pn = Get-AIGitPolicy -Path $root -Profile $p
        Assert-True ($null -eq $pn.RepoRoot -and -not $pn.Commit)
    }

    # Clear-AIScratchLeftovers: the ai launcher and the stream watchdog keep {ScratchRoot} clean with it.
    $sw = Join-Path $root 'sweep'; New-Item -ItemType Directory $sw | Out-Null
    $old = (Get-Date).AddDays(-2)
    $made = @{}
    foreach ($n in 'ab12cd34.x9z', 'zz99yy88.q1w', 'settings.yml', 'Microsoft.NET.Workload_1_20261012_2_3.log', 'MSBuildTempab.cd', 'speedy-run-screens-1', 'cc_runas_test_0b46', 'claude', 'streams', 'temp', 'keep.txt', 'QQ12RR34.ZZZ') {
        $x = Join-Path $sw $n
        if ($n -match '\.(yml|log|txt)$') { Set-Content -LiteralPath $x 'x' } else { New-Item -ItemType Directory $x | Out-Null; Set-Content (Join-Path $x 'f.txt') 'x' }
        if ($n -ne 'zz99yy88.q1w') { $i = Get-Item -LiteralPath $x -Force; $i.LastWriteTime = $old; $i.CreationTime = $old }
        $made[$n] = $x
    }
    Test-Case 'scratch sweep: removes day-old leftover shapes, at most -Max per call, and says how many are left' {
        $r1 = @(Clear-AIScratchLeftovers -Root $sw -Max 3)
        Assert-Equal 3 $r1[0].Swept; Assert-Equal 2 $r1[0].Left
        $r2 = @(Clear-AIScratchLeftovers -Root $sw)
        Assert-Equal 2 $r2[0].Swept; Assert-Equal 0 $r2[0].Left
        foreach ($n in 'ab12cd34.x9z', 'Microsoft.NET.Workload_1_20261012_2_3.log', 'MSBuildTempab.cd', 'speedy-run-screens-1', 'cc_runas_test_0b46') { Assert-True (-not (Test-Path -LiteralPath $made[$n])) "$n should be swept" }
    }
    Test-Case 'scratch sweep: a fresh leftover, other names, a real-extension file and an upper-case name stay' {
        foreach ($n in 'zz99yy88.q1w', 'settings.yml', 'claude', 'streams', 'temp', 'keep.txt', 'QQ12RR34.ZZZ') { Assert-True (Test-Path -LiteralPath $made[$n]) "$n should stay" }
    }
    Test-Case 'scratch sweep: a missing root and the same root twice are harmless' {
        $r = @(Clear-AIScratchLeftovers -Root @((Join-Path $root 'nope'), $sw, $sw))
        Assert-Equal 1 $r.Count
    }
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
