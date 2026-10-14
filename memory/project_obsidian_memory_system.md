---
name: project_obsidian_memory_system
description: "MyWorkVault memory system at 03 Shared\\Memory - INSTALLED 2026-08-01; no version control in the vaults, two-account Obsidian gotcha, credential guard"
metadata: 
  node_type: memory
  type: project
  originSessionId: 54748f03-d49a-450f-9db1-1de5549ec592
  modified: 2026-08-01T23:18:35.584Z
---

Durable-memory system for Claude Code, **installed 2026-08-01** at
`C:\devopslocal\ObsidianVaults\Work\MyWorkVault\03 Shared\Memory`. Self-contained:
own `.claude\` (settings + `hooks\Protect-Vault.ps1` + 4 skills), `Templates\`,
`tools\Test-VaultHealth.ps1`, `CLAUDE.md`, and
`Drafts/Sessions/Decisions/Knowledge/Indexes`. Spec: `03 Shared\AICosts\ClaudeObsidian.md`.

## No version control in the Obsidian vaults

**Nothing under `C:\devopslocal\ObsidianVaults` is tracked or checked in** (user, 2026-08-01).
Do not run Git commands there - not even `status`/`diff`/`log`. Do not report vault changes
as a diff; list file paths. Do not create or maintain a `.gitignore`.

`MyWorkVault\.git` is a dormant artefact: 2 commits, both 2026-05-25 "vault backup: …",
no remote, nothing since. Personal vault is not a repo at all. Durability = Obsidian Sync
plus File Recovery, so prefer creating new files over modifying existing ones.

Corrected overstatement: the 2026-05-25 commit does contain `00 Credentials`, but with no
remote and no clones that adds no exposure beyond the plaintext files already on disk.
Don't repeat "the credentials are in git history" as a finding.

## Two Windows accounts — the thing that bites

`CORP\agenewe` (Claude Code, your shell) and `CORP\genewe` are **both real accounts**
on this box, each with a real profile. `C:\Users\genewe` is NOT a typo for `agenewe`.

Obsidian runs as `CORP\genewe`, from agenewe's binary, reading genewe's
`AppData\Roaming\obsidian\obsidian.json`, publishing pipe `\\.\pipe\obsidian-cli-genewe`.

Consequence: **the Obsidian CLI can never work from a Claude Code session.** The CLI as
`agenewe` looks for `obsidian-cli-agenewe` and prints the misleading "The CLI is unable to
find Obsidian. Please make sure Obsidian is running" — while Obsidian *is* running. Account
boundary, not PATH. Don't debug it. Nothing in the memory system depends on the CLI.

## Credential guard

`00 Credentials\` is plaintext Markdown - the vault's real private area, not a `98-Private`.
Verified working: 10 absolute-path deny rules (both `C:\` and `/c/` forms) in
`~\.claude\settings.json` block `Glob`/`Read` from a `C:\devops\myworkspace` session,
**live, no restart**. Deny outranks the broad `Edit(...MyWorkVault\**)` allow already there.

Unclosed: Local REST API verified listening on `127.0.0.1:27124`, owned by the genewe-run
Obsidian, reads the whole vault outside Claude Code's permission layer.

## Two hook rules learned

- A `PreToolUse` path guard must scan **path fields only**, never `new_string`/`content`.
  Otherwise writing the literal text `00 Credentials\**` into settings.json blocks its own
  installation. Permanent regression test: `AllowedEditMentioningCreds` must exit 0.
- Matcher needs `PowerShell` and `mcp__filesystem__.*|mcp__obsidian__.*`; `Bash`-only is
  bypassed by this harness's separate PowerShell tool. 9/9 hook cases pass.
- `(^|[\\/])credentials?([\\/]|$)` does NOT match `00 Credentials` (space precedes, not a
  slash). Use `(^|[\\/])[^\\/]*credential[^\\/]*([\\/]|$)`.

See [[reference_path_form_gotcha]] for the dual `C:\` + `/c/` requirement and
[[reference_permission_tier_precedence]] for deny/ask/allow ordering.
Related: [[project_doc_location]], [[reference_workai_sync]]
