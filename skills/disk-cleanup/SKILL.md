---
name: disk-cleanup
description: Finds the largest files on a Windows drive and frees space by deleting ONLY allowlisted junk (temp folders, crash dumps, error reports, Windows Update downloads, Delivery Optimization cache, browser caches, Recycle Bin, old IIS logs) and clearing package caches through their own commands (NuGet, npm, pip). The drive is chosen per request (default C). Every other large file gets advice only, never deletion. Use when asked to clean up a disk, free disk space, find what is filling a drive, or when a drive is low on space.
---

# Disk Cleanup

Two scripts. The scan is read-only. The delete step acts only on categories the user approved in this
conversation, and re-validates every file against the allowlist in `scripts/DiskCleanup.Categories.ps1`.

## Hard rules

- Delete ONLY with `scripts/Remove-SafeCleanup.ps1`. Never `Remove-Item`, `del`, `rm` or Explorer for this task.
- Delete ONLY categories the user picked by name in this conversation. No pick, no delete.
- Files with verdict `Keep` are never deleted by this skill, however large. Give the `Hint` as advice and stop.
  The user deletes those personally, if at all.
- Never widen the allowlist on the fly. A new category is a change to `DiskCleanup.Categories.ps1` in the
  ai-setup repo (see the ai-repo-management skill), reviewed like any other code change.
- Never run the WinSxS / `powercfg` / DISM commands from the hints yourself. Show them; the user runs them.

## Workflow

1. **Drive.** Take the drive letter from the request (`D`, `D:`, `D:\` all work). None given: use `C` and say so.
2. **Scan** (read-only; takes minutes on a large drive because it walks every file for the largest-files list):

   ```powershell
   pwsh -NoProfile -File "{ClaudeHome}\skills\disk-cleanup\scripts\Find-SafeCleanup.ps1" -Drive <letter> -Top 25
   ```

   - `-SkipLargest` sizes the categories only (fast).
   - Run elevated to include `WindowsTemp`, `WindowsUpdateDownload`, `DeliveryOptimization`, `KernelMemoryDump`,
     and other users' folders. Not elevated: the Warnings section lists what was skipped.
   - The last line is `MANIFEST: <path>`. Keep it for step 4.
3. **Report.** Show the category table (Eligible size per category) and the largest-files table. For each large
   file give its verdict:
   - `Safe:<Category>`, `Confirm:<Category>`, `Regenerable:<Category>` - deletable through that category.
   - `TooNew:<Category>` - in a category but younger than its minimum age; it is left alone.
   - `Keep` - not deletable here. Quote the hint if there is one.
4. **Ask.** Use AskUserQuestion (multiSelect) with the categories that have eligible bytes, largest first.
   State in each option what it costs:
   - `Confirm` tier: RecycleBin empties every user's bin on the drive; IisLogs loses request history over 30 days.
   - `Regenerable` tier: the next build or install re-downloads. NuGetCache: private feeds need sign-in again on
     restore. These run the tool's own command (`dotnet nuget locals all --clear`, `npm cache clean --force`,
     `pip cache purge`) for the current user only.
   - BrowserCache is skipped while Chrome, Edge or Firefox runs; ask the user to close them first.
5. **Delete** only the picked categories:

   ```powershell
   pwsh -NoProfile -File "{ClaudeHome}\skills\disk-cleanup\scripts\Remove-SafeCleanup.ps1" -ManifestPath "<manifest>" -Category UserTemp,CrashDumps -Confirm:$false
   ```

   `-Confirm:$false` is required because the shell is non-interactive; the user's pick in step 4 is the
   confirmation. Add `-WhatIf` instead for a dry run. A manifest older than 24 hours is refused: rescan.
6. **Report** the per-category lines (deleted, skipped, failed) and the free-space before/after line. Failures are
   usually files locked by a running process; that is expected for temp folders. The CSV log path is printed.

## What the delete step re-checks per file

Allowed roots are recomputed from the drive letter (manifest paths are not trusted), then each file must:
be under a category root and match its pattern; not be hard-excluded (`pagefile.sys`, `hiberfil.sys`,
`swapfile.sys`, `\Windows\WinSxS\`, `\Windows\Installer\`, `\Windows\System32\`, `\System Volume Information\`);
have no junction or symlink between it and the root; still be old enough; and have the same size and timestamp as at
scan time. Anything else is logged as `skip: <reason>`.

## Categories

| Name | Tier | Min age | Location |
| --- | --- | --- | --- |
| UserTemp | Safe | 1 day | `Users\*\AppData\Local\Temp` |
| WindowsTemp | Safe | 1 day | `Windows\Temp` |
| WindowsUpdateDownload | Safe | 10 days | `Windows\SoftwareDistribution\Download` |
| DeliveryOptimization | Safe | 1 day | NetworkService DeliveryOptimization `Cache` |
| CrashDumps | Safe | 1 day | `*.dmp` in user `CrashDumps`, `Windows\Minidump`, `Windows\LiveKernelReports` |
| KernelMemoryDump | Safe | 1 day | `Windows\MEMORY.DMP` |
| ErrorReports | Safe | 1 day | `ProgramData\...\WER\{ReportArchive,ReportQueue,Temp}`, user WER |
| BrowserCache | Safe | none | Chrome / Edge `Cache`, `Code Cache`, `GPUCache`; Firefox `cache2` |
| RecycleBin | Confirm | none | `$Recycle.Bin` |
| IisLogs | Confirm | 30 days | `*.log` under `inetpub\logs\LogFiles` |
| NuGetCache | Regenerable | command | current user `.nuget\packages`, `NuGet\v3-cache`, `NuGet\plugins-cache` |
| NpmCache | Regenerable | command | current user `npm-cache` |
| PipCache | Regenerable | command | current user `pip\cache` |

Requires PowerShell 7.2+ (`PriorityQueue`, `EnumerationOptions`).
