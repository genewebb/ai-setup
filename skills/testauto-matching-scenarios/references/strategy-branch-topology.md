# Strategy Execution Branch Topology

Reference for the `testauto-matching-scenarios` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Strategy Execution Branch Topology

From `UnifiedMatchingScenario.ProcessBatchAsync` — the high-level dispatch:

```
OperationType == BatchLoad?
  YES → batch-level loop: POST/PATCH all records, one metric per batch  (Scenario 1)
  NO  → per-record loop: ExecuteOperationAsync per record               (Scenarios 2, 3A, 3B, 3C)
        After loop:
          !WaitForMatching && trackedRecords > 0?
            YES → persist tracked records                               (Scenario 3C-Continuous)
```

> **Post-test metric collection ("Scenario 4") is no longer a branch here.** The old
> `OperationType == CollectPostTestMetrics` / `ExecutePostTestMetricCollectionAsync` path (and the
> `CollectPostTestMetrics` operation-type constant) were removed from `UnifiedMatchingScenario` and
> extracted into a standalone **`UnifiedMatchingPostRunCollectionScenario`** (editor type
> `CustomParmsEditorType.UnifiedMatchingPostRunCollection`, editor `UnifiedMatchingPostRunCollectionEditor`).
> A 3c run (`CreateOnly`, `WaitForMatching=false`) writes `MetricCollectionStatus="Pending"` rows to
> `UnifiedMatchingApiExecution` with the matching/survivorship columns null; the post-run scenario later
> reads those Pending rows, polls the Matching DB for each record's matching/golden/survive timing,
> updates the rows **in place**, and flips status to `Collected` (or `Failed` + error). Declared with
> `MetricDetailNone`/`MetricBatchSummaryNone` (no-metrics path — it enriches another run's rows), runs as
> a single self-managed job (`MaxHangfireScenarioServersCount=1`) parallelized internally via
> `SemaphoreSlim`, and is re-run safe (only Pending rows are picked up).

`MatchingOperationExecutor.ExecuteOperationAsync` dispatch:

```
LookupOnly        → ExecuteLookupOnlyAsync           (3A, 3B)
LookupThenCreate  → ExecuteLookupThenCreateAsync      (3C)
CreateOnly        → ExecuteCreateOnlyAsync            (2)
BatchLoad         → ExecuteBatchLoadAsync             (1 — batch path above handles this)
```

`CreateAndWaitForMatchAsync` path:

```
IsBatchLoadMode?    → skip metric collection                     (1)
!WaitForMatching?   → track record, skip polling                 (3C-Continuous)
else                → poll DB for matching/survivorship timing   (2, 3A, 3B, 3C-Interactive)
```

Key file: `TestAuto.Matching/Strategies/` — each scenario branch lives in its own strategy class.

---
