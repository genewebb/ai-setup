---
name: testauto-scenario-types-attribute
description: >
  ScenarioTypesAttribute declaration, parameter order, and registry lookup patterns for
  TestAuto scenario classes. Use when adding [ScenarioTypes] to a new scenario, choosing
  DataPattern or CustomParmsEditorType values, understanding how the batch orchestrator
  determines job count, checking whether a scenario requires metrics, or debugging
  ScenarioTypeRegistry failures after plugin load.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto ScenarioTypesAttribute

## Attribute Declaration

Every concrete scenario class **must** have `[ScenarioTypes(...)]` applied. The attribute
is defined on `ScenarioTypesAttribute` in `TestAuto.Shared.Common.Scenario`. It is not
inherited (`[AttributeUsage(Inherited = false)]`).

```csharp
[ScenarioTypes(
    typeof(MyTestDataGenerator),    // 1. TestDataType
    typeof(MetricDetailRecordApi),  // 2. MetricDetailType
    typeof(MetricBatchSummaryBase), // 3. MetricSummaryType
    RestSubjectArea.Profisee,       // 4. RestSubjectArea
    DataPattern.Paged,              // 5. DataPattern        (default: Other)
    CustomParmsEditorType.Default)] // 6. CustomParmsEditor  (default: Default)
public class MyScenario : ScenarioBase { ... }
```

---

## Parameter Reference (exact order)

### 1. `Type testDataType`

The `ITestData` implementation (concrete generators derive from `DataRecordBase : ITestData`)
that produces test records for this scenario. Common types:

| Type                      | Use case                                              |
| ------------------------- | ----------------------------------------------------- |
| `PagedRecords`            | Scenarios that page through existing entity records   |
| `UniqueRecordCodes`       | Scenarios that generate unique record codes           |
| `DefaultNoOpGenerator`    | Scenarios that fetch their own data (no pre-generated records) |

### 2. `Type metricDetailType`

The metric detail class that captures per-record/per-call metrics. Use `MetricDetailNone`
to opt out of metrics entirely (triggers the no-metrics execution path).

| Type                          | Use case                                      |
| ----------------------------- | --------------------------------------------- |
| `MetricDetailRecordApi`       | Standard record CRUD operations               |
| `MetricDetailConnectApiExecution` | Connect batch execution metrics           |
| `MetricDetailNone`            | Utility/metadata scenarios — no metrics       |

### 3. `Type metricSummaryType`

The metric summary class for aggregating batch results.

| Type                      | Use case                                      |
| ------------------------- | --------------------------------------------- |
| `MetricBatchSummaryBase`  | Standard summary for most scenarios           |
| `MetricBatchSummaryNone`  | Paired with `MetricDetailNone` (no metrics)   |

### 4. `RestSubjectArea restSubjectArea`

The REST API area this scenario targets. Used by `ScenarioBase.GetRestSubjectAreaFromAttribute()`
to resolve the correct `IRestClient`.

| Value          | API area                              |
| -------------- | ------------------------------------- |
| `Profisee`     | Core records/entity REST API (also used by metadata scenarios — there is no `Metadata` member) |
| `Metrics`      | Metrics REST API                      |
| `Connect`      | Connect service (strategy execution)  |
| `Portal`       | Portal API                            |
| `Matching`     | Matching API                          |
| `Data`         | Data API                              |
| `ScenarioMgt`  | Scenario management / workload tracking |
| `Monitor`      | Monitor API                           |

### 5. `DataPattern dataPattern` (default: `DataPattern.Other`)

Controls how `BatchJobOrchestrator` partitions work into Hangfire child jobs. **Wrong
value silently breaks the pipeline** — no exception is thrown, but job count and payload
will be wrong.

See the DataPattern section below for full details.

### 6. `CustomParmsEditorType customParmsEditor` (default: `CustomParmsEditorType.Default`)

Selects the UI editor rendered in the scenario editor for the CustomParms field. Does not
affect batch execution logic — UI only.

See the CustomParmsEditorType section below for full details.

---

## DataPattern Enum

Defined in `TestAuto.Shared.Common.Scenario.ScenarioTypesAttribute.cs`.

| Value        | Child jobs per server    | Payload                        | When to use                                                 |
| ------------ | ------------------------ | ------------------------------ | ----------------------------------------------------------- |
| `Other`      | 1 (one per server)       | Empty `List<Record>`           | Default / legacy. Scenario self-partitions via `GlobalBatchNumber`/`TotalGlobalBatches` |
| `Paged`      | N (one per page)         | Page of records from factory   | Orchestrator controls paging; most CRUD read scenarios      |
| `Single`     | N (one per record)       | Single record from factory     | Per-record isolation needed (e.g., strategy execution)      |
| `SelfManaged`| 1 (one per server)       | Empty payload                  | Scenario streams its own records internally (e.g., `MatchingStrategyPollingScenario`) |

