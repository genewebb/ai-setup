---
name: project_crewchief_clu_wizard_and_step_param_value_card
description: CrewChief 2026-08-27 — step-param value card + CLU editor turned into a 4-page wizard with a copy-and-run Review page; CLU arg builder does not validate on build
metadata: 
  node_type: memory
  type: project
  originSessionId: 78876ca4-014f-4b69-84e8-acbd44c3ac3e
  modified: 2026-08-27T20:47:43.042Z
---

Built 2026-08-27 (build 0-error, unit suite 3328 → **3336**, uncommitted). Two enhancements in `StepEditorCard`:

1. **Step Parameters value card** — the grid's Value cell and the Add Parameter dialog now host `SecretValueEditor ShowRuntime="true"` (Siblings = `BuildResolutionParameters()`, the merged step-over-globals set). The separate **Effective Value** column is gone, replaced by the Runtime pill inside the cell — same trade the WorkloadEditor global-params grid made on 8/25. One change covers the Steps list AND a workload's inline steps, since both host this card. Side effect: **`ValuePreviewCell.razor` now has ZERO call sites** (left in place, not deleted).

2. **CLU editor is a 4-page wizard** — Task / Options / Advanced / Review, mirroring the Configure wizard's rail (`cc-wizard-*`, `cc-cfg-panel`, `cc-cfg-stat*` classes are all reused; the CLU nav has its **own** `_cluStepIndex` so the two wizards never share a page). Advanced Arguments left its `<details>` — a wizard page IS the disclosure. Review has stat tiles, validation, the copy-and-run command, and a **Re-check** button that re-probes the secrets.

**Non-obvious facts this uncovered (verified in code, not guessed):**
- `CLUCommandBuilder.BuildArguments` **does NOT validate** — a missing required option emits the flag with an empty value (`-file  -type MODEL`). `Validate` is a separate call that only `CLUExecutor.CanExecute` makes. So `BuildCluPreview` validates FIRST and returns `# No command yet — <errors>`; a test caught this by asserting the opposite.
- `CLUExecutor.cs:173` builds `Arguments = string.Join(" ", arguments)` — **nothing is quoted**, so a path with spaces is split by the CLU itself. Pre-existing defect, NOT fixed here; the Review page warns instead of quoting only in the preview (which would look healthier than the run).
- CLU path/ClientId come from `ICLUPathProvider` / `ICLUClientIdProvider` (config keys `Profisee:CLU:Path` / `Profisee:CLU:ClientId`); **both throw** with operator-facing text when unset (`GetCLUPathAsync` also throws when the file is missing). Probed lazily only when the operator lands on Review, and captured into `_cluExePathIssue` / `_cluClientIdIssue`.
- The card now injects `ICLUCommandBuilder` + both providers, so every bUnit context rendering it needs them — registered once in `CrewChief.Tests.Unit/Web/SecretCatalogTestServices.AddSecretCatalogForTests` (plus `AddMemoryCache`). A test needing a resolvable CLU path must create a **real temp file**.
- `CLUStep` keeps every field in the inherited `Parameters` dictionary (`CLU_FilePath`, `CLU_Strategy`, …), i.e. the SAME dictionary as step parameters — so CLU_* keys already show up as rows in the Step Parameters grid and are resolvable as `{{CLU_FilePath}}`. Pre-existing, untouched.

Docs updated: `15_StepGuideClu.md` (wizard + Review section + 2 troubleshooting rows), `05_CookbookStepBuilder.md`, `36_OpsSecretReplacement.md`. See [[project_crewchief_value_card_2026-08-25]], [[project_crewchief_value_builder]], [[crewchief-web-ui]].
