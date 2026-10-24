#requires -Version 7
# install.ps1: the location review that runs before anything is written. Every case runs the real install.ps1 of this
# clone against a scratch machine profile (AI_MACHINE_CONFIG) with a scratch Claude home, in -WhatIf/-Check or in a mode
# that must refuse, so nothing in the real Claude home, Documents or this clone changes.
# Run: pwsh -NoProfile -File Install.Tests.ps1
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$repo = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path.TrimEnd('\')
$install = Join-Path $repo 'install.ps1'

$root = New-TestRoot 'inst-ps1'
$oldCfg = $env:AI_MACHINE_CONFIG; $oldCcd = $env:CLAUDE_CONFIG_DIR
try {
    $home1 = Join-Path $root 'home\.claude'; $scratch = Join-Path $root 'scratch'; $wt = Join-Path $root 'wt'; $repos = Join-Path $root 'repos'
    New-Item -ItemType Directory -Force $home1, $scratch, $wt, $repos | Out-Null
    $cfg = Join-Path $root 'profile.md'
    $access = "| Path | Access | Note |`n|---|---|---|`n| {ReposRoot} | read, edit | |`n| {ScratchRoot} | read, edit | |"
    function Write-Profile([string]$Work = $repo) {
        New-TestProfile -Path $cfg -Keys ([ordered]@{ AIWorkRoot = $Work; ClaudeHome = $home1; ReposRoot = $repos; ScratchRoot = $scratch; WorktreesRoot = $wt; TestedClaudeVersion = '2.1.286' }) -Sections ([ordered]@{
                'Claude access' = $access
                'Git policy'    = "| Repo | Commit | Push | Worktrees | Note |`n|---|---|---|---|---|`n| $repo | yes | yes | no | test |`n| $(Join-Path $repos 'nope') | yes | no | no | missing on purpose |"
            })
    }
    $env:AI_MACHINE_CONFIG = $cfg
    function Run([string[]]$More) { $o = & pwsh -NoProfile -File $install @More *>&1; [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($o -join "`n") } }
    function Home-Empty { @(Get-ChildItem -LiteralPath $home1 -Force -Recurse -ErrorAction SilentlyContinue).Count -eq 0 }

    # ---- the Claude home the profile names is not the one Claude reads (no CLAUDE_CONFIG_DIR, so ~\.claude) ----
    Write-Profile
    $env:CLAUDE_CONFIG_DIR = $null
    $w = Run @('-NoPull', '-WhatIf')
    Test-Case '-WhatIf lists every location with its state and the repos of the git policy' {
        Assert-Equal 0 $w.Code $w.Out
        Assert-Match $w.Out '== locations on '
        Assert-Match $w.Out 'KEY\s+PATH\s+STATE'
        Assert-Match $w.Out ([regex]::Escape($scratch) + '\s+local')
        Assert-Match $w.Out ([regex]::Escape((Join-Path $repos 'nope')) + '\s+MISSING, commit=yes')
        Assert-Match $w.Out 'this clone \(AIWorkRoot\)\s+' + [regex]::Escape($repo) + '\s+ok'
        Assert-Match $w.Out 'PowerShell 7 profile\s+' + [regex]::Escape((Split-Path $PROFILE.CurrentUserCurrentHost))
        Assert-Match $w.Out 'memory junction\s+' + [regex]::Escape((Join-Path $home1 'memory'))
        Assert-Match $w.Out "scratch cleanup task\s+'AI scratch cleanup' hourly as \S+, ONLY under " + [regex]::Escape($scratch) + ', files unused 7 days'
        Assert-NoMatch $w.Out 'REGISTERED '
        Assert-Match $w.Out "DRY-RUN task 'AI scratch cleanup' hourly"
        Assert-Match $w.Out 'scratch cleanup: would register'
    }
    Test-Case '-WhatIf names a Claude home Claude does not read as a stop, but goes on reporting and writes nothing' {
        Assert-Match $w.Out 'NOT what Claude reads'
        Assert-Match $w.Out 'STOP: the profile''s ClaudeHome is'
        Assert-Match $w.Out 'a real run would stop here'
        Assert-Match $w.Out 'nothing is written, so no confirmation is asked'
        Assert-Match $w.Out '== summary \(nothing was written\)'
        Assert-Match $w.Out 'memory: would link'
        Assert-True (Home-Empty) 'the scratch Claude home gained files under -WhatIf'
    }
    $r = Run @('-NoPull', '-Yes')
    Test-Case 'a real run refuses (exit 2) when the profile''s ClaudeHome is not what Claude reads, and writes nothing' {
        Assert-Equal 2 $r.Code $r.Out
        Assert-Match $r.Out 'STOP: the profile''s ClaudeHome is'
        Assert-Match $r.Out 'Nothing was changed'
        Assert-NoMatch $r.Out '== git pull|== Claude runtime'
        Assert-True (Home-Empty) 'the scratch Claude home gained files on a refused run'
    }

    # ---- CLAUDE_CONFIG_DIR makes the scratch home the real one; now the clone must be the profile's AIWorkRoot ----
    $env:CLAUDE_CONFIG_DIR = $home1
    Write-Profile -Work (Join-Path $root 'elsewhere\ai-setup')
    $r2 = Run @('-NoPull', '-Yes')
    Test-Case 'a real run refuses when this clone is not the profile''s AIWorkRoot, naming both paths' {
        Assert-Equal 2 $r2.Code $r2.Out
        Assert-Match $r2.Out 'NOT THE PROFILE''S AIWorkRoot'
        Assert-Match $r2.Out ('STOP: this clone is ' + [regex]::Escape($repo) + ' but the profile''s AIWorkRoot is ' + [regex]::Escape((Join-Path $root 'elsewhere\ai-setup')))
        Assert-True (Home-Empty) 'the scratch Claude home gained files on a refused run'
    }
    Write-Profile
    $r3 = '' | & pwsh -NoProfile -File $install -NoPull *>&1; $r3Code = $LASTEXITCODE
    Test-Case 'with both locations right, a real run with redirected input and no -Yes refuses instead of hanging on the question' {
        Assert-Equal 2 $r3Code ($r3 -join "`n")
        Assert-Match ($r3 -join "`n") 'input is redirected. Re-run with -Yes'
        Assert-NoMatch ($r3 -join "`n") '== git pull|== Claude runtime'
        Assert-True (Home-Empty) 'the scratch Claude home gained files on a refused run'
    }
    $c = Run @('-NoPull', '-Check')
    Test-Case '-Check with both locations right lists them as ok and ends in the installer''s own check report' {
        Assert-Equal 0 $c.Code $c.Out
        Assert-Match $c.Out 'Claude runtime\s+' + [regex]::Escape($home1) + '\s+ok: what Claude reads'
        Assert-Match $c.Out 'Installed revision: none'
        Assert-Match $c.Out 'runtime: checked into'
        Assert-True (Home-Empty) 'the scratch Claude home gained files under -Check'
    }
    # ---- stale profile files: a profile.d or Gene.* module file the repo no longer has would still load ----
    $pd = Join-Path $root 'pwshdir'; $wp = Join-Path $root 'winpsdir'
    New-Item -ItemType Directory -Force (Join-Path $pd 'profile.d'), (Join-Path $pd 'Modules\Gene.Profile'), (Join-Path $pd 'Modules\Other.Mod'), $wp | Out-Null
    Set-Content (Join-Path $pd 'profile.d\retired.ps1') '# gone from the repo'
    Set-Content (Join-Path $pd 'Modules\Gene.Profile\AiGroup.ps1') '# gone from the repo'
    Set-Content (Join-Path $pd 'Modules\Other.Mod\Other.Mod.psm1') '# not ours'
    Set-Content (Join-Path $pd 'mine.ps1') '# my own file'
    $s = Run @('-NoPull', '-WhatIf', '-PwshProfileDir', $pd, '-WinPsProfileDir', $wp)
    Test-Case '-WhatIf lists stale profile.d and Gene.* module files as would remove; other modules and own files are left alone' {
        Assert-Equal 0 $s.Code $s.Out
        Assert-Match $s.Out 'PowerShell 7 profile\s+' + [regex]::Escape($pd)
        Assert-Match $s.Out ('would remove ' + [regex]::Escape((Join-Path $pd 'profile.d\retired.ps1')))
        Assert-Match $s.Out ('would remove ' + [regex]::Escape((Join-Path $pd 'Modules\Gene.Profile\AiGroup.ps1')))
        Assert-NoMatch $s.Out 'would remove .*Other\.Mod|would remove .*mine\.ps1'
        Assert-Match $s.Out 'PowerShell profile: .*2 stale file\(s\) would be removed'
        Assert-True (Test-Path (Join-Path $pd 'profile.d\retired.ps1')) 'removed under -WhatIf'
    }

    # ---- no profile at all: the first-run message says what the file is and where it is described ----
    $env:AI_MACHINE_CONFIG = Join-Path $root 'no-such-profile.md'
    $n = Run @('-NoPull', '-Yes')
    Test-Case 'a machine with no profile is told what to create and where it is described, and nothing runs' {
        Assert-Equal 2 $n.Code $n.Out
        Assert-Match $n.Out 'Machine config file not found'
        Assert-Match $n.Out 'docs\\machine-config-design.md section 4.1'
        Assert-NoMatch $n.Out '== locations'
    }
}
finally {
    $env:AI_MACHINE_CONFIG = $oldCfg; $env:CLAUDE_CONFIG_DIR = $oldCcd
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
