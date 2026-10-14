# UnifiedMatchingScenarioEditor — Entry Points, Wizard State, Template Mappings

Reference for the `testauto-matching-scenarios` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Blazor Editor Entry Points and Wizard State

### Entry Point Files

| File | Role |
|---|---|
| `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor` | Wizard markup and step rendering |
| `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs` | `SaveToConfiguration`, `LoadFromConfiguration`, step management; contains `UnifiedMatchingConstants` as an inner static class at the bottom |
| `TestAuto.Web/Components/Controls/Models/WizardState.cs` | All wizard state fields; `GetStepsForTemplate()`; computed properties including `ShowScenario3A` |
| `TestAuto.Web/Components/Controls/WizardSteps/` | One `.razor` + `.razor.cs` per step |

**Constants split**: `UnifiedMatchingConstants` (editor-side, inside `.razor.cs`) holds UI constant strings. `TestAuto.Matching/Common/MatchingConstants.cs` holds runtime constant strings. When adding a new CustomParm key, decide which layer owns it — runtime consumption belongs in `MatchingConstants.cs`.

### Wizard State Model (`WizardState.cs`)

All wizard UI state is held in `WizardState`. The two key methods that bridge UI ↔ config are:

- `LoadFromConfiguration()` — reads `ScenarioConfiguration.ScenarioRuntime.CustomParms` into `WizardState` fields
- `SaveToConfiguration()` — writes `WizardState` fields back to `CustomParms` as a flat `Dictionary<string, JToken>`

Every wizard step calls `OnStateChanged()` → `SaveToConfiguration()` on any value change. The config is always in sync with the UI state — there is no deferred save.

Key computed property:
```csharp
// WizardState.cs
public bool ShowScenario3A => IsLookupOnly;
```
`ShowScenario3A` gates all 3A-specific logic in both `SaveToConfiguration` and `LoadFromConfiguration`. Always use this property rather than duplicating the condition.

### Template-Step Mappings

`WizardState.GetStepsForTemplate()` switches on `SelectedScenarioTemplate`:

| Template constant | Steps in order (step id) |
|---|---|
| `Template_Scenario1` | scenario-selection → execution-limits → concurrency-pacing → source-systems → custom-parms → review |
| `Template_Scenario2` | scenario-selection → execution-limits → concurrency-pacing → record-mix → source-systems → mutation-level → custom-parms → review |
| `Template_Scenario3A` | scenario-selection → execution-limits → concurrency-pacing → source-records → record-source → source-systems → [record-pool*] → lookup-attributes → custom-parms → review |
| `Template_Scenario3B` | scenario-selection → execution-limits → concurrency-pacing → source-records → record-mix → source-systems → lookup-attributes → custom-parms → review |
| `Template_Scenario3C` | scenario-selection → execution-limits → concurrency-pacing → record-mix → source-systems → custom-parms → review |

`Template_Scenario3A` is built dynamically by `Get3ASteps()`; the `record-pool` ("Match Status Filter") step is inserted only when `Scenario3ARecordSource == "TargetEntity"`. There is a single `Template_Scenario3C` — the Interactive/Continuous split exists only in sample-config file names, not as separate template constants or wizard steps.

### Scenario 3A CustomParms Written by the Wizard

| Key | Written by | Notes |
|---|---|---|
| `OperationType` = `LookupOnly` | `SaveToConfiguration` | Fixed for 3A |
| `RecordSource` = `ExistingMatchedOnly` | `SaveToConfiguration` | Fixed for 3A |
| `ExpectIndexedModel` = `true` | `SaveToConfiguration` | Fixed for 3A |
| `MatchingStrategyName` | Source Records step | Required — must match Profisee strategy name |
| `LubcRequestAttributes` | Lookup Attributes step checkboxes | See overwrite guard below |
| `MatchStatusFilter` | Record Pool step checkboxes (int[] JArray) | Default `[20,30,40,50]` if missing |
| `TimeLimit` | Timing step | |
| `MatchStatusColumnName` | Source Records step | |
| `MatchClusterColumnName` | Source Records step | |
| `GoldenRecordColumnName` | Source Records step | |

**Editor-only round-trip keys** (not consumed at runtime):

| Key | Purpose |
|---|---|
| `SelectedScenario3ASourceCodes` | Which source checkboxes are ticked in Record Pool step |
| `SelectedMatchStatusCodes` | Which match status checkboxes are ticked |
| `SelectedLookupAttributeCodes` | Which attribute checkboxes are ticked |
| `Scenario3ARecordSource` | Live UI selector value (`WizardState.cs`); values `"TargetEntity"` / `"ModelSource"`, default `"TargetEntity"` |

> `RecordPoolSource` is legacy/backward-compat load-only (never `"MatchedRecords"`); the live selector is `Scenario3ARecordSource`.
