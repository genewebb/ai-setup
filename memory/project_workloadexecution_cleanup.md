---
name: project_workloadexecution_cleanup
description: CleanUpOldRun.ps1 — version-filtered WorkloadExecution cleanup via Profisee staging; entity graph + meta.tStaging Row Count gotcha
metadata: 
  node_type: memory
  type: project
  originSessionId: cc4dfccc-6b46-4a5c-ab20-be943a318e98
---

`C:\devopslocal\PowershellScripts\CleanUpOldRun.ps1` cleans up old test runs keyed off the
`WorkloadExecution` Profisee entity, version-filtered (default `26R2P`/`26R2PV2`, resolved by **Code**
not ID — IDs differ per env: local 13/14, prod 17/19). Modeled on ResetDevTest.ps1.

**Mechanism:** stages deletes via `UnitTest.ClearTestData @WhatIf=2` (1=Preview, 2=Stage, 0=Execute)
into Profisee's native `stg.t<Entity>_Delete` tables; never deletes directly. Actual deletes are run
manually from the Profisee **staging UI** (Process), in dependency order. `$Target` switch = Local
(Integrated Security) | Prod (full conn string / `$env:SPEEDMERCHANTS_PROD_CONNSTR`); ONE env per run.

**Dependency order (enforced by real FKs):** 12 child entities (Seq 1-12, any order — flat, none ref
each other) → `WorkloadExecution` (Seq 13) → `TestAutoWorkflowExecution` (Seq 14). The 12 children all
carry a `WorkloadExecution` domain column (child stores parent's `ID`). `TestAutoWorkflowExecution` has
no WE link — reached via `Detail.WorkflowExecutionParent`; deleted only if NO detail survives (safe
NOT EXISTS incl. `IS NULL`, else NULL-link orphans cause FK violation).

**Key gotchas (verified):**
- Staging-UI **"Row Count" column = `meta.tStaging.LastRunRowCount`**, NULL until a batch is
  *processed* — NOT a live `COUNT(*)`. Physical `stg.t…_Delete` can hold rows while the grid shows 0.
  Trust `COUNT(*)`, not the grid. Process DOES pick up rows inserted directly by ClearTestData.
- The WorkloadExecution model + `stg` + `ClearTestData` live in the **`speedmerchants`** DB on
  CorpLTR94, NOT the `Profisee` platform DB (which has none of these).
- Type-1 orphans = detail own-version target but NULL/non-target WE link → left behind; script's
  §5a integrity report flags them for manual relink before the run (does not auto-fix).
- Staging-delete infra (`stg.t/p<Entity>_Delete`) is created manually per-entity in Profisee; prod
  only had it for RecordApiExecution + RecordInteractiveApiExecution initially.

Full spec + validation: `99 Documentation\speed-merchants\planning\Design_WorkloadExecutionCleanup.md`.
Related: [[project_perfdashboard]], [[speedmerchants-db-migration]], [[reference_scenariomgt_db]].
