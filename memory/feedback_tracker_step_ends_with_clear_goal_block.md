---
name: feedback-tracker-step-ends-with-clear-goal-block
description: Every /goal tracker step (and any one-row-per-session loop) ends with a copy-paste /clear + /goal block using the FULL tracker path
metadata:
  type: feedback
---

At the end of every tracker row (the requirements finish tracker, or any `/goal <file>` one-row-per-session loop), end the reply with a fenced `text` block Gene can paste straight in:

```text
/clear
/goal Q:\Work\Work\99 Documentation\speedy\Speedy-Requirements-Tracker.md
```

Name the next row above it; flag it if it is a `gene` row (Gene must be present for the picker). Give it even when the step was blocked, or when this session stopped because of a concurrent session.

**Why:** Gene, 2026-09-24: "at the end of each item give me a copy paste of the /clear and /goal prompt with the full file path".

**How to apply:** the full absolute path, never a relative one. Written with a Python heredoc, `\r` in `speedy\requirements\review` turns into CR bytes; check with `cat -A`. Related: [[feedback-prompts-full-paths-with-suggestions]], [[project-requirements-finish-tracker-2026-09-24]].
