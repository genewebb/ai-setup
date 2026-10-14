---
name: feedback-one-step-at-a-time-when-troubleshooting
description: "When Gene is driving a fix by hand (imports, UI steps), give ONE step, wait for the result, then the next"
metadata:
  node_type: memory
  type: feedback
  originSessionId: a23d97ec-2260-44b9-86f7-27c46e1a5b0f
  modified: 2026-10-13T21:31:34.876Z
---

When Gene performs the steps (UI clicks, CLI with password prompts), give exactly one action per reply, then wait for the outcome before the next.

**Why:** 2026-10-13, CrewChief secrets import troubleshooting: after a reply with options, caveats and a multi-step fallback, Gene said "Slow down lets just do 1 thing at a time till it works".

**How to apply:** One step, the exact command or click, and what result to report back. No alternative routes or fallback lists until the current step fails. Related: [[feedback-scope-discipline]].
