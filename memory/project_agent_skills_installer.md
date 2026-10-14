---
name: project-agent-skills-installer
description: "Second skill system (.agents\\skills + .skill-lock.json from the `skills` CLI) vs the work-ai linker; user consolidates installed skills into work-ai"
metadata: 
  node_type: memory
  type: project
  originSessionId: 67602b2e-03fe-414a-aa32-25d7a24793c9
---

There are TWO skill systems feeding the Claude Code read location `C:\Users\agenewe\AI\skills` (= `~/.claude/skills`):

1. **work-ai linker** (the managed one — see [[ai-repo-management]] / project_repos): source in `...\work-ai\skills\<name>`, junctioned by `link-to-ai.ps1` (`mklink /J`).
2. **`skills` CLI installer**: pulls skills from GitHub (e.g. `mattpocock/skills`, `vercel-labs/skills`) into `C:\Users\agenewe\.agents\skills\<name>`, tracked in `C:\Users\agenewe\.agents\.skill-lock.json` (repo, skillPath, skillFolderHash, cross-agent `lastSelectedAgents`). It junctions only the skills it installs; older unlinked folders also sit in `.agents\skills`.

**User preference (2026-06-11):** does NOT use the `skills` installer for sync/update. When installed skills appear in `.agents\skills`, consolidate them into the work-ai linker system. Migration steps: copy `.agents\skills\<name>` → `work-ai\skills\<name>`; add name to `link-to-ai.ps1` `$skills`; delete the old read-location junction (`cmd /c rmdir`) because the linker skips when target EXISTS; re-run linker so junctions point to work-ai; verify; then remove the `.agents` copy and prune its `.skill-lock.json` entry.

**Gotcha:** skills with `disable-model-invocation: true` in frontmatter (e.g. `teach`, `zoom-out`) are intentionally hidden from the model-invocable skill list — they only run as user slash commands. Their absence from the loaded list is by design, NOT a broken install.

**Why:** keeps every skill under one version-tracked, Obsidian-synced system instead of a separate installer that drifts from upstream and syncs to 14 other agents.
**How to apply:** when the user adds/installs new skills, check `.agents\skills` creation times + `.skill-lock.json`, then migrate into work-ai unless told otherwise.
