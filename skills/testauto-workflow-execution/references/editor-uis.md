# WorkflowScenariosEditor and WorkflowExecutionEditor

Reference for the `testauto-workflow-execution` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## WorkflowScenariosEditor — Workflow Editing UI

**Location**: `TestAuto.Web/Components/Pages/WorkflowScenariosEditor.razor(.cs)`

Page for editing scenarios within a workflow template. Distinct from execution — this page manages the `TestAutoWorkflowDetail` records (design time), not `TestAutoWorkflowExecutionDetail` (runtime).

### ScenarioDetailItem ViewModel

In-memory representation of a workflow detail record. Never fetch the record again if `OriginalRecord` is set — use it directly.

```csharp
class ScenarioDetailItem
{
    string Code;                   // TestAutoWorkflowDetail.Code (empty for new)
    int ExecutionOrder;            // display order; RenumberExecutionOrders() keeps this sequential
    string DisplayName;
    string DisplayDescription;
    ScenarioConfiguration Configuration;   // loaded via IScenarioConfigStore.LoadAsync
    string Category;
    string[] Tags;
    Record? OriginalRecord;        // raw Profisee record; null for new unsaved scenarios
    bool IsNew;                    // true until first save; create vs update path
    bool IsDirty;                  // true when local state differs from last saved state
}
```

`IsDirty` is only set for **existing** scenarios (not new ones) — new ones are always considered pending create.

### InMemoryEditorResult — Embedded Editing Pattern

When editing a scenario from `WorkflowScenariosEditor`, open `ScenarioEditorContent` in a Radzen dialog and receive the result back without the editor saving to the database:

```csharp
var result = await DialogService.OpenAsync<ScenarioEditorContent>(
    $"Edit Scenario: {SelectedScenario.DisplayName}",
    new Dictionary<string, object>
    {
        { "InitialConfigurationJson", JsonConvert.SerializeObject(configClone) },
        { "InitialDisplayName", SelectedScenario.DisplayName ?? "" },
        { "InitialCategory", SelectedScenario.Category ?? "" },
        { "InitialTagsCsv", tagsCsv },
        { "ShowHeader", false },
        { "ShowActionBar", true },
        { "EnableNavigationGuard", false },       // no nav guard inside dialog
        { "EnableDraftPersistence", false },       // caller manages state
        { "WorkflowSteps", steps },               // List<WorkflowStepInfo> for context
        { "CurrentStepOrder", SelectedScenario.ExecutionOrder },
        { "OnCancelled", EventCallback.Factory.Create(this, () => DialogService.Close()) }
    },
    new DialogOptions { Width = "92vw", Height = "92vh", Resizable = true, Draggable = true,
                        CloseDialogOnOverlayClick = false, CloseDialogOnEsc = false, ShowClose = true });

if (result is InMemoryEditorResult updated)
{
    SelectedScenario.Configuration = updated.Configuration;
    SelectedScenario.DisplayName = updated.DisplayName ?? SelectedScenario.DisplayName;
    SelectedScenario.Tags = updated.Tags;
    SelectedScenario.IsDirty = true;
    await SaveAllChangesAsync();  // auto-save immediately after edit
}
```

`WorkflowStepInfo` provides context so the embedded editor can show "Step 3 of 8":
```csharp
class WorkflowStepInfo { int ExecutionOrder; string DisplayName; string ScenarioName; }
```

Always pass a **deep clone** of `Configuration` — never the live reference — to avoid mutation before the user saves.

### QuickEdit Bulk-Apply

The QuickEdit panel applies shared field values to all (or selected) scenarios in one operation. Three sections with independent enable/disable flags:

| Section | Fields | Default applied | Gate |
|---|---|---|---|
| 1 — Category & Tags | `Category`, `Tags` | ✅ ON | none |
| 2 — Target Environment | `ProfiseeVersion`, `TargetEnvironment`, `ExecutionMode`, `TargetEnvironmentName`, `TargetApplicationServer`, `TargetDatabaseServer` | ✅ ON | none |
| 3 — Runtime Tuning | `MaxHangfireServers`, `BatchSize`, `RecordsPerBatch`, `TestRecordLimit`, `DqRuleCount`, `MaxHangfireJobs`, `TargetMetricEntity` | ❌ OFF | `RuntimeTuningAcknowledged` checkbox required |

