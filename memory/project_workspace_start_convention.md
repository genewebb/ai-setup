---
name: workspace-start-convention
description: "Sessions start in C:\\devops\\myworkspace (launch pad, not a project); memory is shared at ~/.claude/memory; Bash(*) blanket is deliberate"
metadata: 
  node_type: memory
  type: project
  originSessionId: 164e7710-52ca-4205-8c9e-769af15611f2
  modified: 2026-07-30T14:24:57.461Z
---

Workspace convention established 2026-07-30:

- **Start directory**: `C:\devops\myworkspace` — a non-project launch pad with its own `CLAUDE.md` (repo index + conventions). All repos under `C:\devops\repos` are reachable via global `additionalDirectories` + `Read/Edit` allow rules in `~/.claude/settings.json`.
- **Shared auto-memory**: `autoMemoryDirectory` (user settings) points ALL sessions at `C:\Users\agenewe\.claude\memory` regardless of cwd. The old per-project memory dirs under `~/.claude/projects/*/memory` were emptied into it (speed-merchants corpus + governance notes + 2026-03/04 myworkspace notes).
- **Bash(*) blanket is deliberate** (Claude Code only): allow list holds `Bash(*)` + `PowerShell(*)`; safety comes from the deny/ask tiers, defaultMode auto, and the git-commit-block hook. Recorded in `~/ai/permissions/permissions.yaml` under `tools.claude_code_extras` — the enumerated `commands.allow` there is canonical for OTHER clients only. Never translate the blanket to a client without an ask tier (VS Code).
- **Plugins global**: code-simplifier, github, claude-md-management were promoted from speed-merchants project settings to user settings.
- Settings backup from the migration: `~/.claude/settings.json.bak-2026-07-30-workspace`.
- **Per-repo `.claude/` settings are inert under this convention**: project settings only load when a session is rooted in that repo, never via `additionalDirectories`. speed-merchants' `.claude/settings*.json` were deleted 2026-07-30 (its `.gitignore` pattern `.*/` means `.claude/` was never tracked anyway — no repo settings are shared with teammates).
- **Guardrail parity audit 2026-07-30**: with `CLAUDE_CODE_USE_POWERSHELL_TOOL=1`, every git guardrail must cover BOTH tools — git-commit-block hook matcher widened to `Bash|PowerShell`, its regex now catches `git -C <path> commit`, and deny tier gained `git -C` merge/cherry-pick (Bash) plus all `git -C` forms for PowerShell. Known accepted gap: canonical `file_access.ask` (.env/*.pem/**/secrets/**) has no Claude Code counterpart and the drift checker only compares commands.
