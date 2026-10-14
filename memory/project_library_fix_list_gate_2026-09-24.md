---
name: project_library_fix_list_gate_2026-09-24
description: Gene's 9/24 library fix list (W1a..L1, V1): V1 sticky view SHIPPED b6ff0a3; UI items at mockup gate TmAiRdVKG1e9swC2cMaJAc; S1 reveal-all conflicts with REQ-SECRETSUI-026
metadata:
  type: project
---

Fix list saved at scratchpad gene-fix-list-2026-09-24.md (session 0359fc02).
- V1 sticky card/list view DONE b6ff0a3: StickyView (localStorage speedy.{screen}.view/.cols on Steps/Workloads; HttpOnly cookie speedy.view.reference-data on static Reference Data; address always wins; card link names view=cards).
- Mockup gate https://claude.ai/artifact/TmAiRdVKG1e9swC2cMaJAc covers W1a W1b A1a A2 D1a-c L1 W2 R1 S2 S4 S1, answers S3/P2. Awaiting Gene.
- S1 "show ALL sensitive when unlocked" contradicts REQ-SECRETSUI-026 (one deliberately selected value; SecretsWorkspace holds one RevealedAddress). Options A all / B show-all switch (recommended) / C per-row. A or B needs an amendment under review/amendments/ first.
- Open gate Qs: Steps type-tree filter too? Reference sets + run profiles have no tags (A1a there needs tags first).
- "Secrets Preview section" (S2) = ValueEditor Preview (ValuePreviewCell) -> move into RuntimeValueChip hover; problems stay under field.
- Flake seen once: AC_ACTIVITY_003_ReattachesToTheSameRun failed at 131 ms under parallel load, passed 4 reruns.

**Why:** Gene reviews UI at a mockup gate before code ([[feedback_ui_port_characterise_and_uxreview]]).
**How to apply:** build only approved items; S1 only after the amendment is approved.
