---
name: feedback_coordinator_inbox_report_every_tick
description: "Coordinator must check its inbox every tick and open each report with per-inbox counts plus \"Coordinator working\""
metadata:
  node_type: memory
  type: feedback
  originSessionId: f7f972f6-eecc-483b-b761-e6144a85ff21
  modified: 2026-10-10T14:48:03.523Z
---

On every coordinator tick (the normal status cadence), check the inbox and open the report to Gene with one line: the open count per inbox (kit, plan, author, build, integrate, status) and a statement that the coordinator is working and on what. Print it even when every count is 0. The same counts go in the coordinator.log.md tick line (`| inbox: kit N / plan N / ... |`).

**Why:** Owner asked 2026-10-10 10:43 EDT. Overnight the plan inbox grew to 18 items and no coordinator tick ran from 02:50Z onward, and reports never showed the inbox state.

**How to apply:** This is now in stream-coordinator SKILL.md step 1 ("Inbox report"), published to the corpus 2026-10-10. See [[feedback_stream_inbox_every_10_minutes]] and [[feedback_report_times_in_local_edt]].
