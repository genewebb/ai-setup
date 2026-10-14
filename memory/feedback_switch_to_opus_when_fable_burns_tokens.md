---
name: feedback-switch-to-opus-when-fable-burns-tokens
description: "Gene 2026-09-12 22:09 — \"We need to switch to opus Fable 5.1 is burning too many tokens\"; the foreman session should run on opus, not Fable, unless Gene says otherwise"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 94087952-8fd3-471b-81c9-eddfab85145d
  modified: 2026-09-13T02:10:22.316Z
---

Gene, 2026-09-12 22:09, mid-loop: "We need to switch to opus Fable 5.1 is burning too many tokens."

**Why:** Fable authored SEVEN tickets + graders + self-tests ahead of the executor (P1.4–P1.7, P2.3–P2.7) in one session (~14M tokens of context churn). The loop design ([[project-myfable-foreman]], [[feedback-loop-models-fable-plans-opus-executes]]) said Fable plans + verifies; Gene has now capped that.

**How to apply:**
- Run the `/myfable` session on **opus** (`/model opus` in the SAME session — a restart loses in-flight background workers, as at 20:30 on 9/12). Verifier dispatches (`foreman-verifier`) also on opus unless Gene re-enables Fable.
- Author ONE ticket ahead, not seven: the next row's ticket + grader + self-test while the current worker runs, nothing further.
- Do not pre-read whole subsystems for rows two phases away; gather at dispatch time.
- If a row genuinely needs Fable-grade judgement (a security row, a gate review), ask Gene first.


**2026-09-13 19:56 — opus everywhere.** The lead, the workers and the verifier all run on opus (`.looporeman.json`): the Fable improvements are too expensive for practical use. A high-value, low-cost spot may name Fable per class via `verifierModelByClass` (candidate: the blind verifier on security rows only); default stays opus.

**2026-09-13 20:27 — the ONE Fable target: the blind verifier on code and security rows** (`verifierModelByClass: { code: fable, security: fable }`). Why: read-only, bounded (~115k tokens/row), and the step that catches what the worker's own build, tests and grader miss. Lead, workers and the mockup batch verifier stay opus.

**2026-09-13 20:28 — reverted to opus.** Every real verifier catch on record (4 bugs + the secret leak) was by an opus verifier; Fable on the verifier costs ~1.6–2.2x per code row for an unmeasured gain. Measure first (a Fable verifier beside the opus one on three rows) before switching.
