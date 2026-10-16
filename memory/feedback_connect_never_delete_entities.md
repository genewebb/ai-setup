---
name: feedback-connect-never-delete-entities
description: "Connect test workloads must NEVER delete an entity Connect did not create; no teardown at all — clean start, create, run"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 91871b75-b25a-4910-820d-badb705fb365
  modified: 2026-10-15T16:21:58.189Z
---

Connect workloads (D:\PowershellScripts\CrewChiefConnect\New-ConnectWorkloads.ps1) must never delete an entity that Connect does not create, and there is no teardown after a test.

**Why:** Gene, 10/15/2026, after connect-model-legacy-cleanup tried to delete the old base entities PDATA, PDATA15/30/60/120 and PDATA1M on SMVM1. Every delete returned 400, so nothing was lost. Gene's model: start from a clean environment (database reset to baseline), create the Connect entities, rely on the Dba_*_PDATA reference data already in the model, run the tests, and delete nothing afterwards.

**How to apply:** The legacy cleanup removes only non-family Connect strategies and service configurations. The 3 entity teardown workloads (main-entities-delete, profisee-to-profisee-target-delete, profisee-to-profisee-target-domains-delete) were removed from the generator. Never re-add an entity DELETE without Gene asking for it. See [[project-crewchief-connect-restructure-2026-10-13]].
