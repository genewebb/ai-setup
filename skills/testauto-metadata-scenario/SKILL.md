---
name: testauto-metadata-scenario
description: >
  MetadataManagementScenario and MetadataLoadScenario design patterns for TestAuto. Use when implementing metadata CRUD load tests, configuring entity/attribute Add/Delete CustomParms, understanding idempotency and collision handling, debugging iteration limits and uniqueness suffixes, or wrapping metadata API calls with the InstrumentAsync/InstrumentWithResultAsync metric helpers in ScenarioBaseMetadata.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Metadata Scenario

## When to Use

- Implementing a scenario that creates or deletes Profisee entities and attributes via the API
- Configuring `CustomParms` for metadata management or load test scenarios
- Debugging name collisions, iteration limits, or uniqueness suffix behavior
- Adding domain entity support to a metadata scenario
- Wiring metrics collection for entity/attribute operations

## Scenario Types

There are two distinct scenario classes. Choose based on whether the goal is one-shot management or iterative load testing.

### MetadataManagementScenario

- Parses `entities` and `attributes` from `CustomParms` and executes each action exactly once.
- Supports `Add` and `Delete` actions for attributes. For **entities** the `action` value is ignored — `ProcessEntitiesCoreAsync` always deletes the entity if it exists, then recreates it, regardless of whether the config says `Add` or `Delete`.
- Handles domain entities: ensures domain entities are created before domain-type attributes reference them.
- Per-item failures are caught and recorded — the scenario continues to the next entity/attribute rather than stopping on the first error. The one hard gate: if **any** entity operation fails, attribute processing is skipped entirely (and otherwise attributes are only processed for entities that succeeded).
- Does not iterate. Does not have time or iteration limits.
- Uses `MetadataCrudHelper` (`ProcessEntitiesAsync` / `ProcessAttributesAsync`) and `IRestClient` for all operations.

### MetadataLoadScenario

- Executes the same entity/attribute operations repeatedly across bounded iterations.
- Supports time-bounded (`TimeLimit`) and iteration-bounded (`IterationLimit`) execution.
- By default uses the raw config entity names verbatim each iteration (`UseBaseNamesOnly` is effectively true); opt into per-iteration unique entity names by setting `UseBaseNamesOnly=false`.
- Supports concurrent execution — multiple simultaneous instances with thread-safe name generation.
- An all-or-nothing policy applies per iteration: if any operation fails, the entire iteration is marked failed.
- Use this when measuring throughput, detecting regressions under load, or stress-testing the metadata API.

## CustomParms JSON Structure

Both scenarios share the same `entities` and `attributes` schema. `MetadataLoadScenario` adds timing and iteration parameters.

### MetadataManagementScenario

```json
{
  "CustomParms": {
    "entities": [
      { "name": "Customer", "action": "Add" },
      { "name": "StatusType", "action": "Add", "isDomain": true }
    ],
    "attributes": [
      { "entity": "Customer", "name": "FirstName", "action": "Add", "type": "String", "length": 50 },
      { "entity": "Customer", "name": "Balance", "action": "Add", "type": "Number", "precision": 2, "length": 10 },
      { "entity": "Customer", "name": "Status", "action": "Add", "type": "Domain", "domainEntity": "StatusType" }
    ]
  }
}
```

### MetadataLoadScenario (additional parameters)

```json
{
  "CustomParms": {
    "TimeLimit": "00:05:00",
    "IterationLimit": "15",
    "SleepMinMs": "1",
    "SleepMaxMs": "10",
    "TransformSeed": "12345",
    "MaxRetries": "5",
    "entities": [...],
    "attributes": [...]
  }
}
```

### Entity Definition Fields

| Field      | Required | Description                                       |
|------------|----------|---------------------------------------------------|
| `name`     | Yes      | Entity name. Max 40 characters.                   |
| `action`   | Yes      | `Add` or `Delete`                                 |
| `isDomain` | No       | `true` if this is a domain entity. Default false. |

### Attribute Definition Fields

| Field          | Required | Description                                                |
|----------------|----------|------------------------------------------------------------|
| `entity`       | Yes      | Name of the parent entity                                  |
| `name`         | Yes      | Attribute name                                             |
| `action`       | Yes      | `Add` or `Delete`                                          |
| `type`         | Yes      | `String`, `Number`, `Date`, `DateTime`, `Link`, `Domain`   |
| `length`       | No       | Field length                                               |
| `precision`    | No       | Decimal precision (for `Number` type)                      |
| `domainEntity` | No       | Referenced domain entity (required when `type=Domain`)     |
| `description`  | No       | Human-readable description                                 |

## Domain Entity Handling

Domain entities must be declared in the `entities` array with `"isDomain": true`. Attributes of `type=Domain` reference a domain entity by name via `domainEntity`.

The execution flow guarantees that all domain entities are created before any domain-type attributes are processed. If a referenced domain entity is not present in the `entities` list, validation fails before any API calls are made.

