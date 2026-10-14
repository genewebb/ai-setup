---
name: reference-file-move-overwrite-transient-access-denied
description: "speedmerchants: File.Move(temp, dest, overwrite) over a just-written file intermittently throws 'Access to the path is denied' under load on CORPLTR94 — reuse JsonFileStore.InstallWithRetry, never a bare move"
metadata: 
  node_type: memory
  type: reference
  originSessionId: b1f8cd5f-6ce3-4617-9512-c6797bf44a0a
  modified: 2026-09-22T05:15:24.318Z
---

On this box, replacing a file that was written moments earlier (`File.Move(temp, dest, overwrite: true)`) fails
intermittently with `UnauthorizedAccessException: Access to the path is denied` when the test suite runs under
load — another process (scanner/indexer) briefly holds the fresh file. Seen 2026-09-22 in the backup restore
(crewchief-backup-restore Goal 2): 2 failures in 24 runs of a 3-way concurrent test loop, 0 in 24 after the fix.

**Why:** a filtered run passes; only the full suite or concurrent loops show it, so it reads as "flaky test"
when it is a real production write that fails a restore unit.

**How to apply:** install a scratch file through `JsonFileStore.InstallWithRetry(temp, target)` (made
`internal` for this; 5 attempts, growing backoff) instead of a bare `File.Move`. To reproduce a suspected
flake, loop the filtered test class in 3 parallel shells and make every assert print `result.Kind + Message`.
Related: [[reference-artifacts-path-must-stay-under-repo]].
