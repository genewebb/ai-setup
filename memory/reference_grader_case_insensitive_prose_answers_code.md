---
name: reference_grader_case_insensitive_prose_answers_code
description: "PowerShell -match is case-insensitive while [regex]::Matches is case-sensitive, so a grader mixing them lets prose answer a clause about code"
metadata: 
  node_type: memory
  type: reference
  originSessionId: c6ce4951-6bc9-4695-a55f-766a2d5318ae
  modified: 2026-09-10T21:23:27.195Z
---

Measured across the speedmerchants loop 2026-09-10: of **118 graders**, **108 use `-match`/
`-notmatch`** (case-INSENSITIVE), only **24 strip comments**, and **none blank string literals**.

`[regex]::Matches($text, $pattern)` is **case-SENSITIVE**. `$text -match $pattern` is **case-
INSENSITIVE**. A grader using both has clauses that disagree about case, and the loose ones can be
satisfied by prose.

**It happened.** `u7b-25`'s A3 asked whether the run summaries print a duplicate figure and was
**GREEN at baseline** — because `AgentRunner.cs:218` carries the word "redelivered" in `--help` text
inside a verbatim string literal. Comment-stripping does not help: string literals survive it.

**The fix, in order of strength:**
1. `-cmatch` / `-cnotmatch` everywhere, so lowercase prose cannot match a PascalCase identifier.
2. Require a **declaration** (`^\s*(?:public|internal)\s...`) or a **member access** (`\.\s*Name`)
   rather than a bare token — prose has neither.
3. Acceptance-test the pattern in isolation against plausible names AND prose forms before dispatch.

Blanking string literals wholesale is wrong for printed figures: `$"X={result.Count}"` needs the
interpolation hole preserved.

**IT IS NOT ONLY GRADERS — the loop's own reporting tooling has had it three times**, and each one lied
to Gene on the published page rather than in a criterion:
1. `Write-Schedule.ps1`'s done-predicate `-match '✅|DONE'` made 48.RV7 render **Complete** off the prose
   "a correct-stub probe is deliberately NOT done". Fixed to `-cmatch '✅|\[x\] DONE'` (9/10).
2. The same file's Started fallback `-match 'DISPATCHED|RUNNING|IN PROGRESS|...'` rendered a QUEUED row
   (48.MIG2) as **Started** off "the finding is recorded in PROGRESS.md" — `in PROGRESS` matched
   case-insensitively. Fixed to `-cmatch` on 2026-09-10 17:2x, minutes after filing the row.
3. `Build-Schedule-Html.py` reads `state` rather than re-deriving it, so it inherited both.
**Rule: any predicate deciding STATE from prose is the same defect class as one deciding CODE from prose.**
Use `-cmatch`, demand the marker in capitals, and prefer a structured signal (`dispatched.json`) over text.

Tracked as row 48.GH. Related: [[feedback_grader_clause_shapes_that_fail]],
[[reference_write_tasklist_row_silently_dropped]].
