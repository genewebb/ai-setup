---
name: reference-pwsh-ram-pct-and-claude-process-tree
description: "Cheap system RAM % in pwsh 7 (GC.GetGCMemoryInfo, no WMI/Add-Type) and the claude.exe process tree on Windows (native binary, daemon/pty-host trio)"
metadata:
  node_type: memory
  type: reference
  originSessionId: 6152524c-4243-4593-91d8-64515627c267
  modified: 2026-09-28T15:35:18.323Z
---

- RAM % in pwsh 7 without WMI: `[GC]::Collect(0); $g=[GC]::GetGCMemoryInfo(); 100*$g.MemoryLoadBytes/$g.TotalAvailableMemoryBytes` = same as Win32 dwMemoryLoad, ~12 ms. Add-Type P/Invoke GlobalMemoryStatusEx costs 200-600 ms per fresh process. `Microsoft.VisualBasic.Devices.ComputerInfo` does NOT exist in pwsh 7.
- claude.exe (`~\.local\bin\claude.exe`) is a single native binary, no bun/node child. node.exe under cmd = MCP servers.
- Background sessions = 3 claude.exe: `daemon run` (parent WmiPrvSE) -> `--bg-pty-host` -> `--session-id ... --resume`.
- Status line / tool shells descend from their session's claude.exe (claude -> cmd -> pwsh); nearest claude.exe ancestor via PS `Process.Parent` = current session. Implemented in `~\.claude\statusline.ps1` line 2 (Claude / All Claude / RAM), 2026-09-28.
