---
name: feedback_collapsible_panels_matching_rail_pattern
description: Gene wants side panels collapsible "like the Matching scorecard panel": chevron toggle in panel head, collapse to narrow rail (not hidden), state remembered in localStorage
metadata:
  type: feedback
---

Side panels (menus, folder panes, summary panels) collapse the way TestAuto's Matching scorecard "Your comparison" panel does (version-compare.css `.mw-side-toggle`/`.mw-chev`/`.mw-layout--collapsed`): a chevron button in the panel head, collapsed = narrow rail (~56px, icons or vertical label), never fully hidden, choice remembered per page in localStorage. Goal = max working space in the main area.

**Why:** Gene 10/30: "make the whole left menu panel collapsable ... just like we did the panel for the scorecard for matching", then "do the same to the folders part of steps, workloads, reference data so we can get as much working space".

**How to apply:** CrewChief 10/30 (uncommitted): left menu = icon rail (NavMenu.razor.cs data-driven, MainLayout key `crewchief.layout.sidebarCollapsed`); folder panes = `FolderPaneState` (Pages, CardViewState convention, keys `crewchief.<page>.folderPaneCollapsed`) + FolderTree `Collapsed`/`CollapsedChanged` rail showing the active folder filter. Reuse these for any new panel. Related [[feedback_speedy_view_memory_localstorage]].
