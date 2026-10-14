---
name: crewchief-library-folders
description: >
  CrewChief's nested folder trees for the step and workload libraries — FolderPath as the single
  path-traversal seam, LibraryFolderIndex's globally-unique-name shadow ranking, the additive-only folder
  catalogue that can never hide an item, and the deliberately SEPARATE folder lists for Steps and
  Workloads. Use when adding or moving a step or workload folder, working on FolderPath /
  LibraryFolderIndex / LibraryFolderCatalog / LibraryFolderService / FolderTree / FolderFilter, injecting a
  folder service, diagnosing a duplicate-name badge or a folder that will not delete, or reasoning about
  path-traversal safety in the file stores.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief library folders

Until 2026-09-01 the step and workload libraries were flat. They are now nested trees, and the change
touched three things an agent cannot infer from any single file: the traversal guard, name resolution, and
where the list of folders actually lives.

Paths are now `<dataFolder>/<kind>/[<folder>/...]<name>.<kind>.json` — see
[[crewchief-file-persistence]] for the rest of the store contract.

## When to Use

- "Add a folder" / "move this step into a folder"
- "Two steps have the same name — which one wins?"
- "Why is this folder still listed after I deleted its contents?"
- "Which service do I inject to list workload folders?"
- Reviewing anything that builds a path from a folder argument

## 1. `FolderPath` is the traversal guard, and the kebab check no longer is

**This is the correction that matters most.** The kebab-case check on a step/workload NAME used to be the
stores' *entire* path-traversal guard — `Get`/`Delete` validated before any `Path.Combine`, so `../escape`
could not form a path. `FolderPath.cs:11-17` states plainly that once a folder joins the path **that is no
longer sufficient.**

So every folder argument passes through `FolderPath`, which applies **two** checks:

1. each segment is kebab-validated; **and**
2. `FolderPath.ResolveUnder` asserts the resolved path still sits **inside the library root**.

The in-source comment calls the second one *"the one that holds even if the grammar is later relaxed — do
not drop it."* Treat it as the guard. Never re-derive path building from a name check alone.

`FolderPath.IsSameOrBeneath` carries a **prefix trap**: it compares with the folder plus a `/` suffix, so
`matching-archive` is correctly NOT a child of `matching`. A naive `StartsWith` gets this wrong.

## 2. Names stay GLOBALLY unique — the shadow verdict

Folders did **not** make names per-folder. A name is still globally unique across a library, so two files
claiming one name is a real state that must be resolved rather than prevented.

`LibraryFolderIndex.Build` does **one recursive walk** (`SearchOption.AllDirectories`) and ranks
collisions:

| Rule | Behaviour |
|---|---|
| Winner | **Shallowest path wins** |
| Tie-break | Ordinal by relative path |
| Losers | **Still returned**, carrying the winner's path via `LibraryEntry.ShadowedBy` |

That last row is the design decision: a duplicate is **badged, not hidden**. If losers were dropped, an
operator would see a file on disk that the UI denies exists. A shadowed copy is listed and **Save-refused**
— the same reasoning as the broken-file stub in [[crewchief-file-persistence]].

## 3. The folder catalogue is additive-only and never authoritative for absence

An **empty folder cannot exist in a file-derived index** — there is no file to imply it. So
`LibraryFolderCatalog` persists a separate vocabulary at `<dataFolder>/folders/<library>.json`:

- The listed folders are the **union** of the catalogue and what is observed on disk.
- Therefore the catalogue is **additive-only and can never hide an item**. It answers "what folders exist",
  never "what does not".
- **Explicit-ancestors rule**: creating `a/b/c` writes rows for `a` and `a/b` too, so a tree renders
  without inferring parents.
- A legacy shared `catalog.json` seeds both lists once.

Consequence for `LibraryFolderService`: a **catalogue-only** folder (no files beneath it) must skip
`MoveFolder` — there is nothing on disk to move.

## 4. Steps and Workloads have DELIBERATELY SEPARATE folder lists

Not an oversight, and not shared state. Inject the **marker interface**, never the base:

| Inject | For |
|---|---|
| `IStepFolderService` | the step library's folders |
| `IWorkloadFolderService` | the workload library's folders |
| ~~`ILibraryFolderService`~~ | **do not inject directly** — it cannot know which library you meant |

DI cannot distinguish the two by type alone, which is exactly why the markers exist.

## 5. The UI seams

- `FolderTree` / `FolderTreeNode` — the tree control. **The root is a real tree node**, not a synthetic
  header, and drag-drop **moves immediately** (no confirm step).
- `FolderFilter` — the filter convention: `null` = all, `""` = root only, a path = that folder **and its
  descendants** (via the suffix check in §1).

See [[crewchief-web-ui]] for the list-filter delegation pattern these sit inside.

## Sources

- `CrewChief\CrewChief.Data\Stores\FolderPath.cs`
- `CrewChief\CrewChief.Data\Stores\LibraryFolderIndex.cs`
- `CrewChief\CrewChief.Data\Stores\LibraryFolderCatalog.cs`
- `CrewChief\CrewChief.Data\Services\LibraryFolderService.cs`
- `CrewChief\CrewChief.Data\Stores\StepFileStore.cs`
- `CrewChief\CrewChief.Data\Stores\WorkloadFileStore.cs`
- `CrewChief\CrewChief.Web\Components\Controls\FolderTree.razor`
- `CrewChief\CrewChief.Web\Components\Controls\FolderTreeNode.cs`
- `CrewChief\CrewChief.Web\Components\Pages\FolderFilter.cs`
