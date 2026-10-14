---
name: testauto-matching-strategy-pattern
description: >
  Strategy pattern decomposition of UnifiedMatchingScenario for TestAuto. Use when refactoring
  UnifiedMatchingScenario, implementing a matching strategy class, constructing a
  MatchingIterationContext, mapping operations to executors, which strategy a config resolves to via
  MatchingStrategyFactory (IsBatchLoadMode / WaitForMatching, never OperationType), why a wizard-built
  3A gets ContinuousStrategy, the no-op PostLoopAsync hook, or the
  BatchLoad/OperationalBatch/LookupStress/ScoringTest/LUBC topology.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Matching Strategy Pattern

## When to Use

- Refactoring or extending `UnifiedMatchingScenario.ProcessBatchAsync`
- Adding a new matching scenario type that requires its own iteration or post-loop behavior
- Tracing which executor method handles a given `OperationType`
- Understanding how `WaitForMatching` and `IsBatchLoadMode` route to different strategies
- Debugging why a scenario's metrics are not being collected as expected

## Why the Strategy Pattern Exists

`UnifiedMatchingScenario.ProcessBatchAsync` was approximately 400 lines with interleaved scenario-specific branching, making it difficult to test individual scenarios in isolation, understand which code path a given configuration would follow, or add a new scenario type without risking regressions in existing paths.

The strategy pattern extracts each distinct execution path into its own class, reducing `ProcessBatchAsync` to approximately 60 lines of pure orchestration. Scenario-specific logic lives exclusively in strategy implementations.

