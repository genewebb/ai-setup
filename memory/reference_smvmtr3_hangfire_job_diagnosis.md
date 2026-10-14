---
name: reference-smvmtr3-hangfire-job-diagnosis
description: "How to diagnose a \"stuck\" TestAuto scenario on SMVMTR3 from the Hangfire SQL tables when Seq is unreachable"
metadata:
  node_type: memory
  type: reference
  originSessionId: 73a9ed09-cd31-4184-bd51-35df91276f2e
  modified: 2026-10-02T18:17:18.076Z
---

SMVMTR3: `sqlcmd -S SMVMTR3 -E -C` works from CORPLTR94 (Windows auth). Seq port 5341 is NOT reachable. DBs: `TestAuto` (a Profisee DB; its `monitor.*` tables were empty 2026-10-01, so the Monitor API reads from elsewhere) and `Hangfire` with schema **`testautojobs`** (not `HangFire`).

A "stuck" scenario is often a job failing fast and waiting on Hangfire's exponential retry (10 attempts). Read `testautojobs.State where JobId=<id> order by Id` for the exception message per attempt. Hangfire retries run the currently deployed code, so deploying before retries run out lets the next retry pick up a fix.

2026-10-01 case: MatchingResultsScenario job 959 failed with "Monitor API returned 3400 of 13544 records ... after 69 page(s)". Fix: shared `GatewayPageReader` (TestAuto.Shared.Http/Rest) that drops to the served page size when page 1 comes back short. Related: [[feedback-verify-no-guessing]]

Filter out recurring noise: `WHERE InvocationData NOT LIKE '%WorkflowMonitorJob%' AND NOT LIKE '%ResourceMetricsUpdateJob%'`. When ProcessBatchJob ends Failed after 10 retries, its continuations (MetricsPersistence/WorkloadExecutionUpdate/ResourceCollection, Options=1 OnlyOnSucceeded) sit `Awaiting` forever, so the run looks hung. A new run is needed; retries are exhausted.

2026-10-02 case: S2 (RecordSource=Mixed) job 955 failed "Invalid record mix distribution" with NoChange 85 / Changed 10 / New 5. The editor validates a three-way sum, but RecordMixManager.ConfigureMixedDistribution's 26R1 branch forces NoChangePercent=0 and needs Changed+New=100.
