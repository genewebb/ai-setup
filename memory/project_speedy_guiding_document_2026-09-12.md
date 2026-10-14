---
name: project_speedy_guiding_document_2026-09-12
description: "The 2026-09-12 guiding document that re-shapes board rows 52-54 — section gate, patterns for three offenders, docs as by-product, dial-up study; reviewed by Fable 10:35 with five corrections"
metadata: 
  node_type: memory
  type: project
  originSessionId: dab7e805-1f7d-4599-a8f9-7e54417973f7
  modified: 2026-09-12T14:17:39.915Z
---

**`Q:\Work\Work\99 Documentation\speedy\GuidingDocument_RemainingWork.md`** is the steering document
for all remaining Speedy work (authored 09:28–09:49, reviewed/corrected 10:00–10:35 by Fable 5.1;
§11 is the review record). Artifact: https://claude.ai/code/artifact/0b628ca4-2ade-40ca-b34c-41a4ad4854c8.
`vNextImplementation_v3.md` stays the delivery log; **`.loop\tools\schedule.json` is the authority on
row status** — v3's UoW-9 table was stale (said row 51 `Ready`; it closed 09-05 23:32, 80m vs 260).

**Gene's next steps (10:00):** review + Q&A with Fable (DONE) → full implementation planning with
Fable → swap back to the Fable-foreman loop.

**What it decided that is not derivable from the board:**

- **Sections, not screens.** Gate = mockup batch → Gene approves → build → wire → full battery per
  page (bUnit + composed + Playwright + axe) → help docs → close. **Rejection re-enters the WHOLE batch
  at step 1** (Gene 10:20). Nothing starts until the previous section closes (learning loop).
- **"First cut = scope, battery = coverage."** Scope cut, coverage not. 198.6h cannot be corrected on
  paper; **section 2 (Secrets) is the calibration row** (Gene 10:20) — section 1 carries the list
  pattern's birth cost.
- **Patterns for three offenders only** (list, definition editor, run history ≈ 20/51); each **born in
  the first section that needs it** as a graded deliverable; **contract from the hardest consumer**
  (author rec). Import/export, diagnostics, settings duplicate on purpose; revisit at TestAuto gate.
- **CrewChief sections:** 1 Reference Data (list born) · 2 Secrets (calibration) · 3 Steps
  (+Templates +Connect import; editor born) · 4 Workloads · 5 Cross-cutting (Activity, Backup, help
  shell, capability preflight; run-history born). Prereqs: P1 component kit (9.13 value picker), P2
  minimal nav shell. **Row 51 tokens already DONE.** Backlogged: 9.12, 9.16.
- **310,000 words / 138 files of donor in-app help** measured, on no board row; mockup `NOTES.md` at
  approval IS the help doc draft, promoted at section close.
- **Mockups kept in `speedy\ui\`**, static HTML linking the REAL `speedy.css` with SHA in
  `SOURCE.json`, one fictional dataset, `.actual.png` from Playwright beside each; vault + Artifact.
- **Stage 1 of the dial-up study does NOT start now** (Gene 10:20: "not ready to run the tests"). The
  "start in parallel on donor" proposal was withdrawn. Rules on/off = first Tier 2 axis (O6 closed).

Dial-up facts and the five review corrections: [[reference_speedy_dial_up_measurement_constraints]].
Related: [[reference_vnext_plan_doc_v3]], [[feedback_ui_mockups_before_implementing]],
[[reference_obsidian_smb_vault_watcher_blind]].
