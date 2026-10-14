---
name: reference-claude-wezterm-attention-bell
description: "Claude Code \"needs input\" signal in WezTerm = built-in preferredNotifChannel terminal_bell + WezTerm visual_bell/bell handler; hooks CANNOT emit BEL to the terminal"
metadata:
  node_type: memory
  type: reference
  originSessionId: 0b764e74-e444-4097-b9ac-d3bddc2c7f57
  modified: 2026-09-28T17:18:38.360Z
---

Set 2026-09-28 (Claude Code 2.1.283, WezTerm 20240203).

- `~/.claude/settings.json` `"preferredNotifChannel": "terminal_bell"`: Claude itself writes BEL to its own terminal on the same event as Notification hooks (aM(): permission/AskUserQuestion/elicitation dialogs after 6 s unanswered; idle_prompt 60 s after turn end). `auto` resolves to no_method_available for WezTerm, so it has to be set explicitly.
- A hook can't do this: hook children get a private hidden console (GetConsoleProcessList showed only pwsh+cmd), and stdout is captured. The only other route is AttachConsole(claude pid) and writing to CONOUT$, which is hacky and test-only (scratch script bel-to-claude-console.ps1).
- `~/.wezterm.lua`: visual_bell BackgroundColor, colors.visual_bell #7a1f1f, a `bell` handler that sets wezterm.GLOBAL['bell_pane_<id>'] and logs `lua: bell: pane N` to `~/.local/share/wezterm/wezterm-gui.exe-log-<gui pid>.txt`. format-tab-title shows yellow `▲ ` until the tab is visited.
- To validate the wezterm config, use `wezterm --config-file X ls-fonts --text a` and look for ERROR lines. `show-keys` ignores config errors (it passed a syntax-error control).
- WezTerm 20240203 has no taskbar flash/attention API (no FlashWindow in the binary).
