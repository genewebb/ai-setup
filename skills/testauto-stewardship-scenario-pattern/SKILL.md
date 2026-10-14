---
name: testauto-stewardship-scenario-pattern
description: >
  StewardshipFilterScenario design: weighted-probability CRUD loop, page-minus-selected delete pick,
  the dual-zero TimeLimit/IterationLimit throw, verify-after-mutate GET, ScenarioDataShape
  attribute-width control, and CustomParms. Use when creating or modifying stewardship-style
  scenarios, tuning CRUD ratios, how the DBA filter record is generated, configuring stewardship
  scenario JSON, or debugging iteration-level metric recording in CRUD-mix scenarios.
---

Repo: speed-merchants (paths below are repo-relative)

# StewardshipFilterScenario Pattern

`StewardshipFilterScenario` simulates realistic DBA/stewardship workloads by
mixing creates, updates, and deletes on a per-iteration probabilistic basis
rather than running uniform batches. This models human stewardship patterns
where any given session may create new records, update existing ones, or delete
stale entries, with each operation type occurring at a configured frequency.

---

## What It Simulates

Unlike pure throughput scenarios that hammer a single operation repeatedly,
`StewardshipFilterScenario`:

- Works within a filter scoped to a single domain attribute value (set at
  initialization by `StewardshipFilterRecords`).
- Per iteration, navigates to a random page of matching records and selects one
  record by code.
- Rolls a weighted die each iteration to decide whether to **create**, **update**,
  or **delete** a record — or do nothing if all weights are zero or disabled.
- Issues a verification GET after every mutating operation.
- Includes configurable sleep intervals between steps to model real user pacing.

---

## StewardshipFilterRecords — Initialization

`StewardshipFilterRecords` (the `TestDataType`) generates exactly one `Record`
whose `ScenarioData` attribute holds a filter string. The filter is built from a
randomly chosen domain attribute and one of its cached values:

```csharp
// Seeded RNG so the filter is deterministic across runs
var rnd = new Random(12345);
var attributeName = allAttributes.Keys.OrderBy(_ => rnd.Next()).First();
var attributeValue = values[rnd.Next(values.Count)];
string filter = $"[{attributeName}] eq '{attributeValue}'";
```

This single record is cached and returned by `GetRecords(pageNumber, pageSize)`.
The scenario uses `filter` as its query scope; all paged GETs in the main loop
operate within that filtered result set.

---

## Weighted Probability-Roll CRUD Loop

Each iteration performs exactly one mutating operation (or none if all
probabilities are disabled). The selection uses a 1–100 dice roll against
cumulative percentage thresholds:

```csharp
int newPct = _createNewRecords ? _newRecordPercent : 0;
int updPct = _updateExistingRecords ? _updateRecordPercent : 0;
int delPct = _deleteRecords ? _deleteRecordPercent : 0;
int totalPct = newPct + updPct + delPct;

if (totalPct > 0)
{
    int roll = rnd.Next(1, 101);
    if      (roll <= newPct)                  // CREATE branch
    else if (roll <= newPct + updPct)         // UPDATE branch
    else if (roll <= newPct + updPct + delPct) // DELETE branch
}
```

The percentages are **not required to sum to 100**. If `totalPct < 100`, some
iterations perform no mutation (only GETs). If `totalPct == 0` or all flags are
false, the iteration is read-only.

---

## Iteration Steps in Order

1. **Random page GET** (`GETPAGE`) — computes max pages from
   `UpdateRecordsAvailable / BatchSize`, picks a random page, fetches it.
2. **Guard: empty page** — if no records returned, logs and continues to next
   iteration.
3. **Optional sleep** (`SleepMinMs`–`SleepMaxMs` ms).
4. **Single-record GET by code** (`GET`) — picks a random record from the page,
   stores its code in `_selectedRecordCode`, adds to `_usedRecordCodes`.
5. **Optional sleep**.
6. **Weighted CRUD roll** — executes exactly one of:
   - **CREATE**: `POST` a clone of the selected record with code suffix `_New`,
     then verify with `GET` by new code.
   - **UPDATE**: `PATCH` the selected record with a timestamped name, then
     verify with `GET` by code.
   - **DELETE**: picks a random record from the same page whose `Code` differs
     from `_selectedRecordCode` (page minus selected — *not* a `_usedRecordCodes`
     lookup), issues `DELETE`, then verify with `GET` by code (expected
     `NotFound`). No candidate on the page → the branch is a silent no-op.
