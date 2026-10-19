# Registers the nightly Tier 2 run as a Windows scheduled task (2026-10-05 priority-focus-design 3.3). The owner runs it
# once per stream host (SMVMTR1), in an elevated pwsh:
#   Register-NightlySuite.ps1 -Repo <repo> [-At 01:00] [-Unregister] [-DryRun]
# The task runs, every day at -At (local time):
#   pwsh -NoProfile -NonInteractive -File "<this folder>\Invoke-NightlySuite.ps1" -Repo "<repo>"
# which runs Start-SuiteRun.ps1 -Repo <repo> -Session suite-nightly -Reason nightly -Wait and time-stamps its output into
# the log (-Wait keeps the legs inside the task, under its 6 h limit, instead of a process detached from it). The task
# runs a FILE: an inline -Command with quoted text in it does not survive CreateProcess's argument parsing (final review
# C1, a ParserError on every run). -DryRun prints the exact executable and argument line ("exe:" / "args:").
# Start-SuiteRun.ps1 does the rest: one nightly per 01:00 window (SKIP-NIGHTLY), a running run skips it (RUN-BUSY), and
# a live integrator lock makes it yield with a stream-integrate inbox item (YIELDED). Its output goes to
# .streams\logs\suite-nightly.txt (appended). The task runs as the current user whether or not that user is logged on
# (S4U logon: no stored password, no network credentials, which the local repo does not need).
# Task name: "Speedy Tier2 nightly <repo folder name>". Re-running replaces it. Prints REGISTERED / UNREGISTERED / DRY-RUN,
# or REFUSED (exit 3) when Task Scheduler refuses the change or no task is found after it (kit item IN-20261019125329-9e23).
param(
    [Parameter(Mandatory)] [string] $Repo,
    [string] $At = '01:00',
    [switch] $Unregister,
    [switch] $DryRun
)
$ErrorActionPreference = 'Stop'
$Repo = (Resolve-Path $Repo).Path
$name = "Speedy Tier2 nightly $(Split-Path $Repo -Leaf)"
if ($Unregister) {
    if ($DryRun) { "DRY-RUN unregister '$name'"; exit 0 }
    if (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue) {
        try { Unregister-ScheduledTask -TaskName $name -Confirm:$false -ErrorAction Stop }
        catch { "REFUSED unregistering '$name' failed: $(("$_" -split "`n")[0].Trim()) (run from an elevated pwsh)"; exit 3 }
        "UNREGISTERED '$name'"
    } else { "NOT-REGISTERED '$name'" }
    exit 0
}
$pwsh = (Get-Command pwsh).Source
$script = Join-Path $PSScriptRoot 'Invoke-NightlySuite.ps1'
$log = Join-Path $Repo '.streams\logs\suite-nightly.txt'
# Paths are double-quoted for CreateProcess; a path holding a double quote cannot be passed this way at all.
if ($script.Contains('"') -or $Repo.Contains('"')) { "REFUSED a path holds a double quote: $script / $Repo"; exit 2 }
$argLine = "-NoProfile -NonInteractive -File `"$script`" -Repo `"$Repo`""
$time = [datetime]::ParseExact($At, 'HH:mm', [Globalization.CultureInfo]::InvariantCulture)
if ($DryRun) {
    "DRY-RUN task '$name' daily at $At (log $log)"
    "  exe: $pwsh"
    "  args: $argLine"
    exit 0
}
$action = New-ScheduledTaskAction -Execute $pwsh -Argument $argLine -WorkingDirectory $Repo
$trigger = New-ScheduledTaskTrigger -Daily -At $time
$principal = New-ScheduledTaskPrincipal -UserId ([Security.Principal.WindowsIdentity]::GetCurrent().Name) -LogonType S4U -RunLevel Limited
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Hours 6)
# The ScheduledTasks cmdlets are module functions that do not see this script's ErrorActionPreference: without
# -ErrorAction Stop a refusal ('Access is denied' from a non-elevated pwsh) is non-terminating and REGISTERED would follow.
try { Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force -ErrorAction Stop | Out-Null }
catch { "REFUSED registering '$name' failed: $(("$_" -split "`n")[0].Trim()) (run Register-NightlySuite.ps1 from an elevated pwsh)"; exit 3 }
if (-not (Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue)) { "REFUSED '$name' not found after registration (run Register-NightlySuite.ps1 from an elevated pwsh)"; exit 3 }
"REGISTERED '$name' daily at $At as $([Security.Principal.WindowsIdentity]::GetCurrent().Name) (log $log)"
exit 0