Example: `StatusType` must be created before `Customer.Status` (which has `"domainEntity": "StatusType"`) can be added.

## Idempotency and Collision Handling

### MetadataManagementScenario

- **Entities**: the `action` value is ignored — every listed entity is deleted if it exists, then recreated. This makes entity processing idempotent regardless of `Add`/`Delete`.
- **Attributes** honor the action: `Add` creates the attribute (domain-type attributes delete any existing copy first); `Delete` checks existence before deleting, and a missing attribute (or 404) is treated as success.

### MetadataLoadScenario — Uniqueness Suffixes (OPT-IN)

**Suffixing is OFF by default.** The `UseBaseNamesOnly` CustomParm (MetadataLoadScenario.cs:512-516) defaults to **true** when absent — and stays true for any value other than `"false"`/`"0"`. When true, `MetadataNameTransformer` applies **no suffix**: the raw config entity names are used verbatim across every iteration. This is what you want for management-style runs where the same named entity is deleted-and-recreated each pass.

To enable the load-test uniqueness suffix, set `UseBaseNamesOnly` explicitly to `false` (or `0`). Only then does each iteration generate unique entity names using the format:

```
{BaseName}_{EnvShort}_{ThreadId}_{Seed}_{Iteration}
```

Example: `Customer_CORP_100_12345_001`

The `{Seed}` segment is **hardcoded to `12345`** — `MetadataNameTransformer.GetTransformSeed()` (line 178-181) returns the literal `"12345"` and ignores any configured `TransformSeed`, so changing `TransformSeed` has no effect on generated names.

If a name collision is still detected, a nonce suffix is appended and the operation is retried:

```
Customer_CORP_100_12345_001-r1
Customer_CORP_100_12345_001-r2
```

Name length constraint: entity names must not exceed 40 characters after transformation. Design base names to leave room for the suffix.

Collision retry uses exponential backoff (capped at 10 s per delay). `MaxRetries` (default 1, no upper cap) controls how many times a collision is retried before failing the iteration.

## Iteration Model and Execution Behavior

Applies to `MetadataLoadScenario` only.

### Limits and Guardrails

| Parameter        | Default        | Enforced constraint                                              |
|------------------|----------------|------------------------------------------------------------------|
| `TimeLimit`      | `00:00:00`     | Optional. Zero/unparseable = unlimited (time dimension unbounded) |
| `IterationLimit` | `0`            | Optional. `0` = unlimited (iteration dimension unbounded)         |
| `SleepMinMs`     | `0`            | Optional. No range bounds enforced by the scenario                |
| `SleepMaxMs`     | `0`            | Optional. No range bounds enforced by the scenario                |
| `MaxRetries`     | `1`            | Optional. No upper cap                                            |
| `UseBaseNamesOnly` | effectively `true` | Optional. Absent (or any value except `"false"`/`"0"`) = base config names used verbatim, no suffix. Set `false`/`0` to opt into the load-test uniqueness suffix |
| `TransformSeed`  | (ignored)      | Optional but **no effect** — the `{Seed}` segment is hardcoded to `12345`; see below |
| `entities`       | —              | **Required**: at least 1; names non-empty, unique, ≤ 40 chars     |
| `attributes`     | —              | `entity`/`domainEntity` must reference a declared entity          |

**Both limits zero throws.** If `TimeLimit` is zero **and** `IterationLimit` is 0, `ForEachIterationAsync` throws `InvalidOperationException` (infinite-loop guard) — set at least one. There is no per-test cap on entity/attribute counts.

Execution stops when either `TimeLimit` or `IterationLimit` is reached, whichever comes first.

### Failure Policy

All-or-nothing per iteration: if any entity or attribute operation fails within an iteration, the entire iteration is marked as failed. The scenario continues to the next iteration unless the failure is unrecoverable.

### Concurrent Support

Each concurrent instance uses its thread ID in the name transformation, ensuring globally unique names across simultaneous test runs.

### Usage Examples

```json
// Basic load test
{ "TimeLimit": "00:10:00", "IterationLimit": "100", "SleepMinMs": "100", "SleepMaxMs": "500", "TransformSeed": "12345" }

// High-frequency stress
{ "TimeLimit": "00:01:00", "IterationLimit": "1000", "SleepMinMs": "1", "SleepMaxMs": "1", "TransformSeed": "99999" }

// Long-running time-bounded only
{ "TimeLimit": "02:00:00", "IterationLimit": "0", "SleepMinMs": "1000", "SleepMaxMs": "5000", "TransformSeed": "55555" }
```

## Metrics Collection

### MetadataManagementScenario

Reports start, end, pass/fail, and error information for each entity and attribute operation. Uses existing `MetricBatchSummaryBase` and `MetricDetailBase` types.

### MetadataLoadScenario

