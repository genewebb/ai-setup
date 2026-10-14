---
name: feedback-auto-approve-recommendations-speedy-build
description: "2026-09-26 Gene auto-approves Claude's recommended option on every Speedy build-campaign question; decide, log, keep going; he adjusts at manual testing"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 63da107a-d636-46d6-b6aa-9e8658ff93aa
  modified: 2026-09-27T23:10:24.173Z
---

On 2026-09-26, during the Speedy build campaign (group 1 Reference Data onward), Gene said: "Make a recommendation on any questions, I now auto approve your recommendation I will make any changes at manual testing".

**Why:** the rounds of AskUserQuestion were slowing the build. Gene will correct anything when he tests it by hand.

**How to apply:**
- Don't ask. Take the recommended option and record it as a decision row in the group's task list (e.g. `speedy\build\01-RefData-Tasks.md`, RDQ-n), marked "auto-approved (Gene standing rule 2026-09-26)".
- Owner visual inspection (NFR-UI-DONE gate 3) moves to Gene's manual testing.
- A requirements amendment publish: publish only after a clean-session review with no blocking or major findings, cite this rule, and tell Gene.
- This supersedes [[feedback_questions_via_askuserquestion]] for this campaign. Destructive actions (worktree removal, deleting data) still need explicit confirmation.

**Stream kit builders too (2026-09-27 18:57):** "update /stream build to auto accept recommendations, I will adjust anything implemented during manual testing to keep the builder continuously working". Built into stream-build v0.2 (Auto-accept section): open choices are decided and noted on the task; a needed file outside the write set is added with `Update-Task.ps1 -Role build -AddWriteSet` (exit 7 WRITESET-OVERLAP only when another open task owns it); advisory verifier findings never stop `built`. Still bounced: wrong ticket/grader → planned, second verifier FAIL, destructive actions.

**Requirements tracker too (2026-09-26 18:33, recorded as Q0-78 in Speedy-Requirements-Tracker.md):** "I will accept your recommendations for all questions and adjust at implementation time". Covers even questions with no clear recommendation (Q0-72 had excluded those). Decide, record basis as "auto-approved under Q0-78", keep going.
