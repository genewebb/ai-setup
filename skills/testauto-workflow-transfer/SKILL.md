---
name: testauto-workflow-transfer
description: >
  Cross-machine workflow transfer (IWorkflowTransferService / WorkflowBundle) — exports a whole
  workflow to a self-contained portable JSON bundle and re-imports it as a new workflow elsewhere.
  Use when moving or replicating a workflow between TestAuto instances, building or importing a
  WorkflowBundle, the Workflows page import/export UI, or how step configs are resolved on export and
  re-persisted under new codes on import. Distinct from testauto-workflow-export.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Workflow Transfer

> **UI terminology (2026-07)**: the web UI now labels workflows as **"Workloads"** (nav menu, page titles, help text). ALL code identifiers, routes, entities, and config keys remain `Workflow*` / `WorkloadExecution*` — "the Workloads page" = `Workflows.razor`, "Workload Builder" = `WorkflowBuilder.razor`, "Workload Execution" = `WorkflowExecution.razor`.

`IWorkflowTransferService` makes a workflow **portable between machines**. `BuildBundleAsync` serializes a workflow and *all* its step configurations into a self-contained `WorkflowBundle` (a plain JSON DTO), and `ImportBundleAsync` recreates that workflow on a different TestAuto instance — minting brand-new codes and re-persisting every step's config under the new owner.

This is **not** the same as [[testauto-workflow-export]]. That skill's `WorkflowExportService` writes scenarios to files or creates standalone `TestAutoScenarios` records and has **no import path**. `WorkflowTransferService` is a separate, round-trippable bundle service: export → carry the bundle to another machine → import.

## When to Use

- "Move this workflow from the demo box to prod."
- "Export a workflow as a bundle / import a workflow bundle."
- "Replicate a workflow on another machine."
- "Working on the import/export buttons on the Workflows page."
- "Why does importing a bundle create a new workflow code instead of reusing the old one?"
- "Export failed: 'step X could not be resolved — chunked config missing'."

## Transfer vs Export — pick the right service

| | `WorkflowTransferService` (this skill) | `WorkflowExportService` ([[testauto-workflow-export]]) |
|---|---|---|
| Output | one portable `WorkflowBundle` JSON | files on disk **or** new TestAutoScenarios records |
| Re-import | **yes** — `ImportBundleAsync` | none (export-only) |
| Cross-machine | yes — bundle is fully self-contained | no — local artifacts |
| Creates a workflow | yes — brand-new on import | no |
| Config in output | fully resolved raw JSON, **never** a CHUNKREF | decompressed / re-serialized inline |

## The Bundle Shape

```csharp
public sealed class WorkflowBundle
{
    public string SchemaVersion { get; set; } = "1.0";
    public string WorkflowName { get; set; } = "";
    public string? Category { get; set; }
    public string? Tags { get; set; }
    public string? Description { get; set; }
    public List<WorkflowBundleStep> Steps { get; set; } = new();
}

public sealed class WorkflowBundleStep
{
    public int ExecutionOrder { get; set; }
    public string? ScenarioDisplayName { get; set; }
    public string? ScenarioDisplayDescription { get; set; }
    public string? Category { get; set; }
    public string? Tags { get; set; }
    public string? ProfiseeVersion { get; set; }
    public string ScenarioConfigurationJson { get; set; } = ""; // fully-resolved raw JSON, never "CHUNKREF:"
}
```

**Invariant:** `ScenarioConfigurationJson` is always the fully expanded JSON. Chunked/compressed references are resolved at export time so the bundle is self-contained and portable.

## Export — `BuildBundleAsync(workflowCode)`

1. Load the workflow record (`GetWorkflowAsync`); fail if not found.
2. Fill the bundle header (name, category, tags, description).
3. Enumerate `TestAutoWorkflowDetail` records filtered by workflow code, ordered by `ExecutionOrder`.
4. For each detail, resolve its stored config to full raw JSON via **`IScenarioConfigStore.ResolveRawAsync`** (see [[testauto-scenario-config-store]]).
   - **Each resolve is wrapped in try/catch.** A dangling CHUNKREF throws `InvalidOperationException`; the step's failure is collected with its display name + execution order.
5. **All-or-nothing:** if *any* step fails to resolve, return `Failure` with a summary naming each broken step — **no partial bundle** is produced. The caller learns exactly which step needs a re-save/re-import.

## Import — `ImportBundleAsync(bundle)` (always-new semantics)

Import never reuses old identifiers. It mints a fresh workflow and fresh detail codes:

1. Validate (non-null bundle, ≥1 step, non-empty `WorkflowName`).
2. `CreateWorkflowAsync` — the **platform assigns the new workflow code** (use the returned code, not anything from the bundle).
3. For each step in `ExecutionOrder`:
   - Generate a new `detailCode = Guid.NewGuid()`.
   - Deserialize `ScenarioConfigurationJson` → `ScenarioConfiguration` (per-step try/catch; null/blank → error).
   - **Re-persist** via `_store.PersistAsync(config, ConfigOwnerType.WorkflowTemplate, detailCode, ct)` — this re-chunks the config under the *target* machine's own codes. The stored value (inline JSON or a fresh CHUNKREF) goes into the detail's `ScenarioConfiguration`.
   - Build the `TestAutoWorkflowDetail` record (workflow = new code, ExecutionOrder, display fields, etc.).
4. Batch-create all detail records with `CreateRecordsWithDetailAsync`; **HTTP 207 multi-status is treated as success** (partial-success semantics), other non-success codes are collected as errors.
5. Return the new workflow code; if any step failed, return `Failure` with a per-step summary (the workflow was still created).

**Config ownership re-binding:** on export the config belonged to the source detail's chunk group; on import it is re-persisted under `WorkflowTemplate-{newDetailCode}`, so the chunk store on the target machine owns fresh chunks keyed to the new codes. This is why import is always-new rather than an in-place overwrite.

## DI Registration

```csharp
services.AddScoped<IWorkflowTransferService, WorkflowTransferService>();
```

Constructor deps: `IWorkflowService`, `Func<RestSubjectArea, IRestClient>` (uses `RestSubjectArea.ScenarioMgt`), `IScenarioConfigStore`, `Serilog.ILogger`.

## Pitfalls

| Pitfall | Reality |
|---|---|
| Expecting import to preserve the original workflow/detail codes | Import is always-new — the platform assigns a new workflow code and every detail gets a fresh GUID. |
| Treating a 207 on the detail batch as a failure | 207 multi-status is accepted as success. Only non-207 non-success codes are errors. |
| Assuming a bundle exports partially when a step is broken | `BuildBundleAsync` is all-or-nothing — one dangling CHUNKREF fails the whole export with a per-step reason. |
| Confusing this with WorkflowExportService | Different service, different output, no overlap. See the table above and [[testauto-workflow-export]]. |
| Bundle carrying CHUNKREF/compressed values | It never does — configs are fully resolved on export. If you see a CHUNKREF in a bundle, something bypassed `BuildBundleAsync`. |

## Sources

- `TestAuto.Web\Services\WorkflowTransfer\WorkflowTransferService.cs`
- `TestAuto.Web\Services\WorkflowTransfer\IWorkflowTransferService.cs`
- `TestAuto.Web\Services\WorkflowTransfer\WorkflowBundle.cs`
- `TestAuto.Web\Components\Pages\Workflows.razor` + `Workflows.razor.cs` (import/export UI)
- `TestAuto.Web\AutoRegistration\WebModuleRegistrar.cs` (DI)
- `Testing.SpeedMerchants.Unit\Web\Services\WorkflowTransfer\WorkflowTransferServiceTests.cs`
