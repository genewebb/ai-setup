---
name: project-corpsql03-c-drive-full-2026-09-28
description: "CORPSQL03 C: filled 9/26-9/28 by ~329 GB ERRORLOG from 9002 spam; root = Profisee300M log hit 512 GB max_size + Ola LOG backups failing 3013 from 9/26 05:45"
metadata:
  node_type: memory
  type: project
  originSessionId: 64b74e5e-8786-49bb-8bbd-8b83d6b9a294
  modified: 2026-09-28T16:56:14.383Z
---

Incident, verified by querying CORPSQL03 on 2026-09-28 (sqlcmd -S corpsql03 -E works from CORPLTR94; \\corpsql03\c$ access denied):
- 9/26 00:00: Ola IndexOptimize did ONLINE rebuilds and UPDATE STATISTICS on data.tRetailClient (Profisee300M). By 00:22 the log had hit max_size (K:\SQLLogs\Profisee300M_log.ldf, capped at 512 GB), producing 9002 errors.
- The 05:15 and 05:30 log backups ran (~160 GB each). From 05:45 every Ola LOG backup failed with 3013, 203 times, until the 09:00 9/28 restart. The underlying error is unknown: the job output files for 9/26-27 are gone and CommandLog.ErrorMessage is NULL.
- The app retried endlessly, and every attempt wrote 9002 and 22001 to ERRORLOG on C: at ~100 MB/min (1.8M 9002 rows in 23 min). That is the ~329 GB "SQL error file".
- A manual 511 GB log backup at 09:40 9/28 cleared the log; 9002s stopped at 09:55.
- Agent job history keeps only ~100 rows per job, so the 9/26 failures were purged. Check master.dbo.CommandLog instead.

**Why:** C: holds ERRORLOG and log backups don't; a failure in the log backup job turns into a C:-full outage through ERRORLOG.
**How to apply:** For CORPSQL03 disk or 9002 issues, check CommandLog for 3013 first, then the ERRORLOG size (xp_enumerrorlogs caps at 2147483647; use sys.dm_os_enumerate_filesystem).
