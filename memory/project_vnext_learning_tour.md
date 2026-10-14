---
name: project_vnext_learning_tour
description: "The vNext learning tour for Gene lives in Q:\\Work\\Work\\99 Documentation\\speedy\\vnext-tour — diagram 01 covered, 02 and 03 owed; RESUME-HERE.md is the restart point"
metadata: 
  node_type: memory
  type: project
  originSessionId: 294cde8f-293d-4642-975e-7d247c797d22
  modified: 2026-09-09T14:01:53.990Z
---

Started 2026-09-08 18:00 EDT on Gene's ask: *"I want to learn what we are building with the vNext...
take me on a tour asking question to make sure I understand what has been built and what is being
built and contrast it to the donors."*

**Folder: `Q:\Work\Work\99 Documentation\speedy\vnext-tour\`** — note this is `speedy\`, NOT the
programme's own `speed-merchants\vNext\` folder where the plan and per-unit designs live.

**`RESUME-HERE.md` in that folder is the restart point.** It carries the covered/not-covered table,
the established facts, the regeneration commands, and a paste-ready restart prompt. Read it before
doing any more tour work rather than re-deriving.

**State at 2026-09-09: diagram 01 (runtime) COVERED — 11 of 11 boxes explained, 13 Q&A written.
Diagrams 02 (donor parity) and 03 (run lifecycle) owe both.**

**Two format decisions Gene drove, and they stick:**

1. **Click a box, get prose.** Gene: *"When you click on a box add an expanding section at the bottom
   that talks about its function and compare it to the old system"*, then *"update all the boxes with
   the purpose in plain english of what they do so I can just click on each one and read it."*
   archify's schema has **no long-text field per node** and its delivered HTML is receipt-frozen, so
   the answer was a hand-authored companion page — `01-vnext-runtime-explained.html` — beside the
   archify original. Each panel has three blocks: *What it does* / *What it replaces* (TestAuto and
   CrewChief side by side) / *One thing to know*. Keep both files; archify has the better viewer,
   the companion has the teaching.
2. **Do not quiz him on facts he has not been given.** Gene: *"I do not know the answers to these
   questions so start building a Q&A document."* Answer first, in writing, cited. The Socratic
   default is wrong here because he is learning a system he has not read.

Also: *"you are not using the same words as the html has"* — when walking a diagram, quote box and
edge labels **verbatim**. Paraphrasing them makes the narration unfollowable.

**Two build traps already paid for** (full detail in RESUME-HERE §3): keep archify JSON ASCII-only
(a Python cp1252 re-read double-encoded every em dash into `a<euro>"`), and the dataflow/lifecycle
renderers have **fixed layout grids that `meta.viewBox` does not stretch** — dataflow stage pitch
215px, 5 fixed rows, node width ≤160px; lifecycle phase columns at x 94/248/402/556/710 with only
three columns in the event and outcome lanes.

Related: [[reference_vnext_plan_doc_v3]], [[reference_archify_diagram_skill]],
[[feedback_explain_plain_english_with_example]], [[project_vnext_planning_sweep_2026-09-05]].
