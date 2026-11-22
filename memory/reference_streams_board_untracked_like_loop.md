---
name: reference-streams-board-untracked-like-loop
description: ".streams is excluded via .git/info/exclude with 0 tracked files, so the whole stream board sits exactly where .loop sat before the 2026-09-26 wipe"
metadata: 
  node_type: memory
  type: reference
  originSessionId: fdc71f18-c334-4b35-81a3-3e8bc6b3f329
  modified: 2026-09-29T16:48:46.176Z
---

`.streams/` in `D:\devops\repos\speedmerchants` is excluded at `.git/info/exclude:27`, not `.gitignore`, and
`git ls-files .streams` returns 0. Every grader, ticket, patch, verdict and log on the board is therefore in no commit,
on this machine only, and not even shared through the repo's own ignore rules. The only copy mechanism found is
`D:\tmp\stream-host\Copy-StreamToHost.ps1`, a one-shot host-migration script using `robocopy /MIR` — a mirror, which
propagates a deletion rather than protecting against one. There is no scheduled backup.

This is the same position `.loop` was in before it was wiped on 2026-09-26, and that wipe is still doing damage: it
destroyed `rd-25.ps1`, `rd-33.ps1`, `PLAN-1.RD-25.md`, `PLAN-1.RD-33.md` and the `D:\tmp\speedy-build\` re-shoot
harness, and commit `909a2f1` (which several graders pinned against) is not in the repository either.

**Why:** a grader that shells out to a path outside the repo, or pins a commit, is only as durable as that thing —
and on this board nothing outside a commit is durable.

**How to apply:** treat a grader that reads anything outside `-Root` as a defect, and pin CONTENT (a hash, or an
embedded base64 blob checked after decoding) rather than a commit id. When a baseline must be relative, ask the graded
tree's own HEAD instead of a fixed hash or a named commit. Before relying on board state surviving, check whether it is
tracked. Related: [[project-myloop-state-wiped-2026-09-26]], [[project-stream-kit-replaces-myloop]].
