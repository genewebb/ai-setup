---
name: project_speedmerchants_graceful_stop_keeps_live_leases
description: "speed-merchants vNext finding (47.K, 2026-09-07) — a graceful fleet stop (SIGTERM / docker stop) does NOT release the rows it holds under a live lease; they wait the full 30s lease exactly like a SIGKILL. Follow-up row 47.K2 queued."
metadata: 
  node_type: memory
  type: project
  originSessionId: fe35a383-1d24-4c5e-be3d-3bf85b9770f4
  modified: 2026-09-07T18:39:07.072Z
---

Measured by the P9 two-driver kill proof's falsification 1 on 2026-09-07: `docker stop` of a fleet holding 2 Claimed rows → `secondsToReclaim` 32.9s; `docker kill` → 33.0s / 29.7s / 30.1s. Identical.

**Why:** `SqlWorkDispenser.SweepAsync` (teardown) and the in-claim sweep both run `SqlClientWorkStore.SweepExpiredLeasesSql`, whose predicate is `LeaseUntilUtc < @nowUtc`. No shutdown path anywhere sets a fleet's OWN live-leased rows back to `Ready`; only lease expiry frees them. The PLAN 47.K D-C rationale ("a polite stop lets the teardown sweep release its own claims") was therefore wrong; the SIGKILL directive stood for a different reason (a death where demonstrably nothing ran).

**Consequence:** not a correctness defect (nothing is lost; the survivor redelivers after the lease) but a ~30s stall on every polite fleet restart mid-run. Queued as follow-up row **47.K2 — graceful stop releases its own live claims** (needs its own grader; an `IWorkDispenser.ReleaseOwnAsync`-shaped statement `WHERE OwnerAgent = @me AND Status = Claimed` on cancellation, plus a P9 leg comparing stop vs kill).

**How to apply:** when a proof or a PLAN reasons about what a graceful shutdown releases, check the sweep predicate first; when 47.K2 is planned, P9 already has the stop-vs-kill measurement shape (its falsification 1) to turn into a receipt leg. Related: [[project_orchestrator_worker_loop_hardening]], [[feedback_loop_practices_that_caught_defects]].
