# CLI-to-Batch Execution Pipeline (Steps 1-8 + End-to-End Trace)

Reference for the `testauto-workflow-execution` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## CLI-to-Batch Execution Pipeline

This section traces the full execution path from a CLI invocation through Hangfire batch orchestration to metrics persistence.

### Step 1 — VerbRunTestOptionsHandler (CLI Entry Point)

`VerbRunTestOptionsHandler` is the entry point when running scenarios from the command line.

**Modes**:
- `--list` flag: enumerates all registered scenarios and exits
- Sample mode: calls configuration generators to emit sample JSON files
- Normal execution: reads and validates a scenario config JSON, then calls `IScenarioExecutionService`

**How it works** (`VerbRunTestOptionsHandler.HandleAsync`, scenario-dispatch branch):
1. Requires `--filepath`; reads and validates the scenario config via
   `_validationManager.ValidateScenarioAsync(options.FilePath)` (FluentValidation), which returns the
   deserialized `(cfg, validationResult)` pair. Invalid ⇒ prints errors and returns.
2. Hands the whole config to **`IScenarioEnqueueService`** — a single call, nothing else
   (`VerbRunTestOptionsHandler.cs:150`):

```csharp
await _scenarioEnqueueService.EnqueueScenarioAsync(cfg);
```

3. The CLI does **not** build a `SecurityContext`, serialize JSON, compute a queue name, or touch
   `IScenarioExecutionService` — `ScenarioEnqueueService` does all of that. `_scenarioEnqueueService`
   is an **optional** ctor dependency (`IScenarioEnqueueService? = null`); when Hangfire batch
   orchestration isn't registered the handler prints
   *"Error: IScenarioEnqueueService is not available…"* and returns without running anything
   (`VerbRunTestOptionsHandler.cs:143-148`).

**`ScenarioEnqueueService.EnqueueScenarioAsync`** (`ScenarioEnqueueService.cs:29-61`) — the sole
implementation, shared by CLI and Web — builds the `SecurityContext` (`Environment.UserName`,
role `Administrator`, token = `ScenarioRestTarget.RestApiKey`), serializes config + security with
Newtonsoft, reads `serverCount` from `ScenarioRuntime.MaxHangfireScenarioServersCount` (default 1),
and enqueues onto the **`"default"` queue** — *not* `scn-{name}`:

```csharp
var jobId = _jobClient.Enqueue(
    "ScenarioDispatcher", "Dispatch",
    new object[] { scenarioName, serverCount, cfgJson, secJson },
    "default");                                  // ← default queue, by name, via ITestAutoBackgroundJobClient
```

The `scn-{name}` queue is created later, by `BatchJobOrchestrator`; the dispatcher only *reads* it
(`FetchedCount`) to count in-flight orchestrators.

---

### Step 2 — ScenarioExecutionService & Scenario Factory

`IScenarioExecutionService` (impl: `ScenarioExecutionService`) is the **Web/in-process** execution
entry point — the CLI dispatch branch above does not call it (it stops at `IScenarioEnqueueService`).
It receives the validated configuration and resolves the correct scenario class.

**How it works**:
1. Uses a factory or the DI container to create an instance of the scenario class matching `ScenarioConfiguration.ScenarioName` (e.g., `GetRecordByCodeScenario`)
2. Wires common dependencies (metrics, logging, REST client) via the base class
3. Calls `scenario.RunScenarioAsync(configuration, securityContext)`

---

### Step 3 — Base Class Hierarchy

Scenario classes form a multi-level inheritance chain that centralizes shared behavior:

| Class | Role |
|---|---|
| `ScenarioBase` | Root base: `ValidateConfiguration`, `CreateRequestMetric`, `RecordMetric`, sample config generation. Declares abstract `RunScenarioAsync` and `ProcessSingleRecordAsync`. |
| Specialized bases (e.g., `GetRecordBase`) | Inherits `ScenarioBase`; adds operation-specific setup (e.g., GET attribute configuration). Batch paging is handled externally by the orchestrator. |
| Concrete scenario (e.g., `GetRecordByCodeScenario`) | Inherits the specialized base; implements only scenario-specific logic. |

`RunScenarioAsync` in the new model is primarily responsible for configuration validation and pre-processing. Actual batch dispatch is handled by `BatchJobOrchestrator`.

---

### Step 4 — ScenarioDispatcher.Dispatch

`Dispatch(string scenarioName, int serverCount, string configJson, string securityJson)` — decorated `[DisableConcurrentExecution(timeoutInSeconds: 30)]` and `[AutomaticRetry(Attempts = 0)]`.

**How it works**:
1. Deserializes the two JSON blobs back into `ScenarioConfiguration` and `SecurityContext`
2. Counts in-flight work via `monitor.FetchedCount("scn-{scenarioName}")` (the scn- queue is used here for **counting**)
3. Calculates `toEnqueue = Math.Max(0, serverCount – running)`
4. Partitions the record space (`TestRecordLimit`) across the orchestrators and enqueues up to `toEnqueue` new `BatchJobOrchestrator.StartBatchProcessing` jobs on the **`default`** queue:

```csharp
for (int i = 0; i < toEnqueue; i++)
{
    var orchJob = Job.FromExpression<BatchJobOrchestrator>(
        o => o.StartBatchProcessing(scenarioName, threadId, desired, orchestratorCfg, batchSize, string.Empty, security));
    _jobs.Create(orchJob, new EnqueuedState(queue: "default"));
}
```

