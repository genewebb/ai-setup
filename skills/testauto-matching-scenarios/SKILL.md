---
name: testauto-matching-scenarios
description: >
  Matching scenario architecture and 26R1 configuration guide for TestAuto. Use when implementing
  UnifiedMatchingScenario, the 26R1 scenario types (1/2/3A/3B/3C), RecordSource modes,
  RecordMixManager, matching CustomParms, the UnifiedMatchingScenarioEditor wizard, the 3B/3C
  OperationType mismatch against the shipped samples, nested-section vs flat CustomParms configs, the
  LubcRequestAttributes overwrite guard, MatchingResultsScenario,
  UnifiedMatchingPostRunCollectionScenario, or matching metric shapes.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Matching Scenarios (26R1)

> **Scope**: speed-merchants (TestAuto.Matching)
> **Source**: ScenarioGuide_Matching.md, MatchingContext.md, MatchingScenarioDeepDive.md

---

## Reference files (load on demand)

This file carries the scenario matrix, CustomParms, and gotchas. The catalogs and
analysis material live in `references/` and cost nothing until you read one.

| File | Read it when |
|---|---|
| `references/sample-configs.md` | You want copy-paste JSON for 3A / 3B / 3C |
| `references/matching-deep-dive.md` | Interpreting scores, choosing dedup vs match-merge, or tuning performance |
| `references/recordmixmanager.md` | Calling/extending `RecordMixManager`, or the CRUD split is wrong |
| `references/wizard-editor.md` | Editing the wizard or tracing which CustomParm a control writes |
| `references/strategy-branch-topology.md` | A scenario takes an unexpected code path |

---

## 26R1 Scenario Types

| Scenario | Mode | CM State | Record Mix | Duration | Threads | Purpose |
|---|---|---|---|---|---|---|
| **1** | Batch | OFF | 100% New | Until complete | 1 | Initial load from empty model |
| **2** | Operational | ON | 85% Changed, 15% New | Until complete | 1 | Operational batch load (100K) |
| **3A** | Operational | ON | Existing Only | 60 min | 20 | Lookup stress test (no scoring) |
| **3B** | Operational | ON | New Values Only | 60 min | 20 | Lookup scoring test (4 fuzzy attrs) |
| **3C** | Operational | ON | 100% New / `CreatePercent=100` | 60 min | 20 | LUBC user simulation |

> **Critical**: "NoChange" records are NOT used in 26R1 — they don't trigger matching.
>
> **3C mix**: the wizard template sets `NewPercent=100` / `CreatePercent=100` / `UpdatePercent=0`
> (`UnifiedMatchingScenarioEditor.razor.cs:258-262`). The older "85% Create / 15% Update" split is
> what the wizard now applies to **3B** (`razor.cs:237-238`); the 3C *samples* still ship an
> 85/15 Changed/New `Mixed` distribution. See the matrix below.

---

## OperationType × RecordSource Matrix

> ⚠️ **Two live mappings disagree for 3B/3C.** The wizard is the source of truth for new work;
> the shipped sample JSONs lag behind it and are still loaded verbatim. Both tables below are real.
> Do not "fix" one toward the other — this mapping has been flipped in both directions by past audits.

**Wizard mapping** — authoritative. `ApplyScenarioTemplate` in
`TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs:161-281`
(inverse map: `WizardState.InferTemplateFromSettings()`,
`TestAuto.Web/Components/Controls/Models/WizardState.cs:620-641`;
show-flags `ShowScenario3B => IsLookupThenCreate` / `ShowScenario3C => IsCreateOnly` at
`WizardState.cs:261-262`):

| Scenario | OperationType | RecordSource | Mix / flags set by the template |
|---|---|---|---|
| 1 | `BatchLoad` | `NewValuesOnly` | `NewPercent=100`, `ExpectEmptyModel=true`, `WaitForMatching=false` (`razor.cs:166-176`) |
| 2 | `BatchLoad` | `Mixed` | `ChangedPercent=85`, `NewPercent=15`, `ExpectIndexedModel=true` (`razor.cs:189-200`) |
| 3A | `LookupOnly` | `ExistingMatchedOnly` | `WaitForMatching=false`, `ExpectIndexedModel=true`, `MatchStatusFilterText="20, 30, 40, 50"` (`razor.cs:212-222`) |
| 3B | **`LookupThenCreate`** | `NewValuesOnly` | `NewPercent=100`, `CreatePercent=85`, `UpdatePercent=15`, `WaitForMatching=true` (`razor.cs:231-251`) |
| 3C | **`CreateOnly`** | `NewValuesOnly` | `NewPercent=100`, `CreatePercent=100`, `WaitForMatching=false`, `CollectMetricsPostTest=true` (`razor.cs:255-274`) |

