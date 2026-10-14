---
name: project_crewchief_requirements_corpus
description: "CrewChief has its OWN requirements corpus at Q:\\Work\\Work\\99 Documentation\\CrewChief\\Requirements (Speedy standard, own manifest/ids/schemas copy); first feature FEAT-CC-MODEL-IMPORT-001 (model import from export + Excel refdata), DRAFT 2026-09-19; retrospective convention per feature"
metadata: 
  node_type: memory
  type: project
  originSessionId: a86b5b9b-3296-4235-aa9a-cacdfb8b3e36
  modified: 2026-09-19T16:44:09.389Z
---

CrewChief requirements live in a separate corpus root: `Q:\Work\Work\99 Documentation\CrewChief\Requirements`
(Gene, 2026-09-19: "put crewchief requirements here"). It uses the Speedy standard `RequirementDesign.md`
unchanged, but has its OWN `manifest.yaml`, `ids.yaml` (every DOMAIN starts `CC-`), a COPY of `schemas/` taken
2026-09-19 (reqtools loads schemas from the validated root; re-copy when Speedy's change), `plans/` and `review/`
(both excluded from validation). Validate with
`python C:\devops\repos\speedmerchants\tools\requirements\reqtools.py validate "Q:\Work\Work\99 Documentation\CrewChief\Requirements"`.

First feature: `features/FEAT-CC-MODEL-IMPORT-001.yaml` (model import wizard `/model-import`: model export +
one .xlsx per entity → `-teardown`/`-build`/`-refdata`/`-full-run`/optional `-datastore` workloads), revision
`35fd45f9` (amended 2026-09-19 during implementation: REQ-003/005/006/008/009, AC-003/005/006/008/009/012/014), status DRAFT, 17 REQ / 17 AC / 3 VERIFY / 1 MET / 3 open Q (all non-blocking). Q-001 and Q-002 answered
and retired 2026-09-19: batch size is a design-time value; the live probe (VERIFY-003 attempt 1, evidence filed under
revision folder 3db20a9a) showed domain = Code string, Date yyyy-MM-dd, DateTime yyyy-MM-ddTHH:mm:ss with NO Z (Z is
rejected), null clears a value, and a rejected value does NOT roll a batch back (records stored minus the bad attribute). Plan: `plans/2026-09-19-model-import-plan.md` (10 tasks, mockup gate = Task 7).

**Retrospective convention (Gene's ask):** every feature gets `review/RETROSPECTIVE-<FEAT-ID>.md`, filled at
planning, implementation and verification with what the requirement failed to say, what was unhelpful, and what
to change in the standard; owned by a non-blocking Q on the feature (Q-CC-MODEL-IMPORT-005 here).

**Why:** trial of the requirements system on a real non-Speedy target; Gene wants to learn whether the format
helps planning/implementing.
**Lessons folded into the skill 2026-09-19:** `requirements-writing/references/criteria-checks.md` (ten criterion checks from this feature).
**How to apply:** author CrewChief requirements here, never in the Speedy corpus; write the retrospective entry at
each of the three moments; push every file via Write-VaultFile.ps1 and verify by hash (23/23 matched 9/19).
Related: [[project_speedy_requirements_system]], [[feedback_requirements_system_review_gate_per_task]].
