---
name: testauto-batch-orchestration
description: >
  Hangfire batch orchestration pipeline for TestAuto scenario execution. Use when
  understanding how scenarios are dispatched and executed through Hangfire, debugging
  batch job failures, adding new job continuations, tracing the per-scenario queue
  naming convention, working with DynamicServerManager, or understanding how
  WorkloadExecution records get their final status.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Batch Orchestration Pipeline

## Overview

All scenario execution flows through a deterministic Hangfire job chain. The chain
is initiated by `ScenarioEnqueueService` and terminates with `ResourceCollectionJob`.
Each step is a Hangfire background job, with continuations wired by the orchestrator
at enqueue time.

---

## The 8-Step Job Chain

```
ScenarioEnqueueService
  └─► ScenarioDispatcher.Dispatch                     (queue: "default")
        └─► BatchJobOrchestrator.StartBatchProcessing (queue: "default", N instances)
              └─► BatchJobOrchestrator.ProcessBatchJob (queue: "scn-{scenario}", M child jobs)
                    └─► MetricsPersistenceJob           (continuation, metrics path only)
                          └─► WorkloadExecutionUpdateJob (queue: "workload")
                                └─► ResourceCollectionJob (continuation, if feature flag enabled)
              └─► DynamicServerCleanupJob               (batch continuation, "default" queue)
              └─► MetricBatchSummaryAggregator           (batch continuation, "aggregation" queue, if CreateBatchSummaries=true)
```

**No-metrics path** (MetricDetailType == MetricDetailNone):

```
ProcessBatchJob
  └─► WorkloadExecutionUpdateJob   (chained directly after last child job, skipping MetricsPersistenceJob)
        └─► ResourceCollectionJob
```

---

## Step-by-Step Details

### 1. ScenarioEnqueueService

**File**: `TestAuto.Scenarios\BatchProcessing\ScenarioEnqueueService.cs`

Sole entry point for all scenario job creation. Reads `MaxHangfireScenarioServersCount`
from `ScenarioConfiguration.ScenarioRuntime` to determine how many orchestrator servers
to spin up. Serializes `ScenarioConfiguration` and `SecurityContext` to JSON and enqueues
`ScenarioDispatcher.Dispatch` on the `"default"` queue.

```csharp
var jobId = _jobClient.Enqueue(
    "ScenarioDispatcher", "Dispatch",
    new object[] { scenarioName, serverCount, cfgJson, secJson },
    "default");
```

### 2. ScenarioDispatcher.Dispatch

**File**: `TestAuto.Scenarios\BatchProcessing\ScenarioDispatcher.cs`

Decorated with `[DisableConcurrentExecution]` and `[AutomaticRetry(Attempts = 0)]`.
Checks the scenario's queue for already-running jobs, then enqueues up to `serverCount`
`BatchJobOrchestrator.StartBatchProcessing` jobs on the `"default"` queue, each with a
unique `SimulatedUserThreadId` (1-based server index).

Queue name is computed here and in the orchestrator: `"scn-" + QueueNameHelper.Normalize(scenarioName)`.

### 3. BatchJobOrchestrator.StartBatchProcessing

**File**: `TestAuto.Scenarios\BatchProcessing\BatchJobOrchestrator.cs`

The core orchestrator. Per call (one per Hangfire server):

1. Creates a dedicated `BackgroundJobServer` listening on the scenario queue.
2. Reads the `[ScenarioTypes]` attribute from the scenario implementation to get `DataPattern`.
3. Partitions work across servers based on `DataPattern` (see DataPattern section below).
4. Wraps all child job creation in a single `BatchJob.StartNew` call — this is the **parent batch**.
5. Registers the new server with `DynamicServerManager` keyed by `parentBatchId`.
6. Schedules `DynamicServerCleanupJob` as a batch continuation (`OnAnyFinishedState`).
7. Optionally schedules `MetricBatchSummaryAggregator` (`CreateBatchSummaries` config flag).
8. Resolves `WorkloadExecutionCode` (from `CustomParms["WorkloadExecutionCode"]` first, then
   `ScenarioEnvironment.WorkloadExecution`).
9. Chains `WorkloadExecutionUpdateJob` after the last `MetricsPersistenceJob` (metrics path)
   or after the last child job (no-metrics path).
10. Chains `ResourceCollectionJob` after `WorkloadExecutionUpdateJob` if
    `FeatureFlags:EnableResourceCollection` is true.

Returns `parentBatchId` for correlation.

### 4. BatchJobOrchestrator.ProcessBatchJob

**File**: `TestAuto.Scenarios\BatchProcessing\BatchJobOrchestrator.cs`

Runs inside the scenario-specific Hangfire server. Sets `GlobalBatchNumber` and
`TotalGlobalBatches` on `ScenarioEnvironment` before delegating to `BatchProcessor`.
Stores `BatchExecutionStatus` as a Hangfire job parameter for use by downstream jobs.

For **no-metrics scenarios**: if `summary.ExecutionStatus == "Failed"`, writes `Failed`
status directly to the `WorkloadExecution` REST record via `SetWorkloadExecutionFailedAsync`
(best-effort, does not throw).

