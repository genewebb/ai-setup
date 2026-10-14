---
name: reference_testauto_service_boot_7009_timeout
description: TestAuto Windows Service stays Stopped after reboot with SCM event 7009 30s timeout while CrewChief starts fine - fixed with sc failure recovery actions
metadata: 
  node_type: memory
  type: reference
  originSessionId: 02caa20e-5e33-4ece-b132-07431cd7a8cb
  modified: 2026-08-10T14:28:44.473Z
---

**TestAuto does not come up after a reboot while CrewChief on the same box does.** Verified CORPLTR94 2026-08-10 (boot 09:29:08): System event log, **SCM event 7009 at 09:34:43 — "A timeout was reached (30000 milliseconds) while waiting for the TestAuto service to connect"**, plus 7000. Service left `Stopped`, and `web\LogFiles\SystemLog.log` had **no entries after the pre-reboot shutdown**, so the process never reached the file sink.

The asymmetry is NOT registration — `sc qc` showed both services identical: `AUTO_START (DELAYED)`, same account, no dependencies. It is what startup **does**: CrewChief is files-only and signals `SERVICE_RUNNING` almost immediately, whereas TestAuto loads secrets over REST and opens SQL for Hangfire *before* the host starts. At boot those local dependencies (SQL, Profisee/IIS) are themselves still starting, so the 30s SCM budget expires. `delayed-auto` does not cover it — it was already delayed-auto when this happened.

Fix (in `TestAuto.iss` `InstallOrUpdateService`, and applied live via `sc.exe`):
```
sc failure TestAuto reset= 86400 actions= restart/60000/restart/120000/restart/300000
sc failureflag TestAuto 1
```
`failureflag 1` is the load-bearing part: recovery actions otherwise fire only for a **crash**, not for a start-timeout. Verify with `sc qfailure TestAuto` and `sc qfailureflag TestAuto` (expect `FAILURE_ACTIONS_ON_NONCRASH_FAILURES: TRUE`).

This retries rather than shortens startup. The deeper fix — moving the secrets/SQL work off the pre-`SERVICE_RUNNING` path into background hosted services so the service signals fast — is NOT done and remains the real remedy if the retries ever prove insufficient.

Related: [[project_testauto_service_install_plan]], [[reference_testauto_https_localhost_name_mismatch]]
