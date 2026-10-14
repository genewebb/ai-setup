---
name: project_crewchief_folders
description: CrewChief step/workload subfolders — Option B, SHIPPED 2026-09-01 (uncommitted), suite 3792 green
metadata:
  type: project
---

**SHIPPED 2026-09-01** (uncommitted; build 0 errors, suite 3792/0, +100 tests). Docs:
- `99 Documentation\speed-merchants\planning\Design_CrewChiefStepWorkloadFolders.md`
- `99 Documentation\speed-merchants\planning\Plan_CrewChiefStepWorkloadFolders.md` (14 TDD tasks, ~3.5 days)

**Option B chosen**: real subdirectories under `steps\` / `workloads\`, but the NAME stays the identity
and stays globally unique. A folder is where a file lives, not what it is called. Option C (path as
identity) rejected — would break run history, `RunWorkloadStep.workloadName`, CLI args, every
name-keyed dictionary, and need a migration.

Facts that made it cheap (verified in code, not assumed):
- `WorkloadStepEntry` is INLINE-ONLY — no live ref to library steps (`LegacyWorkloadRefGuard` rejects
  legacy `ref`). Moving/renaming a library step cannot break a workload.
- `BackupService` already walks `SearchOption.AllDirectories` with relative zip entries — folder-safe.

Key decisions: `Folder`/`ShadowedBy` are `[JsonIgnore]` (path is the authority, nothing to drift);
duplicate name across folders = shallowest wins, loser badged **Shadowed** and refused for write;
folder-move IS in scope (user asked 9/1) and does NOT refuse shadowed/unreadable files because it is a
directory operation; bundles get an additive `folders` map at schema 1.1.

Path safety grew: the kebab name check WAS the traversal guard — now each folder segment is
kebab-validated AND the resolved path is asserted under the library root.

Built: `FolderPath` (traversal guard), `LibraryFolderIndex` (one walk + shadow verdict), folder-aware
CRUD + `Move`/`MoveFolder`/`AllFolders` on both stores, `folders`/`folder` bundle keys, `FolderFilter`,
`MoveToFolderBar` + `FolderMoveDialog` controls, Folder facet/column/Shadowed badge on both pages,
`crewchief list --folder`, backup pin test, help docs.

**Deviations from the plan, all deliberate:** bundles did NOT get a schema bump (ValidateImportable
compares versions for EXACT equality — a bump would reject every existing bundle; keys are additive at
1.0 instead). No FolderPicker control (plain RadzenDropDown, like the Tags facet). Both pages
null-coalesce `AllFolders()` because Moq returns null for un-stubbed members in 8 existing test contexts.

**Bug caught pre-ship:** export read `Folder` off the CLONE — `Clone` round-trips JSON and `Folder` is
`[JsonIgnore]`, so every export would have recorded no folders. Read from the SOURCE before cloning.

Related: [[project_crewchief_bulk_tagging]] (the checkbox selection folder-move reuses)
