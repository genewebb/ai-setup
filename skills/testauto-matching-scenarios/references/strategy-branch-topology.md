# Strategy Execution Branch Topology

Reference for the `testauto-matching-scenarios` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Strategy Execution Branch Topology

From `UnifiedMatchingScenario.ProcessBatchAsync` — the high-level dispatch. The strategy is picked once by
`MatchingStrategyFactory.Create` (routes on `IsBatchLoadMode`, then `!WaitForMatching`; never on `OperationType`):

```
validate config → MatchingRecordLoader.InitializeAsync → ValidateEntityExpectationsAsync (throws on ExpectEmpty/ExpectIndexed miss)
strategy = IsBatchLoadMode ? BatchLoadStrategy : !WaitForMatching ? ContinuousStrategy : PerRecordStrategy
loop while time/iteration limit left AND RecordMixManager.HasMoreRecordsAsync:
    GetNextBatchAsync(BatchSize) → strategy.ProcessIterationAsync
      BatchLoadStrategy  → New: POST create, else PATCH; one metric row per batch   (Scenarios 1, 2)
      PerRecord/Continuous → ExecuteOperationAsync per record, one row per record   (3A, 3B, 3C)
strategy.PostLoopAsync → build MetricBatchSummary
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

`MatchingOperationExecutor.ExecuteOperationAsync` dispatch
(`TestAuto.Matching/Services/MatchingOperationExecutor.cs:68-85`, verified 2026-11-02):

```
LookupOnly                       → ExecuteLookupOnlyAsync              (3A; old 3B samples)
LookupThenCreate | CreateOnly    → route on PerformLookupBeforeCreate:
    true                         → ExecuteLookupThenCreateAsync        (wizard 3B)
    false                        → ExecuteCreateOnlyAsync              (wizard 3C)
BatchLoad                        → ExecuteBatchLoadAsync               (1/2 — BatchLoadStrategy normally handles these)
anything else                    → ExecuteCreateOnlyAsync              (flag ignored)
```

`PerformLookupBeforeCreate` is a CustomParm (`MatchingConstants.PerformLookupBeforeCreate`). When absent it
defaults from `OperationType`: `true` only for `LookupThenCreate`, `false` otherwise
(`Common/MatchingParmDefaults.cs:13`). So an unchanged config keeps the old behavior, but a config can flip
lookup-first on/off without changing `OperationType`. Do not route on the operation name alone.

`ExecuteLookupThenCreateAsync`: lookup; a 2219 (insufficient match fields) response counts as **no match**
and creates; a non-success lookup returns its status (no create); a match (`TotalRecords > 0`) skips the create.

`CreateAndWaitForMatchAsync` path (`MatchingOperationExecutor.cs:301-454`):

```
create fails, or 207 with a per-record server error → failure (BadRequest when IsSuccess)
no record Code returned                              → BadRequest
IsBatchLoadMode?    → return Created, no per-record metrics      (1/2)
!WaitForMatching?   → stamp MetricCollectionStatus=Pending, return (3C-Continuous; post-run scenario fills it)
else                → poll DB for create/match/golden/survive timing + fetch GoldenRecordCode (3B, 3C-Interactive)
```

`ContinuousStrategy` is just `PerRecordStrategy` with a different name; it no longer persists anything
post-loop (`Strategies/ContinuousStrategy.cs`).

Key file: `TestAuto.Matching/Strategies/` — each scenario branch lives in its own strategy class.

---
