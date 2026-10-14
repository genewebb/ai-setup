---
name: reference_destructive_path_guard_cmd_switch_false_positive
description: "destructive-path-guard prompted on any delete + cmd /c | mklink /J | robocopy /MIR because \"/c\" read as Git Bash drive root; permission rules cannot fix a hook \"ask\"; patch script C:\\tmp\\Patch-DestructivePathGuard.ps1 (2026-09-30)"
metadata:
  node_type: memory
  type: reference
  originSessionId: ad1cbbdb-c083-484e-be03-41cf713f3a30
  modified: 2026-09-30T18:52:11.536Z
---

A prompt saying `Hook PreToolUse:... destructive-path-guard: ... outside the repo/scratch roots (/c)` comes from `~\.claude\scripts\destructive-path-guard.ps1`, NOT from permissions.yaml or settings.json. A hook's "ask" beats every allow rule, so editing permissions cannot silence it.

Cause fixed 2026-09-30: switch tokens like `/c` `/J` `/MIR` read as POSIX absolute paths. The fix drops `/x` switches only in segments that call cmd, mklink, robocopy, xcopy, icacls, attrib or takeown. It also closed a gap where `cmd /c rd ...` was never seen as destructive, made the temp root per-user (`[IO.Path]::GetTempPath()`, needed on SMVMTR1 where the user is `speedmerchants`), and added `c:\devops\worktrees\`.

**How to apply:** the patch script is idempotent, backs up the file, and restores on self-test failure. On a machine whose guard is still unpatched, run `pwsh -NoProfile -File <path>\Patch-DestructivePathGuard.ps1`. Hook scripts are COPIED per machine from S:\AIWork, so patch both the S: source and `~\.claude\scripts` ([[project_aiwork_move_to_s_drive]]). CORPLTR94 was patched 2026-09-30, and its 72 hook tests pass.
