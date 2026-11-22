---
name: reference_stream_late_verifier_overwrites_verdict
description: "A stand-in build agent that released a task as \"verifier hung\" can still get the verifier's answer hours later and overwrite the next run's verdict file"
metadata:
  node_type: memory
  type: reference
  originSessionId: f7f972f6-eecc-483b-b761-e6144a85ff21
  modified: 2026-10-09T12:49:24.463Z
---

On 2026-10-09 the coordinator's first stand-in on G4.T041 (build-sup-202610090910) released the task at 11:50Z, saying verifier round 5 had hung.

- A second stand-in then ran a fresh round 5. It passed at 12:19Z, and the task was integrated at 12:24Z.
- The first agent was still alive. Its "hung" verifier returned FAIL at about 12:48Z, about 3 hours after it started.
- The first agent then wrote that FAIL into the same `.streams/verdicts/G4.T041.verdict5.md`, so the PASS text was lost.
- Both verifiers had found the same two gaps. The second graded them Low advisory; the first called them a FAIL. The fix was a follow-up row, G4.T134, not a revert.

**How to apply:** when a stand-in releases a task because its verifier hung, end that stand-in agent before claiming the task again. Never resume it after the release. Give the next run a distinct verdict file name, for example verdict5b. Related: [[reference_stream_prompted_unit_goes_stale_after_reclaim]].
