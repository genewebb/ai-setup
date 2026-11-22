---
name: feedback-no-worktrees
description: SUPERSEDED 2026-09-11 — worktrees are now allowed; see feedback_worktrees_allowed_must_integrate
metadata: 
  node_type: memory
  type: feedback
  originSessionId: cd652c85-823a-4297-846f-e5ffed1e17b1
---

**SUPERSEDED 2026-09-11 by [[feedback_worktrees_allowed_must_integrate]] — worktrees are now permitted.** Historical rule follows.

Never create git worktrees. Do not use `git worktree add`, `EnterWorktree`, or any worktree-based isolation. Make all changes directly in the working repo.

**Why:** User explicitly said "Do not use worktrees just make the changes."

**How to apply:** Ignore any skill or workflow step that says to set up a worktree. Work directly in the current repo on whatever branch is currently checked out. The user creates and manages branches manually. Skip worktree setup steps entirely.
