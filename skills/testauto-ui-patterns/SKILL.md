---
name: testauto-ui-patterns
description: >
  UI layout, dialog sizing, editor caching, and navigation conventions for TestAuto Blazor pages. Use
  when building list or editor pages, search/filter UX, modal dialogs, returning results from an
  editor dialog (*Result/Saved convention), custom-parms editor popup vs inline, Radzen chart series
  binding, scenario list filtering/paging/view-mode persistence, refreshing a polled RadzenDataGrid,
  or [PersistentState] across circuit drops.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto UI Patterns

> **Scope**: speed-merchants (TestAuto.Web — Blazor Web App, Interactive Server render mode + Radzen)
> **Source**: AGENTS.md (Learned Workspace Facts + Preferences) — *source removed 2026-05-31; content migrated to work-ai, this skill is now canonical*

---

## Polled Grids and Persistent View State

Pattern from the 2026-07 RadzenDataGrid conversions (`ExecutionMonitoring.razor(.cs)`, `ExecutionHistory.razor(.cs)`; `ExecutionDashboard.razor` was the original exemplar):

- **A replaced collection needs an explicit reload.** A `RadzenDataGrid` does not re-render just because the backing collection is replaced. Capture the grid with `@ref` and call `await grid.Reload()` after the data collections are reassigned.
- **Only one of these two pages actually polls.** Don't assume a `PeriodicTimer` on every grid page — check before you copy the pattern:
  - `ExecutionMonitoring.razor.cs` **is** timer-polled. `OnInitializedAsync` creates a `PeriodicTimer` from `PollingIntervalSeconds` (default 90) plus a `CancellationTokenSource`, then fires `RefreshLoopAsync` on a background `Task.Run` (`ExecutionMonitoring.razor.cs:130-134`). Each tick wraps everything in one `await InvokeAsync(async () => { … })` that refreshes data, calls `_activeGrid.Reload()` / `_historyGrid.Reload()`, then `StateHasChanged()` (`ExecutionMonitoring.razor.cs:150-166`). That `InvokeAsync` marshalling is mandatory — the loop runs off the renderer's sync context.
  - `ExecutionHistory.razor.cs` has **no timer at all** — no `PeriodicTimer`, no `System.Threading.Timer`, no `IDisposable`. It refreshes only on user action: `OnInitializedAsync` → `LoadHistory()`, and thereafter the scenario-name box, the Status/TimeRange selects, and an explicit Refresh button all re-invoke `LoadHistory()` (`ExecutionHistory.razor:21,24,33,41`). `LoadHistory()` ends with the same `_historyGrid.Reload()` call (`ExecutionHistory.razor.cs:90-93`), which is why the reload rule still applies — the trigger is a user event, not a tick.
- **Don't double-paginate.** Pages that already do server-side paging with their own page-size dropdown + prev/next controls (ExecutionMonitoring) keep grid `AllowPaging` **off** — grid paging would paginate a single server page. Pages that load the full list have **two** options: client grid paging (`AllowPaging=true`, e.g. ExecutionHistory), or the house **`<PagingControl>`** external pager with `AllowPaging="false"` — used by `Scenarios`, `ScenarioTemplates`, `Workflows`, `WorkflowBuilder`, `ScenarioListEditor` and `ProductionSync` (6 call sites). Prefer `PagingControl` for consistency with the list-page family.

> [!warning] With `PagingControl`, grid-native sorting is not enough
> `RadzenDataGrid` only sorts **the data it was handed** — i.e. the current window. Clicking a column header
> therefore sorts within the page and looks broken. Handle `LoadData`, capture `args.Sorts`, sort the **full
> backing list**, and only then `Skip`/`Take` the window (`ProductionSync.razor.cs:144-200`).
- **Row highlighting via `RowRender`** — set `args.Attributes["class"]` only when the class is non-empty so Radzen's own `rz-data-row` classes are preserved on normal rows.
- **Template columns → `AllowSorting=false`.** Columns rendered from `Record.SafeGetValue` helpers have no `Property` to sort on.
- **`[PersistentState]` for user view state.** Filters, page sizes, and current-page properties (public) survive circuit drop/resume — the runtime rehydrates them **before** `OnInitialized*`. Use a 0-sentinel so a fresh (non-resumed) load still applies the configured default, and never persist the polled data collections themselves (they re-fetch).

---

## Dialog Sizing Standard

All scenario-editing dialogs use:

