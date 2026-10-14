---
name: feedback-ui-port-characterise-and-uxreview
description: "ANY new UI design or UI update goes through the ui-ux-pro-max skill and mockups reviewed at a gate BEFORE code; port sections also start with donor characterisation; accessibility findings go straight into build/battery rows, never asked"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 22d5dbd3-c155-4749-bee7-fcbb38ec1329
  modified: 2026-09-14T19:09:01.978Z
---

**Standing rule (Gene 9/14): any new UI design or update — screen, panel, pane, dialog, visible change — goes through the `ui-ux-pro-max` skill and produces mockups reviewed at a human gate before any code.** Outside port sections that means a mockup row + integer gate ahead of the build row (e.g. 52.S0.4m/gate 70, 52.S0.8m/71, 52.S9.1m/72).

Every UI port section (52.S1–S5: reference data, secrets, steps, workloads, cross-cutting) runs two rows before its mockups:
- `.0a` **characterise the donor** — run today's functionality for real (read-only in the donor repo) and record reference outputs the port must match; the section's wire rows cannot close until the port matches.
- `.0b` **UX review with the `ui-ux-pro-max` skill** — suggested-fixes list; mockups are built with the skill applying the fixes; the approved kit (gate 60) stands, so no new design system.

**Accessibility findings are never asked about.** Each one is placed directly into the section's build rows (implemented) and battery rows (asserted).

**Why:** the section recipe proved new pages only against themselves; donor parity was a stated goal with no row checking it. Gene wants re-verification of current functionality before any port, and UX fixes driven by the skill rather than left to the mockup author, without being asked accessibility questions.

**Port-section testing also required:** donor-written files kept as `.0a` fixtures and opened unchanged by `.4x`; 1,000-item list timing in list batteries; secret masking in editor/export/raw JSON batteries; `.7` runs section-close-full-tests.ps1 + live handover; one cross-section journey battery (52.S5.5d).

**How to apply:** any new UI port section or re-cut keeps `.0a` + `.0b` ahead of `.1`; ticket text for build rows names the `.0b` accessibility findings, battery rows assert them, wire rows name the `.0a` reference outputs. Related: [[feedback_ui_parity_before_new]], [[project_speedy_crewchief_section_plan_2026-09-12]], [[feedback_section_close_requires_full_tests_incl_playwright]].
