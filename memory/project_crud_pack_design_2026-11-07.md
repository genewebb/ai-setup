---
name: project-crud-pack-design-2026-11-07
description: "CRUD workload pack design decisions 11/07 (sizes, stewardship durations, users, snapshot reset, business-rule removal, 26R3T, SMVM1 single-box)"
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-07T17:03:32.677Z
---

CRUD pack (`CrewChief/packs/crud`), Matching blueprint, decided with Gene 11/07/2026:
- Version 26R3T while building; convert to 26R4 when clean.
- Topology: ONE app server (SMVM1), ONE test server (SMVMTR1), ONE DB (SMVMDB1); no cross-server targets.
- Source = TDATA entity (10M) inside the Profisee DB (CDP reads it); targets ZDATA (create/update/get/delete) and TDATA (stewardship). No ModelSourceCRUD needed.
- Today's reference workflows (PROD TestAuto): 10000195 "26R3 Release CRUD Testing No Business Rules", 10000197 "... With Business Rules", tags Current Release, category CRUD; 18 steps; keep untouched.
- Sizes 1K/10K/100K/1M for create/update(85/10/5 already)/get/delete; stewardship durations 1/5/15/30/60 min; widths 15/30/60/120 (FF+domain 10+5, 20+10, 40+20, 70+50); users 1/10/100 (keep 1 for parity).
- All stewardship steps use source TDATA (today steps 10-13 wrongly use PDATA; Gene chose fix).
- Reset (Gene 11/07 after spike): FULL RESTORE of profisee_CRUD_base.bak before every test (5.4 min). Snapshot rejected: revert after stewardship-like churn took 10.1 min (37.5 GB sparse). No snapshot ever exists.
- Delete: keep today's filter Contains([Code],'_New') OR Contains([Name],'_Changed') (deletes the ~15% Update touched; PROD 26R3: Create 1M, Update 150K, Delete 150K). Generated workflows tagged AUTO + CRUD + version + machine + size; NOT 'Current Release' (Gene moves it by hand).
- Business rules: base DB carries 20 rules (10 on TDATA + 10 on ZDATA); No-BR runs restore then delete all 20 rules (Profisee REST, never SQL); the next restore brings them back. Gene supplies the base DB.
- PDATA is the standard structure + test data for Connect AND CRUD (TDATA/ZDATA are PDATA copies). CRUD exercises the REST API (gateway); Connect goes through CDP. Base backup: E:\SQLBackups\profisee_CRUD_base.bak (made 11/07: SIMPLE recovery, 16 GB log, 12.4 GB compressed; Gene deleted the original Profisee26R3CRUDTestsWithBusinessRules.bak).
- Workflows (20): core per size x BR mode (8) + stewardship per duration x BR mode (10) + `crud-1m-release-{br,nobr}`
  (Gene 11/07: 1M release = PROD's 18 steps in PROD order, one restore, Delete last). Tests: 1K/10K/100K = core +
  5/15/30-min stewardship (my call, unconfirmed), 1M = release run, smoke = 1K core br + 1-min steward nobr.
- Gene 11/07: TargetEnvironmentName + TargetApplicationServer = app server (history parity), TargetDatabaseServer = real DB.
- Built + deployed 11/07: generator in skill `crewchief-crud-pack`; SMVMTR1 preflight + setup green, workflows
  10000470-10000489. Help pages 69-72, rule 8 softened (CRUD has no source DB). Nothing committed (Gene commits;
  speed-merchants branch bug/crud_pack_updates/genewebb, ai-setup clone on main).
- Open: schedules for CRUD? (none built).

**Why:** short runs (1K + 1-5 min) for fast checks plus one release run per mode matching today's load.
**How to apply:** follow [[crewchief-workload-packs]] blueprint; see [[project_smvmtr1_packs_verified_2026-11-07]] for box state.
