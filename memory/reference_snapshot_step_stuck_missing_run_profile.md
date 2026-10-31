---
name: reference_snapshot_step_stuck_missing_run_profile
description: "Prod TestAuto \"Capture Matching Status Counts\" step stuck Running forever = run-profile code missing in UnifiedMatchingApiExecutionRunProfile (REST 207 / error 8617); Hangfire retries 10x, each retry writes an orphan MatchGroupResults record, WorkloadExecution never flips to Failed"
metadata:
  node_type: memory
  type: reference
  originSessionId: 593fcb78-1ded-462a-9086-0bd2c111037c
  modified: 2026-10-28T22:21:17.172Z
---

2026-10-28 prod run "Matching 1M 26R3 Execution" (10000267, SMVMTR2) stuck on step 6 (MatchingSnapshotCaptureScenario, Pre) 7 h, then again after resume.

**Root cause:** CustomParm `UnifiedMatchingApiExecutionRunProfile` = `26R3-RetailClient-Scenario 1-1000000-0`, but `data.tUnifiedMatchingApiExecutionRunProfile` had no 26R3 1M rows (only 300M/15M/10M/100M for 26R3; 1M existed for 26R2 only). Profisee REST returns **207** with `8617 : The value for the domain based attribute is not valid` and STILL creates the record (DBA left NULL). Scenario treats 207 as failure and throws (`MatchingSnapshotCaptureScenario.cs` ~line 366).

**Why it looks "stuck" instead of Failed:**
- Hangfire default `[AutomaticRetry]` = 10 attempts, backoff `(n-1)^4+15+rand*n` s (last gaps 11, 25, 42, 70, 113 min). Each attempt writes another orphan `UnifiedMatchingApiExecutionMatchGroupResults` row (11 rows for WorkloadExecution 11424).
- `WorkloadExecutionUpdateJob` is chained `OnlyOnSucceededState`, so after the 10th failure nothing marks `tWorkloadExecution` Failed; `WorkflowMonitorJob` keeps logging "status is Running" every minute.
- Restarting TestAuto + recreating the Hangfire DB (SMVMTR2 local SQL `Hangfire`, schema `testautojobs`) deletes the retry job, so the WorkloadExecution can never complete.

**How to apply:**
- Stuck snapshot step: grep `\\<runner>\c$\Deploy\TestAuto\web\LogFiles\SystemLog_*.log` for `8617` first. Check run-profile rows exist for version+size BEFORE running a workflow on a new size.
- Fix = create the 5 run-profile rows (Scenario 1, 2, 3a, 3b, 3c) copying attributes from a sibling size (ProfiseeVersion DBA, Scenario 27, MatchingStrategy 1, counts 42/5/37/0/0, SourceRecordCount), then mark WorkloadExecution Failed and Resubmit from the step; purge the orphan NULL-run-profile result rows.
- Code defects to file: validation 207 should not be retried (or Attempts=0 on ProcessBatchJob), and an exhausted/failed child job must flip WorkloadExecution to Failed. Related: [[feedback_207_not_success]], [[reference_matching_3b_synthetic_timings_and_nsb_audit]].
