---
name: feedback-integrator-inbox-every-10-min
description: stream-integrate loop must wake at most every 600 s in EVERY state (even during long suite runs) so the inbox is read every 10 minutes
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4599ecab-4540-423c-841b-aeba6b8760d1
  modified: 2026-10-02T14:11:56.527Z
---

Gene, 2026-10-02: "Update your skill to check your inbox every 10 minutes automatically." stream-integrate SKILL.md v0.8
now says every ScheduleWakeup is 600 s or less, in every state, including while a step-B suite run or a detached drain
is going. Each tick runs Enter-Integrator, works the inbox, then polls the run log.

**Why:** with 25-30 min wakeups during G2's suite runs, plan items asking to stop a doomed run (G3.T203 registration
break) or apply a fix next sat unread up to 30 min.

**How to apply:** never pick a longer delay because a run is long; quiet ticks are `noop: true`. The skill was edited
via Publish-KitFile.ps1 -BaseHash (corpus D:\AIWork\work-ai\skills) plus a direct copy of that one file into the live
link tree, because a full Install-AIMachine apply would stop on other sessions' drift. Related:
[[reference_kit_corpus_vs_live_divergence]], [[feedback_g2_sessions_first]].
