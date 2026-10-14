---
name: testauto-scenario-metrics
description: >
  Attribute-driven scenario and metrics framework for TestAuto. Use when adding a new
  scenario class, defining [ScenarioTypes] and [MetricColumn] attributes, building metrics
  with GenericMetricDetailBuilder<T>, instrumenting CRUD REST calls via ScenarioBaseCrud's
  ExecutePost/Patch/Get/DeleteAsync helpers, wiring TestDataFactory data generators, or
  troubleshooting silent metric persistence failures.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Attribute-Driven Scenario & Metrics Framework

> **Scope**: speed-merchants (TestAuto + TestAuto.Shared)
> **Source**: TestAuto/Documentation/AttributeDrivenMetricsGuide.md, MetricCollection.md

---

## [ScenarioTypes] Attribute

Every scenario class must be decorated with `[ScenarioTypes]`:

```csharp
[ScenarioTypes(
    typeof(PagedRecords),              // ITestData: how test records are generated
    typeof(MetricDetailRecordApi),     // MetricDetailBase-family: per-record metric class
    typeof(MetricBatchSummaryBase),    // MetricBatchSummaryBase: batch summary (optional custom)
    RestSubjectArea.Profisee,          // Which REST client to use
    DataPattern.Paged                  // Data access pattern
)]
public class GetRecordsByPageAndBatchScenario : ScenarioBaseCrud { }
```

> **There is no `LubcMatchingScenario` class.** A bare-name grep hits only the legacy sample
> `TestAuto.Matching\Samples\TestCases\LubcMatching.json` (`"ScenarioName": "LubcMatchingScenario"`).
> Don't cite it as a live example.

### Parameters

| Parameter | Type | Description |
|---|---|---|
| TestDataType | `typeof(ITestData)` | Record generator class used by `TestDataFactory` |
| MetricDetailType | `typeof(MetricDetailBase)` | Per-record metric class; properties need `[MetricColumn]` |
| MetricSummaryType | `typeof(MetricBatchSummaryBase)` | Batch summary; use `MetricBatchSummaryBase` unless custom |
| SubjectArea | `RestSubjectArea` | `Profisee`, `Metrics`, `Connect`, `Portal`, `Matching`, `Data`, `ScenarioMgt`, `Monitor` |
| DataPattern | `DataPattern` | `Single`, `Paged`, `SelfManaged`, or `Other` |
| EditorType | `CustomParmsEditorType` | Optional — specifies the custom parms UI editor |

---

## [MetricColumn] Attribute

> **Silent failure rule**: Column names in `[MetricColumn("...")]` must **exactly** match the attribute name in the Profisee entity. A mismatch causes data to not be saved — no error, no warning.

```csharp
// NB: this one derives from MetricRequestBase, NOT MetricDetailBase directly
// (MetricDetailLubcMatching.cs:12). Real chain:
//   MetricDetailLubcMatching : MetricRequestBase : MetricDetailExtended : MetricDetailBase
// so it still satisfies the [ScenarioTypes] MetricDetailType slot and
// [MetricColumn] mapping works identically — but don't "fix" the declaration
// to MetricDetailBase; you would drop the request/extended columns.
public class MetricDetailLubcMatching : MetricRequestBase
{
    [MetricColumn("LubcRequestTime")]
    public DateTimeOffset? LubcRequestTime { get; set; }

    [MetricColumn("LubcResponseTime")]
    public DateTimeOffset? LubcResponseTime { get; set; }

    [MetricColumn("LookupDurationMs")]
    public int? LookupDurationMs { get; set; }
}
```

- Every property to persist **must** have `[MetricColumn]`
- The string value must match the Profisee entity attribute name exactly (case-sensitive)
- Reflection maps properties to columns automatically — no manual mapping code

---

## MetricDetailBase Inheritance

```csharp
// Base provides: DetailType, StartTime, EndTime, etc.
public class MyMetricDetail : MetricDetailBase
{
    [MetricColumn("MyCustomField")]
    public string? MyCustomField { get; set; }
}
```

