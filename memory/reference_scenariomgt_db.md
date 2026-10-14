---
name: reference-scenariomgt-db
description: TestAuto ScenarioMgt has TWO instances — production is the hosted profiseecloud.dev/speedmerchantstest, the local speedmerchants DB is only a dev copy; how to read each and decode the compressed step configs
metadata:
  node_type: memory
  type: reference
  originSessionId: de927cca-c7d9-4280-916c-efa0f4700d44
  modified: 2026-08-12T20:49:53.583Z
---

**Two instances exist and they DIVERGE. Confirm which one before analysing anything.**

- **Production ScenarioMgt = `https://profiseecloud.dev/speedmerchantstest/rest/`** — hosted/SaaS, no SQL
  endpoint. Read it with the `speedMcpRemote` MCP tools (`get_records`, `get_records_count`,
  `get_attributes_by_entity`). Config source: `C:\devopslocal\Secrets\CORPLTR94.prodspeed.json` →
  `RestClients:ScenarioMgt:BaseUrl`. This is where real runs, workloads and metrics live.
- **Local `speedmerchants` DB on `localhost` (CORPLTR94)** — a dev copy. Same entity schema, DIFFERENT data:
  workload names, workflow codes, WorkloadExecution codes and metric rows all differ. Reachable over SQL.

**Cost of confusing them (2026-08-12):** a whole Connect metrics investigation was run against the local copy
— WorkloadExecution codes 100006884/908/916/940 and 2000 clean `ConnectApiExecution` rows — while the user's
actual runs were production codes 100007498/502/589/593 with 4000 rows, 1998 of them wrong. The tell was the
UI screenshot: workloads named `Connect SQL Provider 1M (4 Threads)` / `(8 Threads)` that did not exist in the
local DB **or its temporal history**. A name in the UI with no row in the DB you are querying = wrong instance,
not a rename you missed.

The UI "Workloads" page is `TestAuto.Web\Components\Pages\Workflows.razor` over the **`TestAutoWorkflow`**
entity; steps are `TestAutoWorkflowDetail` (`ExecutionOrder`, `ScenarioConfiguration`).

**Profisee expression filters** (MCP `filter` param) are case-sensitive function names and need double-quoted
literals: `CONTAINS([Name],"Connect SQL")`, `[Workflow] = "10000163"`, `ENDSWITH([Code],"000001")`.
`Contains(...)` silently returns zero rows rather than erroring.

**`ScenarioConfiguration` / `ScenarioData` encodings:** `BROTLI:`/`GZIP:` + base64 (codec in
`TestAuto.Shared/Services/TemplateStorage.cs`), plain inline JSON for small configs (the collection steps are
inline), or `CHUNKREF:<groupKey>:<count>` for large ones — chunks reassemble from
`TestAutoScenarioConfiguration` ordered by `Seq`; `inspect-config.ps1` does NOT implement CHUNKREF.

Local-only reader: `pwsh -File C:\devopslocal\powershellscripts\inspect-config.ps1 -WorkflowCode <code> -CustomParmsOnly`.

Related: [[project_connect_runprofile_direction_authority]], [[reference_connex_recordcount_is_keyrange_width]]
