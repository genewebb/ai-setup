---
name: reference-smvmtr2-testauto-logs-and-sql
description: "Where SMVMTR2 TestAuto step errors live (file logs, not tLogging/Seq) and how to reach its SQL from the laptop (explicit ServerSPN)"
metadata:
  node_type: memory
  type: reference
  originSessionId: 881c127c-2501-497f-ac6d-facb1f403477
  modified: 2026-10-07T14:58:22.651Z
---

SMVMTR2 (10.0.0.12) TestAuto step errors (e.g. MultiStepUtilityScenario "no per-record error text, see the step log") are in `\\SMVMTR2\c$\Deploy\TestAuto\web\LogFiles\SystemLog_NNNN.log` (UTC stamps, 10 MB rolls about every 30 min, about 9 h retained). Seq on SMVMTR2:5341 needs its own API key and held only events from after the last app restart. The `TestAuto` DB's `logging.tSystemLog` is Profisee's own log and was stale (9/9). There is no `tLogging` table.

SQL on SMVMTR2 (default SQL 2022): databases `TestAuto` (a Profisee DB) and `Hangfire` (schema `testautojobs`). TCP was disabled until 2026-10-07; Gene enabled TCP and opened 1433, and added CORP\agenewe as sysadmin. From the laptop over the VPN, plain `sqlcmd -E` fails ("cannot contact a domain controller", because the SPN `MSSQLSvc/...:1433` is missing). Use ODBC with `ServerSPN=MSSQLSvc/SMVMTR2.corp.profisee.com`. Helper script pattern: System.Data.Odbc in pwsh.

A matching-step timeout looks like: `[SQL_SCRIPT] PowerShell Invoke-RestMethod execution failed ... Elapsed: 60383ms, Error: HTTP : The operation has timed out`. CurlStep REST calls have a 60 s timeout.

Related: [[reference-smvmtr3-hangfire-job-diagnosis]] [[reference-matching-3b-synthetic-timings-and-nsb-audit]]
