---
name: project_stream_host_smvmtr1_2026-09-28
description: "9/28 decision to move the speedmerchants stream kit off CORPLTR94 onto lab VM SMVMTR1; scripts in C:\\tmp\\stream-host; tokens, not CPU, are the ceiling"
metadata:
  node_type: memory
  type: project
  originSessionId: f8883ba6-deb0-408f-bb53-b3303a9b5b0f
  modified: 2026-09-29T15:28:02.423Z
---

2026-09-28 18:30 EDT: Gene chose to run the whole stream kit (all roles) on **SMVMTR1**; the laptop becomes a viewer.
Scripts at `C:\tmp\stream-host\`: `Install-StreamHost.ps1` (run on VM, elevated, in RDP), `Copy-StreamToHost.ps1`
(laptop; `-Phase Seed` then `-Phase Final`, which refuses unless the board is quiet), and `Test-StreamHostReady.ps1`
(read-only; passes 0 FAIL on the laptop).

**Why:** the laptop's WSL VM is fixed at 32 GB of 64 GB (RAM peaked at 95%), and sessions died overnight. Gene: "more
horsepower than I have tokens for", so Claude usage limits, not CPU, cap the number of builders.

**How to apply:**
- SMVMTR2 runs the DEPLOYED stack under compose project `speedmerchants` on the dev ports (5310, 5311, 14400, 5672,
  15672), so a G-suite deploy there would replace it. Keep TR2 as the manual-test box, not a stream host.
- SMVMTR1 on 9/28 had no WSL, no Docker, only the .NET 6 SDK, no Claude Code, and 28 GB free on C:. The repo goes on D:
  behind `C:\devops\...` junctions, because tasks.json records absolute C:\devops paths.
- The home desktop was rejected for policy reasons: corporate code and secrets would sit on a non-domain machine.
- Running Invoke-Command setup on the VMs from here was denied; Gene runs the scripts over RDP.

**Update 9/28 20:35:** Gene reversed two points. SMVMTR2 is now a BUILD host plus the TARGET host, and it runs the
deployed stack under the `speedmerchants` Rancher. SMVMTR1 is the hub.
- Loops run as **CORP\speedmerchants**: an admin account, Claude at `C:\Deploy\Claude`, signed in as gene.webb@profisee.com.
  WinRM runs as agenewe, so per-user env for speedmerchants goes into `HKU\<sid>\Environment`.
- `~\.claude\CLAUDE.md` there is a symlink to `S:\AIWork` and looks broken over WinRM.
- **Layout (Gene 9/28 22:10): CODE ON C:, CONTAINERS ON D:.** Repos and worktrees go in real folders under C:\devops, as on
  the laptop, never junctioned. The Rancher WSL disks go in D:\RancherDesktop\distro and \distro-data, moved with
  `wsl --manage <d> --move`. `tools\stream-host\Move-StreamHostLayout.ps1` migrates a host; a copy is in C:\tmp\stream-host on each VM.
  See [[feedback_no_code_on_d_drive]]. It was cloned from origin branch `users/agenewe/stream-sync`, because
  `stream` needs a PR (TF402455).
- The SUT is https://smvm2.corp.profisee.com/profisee. The key is `C:\deploy\secrets\<HOST>_CrewChief.json`
  [0].RestKeys.values.ProfiseeRestKey.
- Git: system `safe.directory` is set, GCM is the helper, and pushes use Gene's PAT.

**Cutover 9/28 21:30:** the laptop sessions died when accounts changed. `users/agenewe/stream-sync` is a SNAPSHOT
branch with no history in common with master: each sync is `git commit-tree <master HEAD^{tree}> -p <sync head>`, then a push.
The auto-mode classifier refused three things from Claude: force-breaking claims, committing, and the push. Gene runs those.
G1.T09 stays `building` with no claim, waiting on G1.T13 and G1.T15. Copy-StreamToHost now treats that as parked.

**9/28 23:58 snapshot flow RETIRED:** the laptop becomes a normal tracking clone of `origin/users/agenewe/stream-sync` (old laptop master kept as `laptop-master-backup`). Laptop, SMVMTR1 and SMVMTR2 all `git pull` / `git push` that one branch; no more `commit-tree` snapshots. Verified before the switch: sync `4c96a0c` tree == laptop `ac878ed` tree, so laptop commit `bcfab84` (deploy\ + tools\stream-host) was the only delta and was cherry-picked onto the branch.

**9/29: `users/agenewe/stream-sync` IS the real working/main branch** (Gene). Don't call it a workaround or a snapshot. Laptop `origin/HEAD` is now set to it with `git remote set-head`, so Claude Code sees it as the main branch. `stream` (only `07eea80`) is stale; only a PR would move it. Local `master` and `laptop-master-backup` (`bcfab84`) are stale leftovers.

Related: [[project_stream_kit_replaces_myloop]], [[reference_lab_hardware_smvm]].
