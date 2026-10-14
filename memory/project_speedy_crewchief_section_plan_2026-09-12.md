---
name: project_speedy_crewchief_section_plan_2026-09-12
description: "2026-09-12 implementation plan that replaces board rows 52.01–52.18 with 70 section-shaped rows (P1 kit, P2 nav, §1–§5), sized from donor HEAD e0ebfc33; NOT yet applied to the board — waits on Gene's read"
metadata: 
  node_type: memory
  type: project
  originSessionId: f0c59fa0-f352-4ee5-967f-6069f443af26
  modified: 2026-09-12T15:04:27.156Z
---

**`Q:\Work\Work\99 Documentation\speedy\ImplementationPlan_CrewChiefSections.md`** (Artifact
https://claude.ai/code/artifact/c4ecab53-151b-43e2-ae82-6e464f57a9cc) is the plan that re-cuts row 52
per the guiding document ([[project_speedy_guiding_document_2026-09-12]]). Written 10:45–11:1x, Fable 5.1.
**The board was NOT changed** — §10 of the plan is the exact `Write-TaskList.ps1` block, the
`schedule-order.txt` replacement and the archive step, to apply only after Gene reads it.

**Shape:** 70 rows (6 are 0-minute integer HUMAN GATE rows 60–65 — `Write-Schedule.ps1` only recognises a
gate as an INTEGER header row whose status matches `human gate`). Keys `52.P1.1a…52.P1.7`, `52.P2.3…7`,
`52.S1.1…52.S5.7`; one row per gate step, build/wire/battery split per screen under the 120-min ceiling.
Totals 4,755 plan / 4,296 est (71.6 h) vs the old 3,130 plan — up 52 % because mockups (800), help (350),
closes (105) and pattern births (210) were never on the old board. First-cut saving is unmeasured until
`52.S2.7` (Secrets calibration), which re-derives §3–§5 est and answers O3.

**Sizing rates (labelled in §0.2):** port = donor in-scope lines ÷ 17/min (from UoW9_Plan rows 4/5/9/11);
pattern reuse 60 % (assumption, calibrated at §4); 45 min per route for Playwright+axe+`.actual.png`+smoke;
mockups 25/screen, 15/kit component, 20/batch (NO measured datum — P1 is the first); help 20/page
(assumption); est = plan × 0.90.

**Decisions Gene can overturn (plan §11):** D-b nav frame mocked in the P1 batch (no P2 gate) · D-c
MD2Razor pipeline (package+csproj+MarkdownDocBase+HelpLayout, no route) pulled into P2 so §1's docs
compile · D-d Monaco cut, JsonPane = textarea · D-e Home 9.1 joins §5 (guiding doc §4 never placed it) ·
D-f capability badge deferred to §5 retrofit · D-g `.wl-publish*` CSS in 52.S4.3a · D-i Builder engine
lands in `Infrastructure/Execution` beside `TokenShapes`, not Domain · D-j 53.03's status dangles, untouched.

**Verify-at-dispatch items (not asserted):** the domain step type name (52.S3.3a); `ILocalSecretStore`'s
per-entry write surface (52.S2.4 — only Import/Export/GetSections/GetStatus seen); `cli` seeding verbs for
reference data and secrets; `TokenShapes` lacks the six members the donor engine calls (confirmed absent).

**Pattern contracts are in code in the plan:** `ListViewState` + `SpeedyListShell<TItem>` (52.S1.3a),
`DefinitionEditor<TStep>` (52.S3.3a), `RunHistoryShell` (52.S5.3a), `NavEntries.All/.Exempt` (52.P2.3).

Related: [[reference_vnext_plan_doc_v3]], [[project_speedy_ui_skills_review_2026-09-09]],
[[feedback_vnext_schedule_format]], [[reference_obsidian_smb_vault_watcher_blind]].
