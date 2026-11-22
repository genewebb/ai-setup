---
name: feedback-report-inbox-count-every-tick
description: "Every loop/status tick must check the inbox and report open count, held items with step, and current work (or idle)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: fdb8702f-dda6-4ad9-8b9c-9852b5b7c684
  modified: 2026-10-10T14:43:48.859Z
---

On every loop tick (the session's normal status cadence), check the inbox and report: number of open items, each item held with its step, and what the session is working on now (or `idle`). Do this on idle ticks too. For the stream kit, "inbox" means the kit inbox (`Get-InboxItems.ps1 -Open`) plus `ReadNotifications`.

**Why:** On 2026-10-10 the owner said "read your inbox" and could not tell whether the session was alive or working. An empty tick report looks the same as a dead session.

**How to apply:** Every tick report needs one line like `Inbox: N open; holding X (suites running); working on Y`. stream-kit SKILL.md `/stream-kit inbox` step 7 states this rule for kit sessions. Related: [[feedback-stream-inbox-every-10-minutes]] [[index_stream_kit]]
