---
name: reference_corpsql03_hardware_profile
description: "CORPSQL03 measured hardware 2026-08-17: 2x EPYC 9474F 96C/192T, 1.5TB in 24x64GB DDR5-4800, 4 NUMA nodes (NPS2), 8x Micron 7450 NVMe individually addressable, UEFI + Secure Boot OFF, but Hyper-V host + SQL owning 905GB + another user logged in"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 20823a52-9dc4-437d-b376-c1594585db4a
  modified: 2026-08-17T14:37:27.355Z
---

Measured with `C:\devopslocal\powershellscripts\getmachineresources.ps1` on 2026-08-17
(non-elevated, so BitLocker/TPM/bcdedit were skipped). Raw output: `C:\Tmp\corpsql03\`.

**Corrects the "512 cores / 8 SATA SSDs" premise in the Obsidian doc `52 Technical\Containers\PeformanceTesting\06 Better Test Bed`, which is now known wrong on both counts.**

## Hardware
- Supermicro **AS-2126HS-TN**, board H14DSH, AMI BIOS 1.5 (2025-05-11), Platform Role = Enterprise Server
- **2x AMD EPYC 9474F** — 48C each = **96 physical / 192 logical**, SMT on, all cores uniform
  (single efficiencyClass — no P/E lottery). Base = max = 3601 MHz observed. L3 = 256 MB/socket
  => 8 CCDs x 32 MB, 6 cores per CCD.
- **4 NUMA nodes = NPS2.** 48 logical procs and **384 GB per node**, and Windows makes
  **4 processor groups** of 48 (so groups align 1:1 with NUMA nodes). NPS4 would give 8 nodes,
  L3-as-NUMA up to 16.
- **1.5 TB RAM: 24 x 64 GB Samsung RDIMM, all 24 channels populated (12/socket, 1 DPC).**
  Rated 5600, running **4800 = Genoa platform max, not a misconfiguration.** Perfectly balanced.
- OS: **Windows Server 2025 Standard** build 26100. **BIOS Mode UEFI, Secure Boot State = Off.**
- BMC: "Microsoft Generic IPMI Compliant Device" present => Supermicro IPMI/Redfish available.

## Storage — 8 data drives are NVMe, NOT SATA, and NOT behind RAID
- Disks 0-7: **Micron MTFDKCC3T8TGP (7450 PRO 3.84 TB) NVMe SSD**, each on **its own
  "Standard NVM Express Controller"** (PCI VEN_1344). GPT, one volume each: D F G H I K L M.
  Individually addressable — dedicating one drive per container needs no firmware change.
- Disk 8 only: **Broadcom SAS 3808** (megasas35) 447 GB RAID volume = **C: boot/system**.
  So Windows boot lives on a completely separate device from the data drives.
- **Zero unallocated space on all 9 disks.** F/G/H/I are ~99% empty (~3553 of 3577 GB free),
  so Linux would need one of those volumes repurposed rather than free space carved out.
- L: TempDB-Log (2071 GB used), M: HyperV-64k (2062 GB used), D: (1298 GB used).

## Why it is NOT a quiet machine (the actual blocker)
- **HypervisorPresent = True**: Hyper-V role installed, `vmms` running, Hyper-V virtual switch +
  virtual ethernet adapters present, 2 TB on an M: HyperV volume. Every topology number above is
  the root-partition view. Running the isolation harness under Windows here would be *worse* than
  the laptop.
- **SQL Server 2022 Developer 16.0.4262.2**, `max server memory` = **1,024,000 MB (1000 GB)**,
  committed 905 GB. That is why 3 of 4 NUMA nodes report **0 bytes free**. MAXDOP 8,
  affinity mask 0, automatic soft-NUMA ON.
- Databases: **Profisee 2820 GB**, ModelSource 158.7 GB.
- IIS (W3SVC) running. User **joshma** logged in over RDP since 2026-08-12.
- Load at survey time was only 0.5% CPU, uptime 5.4 days — idle, but not unowned.

**How to apply:** hardware-wise this is a far better isolation test bed than the laptop on every
axis (real NUMA nodes with private memory controllers, dedicated NVMe per container, uniform cores,
Secure Boot off so custom kernels are unblocked). The open questions are ownership and downtime,
not capability. Still unknown: BitLocker state, TPM, firmware NPS/SMT/boost/determinism settings
(no vendor BIOS WMI provider — read via BIOS setup or Supermicro Redfish), and whether Hyper-V VMs
are actually running. Re-run the survey **elevated** to close the first two.

Related: [[project_container_isolation_perf_2026-08-16]] [[reference_corpsql03_missing_wsman_spn]]
[[reference_machine_resource_survey_script]]
