---
name: project_remember_plugin_install
description: remember@claude-plugins-official installed 2026-08-01; storage redirected to ~/.remember to keep repos clean; bash on PATH is the WSL shim
metadata: 
  node_type: memory
  type: project
  originSessionId: 5b8d5633-9e1d-41a2-a8d6-8a777c2ff523
  modified: 2026-08-01T17:24:15.370Z
---

Installed `remember@claude-plugins-official` v0.12.3 (user scope) on 2026-08-01. It is a
*third* memory layer alongside built-in auto-memory (`autoMemoryDirectory` → `~/.claude/memory`,
~148 files) and the MCP knowledge graph — see [[reference_prompt_cost_analysis]] before adding more.

**Storage was redirected on purpose.** The plugin's default is "legacy" mode, which writes a
`.remember/` folder into *every project dir it runs in* — that would drop untracked folders into
`C:\devops\repos\speed-merchants` and friends. Fixed by creating `~/.remember/config.json` with
`"data_dir": "~/.remember/{slug}"`, which flips it to "external" mode. Verified:
`REMEMBER_DIR = ~/.remember/c--devops-repos-speed-merchants`. Delete that file to revert.
Config precedence: per-project > user-global (`~/.remember/config.json`) > plugin-bundled.

**Gotcha — `bash` on PATH is `C:\WINDOWS\system32\bash.exe`, the WSL shim, not Git Bash.**
It mangles Windows paths (strips backslashes) and exits 127. The plugin's hooks are
`bash "${CLAUDE_PLUGIN_ROOT}/scripts/*.sh"`. Under Git Bash (`/usr/bin/bash`) the same scripts
run clean. If remember's hooks silently never fire, check which bash the harness resolved.

Health check: `bash ~/.claude/plugins/cache/claude-plugins-official/remember/0.12.3/scripts/doctor.sh`
(set `CLAUDE_PROJECT_DIR` first, or it assumes cwd). Needs python + jq — both present.

**Why:** the default install would have polluted git repos, and the WSL-bash shim is a silent
failure mode that looks like "the plugin just doesn't do anything".

**How to apply:** if remember appears dead, run doctor.sh under Git Bash before assuming a
config problem — and never let a hook-based plugin default to in-project storage.
