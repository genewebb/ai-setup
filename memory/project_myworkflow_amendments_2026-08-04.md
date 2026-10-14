---
name: project_myworkflow_amendments_2026-08-04
description: "/myworkflow gained census probe, scope ratification, deviation-blocked, -ExcludeLocally and a mandatory -Paths gate on 2026-08-04 — the loop behaves differently from any earlier session's memory of it"
metadata: 
  node_type: memory
  type: project
  originSessionId: 4ba72a7f-ac41-4d46-a1c9-ab0a330a5010
  modified: 2026-08-04T13:06:52.567Z
---

All nine amendments from `99 Documentation\Goals\LESSONS-2026-08-03-crewchief-teams-step.md` were
applied 2026-08-04 (that doc's `## Applied` section is the authoritative per-section map). Behaviour
that changed, and that an older memory of this skill will get wrong:

- **GOAL.md is no longer blanket-immutable.** Intent is immutable; the FILE LIST is amendable by the
  Verifier under a five-condition ratification protocol (`SKILL.md § Scope ratification protocol`).
  Condition 4 — the diff must only ADD, never weaken an assertion — is the load-bearing one.
- **`deviation-blocked`** is a third deviation kind: Executor finished but a forbidden file must also
  change. Fails the iteration, no rollback, no identical retry; logged `partial` so
  `Test-Budget.ps1` (which counts only `fail`, line 174) leaves the consecutive-failure streak clean.
- **Interview Batch 3b** greps the test tree for coverage assertions before finalizing scope.
- **`-Paths` is mandatory on `Get-ChangedFiles.ps1`** and the script now warns on stderr when it is
  omitted mid-loop. Without it gate 4 compares a cumulative diff to a per-iteration expectation.
- **`-ExcludeLocally` is the new default switch** on `Initialize-Loop.ps1` (writes `.git\info\exclude`
  via `git rev-parse --absolute-git-dir`). `-AddGitIgnore` still works, now opt-in only.
- **`MODELS.md` records a 60-140k-token floor per Executor dispatch** — batch trivial follow-ups, and
  do not dispatch at all for one-token edits.

**Why:** the source run met 5/5 criteria but aborted once and needed three mid-run GOAL amendments,
all from the same root cause — coverage assertions that no interview can surface.

**How to apply:** before proposing changes to this skill, read the lessons doc's `## Applied` table —
these nine are done. Related: [[project_crewchief_steptype_coverage_assertions]],
[[project_orchestrator_worker_loop_hardening]], [[reference_workai_sync]].
