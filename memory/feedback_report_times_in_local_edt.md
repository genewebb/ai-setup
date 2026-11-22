---
name: feedback-report-times-in-local-edt
description: "When reporting times to Gene, use local EDT (e.g. 19:20), not UTC \"Z\" times from stream logs"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 88dd58c6-96b7-40c3-a725-168a9ff9ce84
  modified: 2026-10-05T23:03:04.425Z
---

Report times to the owner in local time (EDT, UTC-4), not the UTC `...Z` stamps that `.streams` logs, tasks.json and inbox lines use.

**Why:** On 2026-10-05 I said G3's Browser leg would finish "~23:20Z"; Gene read it as local time and asked how it could be 23:20 when it was 19:02. The stream files are all UTC, so raw copies mislead.

**How to apply:** Convert every time in user-facing text to local (subtract 4 h in EDT; check `Get-Date -Format 'HH:mm zzz'` if unsure). Keep UTC only inside files written under `.streams\` (coordinator.log.md, decisions.md, inbox), which use UTC by convention. Related: [[feedback-voice-caveman-plus-truth-format]].