### 5. BatchProcessor.ProcessBatchAsync

**File**: `TestAuto.Scenarios\BatchProcessing\BatchProcessor.cs`

Deserializes the JSON payload back to `List<Record>`, resolves the concrete scenario via
`IScenarioFactory`, calls `scenario.InitializeBatchAsync(config, security)`, then invokes
`ProcessBatchAsync` via reflection. Returns `MetricBatchSummaryBase`.

### 6. MetricsPersistenceJob

Continuation of each `ProcessBatchJob` child job, wired with
`JobContinuationOptions.OnlyOnSucceededState`. Skipped entirely when
`ScenarioTypeRegistry.RequiresMetrics(scenarioName)` returns `false` (i.e., scenario uses
`MetricDetailNone`).

### 7. WorkloadExecutionUpdateJob

**File**: `TestAuto.Scenarios\Jobs\WorkloadExecutionUpdateJob.cs`

Queue: `"workload"`. Reads `FeatureFlags:EnableWorkloadExecutionUpdates` (defaults `true`).
Delegates to `WorkloadExecutionUpdateHelper.UpdateWorkloadExecutionWithSummaryAsync`, passing
the comma-separated `batchJobIds` string so the helper can read `BatchExecutionStatus`
parameters from the Hangfire job store. Does not throw on failure — logs error and allows
the Hangfire job to complete so the pipeline can be investigated manually.

### 8. ResourceCollectionJob

Continuation of `WorkloadExecutionUpdateJob`, wired with
`JobContinuationOptions.OnlyOnSucceededState`. Guarded by `FeatureFlags:EnableResourceCollection`
(defaults `true`). Collects resource usage data for the completed workload execution.

---

## Per-Scenario Queue Naming

```
queueName = "scn-" + QueueNameHelper.Normalize(scenarioName)
```

`QueueNameHelper.Normalize` produces lowercase with spaces replaced by hyphens. Examples:

| ScenarioName                    | Queue name                            |
| ------------------------------- | ------------------------------------- |
| `GetRecordsByPageAndBatch`      | `scn-getrecordsbypageandbatch`        |
| `Unified Matching Scenario`     | `scn-unified-matching-scenario`       |
| `MetadataManagementScenario`    | `scn-metadatamanagementscenario`      |

A matching `BackgroundJobServer` is created in `StartBatchProcessing` listening exclusively
on this queue. Worker count is `MaxConcurrentBatchesPerHangfireScenarioServer` (minimum 1).

---

## DataPattern and Batch Partitioning

The `DataPattern` enum (defined in `ScenarioTypesAttribute`) controls how the orchestrator
divides work across Hangfire child jobs.

| Value        | Child jobs created per server      | Payload                                    |
| ------------ | ---------------------------------- | ------------------------------------------ |
| `Paged`      | One per page (page slice)          | `factory.GetRecordsForScenario(...)` page  |
| `Single`     | One per record (record slice)      | `factory.GetRecordsForScenario(...)` single record |
| `Other`      | One per server (legacy = Paged)    | Empty `List<Record>` — scenario fetches own data |
| `SelfManaged`| One per server                     | Empty payload — scenario streams its own data via `RecordMixManager` |

**`Other` in practice**: Despite the name, `DataPattern.Other` is treated as one job per
server with partition identity (`serverIndex`/`totalServers`). The scenario itself uses
`GlobalBatchNumber`/`TotalGlobalBatches` from `ScenarioEnvironment` to self-partition (e.g.,
`RecordMixManager` computes a non-overlapping slice). Per its doc comment it is the legacy
option that behaves like `Paged` — but it is NOT the enum default: `default(0)` is `Single`,
and `BatchJobOrchestrator` falls back to `Paged` for patterns it does not explicitly handle.
Used by legacy and matching-type scenarios.

**`SelfManaged`**: **one child job PER SERVER — not one job total.** `SelfManaged` takes the *same*
branch as `Other`: `if (dataPattern == DataPattern.Other || dataPattern == DataPattern.SelfManaged)`
(`BatchJobOrchestrator.cs:176`). That branch runs once per `StartBatchProcessing` invocation — i.e.
once per Hangfire server the dispatcher enqueued — and creates exactly one `ProcessBatchJob`
(`:199-211`) with an empty `List<Record>` payload plus partition identity
(`globalBatchNumber = serverIndex`, `totalGlobalBatches = totalServers`, `:196-197`) so the scenario
can self-partition via `RecordMixManager`.

Total child jobs therefore = `MaxHangfireScenarioServersCount`. You get "one job total" only when
that setting is **1** — the usual config for single-server scenarios like
`MatchingStrategyPollingScenario`, and the reason the old "one job total" wording looked right.
Set it to N and you get N concurrent self-managed jobs, each with a distinct `serverIndex`.
The in-code comment says it plainly: *"both get exactly one job here with partition identity
(serverIndex/totalServers) for self-partitioning… =N for multi-server concurrent scenarios."*