---

## GenericMetricDetailBuilder\<T\>

Use the builder to populate metrics inside your scenario logic:

```csharp
var builder = new GenericMetricDetailBuilder<MetricDetailLubcMatching>()
    .With(d => d.DetailType, DetailTypeName)
    .With(d => d.StartTime, DateTime.UtcNow)
    .With(d => d.LubcRequestTime, DateTimeOffset.UtcNow)
    .With(d => d.LubcResponseTime, DateTimeOffset.UtcNow)
    .With(d => d.LookupDurationMs, elapsed.Milliseconds);

var detail = builder.Build();
```

`Build()` simply returns the accumulated detail — it does **not** validate that `[MetricColumn]` properties were set; unset properties persist as null/default.

---

## ScenarioBaseCrud HTTP Execution Helpers

`ScenarioBaseCrud` (`TestAuto.Records/Common/ScenarioBaseCrud.cs`) provides consolidated `protected` execution helpers that wrap each RestClient call with timing, metric construction, metric recording, and logging. This is the convention for CRUD scenario instrumentation — call a helper with a delegate instead of calling the REST client directly and hand-building a `MetricDetailRecordApi`.

**7 helpers covering the 4 HTTP verbs** (6 method names — GET and DELETE have `...WithResult` variants):

| Helper | Signature (key parms) | Returns | Verb tagging |
|---|---|---|---|
| `ExecutePostAsync<TResponse>` | `Func<Task<TResponse>> operation, string endpoint, int recordCount` | `MetricDetailRecordApi` | Defaults to POST in `SetBaseMetricProperties` |
| `ExecutePatchAsync<TResponse>` | same as POST | `MetricDetailRecordApi` | Sets `HttpPatch` |
| `ExecuteGetAsync` (overload 1) | `Func<Task<RecordResult>> operation, endpoint, int recordCount, bool isCodeLookup = true, bool requestWasFiltered = false` | `MetricDetailRecordApi` | Sets `HttpGet` |
| `ExecuteGetAsync` (overload 2) | same minus `recordCount` | `(RecordResult result, MetricDetailRecordApi metric)` | Sets `HttpGet` |
| `ExecuteGetWithResultAsync` | same as GET overload 2 | `(RecordResult, MetricDetailRecordApi)` | Sets `HttpGet` |
| `ExecuteDeleteAsync` | `Func<Task<JsonResponse>> operation, endpoint, int recordCount` | `MetricDetailRecordApi` | Sets `HttpDelete` |
| `ExecuteDeleteWithResultAsync` | `IRestClient restClient, entityName, List<string> recordCodes, bool clearReferencesBeforeDelete, endpoint` | `(JsonResponse, MetricDetailRecordApi)` | Sets `HttpDelete` |

All but `ExecuteDeleteWithResultAsync` take the REST call as a delegate; that one is the exception — it invokes `restClient.DeleteRecordsAsync(...)` itself.

### What every helper does

1. Times the awaited operation with `_stopWatchTimer` (start/end/elapsed ms)
2. Builds a `MetricDetailRecordApi` — success from `IsSuccess` (POST/PATCH/DELETE) or `StatusCode == OK` (GET); error messages joined from `GetErrors()` as `[Code] Description`
3. Calls `SetBaseMetricProperties(detail, cfg, recordCount, endpoint)` — fills `DetailType`, scenario id/name, entity, attribute/DBA counts, page size, environment/workload columns
4. Records via `_metricsAggregatorService.RecordMetric(detail)`
5. Logs a tagged structured event plus `LogProgress(...)`

### Gotchas

- **GET counts actual records**: `ResponseRecordCount` comes from `resp.Records?.Count`, not the requested count; `isCodeLookup`/`requestWasFiltered` flow into the metric flags
- **POST/PATCH/DELETE use `dynamic`** on the response — any `TResponse` exposing `IsSuccess`, `StatusCode`, `GetErrors()`, `ResponseContent` works
- **POST never sets `HttpRequestType` explicitly** — `SetBaseMetricProperties` only defaults it to POST when empty, so verb-specific helpers must set theirs first (they do)

