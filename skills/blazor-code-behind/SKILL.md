---
name: blazor-code-behind
description: >
  Blazor code-behind structure and conventions for TestAuto.Web components. Use when creating or
  editing .razor / .razor.cs pairs, wiring DI into a component, lifecycle methods, [Parameter] and
  EventCallback, IDisposable on a component, the partial-class split, choosing a shared base class
  (MarkdownDocBase, ConnExResourcePageBase, BulkCustomParmsEditorBase), auto-refresh timers,
  prerender ObjectDisposedException, or InvokeAsync marshalling.
---

# Blazor Code-Behind Pattern

TestAuto.Web separates every non-trivial Blazor component into a `.razor` markup file and a
`.razor.cs` code-behind file. The code-behind is a `partial class` that carries all C# logic —
DI injection, parameters, private state, and lifecycle hooks — while the `.razor` file contains
only markup and minimal inline expressions. This keeps razor files short and diff-friendly and
puts all testable logic in plain C# files.

## When to Use

- "adding a new Blazor component or page to TestAuto.Web"
- "injecting a service into a component"
- "adding a lifecycle method like OnInitializedAsync"
- "declaring a [Parameter] on a component"
- "wiring an EventCallback between parent and child"
- "implementing IDisposable on a component (e.g. for a timer)"
- "splitting an existing .razor file into a .razor / .razor.cs pair"

## File Pair Convention

Every component consists of exactly two files with the same base name:

```
ComponentName.razor       ← markup only; @using / @inject are rare here
ComponentName.razor.cs    ← partial class; all C# logic lives here
```

The `.razor.cs` class must be declared `partial` so the Blazor compiler can merge it with the
generated partial class produced from the `.razor` file. The namespace matches the folder path
under `TestAuto.Web` (e.g. `TestAuto.Web.Components.Pages`, `TestAuto.Web.Components.Controls`).

## Base Class Inheritance

| Scenario | Base class |
|---|---|
| Standard component or page | `ComponentBase` |
| Layout component (`MainLayout`) | `LayoutComponentBase` |
| Component that must release resources | `ComponentBase` + `IDisposable` |

```csharp
// Standard page / control
public partial class ScenarioEditor : ComponentBase { ... }

// Layout
public partial class MainLayout : LayoutComponentBase { ... }

// Component with timer or subscription
public partial class ExecutionMonitoringDialog : ComponentBase, IDisposable { ... }
```

The overwhelming majority of components extend `ComponentBase` directly — a scan of
`TestAuto.Web/**/*.razor.cs` on 2026-07-27 found 112 `: ComponentBase` declarations against one
`LayoutComponentBase` and a handful of shared bases. But it is **not** true that there are no
custom base classes; there are six, and two of them are the required entry point for their
feature area.

### Shared component base classes

Re-derive this list with `grep -rn "class [A-Za-z0-9_]*Base" --include=*.cs TestAuto.Web` plus
`grep -rhoE "@inherits [A-Za-z0-9_.<>]+" --include=*.razor TestAuto.Web` — the counts below will drift.

