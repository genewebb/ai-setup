---
name: reference-stream-build-check-inbox-before-handoff
description: stream-build reads its inbox only at cycle start; a HOLD item filed mid-build is missed unless the inbox is re-read right before marking built
metadata:
  node_type: memory
  type: reference
  originSessionId: 8082bbc9-52fb-4e53-9a34-f0b6977ebe46
  modified: 2026-10-02T13:25:21.250Z
---

stream-build reads its inbox (Get-InboxItems -Skill stream-build -Open) only at step 0. On 2026-10-02 a stream-author filed a "hold G3.T257, do not export or release" bug item at 13:08Z, while the builder was waiting on its verifier. The builder marked the row built at 13:11Z and only saw the item afterwards. It then had to forward the hold to stream-integrate.

The hold was real. The ticket's CSS edit moved the stylesheet digest pinned by tests/Tests.Architecture PaletteConformanceTests.ApprovedSheetDigest. The targeted tests did not cover it, and neither did the verifier.

**How to apply:**
- Re-run Get-InboxItems for stream-build immediately before `Update-Task -To built`.
- If an item names the task, act on it before releasing the row.
- For any edit to src/Web/wwwroot/css/speedy-crewchief.css, also run `tests/Tests.Architecture --filter PaletteConformanceTests`.

Related: [[reference-stream-stale-read-blocks-and-bugs]]
