---
name: feedback_mark_row_started_at_dispatch
description: "Gene wants the live schedule to show which row is running right now — mark it Started at dispatch via dispatched.json, not at close"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-09T02:50:48.452Z
---

Gene, 2026-09-08 12:02: *"Why is 59.3f marked as queued instead of started — you need to update each task
as it starts."* He had asked the same thing once before (09-07: *"Nothing is showed as in progress on the
vNext Programme Schedule, what is in flight"*), so this is a repeat correction, not a first one.

**Why:** the page is how he sees the loop without interrupting it. A schedule where the running row reads
"Queued" cannot answer the one question he actually asks it — what is happening right now — and it makes
the whole status column untrustworthy rather than just incomplete.

**How to apply:** `Write-Schedule.ps1` always understood three states (Queued / Started / Complete), but
`Started` was derived from the row's status TEXT, which is only rewritten at close — so nothing ever wrote
it. Fixed 09-08 by adding `.loop/tools/dispatched.json`, read the same way `actuals.json` is:

```json
{ "59.3f": { "at": "2026-09-08T12:12", "what": "<one line on what it is doing>" } }
```

`at` feeds the page's **Status Time** column (Gene 09-08 12:46: *"the time is either when it starts or when
it finishes and is blank for queued"*). A bare string is still accepted for entries written before that
shape existed, but it leaves Status Time empty — always write the object form.

Add the key **at dispatch**, remove it **at close**, then regenerate and republish. A key present forces
`state = Started` and prefixes the row's status with `▶ <text>`.

**The path is `.loop/tools/dispatched.json`, beside `actuals.json` — NOT `.loop/dispatched.json`.**
`Write-Schedule.ps1` resolves it from `$PSScriptRoot`, so a copy one directory up is read by nothing and
the row silently stays Queued. Got that wrong once at 59.3i's dispatch; the symptom is a regenerate that
reports the right row count and still shows `state=Queued`.

Deliberately a separate file rather than an edit to `Write-TaskList.ps1`: that file is hand-edited,
five-element tuples with doubled apostrophes, and **a malformed row is dropped silently** — see
[[reference_schedule_json_is_the_backup]]. It cost three recoveries in one session, including a stamped
row that simply vanished from the table. A dispatch marker has to be the cheapest write in the loop or it
will not survive a busy iteration.

Related: [[feedback_iteration_close_print_remaining_tasks]], [[feedback_vnext_schedule_format]].
