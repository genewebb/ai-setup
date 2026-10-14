---
name: testauto-metric-detail-builder
description: >
  Fluent builders for MetricDetailBase and MetricBatchSummaryBase in TestAuto scenarios, plus the two
  separate metric factories beside them. Use when building details with GenericMetricDetailBuilder or
  summaries with MetricSummaryRequestBuilder, wiring IMetricFactory vs the distinct
  IMetricDetailFactory, deciding which a scenario should inject, or debugging zero elapsed-time in
  persisted metrics (missing .Update()). The two factories share no members — not one API, and not
  the TestData.* enrichment generators.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Metric Detail Builder

This skill covers the fluent builder pattern used throughout `TestAuto.Metrics` and
`TestAuto.Shared` to construct metric records that are persisted after Hangfire batch jobs
complete.

---

## GenericMetricDetailBuilder\<TDetail\>

Located in `TestAuto.Shared/Builders/GenericMetricDetailBuilder.cs`.

A single, reusable builder for **any** `TDetail : MetricDetailBase, new()`. Replaces the
old pattern of writing a dedicated builder class per detail type.

```csharp
var detail = new GenericMetricDetailBuilder<MyDetailType>()
    .With(d => d.ScenarioName, "Matching_Standard")
    .With(d => d.ExecutionStatus, "Complete")
    .With(d => d.RecordCode, record.Code)
    .With(d => d.LubcRequestTime, DateTimeOffset.UtcNow)
    .Build();
```

### How it works

- Constructor allocates `new TDetail()` immediately.
- `.With<TProp>(Expression<Func<TDetail, TProp>> selector, TProp value)` extracts the
  `PropertyInfo` from a `MemberExpression` and sets the value via reflection.
- `.Build()` returns the accumulated `TDetail` instance.
- Throws `ArgumentException` if the selector is not a direct property reference
  (e.g. method calls or nested expressions are rejected).

### Rules

- The expression **must** be a direct property accessor: `d => d.SomeProp`. Computed
  expressions like `d => d.A + d.B` or method calls like `d => d.GetFoo()` will throw.
- `TDetail` must have a public parameterless constructor (`new()` constraint).
- Each `.With(...)` call returns `this` — chain as many as needed before `.Build()`.

---

## MetricSummaryRequestBuilder

Located in `TestAuto.Metrics/Builders/MetricSummaryRequestBuilder.cs`.

Builds a `MetricBatchSummaryBase` for the end-of-batch summary record. Requires an
`IMetricBatchSummaryFactory` (injected) and a scenario name. The factory creates the
correct strongly-typed summary subclass via `summaryFactory.Create(scenarioName)`.

### Full method surface

| Method | Sets |
|---|---|
| `.WithDetailedMetrics(list)` | `DetailedMetrics` collection |
| `.WithRecordVolume(n)` | `RecordVolume` |
| `.WithElapsedSeconds(n)` | `ElapsedSeconds` directly |
| `.WithElapsedTime(timespan)` | `ElapsedTime` (requires `.Update()` to derive seconds) |
| `.WithStartTime(dt)` / `.WithEndTime(dt)` | `StartTime` / `EndTime` |
| `.WithSuccessfulRecords(n)` / `.WithFailedRecords(n)` | success/fail counts |
| `.WithMaxRunningScenarioCount(n)` | concurrency high-water mark |
| `.WithProfiseeVersion(s)` | `ProfiseeVersion` |
| `.WithScenario(name, id)` | both `ScenarioName` and `ScenarioId` together |
| `.WithScenarioName(s)` / `.WithScenarioId(id)` | individual scenario fields |
| `.WithWorkloadName(s)` / `.WithWorkloadId(id)` | workload fields |
| `.WithHangfireJob(n)` | `HangfireJob` int |
| `.WithJobName(s)` / `.WithJobId(id)` | job identification |
| `.WithDriverName(s)` / `.WithDriverId(id)` | driver identification |
| `.WithSummaryType(s)` | `SummaryType` string |
| `.Update()` | **Derives `ElapsedSeconds` from `ElapsedTime`** |
| `.Build()` | Returns the `MetricBatchSummaryBase` |

### CRITICAL: Always call `.Update()` before `.Build()` when using `.WithElapsedTime()`

```csharp
// WRONG — ElapsedSeconds stays 0 even though ElapsedTime is set
var summary = builder
    .WithElapsedTime(elapsed)
    .Build();

// CORRECT
var summary = builder
    .WithElapsedTime(elapsed)
    .Update()   // <-- derives ElapsedSeconds = (int)ElapsedTime.TotalSeconds
    .Build();
```

`.Update()` only copies `ElapsedTime → ElapsedSeconds` if `ElapsedTime != default`. If
you set `ElapsedSeconds` directly via `.WithElapsedSeconds(n)` you do not need `.Update()`.

### Typical usage pattern

