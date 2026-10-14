---
name: feedback_iteration_close_print_remaining_tasks
description: At every loop iteration dispatch AND close, update the live HTML schedule artifact (regenerate schedule.json, rebuild, republish same URL, refresh archive copy) and print ONE line with the link — no inline remaining-tasks table in chat (Gene 2026-09-05 22:06 supersedes the earlier "print the table" rule)
metadata:
  type: feedback
---

At every iteration boundary of the vNext loop (dispatch and close), refresh the live schedule page instead of printing a remaining-tasks table inline.

**Why:** Gene 2026-09-05 22:06: "I like the HTML schedule — replace the inline table with just an update to that at the beginning and end of each task, just print out 'new table produced' or something to that effect." The inline table (his 09-05 morning rule) was long and repeated; the artifact is the single live view.

**How to apply:** at each dispatch and each close: (1) update the `$rows` status text in `.loop\tools\Write-TaskList.ps1` (or `-StatusKv`), (2) run `.loop\tools\Write-Schedule.ps1` (writes `TaskList.md` + `schedule.json`), (3) `python .loop\tools\Build-Schedule-Html.py` into the scratchpad `schedule.html`, (4) republish via the Artifact tool with the SAME file path (keeps URL https://claude.ai/code/artifact/f5d668e7-169b-431f-a63c-2742bf637944), (5) copy the HTML over `claude\webpages\2026-09-05-vnext-schedule.html`, (6) print one line: "Schedule updated — <link> — next: <row>". Related: [[feedback_publish_artifacts_and_archive]], [[project_vnext_planning_sweep_2026-09-05]].

**Gene 2026-09-06 00:06: "Going forward add to the table the estimated versus actual time."** The schedule table (TaskList.md + the HTML artifact) carries an Actual column: agent-minutes per closed row from `.loop\tools\actuals.json` (row key → minutes), read by `Write-Schedule.ps1`, emitted in `schedule.json`, rendered by `Build-Schedule-Html.py` with a tile summing estimated vs actual over done rows. Record the actual in `actuals.json` at every close before regenerating.

**Gene 2026-09-09 20:39, second telling: "You are required to update the task list when a task starts and finishes."** The rule above already said dispatch AND close; what failed was ORDER. At 48.I's dispatch I wrote `dispatched.json`, then republished the `schedule.html` that had been built at the PREVIOUS row's close — so the live page showed 48.I as **Queued while its Executor was running**. The start half existed on disk and never reached the page.

**The dispatch sequence is fixed and the regeneration comes LAST:** (1) write `.loop	ools\dispatched.json` — `Write-Schedule.ps1` treats it as the live signal and it WINS over the status text; (2) set that row's status text in `Write-TaskList.ps1` to `DISPATCHED <MM-DD HH:MM> (model; criterion)` so the row still reads Started if `dispatched.json` is ever cleared early; (3) THEN `Write-Schedule.ps1`; (4) THEN `Build-Schedule-Html.py`; (5) THEN republish. Rebuilding before step 1 publishes a page that is already stale. The close sequence is the mirror: `[x] DONE` status text, record `actuals.json`, clear `dispatched.json` to `{}`, regenerate, republish.

**Check the page says what you think it says.** `schedule.json`'s `state` field is the cheap verification — `Started` for the running row, `Complete` with a non-null `actual` for the closed one — and it costs one command to read before publishing.

**Step 5's archive path DOES NOT EXIST on this machine (verified 2026-09-09 20:40).** `claude\webpages6-09-05-vnext-schedule.html` is not under `~`, not under `C:\devopslocal`, and a filename search for it returns nothing — so that step has been silently unperformable, not merely skipped. The canonical on-disk copy is `.loop	ools\schedule.html`, which `Build-Schedule-Html.py` writes directly and which every republish reads. Treat that as the archive unless Gene names a new location; do not recreate the old path on a guess.

**Gene 2026-09-09 21:24, THIRD telling — "You are still failing to update the task list at the start of the task." Three distinct faults, only one of which was the one previously recorded:**

1. **`dispatched.json` HAS THE WRONG SHAPE unless it is keyed BY ROW KEY.** `Write-Schedule.ps1:72-80` reads `{"<rowKey>": "label"}` or `{"<rowKey>": {"what": "...", "at": "..."}}`. Writing `{"row": "48.G2", "model": "opus", ...}` registers a phantom row named `row` and marks NOTHING in flight — it was inert for five consecutive rows on 09-09. The one row that appeared Started did so only through the fallback `$status -match 'DISPATCHED|RUNNING|IN PROGRESS'` on its status TEXT, by accident. **Verify with `schedule.json`'s `state` field after regenerating; never assume the write took.**

2. **A row starts when the ORCHESTRATOR starts it, not when the Executor launches.** Authoring and baselining a grader is ~13 of every ~45 minutes per row. Mark the row Started at the moment work on it begins, with a `what` naming the phase ("Orchestrator authoring grader u7b-12"), and update it at Executor dispatch.

3. **NEVER close a row and then stop to summarise.** On 09-09 the 48.I close was followed by a write-up and a ScheduleWakeup, leaving 18 minutes with nothing in flight and nothing marked Started. Close, mark the next row Started, dispatch, THEN summarise — this is the same rule as [[feedback_never_stop_to_report_between_rows]] and the schedule artifact is where its violation becomes visible to Gene.
