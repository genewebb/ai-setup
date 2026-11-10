---
name: project-corpsql03-proxmox-conversion-2026-11-09
description: CORPSQL03 (Hyper-V host of CORPVMHA1) converts to Proxmox VE; no new hardware; DB container variant decided by pilot; notes in vault 52 Technical\Containers\NewHardware
metadata:
  node_type: memory
  type: project
  originSessionId: 99975b22-753a-4027-a0c6-2b23dec9084e
  modified: 2026-11-10T01:34:12.046Z
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

**Added 2026-11-09 (later):** Gene's requirement: isolation test must use full instances (app server Windows VM + its own separate DB server), at least 3 instances simultaneously, more if possible. SQL-only (Level A) is diagnostic only, no verdict. Note 2 E4 reworked: blocks = each instance solo + all together, compare to own solo, bootstrap over blocks, idle slot rotates, report by position. SMVMTR1-3 online (no SMVMTR4); fourth driver open. Campaign ~240 h (3 instances). Gene asked about <1% noise: unknown until E1; margin floor 2% vs 1% is open decision after E1. Lucid layout diagram: https://lucid.app/lucidchart/a8bc58dc-7b17-4886-9f55-e63c74cdf331/edit
Decided by Gene 2026-11-09: margin floor stays 2%, revisit after E1; E4 starts with 3 instances (SMVMTR1-3), fourth driver later.
Gene 2026-11-09: once the Proxmox box is configured, Gene sets up access from the laptop so Claude can drive checks and changes. Until then no access to the new host; do not assume it.
