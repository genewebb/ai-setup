---
name: reference_grader_ordering_clause_indexof_blind_spot
description: "Loop grader gotcha — a refuse-before-publish ordering clause built on IndexOf of a joined literal silently PASSES when the call is split across lines (`await _publisher` NEWLINE `.PublishAsync`); match whitespace-tolerantly and FAIL when an operand is absent"
metadata: 
  node_type: memory
  type: reference
  originSessionId: fe35a383-1d24-4c5e-be3d-3bf85b9770f4
  modified: 2026-09-07T19:00:13.458Z
---

Found 2026-09-07 while authoring the 47.H grader (`u7-5e-publication.ps1`) for the speed-merchants vNext loop.

**The blind spot.** `WorkloadLauncher.LaunchAsync` calls `await _publisher` on one line and `.PublishAsync(...)` on the next. A grader clause written as `$la.IndexOf('_publisher.PublishAsync')` returns −1, and a guard shaped `if ($iRef -ge 0 -and $iPub -ge 0 -and $iRef -gt $iPub) { Bad }` treats the absence as a pass. The 47.G grader (`u7-r28-roles.ps1` clause 6, "the refusal must come BEFORE the publish") had exactly this shape and proved nothing; the code happened to be right because the Verifier read it.

**Two more traps in the same file.** (1) PowerShell `if` is a statement — `$out += ,(if (...) {...} else {...})` is a parse error that silently empties the array; assign `$slice = if ...` first. (2) `Method-Body` slicing the FIRST declaration of an overloaded name made the code's overload ORDER matter (47.G noted the leak); slice every declaration and pick by content (`Method-Bodies-Named` in the 47.H grader).

**A third trap, found 2026-09-07 15:4x on .NET SDK 10.0.400:** `dotnet test --filter <no match>` exits 0 and prints NEITHER `No test matches the given testcase filter` (the 10.0.302 text the loop skill documents) NOR a `Passed!`/`Failed!` summary — only "A total of 1 test files matched the specified pattern." Every grader's `if ($o -match 'No test matches')` branch is therefore dead code; the vacuous case is caught only by the fallback "did not report Failed: 0" branch, with an empty message. Write the guard as "no `Passed!`/`Failed!` summary line at all = vacuous".

**How to apply:** in any structural grader, (a) match member-access chains with `\s*\.\s*` between segments; (b) compute positions from `[regex]::Match(...).Index`; (c) add an explicit `Bad` when any ordering operand is −1 — "it must never pass by absence"; (d) for overloads, slice all declarations and select by a body marker. Related: [[reference_loop_criteria_quote_mangling]], [[feedback_loop_practices_that_caught_defects]].
