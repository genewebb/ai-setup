---
name: project_unified_matching_prod_timing_audit_2026-09-30
description: "Prod warehouse audit 9/30 of UnifiedMatchingApiExecution timings (data.vUnifiedMatchingApiExecution on speedmerchants-prod-mssql): Start/End/Elapsed consistent; matching chain wrong ($LastChgDTM reads, golden-row survive stamp negative, post-run CreateRequestTime loses ms); 3b 9/16+9/30 runs all lookups matched = no creates; 3c 100008613 still Pending"
metadata:
  node_type: memory
  type: project
  originSessionId: dea19cef-9723-4c76-b577-d6ad7cd4aaad
  modified: 2026-09-30T17:22:21.476Z
---

Prod metric entity = `data.vUnifiedMatchingApiExecution` (Profisee view; no RequestStart/End columns - StartTime/EndTime/ElapsedTime_Ms/ResponseTimeMs). WEs: S2 100008344/459/590, 3a 346/487/598, 3b 339/449/604, 3c 351/448/613. No Scenario 1 rows.

Verified 9/30:
- StartTime/EndTime/ElapsedTime_Ms/ResponseTimeMs agree within 2 ms on all rows. S2 BatchLoad ResponseTimeMs = 0 (not set).
- Lookup/Create durations = response-request (int truncation ~0.5 ms).
- `MatchingMetricsCollector` reads `$LastChgDTM` for create, match AND golden → post-run 3c (448, 351): CreateTxn == MatchTxn == GoldenTxn on 100% rows → MatchingDurationMs 0. 3b 339 (interactive) MatchingDurationMs plausible (~5-10 s, batch-shared stamps).
- Survive = golden ROW's `$LastChgDTM` by ID → 3c 448: 95% Survive < Match, SurvivorshipDurationMs negative (~-0.9 s avg). No-golden path sets Survive=Match → 0.
- Post-run `ReadPendingPageAsync` parses CreateRequestTime via JToken.ToString()+DateTime.TryParse → ms lost (E2E first timestamp = hh:mm:ss.000); 97/100 sampled E2E rows off vs stored CreateRequestTime.
- 3b 449 + 604: 100% LookupHasMatches=Y, zero creates → holdout pool already in Profisee; 3b is acting as 3a. 3b 339 (9/15): all N, creates + waits.
- 3c 100008613 (9/30) 100K rows still Pending - post-run step not run/failed.

Timings entity (`data.vUnifiedMatchingApiExecutionTimings`, MatchingResultsScenario + MonitorActivityCollector): 6 buckets in code = 6 OperationName domain values = 6 rows per run. But Total Time = SUM of buckets (not wall clock), so unbucketed time is invisible: S1 100008471 wall 29,211 s vs sum 4,262 (Matching 0, Survivorship 0); S1 549 wall 47,082 vs 3,105. Master Indexing end > Total end on S1 471/549. 9/30 Timings UnifiedMatchingScenarioWorkloadExecution (539/570/569) do NOT equal the ApiExecution WEs (590/604/613); 9/15-16 did match -> {{STEP:N}} link stale.
Code fixes applied 9/30 (uncommitted): collector create=$EnterDTM, match=COALESCE([Match DateTime],$LastChgDTM), survive polls golden row until >= match (notBefore), post-run ReadUtcDateTime, BatchLoad ResponseTimeMs; unit tests PostRunCollectionDateReadTests 7/7.

Timings fixes applied 9/30 (uncommitted): MonitorActivityCollector.Classify (public static, pure) - Indexing excludes master activities, Total = wall clock incl. activity Started/Completed, NEW 7th bucket "Unaccounted" = Total - union of phase intervals, empty bucket = null (OperationStartTime DateTime?, OperationDurationSec int?), OperationEndTime text as "yyyy-MM-dd HH:mm:ss.fff" (no 'T' so server doesn't re-parse). Unit tests MonitorActivityClassifyTests 6/6 (synthetic). PREREQ: add "Unaccounted" member to prod UnifiedMatchingApiExecutionOperationName domain entity before deploying. Not done: detail-name fix (needs SMVM3 "Distinct detail record names" log), {{STEP:N}} relink.

User committed the above in 3d382e06. SMVMDB3 (Profisee DB, `sqlcmd -S SMVMDB3 -E -C -d Profisee`; SMVM3 itself not SQL-reachable) 15M S1 run, Timings WE 100008585: prod rows entered 10:02:41, after all monitor rows existed (details inserted <1 s after their Timestamp), yet the recorded buckets match ONLY a read missing each activity's tail: act5 lost `Indexing Finished`, act6 lost `Clustering Finished` (row 162/1624), act8 max seen 09:29:54 (row ~2652/2726). Cause is in the REST paging; exact server behaviour is unproven (no API/Seq access; TR1 Seq 401). Old loops stopped on `totalPages` and `break` on a failed page = silent partial. Fix (uncommitted): `GetAllPagesAsync` pages until an empty page or no new Code, retries 3x, throws on failure or count < envelope `totalRecords`. Scoring end also accepts `Scoring "<attr>" Job Id N Finished` (act5 has no `Scoring Finished - X`). Full-data expected S1: Indexing ~16,692 s, Scoring ~8,109, Matching 20,532, Survivorship 1,106, Master 869, Total 48,850, Unaccounted ~9,662 s ≈ Syncing (`Syncing Started/Finished`: act5 7,899 s + act8 1,759 s) = candidate 8th bucket, needs domain member. DONE 9/30 (uncommitted): 8th bucket "Syncing" (`OperationName_Syncing`, `MatchingPhaseDurations.Syncing`, Syncing Started/Finished on all activities, row emitted before Unaccounted), docs + CompleteReference updated, unit tests 15/15. PREREQ: prod domain needs BOTH "Syncing" and "Unaccounted" members before deploy.

STATUS 9/30 11:50 EDT: ALL fixes above committed (3d382e06 10:53 + f55a99e7 11:35, incl. GetAllPagesAsync + Syncing). Prod domain `data.tUnifiedMatchingApiExecutionOperationName` has Syncing (ID 7, added 15:34 UTC) but NO "Unaccounted" member - must add before deploy. Still open: Profisee rerun to verify buckets, detail-name fix, {{STEP:N}} relink, 3c 613 post-run, 3b holdout pool.

9/30 13:2x: user changed prod Timings `OperationEndTime` text -> datetime2. Code switched (uncommitted) to `DateTime? OperationEndTime` = `EndTimeUtc?.UtcDateTime`, same as OperationStartTime; `OperationEndTimeFormat` const removed. Build clean, 136 Matching unit tests pass. Old rows keep the +4h end shift from the text era.

**Why:** User flagged Start/End/elapsed "not right"; wall-clock fields are right, the matching-chain fields are not.
**How to apply:** Fix direction pending user choice: create time from `$EnterDTM`, match time from a per-record source (e.g. `[Match DateTime]`), survive not from golden-row LastChg, parse JToken dates with Value<DateTime>. Related [[project_unified_matching_metric_defects_2026-09-13]].
