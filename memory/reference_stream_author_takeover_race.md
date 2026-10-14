---
name: reference-stream-author-takeover-race
description: "Stream-kit author takeover of a stale claim can race a still-alive old session that rewrites the same ticket/grader; hash before writing, re-verify after"
metadata:
  node_type: memory
  type: reference
  originSessionId: f98abe3a-fd66-49cc-a1d9-dac7394654fe
  modified: 2026-09-28T12:42:40.667Z
---

A stream-author claim whose beat is older than 30 minutes can be taken over, but the old session may still be alive.
It may be stuck in a long skeptic wait, and it won't see the takeover until its next Update-Task returns CLAIM-LOST.

On 2026-09-28, G2.T04 was taken over from author-...-7487 at 07:04Z. 7487 then rewrote the ticket (and possibly the
grader) between 12:05Z and 12:28Z, interleaved with my own edits, and later sent an inbox note. Nothing was lost,
because my writes landed last and my RED ran on the final grader, but the files briefly held mixed text.

**How to apply:**
- After a takeover, record the ticket and grader SHA-256 and mtime at claim time.
- Re-check them before each write. If they changed, re-read in full before editing.
- Before release, confirm the RED log's `GRADER sha` equals the current grader hash.
- After release, read the inbox for a collision note from the old session.
- `Copy-Item` keeps mtimes, so a copied "final version" can carry an old timestamp; compare content, not dates
  ([[reference-copy-item-preserves-mtime-breaks-counterfactual]]).

Related: [[reference-tracker-concurrent-sessions-check-output-exists]], [[project-stream-kit-replaces-myloop]].
