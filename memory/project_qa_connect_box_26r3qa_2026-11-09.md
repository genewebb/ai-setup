---
name: project-qa-connect-box-26r3qa-2026-11-09
description: QA tester sets up own Connect box from pack zip 20261109-141040 with ProfiseeVersionCode 26R3QA; checklist in vault Connect\QA Connect Setup 26R3QA.md
metadata:
  node_type: memory
  type: project
  originSessionId: 4d4c88ac-d91f-49d4-ac6c-7b13b8d68d9c
  modified: 2026-11-09T20:25:14.862Z
---

11/09: Gene prepared `Q:\Work\Work\99 Documentation\Connect\QA Connect Setup 26R3QA.md` (short version of help page
62_PackConnectNewMachine) for a QA tester's own boxes. Pack zip `crewchief-backup-20261109-141040-pack-connect.zip`
lives on `\\SMVMTR1\c$\Deploy\CrewChief\Backups`; verified it matches repo commit 6f62740e reference data
(SMVMTR1/SMVM1/SMVMDB1, P2P SMVM2/SMVMDB2, 26R3T, blank service names, Profisee-analytics pools, 215 workloads).

Gaps found in the QA doc 11/09 (all FIXED in the doc 11/09 15:25): stray `w` on line 1; does not say keep `connect/urls:ScenarioMgtBaseUrl`
(speedmerchantstest = PROD DB, so QA's 54 workflows/run profiles/tags land in PROD model); says pack defaults "26R3"
but zip ships 26R3T; value table lacks service account + app-server admin account; drops the Get-Service check.

Gene 11/09: QA uses a COMPLETELY DIFFERENT machine set, no SMVMTR*/SMVM* box at all (every lab value in the six
sets must be replaced, P2P target included). Remote provider targets are still shared with the lab boxes.

**Why:** real implementation pending; Gene asked to be ready to help.
**How to apply:** walk QA through steps in order; one-box rule vs SMVMTR1/TR2 for remote providers. See
[[crewchief-connect-test-rounds]].
