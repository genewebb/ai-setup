---
name: reference-beat-loop-dies-with-background-limit
description: "A background beat loop for a stream-build claim stops at the 2 h background-task limit; if the session then goes idle, the watchdog reaps the claim and another builder takes the row."
metadata:
  node_type: memory
  type: reference
  originSessionId: 722ba0bb-1652-4d9f-8699-d690f1083b42
  modified: 2026-10-03T17:04:20.442Z
---

On 2026-10-02 the builder claimed G2.T115, started a 5-minute beat loop as a background task, and then the session went idle mid-step 4b. The loop hit the 2-hour background limit (last beat 18:49Z). The next morning stream-status reaped the stale claim and the worktree, and build-202610011145-e4c9 claimed the row 90 seconds later. The only artifact left was an unfinished draft check under `.streams\checks\`.

**Why:** a background beat loop is not durable. It dies at its time limit, and a session that is idle does not notice.

**How to apply:**
- While holding a claim, restart the beat loop before its 2-hour limit.
- Keep a ScheduleWakeup of 30 minutes or less, so the session checks the claim itself.
- If a claim is lost, tell the new holder through the stream-build inbox about any half-made artifacts.

Related: [[reference-stream-build-beat-during-long-builds]]
