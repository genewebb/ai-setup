---
name: reference-claude-hook-output-channels
description: Hook output channels — systemMessage is the zero-token nudge path; SessionStart stdout injects context; Stop stdout is near-invisible
metadata: 
  node_type: memory
  type: reference
  originSessionId: 2ff4c5a7-4085-4485-b826-5358d33ceffa
  modified: 2026-08-01T19:55:05.331Z
---

Claude Code hooks have three distinct output channels and picking the wrong one
either costs tokens forever or makes the output invisible.

- **`systemMessage`** (JSON field, alongside `continue: true`) — shown to the user,
  does **NOT** enter the model's context. **Zero token cost.** This is the correct
  channel for any advisory/nudge hook. Shape:
  `@{ continue = $true; systemMessage = $msg } | ConvertTo-Json -Compress`
- **`SessionStart` stdout** — **injected into the model's context** (this is how the
  `remember` plugin works). Anything written here is re-read on every subsequent turn
  of that session. Never use it for a nudge whose purpose is reducing token cost.
  Same for `hookSpecificOutput.additionalContext`.
- **`Stop` stdout with exit 0** — only surfaced in transcript mode (Ctrl-R), i.e.
  effectively invisible in normal use. Not a viable notification path.

Other verified behaviours:
- `Stop` payload has `stop_hook_active` — guard on it or the hook piles on during a
  stop-hook continuation.
- `SessionStart` payload has `source`: `startup` | `resume` | `clear` | `compact`.
- `hook-dispatch.ps1` resolves `-Id X` to `scripts/X.ps1` and **`exit 0`s silently if
  the file is missing** — fails open. Verify a hook by the script's existence, not by
  the `settings.json` entry.
- Whether `context_window.*` arrives on stdin is confirmed only for the **status line**.
  For Stop/SessionStart, prefer it if present but fall back to parsing the transcript
  tail for the last assistant `usage` block.

Live examples: `~/.claude/scripts/context-watch.ps1`,
`~/.claude/scripts/session-context-nudge.ps1`, `~/.claude/scripts/lib/context-size.ps1`.

Related: [[reference-claude-hook-activation]], [[reference-prompt-cost-analysis]]
