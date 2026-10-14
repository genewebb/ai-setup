---
name: feedback_workflow_parallelizes_agents
description: The Workflow tool runs agent() calls concurrently even when written as sequential awaits — do not rely on it to serialize file-mutating agents
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 7f76139b-3f09-411a-ba87-88ab6d9b2e03
---

The Workflow tool ran top-level `await agent()` calls **in parallel**, not sequentially. Evidence (CrewChief sealed-secrets run, 2026-07-16): the run journal showed **6 agents "started" before any "result"**, and the CLI group finished first and reported it had to build groups 3–5's work "because they did not exist yet" — impossible under true sequential execution.

**Why it bit:** with `[[feedback_no_worktrees]]` in force (no isolation), multiple agents mutated the same files (`CrewChief.Data\Secrets\*`, `Program.cs`, `.gitignore`) concurrently → last-writer-wins collisions. Compiled green but left an impl/test mismatch + non-atomic tests (shared process-global env var under `[assembly: Parallelize(MethodLevel)]`) that flaked (1139 serial-green, but 0–3 failing per parallel run).

**How to apply:**
- For **file-mutating** multi-step work under the no-worktrees rule, do NOT use a Workflow expecting sequential awaits to serialize it. Either (a) dispatch **single Agent-tool calls one at a time** (launch, await completion, then launch the next — the main loop genuinely serializes), or (b) only use Workflow for **read-only** fan-out (review/research) where parallel writes can't collide.
- Workflows that touch **distinct** files per group can still converge green in parallel (the earlier fixes/enhancements workflows did) — the risk is groups overlapping on the **same** new files.
- If a workflow must mutate shared files, the tool's `isolation: "worktree"` is the intended guard — but that's forbidden here, so avoid it.
- Diagnose a suspect workflow by Reading its `subagents/workflows/<runId>/journal.jsonl` (safe; holds structured results) — count "started" vs "result" interleaving.

Recovery pattern that worked: run the suite **serially** (`-- MSTest.Parallelize.Workers=1`) to prove code soundness vs. test races, then make the new tests parallel-safe (unique per-test env-var names + `[DoNotParallelize]` on classes touching env/DPAPI/OS-global state). Relates to [[project_crewchief_review_2026-07-16]], [[feedback_tests_must_be_atomic]].
