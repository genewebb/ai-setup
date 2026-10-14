---
name: project_crewchief_review_2026-07-17
description: "CrewChief full solution-architecture review 2026-07-17 — the deep-dive pack, what's now fixed, and the remaining findings"
metadata: 
  node_type: memory
  type: project
  originSessionId: e6761d44-d970-4c16-b314-d56232abbf65
---

Full solution-architecture-review of CrewChief on 2026-07-17 (branch bug/crewchief_testing/genewebb @ f5364aa0, post-PR-24588). 12-doc deep-dive pack written to `C:\devopslocal\Documentation\speed-merchants\reviews\2026-07-17_solution-review\` (00_SolutionInventory … 11_DeveloperGuide, 10 ADRs, README_DeepDivePack index). Method: 3 parallel read-only agents (Engine/Web/Data+CLI) + live build+test.

**Live gates at head (better than README's recorded 941):** build 0/0, Unit **1220/1220**, Integration **24/24, 0 skipped** (SQL was configured on this box so SQL-gated cases ran). 17 step types now (IisReset added; README still says 16).

**ALL prior findings FIXED** — the 4 handoff bugs (curl non-2xx, two-hop token, maxTimeSeconds, dead CurlExecutor) AND all 6 of the 2026-07-16 findings: ContinueOnError silent-skip (WorkloadEngine.cs:199-222 synthesizes failure), SQL AutoWrap batch-swallow, curl drain WaitForExit, dead mid-step cancel (all 5 legacy executors now tree-kill), coordinator live-list mutation (copy-on-write Snapshot), editor coordinator-bypass, runs.json .tmp collision + best-effort writes, resume --param drop, SecretsBootstrapMiddleware now wired (Program.cs:240).

**Remaining findings (see 08_RefactoringBacklog B1–B24):**
- CRITICAL: still no auth anywhere + ListenAnyIP → unauthenticated RCE (ADR-009, needs a decision). Secret-echo-to-runs.json plaintext (H-2).
- HIGH: B1 IisReset default type "IisReset" has NO orchestrator executor alias (UtilityOrchestrator.cs:60-83) → "No executor found"; workaround set type "IisResetStep". Root cause = StepTypeRegistry not the sole dispatch source (ADR-008): also 2 duplicated CreateStepForType factories (Steps.razor.cs:217 + WorkloadEditor.razor.cs:373) + separate alias table.
- MED: B3 [JsonExtensionData] on UtilityStepBase defeats Overrides typo validation (dead code). B5/B6 SQL AutoWrap drops GO n repeats + single write-batch hits SOURCE conn outside txn. B8 RunRecord.StepResults missing NullValueHandling.Ignore → NRE on hand-edited runs.json (residual of prior null-collection fix). B9 TimeoutSeconds=0 = instant in 5 legacy executors (infinite elsewhere). B10 token replace skipped when Parameters empty. B14/B15 non-atomic secret writes + fixed .tmp in step/workload/ref stores. F6 session-local mutex → cross-session lost runs.json updates.
- Commendations: Tier-1 sealed secrets textbook (AES-GCM, 300k PBKDF2, downgrade protection both directions); DPAPI CurrentUser; SetApiKey parameterized+1-row; path traversal not exploitable (kebab guard); XSS-safe (@ in <pre>, no MarkupString). Tier-2 crypto weak BY DESIGN (CBC/fixed-salt/10k/static-IV) for TestAuto v2 byte-compat = ADR-006, don't "fix".

Supersedes [[project_crewchief_review_2026-07-16]]. Relates [[project_crewchief_standalone]], [[project_crewchief_steptype_factory_duplicated]].
