---
name: reference_lab_hardware_smvm
description: "Lab hardware measured 2026-09-24: SMVM1-3, SMVMTR1-3, SMVMDB1-3 are identical Azure VMs (32 vCPU Xeon 8370C, 256 GB, WS2025 Datacenter Azure); CORPLTR94 i9-13950HX 64 GB NVMe"
metadata:
  node_type: memory
  type: reference
  originSessionId: 0359fc02-cccc-4830-81fb-20a4bcd43ea3
  modified: 2026-09-24T03:25:01.559Z
---

Measured read-only 2026-09-24 (WinRM CIM on SMVM2/SMVMTR2, SQL DMVs on SMVMDB2); Gene confirmed sets 1 and 3 are identical to set 2.

- SMVM1/2/3 (app) and SMVMTR1/2/3 (runner): Intel Xeon Platinum 8370C, 1 socket x 16 cores = 32 logical, 256 GB, Windows Server 2025 Datacenter Azure Edition, Azure managed disk (reports SAS 1 TB). = production label APP32CORE256GB.
- SMVMDB1/2/3: 32 logical (1x16), 255 GB, same OS, SQL Server 2022 Developer 16.0.1200.5; volumes C 117 GB, D 896 GB, E 1023 GB. = SQL-OP32CORE256GB.
- CORPLTR94: i9-13950HX 24C/32T, 64 GB, WDC SN810 2 TB NVMe, Windows 11 Enterprise.
- CORPSQL03: see [[reference_corpsql03_hardware_profile]].
- Reach: WinRM works to SMVM2 and SMVMTR2 from this box; SMVM3, SMVMDB1/3, SMVMTR3 refuse WinRM.

Used in Speedy shipped run profiles `lab-vm-32core-256gb`, `lab-sql-32core-256gb`, `corpltr94-workstation`.
