---
name: project-test-lab-topology-cadence
description: "Perf test lab boxes and release cadence (Gene 11/07/2026): SMVM1-3 for Connect/CRUD, CORPVMHA1+CORPSQL03 for large runs, 26R3 now, 26R4 next"
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-07T12:42:04.430Z
---

Gene 11/07/2026:
- Older versions retired. Build/verify packs on 26R3 (no Profisee Windows service; service keys blank). Next real round: 26R4, as early as week of 11/09.
- Cadence per release: a mid-release check and a post-release run of Connect, Matching and CRUD; plus Matching-only rounds.
- Connect and CRUD run on SMVM1, SMVM2, SMVM3 (each with its own test server SMVMTR1/2/3 and DB server SMVMDB1/2/3).
- All LARGE testing runs on app server CORPVMHA1 with DB CORPSQL03, driven from any free SMVMTR* box. So a pack's app/DB servers are never assumed to be the CrewChief box; everything comes from reference data.

**Why:** packs must move between these boxes with only reference data + the Profisee-config-and-rebackup step.
**How to apply:** design every pack for remote app/DB servers; 1M/large sizes target CORPVMHA1/CORPSQL03. Related: [[project_pack_backup_inventory_new_machine_2026-11-07]], [[project_crud_pack_design_2026-11-07]].
