#requires -Version 7
# getStreams / pushStreams / updateStreams and the board host guard (pwsh profile, stream region), against throwaway
# git repos: a bare origin with clones A (this host) and B (the old host, reached as \\localhost\C$\... like another
# machine's admin share), and a fake AI setup clone whose install.ps1 / publish.ps1 only log their arguments.
# Run: pwsh -NoProfile -File StreamSync.Tests.ps1   (the temp root must be on C: for the \\localhost\C$ paths)
param([string]$ProfilePath = (Join-Path $PSScriptRoot '..\..\pwsh\PowerShell\Microsoft.PowerShell_profile.ps1'))
. (Join-Path $PSScriptRoot 'TestHarness.ps1')

# Load only the profile's machine-config and stream regions (the rest needs an interactive console).
$text = Get-Content -LiteralPath $ProfilePath -Raw
foreach ($region in '(?s)#region Machine config.*?#endregion', '(?s)#region Stream sessions.*?#endregion Stream sessions') {
    $m = [regex]::Match($text, $region)
    if (-not $m.Success) { throw "profile region not found: $region" }
    . ([scriptblock]::Create($m.Value))
}

function Invoke-Git { param([string]$Dir, [Parameter(ValueFromRemainingArguments)][string[]]$GitArgs) $o = & git -C $Dir @GitArgs 2>&1; if ($LASTEXITCODE) { throw "git $GitArgs : $o" }; $o }
function New-Clone { param([string]$Origin, [string]$Dir) & git clone -q $Origin $Dir 2>&1 | Out-Null; Invoke-Git $Dir config user.email t@t; Invoke-Git $Dir config user.name t }
function Set-Board {
    param([string]$Repo, [object[]]$Tasks = @(@{ id = 'G1.T001'; state = 'done' }))
    New-Item -ItemType Directory -Path (Join-Path $Repo '.streams') -Force | Out-Null
    @{ tasks = $Tasks } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $Repo '.streams\tasks.json')
    Add-Content -LiteralPath (Join-Path $Repo '.git\info\exclude') -Value '.streams/'
}
function ConvertTo-Unc { param([string]$Path) '\\localhost\' + ($Path -replace '^([A-Za-z]):', '$1$') }
# Runs a stream command and returns its error records (they are written, not thrown).
function Get-Errors { param([scriptblock]$Body) @(& $Body 2>&1 6>$null 3>$null | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] } | ForEach-Object { "$_" }) }

