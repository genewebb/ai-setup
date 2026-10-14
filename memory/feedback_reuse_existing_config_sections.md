---
name: feedback_reuse_existing_config_sections
description: "Reuse existing appsettings/config sections; don't invent new ones — check what's already there first"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 3855e7c4-2315-43fa-a872-7386e1dd2b3b
---

When a page/feature needs configuration (page size, intervals, options), **reuse the existing appsettings.json section** that already serves that purpose — do NOT add a new section or new keys. Check `appsettings.json` and how sibling pages already read config before writing any `Configuration.GetValue`/`GetSection` call or editing appsettings.

**Why:** The user maintains the config; inventing parallel sections (e.g. a new `WebUI:WorkflowExecutionEditor`) duplicates what already exists and works, and they will reject it and make you revert. "This was already in the code."

**How to apply:**
- Before adding config: grep appsettings.json + sibling pages for the existing key/section and point at it.
- Concrete case (TestAuto.Web WebUI page size): **Edit Workflow Scenarios** (`WorkflowScenariosEditor`) reads **`WebUI:WorkflowBuilder`**; **Manage/execution edit** (`WorkflowExecutionEditor`) reads **`WebUI:WorkflowExecution`** (the UI section, nested under `WebUI` — distinct from the root-level `WorkflowExecution` engine section). Do NOT create `WebUI:WorkflowScenariosEditor`/`WebUI:WorkflowExecutionEditor` — reuse the existing sections.
- Note: the same short key can appear at two nesting levels (root `WorkflowExecution` = engine timeouts/retries; `WebUI:WorkflowExecution` = UI refresh + page size). Different full paths, not duplicates.
- Don't edit appsettings.json to add sections that already exist elsewhere; revert if you did.

Related: [[feedback_radzenswitch_not_selectbar]] (UI conventions), see [[testauto-ui-patterns]].