```csharp
// ScenarioCustomParmsDialog and scenario editor dialogs
var options = new DialogOptions
{
    Width = "92vw",
    Height = "92vh",
    Resizable = true,
    Draggable = true,
    CloseDialogOnOverlayClick = false
};
```

**Never hardcode pixel sizes.** The 92vw × 92vh standard fills the screen without clipping on common resolutions.

---

## Editor Rendering: Popup, Never Inline

The `CustomParmsEditorHost` is the canonical shared component. The "Custom Parms" `ConfigurationSection` shows a **count summary + "Edit Custom Parms" button**. Clicking opens `ScenarioCustomParmsDialog` full-screen.

**Rule**: Never render the custom parms editor inline inside a `ConfigurationSection`. It must always open in a dialog.

All scenario editing paths (standalone `ScenarioEditor`, workflow editor, execution editor) use the **same** `CustomParmsEditorHost` component — no divergent editor rendering paths.

### ScenarioEditorContent embedding

When `ScenarioEditorContent` is embedded in a Radzen dialog (non-full-screen context):

```razor
<ScenarioEditorContent ShowHeader="false"
                       ShowActionBar="true"
                       EnableNavigationGuard="false"
                       EnableDraftPersistence="false" />
```

---

## Scenario/Workflow List UIs

For workflow or scenario list pages:

- Available scenarios go in a **dropdown** with filter-by-name and filter-by-tags
- Selected scenarios appear in a **separate ordered list**
- **Filter state must be remembered** across interactions (do not reset on selection change)

### Shared list surface — `ScenarioListEditor<TItem>`

The scenario **list/grid surface** (Category/Scenario/Tags filter bar, card + grid views, view toggle, collapse-all, card paging, selection) is a single shared component: `TestAuto.Web/Components/Controls/ScenarioListEditor.razor`, generic over `IScenarioListItem`. Both `WorkflowScenariosEditor` (Edit Workflow Scenarios) and `WorkflowExecutionEditor` (Manage execution edit) host it.

**Rule: do NOT re-implement the scenario list/filter/grid on a page.** Host the component and configure it:
- capability flags `CanPlay/CanCopy/CanEdit/CanDelete/CanReorder/CanExtract/CanDownload` (execution editor locks play/copy/delete/reorder/extract to `false`),
- `StatusSelector`/`StatusBadgeStyleSelector` (execution supplies `ExecutionStatus`; scenarios passes nothing → no Status column),
- `CanEditItem` per-item predicate (execution = `IsScenarioEditable`),
- `IsNewSelector`/`IsDirtySelector`/`ColorIndexSelector`, optional `GridMetricsTemplate` (host renders metric badges via its own helpers),
- `SelectedCodes` + `SelectedCodesChanged` (host owns the selection set for bulk-apply), `ShowSelection`, a per-page `ViewStorageKey`, and `EventCallback<TItem>` actions (`OnEdit`, `OnDownload`, …).

Pure list logic (filter/facets/paging/selection) lives in `ScenarioListState<TItem>` (`Components/Common`), unit-tested in `ScenarioListStateTests`. The **bulk-edit** half stays on each page (`BulkCustomParmsEditorBase`, Quick Edit + `StepTokenBulkEditPanel`/`MatchingBulkEditPanel`).

#### `ScenarioListState<TItem>` — state-machine rules

| Concern | Behavior |
|---|---|
| Filter pipeline | Three independent filters (Category, ScenarioName, Tags) applied in `Filtered` as a chained LINQ query; all comparisons are `StringComparison.OrdinalIgnoreCase` |
| Facet derivation | `DistinctCategories`, `DistinctScenarioNames`, `DistinctTags` — each distinct + case-insensitive + sorted ascending; sourced from live `Items` (not the filtered set) |
| Page reset on filter | `ScenarioListEditor.OnFilterChanged()` sets `_state.CardCurrentPage = 0` immediately after applying any filter-dropdown `ValueChanged` callback — not via `@bind-Value:after` (that pattern is only used for `StateHasChanged` on switches) |
| Page clamping | `ClampPage()` clamps `CardCurrentPage` to `[0, CardTotalPages-1]`; also called by `OnCardGoToPage` |
| View-mode persistence | Read from `localStorage` in `OnAfterRenderAsync(firstRender)` only (try/catch for JS unavailability — e.g. pre-render); written to `localStorage` on every `SetViewMode()` call |
| Selection ownership | `SelectedCodes` is a `HashSet<string>` parameter owned by the **host**. `ScenarioListEditor.OnParametersSet` does `_state.SelectedCodes = SelectedCodes ?? new(StringComparer.OrdinalIgnoreCase)` — it adopts the host's set **by reference, comparer and all**. See the comparer trap below before assuming case-insensitivity. |

