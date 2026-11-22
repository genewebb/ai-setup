---
name: reference-stream-build-no-grader-is-legit
description: "stream-build - a ticketed row with artifacts.grader null is VALID (NO-GRADER); skip step 4a, the builder check carries the clauses; never bounce it to planned"
metadata:
  node_type: memory
  type: reference
  originSessionId: 1913cdde-afda-4717-9d00-4dc3c3f40fcf
  modified: 2026-10-04T05:37:57.719Z
---

A `ticketed` row whose `artifacts.grader` is null and has no `.streams\graders\<t>.ps1` is a legitimate "no grader" row. The author writes "No grader: every clause is an assertion" in the ticket. `Invoke-Grader -Only grader` answers `NO-GRADER` (exit 4): skip step 4a, and let the builder's `.streams\checks\<t>.ps1` carry the clauses (RED = check with the tests absent, plus a mutant).

**Why:** on 2026-10-04 builder session build-202610011146-5657 bounced G3.T060 to `planned` for "grader missing". It was a builder error, and the builder had to file an inbox item to stream-author (IN-20261004051640-3900) to restore it. The very next row, G3.T065, was the same shape and built fine.

**How to apply:** before sending any row back for a missing grader, grep the ticket for "No grader" and re-read stream-build SKILL.md steps 4 and 5 (`NO-GRADER`). Build it with a check instead. Related: [[index-stream-kit]].
