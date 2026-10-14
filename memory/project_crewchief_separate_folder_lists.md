---
name: project_crewchief_separate_folder_lists
description: CrewChief Steps and Workloads keep SEPARATE folder lists (Gene 9/8) - the old shared vocabulary was confusing; plus folder/item drag-and-drop rules
metadata: 
  node_type: memory
  type: project
  originSessionId: ba5a3f2a-f1ed-4de8-8046-daf12e21eb54
  modified: 2026-09-08T15:39:22.250Z
---

**Gene, 2026-09-08:** "having the steps and workloads share the same folder names in the UI is too
confusing we already physically separate so treat them as two separate structures... steps has its
folder list and workloads has its folder list not shared."

Shipped that day, with two more decisions taken in the same session:

- **Drag-and-drop moves immediately** — no confirmation dialog. The success toast names source and
  target, and dragging it back undoes it. Folder AND item drags both.
- **Migration seeds BOTH lists** from the pre-split shared `folders\catalog.json`, then they diverge;
  the legacy file is never written or deleted, it only seeds a library that has no file of its own.
  A one-time dismissible notice (`SeparateFoldersNotice`, localStorage) says the lists are now
  separate. Chosen over "seed each from its own tree", which would silently drop empty folders.
- **"(root)" is a real tree node** — folders render indented UNDER it, not level with it, and its
  caret collapses the whole tree.

Shape: `LibraryFolderCatalog(dataFolder, libraryKey, treeRoot)` per library
(`folders\steps.json`, `folders\workloads.json`); `StepFolderService`/`WorkloadFolderService` behind
distinct `IStepFolderService`/`IWorkloadFolderService` marker interfaces so a page injects its own
library and cannot reach the other. Deleting a folder on Steps no longer consults or touches
Workloads.

Related: [[reference_radzen_datagrid_unsized_column_collapses]].
