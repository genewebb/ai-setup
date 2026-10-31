---
name: feedback-end-items-with-clear-goal-prompt
description: "When working a /goal tracker, end every status update and every finished row with a copy-paste /clear + /goal block using the tracker's full absolute path"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 36343544-0920-4704-a51a-ad91e890b18b
  modified: 2026-09-25T00:53:13.236Z
---

While a /goal session works a tracker (e.g. METRIC-PROFILES-TRACKER), finish each item (each status update, each row recorded) with a fenced copy-paste block:

```text
/clear
/goal Do the next open rows of <FULL tracker path> exactly as its "Instructions for the /goal session" say. ...
```

Use the tracker's own routine text verbatim, with the full absolute path.

**Why:** Gene, 2026-09-24: "add this at the end of each item give me a copy paste of the /clear and /goal prompt with the full file path". He restarts sessions often and wants the restart line ready at every checkpoint.

**How to apply:** the block goes last in the reply, after the Truth-format sections. Related: [[feedback-prompts-full-paths-with-suggestions]].
