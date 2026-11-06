---
name: project_matching_test_board_2026-11-05
description: "Matching status board = SMVMTR1 /MatchingTesting/Status.html, built from C:\\tmp\\matching-status\\MatchingTestBoard.html (BOARD data block) via build-status.sh; republish on every scenario result"
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T17:22:23.639Z
---

Gene 11/05 12:16: "Make this a regular status page in the same place as the connect testing page" (replaces the
Matching Run Flow artifact 5DhG1kbvYw2Ui7cuW2S5wC as the live status view; that artifact was left as is).

- URL: https://smvmtr1.corp.profisee.com/MatchingTesting/Status.html (beside /ConnectTesting/, same web.config:
  default doc Status.html, cache disabled; plain folder, no IIS app).
- Source: `C:\tmp\matching-status\MatchingTestBoard.html`. All state in `const BOARD = {...}`: asOf, lastRun, now,
  sizes, scenarios, runs["<size>|<scn>"] = {s: pass|run|wait|fail|later, why}, history rows
  [when, size, scn, execution, pass|fail|void, note], setup, open. Edit data only.
- Publish: syntax check (`awk` the script block + `node --check`), then `sh /c/tmp/matching-status/build-status.sh`
  (wraps, copies over SMB, prints HTTP status).
- Times on the board are EST; TestAuto PROD execution times are UTC (subtract 5).

**How to apply:** republish whenever a Matching scenario run ends (pass, fail or void). Same pattern as
[[project_connect_test_board_2026-10-30]]; pack details in [[project_crewchief_workload_packs_2026-11-04]].

**11/05 21:40 state:** 1K/10K/100K chains all passed on the old Timings collection (100K: S2 39 min, 3b 77, 3c 101). Activities build deployed 21:20, pack workflows pushed 21:25 (timing steps -> UnifiedMatchingApiExecutionActivities). 1K phase-2 test chain started 21:27. Board republished 21:40.

- 11/06 09:10: 1K chain PASS with new Activities collection (run 2, 23:03); Activities tab + Workloads page checked OK. Purged WE 100010281 (orphan) and 100010409 (failed run 1) via Run Purge UI, then Rebuild summaries (summary rebuild DOES run CreateMatchActivitySummary, SqlMatchingStore.cs:170; dialog text omits it). Board asOf 11/06 09:10. Next: 10K/100K with Activities.
