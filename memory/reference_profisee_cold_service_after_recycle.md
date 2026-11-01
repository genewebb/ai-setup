---
name: reference_profisee_cold_service_after_recycle
description: Profisee 26.3 services stay cold after an app pool recycle or DB restore until called; Monitor then drains nothing and Connect metrics lose BatchRecordCount
metadata:
  type: reference
---
Profisee 26.3 platform services (IIS app pools Profisee-*, e.g. Profisee-monitor at /Profisee/api/monitor) do NOT start
after an app pool recycle, even with startMode=AlwaysRunning + preloadEnabled. A worker process exists, but the app
stays idle until its first HTTP request (no "Initialize." line in Services\Monitor\LogFiles\SystemLog.log).

A DB restore (connect-database-reset) makes NServiceBus trip its circuit breaker (`FTL Failed to peek
Services.Monitor@[messaging]@[profisee]`), and that endpoint is dead until it restarts.

What breaks: messaging.[Services.Monitor] fills up and monitor.tActivity stays empty. ConnectPostRunCollectionScenario
then logs "no monitor.tActivity row", BatchRecordCount is NULL, and HttpResponseCode is inferred from ProcessingState.
SMVMDB1 sat in this state 10/15-10/31.

The old baseline carried about 90 stale Monitor messages. A fresh baseline taken 10/31 16:51 (after a warm reset drained them) restores with an empty queue. The old one is kept at E:/SQLBackups/profisee_ConnectBaseline.prev-20261031-1259.bak.

Fix (10/31): CrewChief generator New-WarmUpStep ("Start Every Service"). It polls GET {{MainHealthUrl}} =
<gateway>/rest/health until every healthChecks entry is Healthy (max 10 min, usually about 26 s). It runs after every
recycle or IIS restart: connect-database-reset, all 9 *-prepare workloads, and the connect-api-key-set-* workloads.
A single GET <gateway>/rest/health warms every service by hand.

Related: [[reference_testauto_prod_sql_server]], [[project_connect_test_board_2026-10-30]]
