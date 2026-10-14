---
name: feedback_vm_d_drive_containers_only
description: "SMVMTR1 layout differs from the laptop: work lives on D: (devops repos/worktrees/myworkspace, tmp, containers); C: is small (20 GB free). SUPERSEDES the 9/28 'D: = containers only' rule"
metadata:
  node_type: memory
  type: feedback
  modified: 2026-10-01T12:57:49.948Z
  originSessionId: e071532a-95ca-4f16-ae81-7a5cb0301769
---

On SMVMTR1, everything Gene works with is on **D:**:
- `D:\devops\repos\speedmerchants` (the real repo; `C:\devops` no longer exists);
- `D:\devops\worktrees`, `D:\devops\myworkspace`;
- `D:\tmp` (Claude scratch);
- `D:\RancherDesktop`, `D:\SQLData`.

C: had only 20 GB free on 10/1. Still on C: (observed 10/1): `C:\PowershellScripts`, `C:\Deploy\Secrets`, `C:\Deploy\Setup\ProfileMachineConfig.md`, IIS `C:\inetpub\wwwroot`. The laptop keeps everything on C: and its NAS letters. Container setup is completely different between the two machines too.

**Why:** Gene 10/1: "Setup for containers and other things is totally different everything is on c on my laptop but on different drives on SMVMTR1" / "Everything on SMVMTR1 is on drive d". This replaces his 9/28 instruction ("NOTHING GOES ON THE D DRIVE OTHER THAN Containers"). The TR1 profile note "D: holds containers only" is stale.

**How to apply:** never copy laptop paths to TR1 by analogy; take every TR1 value from the TR1 profile (`ProfileMachineConfig.md`), and when that is stale, from what is actually on disk. For new TR1 work locations, default to D:. Related: [[project_profile_machine_config]], [[project_stream_host_smvmtr1_2026-09-28]], [[project-machine-config-laptop-live-2026-10-01]].
