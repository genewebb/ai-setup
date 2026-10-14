---
name: machine-sync
description: RETIRED - moving AI setup edits between machines (laptop, CORPVM17, SMVMTR1...) is now git. Use for /machine-sync, "sync TR1 back to the laptop", "push my laptop tweaks to the VM", "get my changes onto this machine": answer with the ai-setup publish/install steps below instead of the old Sync-Machine.ps1 three-way copy.
---

# machine-sync (retired)

The AI setup lives in the private `ai-setup` git repo; each machine's `{AIWorkRoot}` is a clone of it. The old
three-way copy (`{DeployRoot}\steps\Sync-Machine.ps1`, `machines.json`, `sync-base\`) is no longer used.

| Want | Run |
|---|---|
| Send edits from this machine | `pwsh -NoProfile -File {AIWorkRoot}\publish.ps1 -Message "<what changed>"` |
| Take edits made elsewhere | `pwsh -NoProfile -File {AIWorkRoot}\install.ps1` |
| New machine | clone the repo into `{ReposRoot}\ai-setup`, set the profile's `AIWorkRoot` to it, run `install.ps1` |

`install.ps1` covers everything machine-sync carried: corpus runtime, both PowerShell profiles and own modules,
stream-host scripts (to the profile's `StreamHostDir`), plus memory. A conflict is an ordinary git conflict.
