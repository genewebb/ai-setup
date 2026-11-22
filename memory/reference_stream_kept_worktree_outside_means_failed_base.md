---
name: reference-stream-kept-worktree-outside-means-failed-base
description: "Watchdog KEPT a task worktree with owner files 'OUTSIDE the write set' = its base failed part-way (nothing staged), not a HEAD-vs-base reaper bug"
metadata:
  node_type: memory
  type: reference
  originSessionId: 185f5665-8770-43d9-9ee7-eb0430a4dfbe
  modified: 2026-10-02T07:57:20.256Z
---

New-TaskWorktree stages the whole base (`git add -A`), and Export-TaskPatch diffs index vs worktree, so base content
never counts as outside work. When the watchdog keeps a tree because owner files (compose.yaml etc.) read OUTSIDE,
check `git -C <tree> diff --cached --name-only`: empty means the base failed part-way (a dependency patch did not
apply) and the throw skipped the add.

**Why:** 2026-10-02 kit item 76a8 blamed the reaper; the real cause was G3.T235 and G3.T202-2 failing on a doubly
applied GuardKeyWriteCheckTests.cs hunk. Fixed in New-TaskWorktree (stages partial base in a catch, rethrows),
Test-StreamKitRecovery case 57.

**How to apply:** reproduce before trusting a kit item's diagnosis ([[reference-stream-stale-read-blocks-and-bugs]]).
Trees laid before the fix stay kept until `git add -A` runs in them.
