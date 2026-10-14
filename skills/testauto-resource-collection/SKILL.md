---
name: testauto-resource-collection
description: >
  Server resource-metrics collection in TestAuto — harvests CPU/memory/availability for a
  WorkloadExecution's run window from Prometheus into WorkloadExecutionResourceSummary records. Use
  when working on ResourceCollectionScenario, ResourceCollectionService, ResourceMetricsUpdateJob, or
  the TestAuto.External.Prometheus layer; diagnosing summaries stuck Pending or Failed; the attempt
  state machine; query window padding and adaptive step sizing; or adding a resource metric or
  metrics backend.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Resource Collection

This feature collects per-server resource utilization (CPU, memory, availability) for the time window
of a `WorkloadExecution` and writes the results into `WorkloadExecutionResourceSummary` records. It
spans four layers: an external Prometheus client/query layer (`TestAuto.External.Prometheus`), a
service that seeds placeholder rows (`ResourceCollectionService`), a recurring Hangfire job that fills
them in (`ResourceMetricsUpdateJob`), and an on-demand scenario alternative (`ResourceCollectionScenario`).

> `testauto-prometheus-config` documents the *configuration* (appsettings keys, PromQL design,
> scrape/padding rationale). This skill documents the *implementation* — the classes, the flow, and the
> state machine that config drives.

## When to Use

- "Why are my `WorkloadExecutionResourceSummary` records stuck on `Pending`?" / "…marked `Failed`?"
- "How does TestAuto get CPU/memory numbers for a workload run?"
- "Add a disk/network metric to resource collection" / "point it at a different Prometheus"
- "What does `ResourceCollectionScenario` / `ResourceMetricsUpdateJob` / `PrometheusQueryHelper` do?"
- Editing `ResourceCollectionQueryBuilder` PromQL or `ResourceAggregator` percentile/trend math
- Tuning query window padding or the adaptive step for short workloads

## Architecture & Lifecycle

The metrics are produced asynchronously because Prometheus data for a run window is not available until
*after* the scrape interval has elapsed. So collection is split into **seed** then **fill**:

```
WorkloadExecution completes
        │
        ▼
ResourceCollectionService.CollectAndPersistAsync(workloadExecutionCode, cfg)
   • GET WorkloadExecution by code (GetRecordsByCodesAsync)
   • resolve 3 server names: AppServer + DbServer (from the record),
     TestServer (= cfg.ScenarioEnvironment.TargetEnvironmentName)
   • create up to 3 placeholder WorkloadExecutionResourceSummary rows:
        CollectionStatus = "Pending", CollectionStatusAttempts = 0, all metrics 0
        (empty server-name slots and duplicate server names are skipped, not failed)
   • returns true when no create attempt failed (recordsFailed == 0)
        │
        ▼  (later, repeatedly)
ResourceMetricsUpdateJob.ExecuteAsync()   ── recurring, [Queue("scheduled")]
   • page all Pending WorkloadExecutionResourceSummary rows (PageSize default 1000)
   • group by WorkloadExecution; fetch its StartTime/EndTime
        (EndTime missing ⇒ still running ⇒ use UtcNow)
   • per server: increment CollectionStatusAttempts, query Prometheus for the window
        - got data points ⇒ write Max/Avg/Low CPU+Memory, CollectionStatus = "Completed"
        - no data + attempts < MaxCollectionAttempts ⇒ leave Pending (will retry)
        - no data + attempts >= MaxCollectionAttempts ⇒ CollectionStatus = "Failed"
```

`ResourceCollectionScenario` is a **third, on-demand** entry point — an `IScenario` you can run as a
workflow step that does a *single-attempt* version of the fill (see below). The recurring job is the
normal path; the scenario is the manual/forced path.

### Pending → Completed / Failed state machine (the #1 diagnostic)

Each `WorkloadExecutionResourceSummary` row carries `CollectionStatus` ∈ {`Pending`, `Completed`,
`Failed`} and a `CollectionStatusAttempts` counter. When a row is stuck:

