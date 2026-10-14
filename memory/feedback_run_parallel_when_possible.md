---
name: feedback-run-parallel-when-possible
description: "Standing permission to run independent tasks in parallel (tool calls, workers, verifier + publish) to save wall-clock time"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 22d5dbd3-c155-4749-bee7-fcbb38ec1329
  modified: 2026-09-15T21:25:59.185Z
---

Whenever independent tasks can run at the same time, run them in parallel: batch independent tool calls in one message, dispatch disjoint /myloop rows together, publish or collect while a verifier runs.

**Why:** Gene prefers saved wall-clock time over serial execution; waiting on one agent while other owed work sits idle wastes the session.

**How to apply:** In the loop, while a verifier or worker runs, do every other owed step (publish, collect, batch verifier, next ticket) at once. Parallel row dispatch still obeys disjoint write sets and dependency order ([[project-myfable-foreman]]). If Gene questions an ordering, explain the dependency that allowed it.

**Code rows too (2026-09-15 17:24, Gene: "We have UI work and backend work that dont seem to be in conflict why can they not both be in progress at the same time").** I had kept "one code row at a time" as my own rule after the shared-file stretch ended; the skill already fans code rows out on disjoint write sets + different test projects. Serialise only on a real conflict: overlapping write sets (Dispatch-Row refuses), a row that stops/rebuilds the live stack (e2e-ui-smoke, ui-routes-live) beside a row whose proofs/live tests use fleets or the warehouse, or concurrent builds (each worker builds only its own test project, retries once on a locked file). Re-check the rule whenever the queue's shape changes; say the conflict out loud when holding a row back.
