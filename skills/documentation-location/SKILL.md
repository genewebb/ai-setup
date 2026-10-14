---
name: documentation-location
description: >
  Rules for where AI-generated documentation and planning artifacts go for the speed-merchants project.
  Use when asked to save a plan, build notes, bug report, research document, or any AI session artifact
  for speed-merchants.
---

# Documentation Location — Speed Merchants

Where to save AI-generated artifacts (plans, build notes, bug reports, reviews, dated reports) for the speed-merchants project. These live in the **Obsidian Work vault** under `99 Documentation` (consistent with the `project_doc_location` memory: code/repo docs → `99 Documentation\`).

## When to Use

- "Save the plan somewhere"
- "Write build notes"
- "Where should I save this?"
- Creating a planning document, investigation notes, or dated report
- Any AI session artifact that needs to persist beyond the conversation

---

## Correct Location

All speed-merchants AI-generated artifacts go under:

```
{VaultDocsRoot}\speed-merchants\
```

> Do NOT use the old `devopslocal\Documentation\speed-merchants\` folder — that was an old/incorrect location; everything lives in the Obsidian vault now.

---

## Subdirectory Structure

The `speed-merchants` folder already contains these subfolders — use the matching one:

| Purpose | Path |
|---------|------|
| Planning / specs / plans | `…\99 Documentation\speed-merchants\planning\` |
| Architecture reviews | `…\99 Documentation\speed-merchants\architecture\` |
| Bug investigations | `…\99 Documentation\speed-merchants\bugs\` |
| Reviews | `…\99 Documentation\speed-merchants\review\` (and `reviews\`) |
| Setup notes | `…\99 Documentation\speed-merchants\setup\` |
| Skills / reference | `…\99 Documentation\speed-merchants\skills\` |
| Dated run reports | `…\99 Documentation\speed-merchants\` (root) |

(`…` = `{VaultWorkRoot}`.) Create additional subdirectories as needed, following the same pattern.

> **Topic docs vs project docs:** some docs are filed by *topic* directly under `99 Documentation\` (e.g. `99 Documentation\matching\`, `99 Documentation\connex\`) rather than under `speed-merchants\`. Use a topic folder when the doc is about that topic broadly; use `speed-merchants\...` for project planning/build/bug artifacts.

---

## File Naming Conventions

- **Dated artifacts:** `{Topic}_{yyyy-MM-dd}.md` — e.g., `ModelAndDataReview_2026-05-16.md`
- **Plan files:** `Plan_{Feature}.md` — e.g., `Plan_MatchingUpdate.md`
- **Design/spec files:** `Design_{Feature}.md` or `{yyyy-MM-dd}-{topic}-design.md`
- **Build notes:** `BuildNotes_{Feature}.md`
- **Skills / reference:** Descriptive name without date — e.g., `SkillModelAndDataReview.md`

---

## Quick Decision

```
Creating a plan / spec / build notes?
→ {VaultDocsRoot}\speed-merchants\planning\

Creating a dated report from a repeatable skill run?
→ {VaultDocsRoot}\speed-merchants\{Report}_{yyyy-MM-dd}.md

Creating / updating a skill reference doc?
→ {VaultDocsRoot}\speed-merchants\skills\

Doc is about a broad topic (matching, connex, etc.)?
→ {VaultDocsRoot}\{topic}\
```

---

## Sources

- Obsidian Work vault `99 Documentation\speed-merchants\` (live structure)
- `project_doc_location` memory (Obsidian Work vault `99 Documentation`)