### Who inherits this

14 scenario classes subclass `ScenarioBaseCrud` (all in TestAuto.Records): the CRUD page-and-batch Create/Get/Update/Delete scenarios, `CreatePDataScenario`, `CloneAndMutateScenario`, `StewardshipFilterScenario`, and the Get-by-code/filter/history scenarios. Most call these helpers; a few legacy Get scenarios (`GetRecordsByFilterScenario`, `GetRecordsWithHistoryScenario`, `GetRecordsByCodeScenario`) predate the convention and still call the client or `RecordMetric` directly — new scenario code should use the helpers.

---

## Data Pattern Types

| DataPattern | Description | TestRecordLimit behavior |
|---|---|---|
| `Single` | One record per batch | Caps total unique records |
| `Paged` | Up to `RecordsPerBatch` records per batch, until `TestRecordLimit` | Standard paging |
| `SelfManaged` | One child job **per Hangfire server** with an empty `List<Record>` payload; scenario-managed loop (e.g. `ConnectStrategyPollingScenario`, `MatchingStrategyPollingScenario`) | Scenario-defined |
| `Other` | **Identical to `SelfManaged`** — same orchestrator branch, one child job per server, empty payload | Scenario-defined |

> **`Other` does *not* behave like `Paged`.** `BatchJobOrchestrator.cs:176` is a single
> `if (dataPattern == DataPattern.Other || dataPattern == DataPattern.SelfManaged)` branch: both
> serialize an empty `List<Record>` as the payload (`:191`), set
> `ScenarioEnvironment.SimulatedUserThreadId = serverIndex`, and create exactly **one** child
> `ProcessBatchJob` per server carrying `GlobalBatchNumber`/`TotalGlobalBatches` partition identity
> (`:196-211`) so the scenario can self-partition. `MaxHangfireScenarioServersCount` is what controls
> the job count — not `TestRecordLimit`/`BatchSize`. The difference between `Other` and `SelfManaged`
> is intent/documentation only. Marking a genuinely paged scenario `Other` silently collapses it to
> one job per server.

### Paging example

```
RecordsPerBatch: 50, TestRecordLimit: 120
→ Batch 1: records 1–50
→ Batch 2: records 51–100
→ Batch 3: records 101–120
→ Batch 4: [] (done)
```

---

## Built-in Data Generators

| Scenario | TestDataType | Generator | Pattern |
|---|---|---|---|
| `GetRecordByCodeScenario` | `UniqueRecordCodes` | `UniqueRecordCodes` | Single |
| `GetRecordsByPageAndBatchScenario` | `PagedRecords` | `PagedRecords` | Paged |
| `GetRecordsByPageAndBatchSeqScenario` | `PagedRecords` | `PagedRecords` | Paged |
| `CreateRecordsByPageAndBatchScenario` | `PagedRecords` | `PagedRecords` | Paged |
| `MetadataManagementScenario` / `MetadataLoadScenario` / `ConnectPostRunCollectionScenario` / `UnifiedMatchingPostRunCollectionScenario` | `DefaultNoOpGenerator` | `DefaultNoOpGenerator` | No-op (no test data) |

Use `DefaultNoOpGenerator` when the scenario doesn't need test data.

---

## RestSubjectArea & URL Override

### Default configuration (`appsettings.json`)

```json
"RestClients": {
  "Profisee": { "BaseUrl": "https://your-profisee-url/", "ApiKey": "key" },
  "Metrics":  { "BaseUrl": "https://your-metrics-url/",  "ApiKey": "key" }
}
```

Default: if a subject area has no entry, the `Profisee` entry is used as fallback.

### Per-scenario override

```json
"ScenarioRestTarget": {
  "SubjectAreaOverrides": {
    "Matching": {
      "RestUrlBase": "https://custom-matching-url/",
      "RestApiKey":  "custom-matching-key"
    }
  }
}
```

