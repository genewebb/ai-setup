# Deep Dive — Scores, Dedup vs Match-Merge, Strategy Design, Performance Tuning

Reference for the `testauto-matching-scenarios` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Deep Dive: Matching Scores and Strategy Design

### Matching Score Interpretation — Metrics by Scenario

Each scenario emits a distinct metric shape. Misreading which shape applies to a scenario is a common source of confusion when analyzing results.

#### Scenarios 1 and 2 — 6 Phase Buckets (Batch-Level)

Batch scenarios emit one `MetricDetailUnifiedMatching` per batch (not per record). Each metric row covers six timing phases collected from the Matching DB:

| # | Metric | Description | Source |
|---|--------|-------------|--------|
| 1 | Indexing Time | Time to build/update search indexes | Matching DB |
| 2 | Scoring Time | Time to calculate match scores | Matching DB |
| 3 | Matching Time | Time to determine match clusters | Matching DB |
| 4 | Survivorship Time | Time to apply survivorship rules | Matching DB |
| 5 | Master Indexing Time | Time to index golden records | Matching DB |
| 6 | Total Time | End-to-end batch duration | Calculated |

These phase timings are also collected separately by `MatchingResultsScenario` (a distinct scenario class that calls the Monitor REST API using `StartMarkerText`/`EndMarkerText` boundaries and emits exactly six `MetricDetailMatchingResults` rows into `UnifiedMatchingApiExecutionTimings`).

#### Scenario 3A — Per-Lookup Throughput Metrics

| Metric | Description |
|--------|-------------|
| TotalLookups | Lookups completed in test duration |
| AverageResponseTime | Mean lookup response time (ms) |
| Min/MaxResponseTime | Response time bounds |
| MatchesFound | Lookups that returned at least one match |
| NoMatchesFound | Lookups that returned no matches |
| TotalErrors | Failed lookups |
| Throughput | Lookups per second sustained |

**Score signal**: `MatchesFound` vs `NoMatchesFound` ratio is the primary signal for scoring depth. When using `Scenario3ARecordSource=TargetEntity` (existing indexed records), nearly all lookups should return matches — a low match rate indicates filtering or strategy misconfiguration. When using `Scenario3ARecordSource=ModelSource` with original sources (1, 2, 3), expect zero or near-zero matches since those are unseen values. With mutated sources (20, 30, 40), expect partial matches — these are near-miss values that exercise fuzzy scoring paths.

#### Scenario 3B — Per-Lookup Scoring Metrics

Scenario 3B uses `RecordSource=NewValuesOnly` in both mappings, but its `OperationType` differs by source:

| Source | OperationType | Effect |
|---|---|---|
| Wizard `Template_Scenario3B` ("Scenario 3B: Lookup + Create", `UnifiedMatchingScenarioEditor.razor.cs:231`) | `LookupThenCreate` + `WaitForMatching=true` | lookup, then create when no match — full per-record end-to-end timing |
| Shipped sample `UnifiedMatching_Scenario3B_LookupScoring_Small.json:28` | `LookupOnly` | lookup only, no create |

Use the wizard mapping for new work. Either way, because the lookup values are unseen the run
exercises the fuzzy scoring paths, and the lookup leg emits the same per-lookup throughput shape as 3A:

| Metric | Description |
|--------|-------------|
| TotalLookups | Lookups completed in test duration |
| AverageResponseTime | Mean lookup response time (ms) |
| Min/MaxResponseTime | Response time bounds |
| MatchesFound | Lookups that returned at least one match |
| NoMatchesFound | Lookups that returned no matches |
| TotalErrors | Failed lookups |
| Throughput | Lookups per second sustained |

#### Scenario 3C — Create + Match

3C's `OperationType` / `RecordSource` also differ by source:

| Source | OperationType | RecordSource |
|---|---|---|
| Wizard `Template_Scenario3C` ("Scenario 3C: Batch Create", `UnifiedMatchingScenarioEditor.razor.cs:255-256`) | `CreateOnly` | `NewValuesOnly` (`NewPercent=100`, `CreatePercent=100`) |
| Shipped samples `UnifiedMatching_Scenario3C_{Continuous,Interactive}_Small.json:28-29` | `LookupThenCreate` | `Mixed` (85% Changed / 15% New) |

Use the wizard mapping for new work. Note the wizard template is `WaitForMatching=false`, i.e. the
Continuous variant; the Interactive variant is reached by flipping `WaitForMatching` (the toggle is
gated on `ShowWaitForMatchingOptions => IsLookupThenCreate`, `WizardState.cs:263`, so on a `CreateOnly`
3C config the wizard does not surface it — set it via Custom Parameters or use the Interactive sample).
It has two variants:

