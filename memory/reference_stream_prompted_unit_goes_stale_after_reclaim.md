---
name: reference_stream_prompted_unit_goes_stale_after_reclaim
description: A -Live stream unit waiting on a permission prompt keeps its tab after the watchdog frees its claim; approving the prompt later lets a dead claim act on a reclaimed task
metadata:
  node_type: memory
  type: reference
  originSessionId: f7f972f6-eecc-483b-b761-e6144a85ff21
  modified: 2026-10-09T03:50:32.040Z
---

On 2026-10-08/09, two build units sat on Bash permission prompts (pkill commands) for over 2 hours: build-202610082029-63c9 on G4.T124 and build-202610082152-b70a on G4.T054.

The runner json reported "waiting on owner" for the whole time. The board meanwhile moved on: the watchdog freed G4.T124 at 02:40Z (stale beat) and salvaged its worktree, and another builder claimed it again in the SAME worktree. G4.T054 was built by a different session.

The prompt does not go away. If the owner approves it later, the old session resumes on a task it no longer holds.

**How to apply:** each coordinator tick, compare each "waiting on owner" unit's session with the current `claim.session` of its task in tasks.json. When they differ, tell the owner to deny the prompt and end that unit, not to approve it. Related: [[reference_runner_prestage_ghost_sessions]].
