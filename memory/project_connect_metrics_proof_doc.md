---
name: project_connect_metrics_proof_doc
description: "Connect metrics verification doc (2026-08-16) proving the 1M local run's numbers are re-derivable; also holds the Connect-vs-REST head-to-head verdict — reads lose 1.7-25x, writes unresolved"
metadata: 
  node_type: memory
  type: project
  modified: 2026-08-17T00:30:18.778Z
  originSessionId: 2c4adf55-7364-4ae4-adf0-557ab6dd60ea
---

**Doc:** `MyWorkVault\99 Documentation\speed-merchants\connect\Metrics\2026-08-16-connect-metrics-verification-1m-local.md`
Written for the user's boss (Connect-literate, sceptical that Connect is slower than the REST API).
Every section is a copy/paste SQL query with its expected output printed alongside.

**Run under test** (all local on CORPLTR94 — Profisee app, profisee DB, ModelSource, ConnectExport,
TestAuto on one box, Profisee 26R2, 4 Connect worker threads, 122 attributes / 50 DBAs / 0 rules):

| Exec | Batch | Direction | Pages | Records | Wall | rec/s |
|---|---|---|---|---|---|---|
| 100007012 | 10 | Import (POST) | 1000 | 1,000,000 | 1439 s | 694 |
| 100007036 | 12 | Export (GET) | 1000 | 1,000,000 | 1873 s | 533 |

Batch 11 = a second 1M export (1582 s → 632 rec/s) that was **never collected**; its work window ends
0.4 s before batch 12's first pickup, so the two did not overlap — that near-serial handoff is also
what produced batch 12's huge `QueueWaitMs` (avg 2407 s, max 3327 s).

**`DeclaredBatchSize=1000` + `UseConnexRecordCounts=false` were ACTIVE on both collection steps** — and
were provably a **no-op**: `connex.tJob.RecordCount` = 1000 on all 2000 pages, so declared == derived.
Disclosed openly in the doc rather than omitted. The 8x key-range planner defect is absent: 1000
distinct range starts, every bounded range exactly 1000 wide, 0 inverted. Final import page is
open-ended (`Code:10999001..`) — that is normal, not a defect, but it breaks naive `MAX(HiKey)` parses.
`PageKeyRange` is NULL on ALL export rows (Connect emits `KeySetPageSpec` for imports only).

**Connect vs REST verdict (data does not fully settle it):**
- **Reads**: 1-user REST GET = 1631–1715 rec/s vs 4-thread Connect export 533 (local) / 976 (prod) →
  REST 1.7–3.2x faster on a quarter of the parallelism; 13–25x at 10 users (~13,000 rec/s).
  Mechanism: one 1000-record export page costs 4.9–10.9 s of pure work, only 4 in flight.
- **Writes**: INCONCLUSIVE. Connect production imports span 234–1464 rec/s (6x spread); REST creates
  split into two unexplained clusters at the same `SimulatedUserCount` (~460 and ~105 rec/s). Ranges
  overlap. Do NOT claim Connect is slower on writes without a matched run.
- Production Connect ran on SMVM2 app / SMVMDB2 SQL; REST baselines on SMVM3/SMVM2 — **different boxes,
  different dates**. The missing piece is a local REST 1M create + read on CORPLTR94
  (`data.vRecordApiExecution` is empty locally).
- Production 8/14 matrix: import 4T = 234, export 4T = 976, import 8T = 391, export 8T = 1424 — note
  production exports beat imports while locally the import was faster.

Related: [[project_connect_perpage_hangfire_timing]], [[reference_connex_recordcount_is_keyrange_width]],
[[project_connect_runprofile_direction_authority]], [[reference_scenariomgt_db]]