The executor's XML doc comments agree with the wizard:
`Services/MatchingOperationExecutor.cs:87` ("Scenario 3a: Lookup only") → `ExecuteLookupOnlyAsync`,
`:136` ("Scenario 3b: Lookup first, create only if no match found") → `ExecuteLookupThenCreateAsync`,
`:221` ("Scenario 3c: Direct create/upsert without lookup") → `ExecuteCreateOnlyAsync`.
`Strategies/ContinuousStrategy.cs:4` likewise documents 3C-Continuous as `CreateOnly` + `WaitForMatching=false`.

**Shipped sample mapping** — `TestAuto.Matching/Samples/TestCases/Small/*.json`, still live because
`MatchingScenarioConfigBuilder.Read<T>` resolves keys out of nested `JObject`s
(`TestAuto.Matching/Helpers/MatchingScenarioConfigBuilder.cs:256-280`):

| Sample file | OperationType | RecordSource |
|---|---|---|
| `UnifiedMatching_Scenario1_InitialLoad_Small.json:27-29` | `BatchLoad` | `Mixed` |
| `UnifiedMatching_Scenario2_OperationalBatch_Small.json:27-29` | `BatchLoad` | `Mixed` |
| `UnifiedMatching_Scenario3A_LookupStress_Small.json:27-29` | `LookupOnly` | `ExistingMatchedOnly` |
| `UnifiedMatching_Scenario3B_LookupScoring_Small.json:27-29` | **`LookupOnly`** | `NewValuesOnly` |
| `UnifiedMatching_Scenario3C_Continuous_Small.json:27-30` | **`LookupThenCreate`** | `Mixed`, `WaitForMatching=false` |
| `UnifiedMatching_Scenario3C_Interactive_Small.json:27-30` | **`LookupThenCreate`** | `Mixed`, `WaitForMatching=true` |

> **Strategy selection is independent of this mapping.** `MatchingStrategyFactory.Create` routes on
> `IsBatchLoadMode` then `!WaitForMatching` only — it never inspects `OperationType` for 3B/3C
> (`TestAuto.Matching/Strategies/MatchingStrategyFactory.cs:23-29`). See
> [[testauto-matching-strategy-pattern]].

---

## The Scenario Editor (Blazor)

- **Entry point**: `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor(.cs)`
- **State model**: `TestAuto.Web/Components/Controls/Models/WizardState.cs`
- **Wizard steps** are determined by `WizardState.GetStepsForTemplate()` on `SelectedScenarioTemplate`

| Template | Steps |
|---|---|
| `Template_Scenario1` (`"Scenario 1: Initial Load"`) | Scenario → Execution Limits → Pacing → Source Systems → Custom Parameters → Review |
| `Template_Scenario2` (`"Scenario 2: Operational Batch"`) | Scenario → Execution Limits → Pacing → Record Mix → Source Systems → Mutation → Custom Parameters → Review |
| `Template_Scenario3A` (`"Scenario 3A: Lookup"`) | Scenario → Execution Limits → Pacing → Matching Strategy → Record Source → Source Systems → [Match Status Filter*] → Lookup Attributes → Custom Parameters → Review |
| `Template_Scenario3B` (`"Scenario 3B: Lookup + Create"`) | Scenario → Execution Limits → Pacing → Matching Strategy → Record Mix → Source Systems → Lookup Attributes → Custom Parameters → Review |
| `Template_Scenario3C` (`"Scenario 3C: Batch Create"`) | Scenario → Execution Limits → Pacing → Record Mix → Source Systems → Custom Parameters → Review |

*Match Status Filter appears only when `Scenario3ARecordSource == "TargetEntity"`.*

**Serialization**: `LoadFromConfiguration()` ↔ `SaveToConfiguration()` round-trips wizard state through `ScenarioConfiguration.ScenarioRuntime.CustomParms` (flat `Dictionary<string, JToken>`). Every step calls `OnStateChanged()` → `SaveToConfiguration()` on change.

