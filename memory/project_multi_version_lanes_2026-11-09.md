---
name: project-multi-version-lanes-2026-11-09
description: "11/09 brainstorm: TestAutoManager lanes per version (26R2/26R3/26R4), per-lane build/name/prep; Gene decisions; 26R4 Configuration manager waits on Gene pulling product code"
metadata:
  node_type: memory
  type: project
  originSessionId: 95f5b98f-d94c-408a-8901-e309c3b37709
  modified: 2026-11-09T18:53:19.300Z
---

Brainstorm 11/09 (after TestAutoManager 1.1.0 deployed to SMVMTR1). Gene's decisions (all via AskUserQuestion):

- Each lane independent: own Version, Build, lane name, preparation (Install / Reconfigure / Neither).
- A versions file (hand-editable) marks the under-development version (now 26R4 = master); each version has its "Latest" branch (26R2 hotfix/2026R2 - release/2026R2 has NO builds; 26R3 release/2026R3; dev = master), service yes/no (26R2 only), Configuration manager kind.
- Version comes from the build number prefix (26.3.0.x = 26R3), never from branch (master carried 26.2, 26.3, 26.4 over time).
- Build: Latest (newest succeeded on the version's branch) or Specific = every succeeded build of that version from ANY branch (PR merges, feature, hotfix) last 14 days + filter + Load older; picked by BUILD ID (build numbers repeat, 26.2.0.1196 built 4x). ADO pipeline 293 does ~12-14 master builds/day.
- Round sets the box: version values (code, service, pools, config kind) passed as run parameters to the lane's items; all 4 packs change via generators (root globals default to $ref, run param overrides, like Task 13 P2P).
- Neither: install-preflight fails the lane if installed version != lane version.
- Lane name: default '<version> <build> <role>', shown on Status/History and passed to TestAuto runs.
- Base backups: one per version (profisee_CRUD_base_26R3.bak etc.); new '<family>-base-create' start workload per pack makes them; preflight names a missing base.
- Reconfigure = Configuration on the existing DB (install-configure-upgrade); installed version must equal lane version.
- 26R2: all three preps offered from the start (install pack never tried on 26R2; failure shows at install).
- 26R4 Configuration manager: params UNKNOWN; Gene is pulling the product branch/code so we read it from source. Build 26.4.0.387 in C:\Deploy\Downloads\26R4B387 (TR1, SMVM1). See planning\2026-11-08-restart-prompt-26r4-configuration-manager.md.

Recon facts: SMVM1 26.3.0.1194, SMVM2/3 26.3.0.1167, no service on any. Connect pack SOURCE environment.json still says 26R2 + service name (boxes have 26R3T, blank) - stale pack default.

Next: written design in Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-09-multi-version-lanes-design.md (26R4 config section pending), builder check, Gene approval, then writing-plans. Related: [[project-mid-release-round-runner-plan-2026-11-07]].

**Later 11/09:** builder check done; Gene: checkpoints carry version too; bases per DB server (made there); Reconfigure/Neither lanes show installed build (read-only); P2P always same version source/target (my call: Review refuses mismatch). **26R4 Install/Reconfigure DEFERRED** (Gene: work in progress, will change): versions file 'Preparations offered' = Neither only for 26R4. 26R4 cause found in platform source (C:\devops\repos\platform, master 78eeef730b): Configuration now CreateProfiseeDatabase under running account then CREATE USER for app pool login; pack passes same account (AdminUser) for both -> creator is dbo -> SQL 15063 (inference). Chosen fix later: pre-create empty DB owned by sa. Design status: READY FOR GENE'S REVIEW.
