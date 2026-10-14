---
name: project-testdata-closeout-plan-2026-09-24
description: "TESTDATA requirements close-out plan: ledger, invariants I1-I7, delta review with a hard stop; B1-B9 answered; R6 SWAPPED (TESTDATA first, library-fix-list-r1 rebuilt after); tracks T and L"
metadata:
  node_type: memory
  type: project
  originSessionId: 0ea61e79-068c-4a42-9300-94ed42155416
  modified: 2026-09-24T18:51:20.341Z
---

Round-2 clean review (review/claude-review-testdata-r2-2026-09-24.md) found 1 blocking, 6 major and about 25 minor findings. Gene said "we seem to be going in a circle", so the plan review/TESTDATA-CLOSEOUT-PLAN-2026-09-24.md sets these rules:
- R1: the finding ledger is the only work list (now 34 rows, ENT-2 added).
- R2: invariants I1-I7 are checked by both the fix pass and the review. I3 now covers ENTRY.
- R4: round 3 is a DELTA review.
- R5: at most one repair round, then Gene decides.

Gene's decisions, 2026-09-24:
- B1: a validation failure is refused with exit 2 and no run record.
- B2: throughput rounds half to even (donor N0).
- B3: the samples are exempt from REQ-TPL-012 adaptation.
- B4: port the donor backfill checkpoints.
- B5: RUN-4, the key statement finishes, then Cancelled.
- B6: TPL-3, the category marker plus on-demand install for later additions.
- B7: TPL-4, the baseline rationale.
- B8: ENT-2, ENTRY REQ-023 applies duration-display.
- B9: WEB-1, recorded as Gene's decision.

**R6 is revised.** The library-fix-list-r1 clean review (review/claude-review-library-fix-list-r1-2026-09-24.md) found it NOT approvable: 5 blocking, 23 major, 19 minor. Its P1 finding: the package would revert A18 in CONTENT, so it needs a rebuild anyway. TESTDATA therefore publishes first, and the library package is rebuilt after T4.

**Track T.**
- 1a stage is done (C:\tmp\testdata-closeout-r3\stage, 32 placeholders, 0 drift vs live).
- **T1b publish DONE 2026-09-24:**
  - Published 11 live artifacts (the 10 staged plus DEPLOY, which is pin-only) and their views.
  - Allocated 30 IDs in ids.yaml. The TPL-018 pair went into the amendment's pending events file instead.
  - Rebuilt the amendment: 49 artifacts, 13 sweeps.
  - Vault validate: 0 errors / 115 warnings. With the amendment applied: 0 errors / 146 warnings.
  - Report: review/closeout-r3/FIX-REPORT.md. Scripts are in C:\tmp\testdata-closeout-r3\publish.
- **Next is T2**, the clean-session delta review. Then T3, a repair only if needed, then T4, approval.
- **Gotcha:** relation pins do not always put `revision` right after `target` (sometimes `reason` comes between). Use a regex that allows lines in between; the old C:\tmp\repin.py pattern missed one.

**Track L.**
- L1 prompt, FIX-PROMPT-LIBRARY-FIX-LIST-R1-REBUILD: phase A stages at C:\tmp\library-fix-r1b and asks Gene N1/V1, W3, W1/S-1 and A1. Phase B rebuilds after T4.
- Then L2 (REVIEW-PROMPT-LIBRARY-FIX-LIST-R2), L3 repair, L4 approval.

**Why:** full fix-then-full-review cycles each closed findings and opened new ones. Two amendments shared 49 files, so whichever publishes second must rebase.

**How to apply:** the waves table in the plan is authoritative. Never run two vault-writing steps at once (T1b, T3, T4, L1 phase B, L3, L4). L1 phase A may run beside T1b, T2 and T3. Related: [[project-testdata-review-fix-2026-09-24]], [[feedback-reviews-by-claude-clean-session]], [[project-library-fix-list-amendment-r1]].

**T4 DONE 2026-09-24 17:32:** Gene approved all 13 r3 revisions and templates-testdata-samples-r1, which is published. There are 41 READY artifacts: all TESTDATA, WEB-HOST, TEMPLATES, and 29 pin-only re-approvals. PRIORITY-LOAD keeps its REVIEW label. The release is at review/approved/testdata-closeout-2026-09-24/. Pin-only revisions got Claude tool review entries citing r3's clean-session pin-masked check (Gene's choice). A READY artifact with a stale old approval is a validator ERROR, so the stale approval is replaced and named in the note. Next: L1 rebuild.
