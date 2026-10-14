---
name: reference-path-form-gotcha
description: Why C:\tmp prompts under /c/tmp and /tmp on Windows — permission path-form matching gotcha
metadata: 
  node_type: memory
  type: reference
  originSessionId: c97a32c0-251f-44df-9bc4-96487dc452d6
---

On this Windows + Git Bash setup, permission matching is **string/prefix-based on the normalized path**, NOT filesystem-identity-based — so different spellings of "the same" folder are treated as different folders and can trigger approval prompts even when the folder is whitelisted.

Three spellings of `C:\tmp`:
- `C:\tmp` (Windows form) — what Read/Edit/Write tools emit on win32 (`platform: win32`).
- `/c/tmp` — Git Bash MSYS drive-mount; a **true alias** of `C:\tmp`.
- `/tmp` — **FALSE FRIEND**: MSYS *virtual* mount, a genuinely different physical location (≈ `%LOCALAPPDATA%\Temp` / Git install tmp), NOT `C:\tmp`. Do **not** auto-approve `/tmp/**`.

Fix applied (2026-06-19): for every non-HOME entry in `additional_directories`, added auto-approve in BOTH `C:/...` and `/c/...` forms — in `permissions.yaml file_access.allow` AND, after sync, as `Read()/Edit()/Write()` rules plus `/c/...` entries in `additionalDirectories` in `settings.json`. `/tmp` deliberately excluded.

Rule of thumb: when adding a directory permission, add both the Windows form and the `/c/...` Git-Bash drive-mount form; skip the MSYS `/tmp`. See [[reference-permissions-sync]].
