---
name: project-logpull-v12-gui
description: "D:\\PowershellScripts\\logpull.ps1 (Profisee diag collector) v1.2 10/26 - WinForms settings window, remembered settings, SQL detect; uncommitted, GUI click-through + split app/DB detect untested"
metadata:
  node_type: memory
  type: project
  originSessionId: baad7b1c-ebf5-4f74-978a-ac9149bc489c
  modified: 2026-10-26T22:58:13.304Z
---

logpull.ps1 v1.2 built 10/26 in place (backup in session scratch logpull.ps1.orig, hash C55D15B9...). Adds: settings window (auto when interactive + no args, -Gui/-NoGui), console prompts on Server Core, remembered settings %ProgramData%\ProfiseeDiag\logpull-defaults.json (no password), SQL Detect (port-1433 conns from install PIDs + local registry instances), List DBs (tSystemLog flagged), Test, progress window with stop-and-package.

Same v1.2 changes ported 10/26 onto Gene's updated version (26.3 host topology, service/IIS finders, MaxPerDay) as D:\PowershellScripts\forensics_log_pull.ps1; headless run verified. That version's help claims SQL is found by decrypting connection strings - code does NOT do that. logpull.ps1 still lacks the health-probe EndInvoke fix the updated version has.

**Why:** Gene's sites are often split app server + DB server; laptop all-in-one is only one case.
**How to apply:** Precedence = param > remembered > env > SITE DEFAULTS > discovery. Profisee appsettings connection strings are ENCRYPTED (856-char), so SQL target cannot come from config. Untested: real GUI click-through run, elevation relaunch, remote 1433 detect. D:\PowershellScripts is a NAS git repo (dubious ownership from Claude shell); not committed.
