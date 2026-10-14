---
name: feedback_resume_is_the_authority_grant
description: "Telling MyLoop to resume IS Gene's authority grant to reclaim lead, re-derive stale states and recover stranded rows without asking"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 9ad0f53c-a8d0-4663-b061-8c8173fdca68
  modified: 2026-09-17T17:10:56.941Z
---

**Saying "resume" (e.g. `/myloop`) is itself the authority to restart and self-heal.** On resume the loop may
reclaim lead ownership, fix stale ticket/Started/Ticketing states and recover stranded rows on its own — it does
not stop to ask a human first. Gene, 2026-09-17: *"When we resume I want it to fix problems with ownership,
tickets, etc — by telling it to resume I am giving it the authority to restart and fix any problems like this."*

**Why:** the old rule made every orphan recovery wait on a human sentence, so a dead lead left the board frozen
with legal tickets and finished work stranded. The resume instruction already carries the human's intent.

**How to apply:** this SUPERSEDES the narrower rule in [[reference_myloop_orphan_recovery_and_script_gaps]] that
`Claim-Lead.ps1 -Take` may only run once a human says the terminal is gone — resume is that statement. Still
verify the recorded PIDs are actually dead before taking the lock, still never let the heartbeat auto-dispatch
while `_decisions.md` says dispatch is by hand, and still report what was healed. Built as scope in 48.R17
alongside the worker-liveness fix; see [[project_myloop_hardening_2026-09-16]].