**3C-Interactive** (`WaitForMatching=true`) — waits for the golden record after each create, so it emits per-record end-to-end timing:

| Metric | Calculation |
|--------|-------------|
| LookupDuration | LookupResponseTime − LookupRequestTime |
| CreateDuration | CreateResponseTime − CreateRequestTime |
| MatchingDuration | MatchTransactionTime − CreateTransactionTime |
| SurvivorshipDuration | SurviveTransactionTime − MatchTransactionTime |
| TotalEndToEndDuration | SurviveTransactionTime − LookupRequestTime |
| P50/P95/P99 Latency | Percentile distributions across all records in the run |

**3C-Continuous** (`WaitForMatching=false`) — emits `TotalRecordsCreated` and `CreateThroughput` only; the matching/survivorship timings are deferred to `UnifiedMatchingPostRunCollectionScenario`, which reads this run's `Pending` rows on `UnifiedMatchingApiExecution` and updates them **in place** with these fields:

| Metric | Description |
|--------|-------------|
| CreateRequestTime | When the 3C run sent the create API request |
| CreateResponseTime | When the 3C run received the create API response |
| CreateDurationMs | Response − Request (ms) |
| CreateTransactionTime | Profisee transaction timestamp for the create |
| MatchTransactionTime | Profisee transaction timestamp for matching completion |
| MatchingDurationMs | MatchTransaction − CreateTransaction (ms) |
| SurviveTransactionTime | Profisee transaction timestamp for survivorship |
| SurvivorshipDurationMs | Survive − Match transaction time (ms) |
| TotalEndToEndDurationMs | CreateRequest → Survive (ms) |
| GoldenRecordCode | Assigned golden record code |
| SourceWorkloadExecution | WorkloadExecution of the source 3C run |

---

### Deduplication vs. Match-Merge Decision Rules

The choice between scenario modes determines how matching pipeline coverage is measured and whether deduplication (batch clustering) or LUBC (lookup-based merge) is exercised.

#### When to Use BatchLoad (Scenarios 1/2) — Deduplication Path

Use `OperationType=BatchLoad` when:
- Measuring throughput of the bulk ingest pipeline with Continuous Matching **off**
- Evaluating initial deduplication after strategy execution (Scenario 1)
- Testing nightly incremental loads with already-matched data (Scenario 2)
- Metrics are coarse (per-batch, not per-record)

Continuous Matching is a Profisee platform setting that must be toggled out-of-band (e.g. via a
matching-strategy update scenario or a Configure/CLU step) — the scenario config cannot turn it on.
A `ContinuousMatching` CustomParm key *is* declared (`MatchingConstants.cs:270`) and the S1/S2 samples
set it, but no code in `TestAuto.Matching` reads it, so it has no runtime effect. See the
declared-but-dead note in *CustomParms Reference → Core Parameters*.

#### When to Use LookupOnly / LookupThenCreate — LUBC Path

Use lookup-based scenarios when:
- Continuous Matching is **on** and records are matched at ingest time
- End-to-end latency per user-facing operation is the measurement goal

| Goal | Scenario | OperationType (wizard) | OperationType (samples) | WaitForMatching |
|------|----------|------------------------|-------------------------|-----------------|
| Lookup throughput only (existing matched) | 3A | `LookupOnly` | `LookupOnly` | `false` |
| Lookup scoring on new values | 3B | `LookupThenCreate` | `LookupOnly` | wizard `true` |
| Lookup + create + wait for golden record | 3C-Interactive | `CreateOnly` | `LookupThenCreate` | `true` |
| Bulk create without waiting (deferred metrics) | 3C-Continuous | `CreateOnly` | `LookupThenCreate` | `false` |

Only the `WaitForMatching` column drives strategy selection — the `OperationType` column drives
executor-method dispatch. 3A's wizard `WaitForMatching=false` means a wizard-built 3A resolves to
`ContinuousStrategy`, not `PerRecordStrategy` (see [[testauto-matching-strategy-pattern]]).

#### WaitForMatching Decision

`WaitForMatching=true` (Scenario 3C-Interactive):
- Polls for golden record after each create (up to `MaxGoldenRecordAttempts × WaitTimeBetweenGoldenRecordAttemptsMs`)
- Metrics collected in real time — full end-to-end timing per record
- Strategy: `PerRecordStrategy`
- Use when measuring per-record latency under concurrent load