---

## Blazor Editor and Wizard State

Entry-point files, the `WizardState.cs` model, template-step mappings, and the exact
Scenario 3A CustomParms the wizard writes:
**`references/wizard-editor.md`**.

Read it when editing the wizard, tracing which CustomParm a wizard control writes, or
reconciling a saved config against what the editor produced. The overwrite guard below
is the one part that bites at runtime, so it stays here.
### LubcRequestAttributes Overwrite Guard

**Bug fixed March 24, 2026** in `SaveToConfiguration`. An unconditional `SetJArray` for `LubcRequestAttributes` at the LUBC Configuration section ran *after* the 3A block had already written the correct checkbox selection — overwriting it on round-trip edits.

The guard is now a **triple** guard covering 3A, 3B, and 3C
(`TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs:727-729`):
```csharp
// LUBC Configuration
// 3A and 3B write LubcRequestAttributes from checkboxes above; don't overwrite with stale LubcRequestAttributesArray
if (!State.ShowScenario3A && !State.ShowScenario3B && !State.ShowScenario3C)
    SetJArray(p, UnifiedMatchingConstants.LubcRequestAttributes, State.LubcRequestAttributesArray);
```
Any new conditional CustomParm write in `SaveToConfiguration` that shares a key with a scenario-specific write must extend the same guard.

**Two blocks write the key ahead of the guard**, not one:

| Block | Location | Writes |
|---|---|---|
| Scenario 3A round-trip metadata (`if (State.ShowScenario3A)`) | `razor.cs:670-697` | `Scenario3ARecordSource`, `SelectedScenario3ASourceCodes`, `SelectedMatchStatusCodes`, `SelectedLookupAttributeCodes`, and — when any attribute is ticked — both `LookupRequestAttributeCodes` and `LubcRequestAttributes`; plus a `HoldoutSourceSystems` percentage map when `RecordSource == NewValuesOnly` |
| Scenario 3B round-trip metadata (`if (State.ShowScenario3B)`) | `razor.cs:699-709` | `SelectedLookupAttributeCodes`, and — when any attribute is ticked — both `LookupRequestAttributeCodes` and `LubcRequestAttributes` |

There is no equivalent 3C write block; `ShowScenario3C` is in the guard purely to stop the stale
`LubcRequestAttributesArray` from being emitted on a 3C config
(`ShowScenario3C => IsCreateOnly`, `WizardState.cs:262`).

### Cache Entities for 3A Wizard Dropdowns

`IReferenceDataCache` loads these at startup to populate 3A wizard checkboxes:

| Entity | Used for |
|---|---|
| `TestAutoMatchingStrategy` | Strategy dropdown in Source Records step |
| `TestAutoMatchingStatus` | Match status checkboxes in Record Pool step (`InUse` only) |
| `TestAutoMatchingStrategyAttributesReference` | Lookup attribute checkboxes in Lookup Attributes step |
| `TestAutoMatchingAttributes` | Attribute details (fallback tier) |

### Architecture Notes

