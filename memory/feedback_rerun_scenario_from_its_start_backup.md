---
name: feedback-rerun-scenario-from-its-start-backup
description: "Matching perf scenarios: every rerun restores the backup taken before that scenario started; never rerun on top of a dirty state"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T16:44:26.267Z
---

Every rerun of a Matching scenario starts by restoring the Profisee DB backup from before that scenario (S1 = loaded, S2 = after-1, 3a = after-2, 3b = after-3a, 3c = after-3b). Never rerun on top of the state a failed or partial run left.

**Why:** Gene, 11/05/2026: "Whenever you have to rerun a scenario you should drop back to the backup before the scenario started". A run on a dirty state measures nothing comparable.

**How to apply:** The matching pack's scenario workloads (`matching-<size>-scenario<x>`) already restore their start backup as their first real step, so rerunning the whole workload satisfies this. Never run only the TestAuto workflow or hand-fix the DB and continue. Related: [[project_crewchief_workload_packs_2026-11-04]].