Section 3 applies only after the user explicitly checks the acknowledgment checkbox. When the checkbox is unchecked, all Section 3 apply-flags reset to false.

### Card vs Grid View — delegated to the shared `ScenarioListEditor`

`WorkflowScenariosEditor` does **not** own the card/grid view logic itself. `WorkflowScenariosEditor.razor` hosts the shared `ScenarioListEditor` control and passes it a per-page `ViewStorageKey`:

```razor
<ScenarioListEditor TItem="ScenarioDetailItem"
                    ... 
                    ViewStorageKey="workflow-scenarios-view-mode" />
```

- **View toggle + persistence** live in `ScenarioListEditor.razor.cs` (`SetViewMode(bool grid)` at :98) — writes `grid`/`card` to `localStorage` under the supplied `ViewStorageKey`, and reads it back in `OnAfterRenderAsync(firstRender)` (try/catch for JS unavailability).
- **Card paging state** lives on the pure `ScenarioListState<TItem>` (`Components/Common/ScenarioListState.cs`): `CardPageSize` and `CardCurrentPage` (zero-based) at :48-49, with the paged accessor named **`PagedFiltered`** (NOT `PagedCardItems`) at :51-52 — `Filtered.Skip(CardCurrentPage * CardPageSize).Take(CardPageSize)`.
- Grid view uses a Radzen DataGrid.

So there is no `IsGridView` / `LoadViewPreference` / `PagedCardItems` code-behind on `WorkflowScenariosEditor` — that logic was extracted into the shared control (`ScenarioListEditor` / `ScenarioListState<TItem>`). See [[testauto-ui-patterns]] "Shared list surface".

### Per-Scenario Operations

| Operation | Method | Notes |
|---|---|---|
| Copy | `CopyScenarioAsync` | Deep-clone via JSON serialize/deserialize; appended as new item at end with `(Copy)` suffix |
| Extract | `ExtractScenarioAsync` | Pushes config to `TestAutoScenarios` entity (global library) via `ScenarioService.CreateScenarioAsync` |
| Download | `DownloadScenarioAsJsonAsync` | Uses `ScenarioConfigurationExtractor.WrapAndSerialize` → JS `downloadFileWithSaveAs` |
| Delete | `DeleteScenarioAsync` | Adds to `DeletedScenarioCodes`; executed on save via `restClient.DeleteRecordsAsync` |
| Move up/down | `MoveScenarioUp/Down` | Swap in list → `RenumberExecutionOrders()` → `StateHasChanged()` |
| Move top/bottom | `MoveScenarioToTop/Bottom` | Remove + insert at 0 or end → `RenumberExecutionOrders()` |

`RenumberExecutionOrders()` renumbers 1-based sequentially and marks moved existing scenarios as `IsDirty = true`.

### NormalizeStepType

Maps JSON `type` field values to display labels for the step info panel:

```csharp
string NormalizeStepType(string? type) => type?.ToLowerInvariant() switch
{
    "curl" or "curlstep" or "httprequeststep" or "httprequest" or "http" => "Http",
    "sqlstep" or "sql" => "SQL",
    "powershellstep" or "powershell" or "ps" => "PowerShell",
    "commandlinestep" or "commandline" or "cli" or "cmd" => "CommandLine",
    "clustep" or "clu" => "CLU",
    "connex" or "connexstep" => "ConnEx",
    "monitor" or "monitorstep" => "Monitor",
    _ => type
};
```

### Save Strategy

`SaveAllChangesAsync()` processes three buckets in order:
1. **Delete** — `restClient.DeleteRecordsAsync(DeletedScenarioCodes)` — clears `DeletedScenarioCodes` after success
2. **Create** — bulk `restClient.CreateRecordsWithDetailAsync` for all `IsNew = true` items
3. **Update** — bulk `restClient.UpdateRecordsAsync` for all `IsDirty && !IsNew` items

Validation gate: any scenario with an empty `Configuration.ScenarioName` blocks the save with a user-visible error.

---

## WorkflowExecutionEditor — In-Flight Scenario Editing

**Location**: `TestAuto.Web/Components/Pages/WorkflowExecutionEditor.razor(.cs)`

Runtime counterpart to WorkflowScenariosEditor — edits the `TestAutoWorkflowExecutionDetail` records of an **in-flight execution**, not the template. A step can be edited and resubmitted in **any status except Running** (`IsRunningStatus(status)` = case-insensitive "Running" check). Complete/Failed steps are deliberately editable — that's what enables the edit-then-resubmit loop below.

