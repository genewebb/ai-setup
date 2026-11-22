---
name: reference-stream-lock-spin-and-shared-reads
description: "Stream kit 10/10: a stale-lock break on a LIVE holder spun with no sleep (762k decisions.md lines, 113 MB); [IO.File]::ReadLines blocks appenders"
metadata:
  node_type: memory
  type: reference
  originSessionId: fdb8702f-dda6-4ad9-8b9c-9852b5b7c684
  modified: 2026-10-10T16:42:11.715Z
---

On 2026-10-10 (kit item IN-20261010161046-9992), decisions.md held 762,555 lines reading "broke stale tasks.json lock" (113 MB).
- Cause: `Invoke-TasksLocked` broke any lock file older than 120 s. When the holder was alive, `Remove-Item` failed on the open file, but the waiter logged the break anyway and looped with no sleep.
- The inbox lock had the same spin, without the logging.
- Fixed: a lock is broken only when the delete actually succeeds.

`[IO.File]::ReadLines` and `ReadAllLines` open the file with FileShare.Read, so they block appenders while the file is open.
- `Build-CostPage` held decisions.md open for 37.6 s, and every append in that window threw.
- Use lib `Read-SharedLines`, which shares ReadWrite and Delete, for any long read of a shared append-only file.

**How to apply:**
- When kit appends fail with "being used by another process", look first for a long reader or a spinning waiter. Do not assume the retry is too short.
- When decisions.md grows fast, check what is spinning.

Related: [[index_stream_kit]]
