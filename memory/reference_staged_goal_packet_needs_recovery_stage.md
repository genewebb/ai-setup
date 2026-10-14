---
name: reference-staged-goal-packet-needs-recovery-stage
description: Staged implementation packets fail two ways - shortfall with no carry-forward rule, and a definition of done whose required actor the packet never supplies
metadata: 
  node_type: memory
  type: reference
  originSessionId: 6af4940f-e1eb-48e9-bfca-6e03e31a027b
  modified: 2026-09-21T02:13:01.488Z
---

Two defects to check for in any multi-stage `/goal` packet. Both confirmed in `shared-secrets-goals-r2`
(Speedy) and written up in `99 Documentation/speedy/requirements/reviews/Goals1-6/ReviewReport.md`.

**1. Shortfall has no carry-forward.** Stage entry gated only on "verify the required mechanisms exist"
lets the sequence advance past a stage that left its own assigned requirements unbuilt, because the
next stage only needs the interfaces it calls. Stage *exit* is judged against prose milestones, not
against the stage's own assignment table. Result: 16 of 182 requirements never built, 77 more with a
named unbuilt half, checkpoints 1/3/4/5/6 all `BLOCKED / INCOMPLETE`. The final stage's header said it
"owns 0 new accountable requirement implementations" while its assignment section said "fix any
uncovered or incorrectly integrated obligation here" — a contradiction, not a total hole, but enough
that the implementing session created an unreviewed `Goal-07-Completion.md` in its workspace, outside
`Packet-Integrity.json` and outside the vault. **Fix:** tie the exit rule to the assignment table, and
make a blocked stage list its unbuilt owned IDs for the next stage's first work item.

**2. The definition of done needs an actor the packet never supplies.** 53 of 55 verification plans
required `Verifier independent of the implementation author`; the screen gate required owner-or-delegate
inspection of a running screen. The packet stated both correctly and repeatedly, then named nobody and
gave no route. Consequence: 0 of 174 acceptance criteria and 0 of 55 plans could close against a build
with 4,891 passing tests and 0 failures — a structurally guaranteed BLOCKED finish carrying no
information about engineering quality. **Check before issuing any packet:** for every required evidence
role, who performs it, and at which stage.

Also: a cross-cutting per-surface obligation (a screen gate) assigned `owner_goal: 1` when no screen
exists until stage 3 is never revisited, because "exactly one accountable stage" fits a shared mechanism,
not an obligation each new screen re-incurs.

Related: [[project_speedy_requirements_system.md]], [[feedback_verify_no_guessing]].
