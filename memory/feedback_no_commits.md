---
name: feedback-no-commits
description: Git state-changing commands are per-repo — allowed in speedmerchants, never in speed-merchants or anywhere else
metadata:
  node_type: memory
  type: feedback
  originSessionId: cd652c85-823a-4297-846f-e5ffed1e17b1
  modified: 2026-10-01T01:47:02.453Z
---

**PLANNED 2026-09-30:** this table moves into each machine's `ProfileMachineConfig.md`, as the `## Git commit policy` table with `Commit` and `Push` columns. A missing repo gets neither. A `commit-guard` hook enforces it. Gene set speedmerchants to commit yes, push yes. See [[feedback-machine-portable-ai-config]]. Until that ships, the table below holds.

**The rule is now SPLIT BY REPO, and the two repo names differ by one hyphen. Read the path before acting.**

| Repo | Path | Git state changes |
|---|---|---|
| **speedmerchants** (vNext loop) | `C:\devops\repos\speedmerchants` | **ALLOWED** — commits included |
| **speed-merchants** (TestAuto + CrewChief) | `C:\devops\repos\speed-merchants` | **NEVER** |
| everything else | any other repo | **NEVER** |

**Why:** Gene 2026-09-11 00:50, during the vNext orchestrator loop: "split that commit rule by repo, you can do any commit in the speedmerchants repo but the existing rule applies for the speed-merchants repo". The loop generates many small verified rows in `speedmerchants` and he was hand-committing each one — eight-plus times in one night — which also left the tree dirty and kept criteria like `u7-0-endtoend` red on "src/ or tests/ differ from HEAD". The original blanket rule came from 2026-05-31 ("No git commands I do all git manually") after I ran `git rm` during a skill migration; that rule still stands everywhere except `speedmerchants`.

**How to apply:** In `speedmerchants`, commit freely — prefer a commit per closed loop row, after its gates pass, never mid-row while an Executor is running. Everywhere else, and in `speed-merchants` especially, change no repo/index/worktree state: not `git commit`, `git add`, `git rm`, `git restore`, `git mv`, `git checkout`, `git branch`, `git reset`, `git stash`. Edit or delete files with filesystem tools and let Gene stage them. **Executor subagents keep the blanket prohibition regardless of repo** — they run mid-row against a constraint baseline, and a commit underneath a running row breaks the gate-3 comparison and the copy-before-probe recovery path; only the Orchestrator commits, and only at a row's close. Read-only inspection (`log`/`status`/`diff`/`ls-files`) stays fine anywhere.

**Reconfirmed 2026-09-13 22:46** under /myloop: the lead asked whether Gene would commit at a row's close, and he said the lead does the commits as needed. The myloop skill's principle 4 ("never commit") and the global CLAUDE.md rule are both overridden by this per-repo authorization in `speedmerchants`; they still bind workers and verifiers. The commit point is after Close-Row (and the publish), before the next dispatch whose write set overlaps. Stage only the closed row's paths, never `.loop/` (gitignored) or bin/obj.

Related: [[project_myfable_foreman]], [[feedback_copy_before_probe_never_git_checkout]], [[feedback_no_worktrees]], [[project_git_config]].
