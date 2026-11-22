---
name: feedback_isolation_in_progress_tab_2026-11-18
description: "Gene watches the isolation plan page's In Progress tab as a live console; post progress, next steps and problems there via progress.py as I work"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 48e8ba62-42b2-44d2-b5a8-39d62dc558bf
  modified: 2026-11-18T09:04:51.156Z
---

Gene 2026-11-18: "Add a new tab to the status page called In Progress, treat it like a console page that I can just watch that gives me updates on your progress, next steps, problems, etc."

Built: tab `#progress` (first + default tab) on https://smvmtr1.corp.profisee.com/speedy/IsolationTestPlan.html, reads `IsolationProgress.json` every 10 s. Feed writer: `python D:\devops\repos\speed-merchants\docs\isolation\plan-page\progress.py` with `log <info|done|next|problem|decision|test|host|build> "<text>"`, `now "<text>"`, `next "<s1>" "<s2>"...`, `problem "<text>"`, `solved <n>`, `show`. Writes the master beside the script and copies to `C:\inetpub\wwwroot\speedy` (no page republish needed).

**Why:** Gene wants to watch unattended work without asking.
**How to apply:** on every meaningful step (start/finish of a build, test start/result, host change, decision, blocker) post a line; keep `now` and `next` current; add/clear problems. Plain English, no jargon-only lines. Related: [[project_isolation_test_plan_page_2026-11-17]], [[project_isolation_smvmtr1_decisions_2026-11-18]].
