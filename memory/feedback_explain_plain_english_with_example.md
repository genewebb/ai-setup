---
name: feedback-explain-plain-english-with-example
description: "When explaining a change or a bug, lead with plain-English prose and a concrete before/after worked example, not code and API detail"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 83a4516d-2eae-4cf5-b95c-1c532000cfe9
  modified: 2026-09-01T13:32:21.952Z
---

When explaining a proposed change, a bug, or a trade-off, lead with **plain English plus a concrete
before/after example**. Do NOT open with the code, the call path, file:line references, or the
API-level detail. Confirmed 2026-09-01: I explained a `MutationPass` null-cell change twice — first
with the actual C# block, placement-vs-RNG-stream reasoning and blast radius, then again in plain
English with a five-column sample record traced through "today" vs "after". User's verdict on the
second one: *"make a note to update how you explain things this is a better example"*, and they
approved the change immediately off it.

The shape that worked:

1. Two or three sentences of plain prose — what the thing does now, in the user's own domain terms
   ("the engine is told to dirty at most 3 columns per copy").
2. A small concrete example: a handful of named columns with real-looking values, traced line by
   line through the current behaviour and then the new behaviour, each line annotated with what it
   cost ("change 3 of 3 <-- wasted").
3. The result of each run stated in one sentence.
4. The catch / trade-off last, short.

**Why:** the decision the user is actually making is about OUTCOMES in the data, not about where a
guard sits relative to an RNG draw. The code-first version buried the thing that mattered — copies
were silently getting less dirty than configured — under placement and stream-determinism detail
they had not asked about. The worked example made the consequence obvious in about ten seconds.

**How to apply:** save the code, file:line, and determinism/blast-radius analysis for after the
decision, or for when they ask how it is implemented. Diagnosis of a reported bug follows the same
rule: show the offending row's actual values side by side with what they should have been before
naming the method that produced them. Related: [[feedback_max_response_4000_chars]],
[[feedback_verify_no_guessing]] — plain English still means verified, never hand-waved.