Code lives in `TestAuto.Matching\Strategies\`.

## Strategy Classes

Five scenarios supported, collapsing into three strategy classes plus one early return.

**Strategy is chosen by `IsBatchLoadMode` and `WaitForMatching` only — never by `OperationType`.**
Read the `WaitForMatching` column first; the `OperationType` column only decides which
`MatchingOperationExecutor` method runs inside the strategy.

| # | Name | OperationType (wizard) | `WaitForMatching` | Strategy Class | Key Behavior |
|---|---|---|---|---|---|
| 1 | BatchLoad | `BatchLoad` or `CreateOnly`+`ExpectEmptyModel` | n/a (`IsBatchLoadMode` wins) | `BatchLoadStrategy` | Bulk POST/PATCH, one metric per batch, no per-record metrics |
| 2 | OperationalBatch | `BatchLoad` | n/a (`IsBatchLoadMode` wins) | `BatchLoadStrategy` | Wizard *and* samples both set S2 `OperationType=BatchLoad`, so S2 is a batch-load run, not a per-record one |
| 3A | LookupStress | `LookupOnly` | `false` | **`ContinuousStrategy`** | Per-record lookup, no create — but the wizard sets `WaitForMatching=false`, so the factory returns `ContinuousStrategy`, *not* `PerRecordStrategy` |
| 3B | ScoringTest | `LookupThenCreate` | `true` | `PerRecordStrategy` | Per-record lookup against unseen values, create when no match |
| 3C | LUBC | `CreateOnly` | `false` | `ContinuousStrategy` | Per-record create; stamps `Pending` rows for deferred metric collection |

Evidence: wizard `ApplyScenarioTemplate`,
`TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs:166-176` (S1),
`:189-197` (S2), `:212-215` (3A, `WaitForMatching=false` at `:215`), `:231-239` (3B,
`WaitForMatching=true` at `:239`), `:255-263` (3C, `WaitForMatching=false` at `:263`).
`WaitForMatching` is persisted to CustomParms at `razor.cs:581` and re-read by
`MatchingScenarioConfigBuilder.ResolveCollectionMode`
(`TestAuto.Matching/Helpers/MatchingScenarioConfigBuilder.cs:179-205`), which additionally forces it
to `false` for `BatchLoad` and for `CreateOnly`+`ExpectEmptyModel`.

`PerRecordStrategy` and `ContinuousStrategy` share identical orchestration —
`ContinuousStrategy : PerRecordStrategy` overrides only `StrategyName`
(`TestAuto.Matching/Strategies/ContinuousStrategy.cs:16-19`). All per-scenario differentiation
happens inside `MatchingOperationExecutor`.

> **Operation-type caveat — two mappings coexist and both are live.** The wizard
> (`UnifiedMatchingScenarioEditor.razor.cs:231`/`:255`), its inverse map
> (`WizardState.InferTemplateFromSettings`, `Models/WizardState.cs:633-637`), and
> `MatchingOperationExecutor`'s XML doc comments
> (`Services/MatchingOperationExecutor.cs:136` "Scenario 3b: Lookup first, create only if no match
> found" → `ExecuteLookupThenCreateAsync`; `:221` "Scenario 3c: Direct create/upsert without lookup"
> → `ExecuteCreateOnlyAsync`) **all agree**: 3B = `LookupThenCreate`, 3C = `CreateOnly`.
> The **shipped sample configs dissent**:
> `TestAuto.Matching/Samples/TestCases/Small/UnifiedMatching_Scenario3B_LookupScoring_Small.json:28`
> = `LookupOnly`, and both `..._Scenario3C_{Continuous,Interactive}_Small.json:28` =
> `LookupThenCreate`. Those samples are still consumed verbatim — nested keys resolve via
> `MatchingScenarioConfigBuilder.Read<T>` (`MatchingScenarioConfigBuilder.cs:256-280`). Treat the
> wizard as source of truth for new work and the samples as lagging, but expect to encounter both.
> Do not "correct" either side into the other. Because strategy selection ignores `OperationType`
> entirely, this divergence changes which *executor method* runs, not which strategy.
> See [[testauto-matching-scenarios]].

> **Former "Scenario 4 / PostTestCollection" is no longer a strategy.** The `CollectPostTestMetrics`
> operation type and its early-return branch were removed from this pipeline. Deferred metric collection
> for a 3C run is now a standalone scenario, `UnifiedMatchingPostRunCollectionScenario` (see
> [[testauto-matching-scenarios]]), not a branch here.

### ShouldEmitPerRecordDetail Hook

`PerRecordStrategy` exposes one protected extensibility point:

```csharp
protected virtual bool ShouldEmitPerRecordDetail(MatchingIterationContext ctx) => true;
```

It gates the `ctx.Details.Add(builtDetail)` call at the end of each record iteration in
`ProcessIterationAsync` — i.e. whether the per-record `MetricDetailUnifiedMatching` row is emitted
live. Default `true`. A subclass that returns `false` still executes the full per-record operation
(REST call, counters, sleep), it just suppresses the live metric row so a downstream collection step
can emit the authoritative row instead.

**No current subclass overrides it.** `ContinuousStrategy` overrides only `StrategyName` — 3C rows
*are* emitted live; the deferral is expressed via `MetricCollectionStatus="Pending"` stamped inside
`MatchingOperationExecutor`'s continuous branch (see below), and `UnifiedMatchingPostRunCollectionScenario`
later updates those same rows in place. Use the hook only if a future strategy genuinely needs to
suppress the live row rather than stamp-and-enrich.

## Operation Executor Mapping

### MatchingStrategyFactory.Create

Checked in this order (`TestAuto.Matching/Strategies/MatchingStrategyFactory.cs:23-29`):

| Condition                          | Strategy Returned     |
|------------------------------------|-----------------------|
| `config.IsBatchLoadMode == true`   | `BatchLoadStrategy`   |
| `config.WaitForMatching == false`  | `ContinuousStrategy`  |
| (default)                          | `PerRecordStrategy`   |

`IsBatchLoadMode` is derived, not configured:
`OperationType == BatchLoad || (ExpectEmptyModel && OperationType == CreateOnly)`
(`TestAuto.Matching/Common/MatchingScenarioConfig.cs:73-75`). `OperationType` appears nowhere else in
the selection path — a `LookupOnly` config with `WaitForMatching=false` (which is exactly what the 3A
wizard template produces) lands on `ContinuousStrategy`.

### MatchingOperationExecutor.ExecuteOperationAsync

| OperationType      | Executor Method                 | Scenarios (wizard)      | Scenarios (samples) |
|--------------------|---------------------------------|-------------------------|---------------------|
| `LookupOnly`       | `ExecuteLookupOnlyAsync`        | 3A                      | 3A, 3B              |
| `LookupThenCreate` | `ExecuteLookupThenCreateAsync`  | 3B                      | 3C                  |
| `CreateOnly`       | `ExecuteCreateOnlyAsync`        | 3C                      | —                   |
| `BatchLoad`        | `ExecuteBatchLoadAsync`         | 1, 2 (defensive path)   | 1, 2                |
| (unknown)          | `ExecuteCreateOnlyAsync`        | fallback arm of the dispatch switch | |

### MatchingOperationExecutor.CreateAndWaitForMatchAsync

All create-bearing executor methods funnel into `CreateAndWaitForMatchAsync`
(`Services\MatchingOperationExecutor.cs`, public). Callers:

- `ExecuteCreateOnlyAsync` (Scenario 2) — always
- `ExecuteLookupThenCreateAsync` (Scenario 3C) — only when the lookup found no match
- `ExecuteBatchLoadAsync` (`OperationType_BatchLoad` dispatch arm) — defensive path; `BatchLoadStrategy` itself bulk-posts without the executor
- Unknown `OperationType` values fall back to `ExecuteCreateOnlyAsync` in the dispatch switch

After the create succeeds and a record `Code` is extracted, it routes three ways
(checked in this order):

| Mode        | Condition                       | Behavior                                                                                                  | Returns       |
|-------------|---------------------------------|-----------------------------------------------------------------------------------------------------------|---------------|
| BatchLoad   | `_config.IsBatchLoadMode`       | No per-record metric collection at all                                                                     | `201 Created` |
| Continuous  | `!_config.WaitForMatching`      | Stamps `MetricCollectionStatus = MatchingConstants.MetricCollectionStatus_Pending` ("Pending") on the detail, returns immediately | `201 Created` |
| Interactive | `WaitForMatching == true` (default) | Polls via `MatchingMetricsCollector.CollectMetricsAsync` (bounded by `MaxGoldenRecordAttempts` / `WaitBetweenGoldenRecordAttempts`), stamps the four transaction timestamps, then retrieves `GoldenRecordCode` via REST | `201 Created` |

Failure paths return before any of the three branches: a failed create (or a 207
MultiStatus whose payload carries a per-record server error) returns the error
status, and a create with no returned record `Code` returns `400 BadRequest`.
The Continuous branch's `Pending` rows are what `UnifiedMatchingPostRunCollectionScenario`
later enriches in place (see [[testauto-matching-scenarios]]).

### RecordMixManager.GetNextBatchAsync

| `RecordSourceMode`    | Behavior                                    | Typical Scenarios |
|-----------------------|---------------------------------------------|-------------------|
| `ExistingMatchedOnly` | Existing matched records (fetched via REST) | 3A                |
| `NewValuesOnly`       | Holdout records unseen by matching          | 1, 3B, 3C (wizard) |
| `Mixed`               | Mix per configured percentages              | 2; also 1 and 3C in the shipped samples |

When `HasSourceSystemDistribution` is set (explicit per-source-system counts), dispatch
bypasses the mode and uses the per-source-system batch path (Scenario 1).

## Branching Topology

```
resolve strategy via MatchingStrategyFactory.Create
  |
  +--> IsBatchLoadMode?     --> BatchLoadStrategy   (Scenarios 1, 2)
  +--> !WaitForMatching?    --> ContinuousStrategy  (Scenarios 3A, 3C)
  +--> (default)           --> PerRecordStrategy    (Scenario 3B)
