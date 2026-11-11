---
name: project-corpsql03-proxmox-conversion-2026-11-09
description: CORPSQL03 (Hyper-V host of CORPVMHA1) converts to Proxmox VE; no new hardware; DB container variant decided by pilot; notes in vault 52 Technical\Containers\NewHardware
metadata:
  node_type: memory
  type: project
  originSessionId: 99975b22-753a-4027-a0c6-2b23dec9084e
  modified: 2026-11-11T19:38:41.680Z
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
Gene 11/11 eval Windows: licence-terms question = don't care; rebuild VMs every ~6 months via PowerShell install+configure scripts (only our software added after), rebuild between campaigns never during; rearm count checked later with slmgr /dlv. Teams post = note 5. Install planned week of 2026-11-16. Remote WinRM from laptop to CORPSQL03 failed 11/11 with Kerberos 0x80090311 though DC reachable (not diagnosed).
