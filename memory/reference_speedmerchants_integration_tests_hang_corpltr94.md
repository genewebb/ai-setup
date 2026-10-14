---
name: reference-speedmerchants-integration-tests-hang-corpltr94
description: "2026-10-10: every Testing.SpeedMerchants.Integration test hung on CORPLTR94 (no output after 'Test Parallelization enabled', >10 min) before any test seeded data; cause not found"
metadata:
  node_type: memory
  type: reference
  originSessionId: 3cbf42a2-10bf-4c57-99a5-a810b87f7f83
  modified: 2026-10-10T17:16:58.452Z
---

On 2026-10-10 on CORPLTR94, `dotnet test Testing.SpeedMerchants.Integration` hung for every filter I tried, including the existing `WorkAreaEntityShapeTests` and the new `RunPurgeLiveTests.Staging*` tests. The last output line was "MSTest Executor: Test Parallelization enabled". No `RPT…` rows were seeded, so it hung before TestInitialize finished. A `timeout 240` kill reported "Test host process crashed".

Suspect (NOT verified): `PerformanceBaseTestClass.AssemblyInitialize` → `ServiceHelper.RegisterServices` (CDP service + NServiceBus session), which runs for every test in the assembly.

**How to apply:** before running integration tests, run one with `timeout 240` first. If it hangs, report it rather than waiting 10 minutes. Run Purge SQL was instead checked read-only through the speedmerchants-local-mssql MCP.

Related: [[reference-profisee-staging-delete-procs]], [[project_testauto_metric_run_purge_2026-10-07]]
