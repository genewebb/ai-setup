---
name: bulk-custom-parms-editor-base
description: >
  BulkCustomParmsEditorBase<T> abstract Blazor base class for bulk CustomParms editor
  pages in TestAuto.Web. Use when creating a new bulk editor page for workflow or
  execution scenarios, understanding preflight validation, change tracking via
  JToken.DeepEquals, draft persistence in sessionStorage, or the navigation guard
  (unsaved-changes prompt on route change).
---

Repo: speed-merchants (paths below are repo-relative)

# Bulk CustomParms Editor Base

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: `TestAuto.Web/Components/Common/BulkCustomParmsEditorBase.cs`

`BulkCustomParmsEditorBase<T>` centralises the shared logic between `CustomParmsEditor` (workflow) and `ExecutionCustomParmsEditor` (execution): source/target selection, change tracking, preflight validation, draft persistence, and navigation guards. Subclasses only need to implement data loading and saving.

---

## Type Parameter

```csharp
public abstract class BulkCustomParmsEditorBase<T> : ComponentBase, IDisposable, IAsyncDisposable
    where T : class, IScenarioListItem
```

`T` must implement `IScenarioListItem` (provides `Code`, `DisplayName`, `Configuration`).

---

## Abstract Members (implement in subclass)

```csharp
protected abstract Task LoadItemsAsync();             // Populate ScenarioItems
protected abstract Task SaveItemAsync(T item);        // Persist one updated item
protected abstract bool IsScenarioEditable(T item);  // Source/target eligibility
protected abstract string DraftKeyPrefix { get; }    // sessionStorage key prefix
protected abstract void NavigateBack();               // Post-apply navigation
```

---

## Change Tracking

`HasChanges` is computed from `GetChangedKeys()` which diffs the current `EditingConfiguration.ScenarioRuntime.CustomParms` against `OriginalCustomParms` using `JToken.DeepEquals`.

**Key invariant**: `OriginalCustomParms` is captured at the moment of source selection (`SelectSourceScenario`) and is **never mutated** until a successful apply. All diffs are always against the source-selection snapshot — not against the last save.

The apply button (`IsApplyDisabled`) is blocked if:
- No source scenario selected
- No target scenarios selected
- No changes detected
- Blocking validation is enabled AND there are errors

---

## Preflight Validation

Before applying, `RunPreflightAsync` runs up to 10 concurrent target validations using `SemaphoreSlim(10)`:

1. For each target, determine which `changedKeys` exist in the target's CustomParms (`applicable`) and which don't (`skipped`)
2. Clone the target configuration with the proposed changes applied
3. Call `IValidationService.ValidateConfigurationAsync(clone)` on the clone
4. Collect blocking errors and warnings per target
5. Returns `BulkApplyPreflightSummary` with per-target `TargetPreflightResult`

The apply confirmation is a single Radzen `DialogService.Confirm` whose **OK button text switches on whether anything is blocked**:

| Situation | `OkButtonText` | `PreflightDecision` returned |
|---|---|---|
| No blocking errors | `"Apply"` | `ApplyAll` |
| One or more targets blocked | `"Apply Compatible"` | `ApplyCompatible` |

The exact string is `"Apply Compatible"` — **not** "Apply Compatible Only", and the unblocked case is `"Apply"`, not "Apply All" (`BulkCustomParmsEditorBase.cs:458` and `:466`). Cancel in either case returns `PreflightDecision.Cancel`.

---

## Draft Persistence

Draft CustomParms are written to `sessionStorage` with a 1-second debounce after every `OnConfigurationChanged` call.

```
sessionStorage key = "{DraftKeyPrefix}_{SourceScenario.Code}"
```

On source selection, the base class calls `RestoreDraftAsync`. If a draft exists, a Radzen confirm dialog asks the user whether to restore or discard it.

Draft is cleared on successful apply (`ClearDraftAsync`).

---

## Navigation Guard

Two mechanisms prevent accidental data loss:

1. **Blazor `RegisterLocationChangingHandler`**: intercepts in-app navigation and shows a Radzen confirm dialog ("Discard unsaved changes?")
2. **Browser `beforeunload`** (JS interop): `navigationGuard.init` / `navigationGuard.setDirtyState` / `navigationGuard.dispose` protect against browser tab close/refresh. Failures in `navigationGuard.init` are logged as warnings but do not break the page.

---

## DI Requirements

The following are injected via `[Inject]` attributes (all required):
- `NotificationService` (Radzen)
- `DialogService` (Radzen)
- `NavigationManager`
- `IValidationService`
- `IConfiguration`
- `IJSRuntime`
- `Serilog.ILogger`

---

## Sources

- `TestAuto.Web\Components\Common\BulkCustomParmsEditorBase.cs`