| Base class | File | Extends | Who inherits it |
|---|---|---|---|
| `MarkdownDocBase` | `Components/Help/MarkdownDocBase.cs:14` (`abstract`) | `ComponentBase` | **Every generated help-doc page.** Nothing inherits it in source — it is wired by the MSBuild property `<MD2RazorDefaultBaseClass>TestAuto.Web.Components.Help.MarkdownDocBase</MD2RazorDefaultBaseClass>` (`TestAuto.Web.csproj:108`), so the MD2Razor generator emits `public partial class <Doc> : TestAuto.Web.Components.Help.MarkdownDocBase` into `obj/…/md2razor/*.g.cs`. Grepping source for inheritors finds nothing — do not conclude it is dead. See `testauto-help-docs`. |
| `ConnExResourcePageBase` | `Components/Pages/ConnExResourcePageBase.cs:28` (`abstract`) | `ComponentBase` | `ConnExIntegrationStrategies.razor:2` and `ConnExServiceConfigurations.razor:2`, both via `@inherits`. |
| `BulkCustomParmsEditorBase<T>` | `Components/Common/BulkCustomParmsEditorBase.cs:54` (`abstract`, `IDisposable`, `IAsyncDisposable`) | `ComponentBase` | **Nobody, as of 2026-07-27.** The two pages it was written for — `WorkflowScenariosEditor.razor.cs:33` and `WorkflowExecutionEditor.razor.cs:31` — both declare `: ComponentBase, IDisposable` and reimplement the bulk-edit logic inline. The class survives only in `<see cref>` doc comments on `IScenarioListItem`, `ScenarioDetailItem`, and `ExecutionScenarioDetailItem`. Treat it as an intended-but-unadopted base: check whether it still matches before inheriting from it. |
| `TagFilterBase` | `Components/Controls/TagFilter.razor.cs:5` | `ComponentBase` | `TagFilter.razor` via `@inherits`. |
| `TagChipsSelectorBase` | `Components/Controls/TagChipSelector.razor.cs:3` | `ComponentBase` | `TagChipSelector.razor` via `@inherits`. |
| `TagDropdownSelectorBase` | `Components/Controls/TagDropdownSelector.razor.cs:3` | `ComponentBase` | `TagDropdownSelector.razor` via `@inherits`. |
| `SortIconToggleBase` | `Components/Controls/SortIconToggle.razor.cs:3` | `ComponentBase` | `SortIconToggle.razor` via `@inherits`. |

Note the second convention hiding in that table: the four `Tag*`/`SortIconToggle` controls do **not**
use the `partial class` pairing described above. They declare a plain (non-partial) `*Base` class in
the `.razor.cs` and the `.razor` pulls it in with `@inherits <Name>Base`. When you edit one of those
four, follow the local pattern — do not "fix" it into a partial class, which would break the
`@inherits` directive.

## DI Injection

Services are injected via the `[Inject]` attribute on public auto-properties in the code-behind.
`@inject` directives in the `.razor` file are not used for services that have a code-behind.

```csharp
[Inject] public NavigationManager Nav { get; set; } = default!;
[Inject] public IScenarioService ScenarioService { get; set; } = default!;
[Inject] public NotificationService NotificationService { get; set; } = default!;
```

Rules observed in the codebase:
- Always `public` (required by the Blazor injector).
- Always initialized to `default!` to satisfy the nullable analyzer without a constructor.
- Injected services appear at the top of the class, before fields and parameters.

## Parameters

Incoming data from a parent component is declared with `[Parameter]`:

```csharp
// Required parameter — EditorRequired enforces compile-time non-null check
[Parameter, EditorRequired]
public WizardState State { get; set; } = default!;

// Optional parameter with default
[Parameter] public bool ShowSaveButton { get; set; } = true;

// EventCallback — zero-argument notification to parent
[Parameter] public EventCallback StateChanged { get; set; }

// EventCallback<T> — typed payload to parent
[Parameter] public EventCallback<string> OnSaved { get; set; }

// Route parameters on page components
[Parameter] public string? ScenarioId { get; set; }
```

Conventions:
- `[Parameter, EditorRequired]` is used together (comma-separated on one line) for mandatory
  inputs that must not be null.
- `EventCallback` (not `Action` or `Func`) is always used for parent-notification callbacks so
  Blazor can handle re-render scheduling automatically.
- `CascadingParameter` has not been observed in the current codebase; prefer explicit
  `[Parameter]` passing.

## Lifecycle Methods

Only override the lifecycle methods actually needed — do not add empty overrides.

