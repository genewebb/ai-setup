---
name: feedback_never_hold_ready_tickets
description: "MyLoop lead must dispatch every legal ready ticket at once; holding seats empty for speculative risks (a later build staling a receipt, \"parked until released\") is the failure Gene flagged"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 1a412ebb-924b-4fe0-a5a6-bf795960b18e
  modified: 2026-09-17T01:23:40.851Z
---

A ready, legal ticket is dispatched in the same turn it is accepted. Do not hold it because a later row's build might stale its receipt, because a sibling ticket is still being written, or because a row was parked hours earlier without re-checking whether the park still stands. Empty seats beside ready tickets is the defect.

**Why:** 2026-09-16 21:16 Gene: "We still have ... 5 items ticketed, 4 items ticketing BUT NOTHING STARTED" and "Why do I have to continue to manually monitor this your whole job is to manage this". The lead had held 52.S0.4pa for receipt staleness and left 48.R8 parked; throughput showed workers avg 0.4 of 7 seats.

**How to apply:** after every sync, run Get-ReadySet and dispatch everything legal; a staleness risk becomes a residual row, not a hold. If a park or hold is genuinely the human's, say so in the SAME status message as the one-line ask, never silently. Related: [[feedback_never_stop_to_report_between_rows]], [[feedback_run_parallel_when_possible]], [[project_myloop_replacement_evaluation_2026-09-16]].
