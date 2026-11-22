---
name: feedback-isolation-status-frame-container-isolation
description: "Isolation status/ETA questions are about container isolation (cross-impact between instances); the SQL small-transaction slow mode is a separate problem, report it apart"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 7986e46e-eb36-4bdb-a0ee-12f91e19b099
  modified: 2026-11-19T19:42:07.255Z
---

When Gene asks for status, progress or an ETA on the isolation work, frame the answer around **container isolation**: whether one instance's load changes another instance's figures (the P7 verdict on the judged figures, Not isolated / Not decided / Isolated, positive controls, Unvalidated figures).

The SQL small-transaction slow mode (8-connection oltp bursts inside one instance) is a **different problem**: noise inside an instance, not cross-impact. Keep it out of the isolation verdict and ETA. Report it in its own short section, if at all.

**Why:** Gene said 2026-11-19 14:41: "frame the answer I am concerned about container isolation when I ask these questions, the sql issue is a different problem".

**How to apply:** Lead with the isolation verdict and its ETA (P7 days on the final setup). List open isolation gaps (e.g. network bulk Unvalidated). Put the SQL flip under a separate heading such as "Separate problem". Related: [[feedback-isolation-goal-not-performance]].
