---
name: reference_grader_needs_regex_leading_pipe_always_matches
description: "A stream-kit grader \"needs\" regex that starts with | matches the empty string, so the clause always passes — and PowerShell's comma-before-plus precedence produces exactly that element by accident."
metadata: 
  node_type: memory
  type: reference
  originSessionId: 14953f4f-051b-49b9-9a19-c427a7cb1482
  modified: 2026-09-29T17:10:12.798Z
---

In a stream-kit grader, a `needs` element whose regex begins with `|` (for example `'|account/security|AccountSecurityRoute'`) has an empty first alternative, so it matches any text and the clause passes on any implementation. The clause looks strict and proves nothing.

How the bad element appears by accident: `@((E 'A') + '|' + (E 'B'), 'C')` does not build two elements. Comma binds tighter than `+` (see [[reference_powershell_comma_binds_tighter_than_plus]]), so `'|' + ('B','C')` becomes `('|B','|C')` and the last need starts with `|`. Write `@( ((E 'A') + '|' + (E 'B')), 'C' )` with the alternation explicitly parenthesised.

Caught on 2026-09-29 while authoring G3.T032: the `NavMenu_RouteCensus_` clause passed on unpatched main, which a RED check is supposed to make impossible. A RED run that passes a clause you expected to fail is the signal — read the needs array, not the implementation.
