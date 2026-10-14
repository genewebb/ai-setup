---
name: project-crewchief-localrunas-account-mismatch
description: CrewChief local Run-As only works when the Run-As account IS the CrewChief service account; any other account dies with STATUS_DLL_INIT_FAILED (0xC0000142)
metadata: 
  node_type: memory
  type: project
  originSessionId: 12c5e146-c909-4a33-a49f-6cce5ea7b60f
  modified: 2026-07-31T01:09:44.166Z
---

CONFIRMED 2026-07-30 by four runs where the account was the only variable:

| Run-As | CrewChief service account | Result |
| --- | --- | --- |
| speedmerchants | speedmerchants | ran |
| qaautomation | speedmerchants | 0xC0000142 |
| agenewe | qaautomation | 0xC0000142 |
| agenewe | agenewe | ran |

Symptom text: `The local Run-As driver produced no parseable result (running as 'X';
powershell.exe exit code -1073741502). stderr=[]`. `-1073741502` = `0xC0000142` =
STATUS_DLL_INIT_FAILED. The child process IS created (an exit code comes back) and then dies in the
loader before it can write `result.json`.

Cause: `LocalRunAsCommandRunner.LaunchWithToken` calls `CreateProcessWithTokenW` with `StartupInfo`
leaving `lpDesktop` null, and nothing grants the Run-As account's SID access to the service's session-0
window station/desktop. It survives only when that SID already has access — i.e. when it is the
service's own account. So the feature works for exactly the identity that does not need it.

**Why:** every remote-lab / automation account is by definition NOT the CrewChief service account, so
this breaks the whole point of per-step Run As ([[project_crewchief_local_runas_direct_logon]]).

**How to apply:** until fixed, either match the Run-As account to the service account, or better —
run the CrewChief service AS the privileged account and DELETE the workload/step Run As entirely, so
steps execute in-process on the service token (service tokens are never UAC-filtered, and no per-step
logon means no lockout exposure). Fix direction: grant the Run-As SID access to the window station and
desktop before launch, and set `lpDesktop` explicitly.

Compounding diagnosability defect: the per-run work folder is deleted in a `finally`, destroying
`stdout.txt`, `stderr.txt` and `driver.ps1` — which is why the error always reports `stderr=[]` and
explains nothing. Retain the work folder when the driver produces no parseable result, and log its path.

Distinct from [[project_crewchief_localrunas_cmdline_1024]] (0x80070057, lpCommandLine cap) — that one
is fixed; this one is not.
