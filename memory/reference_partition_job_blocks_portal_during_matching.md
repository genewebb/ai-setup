---
name: reference-partition-job-blocks-portal-during-matching
description: Portal login hangs (health green) when Data ShiftTablePartitions Hangfire job holds Sch-M on data.t$Entity waiting behind a long Matching run; killing it just triggers Hangfire retry
metadata:
  node_type: memory
  type: reference
  originSessionId: 04038c57-259f-492a-9686-2f0c0727a101
  modified: 2026-11-01T13:13:47.879Z
---

2026-11-01 CORPVMHA1 / CORPSQL03 Profisee100M: the Portal POST callback after OIDC login hung while /rest/health was all Healthy.

Cause: Data service Hangfire recurring job `ShiftPartitions` (cron `0 0 1 * *`, UTC, so 20:00 EDT on the last day of the month) runs `cdp` `ModelRepository.TruncatePartitions`. That method wraps ALL entities in one TransactionScope, and each `ALTER TABLE ... SYSTEM_VERSIONING = OFF` takes Sch-M, held until the end. It reached tRetailClient (IX held by the 7-day 100M matching run) and waited forever, while holding Sch-M on t$Entity/t$Attribute/etc. Monolith's `SELECT ... FROM data.t$Entity` (Portal login) blocked on Sch-S.

- Diagnose: blocking chain on CORPSQL03. A Profisee_Data session in `ALTER TABLE` with LCK_M_SCH_M. Profisee100M catalog queries (OBJECT_NAME, INFORMATION_SCHEMA) time out; use READ UNCOMMITTED + sys.objects WITH (NOLOCK).
- KILL alone does not help: the job has no [AutomaticRetry], so Hangfire retries ~24 s later and re-takes every lock (datajobs.Job / datajobs.State show it).
- Side effect: a Matching messaging handler's open NSB receive txn held a table X lock on messaging.[Services.Matching], blocking Monitor/Analytics sends. It cleared within ~60 s of the kill.
- Hangfire dashboard /profisee/data/hangfire is behind the same Portal login.
- Bugs written: C:\Tmp\PartionMaintenaceBug.md, C:\Tmp\BugMonitor.md. Gene chose to leave the retry running (matching must not be touched).

Related: [[reference-profisee-cold-service-after-recycle]]
