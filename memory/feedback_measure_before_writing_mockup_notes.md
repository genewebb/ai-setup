---
name: feedback-measure-before-writing-mockup-notes
description: "Never write a measured figure or a layout claim into mockup notes.md without running the probe first; three blind-verifier FAILs on G3.T012 were all unmeasured prose, not broken markup."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: bd347cfa-43b1-4017-9334-736b559faa8e
  modified: 2026-09-29T14:22:53.277Z
---

When writing `notes.md` (or any design-review prose) for a mockup, measure every number and every
layout claim with a Playwright probe over ALL states at ALL widths BEFORE writing the sentence. Never
estimate, never carry a number over from a different element, never generalise one state to the rest.

On G3.T012 three consecutive blind `foreman-verifier` rounds returned FAIL. Every DEFECT was a prose
claim in `notes.md`, never broken markup:
- "about 434 px wide" — the control is 698/904/1049/1132 px depending on state. 434 was the
  `.table-responsive` width with the chrome's 390 button pressed inside a 1440 window: the wrong element.
- "about 80 px below the Run action" — it is 45 px at 1440 and 92 px at 390.
- "the control wraps below the action row" at 390 — backwards; the control is the container's FIRST
  child and the buttons wrap below IT.
- "Import / New workload / Refresh wrap to row two" — true in three library states, but in `no-profiles`
  the control is narrower (904 px) so only Refresh wraps.

**Why:** a grader checks that `notes.md` has its sections and keywords; it cannot check whether a number
is true. A blind verifier measures. The next builder sizes real code against those figures, so a wrong
one is a defect that ships — G3.T013 would have budgeted a shortened label against 434 px when the real
control is up to 1132 px.

**How to apply:** write the probe first, dump every figure for every state at every width, then write
prose from the dump. If a claim cannot be produced from probe output, do not write it. Prefer per-state
figures over one averaged or "about" number. See [[feedback-verify-no-guessing]] and
[[feedback-ui-mockups-before-implementing]].
