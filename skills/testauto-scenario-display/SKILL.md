---
name: testauto-scenario-display
description: >
  Rules for extending scenario badge/pill/tooltip display in TestAuto.Web, centred on the shared
  ScenarioDisplayHelpers class and the unified ScenarioCard. Use when adding a scenario badge,
  tooltip, count, or badge style, deciding whether it belongs on the card or in a page's own grid
  markup via a page-level adapter, threading a card value through the ScenarioListEditor host, or
  adding fields, pills, stat tiles, or action buttons to the card itself.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Scenario Display — Extension Rules

## The Pattern

All display logic derived from `ScenarioConfiguration` lives in **one place**:

```
TestAuto.Web/BusinessLogic/Helpers/ScenarioDisplayHelpers.cs
```

This is a `public static class`. Each page is a **thin adapter** that bridges its local data type to `ScenarioConfiguration` and delegates to the shared class. No business logic lives in the pages.

---

## Two consumers: the card, and the pages' own grid/badge markup

**Read this before adding anything.** There are two independent consumption routes, and they have
different extension steps:

1. **`ScenarioCard`** — takes a single `ScenarioConfiguration? Configuration` parameter and derives
   every value itself (`ScenarioCard.razor.cs:131-141`). Card elements need **no page adapters at
   all**. Only two components render the card; see [Unified ScenarioCard Component](#unified-scenariocard-component).
2. **A page's own grid/badge markup** — the page must bridge its local item type to a
   `ScenarioConfiguration` with an adapter one-liner. This is the only place the adapter pattern
   below still applies.

### Page adapter patterns (grid/badge views only)

| Page | Data type | How to get config | Still reaches markup? |
|---|---|---|---|
| `Scenarios.razor.cs:464-473` | `Record s` | `GetScenarioConfig(s)` | **Yes** — grid badges at `Scenarios.razor:397-406`, plus `GetStepCount` in the card block (`:499`) and the export dialog (`:585,:606-608`) |
| `WorkflowBuilder.razor.cs:534,552` | `string? code` | `GetScenarioConfigByCode(code)` | **Yes** — step-count badge at `WorkflowBuilder.razor:388-391` |
| `WorkflowScenariosEditor.razor.cs:1515-1545` | `ScenarioDetailItem s` | `s.Configuration` | **Mostly no** — see below |

> **`WorkflowScenariosEditor`'s adapters are now nearly all vestigial.** Its scenario list is
> delegated wholesale to `ScenarioListEditor` (`WorkflowScenariosEditor.razor:317`), which owns both
> the card and the `RadzenDataGrid`. The page's own `.razor` references **none** of
> `GetDqRuleCount` / `GetMaxHangfireServers` / `GetBatchSize` / `GetTestRecordLimit` /
> `GetStepCount` / `GetDqBadgeStyle` / `GetServersBadgeStyle` / `GetStepsBadgeStyle` /
> `GetRunProfileCode` / `GetStepsTooltip` / `GetStepPointerTarget` — they survive only as
> declarations plus internal chaining. The **one** page adapter that still reaches markup is
> `GetMetricsSummaryTooltip(scenario)` (`WorkflowScenariosEditor.razor:342`), supplied to
> `ScenarioListEditor` through the `GridMetricsTemplate` RenderFragment, which the control renders
> as a compact single-icon "Metrics" column only when the host provides it
> (`ScenarioListEditor.razor:213-220`). Do not copy the vestigial adapters as a template for new
> work; add a `GridMetricsTemplate`-style host-supplied fragment or a `Func<TItem, …>` selector on
> `ScenarioListEditor` instead.

### Adapter one-liner pattern

```csharp
// WorkflowScenariosEditor
private int? GetXxx(ScenarioDetailItem s) => ScenarioDisplayHelpers.GetXxx(s.Configuration);

// Scenarios
private int? GetXxx(Record s) => ScenarioDisplayHelpers.GetXxx(GetScenarioConfig(s));

// WorkflowBuilder
private int? GetXxx(string? code) => ScenarioDisplayHelpers.GetXxx(GetScenarioConfigByCode(code));
```

---

## Unified ScenarioCard Component

The rich card view is a **single reusable component** — there is no per-page card markup anymore:

```
TestAuto.Web/Components/Controls/ScenarioCard.razor(.cs)
```

There are only **two** places in the codebase that render `<ScenarioCard>`:

| Host | Where | Item type | Distinctive parameters |
|---|---|---|---|
| `ScenarioListEditor.razor` (generic `TItem` list control) | `ScenarioListEditor.razor:308` | `ScenarioDetailItem` **or** `ExecutionScenarioDetailItem` | `Order`, `Status`/`StatusBadgeStyle` supplied via the `StatusSelector`/`StatusBadgeStyleSelector` delegates, `IsNew`/`IsDirty` selectors, `AdditionalCardClass`, `HeaderLeadContent` = selection checkbox. **Never sets `IsActive`.** |
| `Scenarios.razor` (library) | `Scenarios.razor:501` | `Record` (via `SafeGetValue` + `GetScenarioConfig`) | `ShowOrder="false"`, `Status="@null"`, **`IsActive="isActive"`**, `Purpose`, `CreatedBy`/`CreatedAt`/`UpdatedBy`/`UpdatedAt`, `OnCopyInfo`, `CanExtract="false"`/`CanDownload="false"`; `HeaderLeadContent` = error badge + export-steps button |

The two editor pages do **not** instantiate the card themselves — they instantiate `ScenarioListEditor` and let it own the card:

- `WorkflowScenariosEditor.razor:317` → `<ScenarioListEditor TItem="ScenarioDetailItem" …>` (template editor)
- `WorkflowExecutionEditor.razor:372` → `<ScenarioListEditor TItem="ExecutionScenarioDetailItem" …>` (execution editor)

So when adding a card element that an editor must supply, thread the parameter through `ScenarioListEditor` — do not add it to the pages directly. **Values** and **actions** use different mechanisms:

| Kind | Mechanism |
|---|---|
| **Value** | A `Func<TItem, …>` selector |
| **Action** | An `EventCallback<TItem>` on the host, adapted per item to the parameterless `EventCallback` the card expects: `EventCallback.Factory.Create(this, () => Cb.InvokeAsync(item))`, returning `default` when `!Cb.HasDelegate` (`ScenarioListEditor.razor.cs:143-150`, `OnCopyInfo`) |

Returning `default` matters: `ScenarioCard` gates the button on its own `HasDelegate` check, so a host that supplies no callback gets no button rather than a dead one.

Both editor item types implement `IScenarioListItem` (`TestAuto.Web/Components/Common/`). Look/behavior is identical across hosts; hosts differ only by which actions are enabled and which optional elements they populate.

> **`IsActive` is library-only.** The active/inactive dot renders solely because `Scenarios.razor:508` passes `IsActive="isActive"`, derived from the record's `"IsActive"` attribute equalling `"Y"` (`Scenarios.razor:498`). `ScenarioListEditor` never sets the parameter, so it stays `null` and `ScenarioCard.razor:55`'s `@if (IsActive.HasValue)` guard hides the dot in both the template and execution editors.

### Card derives its own display values

The card takes a single `ScenarioConfiguration? Configuration` parameter and computes its private derived properties internally via `ScenarioDisplayHelpers` (DqRules, Servers, Batch, Records, StepCount, SourceEntity, TargetEntity, MetricEntity, RunProfileCode, StepsTooltip, StepPointerTarget). Consumers do **not** pass pre-derived counts/pills — only the config. The one exception is `StepPointerResolvedName` (workflow context, see Step Pointer Special Case below).

> **File-step display was removed** with the file-reference retirement: there is no longer a `scriptKey`/`bodyFilePath` to count, so the former `GetFileStepCount` / `GetFilesTooltip` / `GetFileStepsBadgeStyle` helpers and the file-steps pill no longer exist — all five identifiers return **zero repo-wide hits** in `ScenarioDisplayHelpers.cs` and `ScenarioCard.razor(.cs)`. Step content is inline now (see [[testauto-multistep-steps]]). Do not re-document a files pill.

The card also builds its own info-panel step-detail table from `CustomParms["Steps"]` (`GetStepDetails()` + `NormalizeStepType()`, which maps raw step type strings like `curl`/`sqlstep`/`ps` to display names `Http`/`SQL`/`PowerShell`...).

### How applicability (hide non-applicable) is decided

There is **no per-scenario-type lookup table**. Applicability is decided by **value presence**:

- **Config-derived pills** (steps, RunProfile, step pointer — there is no files pill): the `ScenarioDisplayHelpers` method returns `null` when the config doesn't carry the value, and the card markup guards with `@if (X.HasValue)` / `@if (X != null)`. A scenario type that has no `Steps` array or RunProfile CustomParm simply never shows those pills.
- **Stat tiles** (DQ Rules, Servers, Batch, Records): always rendered; show `—` when the value is null.
- **Entity pills** (Source, Target, Metric Entity): always rendered; the tooltip carries the value or a `"Not set"` / `"None"` fallback.
- **Host-controlled optional elements**: nullable/blank parameters hide their element — `Status` null hides the status badge (template editor), `IsActive` null hides the active/inactive dot, blank `Version`/`Purpose` hide their pill/text, `ShowOrder="false"` hides the sequence-number badge (library page), and the info panel's Execution section only renders when `HasExecutionInfo` (any of Status/ExecutionMachine/StartTime/EndTime/ErrorMessage is supplied).

So: to make a field "not applicable" for a scenario type, make its derivation return `null` for that config shape — never add a scenario-type switch to the card.

### Other card behaviors

- `DefaultCollapsed` seeds collapse state and re-applies when it changes (`OnParametersSet` compares against `_lastDefaultCollapsed`), so a host "Collapse/Expand All" control drives every card while each card still toggles independently afterward.
- `Can*` enable flags (default true) disable individual toolbar actions; `EventCallback` actions no-op when no delegate is set.
- `HeaderLeadContent` RenderFragment slots content left of the order number (the execution editor puts a selection checkbox there).
- All `.sc-*` / `.scenario-card*` CSS lives in `wwwroot/css/custom.css` (global stylesheet), so the card renders identically across editors.

**When adding a new card element**: add the derivation to `ScenarioDisplayHelpers`, a derived property in `ScenarioCard.razor.cs`, and markup in `ScenarioCard.razor` — all three consumers get it automatically. The per-page adapters below are still needed only for the pages' **grid/badge views**.

---

## Current Methods in ScenarioDisplayHelpers

### Count extractors → `int?`
| Method | Reads from |
|---|---|
| `GetStepCount(config)` | `CustomParms["Steps"]` (JArray count) |
| `GetDqRuleCount(config)` | `ScenarioEnvironment.DqRuleCount` |
| `GetMaxHangfireServers(config)` | `ScenarioRuntime.MaxHangfireScenarioServersCount` |
| `GetBatchSize(config)` | `ScenarioRuntime.BatchSize` |
| `GetTestRecordLimit(config)` | `ScenarioTesting.TestRecordLimit` |

### Badge styles → `BadgeStyle` (take `int?` count, not the scenario)
| Method | Logic |
|---|---|
| `GetStepsBadgeStyle(count)` | `count > 0 → Primary` else `Secondary` |
| `GetDqBadgeStyle(count)` | `count == 0 → Success`, `count > 0 → Info`, no value → `Secondary` |
| `GetServersBadgeStyle(count)` | `count == 1 → Success`, `count > 1 → Info`, no value → `Secondary` |

> `GetBatchSizeBadgeStyle` and `GetTestRecordLimitBadgeStyle` always return `BadgeStyle.Success` — these are kept as page-level one-liners, not in the shared class.

### Tooltips → `string?`
| Method | Returns |
|---|---|
| `GetStepsTooltip(config)` | `"1. description\n2. description..."` for all steps |
| `GetRunProfileCode(config)` | The raw `UnifiedMatchingApiExecutionRunProfile` CustomParm value |
| `GetStepPointerTarget(config)` | The step number `N` from `{{STEP:N}}` token, or null |

**`GetMetricsSummaryTooltip(config)` — returns `string`, never null** (the one method in the class
whose return type is non-nullable):

```csharp
// ScenarioDisplayHelpers.cs:121
public static string GetMetricsSummaryTooltip(ScenarioConfiguration? config)
```

It composes every metric badge into one newline-separated block for a single compact grid column,
by calling the other extractors:

- **Always four lines**, each falling back to an em dash `—` when the value is null:
  `DQ Rules:` / `Servers:` / `Batch:` / `Records:` (`:125-128`).
- **Optional lines, only when present**: `Steps: N` (`:132`), `RunProfile: X` (`:135`),
  `Step pointer → step N` (`:138`).
- Joined with `"\n"` (`:140`) — matches the native multiline `title` convention above.

`WorkflowScenariosEditor.razor.cs:1543` wraps it and then **enriches** the step-pointer line with
the resolved scenario name, which needs workflow context the helper cannot have (see
[Step Pointer Special Case](#step-pointer-special-case)). If you add a new stat tile or pill to the
card, add its line here too — otherwise the compact Metrics column silently omits it.

### Entity-name extractors → `string?` (null when blank)
| Method | Reads from |
|---|---|
| `GetTargetMetricEntity(config)` | `ScenarioEnvironment.TargetMetricEntity` |
| `GetSourceEntityName(config)` | `ScenarioTables.SourceEntityName` |
| `GetTargetEntityName(config)` | `ScenarioTables.TargetEntityName` |

> These return `null` (not empty string) when the value is null/whitespace, so the `@if (x.HasValue)`
> badge/pill guard works the same as the count extractors. `Scenarios.razor.cs` adds the adapter wrappers.

---

## How to Add a New Display Element

### Step 1 — Add the logic to ScenarioDisplayHelpers

```csharp
/// <summary>One line explaining what this reads.</summary>
public static int? GetMyNewCount(ScenarioConfiguration? config) =>
    config?.ScenarioRuntime?.MyProperty;

public static BadgeStyle GetMyNewBadgeStyle(int? count) =>
    count is > 0 ? BadgeStyle.Info : BadgeStyle.Secondary;

public static string? GetMyNewTooltip(ScenarioConfiguration? config)
{
    // derive tooltip string from config
    return ...;
}
```

### Step 2 — Add adapter wrappers on each page that needs it

Only add adapters to pages that will actually render the new element. You do not need to add them to all three.

```csharp
// WorkflowScenariosEditor.razor.cs
private int? GetMyNewCount(ScenarioDetailItem s) => ScenarioDisplayHelpers.GetMyNewCount(s.Configuration);
private BadgeStyle GetMyNewBadgeStyle(ScenarioDetailItem s) => ScenarioDisplayHelpers.GetMyNewBadgeStyle(GetMyNewCount(s));

// Scenarios.razor.cs  
private int? GetMyNewCount(Record s) => ScenarioDisplayHelpers.GetMyNewCount(GetScenarioConfig(s));
private BadgeStyle GetMyNewBadgeStyle(Record s) => ScenarioDisplayHelpers.GetMyNewBadgeStyle(GetMyNewCount(s));

// WorkflowBuilder.razor.cs
private int? GetMyNewCount(string? code) => ScenarioDisplayHelpers.GetMyNewCount(GetScenarioConfigByCode(code));
```

### Step 3 — Add the razor markup

**Badge (grid/compact view):**
```razor
@{ var myCount = GetMyNewCount(scenario); }
@if (myCount.HasValue)
{
    <RadzenBadge BadgeStyle="@GetMyNewBadgeStyle(scenario)"
                 Text=@($"Label: {myCount}")
                 title="@(GetMyNewTooltip(scenario) ?? "")" />
}
```

**Pill (card view):**
```razor
@{ var myTooltip = GetMyNewTooltip(scenario); }
@if (myCount.HasValue)
{
    <span class="sc-step-pill" title="@(myTooltip ?? "")">
        <RadzenIcon Icon="icon_name" Style="font-size: 0.8rem;" />
        @myCount label
    </span>
}
```

---

## Tooltip Conventions

- Tooltips are applied via HTML `title` attribute — no Radzen tooltip component needed
- Always use `title="@(GetXxxTooltip(scenario) ?? "")"` — never bind null directly to `title`
- Tooltip text uses `\n` for line breaks (native browser multiline tooltip)
- Format: `"1. Description → detail"` (numbered, arrow separator for key/value pairs)
- Badge tooltips show the full value; badge text stays compact

## Badge Conventions

- Grid/table view: `RadzenBadge` — keep `Text` short (abbreviation or count)
- Card view: `<span class="sc-step-pill ...">` — slightly more space, can show a short label
- Hover tooltip shows the full detail in both views
- Never replace the badge/pill text with long strings — use tooltip for that

## Step Pointer Special Case

The step pointer resolved name requires workflow context (the list of other scenarios in the workflow). This cannot be centralized in `ScenarioDisplayHelpers`. It stays as a page-level method in `WorkflowScenariosEditor.razor.cs`:

```csharp
private string? GetStepPointerResolvedName(int stepTarget) =>
    ScenarioDetailItems.FirstOrDefault(s => s.ExecutionOrder == stepTarget)?.DisplayName;
```

The Scenarios page has no workflow context, so step pointer resolution is not available there.

---

## Key Files

| File | Role |
|---|---|
| `TestAuto.Web/BusinessLogic/Helpers/ScenarioDisplayHelpers.cs` | All shared display logic — the only place to put new config-derived computations |
| `TestAuto.Web/Components/Controls/ScenarioCard.razor(.cs)` | Unified scenario card — single source of card markup + derived display properties |
| `TestAuto.Web/Components/Controls/ScenarioListEditor.razor(.cs)` | Generic `TItem` list control that **hosts the card** for both editors (`ScenarioListEditor.razor:308`); editor-supplied card values arrive as `Func<TItem, …>` selectors |
| `TestAuto.Web/Components/Pages/WorkflowScenariosEditor.razor(.cs)` | Workflow-scoped scenario list (template editor); uses `ScenarioDetailItem` via `ScenarioListEditor` |
| `TestAuto.Web/Components/Pages/WorkflowExecutionEditor.razor(.cs)` | Execution editor; uses `ExecutionScenarioDetailItem` via `ScenarioListEditor` (no helper adapters) |
| `TestAuto.Web/Components/Pages/Scenarios.razor(.cs)` | Standalone scenario browser (library); uses `Record` |
| `TestAuto.Web/Components/Pages/WorkflowBuilder.razor(.cs)` | Workflow construction; uses `string? scenarioCode` |
| `TestAuto.Web/Components/Common/ScenarioDetailItem.cs` / `ExecutionScenarioDetailItem.cs` | Editor item types (both implement `IScenarioListItem`) |

## Checklist When Extending

- [ ] New logic added to `ScenarioDisplayHelpers` only, not inline on the page
- [ ] Card elements added once in `ScenarioCard.razor(.cs)`, never duplicated per page
- [ ] Adapter wrapper added to each page that renders the element (grid/badge views only)
- [ ] Badge style method takes `int?` count, not the scenario object
- [ ] Tooltip uses `?? ""` fallback, never null directly in `title`
- [ ] Badge text is short; full detail goes in tooltip
- [ ] Only added adapters to pages that actually render the element
- [ ] Non-applicable card fields hidden by null-returning derivation + `@if` guard — no scenario-type switches in the card

## Sources

- TestAuto.Web\BusinessLogic\Helpers\ScenarioDisplayHelpers.cs
- TestAuto.Web\Components\Controls\ScenarioCard.razor
- TestAuto.Web\Components\Controls\ScenarioCard.razor.cs
- TestAuto.Web\Components\Controls\ScenarioListEditor.razor (card host, line 308)
- TestAuto.Web\Components\Common\ScenarioDetailItem.cs
- TestAuto.Web\Components\Common\ExecutionScenarioDetailItem.cs
- TestAuto.Web\Components\Pages\WorkflowScenariosEditor.razor
- TestAuto.Web\Components\Pages\WorkflowExecutionEditor.razor
- TestAuto.Web\Components\Pages\Scenarios.razor
- TestAuto.Web\Components\Pages\WorkflowBuilder.razor.cs
