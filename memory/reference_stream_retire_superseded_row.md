---
name: reference_stream_retire_superseded_row
description: Stream kit has no retire/withdrawn state; a superseded blocked row holds Test-GroupClose OPEN-ROWS until the owner approves blocked -> done via a locked write
metadata:
  node_type: memory
  type: reference
  originSessionId: ad0cfc30-35f7-427e-8787-8e53baa8603a
  modified: 2026-10-09T14:48:05.730Z
---

The stream kit has no retire or withdrawn state. A planner can mark a row "SUPERSEDED, do not build" and drop it from the
group's integration task (G4.T075, 2026-10-05), but Test-GroupClose.ps1 still counts every non-fix code/docs/mockup row
of the group set (`Get-GroupSet`, by group field) and refuses with `OPEN-ROWS` while it is `blocked`.
Update-Task.ps1 only allows blocked -> integrated when a kept patch reverse-applies clean, so it cannot retire such a row.

**Why:** G4.T075 sat blocked from 10/05 to 10/09 and would have held the G4 close; G5.T143 followed the same path ("G4.T075 precedent").

**How to apply:** ask the owner (AskUserQuestion). On approval, make one write through `Invoke-TasksLocked` (lib\Streams.ps1) setting
state `done` with a history entry `{at, by, to:'done', note:'withdrawn by owner <date>: superseded by <row>, <plan item>'}`, then
`Add-Decision ... "OWNER-RETIRE <row> blocked -> done: ..."`. Re-run Test-GroupClose to confirm the row left OPEN-ROWS. Done 2026-10-09 for G4.T075.
Related: [[reference_gates_md_is_hand_maintained_and_drifts]].
