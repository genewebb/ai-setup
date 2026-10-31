---
name: reference_manual_monitor_marker_insert
description: How to hand-insert a TestAuto Start/End of Scenario marker into a Profisee DB monitor.tActivity (sqlcmd needs -I; template script in scratch)
metadata:
  node_type: memory
  type: reference
  originSessionId: 9e1bc310-316b-409d-9aac-470cb4c69b0e
  modified: 2026-10-31T08:50:20.652Z
---

TestAuto MonitorStep markers land in `<ProfiseeDB>.monitor.tActivity` (temporal table) as: Name = step description ("Start of Scenario 1 for Retail Client"), Properties `{"Message":"Start of RetailClient Scenario 1"}`, ActivityType "Start of Scenario"/"End of Scenario", Service "TestAuto", Status "Succeeded", times UTC. MonitorActivityCollector finds boundaries by exact Name.

Manual insert: `$EnterUserID`/`$LastChgUserID` NOT NULL, no default (used 4, same as Connect/Matching rows), `$LastChgTypeID` 1; `$UID`/period columns default. sqlcmd MUST use `-I` (QUOTED_IDENTIFIER) or insert fails Msg 1934. Make it idempotent (skip if Name exists).

2026-10-31: added "Start of Scenario 1 for Retail Client" to CORPSQL03 Profisee100M (100M run on CORPVMHA1) first at 23:25 UTC (before import) = WRONG per Gene; Start of Scenario 1 goes AFTER the Connect import ends and BEFORE matching starts. Gene then wanted it JUST BEFORE indexing start: final 2026-10-27 01:19:03.000 UTC (~1.4 s before Indexing 01:19:04.440). Rule: Start marker = ~1 s before the first matching activity. Script: C:\scratch\claude\C--devops-repos-speed-merchants\9e1bc310-316b-409d-9aac-470cb4c69b0e\scratchpad\add_start_scenario1_marker.sql. Activity 5 (Clustering & Survivorship) still Running since 10/27 01:19 at that time.