---

### Step 5 — BatchJobOrchestrator (Hangfire Batch Mechanics)

`BatchJobOrchestrator.StartBatchProcessing` splits work into pages and uses Hangfire.Pro batches.

**How it works**:
1. Uses a `_recordRetriever` delegate to fetch pages of records from the configured data source
2. Calls `BatchJob.StartNew` to open a Hangfire.Pro parent batch
3. Enqueues one `ProcessBatchJob` per page onto the `scn-{scenarioName}` queue:

```csharp
parent.Create(() => ProcessBatchJob(...), new EnqueuedState(queue: scenarioQueue));
```

4. Two distinct continuation mechanisms fire (they are **not** both batch-complete continuations):
   - **Per-child**: each `ProcessBatchJob` gets a `BackgroundJob.ContinueJobWith<MetricsPersistenceJob>(childJobId, …, OnlyOnSucceededState)` attached to it. `MetricsPersistenceJob` has **no `[Queue]` attribute**, so it runs on the **`default`** queue, once per succeeded child job — it is NOT a batch-complete continuation.
   - **Batch-complete**: when **all** page jobs complete, Hangfire.Pro fires one batch continuation — `MetricBatchSummaryAggregator` on the `"aggregation"` queue (gated on `CreateBatchSummaries=true`).
   - The `"persistence"` queue is declared on `FollowOnServer` but is **vestigial** — no job is ever enqueued to it.

---

### Step 6 — BatchProcessor

`BatchProcessor` (implements `IBatchProcessor`) handles individual page batches.

**How it works**:
1. Receives a JSON batch string
2. Deserializes into a list of `Record` objects
3. Processes each record (calls external services, performs calculations)
4. Records per-record metrics
5. Returns a `BatchSummary`

---

### Step 7 — MetricBatchSummaryAggregator

Runs on the `"aggregation"` queue after all page jobs complete.

**How it works**:
1. Pulls individual batch results from Hangfire
2. Merges them into a single `IMetricBatchSummary`
3. Writes a JSON summary file
4. Dashboard display name (`MetricBatchSummaryAggregator.cs:68`) — Hangfire **positional** token, not a
   named one: `[DisplayName("{0} Batch Summary")]` (`{0}` = the first method argument, `scenarioName`)
   - Example: `GetRecordByCodeScenario Batch Summary`

---

### Step 8 — MetricsPersistenceJob

Runs on the **`default`** queue as a **per-child-job** continuation — one instance is attached to each `ProcessBatchJob` via `BackgroundJob.ContinueJobWith<MetricsPersistenceJob>(childJobId, …, OnlyOnSucceededState)`. It is NOT a batch-complete continuation and never targets the `"persistence"` queue (that queue, declared on `FollowOnServer`, is vestigial). `MetricsPersistenceJob` has no `[Queue]` attribute.

**How it works**:
1. Reads detailed metrics from each batch
2. Transforms them to `Record` model objects
3. POSTs them to the metrics REST endpoint
4. Dashboard display name (MetricsPersistenceJob.cs:48): `[DisplayName("{0} Server {1} Batch {2} of {3} Persist Metrics")]`
   - Example: `GetRecordByCodeScenario Server 1 Batch 2 of 3 Persist Metrics`

---

### Concurrency: serverCount

The `serverCount` parameter passed to `ScenarioDispatcher.Dispatch` controls how many `BatchJobOrchestrator` runs are enqueued (`toEnqueue = serverCount – running`, where running = `FetchedCount` on the scn- queue).

| Setting | Behavior |
|---|---|
| `serverCount = 1` | One orchestrator (and its batch) runs at a time |
| `serverCount = 2` | Two orchestrators queued immediately (if none running) |
| WorkerCount = 1 on queue | Orchestrators execute sequentially even if multiple are queued |
| WorkerCount >= 2 | True parallel execution of multiple orchestrators |

`ScenarioDispatcher` re-checks the running count each time `Dispatch` fires, so it only fills up to `serverCount`. (`MaxRunningScenarioCount` exists only as a metric property — it does not gate dispatch.)

---

### End-to-End Trace Summary

```
config.json
  └─► VerbRunTestOptionsHandler   (validate only)
        └─► IScenarioEnqueueService.EnqueueScenarioAsync(cfg)
                build SecurityContext + serialize cfg/security
                enqueue ──► ScenarioDispatcher.Dispatch  [queue: default]
                        check running orchestrators (FetchedCount on scn-{name})
                        enqueue up to serverCount ──►
                            BatchJobOrchestrator.StartBatchProcessing [queue: default]
                                open Hangfire.Pro parent batch
                                per page: ProcessBatchJob [queue: scn-{name}]
                                    BatchProcessor.ProcessBatchAsync
                                        → record metrics → BatchSummary
                                    ContinueJobWith (per child, OnlyOnSucceeded):
                                        MetricsPersistenceJob [queue: default]
                                            → transform → POST to metrics REST endpoint
                                on all pages done (batch continuation, if CreateBatchSummaries):
                                    MetricBatchSummaryAggregator [queue: aggregation]
                                        → merge summaries → write JSON file
```

---
