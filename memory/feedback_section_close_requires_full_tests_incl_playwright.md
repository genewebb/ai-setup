---
name: feedback-section-close-requires-full-tests-incl-playwright
description: "Gene 2026-09-13 13:12 — a section (P1, P2, each 52.S<n>) passes only when the FULL tests pass, Playwright included; the row graders alone did not do that"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 94087952-8fd3-471b-81c9-eddfab85145d
  modified: 2026-09-13T17:17:29.612Z
---

Gene, 2026-09-13 13:12, mid-loop: "Confirm that for the sections to pass that the full tests must work including playwright".

It was NOT true when asked: code rows ran only the projects their grader named (Tests.Unit / Tests.Web / Tests.Architecture), never
Tests.Criteria, never a solution-wide `dotnet test`; Playwright entered only at 52.P2.5 and only `@smoke` (the `@regression` specs are
collected, not run); the section-close rows (52.P1.7, 52.P2.7) were doc rows with no test run at all.

**Why:** a section is the unit Gene signs off; a green row grader over three projects says nothing about Tests.Criteria or a browser.

**How to apply:**
- Every SECTION close row (52.P1.7, 52.P2.7, each 52.S<n>.7) is graded by `.loop/criteria/section-close-full-tests.ps1` (self-tested):
  build; `dotnet test Speedmerchants.sln` with every test csproj printing its own green summary; `e2e-ui-smoke.ps1`; the WHOLE Playwright
  suite (every tag) at retries 0, 0 failed, 0 flaky. P1.7 clause H7, P2.7 clause M7 (non-static).
- A red gate BLOCKS the close; the doc row never edits tests to pass it — the owning row fixes the defect.
- When authoring a future S-section close ticket, add the same clause. Poll that row's monitor with `-StaticOnly` (the gate is slow).
- Related: [[project-myfable-foreman]], [[feedback-grader-clause-shapes-that-fail]].