##### Comparer trap — `SelectedCodes` is case-**sensitive** in practice

Easy to get wrong, because two different defaults disagree and the host's wins:

| Site | Comparer |
|---|---|
| `ScenarioListState.SelectedCodes` field initializer (`Components/Common/ScenarioListState.cs:54`) | `StringComparer.OrdinalIgnoreCase` |
| `ScenarioListEditor.SelectedCodes` `[Parameter]` initializer (`Components/Controls/ScenarioListEditor.razor.cs:16`) | plain `new()` → **ordinal, case-sensitive** |
| `ScenarioListEditor.OnParametersSet` null-fallback (`ScenarioListEditor.razor.cs:83`) | `StringComparer.OrdinalIgnoreCase` — but only reached when the host passes `null` |
| `WorkflowScenariosEditor.SelectedScenarioCodes` (`Components/Pages/WorkflowScenariosEditor.razor.cs:112`) | plain `new()` → **case-sensitive** |
| `WorkflowExecutionEditor.SelectedScenarioCodes` (`Components/Pages/WorkflowExecutionEditor.razor.cs:115`) | plain `new()` → **case-sensitive** |

`OnParametersSet` **overwrites** the state's case-insensitive default with the host's set, so `ScenarioListState.cs:54` is dead in every real hosting path — both live hosts supply a case-sensitive set, and `IsSelected` / `ToggleOne` / `SelectAllFiltered` therefore compare codes **case-sensitively**. Today that is harmless (codes round-trip with identical casing), but it contradicts the case-insensitive filter/facet pipeline in the rows above.

**Rule**: a new host must construct its selection set as `new HashSet<string>(StringComparer.OrdinalIgnoreCase)` if it wants case-insensitive selection. Do not rely on `ScenarioListEditor` or `ScenarioListState` to apply the comparer for you — neither does when a set is supplied. Watch the reassignment sites too (`WorkflowExecutionEditor.razor.cs:449` `codes.ToHashSet()`, `WorkflowScenariosEditor.razor.cs:1098` `new HashSet<string>(affectedCodes)`), which also drop any comparer.

**Page size:** pass `DefaultCardPageSize` + `CardPageSizeOptions` from config, reusing **existing** appsettings sections — do NOT invent new ones (see [[feedback_reuse_existing_config_sections]]):
- `WorkflowScenariosEditor` → `WebUI:WorkflowBuilder` (`DefaultPageSize` 75 / `PageSizeOptions`)
- `WorkflowExecutionEditor` → `WebUI:WorkflowExecution` (the UI section nested under `WebUI` — distinct from the root-level `WorkflowExecution` engine section)

The component applies `DefaultCardPageSize` in `OnInitialized` (not `OnParametersSet`) so the configured default isn't clobbered and user page-size changes persist.

---

## Editor Caching Rules

- **Do not cache** editors on every open — reload from the current `ScenarioConfiguration` state
- Cache is appropriate only when the user has uncommitted draft changes that should survive a tab switch
- `EnableDraftPersistence=false` is the default for embedded editors; only enable if the page explicitly manages draft state

---

## Navigation Guard

`EnableNavigationGuard` protects against leaving a page with unsaved changes. Rules:
- Enable on full-page editors where the user can navigate away
- Disable when the editor is inside a modal (the modal close button is the exit path, not navigation)

---

## InMemoryEditorResult — Dialog Editing Without Auto-Save

When a page needs to edit a scenario *in memory* (the caller controls when/whether to save), open `ScenarioEditorContent` in a dialog and get back an `InMemoryEditorResult`:

