---
name: reference_profile_load_nas_clearseq
description: "pwsh profile took ~11 s to load because it dot-sourced clearseq.ps1 from D: (a Synology NAS share); fixed 2026-10-27 with a lazy clearSeq stub"
metadata:
  node_type: memory
  type: reference
  originSessionId: e11175e5-5462-45e6-a7bb-e8c5544f95e0
  modified: 2026-10-27T20:33:46.878Z
---

On the laptop (CORPLTR94) `D:` is a mapped share, `\\SynologyDS918\devopslocal`, not a local disk. PowershellScriptsDir defaults to `D:\PowershellScripts`.

Before: the profile body ran `Test-Path` (3.3 s) and then dot-sourced `clearseq.ps1` (6.7 s) on every new shell, for a total load around 11 s. After: `clearSeq` is a stub that dot-sources the script on first call. A cold load now takes 0.8-1.0 s, about 1.3 s of which is `Import-Module PSReadLine`.

The fix was made in both `C:\devops\repos\ai-setup\pwsh\PowerShell\Microsoft.PowerShell_profile.ps1` (source) and `Documents\PowerShell\...` (installed). It is left uncommitted on ai-setup main.

**Rule:** never touch a NAS path (D:, Q:) at profile load; make it lazy on first use. To time a profile, dot-source it in `pwsh -NoProfile` with a stopwatch around each part.

Related: [[reference_nas_drive_letters_stale_after_reboot]], [[project_profile_machine_config]].
