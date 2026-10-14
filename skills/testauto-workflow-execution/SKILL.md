---
name: testauto-workflow-execution
description: >
  Workflow execution architecture, state machine, and orchestration in TestAuto. Use when
  implementing workflow features, debugging execution issues, ExecuteWorkflowAsync vs
  ExecuteWorkflowExecutionAsync, how WorkflowMonitorJob calls CheckAndProgressWorkflowAsync, why a
  step does not advance, or execution lifecycle via IWorkflowExecutionService — reset, delete, skip,
  resubmit-from-step, and multi-status filtering.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Workflow Execution

> **UI terminology (2026-07)**: the web UI now labels workflows as **"Workloads"** (nav menu, page titles, help text). ALL code identifiers, routes, entities, and config keys remain `Workflow*` / `WorkloadExecution*` — "the Workloads page" = `Workflows.razor`, "Workload Builder" = `WorkflowBuilder.razor`, "Workload Execution" = `WorkflowExecution.razor`.

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: WORKFLOW-KNOWLEDGE-BASE.md (2026-03-16)

---

## Reference files (load on demand)

This file carries the execution model, status flow, service layer, and troubleshooting.
The deep traces live in `references/` and cost nothing until you read one.

| File | Read it when |
|---|---|
| `references/cli-batch-pipeline.md` | A scenario dies between the CLI and the metrics tables, or tuning `serverCount` |
| `references/editor-uis.md` | Changing `WorkflowScenariosEditor` / `WorkflowExecutionEditor`, or an in-flight edit is lost on resubmit |

---

## Key Principle: Unified Execution Path

**ALL scenario executions flow through `IScenarioExecutionService.ExecuteScenarioAsync`**, regardless of source:
- Full workflow run from template
- Manual single-scenario execution from WorkflowBuilder
- Standalone execution from ScenarioEditor

The `isFromWorkflowExecution` flag is the only argument that differs — and it is **log-only**.

> **`isFromWorkflowExecution` does NOT alter control flow.** Every live use is a Serilog template
> argument: `ScenarioExecutionService.cs:200` (`"ExecuteScenarioAsync ENTRY POINT - Scenario: '{ScenarioName}', isFromWorkflowExecution: {IsFromWorkflowExecution}"`)
> and `:209-210`. Nothing branches on it. Whether a run is tracked and advanced is decided by the
> **records**, not the flag: `WorkflowMonitorJob` → `CheckAndProgressWorkflowAsync` walks
> `TestAutoWorkflowExecution` / `…Detail` rows, so a standalone run is untracked because it has no
> execution-detail record — not because the flag is `false`.

| `isFromWorkflowExecution` | Meaning (diagnostic only) |
|---|---|
| `true` (default) | Caller says "this came from a WorkflowExecutionDetail" — shows up in the Seq entry-point log |
| `false` | Set by the back-compat overload `ExecuteScenarioAsync(configuration, executionOptions, enqueueToHangfire)` (`ScenarioExecutionService.cs:122`), which passes an empty `Record` |

---

## Core Entities

### Templates (Design Time)

| Entity | Purpose | Key Fields |
|---|---|---|
| `TestAutoWorkflow` | Reusable workflow template | Code, Name, ExecutionMachine |
| `TestAutoWorkflowDetail` | Step within a template | Workflow (FK), Scenario (FK), ScenarioConfiguration (compressed JSON), ExecutionOrder |

### Executions (Runtime)

| Entity | Purpose | Key Fields |
|---|---|---|
| `TestAutoWorkflowExecution` | Active/completed execution instance | WorkflowTemplate (FK), ExecutionStatus, ExecutionMachine |
| `TestAutoWorkflowExecutionDetail` | Step within an execution | WorkflowExecution (FK), WorkloadExecutionCode, ExecutionStatus, ExecutionOrder |

---

## Execution Status Flow

```
TestAutoWorkflowExecution:
  Pending → Running → Complete / Failed

TestAutoWorkflowExecutionDetail:
  Pending → Running → Complete / Failed
```

---

## Execution Paths

