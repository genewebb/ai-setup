---
name: reference_write_vaultfile_large_put_times_out
description: Write-VaultFile.ps1 throws TaskCanceledException on a ~68 KB PUT (30 s timeout) but the Obsidian REST API has already written the file — verify by SHA-256 + vault_get_document_map, do not retry blindly
metadata:
  type: reference
---

2026-09-17 20:15: `Write-VaultFile.ps1 -VaultPath ... -Source ...` on a 68,766-byte markdown file failed with
`Obsidian REST API write of ... failed (TaskCanceledException); nothing written` — yet the file on Q: had the new
content and matched the scratch file's SHA-256, and `mcp__obsidian__vault_get_document_map` showed the new headings.
The 30 s `Invoke-RestMethod -TimeoutSec 30` gave up waiting for the response; the write itself succeeded.

**How to apply:** after a TaskCanceledException, hash-compare vault file vs source and check the document map before
retrying. A retry would be harmless (same bytes) but the "nothing written" message is wrong for this case. Related:
[[reference_obsidian_smb_vault_watcher_blind]].
