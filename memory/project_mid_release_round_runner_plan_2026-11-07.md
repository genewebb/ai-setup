---
name: project-mid-release-round-runner-plan-2026-11-07
description: "Plan 11/07: install pack + round UI (WinForms on SMVMTR1) + lanes runner + unified status page for mid-release rounds; Gene decisions D1-D16"
metadata:
  node_type: memory
  type: project
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-07T18:44:09.083Z
---

Plan doc: `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-07-mid-release-round-runner-plan.md` (draft, awaiting Gene approval 11/07). UPDATE 11/07 13:40 (D17-D21): UI is now a .NET Blazor app "Round Manager" (own sln in speed-merchants `RoundManager/`, own Inno installer, Windows service + Kestrel HTTPS on SMVMTR1, SQLite) holding UI + lane runner + status pages; proof round = 3 lanes, smallest loads (crud-test-proof, Connect smoke, Matching smoke), install on, once Gene brings SMVM2/3 up.
Key Gene decisions 11/07: readiness order CRUD > Connect > Matching; rounds run 3 lanes in parallel, one pack per box (SMVM1 CRUD 1M br+nobr 60-min steward, SMVM2 Connect 1M all 27 runs, SMVM3 Matching 1M + 10M); SMVMTR1 holds all queues; UI = WinForms PS like D:\PowershellScripts\forensics_log_pull.ps1, runs ONLY on SMVMTR1, last choices in JSON; new INSTALL pack from old CrewChief install workloads (backups 20261013-111111/111833: corpvm31-26r4-perf-tests-setup etc.) with endings clean DB / base prep / upgrade / CLU addons; build source selectable, default ADO latest; round starts with install by default; Matching 10M is standard (add to pack); status page = one page, tabs + filters by box/work type; P2P export runs AFTER Matching lane (target SMVM3); SMVM2/3 + TR2/3 + DB2/3 DOWN, Gene brings up later (one-lane mode until then); TestAuto deps live on test box, Gene configures by hand.

**Why:** real mid/post-release testing on 26R4 with packs, unattended. **How to apply:** build in phase order P0-P8 of the doc after approval; related [[project_crud_pack_design_2026-11-07]], [[project_test_lab_topology_cadence]].
