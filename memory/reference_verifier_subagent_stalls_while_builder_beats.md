---
name: reference_verifier_subagent_stalls_while_builder_beats
description: A blind verifier subagent can stall for hours at zero output bytes while its builder keeps beating the claim, so no watchdog can see it; stream-build SKILL.md step 7 now bounds it at 30 minutes.
metadata:
  type: reference
---

A `foreman-verifier` subagent can hang indefinitely: on 2026-09-30 a second verifier on `G1.T16` ran **five hours** with zero output bytes, left the worktree untouched, and never answered a direct status message. The builder session kept beating its claim the whole time, so `Invoke-Watchdog.ps1` saw a healthy row, and `G1.T16` went 430 minutes with no history line against a 115-minute estimate. Nothing in the board can distinguish this from a slow build — the kit calls "fresh beat + old history" a false flag on purpose, and it is the only symptom.

The bound now lives in `stream-build/SKILL.md` step 7, after the `**FAIL**` bullet: a verifier that has run 30 minutes at zero output bytes with an untouched worktree is stopped and relaunched; re-prove the worktree byte-identical to the exported patch (CR stripped) before the relaunch so the new verifier grades the same content; beat the claim while waiting; log one history line naming the stall, how long it ran and the HEAD. A relaunch is **not** a FAIL and does not count toward the two-verdict limit.

Practical consequence for anyone supervising: a builder that beats but writes no history for far longer than its estimate is worth one direct status message, and a stalled verifier — not a stuck builder — is the likeliest cause. See [[reference_stream_owner_queue_bullets_are_the_escalations]] and [[reference_loop_does_not_wake_on_subagent_completion]].