- All scenario config flows through `ScenarioConfiguration.ScenarioRuntime.CustomParms` (flat dict) — the wizard is a structured editor for that dict
- `SetJArray` is a no-op when the JArray is null or empty — explicit guards are required for conditional writes
- All business logic services register in `TestAuto.Web/AutoRegistration/WebModuleRegistrar.cs` — never in `Program.cs`. (The `TestAuto.AutoRegistration` *project* holds only the `IModuleRegistrar` contract and the shared DI plumbing; the concrete registrars live in each feature project's own `AutoRegistration/` folder — `TestAuto.Matching/AutoRegistration/MatchingModuleRegistrar.cs`, `TestAuto.Connect/AutoRegistration/ConnectModuleRegistrar.cs`, etc.)

---

## CustomParms Reference

### Core Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `OperationType` | string | `CreateOnly` | `LookupOnly`, `LookupThenCreate`, `CreateOnly`, `BatchLoad` |
| `ContinuousMatching` | bool | `false` | **Declared but dead** — see below |
| `ExpectEmptyModel` | bool | `false` | Scenario 1 only |
| `ExpectIndexedModel` | bool | `false` | Required for 3A |

> **`ContinuousMatching` is a declared-but-dead parm.** The key constant exists
> (`TestAuto.Matching/Common/MatchingConstants.cs:270`) and the Scenario 1 / Scenario 2 samples set it
> (`UnifiedMatching_Scenario1_InitialLoad_Small.json:30` = `false`,
> `UnifiedMatching_Scenario2_OperationalBatch_Small.json:30` = `true`), but **nothing in
> `TestAuto.Matching` ever reads it** — a repo-wide grep finds the constant declaration and the sample
> writes, and no consumer. Setting it changes nothing at runtime. CM state is a Profisee platform
> setting toggled out-of-band (see *When to Use BatchLoad* below); treat this parm as documentation of
> intent only.

### 26R1 Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `RecordSource` | string | `Mixed` | `ExistingMatchedOnly`, `NewValuesOnly`, `Mixed` |
| `ChangedPercent` | int | `85` | % changed records (Scenario 2) |
| `CreatePercent` | int | `85` | % creates (Scenario 3C) |
| `NewPercent` | int | `15` | % new records |
| `TestDurationMinutes` | int | `60` | Duration for timed scenarios |
| `ConcurrentThreads` | int | `20` | Thread count for timed scenarios |

### Data Source Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `BaseTotalRecords` | int | `30000000` | Base pool size |
| `PreviouslyLoadedRecords` | int | `15000000` | Existing records in Profisee |
| `NewRecordSourceSystem` | string | `10` | Source system for new records |
| `UpdateRecordSourceSystem` | string | `20` | Source system for changed records |

### Lookup Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `MatchingStrategyName` | string | | Profisee matching strategy name (required for 3A/3B/3C) |
| `LubcRequestAttributes` | string[] | | Lookup attribute codes |
| `LubcRequestProcessAllAttributeSets` | bool | `true` | Process all attribute sets |
| `LubcResponseGoldenRecordAttribute` | string | `Golden Record` | Golden record attribute name |
| `MaxGoldenRecordAttempts` | int | `10` | Poll attempts |
| `WaitTimeBetweenGoldenRecordAttemptsMs` | int | `5000` | Poll interval |

### Runtime Parameters

| Parameter | Type | Default | Description |
|---|---|---|---|
| `TimeLimit` | TimeSpan | | Max run time (e.g., `"01:00:00"`) |
| `IterationLimit` | int | `0` | Max iterations (0=unlimited) |
| `SleepMinMs` / `SleepMaxMs` | int | `1` | Delay range between iterations |
| `TransformSeed` | int | `12345` | Random seed |

---

## RecordMixManager — Architecture

The `RecordMixManager` uses **partition-based keyset pagination** for O(1) performance at any scale.

| Feature | Approach |
|---|---|
| Memory | Constant — keyset pagination, not in-memory HashSet |
| Partitioning | Per-instance via `ServerIndex` / `TotalServers` |
| SQL | `WHERE [Code] > @LastCode ORDER BY [Code]` — O(1) at any position |
| Progress | `MatchingRecordProgress` with `PercentComplete`, `EstimatedTimeRemaining` |

**Partition calculation**: Each of N instances gets `totalRecords / N` rows (first `remainder` instances get +1). One-time OFFSET sets the keyset starting point; all subsequent queries are O(1).

### Record Source Modes

| Mode | Use case | Scenario |
|---|---|---|
| `ExistingMatchedOnly` | All records already in Profisee | 3A stress test |
| `NewValuesOnly` | All values require scoring | 3B scoring test |
| `Mixed` | Blend of Changed + New | Scenarios 2 and 3C |

---

## RecordMixManager — Service Contract, CRUD Mix, Integration Tests

The `IRecordMixManager` contract, CRUD mix operation semantics, and the integration-test
patterns that exercise them: **`references/recordmixmanager.md`**.

Read it when calling or extending `RecordMixManager`, or when a record mix produces the
wrong create/update/delete split. The architecture and record-source modes above are
enough to configure a scenario.

---
## ModelSource Record Pool

```
[ModelSource].[dbo].[RetailClient]        ← Original records (SourceSystem = '1', '2', '3')
[ModelSource].[dbo].[RetailClientCloned]  ← Mutated variations of the originals
    ├── SourceSystem = '20' (Dynamics)
    ├── SourceSystem = '30' (JDE)
    └── SourceSystem = '40' (SalesForce)
```

### Source System Reference Data (verified Jan 2026)

**RetailClient** (~50M total):

| Source System | Code | Record Count |
|---|---|---|
| Template Records | `1` | 3,000,000 |
| NPPES | `2` | 6,881,257 |
| Generated Records | `3` | 40,118,743 |
| **Total** | | **~50,000,000** |

**RetailClientCloned** (~150M total):

| Source System | Code | Record Count |
|---|---|---|
| Dynamics | `20` | 50,000,000 |
| JDE | `30` | 50,000,000 |
| SalesForce | `40` | 50,000,000 |
| **Total** | | **~150,000,000** |

Grand total: ~200 million records across both tables.

The `NewRecordSourceSystem` / `UpdateRecordSourceSystem` CustomParms reference these codes (default `"10"` and `"20"`).

---

## Key Constants (`MatchingConstants.cs`)

```csharp
// Record source
RecordSource_ExistingOnly = "ExistingMatchedOnly"
RecordSource_NewOnly      = "NewValuesOnly"
RecordSource_Mixed        = "Mixed"

// Record types
RecordType_New     = "New"
RecordType_Changed = "Changed"   // 26R1
RecordType_Update  = "Update"    // Legacy alias for Changed
RecordType_NoChange = "NoChange" // NOT used in 26R1

// Defaults
Default_TestDurationMinutes  = 60
Default_ConcurrentThreads    = 20
Default_Scenario2_ChangedPercent = 85
Default_Scenario2_BatchSize  = 50000
Default_Scenario2_TotalRecords = 100000
```

---

## Sample Configs

Full JSON for the shipped samples — 3A Lookup Stress, 3B Lookup Scoring, 3C LUBC User
Simulation: **`references/sample-configs.md`**.

Read it when you want a copy-paste starting point rather than assembling CustomParms
from the reference tables above.

---
## Strategy Execution Branch Topology

Which strategy class runs for which scenario type / OperationType / RecordSource
combination, and where each branch diverges:
**`references/strategy-branch-topology.md`**.

Read it when a scenario takes an unexpected code path, or before adding a strategy.

---
## Troubleshooting

| Issue | Cause | Solution |
|---|---|---|
| "No existing codes loaded" | `PreviouslyLoadedRecords` = 0 | Set to expected count |
| "Distribution invalid" | Percentages don't sum to 100 | Ensure Changed + New = 100 |
| "Golden record timeout" | Golden record not assigned | Increase `MaxGoldenRecordAttempts` |
| Scenario 3A lookups slower than expected | Records not pre-indexed | Ensure model is indexed before test |
| Scenario 3B all lookups return matches | Wrong RecordSource mode | Set `RecordSource` = `NewValuesOnly` |
| "RecordSourceMode not recognized" | Invalid mode string | Use exact constant values above |

---

## Key Files

| File | Purpose |
|---|---|
| `TestAuto.Matching/Scenarios/UnifiedMatchingScenario.cs` | Main scenario |
| `TestAuto.Matching/Services/RecordMixManager.cs` | Record mix orchestration |
| `TestAuto.Matching/Services/RecordPoolRepository.cs` | ModelSource DB access |
| `TestAuto.Matching/Common/MatchingConstants.cs` | All constants |
| `TestAuto.Matching/Common/RecordPoolConfiguration.cs` | Distribution config |
| `TestAuto.Matching/Metrics/MetricDetailUnifiedMatching.cs` | Per-record metrics |
| `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs` | UI wizard |
| `TestAuto.Web/Components/Controls/Models/WizardState.cs` | Wizard state |

## Sources

- `TestAuto.Web\Documentation\ScenarioGuide_Matching.md`
- `TestAuto.Matching\Documentation\MatchingContext.md`
- `TestAuto.Matching\Documentation\MatchingScenarioDeepDive.md`
- `TestAuto.Matching\Documentation\SourceSystemsAndTestData.md`
- `TestAuto.Matching\Documentation\StrategyPatternDesign.md`

---

## Deep Dive: Matching Scores and Strategy Design

Score interpretation per scenario, deduplication vs match-merge decision rules, strategy
pattern design and variant selection, and performance-tuning indicators:
**`references/matching-deep-dive.md`**.

Read it when interpreting matching metrics, choosing between dedup and match-merge,
designing a new scenario variant, or diagnosing a slow matching run. This is analysis
material — it is not needed to configure or run a scenario.
