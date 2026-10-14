---
name: project_smvm2_matching_service_down_2026-09-10
description: "SMVM2's Profisee Matching microservice has been failing to start since 2026-09-10 00:22 (IIS 500.30); app pool Profisee-matching shows Started with a live w3wp but the app never initialises; stdoutLogEnabled=false so the current exception is unrecorded - last recorded cause (2026-09-09) was SqlException connecting to SQL Server"
metadata: 
  node_type: memory
  type: project
  originSessionId: 6f0d3904-49de-4741-a701-439ff517a35a
  modified: 2026-09-12T02:46:20.876Z
---

**State on 2026-09-11 20:35 EDT**
- `GET https://SMVM2.corp.profisee.com/profisee/api/matching/health` → IIS `HTTP Error 500.30 - ASP.NET Core app failed to start` (HTML).
- Every `/v1/Matching/*` route → gateway 500/400 `Unexpected character … <` ([[reference_profisee_gateway_400_unexpected_character_means_microservice_down]]).
- Controls healthy: `/api/bulkscoring/health` → `Healthy`; `/v1/Records/RetailClient` → 200, 1,000,000 rows.
- App pool `Profisee-matching`: `Started`, `AlwaysRunning`, w3wp PID 7772 alive. Not a stopped pool — the app fails inside the worker.
- Service log `C:\Program Files\Profisee\Master Data Maestro Server\26.2.0\Services\Matching\LogFiles\SystemLog_033.log` last written **2026-09-10 00:22:56**.
- Application log in the 2026-09-11 window: 37 events, exactly ONE matching-related (BulkScoring starting). No fresh startup exception because `web.config` has `stdoutLogEnabled="false"`.
- Last *recorded* failure (2026-09-09 20:22): `Microsoft.Data.SqlClient.SqlException (0x80131904): A network-related or instance-specific error occurred while establishing a connection to SQL Server`. NOT proven to be tonight's cause; `SMVMDB2:1433` is reachable from SMVM2 now; connection strings in its `appsettings.json` are encrypted so the target could not be read.

**To get the real exception**: set `stdoutLogEnabled="true"` in that `web.config`, recycle `Profisee-matching`, hit the health URL once, read `.\logs\`. Config change on a shared box — ask first.

**Consequences observed**: workload `100007302` (3a against SMVM2) 100,000/100,000 failed; `matching.tMatchingStrategy.Status = 0` there and `data.tRetailClient` untouched since 2026-09-05 — the "Enable strategy" and "Continuous matching on" workflow steps reported green while doing nothing (they hit the same dead service).