```csharp
var result = await DialogService.OpenAsync<ScenarioEditorContent>(
    "Edit Scenario",
    new Dictionary<string, object>
    {
        { "InitialConfigurationJson", JsonConvert.SerializeObject(configClone) },
        { "ShowHeader", false },
        { "ShowActionBar", true },
        { "EnableNavigationGuard", false },
        { "EnableDraftPersistence", false },
        { "WorkflowSteps", workflowStepInfoList },   // optional — shows step context
        { "CurrentStepOrder", scenario.ExecutionOrder },
        { "OnCancelled", EventCallback.Factory.Create(this, () => DialogService.Close()) }
    },
    new DialogOptions { Width = "92vw", Height = "92vh", Resizable = true, Draggable = true,
                        CloseDialogOnOverlayClick = false, CloseDialogOnEsc = false });

if (result is InMemoryEditorResult updated)
{
    scenario.Configuration = updated.Configuration;
    scenario.DisplayName = updated.DisplayName ?? scenario.DisplayName;
    scenario.Tags = updated.Tags;
    // caller decides when to persist
}
```

**Rules**:
- Always pass a **deep clone** of `Configuration` — not the live reference — to prevent mutation before save.
- `EnableDraftPersistence = false` — the caller owns state.
- `EnableNavigationGuard = false` — dialog close is the exit path, not navigation.

`WorkflowStepInfo` list is optional; pass it to show the editor which step in the workflow this is (`ExecutionOrder`, `DisplayName`, `ScenarioName`).

---

## Editor-Dialog Return Convention — companion `*Result` with `Saved`

`InMemoryEditorResult` above is one instance of a broader convention used by the **editor dialogs** under `Components/Controls/`. Each such dialog defines a **companion public `*Result` class** (declared in the same file/namespace as the dialog, not necessarily nested) carrying a `bool Saved` flag plus the edited values, and signals its outcome through `DialogService.Close(result)`. The canonical example is `EditSectionDialog` (`Components/Controls/EditSectionDialog.razor.cs`), which edits a secrets section and can also create a new one:

```csharp
public partial class EditSectionDialog : ComponentBase
{
    [Inject] public DialogService DialogService { get; set; } = default!;

    // [Parameter] props pre-populate the form; CreateMode distinguishes add vs edit
    [Parameter] public string SectionName { get; set; } = string.Empty;
    [Parameter] public List<SecretFieldEdit> Fields { get; set; } = new();
    [Parameter] public bool CreateMode { get; set; }
    // (Category / Description / IncludeInReplacements are edited in create mode)

    private void Save() =>                                   // :87
        DialogService.Close(new EditSectionResult
        {
            Saved = true,
            Fields = cleaned,
            IsCreate = CreateMode,
            SectionName = SectionName?.Trim() ?? string.Empty,
            Category = Category,
            Description = Description?.Trim() ?? string.Empty,
            IncludeInReplacements = IncludeInReplacements
        });

    private void Cancel() =>                                 // :145
        DialogService.Close(new EditSectionResult { Saved = false });
}

// Companion result type in the same namespace (EditSectionDialog.razor.cs :163)
public class EditSectionResult
{
    public bool Saved { get; set; }
    public List<SecretFieldEdit> Fields { get; set; } = new();
    public bool IsCreate { get; set; }
    public string SectionName { get; set; } = string.Empty;
    public string Category { get; set; } = "Other";
    public string Description { get; set; } = string.Empty;
    public bool IncludeInReplacements { get; set; }
}
```

Caller pattern-matches the returned object and checks `Saved`:

```csharp
var result = await DialogService.OpenAsync<EditSectionDialog>(title, parms, options);
if (result is EditSectionResult { Saved: true } r)
{
    // apply r.SectionName, r.Fields, r.Category … (r.IsCreate = new section)
}
```

**When to use the `*Result` convention**: editor dialogs that return **multiple fields** and need an explicit confirm/cancel distinction (e.g. `EditSectionDialog` → `EditSectionResult`).

**Contrast — simple dialogs return a raw value** instead of a `*Result`: yes/no confirmations and single-object pickers call `DialogService.Close(true)`, `DialogService.Close(token)`, or `DialogService.Close(null)` directly (e.g. `SaveTemplateDialog` → `Close(true)`, `NestedValueEditorDialog` → `Close(token)`/`Close(null)`). Don't wrap a single value in a `*Result`.

---

## Common Components