```

Inside the streaming loop:

```
ForEachIterationAsync:
  RecordMixManager.GetNextBatchAsync --> recordMix
  strategy.ProcessIterationAsync(iterContext)
    BatchLoadStrategy:   POST/PATCH all records, build one batch metric
    PerRecordStrategy:   for each record -> MatchingOperationExecutor.ExecuteOperationAsync
    ContinuousStrategy:  same as PerRecordStrategy

  (after loop)
  strategy.PostLoopAsync(postLoopContext)
    BatchLoadStrategy:   no-op  -- Task.CompletedTask
    PerRecordStrategy:   no-op  -- virtual, Task.CompletedTask
    ContinuousStrategy:  no-op  -- declares no override; inherits PerRecordStrategy's
```

**`PostLoopAsync` is a no-op in every implementer.** `BatchLoadStrategy.cs:175` and
`PerRecordStrategy.cs:125` both return `Task.CompletedTask`, and `ContinuousStrategy.cs:16-19`
declares no `PostLoopAsync` at all (it derives from `PerRecordStrategy` and overrides only
`StrategyName`). There is no "persist tracked records" step — 3C stamps
`MetricCollectionStatus="Pending"` inline during the loop and
`UnifiedMatchingPostRunCollectionScenario` enriches those rows later. The hook is retained on
`IMatchingStrategy` (`IMatchingStrategy.cs:36`) purely as an extension point.

## Adding a New Strategy

1. Create `TestAuto.Matching\Strategies\MyNewStrategy.cs` implementing `IMatchingStrategy`.
2. Implement `ProcessIterationAsync(MatchingIterationContext context)` — return `true` to continue, `false` to break the loop.
3. Implement `PostLoopAsync(MatchingPostLoopContext context)` — use a no-op body if no post-loop work is needed.
4. Add a new condition to `MatchingStrategyFactory.Create` to return `MyNewStrategy` when the appropriate `MatchingScenarioConfig` state is detected.
5. Add or extend an `OperationType` constant in `MatchingConstants` if the new strategy requires a new operation type.
6. If a new executor method is needed, add it to `MatchingOperationExecutor` and wire it in `ExecuteOperationAsync`.

Do not modify `RecordMixManager`, `MatchingRecordLoader`, `MatchingResultCollector`, `MatchingScenarioConfig`, `MatchingScenarioConfigBuilder`, or `ScenarioBase.ForEachIterationAsync` when adding a strategy.

## Integration Points with UnifiedMatchingScenario

### What the Strategy Receives

`MatchingIterationContext` (`Strategies\MatchingIterationContext.cs`) carries all state a strategy
needs per iteration. Everything except `RecordMix` and the three counters is `required … { get; init; }`,
so a new construction site must supply all of them:

| Member | Kind | Notes |
|---|---|---|
| `RecordMix` | `get; set;` | Current batch `List<(Record, string RecordType)>` from `RecordMixManager`; reassigned before each `ProcessIterationAsync` (`:25`) |
| `Config` | `required init` | `MatchingScenarioConfig` — operation type, flags, limits (`:29`) |
| `ScenarioConfig` | `required init` | Full `ScenarioConfiguration` (`:30`) |
| `GetRestClient` | `required init` | `Func<ScenarioConfiguration, RestSubjectArea, IRestClient>` (`:31`) |
| **`OperationExecutor`** | `required init` | The `MatchingOperationExecutor` instance the per-record strategies dispatch through (`:32`) |
| **`Logger`** | `required init` | `Serilog.ILogger` (`:33`) |
| `Details` | `required init` | Shared `List<MetricDetailBase>` all strategies append to (`:36`) |
| `ScenarioName` / `DetailTypeName` / `TargetTable` / `SelectAttributes` | `required init` | Metric-building metadata (`:39-42`) |
| **`EndpointUrl`** | `required init` | Pre-built endpoint URL, cached once per `ProcessBatchAsync` call (`:45`) |
| **`DelayBetweenIterationsAsync`** | `required init` | `Func<int, int, Task>` — the inter-iteration sleep (`:48`) |
| `TotalSent` / `TotalSucceeded` / `TotalFailed` | `get; set;` | Mutable counters shared across iterations (`:52-54`) |

The four bolded members are easy to miss: `OperationExecutor`, `Logger`, `EndpointUrl`, and
`DelayBetweenIterationsAsync` are all `required` and have no defaults.

`MatchingPostLoopContext` carries state needed for post-loop work:

- `Config`, `ScenarioConfig`, `GetRestClient`, `Logger`, `ScenarioName`

It no longer carries a `TrackedRecords` collection: 3C now stamps `MetricCollectionStatus="Pending"` rows
inline during the loop (no post-loop persistence), so `PostLoopAsync` is a no-op for all current strategies.

### What Does Not Change

| Component                              | Responsibility                                             |
|----------------------------------------|------------------------------------------------------------|
| `MatchingOperationExecutor`            | Per-operation dispatch (Lookup, Create, LookupThenCreate)  |
| `RecordMixManager`                     | Record sourcing and batch composition                      |
| `MatchingRecordLoader`                 | Initialization and record loading                          |
| `MatchingResultCollector`              | Post-validation of entity expectations                     |
| `MatchingScenarioConfig`               | Configuration model                                        |
| `MatchingScenarioConfigBuilder`        | Limit resolution and config construction                   |
| `ScenarioBase.ForEachIterationAsync`   | Loop infrastructure and time/iteration bounds              |

## File Inventory

| File                                      | Type      | Lines |
|-------------------------------------------|-----------|-------|
| `Strategies\IMatchingStrategy.cs`         | Interface | 38    |
| `Strategies\MatchingIterationContext.cs`  | DTO       | 56    |
| `Strategies\MatchingPostLoopContext.cs`   | DTO       | 20    |
| `Strategies\MatchingStrategyFactory.cs`   | Factory   | 32    |
| `Strategies\BatchLoadStrategy.cs`         | Strategy  | 188   |
| `Strategies\PerRecordStrategy.cs`         | Strategy  | 127   |
| `Strategies\ContinuousStrategy.cs`        | Strategy  | 20 (subclass of `PerRecordStrategy`; body is one `StrategyName` override) |

## Sources

- `TestAuto.Matching\Documentation\StrategyPatternDesign.md`
- `TestAuto.Matching\Strategies\MatchingStrategyFactory.cs`
- `TestAuto.Matching\Strategies\MatchingIterationContext.cs`
- `TestAuto.Matching\Strategies\PerRecordStrategy.cs`
- `TestAuto.Matching\Strategies\ContinuousStrategy.cs`
- `TestAuto.Matching\Strategies\BatchLoadStrategy.cs`
- `TestAuto.Matching\Common\MatchingScenarioConfig.cs`
- `TestAuto.Matching\Helpers\MatchingScenarioConfigBuilder.cs`
- `TestAuto.Matching\Services\MatchingOperationExecutor.cs`
- `TestAuto.Web\Components\Controls\UnifiedMatchingScenarioEditor.razor.cs`
