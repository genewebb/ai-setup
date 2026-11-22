---
name: reference-hook-tests-inherit-disabled-hooks-env
description: "A hook silenced for the session ($env:CLAUDE_DISABLED_HOOKS) also silences it inside run-hook-tests.ps1, so cases fail for the wrong reason"
metadata: 
  node_type: memory
  type: reference
  originSessionId: d539ad38-f356-499c-a3ac-6db5ea446494
  modified: 2026-09-29T03:42:00.887Z
---

`run-hook-tests.ps1` launches each case as a child `pwsh`, which inherits this process's environment. If the session has `$env:CLAUDE_DISABLED_HOOKS = 'gateguard'` set (process scope only — it is not in `settings.json`, User or Machine scope), `hook-dispatch.ps1` exits 0 before dot-sourcing the hook, the case sees empty stdout, and it fails as though the hook were broken. Observed 2026-09-28: `dispatch: disable-file matches whole tokens only` failed while the same hook denied correctly when run directly.

**Why:** the dispatcher's kill switch is honoured by the dispatcher, not by the hook script, so a direct run of the hook still fires and the two disagree. The symptom is an empty hook output, which is indistinguishable from "hook decided to stay silent".

**How to apply:** `Test-Hook` now clears `CLAUDE_DISABLED_HOOKS` for every case and a case's own `-Env` still wins — keep that isolation when adding switches. When a hook test fails with empty output, check `$env:CLAUDE_DISABLED_HOOKS` and the mid-session file `~\.claude\hooks-disabled.txt` before reading any hook code. Related: [[reference-destructive-path-guard-short-name-root]].
