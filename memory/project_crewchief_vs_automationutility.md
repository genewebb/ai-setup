---
name: crewchief-vs-automationutility
description: Capability diff + full-replacement plan for CrewChief absorbing the Automation Utility (PR 24286); planning doc + key gaps/conflicts
metadata: 
  node_type: memory
  type: project
  originSessionId: 11dc5356-99d0-42b7-8b69-c24c0a7f66d0
  modified: 2026-07-20T23:43:17.236Z
---

2026-07-20 planning doc `99 Documentation\speed-merchants\planning\Plan_CrewChief_vs_AutomationUtility.md` compares CrewChief to the **Automation Utility** (PR 24286, repo `automation-utilities`, branch `feature/automation-rework` — PR is ABANDONED/not-completed, status 2, so content lives only on that branch; read via shallow clone since ADO MCP file-content tools returned empty).

Both descend from MultiStepUtility (same StepCatalog/StepExecutor/ProgramValidator/RunContext shape), so "full replacement" (user's chosen scope) = CrewChief ABSORBING automation-specific layers, not a rewrite.

Step diff: 10 of 13 mapped steps already covered by CrewChief's 19 types (mapShare/service/apppool/uninstall/install/configure/runSql/restoreSnapshot(=DatabaseOperations superset)/healthGate/wait). MISSING 3: `prepareRepo` (git reset+MSBuild), `deployData` (setup test+snapshot), `runSuite` (test runner subsystem).

Big gaps: (1) test-runner subsystem — ITestRunner + DotnetTestRunner/VsTestRunner (TRX parse) + PlaywrightRunner + suite defs + rerun-failed(TestResultComparer); (2) reporting DB MaestroTestReporting — CONFLICTS: uses EF TestDbContext (EF FORBIDDEN in CrewChief → must be ADO.NET) AND breaks CrewChief files-only invariant (make opt-in); (3) build-source/target model (BuildSourceResolver/MsiInspector/SystemVersionResolver: target mode→MSI dir, version from MSI); (4) healthGate ZeroHealthy→bounded whole-run restart w/ ReportingCommitted guard; (5) profiles-as-targets + `config get/set` dotted-path; (6) CLI monitor/interactive/--suites-only/--foreground; (7) scheduled-task nightly bootstrap.

Plan = 8 phases (0 small gaps → 1 target model → 2 prepareRepo/deployData → 3 test-runner files-only reporting → 4 reporting DB opt-in decision-gated → 5 Playwright → 6 health restart → 7 box deploy mode). Phases 0-3 = majority of value (vstest suite end-to-end, files-only reporting). Open decisions: accept external DB or files-only+export; profile-vs-workload entity; Web UI parity; map plaintext profile secrets → {{$config}}. See [[project_crewchief_standalone]] [[project_crewchief_installer_plan]].