**`Other` vs `SelfManaged`**: Both produce one job per server with an empty payload.
`Other` is the historical default; `SelfManaged` makes the intent explicit. The orchestrator
treats `Other` and `SelfManaged` identically in the partition step — the difference is
documentation/intent only.

**`Paged` vs `Other`**: With `Paged`, the orchestrator calls
`factory.GetRecordsForScenario(...)` for each page and passes records in the JSON payload.
With `Other`, the payload is always an empty list; the scenario fetches records itself via
REST or DB.

**Choosing the right value**:
- Scenario pages through records via `TestRecordLimit`/`BatchSize` config → `Paged`
- Scenario executes once per record with independent metrics → `Single`
- Scenario uses `RecordMixManager` or similar self-streaming → `Other` or `SelfManaged`
- One-shot utility/management scenario (no record iteration) → `Other` with `TestRecordLimit=1`

---

## CustomParmsEditorType Enum

Defined in `TestAuto.Shared.Common.Scenario.ScenarioTypesAttribute.cs`.

| Value                       | UI rendered                                                                       |
| --------------------------- | --------------------------------------------------------------------------------- |
| `Default`                   | Grid for simple key-value pairs plus JSON editor. Correct for most scenarios.     |
| `JsonOnly`                  | JSON-only editor for complex nested CustomParms structures.                        |
| `UtilityScenarioEditor`     | Structured editor specifically for `MultiStepUtilityScenario`.                   |
| `MatchingSnapshotCapture`   | Editor for `MatchingSnapshotCaptureScenario` with step reference support.         |
| `UnifiedMatchingScenario`   | Editor for `UnifiedMatchingScenario` with organized parameter sections.           |
| `MetadataManagementEditor`  | Entity/attribute management editor. Action dropdowns offer exactly **`add` / `delete` / `replace`** (`MetadataManagementEditor.razor.cs:58-59` → `MetadataConstants.cs:167-169`) — there is **no** `Update` action. Values are lowercase constants and are read back case-insensitively, defaulting to `add`. |
| `MatchingStrategyConfigEditor` | Wizard-style editor for `MatchingStrategyUpdateScenario` with conditional fields. |
| `UnifiedMatchingPostRunCollection` | Editor for `UnifiedMatchingPostRunCollectionScenario` — supplies the source (3c) `WorkloadExecution` to enrich plus golden-record polling settings. Replaces the old in-wizard "Scenario 4 / post-test metric collection" config. |
| `ConnectStrategyPolling`    | Editor for `ConnectStrategyPollingScenario` — StrategyName to poll plus poll interval and maximum wait, with range validation matching the scenario's rules. |
| `ConnectPostRunCollection`  | Editor for `ConnectPostRunCollectionScenario` — StrategyName + required RunProfile code plus batch-age / paging / concurrency settings, with range validation matching the scenario's rules. |

---

## ScenarioTypeRegistry

**File**: `TestAuto.Shared\Helpers\ScenarioTypeRegistry.cs`

Reflection-based static cache mapping `scenarioName → ScenarioTypesAttribute`. Built once
at static constructor time by scanning all assemblies in `AppDomain.CurrentDomain`.

### Key methods

```csharp
// Rebuild the map — MUST be called after plugin assemblies are loaded
ScenarioTypeRegistry.Refresh();

// Check whether a scenario needs MetricsPersistenceJob
bool needs = ScenarioTypeRegistry.RequiresMetrics(scenarioName);

// Read individual attribute fields
Type testDataType       = ScenarioTypeRegistry.GetTestDataType(scenarioName);
Type metricDetailType   = ScenarioTypeRegistry.GetMetricDetailType(scenarioName);
Type metricSummaryType  = ScenarioTypeRegistry.GetMetricSummaryType(scenarioName);
CustomParmsEditorType e = ScenarioTypeRegistry.GetCustomParmsEditorType(scenarioName);
```

### RequiresMetrics logic

```csharp
// Returns false only when MetricDetailType == typeof(MetricDetailNone)
// Unknown scenarios default to true (safe default)
public static bool RequiresMetrics(string scenarioName) { ... }
```

This is the gate that controls whether `MetricsPersistenceJob` continuations are created
and whether `WorkloadExecutionUpdateJob` chains after metrics jobs or directly after child
jobs. Getting `MetricDetailType` wrong is the most impactful mistake when declaring
`[ScenarioTypes]`.

---

## MetricDetailNone and the No-Metrics Path

Setting `metricDetailType = typeof(MetricDetailNone)` signals:
- `ScenarioTypeRegistry.RequiresMetrics()` returns `false`
- `MetricsPersistenceJob` continuations are **not created**
- `WorkloadExecutionUpdateJob` chains directly after the last child `ProcessBatchJob`
- If any child job fails, `SetWorkloadExecutionFailedAsync` writes `ExecutionStatus = "Failed"`
  to the `WorkloadExecution` REST record immediately (best-effort)

Always pair `MetricDetailNone` with `MetricBatchSummaryNone` as the summary type.

