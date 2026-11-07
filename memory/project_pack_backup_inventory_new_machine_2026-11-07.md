---
name: project-pack-backup-inventory-new-machine-2026-11-07
description: "ANSWER to \"what DBs do I copy to the shared repo\" - the full list of database backups needed to clone the Connect/Matching/CRUD setup to SMVM2/SMVM3, plus the Profisee-config-then-rebackup rule"
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-07T12:46:24.130Z
---

**When Gene asks which DBs/backups to copy to the shared repo for a full clone (SMVM2, SMVM3, ...), answer with THIS list.**
Re-check it first: if a pack gained a new input backup since 11/07/2026 (grep `.bak` in `CrewChief/packs/*/workloads` and
each pack's CLAUDE.md "files outside CrewChief"), add it here.

Full-clone set (from SMVMDB1 E:\SQLBackups, reviewed 11/07/2026):

| File | Size | Pack | On the new box |
|---|---|---|---|
| ModelSourcePDATA1K.bak | 2 MB | Connect | copy to default backup folder as-is (source load restores it) |
| ModelSourcePDATA1M.bak | 1.2 GB | Connect | copy as-is |
| ModelSourceMatching.bak | 7 GB | Matching | restore once as database ModelSourceMatching (no workload restores it). Check it holds every RetailClient<size>Scenario* table first (backup dated 11/06 17:18) |
| profisee_Matching_empty.bak | 14 MB | Matching | PROFISEE DB: restore, run Profisee Configuration for that machine, back up again same name |
| profisee_CRUD_base.bak | 12.4 GB (47 GB data) | CRUD | PROFISEE DB (10M TDATA, ZDATA empty, 20 rules): restore, configure, back up again same name |

Do NOT copy (packs regenerate them on the new box): profisee_ConnectBaseline_PDATA, profisee_BeforeConnectCleanup,
profisee_ConnectTarget_<box> (on the P2P DB server), profisee_Matching_<size>_<state>, the ConnectExport database
(connect-setup creates it). Not used by any pack: ModelSourcePDATA10M.bak (11.8 GB), ConnectExport.bak (22 MB).
Connect needs no Profisee backup: setup builds its model on an empty install.

Besides databases, a clone also needs (not DBs, mention when relevant): the pack zips restored (workloads + reference-kv
on a NEW box only), that box's reference values, CrewChief secrets, TestAuto deployed, then each pack's preflight + setup.

Gene 11/07: delete the PRODUCED files on SMVMDB1 only after all three packs are done; then Gene copies the full-clone
set to the shared repo to set up SMVM2 and SMVM3.

**Why:** a Profisee .bak stores machine info; restored unconfigured it points at the old machine.
**How to apply:** give this list verbatim when asked; put it in each pack's "move to a new machine" help page.
Related: [[project_crud_pack_design_2026-11-07]], [[project_test_lab_topology_cadence]].
