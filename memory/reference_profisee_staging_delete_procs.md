---
name: reference-profisee-staging-delete-procs
description: "How Profisee staging deletes work (stg.t<Entity>_Delete + stg.p<Entity>_Delete, meta.tStaging status), measured speed vs REST, and traps (silent no-op when running, table not cleared); basis for Run Purge staging rework"
metadata:
  node_type: memory
  type: reference
  originSessionId: 3cbf42a2-10bf-4c57-99a5-a810b87f7f83
  modified: 2026-10-19T14:13:44.664Z
---

Verified 2026-10-10 on prod ScenarioMgt (Azure SQL pc-speedmr-prd-db). Staging was enabled 10/8 16:35 for the 12 run-graph entities, so these exist for each of them: `stg.t<Entity>_Delete (ID, Code)`, view `stg.v<Entity>_Delete` (LEFT JOIN on Code), and proc `stg.p<Entity>_Delete @UserID INT = NULL`.

The proc works like this:
- **Permission check.** The caller's SYSTEM_USER must be a `meta.tUser` with the Super Administrator or Batch Integration Administrator role. The other route is to run as `meta.tSystemCluster.ServiceUserAccount` and pass @UserID.
- **Checkout check.** It fails with status 6 if the model is checked out.
- **Start.** It sets `meta.tStaging` (Name `<Entity>_Delete`) StatusID 3, posts a `StagingProcessed` NServiceBus message to `messaging.[Services.Staging]`, then BLOCKS, polling every 1 s.
- **Result.** Status 4 = Success. 2/5/7/8/9 = errors (`meta.tStagingStatus`).
- **Trap: silent no-op.** If the status is already 3 (Running), the proc RETURNS with no error and does nothing.
- **Trap: table not cleared.** After success the staging table is NOT emptied (1,032,876 rows were still there). Clear it before and after each use.

Speed: Gene's purge of WE 10842 and 10983 deleted 1,032,876 UnifiedMatchingApiExecution rows in 9:32, about 1,800 rows/s, in 50k blocks. It ran as gene.webb@profisee.com (user 1). The REST path manages about 176 rows/s (local orphan delete, 12,177 rows in 1:09).

The Profisee REST API has NO staging route (Swagger has only `Records/bulk/{entity}`, which wipes the whole entity), so a staging delete needs a direct SQL connection. TestAuto had only HangfireDB/MonitorDB plus ProfiseeDB/ConnectDB/DataDB. On SMVMTR2, ConnectDB and DataDB point at CORPSQL03/Profisee300M, the instance under test and NOT the ScenarioMgt store. The secret display truncates at 4000 chars, so the ProfiseeDB value is unseen.

Gene's decisions 10/10: a per-entity "use staging" checkbox in the Run Purge wizard, chosen against the row count shown (NOT a Workload Y/N column); connection = the ProfiseeDB connection string from the secrets file.

**WorkloadExecution children (10/19):** tRecordApiExecution, tRecordInteractiveApiExecution, tUnifiedMatchingApiExecution, tUnifiedMatchingApiExecutionTimings and tUnifiedMatchingApiExecutionMatchGroupResults (these two have BOTH WorkloadExecution and UnifiedMatchingScenarioWorkloadExecution), tWorkloadExecutionResourceSummary, tTestAutoWorkflowExecutionDetail, tTestAutoUtilityExecution, tTestAutoExecutionHistory, tConnectApiExecution. All have stg _Delete tables and procs (ID is an identity column, so insert Code only). Child FK columns hold the WE **ID**: filter by joining to tWorkloadExecution for its Code. Delete children first, tWorkloadExecution last.

**Gene's cleanup rules (10/19):** a restart keeps the SAME WorkloadExecution, so separate WEs for the same setup are separate runs. Delete everything not Complete (no jobs running). A failed run with no metrics = WE row only; a failed run with metrics = delete its metrics first. Keep the latest good run per setup. Check for a complete replacement before deleting a failed run that holds the only data for its version.

Related: [[project_testauto_metric_run_purge_2026-10-07]], [[reference-restclient-bulkdelete-broken]]
