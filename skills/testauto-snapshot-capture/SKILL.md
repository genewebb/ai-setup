---
name: testauto-snapshot-capture
description: >
  MatchingSnapshotCaptureScenario workflow patterns for TestAuto. Use when setting up a
  before/after (Pre/Post) snapshot around a matching run, setting ScenarioStep, supplying the
  target entity via ScenarioTables.TargetEntityName, understanding which match-group counts are
  captured, or reading the UnifiedMatchingApiExecutionMatchGroupResults records the scenario writes.
---

Repo: speed-merchants (paths below are repo-relative)

# MatchingSnapshotCaptureScenario — Workflow Guide

> **Scope**: speed-merchants (TestAuto.Matching)
> **Source of truth**: `TestAuto.Matching/Scenarios/MatchingSnapshotCaptureScenario.cs` +
> `TestAuto.Matching/Samples/TestCases/SnapshotCapture/MatchingSnapshotCapture_Pre_Sample.json` / `_Post_Sample.json`
>
> The repo's `SnapshotCapture/README_WorkflowExample.md` was rewritten to match this (2026-06-07); it had
> previously described an obsolete `CaptureType` / `TargetWorkloadExecutionCode` / `TestAutoMatchingCountersSnapshot`
> design. Code + sample JSON remain the authority if they ever diverge again.

---

## What it does

Each invocation queries the **current match-group count distribution** from the target entity and writes
**one record** to the **`UnifiedMatchingApiExecutionMatchGroupResults`** entity (via the ScenarioMgt REST
client). Run it once **before** and once **after** a matching scenario to capture the delta. The
`ScenarioStep` parm ("Pre"/"Post") labels the capture point.

---

## 3-Step Workflow Pattern

```
Step 1: MatchingSnapshotCaptureScenario (ScenarioStep = "Pre")
  → Writes a Pre match-group-counts record

Step 2: UnifiedMatchingScenario (or any main scenario)
  → Executes matching operations (load, lookup, etc.)

Step 3: MatchingSnapshotCaptureScenario (ScenarioStep = "Post")
  → Writes a Post match-group-counts record
```

All three steps share the same **`WorkloadExecution`** (in `ScenarioEnvironment.WorkloadExecution`). With
the WorkloadExecution Pre-Creation feature this code is generated when the workflow execution is created and
embedded in each step's config automatically; it is stamped onto every result record so Pre and Post can be
correlated.

---

## Required configuration

### Target entity — from `ScenarioTables`, **not** CustomParms

