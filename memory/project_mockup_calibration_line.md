---
name: project_mockup_calibration_line
description: Measured minutes for opus static-HTML mockup batches in the CrewChief section campaign (row 52.P1.*); three lines 2026-09-12, P1 batch 45 actual vs 203 est = 0.22x, proposed 0.3x factor for S-rows
metadata: 
  node_type: memory
  type: project
  originSessionId: 1c9afcba-fb90-4c16-9d40-a5770418aa15
  modified: 2026-09-12T21:42:14.562Z
---

**Mockup calibration lines (opus foreman-worker, static HTML against the real `speedy.css`, vault `speedy\ui\`):**

| Row | Content | Est (opus) | Actual | Factor | Date |
|---|---|---|---|---|---|
| 52.P1.1a | mockup home, `_assets` (css copy + SOURCE.json + sample-data.js), nav-frame.html, README, index, NOTES | 81 | 8 (attempt 1 ~1m for `_assets`, attempt 2 6.7m) | 0.10x | 2026-09-12 16:41 |
| 52.P1.1b | four value-editor family screens (value-editor 34 KB, secret-value-editor, segmented-toggle, runtime-chip) + NOTES extension + index + dataset append | 68 | 19 (17 to grader green + 2 own verification; 219k tokens) | 0.28x | 2026-09-12 17:2x |
| 52.P1.1c | five controls-kit screens (folder-tree, bulk-tag-bar, cards, json-pane, badges) + NOTES section + index links + dataset append (5 keys) | 54 | 18 (5 donor/CSS reading, 2 per screen, 2 NOTES+index, 1 verification; 209k tokens) | 0.33x | 2026-09-12 17:41 |

**P1 batch total: 3 rows, 203 est vs 45 actual = 0.22x.** Proposed mockup factor for S1-S5 sizing: 0.3x of the human estimate (rounded up from 0.22x to keep slack for NOTES growth). Not yet applied to the board — Gene decides at gate 60.

**Why:** the plan (`ImplementationPlan_CrewChiefSections.md`) sized mockup rows for a human; the first measured batch came in at a tenth. Rows 52.P1.1b (75) / 1c (60) and every S1-S5 mockup row are sized the same way.

**How to apply:** expect single digits to low teens of minutes per mockup batch; do not re-size the board off ONE line (Gene rule: measure first). Add a row here at each mockup close; after 1b and 1c, propose a mockup-specific factor to Gene. Related: [[project_speedy_crewchief_section_plan_2026-09-12]], [[reference_speedy_dial_up_measurement_constraints]].

**Code-row calibration (P1 ports, opus foreman-worker):**

| Row | Content | Est | Actual | Factor | Date |
|---|---|---|---|---|---|
| 52.P1.3a | TokenComposition (512 lines) + TokenFilters (979) ported, six TokenShapes members, TextTemplater applies chains, 27 + 5 tests, census row | 77 | 13 (port 5, tests 4, wiring 2, census+grader 2; 189k tokens) | 0.17x | 2026-09-12 20:17 |

Plan rate was donor-lines / 17 per minute; measured ~1,900 lines landed in 13 min. One datum -- do not re-size code rows off it (Gene rule: measure first); P1.7 records the port rate.
- 52.S0.1 (dial mockups, 3 directions + attempt 2 truth fixes) | 40 actual vs 20 est = 2.0x (attempt 1 13m, attempt 2 6m, lead grader/verify ~20m) -- 2026-09-13
- 52.S0.1b (dial screens redrawn in the CrewChief look and feel: dial-a/b/c.html) | 14 actual vs 50 est = 0.28x (worker 12m) -- 2026-09-14
- 52.P1.8c (four palette screens + index.html + palettes.html + the departures sheet) | 43 actual over TWO attempts vs 60 est = 0.72x -- 2026-09-14. The factor is misleading and the reason matters: attempt 1 was LOST when its lead session died, having already written every screen; attempt 2 was handed an ATTEMPT-2 section naming what was already on disk and finished the two remaining NOTES.md clauses in **9 minutes**. Worker minutes were ~9, not 43. A lost attempt inflates dispatch-to-collect minutes without inflating work, so read the per-attempt minutes before treating a row like this as a calibration datum.
