---
name: project-myloop-throughput-tracking
description: "MyLoop logs every row lifecycle step to .loop/metrics/events.jsonl; Get-Throughput.ps1 splits each row's wall-clock into ticket/queue/work/lead waits/verify/rework"
metadata: 
  node_type: memory
  type: project
  originSessionId: a2ce2bbb-6850-4044-9304-dc65407c6c01
  modified: 2026-09-15T23:39:00.371Z
---

Throughput tracking was added to /myloop on 2026-09-15, after Gene asked "Would these go faster if we just did them sequentially" and then "Lets add some tracking so we can find a way to improve throughtput".

**What records it:**
- `LoopEvents.ps1` appends one event per step: ticket-start, ticket-ready, ticket-check, dispatched, reported, collected, verify-start, verdict, rejected, closed.
- The lead records two things by hand with `Add-LoopEvent.ps1`:
  - `author-reported`, with `-At` set to the notification time;
  - `rework`, with `-Kind ticket-recite|grader-fix|build-retry|recollect|reject|other -Minutes -Reason`.
- `Get-Throughput.ps1` writes `.loop/metrics/throughput.md`. Sync-Board prints its one-line summary on every wake.

**First reading (24 h, record-derived only):**
- 1.5 rows closed per hour.
- Workers running averaged 0.55.
- Verify was the largest phase besides work (21%); ticket time was also 21%, from only 5 measured rows.
- A finished worker sat uncollected for 73 min in total.

**18:06 additions:**
- Gene: "I would have thought ticketed means it is done". The board states are now Queued -> Ticketing (being written or checked) -> Ticketed (done, waiting) -> Started -> Complete.
- The report gained a Timeline table with each phase's start and end, including rows still in Ticketing.
- It also gained a "no worker running and no ticket done while a ticket was being written" measure: 177 min in 24 h. It is the true test of whether ticket writing is a bottleneck; a large share of cycle time is not.

**Second reading (19:23, 24 h window) — what the tracking actually taught:**
- **Ticket writing was the bottleneck, workers were not.** 178 min of 1440 had no worker running, no ticket ready, and a ticket being written. Only 11 min had a ready ticket and no worker. Ticket 442 min over 7 rows vs work 655 min over 34 rows: ~2.7x more lead-minutes per row than worker-minutes.
- **Acting on it worked.** Writing 4s/4p/4t/4u while workers ran put four rows in Ticketed at once; the constraint moved from "no ticket exists" to "these rows touch the same files" — a dependency constraint, which is the better one to have.
- **Workers time-weighted average 0.58 against a cap of 7.** Parallelism is nowhere near the limit.
- **Estimates run ~3.4x high:** median actual/estimate 0.29x over 34 rows. The schedule's plan-minute total overstates by more than double.
- **The two-gate ticket check is nearly free:** review wait 1 min total, rework 17 min (1%), 4 retries in 34 rows. The expensive phases are verify (330 min, 20%) and the lead's own waits (collect+close 157 min, 10%, plus 73 min of a finished worker uncollected).
- **Outlier worth watching:** a ticket repeatedly deferred behind reorderings ran 308 min against a 53 min median.

**Why:** without it, parallel-vs-serial questions were answered from CPU load and judgement ([[feedback-run-parallel-when-possible]]).

**How to apply:**
- Record author-reported and rework every time; unrecorded rework hides inside work or ticket time.
- Change pairing, ordering or ticketing on the throughput.md figures, and log the figure in `_decisions.md`.
- The scripts live in the skill ([[project-myfable-foreman]]); install them only through Write-VaultFile.