| Method | When used |
|---|---|
| `OnParametersSet()` | Sync-only derived state that must update every time parameters change (e.g. mapping a `WizardState` into a local `List<>`) |
| `OnParametersSetAsync()` | Async variant — **in active use**. Two live examples: `Components/Controls/RealTimeValidation.razor.cs:37` (re-arms a debounce `Timer` toward `ValidateSectionAsync` whenever `AutoValidate && SectionData != null`) and `Components/Controls/ValidationSummary.razor.cs:20` (awaits `ErrorHandlingService.HandleValidationErrorsAsync(...)` and raises `OnErrorHandlingResultChanged`). Use it when parameter-driven derived state needs an `await`. |
| `OnInitializedAsync()` | First-load data fetching, parallel service calls, starting timers |
| `Dispose()` | Releasing `Timer`, subscriptions, or other unmanaged resources |

```csharp
// Parameter-driven sync transform
protected override void OnParametersSet()
{
    base.OnParametersSet();
    _entries = State.AdditionalCustomParms
        .Select(kvp => new CustomParmEntry { Key = kvp.Key, Value = kvp.Value?.ToString() ?? string.Empty })
        .ToList();
}

// Async first-load with parallel tasks
protected override async Task OnInitializedAsync()
{
    var taskA = ServiceA.GetDataAsync();
    var taskB = ServiceB.GetDataAsync();
    await Task.WhenAll(taskA, taskB);
    // ... consume results
    IsLoading = false;
}

// IDisposable cleanup
public void Dispose()
{
    _refreshTimer?.Dispose();
}
```

`StateHasChanged()` is called manually only when state is mutated outside the normal Blazor
event cycle (e.g. inside a `Timer` callback).

## Timers & Prerender Safety

`System.Threading.Timer` callbacks run on a threadpool thread — they have no access to the
Blazor renderer's synchronization context. Any component-state touch from a callback **must**
be marshalled via `InvokeAsync`:

```csharp
// CORRECT — marshals onto the renderer sync context
await InvokeAsync(StateHasChanged);

// CORRECT — marshal a larger block
await InvokeAsync(async () =>
{
    await RefreshAsync();
    _refreshCountdown = intervalSeconds;
    StateHasChanged();
});

// WRONG — throws from a threadpool callback
StateHasChanged();          // direct call, wrong thread
```

### Start timers in OnAfterRender, not OnInitializedAsync

Under the Interactive Server render mode with prerendering (and the legacy `ServerPrerendered`
hosting before the 2026-07 Blazor Web App migration) Blazor performs two render passes: a
static prerender and then a live interactive circuit. A timer created during `OnInitializedAsync` can fire against
the **already-disposed prerender renderer**, producing an `ObjectDisposedException` in
`RenderTreeDiffBuilder` / `ProcessRenderQueue`.

The safe pattern is `OnAfterRender(bool firstRender)` with the `if (!firstRender) return;`
guard — this lifecycle hook is only called on the interactive circuit, never during prerender:

```csharp
protected override void OnAfterRender(bool firstRender)
{
    if (!firstRender) return;
    _refreshTimer = new Timer(
        _ => _ = RefreshOnTimerAsync(),
        null,
        TimeSpan.FromSeconds(30),
        TimeSpan.FromSeconds(30));
}
```

> **Note**: `Index.razor.cs` starts its timers from `OnInitializedAsync` via `StartAutoRefresh`.
> That page has not been observed to hit the prerender race (possibly due to load ordering), but
> `PerformanceDashboard.razor.cs` was fixed to use `OnAfterRender` after reproducing the
> `ObjectDisposedException`. Prefer `OnAfterRender` for all new timer code.

### _disposed guard

Always set `_disposed = true` in `Dispose()` and check it at the top of the timer callback.
This prevents a late tick (already queued when `Dispose()` is called) from touching a
torn-down circuit:

```csharp
private bool _disposed;

private async Task RefreshOnTimerAsync()
{
    if (_disposed) return;
    try
    {
        await InvokeAsync(RefreshData);
    }
    catch (ObjectDisposedException) { /* circuit torn down between guard and invoke */ }
}

public void Dispose()
{
    _disposed = true;
    _refreshTimer?.Dispose();
}
```

