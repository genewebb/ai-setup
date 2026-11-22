---
name: feedback-stream-worktree-removal-standing-approval
description: "Speedy stream integrator may remove worktrees once ready (closed group, integrated/done row, reversed row with kept patch) - owner standing approval 2026-10-11"
metadata:
  node_type: memory
  type: feedback
  originSessionId: ff5bec9e-bb2c-4d16-839d-3fdf9ebacd09
  modified: 2026-10-12T00:09:03.921Z
---

Owner, 2026-10-11 20:08 EDT, to the integrator: "Approval worktree removal when ready". Standing approval: remove a stream worktree as soon as it is ready, via `Remove-TaskWorktree.ps1` (never `git worktree remove` by hand).

Ready = suite/retest snapshot of a finished run of a closed group; worktree of an integrated/done row; reversed row (patch kept, rebuild starts fresh); orphan dir of a closed group. NOT ready = live build claim (script refuses, exit 3), ADHOC-* trees owned by the ad-hoc session.

**Why:** Worktrees are 0.6-1.5 GB each and the patch is their content; the owner no longer wants to validate each removal.

**How to apply:** Each integrator cycle may sweep `git worktree list` plus orphan dirs under D:\devops\worktrees\speedmerchants and remove ready ones; report each REMOVED line in the cycle status. Supersedes the "never remove worktrees" line for the stream integrator only. Related: [[feedback-worktrees-allowed-must-integrate]].
