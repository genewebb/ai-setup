---
name: testauto-connex-service
description: >
  Profisee Connect internal service layer and Connect scenarios in TestAuto.Connect. Use when
  implementing ConnEx scenarios or jobs, parsing a page key-range spec off connex.tJob.ExtensionData
  (ConnectJobPageSpecParser - inclusive start, exclusive end, inverted-range detection, and why
  IsInverted is false for non-numeric bounds), calling ConnectRestClient, polling a Connect batch to
  completion (ConnectStrategyPollingScenario / ConnectBatchState), collecting per-job execution
  metrics (ConnectPostRunCollectionScenario / ConnectExecutionRepository), or ConnEx authentication
  and path building. ConnEx step config is testauto-multistep-steps.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Connect Service Layer

> **Scope**: speed-merchants (TestAuto.Connect)
> **Source**: `TestAuto.Connect\Services\ConnectRestClient.cs`, `TestAuto.Connect\Scenarios\*`, `TestAuto.Connect\Services\ConnectExecutionRepository.cs`

The Connect service layer provides programmatic access to the Profisee Connect REST API from within TestAuto scenarios and jobs. It is distinct from the ConnEx *step type* used in MultiStepUtilityScenario configs (that uses `ConnExExecutor` — see `testauto-multistep-steps`).

## Current Architecture (post-2026-06 rework)

The Connect artifact lifecycle (create/update/delete/start a service configuration or strategy) is **no longer driven from C# scenarios**. `CreateServiceConfiguration`, `ExecuteStrategyScenario`, and the embedded-resource `ArtifactManager` were all deleted — artifacts are now added, updated, deleted, and started via **ConnEx steps in MultiStepUtilityScenario** (see `testauto-multistep-steps` and `connex-import-tokenization`).

What remains in TestAuto.Connect is the *observe-and-measure* side:

| Component | Role |
|---|---|
| `ConnectStrategyPollingScenario` | Workflow **gate** — waits until the latest batch for a strategy reaches a terminal state. Emits no metrics. |
| `ConnectPostRunCollectionScenario` | Metric **collector** — after a batch finishes, emits one `MetricDetailConnectApiExecution` row per `connex.tJob` page to the `ConnectApiExecution` entity. |
| `ConnectExecutionRepository` | SQL reader scoped to the **instance under test only** — `connex.*`, `monitor.*`, `connexjobs.*` (REST does not surface per-call timings). It never reads or writes TestAuto **model** entities. |
| `ConnectRunProfileReader` | Static, never-fatal REST reader for `ConnectRunProfile` enrichment against the **ScenarioMgt** subject area (replaces the removed SQL path). |
| `ConnectBatchState` | Single source of truth classifying a batch `ProcessingState` as terminal success/failure or keep-polling. |
| `ConnectRestClient` | Typed REST client (batch status, latest-batch lookup, imports, service-provider lookups). |

Typical workflow shape: `MultiStepUtilityScenario (ConnEx steps: import config/strategy, start batch)` → `ConnectStrategyPollingScenario (wait)` → `ConnectPostRunCollectionScenario (collect metrics)`.

---

## ConnectRestClient

**Location**: `TestAuto.Connect/Services/ConnectRestClient.cs`
**Interface**: `IConnectRestClient`

Uses `IHttpClientFactory` directly (does **not** extend `HttpClientFacade`). Auth is injected by the `ApiKeyHandler` DelegatingHandler registered on the named client `IConnectRestClient.ClientName` (`"ConnectClient"`). All methods take an optional `CancellationToken ct = default` and return `JsonResponse`.

### Constructor

```csharp
public ConnectRestClient(IHttpClientFactory httpClientFactory, ILogger logger)
```

The API version is read from the executing assembly's version and converted to a path segment via `.ToApiVersionString()`.

### Available Methods

#### GET

| Method | Purpose |
|---|---|
| `GetBatchStatusAsync(batchActivityCode, ct)` | Poll processing state of a batch |
| `FindLatestBatchByStrategyNameAsync(strategyName, ct)` | Most-recently-created batch job activity for a strategy; `data` array is empty when none exists. Used to resolve a batch started out-of-band. ⚠️ Filters `BatchJobActivities` by `ConnectConstants.JsonBatchStrategyNameField = "Name"` — **explicitly UNVERIFIED against the live gateway `$metadata`** (comment at `ConnectConstants.cs:27-31`). If the gateway exposes the strategy name under a different attribute (e.g. `StrategyName`), the filter matches nothing and both consumers (`ConnectStrategyPollingScenario:~200-210`, `ConnectPostRunCollectionScenario:~290-297`) silently get `null` → "no batch found for strategy". Debugging that error: verify the attribute name against `$metadata` first, then change it in `ConnectConstants`. |
| `GetJobActivitiesByBatchCodeAsync(batchCode, page, pageSize, ct)` | List job activities for a batch |
| `GetServiceProviderByNameAsync(name, ct)` | Look up a service provider by name |
| `GetServiceProviderByUidAsync(uid, ct)` | Look up a service provider by GUID |

#### POST

