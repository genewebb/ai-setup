#requires -Version 7
<#
.SYNOPSIS
    First machine-config rollout on a machine whose corpus copy and profile were staged from the laptop
    (HowToInstall.md in the work vault). Every machine value comes from this machine's profile.

.DESCRIPTION
    Steps: preflight, backup, -Check, -WhatIf, your y, live apply, git worktree repair, self-tests, smoke.
    Everything is logged to {ScratchRoot}\machine-config-rollout\report-<stamp>.txt (the path is printed at the end).
    Run it from {AIWorkRoot}\setup in a plain pwsh as the user whose Claude config is being converted, with no
    Claude session of that user running.

.PARAMETER Yes
    Skip the prompts (the backup prompt and the "Apply live now?" prompt).
.PARAMETER StopAfterWhatIf
    Dry run: preflight, backup, -Check and -WhatIf only. Changes nothing in the Claude home.
.PARAMETER SmokeOnly
    Re-run only the self-tests and the smoke checks after an earlier apply. Changes nothing.
#>
[CmdletBinding()]
param([switch]$Yes, [switch]$StopAfterWhatIf, [switch]$SmokeOnly)
$ErrorActionPreference = 'Stop'
$corpus = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
Import-Module (Join-Path $corpus 'lib\MachineConfig.psm1') -Force -DisableNameChecking
$prof = Get-AIMachineProfile
$k = $prof.Keys
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$here = Join-Path $k['ScratchRoot'] 'machine-config-rollout'
New-Item -ItemType Directory -Force $here | Out-Null
$log = Join-Path $here "report-$stamp.txt"
Start-Transcript -Path $log | Out-Null
$ch = $k['ClaudeHome']
$lr = $k['SkillsLinkRoot']
$inst = Join-Path $corpus 'setup\Install-AIMachine.ps1'
$fails = [System.Collections.Generic.List[string]]::new()
function Step([string]$t) { Write-Host "`n=== $t ===" -ForegroundColor Cyan }
# Child pwsh output does not reach the transcript on its own; pass it through so the report holds it.
function Invoke-Child([string[]]$a) { & pwsh -NoProfile -File @a *>&1 | ForEach-Object { "$_" } | Write-Host; return $LASTEXITCODE }
try {
    Step 'Preflight'
    "user=$env:USERNAME host=$env:COMPUTERNAME profile=$($prof.Path) corpus=$corpus"
    if (-not (Test-Path (Join-Path $corpus 'ai-manifest.json'))) { throw "No ai-manifest.json in ${corpus}: run this from the staged corpus copy." }
    if ((Resolve-Path $k['AIWorkRoot']).Path.TrimEnd('\') -ne $corpus.TrimEnd('\')) { Write-Host "[WARNING] AIWorkRoot is $($k['AIWorkRoot']) but this script runs from $corpus." -ForegroundColor Yellow }
    $problems = @(Test-AIMachineProfile -Profile $prof)
    foreach ($p in $problems | Where-Object Level -ne 'info') { "[$($p.Level.ToUpperInvariant())] $($p.Message)" }
    if (@($problems | Where-Object Level -eq 'error').Count) { throw "The profile has errors (above). Fix $($prof.Path) on the laptop, re-stage, run again." }
    if ($lr) { if (-not (Test-Path (Join-Path $lr 'skills'))) { throw "SkillsLinkRoot $lr is not reachable from this console." }; "SkillsLinkRoot reachable: $lr" }
    "claude: $((& claude --version) 2>&1 | Select-Object -First 1)"
    if (-not $SmokeOnly) {
        # Only this user's Claude sessions read the Claude home the apply rewrites.
        $cl = @(Get-CimInstance Win32_Process -Filter "Name='claude.exe'" | ForEach-Object {
                $ow = Invoke-CimMethod -InputObject $_ -MethodName GetOwner
                [pscustomobject]@{ PID = $_.ProcessId; Owner = "$($ow.Domain)\$($ow.User)"; Path = $_.ExecutablePath }
            })
        $mine = @($cl | Where-Object { $_.Owner -like "*\$env:USERNAME" })
        "claude processes: $($cl.Count) total, $($mine.Count) owned by $env:USERNAME"
        if ($mine.Count -and -not $StopAfterWhatIf) { throw "Claude of $env:USERNAME is running (PIDs $(($mine.PID) -join ', ')). Exit those sessions, then run again." }

        Step 'Backup skills/agents/commands'
        $bk = Join-Path $k['ArchiveRoot'] "ai-config-$(Get-Date -Format 'yyyy-MM-dd')\pre-rollout-$stamp\claude"
        foreach ($d in 'skills', 'agents', 'commands') {
            # The link tree first (what links point at), then the real local items on top (/XJ: do not follow links).
            if ($lr -and (Test-Path (Join-Path $lr $d))) { robocopy (Join-Path $lr $d) (Join-Path $bk $d) /E /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null }
            if (Test-Path (Join-Path $ch $d)) { robocopy (Join-Path $ch $d) (Join-Path $bk $d) /E /XJ /R:1 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null }
            "backup $d : $(@(Get-ChildItem (Join-Path $bk $d) -Recurse -File -Force -ErrorAction SilentlyContinue).Count) files"
        }
        "backup: $bk"

        Step 'Check'
        [void](Invoke-Child @($inst, '-CorpusRoot', $corpus, '-Check'))
        Step 'WhatIf'
        if (Invoke-Child @($inst, '-CorpusRoot', $corpus, '-WhatIf')) { throw 'WhatIf failed (above).' }
        if ($StopAfterWhatIf) { 'Dry run: stopped after -WhatIf. Nothing changed.'; return }
        if (-not $Yes) {
            $a = Read-Host 'Apply live now? Check the link-tree writes and removals above first. Type y to continue'
            if ($a -ne 'y') { throw 'Stopped before the live apply (nothing changed).' }
        }
        Step 'Live apply'
        if (Invoke-Child @($inst, '-CorpusRoot', $corpus)) { throw 'Apply failed (above); the previous state was restored.' }

        # Worktree records hold absolute paths; after a move between drives they point at the old place.
        foreach ($g in @($prof.GitPolicy | Where-Object { $_.Worktrees -eq 'yes' -and $_.Repo -and (Test-Path $_.Repo) })) {
            Step "Worktrees: $($g.Repo)"
            git -C $g.Repo worktree list
            $wt = $k['WorktreesRoot']
            $dirs = @(if (Test-Path $wt) { Get-ChildItem $wt -Directory | ForEach-Object { if (Test-Path (Join-Path $_.FullName '.git') -PathType Leaf) { $_.FullName } else { Get-ChildItem $_.FullName -Directory | Where-Object { Test-Path (Join-Path $_.FullName '.git') -PathType Leaf } | ForEach-Object FullName } } })
            "worktree folders found: $($dirs.Count)"
            if ($dirs.Count) { git -C $g.Repo worktree repair @dirs }
            git -C $g.Repo worktree list
            "prunable after repair: $(@(git -C $g.Repo worktree list --porcelain | Select-String '^prunable').Count) (git worktree prune removes only records whose folder is gone)"
        }
    }

    Step 'Self-tests'
    $tests = @(
        @{ N = 'hooks'; F = "$ch\scripts\tests\run-hook-tests.ps1"; P = 'all \d+ passed' },
        @{ N = 'stream-kit'; F = "$ch\skills\stream-kit\scripts\Test-StreamKit.ps1"; P = 'RESULT fails=0' },
        @{ N = 'stream-kit recovery'; F = "$ch\skills\stream-kit\scripts\Test-StreamKitRecovery.ps1"; P = 'RESULT fails=0' },
        @{ N = 'MachineConfig'; F = "$corpus\setup\tests\MachineConfig.Tests.ps1"; P = ' 0 failed' },
        @{ N = 'GitGuard'; F = "$corpus\setup\tests\GitGuard.Tests.ps1"; P = ' 0 failed' },
        @{ N = 'NestedLinks'; F = "$corpus\setup\tests\NestedLinks.Tests.ps1"; P = ' 0 failed' },
        @{ N = 'LinkRoot'; F = "$corpus\setup\tests\LinkRoot.Tests.ps1"; P = ' 0 failed' }
    )
    foreach ($t in $tests) {
        if (-not (Test-Path $t.F)) { "$($t.N): SKIPPED (not installed here)"; continue }
        $o = & pwsh -NoProfile -File $t.F *>&1 | Out-String
        $ok = $o -match $t.P
        "$($t.N): $(if ($ok) { 'PASS' } else { 'FAIL' })"
        if (-not $ok) { $fails.Add("test $($t.N)"); ($o -split "`n" | Select-String 'FAIL' | Select-Object -First 10) | ForEach-Object { "   $_" } }
    }

    Step 'Smoke'
    [void](Invoke-Child @((Join-Path $ch 'bin\Install-AIMachine.ps1'), '-Check'))
    function Invoke-Hook([string]$Id, [string]$Json) {
        $psi = [Diagnostics.ProcessStartInfo]::new('pwsh', "-NoProfile -File `"$ch\scripts\hook-dispatch.ps1`" -Id $Id")
        $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true
        $p = [Diagnostics.Process]::Start($psi); $p.StandardInput.Write($Json); $p.StandardInput.Close(); $o = $p.StandardOutput.ReadToEnd(); [void]$p.WaitForExit(60000); $o.Trim()
    }
    function Bash-Json([string]$c, [string]$cwd) { @{ session_id = 'smoke'; hook_event_name = 'PreToolUse'; cwd = $cwd; tool_name = 'Bash'; tool_input = @{ command = $c } } | ConvertTo-Json -Compress -Depth 5 }
    foreach ($g in @($prof.GitPolicy | Where-Object { $_.Repo -and (Test-Path $_.Repo) })) {
        $push = Invoke-Hook 'git-guard' (Bash-Json 'git push origin HEAD' $g.Repo)
        $want = if ($g.Push -eq 'yes') { 'allowed' } else { 'deny' }
        $got = if ($push -match 'deny') { 'deny' } elseif (-not $push) { 'allowed' } else { "[$push]" }
        "git push in $($g.Repo): want $want, got $got"; if ($got -ne $want) { $fails.Add("git-guard push $($g.Repo)") }
    }
    # A real repo with no git-policy row (git-guard skips non-repos: git itself refuses there).
    $scratchRepo = Join-Path $k['ScratchRoot'] "git-guard-smoke-$stamp"; git init -q $scratchRepo
    $other = Invoke-Hook 'git-guard' (Bash-Json 'git commit -m x' $scratchRepo)
    "git commit in a repo with no policy row (want deny): $(if ($other -match 'deny') { 'deny' } else { "[$other]" })"
    if ($other -notmatch 'deny') { $fails.Add('git-guard commit outside policy not denied') }
    [IO.Directory]::Delete($scratchRepo, $true)
    'machine-paths:'; Invoke-Hook 'machine-paths' (@{ session_id = 'smoke'; hook_event_name = 'SessionStart'; cwd = $k['ScratchRoot']; source = 'startup' } | ConvertTo-Json -Compress)
    "skills with SKILL.md: $(@(Get-ChildItem "$ch\skills" -Directory | Where-Object { Test-Path "$($_.FullName)\SKILL.md" }).Count)"
    if ($lr) {
        foreach ($d in 'skills', 'agents', 'commands') {
            $all = @(Get-ChildItem "$ch\$d" -Force)
            $ln = @($all | Where-Object { $_.LinkType -eq 'SymbolicLink' -and [string]$_.Target -like "$lr\*" })
            "$d : $($ln.Count) of $($all.Count) are links into $lr"
        }
    }
    $s = Get-Content "$ch\settings.json" -Raw | ConvertFrom-Json
    "CLAUDE_CODE_TMPDIR=$($s.env.CLAUDE_CODE_TMPDIR) TEMP=$($s.env.TEMP) statusLine=$($s.statusLine.command)"
    $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User')
    "ai: $((Get-Command ai -ErrorAction SilentlyContinue).Source)"
    & ai --version 2>&1 | Select-Object -Last 1
}
catch { $fails.Add("STOPPED: $_"); Write-Host "STOPPED: $_" -ForegroundColor Red }
finally {
    Step 'Result'
    if ($fails.Count) { "FAILURES ($($fails.Count)):"; $fails | ForEach-Object { "  $_" } } else { 'ALL GREEN' }
    Stop-Transcript | Out-Null
    Write-Host "Report: $log" -ForegroundColor Yellow
}
