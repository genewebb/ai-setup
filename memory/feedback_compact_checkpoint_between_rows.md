---
name: feedback_compact_checkpoint_between_rows
description: "Gene 2026-09-13 10:45: after closing a row and before dispatching the next, ask 'compact? y/n', wait 60 s, proceed as no"
metadata:
  type: feedback
---

Gene, 2026-09-13 10:45, mid-loop: "Add this to our loop at the end of closing a task before you start the next one give me a prompt to ask if I want to compact y/n wait 60 seconds then proceed as if I responded no."

**Why:** long [[project_myfable_foreman]] sessions accumulate context; the gap between close and the next dispatch is the one moment nothing is in flight, so a compact there loses no worker.

**How to apply:** after Close-Row + baseline + publish + ledger, end the turn with one line `Compact before <next key>? y/n (no answer in 60 s = n)` and `ScheduleWakeup` 60 s with the loop prompt. No reply or `n` on wake: dispatch. `y`: tell Gene to run `/compact` (the model cannot run it), keep the wake sources armed, dispatch after. Do NOT use AskUserQuestion — it blocks with no timeout. Written into myfable-foreman SKILL.md as step 10b. Refines [[feedback_never_stop_to_report_between_rows]] — a 60 s pause, not a stop.