| Method | Purpose |
|---|---|
| `ImportConfigurationsAsync(body, ct)` | Import service configurations |
| `ImportStrategiesAsync(body, ct)` | Import integration strategies |
| `RunStrategyBatchByUidAsync(strategyUid, requestBody, ct)` | Run a strategy batch by GUID |
| `ExecuteImmediateJobAsync(strategyName, payload, ct)` | Execute a job immediately |
| `QueueBatchJobAsync(strategyOrId, ct)` | Queue a batch job |

### All methods return `JsonResponse`

`JsonResponse` is **not** local to TestAuto.Connect — it is `TestAuto.Shared/Rest/JsonResponse.cs`, deriving from `ResponseBase<JToken>` (so `StatusCode` / `ResponseContent` come from the base). Its success test is an **explicit three-status allow-list, not a 2xx range**:

```csharp
// TestAuto.Shared/Rest/JsonResponse.cs:54-59
private bool isSuccess()
{
    return StatusCode == System.Net.HttpStatusCode.OK         // 200
        || StatusCode == System.Net.HttpStatusCode.Created    // 201
        || StatusCode == System.Net.HttpStatusCode.NoContent; // 204
}
```

⚠️ **Any other 2xx is treated as failure.** `202 Accepted` and `206 Partial Content` both make `IsSuccess` false. If a Connect endpoint starts returning 202 for an async batch queue, `ConnectRestClient` callers will see it as an error — widen `isSuccess()` (the identical copy in `JsonResponse<T>` at lines 94-99 must be changed too) rather than working around it at the call site.

### Path Building — deliberately **not** the shared path utility

The house rule is to use the shared path/query utility instead of hand-rolled URLs. `ConnectRestClient` is a **documented exception**: it holds no shared mutable `PathAndQueryBuilder` and instead builds each path per call through a **private** `BuildPath` helper. The rationale is stated in the class doc comment (`ConnectRestClient.cs:14-17`).

```csharp
// ConnectRestClient.cs:156-181 (private)
// Produces: {apiVersion}/Connect/{resource}/{extra}/{segments}?key=val
private string BuildPath(
    string resource,
    string[]? extraSegments = null,
    Dictionary<string, string>? queryParams = null)
```

- Segments are `string.Join("/", ...)` of `_apiVersion` + `HttpRequestConstants.Services.Connect` + `resource` + any `extraSegments`.
- `_apiVersion` is derived once in the constructor from the executing assembly version via `.ToApiVersionString()`, falling back to `"v1"`.
- Query params are `HttpUtility.UrlEncode`d on **both** key and value, then joined with `&`.
- The path is **relative** — the base address comes from the named `IHttpClientFactory` client `IConnectRestClient.ClientName`.

```csharp
// Example: v1/Connect/BatchJobActivities?filter=...&Attributes=...
var path = BuildPath(
    HttpRequestConstants.PathSegments.Connect.BatchJobActivities,
    queryParams: new Dictionary<string, string>
    {
        [AttributeNames.Filter] = $"[{AttributeNames.Code}] eq '{code}'",
        ["Attributes"] = "[ProcessingState],[PageSize],[InvocationMode]"
    });
```

Do **not** copy this exception into new code. Everywhere else in the solution, use the shared path/query utility; `BuildPath` here is private and cannot be reused anyway.

---

## ScenarioBaseConnect — Base Class for Connect Scenarios

**Location**: `TestAuto.Connect/Common/ScenarioBaseConnect.cs`

Thin abstract base (post-rework). Provides the DI scope, the Connect REST client, and the per-batch template-method skeleton. The old artifact/polling/SQL helpers (`LoadArtifactConfig`, `InstrumentTaskAsync`, `WaitForStrategyToCompleteAsync`, `EnsureServiceProviderIdAndNameAsync`, `TestSqlConnection`) were removed with the retired scenarios.

```csharp
public abstract class ScenarioBaseConnect : ScenarioBase, IScenario, IDisposable
```

### Protected State

| Field | Type | Purpose |
|---|---|---|
| `_scope` | `IServiceScope` | Per-scenario DI scope (disposed in `Dispose()`) |
| `_connectClient` | `IConnectRestClient` | Scoped Connect REST client |
| `_allParams` | `Dictionary<string, string>` | Parameters from `ConnectCustomParms` defaults + scenario CustomParms overrides (built by `ConfigureAllParams()` via `CustomParmDictionaryHelper`) |

### Two usage shapes

```
1. Per-record:    keep base ProcessBatchAsync; implement ProcessSingleTaskAsync.
                  Base loop counts success via MetricDetailConnectApiExecution.HttpResponseCode == 200,
                  builds the summary with MetricSummaryRequestBuilder.

2. Self-managed:  override ProcessBatchAsync wholesale (both current scenarios do this);
                  stub ProcessSingleTaskAsync to throw NotSupportedException so a future
                  edit routing through the base record loop surfaces as a programming error.
```

The base `ProcessBatchAsync` pushes `LogTag`/`ScenarioName`/`BatchNumber`/`TotalGlobalBatches`/`WorkloadExecution` into the Serilog `LogContext` for the whole batch.

### ConnectCustomParms — raw vs `[CustomParm]` defaults (important pattern)