| Component | Location | Purpose |
|---|---|---|
| `CustomParmsEditorHost` | `Components/Common/` | Routes to concrete editor by `EditorType` |
| `ScenarioCustomParmsDialog` | `Components/Dialogs/` | Full-screen custom parms popup |
| `ScenarioEditorContent` | `Components/Pages/` | Embeddable scenario editor (no chrome) |
| `ConfigurationSection` | `Components/Controls/` | Collapsible section container |
| `IScenarioListItem` | `Components/Common/` | Interface for scenario list items |
| `ScenarioListEditor<TItem>` | `Components/Controls/` | **Shared** scenario list/grid surface (filter bar, card+grid, view toggle, collapse, paging, selection); hosted by both workflow editors — configure via capability flags + selectors, never re-implement |
| `ScenarioListState<TItem>` | `Components/Common/` | Pure (non-UI) filter/facets/paging/selection state for `ScenarioListEditor`; unit-tested |
| `ScenarioDetailItem` | `Components/Common/ScenarioDetailItem.cs` | Workflow editing ViewModel (IsNew/IsDirty/OriginalRecord); see `testauto-workflow-execution` |
| `InMemoryEditorResult` | `Components/Common/` | Return type from ScenarioEditorContent when editing in-memory (no auto-save) |
| `EditSectionDialog` (+ companion `EditSectionResult`) | `Components/Controls/` | Editor dialog using the companion `*Result` + `Saved` return convention (see "Editor-Dialog Return Convention") |
| `ExecutionScenarioDetailItem` | `Components/Common/` | Execution-specific scenario detail |
| `WorkflowStepInfo` | `Components/Controls/StepLinkingEditor.razor.cs` | ExecutionOrder + DisplayName + ScenarioName; passed to editor for workflow context |
| `SmartJsonEditor` | `Components/Controls/` | **Feature-flagged host** for the enhanced JSON editor — picks `MonacoJsonEditor` or the plain `JsonEditor` textarea (see "Enhanced JSON editor" below) |
| `MonacoJsonEditor` | `Components/Controls/` | **Real, fully-implemented BlazorMonaco host** — not a stub (see "Enhanced JSON editor" below) |
| `JsonEditor` | `Components/Controls/` | Plain `<textarea>` JSON editor; the fallback both of the above render to |

---

## Enhanced JSON editor — `SmartJsonEditor` → `MonacoJsonEditor` → `JsonEditor`

`MonacoJsonEditor` is **not** a placeholder, skeleton, or textarea wrapper. It is a complete Monaco (VS Code) editor host:

- The **BlazorMonaco 3.4.0** package is genuinely referenced — `Directory.Packages.props:10` pins the version, `TestAuto.Web/TestAuto.Web.csproj:52` has the `<PackageReference Include="BlazorMonaco" />`.
- `MonacoJsonEditor.razor` renders a real `<StandaloneCodeEditor>` (from `BlazorMonaco.Editor`) inside a `.monaco-editor-host` div sized `_rows * 19` px, with `@ref="_editor"`, `ConstructionOptions="BuildOptions"` and `OnDidChangeModelContent="OnContentChanged"`.
- `MonacoJsonEditor.razor.cs` is a `ComponentBase, IAsyncDisposable` with the full lifecycle: `BuildOptions` (`:87`) returns `StandaloneEditorConstructionOptions` with `Language = "json"`, `ReadOnly = !IsEditable`, minimap off, `FoldingStrategy = "indentation"`; `OnContentChanged` (`:107`) reads `_editor.GetValue()` and forwards to `JsonContentChanged`; `OnAfterRenderAsync` (`:63`) pushes external `JsonContent` changes back in via `_editor.SetValue`; `DisposeAsync` (`:124`) calls `_editor.DisposeEditor()`. Every JS boundary catches `JSDisconnectedException` and logs the rest via `Logger.WarningWithTag(LogTagConstants.WebUi, …)`.
- It has its **own** internal fallback: until `_libraryReady` is set on first render it renders `<JsonEditor />`, so it degrades rather than flashing an empty box.

The parameter contract (`Title`, `JsonContent`, `JsonContentChanged`, `IsEditable`, `Rows`) is identical across all three components, so they are drop-in interchangeable.

### `SmartJsonEditor`'s loader is a JS readiness probe, not a stub

> [!note] This reversed in 2026-08 — the loader was implemented
> Earlier revisions correctly described `TryLoadEnhancedEditorAsync` as a placeholder that logged
> *"provider requested but not yet installed"* and unconditionally returned `false`. It now really probes
> and mounts Monaco.

`SmartJsonEditor.razor.cs`:

- `OnInitialized` (`:47`) reads `FeatureFlags:EnhancedJsonEditor` — `true` in `TestAuto.Web/appsettings.json`, with `JsonEditorProvider: "Monaco"`.
- `TryLoadEnhancedEditorAsync` (`:89`) rejects any provider other than `"Monaco"` with a warning, then calls
  `JSRuntime.InvokeAsync<bool>("testAutoMonaco.waitForReady", …)` (`:104`) with a 3 s in-browser deadline and
  a 5 s `CancellationTokenSource` backstop. `testAutoMonaco.waitForReady` (`wwwroot/js/site.js`) polls for
  `window.monaco.editor` every 50 ms.

**Why a readiness probe is needed at all:** `App.razor` loads BlazorMonaco's `editor.main.js`, which only
*declares* the AMD module — the loader resolves the graph asynchronously, so `window.monaco` does **not**
exist at first render. Mounting `MonacoJsonEditor` early makes BlazorMonaco log "monaco is undefined" and
render an empty box. The textarea renders first; Monaco swaps in only once the probe returns true
(`_enhancedReady`, `:56`), and a failed probe sets `_useFallback` permanently.

Contrary to the old note, BlazorMonaco does **not** load its own JS in time — a separate readiness call is
required. CrewChief hit the same problem and solved it the same way; see [[crewchief-raw-json-editing]].

Only one consumer today: `Components/Controls/JsonOnlyCustomParmsEditor.razor:25` hosts `<SmartJsonEditor>`.

---

## Icon Rules

Use **Material Symbols** from the approved list only. Bootstrap icons are **not supported** in Radzen Blazor v7.1.7.

Approved icons (common):
- Navigation: `home`, `dashboard`, `menu`, `settings`
- Actions: `add`, `edit`, `delete`, `save`, `refresh`
- Data: `table_chart`, `storage`, `folder`, `dataset`
- Status: `check_circle`, `warning`, `error`, `info`

See `blazor-icons` skill for the full approved list.

---

## Radzen Chart Series — `CategoryProperty`/`ValueProperty`, not `Category=`/`Value=`

When binding a `RadzenColumnSeries` (or any Radzen chart series) to a data collection, use the **string-property-name attributes**:

```razor
<RadzenColumnSeries Data="@MyData"
                    CategoryProperty="Key"
                    ValueProperty="Value" />
```

**Do NOT use `Category=`/`Value=`** (attempting to bind a property directly). These attributes do not exist as `[Parameter]` members and will throw at render time:

```
InvalidOperationException: Object of type 'Radzen.Blazor.RadzenColumnSeries`...' has a property
matching the name 'Value', but it does not have [Parameter] or [CascadingParameter] attributes.
```

This exception cascades into a Blazor circuit `ObjectDisposedException` that kills the page. The fix is always `CategoryProperty="Key" ValueProperty="Value"` (the property name as a string).

Verified in `TestAuto.Web/Components/Pages/PerformanceDashboard.razor` — both series use `CategoryProperty`/`ValueProperty`.

---

## Toggle Controls — use `RadzenSwitch`, never `RadzenSelectBar`

For an on/off option use a **`RadzenSwitch`** (the slider toggle) with a label beside it. For two or more independent on/off options (e.g. "Files" and "Scenarios" that can each be on, off, or both), render **one `RadzenSwitch` per option** — each independently bindable.

```razor
<div class="d-flex align-items-center gap-2">
    <RadzenSwitch @bind-Value="FilesMode" @bind-Value:after="StateHasChanged" />
    <span class="fw-semibold">Files</span>
</div>
<div class="d-flex align-items-center gap-2">
    <RadzenSwitch @bind-Value="ScenariosMode" @bind-Value:after="StateHasChanged" />
    <span class="fw-semibold">Scenarios</span>
