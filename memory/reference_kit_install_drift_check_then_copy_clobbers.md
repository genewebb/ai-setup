---
name: reference-kit-install-drift-check-then-copy-clobbers
description: "A drift check that only REPORTS, in the same command as the copy, overwrote another session's kit script - two sessions add cases to the same self-test file, so on any drift stop, diff and merge"
metadata:
  node_type: memory
  type: reference
  originSessionId: 1a14b1e5-45cb-4509-8b19-dd9a75142145
  modified: 2026-09-30T21:10:30.141Z
---

The `/stream-kit inbox` procedure says to hash-check the live file against the base copy before publishing. On
2026-09-30 at 20:53Z that check ran **in the same shell command as the copy**, printed `DRIFT
Test-StreamKitRecovery.ps1`, and the copy ran anyway — overwriting the session in scratchpad `863df4aa`, which had
installed **case 20** (the `-BuildOutputOnly` prune must delete `bin`/`obj` only BESIDE a project file, because
matching the name alone also deletes `tests\Tests.E2E\node_modules\eslint\bin` and the tree then fails Playwright on a
missing binary — a real defect in the prune installed 18 minutes earlier) and **case 51**. Nothing was lost only
because that session's own stage was still on disk: `find <temp>/claude -name Test-StreamKitRecovery.ps1 -newermt ...`
located `kitfix-1842/live2`, and the suite was rebuilt from it with the local case re-inserted (its snapshot had lost
the line break before `} catch {`, which is a parse error — check that when merging).

**Why:** `Test-StreamKitRecovery.ps1` is the collision point of the whole kit. Every fix adds a case to that ONE file,
so two coordinators working two inbox items always write it, while the scripts they each change are usually disjoint.
A report-only drift check cannot stop it, and there is no lock on `~\.claude\skills\stream-kit\scripts`.

**How to apply:** treat drift as a STOP, never as a line of output — diff the live file against the base, merge the
other session's cases in, run both suites, then install. Never put the check and the copy in one command. Before
installing a suite, `grep` the live copy for case numbers the stage does not have. Recovery path when it happens
anyway: other sessions' stages live under
`C:\Users\speedmerchants\AppData\Local\Temp\claude\C--devops-repos-speedmerchants\<session>\scratchpad\`, so find the
newest copy by mtime and rebuild. Kit fix requested as `IN-20260930210538-9dc0`: an `Install-KitFile.ps1` that takes
the staged file plus the base hash and REFUSES with a named exit code, plus per-case files under a `cases\` folder the
suite dot-sources. Related: [[reference_stream_inbox_item_reopened_while_held]],
[[reference_stream_claim_order_is_group_first_by_design]], [[reference_stream_stale_read_blocks_and_bugs]].
