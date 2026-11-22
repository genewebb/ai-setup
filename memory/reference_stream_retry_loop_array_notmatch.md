---
name: reference-stream-retry-loop-array-notmatch
description: Lock-busy retry loop around Update-Task breaks early when output is an array; pipe to Out-String first
metadata:
  node_type: memory
  type: reference
  originSessionId: 023c4072-961e-42f8-be53-f86019d7361b
  modified: 2026-10-03T19:23:07.332Z
---

A retry loop of the form `$o = pwsh ... 2>&1; if ($o -notmatch 'lock busy') { break }` exits after the FIRST failed
attempt when the output has several lines: `-notmatch` on an array returns the non-matching elements, which are truthy.
On 2026-10-03 this dropped G3.T269's `-Artifacts` call (tasks.json lock held by the coordinator), the following
`-Release` succeeded, and the row went `ticketed` with `artifacts.grader = null`. Invoke-Grader then answers NO-GRADER,
and the author can no longer fix it (CLAIM-LOST once the claim is released).

**How to apply:** collect the output with `| Out-String` before matching. Set artifacts and release in ONE
Update-Task call (`-Artifacts ... -To ticketed -Release`). Check `artifacts.grader` in tasks.json after release. If it
is lost, send stream-plan an inbox item (`-Role plan` bypasses the claim check).

Related: [[reference-stream-kit-update-task-needs-beat]].
