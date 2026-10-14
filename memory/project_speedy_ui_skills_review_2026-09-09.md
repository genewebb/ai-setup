---
name: project_speedy_ui_skills_review_2026-09-09
description: "2026-09-09 review of the four speedy-ui-* campaign skills + the 52.01 grader — the grader failed correct code twice (verbatim C:\\Temp, suite by file name) and passed a comment as a tab; fixed and proven 1/1/0 by C:\\temp\\u9-13-selftest.ps1; donor drifted 4 commits past the plan's sha; 52.01 plan omits TokenShapes.cs"
metadata: 
  node_type: memory
  type: project
  originSessionId: 2b5c14e0-c797-4d53-b1fe-b927e7b6c2b2
  modified: 2026-09-09T22:50:35.151Z
---

Review of `speedy-ui-screen-port` / `-bunit` / `-composed-graph` / `-playwright-axe` and
`C:\temp\u9-13-value-editor.ps1` on 2026-09-09, before row 52.01 was dispatched. Full report:
`Q:\Work\Work\99 Documentation\claude\webpages\2026-09-09-speedy-ui-skills-review.md` (copy at
`C:\temp\REVIEW-REPORT-speedy-ui-skills.md`).

**What was found (all verified against source):**
- The grader, never self-tested, FAILED a correct stub on G2 (`C:\\\\Temp` matched only the C#-escaped
  spelling) and G4 (suite found by `-match 'Value'` in its FILE NAME), and PASSED a wrong stub on G6 (raw
  whole-tree word census; a doc comment "Reference Data" counted). `Strip-Code` stripped `//` before
  blanking strings. Fixed (single-pass lexer, three views, construct-anchored clauses); self-test proves
  baseline 1 / wrong 1 / correct 0. Original kept as `u9-13-value-editor.ORIGINAL.ps1`.
- Donor `speed-merchants` moved `7aee7cc..726dec92` (4 commits): `FolderMoveDialog.razor` +
  `MoveToFolderBar.razor` deleted, `SeparateFoldersNotice.razor` new — plan Row 2 (52.02) lists the deleted
  files as input. `SegmentedToggle` = 126 at both shas (plan's 140 was never true of it).
- 52.01 plan defect: donor `TokenComposition.cs` needs six `TokenShapes` members vNext lacks
  (`SplitFilters`, `FilterSeparator`, `BuildConfigRef`, `BuildRef`, `TryParseWholeConfigRef`,
  `TryParseWholeRef`); vNext `TokenShapes` is in Infrastructure, the plan lands the engine in
  Domain/Application. Raise at dispatch.
- "Eighteen frozen strings" is seventeen (derived by grep over the specs); title + 9 notice sentences
  also asserted. The `.d` skill described C1 as open — 51.A closed it and the smoke grader FAILS the old
  title since 09-05 22:42. `.c` skill resolved a nonexistent `IWorkloadStore`.
- Registration: `criteria-uow9a.json` is the registry the sweep reads; `CRITERIA.json` is the 09-05
  preflight snapshot. `Invoke-CriteriaSweep.ps1 -Filter 'u9-*'` at every close; `-CheckDue` exit 10 = daily
  sweep owed.

**Rules added:** self-test 1/1/0 before dispatch; verify every operand against the declaration; derive
frozen sets by grep; drift = `git diff --stat <plan sha>..HEAD` + dependency census; six canonical bUnit
tokens (`RendersItsMarker`, `EmptyState`, `PrimaryActionSucceeds`, `RefusesByName`, `StoreUnreachable`,
`AnnouncesStatus`); `@media` count = 2; shared files append-only; `ACTUAL 52.xx:` line at close; `.d` legs
only inside their own row.

**Still open for Gene / the loop session:** amend plan Row 1 (TokenShapes) and Row 2 (deleted donor
files); author `u9-bunit-floor.ps1` with the tokens; GOAL "eighteen"; template header comment; D1
(five or six tabs); `speedy-` vs `speedmerchants-` prefix (taxonomy now maps `speedy-ui-*` → Blazor / UI).

Related: [[feedback_grader_clause_shapes_that_fail]], [[reference_loop_criteria_regression_gap]],
[[project_vnext_ui_testing_playwright_reuse]], [[reference_skill_cost_is_size_times_invocations]].
