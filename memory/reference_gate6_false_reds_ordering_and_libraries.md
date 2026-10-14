---
name: reference_gate6_false_reds_ordering_and_libraries
description: "Two ways a gate-6 sweep manufactures RED verdicts that are not defects — running baseline-comparing graders before the re-baseline, and running parameterised library graders standalone."
metadata: 
  node_type: memory
  type: reference
  originSessionId: aa701f44-5fa5-4edf-ae81-2fc43ee32e4c
  modified: 2026-09-11T13:31:12.190Z
---

Measured 2026-09-11 at 48.RV12's gate 6 (53 graders, 13 red). **Four of the thirteen reds were
artefacts of how the gate was RUN, not facts about the row.**

## 1. Baseline-comparing graders are meaningless before the re-baseline

`b2h-master-bootstrap-probe`, `b3-store-reconciliation` (and `b6-0-capability-reconciliation`'s
file-diff arm) assert *"src/ and tests/ unchanged from the iteration-N baseline"*. They read
`.loop/BASELINE.json`, which the loop advances **only after a PASS** (`Get-Baseline.ps1 -Iteration N`).

Run gate 6 before that step and the closing row's own legitimate files are reported as violations.
Both went RED listing `src/Web/Access/WebAccessScheme.cs` and `tests/Tests.Web/WebAccessSchemeTests.cs`,
and both went GREEN immediately after `Get-Baseline.ps1 -Iteration 160` with no code change at all.

`criteria-state.json` made it look worse: it is written by the FULL SWEEP only, never by a per-row
gate run, so its `lastExit` is stale in both directions. All three suspects shared
`lastGreenAt: 2026-09-11T05:59` — one sweep, not three coincidences. **Never read that file as "the
prior verdict" for a hand-run gate.**

**Rule: re-baseline first, then run the baseline-comparing graders.** They are the one family whose
contract requires the passing row's changes to be absorbed before the question means anything.

## 2. A parameterised library is not a grader

`plan-doc-census.ps1` is the generic engine behind `u7-0-plan.ps1`, `u7b-0-plan.ps1` and friends —
each wrapper passes its own row ids. Run bare it exits non-zero with
`Cannot process command because of one or more missing mandatory parameters: Prefix Doc`.

That is a **harness error wearing a verdict's clothes**. Counting it red sends a future reader hunting
a defect in a row that did nothing wrong; counting it green is worse.

Fixed structurally in `.loop/tools/Get-Gate6Graders.ps1`: any script whose first 60 lines declare a
mandatory parameter is skipped and named. **The pattern must accept BOTH spellings** —
`[Parameter(Mandatory)]` and `[Parameter(Mandatory = $true)]`. The first draft required `= $true`,
and `plan-doc-census.ps1` uses the bare form, so it skipped nothing while reading as working. Caught
only by running the selector and checking the skip line actually appeared.

## The general shape

A criterion's whole contract is that it exits 0 or non-zero **on its own**. Anything that needs an
argument, or needs the loop to be in a particular state first, is not answering the question the gate
is asking. See [[reference_gate6_whole_tree_graders_invisible]] for the selection-side blind spot and
[[feedback_loop_practices_that_caught_defects]] for the habit that surfaced this one.
