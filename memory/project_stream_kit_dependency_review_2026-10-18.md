---
name: project_stream_kit_dependency_review_2026-10-18
description: "Stream kit dependency review 10/18 - findings F1-F6 with live-board numbers, the five fixes built (BASE-STALE, freshness tick, dependsWhy + DEP-REVIEW, focus closure FOCUS-PULL, DEP-MOVED cascade), verdict \"no dependency agent\", and the planner audit still to file on SMVMTR1"
metadata:
  node_type: memory
  type: project
  originSessionId: f72b1fa1-4f0b-4455-a732-6236fcf25583
  modified: 2026-10-18T14:37:39.576Z
---

Review of how the stream kit handles `dependsOn` (2026-10-18, Gene asked for an objective critical review, then "make your suggested improvements"). Source of truth is `C:\devops\repos\ai-setup\skills\stream-kit\scripts` (installed copies under `~\.claude\skills` are copies).

**Live-board numbers (laptop copy of speedmerchants `.streams\tasks.json`, 10/17 09:52):** 1,289 rows, 5,740 edges; 1,178 from integration tasks, 209 gate edges, 2,803 share a write-set file, **1,550 share no file** (semantic). 215 ticketed, 182 waiting on deps (median 3.4 d); 152 wait on `G9.T900` + owner gate `G9.G90` (all of G10). 25 dependency bounces with a dependent in flight (19 grader-suspect, 6 rebase). 96 STALE re-authors, all at activation. 3 "already met" rows ever.

**Findings:** F1 `base.deps` fingerprint written, never read. F2 freshness ran once per group activation only. F3 semantic edges have no stated reason. F4 focus set used min effective rank, so an EARLIER open unlisted group's dependency froze a focus row for ever (board said "wait on roots" only). F5 owner gate as 152-row root (intentional, redundant with focus; NOT changed - owner call). F6 no cascade when a dependency leaves built mid-build.

**Built 10/18 (Test-StreamKit 222/222 green; recovery suite +7 cases):**
- `Integrate-Patch.ps1` **BASE-STALE** before any apply: `lib\Streams.ps1 Get-DependencyBaseDrift` compares `base.deps` hashes with the dependency's current patch; mismatch = ticketed, patch kept.
- `Activate-Group.ps1 -FreshnessOnly`: status tick runs it every cycle for ACTIVE focus groups (`Start-StreamRunner.ps1` status tick, `freshness:` on the STATUS-TICK line). Judges the row's OWN write set only (a dependency landing its own files is expected; continuous dependency-file staleness would re-author most chained tickets).
- `dependsWhy` (id -> reason) on every row: `Add-Tasks.ps1`/`Revise-Task.ps1` fill `shared file` / `group order` / `mockup first`, planner text kept, else `unstated`; Revise batch edit `dependsWhy`, refusal `WHY-NO-EDGE`.
- `Get-FocusSet` = `Get-FocusClosure`: plus transitive unlanded dependencies of UNLANDED focus rows (landed rows pull nothing - that broke an existing gate test first). Board flag `FOCUS-PULL`.
- `Update-Task.ps1`: a built row leaving built notes `DEP-MOVED` on building dependents (`Add-DependentBounceNotes`). Board flags `DEP-MOVED`, `DEP-REVIEW` (unstated edge holding 2+ ticketed rows 2+ days; env `STREAM_DEP_REVIEW_MIN_WAITERS/_MIN_DAYS`).
- PS trap hit twice: a lib function returning `, $list` must NOT be wrapped in `@()` by the caller (gives an array holding the list).

**Verdict on a dedicated dependency-revalidation agent: NO.** Mechanical parts are scripts (Gene's rule: mechanical stream work outside Claude); the judgment part belongs to the planner/coordinator who already own `dependsOn` via `Revise-Task.ps1`; a third writer recreates the 9/28 two-planners failure.

**State 10/18 10:40:** Test-StreamKit 222/222, Test-StreamKitRecovery fails=0, installed on laptop (install.ps1 -NoPull -Yes). Publish stopped on the secret guard (fixture `password=hunter2` in Test-StreamKitRecovery.ps1:2759, needs typed yes on a console); Gene runs publish.ps1 in his own terminal. publish.ps1 = `git add -A`, so the prof HUB pwsh profile WIP goes in the same commit (Gene's choice).

**Open:** file a `stream-plan` inbox item on SMVMTR1 (live host, as CORP\genewe) asking for a semantic-edge audit of the focus groups (DEP-REVIEW flags will name the targets once installed there). Not filed from the laptop: laptop board is sync-only. Install on SMVMTR1 via ai-setup publish/install.

**Why:** 85% of ticketed rows wait on dependencies, and nothing on the board could say whether an edge was real or whether a landed base matched what the verifier graded.
**How to apply:** when a dependency question comes up, read `FOCUS-PULL` / `DEP-REVIEW` / `DEP-MOVED` / `BASE-STALE` on the status page first; adjust edges only through `Revise-Task.ps1`. See [[reference_stream_kit_mtime_grader_clause_breaks_on_integrate]], [[feedback_stream_mechanical_work_outside_claude]], [[project_smvmtr1_stream_host_genewe_2026-10-17]].
