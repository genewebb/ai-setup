---
name: reference-grader-text-order-is-not-execution-order
description: "A grader clause about ORDER must skip function bodies - PowerShell scripts declare helpers above the main flow, so the first textual match is usually inside a function that runs last"
metadata: 
  node_type: memory
  type: reference
  originSessionId: e3a74c18-5260-4502-b3a3-80d67fb55328
  modified: 2026-09-30T21:40:53.473Z
---

A stream grader clause that pins the ORDER of two things in a script must measure the MAIN FLOW only: skip every
`function ... { }` body. PowerShell (and the repo's e2e proofs in particular) declare helpers at the top of the file, so
the first textual match of a call is usually inside a helper that executes hundreds of lines later.

Measured on the G3.T149 grader, 2026-09-30: the clause required the setup-seeding call to sit before the first request
at a `/monitor` route. `Invoke-UiDialProof.ps1`'s `Get-MonitorSample` requests `$MonitorUrl` at line 269, about 270
lines ABOVE the sign-in at line 537 that will one day call it, so two of three honest probe files were refused for
seeding "after" a request they make later. `Invoke-PauseDialAtomicProof.ps1` had the same shape at line 352.

The fix is a `Function-Spans` helper: match `(?m)^[ \t]*function\s+[\w-]+`, brace-match from the first `{` with a
walker that steps over quoted strings and here-strings, and keep only matches outside every span. Apply it to BOTH
offsets being compared, not just the later one.

Found by building an honest probe tree and grading it BEFORE handing the grader to the skeptic - the RED run on main
cannot show this class of bug, because on main the call does not exist yet and the clause fails for the right reason.

Related: [[reference_grader_line_anchor_unreachable_in_crlf]] · [[feedback_copy_before_probe_never_git_checkout]]