</div>
```

**Do NOT use `RadzenSelectBar` (segmented toggle-button group) for on/off toggles** — the user has explicitly rejected that style. `RadzenSelectBar` is also a poor fit for independent toggles because, even in `Multiple` mode, it reads as a single segmented control rather than separate switches. Use `RadzenSwitch`. (Checkboxes are also dispreferred for this; use the switch.)

---

## Rejected Patterns

| Pattern | Why rejected |
|---|---|
| Rendering custom parms editor inline in ConfigurationSection | Violates the single-dialog rendering rule |
| Resetting filter state on scenario selection | User preference: filter state must persist |
| Hardcoded pixel dialog sizes | Breaks on different screen sizes |
| Replacing Radzen components with generic alternatives during refactor | Preserve existing UI patterns; fix issues and reach parity before introducing new components |
| `RadzenSelectBar` (segmented toggle buttons) for on/off options | User dislikes the style — use one `RadzenSwitch` per independent on/off option (see "Toggle Controls") |

When a UI suggestion is rejected as "not any better," wait for the user to describe a specific alternative layout, then implement that description exactly.

---

## WizardState

Multi-step wizard state model for the `UnifiedMatchingScenarioEditor` — the CustomParms editor for `UnifiedMatchingScenario`.

**Files**:
- `TestAuto.Web/Components/Controls/Models/WizardState.cs` — state class
- `TestAuto.Web/Components/Controls/Models/WizardStepDefinition.cs` — step record
- `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor.cs` — host component

---

### WizardStepDefinition

```csharp
public record WizardStepDefinition(
    string Id,       // routing key used in @switch (e.g. "scenario-selection", "record-mix")
    string Title,    // displayed in the step indicator bar
    string Description, // subtitle shown in the step content header
    int Order        // zero-based position in the step list
);
```

---

### WizardState Shape (key fields)

`WizardState` is a plain C# class (no `ComponentBase`). It holds **all bound properties** for every wizard step.

| Category | Key Properties |
|---|---|
| Template | `SelectedScenarioTemplate` (string — matches `UnifiedMatchingConstants.Template_*`) |
| Operation | `OperationType`, `RecordSource` |
| Record Mix | `RecordMixEnabled`, `ChangedPercent`, `NewPercent`, `UnchangedPercent`, `CreatePercent`, `UpdatePercent`, `LubcMixEnabled` |
| Execution | `ExecutionMode` ("Time"/"Count"/"Both"), `ConcurrentThreads`, `TestRecordLimit`, `TimeLimitText`, `IterationLimit` |
| Source Systems | `SelectedNewSourceCodes` (HashSet), `SelectedChangedSourceCodes` (HashSet), `SourceSystemEntries` (List<SourceSystemEntry>), `AllModelSources` |
| 3A-specific | `Scenario3ARecordSource` ("TargetEntity"/"ModelSource"), `SelectedScenario3ASourceCodes`, `SelectedMatchStatusCodes`, `SelectedLookupAttributeCodes` |
| Advanced | `MatchingStrategyName`, `MaxGoldenRecordAttempts`, `WaitTimeBetweenGoldenRecordAttemptsMs` |
| JSON preview | `CustomParmsJson` — serialized representation of persisted CustomParms |

**Computed visibility booleans** (drive conditional rendering in each step):

```csharp
bool IsBatchMode          // OperationType == "BatchLoad"
bool IsLookupMode         // LookupOnly or LookupThenCreate
bool IsLookupThenCreate
bool IsLookupOnly
bool IsCreateOnly
bool IsMixed              // RecordSource == "Mixed"
bool ShowRecordMix        // IsMixed && (IsBatchMode || IsLookupThenCreate)
bool ShowScenario3A       // IsLookupOnly
bool ShowScenario3B       // IsLookupThenCreate
bool ShowScenario3C       // IsCreateOnly
bool ShowTestRecordLimit  // IsBatchMode
bool ShowTimedTestSettings
bool ShowLubcConfiguration
```

---

### Step Definitions by Template

`State.GetStepsForTemplate()` returns the step list for `SelectedScenarioTemplate`:

| Template constant | Steps (Id values in order) |
|---|---|
| `Template_Scenario1` | scenario-selection → execution-limits → concurrency-pacing → source-systems → custom-parms → review |
| `Template_Scenario2` | scenario-selection → execution-limits → concurrency-pacing → record-mix → source-systems → mutation-level → custom-parms → review |
| `Template_Scenario3A` | scenario-selection → execution-limits → concurrency-pacing → source-records → record-source → source-systems → record-pool (TargetEntity only) → lookup-attributes → custom-parms → review |
| `Template_Scenario3B` | scenario-selection → execution-limits → concurrency-pacing → source-records → record-mix → source-systems → lookup-attributes → custom-parms → review |
| `Template_Scenario3C` | scenario-selection → execution-limits → concurrency-pacing → record-mix → source-systems → custom-parms → review |
| `Template_Custom` (empty) | scenario-selection only |

Scenario 3A's step list is **dynamic**: the `record-pool` step (Match Status Filter) is only inserted when `Scenario3ARecordSource == "TargetEntity"`.

---

### Step Navigation (in UnifiedMatchingScenarioEditor)

Navigation state lives in the **editor**, not in `WizardState`:

```csharp
private int CurrentStepIndex { get; set; } = 0;
private List<WizardStepDefinition> ActiveSteps { get; set; } = new();

