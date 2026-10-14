---
name: documentation-folder
description: >
  Resolves "the documentation folder" or "documentation folder" to the correct Obsidian vault path
  and guides subdirectory selection. Use whenever the user references "the documentation folder",
  "documentation folder", or asks where to save/write documentation without specifying a full path.
---

# Documentation Folder

**Root path:**
```
{VaultDocsRoot}
```

## Behavior

### If the user specifies a subfolder
Use it as given. Resolve the full path as:
```
{VaultDocsRoot}\<specified-folder>
```

### If no subfolder is specified
1. Look at the context of the request (project, topic, tool, artifact type).
2. Match against the existing subfolders below.
3. Suggest the best fit and explain why in one sentence.
4. Ask the user to confirm or override before writing anything.

## Existing Subfolders

| Folder | Use for |
|--------|---------|
| `ai` | General AI tooling, prompts, patterns not tied to a specific tool |
| `archive` | Outdated or superseded documents |
| `backup` | Backup configs, snapshots, restore notes |
| `cdp` | CDP / Customer Data Platform work |
| `claude` | Claude model notes, usage patterns, Claude-specific docs |
| `claudecode` | Claude Code CLI setup, hooks, settings, keybindings |
| `connex` | Connex integration docs |
| `containers` | Docker, container configs, deployment notes |
| `cursor` | Cursor IDE setup and usage notes |
| `dev-utilities` | Developer tools, scripts, utilities |
| `github-copilot` | GitHub Copilot setup and usage notes |
| `governance` | Data governance, policies, standards |
| `issues` | Bug reports, incident notes, postmortems |
| `matching` | Matching engine docs, configuration, analysis |
| `metrics` | Performance metrics, benchmark results, comparison reports |
| `monitor` | Monitoring setup, alerts, dashboards |
| `mymachine` | Local machine setup, environment config |
| `opencode` | OpenCode IDE notes |
| `otherdevs` | Notes about other developers' setups or work |
| `people` | People-related notes (contacts, org, stakeholders) |
| `speed-merchants` | Speed Merchants project documentation |
| `swagger` | API specs, Swagger/OpenAPI docs |
| `tools` | Miscellaneous tooling docs |
| `vscode` | VS Code setup, extensions, settings |

## Suggestion Logic

Match on these signals (in priority order):

1. **Explicit topic** — user names a tool or project → match directly to that folder
2. **Artifact type** — performance report → `metrics`; bug/incident → `issues`; setup/config → tool-specific folder
3. **Active project context** — speed-merchants work → `speed-merchants`; matching work → `matching`
4. **Fallback** — if nothing fits cleanly, suggest the closest match and note that a new subfolder can be created

## New Subfolders

If no existing folder fits, propose a new subfolder name (kebab-case), create it, and note in your response that it was added.
