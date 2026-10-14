---
name: feedback_worktrees_allowed_must_integrate
description: Worktrees ARE allowed (supersedes the old no-worktrees rule) — but every worktree must be integrated into main and validated there before the task is done
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 88115bc9-15ea-44e9-9368-246d53858785
  modified: 2026-10-01T01:52:04.834Z
---

**PLANNED 2026-09-30:** worktree permission becomes per repo, through the `Worktrees` column of the profile's `## Git policy` table. A missing repo gets no worktrees. On the laptop, only speedmerchants is yes; speed-merchants has no row, so it gets no worktrees. Worktrees are created only under `{WorktreesRoot}`. See [[feedback-machine-portable-ai-config]]. The integrate-and-validate rule below still applies wherever worktrees are allowed.

**SUPERSEDES [[feedback-no-worktrees]] (2026-09-11, Gene).** Claude may freely create and use git
worktrees for parallel or isolated work. They are temporary implementation environments, never final
destinations.

When work in a worktree is complete, in this order:

1. Validate the work in that worktree.
2. Commit all intended changes to the worktree's branch. (Repo rule still applies: commits are OK in
   `speedmerchants`, NEVER in `speed-merchants` — see [[feedback_no_commits]].)
3. Return to the primary working tree at `C:\devops\repos\speedmerchants`.
4. Integrate the worktree branch into the local main branch.
5. Prefer a fast-forward merge when possible.
6. If main has advanced: rebase the worktree branch onto current local main, resolve conflicts,
   rerun validation, then integrate.
7. Run the appropriate build and tests from main after integration.
8. Verify main contains every intended change.
9. Remove the completed worktree.
10. Delete the temporary worktree branch after successful integration.

Worktrees may run concurrently. When several complete, integrate them into main ONE AT A TIME,
resolving conflicts and validating main after each.

**Never discard a worktree holding unique changes until those changes are in main.**

**Why:** Gene wants parallel/isolated execution available, but the authoritative state must always be
the main working tree — completed work stranded in a worktree or temp branch does not count as done.

**How to apply:** A task is not finished until its worktree work is integrated into main AND
validated there. Worktree setup steps in skills are no longer to be skipped. Related:
[[project_repos]], [[feedback_no_commits]].
