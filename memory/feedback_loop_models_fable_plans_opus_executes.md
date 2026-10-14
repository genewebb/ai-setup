---
name: loop-models-fable-plans-opus-executes
description: "Gene's model arrangement for the vNext orchestrator-worker loop — Fable for planning and verification (the session), opus for every Executor dispatch"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: acc1f014-7b40-4f0e-b985-81edf62b4a29
  modified: 2026-09-07T00:06:48.608Z
---

**In the vNext loop, Fable plans and verifies; opus does the in-between.** (Gene, 2026-09-06 20:05.)

- Orchestrator (census, PLAN, grader authoring, dispatch decisions) = the session model = **Fable** (`claude-fable-5-1`).
- Verifier (six gates, re-running proofs, baseline advance, PROGRESS) = same session = **Fable**.
- Executor (every subagent that edits code) = **`model: opus`**, set explicitly on every Agent dispatch. Never fable, never
  inherited.

**Why:** planning and grading quality is where defects were caught (three grader defects and two census errors were
Fable's to find); the Executor work is mechanical against a written PLAN and opus has measured 0.50× of plan on 13 rows.

**How to apply:** start the session on Fable (`claude --model fable` / `/model fable`); if the session comes up on
another model, say so before dispatching. Recorded in `.loop/state.json` `models`, GOAL frontmatter and the skill's
MODELS.md. Related: [[orchestrator-worker-loop-hardening]], [[loop-practices-that-caught-defects]].
