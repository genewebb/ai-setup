#requires -Version 7
<#
.SYNOPSIS
    Keeps this machine's scratch area ({ScratchRoot}) clean: removes what is no longer being used, every hour, as a
    Windows scheduled task. No Claude session, no tokens.

.DESCRIPTION
    Claude's shells point TEMP/TMP at {ScratchRoot}\temp and CLAUDE_CODE_TMPDIR at {ScratchRoot}, so every tool,
    test and build drops files there and nothing removed them (SMVMTR1 held 89,249 top-level entries by 2026-10-17).

    WHERE: only -Root and its subdirectories, and -Root must be this machine's profile ScratchRoot
    (C:\Deploy\Setup\ProfileMachineConfig.md, or AI_MACHINE_CONFIG). Any other path is refused (exit 2), so a task
    registered on an old profile can never sweep a folder that was later put to another use. A drive root is refused
    too. A junction or symlink under the root is never entered and never removed: what it points at is not scratch.

    WHAT "no longer being used" means here:
      - a FILE goes when nothing holds it open (an exclusive open must succeed) AND both its last write and its
        creation are older than -KeepDays (default 7): a file some process still writes, or just made, stays;
      - a known tool leftover at the TOP of the root or of \temp (.NET random-name folders, tmp*.tmp,
        Microsoft.NET.Workload_*.log, MSBuildTemp*, speedy-* and CrewChief test folders: lib\MachineConfig.psm1
        Clear-AIScratchLeftovers) goes after one day, since nothing ever reads those again;
      - a DIRECTORY goes when it is empty after the pass and was created more than -KeepDays ago; \temp itself is
        always kept (and re-created when missing: a process whose TEMP folder is gone fails).
    At most -Max entries (default 5000) go per run, so one run stays short on a host that piled up for weeks; the
    rest go in the next hours. A file that cannot be removed is kept and reported, never an error.

    Each run appends one line to {ScratchRoot}\ai-config-work\Clear-AIScratch.log (kept at 300 lines) and prints it:
    SWEPT files=<n> dirs=<n> MB=<n> left=<n> in-use=<n> root=<root> <seconds>s. -WhatIf prints WOULD-SWEEP and
    removes nothing (it counts the -KeepDays rule only, not the one-day leftover rule).

    -Register (install.ps1 step 6) registers the hourly task "AI scratch cleanup" for the current account: it runs
    the INSTALLED copy, {ClaudeHome}\bin\Clear-AIScratch.ps1, with -Root <ScratchRoot> -KeepDays <n>, whether or
    not the account is logged on (S4U: no stored password; falls back to a logged-on-only task when S4U is refused).
    Re-registering replaces the task. -Unregister removes it. -DryRun prints the exact executable and argument line
    instead ("exe:" / "args:") and registers nothing.

.EXAMPLE
    pwsh -NoProfile -File Clear-AIScratch.ps1 -Root C:\scratch -WhatIf            # example-path
.EXAMPLE
    pwsh -NoProfile -File Clear-AIScratch.ps1 -Register -Root C:\scratch -DryRun  # example-path
