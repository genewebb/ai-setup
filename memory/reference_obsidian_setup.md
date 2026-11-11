---
name: reference-obsidian-setup
description: "Gene's Obsidian vaults use Obsidian Sync (both vaults) + File Recovery; obsidian-git installed in work vault but unused"
metadata:
  node_type: memory
  type: reference
  originSessionId: ea72170f-7282-4a20-b149-8147dc8bb36e
  modified: 2026-11-11T15:27:14.336Z
---

- Vaults: Q:\Work\Work (work, AI-integrated: Local REST API, Claude Code IDE, Dataview, Tasks, Templater, QuickAdd) and Q:\Personal\MyPersonalVault (personal, formatting plugins only).
- Obsidian Sync core plugin enabled in BOTH vaults (Gene confirmed 2026-11-11); File Recovery core plugin also on.
- obsidian-git installed in work vault but no .git at vault root, so it is dead weight next to Sync.
- obsidian MCP = Local REST API plugin's /mcp/ endpoint (4.1.1 on 2026-11-11). 5.x is breaking: new PATCH engine (markdown-patch 2.x), periodic_note_get_path + /periodic/ endpoints REMOVED. Retest vault memory writes after any 5.x upgrade.
- 2026-11-11 upgraded to 5.5.2; verified write / heading append / frontmatter replace / delete via MCP. Quirk: heading append adds a blank line, so appending '- x' under a list starts a NEW list; use `within: -1` + content '\n- x' to extend the existing list. No skills or vault memory contract referenced periodic notes.
- 2026-11-11 compared Obsidian vs Trilium: verdict stay on Obsidian (plain .md files feed agents, obsidian MCP, Qdrant index, 03 Shared\Memory).
