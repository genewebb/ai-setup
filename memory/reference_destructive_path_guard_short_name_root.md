---
name: reference-destructive-path-guard-short-name-root
description: "Scratchpad paths reach hooks as the 8.3 name C:/Users/SPEEDM~1/..., which no long-name root prefix matches"
metadata: 
  node_type: memory
  type: reference
  originSessionId: d539ad38-f356-499c-a3ac-6db5ea446494
  modified: 2026-09-29T03:42:13.565Z
---

The harness hands Claude a scratchpad path spelled with the 8.3 short profile name — `C:/Users/SPEEDM~1/AppData/Local/Temp/claude/...` — so a trusted-root list written as `c:\users\speedmerchants\appdata\local\temp\` never matched and every `rm` under the scratchpad prompted. Fixed 2026-09-28 in `~\.claude\scripts\destructive-path-guard.ps1`: `Normalize` expands the short segment, but only when it is the current user's (8.3 keeps the first 6 characters), so another account's `c:\users\otheru~1\` still reads as outside.

**Why:** the guard compares normalized string prefixes, and 8.3 and long names are different strings for the same directory.

**How to apply:** any path allow-list compared as a string must expand 8.3 names first, or match on a resolved full path. Also remember hooks are not permissions: a `PreToolUse` hook returning `ask` overrides an allow rule, so allow-listing a command in `settings.json` or `permissions.yaml` never silences a hook prompt — fix the hook. Hook scripts are re-read per invocation, so a fix is live for every session with no restart. Related: [[reference-hook-tests-inherit-disabled-hooks-env]] and [[project-aiwork-move-to-s-drive]] (mirror the change to `S:\AIWork\claude\scripts\`).
