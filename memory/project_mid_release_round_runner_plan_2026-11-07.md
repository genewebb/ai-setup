---
name: project-mid-release-round-runner-plan-2026-11-07
description: "Plan 11/07: install pack + TestAutoManager .NET app + lanes runner + unified status page for mid-release rounds; Gene decisions D1-D23"
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-07T19:03:18.371Z
---

Plan doc: `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-07-mid-release-round-runner-plan.md` (APPROVED by Gene 11/07 14:00). D24-D27: Teams messages on run start/finish/fail, brief + specific, via Workflows webhook into channel Speed Merchants (team Speedmerchants chat), configurable with master on/off + per-kind on/off; Run-As = the CrewChief Run-As secret already used; build = ADO pipeline https://profisee.visualstudio.com/Products/_build?definitionId=293, MASTER branch only. UPDATE 11/07 13:40 (D17-D21): UI is now a .NET Blazor app TestAutoManager (folder + sln `TestAutoManager/` in speed-merchants; installs/runs like CrewChief: Inno like CrewChief.iss, C:\Deploy\TestAutoManager, Windows service + Kestrel HTTPS on SMVMTR1, SQLite) holding UI + lane runner + status pages; proof round = 3 lanes, smallest loads (crud-test-proof, Connect smoke, Matching smoke), install on, once Gene brings SMVM2/3 up.
Key Gene decisions 11/07: readiness order CRUD > Connect > Matching; rounds run 3 lanes in parallel, one pack per box (SMVM1 CRUD 1M br+nobr 60-min steward, SMVM2 Connect 1M all 27 runs, SMVM3 Matching 1M + 10M); SMVMTR1 holds all queues; UI = TestAutoManager app (see UPDATE), hosted only on SMVMTR1; new INSTALL pack from old CrewChief install workloads (backups 20261013-111111/111833: corpvm31-26r4-perf-tests-setup etc.) with endings clean DB / base prep / upgrade / CLU addons; build source selectable, default ADO latest; round starts with install by default; Matching 10M is standard (add to pack); status page = one page, tabs + filters by box/work type; P2P export runs AFTER Matching lane (target SMVM3); SMVM2/3 restarted 11/07 13:48 (one-lane mode supported anyway); TestAuto deps live on test box, Gene configures by hand.

**Why:** real mid/post-release testing on 26R4 with packs, unattended. **How to apply:** build in phase order P0-P8 of the doc after approval; related [[project_crud_pack_design_2026-11-07]], [[project_test_lab_topology_cadence]].

**P1 status 11/07 14:50:** install pack generated (skill `crewchief-install-pack`, gen_install.py), 13 workloads, lint PASS, deployed to SMVMTR1 (workloads + reference-kv/install). Help pages 73-76 (orders 40-43) + 60_PacksOverview row; Docs unit tests 18/18. Rulings in P1 plan ledger: no SetApiKey in verify; BaseBackup1..4 slots; add-ons via remote PS on app server. Open: MSI names from first install-build-get run; destructive install-clean on SMVM1 needs Gene's go-ahead.

**11/07 15:55:** CRUD proof PASS (160 min). install-remove-preview OK (SMVM1: Server + FastApp 26.3.0.1167). install-build-get blocked: AzureDevops:adoPAT missing on SMVMTR1 (Gene adds). P2 catalog done (tools/New-PackCatalog.ps1, lint enforces). P3 plan `2026-11-07-p3-testautomanager-plan.md` (Gene: packs via installer + Publish-Packs.ps1, ports 5040/5041, no sign-in); TestAutoManager Core/Data/Runner built, 28 tests green, uncommitted.
