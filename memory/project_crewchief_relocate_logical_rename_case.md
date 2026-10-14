---
name: project_crewchief_relocate_logical_rename_case
description: CrewChief relocateFiles restore failed with SQL Msg 1828 because the logical-rename plan compared names case-sensitively; fixed 2026-08-02
metadata: 
  node_type: memory
  type: project
  originSessionId: a2308b1b-2747-4d63-b2f8-0c17ca519ee5
  modified: 2026-08-02T22:59:39.678Z
---

CrewChief `RestoreDatabase` + `relocateFiles` reported failure with five copies of
*"The logical file name 'profisee...' is already in use."* The RESTORE itself succeeded — the
failure was the follow-up `ALTER DATABASE ... MODIFY FILE` rename phase in
`DatabaseOperationsExecutor.RunRelocatingRestoreAsync`, whose result replaces the restore's result.

Root cause: `BuildRelocationPlan` decided "does this file need a rename?" with
`StringComparison.Ordinal`, but SQL Server compares logical file names case-insensitively. Backup
held `Profisee`/`Profisee_1..3`/`Profisee_log`; step targeted `profisee` — Ordinal said "differs",
SQL said "already in use". Msg 1828 is severity 16, so all five statements in the batch ran and all
five errored.

Fixed 2026-08-02: OrdinalIgnoreCase for the rename test, plus a temp-name two-phase rename when the
target names are a permutation of the current names (`MakeRenamesCollisionSafe`). Three unit tests
added in `DatabaseOperationsExecutorTests`; doc section + troubleshooting row updated in
`21_StepGuideDatabaseOperations.md`.

**Why:** cross-boundary case semantics — C# default comparisons are case-sensitive, SQL Server
identifiers/logical names are not.
**How to apply:** when generating SQL identifier renames from C#, compare with OrdinalIgnoreCase and
treat any rename over a shared namespace as needing collision-safe ordering. See
[[project_crewchief_dbops_rename_relocate]] and [[feedback_verify_no_guessing]].
