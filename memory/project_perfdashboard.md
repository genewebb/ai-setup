---
name: project-perfdashboard
description: "perfDashboard schema in pc-speedmr-prd-db — summary tables, procs, views, and how to update them"
metadata: 
  node_type: memory
  type: project
  originSessionId: f7bb6b64-8c01-406c-8520-96a485034a41
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
- Standard versions: 25R1, 25R2, 25R3, 25R4, 26R1, 26R2P

**To rebuild:**
```sql
EXEC perfDashboard.CreateBatchCrudSummary;
EXEC perfDashboard.CreateUserCrudSummary;
```

**Reference doc:** `C:\devopslocal\ObsidianVaults\Personal\MyPersonalVault\Profisee\Work In Progress\perfDashboard-Summary.md`

**Why:** Built 2026-05-21 to support version-over-version performance comparison reporting.

**How to apply:** When user asks about performance reporting, dashboard procs, or post-migration steps — point to this schema and the reference doc.
