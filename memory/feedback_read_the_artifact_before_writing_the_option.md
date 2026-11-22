---
name: feedback_read_the_artifact_before_writing_the_option
description: Any AskUserQuestion option asserting what code/config/a screen does RIGHT NOW must be read first and cited file:line
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 791f1040-13cb-474c-8883-7a1bc9dc8c14
  modified: 2026-09-29T18:35:44.320Z
---

Before writing an `AskUserQuestion` option (or any recommendation) that asserts what the code, a config, a
screen or a document does **right now**, open that artifact and cite `file:line` in the option text.

Claims about what something *should* do, and trade-offs between designs, need no read. Only present-state
claims do.

**Why:** on 2026-09-29 I built two option sets from ticket prose without opening what they described. Gene
answered both, and both answers had to be withdrawn one round later:

- "Re-pin to a fresh hash" — `.streams\graders\G1.T01.ps1:81-89` **already** ran `Test-UnchangedFromHead`
  (`git diff --quiet HEAD`) and its header at 76-80 named the fresh-hash failure outright. The answer would
  have reversed built, integrated code.
- "Dashboard replaces Home at /" — `src/Web/Components/Pages/HomePage.razor:5` **already** declares itself
  the owner-approved landing dashboard (mockup 2026-09-25). The answer would have discarded that audit.

Both files were readable before I wrote the question. An option that misstates present state does not just
risk a wrong answer — it spends the owner's decision on a false premise, and the withdrawal costs another
round.

**How to apply:** when a question names a grader, a page, a test or a setting, read it first, quote the
deciding line, and let the option say what is there. If reading it is genuinely too expensive, say in the
option that the state is unverified rather than asserting it.

Same family as [[feedback_verify_no_guessing]] and
[[feedback_measure_before_writing_mockup_notes.md]]; the questions themselves follow
[[feedback_questions_via_askuserquestion]].