The entity to query comes from **`ScenarioTables.TargetEntityName`** (the scenario's Target Entity),
surfaced by the base `ApplyConfiguration` as `_targetTable` — consistent with `UnifiedMatchingScenario`,
`UnifiedMatchingPostRunCollectionScenario`, and `MatchingResultsScenario`. If it is missing the scenario
throws `ArgumentException: "Scenario configuration is missing required value: ScenarioTables.TargetEntityName"`.

> Older configs put `TargetEntityName` inside `CustomParms`. That value is now **ignored** — set it under
> `ScenarioTables`. (The sample JSON still carries a redundant `CustomParms.TargetEntityName`; it has no effect.)

### Required CustomParms

| Parameter | Description |
|---|---|
| `MatchingScenarioName` | Scenario label written to the result record (`UnifiedMatchingApiExecutionScenarioName`) |
| `MatchingStrategyName` | Strategy code; used for reference/logging (not written as an attribute) |
| `ScenarioStep` | Capture point label — `"Pre"` or `"Post"` (written as `MetricCollectionStep`) |
| `SourceRecords` | Source record count from config (logged; not queried) — must parse as int |

Each missing/blank required parm throws `ArgumentException: "Scenario configuration is missing required value: <key>"`.

### Optional CustomParms

| Parameter | Default | Description |
|---|---|---|
| `MatchStatusColumnName` | `"Match Status"` | Column queried for match-status distribution |
| `MatchStatusEntityName` | `MatchingConstants.Default_MatchStatusEntityName` (sample uses `"MatchStatus"`) | Match-status domain entity |
| `GoldenRecordColumnName` | `"Golden Record"` | Golden-record flag column |
| `UnifiedMatchingScenarioWorkloadExecution` | `""` | Cross-step link to the measured scenario's WorkloadExecution |
| `UnifiedMatchingApiExecutionRunProfile` | `""` | Run-profile label carried onto the result record (constant `MatchingConstants.UnifiedMatchingRunProfile` — same string is the parm key and the persisted attribute name) |

---

## Sample Configuration (Pre)

```json
{
  "Name": "MatchingSnapshotCaptureScenario_Pre_Sample",
  "ScenarioConfiguration": {
    "ScenarioName": "MatchingSnapshotCaptureScenario",
    "ScenarioTables": {
      "SourceEntityName": "RetailClient",
      "TargetEntityName": "RetailClient"
    },
    "ScenarioRuntime": {
      "BatchSize": 1,
      "CustomParms": {
        "MatchingScenarioName": "Scenario2_BatchLoad",
        "MatchingStrategyName": "RetailClientMatching",
        "ScenarioStep": "Pre",
        "SourceRecords": "100000",
        "MatchStatusColumnName": "Match Status",
        "MatchStatusEntityName": "MatchStatus",
        "GoldenRecordColumnName": "Golden Record"
      }
    }
  }
}
```

The **Post** capture is identical except `"ScenarioStep": "Post"` (see `MatchingSnapshotCapture_Post_Sample.json`).
`BatchSize`/`TestRecordLimit` are `1` — the scenario runs as a single-record batch.

---

## Counts captured per record

`MatchingCountersService.GetMatchGroupCountsAsync(targetEntity, matchStatusCol, matchStatusEntity, goldenRecordCol)`
returns a `MatchGroupCounts`, persisted as attributes on the `UnifiedMatchingApiExecutionMatchGroupResults` record:

| Attribute | Meaning |
|---|---|
| `TotalRecords` | Total records in the entity |
| `AutoApprovedRecords` | Auto-approved match status |
| `ProposedRecords` | Proposed match status |
| `UniqueRecords` | Unique match status |
| `GoldenRecords` | Golden records |
| `OtherMatchStatusRecords` | Any other match status |

Reference attributes also written: `WorkloadExecution`, `MetricCollectionStep` (= `ScenarioStep`),
`UnifiedMatchingApiExecutionScenarioName` (= `MatchingScenarioName`), `UnifiedMatchingScenarioWorkloadExecution`,
`UnifiedMatchingApiExecutionRunProfile`. Record `Name` = `{ScenarioStep}_{TargetEntity}_{yyyyMMddHHmmss}` (UTC); `Code` is
left null for Profisee to generate.

---

## Computing the delta

There is no separate snapshot table. To measure impact, compare the **Pre** and **Post** records for the same
`WorkloadExecution` (filter `MetricCollectionStep = "Pre"` vs `"Post"`) and subtract the count attributes
(`TotalRecords`, `AutoApprovedRecords`, `ProposedRecords`, `UniqueRecords`, `GoldenRecords`,
`OtherMatchStatusRecords`). Query the `UnifiedMatchingApiExecutionMatchGroupResults` entity through the normal
Profisee REST/SQL access for that entity.

---

## Execution & error handling

- Runs in `ProcessBatchAsync` as a single-record batch; returns `MetricBatchSummaryNone.Success` when the result
  record is created, and **throws** (fails the step) if the count query or the persist fails.
- `MatchingCountersService` is initialized from the **Matching** connection string
  (`DatabaseConnectionStringHelper.GetConnectionString(cfg, "Matching", ...)`); the schema is
  `MatchingConstants.ProfiseeDataSchemaName`. A missing connection string surfaces as an
  `InvalidOperationException` ("MatchingCountersService not initialized").
- A failed count query throws (the step fails). A failed **persist** also **throws** —
  `CreateMatchGroupResultRecordAsync` raises `InvalidOperationException` (caught and rethrown), which
  propagates through `ProcessBatchAsync`. It does **not** gracefully log a warning and return a Failed
  summary; either the record is written and the step returns `Success`, or an exception fails the step.

---

## Workflow UI setup (TestAuto Web)

1. Add `MatchingSnapshotCaptureScenario` as **Step 1** with `ScenarioStep = "Pre"`.
2. Add your main scenario (e.g. `UnifiedMatchingScenario`) as **Step 2**.
3. Add `MatchingSnapshotCaptureScenario` as **Step 3** with `ScenarioStep = "Post"`.

All steps share the same `WorkloadExecution` (handled by WorkloadExecution Pre-Creation).

---

## Custom Parms Editor

`MatchingSnapshotCaptureScenario` uses `CustomParmsEditorType.MatchingSnapshotCapture`. The editor class is
`TestAuto.Web/Components/Controls/MatchingSnapshotCaptureEditor.razor`.

---

## Sources

- `TestAuto.Matching\Scenarios\MatchingSnapshotCaptureScenario.cs`
- `TestAuto.Matching\Samples\TestCases\SnapshotCapture\MatchingSnapshotCapture_Pre_Sample.json`
- `TestAuto.Matching\Samples\TestCases\SnapshotCapture\MatchingSnapshotCapture_Post_Sample.json`
- `TestAuto.Matching\Common\MatchingConstants.cs` (parm keys + defaults)
- `...\SnapshotCapture\README_WorkflowExample.md` — rewritten 2026-06-07 to match the code + sample JSON (now consistent with this skill)
