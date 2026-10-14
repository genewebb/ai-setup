---
name: project_getrecords_pagesize_truncation
description: "IRestClient.GetRecordsAsync(entity, queryParams) silently truncates at server-default 50; use GetAllRecordsAsync for full sets"
metadata: 
  node_type: memory
  type: project
  originSessionId: d2c5ac87-a0ef-40f3-8b92-67afa5689392
---

The `IRestClient.GetRecordsAsync(string entityName, Dictionary<string,string>? queryParameters)` overload (RestClient.cs) sends **no PageSize**, so the Profisee Records API applies its **default page size of 50** and silently returns only the first page. `RecordResult.TotalCount` still reports the true total (e.g. 54), but `.Records` holds only 50 — callers that read `.Records` and stop lose the rest.

Caused workflow 10000142 (54 scenarios) to show only 50 in the WorkflowScenariosEditor edit/view, and would also truncate Duplicate/Delete/count of any workflow with >50 details.

**Fix added:** `IRestClient.GetAllRecordsAsync(entity, queryParams, pageSize=100)` pages through until all records are collected — terminates on a short/empty page (returned count < pageSize), with a TotalCount early-out to skip a wasted fetch on exact multiples. Correct for 0 to millions of rows; pageSize only affects round-trip count, not correctness. pageSize=100 is a single round trip for any realistic workflow (won't exceed ~100 scenarios). Use it instead of the no-page-size overload whenever the **full** set is required.

Fixed across BOTH the service layer AND the Blazor pages/controls (the UI calls RestClientFactory(...).GetRecordsAsync directly — fixing only the service layer missed the View/Edit-Workflow screens, which is why the bug kept resurfacing per-screen). Full list of fixed call sites:
- Service layer: WorkflowService.GetAllWorkflowsAsync (workflow LIST) / GetWorkflowScenarioCountAsync / GetWorkflowDetailsAsync / DeleteWorkflowAsync; WorkflowExecutionService GetExecutionsAsync / GetExecutionsByStatusesAsync / GetExecutionDetailsAsync / LoadWorkflowTemplateDetailsAsync (last one feeds CreateExecutionDetailRecordsAsync → a >50-scenario template otherwise builds an execution with only 50 steps).
- UI: WorkflowScenariosEditor.LoadWorkflowScenariosAsync (edit scenarios); WorkflowBuilder.GetWorkflowDetailsAsync (Edit Workflow); Workflows.ViewWorkflow:519 (View) + :902 (execute/duplicate); MatchingBulkEditPanel:191; StepTokenBulkEditPanel:182; WorkflowMonitorJob:53 (running executions per machine); UtilityScenarioEditor:675 (utility template picker).

NOTE: appsettings WebUI:WorkflowBuilder:DefaultPageSize / WebUI:Workflows:DefaultPageSize only control on-screen card paging; raising them does nothing until the REST load is fixed (only ~50 rows ever loaded otherwise). Still NOT changed (different domain, may be intentional / have own paging): ResourceCollectionScenario:210, ResourceMetricsUpdateJob:75 ("firstRecord", intentional single), and test files.

Separately, the editor's on-screen card pagination size comes from `WebUI:WorkflowBuilder:DefaultPageSize` in TestAuto.Web/appsettings.json (Production does NOT override it). That's a display-only cap, independent of the REST truncation above — both happened to be 50.
