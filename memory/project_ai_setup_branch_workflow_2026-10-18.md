---
name: project_ai_setup_branch_workflow_2026-10-18
description: "ai-setup git flow decided 2026-10-18: one work/<change> branch per change, finished (merge --no-ff into main, push, delete) on the machine that started it, both machines proven clean BEFORE new work; guide = vault 99_Frequent\\Push and Pull My Streams.md; tooling (publish.ps1, prof setup push/pull) still main-only, planned later"
metadata:
  node_type: memory
  type: project
  originSessionId: f72b1fa1-4f0b-4455-a732-6236fcf25583
  modified: 2026-10-18T18:03:13.515Z
---

**Decision (Gene, 2026-10-18, after a day of SMVMTR1-vs-laptop merge conflicts on `main`):**
- Branches named `work/<change>` (`work/change1`, `work/dep-review`), one per change. "Lets keep it simple."
- Whoever makes the change commits, pushes and merges it into `main` on THAT machine (laptop or SMVMTR1), then deletes the branch. Merge with `--no-ff` so `git log --first-parent main` lists changes.
- Hard rule: before new work starts anywhere, BOTH clones must show `## main...origin/main` with no ahead/behind, no non-`memory/` dirty files, no `remotes/origin/work/*` left. Root cause of 10/18: SMVMTR1 kit work was uncommitted while laptop work started on `main`.
- Scope chosen: "Guide with manual git first". Tooling stays `main`-only for now: publish.ps1 refuses non-main; `prof setup push/pull` harvest straight onto the target's `main` (fine for memory-only dirt, wrong for kit files); install.ps1 pulls `--ff-only` on the current branch. Follow-up: teach publish.ps1 / prof setup push the `work/*` flow.

**Guide:** `Q:\Work\Work\99_Frequent\Push and Pull My Streams.md` (written 10/18, 248 lines: rule, section 0 pre-check table, laptop flow, SMVMTR1 flow, rollout both directions, recovery 4a-4d, old-command table, cheat sheet). Related pages there: `StreamGuide.md` (tabs + rollout recipe), `Stream and Git.md` (holds an ADO PAT in clear text; never copy it anywhere), `HowToSetupYourPersonalRepo.md`.

**Why:** two writers on one `main` across two clones (plus autonomous Kit-tab edits on SMVMTR1) produced three hand merges in one day; a branch per change makes "in flight" visible (`origin/work/*`) and keeps conflicts off `main`.
**How to apply:** when Gene asks to change anything in `C:\devops\repos\ai-setup`, start with the section 0 check on both clones and a `work/<change>` branch; never commit kit/profile changes on `main`; rollout stays [[feedback_ai_setup_rollout_via_prof]]. See [[project_stream_kit_dependency_review_2026-10-18]], [[project_manageprofile_hub_2026-10-17]].
