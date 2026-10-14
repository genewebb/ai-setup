---
name: reference_uipro_skill_pack_vault_install
description: "UI/UX Pro Max (npm ui-ux-pro-max-cli 2.15.0, MIT) installed 2026-09-14 as 7 vault-backed skills; upstream `design` renamed `uipro-design` to avoid the built-in design-canvas skill; `uipro update` does NOT apply"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 36fb0eef-6e00-4263-8243-c6afdfbf3c20
  modified: 2026-09-14T15:05:39.803Z
---

`uipro init --ai claude` writes 7 skills (172 files) into `<cwd>\.claude\skills`: ui-ux-pro-max, design, design-system, ui-styling, brand, banner-design, slides. `--global` would drop them NATIVE into `~\.claude\skills`, which breaks the vault-first rule ([[ai-repo-management]]), so they were staged in a scratch folder and pushed into `Q:\Work\Work\03 Shared\work-ai\skills\` via `Write-VaultFile.ps1` (REST API, hash-verified), registered in `link-to-ai.ps1` (comment block records the rename + update steps), linked, README regenerated.

**Rename:** upstream `design` -> `uipro-design` (folder, `name:`, every `skills/design/` script path in 5 files, the "Activate the `design` skill" line in references\slides.md). Nothing outside that folder referenced it by name.

**Why:** `design` collides with Claude Code's built-in `design` (design canvas) skill; which one wins is undocumented.

**How to apply:** to update, never run `uipro update` / `uipro init --global` (it would write NATIVE folders and lose the rename). Re-run `uipro init --ai claude` in an empty scratch folder, re-apply the rename, push over the vault folders, `-Check` the README. CLI itself is installed globally via npm (no install scripts; deps chalk/commander/ora/prompts). uipro-design logo/icon/CIP generators call Gemini and need Python.
