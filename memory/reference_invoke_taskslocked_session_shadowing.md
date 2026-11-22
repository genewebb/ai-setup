---
name: reference-invoke-taskslocked-session-shadowing
description: "Stream kit trap - a scriptblock passed to Invoke-TasksLocked sees ITS $Session param, not the caller's; also `, $arr` + caller @() = 1-element array"
metadata:
  node_type: memory
  type: reference
  originSessionId: 63467b00-779c-4e7e-bf25-13432d1bfd23
  modified: 2026-10-04T21:38:31.802Z
---

A scriptblock passed to `Invoke-TasksLocked $P $By { ... }` (stream kit `lib\Streams.ps1`) runs in dynamic scope inside
`Invoke-TasksLocked`, whose own `-Session` parameter shadows any `$Session` of the calling function. Measured 2026-10-04 on
kit item IN-20261004202424-27bf: `Clear-SessionClaims` compared claims to `$Session` and got the runner id (the lock
owner), so no claim ever matched. The self-test case caught it; RED-on-base alone would not have.

**How to apply:** inside such a block, read caller values through uniquely named locals (`$unitSession = $Session`).
Also never `return , $arr.ToArray()` from a function whose caller wraps it in `@()`: that gives one element holding the
array (printed `System.String[]`). Return the array plain. Kit stage layout: [[reference-kit-stage-needs-mirrored-layout]].
