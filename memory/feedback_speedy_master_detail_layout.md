---
name: feedback_speedy_master_detail_layout
description: "Speedy's standing screen layout is CrewChief's master/detail — header actions, card grid left, detail pane right — and every new panel follows it"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 05a61cd5-462a-479d-b5d9-1ae50f21dcb5
  modified: 2026-09-21T13:34:55.873Z
---

Gene, 2026-09-21: "this is the layout for all other panels similar to this as we add them keep it consistent."

The Speedy screen shell is CrewChief's `KeyValueReferenceData` layout, ported 2026-09-21:

- Header row: `h1` with a material icon, actions right-aligned (Import, Refresh/Lock).
- One-line muted subtitle saying what the screen holds.
- State banners under the header, one per named screen state.
- `row g-3` split: `col-12 col-xl-5` master (a `.cc-card-grid` of cards) and `col-12 col-xl-7` detail pane.
- Empty master uses the dashed `.cc-empty` panel; empty detail says "Pick a …  / Its entries open here."
- Selection travels in the **query string**, never a field, so a screen is a shareable link and survives a static-SSR POST.

**Why:** consistency across panels was an explicit instruction, and the layout is also the approved
palette's own — palette A is CrewChief as shipped, so wearing the donor's shell is what
`REQ-UIDONE-001` asks for rather than a departure from it.

**How to apply:** wrap the page in `src/Web/Components/Shell/ScreenScaffold.razor` — slots `Actions`,
`Subtitle`, `Banners`, `Master`, `Detail`, `Footer`, plus `Icon`, `Title`, `ScreenClass`, `State`,
`StateName` and `ShowSplit`. A screen with no master list (the Secrets bootstrap) passes `Detail`
only and gets the same header in one column. Never re-lay out a page by hand: the scaffold is the
consistency, and a page that departs has to do so by not using it, which is visible. The per-card and per-pane classes live in
`speedy-crewchief.css`; the grid, its column modifiers and `.cc-empty` are already in the copied
`crewchief/app.css` and are used as they stand. Introduce **no colour**: every grey the donor uses is
already in that copied sheet, and the accent is `var(--cc-accent, #667eea)` — never the donor's own
`#6366f1`, which appears nowhere in Speedy. See [[feedback_speedy_ui_is_crewchief_look_and_feel]] and
[[feedback_ui_port_characterise_and_uxreview]].

Re-laying out a screen that already has an interface audit **discards it**: `AC-UIDONE-002` wants an
audit at the revision proposed as done, so the audit is re-run and Gene's running-screen inspection
repeated. Budget for that before touching an audited screen.

EXCEPTION (Gene 9/21): step and workload editing do NOT use this split; see [[feedback_speedy_workflow_layout_full_width]].
