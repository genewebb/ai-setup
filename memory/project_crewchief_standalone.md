---
name: project-crewchief-standalone
description: "CrewChief — standalone step/workflow automation product extracted from MultiStepUtility; plan approved-in-progress, lives in Plan_CrewChief.md in Obsidian Misc"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2825694e-b55b-4d8f-8678-6b7544e6d5be
---

**CrewChief** (name chosen 2026-07-14; was "StepRunner"→"PitCrew"): a standalone step + workflow automation tool extracted from MultiStepUtility, planned 2026-07-14.

Authoritative plan: `C:\devopslocal\ObsidianVaults\Work\MyWorkVault\99 Documentation\Misc\Plan_CrewChief.md` (supersedes `99 Documentation\speed-merchants\planning\2026-07-14-steprunner-standalone-design.md`).

Locked decisions:
- **Fully self-contained**: new `CrewChief.sln` in the speed-merchants repo but with ZERO TestAuto.* references — engine code (orchestrator, executors, DTOs, UtilityStepConverter, TextTemplater, ParameterResolver, *WithTag logging extensions) is COPIED once from TestAuto.Utilities and owned independently. Only functional NuGet deps; no Profisee.* packages (Cdp lives only in the dropped scenario wrapper). PowerShell executor shells out to pwsh/powershell.exe — no PS SDK.
- **No TestAuto overhead**: scenario wrapper, Hangfire, ScenarioMgt DB, Monitor step, metrics classes, TestAutoSecrets, chunked-config/BROTLI all dropped.
- **Persistence = files ONLY, no database of any kind** (final, 2026-07-14 after weighing files vs SQLite vs centralized Profisee entity store): one JSON per step (`data\steps\<name>.step.json`) / workflow (`data\workflows\<name>.workflow.json`); run history = single `data\runs.json` shown workload-executions-style with add/delete/clear (no SQLite). Definitions folder is git-friendly (ADO repo recommended for distribution/versioning). Profisee-instance store rejected for bootstrap circularity + 4000-char ceiling; SQLite rejected for whole-db-replace/no-merge. Secrets stay in secrets.local.json, never in the data folder.
- **Concepts**: tagged individual Steps (unique Name, individually runnable) + Workflows composing them via `Ref` (+shallow `Overrides`) or `Inline`, GlobalParameters, open custom-parms bag; WorkflowEngine resolves → copied orchestrator executes sequentially.
- **New step types** (same DTO+IStepExecutor pattern, no new orchestration semantics): Wait, MapShare, ServiceControl, AppPool, Uninstall, Install, Configure, HealthGate (per-service healthChecks assertion — aggregate 503 gotcha), RestoreSnapshot. Runner on one machine; actions may target any reachable machine (optional TargetComputer / conn string / URL). Elevation is operational, not architectural.
- **Behavioral reference only**: automation-utilities PR 24286 (Ethan Kim's "Automation Utility" CLI `auto`, branch feature/automation-rework) — mirror step behavior, take NO code. User explicitly declined convergence/shared-package path.
- Phases: 1 engine copy+shell → 2 workflows → 3 simple steps → 4 box-prep steps → 5 optional CLI (Task Scheduler bridge) → 6 tags polish + JSON export/import + ScenarioConfiguration importer.

All plan open items RESOLVED 2026-07-14: CLU kept; WinRM remote REQUIRED in Phase 4 (shared RemoteExecutor seam for AppPool/Install/Uninstall/Configure); CLI REQUIRED (Phase 5, `crewchief run <workflow>`, Task Scheduler bridge); kebab-case Name=filename-stem confirmed; definitions data\ folder checked into the speed-merchants repo itself (runs.json + secrets.local.json gitignored). Additional locked requirements: **UI visual parity with TestAuto.Web** (same Radzen theme/colors/CSS, copy from TestAuto.Web wwwroot); **two test projects** CrewChief.Tests.Unit (Moq+bUnit) + CrewChief.Tests.Integration (real executors/SQL w/ Assert.Inconclusive when no SQL configured) + **≥90% line-coverage gate** on Engine + Web Services/Models.

Scope additions (2026-07-14/15, user): cancellation (cooperative; WasCancelled contract), live per-step progress, SMTP notifications (INotifier, both surfaces, all run kinds), resume/fix-and-continue (WorkflowResumePlanner incl. "Succeeded (prior run)"), CLI with run+view parity, **in-app help system (Web only)** — MD2RazorGenerator+YamlDotNet pipeline + DocsCatalog/HelpLayout/HelpPage/help-docs.js ported from TestAuto.Web, content modeled on TestAuto.Web\Documentation.

**EXECUTION COMPLETE 2026-07-15**: all 20 tasks + final whole-branch review (opus; "With fixes" = doc captures only, applied). Final state: Unit 631/631, Integration 19+3 SQL-gated Inconclusive, build 0/0, coverage Data 94/Cli 95.4/Engine 81.4 (accepted shortfall). **HANDOFF DOC (read first in any new session): `99 Documentation\speed-merchants\planning\2026-07-15-crewchief-implementation-handoff.md`** — architecture decisions, triaged backlog (4 TestAuto-inherited bugs: curl-fallback non-2xx=Succeeded [High], two-hop token literal-embed, maxTimeSeconds quirks, dead CurlExecutor), known limitations (Web/CLI default data folders DIVERGE; runs.json single-writer; secret-echo persists). Ledger: `.superpowers\sdd\progress.md`. User committed the tree incrementally themselves. Phases 3–6 (box-prep steps, WinRM required, elevation UX) need follow-up plans per spec §10.

Related: [[project-repos]], [[feedback-no-commits]]
