---
name: feedback-compact-at-50-percent-iteration-boundary
description: "Gene's standing rule for long loops - at ~50% context, finish the iteration boundary, save handoff + memory, print the table, then compact before continuing"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 75aa89d7-1a8e-429e-bbf8-a3e0c469e0ac
  modified: 2026-09-05T04:28:03.821Z
---

**Rule (Gene, 2026-09-05 00:27):** "when you get to 50 percent context find a good place and compact before continuing."

**Why:** a compaction mid-Executor loses the gate state and the falsification bookkeeping; a compaction at an iteration boundary (just after a close, or just after a dispatch with the table printed) loses nothing because PROGRESS.md, PLAN.md, BASELINE.json and the handoff carry it.

**Amended 00:28 (Gene): "leave it and let auto compact work."** Claude cannot trigger compaction and should not ask Gene to. **How to apply:** keep the on-disk state compaction-proof at EVERY boundary, so an auto-compact landing anywhere loses nothing: PROGRESS.md dispatch entry written BEFORE the Executor starts (session id, PLAN file list, sabotage list, baseline-verification record); the handoff `remember.md` CURRENT STATE refreshed at each close and each dispatch with the orphan-drill coordinates (subagent transcript folder, which falsification was last); the TaskList table printed at START and END. After a compaction: re-read the handoff, run the orphan drill, resume — never restart. Related: [[feedback-iteration-close-print-remaining-tasks]], [[feedback-loop-practices-that-caught-defects]].
