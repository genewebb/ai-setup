---
name: testauto-scenario-reorder
description: >
  ScenarioReorder.Apply<T> — the shared pure-static reorder math for scenario list editors
  in TestAuto.Web. Use when implementing or modifying move up/down/top/bottom/to-position
  operations on a scenario list, multi-select block moves, pinned (completed/running)
  scenarios that must stay anchored at the front, or extending the reorder UI in
  WorkflowScenariosEditor or WorkflowExecutionEditor.
---

Repo: speed-merchants (paths below are repo-relative)

# Scenario Reorder Math (`ScenarioReorder.Apply<T>`)

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: `TestAuto.Web\Components\Common\ScenarioReorder.cs`

`ScenarioReorder` is the single shared implementation of list-reorder semantics for the
scenario editors. It replaced the per-item `MoveScenarioUp/Down/Top/Bottom` loops (commit
f8a2453a, "scenario movements" enhancement). **Never reimplement move logic in an editor —
call `Apply` and renumber.**

## API

```csharp
public static class ScenarioReorder
{
    public enum Op { Up, Down, Top, Bottom, ToPosition }

    public static List<T> Apply<T>(
        IReadOnlyList<T> items,          // MUST already be in current execution order
        Func<T, string?> codeOf,         // stable identity (scenario Code)
        ISet<string> selectedCodes,      // multi-select supported
        Op op,
        int position = 1,                // 1-based, only for Op.ToPosition
        Func<T, bool>? isPinned = null)  // null → nothing pinned
        where T : class
}
```

Pure function: returns the new order. **The caller renumbers `ExecutionOrder` and marks
items dirty afterward** — `Apply` does neither.

## Semantics

| Behavior | Rule |
|---|---|
| Multi-select | The selection always moves as a **single block**, preserving the selected items' relative order. |
| Pinned items | `isPinned` items are fixed anchors kept at the **front** of the list. They never move, and non-pinned items can never be placed above them. A selected pinned item is silently ignored. |
| `Op.Up` / `Op.Down` | Block moves one slot relative to the unselected movable items (computed from the first/last selected index). |
| `Op.Top` / `Op.Bottom` | Block goes to the start/end of the **movable region** (i.e., just below the pinned anchors for Top). |
| `Op.ToPosition` | `position` is a **1-based absolute position across the full list**; it is converted to a slot within the movable region (`position - pinnedCount - 1`) and **clamped** — a position inside the pinned region lands just below the anchors. |
| Empty selection | Returns the list unchanged. |

## Who pins what

| Editor | `isPinned` | Why |
|---|---|---|
| `WorkflowExecutionEditor` | completed/running scenarios | Finished or in-flight steps must never move, and pending steps can never jump above them. |
| `WorkflowScenariosEditor` (template) | `null` | Templates have no execution state — everything is movable. |

## Usage pattern

```csharp
var reordered = ScenarioReorder.Apply(
    ScenarioDetailItems,
    s => s.Code,
    SelectedCodes,
    ScenarioReorder.Op.ToPosition,
    position: targetPosition,
    isPinned: s => IsCompletedOrRunning(s));   // execution editor only

// Caller's responsibility: renumber + dirty
for (int i = 0; i < reordered.Count; i++)
{
    if (reordered[i].ExecutionOrder != i + 1)
    {
        reordered[i].ExecutionOrder = i + 1;
        MarkDirty(reordered[i]);
    }
}
```

## Related

- [[testauto-scenario-display]] — the ScenarioCard/badge display layer these editors render
- [[testauto-workflow-execution]] — execution lifecycle the pinning rules protect

## Sources

- `TestAuto.Web\Components\Common\ScenarioReorder.cs`
- `TestAuto.Web\Components\Pages\WorkflowScenariosEditor.razor.cs` (`ReorderSelected` / `MoveSelected*`)
- `TestAuto.Web\Components\Pages\WorkflowExecutionEditor.razor.cs` (pinned anchors)