private void GoToStep(int index)      // direct jump — used by step indicator bar clicks
private void OnNextStep()             // CurrentStepIndex++
private void OnPreviousStep()         // CurrentStepIndex--
private void OnStartOver()            // CurrentStepIndex = 0; UpdateActiveSteps()
private void UpdateActiveSteps()      // re-calls State.GetStepsForTemplate(); clamps index if steps shrunk
```

There are no `CanGoNext`/`CanGoBack` guards on the editor — Previous/Next buttons are disabled via `@disabled` attributes in the razor directly.

---

### Template Application

`ApplyScenarioTemplate(string template)` sets all `WizardState` fields to the canonical defaults for a scenario, then calls `State.BuildSourceSystemEntries(null, null)`. It is called:
- From `OnScenarioTemplateChanged` (dropdown)
- From `OnWizardTemplateChanged` (raised by `ScenarioSelectionStep`)

After applying a template, the editor always calls `SaveToConfiguration()` and `UpdateActiveSteps()`, and resets `CurrentStepIndex = 0`.

---

### Consumer Pattern — Step Component

Each step is a Blazor partial class that takes `WizardState` as a `[Parameter]`:

```csharp
// ScenarioSelectionStep.razor.cs (representative)
public partial class ScenarioSelectionStep : ComponentBase
{
    [Parameter, EditorRequired]
    public WizardState State { get; set; } = default!;

    [Parameter]
    public EventCallback StateChanged { get; set; }          // generic field-changed callback

    [Parameter]
    public EventCallback<string> TemplateChanged { get; set; } // template-specific callback

    [Parameter]
    public EventCallback OperationTypeChanged { get; set; }

    [Parameter]
    public EventCallback RecordSourceChanged { get; set; }
}
```

Steps mutate `State` properties directly and then invoke `StateChanged` (or a typed callback). The parent editor's `OnStateChanged()` handler calls `SaveToConfiguration()` and `UpdateActiveSteps()` to persist and rebuild the step list.

---

### Step Rendering in the Razor

The editor renders the active step by switching on `ActiveSteps[CurrentStepIndex].Id`:

```razor
@switch (currentStep.Id)
{
    case "scenario-selection":
        <ScenarioSelectionStep State="@State"
                               StateChanged="@OnStateChanged"
                               TemplateChanged="@OnWizardTemplateChanged"
                               OperationTypeChanged="@OnWizardOperationTypeChanged"
                               RecordSourceChanged="@OnWizardRecordSourceChanged" />
        break;

    case "record-mix":
        <RecordMixStep State="@State" StateChanged="@OnStateChanged" />
        break;

    // ... all other step IDs follow same pattern
}
```

Most steps only need `State` + `StateChanged`. Steps that drive template or operation-type changes have additional typed callbacks so the parent can call the appropriate handler.

---

### Source System Helpers (called by SourceSystemsStep)

| Method | Purpose |
|---|---|
| `SelectAllOriginalSources()` | Fills `SelectedNewSourceCodes` from `AvailableNewSources` |
| `SelectAllMutatedSources()` | Fills `SelectedChangedSourceCodes` from `AvailableChangedSources` |
| `SelectAllSources()` | Fills `SelectedNewSourceCodes` from both pools (S1 pattern) |
| `BuildSourceSystemEntries(newOffsets, changedOffsets)` | Rebuilds `SourceSystemEntries` from `AllAvailableSources` + existing HashSets |
| `SyncSourceCodesFromEntries()` | Re-derives `SelectedNewSourceCodes`/`SelectedChangedSourceCodes` from the unified table after a UI toggle |

---

### Validation

`State.GetValidationWarnings()` returns `List<string>` with human-readable warnings. Called from the razor directly (not from a lifecycle event). Common triggers:

- Record mix percentages don't sum to 100
- `SleepMinMs > SleepMaxMs`
- Invalid `TimeLimitText` format
- No source systems selected for batch mode
- `SourceSystemDistribution` sum mismatch vs. `TestRecordLimit` (stale after direct JSON edit)

---

## Sources

- `AGENTS.md` (Learned User Preferences + Workspace Facts) — *source removed 2026-05-31; content migrated to work-ai, this skill is now canonical*
