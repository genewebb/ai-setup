---
name: feedback_do_it_right_not_a_patch
description: "When fixing a defect, build the correct structure rather than the smallest change that makes the symptom go away"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 34c06f04-ada7-44f8-a3e4-66dc2a3c5365
  modified: 2026-09-03T14:59:27.539Z
---

Gene, 2026-09-03: *"Lets do this right always make a choice to do it the right way rather than patch
it or make something that is clugy."*

Said while a defect fix was in flight. The fix as planned would have worked and passed its gate.

**Why:** the defect that prompted it was a secret-tier separation rule that never fired, because
three different call sites each decided for themselves where the local master password lived. The
planned fix bolted a fallback onto the one site that was reading the wrong source — which makes the
three agree *today, by coincidence*, and leaves the same drift available to whoever adds a fourth
consumer. The gate would have gone green over a hole that had only moved.

A patch that passes its criterion is worse than an obvious bug, because the criterion then certifies
it.

**How to apply:** when a defect turns out to be N places disagreeing about one question, the fix is
one seam that answers the question, consumed by all N — not making the odd one out match the others.
Ask *what is the right structure here* before *what is the smallest change that turns this test
green*. Prefer the correct shape even when it costs another file, another port, another iteration;
say so and do it rather than asking whether it is worth it. Applies to the loop's PLAN authoring too
— amend a plan mid-iteration when it turns out to have specified a patch. See
[[feedback_scope_discipline]] for the counterweight: doing it right is not licence to widen scope
into unrelated work.
