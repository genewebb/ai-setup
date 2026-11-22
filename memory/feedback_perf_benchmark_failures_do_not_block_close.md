---
name: feedback-perf-benchmark-failures-do-not-block-close
description: "Speedy stream: a group whose ONLY failures are speed benchmarks (or unmeasured perf legs) is approved; perf work goes to one row at the end of the board"
metadata:
  node_type: memory
  type: feedback
  originSessionId: ff5bec9e-bb2c-4d16-839d-3fdf9ebacd09
  modified: 2026-10-11T00:11:08.842Z
---

When a Speedy group's only remaining failures are speed/performance benchmarks (e.g. canvas-perf.spec.ts drag p95, first render), approve the group close: exempt those tests (`Test-GroupClose.ps1 -Exempt <test> -Reason <ruling>`) and have stream-plan add ONE performance line item at the end of the board (post-v1). Owner also relaxed UI limits: no 500 ms UI requirement, first render < 1 s; drag-feedback p95 100 ms.

**Why:** Owner, 2026-10-10 evening: "we can work on performance after we get a v1 done"; "If the only failure is that it does not meet the speed benchmark approve it and put a line item at the end to improve performance." Perf measured under 10 live runners is noisy (36.9 ms loaded vs 2.8 ms solo).

**How to apply:** Integrator: exempt benchmark-only failures citing the ruling, never burn fix strikes on them; send stream-plan an item to list them on the end-of-board perf row. Real functional failures still block. Related: [[project-stream-capacity-two-authors-two-builders]].
