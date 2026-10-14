#requires -Version 7
# The S:\AIWork linker layout: ~\.claude\skills is a real folder and EACH skill (and each agent/command file) is a
# symlink into a share other machines use. The first apply must replace the links it covers with real copies and
# never write through them into the share; links it does not cover stay. All under a scratch root.
param([string]$CorpusRoot = (Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$CorpusRoot = (Resolve-Path $CorpusRoot).Path
$root = New-TestRoot 'nestlink'
$oldPath = $env:PATH
try {
    $mc = Join-Path $root 'corpus'
    foreach ($d in 'lib', 'claude', 'setup') { robocopy (Join-Path $CorpusRoot $d) (Join-Path $mc $d) /E /XD tests /NFL /NDL /NJH /NJS /NP | Out-Null }
    foreach ($s in 'machine-config', 'stream-status') { robocopy (Join-Path $CorpusRoot "skills\$s") (Join-Path $mc "skills\$s") /E /NFL /NDL /NJH /NJS /NP | Out-Null }
    New-Item -ItemType Directory -Force (Join-Path $mc 'agents'), (Join-Path $mc 'commands') | Out-Null
    Set-Content (Join-Path $mc 'agents\a.md') 'agent from corpus'; Set-Content (Join-Path $mc 'commands\c.md') 'command'
    Copy-Item (Join-Path $CorpusRoot 'ai-manifest.json') $mc

    $fake = Join-Path $root 'fakebin'; New-Item -ItemType Directory -Force $fake | Out-Null
    Set-Content (Join-Path $fake 'claude.cmd') -Encoding ascii -Value @('@echo off', 'if "%1"=="--version" (echo 2.1.286 ^(Claude Code^) & exit /b 0)', 'exit /b 0')
    $env:PATH = "$fake;$oldPath"

    # The "share": an OLDER, different copy of a corpus skill, a skill the corpus lacks, and an agent file.
    $share = Join-Path $root 'share'
    robocopy (Join-Path $mc 'skills\machine-config') (Join-Path $share 'skills\machine-config') /E /NFL /NDL /NJH /NJS /NP | Out-Null
    Set-Content (Join-Path $share 'skills\machine-config\SKILL.md') 'SHARE VERSION'
    New-Item -ItemType Directory -Force (Join-Path $share 'skills\foreign'), (Join-Path $share 'agents') | Out-Null
    Set-Content (Join-Path $share 'skills\foreign\SKILL.md') 'foreign skill'
    Set-Content (Join-Path $share 'agents\a.md') 'SHARE AGENT'
    $shareBefore = Get-ChildItem $share -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)=$((Get-FileHash $_.FullName).Hash)" }

    $ch = Join-Path $root 'home\.claude'
    New-Item -ItemType Directory -Force (Join-Path $ch 'skills'), (Join-Path $ch 'agents') | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $ch 'skills\machine-config') -Target (Join-Path $share 'skills\machine-config') | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $ch 'skills\foreign') -Target (Join-Path $share 'skills\foreign') | Out-Null
    New-Item -ItemType SymbolicLink -Path (Join-Path $ch 'agents\a.md') -Target (Join-Path $share 'agents\a.md') | Out-Null

    $cfg = Join-Path $root 'profile.md'
    New-TestProfile -Path $cfg -Keys ([ordered]@{ AIWorkRoot = $mc; ClaudeHome = $ch; ReposRoot = (Join-Path $root 'repos'); ScratchRoot = (Join-Path $root 'scratch'); WorktreesRoot = (Join-Path $root 'wt'); TestedClaudeVersion = '2.1.286' }) -Sections ([ordered]@{
            'Claude access' = "| Path | Access | Note |`n|---|---|---|`n| {ScratchRoot} | read, edit | |"
        })
    New-Item -ItemType Directory -Force (Join-Path $root 'repos') | Out-Null
    $env:AI_MACHINE_CONFIG = $cfg
    $inst = Join-Path $mc 'setup\Install-AIMachine.ps1'
    $w = & pwsh -NoProfile -File $inst -ConfigPath $cfg -SkipMcp -ClaudeExeDir $fake -WhatIf *>&1 | Out-String
    $o = & pwsh -NoProfile -File $inst -ConfigPath $cfg -SkipMcp -ClaudeExeDir $fake *>&1 | Out-String; $code = $LASTEXITCODE

    Test-Case 'apply succeeds; -WhatIf names the per-item links and the kept one' {
        Assert-Equal 0 $code $o
        Assert-Match $w 'link -> copy: skills\\machine-config'
        Assert-Match $w 'link -> copy: agents\\a\.md'
        Assert-Match $w '1 link\(s\) not in the corpus are kept'
    }
    Test-Case 'the share is untouched (nothing written through a link)' {
        $now = Get-ChildItem $share -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)=$((Get-FileHash $_.FullName).Hash)" }
        Assert-Equal ($shareBefore -join "`n") ($now -join "`n")
    }
    Test-Case 'covered links became real copies of the corpus' {
        $sk = Get-Item (Join-Path $ch 'skills\machine-config') -Force
        Assert-True (-not $sk.LinkType) 'skills\machine-config is still a link'
        Assert-Equal (Get-FileHash (Join-Path $mc 'skills\machine-config\SKILL.md')).Hash (Get-FileHash (Join-Path $ch 'skills\machine-config\SKILL.md')).Hash
        $want = @(Get-ChildItem (Join-Path $mc 'skills\machine-config') -Recurse -File).Count
        Assert-Equal $want @(Get-ChildItem (Join-Path $ch 'skills\machine-config') -Recurse -File).Count
        Assert-True (-not (Get-Item (Join-Path $ch 'agents\a.md') -Force).LinkType) 'agents\a.md is still a link'
        Assert-Equal 'agent from corpus' (Get-Content (Join-Path $ch 'agents\a.md') -Raw).Trim()
    }
    Test-Case 'a link the corpus does not cover is kept' {
        Assert-Equal 'SymbolicLink' ([string](Get-Item (Join-Path $ch 'skills\foreign') -Force).LinkType)
        Assert-Equal 'foreign skill' (Get-Content (Join-Path $ch 'skills\foreign\SKILL.md') -Raw).Trim()
    }
}
finally {
    $env:PATH = $oldPath
    Remove-Item Env:\AI_MACHINE_CONFIG -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
