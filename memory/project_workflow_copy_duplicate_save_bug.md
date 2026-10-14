---
name: project_workflow_copy_duplicate_save_bug
description: "Edit Workflow Scenarios \"1 unsaved won't clear\" after Save All — copy scenario didn't get a new code; create succeeded server-side but IsNew never cleared"
metadata: 
  node_type: memory
  type: project
  originSessionId: fd088159-8130-4a8c-a51e-d77f0a68499b
---

**Symptom:** On *Edit Workflow Scenarios* (`WorkflowScenariosEditor`), duplicating a scenario then pressing **Save All Changes** left the badge stuck at "1 unsaved" while a green "Saved successfully" toast also showed. Confirmed on workflow 10000154 "Connect Export Test" (copying scenario 4).

**Root cause (verified via Seq + speedmerchants DB, 2026-07-01):**
1. `CopyScenarioAsync` set `Code = string.Empty`, and `BuildWorkflowDetailRecordAsync` guarded with `scenario.Code ??= Guid.NewGuid()` — but `??=` only fires on **null**, not `""`, so the guard misfired.
2. The create **succeeded server-side** (row written, client GUID code) but the UI treated it as failed (relied on the response's `createdRecordCodes` mapped by index, which came back empty) → `IsNew` never cleared → badge pinned.
3. Every re-save re-submitted the same pre-assigned code → gateway **8603 "Cannot create... already exists"**, or spawned another orphan. DB ended up with 2 orphan `...(Copy)` rows at ExecutionOrder 5.
4. The final success toast in `SaveAllChangesAsync` was **unconditional**, masking the failure.

**Fix (all in `WorkflowScenariosEditor`):**
- Copy pre-assigns `Code = Guid.NewGuid().ToString()`; builder guard is `string.IsNullOrWhiteSpace`.
- Create branch clears `IsNew`/`IsDirty` using the codes we **sent** (not index-mapped response), and treats an **8603-only** error as success to self-heal stuck copies (adopts the existing row).
- Added `anyFailure` flag threaded through delete/create/update branches; success toast gated on it (warning toast otherwise).
- Added `UnsavedChangesTooltip` (hover `title` on the badge) listing New/Modified/Deleted items.

**Orphan cleanup:** user deletes the stray `(Copy)` rows in-app after rebuild (a reload now surfaces all rows since creates stop looping). Codes were `19c3f8e4-…` and `950c0e20-…`.

**The "post-commit exception" was a misdiagnosis.** Seq raw showed the real throw was `System.ArgumentException: ownerCode must not be null or whitespace` from `ScenarioConfigStore.PersistAsync` (line 37-38 guard) — a **pre**-commit throw caused by the same empty-code bug, which aborted the whole save batch. The guard fix (never pass empty ownerCode) already eliminates it. Additionally hardened `BuildWorkflowDetailRecordAsync` to **fail soft** (try/catch → return null) so one bad scenario no longer throws up the stack and aborts saving the others; the update branch now pairs scenario↔record and only clears `IsDirty` on scenarios actually sent (was clearing all dirty even if a build was dropped).

Sibling editors (`WorkflowExecutionEditor`, `WorkflowBuilder`) do **not** share this pattern — bug was isolated. Relates to [[testauto-scenario-config-store]] (pre-assigned code enables chunk write before create) and the empty-vs-null class in [[project_model_import_refdata_empty_body]].
