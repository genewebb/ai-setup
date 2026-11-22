---
name: reference_stream_kit_update_task_needs_beat
description: Stream-kit Update-Task.ps1 only refreshes claim.beat when -Beat is passed; a -Note-only heartbeat lets the watchdog steal the task
metadata:
  type: reference
---

`Update-Task.ps1` refreshes `claim.beat` ONLY under `if ($Beat -and $t.claim)`. A heartbeat written
as `-Note "still working"` with no `-Beat` writes history but leaves the beat at claim time.
After 45 minutes `/stream-status`'s watchdog calls the claim stale and returns the task to
`ticketed`; the next `Update-Task` from the original session then fails with
`CLAIM-LOST <task> (no longer held by <session>)`, exit 3, and the work in flight is orphaned.

Pass `-Beat` on EVERY heartbeat, and on any long step boundary. Losing the claim is recoverable if
the patch was exported first (`Export-TaskPatch.ps1`), so export before any long wait.

Related: [[reference_stream_author_takeover_race]] · [[reference_pwsh_call_operator_breaks_npx]]
