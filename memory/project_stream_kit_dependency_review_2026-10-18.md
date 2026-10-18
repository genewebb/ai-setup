---
name: project_stream_kit_dependency_review_2026-10-18
description: "Stream kit dependency review 10/18 - findings F1-F6 with live-board numbers, the five fixes built (BASE-STALE, freshness tick, dependsWhy + DEP-REVIEW, focus closure FOCUS-PULL, DEP-MOVED cascade), verdict \"no dependency agent\", and the planner audit still to file on SMVMTR1"
metadata:
  node_type: memory
  type: project
  originSessionId: f72b1fa1-4f0b-4455-a732-6236fcf25583
  modified: 2026-10-18T15:41:22.528Z
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

**State 10/18 10:40:** Test-StreamKit 222/222, Test-StreamKitRecovery fails=0; laptop installed; PUBLISHED b1cfe17 (Gene typed yes at the secret guard: the Add-Lesson refusal fixture in Test-StreamKitRecovery.ps1:2759 trips the conn-password rule, and so does quoting it in a memory file - never quote that fixture). prof HUB pwsh profile WIP went in the same commit (Gene's choice). Planner audit item FILED on SMVMTR1: `IN-20261018143920-ebda stream-plan` (semantic-edge audit of focus groups via DEP-REVIEW flags; G9.G90 + integration edges need owner sign-off).

**10/18 10:59 MERGE d05c226:** `prof setup push` refused: SMVMTR1's clone had its own kit commit 28f1de6 (ORDERED-BY-MERGE composition-file rule, Find-ArtificialBlockers, Find-TestBlockers, 15 files) conflicting in 3 SKILL.md + Test-StreamKit.ps1 (whole-file conflicts, real diffs small: fetch `\\SMVMTR1\D$\devops\repos\ai-setup main`, `checkout --ours`, re-apply their sentences by hand, keep both test blocks). Merged suites: unit 231/231, recovery 706 PASS fails=0. Versions after merge: integrate v0.19, plan v0.15.

**10/18 11:40 second merge aca808b:** `prof setup push` failed again because publish.ps1 ran `git pull --rebase` with origin unchanged, which replayed 28f1de6 alone and FLATTENED the hand-made merge (fixed in 5833609: fetch, rebase --rebase-merges only when behind; Publish.Tests 9/9). SMVMTR1's planner had meanwhile built its own `dependsWhy` edit in Revise-Task.ps1 (77143de, kit item IN-20261018144201-44e6, acting on my inbox item before my version reached it): kept ITS semantics (`-DependsWhy`, `DEPWHY-NO-EDGE`/`DEPWHY-BAD`, 200 chars, empty clears, removeDependsOn keeps the reason, reason-only edit never releases) + my defaults refill; `Set-DependsWhyDefaults` keeps a stated reason for a removed edge. Suites: unit 231, recovery 712, fails=0. LESSON: filing a planner item about a feature before the kit carrying it is installed on the host makes the host build it twice.

**Open:** SMVMTR1 needs the rollout (`prof setup reload` / `prof setup push -Machine SMVMTR1 -AllowSecrets` / `prof streams update -RestartSessions`) before DEP-REVIEW / FOCUS-PULL / BASE-STALE appear on its status page and the freshness tick runs there.

**Why:** 85% of ticketed rows wait on dependencies, and nothing on the board could say whether an edge was real or whether a landed base matched what the verifier graded.
**How to apply:** when a dependency question comes up, read `FOCUS-PULL` / `DEP-REVIEW` / `DEP-MOVED` / `BASE-STALE` on the status page first; adjust edges only through `Revise-Task.ps1`. See [[reference_stream_kit_mtime_grader_clause_breaks_on_integrate]], [[feedback_stream_mechanical_work_outside_claude]], [[project_smvmtr1_stream_host_genewe_2026-10-17]].
