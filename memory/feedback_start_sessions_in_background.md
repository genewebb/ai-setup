---
name: feedback-start-sessions-in-background
description: "Sessions/runners launched from PowerShell must stay in the background, never pop visible windows"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 185f5665-8770-43d9-9ee7-eb0430a4dfbe
  modified: 2026-10-04T17:49:42.352Z
---

When starting Claude sessions or stream runners from PowerShell (Start-Process), keep them in the background: `-WindowStyle Hidden` (or Minimized), never a visible console window that takes focus.

**Why:** Owner said on 2026-10-04 ("when you are starting sessions with powershell make sure they stay in the background") after the -Live trial launcher opened visible pwsh consoles.

Owner added: visible consoles "popup on the screen and have to be minimized"; real runner sessions will run in WezTerm shells (tabs/panes), not standalone consoles.

**How to apply:** Every Start-Process that launches a runner, claude session or long job gets `-WindowStyle Hidden`. For `-Live` runners, the owner watches through Remote Control (claude.ai/code), not the console. Whether an interactive `-Live` TUI behaves in a hidden console is unverified; check it on the first hidden launch.

Related: [[project-stream-fresh-context-runner]]
