---
name: reference-stream-history-writer-is-by-not-session
description: "tasks.json history entries name their writer in `by`, not `session`; a planner-liveness check on history.session always reads \"no planner live\""
metadata:
  node_type: memory
  type: reference
  originSessionId: 185f5665-8770-43d9-9ee7-eb0430a4dfbe
  modified: 2026-10-03T18:52:35.826Z
---

Stream kit `tasks.json` history entries look like `{at, by, to, note}`. The writing session is in `by`
(for example `plan-23931cca`, `author-...`, `coord-...`); there is no `session` field.

On 2026-10-03 the coordinator's stand-in-planner liveness check filtered `$h.session -like 'plan*'`, which is always
empty, so it reported no planner while `plan-23931cca` was live. Both sessions planned at once; the coordinator's
Add-Tasks was refused on duplicate ids (G3.T294-296), and its Revise put two edges on the wrong rows. Those edges were
undone and the items forwarded back.

**How to apply:** check liveness with `$h.by -like 'plan*'` over history in the last 30 minutes, plus the decisions.md
tail (`[plan-...]` lines) and taken plan inbox items. Related: [[reference-stream-inbox-item-reopened-while-held]].
