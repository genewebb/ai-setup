---
name: project-perfdashboard
description: "perfDashboard schema in pc-speedmr-prd-db — summary tables, procs, views, and how to update them"
metadata: 
  node_type: memory
  type: project
  originSessionId: f7bb6b64-8c01-406c-8520-96a485034a41
  modified: 2026-10-19T16:12:28.046Z
---

The `perfDashboard` schema in `pc-speedmr-prd-db` holds pre-aggregated performance summary data used for version comparison reporting.

**Data flow:**
- `data.tRecordApiExecution` → `perfDashboard.CreateBatchCrudSummary` → `perfDashboard.BatchCrudSummary`
- `data.tRecordInteractiveApiExecution` → `perfDashboard.CreateUserCrudSummary` → `perfDashboard.UserCrudSummary`

**Key facts:**
- Both procs TRUNCATE and rebuild from scratch — run after any new version data is migrated
- Both tables are fully symmetric: Min/Max/Avg/P50/P95/WinsorizedAvg response time + Throughput/ElapsedTime/StartTime/EndTime
- `IsBatchCrud`/`IsInteractiveCrud` filters were removed — everything in `tRecordApiExecution` is batch, everything in `tRecordInteractiveApiExecution` is interactive
- 14 dependent views exist — all SELECT from the summary tables, not raw data (except the two Marketing views which read raw data directly)
- Versions after 2026-10-19 rebuild: 25R1-25R4, 26R1, 26R2, 26R2V, 26R3, 26R3V (V = same-build validation re-run). 26R2P/26R2PV2 raw rows are GONE (purged), so any rebuild drops them; only record = vault metrics\26R1-vs-26R2P-vs-26R2PV2-Comparison.md
- Procs do NOT exclude failed requests from latency (only count PageFailures). Comparison queries must drop executions with PageFailures > 1% of OpCount (26R3 batch Create 100009125/157/179 = all-400 dup-code fast-fails; interactive 100009223 = 503 crash)
- Latest report: vault metrics\26R2-vs-26R2V-vs-26R3-vs-26R3V-Comparison.md (2026-10-19); page C:\tmp\26R2v26R3Performance.html FINAL 10/19 12:15 (plain-English slower/faster/no-change lists, V-only figure where runs disagree >10 pts, run setup section; Gene likes the headline-tile style, found colour tables with 4 lines per cell confusing) (vault md NOT yet)
- TRAP: original 26R2 (July) tWorkloadExecution rows say DqRuleCount 0 for 10-rule runs (metric rows say 10 Rules). Never pick "replacement" runs from WE metadata; use the metric rows' RuleCount/AttributeCount/UserLoad. Cost 10/19: 100006201 (only 26R2 no-rules 120 attr/100 users run) was deleted as "replaced", so no-rules interactive is now 11 common combos, not 12
- SERVER SPLIT (verified 10/19 via tWorkloadExecution.AppServer -> data.tServerProfile 35=SMVM2, 36=SMVM3): 26R2 original ran ALL on SMVM3, one after another; 26R2V/26R3/26R3V ran 10 Rules on SMVM2 and No Rules on SMVM3 IN PARALLEL (26R3 and 26R3V batch Creates started within seconds). No-rules = same server in all 4 versions; rules-vs-no-rules inside a version = cross-server. Rules verified active by timing (writes +130-380% with rules in every run)
- Procs already skip metric rows with no WorkloadExecution (wle.Code IS NOT NULL); failed rows inside a run still count in latency
- Gene 10/19: a V version is the verification run of the same version: report X + XV as ONE version (equal-weight average of the two runs) and show the original-vs-V spread as run-to-run noise
- 06-01 SqlBulkCopy root cause for interactive Delete-with-rules is WRONG for 26R2+: small saves (<=10 records) already go through OPENJSON (cdp b77a320d, 5/27), the only SqlBulkCopy is behind that gate. Regression tracked as ADO Bug 161028 (New, 26R3), cause open

**To rebuild:**
```sql
EXEC perfDashboard.CreateBatchCrudSummary;
EXEC perfDashboard.CreateUserCrudSummary;
```

**Reference doc:** `C:\devopslocal\ObsidianVaults\Personal\MyPersonalVault\Profisee\Work In Progress\perfDashboard-Summary.md`

**Why:** Built 2026-05-21 to support version-over-version performance comparison reporting.

**How to apply:** When user asks about performance reporting, dashboard procs, or post-migration steps — point to this schema and the reference doc.
