---
name: feedback-integrator-cycle-status-report
description: Every stream-integrate cycle must end with a visible status whose first lines are the inbox open count (re-read at report time) and Working/Idle
metadata:
  node_type: memory
  type: feedback
  originSessionId: ad0cfc30-35f7-427e-8787-8e53baa8603a
  modified: 2026-10-10T14:53:06.035Z
---

Every stream-integrate cycle ends with a visible status report, including noop ticks. Line 1: `Inbox: <N> open` (+ ids), from a fresh `Get-InboxItems.ps1 -Skill stream-integrate -Open` run right before the report. Line 2: `Working: <drains/runs/retests in flight>` or `Idle: <why>`. Then the changes this cycle and the next wake time in local EDT.

**Why:** 2026-10-10 the owner asked for it so they can see each tick that the inbox was checked and the loop is alive. The same day two inbox items arrived mid-cycle after the first read.

**How to apply:** written into stream-integrate SKILL.md v0.15 (published via Publish-KitFile, corpus = live). Related: [[feedback_integrator_inbox_every_10_min]], [[feedback_report_times_in_local_edt]].
