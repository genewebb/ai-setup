---
name: reference-workai-overview-readme-generated
description: work-ai Overview/README.md is generated from skill frontmatter — never hand-edit it
metadata: 
  node_type: memory
  type: reference
  originSessionId: 875a0862-8f07-47b0-b7a4-40af27dadba8
  modified: 2026-07-25T19:55:56.736Z
---

`work-ai\Overview\README.md` is a **derived artifact**, not a hand-maintained
list. Every row comes from the `description:` frontmatter of the corresponding
`SKILL.md` / agent file. Hand-editing it will be overwritten.

Regenerate:

```powershell
pwsh "…\work-ai\Overview\Generate-SkillsReadme.ps1"
```

Verify (exit 0 = current, exit 1 = stale):

```powershell
pwsh "…\work-ai\Overview\Generate-SkillsReadme.ps1" -Check
```

Created 2026-07-25 because the README had drifted badly — it claimed 89 skills
dated 2026-05-31 when the corpus held 145 and every CrewChief skill was absent.

The "About" column is the part of a description **before** `Use when`, so a
skill that ignores the house description style renders badly in the index. That
is a signal to fix the description, not the README.

Categorisation is prefix-based (`testauto-`, `crewchief-`, `dotnet-`, …) with an
`$Overrides` map for the exceptions. A new skill landing under **General**
unexpectedly means it needs an `$Overrides` line. The script throws rather than
silently dropping a skill whose category is missing from `$CategoryOrder`.

Wired into the process at `skill-audit-with-update` Phase 5b (mandatory, with
the `-Check` gate) and `ai-repo-management` Step 4.

See [[project_ecc_adoption]].
