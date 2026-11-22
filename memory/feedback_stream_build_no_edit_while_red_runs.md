---
name: feedback-stream-build-no-edit-while-red-runs
description: stream-build - never write into the worktree while the RED grader runs in the background; RED must grade the clean base
metadata:
  node_type: memory
  type: feedback
  originSessionId: 1dfbda97-f3b9-4bec-89a3-ae9c131f2297
  modified: 2026-10-03T17:26:21.178Z
---

When the RED grader (`Invoke-Grader.ps1 -Label red -ExpectRed`) runs with `run_in_background`, do NOT edit or create any file in that worktree until its notification arrives. Read-only exploration only (Read/Grep), and draft new files in the scratchpad.

**Why:** twice on 2026-10-02/03 (G3.T151, G5.T004) the builder edited source while RED was still building, so RED could have graded a half-changed tree. Both times RED had to be redone on a restored clean base (move the file out / `git restore` the path, re-run RED, put the edit back). Copying an edited file back with `Copy-Item` keeps its OLD mtime, so MSBuild skips it as up to date and the next test run silently uses the base build - touch the file (`LastWriteTime = Get-Date`) after restoring.

**How to apply:** run RED in the foreground when you have nothing else to read, or in the background while you only read code. Related: [[reference-stream-build-check-inbox-before-handoff]], [[reference-stream-build-beat-during-long-builds]].
