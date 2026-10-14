---
name: project_matching_3a_step21_hang_2026-09-13
description: "2026-09-13 rerun of LOCAL workflow execution 10000190 step 21 (3a, WE 100007335) never sent a lookup - local /Profisee 26.2.0 instance has been 500.30 since the 9/12 19:24 reboot (services started before SQL was reachable), REST GET swallowed into a fake 'RetailClient empty', Hangfire retries 10x, WE stuck Running"
metadata: 
  node_type: memory
  type: project
  originSessionId: d6e5bf36-22ce-4192-9050-0ede6455c319
  modified: 2026-09-13T19:06:05.160Z
---

**Target is CORPLTR94 (local), NOT SMVM2.** The metrics `Endpoint` column prefix `SMVM2/...` is not a host - do not infer the target box from it. Local IIS has two instances: `/Profisee` (26.2.0, `profisee` DB, holds RetailClient 1,221,458 rows) and `/speedmerchants` (26.1.0, ScenarioMgt DB, no RetailClient).

**Cause chain (verified 2026-09-13 12:30 EDT)**
1. Reboot 2026-09-12 19:24:50; `Profisee-*` workers started 19:25:09; matching SystemLog 19:25:42 `SqlException ... server was not found or was not accessible (Named Pipes, Error 2)`. ANCM keeps serving `500.30` until the pool recycles. `/Profisee/rest`, `/api/matching`, `/api/bulkscoring` all 500.30 in ~10 ms; `/speedmerchants/*` healthy.
2. `RecordDataFacade.GetRecordsAsync` (`TestAuto.Shared.Http/Facades/RecordDataFacade.cs:190-202`) swallows non-2xx into `HttpErrorMessage`, returns `Records=[]`; `MatchingResultCollector.cs:60` checks only `Records.Any()` -> "RetailClient expected to have indexed data but is empty" 1-4 ms after start.
3. `ProcessBatchJob` has no `[AutomaticRetry]` (default 10). Hangfire DB = `Hangfire`, schema `testautojobs`. Continuations `OnlyOnSucceededState` (`BatchJobOrchestrator.cs:218-449`) -> WE never updated. `WorkflowExecution:ScenarioTimeoutMinutes`/`TimeoutHours` are read by no .cs file.

**12:28 EDT** Claude recycled all `Profisee-*` pools (user-approved) -> rest/matching/bulkscoring healthy. **12:30:22** `Hangfire` DB dropped via SSMS by `CORP\genewe`; TestAuto recreated it empty 12:31:06 -> all step 21 jobs gone, WE 100007335 orphaned `Running`. Needs resubmit from step 21.

**3a PROVEN GREEN after user restart (WE 100007336, 12:35-12:55 EDT)**: 100,000 LookupOnly, all 200, LookupHasMatches=Y, RecordActionType=NoChange, keys 0100000000-0100099999, avg lookup 218 ms.

**3b (step 25, WE 100007340) is NOT stuck - it is single-threaded**: runtime `MaxHangfireScenarioServersCount=1`, `MaxConcurrentBatchesPerHangfireScenarioServer=1`, `BatchSize=1`; CustomParm `ConcurrentThreads=20` does not drive the fan-out. `IterationLimit=100000`, `TimeLimit=00:00:00`, `WaitForMatching=true` (polls 4 s x up to 30). Measured 854 creates in 111 min (~7.8 s/record, ~10 s at 15:05) = ~9 days for 100K. One ProcessBatchJob for everything -> 0 metric rows until it ends. Seq stopped receiving TestAuto events at 14:00:30 EDT while the scenario kept creating records (Seq service itself up).
**Fix**: recycle `Profisee-*` app pools after SQL is up; consider a startup-order dependency. Same signature as [[project_smvm2_matching_service_down_2026-09-10]] (SqlException at start, then permanent 500.30).
