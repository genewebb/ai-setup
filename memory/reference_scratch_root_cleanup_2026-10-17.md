---
name: reference-scratch-root-cleanup-2026-10-17
description: "Why {ScratchRoot} filled with 89k entries on SMVMTR1 and how it is kept clean now: hourly Windows scheduled task 'AI scratch cleanup' (bin\\Clear-AIScratch.ps1, registered by install.ps1, no tokens) sweeping ONLY ScratchRoot; one-off wipe script for a full D:\\tmp"
metadata:
  node_type: memory
  type: reference
  originSessionId: 3754e77a-a9e8-42e9-b3f4-cd17c62e480c
  modified: 2026-10-18T17:32:37.299Z
---

**Problem (found 2026-10-17):** Claude's shells get TEMP/TMP = `{ScratchRoot}\temp` and CLAUDE_CODE_TMPDIR = `{ScratchRoot}`, so every .NET `Path.GetTempPath()` user (tests, dotnet workload installs, MSBuild) drops folders at the scratch root and nothing removed them. SMVMTR1 `D:\tmp`: 89,249 top-level entries (28,840 `Microsoft.NET.Workload_*.log`, ~55k 8.3 random-name folders, ~1,800 `speedy-*` test folders). Claude's own `cleanupPeriodDays` is unset and covers transcripts only.

**Fix (Gene 2026-10-17: "a powershell recurring job so we don't use tokens"; "scratch area set at install, cleanup only on it and its sub directories"; retention "anything no longer being used"; hourly):**
- `setup\Clear-AIScratch.ps1` (installed as `{ClaudeHome}\bin\Clear-AIScratch.ps1` via ai-manifest.json). `-Root` MUST equal the profile's ScratchRoot (anything else, a subfolder, a drive root: `REFUSED` exit 2), junctions/symlinks never entered or removed. A file goes when an exclusive open succeeds (nobody holds it) and write+creation are older than `-KeepDays` (7); top-level tool leftovers (`Clear-AIScratchLeftovers` shapes in `lib\MachineConfig.psm1`) after 1 day; empty dirs created > KeepDays ago; `\temp` always kept/re-created; `-Max` 5000 per run; one line per run in `{ScratchRoot}\ai-config-work\Clear-AIScratch.log` (300 lines). `-WhatIf` = WOULD-SWEEP.
- `install.ps1` step 6 (listed in the location review as `scratch cleanup task`, summary line): `Clear-AIScratch.ps1 -Register -Root {ScratchRoot} -KeepDays 7` registers task **AI scratch cleanup**, hourly from the next full hour, current user, S4U (falls back to Interactive if refused), StartWhenAvailable, 55-min limit. `-Unregister` removes; `-DryRun` prints exe/args.
- The `ai` launcher sweep was REMOVED again (redundant); `Invoke-Watchdog.ps1` still runs `Clear-AIScratchLeftovers` each tick as a between-hours top-up on stream hosts.
- Tests: `setup\tests\ScratchClean.Tests.ps1` (16 cases, DryRun registration only), `Install.Tests.ps1` asserts the row + `would register`, `MachineConfig.Tests.ps1` sweep cases, `Test-StreamKitRecovery.ps1` block 32b.
- One-off full wipe for a host that already piled up: `C:\scratch\stream-move\20261017\Clear-Smvmtr1Tmp.ps1` (run ON SMVMTR1, robocopy /MIR from an empty folder, refuses any root but D:\tmp, `-WhatIf` counts). SMB delete of 89k entries from the laptop would take hours; run it on the box.

**10/18 FALSE ALARM:** on SMVMTR1 a non-elevated genewe `install.ps1` prints `Register-ScheduledTask ... Access is denied` for BOTH the S4U and the Interactive attempt, then `WARNING: the cleanup task was not registered`. The task is fine: it was registered from an ELEVATED shell on 10/17 (owner genewe, `-Root "D:\tmp"`, LastTaskResult 0, hourly), and a non-elevated shell of the same user may not `-Force`-replace it. Gene (10/18): leave the warning as is; do not re-diagnose. Would-be fix: `-Register` detects a healthy same-user same-root task and prints KEPT instead.

**Also 10/17:** `install.ps1` lists every profile path, git-policy repo and install target up front and asks `Install to these locations? [y/N]` (`-Yes` skips; `-WhatIf`/`-Check` list without asking; redirected input refuses without `-Yes`); refuses clone ≠ AIWorkRoot and ClaudeHome ≠ what Claude reads. `publish.ps1` main-only, refuses unfinished rebase, shows files + confirms, conflict vs unreachable remote, one push retry. Bug found by the new `Publish.Tests.ps1`: a helper function named `Git` shadowed git.exe (call depth overflow) — never name a PowerShell function after the executable it wraps.