| Symptom | Cause |
|---|---|
| Stays `Pending` forever | No Prometheus data points for the window **and** attempts haven't reached `MaxCollectionAttempts` yet — or the recurring job isn't running (check Hangfire `scheduled` queue). |
| Flips to `Failed` | Reached `MaxCollectionAttempts` (default 5) with still no data — server not scraped, wrong instance label, or window outside retention. |
| Never created at all | The seed step (`CollectAndPersistAsync`) returned false — a placeholder create genuinely failed (`recordsFailed > 0`) or the WorkloadExecution wasn't found in the REST client's environment. Note: an empty or duplicate server name just skips that slot (no row, no failure). |
| `ResourceCollectionScenario` leaves it Pending | The scenario only processes WorkloadExecutions whose `ExecutionStatus == "Complete"` and does **one** attempt with no retry; no data ⇒ left Pending for the recurring job. |

## `ResourceCollectionScenario` (on-demand `IScenario`)

`TestAuto.Scenarios\Scenarios\Resources\ResourceCollectionScenario.cs`

```csharp
[ScenarioTypes(
    typeof(ScenarioConfigurationOnly),   // TestDataType
    typeof(MetricDetailBase),
    typeof(MetricBatchSummaryBase),
    RestSubjectArea.ScenarioMgt,
    DataPattern.Single,                  // one Hangfire job, no generated records
    CustomParmsEditorType.Default)]
[ScenarioDisplay("Resources", Hidden = false)]
public class ResourceCollectionScenario : IScenario
```

- **No CustomParms required.** It deliberately ignores config parameters and instead queries **all**
  `WorkloadExecutionResourceSummary` rows where `CollectionStatus eq 'Pending'`, groups by
  `WorkloadExecution`, and processes them.
- **Complete-only.** It skips any WorkloadExecution whose `ExecutionStatus` is not `"Complete"`.
- **Single attempt, no retry.** Unlike the recurring job it does not increment attempts or mark
  `Failed`; if Prometheus returns no data it logs a warning and leaves the row `Pending`.
- On success it writes `MaxCpu/AvgCpu/LowCpu/MaxMemory/AvgMemory/LowMemory` and
  `CollectionStatus = "Completed"`, then `UpdateRecordsAsync`.
- It resolves a scenario-specific ScenarioMgt REST client via `IRestClientFactory.GetClient(cfg,
  RestSubjectArea.ScenarioMgt)` (honors per-scenario REST overrides), and creates a DI scope in its
  constructor to resolve `MetricsContext`, `IResourceCollectionService`, and `PrometheusQueryHelper`.

## `ResourceMetricsUpdateJob` (the recurring filler)

`TestAuto.Scenarios\Jobs\ResourceMetricsUpdateJob.cs` — `[Queue("scheduled")]`, `ExecuteAsync` is
`[AutomaticRetry(Attempts = 2)]`.

- Reads `ResourceCollection:MaxCollectionAttempts` (default **5**) and `ResourceCollection:PageSize`
  (default **1000**).
- Pages the full Pending set: first a `PageSize=1` probe to read `TotalCount`, then a `while` loop
  fetching `PageSize` pages until a short page signals the last one. (This is the manual paging idiom —
  the REST `GetRecordsAsync` page contract, not `GetAllRecordsAsync`.)
- For each server row: increments `CollectionStatusAttempts` **before** querying, queries Prometheus for
  `[StartTime, EndTime]` (EndTime missing ⇒ `UtcNow`, so running executions still collect), then applies
  the state machine above. Per-row failures are caught so one bad server doesn't abort the batch.
- Logs under `LogTagConstants.Metrics`.

## `ResourceCollectionService` (the seeder)

`TestAuto.Scenarios\Services\ResourceCollectionService.cs` implements `IResourceCollectionService`.

- `CollectAndPersistAsync(workloadExecutionCode, scenarioConfiguration)` is the **placeholder-creation**
  path described in the lifecycle. It makes **up to 3 create attempts — one per server slot, not 3
  retries** — and can legitimately create fewer than 3 rows
  (`ResourceCollectionService.cs:331-405`):

  ```csharp
  var serverList = new[] { servers.ApplicationServer, servers.DatabaseServer, servers.TestServer };  // :331
  var seenServers = new HashSet<string>(StringComparer.OrdinalIgnoreCase);                            // :341
  foreach (var serverName in serverList)
  {
      if (string.IsNullOrWhiteSpace(serverName)) { recordsSkipped++; continue; }   // :347-355 empty slot
      if (!seenServers.Add(serverName))          { recordsSkipped++; continue; }   // :357-364 duplicate name
      … CreateRecordsAsync("WorkloadExecutionResourceSummary", …)                  // :385
  }
  ```

  Both skips are **`recordsSkipped++`, never `recordsFailed++`** — so a config-only step with no
  app/db server, or one where all three slots collapse to the same `ServerNames:TestServerName`
  fallback (`DetermineServerNames`, `:155-173`), yields 1 row and still returns success. Each
  created row gets `CollectionStatus = "Pending"`, `CollectionStatusAttempts = 0`, all metrics 0
  (`:369-380`).

  > Don't confuse the **3 server slots** here with the **`MaxCollectionAttempts` (default 5)** retry
  > counter that `ResourceMetricsUpdateJob` increments later. The seeder never retries anything.
