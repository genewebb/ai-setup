---
name: reference_connect_databricks_fresh_table_delta_conflict
description: Connect Databricks 1M export fails at batch start with DELTA_CONCURRENT_APPEND.METADATA_CHANGE because Databricks auto-sets delta.dataSkippingStatsColumns on the first big ConnEx MERGE; pack fix + evidence/probe recipes
metadata:
  node_type: memory
  type: reference
  originSessionId: 2758a18c-eddd-4fd0-98a4-1142fcc8e388
  modified: 2026-11-12T23:49:16.665Z
---

2026-11-12, SMVMTR1 1M Databricks export on 26R4 (SMVM1, ConnEx 1.8.1.0) failed: TestAuto execution 10000597 'Poll Strategy Databricks Export' = batch Failed.

- Evidence: `\\SMVM1\c$\Program Files\Profisee\Master Data Maestro Server\26.4.0\Services\ConnEx\LogFiles\SystemLog.log` (ERR "Fatal error on write"). Profisee DB connex.tBatch/tJob are wiped by the next pack reset, so read the ConnEx log.
- Root cause (proven on a scratch table): the first ConnEx MERGE into the fresh table (literal VALUES source, 1000 rows x 122 columns) makes Databricks auto-set `delta.dataSkippingStatsColumns` (+ `databricks.delta.dataSkippingStatsColumns.autoSelected`). That is a metadata commit (v2), so the parallel first MERGEs fail. ConnEx (DatabricksWriter.Write, repo `connex`) treats it as non-transient, so there is no retry.
- What does NOT trigger it: a 1-row MERGE, INSERT...SELECT, or MERGE USING SELECT. A plain insert+delete warm-up does NOT fix it. Setting dataSkippingNumIndexedCols does NOT fix it.
- What fixes it: set `delta.dataSkippingStatsColumns` explicitly. Gene chose the 32 columns Databricks picked (global `ExportStatsColumns` in source `connect-databricks-export-prepare`, Recreate step). Test: test_gen_connect `test_databricks_export_table_sets_its_stats_columns_before_connect_writes`. The auto pick varies by about 1 column between runs.
- STATUS 11/12 19:20: change HELD by Gene. It is uncommitted in ai-setup and speed-merchants. SMVMTR1 was put back to the original file, so the current full runs use the old pack and their Databricks exports may fail. Test it after the current full runs: deploy the one file, then run a 1M Databricks export.
- Second, separate failure in the same run: the warehouse "compute cluster maintenance" error is also fatal in ConnEx. The pack fix does not cover it.
- Databricks query history redacts ConnEx statement text. Time travel does not work with SHOW TBLPROPERTIES; read old properties via `SHALLOW CLONE ... VERSION AS OF n` on a scratch table, then drop it.
- Token for probes: DATABRICKS_APIKEY in `\\SMVMTR1\c$\Deploy\Secrets\SMVMTR1_connect_crewchief.slim.json` (never print). Statement API: warehouse ff6259b61ed4de41, catalog rnddatabricksworkspace. Scratch probe scripts used dbx-*.ps1 (session scratchpad, not kept).

Related: [[crewchief-connect-test-rounds]]
