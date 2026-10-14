---
name: vnext-schedule-format
description: "Gene's fixed format for the vNext Programme Schedule artifact (headers, task table columns, decision table) — do not change unless he asks"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: acc1f014-7b40-4f0e-b985-81edf62b4a29
  modified: 2026-09-07T19:32:15.918Z
---

**The vNext Programme Schedule artifact has ONE format, set by Gene 2026-09-06 19:49. Do not change it unless he asks.**

Top headers — only two:
1. Total Estimated Time Left to completion
2. Estimated vs Actual Total

Task table — seven columns, in this order:
1. Order (keep)
2. # (row key, keep)
3. Status — exactly one of `Queued` / `Started` / `Complete`
4. Task — one SHORT, SIMPLE-ENGLISH sentence (added by Gene 2026-09-06 19:59; source `.loop/tools/descriptions.json`,
   one entry per row key; add an entry whenever a row is added)
5. Estimated Time
6. Actual Time
7. Completed Date and Time

No technical task text, no dependency column, no ETA column, no opus/plan double estimate, no tensions
prose, no paste-ready answer channel. **Dependencies live in the implementation documentation** (the UoW
plan docs under `vNext\Design\` and `vNext\TaskList.md`, which keeps the full status text), never on the page.

Decision table — two columns:
1. Order
2. Plain-English description of the decision needed, the options, the recommendation, and pros and cons

Lifecycle: once Gene decides, the decision becomes a row in the Task Table and is REMOVED from the Decision Table.

**Why:** the previous page had eight tiles, an eight-column table with paragraph-long status cells, a tensions
section and an answer channel — too much to read at a glance; Gene wants a schedule, not a report.

**The schedule artifact is PER-ACCOUNT — there is one page per Claude account, not one page.** Gene switches Claude
accounts periodically so the loop has enough tokens to keep running (stated 2026-09-07 15:31), and artifacts do not
cross accounts: `Artifact action: list` only ever shows the CURRENT account's, and a URL owned by the other one is
unreachable, NOT dead. Registry of known schedule pages lives at `.loop/tools/artifact-urls.json`:

| Page | Status |
| --- | --- |
| `f5d668e7-169b-431f-a63c-2742bf637944` | account A; republished 2026-09-07 15:20 |
| `402006bb-a95d-4722-a7fa-56b31ac0e67a` | account B; last published 09-07 14:37; unreachable from A |

**Detect which account is live by listing, never by asking:** run `Artifact action: list` and see which of the
registry URLs comes back. Publish to THAT one (pass `url` + `favicon 🗓️`; a redeploy from a session that has not
read the page is refused until `action: read` runs first). If NEITHER is listed, the account is new: publish fresh,
then add its URL to the registry. Do not "correct" a handoff URL that merely fails to list — say which account it
belongs to instead. Both pages carry a `generated` stamp, which is how a stale one is spotted.

**How to apply:** `.loop/tools/Build-Schedule-Html.py` renders exactly this from `schedule.json` (+ `decisions.json`);
`Write-Schedule.ps1` derives Status and Completed from the row status text. Republish to the same artifact URL at
every dispatch/close ([[iteration-close-print-remaining-tasks]]). Never add a column or tile without asking.