- `GetServerType(serverName)` looks up `ServerProfileType` from `IReferenceDataCache`
  (`EnsureLoadedAsync` then `GetServerProfileType`), falling back to `"Unknown"`.
- It also contains a `CollectResourceMetricsAsync` helper that demonstrates the **window-padding**
  technique for `rate()` stability — pad start by `ResourceCollection:QueryPaddingStartSeconds`
  (default 120s) and end by `QueryPaddingEndSeconds` (default 30s), and use a **dynamic rate window**
  (~40% of padded duration, floored at 30s, capped at the configured `RateWindow`). This is the right
  reference if you need to query a short window without `rate()` returning empty.
- Logs under `LogTagConstants.ResourceCollection`.

## `TestAuto.External.Prometheus` — the query layer

| Class | Responsibility |
|---|---|
| `IPrometheusClient` / `PrometheusClient` | Thin HTTP client. `QueryAsync(query)` → `/api/v1/query`; `QueryRangeAsync(query, start, end)` → `/api/v1/query_range`. `BaseAddress` from `RestClients:Prometheus:BaseUrl`; paths from `Prometheus:QueryPath`/`QueryRangePath`. Newtonsoft-deserializes into `QueryResult`/`QueryData`/`QueryResultItem` (defined in this file). |
| `ResourceCollectionQueryBuilder` | Builds Windows-exporter PromQL. `BuildCpuQuery` (uses `rate()` not `irate()` for stable summaries; instance label `{server}:9182`), `BuildMemoryQuery`, `BuildDiskQuery`, `BuildNetworkQuery`, `BuildAvailabilityQuery` (`up{...}`). Two `[Obsolete]` "optimized" variants are not used — don't revive them. |
| `ResourceAggregator` | Reduces a `QueryResult` to numbers: `AggregateResults` (Min/Max/Average/DataPoints → `AggregatedMetrics`), `CalculatePercentile`/`CalculatePercentiles` (ceiling-index method), `CalculateTrend` (least-squares slope; +ve = rising). Handles both range (`item.Values`) and instant (`item.Value`) result shapes. |
| `PrometheusQueryHelper` | Orchestrator. `GetServerResourceMetricsAsync` runs CPU + Memory + availability **in parallel** (`Task.WhenAll`) → `ServerResourceMetrics`; `GetMultipleServerResourceMetricsAsync` fans across servers; `GetCpuMetricsAsync`/`GetMemoryMetricsAsync`/`IsServerAvailableAsync` are the per-metric primitives. Returns `ResourceMetrics`/`ServerResourceMetrics` (in `ResourceMetrics.cs`). |

### Adaptive step (short-window safety)

`PrometheusClient.QueryRangeAsync` reads `ResourceCollection:QueryStepSeconds` (default **30**). If the
requested window is **shorter** than the step, it shrinks the step to `max(1, floor(window/10))` so a
short run still yields multiple samples instead of one-or-zero data points. This is why very short test
runs still produce non-empty CPU/memory series.

### Gotchas

- **`PrometheusQueryHelper` news up its own** `ResourceCollectionQueryBuilder` and `ResourceAggregator`
  (not DI) — they're stateless. Only `IPrometheusClient` and an `ILogger<PrometheusQueryHelper>` are
  injected; the QueryBuilder and Aggregator are new'd up internally (not DI) — don't add DI registrations
  for them expecting resolution into the helper.
- **`Console.WriteLine` with emoji** is intentional in `PrometheusQueryHelper` (operator-facing console
  output) alongside structured `ILogger` logs — keep both if you edit it.
- **Instance label is hard-coded to `:9182`** (windows_exporter port) inside the query builder. A server
  scraped on a different port silently returns no data → rows go `Failed`.
- **DataPoints == 0 is the gate**, not query failure. A 200-OK Prometheus response with an empty result
  set is the normal "not scraped yet" case the retry loop is built around.

