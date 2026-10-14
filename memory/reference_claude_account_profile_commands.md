---
name: claude-account-profile-commands
description: How Gene launches the work vs home Claude accounts — claude-work / claude-home PowerShell functions backed by CLAUDE_CONFIG_DIR
metadata: 
  node_type: memory
  type: reference
  originSessionId: fa40df6a-0fdf-4238-8da5-c17c0b7727a2
  modified: 2026-09-08T15:46:17.768Z
---

**`CLAUDE_CONFIG_DIR` relocates the ENTIRE Claude Code config directory**, not just credentials — verified
empirically 2026-09-08 on 2.1.263: pointing it at an empty dir produced a fresh `.claude.json` + `backups\` there
and `claude mcp list` returned "No MCP servers configured" despite the work config having many. There is no CLI
flag equivalent; the env var is the only lever.

**Set up in `C:\Users\agenewe\Documents\PowerShell\Microsoft.PowerShell_profile.ps1`** (region
`#region Claude account profiles`, at the end of the file):

- `claude-work` → `~\.claude` (the pre-existing config; identical to bare `claude`)
- `claude-home` → `~\.claude-home`
- `claude-which` / `Get-ClaudeAccount` → table of Account / ConfigDir / Exists / LoggedIn / Active
- `Start-ClaudeAccount -Account work|home` is the worker; it sets the env var, calls `claude`, and restores the
  previous value in `finally` so nothing leaks into the parent shell.

The Windows PowerShell 5.1 profile (`Documents\WindowsPowerShell\`) was deliberately NOT updated.

**Login is per config directory, on disk — not per terminal.** Log in once per account and it persists across
terminals, reboots, and concurrent sessions. Both accounts can run at once in different windows without
clobbering each other.

**The cost:** `~\.claude-home` starts EMPTY — no settings.json, skills, plugins, hooks, memory, MCP servers,
CLAUDE.md, or project history. Sharing pieces requires a junction/symlink per subfolder (e.g. `skills`,
`memory`); do not junction the whole directory or the credentials collide.

Related: [[claude-account-switching]] (what breaks mid-session when the live account changes).
