# Runs a task's grader against a tree (the main tree or a worktree), saves the output to
# .streams\logs\<task>.grader.<label>.txt, prints the PASS/FAIL lines and exits with the grader's code.
# -ExpectRed turns it into the RED check: exit 0 only when the grader fails AND it actually produced clause
# verdicts. A grader that never ran - a PowerShell parse error, a missing file - also exits non-zero while
# printing no PASS/FAIL line at all, and used to pass the RED check: the author released a task whose grader
# cannot run and only the builder found out (kit item IN-20260929170537-8760). No verdict line is
# NO-VERDICT, exit 6, never RED.
# The grader sees $env:STREAM_TASK and $env:STREAM_SINCE_UTC (see Get-TaskSince): a grader that demands fresh evidence
# compares against the kit's time, never a file time. The log ends with "GRADER sha <hash> since <time>", which the
# integrator uses to tell a grader defect from a code defect.
# A run against the MAIN tree (-Root is the repo) holds .streams\main-grader.lock for its whole length, so author RED
# checks and the integrator never build main at the same time (concurrent builds lock obj\ and fail with CS2012). The
# lock file is opened DeleteOnClose: a crashed holder frees it. A waiter gives up after 60 minutes
# (STREAM_MAIN_LOCK_WAIT_SECONDS overrides) with MAIN-GRADER-BUSY, exit 5. Worktree runs never wait.
# -BeatSession <session> beats every 30 seconds (STREAM_BEAT_SECONDS overrides) while the grader runs, so long work
# does not look abandoned: .streams\integrator.lock for the integrator, and with -BeatTask <id> that task's claim for a
# builder (the watchdog breaks a build claim at 45 minutes, and a grader plus a blind verifier can run longer than
# that). Each beat stops as soon as the lock or the claim is no longer that session's.
# TWO SCRIPTS CAN GRADE A TASK (owner rulings 2026-10-02, kit items IN-20261002160453-ce2a and IN-20261002160643-741d):
# the BUILDER's check (artifacts.check, .streams\checks\<task>.ps1: one test per acceptance clause plus the existing
# tests the change can break) and the AUTHOR's grader (artifacts.grader), which a row authored before the rulings keeps
# as one more check. By default both run, check first, into ONE log; the run fails when either fails, and the identity
# line names both hashes as <check>+<grader>. -Only grader or -Only check runs one of them: the builder's RED on a fresh
# worktree, before any edit, is -Only grader. NO-GRADER (exit 4) means neither exists.
# -Repo, -Task and -Root are required but not [Parameter(Mandatory)]: a missing mandatory parameter makes pwsh PROMPT
# for it, and a run started detached (Start-Process -WindowStyle Hidden) then waits on that prompt for ever, with no
# grader and no beat. On 2026-10-09 a builder left out -Repo; the run sat 45 minutes and the watchdog broke the live
# claim (kit item IN-20261009233639-e3a7). A missing one is MISSING-PARAM, exit 7, at once.
# A beating run (-BeatSession) has a wall-clock limit, -TimeoutSeconds (STREAM_GRADER_TIMEOUT_SECONDS, else 3600). Past
# it the child grader and its whole process tree are ended, the log gets a GRADER-TIMEOUT line and the run exits 8, never
# RED. The beat is what kept a hung run alive: on 2026-10-10 the runner's pre-stage grade of G4.T131 sat 2.4 hours on a
# node child (`npx playwright test --list` in a worktree with no node_modules) while the beat kept the claim fresh, so
# the watchdog never freed the row (kit item IN-20261010031237-259d). The child also runs -NonInteractive with stdin
# read from an empty file, so a prompt for input fails or reads end-of-input instead of waiting.
param(
    [string] $Repo = '',
    [string] $Task = '',
    [string] $Root = '',
    [string] $Label = 'run',
    [string] $BeatSession = '',
    [string] $BeatTask = '',
    [ValidateSet('', 'grader', 'check')] [string] $Only = '',
    [int] $TimeoutSeconds = 0,
    [switch] $ExpectRed
)
$missing = @(foreach ($n in 'Repo', 'Task', 'Root') { if (-not (Get-Variable $n -ValueOnly)) { "-$n" } })
if ($missing.Count) { "MISSING-PARAM $($missing -join ' ') (Invoke-Grader.ps1 needs -Repo, -Task and -Root)"; exit 7 }
. "$PSScriptRoot\lib\Streams.ps1"
. "$PSScriptRoot\lib\Recovery.ps1"
$Repo = (Resolve-Path $Repo).Path
$P = Get-StreamPaths $Repo
$doc = Read-Tasks $P
$t = Get-Task $doc $Task
$scripts = [Collections.Generic.List[string]]::new()
foreach ($kind in @('check', 'grader')) {
    if ($Only -and $Only -ne $kind) { continue }
    $s = Get-Field $t 'artifacts', $kind
    if (-not $s) { continue }
    if (-not [IO.Path]::IsPathRooted($s)) { $s = Join-Path $Repo $s }
    $scripts.Add($s)
}
if (-not $scripts.Count) { "NO-GRADER $Task$(if ($Only) { " (no $Only)" } else { ' (neither a check nor a grader)' })"; exit 4 }
$log = Join-Path $P.Logs "$Task.grader.$Label.txt"
if (Test-Path -LiteralPath $log) { Remove-Item -LiteralPath $log -Force }
$since = Get-TaskSince $doc $t
$env:STREAM_TASK = $Task
$env:STREAM_SINCE_UTC = $since
$mainLock = $null
if ((Resolve-Path $Root).Path.TrimEnd('\') -eq $Repo.TrimEnd('\')) {
    # One writer on main: Enter-MainTreeLock is the same lock the integrator takes around its apply.
    $mainLock = Enter-MainTreeLock $P "$Task $Label"
    if (-not $mainLock) { "MAIN-GRADER-BUSY $Task (held by: $(Get-MainTreeLockHolder $P))"; exit 5 }
}
$code = 0
$proc = $null
$timedOut = ''
if ($TimeoutSeconds -le 0) { $TimeoutSeconds = if ($env:STREAM_GRADER_TIMEOUT_SECONDS) { [int]$env:STREAM_GRADER_TIMEOUT_SECONDS } else { 3600 } }
try {
    foreach ($g in $scripts) {
        $part = "$log.part"
        if ($BeatSession) {
            # A child process, so this session can beat the integrator lock while the grader runs.
            $err = "$log.err"
            $in = "$log.in"
            [IO.File]::WriteAllText($in, '')
            $proc = Start-Process -FilePath 'pwsh' -ArgumentList @('-NoProfile', '-NonInteractive', '-File', $g, '-Root', $Root) -PassThru -NoNewWindow -RedirectStandardOutput $part -RedirectStandardError $err -RedirectStandardInput $in
            $every = if ($env:STREAM_BEAT_SECONDS) { [int]$env:STREAM_BEAT_SECONDS } else { 30 }
            $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
            while (-not $proc.HasExited) {
                $left = ($deadline - [DateTime]::UtcNow).TotalMilliseconds
                if ($left -le 0) {
                    try { $proc.Kill($true) } catch { }
                    [void]$proc.WaitForExit(10000)
                    $timedOut = "GRADER-TIMEOUT $Task $(Split-Path -Leaf $g) ran past $TimeoutSeconds s and was ended with its process tree (pid $($proc.Id)); a hung child, not a verdict"
                    break
                }
                if ($proc.WaitForExit([int][Math]::Min($every * 1000, $left))) { break }
                # A beat that cannot get the tasks.json lock (another session holds it past the 15-second wait) is
                # skipped, never fatal: the throw used to end this script and orphan the child grader, which kept the
                # .part log open so the next run failed (kit item IN-20261003171122-a58c). The next tick beats again.
                try {
                    if ($BeatTask) { [void](Update-ClaimBeat $P $BeatSession $BeatTask) } else { [void](Update-IntegratorBeat $P $BeatSession) }
                } catch { Write-Warning "BEAT-SKIPPED $Task ${BeatSession}: $(("$_" -split "`n")[0])" }
            }
            $one = $proc.ExitCode
            # The child's redirect handles can still be closing when it reports its exit, so these steps retry a
            # sharing violation (Invoke-IoRetry, kit item IN-20261004143050-5968).
            if ((Test-Path $err) -and (Get-Item $err).Length -gt 0) { Invoke-IoRetry { [IO.File]::AppendAllText($part, [IO.File]::ReadAllText($err) + [Environment]::NewLine) } }
            if (Test-Path $err) { try { Invoke-IoRetry { [IO.File]::Delete($err) } } catch { } }
            if (Test-Path $in) { try { Invoke-IoRetry { [IO.File]::Delete($in) } } catch { } }
            if ($timedOut) { Invoke-IoRetry { [IO.File]::AppendAllText($part, $timedOut + [Environment]::NewLine) }; $one = 8 }
        } else {
            & pwsh -NoProfile -File $g -Root $Root *> $part
            $one = $LASTEXITCODE
        }
        if ($scripts.Count -gt 1) { Add-LineTo $log "== $(Split-Path -Leaf (Split-Path $g)) $(Split-Path -Leaf $g) exit $one" }
        if (Test-Path -LiteralPath $part) {
            Invoke-IoRetry { [IO.File]::AppendAllText($log, [IO.File]::ReadAllText($part) + [Environment]::NewLine) }
            Invoke-IoRetry { [IO.File]::Delete($part) }
        }
        if ($one -ne 0 -and $code -eq 0) { $code = $one }
        if ($timedOut) { $code = 8; break }
    }
} finally {
    # Any other way out of this script (a throw, Ctrl+C) stops the child grader and its tree, so no orphan keeps the
    # .part log open or builds on after the run is over.
    if ($proc -and -not $proc.HasExited) { try { $proc.Kill($true) } catch { } }
    if ($mainLock) { $mainLock.Dispose() }
}
$identity = ($scripts | ForEach-Object { Get-GraderHash $_ }) -join '+'
Add-LineTo $log ("GRADER sha {0} since {1}" -f $identity, $(if ($since) { $since } else { '-' }))
$verdicts = @(Get-Content $log | Where-Object { $_ -match '^(PASS|FAIL)\s+\S' })
$verdicts
"GRADER exit $code log $log"
if ($timedOut) { $timedOut; exit 8 }
if ($ExpectRed) {
    if (-not $verdicts.Count) { "NO-VERDICT grader printed no PASS/FAIL clause line - it did not run (log $log)"; exit 6 }
    if ($code -ne 0) { exit 0 } else { 'NOT-RED grader passes already'; exit 1 }
}
exit $code
