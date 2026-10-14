---
name: feedback-stream-mechanical-work-outside-claude
description: "Gene (2026-10-06) wants mechanical stream-kit steps (polling for work, claim, inbox/lessons read, worktree, RED pre-run) done in PowerShell outside Claude, like the integrator suites; a Claude unit launches only when a row is already claimed for it"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 6b477d9e-cbab-4a39-9f95-673fbd7d6176
  modified: 2026-10-06T16:17:32.044Z
---

Gene, 2026-10-06, on the author/builder cost review: "Could we not move this out of claude like the testing so maybe some file watcher or something that wakes up only when work is done and tells the author or builder to get it."

**Why:** Every Claude tool call re-reads the whole prefix (~83k tokens per runner unit). Measured on 10/5: 64 author units launched into NONE ($36), and 30-64% of an author unit's tool calls were board plumbing (inbox, lessons, Claim-Task, Update-Task, tasks.json reads), 15-17% of a builder's. The integrator suites already run detached in PowerShell; the same should hold for anything that needs no judgment.

**How to apply:** In stream-kit design work, default to: the runner (PowerShell) watches the board and inbox (event-driven, zero tokens), claims the row itself with the SAME selector the unit would use, stages the packet (task JSON, ticket, grader, lessons, inbox item, worktree, author-grader RED result), and launches Claude with "your task is <id>, packet at <path>". A unit that would end idle, or a RED that is not red, never launches a Claude session. Related: [[reference-stream-cost-transcript-facts]], [[project-stream-tabs-profile-2026-10-04]].
