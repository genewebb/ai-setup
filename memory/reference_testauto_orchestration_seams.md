---
name: reference_testauto_orchestration_seams
description: "How to drive TestAuto from outside — completion is polled not emitted, CLI exits 0 on invalid config, needs elevation, and Complete does imply metrics persisted"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 3b2e771a-f1e5-4e23-814b-6a871161986f
  modified: 2026-08-12T15:11:09.095Z
---

Verified 2026-08-12 reading source for the "metrics complete then CrewChief then TestAuto" chaining question. All paths under `C:\devops\repos\speed-merchants`.

**CrewChief is a subtree of speed-merchants** (`speed-merchants\CrewChief\`), NOT a separate repo. One `git status` covers both.

**Completion is discovered by polling, not emitted.** `WorkflowMonitorJob.cs:49-53` detects finished work with a REST/OData query on `TestAutoWorkflowExecution` filtered `ExecutionStatus eq 'Running' and ExecutionMachine eq <machine>`, then `WorkflowOrchestrationService.cs:472-482` stamps Complete/Failed. Default interval 5 min (`WorkflowMonitor:IntervalMinutes`, gated `FeatureFlags:EnableWorkflowMonitor`). So an external poller is the SAME mechanism TestAuto uses — not a downgrade. There is nothing to subscribe to.

**`Complete` DOES mean metrics are persisted.** `BatchJobOrchestrator.cs:424-432` chains `WorkloadExecutionUpdateJob` after the last `MetricsPersistenceJob` with `JobContinuationOptions.OnlyOnSucceededState`. Safe to trigger downstream work on Complete. But `ResourceCollectionJob` runs AFTER the status flip (`:474-478`) and finishes async via a recurring job — resource data is still landing.

**Two hang hazards, no built-in timeout:** `OnlyOnSucceededState` means a failed metrics job never flips status, so the execution stays `Running` forever; and `CheckAndProgressWorkflowAsync` swallows every exception (`WorkflowOrchestrationService.cs:492-495`). Any caller owns its own wall-clock timeout.

**TestAuto CLI is an exit-code liar on the scenario path.** `VerbRunTestOptionsHandler.HandleAsync` returns `Task` and prints+`return`s on failure (`:120-124` missing filepath, `:134-141` validation errors, `:143-148` missing enqueue service). `Program.cs:85-94` takes its code from `System.CommandLine` `UseDefaults()`, which only maps unhandled exceptions — so **invalid scenario config exits 0**. The `--workload`/`--job`/`--load` branches DO `throw` (`:180, :213, :246`) so those exit 1. Never gate on TestAuto's exit code; read execution status.

**Success on the CLI means "scheduled", not "finished"** — `:150-152` calls `EnqueueScenarioAsync`. No wait-for-completion mode exists.

**TestAuto blocks unattended runs without elevation.** `Program.cs:21` calls `UserHelper.PromptIfNotAdmin`, which is an interactive `AnsiConsole.Confirm` (`UserHelper.cs:59`) defaulting false. Scheduled task must use highest privileges.

**Better trigger surface than the CLI:** `TestAuto.Web\Controllers\ExecutionControlController.cs` — `POST api/executioncontrol/execute` (`:43`, returns 400 WITH validation errors, 500 on failure), `GET jobs/{jobId}/status` (`:110`), `GET active` (`:276`), `GET stats` (`:374`). **No `[Authorize]` attribute on the controller** (`:15-19`) — global policy unverified; treat as a possible unauthenticated execute endpoint.

**There is NO workflow-level HTTP surface.** All 23 controllers in `TestAuto.Web\Controllers\` are scenario / `WorkloadExecution`-level. Nothing starts a `TestAutoWorkflow` by code or reads `TestAutoWorkflowExecution` over HTTP. Driving a multi-step workflow externally needs SQL against ScenarioMgt or a new endpoint.

**Poll the right status endpoint.** `GET api/scenarioexecution/status/{jobId}` reads the WorkloadExecution record (`ScenarioExecutionService.cs:322`) — correct. `GET api/executioncontrol/jobs/{jobId}/status` returns the **Hangfire job state** (`ExecutionControlController.cs:148`), which can report Succeeded as soon as the batch is enqueued — a false completion. `POST api/executioncontrol/execute` returns `WorkloadExecution.Code` as its jobId (`ScenarioWebService.cs:147-150`), so the submit and the poll use the same key.

**CrewChief cannot poll.** `StepTypeRegistry.cs:61,74` has a fixed `WaitStep` and a `CheckPortStep` probe only — no poll-until-status step, so CrewChief cannot orchestrate TestAuto without a new step type.

Recommendation landed in `99 Documentation\speed-merchants\planning\Design_MetricsToCrewChiefToTestAutoOrchestration.md`: thin external PowerShell+ScheduledTask driver, upgrade to ADO pipeline for history/alerting. Related: [[project_crewchief_standalone]], [[feedback_207_not_success]], [[reference_configuration_exe_failure_modes]].
