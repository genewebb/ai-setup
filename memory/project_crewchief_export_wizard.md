---
name: project-crewchief-export-wizard
description: TestAuto→CrewChief export wizard SHIPPED 2026-08-11 via 7-iteration loop; host page corrected 8/12 to Edit Workload Scenarios; manual e2e (workflow 10000159) still pending
metadata: 
  node_type: memory
  type: project
  originSessionId: 8d879f39-96f8-41dd-90c6-141448e6c4c2
  modified: 2026-08-28T17:01:50.290Z
---

TestAuto→CrewChief workload export wizard implemented 2026-08-11 (7-iteration orchestrator-worker
loop, all green, 0 rollbacks; uncommitted on `bug/26r2_testing_newrun/genewebb`).

Spec + as-built deltas: `99 Documentation\speed-merchants\planning\2026-08-11-crewchief-export-wizard-design.md`.

- Wizard reached from the **Edit Workload Scenarios** page (`WorkflowScenariosEditor`, route
  `/workflows/{code}/scenarios`, Workloads → "Edit Scenarios"), "Export to CrewChief" button at the
  RIGHT END OF THE REORDER TOOLBAR (after Down + divider) → 3 pages (Select w/ compatibility badges,
  Parameters reconciliation, Output w/ warnings + "Excluded from export") → downloads
  `.workload-bundle.json` CrewChief imports unchanged.
- That toolbar belongs to the shared generic `ScenarioListEditor<TItem>`, ALSO hosted by
  `WorkflowExecutionEditor` — so the button is host-supplied via a new optional
  `RenderFragment? ReorderToolbarEndContent` (null = renders nothing), following the existing
  `GridMetricsTemplate` precedent. Never hardcode a page-specific action into ScenarioListEditor.
- **Host-page trap**: the Workloads page has TWO edit surfaces for an already-saved workload —
  "Reorder/Edit" → `/workflow-builder?code=` (`WorkflowBuilder`, ordering only) and "Edit Scenarios" →
  `/workflows/{code}/scenarios` (`WorkflowScenariosEditor`, where config editing actually happens).
  The spec said "the workflow edit page" as if there were one; the wizard originally shipped on the
  reorder page and the user could not find it. Moved 2026-08-12 — wizard and CrewChiefExport services
  unchanged, host page only. When a spec names "the X page" in this app, check whether X is plural.
- Export reads PERSISTED config from `ScenarioDetailItem.OriginalRecord` (already in memory), so the
  button is disabled on `HasUnsavedChanges` / `IsLoading` / zero scenarios, with `CrewChiefExportTooltip`
  saying which. The page's own scenario checkboxes are `SelectedScenarioCodes` (bulk field-apply) and are
  deliberately NOT consulted — wizard page 1 owns export selection.
- All new code in `TestAuto.Web/Services/CrewChiefExport/` + `CrewChiefExportWizard.razor(.cs)`;
  pure static services, MIRRORED DTOs, zero CrewChief refs (hard guide: CrewChief never gains
  NServiceBus/platform deps; MonitorStep permanently unsupported — gateway Monitor API is GET-only, verified).
- Key facts: CrewChief step JSON = superset of TestAuto's 6 shared types; type strings pass through
  (registry aliases case-insensitive); strip scriptKey/useRestMethod/customCurlArgs;
  useRestMethod:false = incompatible (R4). Global-safe param = exactly 1 distinct value in live
  selection (126/130 on reference workflow 10000159; conflicts: DatabaseName/Schema/TableName/
  TargetDatabaseTableName — order 18 carries stale PDATA1K).
- 82 unit tests incl. ValidateImportableMirror acceptance + wire-shape pin tests.

**Open**: manual e2e — export 10000159 orders 1–20 (19 scenarios/314 steps), import into CrewChief,
run, compare env state.

**2026-08-28 drift audit + gap-closure plan**: full contract audit vs current CrewChief — NO breaking
drift (schema still "1.0" frozen-by-design, ValidateImportable identical, step entry label/inline
unchanged, 6 exported families keep aliases though registry grew to 27 types, WorkloadFile gained
only optional credential*/notes fields, token regex unchanged, TestAuto DTOs untouched since 8/11);
82/82 unit tests re-verified green. Plan:
`Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-08-28-crewchief-export-gap-closure-plan.md`
— W1 e2e (primary gate), W2 cross-side contract-drift test project (both codebases same repo; C2
binds only TestAuto.Web), W3 grouped export via new RunWorkloadStep (spike-first; name-minting on
import breaks parent workloadName refs), W4 smalls (CLU secrets doc, delete secretsHelper.js,
recorded no-gos: Run-As mapping, CurlStep conversion — TestAuto CurlStep:HttpRequestStep vs CrewChief
CurlStep raw command, shapes incompatible).

**FIXED 8/12**: `window.downloadFile` collision. `secretsHelper.js` defined `(filename, content)`
vs `site.js:4`'s `(content, fileName, contentType)` — same global, args reversed. Was LATENT: nothing
loads secretsHelper.js (`App.razor:49` loads site.js only), all 4 callers use site.js order. Emptied
secretsHelper.js to an explanatory comment rather than deleting (tracked file, `installer/stage/`
carries .br/.gz); doc row in `TestAuto.Web\Documentation\secretsmanagement.md` corrected — it had
falsely advertised the file as live. Outright deletion still recommended as housekeeping.

Related: [[project_crewchief_standalone]], [[reference_workai_sync]]
