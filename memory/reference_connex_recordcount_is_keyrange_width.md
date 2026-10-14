---
name: reference_connex_recordcount_is_keyrange_width
description: "connex.tJob.RecordCount on IMPORT pages is the declared key-range width, not records moved — Connect's planner emits ~7000-wide ranges that wrap the key space 8x, inflating per-page counts and throughput ~8x; monitor.tActivity RecordCount is the authoritative total"
metadata:
  node_type: memory
  type: reference
  originSessionId: de927cca-c7d9-4280-916c-efa0f4700d44
  modified: 2026-08-17T15:53:17.422Z
---

**Symptom:** `ConnectApiExecution` rows for an import show `RequestRecordCount` of 6,000–29,000 per page
instead of the 1,000 page size, summing to ~7,936,000 for a 1,000,000-record source. `WorkloadExecution`
`TotalRecordsProcessed` inherits it, so reported throughput is 2–3x too high (3260 rec/s vs a true 411).
Exports are clean 1,000/page.

**Mechanism (verified live 2026-08-12, SMVMDB2 batch 1):** each import page's `RecordCount` equals the width
of its own `KeySetPageSpec` range exactly (`Code:10007001..10014001` → 7000). The ranges are contiguous but
**wrap back to the start of the code space 7 times** — 8 passes over the same 1M keys — with 7 inverted-range
pages at the wrap points (start > end) that move 0 records and still report `Succeeded`. Source
`ModelSource.dbo.PDATA1M` = 1,000,000 dense rows (codes 10,000,001–11,000,000); target `data.tPDATA120` =
1,000,000 rows with **one temporal version each**, so the data lands correctly — only the page plan and the
per-page accounting are wrong. It is a Connect-side planner defect, not a TestAuto one; `BuildDetail` copies
`job.RecordCount` verbatim.

**Authoritative total:** `monitor.tActivity.Properties.RecordCount` (= 1,000,000), denormalised onto every
metric row as `BatchRecordCount`. Divide by that for throughput, never by `SUM(RequestRecordCount)`.

**Tripwire (both values already on every row, nothing asserts it yet):**
`SELECT WorkloadExecution, SUM(RequestRecordCount), MAX(BatchRecordCount) … HAVING SUM(...) <> MAX(...)`.

**STILL UNFIXED as of 2026-08-16 (re-verified 2026-08-17 on SMVMDB2, fresh environment — connex batch IDs
restarted at 1).** Batch 1 = `DatabaseImport`, 1000 pages, `SUM(RecordCount)` = **7,927,000** for a 1M source;
`MinRecordCount` = **0**, `MaxRecordCount` = 29,000, and **999 of 1000 pages ≠ 1000**. Page 1 range
`10006001..10011001` (5,000 wide, RecordCount 5000); page 2 `10011001..10019001` (8,000 wide, RecordCount 8000).
Batches 2 and 3 (`DatabaseExport`) are clean 1,000/page → 1,000,000 exactly. `monitor.tActivity` RecordCount
reads the correct 1,000,000 on all three. Impact on that run: import elapsed 4,237 s → **236 rec/s** using the
monitor total, but **1,871 rec/s** if connex counts were trusted — an 8x lie.

Direction is the discriminator: **imports inflated, exports clean.** A run where the *export* looks inflated
means the collection steps are mislabelled — see [[project_connect_runprofile_direction_authority]].

**Workaround (2026-08-13, user-requested; reworked same day to CustomParms-only):** the
`DeclaredBatchSize` CustomParm (int, default 0 = off) on ConnectPostRunCollectionScenario forces
`RequestRecordCount`, `ResponseRecordCount` **and `BatchRecordCount`** to that declared per-request size
(Response subtracts `FailedRecordCount`; no-op pages stay 0). So while active, `BatchRecordCount` is NOT the
batch total — the true monitor total still appears in the reconciliation log line. Deliberately NOT
`ScenarioRuntime.BatchSize` (user: leave that field alone, no first-class-field exception to remember — an
earlier same-day version used it and was replaced). Delete the parm once Connect fixes the planner.

**A/B switch:** CustomParm `UseConnexRecordCounts` (bool, default false) parks the override WITHOUT removing
`DeclaredBatchSize` — run trusts connex accounting again, for verifying a Connect fix. Override active =
Warning log; parked = Information log. Both parms have UI in ConnectPostRunCollectionEditor's "Record Count
Workaround" section (numeric + checkbox), constants mirrored in ConnectPostRunConstants.

Related: [[project_connect_import_sequence_race]], [[reference_scenariomgt_db]]
