---
name: project-skill-description-trim-2026-08-01
description: "Item 7 of ReducePromptCost done 2026-08-01 — 42 skill descriptions trimmed, ~3,735 tok cut; floor is ~130 not 90"
metadata: 
  node_type: memory
  type: project
  originSessionId: 1e74b2d6-4efb-4b7b-a2c9-3ef77423c33c
  modified: 2026-08-01T21:27:58.497Z
---

Trimmed 42 fat `description:` fields in `~/.claude/skills/*/SKILL.md` on 2026-08-01
(item 7 of [[reference_prompt_cost_analysis]]). Corpus went **17,641 → 13,906 tokens
(−3,735, −21%)**; over-120 count 57 → 32.

**Why:** always-loaded descriptions are re-read on every turn of every session — the only
unconditional token win available.

**How to apply:**
- Measure with `~/.claude/scripts/desc-inventory.ps1`. The older `context-inventory.ps1`
  counts the **whole frontmatter block** (name, fences, folding markers), so it overstates
  by ~1,500 tokens corpus-wide. Use the `description:`-only figure.
- **~130 tokens is the honest floor for a mega-skill, not 90.** A long description is a
  dense list of distinct trigger nouns; cutting further removes trigger surface and a skill
  that stops firing costs far more than the ~30 tokens saved. Set any regression gate at
  140.
- Cut scaffolding, not triggers: parenthetical implementation notes, repeated
  "understanding the… / working on the…" clause openers, type enumerations already in the
  body, and cross-reference sentences. `crewchief-web-ui` went 427 → 107 with every trigger
  noun intact.
- Skills junction to `03 Shared/work-ai/skills/` in the work vault — edits land there, and
  that syncs via Obsidian, not git ([[reference_workai_sync]]).
- Edits reload live for activation, but the token saving needs a `/clear`
  ([[reference_skill_override_two_speeds]]).
