---
name: reference-prod-chunkref-config-decode-sql
description: How to read a CHUNKREF step config straight from the speedmerchants prod DB (tTestAutoScenarioConfiguration) to see the real CustomParms a run used
metadata:
  node_type: memory
  type: reference
  originSessionId: 78b446a7-da91-4229-8412-4dea77fc73e5
  modified: 2026-10-05T17:25:55.457Z
---

Workflow step configs on prod (`speedmerchants-prod-mssql`, Profisee ScenarioMgt model) live in
`data.tTestAutoWorkflowExecutionDetail.ScenarioConfiguration` (find steps by `WorkflowExecutionParent`,
order by `ExecutionOrder`; `WorkloadExecution` column = tWorkloadExecution.ID, not Code).
Values over 3900 chars are a sentinel `CHUNKREF:<GroupKey>:<n>`; chunks sit in
`data.tTestAutoScenarioConfiguration` (GroupKey, Seq, ScenarioJsonData). Reassemble:

`STRING_AGG(CAST(ScenarioJsonData AS nvarchar(max)),'') WITHIN GROUP (ORDER BY Seq) WHERE GroupKey='WorkflowExecution-<code>'`
then `SUBSTRING(@j, CHARINDEX('"CustomParms"',@j), 3500)` — MCP output truncates at 4000 chars.

Per-batch metrics: `data.tUnifiedMatchingApiExecution` WHERE WorkloadExecution=<ID>; RecordActionType/OperationType/
RecordSourceMode are FK IDs into tUnifiedMatchingRecordActionType / OperationType / RecordSourceMode.

Used 2026-10-05 to prove 300M Scenario 2 "+50k only" was config (Changed 10 / New 5 / NoChange 85), not a snapshot bug.
Related: [[testauto-snapshot-capture]]
