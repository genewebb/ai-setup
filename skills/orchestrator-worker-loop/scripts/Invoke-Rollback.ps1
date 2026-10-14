<#
.SYNOPSIS
    Undoes an iteration's changes: restores tracked modifications AND (opt-in) deletes the new untracked files `git restore` cannot touch.

.DESCRIPTION
    Used by the orchestrator-worker-loop skill's failure protocol (SKILL.md § Failure handling
    step 3) and by the constraint gate's hard-fail path.

    WHY this exists: the old default `rollback-command: git restore -- {files_changed}` silently
    leaves behind every file the Executor CREATED. A rolled-back iteration that added
    src/Options/SmtpOptions.cs left that file on disk, so the next iteration's constraint gate
    flagged it and the "rollback" was a half-rollback.

    Two removal paths, both explicit:
      - tracked, modified  -> git restore -- <paths>
      - untracked, new     -> git clean -f -- <paths>   [requires -AllowClean]

    SAFETY: -Paths is required. `git clean` is NEVER invoked bare and NEVER recurses the whole
    repo; only the paths you pass, and never with -x or -d. Without -AllowClean, new files are
    reported but left alone. This script never runs commit, push, reset --hard, or a branch checkout.

.PARAMETER RootPath
    Absolute path to the repo root.

.PARAMETER Paths
    Explicit paths or globs (repo-relative) to roll back. Required unless -UseLatestCheckpoint.
    Typically the iteration's files-allowed list plus anything the constraint gate flagged.

.PARAMETER AllowClean
    Permit deletion of untracked files among -Paths via `git clean -f --`. Without this switch,
    untracked files are listed as "left in place" and the exit code reflects an incomplete rollback.

.PARAMETER StashSha
    Optional checkpoint SHA from New-Checkpoint.ps1. When supplied, the whole worktree state is
    restored with `git stash apply <sha>` INSTEAD of per-path restore.

.PARAMETER StatePath
    state.json path, used with -UseLatestCheckpoint. Defaults to <RootPath>\.loop\state.json.

.PARAMETER UseLatestCheckpoint
    Resolve StashSha from the most recent state.json checkpoint entry.

.PARAMETER WhatIf
    Print what would happen, change nothing.

.EXAMPLE
    pwsh -File Invoke-Rollback.ps1 -RootPath <repo> -Paths 'src/Services/EmailService.cs','src/Options/SmtpOptions.cs' -AllowClean

.EXAMPLE
    pwsh -File Invoke-Rollback.ps1 -RootPath <repo> -UseLatestCheckpoint

.NOTES
    Exit codes: 0 = rollback complete. 1 = partial (untracked files left because -AllowClean was
    absent, or a git command failed). 2 = script error / not a git repo.
