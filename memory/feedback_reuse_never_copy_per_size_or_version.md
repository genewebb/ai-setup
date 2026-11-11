---
name: feedback-reuse-never-copy-per-size-or-version
description: "Gene's rule 11/11 - a step/workload exists once if reusable across version or size; a size or time change is a small isolated change, never a regeneration of tested packs"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 0acc58d9-fcc9-41fd-b298-2f733f9e654e
  modified: 2026-11-11T17:33:44.116Z
---

Never duplicate a step or workload that can be reused unchanged from version to version (26R3, 26R4) or load to load (1K, 10K, 1M) or time to time (1, 5, 60 minutes). What differs is a value passed in or a reference row, not a copy. Adding or changing a size or a time must be a tiny isolated change; tested workloads stay byte-identical. Renaming or adding something must not ripple into every pack and TestAutoManager.

**Why:** 11/11 Gene stopped the work: every small change regenerated all four packs and forced a retest ("too tightly coupled", "we should not have to change 90% of workflows just to add a new size"). Measured: 347 workloads, 224 distinct once size is a value, 123 pure size copies; 1,936 inline steps, 595 distinct; 4 copies of the API key-set workload (the Connect one drifted).

**How to apply:** before adding a workload, step, generator loop or lint rule, ask "is this a copy that differs by one value?" If yes, make the value an input or a reference row and call the one workload. A shared step = a small called workload (workloads must be all-inline). Say the size of the ripple before proposing any rename or interface change. Review and decisions: `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-11-pack-reuse-review.md`. Related: [[project-multi-version-lanes-2026-11-09]], [[feedback-do-it-right-not-a-patch]].

**Status 11/11 midday:** Gene's decisions: values travel all the way (one workload per job; caller sends Size/Minutes/rules/threads); TestAuto keeps one stored workflow per combination, setup builds each from ONE template + value list in reference data (confirmed twice, no TestAuto change for run-time values); real Connect generator; then lab to 26R4 and run Connect/CRUD/Matching on SMVMTR1-3. May change CrewChief, TestAuto, TestAutoManager, packs: "right change in the right place". New smoke values wanted: Connect 100 records, CRUD stewardship 1 minute ("1M" = million only; minute = `Minutes=1`). Design draft: `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-11-pack-reuse-design.md` (builder check running, NOT yet approved, nothing built). Acceptance test = add those two values after the regeneration with zero workload files changed.

**11/11 afternoon:** design APPROVED; build plan `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-11-pack-reuse-plan.md` (15 tasks: 3 CrewChief changes, packgen module, common pack, 4 generators, lint, TestAutoManager, laptop proof, acceptance test, lab 26R4); progress ledger `2026-11-11-pack-reuse-ledger.md` beside it. More answers: value lists live in the pack in git (pack-owned sets, restored with Replace); default stewardship minutes 1K=1, 10K=5, 100K=30, 1M=60; packs on one box CAN target different instances, so box facts stay per family and the common pack holds workloads only. TestAuto tag keys stay byte-identical. Gene committed the fallback state (speed-merchants 86163565, ai-setup 704f054); I build inline, phase by phase, stop at each phase end for the commit.
