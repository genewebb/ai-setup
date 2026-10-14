---
name: feedback_end_step_with_clear_goal_block
description: End every tracker/goal step with a copy-paste /clear + /goal block using the FULL file path
metadata:
  node_type: memory
  type: feedback
  originSessionId: 3b1ebfa2-a0ad-468c-964d-70e38bf35180
  modified: 2026-09-25T00:53:20.240Z
---

At the end of each tracker row (or any self-driving /goal step), print a fenced `text` block Gene can paste as-is:

```text
/clear
/goal Q:\Work\Work\99 Documentation\speedy\Speedy-Requirements-Tracker.md
```

**Why:** Gene asked for it on 2026-09-24 after row A2: "at the end of each item give me a copy paste of the /clear and /goal prompt with the full file path".

**How to apply:** Name the next row above the block, and flag it when that row is a gene row (he must be present for the picker). Put the block before the final `TRACKER STEP COMPLETE` line. It is written into the tracker's instruction 6. The same full-path rule appears in [[feedback_prompts_full_paths_with_suggestions]]. Related: [[project_requirements_finish_tracker_2026-09-24]].