Applied via `RestUrlManagement.GetWithScenarioOverrides(scenarioConfig)`.

---

## Step-by-Step: Adding a New Scenario

1. **Define types**
   - Implement `ITestData` if you need a custom data generator
   - Inherit `MetricDetailBase`; add `[MetricColumn]` on each property to persist
   - (Optional) Inherit `MetricBatchSummaryBase` for custom summary
   - Create a matching **Profisee entity** with attribute names matching your `[MetricColumn]` strings
   - Set `TargetMetricEntity` in your scenario JSON to that entity name

2. **Annotate the scenario class**
   ```csharp
   [ScenarioTypes(
       typeof(MyTestData),
       typeof(MyMetricDetail),
       typeof(MyMetricSummary),
       RestSubjectArea.Profisee,
       DataPattern.Paged
   )]
   public class MyScenario : ScenarioBaseCrud { }
   ```

3. **Implement scenario logic**
   - Use `GenericMetricDetailBuilder<T>` to populate metrics
   - Read `cfg.ScenarioRuntime.CustomParms` for custom parameters
   - Use `RestUrlManagement` to get base URL and API key

4. **Configure JSON**
   ```json
   {
     "ScenarioEnvironment": { "TargetMetricEntity": "MyEntityName" },
     "ScenarioRuntime": {
       "BatchSize": 1000,
       "CustomParms": { "MyParam": "value" }
     },
     "ScenarioTesting": { "TestRecordLimit": 10000 }
   }
   ```

5. **No extra DI or factory registration** — `[ScenarioTypes]` drives auto-discovery.

> **Reuse tip**: If you don't need custom metrics per request, reuse the existing **`RecordApiExecution`** entity (singular *Record* — `MetricSharedConstants.MetricDetail_Target_RecordApiExecution`, `MetricSharedConstants.cs:84`; there is no `RecordsApiExecution`) and partition tests using the `WorkloadExecution` domain attribute.

---

## Execution Modes via CustomParms

| Mode | CustomParms | Description |
|---|---|---|
| Record-driven | _(default)_ | One run per record |
| Time-driven | `"TimeLimit": "00:05:00"` | Runs until TimeLimit expires |
| Iteration-driven | `"IterationLimit": 15` | Runs until IterationLimit reached |

---

## Nested CustomParm Access

CustomParms is a `Dictionary<string, JToken>`. For nested objects, access as `JObject`:

```csharp
// Manual — direct JObject access
if (customParms.TryGetValue("DataMutationSettings", out var token) && token is JObject settings)
{
    var ruleDefinitions = settings["RuleDefinitions"] as JObject;
    var firstNameRules = ruleDefinitions?["FirstName"]?["Rules"] as JArray;
}

// Helper method pattern
public static JObject? GetCustomObject(IDictionary<string, JToken> customParms, string key)
{
    if (customParms.TryGetValue(key, out var t) && t is JObject obj) return obj;
    return null;
}
var settings = CustomParmHelper.GetCustomObject(customParms, "DataMutationSettings");

// Strongly-typed deserialization
public class DataMutationSettings
{
    public Dictionary<string, RuleDefinition> RuleDefinitions { get; set; }
    public Dictionary<string, List<string>> AttributeGroups { get; set; }
}
var settings = customParms["DataMutationSettings"].ToObject<DataMutationSettings>();
```

Use the strongly-typed approach for complex nested structures — cleaner than repeated `JObject` casts.

---

## Adding a New Detail Type (Attribute-Driven — 2 real steps)

> **This is fully attribute-driven.** There are **no** per-type factory branches, **no**
> `MetricConstants.DetailType_X` constants, **no** builder factory, and **no** per-type
> converter/persistence switch. The concrete detail type is resolved by reflecting over the
> `[ScenarioTypes]` attribute via `ScenarioTypeRegistry`. Any doc describing an 11-file
> "pipeline" (constants → detail factory → summary factory → step builder → list converter →
> persistence handler → DI) is **stale** and describes a superseded design.

