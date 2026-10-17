---
name: reference_permissionrequest_hook_scoped_autoapprove_2026-10-17
description: "Why stream units kept prompting (auto mode drops Bash(*); ask rules beat a PreToolUse allow) and the fix, the PermissionRequest hook scoped-autoapprove.ps1 (answers yes + logs for work inside repo/scratch/profile access rows; out-of-scope and kill-by-name still prompt)"
metadata:
  node_type: memory
  type: reference
  originSessionId: 3754e77a-a9e8-42e9-b3f4-cd17c62e480c
  modified: 2026-10-17T19:15:32.403Z
---

**Facts (Claude Code docs, checked by a docs agent 2026-10-17):**
- Rules evaluate deny, then ask, then allow. A `PreToolUse` hook `allow` does NOT override an ask or deny rule
  ([[reference_permission_tier_precedence]]). That is why every earlier "pre-approve" attempt for the stream
  builders/authors changed nothing.
- Auto mode drops broad allow rules (`Bash(*)`, `PowerShell(*)`) while active
  ([[reference_auto_mode_setup_stripped_bash_wildcard]]). `-Live` units run under the auto-mode classifier even
  with `--permission-mode bypassPermissions` on the line (Remote Control + bypass interaction is undocumented).
- The `PermissionRequest` hook event fires when a prompt WOULD open; its output
  `{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}` answers it.
  In `-p` with `--permission-prompts none` it is the ONLY way to allow. `Monitor` is a valid matcher.
- No API answers a dialog already drawn: the "wait 5 minutes then approve" idea cannot be built; the hook makes
  in-scope prompts never appear instead.

**What was built (ai-setup corpus, published 2026-10-17):**
- `claude\scripts\lib\PathScope.ps1`: one shared scope (`Get-ScopeRoots -ForApproval`, token extraction, cmd-family
  switch stripping incl. `taskkill /PID`, `//FI` Git Bash form, heredoc bodies are data). `destructive-path-guard.ps1`
  dot-sources it so both hooks draw the same line.
- `claude\scripts\scoped-autoapprove.ps1` (PermissionRequest, matcher Bash|PowerShell|Monitor|Read|Edit|Write|
  MultiEdit|NotebookEdit|Glob|Grep): allows when cwd is inside the roots AND every absolute token is inside AND the
  command is not on the never-list (sudo, netsh, icacls, schtasks, reg, shutdown, docker down/rm/prune, taskkill
  /im|/fi, Stop-Process -Name, pkill, kill $(pgrep ...). Kill by PID is allowed. Logs every yes to
  `{ScratchRoot}\ai-config-work\autoapprove\<yyyyMMdd>.log` (env `CLAUDE_AUTOAPPROVE_LOG_DIR`) and to
  `<STREAM_UNIT_OUT>.approvals.log`; the runner prints `APPROVED <n> ... -> <log>` after the unit's EXIT line.
- Registered in `claude\settings.template.json` (renders into settings.json by `install.ps1`; never hand-edit).
- Tests: `claude\scripts\tests\run-hook-tests.ps1` `# --- scoped-autoapprove` section.

**How to apply:** a prompt that still appears is by design out of scope (path outside every root, machine-wide or
by-name kill, UNC, hosts file). Check the day log before widening; widen by adding a `## Claude access` row to
the machine profile, not by editing the hook. Policy: [[feedback_agents_control_repo_scratch_access_rows]].
