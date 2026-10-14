---
name: full-script-every-iteration
description: When iterating on SQL or runnable code the user is actively testing, always deliver the complete updated script — never a diff or snippet
metadata:
  type: feedback
---

When iterating on any SQL script (or other runnable code) the user is actively testing, always deliver the **complete updated script** every time — never a partial diff, snippet, or "here is just the changed section" excerpt.

**Why:** The user pastes the script directly into SSMS or a runner; a partial excerpt forces error-prone manual merging.

**How to apply:** Every revision of a script under active test = full file output, even for one-line changes. (Migrated from myworkspace AGENTS.md, 2026-07-30.)
