---
name: project_connect_postrun_cross_database_hang
description: "ConnectPostRunCollectionScenario \"hang\" was a SqlException retried silently by Hangfire; the two-connection-string fix (2026-08-04) failed in prod because ScenarioMgt is SaaS — model entities are now read over Metrics REST, never SQL (2026-08-05)"
metadata: 
  node_type: memory
  type: project
  originSessionId: f0ad0694-519c-436c-b541-28b715b462da
  modified: 2026-08-05T14:17:59.499Z
---

`ConnectPostRunCollectionScenario` (step 23 of the Connect strategy workflow) appeared to **hang** and
emitted 0 `ConnectApiExecution` rows. It was not hanging — it threw
`SqlException: Invalid object name 'data.tConnectRunProfile'` and **Hangfire retried it silently every 30s**
(`BatchJobOrchestrator.ProcessBatchJob` has no `[AutomaticRetry]` attribute, so the default 10 attempts
apply). The workflow detail row stays `ExecutionStatus 7` (Running) the whole time, so the UI shows a hang
with no error.

**Root cause: two databases, one connection string.** On CORPLTR94:

| Table | Database |
| --- | --- |
| `connex.tBatch`, `connex.tJob`, `monitor.tActivityDetails` | `profisee` (instance under test) |
| `data.tConnectRunProfile`, `data.tConnectApiExecution` | `speedmerchants` (TestAuto model) |

`ConnectExecutionRepository` took a single connection string (`"Profisee"` subject area → `ProfiseeDB` →
`profisee` catalog) and queried both. `GetBatchAsync` succeeded, `GetRunProfileAsync` blew up.

**First fix (2026-08-04) — SUPERSEDED, was only correct on a dev box.** The repository took a second
`modelConnectionString` (`"Metrics"` → `MetricsDB`) for `GetRunProfileAsync`. That works on CORPLTR94, where
`MetricsDB` = `CORPLTR94\SpeedMerchants` *is* the local ScenarioMgt store — and fails on any real runner.

**Real fix (2026-08-05): the model side is REST-only.** On SMVMTR2 (prod runner, instance under test SMVM2,
DB SMVMDB2) ScenarioMgt/Metrics is an **Azure SaaS instance** (`profiseecloud.dev/speedmerchantstest`) with a
SaaS DB, while `MetricsDB`/`ScenarioMgtDB` resolve to `SMVMDB2\SpeedMerchants` — a real but wrong catalog.
**No connection-string value can be correct there**, so `ConnectionStrings:MetricsDB` is vestigial on a
SaaS-ScenarioMgt deployment. Same silent-retry hang reproduced in prod (workload 10000161 "Connect SQL
Provider 1K", execution 10000183, step 23 pinned `Running`, 0 `ConnectApiExecution` rows).

What shipped:
- `ConnectExecutionRepository` back to **one** connection string (connex/monitor on the instance under test);
  `GetRunProfileAsync` deleted from it and from `IConnectExecutionRepository`.
- New `ConnectRunProfileReader` (static, so the plugin auto-scan in `ScenarioManagementServiceExtensions`
  can't DI-register it and break `ValidateOnBuild`) reads `ConnectRunProfile` via
  `IRestClient.GetRecordAsync` on subject area **`ScenarioMgt`** — reference data comes from ScenarioMgt, not
  `Metrics`, even though both point at one instance today. See
  [[reference_scenariomgt_vs_metrics_subject_areas]].
- **The lookup is never fatal.** No client / unknown code / HTTP error / bad payload → `Unresolved(code)`
  (code preserved, counts 0) + logged warning. The profile only supplies `TotalAttributesCount`/`DBACount`/
  `RuleCount`; the platform is the authority on whether the RunProfile domain value is valid, at write time.
- 7 new unit tests (`ConnectRunProfileReaderTests`, Moq'd `IRestClient`) + integration tests moved from SQL to
  REST; `ConnectTests:ModelConnectionString` retired.

**Rule to carry forward: any TestAuto *model* entity read from a scenario goes over the Metrics/ScenarioMgt
REST client, never SQL.** Metric writes already did (`MetricsPersistenceJob` resolves
`clientFor(RestSubjectArea.Metrics)`); the run-profile read was the lone SQL outlier. `ScenarioMgtDB` has the
same shape and is the same latent trap.

**Two follow-on defects surfaced once rows started landing (run 10000172, both fixed 2026-08-04):**

1. **Successful collection marked Failed.** `WorkloadExecutionUpdateHelper.IsMetricSuccessful` probed only the
   `ResponseCode` column, but `ConnectApiExecution` declares **`HttpResponseCode`**. A clean 200 was invisible,
   so the row fell to the `ExecutionStatus.Equals("Success")` fallback — and `data.tExecutionStatus` has no
   `Success` value (it has `Complete`(2) and `Successful`(8)). Result: `FailedBatches=1`, step 23 Failed, the
   workflow halted with 9 steps Pending even though the metric row was perfect. Fixed by probing both column
   names; added `MetricColumnNames.HttpResponseCode`. **The status fallback is still broken for every metric
   type and was deliberately left alone** — widening it would silently reclassify other scenarios' outcomes.
2. **Self-managed scenarios emitted untaggable log events.** `ScenarioBaseConnect.ProcessBatchAsync` pushes
   `WorkloadExecution` into the Serilog `LogContext`, but both Connect scenarios override `ProcessBatchAsync`
   *wholesale*, so the push never ran and no SEQ event carried the execution code — a failing run was
   untraceable by workload code. Extracted `protected IDisposable PushScenarioLogContext(cfg)` into the base;
   both overrides now open with `using var logScope = PushScenarioLogContext(cfg);`. **Any new self-managed
   scenario must do the same.**

**Diagnosis pattern worth reusing:** a TestAuto step that "hangs" with `ExecutionStatus 7` and no
ErrorMessage → read `Hangfire.testautojobs.State` rows where `Name='Failed'`; the real exception is there.
See [[reference_hangfire_job_exception]].

**Not the cause** (both ruled out): a wrong/missing `RunProfileCode` throws `InvalidOperationException`
fail-fast, and a mismatched `StrategyName` throws "no batch found for strategy" — neither hangs.

Related: [[project_connex_service_store_and_logs]], [[reference_scenariomgt_db]],
[[project_repos]]
