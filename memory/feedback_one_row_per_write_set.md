---
name: feedback-one-row-per-write-set
description: "MyLoop - fixes sharing a write set go in ONE row; never split one screen's audit fixes into per-finding rows (Gene pushed back on ballooning estimates 2026-09-27)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 1c475457-1e54-4237-a0cd-5cdd61ea1bc1
  modified: 2026-09-27T17:42:34.199Z
---

Fixes that touch the same files go in one loop row. A new row only for a separate write set or a separate gate. Re-audit folds into the fix row's grader (re-shoot + re-check), not its own row.

**Why:** each row pays fixed overhead (ticket + grader + self-test + worker + collect + verifier; ticket median ~33 min). Splitting the RD-18 audit's 7 fixes into 9 rows put 60 min on a 99 px table overflow; Gene asked why estimates keep ballooning. Same-file rows can't run in parallel anyway.

**How to apply:** when an audit/verifier/worker surfaces findings, group by write set before filing; estimate the change plus ONE overhead. Same-root-cause follow-ups (e.g. RD-33+RD-34) merge. Related: [[feedback-auto-approve-recommendations-speedy-build]], [[project-speedy-build-campaign-2026-09-26]].