`TestAuto.Connect/Configuration/ConnectCustomParms.cs` has **two kinds of members on purpose**:

- `[CustomParm]`-decorated properties (e.g. `ServerName`, `StrategyConfigurationTemplate`) — seeded into `_allParams` by `CustomParmDictionaryHelper.BuildDictionary`, with scenario CustomParms as overrides.
- Plain `const string` keys (e.g. `StrategyName`, `PollIntervalSeconds`, `RunProfileCode`, `MaxBatchAgeMinutes`, `JobPageSize`, `ConcurrentThreads`, `OperationName`, `IncludeFailedJobsOnly`) — **deliberately NOT `[CustomParm]`**. A `[CustomParm]` member with `=> nameof(X)` seeds a self-referential default (`StrategyName = "StrategyName"`), which would defeat required-field validation. The polling/post-run scenarios therefore read the **raw** `cfg.ScenarioRuntime.CustomParms` so a missing required value genuinely fails fast.

---

## ConnectStrategyPollingScenario — Workflow Gate

**Location**: `TestAuto.Connect/Scenarios/ConnectStrategyPollingScenario.cs`

Polls the Connect REST API until the most-recent batch for a named strategy reaches a terminal state. Connect counterpart of `MatchingStrategyPollingScenario`; used when the batch was started out-of-band (manual, scheduled, or a prior workflow step).

```csharp
[ScenarioTypes(
    typeof(ScenarioConfigurationOnly),   // no test records
    typeof(MetricDetailNone),
    typeof(MetricBatchSummaryNone),      // emits NO metrics — pure gate
    RestSubjectArea.Connect,
    DataPattern.SelfManaged,             // one Hangfire job, scenario-managed loop
    CustomParmsEditorType.ConnectStrategyPolling)]
```

### CustomParms (read raw, validated by `ParsePollingParms` — public static, unit-testable)

| Parm | Required | Default | Validation |
|---|---|---|---|
| `StrategyName` | **Yes** | — | non-empty, else `ArgumentException` |
| `PollIntervalSeconds` | No | 30 | integer 1–3600 |
| `MaxWaitMinutes` | No | 720 (12 h) | > 0 and ≤ 1440; also `interval ≤ maxWait*60` (at least one poll must fit) |

Errors name the parameter, offending value, and allowed range — actionable from the execution log alone.

### Flow

1. `ResolveLatestBatchCodeAsync` → `FindLatestBatchByStrategyNameAsync`; no batch → summary **Failed** (workflow stops).
2. `PollUntilTerminalAsync(batchCode, ...)`: status-only `GetBatchStatusAsync` loop (no record-count pagination — unlike the retired `ExecuteStrategyScenario`).
3. Each state classified via `ConnectBatchState.Classify` → returns `PollOutcome` (`Succeeded | Failed | TimedOut | Cancelled`).
4. Only `PollOutcome.Succeeded` maps to `MetricBatchSummaryNone.Success`; everything else (incl. **timeout**) is Failed.

### Test seams

```csharp
internal Func<TimeSpan, CancellationToken, Task> Delay { get; set; }  // default Task.Delay
internal Func<DateTime> UtcNow { get; set; }                          // default DateTime.UtcNow
```

Injected into `PollUntilTerminalAsync` so unit tests run without real sleeps or wall-clock dependency. Production passes `CancellationToken.None` (the `IScenario` contract exposes no framework token), but the loop is token-aware.

### ConnectBatchState — terminal-state policy

`TestAuto.Connect/Common/ConnectBatchState.cs` — shared classifier so callers cannot drift apart:

| `ProcessingState` | `BatchStateKind` |
|---|---|
| `Succeeded` | `TerminalSuccess` |
| `Failed`, `Deleted` | `TerminalFailure` |
| `Processing`, `Enqueued`, `Scheduled`, `Awaiting`, **unknown, null** | `NonTerminal` (keep polling) |

Case-insensitive. Unknown/null states are deliberately non-terminal — the wall-clock timeout is the backstop. `IsKnown(state)` gates a once-per-state "unrecognized ProcessingState" warning. **If Connect introduces a new terminal state it must be added here**, otherwise the poller waits until timeout.

---

## ConnectPostRunCollectionScenario — Metric Collector

**Location**: `TestAuto.Connect/Scenarios/ConnectPostRunCollectionScenario.cs`

After a Connect batch finishes, reads per-page execution data from the Profisee `connex` DB and emits one `MetricDetailConnectApiExecution` row per HTTP call (per `connex.tJob` page) to the `ConnectApiExecution` metric entity via the standard metrics pipeline.

```csharp
[ScenarioTypes(
    typeof(DefaultNoOpGenerator),
    typeof(MetricDetailConnectApiExecution),
    typeof(MetricBatchSummaryBase),
    RestSubjectArea.Connect,
    DataPattern.SelfManaged,
    CustomParmsEditorType.ConnectPostRunCollection)]
```

**Source split**: REST (`FindLatestBatchByStrategyNameAsync`) resolves the latest batch code; per-page timings/counts come from SQL (`IConnectExecutionRepository`) because REST does not surface them.

### CustomParms (validated by `ParsePostRunParms` — public static, unit-testable)

