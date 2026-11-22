---
name: reference_obsidian_smb_vault_watcher_blind
description: "Files written to the Q: vault by filesystem do not appear in Obsidian until restart — SMB defeats the watcher; write via the Local REST API MCP, but PROBE it first, it drops after app:reload"
metadata: 
  node_type: memory
  type: reference
  originSessionId: dab7e805-1f7d-4599-a8f9-7e54417973f7
  modified: 2026-09-12T14:17:51.135Z
---

**Symptom (Gene, 2026-09-12 09:56):** documents added to the Obsidian vault "don't show up until I
close and open it again."

**Cause, verified in session.** `Q:` is `DriveType 4` — a network drive, SMB to the SynologyDS918
`obsidian` share. Obsidian's file watcher is Electron `fs.watch`, which on Windows is
`ReadDirectoryChangesW`, and that API is **not reliable over SMB**: the change happens on the
Synology and the notification frequently never reaches the Windows client. The file is genuinely on
disk — an API `vault_list` reads it straight back — while Obsidian's in-memory index has never heard
of it. Restarting rebuilds the index from disk, which is why close-and-reopen appears to "fix" it.

**Nothing is lost. The index is blind to writes it did not make.**

### The fix — write THROUGH Obsidian, not around it

Use `mcp__obsidian__vault_write` / `vault_append` / `vault_patch` instead of the Write tool or shell
redirection. They call the Local REST API plugin, which goes through Obsidian's own vault layer, so
the index updates synchronously. Paths are **relative to vault root** (e.g.
`99 Documentation/speedy/Foo.md`); the server is confirmed pointed at the `Q:\Work\Work` vault.

**PROBE FIRST — the API goes down after `app:reload` (bitten 2026-09-12 10:35).** After I fired
`app:reload` at 09:58, a `vault_write` at 10:35 failed `Unable to connect`. The plugin does not
reliably come back with the reload. Call `vault_list` before a write; if it fails, fall back to a
filesystem write and tell Gene the index will not see a NEW file until he reloads (a MODIFIED file is
already indexed and is re-read on open).

### For files already written by filesystem

`app:reload` ("Reload app without saving") is registered and can be fired with
`mcp__obsidian__command_execute`. **Ask first** — it drops unsaved workspace state and interrupts
what Gene has open; note content autosaves. And expect the REST API to need a moment (or a manual
plugin toggle) afterwards.

### Exception

HTML and other non-markdown assets (e.g. the `speedy\ui\` mockup folder) are not indexed or rendered
by Obsidian anyway, so plain filesystem writes there are fine.

Related: [[reference_nas_drive_letters_stale_after_reboot]], [[project_obsidian_memory_system]],
[[project_speedy_guiding_document_2026-09-12]].


**2026-09-13 20:13 — every vault write goes through the Obsidian Local REST API**, never a direct file write, even when the obsidian MCP is down: `myloop\scripts\Write-VaultFile.ps1 -Paths <files>` (or `-VaultPath <rel> -Source <scratch file>`) PUTs the bytes with the bearer key read from `~/.claude.json`. Applies to docs, mockups, plans AND the skill folders under `03 Shared\work-ai`.
