---
name: feedback-bulk-delete-ui-groups-not-rows
description: "Bulk delete/purge UIs show entity + reason + totals per group (decide per group), never row lists; scope one subject area at a time; filter by the parent record (workload execution) everywhere"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 2e872688-f90d-435a-b363-0e499a7c56ac
  modified: 2026-10-08T14:39:23.191Z
---

For any bulk delete or purge screen, present **groups, not rows**: entity, reason, total per group, and let the decision (Delete / Keep / select) apply to the whole group. Drill-down is a capped top-N of parent records by count, never a record list. Keep scope small: **one subject area per run**. The parent record (in TestAuto: the workload execution) must be a filter on every view, ideally with a tree parent -> related entities -> counts.

Selection of parent records = vertical checklist (never horizontal chips) showing Name AND Code, with select all / unselect all; the whole flow is a wizard (choices step by step, then a preview of what will actually be deleted, per parent record totals).

**Why:** Gene, reviewing the run purge mockups 10/8: groups can hold a million rows, so row previews are impractical; decisions are made on entity + reason totals; one subject area at a time keeps a purge smaller and more controlled; the workload execution is what decisions hinge on.

**How to apply:** preview figures come from count queries (gateway TotalCount), not row reads; label each group with its reason; expensive per-parent counts load lazily on expand. Related: [[project_testauto_metric_run_purge_2026-10-07]], [[feedback_ui_mockups_before_implementing]].
