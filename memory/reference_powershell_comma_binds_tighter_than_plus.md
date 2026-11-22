---
name: reference-powershell-comma-binds-tighter-than-plus
description: "PowerShell parses @($a, $b + 500) as ($a, $b) + 500 — the arithmetic becomes an extra array element, silently corrupting min/max bounds"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 9e600dde-a18a-4ec3-b816-daeb374fcc8c
  modified: 2026-09-29T15:17:35.647Z
---

In PowerShell the comma operator binds **tighter** than `+`, so an arithmetic expression after a
comma inside `@(...)` is not evaluated as one element:

```powershell
$ends = @($s.Length, $h.At + 500)   # WRONG: ($s.Length, $h.At) + 500  ->  @(804, 60, 500)
$ends = @($s.Length, ($h.At + 500)) # RIGHT: @(804, 560)
```

No error is raised. The array just grows by one bogus element, so
`($ends | Measure-Object -Minimum).Minimum` returns a bound that can be **below** the value it was
meant to clamp. Found it in a stream-kit grader where the corrupted minimum made
`$s.Substring($h.At, $end - $h.At)` throw `length ('-101') must be a non-negative value`, and the
swallowed exception left a stale window so a CORRECT implementation graded red.

**How to apply:** parenthesise every arithmetic expression that follows a comma in an array literal.
When a computed bound behaves impossibly, print the array before trusting the aggregate — the bug is
visible in the elements, never in the result.

Same family as [[reference_powershell_single_pair_array_flattens]].
