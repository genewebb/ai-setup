---
name: project_crewchief_bulk_tagging
description: "CrewChief bulk tag picker on Steps/Workloads lists — shipped 2026-09-01, add-only, unreadable-workload skip"
metadata: 
  node_type: memory
  type: project
  originSessionId: b8e9b528-8bb7-4f37-a650-80f276ecbf3c
  modified: 2026-09-01T18:43:28.694Z
---

Shipped 2026-09-01 (uncommitted). Steps + Workloads list toolbars gained an inline **bulk tag picker**
(`Components/Controls/BulkTagBar.razor`) that appears only while rows are checked, beside Delete Selected.
Pick existing tags and/or type a new one, Apply to N.

Design decisions worth remembering:
- **Add-only.** Bulk remove was deliberately excluded — easy to fire over a filtered selection, no undo.
  Removal stays in the per-item edit dialog.
- **Selection is KEPT after apply** (unlike bulk delete), so a second tag needs no re-ticking.
- Merge rules live in `Components/Pages/TagAssignment.cs` (`Collect`, `Union`) — pure, Ordinal, always
  returns a NEW list so bound RadzenDropDowns resync. Sits beside `ListFilters.cs` for the same
  anti-drift reason.
- Workloads only: a **broken-file stub** (`WorkloadFile.IsUnreadable`) is skipped and named in a warning
  toast — `WorkloadFileStore.Save` refuses stubs, so the throw would otherwise read as a mystery failure.
- A typed tag is pushed into the shared reference-data `tags` set via `ReferenceStore.AddTag` (key=value).

Tests: `Web/TagAssignmentTests.cs` (10) + 4 Steps / 3 Workloads bUnit tests. Suite 3692 green (was 3675).
Docs updated: `00_GettingStarted.md`, `30_OpsWebUi.md`.

Related: [[project_crewchief_token_filters]] [[project_crewchief_ui_conventions_2026-07]]
