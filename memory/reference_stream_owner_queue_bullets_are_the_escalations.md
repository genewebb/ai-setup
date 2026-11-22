---
name: reference_stream_owner_queue_bullets_are_the_escalations
description: "In .streams\\owner\\questions.md the '- ' bullet lines are the real owner escalations; the unprefixed lines are already-applied defaults"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 791f1040-13cb-474c-8883-7a1bc9dc8c14
  modified: 2026-09-29T18:24:10.957Z
---

`.streams\owner\questions.md` mixes two things that look identical to `Get-StreamStatus.ps1`, which counts
every line carrying ` | ` as one owner-queue entry (467 on 2026-09-29):

- Lines starting with `- ` — genuine escalations addressed to the owner. 32 of the 467. These are the ones
  worth presenting as choices.
- Lines with no `- ` prefix — questions a session already answered with its recommended default and logged.
  Per `stream-howto.md`, the owner does nothing if the default is right. These are not blocking.

So "how many owner questions are outstanding" has two very different answers. Triage by the bullet prefix
first, and join the task id against `tasks.json` state: on 2026-09-29, 330 of the 467 sat on `ticketed` tasks
(override still cheap) and 65 on `built`/`integrated` ones (override costs a rebuild or a fix task).

Retiring one: rewrite the line IN PLACE with a leading `RESOLVED ` token, rest byte-identical.
`Lines()` skips `^\s*RESOLVED\s`. Never append a second line. For an owner OVERRIDE, keep the original text
and append ` | OWNER <date>: <decision>` so the record still reads as written, then file the action with
`Send-InboxItem.ps1 -To stream-plan` — the token alone changes no ticket or write set.

See [[project_stream_kit_replaces_myloop]], [[reference_stream_stale_read_blocks_and_bugs]],
[[feedback_auto_approve_recommendations_speedy_build]].
