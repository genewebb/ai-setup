---
name: project_crewchief_review_2026-07-16
description: "CrewChief full code review 2026-07-16 — what shipped, what's fixed vs the handoff, and the open findings"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7f76139b-3f09-411a-ba87-88ab6d9b2e03
---

CrewChief (`C:\devops\repos\speed-merchants\CrewChief\`, standalone `CrewChief.sln`, 6 projects: Engine/Data/Web/Cli + 2 test) got a full 4-agent read-only review on 2026-07-16. Build 0/0, unit 941/941 green. Zero-coupling gates verified: no TestAuto usings (comments only), not in speed-merchants.sln.

**"Workflow" was renamed "Workload" everywhere in shipped code** (WorkloadEngine, WorkloadFile, `*.workload.json`, IWorkloadFileStore, etc.) — the two 2026-07-14 planning docs still say "Workflow".

**Handoff backlog bugs A/B/C/D are all FIXED** in current code: A (curl non-2xx→Succeeded) via `--write-out HTTP_STATUS_CODE` marker; B (two-hop token) now throws `UnresolvedParameterTokenException`; C (maxTimeSeconds) uses `MaxTimeSeconds ?? TimeoutSeconds`; D (CurlExecutor CURL collision) — CurlExecutor demoted to an injected dep of PowerShellRestExecutor, not an IStepExecutor.

**Open findings (fix before destructive workloads):**
- Critical: Web has NO auth, binds all interfaces, runs arbitrary PS/SQL/msiexec → RCE (`Program.cs:35-81`).
- High: `ContinueOnError` entry that fails orchestrator-side validation → 0 StepResults, silently skipped, workload still Succeeds (`WorkloadEngine.cs:199-217`). SQL `AutoWrapPassFailCode` swallows failures in batches ≥1 (`SqlScriptExecutor.cs:430-477`). CurlExecutor missing final drain `WaitForExit()` → intermittent Bug-A recurrence. Mid-step cancel is dead code in 5 legacy process executors (adopt `DefaultProcessRunner`). WorkloadEditor bypasses `IWorkloadRunCoordinator` (own `StartRunAsync`, run dies on nav). Coordinator mutates live `RunRecord.StepResults` list on bg thread → circuit crash mid-run.
- Medium/Low: CLI `resume --param` silently dropped; runs.json shared `.tmp` collision + bare (non-best-effort) writes crash CLI; null-collection JSON NREs; SmtpNotifier empty-Recipients warning gap; `LogTagConstants.SqlScript` used for everything.

Docs reconciled 2026-07-16: banners added to both `2026-07-14-*` planning docs; handoff `2026-07-15` §5 backlog corrected in place with NEW-1..12. In-app Help (`CrewChief.Web\Documentation\*.md`, 31 docs) is the behavioral source of truth. Relates to [[project_crewchief_standalone]].
