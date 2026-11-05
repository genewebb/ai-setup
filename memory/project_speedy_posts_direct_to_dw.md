---
name: project-speedy-posts-direct-to-dw
description: "Speedy (vNext) writes metrics straight to the data warehouse with real SQL types, not Profisee entities"
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T21:55:07.304Z
---

Speedy will post metrics directly to the DW, so all SQL data types are available (decimal, datetime2, bigint, time). Today's TestAuto metric entities live in Profisee, which has no time-span type: durations are Number, and formatted text when shown.

**Why:** Gene, 2026-11-05, while designing UnifiedMatchingApiExecutionActivities.
**How to apply:** when designing a Profisee metric entity now, store raw values (for example seconds as Number with 3 dp, no HH:MM:SS text copies) so the move to Speedy is a straight type swap. See [[project-matching-test-board-2026-11-05]].
