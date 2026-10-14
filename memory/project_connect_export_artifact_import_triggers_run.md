---
name: project_connect_export_artifact_import_triggers_run
description: "The 1M Connect workload's export leg runs TWICE because step 27's config bundles Import+Enable+Execute while steps 28/29 repeat Enable+Execute — the collected export is always the SECOND one, queued behind a duplicate"
metadata: 
  node_type: memory
  type: project
  originSessionId: 54fb8606-dddf-4375-ac28-46418a5f64e6
  modified: 2026-08-17T16:55:45.730Z
---

**Symptom.** The "Connect SQL Provider 1M" workload defines 1 import + 1 export, but Connect records
**three** batches: one `DatabaseImport` and **two** `DatabaseExport`, both 1,000,000 records, both under
the same `StrategyId` `88f0cf8d-cee5-45b2-9d74-dc54b79b49fd`. Neither export is a reference-data load.

**Root cause (verified 2026-08-17).** Workflow step **order 27** ("Export PDATA120 with Connect -
Step 1: Import") has a chunked config whose `Steps` array holds **three** ConnEx operations, not one:

```
order 27  GroupKey WorkflowTemplate-ced909e5-0471-41c6-87c9-a94b911d7ec3  (14 chunks)
    operation "Import"    description "Import Export PDATA120 with Connect - Step 1: Import"
    operation "Enable"    description "Import Export PDATA120 with Connect - Step 2: Enable"
    operation "Execute"   description "Import Export PDATA120 with Connect - Step 3: Execute"   <-- fires a run
```

Then workflow steps **28** (`Enable`) and **29** (`Execute`) repeat it, producing a second batch.
The import leg is correct by contrast: step **17** (`GroupKey WorkflowTemplate-8b3ee203-…`, 13 chunks)
contains only `operation: "Import"`, and its Enable/Execute live in steps 18/21 — one batch.

Timing proof, local CORPLTR94 run 2026-08-16 (step times from `data.vTestAutoWorkflowExecutionDetail`,
batch times from `connex.tBatch.$EnterDTM`, all UTC):

| Order | Step ran | Batch created |
|---|---|---|
| 17 (Import only) | 20:16:01.010–20:17:01.021 | none |
| 21 (Execute) | 20:20:01.683–20:21:01.335 | batch 10 @ 20:20:09.130 |
| **27 (Import+Enable+Execute)** | 20:49:02.691–20:50:03.117 | **batch 11 @ 20:49:04.237 (+1.5 s)** |
| 28 (Enable) | 20:50:03.445–20:51:02.993 | none |
| 29 (Execute) | 20:51:03.306–20:52:02.893 | batch 12 @ 20:51:06.050 (+2.7 s) |

Reproduced on SMVMDB2 (run of 2026-08-16 evening, preserved in database **`ConnectRun1`** after the user
backed up and restored `profisee` there on 2026-08-17): export batches entered 02:39:15.940 and
02:41:17.370 — the same **2 min 01 s** spacing as the local 27→29 gap.

**Measurement consequence.** The polling step waits through BOTH exports (local step 30 ran 3,303 s) and
`ConnectPostRunCollectionScenario` collects the **second** batch. Every collected export figure is
therefore the second consecutive identical 1M export, queued behind a duplicate — that is the source of
the export's huge `QueueWaitMs` (local avg 2,407 s), and it means the measured export ran against a
just-warmed instance. The first export is never collected (local batch 11, SMVMDB2 batch 2 have no
metric rows). [[project_connect_metrics_proof_doc]] §11 item 5 notes the uncollected batch without
explaining it.

**FIXED 2026-08-17 in production ScenarioMgt** (`profiseecloud.dev/speedmerchantstest`, reachable via the
remote Profisee MCP): workflow **`Connect SQL Provider 1M (4 Threads) v2`**, Code `10000164`, is a copy of
`Connect SQL Provider 1M (4 Threads)` (Code `10000163`) with the two standalone export steps deleted. 28
steps; the single export step is Code `100002818` at ExecutionOrder 25, renamed
"Export PDATA120: Import, Enable and Execute Export", its bundled sub-steps renamed
"Export PDATA120 - Step 1/2/3: Import Strategy Definition / Enable Strategy / Execute Export". Verified:
exactly two `Execute` operations workflow-wide (import order 19, export inside 25). The production
workflow has **no** "Set Connect Number of Threads" and **no** "Reset Application Pool" step — those exist
only in the local CORPLTR94 copy — so the "(4 Threads)" name is not enforced by the workflow; the count is
whatever `connex.tServiceProvider` already holds on SMVM2.

**Naming bug alongside it.** All three export-leg steps are named "… - Step N: **Import**"
(orders 27/28/29) though their operations are Import / Enable / Execute, and the inner `description`
fields read "Import Export PDATA120 with Connect - Step N: …". The import leg is named correctly.
Names only — the import-leg configs are right.

**Do NOT conclude** that importing an export artifact auto-triggers a run. That was an earlier wrong
inference from the step *names* before the chunked config was reassembled. The trigger is the explicit
bundled `Execute`.

**Reassembling a CHUNKREF config** (`CHUNKREF:WorkflowTemplate-<guid>:<n>`) — the scenario-config-inspector
skill does not implement this; chunks live in `data.vTestAutoScenarioConfiguration`:
`SELECT STRING_AGG(CAST(ScenarioJsonData AS nvarchar(max)), '') WITHIN GROUP (ORDER BY Seq)
 FROM data.vTestAutoScenarioConfiguration WHERE GroupKey = 'WorkflowTemplate-<guid>' GROUP BY GroupKey;`

Verify on any future run: `SELECT ID, Type, Name, StrategyId, [$EnterDTM] FROM connex.tBatch ORDER BY ID;`
Three rows with two matching export `StrategyId`s = still present.

Related: [[project_connect_perpage_hangfire_timing]], [[reference_connex_recordcount_is_keyrange_width]],
[[project_connect_runprofile_direction_authority]], [[reference_scenariomgt_db]]
