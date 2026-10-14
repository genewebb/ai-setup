---
name: project-testdata-targets-fix-2026-09-23
description: "FEAT-TESTDATA-* 9/23-24: all Gene answers applied, 0 open Qs, READY gaps deferred (READY-DEFERRED-FIXES.md), CLI-001 READY; clean review owed"
metadata:
  node_type: memory
  type: project
  originSessionId: e53f9200-e4eb-4ea9-889c-8db53fc6eb4f
  modified: 2026-09-24T03:43:09.414Z
---

State of the 10 FEAT-TESTDATA-* targets on 2026-09-24. All are REVIEW, and BACKLOG shows 0 active questions.

- Gene's decisions:
  - Resume rule for both kinds: any completed checkpoint means a resume, with no DDL (RUN#resume-before-recreate).
  - A changed ChunkSize on resume is refused.
  - The protected-DB list comes from the deployment config read at service start; an empty or unreadable list refuses start (REQ-TDENGINE-014/027).
  - Samples are seeded once, keep their localhost connection strings, and are never copied back.
  - Help exits 0 for both kinds.
  - A report requested with an emission is shape-only, for both kinds.
  - A created mutation DB is set to SIMPLE recovery.
  - Report Warnings section for both kinds.
  - MaxPerParent above 100 is refused at validation.
  - A generation file is refused by the mutation load.
- MUTATION disposition is now REDESIGN, because PORT forbids `change` rows (rule 5).
- 2026-09-24: Gene confirmed RUN#outcome-not-exception.
- FEAT-CLI-001 is READY at 5d075ddb, with Gene's review plus approval. A superseded approval must be REMOVED for READY; the validator errors on a stale approval.
- The READY-target gaps were DEFERRED (Gene chose option c). They are listed in review/READY-DEFERRED-FIXES.md and noted on the candidate mappings. Apply them the next time UI-SHELL, INSTALLER, UI-ACTIVITY or WORKLOAD-RUN is reopened.
- Live corpus: 0 errors, 114 warnings.

**Why:** the next session needs the decisions and blockers without re-deriving them.
**How to apply:**
- The run log is review/OVERNIGHT-TESTDATA-LOG-2026-09-23.md ("Second run" and "Third pass" sections).
- Next step: a clean-session review (the runbook morning prompt).
- `digest --write` reflows review `given` blocks. Snapshot and restore `reviews`/`approvals` around it every time.
- Related: [[project_speedy_requirements_system]].