To add a new detail type you touch exactly **two** things:

| Step | What to do |
|---|---|
| 1. Create the detail DTO | Add `MetricDetailX : MetricDetailBase` with `[MetricColumn("...")]` properties, in the **owning domain project** (e.g. `TestAuto.Records\Metrics`, `TestAuto.Connect\Metrics`, `TestAuto.Metadata\Metrics`). |
| 2. Reference it in the attribute | Pass `typeof(MetricDetailX)` as the **2nd** argument of `[ScenarioTypes(...)]` on the scenario class (the `MetricDetailType` slot). |

That's it. No factory edits, no `DetailType_X` constant, no builder factory, no per-type
converter, no per-type persistence handler, no extra DI registration.

### Why only two steps — how the factories actually behave

- **`MetricDetailFactory.CreateByDetailType`** (`MetricDetailFactory.cs:53-63`) is
  attribute-driven: it finds the scenario type whose `[ScenarioTypes]` `MetricDetailType.Name`
  matches the requested type name and calls `Activator.CreateInstance` on it. There are **no**
  `if (detailType == ...)` branches.
- **`MetricBatchSummaryFactory.CreateBySummaryType`** (`MetricBatchSummaryFactory.cs:52-93`)
  just returns `new MetricBatchSummaryBase()`; `Deserialize` always targets
  `MetricBatchSummaryBase` via a converter. There are **no** per-type summary branches — reuse
  `MetricBatchSummaryBase` unless you have a genuine custom summary.
- **`MetricDetailBuilderFactory` / `MetricDetailStepBuilder` do not exist** in the codebase
  (0 hits — they appear only in a stale doc). They were replaced by the generic
  `GenericMetricDetailBuilder<T>` (see sibling skill **testauto-metric-detail-builder**).

### Where the real files live

There is **no** `TestAuto.Metrics.Common` project and **no** shared `MetricDetailX.cs` /
`MetricBatchSummaryX.cs`. `MetricConstants.cs` exists only per-domain
(`TestAuto.Records\Metrics`, `TestAuto.Metadata\Metrics`), and detail DTOs live per-domain,
e.g. `TestAuto.Records\Metrics\MetricDetailRecordApi.cs`,
`TestAuto.Connect\Metrics\MetricDetailConnectApiExecution.cs`. Put your new
`MetricDetailX : MetricDetailBase` in whichever domain project owns the scenario.

---

## Metric Collection in Batch Jobs

Each batch job collects per-record metrics; the orchestrator aggregates them via a Hangfire continuation.

### Per-Record Collection (inside `IBatchProcessor.ProcessBatchAsync`)

For each record, capture: start time / end time / elapsed ms, response status, response size, endpoint, query parameters, scenario metadata, and batch size. Create the X-specific metric subtype and call `batchSummary.Add(metric)`. Also increment the summary counters: `TotalRecordsProcessed`, `SuccessfulRecords`, `FailedRecords`.

### Batch Summary Aggregation (inside `ScenarioBatchJobOrchestrator`)

Once all page-level batch jobs complete, Hangfire.Pro fires a continuation job via `BatchJob.ContinueBatchWith`. That continuation:

1. Retrieves each batch's `BatchSummary` via the job result helper
2. Sums totals: `TotalRecordsProcessed`, `SuccessfulRecords`, `FailedRecords`, `ElapsedTime`
3. Concatenates all `DetailedMetrics` lists into a single collection
4. Serializes the merged `BatchSummary` to JSON for output or further reporting

Decoupling collection from aggregation means each batch worker focuses only on its page, and no large in-memory transfers cross job boundaries — only Hangfire job IDs.

---

## The response-code column is NOT uniform across metric entities

`MetricColumnNames` (`TestAuto.Shared/Models/MetricColumnNames.cs:21-25`) carries **two** names for the same
idea:

| Column | Used by |
|---|---|
| `ResponseCode` | Most metric entities |
| `HttpResponseCode` | **`ConnectApiExecution`** |

