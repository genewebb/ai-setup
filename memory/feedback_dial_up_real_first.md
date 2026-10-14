---
name: feedback-dial-up-real-first
description: Gene 2026-09-13 16:56 - get dial up/down (load tests) REALLY working from the UI before gate 61, even if other rows slip; secrets picker stays in sequence
metadata:
  type: project
---

"Lets adjust these NOW before we have too much invested. I want to get something real working even if it means delaying some of the other things." 16:57: "Work these changes in before the item 61 gate. We dont have to do the secrets picker until after we do reference data then the secrets ... we just need to plan for it and change what must be changed now (like URL)".

Agreed 16:56: run profile = declared/captured/observed; ramp from UI + coordinator actually running + Total/Per-fleet choice on the form; split "how much load" from "what each user does" so scenarios (future CrewChief-style workloads) reuse dial/ramp/run profile. Also asked: route away from /workloads (collides with /library/workloads), claim size needs description/hover, stop condition (a) requests (b) duration (c) whichever first.

**How to apply:** load-test section rows sit BEFORE gate 61 on the board; API-key Secret picker is a planned residual on 52.S2.4. Plan: C:\devops\repos\speedmerchants\.loop\PLAN-SECTION-S0-LoadTests.md. Related: [[feedback-value-picker-always]]
