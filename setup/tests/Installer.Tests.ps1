#requires -Version 7
# Installer and launcher behaviour (spec 5.2 settings, 5.11 stale exports, 5.12 rejected revocation, 5.13 change
# detection, 5.14 concurrency + interrupted apply, 5.16 fresh machine inventory, 5.18 read-only + repeatability,
# 5.19 activation report, plus drift). Everything runs against a scratch Claude home, a mini corpus built from this
# corpus, a scratch profile and a fake 'claude' on PATH. Nothing touches the live install, settings or shims.
param([string]$CorpusRoot = (Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot 'TestHarness.ps1')
$CorpusRoot = (Resolve-Path $CorpusRoot).Path
Import-Module (Join-Path $CorpusRoot 'lib\AISettings.psm1') -Force -DisableNameChecking

$root = New-TestRoot 'inst'
$realShim = @(Get-Command claude -All -ErrorAction SilentlyContinue | Where-Object CommandType -eq 'Application' | ForEach-Object { Join-Path (Split-Path $_.Source) 'ai.cmd' } | Where-Object { Test-Path $_ })
$realShimHash = @($realShim | ForEach-Object { (Get-FileHash $_).Hash })
$oldPath = $env:PATH
try {
    # ---- fixture: mini corpus (the real lib, scripts, templates and setup; two skills, one agent, one command) ----
    $mc = Join-Path $root 'corpus'
    foreach ($d in 'lib', 'claude', 'setup') { robocopy (Join-Path $CorpusRoot $d) (Join-Path $mc $d) /E /XD tests /NFL /NDL /NJH /NJS /NP | Out-Null }
    foreach ($s in 'machine-config', 'stream-status') { robocopy (Join-Path $CorpusRoot "skills\$s") (Join-Path $mc "skills\$s") /E /NFL /NDL /NJH /NJS /NP | Out-Null }
    New-Item -ItemType Directory -Force (Join-Path $mc 'agents'), (Join-Path $mc 'commands') | Out-Null
    Set-Content (Join-Path $mc 'agents\a.md') 'agent'; Set-Content (Join-Path $mc 'commands\c.md') 'command'
    Copy-Item (Join-Path $CorpusRoot 'ai-manifest.json') $mc

    # ---- fixture: fake claude first on PATH (answers --version; records its environment) ----
    $fake = Join-Path $root 'fakebin'; New-Item -ItemType Directory -Force $fake | Out-Null
    Set-Content (Join-Path $fake 'claude.cmd') -Encoding ascii -Value @(
        '@echo off', 'if "%1"=="--version" (echo 2.1.286 ^(Claude Code^) & exit /b 0)',
        'set AI_ > "%AI_TEST_MARKER%"', 'echo CLAUDE_CODE_TMPDIR=%CLAUDE_CODE_TMPDIR%>> "%AI_TEST_MARKER%"', 'exit /b 0')
    $env:PATH = "$fake;$oldPath"
    $env:AI_TEST_MARKER = Join-Path $root 'claude-env.txt'

    # ---- fixture: profile ----
    $ch = Join-Path $root 'home\.claude'; $ro = Join-Path $root 'readonly'; $vaultA = Join-Path $root 'vaultA'; $vaultB = Join-Path $root 'vaultB'
    New-Item -ItemType Directory -Force $ch, $ro, $vaultA, $vaultB, (Join-Path $root 'repos') | Out-Null
    $cfg = Join-Path $root 'profile.md'
    $access = "| Path | Access | Note |`n|---|---|---|`n| {ReposRoot} | read, edit | |`n| {ScratchRoot} | read, edit | |`n| $ro | read | |"
    function Write-Profile([string]$Vault = $vaultA, [switch]$NoRepos, [string]$Access = $access, [string]$Work = $mc) {
        $k = [ordered]@{ AIWorkRoot = $Work;ClaudeHome = $ch; ScratchRoot = (Join-Path $root 'scratch'); WorktreesRoot = (Join-Path $root 'wt'); VaultWorkRoot = $Vault; TestedClaudeVersion = '2.1.286' }
        if (-not $NoRepos) { $k.ReposRoot = (Join-Path $root 'repos') }
        New-TestProfile -Path $cfg -Keys $k -Sections ([ordered]@{ 'Claude access' = $Access })
    }
    Write-Profile
    $env:AI_MACHINE_CONFIG = $cfg

    # ---- fixture: the old linker layout (skills junction to an identical copy, plus Claude-managed skills\synced) ----
    $oldAI = Join-Path $root 'oldAI'
    robocopy (Join-Path $mc 'skills') (Join-Path $oldAI 'skills') /E /NFL /NDL /NJH /NJS /NP | Out-Null
    New-Item -ItemType Directory -Force (Join-Path $oldAI 'skills\synced\x') | Out-Null; Set-Content (Join-Path $oldAI 'skills\synced\x\SKILL.md') 'synced'
    New-Item -ItemType Junction -Path (Join-Path $ch 'skills') -Target (Join-Path $oldAI 'skills') | Out-Null
    $oldTree = Get-ChildItem $oldAI -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)=$((Get-FileHash $_.FullName).Hash)" }
    $inst = Join-Path $mc 'setup\Install-AIMachine.ps1'
    function Install([string[]]$More = @()) { $o = & pwsh -NoProfile -File $inst -ConfigPath $cfg -SkipMcp -ClaudeExeDir $fake @More *>&1; [pscustomobject]@{ Code = $LASTEXITCODE; Out = ($o -join "`n") } }
    function State { Get-Content (Join-Path $ch 'machine-config.state.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 30 }
    function Settings { Get-Content (Join-Path $ch 'settings.json') -Raw | ConvertFrom-Json -AsHashtable -Depth 30 }
    function Tree-Hash { Get-ChildItem $ch -Recurse -File -Force | Where-Object FullName -notmatch 'machine-config\.lock$' | Sort-Object FullName | ForEach-Object { "$($_.FullName.Substring($ch.Length))=$((Get-FileHash $_.FullName).Hash)" } }
    function Inventory-Ok { $s = State; foreach ($rel in $s.files.Keys) { $p = Join-Path $ch $rel; if (-not (Test-Path $p) -or (Get-FileHash $p).Hash -ne $s.files[$rel]) { return "$rel" } }; return '' }

    # ---- 5.16 fresh machine ----
    $r = Install
    Test-Case 'fresh install into an empty Claude home succeeds' { Assert-Equal 0 $r.Code $r.Out }
    Test-Case 'a skills junction with identical content becomes a full real copy; its target is untouched' {
        Assert-True (-not (Get-Item (Join-Path $ch 'skills') -Force).LinkType) 'skills is still a link'
        $want = @((State).files.Keys | Where-Object { $_ -like 'skills\*' }).Count
        Assert-True ($want -gt 0) 'no skills in the inventory'
        $have = @(Get-ChildItem (Join-Path $ch 'skills') -Recurse -File | Where-Object FullName -notlike '*\synced\*').Count
        Assert-Equal $want $have
        Assert-Equal 'synced' (Get-Content (Join-Path $ch 'skills\synced\x\SKILL.md') -Raw).Trim()
        $now = Get-ChildItem $oldAI -Recurse -File | Sort-Object FullName | ForEach-Object { "$($_.FullName)=$((Get-FileHash $_.FullName).Hash)" }
        Assert-Equal ($oldTree -join "`n") ($now -join "`n")
    }
    Test-Case 'the installed inventory matches the manifest by name and hash' {
        Assert-Equal '' (Inventory-Ok)
        $s = State
        Assert-True ($s.files.Contains('skills\machine-config\SKILL.md') -and $s.files.Contains('scripts\git-guard.ps1') -and $s.files.Contains('bin\ai.ps1') -and $s.files.Contains('lib\MachineConfig.psm1')) 'manifest entries missing'
    }
    Test-Case 'the generated settings carry only this profile''s paths' {
        # The test root itself sits under the user's temp folder, so drop it first; nothing else may name this laptop.
        $raw = Get-Content (Join-Path $ch 'settings.json') -Raw
        Assert-Match $raw ([regex]::Escape(($ch -replace '\\', '/')))
        $txt = $raw.Replace(($root -replace '\\', '\\'), '').Replace(($root -replace '\\', '/'), '').Replace((ConvertTo-AIRulePath $root), '')
        $hit = [regex]::Matches($txt, '.{0,60}(?i:agenewe|devops[\\/]+repos|C:[\\/]+tmp).{0,40}') | ForEach-Object Value
        Assert-Equal 0 @($hit).Count ($hit -join ' || ')
    }
    # ---- 5.2 generator output ----
    Test-Case 'settings: access rows render as //c rules, additionalDirectories and AI_ env' {
        $s = Settings; $rp = ConvertTo-AIRulePath (Join-Path $root 'repos')
        Assert-True (@($s.permissions.allow) -contains "Read($rp/**)") (@($s.permissions.allow) -join ' | ')
        Assert-True (@($s.permissions.allow) -contains "Edit($rp/**)") 'edit allow missing'
        Assert-True (@($s.permissions.additionalDirectories) -contains (Join-Path $root 'repos')) 'additionalDirectories missing'
        Assert-Equal (Join-Path $root 'scratch') $s.env.AI_SCRATCHROOT
        Assert-Equal (Join-Path $root 'scratch') $s.env.CLAUDE_CODE_TMPDIR
        Assert-Equal (Join-Path $root 'scratch\temp') $s.env.TEMP
    }
    # ---- 5.18 read-only ----
    Test-Case 'a read-only row renders Read allow plus Edit deny' {
        $s = Settings; $rp = ConvertTo-AIRulePath $ro
        Assert-True (@($s.permissions.allow) -contains "Read($rp/**)") 'read allow missing'
        Assert-True (@($s.permissions.deny) -contains "Edit($rp/**)") (@($s.permissions.deny) -join ' | ')
        Assert-True (@($s.permissions.allow) -notcontains "Edit($rp/**)") 'edit allowed on a read-only row'
    }
    # ---- 5.18 repeatability ----
    Test-Case '-WhatIf and -Check change nothing in the Claude home' {
        $before = Tree-Hash
        $w = Install @('-WhatIf'); $c = Install @('-Check')
        Assert-Equal 0 $w.Code $w.Out; Assert-Equal 0 $c.Code $c.Out
        Assert-Equal ($before -join "`n") ((Tree-Hash) -join "`n")
    }
    Test-Case 'applying twice with identical inputs makes no effective change' {
        $id = (State).identity; $sj = (Get-FileHash (Join-Path $ch 'settings.json')).Hash
        $r2 = Install
        Assert-Equal 0 $r2.Code $r2.Out
        Assert-Match $r2.Out '0 files written, 0 removed'
        Assert-Equal $id (State).identity; Assert-Equal $sj (Get-FileHash (Join-Path $ch 'settings.json')).Hash
    }
    Test-Case 'a launch with nothing changed is a no-op' {
        $before = Tree-Hash; $l = Install @('-Launch'); Assert-Equal 0 $l.Code $l.Out
        Assert-Equal ($before -join "`n") ((Tree-Hash) -join "`n")
    }
    # ---- 5.13 complete change detection ----
    $id0 = (State).identity
    $tpl = Join-Path $mc 'claude\settings.template.json'
    $t = Get-Content $tpl -Raw | ConvertFrom-Json -AsHashtable -Depth 30; $t.env['AI_TEST_TEMPLATE_ONLY'] = 'x'
    ($t | ConvertTo-Json -Depth 30) | Set-Content $tpl
    $l1 = Install @('-Launch')
    Test-Case 'a template-only change is detected and installed' { Assert-Equal 0 $l1.Code $l1.Out; Assert-True ((State).identity -ne $id0) 'identity unchanged'; Assert-Equal 'x' (Settings).env.AI_TEST_TEMPLATE_ONLY }
    $id1 = (State).identity
    Add-Content (Join-Path $mc 'claude\scripts\credentials-guard.ps1') '# guard-only change'
    $l2 = Install @('-Launch')
    Test-Case 'a guard-script-only change is detected and installed' {
        Assert-Equal 0 $l2.Code $l2.Out; Assert-True ((State).identity -ne $id1) 'identity unchanged'
        Assert-Match (Get-Content (Join-Path $ch 'scripts\credentials-guard.ps1') -Raw) 'guard-only change'
    }
    $id2 = (State).identity
    Add-Content (Join-Path $mc 'lib\AISettings.psm1') "`n# generator-only change"
    $l3 = Install @('-Launch')
    Test-Case 'a generator-only change is detected and installed' { Assert-Equal 0 $l3.Code $l3.Out; Assert-True ((State).identity -ne $id2) 'identity unchanged'; Assert-Equal '' (Inventory-Ok) }

    # ---- drift ----
    Add-Content (Join-Path $ch 'skills\machine-config\SKILL.md') 'hand edit'
    $sj = Settings; $sj.permissions.allow += 'Bash(hand-added:*)'; ($sj | ConvertTo-Json -Depth 30) | Set-Content (Join-Path $ch 'settings.json')
    Add-Content (Join-Path $mc 'skills\stream-status\SKILL.md') "`nsource change"
    $d1 = Install
    Test-Case 'drift stops the apply (exit 3), keeps a copy and queues the hand-added rule' {
        Assert-Equal 3 $d1.Code $d1.Out
        Assert-True (@(Get-ChildItem (Join-Path $ch 'machine-config') -Directory -Filter 'drift-*').Count -ge 1) 'no drift copy'
        $pend = Get-Content (Join-Path $ch 'machine-config.pending.json') -Raw | ConvertFrom-Json
        Assert-True (@($pend.items | Where-Object rule -eq 'Bash(hand-added:*)').Count -eq 1) 'rule not queued'
        Assert-Match (Get-Content (Join-Path $ch 'skills\machine-config\SKILL.md') -Raw) 'hand edit'
    }
    $d2 = Install @('-AcceptDrift')
    Test-Case '-AcceptDrift applies and the queue survives' {
        Assert-Equal 0 $d2.Code $d2.Out; Assert-Equal '' (Inventory-Ok)
        Assert-True (Test-Path (Join-Path $ch 'machine-config.pending.json')) 'queue lost'
    }

    # ---- 5.14 interrupted apply ----
    $before = Tree-Hash; $idB = (State).identity
    Add-Content (Join-Path $mc 'skills\stream-status\SKILL.md') "`nchange two"
    $env:AI_TEST_FAIL_BEFORE_STATE = '1'
    $f = Install
    Remove-Item Env:\AI_TEST_FAIL_BEFORE_STATE
    Test-Case 'a failure before the state record rolls back to the prior install' {
        Assert-True ($f.Code -ne 0) 'apply reported success'
        Assert-Equal $idB (State).identity
        Assert-Equal '' (Inventory-Ok)
        $now = Tree-Hash | Where-Object { $_ -notmatch '^\\(machine-config\\|settings\.json\.bak-)' }
        $was = $before | Where-Object { $_ -notmatch '^\\(machine-config\\|settings\.json\.bak-)' }
        Assert-Equal ($was -join "`n") ($now -join "`n")
    }
    # ---- 5.14 concurrency ----
    $jobs = 1..2 | ForEach-Object { Start-Job -ScriptBlock { param($i, $c, $f, $p) $env:PATH = $p; $env:AI_MACHINE_CONFIG = $c; & pwsh -NoProfile -File $i -ConfigPath $c -SkipMcp -ClaudeExeDir $f -Launch *>&1 | Out-Null; $LASTEXITCODE } -ArgumentList $inst, $cfg, $fake, $env:PATH }
    $codes = @($jobs | Wait-Job | Receive-Job); $jobs | Remove-Job
    Test-Case 'two launches at once end on one consistent revision' {
        Assert-Equal '0|0' ($codes -join '|')
        Assert-True ((State).identity -ne $idB) 'change not applied'
        Assert-Equal '' (Inventory-Ok)
        Assert-Match (Get-Content (Join-Path $ch 'skills\stream-status\SKILL.md') -Raw) 'change two'
    }

    # ---- 5.11 stale exports through ai ----
    $ai = Join-Path $ch 'bin\ai.ps1'
    $env:AI_VAULTWORKROOT = $vaultA
    Write-Profile -Vault $vaultB
    & pwsh -NoProfile -File $ai | Out-Null; $aiCode = $LASTEXITCODE
    Test-Case 'ai applies the changed profile and the child sees the new value, not the stale export' {
        Assert-Equal 0 $aiCode
        Assert-Equal $vaultB (Settings).env.AI_VAULTWORKROOT
        $m = Get-Content $env:AI_TEST_MARKER -Raw
        Assert-Match $m ([regex]::Escape("AI_VAULTWORKROOT=$vaultB"))
        Assert-Match $m 'AI_LAUNCH_REVISION=[0-9A-F]{64}'
        Assert-Match $m ([regex]::Escape("CLAUDE_CODE_TMPDIR=$(Join-Path $root 'scratch')"))
    }
    $env:AI_VAULTWORKROOT = $vaultB
    Write-Profile -Vault ''
    Remove-Item $env:AI_TEST_MARKER
    & pwsh -NoProfile -File $ai | Out-Null
    Test-Case 'a vault row made blank clears the export for the child' {
        Assert-True (-not (Settings).env.Contains('AI_VAULTWORKROOT')) 'settings still carry it'
        Assert-NoMatch (Get-Content $env:AI_TEST_MARKER -Raw) 'AI_VAULTWORKROOT='
    }
    # ---- 5.19 activation ----
    Write-Profile -Vault $vaultA -Access ($access + "`n| $vaultA | read, edit | |")
    $act = Install
    Test-Case 'an added folder and changed env are reported as needing a fresh launch' {
        Assert-Equal 0 $act.Code $act.Out
        Assert-Match $act.Out 'Active only after a fresh launch.*env.*additionalDirectories'
    }
    # ---- 5.17 source unavailable (settings-only mode) ----
    $filesBefore = (State).files
    Write-Profile -Vault $vaultB -Access ($access + "`n| $vaultA | read, edit | |") -Work (Join-Path $root 'nas-down\aiwork')
    $so = Install @('-Launch')
    Test-Case 'with the corpus unreachable the launch re-renders settings from the installed templates' {
        Assert-Equal 0 $so.Code $so.Out
        Assert-Match $so.Out 'Corpus not reachable.*installed templates'
        Assert-Equal $vaultB (Settings).env.AI_VAULTWORKROOT
    }
    Test-Case 'settings-only mode keeps hooks, skills, statusline and every runtime file' {
        Assert-Equal '' (Inventory-Ok)
        $s = State
        Assert-Equal (($filesBefore.Keys | Sort-Object) -join '|') (($s.files.Keys | Sort-Object) -join '|')
        Assert-True ((Settings).Contains('hooks') -and (Settings).Contains('statusLine')) 'hooks or statusLine missing from settings'
        Assert-True (Test-Path (Join-Path $ch 'skills\machine-config\SKILL.md')) 'skill removed'
    }
    Write-Profile -Vault $vaultA -Access ($access + "`n| $vaultA | read, edit | |")
    # ---- 5.12 rejected revocation ----
    Write-Profile -NoRepos -Access "| Path | Access | Note |`n|---|---|---|`n| {ScratchRoot} | read, edit | |"
    Remove-Item $env:AI_TEST_MARKER -ErrorAction SilentlyContinue
    $settingsBefore = (Get-FileHash (Join-Path $ch 'settings.json')).Hash
    & pwsh -NoProfile -File $ai *>&1 | Out-Null; $revCode = $LASTEXITCODE
    Test-Case 'removing a folder plus an invalid required key stops the launch; no session starts' {
        Assert-Equal 2 $revCode
        Assert-True (-not (Test-Path $env:AI_TEST_MARKER)) 'claude was started'
        Assert-Equal $settingsBefore (Get-FileHash (Join-Path $ch 'settings.json')).Hash
    }
    Test-Case 'the live ai shim was never touched' {
        Assert-Equal ($realShimHash -join '|') (@($realShim | ForEach-Object { (Get-FileHash $_).Hash }) -join '|')
    }
}
finally {
    $env:PATH = $oldPath
    foreach ($v in 'AI_MACHINE_CONFIG', 'AI_TEST_MARKER', 'AI_VAULTWORKROOT', 'AI_TEST_FAIL_BEFORE_STATE') { Remove-Item "Env:\$v" -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}
Complete-Tests
