---
name: testauto-bounded-parallel-fanout
description: >
  The SemaphoreSlim(10) + Task.WhenAll bounded parallel fan-out convention for eliminating
  sequential 1+N gateway calls in TestAuto. Use when a list page, controller, or bulk editor
  loops per-item REST/store calls (config resolution, counts, detail loads, validations),
  when parallelizing any per-record gateway round-trip, or when populating a Dictionary
  cache from parallel work (the tuple-then-populate rule — Dictionary is not safe for
  concurrent writes).
---

Repo: speed-merchants (paths below are repo-relative)

# Bounded Parallel Fan-Out (SemaphoreSlim + Task.WhenAll)

TestAuto's standing convention for turning a sequential 1+N gateway loop (one list call + N
per-item calls) into a bounded parallel fan-out. Introduced during the 2026-07 list-page
performance work (Scenarios / Workflows / Workflow Execution loads were sequential per-item
awaits); now used across list pages, controllers, and bulk editors.

## When to Use

- "This list page is slow — it awaits one gateway call per row"
- "Parallelize these per-scenario config loads / per-workflow counts / per-target validations"
- "How do I safely fill a cache Dictionary from parallel tasks?"
- Any loop of independent `IRestClient` / config-store / facade calls per item

## The Pattern

```csharp
// Scenarios.razor.cs:174-200 (canonical exemplar) — resolve every scenario's stored config
_scenarioConfigCache.Clear();
var configSemaphore = new SemaphoreSlim(10);           // cap concurrent gateway calls at 10
var configTasks = all
    .Select(s => new { Key = s.Code ?? s.Name ?? string.Empty, Stored = s.SafeGetValue<string>("ScenarioData") })
    .Where(x => !string.IsNullOrEmpty(x.Key))
    .Select(async x =>
    {
        await configSemaphore.WaitAsync();
        try
        {
            var cfg = string.IsNullOrWhiteSpace(x.Stored) ? null : await Store.LoadAsync(x.Stored);
            return (x.Key, Config: cfg);               // return a tuple — do NOT write shared state here
        }
        finally
        {
            configSemaphore.Release();                 // always in finally
        }
    });
var resolvedConfigs = await Task.WhenAll(configTasks);
foreach (var (key, cfg) in resolvedConfigs)            // populate single-threaded AFTER WhenAll
    _scenarioConfigCache[key] = cfg;
```

## Rules

| Rule | Why |
|---|---|
| Cap with `new SemaphoreSlim(10)` | Bounds concurrent gateway round-trips; 10 is the repo-wide convention |
| `WaitAsync()` … `try/finally { Release(); }` | A faulted task must not leak a slot |
| Tasks return **tuples/values**, never write shared state | The fan-out runs concurrently |
| Populate `Dictionary` caches **single-threaded after `Task.WhenAll`** | Plain `Dictionary` is not safe for concurrent writes — this is the race the pattern exists to avoid (the code comments state it verbatim) |
| `Task.WhenAll` result order mirrors input order | Duplicate keys resolve last-wins exactly like the old sequential loop; status/order-sensitive callers rely on this |

## Where It's Used (evidence)

| Site | Fan-out |
|---|---|
| `Components/Pages/Scenarios.razor.cs:178-200` | Per-scenario config resolution (CHUNKREF `Store.LoadAsync`) into `_scenarioConfigCache` |
| `Components/Pages/Workflows.razor.cs:228-242` | Per-workflow scenario counts |
| `Components/Pages/WorkflowBuilder.razor.cs:143-164` | Per-step config resolution into cache |
| `Components/Pages/WorkflowExecutionEditor.razor.cs:264-280` | Per-detail config resolution into cache |
| `Components/Pages/WorkflowExecution.razor.cs:159-175` | Per-execution detail loads |
| `Controllers/ExecutionControlController.cs:291-306` | Per-status execution queries (order-preserving) |
| `Components/Common/BulkCustomParmsEditorBase.cs:378-426` | Bulk-apply per-target work |
| `Components/Controls/MatchingBulkEditPanel.razor.cs:102` (`resolveSemaphore`) + `:185` (`applySemaphore`) | Bulk matching edit — one fan-out to resolve each target's config, a second to apply |
| `Components/Controls/StepTokenBulkEditPanel.razor.cs:104` (`resolveSemaphore`) + `:176` (`applySemaphore`) | Same two-phase resolve/apply shape for bulk step-token edits |

