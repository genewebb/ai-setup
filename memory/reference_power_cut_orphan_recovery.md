---
name: reference_power_cut_orphan_recovery
description: "After a power cut or session death mid-Executor, recover the agent's final report from its subagent transcript rather than re-running the row"
metadata: 
  node_type: memory
  type: reference
  originSessionId: acc1f014-7b40-4f0e-b985-81edf62b4a29
  modified: 2026-09-06T13:41:31.936Z
---

A loop session that dies mid-Executor (power cut, crash, closed terminal) has lost **nothing**. Recover, never re-dispatch.

**Where the state actually lives:**
- The Executor's full final report — `~/.claude/projects/<proj>/<session-id>/subagents/agent-*.jsonl`, last line, `message.content[].text`. Newest `.jsonl` by mtime is the orphan; its last timestamp is when the power died.
- `agent-*.meta.json` beside it gives the dispatch time; last transcript timestamp minus that = the agent-minutes for `actuals.json`.
- Timestamps inside the transcript are **UTC** — convert before recording.
- The code — in the working tree, or already committed if Gene ran a catch-up commit.
- The checkpoint — `.loop\state.json` `checkpoints[]`, a `git stash create` SHA (dangling commit, survives reboot).

**Constraint gate after a catch-up commit.** `git status` is clean, so the gate has nothing to compare. Use `git diff <checkpoint stash SHA> HEAD -- src tests scripts` instead — that yields exactly the orphaned row's file set. It over-reports by the files that were **untracked** when the checkpoint was stashed (earlier closed rows' new files), so expect a small, explainable excess rather than a breach.

**Re-run every gate yourself.** The Executor's report is a claim; the outage cost verification effort, not verification quality.

**Post-reboot false negatives.** Any grader with a container leg fails until the Docker/Rancher engine finishes starting (`docker info` fails, the leg is SKIPPED, exit 2). Retry once the engine answers before treating it as a regression. See [[reference_rancher_desktop_switch]].

Proven 2026-09-06 on row 47.C: Executor finished 07:29, power died seconds later, row closed 09:35 with all six gates re-run and zero work lost. See [[project_vnext_replan_2026-09-04]] and [[feedback_loop_practices_that_caught_defects]].