| Parm | Required | Default | Validation |
|---|---|---|---|
| `StrategyName` | **Yes** | — | non-empty |
| `RunProfileCode` | **Yes** | — | non-empty **and must be an existing `ConnectRunProfile` code** — RunProfile is a Domain attribute on `ConnectApiExecution`, so an unknown code is rejected by the model. Existence is **no longer verified in the step**: `ConnectRunProfileReader.ReadAsync` never throws, so a bad code surfaces later as a domain-validation rejection on the metric write, not as an `InvalidOperationException` mid-run. |
| `MaxBatchAgeMinutes` | No | 60 | ≥ 1 |
| `JobPageSize` | No | 1000 | 1–10000 |
| `ConcurrentThreads` | No | 4 | 1–32 (SemaphoreSlim cap for parallel detail mapping) |
| `OperationName` | No | derived from job `Type` | override label (e.g. `RecordsCreate`) |
| `IncludeFailedJobsOnly` | No | false | when true, emit rows only for jobs with `ProcessingState != 'Succeeded'` |

Also enforced: `ScenarioEnvironment.TargetMetricEntity` must be `ConnectApiExecution` or blank (blank is defaulted to `ConnectApiExecution` in `ApplyConfiguration`).

### Flow

1. **Resolve batch** via REST (sole derivation point); none → throw.
2. **Load batch metadata** from `connex.tBatch` (`GetBatchAsync`); missing → throw.
3. **Stale-batch guard**: if `now - batch.LastChangeUtc > MaxBatchAgeMinutes`, warn and return an empty summary (0 rows) — prevents re-collecting an old run by accident.
4. **Load RunProfile over REST** (`ConnectRunProfileReader.ReadAsync(scenarioMgtClient, code, logger)`) — enrichment source (attribute/DBA/rule snapshot counts), **best-effort**: a failure degrades to `Unresolved(code)` rather than failing the step, and the lookup is bounded by `DefaultLookupTimeoutSeconds` (30 s) with abandon-on-timeout. The reader is `static` **by design** so the DI plugin scan / `ValidateOnBuild` does not try to construct it.
5. **Page `connex.tJob`** (`GetJobsAsync`, page loop until short page); per job, bounded by `ConcurrentThreads`, map to a detail row with `BuildDetail` (public, unit-testable).
6. Build the summary: `recordVolume`/success/fail counted per row (`HttpResponseCode == 200` → success).

Requires a resolvable **Profisee SQL connection string** (`DatabaseConnectionStringHelper.GetConnectionString(cfg, "Profisee", ...)`); the repository is constructed per-run with it — no connection string → throw.

### `BuildDetail` mapping highlights

- `Code` = `{BatchCode}-{PageNumber:D6}` (unique per row); `RequestStart/End` = job `EnterDtm`/`LastChgDtm`; elapsed derived.
- `HttpResponseCode`: monitor result keyed by `PageNumber` wins when present; else derived from `ProcessingState` (`Succeeded` → 200, else 500).
- `HttpRequestType`: `GET` if job `Type` contains "Export", else `POST`. `HttpErrorMessage`: job `ErrorDetails` truncated to 4000.
- `ResponseRecordCount` = `RecordCount - FailedRecordCount`; profile snapshot fills `AttributeCount`/`DbaCount`/`DqRuleCount`/`RequestAttributeCount`.

### MetricDetailConnectApiExecution — inheritance rule

`TestAuto.Connect/Metrics/MetricDetailConnectApiExecution.cs` extends **`MetricDetailBase`** (`:26`) — see the dedicated section below for why `MetricDetailExtended` was abandoned. Inherited shared columns (`ExecutionStatus`, `ProfiseeVersion`, `ScenarioName`→`Scenario`, `WorkloadExecution`, `Workload`) are **set but deliberately NOT redeclared** — the persistence handler reflects with `FlattenHierarchy`, and a redeclaration would map the same column twice. Connect-specific columns are declared locally (`Code`, `RunProfile`, `OperationName`, server/env fields, `HttpRequestType`, `HttpErrorMessage`, `PageSize`, `HttpResponseCode`, `Request*` timings/volumes, profile snapshot counts; constants in `ConnectMetricConstants`).

---

## ConnectExecutionRepository — SQL Schema Coupling

**Location**: `TestAuto.Connect/Services/ConnectExecutionRepository.cs` (interface + record types in `IConnectExecutionRepository.cs`)

The one place the scenario touches SQL directly. **All `connex` column names are isolated here so a Profisee-version schema change is a single-file fix** (plan risk R-Schema).

