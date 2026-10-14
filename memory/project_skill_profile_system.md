---
name: project_skill_profile_system
description: Skill-profile system for work-ai — Set-SkillProfile.ps1 + shared skill-taxonomy.ps1 keep the skill listing under its ~10k context budget
metadata: 
  node_type: memory
  type: project
  originSessionId: 48036b6c-03b5-4821-aa20-ae5dbe200171
  modified: 2026-08-01T19:37:41.222Z
---

Built 2026-08-01. The skill listing (every enabled skill's name + description,
rendered into every session's system prompt) is budgeted at ~1% of the context
window — ~10,000 tokens on a 1M model. All 141 skills enabled measured **~18,000
est. tokens**, so descriptions were being silently truncated and skill routing
degraded.

**Files** (all in `work-ai\`):

| File | Role |
|---|---|
| `skill-taxonomy.ps1` | The ONE category definition — `$CategoryOrder`, `$PrefixMap`, `$Overrides`, `$CategoryAlias`, `Get-SkillCategory`, `Resolve-CategoryName` |
| `Set-SkillProfile.ps1` | `-Status -Catalog -Set -Apply -Reset -Worksheet -Budget` |
| `Overview\Generate-SkillsReadme.ps1` | Now dot-sources the taxonomy instead of inlining it |
| `skills\skill-profile\SKILL.md` | Operating manual, ~84 tok resident |

**Docs** live in `03 Shared\optimization\`: `Skill Profiles - How To Use.md`
(operator guide) and `Skill Profiles - Design.md` (decisions + evidence).

**Category sizes**: TestAuto 68/9,149 · CrewChief 20/3,689 · Harness 17/1,569 ·
AI-Authoring 11/1,218 · .NET 10/974 · General 7/488 · Profisee 4/557 · Blazor
2/295 · TestData 1/188. All on = ~18,100.

`-Set crewchief,harness,general` → 5,830, under budget. Every profile also carries
`skill-profile` (84 tok) since it cannot disable itself. **`-Set testauto` alone
is 9,149** — TestAuto work needs per-task selection (`-Catalog` then `-Apply`),
not a category switch.

**Gotchas**
- `pwsh -File` does NOT bind arrays: `-Set a,b,c` arrives as one string. The
  script splits on commas itself — do not "fix" callers passing a bare list.
- PowerShell `-contains`/`-eq` are case-insensitive, so `Resolve-CategoryName`
  must return the canonical list's spelling, never the caller's input.
- A new skill without a known prefix lands in **General** until it gets a line in
  `$Overrides`. One map only.
- Regression proof for the taxonomy extraction: `Generate-SkillsReadme.ps1 -Check`
  exit 0 + byte-identical README.

See [[reference_skill_override_two_speeds]], [[project_agent_skills_installer]],
[[reference_workai_overview_readme_generated]], [[reference_workai_sync]].
