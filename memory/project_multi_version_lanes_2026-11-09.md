---
name: project-multi-version-lanes-2026-11-09
description: "Multi-version lanes (26R2/26R3/26R4), per-lane build/name/prep, Gene decisions; 26R4 Configuration support built + proven on laptop 11/11 (one path, empty sa-owned DB), uncommitted, lab deploy open"
metadata:
  node_type: memory
  type: project
  originSessionId: 95f5b98f-d94c-408a-8901-e309c3b37709
  modified: 2026-11-11T16:52:45.644Z
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

**11/10 26R4 Configuration plan written (built 11/11, see below):** `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-10-26r4-configuration-manager-plan.md`. Source facts (platform master 03bb8231fb vs origin/release/2026R3; Server\Configuration unchanged since 78eeef730b): switches = 26R3 set + optional profiseeDBConnectionString/dataDBConnectionString; 26R3 UpdateSecurityForWindows.sql gave the DB to prof_dlp_login before CREATE USER, 26R4 removed that (commit d7dca73b2d 10/14) = cause of 15063 when one account creates the DB and is the pool account (inference, fits the log); empty DB (zero base tables) is accepted by 26R3 and 26R4. Gene decisions: D1 pack steps create the empty DB (CreateDatabase + SQL step owner = SUSER_SNAME(0x01)), no CrewChief Configure feature; D2 ONE path all versions, ConfigurationManagerKind + refusal removed from 4 packs and TestAutoManager. Gate: laptop hand runs A3a (no DB, expect 15063), A3b (empty DB owner sa, expect pass), A4 (26R3 base upgrade, unproven).

**11/11 built + proven on laptop (uncommitted, not deployed to lab):** packs (4 generators, Test-Pack R-config), TestAutoManager (ConfigurationManagerKind gone, 26R4 default preps Install/Reconfigure/Neither), CrewChief (failure markers, 2 new switches). Laptop workload `26r4-end-to-end-to-e` (CLI 10.0.4 from source in `C:\Deploy\CrewChief26R4`, data folder there; installed CrewChief 8.2.0 untouched) green: clean install 26.4.0.435 on empty sa-owned DB (no 15063), 26R3 seed upgrade to `profisee_Matching_empty_26R4P.bak`, Matching 1K all scenarios. Laptop `/profisee` is now 26.4.0.435, version code 26R4P; old `Profisee` DB backed up `C:\DatabaseBackups\Profisee_before-26R4-clean-install_20261110.bak`. Open: lab deploy, 26R3 single-path proof, lab `versions.json` 26R4 still Neither; possible 15063 in `install-configure-upgrade` when restorer = pool account and base lacks that DB user (seed `profisee_Matching_empty.bak` verified to lack it; restored DB owner = restoring account; lab CrewChief account unchecked; my recommendation: add owner step there too). Result section 0 of the plan doc.

**11/11 after reboot:** Gene: add owner step to `install-configure-upgrade` too. Done, uncommitted (ai-setup `gen_install.py` `owner_db(new_db)`, regenerated, only that workload changed, lint 4/4 PASS, docs 73/install CLAUDE.md/README/SKILL). Laptop proof run `4e8ed8e0` on DB `Profisee` Succeeded (owner sa, Configuration 436 s, key set+verified, health 200); proves step + no regression, NOT the 15063 cause (CLI ran as agenewe, pool user existed). speed-merchants earlier work found committed (ceb3fb8a, author Gene Webb, 11/10 22:18); owner-step edits there + all ai-setup edits uncommitted. Install pack zip built before 11/11 lacks the owner step: rebuild before lab publish. `C:\Deploy\CrewChief26R4` deleted 11/11; proof logs + runs.json in `C:\Deploy\Archive\CrewChief26R4-proof-20261111`; laptop installed CrewChief 10.0.6 data (`C:\Deploy\CrewChief\web\data`) is now install pack ONLY (Gene 11/11); e2e workload `26r4-end-to-end-to-e`, matching workloads/refs and 14 old steps only in `C:\Deploy\Archive\CrewChief-data-before-install-only-20261111`. Pack redesign review (reuse, no per-size copies) pending Gene's decisions: [[feedback-reuse-never-copy-per-size-or-version]]. Post-reboot gotcha: services that start before SQL is up stay 500.30 until pool recycle.

Recon facts: SMVM1 26.3.0.1194, SMVM2/3 26.3.0.1167, no service on any. Connect pack SOURCE environment.json still says 26R2 + service name (boxes have 26R3T, blank) - stale pack default.

Next: written design in Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-09-multi-version-lanes-design.md (26R4 config section pending), builder check, Gene approval, then writing-plans. Related: [[project-mid-release-round-runner-plan-2026-11-07]].

**Later 11/09:** builder check done; Gene: checkpoints carry version too; bases per DB server (made there); Reconfigure/Neither lanes show installed build (read-only); P2P always same version source/target (my call: Review refuses mismatch). **26R4 Install/Reconfigure DEFERRED** (Gene: work in progress, will change): versions file 'Preparations offered' = Neither only for 26R4. 26R4 cause found in platform source (C:\devops\repos\platform, master 78eeef730b): Configuration now CreateProfiseeDatabase under running account then CREATE USER for app pool login; pack passes same account (AdminUser) for both -> creator is dbo -> SQL 15063 (inference). Chosen fix later: pre-create empty DB owned by sa. Design status: READY FOR GENE'S REVIEW.
