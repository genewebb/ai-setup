---
name: reference-permissions-drift-checker
description: Permissions sync is manual and every client copy drifts; verify with Check-PermissionsDrift.ps1
metadata: 
  node_type: memory
  type: reference
  originSessionId: 875a0862-8f07-47b0-b7a4-40af27dadba8
  modified: 2026-07-25T21:11:47.470Z
---

**Skills propagate automatically; permissions do not.** Skills work by shared
reference — Claude Code reads `~\AI\skills`, Copilot's `~\.copilot\skills` is a
junction to it, and VS Code's `chat.agentSkillsLocations` points at it. One
directory, three readers, drift structurally impossible. Only Cursor gets
copies (per-skill junctions), which is why Cursor is the only tree that drifts.

Permissions propagate by **copy**: `permissions.yaml` is canonical, but
`~\.claude\settings.json` and `%APPDATA%\Code\User\settings.json` are
independent hand-synced forks. Nothing automates it — `~\ai\scripts\sync.ps1`
only fetches external skills, and the skill audit never touches permissions.

Verify after any permissions change (exit 0 clean / 1 drift, never writes):

```powershell
pwsh "$env:USERPROFILE\ai\permissions\Check-PermissionsDrift.ps1" -Detail
```

**The tier models differ, and that is where the bugs come from.** Claude Code
has allow/ask/deny and resolves deny > ask > allow, so a blanket
`Bash(docker:*)` in allow is *fine* — the ask entries override it. VS Code's
`chat.tools.terminal.autoApprove` is a flat regex→bool map with **no ask
tier**: `ask` must be expressed as ABSENCE. A blanket `"/^docker/": true` there
is not "prefer allow", it silently overrides the entire ask tier.

Found 2026-07-25: 42 of 61 ask-tier commands were auto-approved in VS Code via
`/^docker/` and `/^obsidian/` blankets (incl. `obsidian eval`,
`docker system prune`). Fixed by enumerating safe subcommands and dropping the
blankets — not by adding `false` overrides, because false-beats-true precedence
is undocumented for VS Code and could not be verified.

**Anchor short patterns.** `/^fd/` matched the deny-tier `fdisk`;
`/^docker build/` matches `docker builder prune`. The checker caught the
`fd`/`fdisk` collision that a careful manual pass missed — run it, don't eyeball.

Wired into [[reference_permissions_sync]] via the `permissions-yaml` skill
(mandatory post-sync gate) and `config-gc` channel 5.
