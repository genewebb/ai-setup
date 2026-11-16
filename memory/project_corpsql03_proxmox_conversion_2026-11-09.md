---
name: project-corpsql03-proxmox-conversion-2026-11-09
description: CORPSQL03 (Hyper-V host of CORPVMHA1) converts to Proxmox VE; no new hardware; DB container variant decided by pilot; notes in vault 52 Technical\Containers\NewHardware
metadata:
  node_type: memory
  type: project
  originSessionId: 99975b22-753a-4027-a0c6-2b23dec9084e
  modified: 2026-11-16T13:21:15.313Z
---

Gene 2026-11-09: **no new hardware purchase** (Option A 9-server rack and Option B big server are dropped). Work = convert existing CORPSQL03 (Windows Server 2025 + Hyper-V, hosts CORPVMHA1) to Proxmox VE with Windows app-server VMs + Linux SQL Server containers, and prove isolation between Profisee instances by repeated measurement.

Decisions (Gene, 11/09):
- DB "Linux container": **pilot both** (Docker in pinned Linux VM vs LXC on host), keep the quieter. My recommendation was Docker-in-VM (Microsoft lists Docker Engine; LXC not listed; Proxmox documents no LXC pinning option).
- Purchase-option notes kept but marked dropped, not deleted (my choice; Gene said "eliminate").

Notes (design only, nothing built or measured): `Q:\Work\Work\52 Technical\Containers\NewHardware\CORPSQL03 Proxmox - 1 Hardware and Current State.md`, `- 2 Isolation Design and Test.md`, `- 3 Settings.md`.

Facts worth not re-deriving (read from the machine 11/09):
- `corp\agenewe` is local admin on CORPSQL03 since 11/09 (WinRM + c$ work) and SQL sysadmin. BMC = 10.36.52.48 (no credentials held).
- 96 cores / 192 threads (NOT 512 as the vault Proxmox guide says), 4 NUMA nodes x 384 GB, 8 separate NVMe.
- Profisee connects to SQL by Kerberos as CORP\speedmerchants: SQL on Linux needs AD keytab or SQL login. Whether Profisee runs on SQL Server for Linux is UNKNOWN = gate 0.
- All backups live on the box: folder is `D:\DBBackup` (no "s"; `D:\DBBackups` does not exist).

**Why:** Gene wants variance between instances as near zero as possible, and the real number if not zero.
**How to apply:** start from the three notes; do not reopen purchase options; nothing destructive on CORPSQL03 before the gates in note 1 section 4. Related: [[project-test-lab-topology-cadence]].
Gene 2026-11-09: Windows app-server VMs = trial (evaluation) Windows Server; DB = Linux containers running SQL Server 2022. Gate 8 in note 1 updated. Open: eval length/rearm/expiry behaviour, SQL edition (assumed Developer).
Gene 2026-11-10: install most likely in person at the server, USB key, all partitions on all drives removed, 100% clean Proxmox install. Means on-box backups/DBs/CORPVMHA1 VHDX are destroyed: gates in note 1 must be met first. BIOS values recorded at the console before wipe; BMC login optional.
Gene 2026-11-11: fresh ModelSource full backup made; ALL backups copied to CORPNAS01 (path not given). Gate 3 MET (Gene waived test restore: backups restored many times before). Weekly backup job failures: ignore for now. Gate 9 added: isolated network. ~99% of work on this box only, so VM-to-DB test traffic on Proxmox internal bridge (no NIC, no IT). External load from SMVMTR1/SMVM1/SMVMDB2 only if box alone can't do it; then IT VLAN/switch.
2026-11-11: onsite checklist = note `CORPSQL03 Proxmox - 4 Onsite Checklist.md` (go/no-go, BIOS photos, BMC, install, IT questions, exit test over VPN, remote work list). IT answers 11/11 (supersede BMC-required): NO remote BMC ever, IT owns hardware. Plan: final BIOS on site, SMT/boost toggled from Linux sysfs, kernel options via one-time boot + watchdog, IT contact for power cycles. Host name CorpProxMox01, DHCP only (reservations), VMs CorpVMxxx, nothing blocked on VPN/outbound, kb/monitor in room. Isolated net = Linux bridge with no port (answer to IT's "Hyper-V private switch" question).
Gene 11/11 decisions: licence topic CLOSED = evaluation Windows, no Datacenter/EA/Azure Local discussion. Platform check closed (Gene: Profisee runs on Windows regardless of hypervisor). Gate 0 auth settled = SQL login (user ID/password), no AD keytab. Gate 0 CLOSED: making CrewChief/TestAuto work with Linux SQL (paths, SQL login) = known post-install task, not a wipe blocker. Rough public prices: Datacenter 96 cores ~$40.6K one time list; Azure Local ~$10/core/mo host + $23.30/core/mo Windows guests, waived by AHB with SA. CORPVMHA1 = rebuild clean (Gene copying VHDX to CORPNAS01 on 11/11 as fallback; target `\\CORPNAS01\Rnd\PerformanceTesting\CORPVMHA1`, Gene's Z: = `\\CORPNAS01\Rnd`). Ask IT for isolated driver VLAN/port now, unused unless needed.
2026-11-16 review (read-only, WinRM to CORPSQL03 works again): notes live in vault `99_Frequent\NewHardware` (Q: not mapped on laptop; read via Obsidian MCP). New on box since 11/11: after-1 striped backup on D/F/G/H/I, ModelSourceMatching DB + .bak, Ola fulls 11/15 (weekly job works). CorpVMHA1.vhdx now 1,170 GB on M:, second copy on L:\CorpVMHA1 (11/12). Gene 11/16: "all backups have been copied to CORPNAS01" (I could not see the NAS: laptop DNS gives the same IP for CORPNAS01 and SMVMTR1). Still open in notes: gates 1, 2 (baseline), 6; contradictions in note 4 (boost on/off in BIOS, static vs DHCP, BMC references, IOMMU reboot required vs optional), driver location, which server names survive.
Gene 11/16 decisions: gate 2 (baseline) WAIVED; gate 1 (owner sign-off/window) REMOVED: "we have complete control of CORPSQL03, can stop SQL Server anytime" - do not raise sign-off again. Gate 6 CLOSED 11/16: WISdom + collection agents (windows_exporter, Arc/SQL Extension) just go away with the box, not an issue; TestDataGenerationAndMutation service also no impact (Gene 11/16), removed from list. Notes 1-4 corrected 11/16 (boost+SMT ON in BIOS, switched from Linux; DHCP reservation; no BMC). New note `CORPSQL03 Proxmox - 6 Cookbook.md` = ordered install checklist; BIOS photos go to `C:\scratch\CORPSQL03-BIOS\before|after|linux` for me to read and return the board-specific change list before any wipe.
Gene 11/16: ALL 100M Matching testing PAUSED for now (see [[project-matching-large-100m-continue-2026-11-14]]); not a wipe blocker. No gate open as of 11/16; CORPVMHA1 disk image copy confirmed by Gene 11/16. Nothing blocks the wipe; remaining pre-work = IT booked, installer USB, DHCP reservation, then cookbook step 7 (last look) onward.
Gene 11/11 eval Windows: licence-terms question = don't care; rebuild VMs every ~6 months via PowerShell install+configure scripts (only our software added after), rebuild between campaigns never during; rearm count checked later with slmgr /dlv. Teams post = note 5. Install planned week of 2026-11-16. Remote WinRM from laptop to CORPSQL03 failed 11/11 with Kerberos 0x80090311 though DC reachable (not diagnosed).