> [!danger] A success check must probe BOTH names
> Probing only `ResponseCode` made a clean **200 invisible** on Connect rows. They then fell through to the
> status check — which **cannot match them**, because `Complete` / `Successful` are `ExecutionStatus` domain
> values and never the literal `"Success"`. Net effect: a fully successful collection was counted as a
> **failed batch** and marked the step Failed.
>
> `WorkloadExecutionUpdateHelper.IsMetricSuccessful` (`:707`) now iterates both column names. If you add a
> metric entity, either reuse `ResponseCode` or add your name to that array — do not invent a third spelling
> and leave the checker behind.

**Related fail-fast change:** `WorkloadExecutionUpdateHelper` now marks the WorkloadExecution **`Failed`**
when a metrics-required scenario persisted **zero** rows (`:187-209`), instead of returning `false` and
leaving it `Running` for the workflow monitor to poll forever. A run that produced no metrics is a failed
run, and saying so immediately beats an execution that never terminates. See
[[testauto-workflow-execution]].

## Metrics Persistence Pipeline

The persistence job is a follow-on continuation that runs after the aggregation job completes.

### Execution Flow

```
Scenario batch jobs
  → each stores result in Hangfire by job ID

Aggregation job
  → retrieves intermediate summaries by job ID
  → merges into final aggregated summary

Persistence job (follow-on continuation)
  → receives list of Hangfire job IDs
  → retrieves detailed metric records from Hangfire storage
  → transforms records via Transformation Service
  → POSTs batches to target REST API
  → on POST failure: throws → Hangfire retry handles re-execution
```

### Key Components

**Persistence Job**: Retrieves details via `JobStorage.Current.GetConnection()`, passes to Transformation Service, batches to `[data].[tBatchCrudScenarioExecution]`, calls the REST API client. Throws on failure so Hangfire retries.

**Transformation Service**: Maps each `IMetricDetail` to the target data store DTO schema using a strategy/factory pattern. Configurable mapping rules — extend without major code changes.

**Batch-Level Reporting**: The persistence job uses custom Hangfire job parameters to track count:
```csharp
jobClient.SetJobParameter(jobId, "PersistedCount", successCount);
jobClient.SetJobParameter(jobId, "FailedCount",    failureCount);
```

**Intermediate vs Final Summaries**: The aggregator sets a distinguishing flag so the persistence job can select only the detail records for the current phase.

---

## Key Files

| File | Purpose |
|---|---|
| `TestAuto.Shared/Common/Scenario/ScenarioTypesAttribute.cs` | [ScenarioTypes] attribute (also defines the `DataPattern` enum — there is no separate `DataPattern.cs`) |
| `TestAuto.Shared/Models/MetricColumnAttribute.cs` | [MetricColumn] attribute |
| `TestAuto.Shared/Models/MetricDetailBase.cs` | Base metric detail class |
| `TestAuto.Shared/Builders/GenericMetricDetailBuilder.cs` | Metric builder |
| `TestAuto.Scenarios/Factories/TestDataFactory.cs` | Record generator factory |
| `TestAuto.Shared/Rest/RestSubjectArea.cs` | Subject area enum |

## Sources

- `TestAuto\Documentation\AttributeDrivenMetricsGuide.md`
- `TestAuto\Documentation\AddingNewDetailTypes.md`
- `TestAuto\Documentation\MetricCollection.md`
- `TestAuto\Documentation\PersistMetricsDesign.md`
- `TestAuto\Documentation\MetricCollection.md`
- `TestAuto\Documentation\AddingNewDetailTypes.md`
- `TestAuto\Documentation\ParmHelper.md`
- `TestAuto.Records\Common\ScenarioBaseCrud.cs`
- `TestAuto.Scenarios\BatchProcessing\BatchJobOrchestrator.cs` (DataPattern branching, lines 165-290)
- `TestAuto.Shared\Common\Metrics\MetricSharedConstants.cs` (target metric entity names, lines 84-85)
- `TestAuto.Matching\Metrics\MetricDetailLubcMatching.cs` (line 12)
