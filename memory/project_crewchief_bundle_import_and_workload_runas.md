---
name: project_crewchief_bundle_import_and_workload_runas
description: 2026-09-24 CrewChief bundle import + workload Run As (engine + editor field/chips) + profile freeze-on-use + sticky-view menu fix + Run profiles layout A all BUILT uncommitted; amendment library-fix-list-r2 staged on top of r1
metadata:
  node_type: memory
  type: project
  originSessionId: 0359fc02-cccc-4830-81fb-20a4bcd43ea3
  modified: 2026-09-24T19:07:38.217Z
---

2026-09-24 (speedmerchants, uncommitted):

- CrewChief `*.workload-bundle.json` (C:\Deploy\Templates\Workloads, 16 files) failed with "Step Type is required": CrewChief puts each step at `{label, inline{type, flat settings}}` and globals in a `globalParameters` map, with the same "1.0" envelope. Fix: `src/Infrastructure/Transfer/CrewChiefShapes.cs`, shared by the step and workload imports. Label becomes the step name (a null label leaves the name empty). Settings move into parameters. A global name with spaces (`Source System`) is joined to `SourceSystem`, and its `{{...}}` tokens are rewritten. Types are kept as written, since the catalog resolves aliases. The dry-run imported all 16.
- Workload Run As, ported from donor `WorkloadRunAsInheritance`:
  - Code: Domain `WorkloadRunAs` (the ToString never prints the password); `Application/Steps/WorkloadRunAsInheritance`; `runAs` in `WorkloadDto`.
  - Wired into the runner (root and child), `NestedWorkloadGraph.LeafSteps` (preflight), the resume fingerprint (user and section only, never the password), merge (when sources differ, it pushes down per source), copies, and the editor (kept on save).
  - Rules: the 12 Windows-account step types inherit; the SQL family never does; a step's own Run As wins even when half filled; a child's own Run As wins, otherwise it inherits the caller's.
- Gate ArxpgmyYbHVzA5qRL3p5gG APPROVED (layout A, lock on first run, field + chips) and BUILT:
  - Run As group in WorkloadEditorPage metadata card (3 ValueEditors) + per-step chip `data-workload-step-runs-as` = workload|own|sql|host.
  - Freeze on use: `IProfileUseRecorder` (RunProfileLibrary) called by WorkloadRunCoordinator after admission; match by kind+content hash; failures to `WorkloadRunRecord.Notes` (Activity alert). Load-launcher runs mark nothing; targets never frozen.
  - StickyView: records nothing once the address path is another screen's; omitted view/cols restores remembered; toggles write explicit values.
  - Run profiles layout A: `ProfileKindsRail` (Folders slot, links `?kind=`), one-kind `ProfileLibraryList` (Kind/OpenName params, no hash on rows), `ProfileFingerprint` (collapsed Details + copy).
- DEFECT found+fixed: a used profile could never change. Its fields were disabled and Save as new of unchanged content is refused as DuplicateContent. Now "Copy and edit" unlocks a copy, and Save as new commits it. The mockup said "Save as new and edit"; the label deviation goes to Gene. Also, a refused Save as new used to clear its own refusal (SetText cleared _outcome).
- Requirements: amendment `review/amendments/library-fix-list-r2` is built ON r1's proposed files (r1 is unapproved and owns the same artifacts).

**Why:** Gene said "We should be able to map crewchief to the new format" and picked "Add a workload Run As".
**How to apply:** r2 is approved after r1 (or rebased if r1 changes). Clean-session review is owed for both. See [[feedback_ui_mockups_before_implementing]] and [[feedback_questions_via_askuserquestion]].