### Running-Step Protection

| Guard | Where | Effect |
|---|---|---|
| `IsScenarioEditable(scenario)` → `!IsRunningStatus(...)` | per-step | Running steps can't be selected for editing (also drives editable/non-editable counts) |
| `LockedScenarioCodes` | bulk panels | Running steps excluded from the bulk token/matching panels |
| `runningTail` check in `RestartFromSelectedAsync` | resubmit (UI) | Blocks restart if any step at/after the chosen order is Running |
| Re-check inside `ResubmitFromScenarioAsync` | resubmit (service) | Defensive server-side repeat of the Running check in case the UI is stale |

### OpenScenarioEditorDialog — Embedded Full Editor

Two methods, one dialog — there is **no** `NavigateToCustomParmsEditor` (that name is gone; don't
grep for it):

| Member | Where | Role |
|---|---|---|
| `OpenScenarioEditorDialogForItem(ExecutionScenarioDetailItem scenario)` | `WorkflowExecutionEditor.razor.cs:708`, bound as `OnEdit="@OpenScenarioEditorDialogForItem"` (`.razor:386`) | Card/row **"Edit"** entry point. Rejects non-editable (Running) steps with a warning notification, sets `SelectedScenario`, then delegates |
| `OpenScenarioEditorDialog()` | `WorkflowExecutionEditor.razor.cs:905` | Does the actual work for `SelectedScenario` |

The template-side page mirrors this pair: `WorkflowScenariosEditor.razor.cs:1103` /
`:1153` (`OnEdit="@(s => OpenScenarioEditorDialogForItem(s))"`). Other pages use their own
single-arg overloads — `Scenarios.razor.cs:851` `OpenScenarioEditorDialog(type, id)`,
`ConnExResourcePageBase.cs:421` and `EntityModelImport.razor.cs:135`
`OpenScenarioEditorDialog(scenarioCode)`.

`OpenScenarioEditorDialog()` embeds `ScenarioEditorContent` in a Radzen dialog using the same **in-memory mode** as WorkflowScenariosEditor (see InMemoryEditorResult pattern above). Execution scenarios live in WorkloadExecution, not TestAutoScenarios, so the configuration is passed directly rather than loaded by code. Key differences:

- Guards `SelectedScenario.IsNew` — a never-saved scenario must be saved first (warning: "Save the execution first…")
- Passes a **deep clone**: `DeepCloneConfiguration(config)` (Newtonsoft serialize → deserialize round-trip) so dialog edits can't mutate live state before save
- `EnableNavigationGuard = false`, `EnableDraftPersistence = false` — the page owns state
- On `InMemoryEditorResult`: applies `Configuration`, `DisplayName`, `DisplayDescription`, `Category`, `Tags` back to the item, then `MarkSelectedDirty()` → `UpdateJsonEditorsFromModel()` → `StateHasChanged()` → **`await SaveAllChangesAsync()` — the execution editor auto-saves after an in-dialog edit** (added in commit 00241476, "mirrors WorkflowScenariosEditor"; previously the edit lived only in memory and was silently lost unless the user clicked the disabled-until-dirty Save All Changes button)

**Persist-back**: `SaveAllChangesAsync()` re-persists each dirty step's config via `IScenarioConfigStore.PersistAsync` (inline or chunked) and updates its `TestAutoWorkflowExecutionDetail` record (ExecutionOrder, display fields, ScenarioConfiguration, ExecutionStatus, ProfiseeVersion, Category, Tags). `IsDirty` clears on success — a 207 multi-status response counts as success.

### Edit-Before-Resubmit Workflow

The fix-and-rerun loop for a failed (or any non-Running) step:

1. Edit the step's config via the embedded editor → item marked dirty
2. Pick the restart step in the restart-from-step dropdown (`RestartFromOrder`)
3. `RestartFromSelectedAsync` confirms (warns if `ExecutionMachine` ≠ this machine — resettable here, but must be **run** on the target machine), then **auto-saves unsaved edits first** (`HasUnsavedChanges` → `SaveAllChangesAsync`) so the reset steps carry the fixed config
4. Calls `ResubmitFromScenarioAsync(ExecutionCode, fromOrder)` — resets the tail steps and leaves the execution **Pending; it does NOT run it**
5. User runs it from the Executions page (resume path → `ExecuteWorkflowExecutionAsync`)
