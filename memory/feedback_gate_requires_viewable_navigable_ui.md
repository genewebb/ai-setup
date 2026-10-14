---
name: feedback-gate-requires-viewable-navigable-ui
description: Gene 2026-09-13 16:19 — a row/section that touches the UI does not close unless Gene can VIEW and NAVIGATE that UI on the live stack; confirming it is part of the gate
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 94087952-8fd3-471b-81c9-eddfab85145d
  modified: 2026-09-13T20:23:40.074Z
---

Gene, 2026-09-13 16:19, mid-loop, after the composed host had silently served HTTP 500 on every page since 09-12 (48.SEC4 DI cycle,
fixed by 52.P1.6a) while every row grader stayed green: "I must be able to view and navigate the UI for the items we work on to close
I think that is self evident but confirming that is part of the gate".

**Why:** unit/bUnit suites and static graders passed for ~30 hours over a web host that could not serve a single page; nobody GETted a
page. Gene signs off on what he can see, not on test counts.

**How to apply:**
- Every row that writes under `src/Web` carries the crosscheck `.loop/criteria/web-host-answers.ps1` (rebuilds `web`, GET 200 + marker);
  a red crosscheck blocks the close.
- Every SECTION close gate (`section-close-full-tests.ps1`) ends by leaving the stack UP for Gene: web rebuilt from the tree, every
  registered route answers 200 with its marker and the nav links to it, and `fleet` restarted (the smoke run stops it).
- At a section close / human gate, hand Gene the URL (http://localhost:5310/monitor) and the routes to click — the gate is his view, not
  only the scripts.
- Related: [[feedback-section-close-requires-full-tests-incl-playwright]], [[project-myfable-foreman]].
