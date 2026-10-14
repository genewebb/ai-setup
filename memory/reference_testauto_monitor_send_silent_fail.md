---
name: reference-testauto-monitor-send-silent-fail
description: "TestAuto Monitor step \"COMPLETE\" but no row in monitor.tActivity = send failed silently; check nsb_log_*.txt beside the app and the MonitorDB Initial Catalog in secrets"
metadata:
  node_type: memory
  type: reference
  originSessionId: 06d2ca96-1f99-4120-9472-a1fceb0985e3
  modified: 2026-10-04T00:47:34.337Z
---

On 2026-10-03, workflow execution 10000231 on SMVMTR2 had its Monitor step marked COMPLETE, but no row was written.
- The cause was in `nsb_log_2026-10-04_0.txt` in `C:\Deploy\TestAuto\web`: `destination queue 'Services.Monitor@[messaging]@[Profisee]' could not be found`.
- Profisee `MonitorCommander.StartActivityAsync` logs a failed send and does not throw, so the step reports success.
- Root cause: `TestAuto.Web\SecretsTemplate\InitialSecretsTemplate.json` had `Initial Catalog=Profisee` fixed for ProfiseeDB, MatchingDB, MonitorDB, ConnectDB, PortalDB and DataDB.
  - CORPSQL03 has an empty `profisee` database; the real one is `Profisee300M`.
  - Step 2 (`MatchingSnapshotCaptureScenario`) hit the same wrong database.
  - Gene fixed the stored secrets.
- Code changes (uncommitted):
  - A new template key, `ServerNames:ProfiseeDatabaseName`.
  - `MonitorActivityWriter` reads the row back through `IMonitorActivityConfirmer` (60 s) and throws if the row is missing.
- The "End of Scenario 1 for Retail Client" row was added by hand as `monitor.tActivity` ID 17 in Profisee300M. `StartedTime` in that table is UTC.
- Save errors seen during the fix: the `/secrets` save returned 400 "Attribute Version not found" on `TestAutoSecrets`. Gene said it worked after fixing the database, so no attribute was added.

Related: [[reference-sqlcmd-quoted-identifier-profisee]]
