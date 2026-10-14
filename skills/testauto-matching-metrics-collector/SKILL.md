---
name: testauto-matching-metrics-collector
description: >
  SQL polling pattern for collecting per-record matching and survivorship timestamps
  in TestAuto. Use when implementing a metrics collector that queries Profisee physical
  tables, understanding the 5-phase polling sequence (create → match cluster → terminal
  state check → golden record → survivorship), handling SqlParameter reuse restrictions,
  converting DateTime/DateTimeOffset from SQL results, or investigating negative / unexpected
  matching-survivorship durations and what PopulateDerivedDurations actually writes.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Matching Metrics Collector

> **Scope**: speed-merchants (TestAuto.Matching)
> **Source**: `TestAuto.Matching/Helpers/MatchingMetricsCollector.cs`

Collects per-record matching and survivorship timestamps by polling Profisee **physical** SQL tables. Returns a `MetricDetailMatching` that callers treat as a **timestamp carrier** — the transaction times are copied onto the persisted `MetricDetailUnifiedMatching`; the `MetricDetailMatching` itself is not persisted.

Current consumers (the collector is constructed via `new MatchingMetricsCollector(sqlHelper, logger)` in `ScenarioBaseMatching`, not resolved from DI):

- `MatchingOperationExecutor` (`Services/MatchingOperationExecutor.cs`) — calls `CollectMetricsAsync` on the interactive create path only (`WaitForMatching` true). BatchLoad mode skips per-record collection entirely; continuous 3c mode stamps the row `Pending` and returns without collecting.
- `UnifiedMatchingPostRunCollectionScenario` (`Scenarios/UnifiedMatchingPostRunCollectionScenario.cs`) — the deferred 3c pass: re-collects timings for each `Pending` row (passing `null!` for the create detail) and updates the row in place to `Collected`/`Failed`.

`PerRecordStrategy` does **not** reference the collector — it builds the `MetricDetailUnifiedMatching` and delegates operation dispatch to `MatchingOperationExecutor`, which invokes the collector.

---

## Physical Table Convention

All queries target the physical data table, not the logical entity:

```csharp
var logicalName = cfg.ScenarioTables.TargetEntityName;
SqlIdentifierValidator.ValidateIdentifier(logicalName, nameof(logicalName));  // must validate before interpolation
var physicalTable = $"data.[t{logicalName}]";
```

Always validate the identifier before string interpolation. Columns use their Profisee display names (with spaces), not SQL-safe aliases: `[Match Cluster]`, `[Golden Record]`, `[Match Status]`.

All record lookups use `[Code]` (the Profisee record code string), **not** `[$UID]` (the internal GUID).

---

## 5-Phase Collection Sequence

```
Phase 1: Build physical table name
Phase 2: Get create transaction time  →  SELECT [$LastChgDTM] WHERE [Code] = @Code
                                          (fallback: responseReceived if null)
Phase 3a: Poll for match cluster     →  poll [Match Cluster] until non-null
           → get [$LastChgDTM]          then SELECT [$LastChgDTM] WHERE [Code] = @Code
Phase 3a-check: Terminal state?      →  [Match Status] set AND [Golden Record] null?
                                          → YES: set golden=match, survive=match, done
Phase 3b: Poll for golden record     →  poll [Golden Record] until non-null (int ID)
           → get [$LastChgDTM]          then SELECT [$LastChgDTM] WHERE [Code] = @Code
Phase 3c: Poll for survive time      →  poll [Golden Record] until non-null (golden ID)
           → get golden record time      then SELECT [$LastChgDTM] WHERE [ID] = @GoldenId
Phase 4:  Populate derived durations  →  detail.PopulateDerivedDurations()
```

**Phase 3b vs Phase 3c**: Both poll `[Golden Record]`, but use the result differently:
- Phase 3b returns `[$LastChgDTM]` of the **source record** (the record created by the test)
- Phase 3c parses `[Golden Record]` as an integer ID, then queries `[$LastChgDTM]` of the **golden record** (a different row, `WHERE [ID] = @GoldenId`)

---

## Terminal State Detection

When the matching engine disposes a record as Unique, Rejected, or similar — it sets `[Match Status]` without creating or assigning a `[Golden Record]`. Polling for a golden record in this state would timeout unnecessarily.

```csharp
// Check performed between Phase 3a and Phase 3b
if ([Match Status] is set) AND ([Golden Record] is null):
    → terminal state — skip golden + survivorship polling
    → set GoldenRecordTransactionTime = MatchTransactionTime
    → set SurviveTransactionTime = MatchTransactionTime
    → call PopulateDerivedDurations() and return
```

This requires **two separate SQL commands** (one for `[Match Status]`, one for `[Golden Record]`) because `SqlParameter` cannot be reused across commands.

---

## SqlParameter Reuse Restriction

`SqlParameter` objects **cannot be reused across separate `ExecuteScalar` calls**. Each call requires a freshly constructed parameter:

```csharp
// WRONG — reusing the same parameter:
var codeParam = new SqlParameter("@Code", SqlDbType.NVarChar) { Value = code };
var first = _sql.ExecuteScalar(sql1, codeParam);
var second = _sql.ExecuteScalar(sql2, codeParam);  // throws or returns wrong result

// CORRECT — new parameter per call:
var codeParam = new SqlParameter("@Code", SqlDbType.NVarChar) { Value = code };
var first = _sql.ExecuteScalar(sql1, codeParam);
var codeParam2 = new SqlParameter("@Code", SqlDbType.NVarChar) { Value = code };
var second = _sql.ExecuteScalar(sql2, codeParam2);
```

