---
name: permissions-yaml
description: >
  Claude Code permission management via {AIWorkRoot}\claude\permissions.yaml, the one shared source for
  permissions.allow / ask / deny in the generated settings.json. Use when adding auto-approve commands,
  updating command permissions (allow/ask/deny), approving MCP tools, or moving a hand-approved rule into
  the source. Triggers on "add to auto-approve", "update permissions", "allow command", "deny command".
---

# Permissions YAML Management

`{AIWorkRoot}\claude\permissions.yaml` holds the Claude Code rules shared by every machine. The installer
renders it, together with the machine profile's `## Claude access` table, into `{ClaudeHome}\settings.json`.

- **Never hand-edit `settings.json`.** It is generated; a hand edit is drift and the next apply stops (exit 3).
- **Machine paths do not go here.** A folder this machine may read or edit belongs in the profile's
  `## Claude access` table (`ProfileMachineConfig.md`; `/machine-config show` prints its path), not in this file.
- Other clients (VS Code, Cursor, OpenCode, Copilot) are retired; there is nothing to sync to them.

## Structure

```yaml
allow:   # auto-approved
- Bash(git status:*)
- mcp__memory
ask:     # prompts
- Bash(docker compose down:*)
deny:    # always blocked
- Edit({VaultWorkRoot}\00 Credentials\**)
```

Rules are written in Claude Code's own rule syntax. `{Key}` is a machine path from the profile:

- in `Read` / `Edit` / `Write` rules it renders as `//c/...`;
- in `Bash` / `PowerShell` rules it renders literally, once with `\` and once with `/`;
- a rule whose `{Key}` is blank on a machine is skipped (a skipped deny is reported).

One owner per rule: never put the same pattern in two tiers.

## Workflow: add or change a rule

1. Read `{AIWorkRoot}\claude\permissions.yaml` and find the tier.
2. Add the rule near related ones; keep comments and order. Use `{Key}` for any machine path.
3. Write the file through `pwsh "{ClaudeHome}\bin\Write-AIFile.ps1" -Path <file> -Source <edited copy>`.
4. Run `/machine-config apply` (or `Install-AIMachine.ps1`). It regenerates `settings.json` and reports which
   changes need a fresh launch.
5. Verify: the rule is in `{ClaudeHome}\settings.json` under the expected tier.

## Workflow: a rule approved in a session

Approving a prompt ("always allow") writes into `settings.json` or a repo's `.claude\settings.local.json`.
Those rules are harvested into this file, not kept where they landed:

```powershell
pwsh "{ClaudeHome}\bin\Invoke-AIHarvest.ps1" -Action propose          # list open rules, with their {Key} form
pwsh "{ClaudeHome}\bin\Invoke-AIHarvest.ps1" -Action accept -Id <n>   # add to permissions.yaml
pwsh "{ClaudeHome}\bin\Invoke-AIHarvest.ps1" -Action reject -Id <n>
pwsh "{ClaudeHome}\bin\Invoke-AIHarvest.ps1" -Action finalize         # after apply: remove the originals
```

`/machine-config harvest` runs the same steps.

## Rules

- **Prefer narrow patterns.** `Bash(git fetch:*)`, not `Bash(git:*)`.
- **Anchor short command prefixes.** A bare prefix like `fd` also matches `fdisk`.
- **A deny beats an allow.** If an allow conflicts with an existing deny, the harvest reports it as a conflict
  instead of adding it.