#>
[CmdletBinding(DefaultParameterSetName = 'Sweep')]
param(
    [Parameter(ParameterSetName = 'Sweep')][Parameter(ParameterSetName = 'Register')][string]$Root,
    [Parameter(ParameterSetName = 'Sweep')][Parameter(ParameterSetName = 'Register')][ValidateRange(1, 365)][int]$KeepDays = 7,
    [Parameter(ParameterSetName = 'Sweep')][ValidateRange(1, 1000000)][int]$Max = 5000,
    [Parameter(ParameterSetName = 'Sweep')][switch]$WhatIf,
    [Parameter(ParameterSetName = 'Register', Mandatory)][switch]$Register,
    [Parameter(ParameterSetName = 'Unregister', Mandatory)][switch]$Unregister,
    [Parameter(ParameterSetName = 'Register')][Parameter(ParameterSetName = 'Unregister')][switch]$DryRun
)
$ErrorActionPreference = 'Stop'
$taskName = 'AI scratch cleanup'
Import-Module (Join-Path $PSScriptRoot '..\lib\MachineConfig.psm1') -Force -DisableNameChecking
function Same-Path([string]$a, [string]$b) { [string]::Equals([IO.Path]::GetFullPath($a).TrimEnd('\'), [IO.Path]::GetFullPath($b).TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase) }
function Refuse([string]$m) { Write-Host "REFUSED $m" -ForegroundColor Red; exit 2 }

# ---- unregister ------------------------------------------------------------------------------------------------
if ($Unregister) {
    if ($DryRun) { "DRY-RUN unregister '$taskName'"; exit 0 }
    if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) { Unregister-ScheduledTask -TaskName $taskName -Confirm:$false; "UNREGISTERED '$taskName'" } else { "NOT-REGISTERED '$taskName'" }
    exit 0
}

# ---- the root: the profile's ScratchRoot and nothing else -------------------------------------------------------
$prof = Get-AIMachineProfile
$scratchRoot = [string]$prof.Keys['ScratchRoot']
if (-not $scratchRoot) { Refuse "the machine profile $($prof.Path) has no ScratchRoot" }
if (-not $Root) { $Root = $scratchRoot }
if (-not (Same-Path $Root $scratchRoot)) { Refuse "-Root $Root is not this machine's ScratchRoot ($scratchRoot in $($prof.Path)). This script sweeps the scratch area only; re-run install.ps1 to re-register the task on the current profile." }
$full = [IO.Path]::GetFullPath($Root).TrimEnd('\')
if ($full -match '^[A-Za-z]:$' -or $full -eq [IO.Path]::GetPathRoot($full).TrimEnd('\')) { Refuse "$Root is a drive root; the scratch area must be a folder" }
if ($full.Contains('"')) { Refuse "$Root holds a double quote, which cannot be passed to a scheduled task" }

# ---- register ---------------------------------------------------------------------------------------------------
if ($Register) {
    $pwsh = (Get-Command pwsh).Source
    $installed = Join-Path ([string]$prof.Keys['ClaudeHome']) 'bin\Clear-AIScratch.ps1'
    $installedThere = Test-Path -LiteralPath $installed
    if (-not $installedThere -and -not $DryRun) { Refuse "$installed is not installed yet (Install-AIMachine.ps1 puts it there); the task would run nothing" }
    $argLine = "-NoProfile -NonInteractive -File `"$installed`" -Root `"$full`" -KeepDays $KeepDays"
    $user = [Security.Principal.WindowsIdentity]::GetCurrent().Name
    if ($DryRun) {
        "DRY-RUN task '$taskName' hourly as $user on $full (files unused $KeepDays days)$(if (-not $installedThere) { ' (the script is not installed yet; the runtime step installs it)' })"
        "  exe: $pwsh"
        "  args: $argLine"
        exit 0
    }
    $action = New-ScheduledTaskAction -Execute $pwsh -Argument $argLine -WorkingDirectory (Split-Path $installed)
    $start = (Get-Date).Date.AddHours((Get-Date).Hour + 1)
    $trigger = New-ScheduledTaskTrigger -Once -At $start -RepetitionInterval (New-TimeSpan -Hours 1)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit (New-TimeSpan -Minutes 55) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    $how = 'logged on or not (S4U)'
    try {
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType S4U -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    } catch {
        # S4U needs the right to register for the account (an elevated shell has it); a plain shell gets a task that
        # runs while the account is logged on, which is when the scratch area fills anyway.
        $principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Limited
        Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        $how = "while logged on only (S4U refused: $($_.Exception.Message.Trim()))"
    }
    "REGISTERED '$taskName' hourly from $($start.ToString('HH:mm')) as $user, $how, on $full (files unused $KeepDays days)"
    exit 0
}

# ---- sweep ------------------------------------------------------------------------------------------------------
if (-not (Test-Path -LiteralPath $full -PathType Container)) { Refuse "$full does not exist" }
$sw = [Diagnostics.Stopwatch]::StartNew()
$temp = Join-Path $full 'temp'
$logDir = Join-Path $full 'ai-config-work'
$log = Join-Path $logDir 'Clear-AIScratch.log'
$cut = (Get-Date).ToUniversalTime().AddDays(-$KeepDays)
$budget = $Max
$files = 0; $dirs = 0; $bytes = 0L; $left = 0; $inUse = 0
$keepAlways = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
foreach ($k in @($full, $temp, $logDir, $log)) { [void]$keepAlways.Add($k) }

# 1. Known tool leftovers at the top of the root and of \temp go after a day, whatever -KeepDays says.
if (-not $WhatIf) {
    foreach ($r in @(Clear-AIScratchLeftovers -Root @($full, $temp) -OlderThanHours 24 -Max $budget)) { $files += $r.Swept; $budget -= $r.Swept; $left += $r.Left }
}

function Test-Reparse([string]$Path) { try { ([IO.File]::GetAttributes($Path) -band [IO.FileAttributes]::ReparsePoint) -ne 0 } catch { $true } }

# 2. Every file under the root, depth first, so a directory emptied below is seen empty on the way back up.
function Sweep-Dir([string]$Dir) {
    $entries = try { [IO.Directory]::EnumerateFileSystemEntries($Dir) } catch { return }
    foreach ($e in $entries) {
        if ($keepAlways.Contains($e)) { if ([IO.Directory]::Exists($e) -and -not (Test-Reparse $e)) { Sweep-Dir $e }; continue }
        if (Test-Reparse $e) { continue }   # a junction or symlink: not scratch, not entered, not removed
        if ([IO.Directory]::Exists($e)) {
            Sweep-Dir $e
            try {
                if ([IO.Directory]::GetCreationTimeUtc($e) -lt $cut -and -not [IO.Directory]::EnumerateFileSystemEntries($e).GetEnumerator().MoveNext()) {
                    if ($script:budget -le 0) { $script:left++; continue }
                    if (-not $WhatIf) { [IO.Directory]::Delete($e) }
                    $script:dirs++; $script:budget--
                }
            } catch { }
            continue
        }
        try {
            $fi = [IO.FileInfo]::new($e)
            if ($fi.LastWriteTimeUtc -ge $cut -or $fi.CreationTimeUtc -ge $cut) { continue }
            if ($script:budget -le 0) { $script:left++; continue }
            # In use = someone holds it open: an exclusive open fails. Such a file stays for the next hour.
            try { $h = [IO.File]::Open($e, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None); $h.Dispose() }
            catch [IO.IOException] { $script:inUse++; continue }
            catch [UnauthorizedAccessException] { $script:inUse++; continue }
            if (-not $WhatIf) { if ($fi.IsReadOnly) { $fi.IsReadOnly = $false }; $fi.Delete() }
            $script:files++; $script:bytes += $fi.Length; $script:budget--
        } catch { $script:inUse++ }
    }
}
Sweep-Dir $full
if (-not (Test-Path -LiteralPath $temp)) { New-Item -ItemType Directory -Path $temp | Out-Null }

$line = "{0:yyyy-MM-dd HH:mm:ss} {1} files={2} dirs={3} MB={4:N1} left={5} in-use={6} root={7} {8:N1}s" -f (Get-Date), $(if ($WhatIf) { 'WOULD-SWEEP' } else { 'SWEPT' }), $files, $dirs, ($bytes / 1MB), $left, $inUse, $full, $sw.Elapsed.TotalSeconds
if (-not $WhatIf) {
    try {
        New-Item -ItemType Directory -Force -Path $logDir | Out-Null
        $old = if (Test-Path -LiteralPath $log) { @(Get-Content -LiteralPath $log) | Select-Object -Last 299 } else { @() }
        Set-Content -LiteralPath $log -Value (@($old) + $line) -Encoding utf8NoBOM
    } catch { }
}
$line
exit 0