$root = New-TestRoot 'streamsync'
if ($root -notmatch '^C:') { Write-Host "SKIP: temp root $root is not on C:" ; exit 0 }
$log = Join-Path $root 'kit.log'
$env:STREAMSYNC_TEST_LOG = $log
try {
    $origin = Join-Path $root 'origin.git'; & git init -q --bare -b main $origin
    $seed = Join-Path $root 'seed'; New-Clone $origin $seed
    Set-Content (Join-Path $seed 'code.txt') 'v1'; Invoke-Git $seed add -A; Invoke-Git $seed commit -q -m v1; Invoke-Git $seed push -q origin HEAD:main
    $a = Join-Path $root 'a\smtest'; New-Clone $origin $a
    $b = Join-Path $root 'b\smtest'; New-Clone $origin $b
    Set-Board $a @(@{ id = 'OLD.T001'; state = 'done' })
    Set-Board $b @(@{ id = 'G1.T001'; state = 'built' }, @{ id = 'G1.T002'; state = 'planned' })
    Set-Content (Join-Path $b '.gitignore') '.env'; Invoke-Git $b add -A; Invoke-Git $b commit -q -m ignore; Invoke-Git $b push -q
    Invoke-Git $a pull -q --ff-only
    Set-Content (Join-Path $b '.env') 'CHANNEL=1'

    # Fake AI setup clone: the real machine-config module, logging install/publish stubs.
    $aiOrigin = Join-Path $root 'ai.git'; & git init -q --bare -b main $aiOrigin
    $ai = Join-Path $root 'ai'; New-Clone $aiOrigin $ai
    New-Item -ItemType Directory (Join-Path $ai 'lib') | Out-Null
    Copy-Item (Join-Path $PSScriptRoot '..\..\lib\MachineConfig.psm1') (Join-Path $ai 'lib')
    foreach ($s in 'install', 'publish') {
        # Prints a line like the real scripts do, so output leaking into a caller's return value shows up.
        Set-Content (Join-Path $ai "$s.ps1") "Add-Content -LiteralPath `$env:STREAMSYNC_TEST_LOG -Value ('$s ' + (`$args -join ' ')); '$s output'; exit [int]`$env:STREAMSYNC_TEST_EXIT"
    }
    Invoke-Git $ai add -A; Invoke-Git $ai commit -q -m stubs; Invoke-Git $ai push -q -u origin main

    $scratch = Join-Path $root 'scratch'; New-Item -ItemType Directory $scratch | Out-Null
    $cfg = Join-Path $root 'profile.md'
    $keys = [ordered]@{ ReposRoot = $root; SpeedyRepo = $a; AIWorkRoot = $ai; ScratchRoot = $scratch; WorktreesRoot = (Join-Path $root 'wt') }
    $policy = "| Repo | Commit | Push | Worktrees | Owner push | Note |`n|---|---|---|---|---|---|`n| $a | yes | no | yes | yes | |`n| $b | yes | yes | no | | |"
    New-TestProfile -Path $cfg -Keys $keys -Sections @{ 'Git policy' = $policy }
    $global:GeneMachineConfigPath = $cfg
    $env:AI_MACHINE_CONFIG = $cfg
    Read-GeneMachineConfig

    Test-Case 'repo defaults to SpeedyRepo from the machine config' {
        Assert-Equal $a (Resolve-GeneStreamRepoPath -Caller t)
        Push-Location $root; try { Assert-Equal $a (Enter-GeneStreamRepo -Caller t) } finally { Pop-Location }
        Assert-Equal $b (Resolve-GeneStreamRepoPath -Repo $b -Caller t)
    }

    Test-Case 'host guard: no marker passes; another host or MOVED refuses; -AnyHost overrides' {
        Assert-True (Test-GeneStreamHost -Repo $a -Caller t)
        Write-GeneStreamBoardFile -Repo $a -Kind host -Data ([ordered]@{ host = 'OTHERBOX' })
        $errs = Get-Errors { Test-GeneStreamHost -Repo $a -Caller t }
        Assert-Match ($errs -join ' ') "host is OTHERBOX"
        Assert-True (Test-GeneStreamHost -Repo $a -Caller t -AnyHost 3>$null)
        Write-GeneStreamBoardFile -Repo $a -Kind host -Data ([ordered]@{ host = $env:COMPUTERNAME })
        Assert-True (Test-GeneStreamHost -Repo $a -Caller t)
        Write-GeneStreamBoardFile -Repo $a -Kind moved -Data ([ordered]@{ to = 'NEWBOX'; at = 'now' })
        Assert-Match ((Get-Errors { Test-GeneStreamHost -Repo $a -Caller t }) -join ' ') 'moved to NEWBOX'
        Remove-Item (Get-GeneStreamBoardFile -Repo $a -Kind moved), (Get-GeneStreamBoardFile -Repo $a -Kind host)
    }

    Test-Case 'addStreams and addStreamTab refuse on a moved board' {
        Write-GeneStreamBoardFile -Repo $a -Kind moved -Data ([ordered]@{ to = 'NEWBOX'; at = 'now' })
        try {
            Assert-Match ((Get-Errors { addStreams -Repo $a -DryRun }) -join ' ') 'moved to NEWBOX'
            Assert-Match ((Get-Errors { addStreamTab -Author -Repo $a -DryRun }) -join ' ') 'moved to NEWBOX'
            Assert-Match ((Get-Errors { addStreamTab -Role Status -Repo $a -DryRun }) -join ' ') 'moved to NEWBOX'
        }
        finally { Remove-Item (Get-GeneStreamBoardFile -Repo $a -Kind moved) }
    }

    Test-Case 'remote machine path: drive path becomes the admin share' {
        $remoteCfg = Join-Path $root 'remote.md'
        New-TestProfile -Path $remoteCfg -Keys ([ordered]@{ SpeedyRepo = 'D:\devops\repos\speedmerchants'; AIWorkRoot = '%USERPROFILE%\x' })
        $global:GeneMachineConfigPath = $remoteCfg
        try {
            Assert-Equal '\\localhost\D$\devops\repos\speedmerchants' (Get-GeneRemoteMachinePath -ComputerName localhost -Key SpeedyRepo)
            Assert-Throws { Get-GeneRemoteMachinePath -ComputerName localhost -Key AIWorkRoot } '*not a plain drive path*'
            Assert-Throws { Get-GeneRemoteMachinePath -ComputerName localhost -Key NoSuch } '*no NoSuch row*'
        }
        finally { $global:GeneMachineConfigPath = $cfg }
    }

    Test-Case 'getStreams: code fast-forwards; kit runs install.ps1 -Yes' {
        Set-Content (Join-Path $seed 'code.txt') 'v2'; Invoke-Git $seed pull -q; Invoke-Git $seed commit -q -am v2; Invoke-Git $seed push -q origin HEAD:main
        Remove-Item $log -ErrorAction SilentlyContinue
        getStreams -Yes 6>$null
        Assert-Equal 'v2' (Get-Content (Join-Path $a 'code.txt'))
        Assert-Equal 'install -Yes' (Get-Content $log)
    }

    # Only without a console: with one, getStreams asks whether to publish first (Read-Host would wait here).
    if ([Console]::IsInputRedirected) { Test-Case 'getStreams: unpublished kit changes refuse without a console; install.ps1 not run' {
        Set-Content (Join-Path $ai 'memory.md') 'new'
        Remove-Item $log -ErrorAction SilentlyContinue
        try {
            Assert-Match ((Get-Errors { getStreams -NoCode }) -join ' ') 'unpublished changes'
            Assert-True (-not (Test-Path $log)) 'install.ps1 must not run'
        }
        finally { Remove-Item (Join-Path $ai 'memory.md') }
    } }

    Test-Case 'getStreams: a failing install.ps1 stops before the code step' {
        Set-Content (Join-Path $seed 'code.txt') 'v2b'; Invoke-Git $seed commit -q -am v2b; Invoke-Git $seed push -q origin HEAD:main
        $before = Invoke-Git $a rev-parse HEAD
        $env:STREAMSYNC_TEST_EXIT = '3'
        try { Assert-Match ((Get-Errors { getStreams -Yes }) -join ' ') 'install.ps1 exited 3' }
        finally { Remove-Item Env:STREAMSYNC_TEST_EXIT }
        Assert-Equal $before (Invoke-Git $a rev-parse HEAD) 'code must not be pulled after a failed install'
        Assert-True (Invoke-GeneStreamKitGet -Caller t -Yes 6>$null) 'success returns exactly $true'
        Assert-Equal 'True' "$(Invoke-GeneStreamKitGet -Caller t -Yes 6>$null)" 'no script output in the return value'
        Invoke-Git $a pull -q --ff-only
    }

    Test-Case 'getStreams: a diverged branch is refused, not merged' {
        Set-Content (Join-Path $a 'local.txt') 'x'; Invoke-Git $a add -A; Invoke-Git $a commit -q -m local
        Set-Content (Join-Path $seed 'code.txt') 'v3'; Invoke-Git $seed commit -q -am v3; Invoke-Git $seed push -q origin HEAD:main
        try {
            Assert-Match ((Get-Errors { getStreams -NoKit }) -join ' ') 'diverged'
        }
        finally { Invoke-Git $a reset -q --hard origin/main~1; Invoke-Git $a pull -q --ff-only }
    }

    Test-Case 'pushStreams: owner push from the Owner push column; no row = skipped' {
        Set-Content (Join-Path $a 'feature.txt') 'f'; Invoke-Git $a add -A; Invoke-Git $a commit -q -m feature
        $head = Invoke-Git $a rev-parse HEAD
        pushStreams -NoKit -Yes 6>$null
        Assert-Equal $head (Invoke-Git $origin rev-parse main)
        # A repo with no policy row is never pushed.
        $c = Join-Path $root 'c\smtest'; New-Clone $origin $c
        Set-Content (Join-Path $c 'c.txt') 'c'; Invoke-Git $c add -A; Invoke-Git $c commit -q -m c
        $out = pushStreams -Repo $c -NoKit -Yes 6>&1 | Out-String
        Assert-Match $out 'no owner push'
        Assert-Equal $head (Invoke-Git $origin rev-parse main)
        Invoke-Git $b pull -q --ff-only
    }

    Test-Case 'pushStreams: kit publish.ps1 runs only when there is something to publish' {
        Remove-Item $log -ErrorAction SilentlyContinue
        pushStreams -NoCode -Yes -Message 'm1' 6>$null
        Assert-True (-not (Test-Path $log)) 'clean clone: publish.ps1 not run'
        Set-Content (Join-Path $ai 'memory.md') 'new'
        try { pushStreams -NoCode -Yes -Message 'm1' 6>$null; Assert-Equal 'publish -Message m1 -Yes' (Get-Content $log) }
        finally { Remove-Item (Join-Path $ai 'memory.md') }
    }

    Test-Case 'board noise: claims and building count, parked and built tasks travel' {
        $tasks = @(
            @{ id = 'T1'; state = 'built' }
            @{ id = 'T2'; state = 'building'; claim = @{ session = 'build-1' } }
            @{ id = 'T3'; state = 'building'; dependsOn = @('T4') }
            @{ id = 'T4'; state = 'planned' }
        )
        $n = Join-Path $root 'n'; New-Item -ItemType Directory $n | Out-Null; & git init -q $n
        Set-Board $n $tasks
        $noise = Get-GeneStreamBoardNoise -Repo $n
        Assert-Equal 'T2' $noise.Claims; Assert-Equal 'T2' $noise.Flight
        Assert-True (-not $noise.Lock -and -not $noise.Dirty.Count)
    }

    Test-Case 'pushStreams -Handoff: quiet board pushed, handoff.json written' {
        Set-Content (Join-Path $b 'fromb.txt') 'b'; Invoke-Git $b add -A; Invoke-Git $b commit -q -m fromb
        pushStreams -Handoff -Repo $b -Yes 6>$null
        $h = Read-GeneStreamBoardFile -Repo $b -Kind handoff
        Assert-Equal $env:COMPUTERNAME $h.from
        Assert-Equal (Invoke-Git $b rev-parse HEAD) $h.head
        Assert-Equal (Invoke-Git $b rev-parse HEAD) (Invoke-Git $origin rev-parse main)
    }

    $bUnc = ConvertTo-Unc $b
    Test-Case 'takeover refuses: dirty old repo, claims, a different tree' {
        Set-Content (Join-Path $b 'dirty.txt') 'd'
        try { Assert-Match ((Get-Errors { getStreams -FromHost localhost -FromRepo $bUnc -Yes }) -join ' ') 'uncommitted' }
        finally { Remove-Item (Join-Path $b 'dirty.txt') }
        $doc = Get-Content (Join-Path $b '.streams\tasks.json') -Raw
        Set-Board $b @(@{ id = 'G1.T001'; state = 'building'; claim = @{ session = 'x' } })
        try { Assert-Match ((Get-Errors { getStreams -FromHost localhost -FromRepo $bUnc -Yes }) -join ' ') 'not quiet' }
        finally { Set-Content (Join-Path $b '.streams\tasks.json') $doc }
        Assert-True (Test-Path (Join-Path $a '.streams\tasks.json')) 'old board untouched'
        Assert-True (-not (Test-Path (Get-GeneStreamBoardFile -Repo $b -Kind moved))) 'old host not marked'
    }

    Test-Case 'takeover without handoff refuses unless -NoHandoff' {
        $h = Get-GeneStreamBoardFile -Repo $b -Kind handoff; $keep = Get-Content $h -Raw; Remove-Item $h
        try { Assert-Match ((Get-Errors { getStreams -FromHost localhost -FromRepo $bUnc -Yes }) -join ' ') 'has not handed off' }
        finally { Set-Content $h $keep }
    }

    Test-Case 'getStreams -FromHost: board mirrored, old board saved, markers, exclude, .env' {
        Remove-Item $log -ErrorAction SilentlyContinue
        getStreams -FromHost localhost -FromRepo $bUnc -Yes 6>$null
        Assert-Equal (Get-Content (Join-Path $b '.streams\tasks.json') -Raw) (Get-Content (Join-Path $a '.streams\tasks.json') -Raw)
        Assert-Equal 'install -Yes' (Get-Content $log)
        $saved = @(Get-ChildItem (Join-Path $scratch 'stream-move') -Recurse -Filter tasks.json)
        Assert-True ($saved.Count -eq 1 -and (Get-Content $saved[0].FullName -Raw) -match 'OLD\.T001') 'old board saved under ScratchRoot'
        Assert-Equal $env:COMPUTERNAME (Read-GeneStreamBoardFile -Repo $a -Kind host).host
        Assert-Equal $env:COMPUTERNAME (Read-GeneStreamBoardFile -Repo $b -Kind moved).to
        Assert-True (-not (Test-Path (Get-GeneStreamBoardFile -Repo $a -Kind handoff))) 'handoff.json not carried'
        Assert-Equal 'CHANNEL=1' (Get-Content (Join-Path $a '.env'))
        Assert-True (Test-GeneStreamHost -Repo $a -Caller t)
        Assert-Match ((Get-Errors { Test-GeneStreamHost -Repo $b -Caller t }) -join ' ') 'moved to'
        Assert-Match ((Get-Errors { getStreams -FromHost localhost -FromRepo $bUnc -Yes }) -join ' ') 'already moved'
    }

    Test-Case 'updateStreams -DryRun reports and changes nothing' {
        $before = (Get-ChildItem (Join-Path $a '.streams') -Recurse -File).Count
        $out = updateStreams -DryRun 6>&1 | Out-String
        Assert-Match $out 'running now'
        Assert-Equal $before (Get-ChildItem (Join-Path $a '.streams') -Recurse -File).Count
    }
}
finally {
    Remove-Item Env:AI_MACHINE_CONFIG, Env:STREAMSYNC_TEST_LOG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
