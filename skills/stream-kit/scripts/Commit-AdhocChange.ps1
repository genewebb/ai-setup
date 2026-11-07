# Lands one stream-adhoc change on the main tree: the ad-hoc role's only way onto main (owner ruling 2026-10-11,
# "Adhoc commits itself"). An ad-hoc change has no task row, no author grader and no suite run; its proof is that the
# solution compiles and the one targeted test the change added passes, both on main with the change applied.
#
# In ONE process, so the locks are held from the apply to the commit:
#   1. exports the worktree's change (tracked and new files) as .streams\adhoc\<Id>.patch;
#   2. takes .streams\integrate-patch.lock, so no Integrate-Patch run is between its own apply and commit, then
#      .streams\main-grader.lock, so no grader compiles main while it is rewritten (both waited for, -WaitSeconds);
#   3. refuses when a path the patch touches is already dirty on main, or the patch does not apply (rebase first);
#   4. applies it, builds the solution, runs `dotnet test <TestProject> --no-build --filter <TestFilter>`, then the
#      repo census (.streams\config.json "census") when the patch touches its paths;
#   5. PASS: commits exactly the patch's paths as "<Id>: <Title>" and pushes like Integrate-Patch (git policy rows
#      from the machine profile, fail closed); FAIL: reverses the patch, so main never keeps an unproven change.
# A filter that matches no test is a FAIL: a change with no test of its own is not proven.
# Outcome line (one of): COMMITTED <Id> <sha> | REVERSED <Id> (build|test|census failed; log <path>) | REBASE <Id> |
# DIRTY <Id> <paths> | NOTHING <Id> | LANDED <Id> <commit> (HEAD already holds it; 'Landed:' added to the request file) | ADHOC-BUSY <Id> (<lock> held by <holder>) | COMMIT SKIPPED <Id> (git policy).
# Exit 0 committed (or -NoCommit applied), 1 reversed, 2 nothing to land, 3 refused (rebase / dirty), 4 busy.
# STREAM_ADHOC_DOTNET replaces the dotnet executable (the self-test's stub).
param(
    [Parameter(Mandatory)] [string] $Repo,
    [Parameter(Mandatory)] [string] $Session,
    [Parameter(Mandatory)] [ValidatePattern('^ADHOC-\d{8}-\d+$')] [string] $Id,
    [Parameter(Mandatory)] [string] $Worktree,
    [Parameter(Mandatory)] [string] $Title,
    [Parameter(Mandatory)] [string] $TestProject,
    [Parameter(Mandatory)] [string] $TestFilter,
    [string] $Solution = '',
    [int] $WaitSeconds = 1800,
    [string] $PushRef = $(if ($null -ne $env:STREAM_PUSH_REF) { $env:STREAM_PUSH_REF } else { '<profile>' }),
    [switch] $NoCommit
)
. "$PSScriptRoot\lib\Streams.ps1"
$Repo = (Resolve-Path $Repo).Path
$Worktree = (Resolve-Path $Worktree).Path
$P = Get-StreamPaths $Repo
$dotnet = if ($env:STREAM_ADHOC_DOTNET) { $env:STREAM_ADHOC_DOTNET } else { 'dotnet' }
$adhocDir = Join-Path $P.Root 'adhoc'
$logDir = Join-Path $P.Root 'logs\adhoc'
New-Item -ItemType Directory -Path $adhocDir, $logDir -Force | Out-Null