Plain `Task.WhenAll` (no semaphore) is used for small fixed fan-outs of 2–5 known tasks
(`Index.razor.cs:195`, `Metrics.razor.cs:39`, `ScenarioCompare.razor.cs:88`,
`ConnExResourcePageBase.cs:99`, `Services/Logs/LogDetailService.cs:39`) — the semaphore is for
per-item fan-outs whose width scales with data.

## `IRestClient` is NOT safe for concurrent use — build one per task

Any bounded fan-out doing REST work must construct a **fresh `IRestClient` inside each task**, never share
one across the fan-out.

The reason is a shared mutable builder: a client's three facades share **one** `PathAndQueryBuilder`
(`SyncEndpointFactory.cs:77-80`), whose `pathSegments` / `parameters` are mutable *instance* fields
(`PathAndQueryBuilder.cs:14-17`). Two concurrent tasks therefore race between configuring the builder and
calling `Build()`, and emit **corrupted request paths**. Observed live in Production Sync: requests silently
lost their `PageSize`, which produced spurious "Blocked" rows — a data-looking bug with an entirely
mechanical cause.

```csharp
// ProductionSync.razor.cs:432-435 — fresh client inside the task, not captured from outside
var client = EndpointFactory.Create(endpoint);
```

### Sanctioned exception to "tasks return tuples, never write shared state"

Mutating a **per-item object the task exclusively owns** (e.g. an `EntityRow` bound to a live-updating grid)
is safe and is exactly what a progress-reporting UI needs. The ban is on writes to a **shared collection** —
a `Dictionary` or `List` touched by more than one task.

## Anti-Patterns

| Don't | Do |
|---|---|
| `foreach (var s in all) { cache[k] = await Load(s); }` | The 1+N sequential loop this pattern replaces |
| Unbounded `all.Select(async …)` + `WhenAll` | Hundreds of concurrent gateway calls; always cap with the semaphore |
| Writing `cache[key] = …` inside the parallel lambda | Dictionary corruption under concurrency — return tuples, populate after |
| `ConcurrentDictionary` just to dodge the race | The convention is tuple-then-populate; keeps the cache type and last-wins semantics unchanged |

## Related

- [[bulk-custom-parms-editor-base]] — the bulk-editor preflight uses this same pattern
- Memory `project_list_page_nplus1_parallelization` — origin of the list-page work
- `testauto-connex-service` / `testauto-matching-scenarios` — other SemaphoreSlim uses with
  different caps (`ConcurrentThreads`) for in-scenario parallelism

## Sources

- `TestAuto.Web\Components\Pages\Scenarios.razor.cs` (lines 174–200)
- `TestAuto.Web\Components\Pages\Workflows.razor.cs` (lines 228–242)
- `TestAuto.Web\Components\Pages\WorkflowBuilder.razor.cs` (lines 143–164)
- `TestAuto.Web\Components\Pages\WorkflowExecutionEditor.razor.cs` (lines 264–280)
- `TestAuto.Web\Components\Pages\WorkflowExecution.razor.cs` (lines 159–175)
- `TestAuto.Web\Controllers\ExecutionControlController.cs` (lines 291–306)
- `TestAuto.Web\Components\Common\BulkCustomParmsEditorBase.cs` (lines 378–426)
- `TestAuto.Web\Components\Controls\MatchingBulkEditPanel.razor.cs` (lines 102, 185)
- `TestAuto.Web\Components\Controls\StepTokenBulkEditPanel.razor.cs` (lines 104, 176)
