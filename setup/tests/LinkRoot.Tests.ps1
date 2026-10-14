#requires -Version 7
# R38: with SkillsLinkRoot set, every skill, agent and command in ClaudeHome is a symbolic link into that tree (a share
# several machines use). The corpus wins: its content is written into the tree first, extras there are removed, and the
# links are set or retargeted. A failed apply restores the tree and the links; blanking the key goes back to copies
# without touching the tree. All under a scratch root.
param([string]$CorpusRoot = (Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$CorpusRoot = (Resolve-Path $CorpusRoot).Path
$root = New-TestRoot 'linkroot'
$oldPath = $env:PATH
try {
    $mc = Join-Path $root 'corpus'
    foreach ($d in 'lib', 'claude', 'setup') { robocopy (Join-Path $CorpusRoot $d) (Join-Path $mc $d) /E /XD tests /NFL /NDL /NJH /NJS /NP | Out-Null }
    foreach ($s in 'machine-config', 'stream-status') { robocopy (Join-Path $CorpusRoot "skills\$s") (Join-Path $mc "skills\$s") /E /NFL /NDL /NJH /NJS /NP | Out-Null }
    New-Item -ItemType Directory -Force (Join-Path $mc 'agents'), (Join-Path $mc 'commands') | Out-Null
    Set-Content (Join-Path $mc 'agents\a.md') 'agent from corpus'; Set-Content (Join-Path $mc 'commands\c.md') 'command from corpus'
    Copy-Item (Join-Path $CorpusRoot 'ai-manifest.json') $mc

    $fake = Join-Path $root 'fakebin'; New-Item -ItemType Directory -Force $fake | Out-Null
    Set-Content (Join-Path $fake 'claude.cmd') -Encoding ascii -Value @('@echo off', 'if "%1"=="--version" (echo 2.1.286 ^(Claude Code^) & exit /b 0)', 'exit /b 0')
    $env:PATH = "$fake;$oldPath"

    # The share: an older copy of one corpus skill plus a stale file in it, a skill the corpus lacks, an older agent.
    $share = Join-Path $root 'share'
    robocopy (Join-Path $mc 'skills\machine-config') (Join-Path $share 'skills\machine-config') /E /NFL /NDL /NJH /NJS /NP | Out-Null
    Set-Content (Join-Path $share 'skills\machine-config\SKILL.md') 'SHARE VERSION'
    Set-Content (Join-Path $share 'skills\machine-config\stale.md') 'only on the share'
    New-Item -ItemType Directory -Force (Join-Path $share 'skills\foreign'), (Join-Path $share 'agents') | Out-Null
    Set-Content (Join-Path $share 'skills\foreign\SKILL.md') 'foreign skill'
    Set-Content (Join-Path $share 'agents\a.md') 'SHARE AGENT'

    # ClaudeHome: right link, a real local copy (the stream-host layout), a link elsewhere, a foreign link, one missing.
    $ch = Join-Path $root 'home\.claude'
    $elsewhere = Join-Path $root 'elsewhere'; New-Item -ItemType Directory -Force $elsewhere | Out-Null; Set-Content (Join-Path $elsewhere 'a.md') 'ELSEWHERE'
    New-Item -ItemType Directory -Force (Join-Path $ch 'skills\stream-status'), (Join-Path $ch 'agents') | Out-Null
    Set-Content (Join-Path $ch 'skills\stream-status\SKILL.md') 'LOCAL RESOLVED COPY'
    New-Item -ItemType SymbolicLink -Path (Join-Path $ch 'skills\machine-config') -Target (Join-Path $share 'skills\machine-config') | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $ch 'skills\foreign') -Target (Join-Path $share 'skills\foreign') | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $ch 'agents\a.md') -Target (Join-Path $elsewhere 'a.md') | Out-Null

    $keys = [ordered]@{ AIWorkRoot = $mc; ClaudeHome = $ch; ReposRoot = (Join-Path $root 'repos'); ScratchRoot = (Join-Path $root 'scratch'); WorktreesRoot = (Join-Path $root 'wt'); TestedClaudeVersion = '2.1.286'; SkillsLinkRoot = $share }
    $cfg = Join-Path $root 'profile.md'
    $access = @{ 'Claude access' = "| Path | Access | Note |`n|---|---|---|`n| {ScratchRoot} | read, edit | |" }
    New-TestProfile -Path $cfg -Keys $keys -Sections $access
    New-Item -ItemType Directory -Force (Join-Path $root 'repos') | Out-Null
    $env:AI_MACHINE_CONFIG = $cfg
    $inst = Join-Path $mc 'setup\Install-AIMachine.ps1'
    $run = { param([string[]]$extra) $o = & pwsh -NoProfile -File $inst -ConfigPath $cfg -SkipMcp -ClaudeExeDir $fake @extra *>&1 | Out-String; [pscustomobject]@{ Out = $o; Code = $LASTEXITCODE } }
    $items = 'skills\machine-config', 'skills\stream-status', 'agents\a.md', 'commands\c.md'
    $corpusOf = { param($item) $p = Join-Path $mc $item; if (Test-Path $p -PathType Container) { Get-ChildItem $p -Recurse -File | ForEach-Object { "$($_.FullName.Substring($p.Length))=$((Get-FileHash $_.FullName).Hash)" } | Sort-Object } else { (Get-FileHash $p).Hash } }
    $shareOf = { param($item) $p = Join-Path $share $item; if (Test-Path $p -PathType Container) { Get-ChildItem $p -Recurse -File | ForEach-Object { "$($_.FullName.Substring($p.Length))=$((Get-FileHash $_.FullName).Hash)" } | Sort-Object } else { (Get-FileHash $p).Hash } }

    $w = & $run @('-WhatIf')
    $a1 = & $run @()

    Test-Case '-WhatIf names the link-tree writes, removals and links to set' {
        Assert-Equal 0 $w.Code $w.Out
        Assert-Match $w.Out 'link tree write: skills\\machine-config\\SKILL\.md'
        Assert-Match $w.Out 'link tree remove: skills\\machine-config\\stale\.md'
        Assert-Match $w.Out 'SkillsLinkRoot .*: 3 links to set'
    }
    Test-Case 'every corpus item is a symbolic link to SkillsLinkRoot\<kind>\<name>' {
        Assert-Equal 0 $a1.Code $a1.Out
        foreach ($i in $items) {
            $x = Get-Item (Join-Path $ch $i) -Force
            Assert-Equal 'SymbolicLink' ([string]$x.LinkType) "$i is not a link"
            Assert-Equal (Join-Path $share $i) ([string]$x.Target) "$i points elsewhere"
        }
    }
    Test-Case 'the corpus wins in the link tree; foreign content there is untouched' {
        foreach ($i in $items) { Assert-Equal ((& $corpusOf $i) -join "`n") ((& $shareOf $i) -join "`n") "$i differs from the corpus" }
        Assert-True (-not (Test-Path (Join-Path $share 'skills\machine-config\stale.md'))) 'stale.md is still on the share'
        Assert-Equal 'foreign skill' (Get-Content (Join-Path $share 'skills\foreign\SKILL.md') -Raw).Trim()
        Assert-Equal 'SymbolicLink' ([string](Get-Item (Join-Path $ch 'skills\foreign') -Force).LinkType)
        Assert-Equal 'ELSEWHERE' (Get-Content (Join-Path $elsewhere 'a.md') -Raw).Trim()
    }
    Test-Case 'the replaced local copy and the overwritten share files are in the rollback snapshot' {
        $rb = Get-ChildItem (Join-Path $ch 'machine-config') -Directory -Filter 'rollback-*' | Select-Object -First 1
        Assert-Equal 'LOCAL RESOLVED COPY' (Get-Content (Join-Path $rb.FullName 'items\skills\stream-status\SKILL.md') -Raw).Trim()
        Assert-Equal 'SHARE VERSION' (Get-Content (Join-Path $rb.FullName 'linktree\skills\machine-config\SKILL.md') -Raw).Trim()
        Assert-Equal 'only on the share' (Get-Content (Join-Path $rb.FullName 'linktree\skills\machine-config\stale.md') -Raw).Trim()
    }
    Test-Case 'a second apply has nothing to do' {
        $c = & $run @('-Check')
        Assert-Match $c.Out '0 links to set, 0 files to write and 0 to remove'
        Assert-Match $c.Out '\(up to date\)'
    }
    Test-Case 'another machine editing the share is drift: apply stops, -AcceptDrift puts the corpus back' {
        Set-Content (Join-Path $share 'skills\machine-config\SKILL.md') 'EDITED ON TR2'
        $d = & $run @()
        Assert-Equal 3 $d.Code $d.Out
        Assert-Equal 'EDITED ON TR2' (Get-Content (Join-Path $share 'skills\machine-config\SKILL.md') -Raw).Trim()
        $d2 = & $run @('-AcceptDrift')
        Assert-Equal 0 $d2.Code $d2.Out
        Assert-Equal ((& $corpusOf 'skills\machine-config') -join "`n") ((& $shareOf 'skills\machine-config') -join "`n")
    }
    Test-Case 'a failed apply restores the link tree and the replaced entry' {
        $before = (& $shareOf 'skills\machine-config') -join "`n"
        Set-Content (Join-Path $mc 'skills\machine-config\SKILL.md') 'NEW CORPUS VERSION'
        [IO.File]::Delete((Join-Path $ch 'commands\c.md')); Set-Content (Join-Path $ch 'commands\c.md') 'LOCAL COMMAND'
        $env:AI_TEST_FAIL_BEFORE_STATE = '1'
        try { $f = & $run @('-AcceptDrift') } finally { Remove-Item Env:\AI_TEST_FAIL_BEFORE_STATE }
        Assert-True ($f.Code -ne 0) $f.Out
        Assert-Match $f.Out 'Restoring the previous install'
        Assert-Equal $before ((& $shareOf 'skills\machine-config') -join "`n")
        $c = Get-Item (Join-Path $ch 'commands\c.md') -Force
        Assert-True (-not $c.LinkType) 'commands\c.md should be the local file again'
        Assert-Equal 'LOCAL COMMAND' (Get-Content $c.FullName -Raw).Trim()
        $ok = & $run @('-AcceptDrift')
        Assert-Equal 0 $ok.Code $ok.Out
        Assert-Equal 'NEW CORPUS VERSION' (Get-Content (Join-Path $share 'skills\machine-config\SKILL.md') -Raw).Trim()
        Assert-Equal 'SymbolicLink' ([string](Get-Item (Join-Path $ch 'commands\c.md') -Force).LinkType)
    }
    Test-Case 'blanking SkillsLinkRoot goes back to real copies and leaves the share alone' {
        $shareNow = Get-ChildItem $share -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)=$((Get-FileHash $_.FullName).Hash)" }
        $k2 = [ordered]@{} + $keys; $k2['SkillsLinkRoot'] = ''
        New-TestProfile -Path $cfg -Keys $k2 -Sections $access
        $b = & $run @()
        Assert-Equal 0 $b.Code $b.Out
        foreach ($i in $items) {
            Assert-True (-not (Get-Item (Join-Path $ch $i) -Force).LinkType) "$i is still a link"
            Assert-Equal ((& $corpusOf $i) -join "`n") $(if (Test-Path (Join-Path $ch $i) -PathType Container) { (Get-ChildItem (Join-Path $ch $i) -Recurse -File | ForEach-Object { "$($_.FullName.Substring((Join-Path $ch $i).Length))=$((Get-FileHash $_.FullName).Hash)" } | Sort-Object) -join "`n" } else { (Get-FileHash (Join-Path $ch $i)).Hash }) "$i copy differs"
        }
        $after = Get-ChildItem $share -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)=$((Get-FileHash $_.FullName).Hash)" }
        Assert-Equal ($shareNow -join "`n") ($after -join "`n")
    }
    Test-Case 'an unreachable SkillsLinkRoot stops validation' {
        $k3 = [ordered]@{} + $keys; $k3['SkillsLinkRoot'] = (Join-Path $root 'no-such-share')
        New-TestProfile -Path $cfg -Keys $k3 -Sections $access
        $v = & $run @('-WhatIf')
        Assert-Equal 2 $v.Code $v.Out
        Assert-Match $v.Out 'SkillsLinkRoot .* is not reachable'
    }
    Test-Case 'SkillsLinkRoot = the corpus copy: links go into it, and an edit there is a corpus edit, not drift (R39)' {
        $ch2 = Join-Path $root 'home2\.claude'; New-Item -ItemType Directory -Force $ch2 | Out-Null
        $k4 = [ordered]@{} + $keys; $k4['SkillsLinkRoot'] = $mc; $k4['ClaudeHome'] = $ch2
        New-TestProfile -Path $cfg -Keys $k4 -Sections $access
        $first = & $run @()
        Assert-Equal 0 $first.Code $first.Out
        Assert-Equal (Join-Path $mc 'skills\machine-config') ([string](Get-Item (Join-Path $ch2 'skills\machine-config') -Force).Target)
        # Edit through the link, as a session on that machine would.
        Set-Content (Join-Path $ch2 'skills\machine-config\SKILL.md') 'EDITED ON THE MACHINE'
        $c = & $run @('-Check')
        Assert-True ($c.Out -notmatch 'Drift:') $c.Out
        Assert-Match $c.Out '\(apply pending\)'
        $again = & $run @()
        Assert-Equal 0 $again.Code $again.Out
        Assert-Equal 'EDITED ON THE MACHINE' (Get-Content (Join-Path $mc 'skills\machine-config\SKILL.md') -Raw).Trim()
    }
}
finally {
    $env:PATH = $oldPath
    Remove-Item Env:\AI_MACHINE_CONFIG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
