---
name: feedback-max-response-4000-chars
description: Hard cap of 4000 characters on every user-facing response
metadata:
  type: feedback
---

Every user-facing response must be **4000 characters or fewer**. Stated as a hard rule on 2026-08-18.

**Why:** long responses are unreadable in the terminal and bury the decision-relevant part. Verbosity is
a cost, not thoroughness.

**How to apply:** put the conclusion first; cut narration of work already visible in tool calls. For a
long-running loop, report gate results as a compact table plus only findings that change a decision —
move the full detail into the on-disk log (`.loop/PROGRESS.md`) instead of the reply. Insight blocks stay,
but one per response, not three. Related: [[feedback_scope_discipline]].
