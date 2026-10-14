---
name: feedback_speedy_workflow_layout_full_width
description: "Step editing and workloads keep CrewChief's FULL-WIDTH workflow layout, never the 5/7 master/detail split — a workflow gets long"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: e3dd5abf-c57e-4aff-8d75-e32e4cf90a27
  modified: 2026-09-21T20:29:57.587Z
---

Gene, 2026-09-21 (approving the Connect step editor mockup): "we want to keep the workflow layout that CrewChief uses as a workflow can get very long and we dont want it to be 1/2 of the page width."

This is the EXCEPTION to [[feedback_speedy_master_detail_layout]]. The master/detail `ScreenScaffold` split is for list-and-inspect screens (Reference data, Secrets). Step and workload editing follow the donor instead:

- **Workload editor** (donor `CrewChief.Web/Components/Pages/WorkloadEditor.razor`): full-width page. One header action row (Export all, Add from library, Add inline step | Check capability, Cancel, Run, Save) plus a Fields/JSON toggle. A compact metadata card (Name, Description, collapsed Tags / Global parameters / Run As rows). Then a vertical list of full-width `wl-step-card`s: a 4px left border and header band in the step type's accent colour, `wl-seq` number, title, `cc-steppill` type pill, the `wl-action` icon toolbar, and a collapsible body holding Label, Fields/JSON and the `StepEditorCard`.
- **Steps library** (donor `Steps.razor`): a narrow folder column (`col-lg-3 col-xl-2`) plus a full-width card grid. Edit opens a wide dialog, `max-width: min(1000px, 96vw)`, with a command bar (type identity, Change type, Fields/JSON, Name, Save).
- ConnEx step type: accent `#0dcaf0`, band `#e0f7fa`, icon `hub`.
- The `wl-*` rules live in the donor's scoped `WorkloadEditor.razor.css`, not in the port's copied sheets. Porting them means an addition to `speedy-crewchief.css`, which moves the digest `NFR-UI-DONE-001` pins, so budget for that amendment.

**Why:** a workflow's step list gets long, and half-width panes crush the step editors.

**How to apply:** any step, workload or workflow screen gets the donor's full-width structure. Mockups for them show it in context.

**Update 2026-09-23 (Gene, after seeing the 5/7 Workloads screen):** "go back to the existing crewchief layout with the new colors": (1) folder tree back on the left WITH drag and drop, (2) a list view, (3) a separate edit screen, (4) wider cards, for Workloads AND Steps. Built as: `ScreenScaffold` `Folders` slot (col-lg-3 col-xl-2 tree + col-lg-9 col-xl-10 body), `LibraryViewBar` (cards/list + 2/3/4 per row, kept in `?view=list&cols=`), FolderTree drag (folder onto folder = reparent, card/list-name onto folder = MoveItem; a selected step drags the whole selection). Steps edit on `/steps/edit?edit=` (same component, full width, Back keeps filters), NOT the donor's 1000px dialog. Workload recent runs + Folder picker moved to `/workloads/edit`.