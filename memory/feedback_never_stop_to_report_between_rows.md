---
name: feedback_never_stop_to_report_between_rows
description: "Gene should never have to say \"continue\" — dispatch the next row before reporting, and use a running Executor's time to author the next grader"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-08T16:42:58.327Z
---

Gene, 2026-09-08 12:17: *"continue and STOP forcing me to tell you to keep going."* He had already said it
once in stronger terms the day before: *"DO NOT STOP just to report ONLY STOP when you can not continue DO
NOT WAIT FOR A PROMPT to CONTINUE."* Two tellings means the behaviour, not the wording, was the problem.

**Why:** in the orchestrator-worker loop a row's close and the next row's dispatch are the same beat. Ending
a turn on a close hands the loop back to him for no reason — he then has to type "continue", which is work
he is paying me to remove. A report is a by-product of the loop, never a stopping point.

**How to apply — the order inside one turn, every time:**

1. Close the finished row (gates, baseline, PROGRESS, schedule, republish).
2. **Author the next row's grader and verify it RED, write the PLAN, mark `dispatched.json`, dispatch.**
3. *Then* write the user-facing summary, covering both the close and what is now running.

Never end a turn with "next is X" — dispatch X first. While an Executor runs, the right work is authoring
the grader for the row AFTER it, and clearing queued corrections in `.loop/` files (which no Executor is
touching). That turns dead time into a red baseline that is ready the moment the notification lands.

Only stop for: a decision genuinely his (a scope cut, a destructive action, a credential), or a hard block.
And **re-check a blocker before handing it over** — one was already resolved by the time I raised it, which
is its own version of wasting his turn.

Related: [[feedback_implement_autonomously]], [[feedback_mark_row_started_at_dispatch]],
[[feedback_iteration_close_print_remaining_tasks]].
