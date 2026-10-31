---
name: feedback_end_step_with_clear_goal_block
description: End every tracker/goal step, status update and finished row with a copy-paste /clear + /goal block using the FULL file path
metadata:
  node_type: memory
  type: feedback
  originSessionId: 3b1ebfa2-a0ad-468c-964d-70e38bf35180
  modified: 2026-10-31T09:00:00.000Z
---

At the end of each tracker row, status update or self-driving /goal step (any `/goal <file>` one-row-per-session loop), print a fenced `text` block Gene can paste as-is:

```text
/clear
/goal Q:\Work\Work\99 Documentation\speedy\Speedy-Requirements-Tracker.md
```

When the tracker has its own routine text ("Do the next open rows of <FULL tracker path> exactly as its Instructions for the /goal session say ..."), use that text verbatim instead.

**Why:** Gene asked for it on 2026-09-24 after row A2: "at the end of each item give me a copy paste of the /clear and /goal prompt with the full file path". He restarts sessions often and wants the restart line ready at every checkpoint.

**How to apply:**
- Always the full absolute path, never a relative one.
- Name the next row above the block, and flag it when that row is a gene row (he must be present for the picker).
- Give the block even when the step was blocked, or when this session stopped because of a concurrent session.
- The block goes last in the reply, after the Truth-format sections, and before a final `TRACKER STEP COMPLETE` line if the tracker uses one. It is written into the tracker's instruction 6.
- Writing the path with a Python heredoc turns `\r` in `speedy\requirements\review` into CR bytes; check with `cat -A`.

Merged 2026-10-31 from two duplicates (now in archive/). The same full-path rule appears in [[feedback_prompts_full_paths_with_suggestions]]. Related: [[project_requirements_finish_tracker_2026-09-24]].
