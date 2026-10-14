---
name: feedback_grader_clause_shapes_that_fail
description: "The grader clause shapes that keep failing in the vNext loop — match constructs, never adjacent characters, banned substrings, exact signatures, under-derived censuses or mutually unsatisfiable pairs"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 25a6f180-ace3-4c16-9718-60b837d6c54c
  modified: 2026-09-09T13:26:39.799Z
---

Fifteen grader defects across two days of the vNext orchestrator-worker loop. The early ones let bad code
through; **five of the recent ones FAILED CORRECT CODE, and three of those shaped the product to satisfy
the grader.** That second kind is worse: a grader that misses a defect leaves the code as it was, while a
grader that fails correct code makes somebody write something worse and attach no reason to it.

**Why:** every one of these matched CHARACTERS rather than CONSTRUCTS.

**The four shapes to stop reaching for:**

1. **Two tokens required adjacent (same line, or within N characters).** Inno `[Run]` puts the executable
   and its arguments in separate FIELDS; Pascal builds command lines in pieces; C# splits imports across
   lines. `advfirewall` (59.2), `sc.exe … password=` (59.4 — the clause could not catch a *verbatim copy of
   the donor code it forbade*), and `SERVICE_DELETE_ACCESS` read as a delete (59.5). **Follow the taint
   instead:** find the variable a value is built into, then follow that variable to the call.
2. **A banned substring.** 59.4's `AccountIsBuiltIn` now composes `'LOCAL' + 'SYSTEM'` at run time, because
   two criteria fail the build if the token appears anywhere — including in the code that must recognise it
   to refuse it. Ban a *behaviour*, not a spelling.
3. **An exact signature or list.** `u7-3-saturation` pinned a roster to five types; a later row legitimately
   widened it to six — exactly what the clause's own failure message asks of every future entry — and it
   reported "the tuple was not widened" over a tuple widened twice. Assert the member that matters and let
   the list grow.
4. **A lazy regex to the first closing brace.** `catch (SqlException e) { … }` sliced to the first `}` stops
   at the **interpolation brace** in `$"...{name}..."`, so the idiomatic one-liner failed and the shipped
   code hoisted a local purely to satisfy the pattern. **Count braces, quote-aware.**

**Two more that let things through, for completeness:** an OR whose weakest term cannot fail
(`Lsa…|Lsa…|advapi32` — the DLL name survives every import), and `[regex]::Match` where two things exist
(checked the first of two account checkers and reported on both — a silent install could have registered
under a local account while the grader said it could not). Use `Matches` and require all.

## Three more shapes, from rows 59.3i and 59.9 (2026-09-08/09) — count now EIGHTEEN

**Not one of the last five let bad code through.** Every one either failed correct work or reported
coverage it did not have.

5. **A two-token match over source that still contains STRING LITERALS.** `L8` asked "does this criterion
   still invoke the runner?" by matching `dotnet` … `test` on one line. A census line legally quoting
   `'mcr.microsoft.com/dotnet/sdk:10.0'` and `'No test matches'` satisfied it, **and an Executor left a
   migratable file un-migrated to avoid tripping it.** Fix: **blank string literals before any clause asks
   "is this a CALL?"** Keep the quotes so offsets survive; replace the contents with spaces. Stripping
   comments is not enough — a quoted identifier is not a call.
6. **A census derived from the wrong spelling, which reports a gap of zero over a real gap.** `N6a`
   derived the installer's command-line switches from `'/NAME='` literals; Inno parses
   `{param:NAME|default}`, and the quoted form survived in exactly ONE operator message — so it graded
   **1 of 7** switches and could not fail. Fix: **union every spelling the subject actually uses, and put
   a FLOOR under the derived count** so a collapsed derivation fails instead of passing quietly.
7. **Two clauses that cannot both be green.** `N9a` required a file to be git-TRACKED (only route: the
   index, since committing is forbidden), which makes the tree read dirty forever; `N10b` required the
   tree to read clean. **Unsatisfiable by any work**, and the PLAN's own verification step contradicted it
   too. Fix: measure a **DELTA across the boundary you care about** (snapshot, act, snapshot,
   `Compare-Object`) rather than an absolute state. Before shipping a grader, ask whether any two clauses
   constrain the same observable in opposite directions.

**And one that is the same defect as #3 wearing different clothes: a clause satisfied by a DIFFERENT
SUBJECT.** `S6` required a test naming a "blank connection string" case — and five pre-existing tests
about the *warehouse* connection satisfied it. Scoped to test-method names across the whole suite it was
then satisfied by an earlier row's *Domain* tests. Only scoping it to the two files where a BINDING test
belongs made it able to fail. **A clause must be unable to pass on work that already exists.**

## The limit of probing, and the shape that beat it (2026-09-09, defects 19–21)

**Probing validates a clause's MECHANICS. It cannot validate its OPERANDS.** I write the "correct" stub
from the same belief that produced the clause, so a wrong member name, column name or count passes the
probe and then fails every real Executor. Three in a row came from this:

- **A member name read off a FILE name.** A clause required `RunProfileMapping.CapturedRunProfileTableName`;
  the constant is declared in `RunProfileDefaults` — same file, different class. I had built the operand
  from a grep whose output showed file paths. **No compiling code could satisfy it**; the only route was a
  `using` alias shadowing the real type, and 48.B's Executor refused to write it and reported
  `deviation-blocked` with the declaration quoted. That refusal was worth more than the row.
