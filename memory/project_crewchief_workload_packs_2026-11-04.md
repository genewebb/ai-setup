---
name: project-crewchief-workload-packs-2026-11-04
description: "CrewChief workload packs (Connect): committed; Task 12 live on SMVMTR2 11/04 17:56 (setup+preflight PASS, queue running on pack); Task 13 TR1 gated by Gene"
metadata:
  node_type: memory
  type: project
  originSessionId: 34a49909-8fbf-493a-ab83-eee68b7ef6e7
  modified: 2026-11-04T21:51:35.649Z
---

Generator-free Connect pack. Design + plan: `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-04-crewchief-workload-packs-{design,implementation-plan}.md`.

State 11/04 17:57: Tasks 1-11 committed+pushed by Gene. Task 12 LIVE on SMVMTR2: pack restored Replace (via one-off cli-runner/cli-pack-restore-connect workload calling crewchief restore), preflight PASS, connect-setup PASS ~20 min, 54/54 tags exactly one, 26R2 queue unpaused 17:56 (first pack run connect-1k-t8-sql-server-export-run). Gene backups pre-restore: TR1/2/3 C:	mpewchief-backup-*.zip.
- Engine: key descriptions + keyBlankAllowed, runWhen/Skipped, AppPool blank drop, workflowTag + TestAuto `GET api/workflows/by-tag`, restore by folder Add/Replace, pre-run reference check, Reference Data page UI.
- Pack: `CrewChief/packs/connect` (215 workloads start/tests/schedule/internal, 6 `connect/*` sets with SMVMTR2 values), tools `packs/tools/{Convert-ToPack,Test-Pack,New-PackBackup}.ps1`, `packs/connect/CLAUDE.md`.
- Skill `ai-setup/skills/crewchief-workload-packs` (written on ai-setup main working tree; Gene rolls out). Docs Connect 01/02/03 rewritten.
- My calls to confirm with Gene: dropped WorkflowTags/BackupPrefix keys (tags composed from version + MainMachineTag); connect-setup includes 1K t4 prepare-alls; token-hover description in step editor NOT built (deferred).

**Why:** box-neutral pack, person edits only reference data.
**How to apply:** next = Task 12 on SMVMTR2 after Gene deploys (no run active): restore pack zip with Replace into a clean data folder, preflight, setup, preflight, then 26R2 queue. Task 13 TR1 retrofit gated by Gene. Related: [[project-connect-empty-model-bootstrap-2026-11-04]].