# The repo's git policy from the machine profile: { Commit; Push; Why }. Any failure to read it denies both.
function Get-AdhocGitPolicy([string] $Repo) {
    try {
        $lib = @((Join-Path $PSScriptRoot '..\..\..\lib\MachineConfig.psm1'), (Join-Path $HOME '.claude\lib\MachineConfig.psm1')) |
            Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $lib) { throw 'MachineConfig.psm1 not found' }
        Import-Module $lib -Force -DisableNameChecking
        $prof = Get-AIMachineProfile
        $pol = Get-AIGitPolicy -Path $Repo -Profile $prof
        $why = if ($pol.Row) { "Git policy row for $($pol.RepoRoot) in $($prof.Path)" } else { "no Git policy row for $Repo in $($prof.Path)" }
        [pscustomobject]@{ Commit = $pol.Commit; Push = $pol.Push; PushRef = $pol.PushRef; Why = $why }
    } catch {
        [pscustomobject]@{ Commit = $false; Push = $false; PushRef = ''; Why = "machine profile could not be read: $(("$_" -split "`n")[0])" }
    }
}

# 1. Export. Staging in the ad-hoc worktree's own index makes new files part of the diff.
[void](Invoke-Git $Worktree @('add', '-A'))
$patch = Join-Path $adhocDir "$Id.patch"
# git writes the patch file itself (--output), byte for byte. Capturing its stdout instead decodes it through
# [Console]::OutputEncoding (ibm437 under pwsh -NoProfile on SMVMTR1), so every non-ASCII character came out mangled:
# a patch deleting an em dash failed `git apply --check` (REBASE for ever) and one adding it would commit mojibake
# (kit item IN-20261012180815-5151). core.quotePath=false keeps a non-ASCII file name raw in the headers read below.
& git -C $Worktree -c core.quotePath=false diff --cached --binary --output=$patch HEAD
if ($LASTEXITCODE -ne 0) { throw "git diff failed in $Worktree" }
if ((Get-Item -LiteralPath $patch).Length -eq 0) { Remove-Item -LiteralPath $patch; "NOTHING $Id (no change in $Worktree)"; exit 2 }
$diff = [IO.File]::ReadAllLines($patch, [Text.UTF8Encoding]::new($false))
$paths = @($diff | ForEach-Object { if ($_ -match '^diff --git a/(.+) b/(.+)$') { $Matches[1]; $Matches[2] } } | Sort-Object -Unique)

# 2. Locks: the drain lock first (same handle shape as Integrate-Patch: FileShare.None, DeleteOnClose), then main.
$drain = $null; $main = $null; $applied = $false
$deadline = (Get-Date).AddSeconds($WaitSeconds)
while (-not $drain) {
    try {
        $drain = [IO.FileStream]::new((Join-Path $P.Root 'integrate-patch.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None, 4096, [IO.FileOptions]::DeleteOnClose)
        $b = [Text.Encoding]::UTF8.GetBytes("adhoc $Id $Session pid $PID at $(Get-Now)"); $drain.SetLength(0); $drain.Write($b, 0, $b.Length); $drain.Flush()
    } catch [IO.IOException] {
        if ((Get-Date) -gt $deadline) { "ADHOC-BUSY $Id (integrate-patch.lock held by an Integrate-Patch run)"; exit 4 }
        Start-Sleep -Seconds 5
    }
}
try {
    $left = [int][math]::Max(1, ($deadline - (Get-Date)).TotalSeconds)
    $main = Enter-MainTreeLock $P "adhoc $Id $Session" $left
    if (-not $main) { "ADHOC-BUSY $Id (main-grader.lock held by $(Get-MainTreeLockHolder $P))"; exit 4 }

    # 3. Refusals: never mix with owner or integrator dirt on the same paths, never force a stale patch.
    $dirty = @(& git -C $Repo status --porcelain -- @paths)
    if ($dirty.Count) { "DIRTY $Id $(($dirty | ForEach-Object { $_.Substring(3) }) -join ', ')"; exit 3 }
    & git -C $Repo apply --check --binary --whitespace=nowarn $patch 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        # The paths are clean on main, so a clean reverse check means HEAD already holds the change: someone else
        # committed it under another subject. The request file then carries 'Landed: <commit>', which the status
        # page's left-to-plan count reads in place of an '<Id>:' subject.
        & git -C $Repo apply --reverse --check --binary --whitespace=nowarn $patch 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            $by = (Invoke-Git $Repo (@('log', '-1', '--format=%H', 'HEAD', '--') + $paths)) | Select-Object -First 1
            $req = Join-Path $adhocDir "$Id.md"
            $line = "Landed: $by"
            $has = (Test-Path -LiteralPath $req) -and (@(Get-Content -LiteralPath $req) -contains $line)
            if (-not $has) { Add-Content -LiteralPath $req -Value $line -Encoding utf8 }
            Add-Decision $P $Session "adhoc $Id already on HEAD in $by (committed by someone else); request file records Landed"
            "LANDED $Id $by (already on HEAD; recorded in $req)"; exit 0
        }
        "REBASE $Id (patch does not apply to main HEAD; rebase the worktree onto main and run again)"; exit 3
    }

    # 4. Apply, build, targeted test.
    [void](Invoke-Git $Repo @('apply', '--binary', '--whitespace=nowarn', $patch))
    $applied = $true
    if (-not $Solution) { $Solution = @(Get-ChildItem -LiteralPath $Repo -File | Where-Object { $_.Extension -in '.sln', '.slnx' } | Select-Object -First 1 -ExpandProperty Name) | Select-Object -First 1 }
    $buildLog = Join-Path $logDir "$Id.build.txt"
    $testLog = Join-Path $logDir "$Id.test.txt"
    $buildTarget = if ($Solution) { Join-Path $Repo $Solution } else { $Repo }
    & $dotnet build $buildTarget -nologo 2>&1 | Set-Content -LiteralPath $buildLog -Encoding utf8
    $buildExit = $LASTEXITCODE
    $failed = $null
    if ($buildExit -ne 0) { $failed = "build failed; log $buildLog" }
    else {
        & $dotnet test (Join-Path $Repo $TestProject) --no-build --filter $TestFilter -nologo 2>&1 | Set-Content -LiteralPath $testLog -Encoding utf8
        $testExit = $LASTEXITCODE
        $testText = Get-Content -LiteralPath $testLog -Raw
        if ($testExit -ne 0) { $failed = "test failed; log $testLog" }
        elseif ($testText -match 'No test matches the given testcase filter|No test is available') { $failed = "test failed: the filter '$TestFilter' matched no test; log $testLog" }
    }
    # 4b. The repo census (.streams\config.json "census", the script Invoke-Grader runs for every task patch) runs on
    # main when the patch touches its paths, so an ad-hoc change meets the same repo-wide rules as a built one instead
    # of reaching them only at the nightly suite. A FAIL id in .streams\suites\census-baseline.json is main's own red.
    $censusCfg = (Get-StreamConfig $P)['census']
    if (-not $failed -and $censusCfg -is [Collections.IDictionary] -and $censusCfg['script']) {
        $cs = [string]$censusCfg['script']
        if (-not [IO.Path]::IsPathRooted($cs)) { $cs = Join-Path $Repo $cs }
        $rx = if ($censusCfg['paths']) { [string]$censusCfg['paths'] } else { '.' }
        if ((Test-Path -LiteralPath $cs) -and @($paths | Where-Object { ($_ -replace '\\', '/') -match $rx }).Count) {
            $censusLog = Join-Path $logDir "$Id.census.txt"
            & pwsh -NoProfile -NonInteractive -File $cs -Root $Repo 2>&1 | Set-Content -LiteralPath $censusLog -Encoding utf8
            $censusExit = $LASTEXITCODE
            if ($censusExit -ne 0) {
                $known = @()
                $bf = Join-Path $P.Root 'suites\census-baseline.json'
                if (Test-Path -LiteralPath $bf) { try { $known = @((Get-Content -LiteralPath $bf -Raw | ConvertFrom-Json -AsHashtable)['fails']) } catch { $known = @() } }
                $lines = @(Get-Content -LiteralPath $censusLog)
                $newFail = @($lines | Where-Object { $_ -match '^FAIL\s+([^\s:]+)' -and $known -notcontains $Matches[1] } | ForEach-Object { ($_ -split '[\s:]+')[1] })
                $anyFail = @($lines | Where-Object { $_ -match '^FAIL\s+\S' })
                if ($newFail.Count -or -not $anyFail.Count) {
                    $failed = "census failed ($(if ($newFail.Count) { $newFail -join ', ' } else { "exit $censusExit" })); log $censusLog"
                }
            }
        }
    }
    if ($failed) {
        [void](Invoke-Git $Repo @('apply', '-R', '--binary', '--whitespace=nowarn', $patch))
        $applied = $false
        & git -C $Repo update-index -q --refresh 2>&1 | Out-Null
        Add-Decision $P $Session "adhoc $Id reversed on main: $failed"
        "REVERSED $Id ($failed)"; exit 1
    }

    # 5. Commit exactly the patch's paths; other dirty or staged files stay out.
    if ($NoCommit) { $applied = $false; "APPLIED $Id (build and test PASS; left uncommitted, -NoCommit)"; exit 0 }
    $gitPolicy = Get-AdhocGitPolicy $Repo
    if ($PushRef -eq '<profile>') { $PushRef = Resolve-StreamPushRef $Repo $gitPolicy.PushRef }
    if (-not $gitPolicy.Commit) {
        $applied = $false
        Add-Decision $P $Session "adhoc $Id applied on main, commit skipped: Commit is not allowed ($($gitPolicy.Why))"
        "COMMIT SKIPPED $Id (git policy: $($gitPolicy.Why))"; exit 0
    }
    $staleLock = Clear-StaleGitIndexLock $P $Session $Repo; if ($staleLock) { "STALE-INDEX-LOCK removed $staleLock" }
    [void](Invoke-Git $Repo (@('add', '-A', '--') + $paths))
    [void](Invoke-Git $Repo (@('commit', '-q', '-m', "${Id}: $Title", '-m', "Committed by stream-adhoc ($Session); build and targeted test ($TestFilter) PASS on main.", '-m', 'Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>', '--') + $paths))
    $applied = $false
    $sha = (Invoke-Git $Repo @('rev-parse', '--short', 'HEAD')) | Select-Object -First 1
    Add-Decision $P $Session "adhoc $Id committed as $sha"
    "COMMITTED $Id $sha"
    $remotes = @(& git -C $Repo remote 2>$null)
    if ($PushRef -and ($remotes -contains 'origin') -and -not $gitPolicy.Push) {
        "PUSH SKIPPED $Id $sha (git policy: $($gitPolicy.Why))"
    } elseif ($PushRef -and ($remotes -contains 'origin')) {
        try { [void](Invoke-Git $Repo @('push', 'origin', "HEAD:$PushRef")); "PUSHED $Id $sha -> $PushRef" }
        catch { Add-Decision $P $Session "push of adhoc $Id $sha failed (commit stands): $($_.Exception.Message)"; "PUSH FAILED $Id $sha (committed)" }
    }
    exit 0
} catch {
    # Any throw between the apply and the commit takes the change back off main.
    if ($applied) {
        & git -C $Repo apply -R --binary --whitespace=nowarn $patch 2>&1 | Out-Null
        & git -C $Repo update-index -q --refresh 2>&1 | Out-Null
        Add-Decision $P $Session "adhoc $Id threw after the apply; patch reversed: $(("$_" -split "`n")[0])"
    }
    throw
} finally {
    if ($main) { $main.Dispose() }
    if ($drain) { $drain.Dispose() }
}
