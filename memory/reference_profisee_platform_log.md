---
name: reference-profisee-platform-log
description: Where the Profisee platform/gateway server-side log lives (tSystemLog) — the source of truth for ConnEx/gateway errors that Seq and TestAuto discard
metadata: 
  node_type: memory
  type: reference
  originSessionId: f12f5936-ec4f-45de-983c-b09d9c41012c
---

The Profisee **platform/gateway** server-side log is the SQL table **`Profisee.logging.tSystemLog`** on CORPLTR94 (schema is `logging`, NOT `dbo` — a `LIKE '%Log%'` search of dbo only finds `__RefactorLog` and misses it; use `INFORMATION_SCHEMA.TABLES` across all schemas to find it). It is a **Serilog MSSQL-sink table**. Full columns (verified 2026-06-15): `Id bigint, Message nvarchar(max), Level nvarchar(128), TimeStamp datetime NOT NULL, Exception nvarchar(max), LogEvent nvarchar(max), EventType, EventCode, AssemblyName, AssemblyVersion, SourceContext nvarchar(500), EnvironmentUserName, MachineName`. **`TimeStamp` is UTC** (local EDT 12:46 = 16:46 UTC), so offset queries by the machine's UTC offset. `Level` holds Serilog levels (`Error`/`Fatal`/`Warning`/`Information`); `SourceContext` is the originating class.

Why it matters: this is the ONLY place the *real* cause of a Connect/ConnEx HTTP 500 appears. TestAuto's `ConnExExecutor` tries to surface the response body, but a 500 from the gateway often has an **empty body** (e.g. `TaskCanceledException` = the gateway's outbound HttpClient hit its ~100 s default timeout while the ConnEx backend retried a failing source-DB login). Seq (`seq-query` skill) holds the TestAuto app logs and the outbound request, but NOT the gateway's stack trace — `tSystemLog` does.

Query pattern (find a gateway 500 + its exception):
```sql
SELECT Id, TimeStamp, Level, LEFT(Message,400) Msg, LEFT(Exception,2000) Ex
FROM Profisee.logging.tSystemLog
WHERE TimeStamp BETWEEN '<utc-start>' AND '<utc-end>'
  AND (Level IN ('Error','Fatal') OR Exception IS NOT NULL)
ORDER BY TimeStamp;
```
Reachable via the `mcp__corpltr94_profisee__execute_query` MCP (cross-DB prefix `Profisee.logging.tSystemLog`; that MCP's own `all_table_names` only lists dbo). Pairs with [[reference_scenariomgt_db]] and the seq-query skill.
