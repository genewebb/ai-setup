---
name: reference-hangfire-job-exception
description: Where to find the real exception when a TestAuto scenario job silently retries or a workflow step hangs in Running
metadata: 
  node_type: memory
  type: reference
  originSessionId: f12f5936-ec4f-45de-983c-b09d9c41012c
---

When a TestAuto scenario's Hangfire job throws, the workflow step can look "stuck" — it stays `Running` and Seq only shows `ProcessBatchAsync ENTRY` re-appearing every ~30/45/60s (that cadence = **Hangfire retry backoff**, i.e. the job is *failing and being retried*, not working). Seq often does NOT carry the scenario's exception in that case.

The real exception lives in the **Hangfire DB**: database `Hangfire`, schema **`testautojobs`** (not `HangFire`/`dbo`), table **`State`**. Grab the `HangfireJobId: N` from the Seq `ProcessBatchJob started` line, then:

```sql
SELECT s.Name AS StateName, s.Reason, s.CreatedAt, CAST(s.Data AS nvarchar(max)) AS Data
FROM Hangfire.testautojobs.State s
WHERE s.JobId = <N>
ORDER BY s.Id DESC;
```

The `Failed` row's `Data` JSON has `ExceptionType` / `ExceptionMessage` / `ExceptionDetails` (full stack trace). Reachable via the `mcp__corpltr94_profisee__execute_query` MCP (cross-DB prefix `Hangfire.testautojobs.State`). This is how the ConnectStrategyPollingScenario hang was traced to a `FluentValidation.ValidationException` (config-only scenario with 0 record-count fields), not the strategy name. Pairs with [[reference_profisee_platform_log]] (gateway errors) and the seq-query skill (app logs).
