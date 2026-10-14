---
name: profiseecrudtests-env-swap
description: Local Profisee on CORPLTR94 was re-pointed to the ProfiseeCRUDTests DB on 2026-07-14 (~12:47) for production CRUD testing; the swap window caused platform-wide outage that looked like CRUD test failures
metadata: 
  node_type: memory
  type: project
  originSessionId: 8b3c1f4d-e64e-4ae7-ba07-d5aecf1d0614
---

On 2026-07-14 (~12:47–13:14 local) the CORPLTR94 Profisee instance was switched/restored to database **ProfiseeCRUDTests** (branch bug/production_testing/genewebb). During the window: auth couldn't open the DB ("login failed" + "session is in the kill state"), gateway 500.30, WCF GetLicenseInformation/GetSettings content-type errors, 443 connection refused (WorkflowMonitorJob failed every minute), `/health` 500. All transient — after ~13:14 the gateway was up (26.1.0.1795) and errors stopped. DB is ONLINE, `CORP\svc_web` mapped with `prof_exec` in both Profisee and ProfiseeCRUDTests.

**Why:** CRUD test failures in that window were environmental (platform mid-swap), NOT the .NET 10 / case-insensitive-JSON code changes (full HEAD~4..HEAD diff of the CRUD path reviewed clean).

**How to apply:** When "tests suddenly failing" coincides with a Profisee DB/environment swap, check Seq for the 500.30 / connection-refused / kill-state signature first ([[import-500-gateway-startup]] pattern). Residual risks after a swap: TestAuto's x-api-key may not exist in the new DB ("No client with id ... found. aborting" in auth logs → re-run secrets update per testauto-secrets-management), and `RunDatabaseMaintenance` recurring job fails config with missing `DATABASEMAINTENANCEISENABLED` key.
