---
name: project_crewchief_dbops_rename_relocate
description: 2026-07-25 CrewChief DatabaseOperationsStep gained first-class rename-on-restore (relocateFiles WITH MOVE + logical rename) and waitIndefinitely (timeout 0) for huge restores
metadata: 
  node_type: memory
  type: project
  originSessionId: 777a7eea-fcad-44ae-9256-e6de518573d5
  modified: 2026-07-25T13:48:50.984Z
---

2026-07-25: Added two capabilities to CrewChief `DatabaseOperationsStep` / `DatabaseOperationsExecutor`
(`CrewChief.Engine/…`), driven by the "restore a Profisee26R2 backup as Profisee (200M rows)" use case.

**`relocateFiles` (bool, RestoreDatabase only)** — first-class rename on restore. Before this a plain
`RESTORE ... FROM DISK` wrote the backup's ORIGINAL physical paths → collided with the source DB if it
still existed, or left the new DB on mis-named files. Now when on, the executor:
1. `ReadBackupFileListAsync` → `RESTORE FILELISTONLY FROM DISK = @disk` (parameterized; reads
   LogicalName/Type BY NAME so version-varying column set never breaks it).
2. `ReadDefaultFileLocationsAsync` → `SERVERPROPERTY('InstanceDefaultData/LogPath')` w/ sys.master_files
   (db 1) fallback.
3. Pure `BuildRelocationPlan(db, files, locations)` → MOVE clauses (data→data dir, log→log dir, named
   `<db>.mdf`/`<db>_N.ndf`/`<db>_log.ldf`) + logical renames (old!=new only).
4. `BuildRestoreDatabaseCommandWithMove` runs, then `BuildLogicalRenameCommand` (`ALTER DATABASE …
   MODIFY FILE NEWNAME`). Restore-fail skips rename; rename-fail surfaces its error (DB already restored).
Reads run under the same impersonation as the restore. Default OFF (restore-in-place unchanged).

**`waitIndefinitely` (bool, all ops)** — forces effective CommandTimeout=0 (infinite), overriding
`timeoutSeconds`. TimeoutSeconds already treated 0 as infinite; this just exposes it clearly for
hours-long backups/restores. Cancellation still works.

Seam: `IDatabaseCommandRunner` gained the two read methods + records `BackupLogicalFile`/
`DefaultFileLocations`; `DefaultDatabaseCommandRunner` implements (shared `OpenMasterConnection`).
Command builders are pure static + unit-tested. Editor: two RadzenSwitches in StepEditorCard DB-ops
branch (Relocate&rename under Overwrite; Wait-indefinitely by Dry Run). Doc: 21_StepGuideDatabaseOperations.md.
Tests: DatabaseOperationsExecutorTests (+18). Related [[project_cdp_sqlbulkcopy_regression]] is unrelated.
