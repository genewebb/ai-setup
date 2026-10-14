---
name: project-doc-location
description: Where AI-generated documentation and artifacts should be stored — two locations based on content type
metadata: 
  node_type: memory
  type: project
  originSessionId: 90d1612e-a3d9-492b-a34d-9d99b18beaf4
  modified: 2026-08-12T14:58:49.983Z
---

Documentation splits into two Obsidian vault folders based on content type:

| Type | Location |
|---|---|
| Code / repo related | `C:\devopslocal\ObsidianVaults\Work\MyWorkVault\99 Documentation\` |
| Tool related | `C:\devopslocal\ObsidianVaults\Work\MyWorkVault\52 Technical\` |

**Examples:**
- Plans, build notes, bug reports, architecture decisions for a repo → `99 Documentation\`
- Guides for tools like Claude Code, MCP servers → `52 Technical\`

**Why:** User's Obsidian Work vault uses numbered folders for organization. 99 = project/code docs, 52 = tooling and technical references.

**How to apply:** Before writing any documentation file, determine if it's about code/a repo or about a tool, then use the corresponding path. Never use `C:\devopslocal\Documentation\` or `.cursor/documentation/`.

## Naming conventions inside each folder (verified 2026-08-12)

Two dialects coexist — match the subfolder you land in, don't invent a third:

| Folder | Convention | Examples |
|---|---|---|
| `52 Technical\` | Title Case With Spaces | `Powershell Profiles.md`, `Adding and Editing Mcp Servers.md` |
| `99 Documentation\speed-merchants\planning\` | `Design_PascalCase.md` / `Plan_PascalCase.md` / `TestPlan_*.md` | `Design_CheckRemoteAccess.md`, `Plan_CrewChiefRawJsonPanes.md` |
| `99 Documentation\CrewChief\` | `YYYY-MM-DD-kebab-topic-<design\|plan\|guide>.md` | `2026-08-05-connect-export-conversion-design.md` |
| `99 Documentation\<other topic>\` | kebab-case, often date-prefixed | `connect-metrics-collection-explained.md` |

**Default for a speed-merchants or CrewChief design/recommendation doc:** `99 Documentation\speed-merchants\planning\Design_*.md` — that folder holds the live (non-Archive) design docs and covers both products, since CrewChief is a subtree of speed-merchants. Use `99 Documentation\CrewChief\` only for CrewChief-only docs following the dated pattern already there.

Iterated docs become `-v2`/`-v3` **siblings**, not in-place rewrites (see `connex\connex-step-implementation-plan-v1..v4.md`). Superseded docs move to an `Archive\` subfolder rather than being deleted.
