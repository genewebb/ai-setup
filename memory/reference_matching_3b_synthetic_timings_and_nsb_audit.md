---
name: reference-matching-3b-synthetic-timings-and-nsb-audit
description: "UnifiedMatching 'Failed to get match cluster update time' = FAKE timings; resolve a run's REAL runner via ExecutionMachine -> tServerProfile before reading any target DB (ScenarioEnvironment labels lie)"
metadata:
  node_type: memory
  type: reference
  originSessionId: b7cf08ec-b863-4b53-b412-1b215a28610c
  modified: 2026-10-10T11:10:43.417Z
---

Found 2026-10-06 on run 10000237 ("Matching 300M 26R3 Scenario 3b"). Gene thought it ran on SMVMTR2 against CORPVMHA1/CORPSQL03 Profisee300M, and the config labels said so too.

**Find the real runner first.** In prod `data.tTestAutoWorkflowExecution.ExecutionMachine`, the value is an FK to `data.tServerProfile` (41 = SMVMTR2, 42 = SMVMTR3). The runner's secrets (`data.tTestAutoSecrets.MachineName`) choose the actual REST and DB targets. `ScenarioEnvironment.TargetApplicationServer/TargetDatabaseServer` and the metric `Endpoint` column (`UnifiedMatchingScenario.BuildEndpointUrl`) are only labels. 10000237 ran on SMVMTR3, so it hit set 3: SMVMDB3 `profisee`, a 15M RetailClient model that had never been matched. I spent an hour reading the wrong environment.

- `MatchingMetricsCollector.CollectMetricsAsync`: when the Match Cluster poll gives up, it sets HttpErrorMessage and copies `responseReceived` into the Match, GoldenRecord and Survive times. The row looks fully timed, but the times are invented. Signs: all three times are equal, survivorship is 0 ms, GoldenRecordCode is NULL, and ResponseTimeMs is about the poll window.
- 10000237 cause: step 4's clustering job (matchingjobs Job 70, QueueClusteringAsync) ran over the 15M model all through 3b. It failed at 01:35Z with "Failed to update strategy status 'RetailClient' ... 0" and then disabled the strategy. Monitor activities 6 and 7 are stuck at Running, and step 6 (strategy idle poll) can never finish.
- To prove whether a Monitor marker was sent, query `messaging.Audit` headers (TimeSent, EnclosedMessageTypes, OriginatingMachine) in the right Profisee DB. Put the SQL in a file and run `sqlcmd -i`, because `$."..."` breaks PowerShell quoting.
- SMVMTR3 build from 10/2 lacks `MonitorActivityConfirmer`. Its nsb_log shows "License expired" on 10/5. Its logs roll over within hours.

- 2026-10-10: same trap on 10000245 (300M 3a, labelled CORPVMHA1, Complete): runner 42 = SMVMTR3, whose only tTestAutoSecrets row (MachineName is int FK to tServerProfile) points REST at SMVM3; only SMVMTR2 (41) secret points at CORPVMHA1. Quick fingerprint without secrets: lookup latency p50 ~45-55 ms = SMVM3, ~170-190 ms = CORPVMHA1. Confirmed by SMVMTR3's own logs (\\SMVMTR3\c$\Deploy\TestAuto\web\LogFiles: WorkflowMonitorJob checking 10000245, MetricsPersistenceJob writing WorkloadExecution 100009060 with MachineName SMVMTR3). ExecutionMachine = secrets value or Environment.MachineName fallback (Program.cs), neither appsettings sets it, so ExecutionMachine is a reliable runner indicator. Gene believed it ran on SMVMTR2. Genuine CORPVMHA1 1M runs: 10000235 (S2, WE 10824) and 10000236 step 4 (3a, WE 10829). Older workflow header/detail rows are gone from live tables; read `tTestAutoWorkflowExecution_History` / `...Detail_History` (latest $LastChgDTM per ID).

Related: [[reference-testauto-monitor-send-silent-fail]], [[reference-prod-chunkref-config-decode-sql]], [[reference-smvmtr3-hangfire-job-diagnosis]]