- **A census direction taken from a plan document.** A clause demanded the field catalogue move from 24 to
  25 entries; measurement showed the field was already declared and already registered by an earlier row,
  so 24 already included it. Demanding 25 would have made an Executor invent a field.
- **A clause reading RAW source for a forbidden operation.** It grepped for `TRUNCATE` in a migrator whose
  own doc comment says *"Nothing here drops or truncates"* — **the file's promise that it never truncates
  would have failed the check for truncation.**

**So the rule is: verify every operand against the declaration, not against a document and not against
your own stub.** `grep -n "class \|const string X"` on the real file, before the clause is written. A
plan document is a statement of intent and drifts; the declaration is the fact. Same for column names — a
plan said `StepKey` where the column is `StepIndex` and the constant was `private`.

**The practice that pays:** probe every new grader against a deliberately-WRONG stub and a
deliberately-CORRECT one before dispatch. That caught a wrong ordering operand (a clause anchored on the
first `foreach` in a file, which was the state-seeding loop, not the dispatch), and it caught #4-style and
#3-style defects twice more *before* an Executor met them. The three that reached an Executor all cost
real work.

**How to apply:** before writing a clause, ask what CONSTRUCT proves the behaviour — a call with an
argument list, a member inside a slice, a position compared against another position, a non-zero exit — and
match that. When a clause fires, check whether it is describing a defect or a spelling. And when an
Executor reports a deviation of the form "I wrote it this way to satisfy the grader", that is a grader
defect report, not a style note.

Related: [[reference_grader_ordering_clause_indexof_blind_spot]],
[[reference_loop_criteria_regression_gap]], [[feedback_loop_practices_that_caught_defects]].

**Two more, both paid for 2026-09-10.**

**A clause windowed in raw characters measures how verbose the COMMENTS are.** Comment-stripping
leaves the indentation behind — 678 characters of it between one call and its `break` — so a
400-character window went red against correct code. Collapse whitespace before measuring
(`[regex]::Replace($slice,'\s+',' ')`), then a 200-char window is stable at any comment volume.

**NEVER write a regex into a grader through a non-raw Python heredoc.** `` becomes a literal
BACKSPACE and `
` becomes real newlines. This has now corrupted two clause repairs: `u7b-16`'s
`WHERE` (unsatisfiable for any source) and `u7b-21`'s W3 member bound (matched nothing, so the
slice silently became the whole file and **a stub with the subject DELETED still went green**). The
grader "passed" both times. Use raw strings, and **always re-probe a repaired clause against a stub
that should fail it** — re-running it is not verification.

## 2026-09-10 18:5x — u7b-33 (48.SEC3), three more, all caught by the first baseline run (now 21 defects)

19. **A GENERIC VERB IS NOT EVIDENCE OF A SPECIFIC CONTROL.** The ordering clauses accepted
    `Refuse|Refused` as "the permitted-target decision was consulted". `RunStoreResult.Refused(` appears
    **ten times** in `WorkloadLauncher.cs` already, so the clause went GREEN on a baseline with no
    allowlist at all. Scope the pattern to the control's OWN vocabulary (permit / allow), and check that
    every occurrence of it in the baseline file is inside a comment — which `Get-GradableCode` blanks.
20. **`[regex]::Match($input, $pattern, $startIndex)` does not exist.** The static 3-arg overload's third
    parameter is `RegexOptions`, so an index throws `MethodException: Cannot convert argument "options",
    with value: "22246"`. With `$ErrorActionPreference = 'Continue'` the clause then fails for the WRONG
    REASON instead of stopping. Use the instance form: `([regex]'pat').Match($text, $index)`.
21. **"Target", "Permitted" and "Refused" are ordinary words in this codebase.** Three of four
    behaviour-by-name clauses were answered by unrelated real tests — a part-restore test, a dial test and
    48.SEC2's own new audit test — and a fourth, `Launch_...IsRefusedRatherThanPermitted`, would have
    answered the launch clause. Require a COMPOUND token that names the control
    (`PermittedTarget|Allowlist|TargetNotPermitted|…`), and put the real decoy names in the probe.

Probe after repair: **25 of 25 both ways**, including the live launcher asserted RED. See
[[reference_grader_case_insensitive_prose_answers_code]].

## 2026-09-10 20:0x — u7b-18's own stripper, measured both ways at 48.RV7's close (defect 22)

The 48.RV7 Executor observed that T1 could be satisfied by the type name in an XML doc comment. **Measured,
and that specific claim is wrong** — `(?m)//.*$` strips `///` as well, so an XML-doc-only file fails T1
correctly. But probing it both ways found two things that ARE true of the hand-rolled stripper:

* **A STRING LITERAL satisfies it.** `_log.Info("retry cancelled: OperationCanceledException")` passes a
  clause asking whether the exception is handled, with no catch anywhere in the file.
* **`//` inside a literal DELETES REAL CODE.** `var u = "https://x/y"; KeepMe();` strips to
  `var u = "https:` — the call after the URL is gone. A census over that text can be wrong in EITHER
  direction: a missing thing found, or a present thing lost.

Fixed by replacing the function body with `Get-GradableCode` (48.GH's helper, which blanks comments AND
literal CONTENT while preserving length) and making T1 `-cnotmatch`. The grader still passes afterwards,
which is the check that matters — it proves the handling is code and not prose.

**THE GENERAL FACT, and it is a standing gap:** the helper exists and almost nothing uses it. The 48.GH
census was 110 of 124 graders folding case and 119 never blanking literals; u7b-18 is only the fourth
adopter. See [[reference_grader_case_insensitive_prose_answers_code]].