`WaitForMatching=false` (Scenario 3C-Continuous):
- Creates records without polling; stamps each create row on `UnifiedMatchingApiExecution` with `MetricCollectionStatus="Pending"` and the matching/survivorship columns null
- **No post-loop persistence step and no parallel tracking entity** — the `Pending` rows *are* the work list
- Matching/golden/survive timing is filled in later by the standalone `UnifiedMatchingPostRunCollectionScenario`, which queries this run's `Pending` rows and updates them in place (status → `Collected`/`Failed`)
- Strategy: `ContinuousStrategy`
- Use when maximizing create throughput and collecting timing separately

#### Post-Run Collection Concurrency Model

`UnifiedMatchingPostRunCollectionScenario` (formerly the in-wizard "Scenario 4") runs as a **single Hangfire job** (`MaxHangfireScenarioServersCount` must be **1**) that parallelizes in-process via `SemaphoreSlim(ConcurrentThreads)`. This differs from the standard multi-server TestAuto batch pattern (where `BatchJobOrchestrator` splits work across N Hangfire jobs).

Rationale: it reads the source run's `Pending` rows from `UnifiedMatchingApiExecution` rather than pushing records — partitioning across multiple jobs would require synthetic "work item" records and concurrent `MetricCollectionStatus` writes with no benefit. Unprocessed rows remain in `Pending` state and are picked up on re-run; accidental double-runs find 0 pending rows and emit an empty summary.

---

### Strategy Pattern Design — Scenario Variant Selection

`MatchingStrategyFactory.Create(config)` resolves exactly one strategy from two boolean flags:

```csharp
// Strategies\MatchingStrategyFactory.cs
if (config.IsBatchLoadMode)   return new BatchLoadStrategy();
if (!config.WaitForMatching)  return new ContinuousStrategy();
return new PerRecordStrategy();
```

**Why 3 strategies, not 5**: Scenarios 2, 3A, 3B, and 3C-Interactive share identical orchestration (per-record loop → `MatchingOperationExecutor` dispatch → individual metric detail building). The differentiation happens inside `MatchingOperationExecutor` (unchanged). Splitting these into 4 strategies would duplicate the per-record loop with no benefit.

#### IMatchingStrategy Interface

```csharp
// Strategies\IMatchingStrategy.cs
internal interface IMatchingStrategy
{
    // Process one iteration (one batch from RecordMixManager).
    // Return true to continue, false to break the loop.
    Task<bool> ProcessIterationAsync(MatchingIterationContext context);

    // Called after the streaming loop. No-op for all current strategies
    // (3C now stamps Pending rows inline during the loop, not post-loop).
    Task PostLoopAsync(MatchingPostLoopContext context);
}
```

#### Context DTOs

`MatchingIterationContext` carries mutable per-iteration state plus stable references:

| Property | Type | Notes |
|----------|------|-------|
| RecordMix | `List<(Record Record, string RecordType)>` | Set per iteration |
| Config | `MatchingScenarioConfig` | Parsed from CustomParms |
| ScenarioConfig | `ScenarioConfiguration` | Runtime config |
| Details | `List<MetricDetailBase>` | Accumulates metric rows |
| GetRestClient | `Func<ScenarioConfiguration, RestSubjectArea, IRestClient>` | REST client factory |
| TotalSent / TotalSucceeded / TotalFailed | `int` | Mutable counters shared across iterations |
| ScenarioName / DetailTypeName / TargetTable / SelectAttributes | `string / List<string>` | Metric building metadata |

`MatchingPostLoopContext` carries post-loop state:

| Property | Type | Notes |
|----------|------|-------|
| Config | `MatchingScenarioConfig` | |
| ScenarioConfig | `ScenarioConfiguration` | |
| GetRestClient | `Func<...>` | REST client factory |
| Logger | `ILogger` | |
| ScenarioName | `string` | |

> `MatchingPostLoopContext` no longer carries a `TrackedRecords` collection — 3C stamps `Pending`
> rows inline during the loop, so there is no post-loop set of records to hand off.

#### Strategy Responsibilities

> **Owned by [[testauto-matching-strategy-pattern]] — not duplicated here.** That skill carries the
> per-scenario strategy table (scenario → `OperationType` → `WaitForMatching` → resolved strategy),
> the per-strategy file/line inventory, and the "`PostLoopAsync` is a no-op in every implementer"
> evidence. A copy of that table lived here for three audits and was wrong each time (it labelled
> 3A as `PerRecordStrategy`, when the wizard's `WaitForMatching=false` for 3A
> — `UnifiedMatchingScenarioEditor.razor.cs:215` — routes it to `ContinuousStrategy`). Read the
> routing rule from the factory snippet above and the resolved per-scenario mapping from the
> strategy-pattern skill; do not re-add a second table.

`MatchingOperationExecutor.ExecuteOperationAsync` dispatches inside the per-record strategies
(`PerRecordStrategy` and its subclass `ContinuousStrategy`):