---

## Example Attribute Usages

### Standard CRUD read scenario (paged)

```csharp
[ScenarioTypes(
    typeof(PagedRecords),
    typeof(MetricDetailRecordApi),
    typeof(MetricBatchSummaryBase),
    RestSubjectArea.Profisee,
    DataPattern.Paged, CustomParmsEditorType.Default)]
public class GetRecordsByPageAndBatchScenario : ScenarioBaseCrud { ... }
```

### Connect post-run metric collection (self-managed)

```csharp
[ScenarioTypes(
    typeof(DefaultNoOpGenerator),
    typeof(MetricDetailConnectApiExecution),
    typeof(MetricBatchSummaryBase),
    RestSubjectArea.Connect,
    DataPattern.SelfManaged, CustomParmsEditorType.ConnectPostRunCollection)]
public class ConnectPostRunCollectionScenario : ScenarioBaseConnect { ... }
```

> No current Connect scenario uses `DataPattern.Single`. Both live `ScenarioBaseConnect`
> scenarios (`ConnectStrategyPollingScenario`, `ConnectPostRunCollectionScenario`) are
> `DataPattern.SelfManaged` — one Hangfire job total, scenario owns its own loop.

### Metadata management utility (no metrics, custom editor)

```csharp
[ScenarioTypes(
    typeof(DefaultNoOpGenerator),
    typeof(MetricDetailNone),
    typeof(MetricBatchSummaryNone),
    RestSubjectArea.Profisee,
    DataPattern.Other, CustomParmsEditorType.MetadataManagementEditor)]
public class MetadataManagementScenario : ScenarioBaseMetadata { ... }
```

### Self-managed matching gate scenario (live values)

Copied verbatim from `MatchingStrategyPollingScenario.cs:43-51`:

```csharp
[ScenarioTypes(
    typeof(ScenarioConfigurationOnly),           // TestDataType - no test records needed
    typeof(MetricDetailNone),                    // MetricDetailType
    typeof(MetricBatchSummaryNone),              // MetricSummaryType
    RestSubjectArea.Matching,                    // REST API subject area
    DataPattern.SelfManaged,                     // Self-managed execution (one Hangfire job)
    CustomParmsEditorType.Default)]              // Simple key-value editor
[ScenarioDisplay("Matching")]                    // UI category
public class MatchingStrategyPollingScenario : ScenarioBaseMatching { ... }
```

Four things worth calling out, because an earlier revision of this skill got all of them wrong:

- The generator is **`ScenarioConfigurationOnly`**, not `DefaultNoOpGenerator`.
- It is a **no-metrics** scenario — `MetricDetailNone` + `MetricBatchSummaryNone`, so
  `RequiresMetrics()` returns false and no `MetricsPersistenceJob` continuation is created. There is
  no `MetricDetailMatchingApi` in the slot.
- The subject area is **`Matching`**, not `Profisee`.
- The editor is **`Default`** (plain key-value grid), not `UnifiedMatchingScenario` — that editor
  belongs to `UnifiedMatchingScenario` itself, not to this polling gate.

---

## Critical Pitfalls

1. **Wrong DataPattern silently breaks the pipeline.** No exception is thrown. If a
   self-managing scenario is marked `Paged`, the orchestrator will call the factory to
   generate pages and pass record payloads that the scenario ignores. If a paged scenario
   is marked `Other`, only one job per server is created regardless of `TestRecordLimit`.

2. **Plugin scenarios not in registry.** The static constructor fires at first access,
   which may be before plugins are loaded. Always call `ScenarioTypeRegistry.Refresh()`
   after `RegisterPlugins()` / `AddScenarioManagementServices()`.

3. **MetricDetailNone without MetricBatchSummaryNone (or vice versa).** Both types should
   be paired. Mixing them (e.g., `MetricDetailNone` with `MetricBatchSummaryBase`) compiles
   but may cause serialization issues or unexpected metric rows.

4. **Missing [ScenarioTypes] on a scenario class.** `ScenarioBase.GetRestSubjectAreaFromAttribute()`
   throws `InvalidOperationException` at runtime. The registry will not contain the scenario.
   The orchestrator falls back to `DataPattern.Paged` for unknown scenarios.

---

## Sources

- `TestAuto.Shared\Common\Scenario\ScenarioTypesAttribute.cs`
- `TestAuto.Shared\Helpers\ScenarioTypeRegistry.cs`
- `TestAuto.Scenarios\Common\ScenarioBase.cs`
- `TestAuto.Scenarios\BatchProcessing\BatchJobOrchestrator.cs` (DataPattern → job-count branching, lines 165-290)
- `TestAuto.Matching\Scenarios\MatchingStrategyPollingScenario.cs` (lines 43-51)
- `TestAuto.Web\Components\Controls\MetadataManagementEditor.razor.cs` (action list, lines 58-59)
- `TestAuto.Shared\Common\MetadataConstants.cs` (action constants, lines 167-169)