### Server-timer data refresh + client-side JS countdown (Index.razor.cs)

When the UI shows a visible countdown to the next refresh, there is only **one**
`System.Threading.Timer` on the server — `_refreshTimer` — which reloads data on the
interval. The per-second countdown display is driven **client-side in JavaScript**, not
by a second C# timer. There is no `_countdownTimer` and no server-side `_refreshCountdown`
decrement.

- `_refreshTimer` — fires on the data-reload interval, reloads data inside
  `await InvokeAsync(...)`. This is the only server timer, and the only thing `Dispose()`
  releases.
- The visible countdown is a JS helper (`testAutoCountdown.start`) started from
  `OnAfterRenderAsync`, targeting a DOM element by id and counting down each second in the
  browser — no server round-trip per tick.
- The countdown is re-armed via a `_countdownGeneration` / `_countdownStartedGeneration`
  pair: `OnAfterRenderAsync` compares the two and (re)starts the JS countdown only when the
  generation advanced (e.g. after a data reload), so it isn't restarted on every render.

The interval comes from config (`WebUI:Dashboard:RefreshIntervalSeconds`):

```csharp
private int RefreshIntervalSeconds
    => Configuration.GetValue("WebUI:Dashboard:RefreshIntervalSeconds", 60);

// Single server-side data-refresh timer
_refreshTimer = new System.Threading.Timer(async _ =>
{
    await InvokeAsync(async () =>
    {
        await RefreshAsync();
        _countdownGeneration++;   // signal OnAfterRenderAsync to re-arm the JS countdown
        StateHasChanged();
    });
}, null, RefreshIntervalSeconds * 1000, RefreshIntervalSeconds * 1000);

// Client-side countdown, (re)started only when the generation advances
protected override async Task OnAfterRenderAsync(bool firstRender)
{
    if (_countdownGeneration != _countdownStartedGeneration)
    {
        _countdownStartedGeneration = _countdownGeneration;
        await JSRuntime.InvokeAsync<object>(
            "testAutoCountdown.start", "dashRefreshCountdown", RefreshIntervalSeconds);
    }
}

public void Dispose()
{
    _refreshTimer?.Dispose();
}
```

## Superseded async loads — the generation token

An `async` load started before the user changed selection will still complete, and will happily write its
stale results into the newer view. Guard it with a generation counter:

```csharp
private int _loadGeneration;                       // ProductionSync.razor.cs:101

// Every reload / selection change invalidates whatever is in flight:
_loadGeneration++;                                 // :324  (ResetLoadedData)

// Each load captures its own generation...
var generation = ++_loadGeneration;                // :339
// ...and re-checks after EVERY await, and inside every InvokeAsync:
if (generation != _loadGeneration) return;         // :355, and again at :389, :405
```

The re-check must happen **after each `await`**, not once at the top — every suspension point is a chance
for a newer load to start. Check inside `InvokeAsync` callbacks too, since those run later still.

## Poll timers must gate `StateHasChanged` on actual change

A timer that calls `StateHasChanged()` unconditionally re-renders the whole page every tick for the life of
the tab. At a 2-second cadence that is visible: it interferes with grid interaction and resets pager state
under the user's cursor. Compare the polled snapshot against the last one and repaint **only on a
difference** (`ProductionSync.razor.cs:274-284`). Contrast `PerformanceDashboard.razor.cs`, the timer
exemplar cited above, which repaints because its data genuinely changes each tick.

## Private State Conventions

- Private fields use `_camelCase` (e.g. `_entries`, `_grid`, `_refreshTimer`).
- Private properties that are UI-visible but not injected/parameter use `PascalCase` (e.g.
  `IsLoading`, `IsRefreshing`).
