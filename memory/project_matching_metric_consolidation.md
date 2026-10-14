---
name: project-matching-metric-consolidation
description: 3c matching metric consolidation — UnifiedMatchingPostRunCollectionScenario replaces Scenario 4; single-entity two-phase rows
metadata: 
  node_type: memory
  type: project
  originSessionId: 3c01a80e-f512-4572-9b94-b03812925a8a
---

26R2 rework (done in code, build-verified May 2026) eliminating the parallel post-metric-collection entity for matching scenario 3c.

**Old model (removed):** 3c (`CreateOnly`, `WaitForMatching=false`) wrote tracked records to a separate `UnifiedMatchingApiExecutionPostMetricCollection` entity; an in-class `OperationType=CollectPostTestMetrics` branch ("Scenario 4") later read them and inserted rows into `UnifiedMatchingApiExecution`. 3c's own WorkloadExecution got 0 canonical rows → orchestrator gate halted it.

**New model:**
- 3c emits a **Phase A** `MetricDetailUnifiedMatching` row per record to `UnifiedMatchingApiExecution` at create time, stamped `MetricCollectionStatus="Pending"` (set in `MatchingOperationExecutor` `!WaitForMatching` branch). `ContinuousStrategy` is now just a label over `PerRecordStrategy`.
- New scenario **`UnifiedMatchingPostRunCollectionScenario`** (`TestAuto.Matching/Scenarios/`, `MetricDetailNone`/`MetricBatchSummaryNone`, editor `CustomParmsEditorType.UnifiedMatchingPostRunCollection`) reads the source run's Pending rows (`SourceWorkloadExecution` CustomParm, `{{STEP:N}}`), polls the matching DB, and **updates those rows in place** → `Collected`/`Failed`. Its own WE completes via the no-metrics path.
- Entity `UnifiedMatchingApiExecution` gained attrs `MetricCollectionStatus` (Domain→TestAutoMetricCollectionStatus) + `MetricCollectionErrorMessage` (Text 4000). `UnifiedMatchingApiExecutionPostMetricCollection` entity deleted.

**Retired:** `TrackingRecordPersistence`, `MatchingConstants.TrackingEntityName` / `CollectMetricsPostTest` / `Default_CollectMetricsPostTest` / `OperationType_CollectPostTestMetrics`, the `_trackedRecords` plumbing, and the "Scenario 4" template in the UnifiedMatching wizard.

**Also fixed:** dead inherited `[MetricColumn]` leaks on detail entities — removed `DriverId/DriverName/JobId/JobName/WorkloadId` from `MetricDetailExtended`; removed `[MetricColumn]` from `ScenarioId` (MetricDetailExtended) and `DetailType` (MetricDetailBase). `RequestElapsed` leak on the matching entity left parked (benign).

**Why:** the parallel entity broke 3c orchestrator advance and doubled schema/query surface. See [[project-perfdashboard]] if matching metrics feed dashboards.

**Open items:** replicate the two entity-attribute adds to non-local environments; runtime smoke-test a full 26R2 workflow; `RecordTrackingInfo` model is now production-unused (kept).
