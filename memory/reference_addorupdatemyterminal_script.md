---
name: reference-addorupdatemyterminal-script
description: D:\PowershellScripts\AddOrUpdateMyTerminal.ps1 carries Windows Terminal settings embedded; -Capture refreshes; run applies to admin + desktop account; NOT part of stream kit
metadata:
  node_type: memory
  type: reference
  originSessionId: 28b4b57d-60e7-4188-8363-cdb1021347e0
  modified: 2026-10-17T18:22:32.327Z
---

`D:\PowershellScripts\AddOrUpdateMyTerminal.ps1` (UNC `\\SynologyDS918\devopslocal\PowershellScripts`), built 2026-10-17.
- Windows Terminal settings.json embedded between `# <MyTerminalSnapshot>` markers; `-Capture` rewrites that block from the running account.
- Default run: self-elevates, winget-installs WT if missing, applies settings to elevated account (agenewe) AND Explorer owner in same session (genewe), backup only on change (keeps 5), recreates Public-desktop shortcuts "Terminal (Admin)" (RunAs flag) + "Terminal" (normal). -Help/-h lists options.
- One file to copy; Gene copies to `C:\PowershellScripts` on other machines.

**Why:** Gene said it has nothing to do with stream work; keep it separate from the stream kit / addStreamTab profile.
**How to apply:** never fold it into stream-kit scripts or ai-setup without asking. Related: [[feedback-full-script-every-iteration]].
