---
name: reference_stream_mockup_deliverables_lost_from_tmp
description: Stream mockup deliverables built under D:\tmp are lost on cleanup; the verdict file's gallery URL is the recovery path
metadata:
  type: reference
---

Stream mockup tasks were built into `D:\tmp\speedy-mockups\...` and only re-pointed into `.streams\mockups\` on 2026-09-29. Four INTEGRATED mockups had already lost their deliverable when the D:\tmp copies went away: G2.T11 (g2/welcome), G2.T12 (g2/templates), G3.T023 (G3a/signin-unlock-states), G3.T075 (g3b/capability-checks).

Recovery order: a surviving `D:\tmp` copy first, then the **gallery URL recorded in `.streams\verdicts\<task>.md`** (`Gallery: https://claude.ai/artifact/...`), and only redraw when neither exists (G2.T12 had neither).

A mockup grader can read GREEN while the repo path is empty: a grader still carrying an absolute `-Sheets`/`-Root` default finds the old D:\tmp copy. Treat a mockup grader PASS as meaningless until `Test-GraderPortability.ps1` says the grader is portable. See [[reference_stream_stale_read_blocks_and_bugs]] and [[reference_streams_board_untracked_like_loop]].
