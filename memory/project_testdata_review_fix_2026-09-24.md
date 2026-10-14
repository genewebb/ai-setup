---
name: project-testdata-review-fix-2026-09-24
description: "FEAT-TESTDATA-* clean review 9/24 + fix pass PUBLISHED; round 2 (A11a/A18-A21): TEMPLATES amendment templates-testdata-samples-r1 staged (49 artifacts, 30 READY), lint knows rendered reads; next = Gene runs review/REVIEW-PROMPT-TESTDATA-R2 in a NEW session"
metadata:
  type: project
---
State on 2026-09-24:

- The Claude clean-session review is at review/claude-review-testdata-2026-09-24.md.
- Gene's answers are at review/TESTDATA-REVIEW-FIX-ANSWERS-2026-09-24.md (A1-A17).
- The fix pass has been published: the 10 FEAT-TESTDATA files, FEAT-WEB-HOST-001, ids.yaml (99 IDs allocated by coordinator-claude-testdata-review-fix) and READY-DEFERRED-FIXES.md. Each file was hash-verified.
- Live corpus: 0 errors, 134 warnings (114 before). The 20 new warnings are the lint "then does not mention persisted or measured state" on UI-display ACs.

Changes that deviate from or add to the plain answers:
- GENERATION became REDESIGN, with decision decimal-at-scale: decimals round half away from zero at NumberScale.
- WEB-HOST became REDESIGN, with REQ-WEBHOST-006 and decision host-owns-start-refusal. The host refuses to start; ENGINE supplies the check through REQ-TDENGINE-027.
- A11 deviation: Gene said RUN should own the duration format. It lives in ENGINE instead, as term duration-display, because RUN applies ENGINE and the reverse link would create a cycle. REPORT points at ENGINE.
- The TEMPLATES side of the samples hybrid is deferred. It sits in the FEAT-TEMPLATES-001 section of READY-DEFERRED-FIXES.md.
- .NET rounding: "{0:0}" rounds half away from zero, while "N0" rounds half to even. Report throughput uses N0 to match the donor.

**Why:** this session authored the fixes, so it cannot review them.
**How to apply:**
- Next step: a NEW clean-session review of the 10 artifacts plus WEB-HOST.
- Tell Gene about the A11 deviation if he asks where the duration format lives.
- Staging helpers such as fx.py (json round-trip to kill YAML anchors) were in the session scratchpad and are now gone.
- Supersedes the status part of [[project-testdata-targets-fix-2026-09-23]].

Round 2, later on 2026-09-24 (answers A11a and A18-A21 are in the answers file):
- A11a: Gene accepted duration-display staying in ENGINE.
- A18: CONTENT had REQ-TDCONTENT-008 (no start copies) against REQ-TDCONTENT-010 (newer copy at upgrade start). Fixed
  so the newer copy is written only by an explicit Templates install or update. CONTENT was republished.
- A19: the reqtools lint accepts rendered or printed reads (THEN_RENDERED_WORDS). Live validation: 0 errors,
  108 warnings. reqtools.py is uncommitted.
- A20: the TEMPLATES side was staged as review/amendments/templates-testdata-samples-r1, adding REQ-TPL-016/017 and
  AC-TPL-016/017. IDs are only in ids-events-to-append.yaml. The pin cascade covers 49 artifacts, 30 of them READY and
  proposed REVIEW. Approving it means Gene re-approves those pin-only. It conflicts with library-fix-list-r1.
- A21: Gene pastes review/REVIEW-PROMPT-TESTDATA-R2-2026-09-24.md into a new session.
- Lesson: a READY artifact that applies a non-READY target is a validator ERROR. Any change to a widely pinned READY
  target therefore cascades through every pin; count the READY consumers before recommending "apply now".