```
// TestAuto.Matching/Services/MatchingOperationExecutor.cs:68-83
LookupOnly        → ExecuteLookupOnlyAsync        (:70-71)   wizard 3A  | samples 3B
LookupThenCreate  → ExecuteLookupThenCreateAsync  (:73-74)   wizard 3B  | samples 3C
CreateOnly        → ExecuteCreateOnlyAsync        (:76-77)   wizard 3C
BatchLoad         → ExecuteBatchLoadAsync         (:79-80)   defensive — BatchLoadStrategy bulk-posts itself
(unmatched)       → ExecuteCreateOnlyAsync        (:82)      silent default for an unknown OperationType
```

The scenario labels follow the wizard/sample split documented in the goal table above — the
dispatch arms themselves are keyed only on `OperationType`, never on a scenario number.

Post-run metric collection is no longer a branch in `ProcessBatchAsync`; it is the standalone `UnifiedMatchingPostRunCollectionScenario`, which shares no infrastructure with the streaming loop (no `RecordMixManager`, no `ForEachIterationAsync`, no `MatchingOperationExecutor`) — it reads `Pending` rows and updates them in place.

#### Unchanged Components (Strategy Extraction Did Not Touch)

- `MatchingOperationExecutor` — per-operation dispatch
- `RecordMixManager` — record sourcing and keyset pagination
- `MatchingRecordLoader` — initialization
- `MatchingResultCollector` — post-validation
- `MatchingScenarioConfig` / `MatchingScenarioConfigBuilder`
- `ScenarioBase.ForEachIterationAsync` — loop infrastructure

---

### Performance Tuning Indicators

Use these signals to diagnose when match counts or timing diverge from expected.

#### Match Count Divergence

| Symptom | Likely Cause | Action |
|---------|--------------|--------|
| 3A `MatchesFound` near 0 (TargetEntity mode) | `MatchStatusFilter` excludes populated statuses, or entity has no matched records | Verify filter codes `["20","30","40","50"]` match entity domain; confirm model is indexed |
| 3A `MatchesFound` near 100% (ModelSource/Original mode) | Holdout offset too low — records overlap with S1 load | Increase `HoldoutStartAfterRow` past S1 consumption point |
| 3C-Interactive golden record timeout (`"Golden record timeout"`) | Matching/survivorship not completing within poll window | Increase `MaxGoldenRecordAttempts` or `WaitTimeBetweenGoldenRecordAttemptsMs`; check CM is enabled |
| S2 `NoMatchesFound` unexpectedly high | `ChangedSourceSystems` routing mutated records through original path | Confirm `ChangedSourceSystems` uses mutated codes (20, 30, 40), not original (1, 2, 3) |

#### Scoring Depth Control (Scenario 3A ModelSource Mode)

The source system selection controls how hard the scoring engine works:

| Source Type | Source Systems | Effect |
|-------------|----------------|--------|
| Original (unseen) | 1, 2, 3 | Completely new values — forces full fuzzy scoring; expect near-zero matches |
| Mutated (near-miss) | 20, 30, 40 | Typos/abbreviations of loaded records — exercises near-miss scoring paths; expect partial matches |

Use original sources to stress the scoring engine at maximum load. Use mutated sources to test precision of the fuzzy match thresholds.

#### Mutation Intensity (Scenario 2 Changed Records)

`UpdateVariationLevel` (Light / Medium / Heavy) controls how aggressively matching attributes are mutated at runtime before loading Changed records. Higher intensity means more attribute drift, which forces more re-scoring. Use Medium as a baseline; Heavy is appropriate for stress-testing survivorship rule coverage.

#### Throughput vs. Latency Tradeoff

| If... | Then... |
|-------|---------|
| `MaxHangfireScenarioServersCount` is high and throughput is lower than expected | Check that `TestRecordLimit` is partitioned correctly — each server must have a non-overlapping partition |
| 3C-Interactive `TotalEndToEndDuration` P99 spikes relative to P50 | Indicates golden record polling timeouts for a tail of records; review CM queue depth |
| 3C `CreateThroughput` is high but Scenario 4 shows high `MatchingDurationMs` | CM queue is backing up; look at queue depth and server resources |
| S1/S2 Scoring Time bucket is disproportionate | Fuzzy attribute count in strategy may be high; review matching strategy attribute configuration |

#### Scenario 4 Re-run Safety

Scenario 4 filters by `MetricCollectionStatus = 'Pending'`. Records processed successfully move to `Collected`; failures move to `Failed`. Re-running picks up only remaining `Pending` records. To re-collect failed records, reset their status back to `Pending` in the tracking entity before re-running.
