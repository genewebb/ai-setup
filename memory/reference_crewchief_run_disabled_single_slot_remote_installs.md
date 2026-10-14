---
name: crewchief-run-disabled-single-slot-remote-installs
description: "CrewChief \"Run button disabled everywhere\" = another run holds the app-wide single run slot; header chip \"Running: <name>\" says which. Remote installs live at \\\\<host>\\c$\\Deploy\\CrewChief\\web\\data\\runs.json (SMVMTR2, SMVMTR3 as of 2026-09-15)."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 666fc6be-b49a-48c7-af9d-ac1a393edca1
  modified: 2026-09-15T17:56:29.908Z
---

**Symptom:** every Run button (workload list, card, editor, Resume) disabled. Header chip shows `Running: <workload>`.

**Cause (by design, not a bug):** `WorkloadRunCoordinator._isBusy` is one in-memory slot per CrewChief process. `Workloads.razor` `AnyRunBusy`, `WorkloadCard.RunBlocked`, `WorkloadEditor.RunDisabledReason()` all read `Coordinator.IsBusy`. Slot clears only when the engine returns (`RunToCompletionAsync` finally block). Grid-view RadzenButton title stays "Run" (no reason shown); card + editor show "Another run is in progress".

**How to check which instance/run:** each install's `data\runs.json` (RunHistoryFile) gets the record with Outcome `Running` at start. Local deploy: `C:\Deploy\CrewChief\web\data\runs.json` (ports 5030/5031). Remote installs reachable read-only via admin share: `\\SMVMTR2\c$\Deploy\CrewChief\web\` and `\\SMVMTR3\c$\Deploy\CrewChief\web\` (SMVMTR1/SMVM1/SMVM2 had none 2026-09-15). Logs: `<install>\logs\crewchief-YYYYMMDD.log` — a run always logs, so a silent log since startup means no run on that instance.

**Why:** 2026-09-15 Gene reported Run disabled "in latest CrewChief"; the local box had no run, the live one was on SMVMTR3 (26r2-matching-restore-db-ready-to-match, 19 steps). Check the header chip and the remote runs.json before hunting a code bug. See [[index_crewchief]].
