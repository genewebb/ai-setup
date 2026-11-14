---
name: project-matching-large-100m-continue-2026-11-14
description: "100M Matching on CORPVMHA1/CORPSQL03 Profisee100M: S1 done by hand (11/03-11/07); plan 11/14 = new pack packs/matching-large run from SMVMTR3 to finish S1 and run S2-3c; plan only, not built"
metadata:
  node_type: memory
  type: project
  originSessionId: 30030f2b-29ba-4de1-a057-b1b5de691d97
  modified: 2026-11-14T15:23:18.671Z
---

State read 2026-11-14 (CORPSQL03 Profisee100M, read-only): monitor.tActivity ID 6 Start of Scenario 1 (hand-inserted) 2026-11-03 20:29:24 UTC; Txn 2018 Indexing to 11-06 20:03, Clustering & Survivorship to 11-07 09:12:40 UTC; extra Indexing Txn 12087 (08:37-10:12) and 31519 (10:12-14:18:10 UTC), trigger unknown. No End marker, no TestAuto execution. data.tRetailClient 120,004,763 rows. DB 5 data files D/F/G/H/I (300 GB each, 754 GB used), log K 494 GB; FULL recovery with 15-min log backups; backup compression default on; default backup D:\DBBackup. Free: D 626 GB, F/G/H/I 3.2 TB each.
S1 load source (Gene): ModelSource master dbo.RetailClient, first 20M per source system.

Gene decisions 11/14: End marker ~1 s after 14:18:10 UTC; S2/3a/3b/3c = 1M each (not pack N/10); build scenario tables from master (script needs slice param); real RetailClient100MScenario1 table; full striped .bak after each scenario (D,F,G,H,I); new pack `packs/matching-large`, family matching-large, own reference-kv; 26R3, instance profisee; repoint SMVMTR3 TestAuto SourceRecordDB (and Profisee REST client) to 100M for the run; SMVM3 lane idle meanwhile. Working matching pack must not change.

Facts: DatabaseOperationsStep backs up to ONE file only. Tag box = CrewChief box $env:COMPUTERNAME (SMVMTR3). 26R3 100M run profiles exist in PROD (Scenario 1/2/3a/3b/3c-100000000-0). Related: [[project_test_lab_topology_cadence]], [[reference_profisee_monitor_activity_30day_purge]], [[reference_partition_job_blocks_portal_during_matching]].