**`Single`**: Used for scenarios that need per-record isolation, e.g., `GetRecordByCodeScenario`
where each record triggers a separate REST call with independent metrics (also
`GetRecordsByCodeScenario` — note the class name has no `s` on `Code`, and it lives in the
oddly-named file `TestAuto.Records/Scenarios/CRUD/Get/GetRecordsByCodes.cs:31`, which is *not* a
type name — `DeleteRecordsByPageAndBatchScenario`, `StewardshipFilterScenario`).

**`Paged`**: Explicit paged pattern, e.g., `GetRecordsByPageAndBatchScenario`. Orchestrator
computes `totalPages = ceil(TestRecordLimit / BatchSize)` and distributes pages across servers.

---

## DynamicServerManager Lifecycle

**File**: `TestAuto.Scenarios\BatchProcessing\DynamicServerManager.cs`

Internal static class backed by a `ConcurrentDictionary<string, BackgroundJobServer>`.

| Method          | Description                                                                 |
| --------------- | --------------------------------------------------------------------------- |
| `Register(key, server)` | Called in `StartBatchProcessing` with `key = parentBatchId` after `BatchJob.StartNew` returns. |
| `DisposeServer(key)`    | Called by `DynamicServerCleanupJob` — removes and disposes the server. Idempotent. |
| `DisposeAll()`          | Called during app shutdown to dispose all remaining servers.               |
| `Count`                 | Read-only count of live registered servers.                                |

The server must remain alive until all child jobs on its queue finish. The cleanup
continuation fires `OnAnyFinishedState` (not just success), ensuring the server is
always reclaimed even when child jobs fail.

---

## No-Metrics Path

When `ScenarioTypeRegistry.RequiresMetrics(scenarioName)` returns `false`:

- `MetricsPersistenceJob` continuations are **not created** for any child job.
- `WorkloadExecutionUpdateJob` is chained directly after the **last child job** (`childJobIds.Last()`).
- If a child job fails, `SetWorkloadExecutionFailedAsync` writes `ExecutionStatus = "Failed"`
  to the `WorkloadExecution` REST record immediately (best-effort) so downstream monitoring
  can detect the failure even before `WorkloadExecutionUpdateJob` runs.

`RequiresMetrics` returns `false` when `MetricDetailType == typeof(MetricDetailNone)`.
Unknown scenarios default to `true` for safety.

---

## WorkloadExecutionCode Resolution Order

The orchestrator resolves the code to update in this order:

1. `ScenarioConfiguration.ScenarioRuntime.CustomParms["WorkloadExecutionCode"]` — manual job
   with custom code injection.
2. `ScenarioConfiguration.ScenarioEnvironment.WorkloadExecution` — normal automated job code
   set by the WebUI at dispatch time.

If neither is set, `WorkloadExecutionUpdateJob` is not scheduled and a warning is logged.

---

## Feature Flags

| Flag                                      | Default | Controls                                       |
| ----------------------------------------- | ------- | ---------------------------------------------- |
| `CreateBatchSummaries`                    | false   | Whether to run `MetricBatchSummaryAggregator`  |
| `FeatureFlags:EnableWorkloadExecutionUpdates` | true | Whether `WorkloadExecutionUpdateJob` runs      |
| `FeatureFlags:EnableResourceCollection`   | true    | Whether `ResourceCollectionJob` is scheduled   |

---

## Common Pitfalls

- **Wrong DataPattern on a new scenario**: silently creates the wrong number of child jobs.
  A scenario that self-manages data but is marked `Paged` will produce N empty-payload jobs.
  Check `[ScenarioTypes]` DataPattern first when diagnosing unexpected job counts.

- **Plugin scenarios missing from registry**: `ScenarioTypeRegistry` is populated at static
  constructor time. If plugins are loaded after startup, call `ScenarioTypeRegistry.Refresh()`
  to rebuild the map.

- **DynamicServerManager server leak**: if `DynamicServerCleanupJob` fails or never runs,
  the `BackgroundJobServer` stays registered and its worker threads remain alive. Check
  `DynamicServerManager.Count` in diagnostics.

- **WorkloadExecutionUpdateJob not running**: the job is wired as
  `OnlyOnSucceededState`. If all `MetricsPersistenceJob`s (or child jobs on the no-metrics
  path) fail, `WorkloadExecutionUpdateJob` never fires. The `SetWorkloadExecutionFailedAsync`
  best-effort write covers the no-metrics failure case but not the metrics path.

---

## Sources

- `TestAuto.Scenarios\BatchProcessing\BatchJobOrchestrator.cs`
- `TestAuto.Scenarios\BatchProcessing\BatchProcessor.cs`
- `TestAuto.Scenarios\BatchProcessing\ScenarioDispatcher.cs`
- `TestAuto.Scenarios\BatchProcessing\DynamicServerManager.cs`
- `TestAuto.Scenarios\BatchProcessing\ScenarioEnqueueService.cs`
- `TestAuto.Scenarios\Jobs\WorkloadExecutionUpdateJob.cs`
