---
name: reference_started_state_was_transient
description: The loop's Started state lived only in dispatched.json and was DELETED at close, so 67 closed rows could never prove they were opened; started.json is the append-only ledger that fixes it
metadata:
  type: reference
---

Gene, 2026-09-10 18:38: *"How can these task closed when they were not opened"*. He was right, and it was
not a rendering bug.

`dispatched.json` was the ONLY store of a row's start time, and the close step **deleted** the entry. So
`Started` was a state that existed for the hours a row was in flight and then vanished: all 67 closed rows
carried `started: ""`, and the page rendered them Queued → Complete with nothing in between. Anything closed
before 2026-09-08 12:02 never rendered Started at all, because nothing wrote the middle state until then.

Fix (09-10 18:4x):
- **`.loop\tools\started.json`** — append-only ledger, `{ key: { at, closedAt, minutes, basis, what } }`.
  `basis` is `observed` (a real dispatch stamp) or `derived` (backfilled as `closedAt - actual`, which has
  the right duration but a wall-clock that excludes verification time). **An observed entry must never be
  overwritten by a derived one.**
- **`.loop\tools\Close-Row.ps1`** — the only correct way to clear a dispatch marker: it writes the ledger
  FIRST and only then drops the live entry, and it throws if the row has no `at` stamp to preserve.
- `Write-Schedule.ps1` reads the dispatch stamp first, then the ledger, so a CLOSED row still reports when
  it opened; the HTML puts `opened … (basis) · closed …` on the Status-Time cell's tooltip, leaving the
  fixed column format alone.

Backfill result: 69 ledger entries, 67 derived + 2 observed; 67 of 67 closed rows now have a start stamp.

Caught while wiring it: `$StartedBasis` (the ledger table) and `$startedBasis` (the per-row value) are
**one variable** — PowerShell variable names are case-insensitive, so the first row's string clobbered the
table. Fourth appearance of that defect class in this loop's own tooling in one day; see
[[reference_grader_case_insensitive_prose_answers_code]] and
[[feedback_mark_row_started_at_dispatch]].

## Second half, same complaint (Gene 18:40: "we have other tasks that are well past their expected time")

A start stamp alone cannot answer "is this late", so an in-flight row now carries `elapsed`, `overdue` and
`blocked`. **Three outcomes, and they are not the same fact:**

- **blocked** — the clock is WAITING time, someone else's to spend, and is never flagged late. 48.MIG1 had
  been Started 141m against a 20m estimate and was not overrunning at all; it was held on Gene's word.
- **overdue** — elapsed past the PLAN estimate with work actually in flight. Red on the page.
- **running** — elapsed inside the estimate.

`blocked` is an **explicit boolean in `dispatched.json`**, never inferred from the `what` prose — prose
sniffing is the defect class that produced three wrong states in this tooling on one day.

Closed overruns are the calibration half and are now on the est-vs-actual tile: **10 of 66 ran over, worst
59.3c at 5.70×**. The windowed (last-10) opus factor hides that tail by construction.
