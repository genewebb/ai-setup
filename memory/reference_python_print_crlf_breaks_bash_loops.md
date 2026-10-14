---
name: reference-python-print-crlf-breaks-bash-loops
description: Windows python print() emits CRLF; a bash `for f in $(python ...)` loop gets a trailing CR on every name except the last, so every file op silently misses
metadata:
  type: reference
---

On this box `python -c "print('\n'.join(paths))"` writes CRLF. Captured into a bash list, each item ends in `\r` except the last, so `Write-VaultFile.ps1 -VaultPath ".../$f"` and `[ -f "$V" ]` all fail while the LAST file succeeds — looks like a flaky share/lag. Seen 2026-09-21 pushing release r3 (21 of 22 "FAIL").

**Fix:** pipe through `tr -d '\r'` (or write the list to a file and `tr -d '\r'` it) before looping. Related: [[reference-backslash-escapes-become-control-bytes]].
