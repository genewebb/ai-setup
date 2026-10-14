---
name: reference-permissions-sync
description: How AI-tool permissions are managed and synced — canonical permissions.yaml + AI-driven sync (no script)
metadata: 
  node_type: memory
  type: reference
  originSessionId: c97a32c0-251f-44df-9bc4-96487dc452d6
  modified: 2026-07-30T13:20:31.621Z
---

Permission management for all the user's AI clients is centralized in a **canonical** file: `C:\Users\agenewe\ai\permissions\permissions.yaml` (loaded via the `permissions-yaml` skill).

**There is NO sync script.** "Sync" = the agent translates `permissions.yaml` into each client's native config file. Triggered by phrases:
- "sync permissions to Claude Code" → write `~/.claude/settings.json` only
- "sync permissions to all clients" → also Copilot (`%APPDATA%/Code/User/mcp.json` + `settings.json`), OpenCode (`~/.config/opencode/opencode.json`), Cline, Kilo

Golden rule: **edit `permissions.yaml` first (source of truth), THEN sync.** Never hand-edit a client config directly — the next sync overwrites it.

Mapping into Claude Code `settings.json`:
- `commands.allow/ask/deny` glob `P` → `Bash(<P minus trailing *>:*)` in `permissions.{allow,ask,deny}`. Broad prefix rules subsume narrower ones (e.g. `Bash(git -C:*)` covers all `git -C * <subcmd>`; `Bash(pwsh:*)`/`Bash(powershell:*)` cover all `pwsh*X`/`powershell*X`).
- `mcp_servers.<name>` → bare `mcp__<name>` allow entry.
- `file_access.allow` path → `Read()`/`Edit()`/`Write()` allow entries (this client has NO blanket `Read(HOME/**)`, so HOME-relative dirs still need explicit entries).
- `additional_directories` → `permissions.additionalDirectories` (workspace boundary, separate from the allow dialog).

`settings.json` is read at **session start**, not live — changes apply to new sessions; reload/restart to apply mid-session. See [[reference-path-form-gotcha]] for why entries need both Windows and `/c/` forms.

## Claude-Code-only "allow-all-unless-destructive" policy (2026-07-30)

User policy: **allow all Bash + Python (they run through the shell) unless destructive or system-touching.**
Applied to **Claude Code `~/.claude/settings.json` ONLY** — deliberately NOT canonical/VS Code, because VS Code
has no ask tier and a blanket allow there overrides every guard (the `/^docker/` failure the skill warns of).
- `allow`: added `Bash(*)` + `PowerShell(*)` floor; removed the `Bash(git -C:*)` and `GIT_SEQUENCE_EDITOR` blanket allows.
- `deny` (hard, all user-chosen): state-changing git (push/commit/reset --hard/rebase/merge, plain + `-C` + PowerShell forms), registry WRITES (`reg add/delete/…`, `regedit`, PS `*-Path HK*`), service/account mutation (`sc delete/config/create`, `net user`, `schtasks /create|delete|change`, PS `*-Service`/`*-LocalUser`/`*-LocalGroupMember`/`*-ScheduledTask`), and PowerShell mirrors of the 11 physical-destruction denies (`Stop/Restart-Computer`, `Format-Volume`, `Clear-Disk`, `Remove-Partition`, raw `shutdown`/`diskpart`/`format`…). Counts after: allow 385 / ask 79 / deny 84.
- `ask`: recoverable (`rm -rf`, `icacls /grant|deny`, `takeown`, PS `Remove-Item -Recurse`, firewall cmdlets, `Stop/Restart-Service`).
- Registry **reads** stay allowed (`reg query`, `Get-ItemProperty HK…`).

**Two caveats that matter:**
1. **Fragile against re-sync** — a canonical→Claude sync regenerates `settings.json` and silently wipes this. Re-apply after any sync, or move to canonical (reopens the VS Code problem).
2. **Denylist-over-a-shell leaks** — composition (`bash -lc "…"`, `eval`, `$(…)`, mid-var paths) bypasses prefix-matched denies. The standing instructions (never state-changing git; confirm destructive actions) are the real guarantee; patterns are defense-in-depth.

The drift checker exits 0 because it only flags **contradictions**, never **extras** — so it does NOT detect this intentional Claude-Code-vs-canonical divergence. Transform scripts + a pre-change backup live in the session scratchpad (`permbak-*`).
