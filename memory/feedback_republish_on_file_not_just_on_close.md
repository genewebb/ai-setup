---
name: feedback_republish_on_file_not_just_on_close
description: "Regenerate and republish the schedule after ANY Write-TaskList.ps1 edit — filing a new row counts, not just closing one."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: aa701f44-5fa5-4edf-ae81-2fc43ee32e4c
  modified: 2026-09-11T14:45:09.603Z
---

Gene, 2026-09-11 10:42: *"There is no 48.RV13C in the task list keep it up to date"*.

He was right. `48.RV13c` had been written into `Write-TaskList.ps1` and `schedule-order.txt`, but I
went straight from filing it to dispatching the next Executor without running `Write-Schedule.ps1` +
`Build-Schedule-Html.py` + the Artifact publish. The published page was two rows behind reality.

**Why:** my habit had attached the republish to CLOSING a row. Filing one mid-turn — which is where
most new rows are born, out of an Executor's deviation-note — skipped it entirely.

**How to apply:** any edit to `Write-TaskList.ps1` or `schedule-order.txt` ends with regenerate +
publish, in the same turn, before dispatching anything. Filing, correcting a row's text, and closing
are all the same trigger.

Check the `N tasks` count the HTML builder prints against
`grep -c "^    @('" .loop/tools/Write-TaskList.ps1` every time — they must match, and a mismatch is
the only signal that a malformed row parsed clean and vanished
([[reference_write_tasklist_row_silently_dropped]]).

**Why it matters:** the schedule page is the only view Gene has of the programme
([[reference_schedule_json_is_the_backup]]). A row that exists only in a PowerShell source file he
does not read is a row that does not exist to him — and he is the one who decides what gets built at
the gate.
