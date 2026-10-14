---
name: project_loop_paused_restart_here_2026-09-17
description: MyLoop paused 2026-09-17 12:08 mid restart-gate; 2 of 4 hand-fixes landed; start-up card at .loop\RESTART-HERE.md; requirements system started separately on Q:
metadata:
  type: project
---

**MyLoop is PAUSED (since 2026-09-17 12:08) and must NOT be restarted until `48.R17b` and `48.WAVE1` are
implemented** — Gene: *"do not restart until the fix(s) are done so that we can start out right."* Both lead PIDs are
dead. Fixes are made BY HAND while paused (the loop cannot repair its own engine while running on it); each row's grader
is the proof — RED before, GREEN after — plus self-test, build, the 30-case suite and the crosscheck, **run one at a time**.

**Landed:** `48.R14` complete; `48.R17a` landed + accepted (hard-7 C6 red is a verified mutually-unsatisfiable probe,
filed as `48.R7b`, never edit hard-7 for it). **Owed:** `48.R17b`, `48.WAVE1`, then one careful board-filing pass, then
resume and watch the first wave against five pre-committed criteria. `48.R12` = first row after restart.

**Start-up card:** `C:\devops\repos\speedmerchants\.loop\RESTART-HERE.md` (state, gate, criteria, housekeeping,
census digest, corrections). Ledger: `.loop\FIX-PROGRAMME.md`.

**Why:** the restart gate was chosen on measured incidents (52.S0.4zc killed while alive; a fresh session repairs
nothing on wake; 19 of 42 overrides were misattribution). Measured today and worth not forgetting: recorded lead-read
median is **7 min** (not 18), authoring **28 min** (not 90); the ticket form cannot hold a quantity (59% of symbol
citations drift); 93% of open board rows have no checkable requirement.

**How to apply:** on `/myloop` or "resume", read RESTART-HERE.md first; do not dispatch against board prose for anything
that now has a requirements artifact under `Q:\Work\Work\99 Documentation\speedy\requirements\`.
Related: [[project_myloop_hardening_2026-09-16]], [[feedback_resume_is_the_authority_grant]],
[[project_speedy_requirements_system]].
