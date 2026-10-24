---
name: project-crewchief-configure-remove-instance
description: "CrewChief Configure step Remove instance operation (built 10/21, uncommitted in speed-merchants) + suspected Configuration.exe service-name defect to verify live"
metadata:
  node_type: memory
  type: project
  originSessionId: 16b17f2f-4dad-460d-8c1e-eb7310cde1d9
  modified: 2026-10-21T20:15:18.093Z
---

Configure step got `operation: Configure | RemoveInstance` (2026-10-21, branch bug/26r3_slowdown_testing/genewebb, NOT committed — speed-merchants never commits).
Remove = `/removeFromCluster:TRUE /maestroWebURL [/webSiteName] [/clientId]` only; other switches + raw args kept on step, unsent. Preflight state read (nothing present = success, exe not run), exe, unregister log-scan, postflight verify (leftover IIS apps/pools/service fail step). DB/logins/files/MSI not removed. UI: toggle above stepper with inline confirm, red active step, danger banner, Remove page (3 full value cards), red "Removes instance" chip (RemovesInstanceChip) on Steps list/card + WorkloadEditor.

**Why:** Gene asked to add instance removal to the Configure Profisee Platform step; decisions taken via AskUserQuestion (parity + verify, URL required via picker, missing = no-op, local verify only, direction A toggle).

**How to apply:** Still needs a LIVE test on a real box. Suspected platform defect (code reading only, `WebAppConfigurationContext.cs:338` LoadConfig sets ServiceName="Profisee"): Configuration.exe's DeleteService likely misses the real `Profisee {ver} ({app})` service, so the postflight should FAIL naming the service — confirm on first live run before blaming CrewChief. Also unverified live: Get-WebApplication path shape, IIS app-name case. Related: [[feedback-no-commits]].
