---
name: feedback-loop-two-strike-rule
description: "/myloop two-strike rule — after 2 verifier FAILs on one row, never re-ticket it a third time; close on what passes and carry findings to new rows, or split the row"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 22d5dbd3-c155-4749-bee7-fcbb38ec1329
  modified: 2026-09-14T11:57:49.380Z
---

After a row has had **two verifier FAILs**, the lead does not write a third attempt on that row. Either close on the parts that pass and file each remaining finding as its own row (named as the Residual), or split the row into smaller rows and dispatch those. A PASS_WITH_NOTES whose notes are real but separable closes, with the notes carried to rows. It is not rejected to fold them into the same row.

**Why:** 2026-09-14 00:36–07:56. 52.S0.3b ran six attempts in about 7.5 hours while only one row closed all night. Causes, most important first:
1. The lead's own ticket design was wrong: a coordinator top-up that can never keep up with a fast target. That cost two attempts.
2. The row grew in place from "Duration-only launch" into a rewrite of concurrent claiming (supply created at claim, lock order, deadlocks, clock skew, census, withdrawal contract).
3. The lead rejected a PASS_WITH_NOTES and bundled extra fixes into the next attempt, which introduced deadlocks.

Each verifier finding was real, but re-ticketing the same row stalled the queue behind it. Gene saw "almost no work completed" and approved this rule ("Ok").

**How to apply:** count the verifier FAIL verdicts in the row record before writing any attempt after the second one. On a third, close or split instead: log the decision in `rows\_decisions.md`, and add the new rows to Write-TaskList with a regen and publish in the same turn. Design mistakes the lead authored count against the row too: if the ticket's own design was wrong, split out the redesign as its own row rather than rewriting the ticket. Related: [[project_myfable_foreman]], [[feedback_never_stop_to_report_between_rows]], [[feedback_loop_practices_that_caught_defects]].
