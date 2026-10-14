---
name: vnext-workflow-engine-agnostic-port
description: "D7 (Gene 2026-09-05 20:58): vNext's workflow layer is engine-agnostic by design — one IWorkflowEngine port + registry + capability flags, native (CrewChief-style) adapter first, Elsa or any later engine as an adapter that must pass a conformance kit; engines orchestrate but never execute; dbo.Run is the only truth. Carried by loop row 53.02 (450m) between W1.1 and W1.2."
metadata: 
  node_type: memory
  type: project
  originSessionId: 066f3f32-f062-4351-be28-5be527d59764
  modified: 2026-09-06T01:05:45.473Z
---

**Ruling (Gene 20:58, after asking how to stay agnostic across CrewChief / Elsa / an unknown engine, "1 to N or swap them out easily"): "use your best practice pattern, record that and adjust the schedule."** Recorded as D7 in `Q:\Work\Work\99 Documentation\speed-merchants\vNext\Design\W1_ProFlowSpike.md` §8 (+ §6 row 8). It supersedes the 20:33 option row 50.W1.0 and UoW-10 D3's two-implementation `IWorkflowCatalog` hedge; it does NOT reopen D6 (native first, Elsa at the end, possibly v2).

**The seven rules:** (1) `WorkloadDefinition` (CrewChief bundle) is the only authored artifact; `IWorkflowCatalog` has exactly ONE implementation; an adapter compiles the bundle into its own model at start. (2) Engines orchestrate, never execute — every adapter resolves `StepExecutorRegistry` and calls the same `IStepExecutor`; an Elsa activity is a thin wrapper. (3) `dbo.Run` + `StepRunRecord` are the single truth; engine-internal state is private scratch nobody reads; nullable `Orchestrator` column names the owner. (4) Anti-corruption layer per adapter in `src/Infrastructure/Engines/<Name>/` with one `AddSpeedy` module; an architecture test fences the namespace. (5) `IWorkflowEngineRegistry.Resolve(name)` + `EngineCapabilities` flags limited to the four reopen triggers (human wait · durable timer · bookmarked branching · global parameters); refusal BY NAME before start. (6) `WorkflowEngineConformance<TEngine>` kit (start · 3 steps · status · suspend · resume · SIGKILL · parent+3) is the admission ticket — no green kit, no registration. (7) `engine: native` written on save; composition census covers every registered engine. Refused: a generic activity abstraction in the domain, engine fields on the definition, pages reading an engine store, a second catalogue.

**Schedule effect:** 53.02 retitled + 330→450 plan (orchestrator estimate, re-calibrate at close), moved out of the UoW-10 block to sit between 50.W1.1 (needs `ParentRunId`) and 50.W1.2 (launcher resolves via the registry); 50.W1.0 folded to 0m; 50.B = Elsa adapter vs the kit, 550m, dormant, not in ALL-IN. ALL-IN 411h 51m at 21:05 (+73m). GOAL W1.6 = 53.02's criterion (`u10-w2-workflow-port.ps1`).

**How to apply:** when 53.02's PLAN is written, the seven rules are the falsifications (second catalogue impl, engine namespace outside its folder, step run outside the registry, kit red for native). Any future "add engine X" request = one adapter folder + module + kit green; if it needs more, the port is wrong, not the request. Related: [[vnext-planning-sweep-2026-09-05]], [[review-pages-need-readable-pick-channel]].

**SUPERSEDED IN PART 2026-09-13 18:49 (Gene, dial-builder page D17): Elsa is DROPPED from the plan.** Row 50.B marked DROPPED on the board; the periodic Elsa feature review is no longer owed. The port itself (rules 1–6) STAYS as architecture because the native engine needs the same seams; the conformance kit becomes the native engine's own test. See [[project_dial_workload_builder_design_2026-09-13]].

**19:08 follow-through:** rows 50.B and 50.W1.0 REMOVED from Write-TaskList.ps1 and schedule-order.txt (not just marked); 53.02 retitled native-only, registry / EngineCapabilities / refusal-by-name / `engine:` field dropped, 450 → 330 plan (300 cal); 50.W1.2 uses the one native engine; decision table rows for W1 marked SUPERSEDED / RESOLVED NEVER. Board 319 tasks, schedule v156. The `elsa-feature-review` skill is now dead weight (not deleted; skills live in the ai repo).
