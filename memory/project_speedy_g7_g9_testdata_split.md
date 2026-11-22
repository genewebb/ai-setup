---
name: project_speedy_g7_g9_testdata_split
description: "Owner 2026-10-10 chose to plan the 306 unplanned clauses (17 reqs, test-data family + CLI + rest) as THREE groups G7-G9, not one G7"
metadata:
  node_type: memory
  type: project
  originSessionId: 6a305cf0-eed3-40c7-b572-c6e848aaec04
  modified: 2026-10-10T16:30:27.004Z
---

On 2026-10-10 at 12:30 EDT the owner chose to put the 306 unplanned clauses into three groups, all queued after G6:
- G7 "Test Data Engine": ENGINE, GENERATION, CONTENT and MUTATION (125 clauses).
- G8 "Test Data Entry and Import": ENTRY, CONSOLE and IMPORT (81 clauses).
- G9 "Test Data Run, Report and Deploy": RUN, REPORT, DEPLOY, plus CLI, LIBRARIES, UX-LIBRARY-LIST, WEB-HOST and three NFRs (100 clauses).

The 306 are clauses that no group names. They come from 17 requirements: the test-data family plus CLI, libraries, the web host and three NFRs.

The planner inbox item is IN-20261010163017-3ab6. It supersedes IN-20261010144938-96bc.

**Why:** Groups close one at a time, so one 306-clause group would be bigger than G3 (282 clauses), the slowest group so far. Groups the size of G4-G6 (75-114 clauses) close sooner and give the owner test checkpoints.

**How to apply:**
- Only /stream-plan creates groups. The coordinator may not (stream-coordinator SKILL.md:144: "never change a group's scope").
- The documented route to a new group is a start prompt with a groups: list. A planner inbox item may not be picked up.
- If G7-G9 have not appeared on the board, tell the owner to start a fresh /stream-plan session with the start prompt.

Related: [[project_stream_kit_replaces_myloop]]
