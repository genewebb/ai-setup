---
name: feedback-run-suites-once-at-group-close
description: "MyLoop/Speedy build - make all a group's changes first, run the full test suites ONCE at the group close-out; row graders run targeted tests only (Gene 2026-09-27)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 1c475457-1e54-4237-a0cd-5cdd61ea1bc1
  modified: 2026-09-27T19:54:02.930Z
---

Gene, 2026-09-27: "make all the changes then run the test suit once not after everyone", then confirmed: "I am fine with coding everything, then running unit tests and integration test then fixing any issues then retesting". Cycle per group: code rows → suites once → fix rows → suites once more → close.

Row graders run only the filtered test classes the row touches, plus a filtered counterfactual and static pins that take seconds. They never include a whole-suite clause and never re-run closed rows' graders. Collect-Row for group rows uses `-SkipRegression`. The whole suites (Tests.Unit, Tests.Web, Tests.Browser, Architecture, Playwright) and every closed row's grader run ONCE, in the group's close-out row (the 1.RD-19 pattern). A break found there becomes a fix row for the row that caused it.

**Why:** each code row paid about an hour of suite time. Tests.Unit is ~15 min, and it ran ×4 per row: at accept, in the worker, at collect and in the verifier. Parallel suite runs in one tree also lock bin folders, which cost RD-23 ~30 min. The estimates ballooned for small fixes.

**How to apply:** strip suite clauses from every new grader; give every group a close-out row; estimate rows without suite time. Related: [[feedback-one-row-per-write-set]], [[feedback-section-close-requires-full-tests-incl-playwright]] (still true: the SECTION close runs full tests incl. Playwright).
