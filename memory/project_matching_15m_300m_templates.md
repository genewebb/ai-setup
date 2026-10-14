---
name: project_matching_15m_300m_templates
description: "Matching 15M (10000165) + 300M (10000166) templates = copies of Matching 1M (10000160, 44 steps) scaled 2026-09-14; offset rule = end of S1 load (volume/5 per source system) + 100k gaps; real RetailClient source = 500M (100M per source system), local ModelSource is a 3M/SS cut-down"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7cb23a63-eb62-412f-89bb-3dff2735da06
  modified: 2026-10-03T20:38:21.769Z
---

**2026-10-03 UPDATE, prod workflow `Matching 300M 26R3` (10000185)**: workloads raised to 1M per scenario (Gene). Offsets now S2 60,000,000 / 3b 60,100,000 / **3c 60,400,000** (3b 200k/SS runs to 60.3M). Prefix 26R3, MaxWait 1440, 3b/3c TimeLimit 06:00:00. S1 loaded = RetailClient300M = first 60M codes per SS; all steps read RetailClient (500M). Change sheet: C:\Tmp\MatchingUpdates.md Step D2. SourceSystemNewOffsets = editor display only; runtime uses NewRecordStartingOffset.

**2026-10-03 RESTRUCTURE, 300M 26R3 (wf 165)**: NoOps gone. Gene's flow: step 1 = Create Base Snapshot `Profisee300M_Matching_AfterScenario1` (only if missing); steps 2-7 = clear logs, pings, S1 collection. Steps 17/23/33/44 (AFTER S2/3a/3b/3c) = "Revert and Recreate Base Snapshot", each a MultiStep: iisreset /stop (refuses unless on CORPVMHA1 and not under w3wp), then SINGLE_USER + RESTORE FROM DATABASE_SNAPSHOT, then MULTI_USER, then DROP + CREATE the snapshot (Gene holds that a revert needs a fresh snapshot; MS docs don't say so), then iisreset /start, then matching/bulkscoring health retried 10x30s. Orphan chunk rows WorkflowTemplate-f44b1937-...-1..3 (harmless). Config is chunked (CHUNKREF ...:3, chunk rows WorkflowTemplate-<code>-1..3). Tokens are now 12/28/38. Gene picked: no log regrow, final restore at 44. Gotchas: Profisee trims whitespace at chunk edges (never split on a space), and the MCP SQL client treats `:word` as a bind parameter (use a placeholder plus REPLACE). Generator: session 06d2ca96 scratchpad gen_restore.sql.

**Data layout**: 5 source systems Apple/Credibly/Intuit/Seed/Walmart. Real RetailClient source = 500M, 100M per source system. Local CORPLTR94 `ModelSource.dbo.RetailClient` = 3M/SS (cut-down for local testing) + `RetailClient1M` = 200k/SS. Scenario 1 loads the first volume/5 rows of EACH source system (1M: codes `xx00000000-xx00199999`). Offsets (`NewRecordStartingOffset`) count per source system.

**Offset rule** (workloads stay 100k like 1M, per user): S2 = volume/5; 3b = volume/5 + 100k; 3c = volume/5 + 200k.
- 1M: 200,000 / 300,000 / 400,000 (unchanged)
- 15M: 3,000,000 / 3,100,000 / 3,200,000
- 300M: 60,000,000 / 60,100,000 / 60,200,000
Plain x-multiply rejected: 300M 3c at 120M overflows a 100M source system (WarnAndStop = zero records).

**Also scaled in 15M/300M**: `UnifiedMatchingApiExecutionRunProfile` `-1000000-` -> `-15000000-`/`-300000000-` (16 steps); `SourceRecords` (snapshot metric, config-only) 10000 -> volume (steps 6,10,13,19,27,33,36,43); `ModelSourceDefaults.*.Count` 3M -> 100M (editor-only, steps 16,24,30,39); 300M step 8 `MaxWaitMinutes` 2880 -> 21600. 3a offset 5000 left (ExistingMatchedOnly ignores it).
**Unchanged by design**: workloads (S2 100k, 3b/3c distributions + IterationLimit 100k, 1h TimeLimits), step tokens (7/16/30/39), environment fields (CORPLTR94).
1M still has `SourceRecords` 10000 (looks stale; not changed - not asked).

Script `Scale-MatchingTemplate.ps1` (session 7cb23a63 scratchpad); before/after dumps `C:\tmp\matching_scale_2026-09-14\`. Related: [[project_unified_matching_metric_defects_2026-09-13]], [[reference_matching_put_strategies_forces_disabled]].
