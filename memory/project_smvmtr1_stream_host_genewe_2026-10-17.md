---
name: project_smvmtr1_stream_host_genewe_2026-10-17
description: "SMVMTR1 is the stream host again from 2026-10-17 19:04, running as CORP\\genewe (not agenewe); fresh deploy steps, ACL trap, runner tabs, what is where"
metadata:
  node_type: memory
  type: project
  originSessionId: 3754e77a-a9e8-42e9-b3f4-cd17c62e480c
  modified: 2026-10-18T00:32:23.550Z
---

Stream host = **SMVMTR1, account CORP\genewe** (Gene's choice 2026-10-17: log on as genewe, admin shell = same user,
streams in NON-elevated windows). The old agenewe install there is orphaned (left untouched). Laptop board
`.streams\runners\STOP` says it is a stale snapshot. Supersedes [[project_stream_host_back_to_laptop_2026-10-17]].

**Where:** ai-setup clone `D:\devops\repos\ai-setup` (AIWorkRoot), ClaudeHome `C:\Users\genewe\.claude`, repo
`D:\devops\repos\speedmerchants` on branch `users/agenewe/stream-sync`, worktrees `D:\devops\worktrees`, scratch `D:\tmp`,
StreamHostDir `D:\devops\stream-host`, Rancher disks `D:\RancherDesktop\{distro,distro-data}` (genewe, moby, k8s off,
autostart + background), status page https://smvmtr1.corp.profisee.com/speedy/status.html (IIS C:\inetpub\wwwroot\speedy).
Old speedmerchants-account Rancher disks DELETED (Gene). Old TR1 worktrees (all rows integrated) were moved aside and Gene
deleted them 2026-10-17 20:06.

**Deploy steps that worked:** profile edits (AIWorkRoot, StreamHostDir, access + git rows) -> clone ai-setup -> install.ps1
-> Claude native install + `.local\bin` on User PATH -> `uv` + `uv tool install claude-swap` (cswap.exe is a uv stub,
copying it from another account fails "Failed to canonicalize script path") -> plugins by hand (seeded settings do not
install them; profisee marketplace = ADO, Gene adds by hand) -> GCM settings (Gene's recipe: helper manager,
useHttpPath for dev.azure.com, wincredman, msauthFlow system) -> 7 stream env vars written into genewe's HKU\...\Environment
over WinRM (values never printed), then a WM_SETTINGCHANGE broadcast + reopen Windows Terminal -> `.env` (laptop timings,
SPEEDY_WORKER_CHANNEL_DIR repointed) + New-WorkerChannelCertificates.ps1 as genewe -> npm ci + playwright install ->
robocopy board -> strip runners/STOP, quota-hold, tabs\*.json, repoint status-url/priority-url/status-mirror.
Re-run install.ps1 once claude is on PATH or the `ai.cmd` shim is skipped.

**ACL TRAP (cost 2 failed starts):** anything created from an ELEVATED window or over the admin share as agenewe is owned
by Administrators and genewe (non-elevated) gets only Users read+append: git pull "unable to unlink ... Invalid argument",
runner TICK-FAILED / PRESTAGE-FAILED "Access to the path is denied". Fix applied:
`icacls <dir> /grant 'CORP\genewe:(OI)(CI)F' /T` on speedmerchants, ai-setup, worktrees, stream-host, D:\tmp,
C:\inetpub\wwwroot\speedy. Any future copy onto TR1 needs the same grant.

**Tabs:** owner ruling 2026-10-17 "Runners for 4, Planner interactive": addStreams opens Integrator/Kit/Coordinator/Status
as gated Start-StreamRunner -Live tabs, Planner a long /loop session (ai-setup b17bda9). Test-StreamHostReady port 5310
FAIL is a false alarm: SpeedyTlsProxy service holds 10.0.0.6:5310, compose binds 127.0.0.1:5310.
Rancher "timed out dialing Hyper-V socket" after first start: rdctl shutdown, wsl --shutdown, rdctl start fixed it.

**Runner tabs in plain words + suite filter (ai-setup 5417be6, owner 2026-10-17 "cryptic", "add a filter"):** tab
lines in LOCAL time, a 'doing'/'failed' line under each code, every wait names its next-look clock time.
Test-StreamKitRecovery `-List` / `-Only '^74\.,^112\.'` runs only those sections (33 s vs ~40 min); Gene does not
want the full 40-minute run for a narrow change: run the sections that read the changed code.

**Lost-edit lesson (ai-setup d1dfac5):** the status page's category totals line (owner ask 10/16) was edited straight
into CORPVM17's INSTALLED copy (~\.claude\skills), never published, and vanished on the host move. Kit edits go into
the ai-setup repo (Publish-KitFile) only. Before retiring a host, compare its installed skills to git history
(hash-object vs every committed blob): on 10/17 only Build-StatusPage.ps1 was missing.
Same commit: stream-build verifier runs FOREGROUND (background verifier + Monitors swallowed /exit, RESULT-GRACE).
