---
name: project-test-loop-autoapprove-hook
description: PreToolUse hook that lets the integration-test fix loop run unattended without bypassing all permissions
metadata: 
  node_type: memory
  type: project
  originSessionId: 5791e5d5-c59f-45ed-a506-a1801e43ba45
---

To let the `skill-fix-integration-tests` loop run autonomously without a blanket `--dangerously-skip-permissions`, a scoped PreToolUse hook auto-approves ONLY the loop's maintenance commands.

- **Script**: `C:\Users\agenewe\.claude\scripts\test-loop-autoapprove.ps1`
- **Registered**: `~/.claude/settings.json` → `hooks.PreToolUse`, matcher `"Bash|PowerShell"` (separate entry from the `git-commit-block` Bash hook).
- **Approves** (anchored, target-scoped): `taskkill`/`kill`/`Stop-Process` of `testhost`/`vstest.console`; `mkdir`/`New-Item` of `TestResults`; `Remove-Item`/`rm` under a `\tmp\` or `/tmp/` segment; `Start-Sleep`. Emits `{hookSpecificOutput.permissionDecision: "allow"}`.
- **Chain guard**: refuses to approve any command containing `;  |  &  \`` , newline, or `$(` — so a destructive statement can't ride along on an approved one. Everything unmatched falls through to the normal prompt.

**Why:** `PowerShell(*)` already auto-approves all PowerShell-tool calls; the loop's prompts came from the **Bash-tool** path where `taskkill`/`kill`/`mkdir` sit in the global `ask` list (and `Stop-Process`/`Remove-Item` are unlisted). A PreToolUse `allow` decision is the only way to clear those without *removing* them from `ask` and weakening every other session.

**How to apply:** This is Claude-Code-only — it lives in settings.json, NOT in `~/ai/permissions/permissions.yaml` (the yaml has no hooks section and syncs to other clients that don't share this hook). To broaden the loop's approved commands, edit the `$approved` regex array in the script; keep each pattern anchored + target-scoped. Related: [[reference_permissions_sync]], [[feedback_no_commits]] (the sibling git-commit-block hook).
