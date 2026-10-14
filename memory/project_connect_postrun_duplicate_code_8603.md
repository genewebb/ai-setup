---
name: project_connect_postrun_duplicate_code_8603
description: "ConnectPostRunCollectionScenario 'hang' 2026-08-07 (exec 10000187): metric row Code {BatchCode}-{Page:D6} collided with prior run's row (8603 duplicate) after connex DB rebuild reset batch codes to 1; write 400s, WorkloadExecution stays Running forever"
metadata: 
  node_type: memory
  type: project
  originSessionId: 930ea55b-9958-45d8-b269-24bc5e79ab1e
  modified: 2026-08-08T00:49:31.603Z
---

Run: workflow execution 10000187 "Connect SQL Provider 1K" on SMVMTR2 (target SMVM2/SMVMDB2, ScenarioMgt = SaaS profiseecloud.dev/speedmerchantstest). Step 22 polling completed in 59s (batch Succeeded). Step 23 ConnectPostRunCollectionScenario pinned `Running` 21:12→user cancel 21:44.

**Not a hang, not a retry loop.** Scenario ran clean: resolved batch, RunProfile over REST, emitted 1 row. `MetricsPersistenceJob` POST `v1/Records/ConnectApiExecution` returned **HTTP 400, error 8603 "Cannot create or update this member because it already exists. RecordCode: 1-000001"** (SystemLog_476.log ~line 12557 on SMVMTR2).

**Root cause:** `BuildDetail` sets `Code = {BatchCode}-{PageNumber:D6}`. The workflow rebuilds the ModelSource/connex side, so `connex.tBatch` codes restart at 1 every run. ConnectApiExecution `Code` is unique in the model — row `1-000001` from the 8/5 run (WorkloadExecution 100007213) already existed. Every fresh-environment rerun collides.

**Why it looks like a hang:** MetricsPersistenceJob logs ERR but completes; `WorkloadExecutionUpdateJob` then finds 0 metric rows for the WorkloadExecution ("STEP 2 FAILED: No metric records found") and leaves the WorkloadExecution `Running`. `CheckAndProgressWorkflowAsync` polls "WorkloadExecution ... status is Running" every minute forever. Third distinct cause of the same pinned-Running signature (see [[project_connect_postrun_cross_database_hang]]).

**FIXED + VERIFIED (2026-08-07, local exec 10000174, all 32 steps Complete):** rows `100006778-1-000001` / `100006752-3-000001` landed HTTP 200; both poll steps saw Succeeded on poll #1 (<1s work); no hang. Residual: 207 MultiStatus with 8609×4 per write — `IsCodeLookup`/`MaxRunningScenarioCount`/`SimulatedUserThreadId`/`SimulatedUserCount` ([MetricColumn] on MetricDetailExtended, non-nullable bool/int so null-guard can't skip) missing from ConnectApiExecution entity on BOTH local and speedmerchantstest. User decision: do NOT add attrs to entity — remove from detail instead. **Done (2026-08-07):** `MetricDetailConnectApiExecution` rebased `MetricDetailExtended`→`MetricDetailBase`, declaring locally only the Extended columns Connect uses (TargetEnvironmentName, HttpRequestType, HttpErrorMessage, PageSize); CRUD-only props + ScenarioId + TargetEnvironment (dual-Environment-column hazard) gone. No `MetricDetailExtended` casts existed anywhere. Guard test `MetricType_DoesNotCarryCrudOnlyColumns`. ALSO done: all 20 `[DIAG]` ErrorWithTag sites in TestAuto.Connect downgraded to DebugWithTag (regex sweep, 4 files). Build clean, 785 unit tests green. Awaiting rebuild+redeploy+rerun verify (expect clean 200/201, no 207).
1. `BuildDetail` Code now `{WorkloadExecution}-{BatchCode}-{Page:D6}` (prefix omitted when WorkloadExecution blank — standalone runs). Tests updated + 2 new (`BuildDetail_Code_IsScopedToWorkloadExecution`, `..._WithoutWorkloadExecution_OmitsPrefix`).
2. `WorkloadExecutionUpdateHelper` STEP 2 FAILED branch (metrics-required scenario, 0 rows) now writes ExecutionStatus=Failed to the WorkloadExecution (via existing `UpdateWorkloadExecutionRecordAsync`, FailedBatches=1) before returning false — workflow fails visibly instead of pinning Running. No-metrics branch untouched. No unit seam for helper (needs IRestClientFactory/RestUrlManagement mocks) — verified by build + 784-test suite green.

Deployed runner SMVMTR2 still on build 1.7.9714.2175 (also predates Environment-column fix) — needs redeploy before rerun.

**Diagnosis path (runner unreachable via WinRM/SQL):** local Seq empty because run was on SMVMTR2; SMVMTR2 Seq needs its own API key (401 with CORPLTR94 key); WinRM Kerberos 0x80090311 (missing WSMAN SPN pattern); SQL remote refused. **Admin share works:** `\\SMVMTR2\c$\Deploy\TestAuto.Web\LogFiles\SystemLog_*.log` — file logs have everything.

Entity domain state on speedmerchantstest (verified 8/7): ConnectApiExecution has Domain attrs RunProfile→ConnectRunProfile, Environment→ServerProfile, ExecutionStatus, HttpRequestType, ProfiseeVersion, Scenario, Workload, WorkloadExecution; rest FreeForm. RunProfile resolved fine ('26R2-SQLSERVER-PROFISEE-I-100000-100000-0-4', Attributes=122, DBA=50).
