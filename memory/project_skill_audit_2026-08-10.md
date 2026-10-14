---
name: project-skill-audit-2026-08-10
description: "Mode-1 skill audit of the 127-commit/516-file diff — 7 new skills, ~30 corrected; CrewChief Ref/Overrides retired; reverse-staleness now the top defect class"
metadata: 
  node_type: memory
  type: project
  originSessionId: bd62c45b-a588-4a6e-ba96-a8dd24696ae7
  modified: 2026-08-10T18:47:30.502Z
---

Ran `/skill-audit-with-update` Mode 1 on 2026-08-10 over `4c367fe6..15401a46` (127 commits, 516 files,
+78,894/−5,134). 7 read-only Explore agents by subsystem, each given the skill inventory as a coverage
filter. ~96 raw findings → **7 new skills + ~30 corrections, all applied**. Corpus 143 → **150**.
New baseline recorded: `15401a464568d9ade9dee6d7f922b1d15a983e02`.

**Biggest structural change: CrewChief retired `Ref`/`Overrides` on workload steps.** `WorkloadStepEntry` is
now `Inline` + `Label` only. `UpdateStepReferences`, `StepLibrarySnapshot`, `resolveRef`,
`CountLibraryReferences` = zero repo-wide hits. Adding from the library **deep-copies** the step; renaming a
library step affects no workload. `LegacyWorkloadRefGuard` refuses legacy files at load because Newtonsoft
would otherwise deserialize `{"ref": "..."}` into an EMPTY step that runs as a no-op and **reports success**.

**Reverse-staleness is now the most common defect class** — a skill still warning about a bug that has since
been fixed, which sends readers to "fix" working code. **Six** instances: the 30 s `MaxTimeSeconds` hardcode
(now `?? TimeoutSeconds`), `SmartJsonEditor`'s "still a stub" loader (now a real readiness probe),
`BaseApiController`'s `Forbid()` body loss (now `StatusCode(403, …)`), `MetricsCard`'s `chart-bar` default
(now `bar_chart`), a note warning that a `Program.cs` comment was stale (the comment was rewritten), and the
`Features:` vs `FeatureFlags:` log-line caveat (the line now names the key correctly).
When auditing, check the *fixed* direction as hard as the *broken* one.

Applied in **two passes**: the first covered ~37 of ~96 consolidated findings and deferred the rest; a
follow-up ("finish all work that was not done before") drained the remaining 18 to zero. Worth noting for
next time — **an agent's 12-finding cap is a reporting limit, not a relevance ranking**; items below the cut
included a whole 5-route transport model (`BoxPrepRouting`) and a metric-column bug that marked successful
batches as failed. Budget for a second pass rather than treating the first as complete.

Also found a **third census oracle** for [[project_crewchief_steptype_coverage_assertions]]:
`WorkloadRunAsInheritanceTests:353` asserts the box-prep family is **7**, enumerated by reflection over
"registered types declaring a `CredentialSecretName` property" — there is no marker interface, so membership
is defined by a property's presence.

New skills: crewchief-capability-preflight, crewchief-raw-json-editing, crewchief-connect-import,
crewchief-help-docs, testauto-https-hosting, testauto-windows-service-hosting, testauto-production-sync.

Related: [[project_crewchief_workload_merge]], [[project_crewchief_builtin_pool_protection]],
[[project_testauto_production_sync_plan]], [[feedback_verify_no_guessing]]
