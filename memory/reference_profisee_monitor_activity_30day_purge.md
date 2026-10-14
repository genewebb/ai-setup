---
name: reference_profisee_monitor_activity_30day_purge
description: Profisee purges monitor.tActivity rows ~30 days after StartedTime; deleted rows survive in monitor.tActivity_History ($LastChgTypeID=3). Backdated markers get purged too.
metadata:
  node_type: memory
  type: reference
  originSessionId: 06d2ca96-1f99-4120-9472-a1fceb0985e3
  modified: 2026-10-03T18:47:20.964Z
---

Seen on CORPSQL03/Profisee300M 2026-10-03: IDs 1 (started 09-02 05:05), 2, 3 (Txn 6019, 09-02 14:16) and 16 (backdated TestAuto start marker, StartedTime 09-02 14:15, inserted 10-02 14:04) were all deleted; each delete landed ~30 days after the row's StartedTime (ID 1 at 10-02 14:08, IDs 2/3/16 together at 10-02 23:00). Inferred: age-based retention keyed on StartedTime, NOT on insert time. No 30-day value in meta.tSystemSetting (EVENTRETENTIONDAYS=45, HISTORYRETENTIONDAYS=3650) or monitor.t$Entity config; real setting location unknown (probably Profisee service config).

**Recover**: full rows kept in `monitor.tActivity_History`; delete version = `$LastChgTypeID = 3`.
**How to apply**: any long matching run (>~25 days) loses its early Monitor rows before MatchingResultsScenario can read them. Collect timings within 30 days of start, or read from tActivity_History. A backdated marker insert is purged by the next sweep.
Related: [[project_matching_15m_300m_templates]], [[reference_sqlcmd_quoted_identifier_profisee]].

**Restore wipe (2026-10-12)**: CORPSQL03 `Profisee` restored 10-11 from Profisee300M backup (10-03). At 12:53:53 UTC corp\speedmerchants re-stamped all service-client rows in meta.tUser (Profisee reconfigure); at 12:56:38 UTC user 4 "Profisee Monitor" deleted ALL 16 monitor.tActivity rows in one txn (893687), regardless of age. Not an app-setting filter. Rows recoverable from tActivity_History. Exact trigger inside Monitor service unverified.
**Likely setting (found 10-12)**: Monitor service `appsettings.json` (`...\Master Data Maestro Server\<ver>\Services\Monitor\`) has `DataRetentionDays` (7 on CORPLTR94 26.2.0 and 26.3.0), `HousekeepingTime: 23`, `HousekeepingIntervalInDays: 1`. Fits today's wipe (newest row 11 days old). Does NOT fit the earlier 30-day pattern, so the old app server probably had a different value. Not confirmed which machine ran Monitor against CORPSQL03 (no access to \CORPSQL03\c$). Wipe hit ~3 min after reconfigure, not at 23:00, so housekeeping probably also runs at service start (inferred).
**Correction (10-12)**: app server for CORPSQL03 = **CORPVMHA1** (`https://corpvmha1.corp.profisee.com/profisee`), not CORPLTR94. Its `\corpvmha1\c$\Program Files\Profisee\Master Data Maestro Server\26.3.0\Services\Monitor\appsettings.json` was set to DataRetentionDays/AuthEventLogRetentionDays 360 at 09:20 local 10-12 (after the wipe). Only the Monitor service file has the key; other services' appsettings (Monolith, Gateway, etc.) do not. Readable from CORPLTR94 via admin share.
**10-12 re-added**: after the re-restore, IDs 1-16 survived (retention 360); End marker re-inserted as ID 17 (StartedTime 2026-10-04 00:13:05.143 UTC, ActivityType "End of Scenario", Service TestAuto, user 4) in CORPSQL03 `Profisee`, so Gene could take a fresh backup.
