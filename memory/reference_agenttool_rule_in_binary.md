---
name: reference-agenttool-rule-in-binary
description: "The \"Do not call the AgentTool unless the user requested it\" line ships in the claude binary — not config, and it is conditional"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 1e74b2d6-4efb-4b7b-a2c9-3ef77423c33c
  modified: 2026-08-01T21:28:14.782Z
---

The system-prompt lines *"Do not call the AgentTool unless the user requested it"* and
*"Do not use workflows or deep-research unless the user requested it"* are **compiled into
the `claude` binary** (`C:\Users\agenewe\.local\bin\claude`, ~265 MB native install, 5
occurrences, as `Kep = [...].join(...)`). They are **not** in any config file.

Confirmed absent from: `~/.claude/CLAUDE.md`, project `CLAUDE.md`, project
`.claude/settings.local.json`, `~/.claude.json` (note: this sits **outside** `~/.claude/`,
so a recursive grep of that directory can never reach it), `settings.json`,
`remote-settings.json`, `policy-limits.json`, `agents/`, `~/Documents/PowerShell`,
`C:\devopslocal\powershellscripts`, `C:\ProgramData\ClaudeCode` (no such dir). No
`statsig/` cache exists.

**Two consequences.** No config edit can remove it — do not go hunting. And it is
*conditional*, not a prohibition: the CLAUDE.md **Delegation** section ("When I ask for a
long unattended run, use a single `Agent` call") is a standing user request that satisfies
it, so the `Agent` route is open. This closed what
[[reference_prompt_cost_analysis]] had carried as its highest-value open thread (item 6,
~180M tok).

Verify: `grep -c "unless the user requested it" ~/.local/bin/claude` returns non-zero
(expected); a hit in any config file would be new and *would* be actionable.