| Method | Table(s) | Returns |
|---|---|---|
| `GetBatchAsync(batchCode)` | `connex.tBatch` | `ConnectBatchInfo?` (Id, Code, Uid, StrategyId — *nvarchar GUID-ish string, not int* — PageSize, JobCount, ProcessingState, InvocationMode, EnterUtc, LastChangeUtc) |
| `GetJobsAsync(batchId, page, pageSize)` | `connex.tJob` | `List<ConnectJobRow>` ordered by PageNumber then enter time |
| `GetJobHttpResultsAsync(batchUid)` | **`monitor.tActivityDetails` only** — there is no join to `monitor.tActivity`; the query filters `monitor.tActivityDetails d` on `d.ParentActivityId` (see the comment at `ConnectExecutionRepository.cs:109`, query at `:116`) | `Dictionary<int, ConnectJobHttpResult>` keyed by job PageNumber. **Best-effort**: empty map when no monitor entries match; caller falls back to ProcessingState-derived codes. Defensive JSON property parsing (`TryParseHttpResult`). |
| `GetJobTimingsAsync(batchUid, ct)` (`IConnectExecutionRepository.cs:42`) | `connexjobs.State` ⋈ `monitor.tActivityDetails` | `Dictionary<int, ConnectJobTiming>` — per-page work timings from Connect's own Hangfire storage |

### `ConnectRunProfileReader` — RunProfile moved from SQL to REST

`TestAuto.Connect/Services/ConnectRunProfileReader.cs`. A **static**, never-fatal, time-bounded reader
against the **ScenarioMgt** subject area.

- **Why ScenarioMgt**: `ConnectRunProfile` is a TestAuto *model* entity, and the model lives wherever
  ScenarioMgt lives — on a real runner a hosted/SaaS endpoint. `RestClients:ScenarioMgt:BaseUrl` is the one
  address that always names the model instance. The removed SQL path assumed the model DB was reachable from
  the runner, which is frequently false; worse,
  `DatabaseConnectionStringHelper` silently falls back to `ProfiseeDB` when `MetricsDB` is absent, which
  produced a silent Hangfire-retry hang rather than an error.
- **Never throws.** Any failure — including a malformed payload — resolves to `Unresolved(code)` plus a
  logged warning (`:25`).
- **`DefaultLookupTimeoutSeconds = 30`** with abandon-on-timeout (`:45`). A stalled ScenarioMgt endpoint
  would otherwise block the await forever and hang the scenario.
- **`static` by design** (`:34`) so the DI plugin scan / `ValidateOnBuild` does not try to construct it.

### `GetJobTimingsAsync` — per-page timings from Connect's OWN Hangfire storage

`connexjobs.State` is the only place a per-page work duration exists. The join
(`ConnectExecutionRepository.cs:223-224`) is:

```sql
JOIN connexjobs.State s
  ON s.JobId = TRY_CAST(JSON_VALUE(d.Properties, '$.BackgroundJobId') AS bigint)
```

`Succeeded.Data` carries `{"SucceededAt":…,"PerformanceDuration":…,"Latency":…}`, and
**`PerformanceDuration` is preferred** over `EndedUtc - StartedUtc` (`:268`) because it **excludes queue
wait** — the difference between "how long the work took" and "how long the page sat in a queue", which is
usually the number you actually want.

It is **best-effort**: Hangfire state rows expire, so when none resolve the collector logs and **falls back
to the batch window** (`:290`) rather than failing. Note `[DIAG]`-prefixed lines here are temporary
diagnostics slated for demotion (`ConnectConstants.DiagPrefix`) — do not treat them as real errors.

### `MetricDetailConnectApiExecution` extends `MetricDetailBase`, NOT `MetricDetailExtended`

> [!warning] This is deliberate and must not be "tidied" back
> The persistence handler maps every visible `[MetricColumn]`. `MetricDetailExtended`'s `IsCodeLookup`,
> `MaxRunningScenarioCount`, `SimulatedUserThreadId` and `SimulatedUserCount` **do not exist on the
> `ConnectApiExecution` entity** — and being non-nullable value types, the mapper's null-skip cannot drop
> them. Every write came back **HTTP 207 with error 8609 per column** (`MetricDetailConnectApiExecution.cs:20`).

Only `ExecutionStatus`, `ProfiseeVersion`, `ScenarioName`→`Scenario`, `WorkloadExecution`, `Workload` are
inherited-and-not-redeclared; `HttpRequestType`, `HttpErrorMessage`, `PageSize` are declared **locally**.
`TargetEnvironment` is intentionally absent — it shares the `Environment` column with
`TargetEnvironmentName`, and only the latter carries a valid ServerProfile code.

`Code` is now `{WorkloadExecution}-{BatchCode}-{PageNumber:D6}` (batch/page only when there is no
WorkloadExecution), because connex batch codes **restart at 1 on environment rebuild** and collided —
the 8603 duplicate-code failure.

---

## DI Registration

`ConnectRestClient` is registered in `ConnectModuleRegistrar`. Inject via `IConnectRestClient`:

```csharp
public class MyConnectScenario(IConnectRestClient connectClient) { }
```

`ConnectExecutionRepository` is **not** DI-registered — `ConnectPostRunCollectionScenario` constructs it per run from the resolved connection string.

---

## Relationship to testauto-multistep-steps

| Concern | Use |
|---|---|
| Create/update/delete/start ConnEx artifacts (configs, strategies, providers) | `testauto-multistep-steps` (ConnExStep) — this replaced the retired `CreateServiceConfiguration`/`ExecuteStrategyScenario` |
| Wait for a running batch to finish (workflow gate) | `ConnectStrategyPollingScenario` (this skill) |
| Collect per-job execution metrics after a run | `ConnectPostRunCollectionScenario` (this skill) |
| Calling Connect REST API programmatically from C# | `ConnectRestClient` (this skill) |
| Tokenizing an exported artifact for import | `connex-import-tokenization` |