- Radzen component references captured with `@ref` are private nullable fields
  (e.g. `private RadzenDataGrid<T>? _grid;`).

## Nested Types

Small data-transfer types used only by one component are defined as `public` nested classes
inside the code-behind:

```csharp
public class CustomParmEntry
{
    public string Key { get; set; } = string.Empty;
    public string? Value { get; set; } = string.Empty;
}
```

## Examples

### Minimal control (parameters + EventCallback only)

```csharp
namespace TestAuto.Web.Components.Controls;

public partial class ScenarioActionBar : ComponentBase
{
    [Parameter] public string Title { get; set; } = "Actions";
    [Parameter] public bool ShowSaveButton { get; set; } = true;
    [Parameter] public EventCallback OnSave { get; set; }
    [Parameter] public EventCallback OnExecute { get; set; }
}
```

### Page shell (routing + DI + navigation callbacks)

```csharp
namespace TestAuto.Web.Components.Pages;

public partial class ScenarioEditor : ComponentBase
{
    [Inject] public NavigationManager Nav { get; set; } = default!;

    [Parameter] public string? ScenarioId { get; set; }

    private void HandleSaved(string newId)
        => Nav.NavigateTo($"/scenario-editor/S/{Uri.EscapeDataString(newId)}");
}
```

### ⛔ ANTI-PATTERN — starting a timer in a dialog's `OnInitializedAsync`

`ExecutionMonitoringDialog.razor.cs` is the live example of what **not** to copy. Verified at
`Components/Controls/ExecutionMonitoringDialog.razor.cs:22-32` and `:46-63`:

```csharp
// ⛔ DO NOT COPY — this is the current shape of ExecutionMonitoringDialog
public partial class ExecutionMonitoringDialog : ComponentBase, IDisposable
{
    private Timer? _refreshTimer;

    protected override async Task OnInitializedAsync()          // :22
    {
        await LoadExecutionStatus();
        // ⛔ timer started during (possible) prerender
        _refreshTimer = new Timer(async _ => await RefreshStatus(), null,
                                  TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));   // :26
    }

    private async Task RefreshStatus()                          // :46
    {
        if (IsRefreshing) return;
        try
        {
            IsRefreshing = true;
            await LoadExecutionStatus();
            StateHasChanged();      // ⛔ threadpool thread, no InvokeAsync
        }
        catch (Exception ex) { NotificationService.Notify(...); }   // ⛔ Notify from off-context too
        finally { IsRefreshing = false; }
    }

    public void Dispose() => _refreshTimer?.Dispose();   // ⛔ no _disposed flag
}
```

Four concrete defects, each already covered by a rule above:

1. **Prerender/disposal hazard.** The timer is armed in `OnInitializedAsync`, which runs on the
   static prerender pass as well as the interactive circuit. A tick can land on the already-disposed
   prerender renderer → `ObjectDisposedException` out of `RenderTreeDiffBuilder` /
   `ProcessRenderQueue`. See "Start timers in OnAfterRender, not OnInitializedAsync".
2. **No `InvokeAsync` marshalling.** `RefreshStatus` calls `StateHasChanged()` (and
   `NotificationService.Notify`) directly from a `System.Threading.Timer` threadpool callback, with
   no renderer sync context. See "Timers & Prerender Safety".
3. **No `_disposed` guard.** `Dispose()` only disposes the timer. A tick already queued when the
   dialog closes still runs `LoadExecutionStatus()` against a torn-down circuit. See "_disposed guard".
4. **Dialog lifetime makes it worse.** A dialog is opened and closed repeatedly within one circuit,
   so the dispose race fires far more often here than on a long-lived page.

**Rule**: in a dialog, arm timers from `OnAfterRender(firstRender)`, marshal every state touch through
`await InvokeAsync(...)`, and gate the callback on a `_disposed` flag set in `Dispose()`.
`PerformanceDashboard.razor.cs` is the corrected reference implementation.

