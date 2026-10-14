---
name: reference_matching_pool_offsets_and_alignment
description: "Four non-obvious runtime facts about UnifiedMatchingScenario record-pool config — the per-source offset maps are dead, TestRecordLimit is the partition cap, SourceSystemDistribution is absolute counts, and ModelSource clones are ordinal-aligned to their originals"
metadata: 
  node_type: memory
  type: reference
  originSessionId: e1a360d6-aa1f-48db-a87d-c1cdde9f6e5f
  modified: 2026-09-09T21:27:59.145Z
---

Verified 2026-09-09 against `speed-merchants` code + the local `speedmerchants`/`profisee`/`ModelSource` DBs while fixing the Matching 1M and Matching 15M workflow templates.

**1. `SourceSystemNewOffsets` / `SourceSystemChangedOffsets` are DEAD CONFIG.**
Written and re-read only by `UnifiedMatchingScenarioEditor.razor.cs` (:439, :754) as wizard round-trip state. Nothing in `TestAuto.Matching` reads them. The runtime uses only the two scalars `NewRecordStartingOffset` / `ChangedRecordStartingOffset`, applied to EVERY source in that class by `RecordMixManager.GetEffectiveOffsetForSource` (:405-437). A config showing per-source offsets of 833,333 while the scalar says 5,000 is really running at 5,000.

**2. `ScenarioTesting.TestRecordLimit` is the partition cap**, not a hint — `RecordMixManager` :197/:233 makes it `_partitionSize`; `GetNextBatchAsync` returns empty once `_recordsProcessed >= _partitionSize`. `IterationLimit` must independently be >= ceil(TestRecordLimit / BatchSize) or the run stops early (bit us on 3a: IterationLimit 1000 x BatchSize 500 = 500,000 against a 1,000,000 limit).

**3. `SourceSystemDistribution` holds ABSOLUTE COUNTS, not percentages** (`RecordMixManager` :174 `ParseSourceSystemDistribution`). Raising `TestRecordLimit` without resyncing it exhausts the sources early and trips `RecordExhaustionBehavior=WarnAndStop`. The percentage-based form is a different key, `NewRecordDistribution.SourceSystems[].Percent` (:1293).

**4. ModelSource clones are ordinal-aligned to their originals.**
`RetailClient` codes run 100000000..149999999 contiguously across source systems 1 (3,000,000) / 2 (6,881,257) / 3 (40,118,743). `RetailClientCloned` codes are `2000000000 + 3n` (SS20), `+1` (SS30), `+2` (SS40). Clone ordinal *n* and RetailClient global ordinal *n* share `OriginalRecordId1` — i.e. **at any offset, sources 20/30/40 are three fuzzy variants of the same person as source 1's row**. Proven: clone `2000750000` and original `100250000` both carry `CCF4EE4C-9A3B-472F-A31F-1123631FB4D8`.

**Consequences for scenario 3b (`LookupThenCreate`):** the create leg fires only on a lookup MISS (`MatchingOperationExecutor.cs` :189-201 returns early on a hit). So the offset must clear the already-loaded window, and with all six sources selected expect only ~50% creates (source 1's row creates; its 20/30/40 clones then hit it). Historical proof of getting this wrong: 2,000 rows on `UnifiedMatchingApiExecution` with `LookupHasMatches=Y` on 100% and `CreatedRecordCode` NULL on all.

**Offset sizing rule:** loaded-window-per-source, then a disjoint band per scenario. At a 1M model (first 200,000 of sources 1,2,3,20,30; source 40 unloaded) we used S2 200,000 / 3b 300,000 / 3c 400,000. At a 3M-per-source 15M model, source 1 is fully consumed (ModelSource has exactly 3,000,000) and must be dropped from the new-source lists.

Related: [[testauto-matching-scenarios]] skill, [[project_matching_3b3c_label_and_comment_bugs]].
