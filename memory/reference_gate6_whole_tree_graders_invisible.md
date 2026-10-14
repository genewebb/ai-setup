---
name: reference_gate6_whole_tree_graders_invisible
description: "A whole-tree grader (g3-census-audit) is invisible to a gate-6 census keyed on graders that NAME the touched files; g3 went red at 48.SEC3b's close and nobody saw it for a row."
metadata: 
  node_type: memory
  type: reference
  originSessionId: aa701f44-5fa5-4edf-ae81-2fc43ee32e4c
  modified: 2026-09-11T06:58:19.876Z
---

**Gate 6 extended is usually run by censusing graders that NAME the row's touched files** (`grep` the
criteria dir for `WorkloadModule`, `CliRunner`, …). That census cannot see a grader that names no file
because it walks the whole tree.

Measured 2026-09-11: `g3-census-audit.ps1` went RED the moment row **48.SEC3b** closed, because that row
added `tests/Tests.Unit/PermittedTargetHostsCompositionTests.cs`, which carries a census, and nothing
classified it in `tests/CENSUS-INVENTORY.md`. My gate 6 ran 12 graders over the touched file names and all
12 were fine; `g3` names none of those files, so it was never run. It stayed red through the next row and
was found only because **48.RV9b's Executor reported it as a `deviation-note`** — the PLAN had told it
"g3 exits 0 either way", and it measured instead of believing.

**How to apply:** when a row ADDS a test file, run the whole-tree graders explicitly at its close —
`g3-census-audit.ps1` at minimum — not just the ones matching the touched file names. Any row that creates
a file with a counted literal owes `CENSUS-INVENTORY.md` a row in the same commit.

Same family as [[reference_loop_criteria_regression_gap]] (gate 6 never re-checks earlier CRITERIA) — the
blind spot is the *keying* of the census, not the graders.

Related: [[feedback_grader_clause_shapes_that_fail]], [[reference_grader_case_insensitive_prose_answers_code]].
