---
name: project_connect_perpage_hangfire_timing
description: "Per-page Connect timing now comes PRIMARILY from connex.tJob's system-versioned temporal history (first Processing version = pickup); Hangfire connexjobs.State is only the fallback — verified 2000/2000 pages match within 1ms on 2026-08-16"
metadata:
  node_type: memory
  type: project
  originSessionId: 930ea55b-9958-45d8-b269-24bc5e79ab1e
  modified: 2026-08-17T15:53:39.511Z
---

**Timing source order (current, `ConnectPostRunCollectionScenario.cs:543-590`):**

1. **PRIMARY — `connex.tJob FOR SYSTEM_TIME ALL`** (`GetJobLifecyclesAsync`,
   `ConnectExecutionRepository.cs:294-377`). System-versioned temporal table, **infinite** retention.
   `RequestStart` = first `Processing` version, `RequestEnd` = MAX terminal version,
   `RequestElapsedTimeMs` = Finished − PickedUp, `QueueWaitMs` = PickedUp − Enqueued.
   **Rule is `ROW_NUMBER() ... rnState = 1` — FIRST version of each state.** Version counts are NOT
   fixed: import job = 2 Enqueued + 2 Processing + 1 terminal; export = 2 Enqueued + 3 Processing + 1
   terminal. Taking the LAST Processing lands on an intermediate write (record counts being filled in)
   and collapses the work window to milliseconds.
2. **FALLBACK — Hangfire `connexjobs.State`** (`GetJobTimingsAsync`), joined via
   `monitor.tActivityDetails.Properties.$.BackgroundJobId`. `Succeeded.Data.PerformanceDuration`
   excludes queue wait. Rows expire ~168h, hence not primary. Its `Latency` is NOT interchangeable with
   the temporal queue wait (only 50/1000 jobs agreed within 2s) so `QueueWaitMs` is left null here.
3. **LAST RESORT — batch window.** Cumulative, queue-inclusive; on the 2026-08-07 reference run it was
   ~97% queue wait and ranked slowest pages in nearly the wrong order.

**Worker concurrency is directly provable:** distinct `JSON_VALUE(connexjobs.State.Data,'$.WorkerId')`
across a batch's `Processing` states = the real thread count (returned exactly 4 for both 1M batches
2026-08-16). Cross-check: SUM(per-page work ms) ÷ wall-clock = effective threads (3.91–3.93 of 4).

**VERIFIED 2026-08-16, local CORPLTR94 1M run** (import exec 100007012 / connex batch 10; export exec
100007036 / batch 12): recomputing every timing from raw temporal history matched the stored
`ConnectApiExecution` rows on **2000/2000 pages within 1 ms** for start, end, work ms and queue wait.
Import 1,000,000 rec / 1439 s = 694 rec/s; export 1,000,000 / 1873 s = 533 rec/s; per-page work
3.7–15.7 s (import) and 4.9–10.9 s (export). Full write-up with copy/paste SQL:
`MyWorkVault\99 Documentation\speed-merchants\connect\Metrics\2026-08-16-connect-metrics-verification-1m-local.md`
— see [[project_connect_metrics_proof_doc]].

**BOTTOM-UP BINDING — verify the join instead of trusting it (verified 2026-08-17, SMVMDB2).** The usual
Hangfire read joins through `monitor.tActivityDetails.Properties` (`$.BackgroundJobId`, `$.BatchJobIndex`), so a
bad propagation would silently mis-attribute every page. That pair is **redundant** — Hangfire binds itself to
Connect with no monitor involvement:
- `connexjobs.Job.InvocationData` → `{"t":"...ConnEx.Core.Services.Operations.BatchJobService","m":"ProcessJob",
  "p":["System.String","Hangfire.Server.PerformContext"],"q":"02_<serviceProviderUid>"}` — one queue per service
  provider, NOT per batch.
- `connexjobs.Job.Arguments` = `["\"12\"",null]` — **element 0 is `connex.tJob.ID`**, JSON-quoted, so parse with
  `REPLACE(JSON_VALUE(Arguments,'$[0]'),'"','')` then CAST (a bare TRY_CAST returns NULL).
- `connexjobs.JobParameter` has one `BatchId` row per job (38 chars = quoted batch `$UID` GUID).
- `connexjobs.Job.Id` and `connex.tJob.ID` both restart at 1 on environment rebuild — never join across
  environments or assume a global ID.

Propagation test result on the 2026-08-16 SMVMDB2 run (3 batches x 1000 pages): **3000/3000 monitor rows agree**
with the layer-0 page number, 0 orphans in either direction. Identity propagation is sound; the corruption on
that run was *payload semantics* (`RecordCount`), which no join check can catch — see
[[reference_connex_recordcount_is_keyrange_width]].

`HousekeepingScheduler.CleanUpCompletedBatches` / `CleanUpFileExportTempFiles` are recurring Hangfire jobs
(job IDs 1-2) — that is what trims Hangfire history, so treat `connexjobs.State` as a ~1-day window in practice,
not the nominal 168 h.

Other Hangfire schemas per Profisee service: datajobs, matchingjobs, monitorjobs, portaljobs,
proflowjobs, taskmanjobs, hostjobs, modelingjobs — same pattern usable elsewhere.

Related: [[project_connect_postrun_duplicate_code_8603]], [[project_connect_postrun_cross_database_hang]],
[[reference_connex_recordcount_is_keyrange_width]]
