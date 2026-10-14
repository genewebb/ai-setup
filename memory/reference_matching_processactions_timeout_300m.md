---
name: reference-matching-processactions-timeout-300m
description: "POST v1/Matching/{strategy}/processActions on Profisee300M blocks ~6 min before queuing; gateway gives up at 100 s (500), CurlStep at its timeoutSeconds; matching still runs"
metadata:
  node_type: memory
  type: reference
  originSessionId: 9b47af87-9950-415f-8272-93f133b333e1
  modified: 2026-10-09T19:09:43.326Z
---

Found 2026-10-09 on run 10000244 ("Matching 300M 26R3 Scenario 3a", ran on SMVMTR2, not SMVMTR3) step 3 "Enable RetailClient Matching Strategy Then Run".

- Step 2 CurlStep `POST .../v1/Matching/RetailClient/processActions` has `timeoutSeconds: 60` in the stored config. It timed out at 60 s.
- Gateway on CORPVMHA1 logged `responded 500 in 100032 ms` (its HttpClient.Timeout = 100 s to Matching API). So raising the step timeout alone still fails with 500.
- Matching API kept going: matchingjobs batch job StartProcessingAsync created 17:31:14Z, rest of batch created/enqueued 17:37:15Z (Hangfire Latency 361 s). Monitor activity "Strategy RetailClient for Transaction 94545" started 17:37:15 and runs fine. Cause of the 6-min in-request gap NOT verified (Matching API logs only Warn+; services had restarted 17:23Z).
- PATCH enable (PortalSupportController.EnableStrategies) logs ERR "QueueJob request failed because the strategy is disabled" + WRN "enabled but failed to queue job" — harmless, PATCH returns success.
- Where to look: CORPSQL03 Profisee300M `logging.tSystemLog` (TestAuto + gateway + matching errors), `matchingjobs.Job/State`, `monitor.tActivity`; files `\\CORPVMHA1\c$\Program Files\Profisee\Master Data Maestro Server\26.3.0\{Gateway,Services\Matching}\LogFiles\SystemLog.log` (local time -04:00).

Related: [[reference-matching-3b-synthetic-timings-and-nsb-audit]] [[reference-smvmtr2-testauto-logs-and-sql]]
