---
name: reference-gateguard-hook
description: The GateGuard PreToolUse hook blocks the FIRST Edit/Write to each file per session until four facts are presented; how to satisfy it in one retry
metadata: 
  node_type: memory
  type: reference
  originSessionId: 2c31adc2-4218-414a-af8c-5d7fc72a07ec
  modified: 2026-09-07T01:52:11.000Z
---

A hook named **GateGuard** intercepts the first Edit (and Write) to each file in a session and refuses it with:
"present these facts, then retry the same edit: 1. ALL files that reference or import this file (Glob/Grep, do not
guess); 2. the public members this change affects; 3. real field names / structure / formats if it reads or writes
data; 4. the user's current instruction verbatim." Later denials on other files come "condensed" (same four facts,
one line). It fires **once per file per session**; the retry with identical arguments succeeds.

**How to apply:** for loop bookkeeping files (`.loop/PROGRESS.md`, `.loop/PLAN.md`, `.loop/tools/Write-TaskList.ps1`)
grep their consumers FIRST (Test-Budget.ps1, Get-ChangedFiles.ps1, Close-Plan.py, Write-Schedule.ps1) and quote the
handoff/user line in the same message as the retry — that turns two round-trips into one. Do not disable it
(`$env:CLAUDE_DISABLED_HOOKS='gateguard'`) without Gene's say-so. Shell appends (`Add-Content` to a repo file) are a
separate permission denial, not GateGuard; use Read(offset,limit) + Edit for large logs instead.

Related: [[reference-claude-hook-activation]], [[reference-claude-hook-output-channels]].