#>
[CmdletBinding()]
param(
    # Position 0 declared so every other parameter is name-only.
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RootPath,

    [string[]]$Paths = @(),

    [switch]$AllowClean,

    [string]$StashSha,

    [string]$StatePath,

    [switch]$UseLatestCheckpoint,

    [switch]$WhatIf
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\LoopCommon.ps1"

if (-not (Test-Path -LiteralPath $RootPath)) {
    Write-LoopError "RootPath not found: $RootPath"
    exit 2
}
$RootPath = (Get-Item -LiteralPath $RootPath).FullName.TrimEnd('\', '/')

if (-not (Test-LoopGitRepo -RootPath $RootPath)) {
    Write-LoopError "Not a git repo: $RootPath - no automatic rollback available. Restore manually from your own backup."
    exit 2
}

# Per-path rollback does NOT need a commit: `git restore` reads the index by default and
# `git clean` needs no history. Only checkpoint-based restore requires a HEAD.
$hasHead = Test-LoopGitHasHead -RootPath $RootPath
if (-not $hasHead -and ($StashSha -or $UseLatestCheckpoint)) {
    Write-LoopError "Repo has no commits (no HEAD), so checkpoint restore is unavailable. Use -Paths for per-path rollback instead."
    exit 2
}

if (-not $StatePath) { $StatePath = Join-Path (Join-Path $RootPath '.loop') 'state.json' }

if ($UseLatestCheckpoint -and -not $StashSha) {
    $state = Read-LoopJson -Path $StatePath
    if ($state -and ($state.PSObject.Properties.Name -contains 'checkpoints') -and @($state.checkpoints).Count -gt 0) {
        $StashSha = (@($state.checkpoints) | Select-Object -Last 1).stash_sha
        Write-Host ("Using latest checkpoint: {0}" -f $StashSha) -ForegroundColor DarkGray
    } else {
        Write-LoopError "No checkpoints recorded in $StatePath - pass -Paths instead."
        exit 2
    }
}

# --- Whole-worktree restore from a checkpoint ---
if ($StashSha) {
    if ($WhatIf) {
        Write-Host ("[WHATIF] git -C {0} stash apply {1}" -f $RootPath, $StashSha)
        exit 0
    }
    $res = Invoke-LoopGit -RootPath $RootPath -Arguments @('stash', 'apply', $StashSha)
    if ($res.ExitCode -ne 0) {
        Write-Host ("[FAIL] git stash apply {0} failed:" -f $StashSha) -ForegroundColor Red
        $res.Lines | ForEach-Object { Write-Host ("       {0}" -f $_) -ForegroundColor Yellow }
        exit 1
    }
    Write-Host ("[OK] Worktree restored from checkpoint {0}" -f $StashSha) -ForegroundColor Green
    exit 0
}

# --- Per-path rollback ---
$pathList = @($Paths | ForEach-Object { "$_".Split(',') } | ForEach-Object { $_.Trim().Replace('\', '/') } | Where-Object { $_ })
if ($pathList.Count -eq 0) {
    Write-LoopError "-Paths is required (or use -UseLatestCheckpoint). Refusing to roll back the entire worktree implicitly."
    exit 2
}

$status = Invoke-LoopGit -RootPath $RootPath -Arguments @('status', '--porcelain', '-uall')
if ($status.ExitCode -ne 0) {
    Write-Error ("git status failed: {0}" -f ($status.Lines -join '; '))
    exit 2
}

$untrackedNow = New-Object System.Collections.Generic.HashSet[string]
$changedNow   = New-Object System.Collections.Generic.HashSet[string]
foreach ($line in $status.Lines) {
    if ([string]::IsNullOrWhiteSpace($line) -or $line.Length -lt 4) { continue }
    $code = $line.Substring(0, 2)
    $rest = $line.Substring(3).Trim()
    if ($rest -match '^(?<old>.+?)\s->\s(?<new>.+)$') { $rest = $Matches['new'] }
    $rel = $rest.Trim('"').Replace('\', '/')
    if ($code -eq '??') { [void]$untrackedNow.Add($rel) } else { [void]$changedNow.Add($rel) }
}

$matchers = @(New-LoopMatcher -Patterns $pathList)

$toRestore = @(@($changedNow)   | Where-Object { Test-LoopGlobMatch -RelativePath $_ -Matchers $matchers })
$toClean   = @(@($untrackedNow) | Where-Object { Test-LoopGlobMatch -RelativePath $_ -Matchers $matchers })

$partial = $false

if ($toRestore.Count -gt 0) {
    if ($WhatIf) {
        Write-Host ("[WHATIF] git restore -- {0}" -f ($toRestore -join ' '))
    } else {
        $res = Invoke-LoopGit -RootPath $RootPath -Arguments (@('restore', '--') + $toRestore)
        if ($res.ExitCode -ne 0) {
            Write-Host "[FAIL] git restore failed:" -ForegroundColor Red
            $res.Lines | ForEach-Object { Write-Host ("       {0}" -f $_) -ForegroundColor Yellow }
            $partial = $true
        } else {
            Write-Host ("[OK] Restored {0} tracked file(s):" -f $toRestore.Count) -ForegroundColor Green
            $toRestore | ForEach-Object { Write-Host ("       {0}" -f $_) -ForegroundColor DarkGreen }
        }
    }
} else {
    Write-Host "[OK] No tracked modifications among the given paths." -ForegroundColor DarkGray
}

if ($toClean.Count -gt 0) {
    if (-not $AllowClean) {
        Write-Host ("[WARN] {0} NEW untracked file(s) left in place (pass -AllowClean to delete):" -f $toClean.Count) -ForegroundColor Yellow
        $toClean | ForEach-Object { Write-Host ("       {0}" -f $_) -ForegroundColor Yellow }
        Write-Host "       Rollback is INCOMPLETE - the constraint gate will keep flagging these." -ForegroundColor Yellow
        $partial = $true
    } elseif ($WhatIf) {
        Write-Host ("[WHATIF] git clean -f -- {0}" -f ($toClean -join ' '))
    } else {
        $res = Invoke-LoopGit -RootPath $RootPath -Arguments (@('clean', '-f', '--') + $toClean)
        if ($res.ExitCode -ne 0) {
            Write-Host "[FAIL] git clean failed:" -ForegroundColor Red
            $res.Lines | ForEach-Object { Write-Host ("       {0}" -f $_) -ForegroundColor Yellow }
            $partial = $true
        } else {
            Write-Host ("[OK] Deleted {0} new untracked file(s):" -f $toClean.Count) -ForegroundColor Green
            $toClean | ForEach-Object { Write-Host ("       {0}" -f $_) -ForegroundColor DarkGreen }
        }
    }
}

if ($partial) { exit 1 } else { exit 0 }
