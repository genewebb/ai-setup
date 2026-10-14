---
name: feedback_mark_started_includes_orchestrator_work
description: "Mark a row Started when MY OWN work on it begins, not only when an Executor is dispatched — internal work counts"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: c6ce4951-6bc9-4695-a55f-766a2d5318ae
  modified: 2026-09-15T20:44:43.389Z
---

Gene, 2026-09-10 16:39, third telling of the Started rule and the first time the gap was named:
"Also nothing is showing as started so once again you have failed to follow the rules. If you are
working on internal stuff for a task just mark that step as started."

I had been reading [[feedback_mark_row_started_at_dispatch]] as "at EXECUTOR dispatch". It is wider:
**any work on a row, including the Orchestrator's own, marks it Started the moment it begins.** That
covers grader authoring and repair, investigations, live rehearsals, and anything held awaiting Gene's
word. `dispatched.json` takes `{"<key>": {"what": "...", "at": "<ISO>"}}`; `what` should say
ORCHESTRATOR when no Executor is involved, and what the row is waiting on if it is held.

**Why:** the published schedule is Gene's only window into what is live. A 20-minute investigation
with an empty board tells him nothing is happening, which is worse than a wrong estimate — he asked
twice in one hour why nothing showed Started. The board is a status report, not a dispatch log.

**Under /myloop (4th telling, 2026-09-15 12:45: "I dont see anything started?")** — three ticket authors had run
for 40+ minutes with the board showing 0 started, because Dispatch-Row only marks Started at WORKER dispatch and
hand-editing dispatched.json is forbidden. Fixed in the loop: `scripts\Mark-Started.ps1 -RootPath <repo> -Keys <k>
-What "<work>" [-At <yyyy-MM-ddTHH:mm>]` writes an `ORCHESTRATOR:` entry, Dispatch-Row keeps its `at`, Reconcile-Rows
lists it as "started by the lead", and SKILL.md step 7 calls it BEFORE any ticket author launches. Run it for every
key the moment an author, refresh or investigation starts.

**The flip side (2026-09-15 15:33, Gene: "We have several overdue items do we know why").** Starting the clock at ticket
authoring made two rows read OVERDUE that were not late: 52.S0.4i (ticket 12:36, queued behind two code rows for the build,
worker dispatched 15:25, showed 172m vs 90 est eight minutes into its worker) and 52.S0.4n (ticket accepted 14:40, idle in
the queue). The PAUSED state for exactly this already existed from 2026-09-10 (48.SEC3); Mark-Started never used it.
Fixed: Write-Schedule.ps1's overdue clock runs from the row record's last attempt `at` (worker dispatch);
`Mark-Started.ps1 -WaitingOn "<row/slot>" -WorkedMinutes <n>` marks an accepted, queued row paused; SKILL.md step 7 says
to do it the same turn a ticket is accepted. **Started = work began; overdue = the worker is past its estimate; waiting
is neither.**

**Superseded the same day (16:40, Gene: "How can 52.S0.4n be Started and Queued" / "I would think it is queued, ticketed,
started").** The lifecycle is **Queued -> Ticketed -> Started -> Complete**. Ticket work (being written, or written and
waiting) is TICKETED, which is still visible activity on the page; STARTED means a worker is dispatched. Mark-Started now
writes `phase: 'ticket'`; Write-Schedule maps it (and any queued row with a PLAN file) to Ticketed. Never show a row as two
states, and never label a waiting row with another state's name ("queued", "paused").

**How to apply (pre-myloop boards):** write `dispatched.json` BEFORE the first tool call against a row, re-run
`Write-Schedule.ps1` + `Build-Schedule-Html.py`, republish the artifact. Remove the entry at close.
See [[feedback_iteration_close_print_remaining_tasks]] for the publish cadence and
[[reference_schedule_json_is_the_backup]] for why schedule.json matters.