7. **Optional sleep**.
8. **Final verification GET** (`GET`) — re-fetches `_selectedRecordCode` to
   confirm it is still accessible after the iteration's operations.

---

## `_usedRecordCodes` Is Bookkeeping Only — the Delete Pick Is "Page Minus Selected"

`_usedRecordCodes` is a `List<string>` cleared at the start of each iteration
(`StewardshipFilterScenario.cs:296`). Every code touched in the iteration is
appended to it (`:303`, `:345-346`, `:378-379`, `:426-427`) — but **nothing ever
reads it as a filter**. The only membership test is the guard that keeps the list
free of duplicates.

The delete branch picks its candidate purely by excluding the *currently selected*
record from the current page:

```csharp
// StewardshipFilterScenario.cs:422-427
var deleteCandidates = recs.Where(r => r.Code != _selectedRecordCode).ToList();
if (deleteCandidates.Any())
{
    var deleteRecord = deleteCandidates[rnd.Next(deleteCandidates.Count)];
    // ...then, separately, bookkeeping only:
    if (!_usedRecordCodes.Contains(deleteRecord.Code))
        _usedRecordCodes.Add(deleteRecord.Code);
```

So the guarantee is narrow: the delete target differs from the one record GET-ed
this iteration. It does **not** exclude records touched by earlier operations, and
because the list is re-cleared every iteration there is no cross-iteration
protection either. Do not rely on `_usedRecordCodes` for concurrency safety across
parallel batch jobs — nothing in the scenario enforces it.

If the page yields no candidate (only the selected record present), the delete
branch does nothing at all: no DELETE, no verify GET, no failure recorded.

---

## Verify-After-Mutate GET Pattern

After every `POST`, `PATCH`, or `DELETE`, the scenario issues a single-record
GET to confirm the operation landed:

- **After POST**: GET by `{originalCode}_New` — expects `200 OK`.
- **After PATCH**: GET by the updated code — expects `200 OK` with modified
  name.
- **After DELETE**: GET by deleted code — expects `404 Not Found` (recorded as
  success if the scenario treats 404 as expected; check metric `ResponseCode`).

All verify GETs are recorded as `MetricDetailRecordApi` entries with
`isCodeLookup: true` and appended to the iteration's `details` list alongside
the primary operation metric.

---

## ScenarioDataShape / Attribute-Width Control

`_selectAttributes` is resolved by `ScenarioBaseCrud.ApplyConfiguration` using
a three-level precedence:

| Priority | Source | Behavior |
|---|---|---|
| 1 | `ScenarioQuery.SelectAttributes` (comma-separated string) | Used verbatim |
| 2 | `ScenarioDataShape.FreeformAttributes` and/or `DomainAttributes` > 0 | `MetadataConstants.GetPDataByWidth(ffa, dba)` |
| 3 | Neither set | Full width: `MetadataConstants.PDATAAttributeNames()` |

`BuildCreateRecordFromSource` and `BuildUpdateRecordFromSource` copy only
attributes present in `_selectAttributes` (excluding `Code` and `Name` which
are always set explicitly). Setting `FreeformAttributes: 2, DomainAttributes: 1`
limits the payload to 2 freeform + 1 domain attribute per operation, reducing
API payload size without changing the operation count.

---

## Configuration Parameters (CustomParms)

All keys are defined in `SharedConstants` and registered via `[CustomParm]`
on `RecordsCustomParms`.

| Key | Type | Description |
|---|---|---|
| `CreateNewRecords` | bool | Enable the create branch. |
| `NewRecordPercent` | int | % chance (1–100) of a create being selected per iteration. |
| `UpdateExistingRecords` | bool | Enable the update branch. |
| `UpdateRecordPercent` | int | % chance of an update being selected per iteration. |
| `DeleteRecords` | bool | Enable the delete branch. |
| `DeleteRecordPercent` | int | % chance of a delete being selected per iteration. |
| `NumberOfRandomReads` | int | Reserved; read but not currently used by the main loop logic. |
| `LowBatchSize` | int | Reserved; carried over from generator but not used in the loop. |
| `HighBatchSize` | int | Reserved; carried over from generator but not used in the loop. |
| `TimeLimit` | TimeSpan string | Maximum wall-clock duration (e.g. `"05:00:01"`). `"00:00:00"` = unbounded on the time dimension. |
| `IterationLimit` | int | Maximum number of iterations. `0` = unbounded on the iteration dimension. |
| `SleepMinMs` | int | Minimum random sleep between steps (ms). |
| `SleepMaxMs` | int | Maximum random sleep between steps (ms). |
| `UpdateRecordsAvailable` | int | Total records available in the target entity; used to compute max random page number. |

