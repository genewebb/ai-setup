---
name: reference-corpvm17-defender-no-local-exclusions
description: "CORPVM17 Defender policy DisableLocalAdminMerge=1: Add-MpPreference exclusions are saved but IGNORED; IT will not change it (Gene 10/14). Defender ~2 cores under stream load; size runners to CPU instead"
metadata:
  node_type: memory
  type: reference
  originSessionId: f0454aab-598a-49d1-b5bc-df925330f846
  modified: 2026-10-15T00:08:39.351Z
---

Checked 2026-10-14 on CORPVM17 (stream host, 16 logical cores, 96 GB):
- `HKLM\SOFTWARE\Policies\Microsoft\Windows Defender\DisableLocalAdminMerge` = 1. Local exclusions added with
  `Add-MpPreference -ExclusionPath` land in `HKLM\SOFTWARE\Microsoft\Windows Defender\Exclusions\Paths` with no error
  but have NO effect; `(Get-MpPreference).ExclusionPath` shows only the policy list.
- Gene added C:\devops\repos, C:\devops\worktrees, agenewe .nuget\packages, AppData\Local\rancher-desktop locally
  (inert, kept). IT will NOT add exclusions: do not suggest Defender exclusions again for this machine.
- Under 5 authors + 5 builders: CPU 89-100%, MsMpEng ~2 cores, builders' dotnet/testhost the main load, authors light.
  Lever = fewer builders (`removeStreamTab -Builder -Number <n>`, cap `StreamMaxBuilders` in the machine profile).
  Old host (SMVMTR1) had 32 faster cores.

Related: [[project-stream-host-move-corpvm17-2026-10-13]], [[project-stream-tabs-profile-2026-10-04]].
