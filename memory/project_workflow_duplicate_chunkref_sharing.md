---
name: project_workflow_duplicate_chunkref_sharing
description: Duplicate Workflow copied the CHUNKREF sentinel verbatim so the copy shared config chunk rows with the original — fixed 2026-09-09 in WorkflowService; the workflow MERGE path still has the identical defect
metadata: 
  node_type: memory
  type: project
  originSessionId: e1a360d6-aa1f-48db-a87d-c1cdde9f6e5f
  modified: 2026-09-09T21:28:18.737Z
---

**The bug (fixed).** `RecordCloner.CloneWorkflowWithDetails` copies `ScenarioConfiguration` verbatim. Inline JSON and legacy `BROTLI:`/`GZIP:` values are self-contained so that is correct, but a `CHUNKREF:WorkflowTemplate-<detailCode>:<n>` sentinel names the SOURCE step's chunk group. A duplicated workflow therefore read and wrote the original's rows in `TestAutoScenarioConfiguration`: editing either template silently changed the other, and deleting the source would strand the copy. Caught before damage because the copy's sentinels still carried the 1M template's detail codes.

**Fix** in `WorkflowService.DuplicateWorkflowAsync` (2026-09-09): pre-assign `detail.Code = Guid.NewGuid().ToString()` before creation, then `RehomeClonedScenarioConfigurationAsync` re-persists via `IScenarioConfigStore.PersistAsync(config, ConfigOwnerType.WorkflowTemplate, newCode)`. Non-chunked values pass through untouched. An unresolvable source sentinel THROWS rather than copying it forward — silently re-sharing is the failure being fixed. Same pre-assign pattern `DuplicateScenarioAsync` already used correctly (see [[project_workflow_copy_duplicate_save_bug]]).

Verified after rebuild: 37 steps, zero shared detail codes, zero overlapping chunk group keys, content hash-identical to the original.

**STILL OPEN — the merge path has the same defect.** `Workflows.razor.cs:1156` (workflow merge) clones details with `RecordCloner.CloneRecord` and sets `Code = null`, so merged steps also inherit the source's `CHUNKREF`. Not fixed because that page has no `IScenarioConfigStore` injected — needs DI wiring too. The "Demo of Workload Merge" workflow exists, so the path is in use.

**Why:** any code path that clones a record carrying `ScenarioConfiguration` must re-home chunked values under the new owner code. Check `ConfigChunkSentinel.IsChunked(value)` before copying.