```csharp
var summaryRequest = new MetricSummaryRequestBuilder(_summaryFactory, scenarioName, _logger)
    .WithDetailedMetrics(detailList)
    .WithRecordVolume(totalRecords)
    .WithSuccessfulRecords(successCount)
    .WithFailedRecords(failCount)
    .WithStartTime(startTime)
    .WithEndTime(endTime)
    .WithElapsedTime(endTime - startTime)
    .WithScenario(scenarioName, scenarioId)
    .WithProfiseeVersion(profiseeVersion)
    .Update()   // derive ElapsedSeconds
    .Build();
```

---

## MetricFactory / IMetricFactory

Located in `TestAuto.Metrics/Common/MetricFactory.cs`.

Responsible for instantiating the correct `MetricDetailBase` and `MetricBatchSummaryBase`
concrete types for a given scenario.

```csharp
// Create a detail instance for a single record result
MetricDetailBase detail = _metricFactory.CreateMetric(config, isSuccess: true, dimensionUnderTest);

// Create a batch summary container
MetricBatchSummaryBase summary = _metricFactory.CreateBatchSummary(config);

// Create a workload summary
MetricWorkloadSummary workload = _metricFactory.CreateWorkloadSummary(config);
```

### How type resolution works

- `CreateMetric`: uses `ScenarioTypeRegistry.GetMetricDetailType(config.ScenarioName)` to
  look up the registered `TDetail` type (driven by an attribute on the scenario class),
  then `Activator.CreateInstance(detailType)`. Populates `ScenarioName` and
  `ExecutionStatus` automatically.
- `CreateBatchSummary`: always returns a `new MetricBatchSummaryBase` with `ScenarioName`
  set. Does not use the registry.
- The `DetailTypeName` used by `ScenarioTypeRegistry` comes from an attribute on the
  scenario class — wrong attribute value means wrong type is instantiated.

---

## IMetricDetailFactory — a DIFFERENT factory, not an alias

`IMetricDetailFactory` (`TestAuto.Metrics/Interfaces/IMetricDetailFactory.cs`, implemented by
`TestAuto.Metrics/Factories/MetricDetailFactory.cs:16`) is a **separate** interface from
`IMetricFactory`. They share **no members**. Both are registered as singletons side by side
(`MetricsServiceExtensions.cs:45-46`) and both are injected into `ScenarioBase` as distinct fields
(`ScenarioBase.cs:36` `_metricFactory`, `:38` `_metricDetailFactory`).

```csharp
public interface IMetricDetailFactory
{
    MetricDetailBase Create(IMetricScenarioConfiguration scenarioConfiguration);
    MetricDetailBase Create(string scenarioName);
    MetricDetailBase CreateByDetailType(string detailType);
    MetricDetailBase Deserialize(string json, IMetricScenarioConfiguration scenarioConfiguration);
    MetricDetailBase Deserialize(string json, string scenarioName);
}
```

| | `IMetricFactory` | `IMetricDetailFactory` |
|---|---|---|
| Scope | Detail **+** batch summary **+** workload summary | Detail objects only |
| Members | `CreateMetric(config, isSuccess, dimensionUnderTest)`, `CreateBatchSummary(config)`, `CreateWorkloadSummary(config)` | `Create(config)`, `Create(scenarioName)`, `CreateByDetailType(detailType)`, `Deserialize(json, config)`, `Deserialize(json, scenarioName)` |
| Populates fields on create? | Yes — sets `ScenarioName` and `ExecutionStatus` from `isSuccess` (`MetricFactory.cs:37-40`) | No — bare `Activator.CreateInstance` (`MetricDetailFactory.cs:62`, `:71`) |
| Deserialization | None | Yes — the JSON round-trip entry point |
| Type lookup | `ScenarioTypeRegistry.GetMetricDetailType(config.ScenarioName)` (`MetricFactory.cs:34`) | `IScenarioResolver` → the scenario's `[ScenarioTypes]` attribute (`:34-35`, `:46-47`, `:65-72`), **or** a reverse registry scan by detail-type name (`:56-62`) |
| Ctor dependency | `IServiceProvider` | `IScenarioResolver` |

**Which to inject**: use `IMetricFactory` when a scenario needs the summary objects too; use
`IMetricDetailFactory` when you only need a detail instance, or when you must rehydrate a detail
from stored JSON (`Deserialize`) or resolve one from a bare `DetailType` string
(`CreateByDetailType` — the persistence path, where only the string is available).

---

## MetricsPersistenceJob

Located in `TestAuto.Metrics/HangfireJobs/MetricsPersistenceJob.cs`.

Runs after a batch of Hangfire worker jobs finishes. Reads job results from Hangfire
storage, deserializes summaries, groups detail metrics by `DetailType`, and dispatches to
type-specific persistence handlers.

### Constructor dependencies

- `IHangfireReader` — reads job state and deserializes results from Hangfire storage
- `Func<RestSubjectArea, IRestClient>` factory — resolves a `RestSubjectArea.Metrics`
  scoped REST client for persisting summaries to the metrics API
- `IMetricBatchSummaryFactory` — deserializes raw JSON back into typed summary objects
- `IMetricDetailPersistenceFactory` — dispatches details to type-specific persistence handlers

### Job execution: `ExecutePersistenceAsync`

