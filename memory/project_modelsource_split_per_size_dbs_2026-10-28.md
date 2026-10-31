---
name: project_modelsource_split_per_size_dbs_2026-10-28
description: "ModelSource split on CORPSQL03 (one DB per test size, fixed table names RetailClient/PDATA, 5-drive spread, no compression); scripts in C:\\Deploy\\SQLScripts\\ModelSource on the laptop; 1M proven end to end 2026-10-28, other sizes await Gene's go"
metadata:
  node_type: memory
  type: project
  originSessionId: 159810d1-4d6d-45ae-9499-11e3880c4774
  modified: 2026-10-28T22:36:24.280Z
---

**ModelSource split (started 2026-10-28).** CORPSQL03.ModelSource (755 GB, one mdf) is being split into one database per test size, each holding ONE data table under a fixed name: `ModelSource<N>.dbo.RetailClient` (matching: 1M, 10M, 15M, 100M, 300M, 500M = the untouched master) and `ModelSourcePDATA<N>.dbo.PDATA` (CRUD: 1K, 1M, 10M). Each also keeps the 5-row `dbo.SourceSystem` (RetailClient DBs only). Backups `D:\DBBackup\ModelSourceRetailClient<N>.bak` / `ModelSourcePDATA<N>.bak`; **on restore the DB is always named `ModelSource`** (script 04 renames files and logical names).

Gene's decisions: NO data compression (parity of the Connect load metric over size; PAGE would save 57%); scenarios unchanged, only Connect load definitions get repointed to the fixed table names; files spread D,F,G,H,I + log K like the Profisee perf DBs; SIMPLE recovery; smallest footprint = exact pre-sizing + TRUNCATEONLY + log shrunk to 512 MB (1 GB for >= 100M).

Scripts (laptop `C:\Deploy\SQLScripts\ModelSource`, meant to live at the same path ON CORPSQL03 once c$/remoting access is fixed): `01-Create-ModelSourceDb.sql`, `02-Copy-Table.sql` (DDL from sys.columns, keyset batches, IDENTITY_INSERT, resumable, builds IX_RetailClient_Code + IX_RetailClient_SourceSystem_Code), `03-Finalize-And-Backup.sql` (count + CHECKSUM_AGG(BINARY_CHECKSUM(*)), CHECKDB, TRUNCATEONLY, log shrink with VLF roll, backup COMPRESSION+CHECKSUM, VERIFYONLY), `04-Restore-ModelSource.sql` (WITH MOVE round-robin over given drives), `Run-ModelSourceSplit.ps1` (driver, -Sizes, -Steps, -DropExisting, sizing from the source table's used pages).

Status 2026-10-28 18:00: ALL NINE sizes built, verified and backed up (1M 0.24 GB, 10M 2.4, 15M 3.6, 100M 23.7, 300M 71, 500M 120, PDATA1K 0.001, PDATA1M 1.2, PDATA10M 11.8; 300M took 1h13, 500M 2h02). Gene is moving the .bak files off CORPSQL03 to a file share and dropping ModelSource<N> DBs himself. **Original ModelSource on CORPSQL03 is KEPT PERMANENTLY (Gene, 2026-10-28 18:36): never suggest dropping it.** It stays the rebuild source and the master for new variations; the RetailClient500M rename inside it is not planned. Also added `05-Generate-RetailClient-Variation.sql` (TOP-N per source system from the master, tested on 50K) and `HowToCreateDataVariations.md` in the scripts folder. Scripts still need copying to CORPSQL03 `C:\Deploy\SQLScripts\ModelSource` once c$ access works. Plan file: `~\.claude\plans\pasted-content-id-218a-this-table-precious-cerf.md`.

**Why:** DB too big to copy to other servers; per-size DBs restore fast and small.
**How to apply:** continue with `.\Run-ModelSourceSplit.ps1 -Sizes 10M,15M,100M,PDATA1K,PDATA1M,PDATA10M,300M,500M` only after Gene's go; 300M/500M are hours each (run unattended, /loop). See [[reference_sql_shrinkfile_minimumsize_and_sqlcmd_v_quoting]].
