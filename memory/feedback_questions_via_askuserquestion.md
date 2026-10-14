---
name: feedback-questions-via-askuserquestion
description: "EVERY decision Gene owns = AskUserQuestion picker question with a recommendation (rounds of 4), never a caveat list or markdown list"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 90ab570c-a1db-4128-90de-04447a9d640e
  modified: 2026-09-24T12:54:00.633Z
---

When Gene asks for "questions with options/choices", present them through the AskUserQuestion tool (pickable in the prompt), in rounds of up to 4, recommended option first with "(Recommended)". Never as a markdown list in chat.

**Why:** Gene 2026-09-24: "When I say present me with questions I mean give me a list of questions with choices that I pick in the prompt not as a list" — after a text list of 12 fix questions for the TESTDATA review.

**Standing rule (Gene 2026-09-24 12:49):** "For now and going forward anything you need a decision to me just present it as a question with a recommendation." Applies unprompted: deviations, open requirement questions and choices buried in a report become picker questions, never "things to review" bullets.

**How to apply:** Any decision batch → AskUserQuestion rounds; keep option descriptions short with the trade-off; low-stakes defaults can be one final multi-select round. Related: [[feedback-requirements-system-review-gate-per-task]]
