---
name: reference-claude-hook-activation
description: Hooks and skills activate live without a restart; the env-var hook kill switch cannot be set mid-session
metadata: 
  node_type: memory
  type: reference
  originSessionId: 875a0862-8f07-47b0-b7a4-40af27dadba8
  modified: 2026-09-07T02:00:44.677Z
---

Verified 2026-07-25 while building the GateGuard hook.

**Hooks and skills activate immediately — no Claude Code restart needed.**
Editing `~\.claude\settings.json` to add a `PreToolUse` entry began gating tool
calls within the same session. Adding five new skill junctions made them
available in the same session too. Documentation that says "restart to pick up
a new skill/hook" is stale.

**Exception (2026-09-06):** the SessionEnd *outer* abort budget is computed from the settings-hook snapshot
taken at session start (`initialHooksConfig`), so a settings `timeout` added mid-session only counts from the next
session. Separately, every SessionEnd hook has a hard 1.5 s per-hook default that only the hook's own `timeout`
overrides. See [[reference-sessionend-hook-1-5s-budget]].

**`$env:CLAUDE_DISABLED_HOOKS` cannot be changed mid-session.** Every PowerShell
or Bash tool call runs in its own process; hooks inherit the *Claude Code*
process environment, which no tool call can mutate. An env-var kill switch only
works if exported before launching Claude Code — i.e. never at the moment you
actually need it.

The working pattern is a **file-based switch** read by the hook at run time:
`~\.claude\hooks-disabled.txt`, one hook id per line, `#` for comments. Both
mechanisms live in `~\.claude\scripts\hook-dispatch.ps1`. Note the permission
classifier will prompt before letting an agent write that file, since it reads
as disabling a safety control.

Hook output contract in use here: always `exit 0`; express a block by emitting
`hookSpecificOutput.permissionDecision = 'deny'` with a
`permissionDecisionReason`, which is fed back to the model.

See [[project_ecc_adoption]].