---

## Common Pitfalls

| Pitfall | Cause | Fix |
|---|---|---|
| Polling scenario fails immediately | No batch exists yet for `StrategyName` | Start the batch first (ConnEx step / out-of-band); the poller only *waits*, it never *starts* |
| Poller runs until timeout on a finished batch | New Connect terminal state not in `ConnectBatchState` | Add the state to `SuccessStates`/`FailureStates` in `ConnectBatchState` |
| Post-run scenario emits 0 rows, no error | Stale-batch guard tripped (`MaxBatchAgeMinutes`) | Raise `MaxBatchAgeMinutes` or run collection sooner after the batch |
| Metric write rejected on the `RunProfile` domain attribute | `RunProfileCode` is not an existing `ConnectRunProfile` code | RunProfile is a Domain value on `ConnectApiExecution` — create/choose an existing code. The old in-step `InvalidOperationException: ConnectRunProfile code ... not found` **no longer occurs**: the reader is never-fatal, so the failure now lands at the metric write |
| `TargetMetricEntity must be 'ConnectApiExecution'` | Scenario env points at another metric entity | Leave `TargetMetricEntity` blank (defaults) or set exactly `ConnectApiExecution` |
| `NotSupportedException` from `ProcessSingleTaskAsync` | Something routed a self-managed scenario through the base record loop | Both scenarios are `DataPattern.SelfManaged` + override `ProcessBatchAsync`; don't change either side alone |
| Post-run scenario throws "no SQL connection string resolved" | Profisee DB connection not configured for the environment | Configure the Profisee connection string in secrets (`DatabaseConnectionStringHelper` path) |

---

## ConnExConstants — API Path Reference

`TestAuto.Utilities.Common.ConnExConstants` centralizes all endpoint strings and resource-type mappings. There are **two distinct path systems** — use the right one for the right layer.

### Gateway paths (used by `ConnExExecutor` / `ConnExStep`)

These are the Profisee REST gateway proxy paths. ConnExStep's `BaseUrl` must point to the Profisee REST gateway base, not a direct ConnEx host.

| Resource | Constant | Path |
|---|---|---|
| Service Configuration | `GatewayConfigurationsPath` | `v1/Connect/Configurations` |
| Integration Strategy | `GatewayStrategiesPath` | `v1/Connect/Strategies` |
| Service Provider | `GatewayServiceProvidersPath` | `v1/Connect/ServiceProviders` |

### Direct ConnEx paths (used by `ConnectRestClient`)

These are the direct ConnEx API paths used by the programmatic client in C# scenarios.

| Resource | Import (POST) | Export/Delete base |
|---|---|---|
| Service Configuration | `/v1/serviceconfigurations/import` | `/v1/serviceconfigurations` |
| Integration Strategy | `/v1/integrationstrategies/import` | `/v1/integrationstrategies` |
| Service Provider | `/v1/serviceproviders/import` | `/v1/serviceproviders` |

### Resource type auto-detection

The executor infers `ResourceType` from the artifact JSON root keys (case-insensitive):

| Artifact root key | Detected as |
|---|---|
| `ServiceConfigurationRecord` / `serviceConfigurationRecord` | `ServiceConfiguration` |
| `IntegrationStrategyRecord` / `integrationStrategyRecord` | `IntegrationStrategy` |
| `ServiceProviderRecord` / `serviceProviderRecord` | `ServiceProvider` |

If the artifact contains none of these keys — or more than one — auto-detection fails and the step requires an explicit `ResourceType`.

### Other constants

| Constant | Value | Purpose |
|---|---|---|
| `BaseUrlConfigKey` | `RestClients:Connect:BaseUrl` | Config key for gateway base URL |
| `ApiKeyConfigKey` | `RestClients:Connect:ApiKey` | Config key for API key |
| `MaxArtifactSizeMBConfigKey` | `ConnEx:MaxArtifactSizeMB` | Override max artifact size (default 10 MB) |
| `ApiKeyHeader` | `x-api-key` | HTTP header used for authentication |
| `ConnectClientName` | `ConnectClient` | Named `IHttpClientFactory` client used by integration tests |
| `DefaultArtifactVersion` | `1.7.1.0` | Artifact version string embedded in templates |

---

## Service Configuration Artifact Format

ConnEx artifacts come in two formats depending on source — both are valid input to `ConnExStep`.

> ⚠️ **The two legacy top-level folders are MIXED — do not treat either as "the flat folder".** `TestAuto.Utilities/Scripts/ConnEx/ServiceConfigurations/` and `.../IntegrationStrategies/` (the un-namespaced folders that predate the per-provider template library) each hold **mostly `$type`-annotated artifacts plus exactly one flat record-format file**:
>
> | Folder | `$type`-annotated (artifact format) | Flat (record format) |
> |---|---|---|
> | `ServiceConfigurations/` | `CORPLTR94_ModelSource.json`, `ModelSource.json`, `RetailClient120MServiceConfig.json` | `Service_Configuration_for_SMVMDB3_ModelSource.json` |
> | `IntegrationStrategies/` | `CORPLTR94_Import_ModelSource1K.json`, `RetailClient120MStrategy.json`, `RetailClient5K.json` | `SMVM3_LoadRetailClient_5K.json` |
>
> Always open the file and check for a `"$type"` root property before assuming a format. The per-provider template library (`SqlServer/`, `Snowflake/`, …) is **uniformly `$type`-annotated** — see [[testauto-connex-provider-templates]].