### Full component (DI + OnInitializedAsync + IDisposable) — corrected shape

```csharp
namespace TestAuto.Web.Components.Controls;

public partial class ExecutionMonitoringDialog : ComponentBase, IDisposable
{
    [Inject] public IScenarioExecutionService ExecutionService { get; set; } = default!;
    [Inject] public NotificationService NotificationService { get; set; } = default!;

    [Parameter] public string JobId { get; set; } = string.Empty;

    private Timer? _refreshTimer;
    private bool _disposed;

    protected override async Task OnInitializedAsync()
        => await LoadExecutionStatus();          // data load only — no timer here

    protected override void OnAfterRender(bool firstRender)
    {
        if (!firstRender) return;                // interactive circuit only
        _refreshTimer = new Timer(_ => _ = RefreshOnTimerAsync(), null,
                                  TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
    }

    private async Task RefreshOnTimerAsync()
    {
        if (_disposed) return;
        try { await InvokeAsync(RefreshStatus); }
        catch (ObjectDisposedException) { /* circuit torn down between guard and invoke */ }
    }

    public void Dispose()
    {
        _disposed = true;
        _refreshTimer?.Dispose();
    }
}
```

### Control with OnParametersSet + nested type

```csharp
namespace TestAuto.Web.Components.Controls.WizardSteps;

public partial class CustomParmsStep : ComponentBase
{
    [Parameter, EditorRequired]
    public WizardState State { get; set; } = default!;

    [Parameter] public EventCallback StateChanged { get; set; }

    private List<CustomParmEntry> _entries = new();

    protected override void OnParametersSet()
    {
        base.OnParametersSet();
        _entries = State.AdditionalCustomParms
            .Select(kvp => new CustomParmEntry { Key = kvp.Key, Value = kvp.Value?.ToString() ?? string.Empty })
            .ToList();
    }

    public class CustomParmEntry
    {
        public string Key { get; set; } = string.Empty;
        public string? Value { get; set; }
    }
}
```

## Sources

- `TestAuto.Web/Components/Controls/WizardSteps/CustomParmsStep.razor.cs`
- `TestAuto.Web/Components/Controls/WizardSteps/CustomParmsStep.razor`
- `TestAuto.Web/Components/Pages/ScenarioEditor.razor.cs`
- `TestAuto.Web/Components/Pages/Index.razor.cs`
- `TestAuto.Web/Components/Layout/MainLayout.razor.cs`
- `TestAuto.Web/Components/Controls/ExecutionMonitoringDialog.razor.cs` (⛔ the timer-in-`OnInitializedAsync` anti-pattern, not a template)
- `TestAuto.Web/Components/Controls/RealTimeValidation.razor.cs`, `ValidationSummary.razor.cs` (live `OnParametersSetAsync`)
- `TestAuto.Web/Components/Help/MarkdownDocBase.cs` + `TestAuto.Web.csproj` `<MD2RazorDefaultBaseClass>` (generator-wired base)
- `TestAuto.Web/Components/Pages/ConnExResourcePageBase.cs`, `Components/Common/BulkCustomParmsEditorBase.cs` (shared bases)
- `TestAuto.Web/Components/Controls/TagFilter.razor.cs`, `TagChipSelector.razor.cs`, `TagDropdownSelector.razor.cs`, `SortIconToggle.razor.cs` (`@inherits` non-partial base convention)
- `TestAuto.Web/Components/Controls/ScenarioActionBar.razor.cs`
- `TestAuto.Web/Components/Pages/PerformanceDashboard.razor.cs` (OnAfterRender + _disposed guard)
- `TestAuto.Web/Components/Pages/Index.razor.cs` (single server-side `_refreshTimer` for data reload; per-second countdown driven client-side via `testAutoCountdown.start`, re-armed by the `_countdownGeneration`/`_countdownStartedGeneration` pair from OnAfterRenderAsync)
