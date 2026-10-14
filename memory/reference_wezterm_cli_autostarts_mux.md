---
name: reference_wezterm_cli_autostarts_mux
description: "`wezterm cli list` with no GUI silently spawns a headless wezterm-mux-server and exits 0; use `wezterm cli --no-auto-start` in any GUI check"
metadata:
  node_type: memory
  type: reference
  originSessionId: 7fb21f1f-143d-43f4-acf3-a5550ca6256e
  modified: 2026-10-04T18:40:07.155Z
---

Seen 2026-10-04 on CORPLTR94 (laptop runs Wave terminal, no WezTerm GUI): `wezterm cli list` printed a WARN, ran `wezterm-mux-server.exe --daemonize`, and returned exit 0 with an empty list. A "is the GUI reachable" check built on it passes, and later `cli spawn` tabs open in the invisible mux.

- Fix used in the pwsh profile's `Test-GeneStreamPrereqs` (addStreams/addStreamTab): `wezterm.exe cli --no-auto-start list`.
- `addStreamTab` also checks `$env:WEZTERM_PANE` (Test-GeneWezTerm); `addStreams` does not, by design (it can open a new window from outside WezTerm while a GUI runs).
- If a stray `wezterm-mux-server` appears after a probe, it was the probe; stop it.

Related: [[project_profile_machine_config]], [[project_machine_sync_skill_2026-10-01]].
