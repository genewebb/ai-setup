---
name: reference_foreman_agent_types_not_exposed_after_q_remap
description: "In a session started while Q: was down, the harness never exposes the custom agent types (foreman-worker, foreman-verifier ...) even after the remap restores the skills; Agent() answers \"Agent type not found\" and the dispatch must fall back to general-purpose with the model set explicitly"
metadata: 
  node_type: memory
  type: reference
  originSessionId: a9ffccdd-9a37-438d-a068-1a38be87e221
  modified: 2026-09-12T23:54:59.396Z
---

**Measured 2026-09-12 19:52.** Session opened at 19:32 with `Q:` Unavailable. After `net use Q: /delete /y` +
remap, the Skill tool re-scanned and `/myfable` plus the whole work-ai library reappeared (verified). The
**Agent tool did not re-scan**: `Agent(subagent_type: foreman-worker)` returned
`Agent type 'foreman-worker' not found. Available agents: caveman:*, claude, claude-code-guide, code-simplifier, Explore, general-purpose, Plan, statusline-setup`
although `~\.claude\agents\` (symlink to `C:\Users\agenewe\AI\agents\`, which is on C:, not Q:) holds
`foreman-worker.md`, `foreman-verifier.md`, `foreman-scout.md` and nine others. **Correction 20:05:** the custom types DID appear later -- a harness notice listed all twelve (foreman-worker,
foreman-verifier, ...) about 13 minutes after the first Agent() call failed, with no action on my side. So the agent
list is re-scanned lazily and LATE, not fixed; a dispatch attempted before that re-scan fails. Nothing observable
triggered it; treat the first minutes after a remap as a window where Agent() may refuse the custom types.

**How to apply:** dispatch as `subagent_type: general-purpose, model: opus` and paste the foreman-worker contract
(the agent file's body: execute one ticket, MUST NOT fence, no subagents, four-status report under 25–40 lines)
into the prompt verbatim; record the fallback in `rows\_decisions.md` and the close note. For a verifier, same
with `model: fable`... if `fable` is not an accepted model name for Agent, disclose the substitution. A session
that needs the real agent types must be started AFTER the remap ([[reference_nas_drive_letters_stale_after_reboot]]).

Related: [[project_myfable_foreman]]
