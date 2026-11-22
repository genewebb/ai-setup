---
name: reference-grader-trx-datarow-name-has-trailing-space
description: "A grader that reads a trx test name by splitting on \"(\" can never match a DataRow test, because MSTest writes a space before the argument list."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 66ca2049-1df0-487b-9264-50351534f8e8
  modified: 2026-09-30T18:20:48.201Z
---

A stream grader that reads per-test outcomes out of a `trx` (the only way, because Speedy's
`Tests.Unit.csproj` sets `VSTestLogger` to `console;verbosity=minimal`, which prints a summary only)
usually does this:

```powershell
Name = ($r.Node.testName -split '\(')[0]
...
$_.Name -eq $test -or $_.Name -like ('*.' + $test)
```

That can never match a **data-driven** test. Measured on a real trx: MSTest writes a `DataRow` result's
`testName` as

```
AKeyThatOnlyLooksLikeTheCategoryMarker_IsStillRefused ("testdata-samples/_other")
```

— with a **space before the parenthesis**, and the name is **not** fully qualified. Splitting on `(`
leaves a trailing space, so both the `-eq` and the `-like '*.' + $test` comparisons fail and the clause
reports "did not run" for a test that ran and passed every row. A parameterless test is unaffected: its
`testName` carries no parenthesis at all.

Fix: `Name = (($r.Node.testName -split '\(')[0]).Trim()`, or match the name as a prefix.

This is unworkaroundable from the builder's side when one clause pins the test by name and another
requires it to carry `DataRow` attributes: no shape of the test satisfies both, so the task goes back to
`planned` as a grader defect. First hit: G2.T105, 2026-09-30, where nine of ten clauses passed and the
targeted filter was 54/54 green.

Related: [[reference_grader_line_anchor_unreachable_in_crlf]],
[[reference_grader_needs_regex_leading_pipe_always_matches]],
[[reference_stream_kit_mtime_grader_clause_breaks_on_integrate]].