This is an ADO.NET limitation — once a `SqlParameter` is consumed by a command it must not be reused. Always allocate a fresh instance for each call.

---

## DateTime / DateTimeOffset Handling

Profisee physical tables can return either `DateTime` or `DateTimeOffset` depending on configuration. Always handle both:

```csharp
var raw = _sql.ExecuteScalar(sql, param);
if (raw is DateTime dt) return dt;
if (raw is DateTimeOffset dto) return dto.UtcDateTime;
return fallback;
```

Use `.UtcDateTime` (not `.DateTime` or `.LocalDateTime`) to strip the offset and get a consistent UTC value.

---

## PollUntilNonNull Pattern

Internal utility used for all polling phases:

```csharp
for (int attempt = 1; attempt <= maxAttempts; attempt++)
{
    var raw = _sql.ExecuteScalar(sqlCheck, checkParams);
    if (raw != null && raw != DBNull.Value)
        return raw;
    await Task.Delay(delayBetweenAttempts);
}
return null;
```

Check for **both** `null` and `DBNull.Value` — SQL NULL comes back as `DBNull.Value`, not C# `null`.

The caller decides what to do on timeout. Current behavior: use the nearest available timestamp as a fallback and call `PopulateDerivedDurations()` before returning.

---

## Derived Durations

After all timestamps are collected, call `detail.PopulateDerivedDurations()`
(`TestAuto.Matching/Metrics/MetricDetailMatching.cs:128-152`). It computes seven `TimeSpan`s and
writes **all 14 fields** unconditionally — there is no guard inside it:

| # | Field | Formula |
|---|---|---|
| 1 | `RecordCreateRequestDuration` | `CreateResponseTime - CreateRequestTime` |
| 2 | `RecordCreateRequestDurationMs` | `(int)` of #1 |
| 3 | `RecordCreateDuration` | `CreateTransactionTime - CreateRequestTime` |
| 4 | `RecordCreateDurationMs` | `(int)` of #3 |
| 5 | `RecordMatchDuration` | `MatchTransactionTime - CreateTransactionTime` |
| 6 | `RecordMatchDurationMs` | `(int)` of #5 |
| 7 | `GoldenRecordCreateDuration` | `GoldenRecordTransactionTime - CreateRequestTime` |
| 8 | `GoldenRecordCreateDurationMs` | `(int)` of #7 |
| 9 | `RecordSurviveDuration` | `SurviveTransactionTime - MatchTransactionTime` |
| 10 | `RecordSurviveDurationMs` | `(int)` of #9 |
| 11 | `RecordProfiseeProcessingDuration` | `SurviveTransactionTime - CreateTransactionTime` |
| 12 | `RecordProfiseeProcessingDurationMs` | `(int)` of #11 |
| 13 | `RecordScenarioCompleteDuration` | `SurviveTransactionTime - CreateRequestTime` |
| 14 | `RecordScenarioCompleteDurationMs` | `(int)` of #13 |

### Durations are raw and deliberately UNCLAMPED — do not "fix" a negative

> [!note] This section previously described a bug. The design changed in 2026-08.
> The old text said the guard promised zeros that `PopulateDerivedDurations()` then overwrote. The
> resolution was not to restore the zeros — it was to **stop promising them**.

`PopulateDerivedDurations()` is now called **unconditionally**, and it is deliberately raw arithmetic:
values are never clamped and negatives are never suppressed (`MetricDetailMatching.cs:130-149`). The
out-of-order-timestamp warning now says *"Durations are reported as computed, not zeroed."*

A negative duration is **meaningful diagnostic output, not a glitch to hide**:

| Field | A negative value means |
|---|---|
| `RecordSurviveDuration` / `RecordProfiseeProcessingDuration` | The incoming record joined a **pre-existing cluster** — the survive timestamp is read off the *golden record's* row, which legitimately predates this record's match |
| `RecordCreateDuration` | Client-vs-DB **clock skew**, or a UTC/Unspecified `DateTimeKind` mismatch between the caller value and the SQL value |

Clamping would report a plausible-looking zero for a record whose timestamps are genuinely inconsistent —
a worse lie than the negative.

`MetricDetailMatching.ValidateDurations()` (`:188`) now **returns** `IReadOnlyList<string>` (empty = healthy)
and flags **both** zero ("never collected") and negative ("timestamps out of order", `:208`) values. The
collector logs that list and does **not** mutate the detail.

**Do not add a clamp.** These durations are diagnostic only: both callers copy just the four transaction
timestamps, and the persisted durations are recomputed downstream by
`MetricDetailUnifiedMatching.PopulateDerivedDurations`.

---

## DI Registration Note

`MatchingMetricsCollector` has a no-arg constructor alongside its real `(SqlHelper, ILogger)` constructor. The no-arg constructor exists solely so the DI container can construct an instance when the `SqlHelper` dependency is not registered (e.g., in unit test contexts without a database). Do not remove it.

---

## Sources

- `TestAuto.Matching\Helpers\MatchingMetricsCollector.cs`
- `TestAuto.Matching\Interfaces\IMatchingMetricsCollector.cs`
- `TestAuto.Matching\Services\MatchingOperationExecutor.cs` (interactive consumer)
- `TestAuto.Matching\Scenarios\UnifiedMatchingPostRunCollectionScenario.cs` (deferred 3c consumer)
