---
name: reference_live_session_does_not_reread_skill_md
description: A rule added to a SKILL.md mid-run cannot reach a session that is already running; it only helps the next one, so a stalled live session still needs an inbox item or the owner.
metadata:
  type: reference
---

A skill's text is loaded when a session starts. Editing `SKILL.md` while sessions are running changes nothing for them — they keep following the text they loaded. Shipping a kit fix is therefore **not** a fix for the session that exposed the defect.

Measured on 2026-09-30: a bounded-verifier rule went into `stream-build/SKILL.md` step 7 at 09:47Z after `G1.T16`'s second verifier stalled five hours (see [[reference_verifier_subagent_stalls_while_builder_beats]]). Its builder `build-202609302040-7b3e` had relaunched a third verifier at 09:39Z and then went silent another 105 minutes — the new 30-minute bound never reached it, because the session had loaded the old step 7 hours earlier.

Consequences worth acting on:
- When a kit or skill fix is aimed at a live failure, the live session needs a **separate** lever: an inbox item its role reads at the next claim, or the owner restarting it. Only the owner can see or restart a session.
- Judge a shipped rule by the next session that starts, never by the row that prompted it.
- The same holds for hooks and permissions text: a running session keeps its loaded copy.
