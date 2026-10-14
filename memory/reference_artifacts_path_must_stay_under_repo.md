---
name: reference-artifacts-path-must-stay-under-repo
description: "When the review host locks src/Web/bin, build/test speedmerchants with --artifacts-path UNDER the repo (tests/bin/<name>), never the scratchpad — tests locate Speedmerchants.sln by walking ancestors"
metadata: 
  node_type: memory
  type: reference
  originSessionId: b1f8cd5f-6ce3-4617-9512-c6797bf44a0a
  modified: 2026-09-22T02:32:44.539Z
---

A running `speedy-web` review host (from `src/Web/bin/Debug/net10.0`) locks the Web bin, so `dotnet build`
of Web, Tests.Unit or Tests.Architecture fails with MSB3021/MSB3027 "locked by speedy-web". Do not stop
Gene's host. Build and test with `--artifacts-path C:/devops/repos/speedmerchants/tests/bin/<name>`
(`bin/` is gitignored, so the tree stays clean).

**Why:** an artifacts path OUTSIDE the repo (e.g. the session scratchpad) makes ~30 composition tests throw
"Could not locate Speedmerchants.sln in any ancestor" — they find the repo root by walking up from the
test binary. Seen 2026-09-21 during crewchief-backup-restore Goal 1.

**How to apply:** use the same `--artifacts-path` on both `dotnet build` and `dotnet test --no-build`.
Related: [[reference-speedy-interactive-page-testing]].