### Flat format (record format)

No `$type` annotations. The `serviceConfigurationRecord` root key is absent — the artifact is the record directly. Live example: `Scripts/ConnEx/ServiceConfigurations/Service_Configuration_for_SMVMDB3_ModelSource.json`.

```json
{
  "Configuration": {
    "serviceProviderId": { "id": "...", "name": "SQL Server Service Provider" },
    "databaseType": "SqlServer",
    "settings": {
      "AuthenticationScheme": {
        "name": null,
        "assignmentType": "Literal",
        "value": "SqlLogon",
        "dataType": 8
      },
      "UsernameVault": {
        "name": "Username",
        "assignmentType": "Credential",
        "value": {
          "name": "Username Credential",
          "providerType": "LocalVault",
          "configuration": { "value": "{{DbUsername}}" }
        },
        "dataType": 1
      },
      "PasswordVault": {
        "name": "Password",
        "assignmentType": "Credential",
        "value": {
          "name": "Password Credential",
          "providerType": "LocalVault",
          "configuration": { "value": "{{DbPassword}}" }
        },
        "dataType": 1
      },
      "ServerName": { "assignmentType": "Literal", "value": "{{DbServer}}", "dataType": 8 },
      "Database": { "assignmentType": "Literal", "value": "{{DatabaseName}}", "dataType": 8 }
    },
    "artifactVersion": "1.7.1.0"
  },
  "Id": "{{ServiceConfigId}}",
  "Name": "{{ServiceConfigName}}",
  "ServiceProviderName": "SQL Server Service Provider",
  "ServiceProviderId": "77d91447-e344-4fc1-a49f-1c089210a40a",
  "Type": "Database"
}
```

### $type-annotated format (portal export / integration tests)

Includes Newtonsoft `$type` discriminators throughout. The root key is `serviceConfigurationRecord`. Auto-detection uses the presence of this key to identify the resource type.

```json
{
  "$type": "Profisee.Platform.ConnEx.Contracts.Administration.ServiceConfigurationArtifact, ...",
  "artifactVersion": "1.7.1.0",
  "serviceConfigurationRecord": {
    "$type": "...",
    "Configuration": {
      "$type": "...",
      "settings": {
        "$type": "System.Collections.Generic.Dictionary`2[...]",
        "UsernameVault": {
          "$type": "...",
          "name": "Username",
          "assignmentType": "Credential",
          "value": {
            "name": "ConnectReadOnly Username",
            "providerType": "LocalVault",
            "vaultId": "91f3b9bd-..."
          },
          "dataType": 1
        }
      }
    },
    "Id": "{{ServiceConfigId}}",
    "Name": "{{ServiceConfigName}}"
  }
}
```

### Credential vs Literal settings

| `assignmentType` | Meaning | `value` shape |
|---|---|---|
| `"Literal"` | Plain text value | string, number, or bool |
| `"Credential"` | Secret stored in a vault | object with `providerType`, `vaultId` (annotated) or `configuration.value` (flat) |

For template-based imports, use `"Credential"` with `"providerType": "LocalVault"` and inject the actual value via `{{token}}` in `configuration.value`. ConnEx creates the vault entry during import.

---

## ConnEx Integration Testing Patterns

**Test class**: `Testing.SpeedMerchants.Integration/Tests/RESTGateway/Connect/ConnExServiceConfigImportTests.cs`

Tests for ConnEx import run against the **real ConnEx API on CORPLTR94**. They are tagged `[TestCategory("Connect")]` and `[TestCategory("Import")]`.

### Test Setup Pattern

```csharp
[TestClass]
public class ConnExServiceConfigImportTests : BaseTest
{
    private IStepExecutor _executor = null!;
    private IHttpClientFactory _httpClientFactory = null!;
    private string _baseUrl = null!;
    private string _apiKey = null!;

