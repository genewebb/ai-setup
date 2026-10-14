---
name: reference_claude_cli_session_flags
description: "Claude CLI 2.1.289 facts: -n is display name only (no resume); --bg + attach/logs/stop background sessions; --max-budget-usd only with -p; mods can run slash commands"
metadata:
  node_type: memory
  type: reference
  originSessionId: 7a4a12d9-1bfc-4bb2-92dc-efc4e075367a
  modified: 2026-10-04T15:16:22.092Z
---

Verified from `claude --help` and the mod type file (v2.1.289, 2026-10-04):
- `-n/--name` sets a display name only. Resume needs `-r/--resume`, `-c/--continue` or `--session-id`. So the stream runner's `-p -n <id>` starts an empty conversation every launch.
- `--bg` starts a background session and prints a short id; `claude attach <id>`, `claude logs <id>`, `claude stop <id>`, `claude agents --json`.
- `--max-budget-usd` and `--include-partial-messages` work only with `--print`. `--output-format stream-json` gives realtime events.
- Remote Control: `claude --remote-control [name]` = interactive session with RC on (no `/remote-control` typing); `--remote-control-session-name-prefix`; `claude remote-control` = separate persistent server. Impossible under `-p`. Do NOT run `claude remote-control --help` in a tool call: it hung 120 s.
- Mods: `$.command.run`, `$.prompt.submit`, `$.session.compact`, `$.session.usage`, `$.tool.register`. Whether `command.run` accepts `/clear` or `/exit` is UNTESTED.

Design using these: `C:\tmp\EnhanceStream.md` (option G = runner + interactive session per unit + unit_done mod). Related: [[stream-skills-sync-tr1-to-vault]].
