---
name: reference-stream-stale-read-blocks-and-bugs
description: "Stream roles file blocks and bug items against stale reads of tasks.json and graders; verify the artifact's CURRENT content before acting on any inbox claim"
metadata:
  node_type: memory
  type: reference
---

Stream inbox items routinely describe a state that was already fixed. Two on 2026-09-29, within 20 minutes:

- A coordinator filed a bug saying `.streams/graders/G1.T01.ps1` still delegates 19 clauses to the wiped
  `.loop/criteria/rd-25.ps1`. The grader had been rewritten 36 minutes earlier and emits 8 clauses of its own
  with no delegation. The item's own cited line numbers pointed at a retirement comment, not at any delegation.
- An author blocked `G5.T015` saying its write set forbids `tests/Tests.Web/NavMenuTests.cs`, 21 minutes after
  that file was added to it.

Both reports were internally consistent and well evidenced, and both were wrong about the present tree.

**How to apply:**
- Never act on an inbox item's premise. Re-read the named file or task and confirm the claim still holds, then
  quote what you found in the close-out note so the sender can see the difference.
- Decline with evidence rather than doing the work anyway: cutting a task for 19 grader clauses that already run
  would have been pure waste.
- Check an item's cited line numbers actually say what it claims. A citation that misses is the cheapest
  staleness signal.
- Before YOU file a block or a bug, re-read the artifact immediately beforehand. This is the same rule
  [[reference-stream-author-takeover-race]] applies to tickets and graders, extended to every role's inbox writes.
- Sweep wider than the item: both items named a subset. The NavMenuTests sweep found 2 more defective tasks, the
  FLEETCHAN orphan sweep found 7 where 1 was reported, and the proof-script sweep found 7 scripts where 4 were
  named with 2 of those paths wrong.

Related: [[project-stream-kit-replaces-myloop]], [[feedback-verify-no-guessing]].
