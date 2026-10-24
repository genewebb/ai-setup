---
name: project_profile_guide_and_export_2026-10-23
description: "Profile guide set lives in vault 99_Frequent\\Profile (3 notes); prof setup export + pwsh\\Install-Profile.ps1 added 10/23 (committed, not yet reloaded/pushed); sp/ep group bug fixed; PAT leak in Stream and Git.md flagged"
metadata:
  node_type: memory
  type: project
  originSessionId: 52393f05-0d8b-4aba-b420-4bc432abd551
  modified: 2026-10-23T13:22:36.934Z
---

2026-10-23: full review of the pwsh profile written to `{VaultWorkRoot}\99_Frequent\Profile\` as three notes:
Profile Guide.md (three copies, machine profile keys, install/rollout, prof hub), Command Reference.md (every
command grouped as `prof other` does, with the machine-profile keys each reads), Coworker Handoff.md (export + install steps).

Code (ai-setup clone, main, committed after 30d400a; NOT yet `prof setup reload`ed or published by Gene):
- `prof setup export [-Out <folder|file.zip>] [-WhatIf]` in `Gene.Profile\Export.ps1`: zips pwsh\ + blank-value
  ProfileMachineConfig.md template (first table only, %USERPROFILE% values kept) + README; Find-Secrets hard-stops;
  share.yaml blockedPatterns mentions are listed then confirmed (27 lines on the laptop profile, all inherent:
  SMVMTR1, genewebb remotes, droplet). Default output `{ScratchRoot}\prof\profile-export-<stamp>.zip`.
- `pwsh\Install-Profile.ps1`: coworker-side installer (mirrors install.ps1 step 4/4b; never overwrites an existing config).
- `sp`/`ep` called `prof streams show/edit` since the 10/17 group rename: fixed to `setup`.
- Pre-existing gate hits: `claude\scripts\lib\PathScope.ps1` lines 17 and 141 (not mine, blocks publish until allowlisted).

**Why:** Gene wants to hand the profile to a coworker with a MachineProfile they fill in themselves; nothing from the AI corpus or secrets may travel.
**How to apply:** point coworker questions at the Coworker Handoff note; export output is for the coworker, the ai-setup repo stays private. Rollout still = [[feedback_ai_setup_rollout_via_prof]]. Security: `99_Frequent\Stream and Git.md` holds a plaintext ADO PAT; Gene to revoke. Related: [[index_stream_host_kit]], [[project_ai_setup_private_git_repo_2026-10-14]].
