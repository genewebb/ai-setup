---
name: reference-stream-revise-ticketed-row-work-not-in-ticket
description: "Folding new work into a TICKETED stream row via Revise-Task adds write set and title only; the ticket and grader never cover it, so the work is silently dropped"
metadata:
  node_type: memory
  type: reference
  originSessionId: 185f5665-8770-43d9-9ee7-eb0430a4dfbe
  modified: 2026-10-02T08:07:44.875Z
---

Revise-Task on a `ticketed` (or later) row changes the board's write set and title, but the builder works only from the
ticket and grader, which were authored before the revise. New work folded into such a row is never built or checked.

**Why:** 2026-10-02, a doc-comment follow-up was folded into G3.T237 after its author had ticketed it; caught and moved.

**How to apply:** before folding work into an existing row, check its state. Fold only into `planned` / `blocked`
rows (no ticket yet), or add a new row / move it to a later unticketed row on the same files. Related:
[[reference-add-tasks-overlap-counts-integrated-and-globs]] (Add-Tasks refuses overlap with integrated owners; add the
row without those files, then Revise `addWriteSet`). Also: in PowerShell `$r` and `$R` are the SAME variable.

`release: auto` on a BUILT row does not send it back to `ticketed` (2026-10-02, G3.T202 stayed built after a file was
removed from its write set). Its kept patch is then stale: file a `stream-integrate` item asking the integrator to
send it back for a rebuild instead of integrating it.

`release: auto` with `addWriteSet` on a blocked row that HAS a ticket + grader still lands it in `planned`, not
`ticketed` (seen 2026-10-02: G3.T249, G3.T247, G3.T145, G3.T138). The same `auto` with NO write-set change sent blocked
G3.T219 to `ticketed`, so the write-set change is the likely trigger (Revise-Task source not read). Revise cannot set
`built`; a row with a valid kept patch goes to `ticketed` and the builder restores the patch. Do not add a placeholder
path to dodge an Add-Tasks overlap: list the integrated owner in `dependsOn` and Add-Tasks accepts the shared file
(G3.T254 with G2.T36, 2026-10-02). An empty write set is refused ("no write set"). Tell the author in the item
close that an author must re-release it.
