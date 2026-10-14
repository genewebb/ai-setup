---
name: project-speedy-build-campaign-2026-09-26
description: "2026-09-26 Speedy real-work campaign priority order (RefData, Backup/Restore, Steps, Workflows, TestAuto, Dial); one group at a time; .loop stays in repo"
metadata:
  node_type: memory
  type: project
  originSessionId: 63da107a-d636-46d6-b6aa-9e8658ff93aa
  modified: 2026-09-26T16:56:58.304Z
---

Gene 2026-09-26 set the Speedy implementation order: 1 Reference Data, 2 Backup and Restore, 3 Steps, 4 Workflows, 5 TestAuto (a couple of scenarios end to end: definition, profiles, run, metrics), 6 Dial Up/Down.

Per group: build task list of outstanding work, work it, resolve questions, confirm functional + UI tests, close out. Then the next group. Later a fresh /myloop gets rows for ONE group at a time.

Requirement status at 2026-09-26: RefData, Backup/Restore, all FEAT-STEP-* READY; Workflows partly (WVC-CANVAS/FLOW, UI-WORKLOADS, WORKLOAD-RUN READY; FEAT-SCENARIO-DEFINITION-001 REVIEW, ACTIVITY-FLOW DRAFT); TestAuto scenario-* features REVIEW. In-flight amendments: refdata-007-consumer-scope-r1 (narrows AC-REFDATA-007, rebase queued via requirements row C0), backup-location-install-r1 (coding row BAK-LOC.1).

**.loop location:** Gene asked for it outside the repo, but myloop hard-wires `<RootPath>\.loop` and its snapshot/constraint gates diff the repo at RootPath, so Gene said leave `.loop` in the repo (2026-09-26).

**How to apply:** don't propose moving .loop again. Check the two in-flight sessions (requirements MP-9, coding BAK-LOC.1) before writing shared files.
