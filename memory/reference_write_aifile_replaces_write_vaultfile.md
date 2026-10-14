---
name: reference-write-aifile-replaces-write-vaultfile
description: "Write-VaultFile.ps1 is RETIRED; every vault/AIWork write goes through {ClaudeHome}\\bin\\Write-AIFile.ps1 -Path -Source (routes by profile Resources table, hash-verified, no direct fallback)"
metadata:
  node_type: memory
  type: reference
  originSessionId: e071532a-95ca-4f16-ae81-7a5cb0301769
  modified: 2026-10-01T12:54:29.829Z
---

Use `pwsh "$HOME\.claude\bin\Write-AIFile.ps1" -Path <absolute dest> -Source <local file>` (module form: `Write-AIFile -Path -Source|-Text` from `~\.claude\lib\AIFile.psm1`).

- Route comes from the profile `## Resources` table: inside a vault = Obsidian REST API PUT (bearer from the obsidian MCP entry in `~\.claude.json`); otherwise direct atomic write. Both hash-verified.
- API down = write STOPS; never falls back to SMB.
- Large PUT timeouts are fine: the hash decides, not the HTTP result.
- Deletes: the API deletes files only (`DELETE /vault/<path>`); empty folders are left behind and must be removed separately.

Supersedes [[reference-obsidian-smb-vault-watcher-blind]] (Write-VaultFile wording). Related: [[project-machine-config-laptop-live-2026-10-01]].
