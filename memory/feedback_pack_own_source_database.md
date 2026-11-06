---
name: feedback-pack-own-source-database
description: "Every CrewChief pack (Connect, Matching, CRUD) gets its own ModelSource<Pack> database named only in <family>/databases:ModelSourceDB; SQL, Connect service configurations and TestAuto CustomParms all take it from there"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-06T20:46:58.209Z
---

Each pack has its own source database: `ModelSourceConnect`, `ModelSourceMatching`, `ModelSourceCRUD` (Gene
2026-11-06), named only in `<family>/databases:ModelSourceDB`. Packs share a target box and SQL Server but never run
at the same time on one target, so the Profisee database restore can stay shared.

**Why:** Connect's load had `ModelSource` typed 9 times while the key existed; Matching's Connect service
configuration lived only inside `profisee_Matching_empty.bak`; TestAuto `MatchingRecordLoader` had
`DatabaseName = "ModelSource"` in code. Moving Connect + Matching to one SQL Server (SMVMDB1) exposed all three.

**How to apply:** for CRUD (and any pack change) the database name must come from the key in all three places:
step SQL (`{{$ref:<family>/databases:ModelSourceDB}}`; `Test-Pack.ps1` now refuses literal DB names), Connect service
configurations (setup/load deletes + imports them with DatabaseName from the key), and TestAuto (a CustomParm written
by setup; Matching: `SourceDatabaseName`). Grep `-w ModelSource` across the pack and the TestAuto area before calling a
pack done. Rule 8 in `60_PacksOverview.md`; skills [[crewchief-workload-packs]], [[crewchief-matching-pack]].
Related: [[project-pack-docs-in-app-help-2026-11-06]].