| Path | Entry Point | Orchestration Method | `isFromWorkflow` |
|---|---|---|---|
| 1 — Full workflow from template | WorkflowScenarioManagement "Start Workflow" | `ExecuteWorkflowAsync(workflowCode)` | `true` |
| 2 — Resume existing execution | WorkflowScenarioManagement "Resume Execution" | `ExecuteWorkflowExecutionAsync(executionCode)` | `true` |
| 3 — Single step (existing saved step) | WorkflowBuilder "Run" button | `ExecuteSingleScenarioFromTemplateDetailAsync(detailCode)` | `false` |
| 4 — Single step (unsaved step) | WorkflowBuilder "Run" button | `ExecuteSingleScenarioFromScenarioAsync(scenarioCode)` | `false` |
| 5 — Single step within active execution | WorkflowScenarioManagement step "Run" | `ExecuteSingleScenarioDetailAsync(executionCode, detailCode)` | `true` |

**Paths 3 and 4 are standalone test runs** — WorkflowMonitorJob does not track them.

---

## Service Layer

### `WorkflowOrchestrationService`
**Location**: `TestAuto.Web/Services/WorkflowOrchestrationService.cs`

Key methods:

| Method | Returns |
|---|---|
| `ExecuteWorkflowAsync(workflowCode)` | WorkflowExecution.Code |
| `ExecuteWorkflowExecutionAsync(executionCode)` | WorkflowExecution.Code |
| `ExecuteSingleScenarioDetailAsync(executionCode, detailCode)` | bool |
| `ExecuteSingleScenarioFromTemplateDetailAsync(detailCode)` | WorkloadExecution.Code |
| `ExecuteSingleScenarioFromScenarioAsync(scenarioCode)` | WorkloadExecution.Code |
| `CheckAndProgressWorkflowAsync(executionCode)` — called by monitor | void |
| `StartNextScenarioAsync(execution, detail)` — internal | void |

### `IScenarioExecutionService`
**Interface**: `TestAuto.Shared/Interfaces/IScenarioExecutionService.cs`
**Impl**: `TestAuto.Scenarios/Execution/ScenarioExecutionService.cs`

```csharp
Task<string> ExecuteScenarioAsync(
    Record workflowExecutionDetailRecord,
    ScenarioConfiguration configuration,
    ExecutionOptions? executionOptions = null,
    bool isFromWorkflowExecution = true   // critical flag — defaults to TRUE
);
// Returns: WorkloadExecution.Code (displayed as Job ID)
```

### `WorkflowMonitorJob`
**Location**: `TestAuto.Web/Jobs/WorkflowMonitorJob.cs`
- Hangfire recurring job on the **`scheduled` queue**, cron `*/{N} * * * *` — N = `WorkflowMonitor:IntervalMinutes` config (default **5 minutes**); gated by `FeatureFlags:EnableWorkflowMonitor`; registered in `WebModuleRegistrar.RegisterWebRecurringJobs`
- Calls `CheckAndProgressWorkflowAsync` for every Running workflow execution
- Updates `TestAutoWorkflowExecutionDetail.ExecutionStatus` from `WorkloadExecution.ExecutionStatus`
- When no details are Running AND Pending details remain → calls `StartNextScenarioAsync`
- When all details Complete/Failed → marks `TestAutoWorkflowExecution` as Complete/Failed

#### Fail-fast: one Failed step stops the whole workflow

`CheckAndProgressWorkflowAsync` evaluates `hasFailed` **before** it considers starting the next step
(`WorkflowOrchestrationService.cs:439-451`):

```csharp
var hasFailed = details.Any(d => string.Equals(d.ExecutionStatus, "Failed", StringComparison.OrdinalIgnoreCase));
// Rule: If any scenario failed, do NOT start remaining scenarios. Mark workflow Failed and stop.
if (hasFailed)
{
    var failedDetail = details.First(d => string.Equals(d.ExecutionStatus, "Failed", StringComparison.OrdinalIgnoreCase));
    await _workflowExecutionService.UpdateExecutionStatusAsync(execution.Code, "Failed", endTime: DateTime.UtcNow, …);
}
```

So remaining `Pending` steps are **never** started after any step fails — the parent execution is
stamped `Failed` with an end time and the monitor stops progressing it. Recovery is the
edit-then-`ResubmitFromScenarioAsync` loop (which resets the tail steps *and* the parent back to
Pending), not "wait for the monitor". Comparison is case-insensitive throughout.

