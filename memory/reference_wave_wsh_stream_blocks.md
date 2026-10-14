---
name: reference-wave-wsh-stream-blocks
description: "Wave Terminal 0.14.5 wsh facts behind addStreams/addStreamTab (stream tabs = Wave blocks, launch via profile hook); measured 2026-10-04"
metadata:
  node_type: memory
  type: reference
  originSessionId: 7fb21f1f-143d-43f4-acf3-a5550ca6256e
  modified: 2026-10-05T13:07:13.746Z
---

Owner switched stream tabs from WezTerm back to Wave on 2026-10-04 (laptop + SMVMTR1 profile). Measured on Wave 0.14.5:

- wsh has NO "new Wave tab" command. `wsh term <dir>` / `wsh run` open a block in the CURRENT Wave tab and print `block:<id>`.
- `wsh run -- cmd` and `wsh run -c` blocks get NO Wave env (no WAVETERM_BLOCKID/JWT, wsh not on PATH). Only shell blocks (`wsh term`) do.
- Wave starts shells as `pwsh -ExecutionPolicy Bypass -NoExit -File <Data>\shell\pwsh\wavepwsh.ps1`; the profile loads BEFORE it, and the Wave env comes from `wsh token $env:WAVETERM_SWAPTOKEN pwsh` inside it. The profile's Initialize-GeneWaveEnv runs that step early.
- Launch scripts live in `%LOCALAPPDATA%\gene-wave-launch\<block id>.ps1`. NOT the temp path: Claude Code sets TMP=C:\scratch\temp, so a launcher run from Claude wrote somewhere a fresh Wave shell never looked.
- `wsh blocks list` needs `--workspace=$env:WAVETERM_WORKSPACEID`, or it lists a different workspace.
- Keys that work: `frame:title` (block title), `wsh badge bell --color #e5484d --beep` / `wsh badge --clear`, `wsh setmeta -b this`, `wsh deleteblock -b <id>`, `wsh termscrollback -b <id>` (read a block's screen).
- addtab/addnew (general tab helpers) are still WezTerm-only.

Related: [[project-stream-tabs-profile-2026-10-04]], [[reference-wezterm-cli-autostarts-mux]]