## DI Wiring

`TestAuto.DependencyInjection\ServiceExtensions\ScenarioManagementServiceExtensions.cs`:

```csharp
// --- Prometheus services for ResourceCollection scenarios ---
services.AddHttpClient<IPrometheusClient, PrometheusClient>(/* BaseUrl from RestClients:Prometheus */);
services.AddTransient<PrometheusQueryHelper>();
services.AddTransient<IResourceCollectionService, ResourceCollectionService>();
services.AddTransient<ResourceCollectionJob>();
```

The recurring filler is scheduled separately —
`TestAuto.DependencyInjection\ServiceExtensions\HangfireServerServiceExtensions.cs`
(`RegisterRecurringJobs`) calls `RecurringJob.AddOrUpdate<ResourceMetricsUpdateJob>(...)`, gated by
config and registered through the `HangfireRecurringJobsService` hosted service (itself wired in
`RegisterAllServices`). See [[testauto-hangfire-architecture]].

## Configuration Keys

| Key | Default | Used by |
|---|---|---|
| `RestClients:Prometheus:BaseUrl` | — | `PrometheusClient` HTTP base address |
| `Prometheus:QueryPath` | `/api/v1/query` | instant query path |
| `Prometheus:QueryRangePath` | `/api/v1/query_range` | range query path |
| `ResourceCollection:QueryStepSeconds` | `30` | range step; adaptive-shrunk for short windows |
| `ResourceCollection:AggregationInterval` | **disputed — see note** | `PrometheusClient` field `_aggregationInterval` |
| `ResourceCollection:QueryPaddingStartSeconds` | `120` | start padding for `rate()` stability |
| `ResourceCollection:QueryPaddingEndSeconds` | `30` | end padding |
| `ResourceCollection:RateWindow` | `2m` | configured rate window cap |
| `ResourceCollection:MaxCollectionAttempts` | `5` | retry cap before `Failed` |
| `ResourceCollection:PageSize` | `1000` | Pending-record paging in the recurring job |

### `AggregationInterval` — code default and shipped config DISAGREE (15 s vs 5 s)

Do not quote a single number for this key. Three different values live in the tree:

| Source | Value | Evidence |
|---|---|---|
| Code fallback when the key is missing/unparseable | **15 s** | `PrometheusClient.cs:43-47` — `TimeSpan.TryParse(aggStr, out _aggregationInterval)`, else `_aggregationInterval = TimeSpan.FromSeconds(15); // default if not set` |
| Shipped `appsettings.json` (what actually runs) | **5 s** (`"00:00:05"`) | `TestAuto.Web\appsettings.json:131` |
| `ResourceMetrics.AggregationInterval` DTO property | **`"1m"`** | `ResourceMetrics.cs:37` — a *string* on the metrics DTO, unrelated to the client's `TimeSpan` |

So on a normal deployment the effective value is **5 s** (config wins); the 15 s literal is only
reachable if someone deletes or mistypes the key. The discrepancy is not obviously intentional —
flag it rather than "fixing" either side, and note `TestAuto\Documentation\PrometheusResourceCollection.md:32`
calls the key *"(Legacy) … now superseded by `QueryStepSeconds`"*, which is why nobody has
reconciled them.

## Sources

- `TestAuto.Scenarios\Scenarios\Resources\ResourceCollectionScenario.cs`
- `TestAuto.Scenarios\Services\ResourceCollectionService.cs`
- `TestAuto.Scenarios\Jobs\ResourceMetricsUpdateJob.cs`
- `TestAuto.External\Prometheus\IPrometheusClient.cs`
- `TestAuto.External\Prometheus\PrometheusClient.cs`
- `TestAuto.External\Prometheus\ResourceCollectionQueryBuilder.cs`
- `TestAuto.External\Prometheus\ResourceAggregator.cs`
- `TestAuto.External\Prometheus\PrometheusQueryHelper.cs`
- `TestAuto.External\Prometheus\ResourceMetrics.cs` — `ResourceMetrics` / `ServerResourceMetrics` DTOs
- `TestAuto.DependencyInjection\ServiceExtensions\ScenarioManagementServiceExtensions.cs` (~lines 152–172) — DI registration
- `TestAuto.DependencyInjection\ServiceExtensions\HangfireServerServiceExtensions.cs` (~line 85) — `RecurringJob.AddOrUpdate<ResourceMetricsUpdateJob>`
