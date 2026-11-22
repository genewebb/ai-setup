---
name: feedback_isolation_goal_not_performance_2026-11-18
description: Isolation testing goal is proving workloads in separate containers/VMs do not affect each other; speed gains are only a by-product
metadata:
  node_type: memory
  type: feedback
  originSessionId: 48e8ba62-42b2-44d2-b5a8-39d62dc558bf
  modified: 2026-11-18T19:17:05.359Z
---

Gene 2026-11-18: "our goal is isolation, if we get improved performance that is a by product but we want to confirm we can run workloads that do not impact each other because they are isolated from other containers."

Gene again same day: "Make sure we stay focused on Isolation, performance is a nice by product of the tuning but reliable, repeatable tests are our goal."

Gene 14:16 same day, the measure: one product run (e.g. load 1M records in batches of 1000; CRUD workload with single updates through stewardship) timed end to end; target run-to-run variation of that total **about 1% or less while other containers run**. Single batches may be faster or slower; the total must stay steady across runs.

**Why:** On 11/18 I spent steps A, E, F, G, I chasing why SQL small transactions flip between two speed levels with nothing else running, and reported speed gains (halt polling, SQL FUA mode). Those are noise and speed findings, not isolation answers. No neighbour-load test had run since the smoke test.

**How to apply:** Judge every next step by whether it moves the isolation verdict (neighbour load on, victim figure unchanged inside the margin). Chase a noise source only as far as it blocks judging a figure; otherwise keep the figure reported-only and move on to neighbour-load phases (P4 fencing, P5 strength steps, P7 standard). Present speed gains as side effects. Repeatability: every kept setting must be owned by the harness or a permanent host config with a read-back (no hand-set or runtime-only tweaks left behind), so a rerun on another day gives the same conditions. Related: [[project_isolation_smvmtr1_decisions_2026-11-18]], [[project_isolation_test_plan_page_2026-11-17]].