Both `TimeLimit` and `IterationLimit` can be set simultaneously — the loop
exits when **either** limit is hit.

> **Both zero throws — it does not run forever.** The scenario does not own its
> `while`; it hands `(_timeLimit, _iterationLimit)` to the shared
> `ScenarioBase.ForEachIterationAsync` primitive
> (`StewardshipFilterScenario.cs:267`). That helper's first statement is an
> infinite-loop guard: when `timeLimit == TimeSpan.Zero && iterationLimit == 0`
> it throws
> `InvalidOperationException("Both IterationLimit and TimeLimit are zero. At least one must be set to a positive value to prevent an infinite loop.")`
> before the first iteration (`ScenarioBase.cs:158-163`). `ProcessBatchAsync`
> therefore fails fast and produces no batch summary. Always give at least one
> dimension a positive value. (Same guard documented in
> [[testauto-scenario-catalog]].)

---

## Example Scenario Config JSON

```json
{
  "Name": "StewardshipFilterScenario_v1",
  "ScenarioConfiguration": {
    "ScenarioName": "StewardshipFilterScenario",
    "MaxRunningScenarioCount": 1,
    "ScenarioTables": {
      "SourceEntityName": "PDATA",
      "TargetEntityName": "TDATA"
    },
    "ScenarioDataShape": {
      "FreeformAttributes": 0,
      "DomainAttributes": 0
    },
    "ScenarioRuntime": {
      "RecordsPerBatch": 1,
      "BatchSize": 50,
      "PageNumber": 0,
      "MaxBatchConcurrency": 1,
      "CustomParms": {
        "TimeLimit": "05:00:01",
        "IterationLimit": "50",
        "SleepMinMs": "500",
        "SleepMaxMs": "10000",
        "CreateNewRecords": "true",
        "NewRecordPercent": "20",
        "UpdateExistingRecords": "true",
        "UpdateRecordPercent": "50",
        "DeleteRecords": "true",
        "DeleteRecordPercent": "10",
        "NumberOfRandomReads": "3",
        "LowBatchSize": "10",
        "HighBatchSize": "50",
        "UpdateRecordsAvailable": "5000"
      }
    },
    "ScenarioTesting": {
      "TestRecordLimit": 100,
      "TestOverrideQueueName": "Not Used"
    },
    "ScenarioQuery": {
      "SelectAttributes": "Code, Name",
      "SortAttributes": "Code",
      "Filter": "",
      "QueryParameters": {
        "CountsOnly": "false",
        "ExcludeValidationStatusDetermination": "false"
      }
    },
    "ScenarioRestTarget": {
      "RestUrlBase": "https://yourhost.corp.profisee.com/profisee/rest/",
      "RestApiKey": "your-api-key-here"
    },
    "ScenarioEnvironment": {
      "DqRuleCount": 0,
      "TargetEnvironment": "On Premise",
      "TargetEnvironmentName": "PFTEST",
      "ProfiseeVersion": "25R1",
      "HangfireJob": 0
    }
  }
}
```

With the above config: each iteration rolls 1–100; rolls 1–20 create, 21–70
update, 71–80 delete, 81–100 no mutation. The scenario runs for up to 5 hours
or 50 iterations, whichever comes first, with 500–10,000 ms sleep between
steps.

---

## Sources

- `TestAuto.Records\Scenarios\Stewardship\StewardshipFilterScenario.cs`
- `TestAuto.Records\DataRecordGenerators\StewardshipFilterRecords.cs`
- `TestAuto.Records\Documentation\StewardshipFilterScenario.md`
- `TestAuto.Records\Common\ScenarioBaseCrud.cs`
- `TestAuto.Scenarios\Common\ScenarioBase.cs` (`ForEachIterationAsync` + dual-zero guard, lines 153-214)
- `TestAuto.Shared\Common\SharedConstants.cs`
- `TestAuto.Records\Configuration\RecordsCustomParms.cs`
- `TestAuto.Scenarios\Samples\TestCases\FullConfiguration\Stewardship\StewardshipFilterScenario_SampleConfig.json`