| Category          | Description                                    |
|-------------------|------------------------------------------------|
| Iteration Metrics | Per-iteration success and failure counts       |
| Entity Metrics    | Entity creation success/failure rates          |
| Attribute Metrics | Attribute creation success/failure rates       |
| Timing Metrics    | Request/response times and elapsed durations   |
| Collision Metrics | Collision detection counts and retry statistics |

Logging levels: `Information` for iteration progress; `Warning` for collision detection and retries; `Error` for failed operations; `Debug` for name transformation details.

### InstrumentAsync / InstrumentWithResultAsync Helpers

`ScenarioBaseMetadata` (`TestAuto.Metadata\Common\ScenarioBaseMetadata.cs`, ~303–459) provides two protected helpers that wrap any metadata operation in a `GenericMetricDetailBuilder<MetricDetailMetadataApi>` with stopwatch timing. They build and return the metric — persistence happens later via the batch summary (`WithDetailedMetrics`).

```csharp
protected async Task<MetricDetailBase> InstrumentAsync<T>(
    Func<Task<T>> operation, string detailType, string httpMethod, string endpoint,
    bool isCodeLookup, bool filtered, int recordCount, Action<object>? customize = null)

protected async Task<(T result, MetricDetailBase metric)> InstrumentWithResultAsync<T>(
    Func<Task<T>> operation, string detailType, string httpMethod, string endpoint,
    bool isCodeLookup, bool filtered, int recordCount, Action<object>? customize = null)
```

- **Choose by return value**: `InstrumentAsync` discards the operation's result and returns only the metric. `InstrumentWithResultAsync` returns a `(result, metric)` tuple. On failure the tuple's `result` is `default!`.
- **What gets timed**: `_stopWatchTimer.StartAndGetStartTime()` is captured as `StartTime` at the top of the builder chain; the timer stops in `finally`, setting `EndTime`, `ElapsedTime`, and `ResponseTimeMs`. The awaited `operation()` dominates the measurement (the remaining builder `.With` calls and the `customize` callback run inside the window too).
- **Failure recording**: the `catch` **swallows the exception — it is never rethrown**. Failures are recorded as `ResponseCode = RestStatusResultCodes.BadRequest`, `ResponseRecordCount = 0`, `ExecutionStatus = ExecutionStatusFailed`. Success records `ResponseCode = Success`, `ResponseRecordCount = recordCount` (the request count echoed back), `ExecutionStatus = ExecutionStatusComplete`. Check `metric.ExecutionStatus` if you need to react to failures.
- **`customize` callback**: receives the builder as `object` (cast to `GenericMetricDetailBuilder<MetricDetailMetadataApi>` to use it). It is invoked *after* the base fields are populated but *before* the operation runs — so it can add or override request-shape fields, but anything it sets on the outcome/timing fields (`ResponseCode`, `ExecutionStatus`, `EndTime`, etc.) is overwritten by the try/catch/finally.
- **Auto-populated fields**: `DetailType`, `HttpRequestType`, `Endpoint`, `ScenarioName`/`ScenarioId`, `EntityName` (`_targetTable`), `SimulatedUserThreadId`, `AttributeCount`, `PageSize` (BatchSize), `MaxRunningScenarioCount`, `EntityWidth`, `DbaCount`, `IsCodeLookup`, `RequestWasFiltered`, `RequestRecordCount`, `TargetEnvironment(Name)`, `ProfiseeVersion`, `WorkloadExecution`, `HangfireJob`. `InstrumentAsync` additionally sets `SimulatedUserCount`; `InstrumentWithResultAsync` additionally sets `RequestAttributeCount` (`_dbaAttCount + _ffaAttCount`).
- Both log a one-line `Information` summary (method, endpoint, record count, response code, elapsed ms) via `LogTagConstants.ForScenario`.
- The XML doc on `ProcessBatchRecordAsync` (~222) directs overrides to "use cached DetailTypeName when calling InstrumentAsync" — pass `DetailTypeName` as the `detailType` argument.
- **No call sites yet**: as of 2026-06, neither `MetadataManagementScenario` nor `MetadataLoadScenario` calls these helpers — they exist for derived-class `ProcessBatchRecordAsync` overrides. A parallel copy lives in `TestAuto.Matching\Common\ScenarioBaseMatching.cs` (~334/413).

## Troubleshooting

| Symptom                | Fix                                                         |
|------------------------|-------------------------------------------------------------|
| Entity name collisions | Increase `MaxRetries`. (Changing `TransformSeed` has no effect — the `{Seed}` segment is hardcoded to `12345`.) |
| Timeout errors         | Reduce `IterationLimit` or increase `TimeLimit`             |
| Memory issues          | Reduce entity/attribute count or iteration frequency        |
| API rate limit errors  | Increase `SleepMinMs` and `SleepMaxMs`                      |

## Sources

- `TestAuto\Documentation\MetadataManagementScenarioDesign.md`
- `TestAuto.Metadata\Documentation\README.md`
- `TestAuto.Metadata\Common\ScenarioBaseMetadata.cs`
