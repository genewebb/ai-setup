---
name: feedback_connect_no_local_profisee
description: "Connect work must not use CORPLTR94's local Profisee instances; all live info and tests come from SMVM1/SMVM2/SMVM3"
metadata:
  node_type: memory
  type: feedback
  originSessionId: c233553b-f77d-4b9e-8e31-0e62ebe2831b
  modified: 2026-11-04T15:44:14.523Z
---

Gene 11/04 10:43: "You should not be using my local profisee instances for anything right now all your information should come from SMVM1, 2, or 3."

**Why:** Gene is rebuilding his local setup (MyDevProfisee, to avoid 3 instances); the local /ProfiseeImport and /Profisee are not a test bed.

**How to apply:** No REST, SQL (corpltr94_profisee MCP included) or CrewChief runs against CORPLTR94 Profisee. Live tests of the Connect empty-model bootstrap run on SMVMTR2 (Main SMVM2, target SMVM3); read-only reference = SMVM1. Plans that say "Local first" are superseded. Related: [[project_crewchief_schedules_2026-11-03]], [[project_connect_test_board_2026-10-30]].
