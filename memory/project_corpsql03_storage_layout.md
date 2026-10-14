---
name: corpsql03-storage-layout
description: "CORPSQL03 rebuilt storage layout 2026-08-31 — drives, tempdb, IFI on, DB create conventions"
metadata: 
  node_type: memory
  type: project
  originSessionId: 30c87ddc-9cd2-4cce-9a75-2f059ee9d830
  modified: 2026-08-31T18:25:32.172Z
---

CORPSQL03 (SQL 2022 CU25, 192 cores, 1TB max memory) storage re-laid 2026-08-31. Old ModelSource/Profisee DBs GONE — box wiped; the Copilot assessment doc in Q:\...\DatabaseMaintenance\ is stale.

**Drives**: C(system), D,F,G,H,I,K,L (3.5TB each), M(1.5TB). **No E: drive.**

**Conventions (user-set)**:
- Data files: `<drive>:\SQLData\` spread over D,F,G,H,I (one file per drive)
- ALL log files: `K:\SQLLogs` (also instance DefaultLog)
- tempdb: `L:\TempDB` — 8 data ×50000MB + log 20000MB (log on L: violates the K: rule; move queued-not-done, needs 1 ALTER + restart)

**IFI enabled** 2026-08-31 14:24 (SeManageVolumePrivilege → NT Service\MSSQLSERVER via secedit, verified Y). Data growth/create instant; logs still zero.

**Create script**: `C:\devops\myworkspace\sql\CreateDatabaseAndSpread.sql` — dynamic, drive-list tunable, sized for 300M→400M records (3.65GB per M records, ratio from Profisee120Failed = 438GB @ 120M, same model). 5×300GB data, 128GB log cap 512GB, FULL recovery (needs log backups or 9002 at cap!), ALLOW_SNAPSHOT_ISOLATION+RCSI+ADR+AUTOGROW_ALL_FILES+QueryStore. Gotcha fixed: `EXEC proc @p = CONCAT(...)` illegal — EXEC args take no expressions.

Log growth stays small (512MB–1GB): logs never IFI (except 2022 ≤64MB growths), growth = write stall; 2014+ VLF rule = 1 VLF when growth ≤ 1/8 log size, so small increments no longer VLF-bloat.

Related: [[corpsql03-hardware]] [[reference_corpsql03_missing_wsman_spn]]