---

## Execution Management & Reset (`IWorkflowExecutionService`)

Distinct from `WorkflowOrchestrationService` (which *runs* workflows via the execution paths above),
**`IWorkflowExecutionService`** (`TestAuto.Web/BusinessLogic/Services/WorkflowExecutionService.cs`) owns
the **CRUD + lifecycle management** of execution records derived from templates — create, query, reset,
delete, skip, and re-run individual steps. Every method returns `ServiceResult<T>`.

| Method | Purpose |
|---|---|
| `CreateExecutionFromTemplateAsync(templateCode, options?)` | Materialize a new `TestAutoWorkflowExecution` (+ details) from a template |
| `GetExecutionsByStatusesAsync(statuses)` | Fetch executions filtered by **one or more** statuses; null/empty = no filter (all). Replaces paired single-status calls |
| `GetExecutionAsync` / `GetExecutionsForTemplateAsync` / `GetExecutionsAsync` / `GetExecutionDetailsAsync` | Single / per-template / filtered / detail reads |
| `ResetExecutionAsync(executionCode)` | Reset the execution **and all its details** to Pending; clears start/end times, error messages, and workload-execution references. Re-runnable from scratch |
| `ResetScenarioAsync(executionDetailCode)` | Reset a **single** detail to Pending (clears its times/error/workload ref) |
| `ResubmitFromScenarioAsync(executionCode, fromOrder)` | Reset the step at `fromOrder` **and every later step** (`ExecutionOrder >= fromOrder`) to Pending — clears times/error/workload ref AND scrubs the `ScenarioEnvironment.WorkloadExecution` pointer baked into the stored compressed config, so the re-run creates a fresh WorkloadExecution instead of recording against the old one. Sets the parent execution back to Pending (clears end time/error) so the resume path (`ExecuteWorkflowExecutionAsync`, which only acts on Pending executions) re-engages from the earliest Pending step. Steps before `fromOrder` keep their status. Fails if any affected step is Running. Returns `ServiceResult<int>` = number of step records reset |
| `SkipScenarioAsync(detailCode)` | Mark a single detail **Skipped** (won't execute) |
| `SkipAllRemainingAsync(executionCode)` | Skip all remaining Pending details; returns count skipped |
| *(on-demand single-detail execution)* | **Not on this service** — use `WorkflowOrchestrationService.ExecuteSingleScenarioDetailAsync(executionCode, detailCode)` (execution path 5 above) |
| `DeleteExecutionAsync(executionCode)` | Cascading delete: detail records first, then the parent execution. **Underlying `WorkloadExecution` runs and their metrics are NOT removed** |
| `UpdateExecutionStatusAsync` / `UpdateExecutionDetailStatusAsync` | Status/time/error mutators used by the monitor + manual actions |

> `ResetExecutionAsync` writes the detail records **in chunks** rather than one-by-one — relevant when an
> execution has many steps. `ResubmitFromScenarioAsync` does the same (chunks of 25).

### Multi-status filter UI (`WorkflowExecution.razor`)

The execution-listing page filters on a **list** of statuses (`FilterStatuses : List<string>`), not a single
value. The status dropdown is `Multiple="true"` with an **"All Status"** option that is **mutually exclusive**
with specific statuses — `OnStatusFilterChanged` clears the specifics when "All Status" is picked (and vice
versa), then `LoadWorkflows` calls `GetExecutionsByStatusesAsync(effectiveStatuses)`. Reset/Delete row actions
are gated by `CanResetWorkflow` / `CanDeleteWorkflow` on the execution's current status.

---

## Configuration Storage

ScenarioConfiguration is persisted via **`IScenarioConfigStore`** (injected as `Store` in the editors) — inline JSON when small, CHUNKREF-chunked when large:

```csharp
var stored = await Store.PersistAsync(config, ConfigOwnerType.WorkflowTemplate, ownerCode);
var config = await Store.LoadAsync(storedValue);  // also reads legacy BROTLI:/GZIP: blobs (TemplateStorage is now only the legacy read codec)
```

See [[testauto-scenario-config-store]] for owner types and the CHUNKREF sentinel.

**Resolution order when loading**:
1. `TestAutoWorkflowDetail.ScenarioConfiguration` (step-specific override)
2. If empty → `TestAutoScenarios.ScenarioData` via `TestAutoWorkflowDetail.Scenario` FK

---

## Service Registration

All business logic services register in `TestAuto.Web/AutoRegistration/WebModuleRegistrar.cs`, **never in `Program.cs`**.

---

## Troubleshooting

### Scenario stuck in "Running"

```sql
SELECT Code, ExecutionStatus, StartTime, EndTime, ErrorMessage
FROM WorkloadExecution
WHERE Code = '<WorkloadExecutionCode from TestAutoWorkflowExecutionDetail>';
```

**Root causes**:
1. `WorkloadExecution` never created → `IScenarioExecutionService.ExecuteScenarioAsync` failed
2. `WorkloadExecution.ExecutionStatus` never updated → Hangfire job crashed
3. `WorkflowMonitorJob` not running → check Hangfire Recurring Jobs dashboard

### Workflow never advances to next step

```sql
SELECT ExecutionOrder, ExecutionStatus, WorkloadExecutionCode, StartTime, EndTime
FROM TestAutoWorkflowExecutionDetail
WHERE WorkflowExecution = '<ExecutionCode>'
ORDER BY ExecutionOrder;
```

**Check**: `WorkloadExecutionCode` is populated; WorkflowMonitorJob is scheduled (default: every 5 minutes); next detail is in Pending status.

### "Workflow is targeted for machine X, not this machine"

```sql
SELECT ExecutionMachine FROM TestAutoWorkflowExecution WHERE Code = '<ExecutionCode>';
```

Resolution: run on the target machine, OR create a new execution on the current machine.

### "Scenario not found" in WorkflowBuilder

**Root causes**:
1. Scenario assembly not in Plugins directory
2. `ScenarioConfiguration.ScenarioName` doesn't match the registered class name
3. `ScenarioData` empty or corrupted

Check Seq startup logs: *"Scanning X assemblies for IScenario implementations"*

---

## Sources

- `{VaultDocsRoot}\speed-merchants\architecture\WORKFLOW-KNOWLEDGE-BASE.md`
- `{VaultDocsRoot}\speed-merchants\architecture\WORKFLOW-QUICK-REFERENCE.md`
- `AGENTS.md` (Learned Workspace Facts section) — *source removed 2026-05-31; content migrated to work-ai skills/memory, this skill is now canonical*
- `TestAuto\Documentation\FlowOfRunningAScenario.md`
- `TestAuto\Documentation\OverviewOfHowAScenarioRunsStartingWithConfigToBatch.md`
- `TestAuto.Web\BusinessLogic\Services\IWorkflowExecutionService.cs`
- `TestAuto.Web\BusinessLogic\Services\WorkflowExecutionService.cs`
- `TestAuto.Web\Components\Pages\WorkflowExecutionEditor.razor(.cs)`

---

## CLI-to-Batch Execution Pipeline

The eight-stage trace from `VerbRunTestOptionsHandler` through
`ScenarioExecutionService` → base-class hierarchy → `ScenarioDispatcher.Dispatch` →
`BatchJobOrchestrator` (Hangfire batch mechanics) → `BatchProcessor` →
`MetricBatchSummaryAggregator` → `MetricsPersistenceJob`, plus `serverCount`
concurrency and the end-to-end trace summary:
**`references/cli-batch-pipeline.md`**.

Read it when a scenario dies somewhere between the CLI and the metrics tables, when
tuning `serverCount`, or when adding a stage to the pipeline.

---

## Workflow editing UIs

`WorkflowScenariosEditor` (ScenarioDetailItem view model, the `InMemoryEditorResult`
embedded-editing pattern, QuickEdit bulk-apply, card vs grid via `ScenarioListEditor`,
per-scenario operations, `NormalizeStepType`, save strategy) and
`WorkflowExecutionEditor` (running-step protection, `OpenScenarioEditorDialog`,
edit-before-resubmit): **`references/editor-uis.md`**.

Read it when changing either editor, or when an in-flight edit does not survive a
resubmit.
