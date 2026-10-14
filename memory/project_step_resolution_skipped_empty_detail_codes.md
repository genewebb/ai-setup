---
name: project-step-resolution-skipped-empty-detail-codes
description: "Root cause — workflow {{STEP:N}} tokens never resolve because detail-code collection returns empty, silently skipping WorkloadExecution pre-creation"
metadata: 
  node_type: memory
  type: project
  originSessionId: ceb93e3d-a365-4bf9-bc1a-c28cbb3b5ebb
---

Confirmed 2026-06-10 (logs+DB+code). When a workflow execution is created from a template via `CreateExecutionFromTemplateAsync` (TestAuto.Web/BusinessLogic/Services/WorkflowExecutionService.cs), `{{STEP:N}}` step-reference tokens in scenario CustomParms are **silently left literal** in the stored config. At runtime a scenario writes the literal `{{STEP:N}}` to a domain-based attribute → Profisee **error 8617** (e.g. MatchingSnapshotCaptureScenario writing `UnifiedMatchingScenarioWorkloadExecution`).

**Causal chain:** detail records ARE created in MDM, but `RestClient.CreateRecordsWithDetailAsync` (RestClient.cs:275) returns `IsSuccess=true` with **empty `CreatedRecordCodes`** (the wrapper re-wraps `raw.ResponseContent` under a new `data` JProperty and the codes don't survive — same envelope-mangling noted at MatchingSnapshotCaptureScenario.cs:345 for the `errors` block). → `createdDetailCodes` is empty ("Created 0 detail records") → `PreCreateWorkloadExecutionsForDetailsAsync` bails at its "No detail codes provided" guard → 0 WorkloadExecutions pre-created (all detail `WorkloadExecution` columns NULL) → step→WE map never built → Pass-2 `ResolveStepReferencesForDetailsAsync` never rewrites tokens.

**Key properties:**
- Resolution is **create-time, one-shot**. `ResetExecutionAsync` nulls WE codes + flips to Pending but NEVER re-resolves and never touches ScenarioConfiguration. So a baked-in literal token survives every reset+rerun; only delete+recreate re-runs resolution.
- Affects EVERY workflow using `{{STEP:N}}`, not just matching. Step references are not inherently broken — they just never got a chance to resolve.
- Diagnostic tell: SEQ log "Created 0 detail records for workflow X. Starting WorkloadExecution pre-creation..." + Warning "No detail codes provided for WorkloadExecution pre-creation". (Workflow's own "Clear Logging Table"/"Clear Monitor Logs" steps wipe SEQ mid-run, so inspect a queued-but-not-started execution.)

**Fix landed 2026-06-10 (error handling):** `CreateExecutionDetailRecordsAsync` now returns `ServiceResult<bool>` and hard-fails when a chunk reports `!IsSuccess`, has a non-empty `data.Errors` (catches 207/8617 from a missing Workload/Scenario domain value), or returns fewer codes than records sent. On failure it logs the underlying error and `CreateExecutionFromTemplateAsync` marks the half-created execution **Failed** (with the error message) and returns a Failure ServiceResult instead of a misleading Pending execution. The prior code explicitly treated a failed/empty create as non-fatal ("fallback to on-demand WE"), which is what hid it. PreCreate's empty-list guard bumped Warning→Error. NOTE: the underlying trigger was the two new Connect scenarios not being registered in the Workload/Scenario tables — user adds those rows separately. (A re-query of detail codes via `GetExecutionDetailsAsync` was considered but not needed once the create is validated.)

**Hardened broadly 2026-06-10:** the swallow-the-207 pattern existed in ~8 `CreateRecordsWithDetailAsync` callers (WebUiRepository ×2, Workflows.razor, WorkflowScenariosEditor ×2, WorkflowExecutionEditor, WorkflowBuilder ×3 — the last three were fire-and-forget with the response discarded). Fixed with a reusable validator: **`TestAuto.Shared/Rest/CreatedRecordsResponseExtensions.ValidateCreate(expectedCount)`** → `CreateRecordsOutcome{IsSuccess,CreatedCodes,ErrorMessage}`. It fails when transport not OK, `Data.Errors` non-empty (207/8617), or codes returned < expected. **Use `response.ValidateCreate(n)` for any bulk create instead of re-checking `IsSuccess`/`==207` by hand.** (Left `MatchingOperationExecutor`/`BatchLoadStrategy` — they gate on CreatedRecordUids + record errors into metrics.)

Related: [[reference_scenariomgt_db]], step-reference-resolution skill, testauto-workflow-execution skill. Orthogonal cleanup option: matching snapshot/results correlation can use `UnifiedMatchingApiExecutionRunProfile` (its own modeled entity; nothing joins on the WE pointer) instead of the `{{STEP:N}}` pointer.
