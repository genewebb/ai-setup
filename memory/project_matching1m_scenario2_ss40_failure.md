---
name: project_matching1m_scenario2_ss40_failure
description: "Matching 1M workflow execution 10000185 failed at Order 15 (Scenario 2 Incremental Batch Load) because ChangedSourceSystems includes source 40, which has no Source System member in the SUT — 200/200 batches 207-partial, 28,200 junk rows inserted"
metadata:
  node_type: memory
  type: project
---

**Diagnosed 2026-09-09.** WorkflowExecution `10000185` ("Matching 1M Execution", workflow `10000160`),
step Order 15 `Matching Scenario 2 Incremental Batch Load` (`UnifiedMatchingScenario`, BatchLoad,
WorkloadExecution `100007143` / ID 4207). SUT = `https://CORPLTR94.corp.profisee.com/profisee`
(config's `TargetEnvironmentName: SMVM2` is a LABEL only — do not chase SMVMDB2).

**Chain.** `ChangedSourceSystems = {20:34, 30:33, 40:33}`, `ChangedPercent 85`, `BatchSize 500`.
`RecordMixManager.GetMixedRecordsBatchAsync` → 425 changed / 75 new;
`FetchFromMultipleSourcesAsync` sorts by percent desc and gives the LAST source the remainder, so
SS20=144, SS30=140, **SS40=141**. Those 141 come from `ModelSource.dbo.RetailClientCloned`
(`SourceSystem='40'`, 50M rows) and post `Source System = "40"`. The SUT's `Source System` entity
has members **1, 2, 3, 20, 30**, MDM, Seed, Apple, Intuit, Unknown, Walmart, Credibly — **no `40`**
(source 40 was never loaded into the 1M model). Profisee answers **HTTP 207** with 141×
`[8617] The value for the domain based attribute is not valid ... Attribute Name: Source System DBACode: 40`.
TestAuto counts a 207-with-any-record-error as a failed batch → `FailedBatches=200`,
`CompletedBatches=0` → step Failed → `WorkflowMonitorJob.CheckAndProgressWorkflowAsync` stopped the
run; Orders 16–37 never started.

**Fix**: drop 40 from `ChangedSourceSystems` / `SelectedChangedSourceCodes` for the 1M template
({20:50, 30:50}), or add a `Source System` member with Code `40` to the SUT.

**Collateral, verified in `localhost.profisee`:**
- 28,200 `tRetailClient` rows (= 141 × 200) were **INSERTED** (`$LastChgTypeID=1`) with a **blank
  Source System** between 22:38:09 and 23:34:09 — the 207 dropped the bad DBA but kept the record.
  Clean these before re-running.
- Only 43,200 of 100,000 rows were touched: 28,200 junk + 15,000 new (SS1/2/3). **Zero
  `$LastChgTypeID=2` rows** — the SS20/SS30 "changed" leg (56,800 posts) persisted nothing. Open
  question, not yet explained.

**Diagnosability gaps:**
- ~~`ErrorMessage` EMPTY on both `tWorkloadExecution` 4207 and
  `tTestAutoWorkflowExecutionDetail` 100004659~~ **FIXED 2026-09-09** — new
  `TestAuto.Shared/Common/Metrics/MetricFailureSummary.cs` censuses DISTINCT error messages (record codes
  normalised to `<varies>`) with occurrence counts, capped at `SharedConstants.MetricFieldMaxLength`.
  Wired through `WorkloadExecutionUpdateHelper` (writes `WorkloadExecution.ErrorMessage`; a reason already
  on the record from `BatchJobOrchestrator` wins, since that writer sat closer to the failure),
  `WorkflowOrchestrationService.GetWorkloadExecutionStatusAsync` (now returns
  `(Status, ErrorMessage)` and copies the reason onto the detail row and the parent workflow row), and
  `BatchJobOrchestrator.SetWorkloadExecutionFailedAsync` (takes a `reason`). Replayed over run 10000185's
  real 200 metric rows: **256 chars** instead of a 4,000-char truncated wall, naming the 8617 / Source
  System / DBACode 40 outright. 6 unit tests in
  `Testing.SpeedMerchants.Unit/Tests/Shared/Metrics/MetricFailureSummaryTests.cs`.
- That metric row stores `ResponseCode=400` while Seq logged `HTTP=207` — see [[feedback_207_not_success]].
- `StartTime`/`EndTime` = `0001-01-01`, `ElapsedSeconds=0` on the failed WorkloadExecution row.
- No fail-fast: first 8617 hit at 22:40:59 (batch ~9) yet all 200 batches ran, burning 57 minutes on
  a 100%-reproducible config error. A preflight that checks every selected source code against the
  target's `Source System` members would have failed in seconds.

Related: [[reference_matching_pool_offsets_and_alignment]] (already records "source 40 unloaded"),
[[testauto-matching-scenarios]], [[reference_scenariomgt_db]].
