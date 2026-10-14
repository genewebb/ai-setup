---
name: project_skill_body_splits_2026-08-01
description: "The 5 heaviest skills were split into core SKILL.md + references/ on 2026-08-01 — bodies cut 56%, and the line-range script that did it"
metadata: 
  node_type: memory
  type: project
  originSessionId: ef7d1507-9389-4274-b379-610fa13e50c5
  modified: 2026-08-01T21:54:44.492Z
---

Item 2 of `03 Shared\AICosts\ReducePromptCost.md`, done 2026-08-01. Five skills split into
a core `SKILL.md` (decision rules, gotchas, failure modes) plus `references/*.md`
(catalogs, full parameter tables, long examples), 22 reference files total:

| Skill | Body before | Core after | Refs |
|---|---:|---:|---:|
| `testauto-multistep-steps` | 18,139 | 8,824 | 6 |
| `testauto-matching-scenarios` | 13,950 | 5,007 | 5 |
| `crewchief-remote-box-prep` | 10,424 | 5,802 | 5 |
| `crewchief-web-ui` | 9,930 | 3,531 | 4 |
| `testauto-workflow-execution` | 9,112 | 3,902 | 2 |
| **Total** | **61,555** | **27,066** | **22** |

Each core file gained a `## Reference files (load on demand)` table with a "read it when…"
row per file — the router stays always-loaded, only the catalog defers. Frontmatter
`name:`/`description:` were left untouched, so activation behaviour is unchanged.

**Why:** the method, not the arithmetic — the saving turned out small, see
[[reference_skill_cost_is_size_times_invocations]].

**How to apply:** to split another skill, do NOT retype the content. Print a
header-plus-token-size outline of `SKILL.md`, pick line ranges from that outline, and move
them with a script that validates fence parity and that each range starts on a header
before writing (`Split-Skill.ps1`, pattern preserved in the doc). The section bodies never
pass through model output, so the edit costs the outline rather than the file. Skills are
junctions into `work-ai\skills\` — edit the vault copy; `references/` under an existing
junction needs no linker run. Regenerate `Overview\README.md` only when a `description:`
changed. Related: [[project_skill_description_trim_2026-08-01]], [[project_repos]].
