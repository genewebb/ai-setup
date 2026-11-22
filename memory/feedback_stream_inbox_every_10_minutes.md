---
name: feedback-stream-inbox-every-10-minutes
description: "Stream kit sessions (coordinator, plan, integrate) must check their inbox every 10 minutes automatically; coordinator loop is /loop 10m"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 185f5665-8770-43d9-9ee7-eb0430a4dfbe
  modified: 2026-10-02T14:13:21.881Z
---

Every stream-kit session works its inbox at least every 10 minutes, unattended. The coordinator runs under
`/loop 10m /stream-coordinator repo: ...` (was 20m) and every tick works the kit and plan inboxes.

**Why:** 2026-10-02 the owner asked each skill to check its inbox every 10 minutes; plan items had waited 20-49 min.

**How to apply:** start or restart the coordinator with `/loop 10m`. Publish skill text through Publish-KitFile.ps1
into the corpus, never by editing the installed copy: on 2026-10-02 other sessions hand-edited installed
stream-plan/stream-integrate SKILL.md for the same request, and Install-AIMachine.ps1 then stopped on drift (exit 3).
Do not `-AcceptDrift` over another session's installed edit; see [[reference-kit-corpus-vs-live-divergence]].