    [TestInitialize]
    public new void Setup()
    {
        base.Setup();

        // Resolve ConnExExecutor from DI — same code path as the UI
        var executors = ServiceProvider.GetServices<IStepExecutor>();
        _executor = executors.First(e => e.StepType == "ConnExStep");

        _httpClientFactory = ServiceProvider.GetRequiredService<IHttpClientFactory>();

        var config = ServiceProvider.GetRequiredService<IConfiguration>();
        _baseUrl = config["RestClients:Connect:BaseUrl"]?.TrimEnd('/') ?? "";
        _apiKey = config["RestClients:Connect:ApiKey"] ?? "";
    }
}
```

Use unique `_testConfigId = Guid.NewGuid().ToString()` per test run to avoid collisions between concurrent or repeated test runs.

### Two Test Strategies

| Strategy | Use when |
|---|---|
| **Via `ConnExExecutor`** (recommended) | Validates the full production code path including token replacement, error handling, and metadata population |
| **Direct HTTP POST** | Isolates whether the issue is executor logic vs artifact format |

#### Via ConnExExecutor
```csharp
var step = new ConnExStep
{
    ArtifactJson = artifactJson,
    Operation = "Import",
    ResourceType = ConnExConstants.ServiceConfiguration,
    ReturnResult = true,
    ExpectedStatusCodes = new List<int> { 200, 201, 204 }
};
var result = await _executor.ExecuteAsync(step, CancellationToken.None);
Assert.IsTrue(result.Succeeded, $"Import failed: {result.ErrorMessage}");
```

#### Direct HTTP POST (import body format)
The ConnEx import endpoint expects `importData` as a **JSON string** (not a parsed object):
```csharp
var body = new JObject
{
    ["configurationSource"] = "Custom",
    ["importData"] = artifactJson,   // string, not JToken.Parse(artifactJson)
    ["returnResult"] = true
};
var client = _httpClientFactory.CreateClient("ConnectClient");
var url = $"{_baseUrl}/{ConnExConstants.GatewayConfigurationsPath}";
using var request = new HttpRequestMessage(HttpMethod.Post, url);
request.Content = new StringContent(body.ToString(Formatting.None), Encoding.UTF8, "application/json");
request.Headers.Add("x-api-key", _apiKey);
var response = await client.SendAsync(request);
```

> **Import body format**: `importData` must be a JSON **string** (the API deserializes it server-side). Passing a parsed `JToken` object causes the API to receive nested JSON, which the server cannot deserialize — it returns 400 or 422. This matches `ConnExExecutor.cs` line ~347 where `artifactJson!` (string) is assigned directly.

### Cleanup Pattern

Always delete test artifacts in `[TestCleanup]` to avoid polluting the Connect instance:

```csharp
[TestCleanup]
public async Task Cleanup()
{
    try
    {
        var client = _httpClientFactory.CreateClient("ConnectClient");
        var url = $"{_baseUrl}/{ConnExConstants.GatewayConfigurationsPath}/{_testConfigId}";
        using var request = new HttpRequestMessage(HttpMethod.Delete, url);
        request.Headers.Add("x-api-key", _apiKey);
        await client.SendAsync(request);
    }
    catch { /* ok if record didn't exist */ }
}
```

### Artifact Format for Integration Tests

Use the `$type`-annotated portal-export format (not the flat template format) when testing against the real ConnEx API — it's the format the server expects. The root key must be `serviceConfigurationRecord` for auto-detection to work.

Unit tests for the new scenarios live in `Testing.SpeedMerchants.Unit/Tests/Connect/` (`ConnectBatchStateTests`, `ConnectStrategyPollingScenarioTests` — using the `Delay`/`UtcNow` seams).

---

## ConnectJobPageSpecParser - the page key-range spec

Parses `connex.tJob.ExtensionData` into a key-range spec that feeds the `PageKeyRange` metric column.
Four judgements are already settled here, so they need not be re-litigated:

- **Bounds are start-inclusive, end-exclusive.**
- **Inverted-range detection is the type's whole reason to exist.** 7 of 1000 observed pages had
  start >= end, matched nothing, and **still reported `Succeeded`**.
- **`IsInverted` is deliberately `false` for non-numeric bounds** - *"unknown is not the same as valid"*.
  Callers must read it as **confirmed bad**, never as confirmed good.
- **A missing END is valid**; a missing START is not. The **final page** of an import legitimately carries
  a null `EndingExclusiveKeyComponents`, i.e. an open-ended spec.

Lookups go through `GetValueCI` because the gateway re-cases keys - that helper is covered by
[[external-json-case-insensitive-reads]] and is not re-documented here.

## Sources

- `TestAuto.Connect\Services\ConnectRestClient.cs`, `IConnectRestClient.cs`
- `TestAuto.Connect\Common\ScenarioBaseConnect.cs`
- `TestAuto.Connect\Common\ConnectBatchState.cs`
- `TestAuto.Connect\Configuration\ConnectCustomParms.cs`
- `TestAuto.Connect\Scenarios\ConnectStrategyPollingScenario.cs`
- `TestAuto.Connect\Scenarios\ConnectPostRunCollectionScenario.cs`
- `TestAuto.Connect\Services\ConnectExecutionRepository.cs`, `IConnectExecutionRepository.cs`
- `TestAuto.Connect\Metrics\MetricDetailConnectApiExecution.cs`, `ConnectMetricConstants.cs`
- `TestAuto.Connect\AutoRegistration\ConnectModuleRegistrar.cs`
- `TestAuto.Utilities\Common\ConnExConstants.cs`
- `TestAuto.Utilities\Scripts\ConnEx\ServiceConfigurations\CORPLTR94_ModelSource.json`
- `Testing.SpeedMerchants.Integration\Tests\RESTGateway\Connect\ConnExServiceConfigImportTests.cs`
- `Testing.SpeedMerchants.Unit\Tests\Connect\` (ConnectBatchStateTests, ConnectStrategyPollingScenarioTests)
