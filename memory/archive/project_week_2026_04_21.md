---
name: Speed-merchants work completed week of 2026-04-21
description: UID-to-Code refactor, WorkflowExecution auto-refresh fixes, UtilityTypeConstants centralization, error message enhancement, Monitor scoring investigation
type: project
originSessionId: f5d73f81-507f-4c6e-8fba-934deccd17d9
---

## Completed Work — Week of 2026-04-21

### 1. UID → Code Refactor (Matching Metrics)

The Profisee REST API does not return `[$UID]` (Guid). All matching metric collection code was refactored from UID to Code (string).

**Files changed:**

- `TestAuto.Matching/Interfaces/IMatchingMetricsCollector.cs` — signature: `Guid recordUid` → `string recordCode`
- `TestAuto.Matching/Helpers/MatchingMetricsCollector.cs` — SQL queries changed from `[$UID]` to `[Code]`, method params changed
- `TestAuto.Matching/Scenarios/UnifiedMatchingScenario.cs` — removed `ResolveRecordUidAsync`, passes Code directly
- `TestAuto.Matching/Services/MatchingOperationExecutor.cs` — passes Code instead of UID
- `Testing.SpeedMerchants.Integration/Tests/Matching/MatchingMetricsCollectorTests.cs` — all tests updated for string codes

**Why:** REST API never returns UIDs; Code is the correct identifier for record lookups.

### 2. WorkflowExecution Auto-Refresh Fix

The modal showing workflow execution scenario details refreshed visually (countdown timer worked) but the modal content didn't update. Root cause: `LoadWorkflows()` replaced the `Workflows` list but `SelectedWorkflow` still pointed to the old object reference.

**Fix:** After `LoadWorkflows()`, re-select `SelectedWorkflow` from the refreshed list by matching on `Code`.

**File:** `TestAuto.Web/Components/Pages/WorkflowExecution.razor.cs`

### 3. UtilityTypeConstants Centralization

All step type strings (Http, CURL, SQL, PowerShell, CommandLine, CLI, CLU, ConnEx, Monitor, etc.) were centralized into `TestAuto.Shared/Constants/UtilityTypeConstants.cs`. Previously raw strings were scattered throughout the codebase.

**Files changed:**

- `TestAuto.Shared/Constants/UtilityTypeConstants.cs` — new constants class with all step type strings
- `TestAuto.Utilities/Services/UtilityOrchestrator.cs` — ScriptKey validation now uses constants

**Why:** User feedback — step type strings should have a single source of truth.

### 4. Error Message Enhancement (UtilityOrchestrator)

The error `"Step 1 failed: "` had no useful detail — empty `ErrorMessage` after the colon. Enhanced to include step identity and cascade through error sources.

**File:** `TestAuto.Utilities/Services/UtilityOrchestrator.cs` (line ~246)

Before: `$"Step {i + 1} failed: {stepResult.ErrorMessage}"`
After: Includes `step.Description ?? step.ScriptKey ?? step.Type` as label, and cascades `ErrorMessage → StandardError → Exception.Message → fallback`.

**Test updated:** `Testing.SpeedMerchants.Unit/Tests/Utilities/Services/UtilityOrchestratorTests.cs` — assertion relaxed to match new format.

### 5. Monitor Scoring Investigation (Unresolved)

Database query on `[monitor].[tActivityDetails]` found ZERO "Scoring Started"/"Scoring Finished" detail records. Indexing, Clustering, and Survivorship markers all exist. User claims markers were produced and visible in monitor logs. Discrepancy unresolved — may need to revisit on next matching run.

**How to apply:** On next matching run, check logged distinct detail names (MonitorActivityCollector.cs lines ~300-302) to see if scoring markers appear under different names.
