---
name: vnext-planning-sweep-2026-09-05
description: "State of the vNext programme after the 2026-09-05 planning sweep — every unit re-sized from its donor at HEAD, all open decisions closed on plan defaults, mockup pick recorded, Elsa verdict = push ProFlow to the end; the ordered schedule table + artifact is the next deliverable (paused 20:23 for the usage limit, resume 22:00)."
metadata: 
  node_type: memory
  type: project
  originSessionId: 75aa89d7-1a8e-429e-bbf8-a3e0c469e0ac
  modified: 2026-09-06T00:25:19.031Z
---

On 2026-09-05 (17:05–20:27) the orchestrator-worker loop ran a PLANNING SWEEP instead of implementation rows (Gene: "do planning and sizes on the other task while you wait on me to view mockups", then 18:30 "finish sizing everything, adjust any order, answer any open items so we can get a complete schedule", 18:41 "do the Elsa spike so we know the final cost and order then produce a new table").

**Results (plan minutes, Executor opus, one vault document per unit under `speed-merchants\vNext\Design\`):** UoW-7 1,300 (405 carried) · UoW-7b 850 (225) · UoW-9 3,130 (960) · UoW-10 7,525 incl. 1,830 of P3.9 backend waves (1,560) · UoW-11 2,455 + 1,200 prerequisites (540) · UoW-12 §8 write workloads 2,750 (495) · UoW-14 = the renamed `TestData.Mutation` parity port 3,490 (unsized) · UoW-13 Generation parity 2,140 (360) · W1 campaign 630 (120 spike) · installer 710 (180) · P3 pending (row 58.0). Every provisional came out 3.2–5.9× under. ALL-IN ≈ 400h before P3.

**Decisions:** mockup pick recorded 18:18 (B/A/B/B/B/B — all recommended; the artifact's localStorage rail could not deliver it, see [[review-pages-need-readable-pick-channel]]). Elsa spike verdict: push ProFlow/Elsa to the END; campaign coordinator-native (`ParentRunId` + `campaign` verb + parent leg; K6 chaos proof blocks CP-4); Elsa 3.5.1 has no net10.0 asset (restore inferred, unverified). P3.11a/b absorbed into UoW-13 row D / UoW-14 row 56.19. `TestData.Shared` does not exist. The agent is a bare console — the installer's first row is `UseWindowsService` + a `serve` verb. Every plan's §6 carries a "Default if not answered" column and the loop proceeds on it (Gene 18:30); reversals go in the pick sheet `claude\webpages\2026-09-05-ui-polish-review.md`.

**Open tensions for Gene:** CP-4 placement — v3's stated path puts UoW-12/13/14 AFTER the gate while its "all four apps" wording implies before; UoW-13 pricing (7.25 lines/min); Elsa net10 restore.

**Mechanics that worked:** `plan-doc-census.ps1` generic grader + thin wrappers with STRICT falsifications; `Close-Plan.py <spec.json>` closes a planning row into PROGRESS/GOAL/v3/TaskList/pick sheet/criteria in one call; `Write-Schedule.ps1` + `schedule-order.txt` re-order the TaskList and export `schedule.json`; `Build-Schedule-Html.py` renders the artifact. Two document-only Executors may run concurrently (disjoint vault files, no repo writes) — recorded as an exception to the one-Executor rule.

**Where the state lives:** `.loop\PROGRESS.md` (every dispatch/close), `.loop\GOAL.md` (Done-when tables per unit), `vNext\TaskList.md` (Gene's one document), `vNextImplementation_v3.md` §0 stamps, the handoff `~\.remember\c--devops-myworkspace\remember.md`.

**Update 2026-09-05 22:36 (resume):** schedule page published as the live table — https://claude.ai/code/artifact/f5d668e7-169b-431f-a63c-2742bf637944 (archive `claude\webpages\2026-09-05-vnext-schedule.{html,md}`; data `.loop\tools\schedule.json`, builder `.loop\tools\Build-Schedule-Html.py`). ALL-IN 24,711 min = 411h 51m, 131 sized rows, finish ≈ Wed 09-23. Loop resumed at row 51.A (UI polish part A; grader `ui-polish-implementation.ps1` = criterion 56). Gene's 22:06 rule: refresh that artifact at every dispatch/close instead of printing a table ([[feedback_iteration_close_print_remaining_tasks]]).