```
For each jobId in the provided list:
  1. GetJobState(jobId)
     - null → log error, skip
     - still Processing → retry up to 3×, 30-second waits each
     - still Processing after 3 retries → log error, skip
     - any state other than "Succeeded" → log error, skip
  2. DeserializeJobResult<object>(jobId)
  3. summaryFactory.Deserialize(resultJson, scenarioName) → MetricBatchSummaryBase
  4. Collect summary.DetailedMetrics into allDetailedMetrics
After all jobs processed:
  Group allDetailedMetrics by DetailType
  Dispatch each group to the appropriate persistence handler
```

### Common pitfalls in MetricsPersistenceJob

- If a job is in a failed/deleted/expired state (not "Succeeded"), its metrics are silently
  skipped — check logs at `LogTagConstants.Metrics` level for skip messages.
- `summaryFactory.Deserialize` returns null if the JSON does not match the expected type for
  the scenario — verify the metric detail type (the second `typeof(...)` argument of
  `[ScenarioTypes]`) is correct on the scenario class.

---

## Common ProcessBatchAsync Pattern

The standard pattern inside a batch processing method (used across many scenarios):

```csharp
var detailList = new List<MetricDetailBase>();
var startTime = DateTime.UtcNow;

foreach (var record in batch)
{
    bool success = false;
    try
    {
        // ... do work ...
        success = true;
    }
    catch (Exception ex)
    {
        _logger.ErrorWithTag(LogTagConstants.Metrics, ex, "Failed record {Code}", record.Code);
    }

    // Build and accumulate one detail per record
    var detail = new GenericMetricDetailBuilder<MyDetailType>()
        .With(d => d.ScenarioName, scenarioName)
        .With(d => d.RecordCode, record.Code)
        .With(d => d.ExecutionStatus,
              success ? MetricSharedConstants.ExecutionStatusComplete
                      : MetricSharedConstants.ExecutionStatusFailed)
        .Build();

    detailList.Add(detail);
}

var endTime = DateTime.UtcNow;

// Build the batch summary — don't forget .Update()
return new MetricSummaryRequestBuilder(_summaryFactory, scenarioName, _logger)
    .WithDetailedMetrics(detailList)
    .WithRecordVolume(batch.Count)
    .WithSuccessfulRecords(detailList.Count(d => d.ExecutionStatus == MetricSharedConstants.ExecutionStatusComplete))
    .WithFailedRecords(detailList.Count(d => d.ExecutionStatus != MetricSharedConstants.ExecutionStatusComplete))
    .WithStartTime(startTime)
    .WithEndTime(endTime)
    .WithElapsedTime(endTime - startTime)
    .WithScenario(scenarioName, scenarioId)
    .Update()   // ← derive ElapsedSeconds — do not omit
    .Build();
```

---

## Named Pitfalls

| Pitfall | Symptom | Fix |
|---|---|---|
| Missing `.Update()` on `MetricSummaryRequestBuilder` | `ElapsedSeconds = 0` in persisted metrics even though job ran for minutes | Add `.Update()` between `.WithElapsedTime(...)` and `.Build()` |
| Wrong metric detail type on scenario class | `MetricFactory.CreateMetric` instantiates wrong subtype; fields are missing in storage | Check the second `typeof(...)` argument of `[ScenarioTypes]` — that is what `ScenarioTypeRegistry` registers as the detail type (there is no separate `[MetricDetailType]` attribute) |
| Using `.WithElapsedSeconds()` and `.WithElapsedTime()` both | `.Update()` will overwrite `.WithElapsedSeconds()` if `ElapsedTime != default` | Pick one approach — prefer `.WithElapsedTime(...).Update()` |
| Providing a non-property expression to `.With(...)` | `ArgumentException` at runtime | Use only direct property accessors: `d => d.PropertyName` |
| Redeclaring a `[MetricColumn]`-mapped base property on a `MetricDetailBase` subclass | Persisted metric has a `null` value for that field (e.g. `ScenarioName`); reads via a `MetricDetailBase` reference also see `null` | Remove the subclass property — the standalone `public string ScenarioName` **shadows** the column-mapped base property, so values assigned to it never reach the mapped one. Use the inherited property; only declare fields the base does **not** define (e.g. `ScenarioId`). |

---

## Sources

- `TestAuto.Shared\Builders\GenericMetricDetailBuilder.cs`
- `TestAuto.Metrics\Builders\MetricSummaryRequestBuilder.cs`
- `TestAuto.Metrics\Common\MetricFactory.cs` (`IMetricFactory` impl)
- `TestAuto.Metrics\Interfaces\IMetricFactory.cs`
- `TestAuto.Metrics\Interfaces\IMetricDetailFactory.cs`
- `TestAuto.Metrics\Factories\MetricDetailFactory.cs` (`IMetricDetailFactory` impl, line 16)
- `TestAuto.DependencyInjection\ServiceExtensions\MetricsServiceExtensions.cs` (both singletons, lines 45-46)
- `TestAuto.Metrics\HangfireJobs\MetricsPersistenceJob.cs`
