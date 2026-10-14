---
name: reference-sessionend-hook-1-5s-budget
description: "Claude Code runs SessionEnd hooks with a hard 1.5s per-hook default timeout; the remember plugin hook needs its own `timeout` AND a settings-level SessionEnd hook timeout, or exit prints \"Hook cancelled\""
metadata:
  node_type: memory
  type: reference
  originSessionId: e07aa899-df83-4386-b7cc-e7fc859af50d
  modified: 2026-09-07T02:00:40.962Z
---

Verified 2026-09-06 (Claude Code 2.1.263) by reading the binary AND by headless `claude -p` probes from a scratch dir.

**Two independent 1.5-second limits apply to every SessionEnd hook:**

1. **Per-hook timeout.** The SessionEnd runner calls the hook batch with `timeoutMs: 1500` (a constant), and each
   command hook gets `hook.timeout ? hook.timeout*1000 : timeoutMs`. So a SessionEnd hook without its own `timeout`
   field is aborted at 1.5 s no matter what settings say. Abort = `ABORT_ERR` = the message
   `SessionEnd hook [...] failed: Hook cancelled`.
2. **Outer abort budget** (`getSessionEndHookTimeoutMs`): `CLAUDE_CODE_SESSIONEND_HOOKS_TIMEOUT_MS` if set, else the
   max `timeout` over **settings** SessionEnd hooks (`initialHooksConfig`, snapshotted at session start), clamped to
   [1500, 60000] ms. Plugin hook timeouts do NOT feed this.

Both must be raised. Probe matrix (`claude -p "ok"` from a scratch dir, stderr captured):

| settings extender (timeout 15) | plugin hook `timeout: 15` | result |
| --- | --- | --- |
| yes | no | Hook cancelled |
| no | yes | Hook cancelled |
| yes | yes | clean exit |

**Why the remember plugin trips it:** `session-end-hook.sh` sources resolve-paths/detect-tools/bootstrap-dirs/log.sh,
which alone measure 1.34–1.48 s on this Windows box (MSYS fork cost), and reaches its backgrounded flush at ~2.5–3 s.
The plugin's hooks.json declares no `timeout` (its comments assume a 60 s kill). The kill usually only takes the
outer wrapper and the flush still lands, but one run (2026-09-05 20:39) lost the flush with
`FATAL: PROJECT_DIR does not exist: :\devops\myworkspace` when the kill hit a `tr` fork mid-path-normalisation.

**Fix in place (2026-09-06):**
- `~/.claude/settings.json` SessionEnd: no-op bash hook `: session-end-budget-extender # ...` with `"timeout": 15`
  (raises limit 2). Keep the comment free of `(` `)` `;` — bash parses the `:` builtin's arguments; a `#` comment is safe.
- `~/.claude/plugins/cache/claude-plugins-official/remember/<ver>/hooks/hooks.json` SessionEnd hook gets `"timeout": 15`
  (raises limit 1). This file is replaced on every plugin update, so
- `~/.claude/scripts/remember-hook-timeout.ps1` (SessionStart via `hook-dispatch.ps1 -Id remember-hook-timeout`)
  re-applies it to whatever `installed_plugins.json` `installPath` currently points at. Idempotent, stderr-only,
  env override `CLAUDE_PLUGINS_DIR` for tests; 5 cases in `scripts/tests/run-hook-tests.ps1`.
- Settings hooks cannot replace a plugin hook: dedup keys on `pluginRoot + command`, so a same-command settings hook
  is a second hook, not an override. There is no per-plugin-hook disable in 2.1.263 (no `disabledHooks` key,
  no `CLAUDE_DISABLED_HOOKS` in the binary — that env var is only the user's own `hook-dispatch.ps1` switch).

**Upstream:** the durable fix is the remember plugin declaring `timeout` on its SessionEnd hook. Not filed as of
2026-09-06. Exit latency stays = real hook duration (~3 s), not the timeout.

**How to apply:** any SessionEnd hook slower than 1.5 s needs BOTH knobs. Confirm a flush completed via
`~/.remember/<slug>/logs/autonomous/session-end-*.log` and `logs/hook-errors.log`. Reproduce/verify with a
`claude -p` probe from a throwaway dir (creates a throwaway `~/.remember/<slug>` store — delete it after).
See [[reference-claude-hook-activation]].
