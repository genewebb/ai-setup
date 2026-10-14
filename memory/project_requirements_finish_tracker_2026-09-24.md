---
name: project_requirements_finish_tracker_2026-09-24
description: "Speedy requirements tracker = speedy/Speedy-Requirements-Tracker.md; three-session split 9/25 (requirements / Speedy-Coding-Tracker / Speedy-Workflow-Tracker) by folder, workflow frozen until Gene merges"
metadata:
  node_type: memory
  type: project
  originSessionId: cfcac4ec-9374-4fef-be5f-3fab9aad78aa
  modified: 2026-09-25T12:12:39.265Z
---

**2026-09-25 ~08:50 FINAL: three sessions, split by folder (Gene).** Each session has its own root tracker in `Q:/Work/Work/99 Documentation/speedy/` and writes only its own folders:
- **Requirements** = `Speedy-Requirements-Tracker.md`. Writes `speedy/requirements/` (live YAML, ids.yaml, review/, amendments) and `tools/requirements/`. Holds A6-A8, B1-B4, MP-9..MP-12 (M1 skipped as superseded; M2-M5 became MP-9..12), C0, D1, E0, F0, all Q0-n and MPQ-19. Next row: A6 (clean-session review).
- **Speedy coding** = `Speedy-Coding-Tracker.md` (Gene renamed it from speedy-tracker.md at 08:43). Writes product code, `metric-profiles/` and `ui/` except the canvas mockups. No open rows; MP-1.2 and MP-1.3a are parked. Holds MPQ-1..18.
- **Workflow** = `Speedy-Workflow-Tracker.md`. Writes `Workflow-vs-Code/` and the canvas mockups in `ui/crewchief/04-workloads/`. It points at `Workflow-vs-Code/GOAL-CANVAS-READY.md`; next is WF-G3 (Gene runs REVIEW-PROMPT-FINAL in a clean session).
- **Workflow is FROZEN for the requirements session** until Gene merges the WVC work. Then requirements row W1 does one final workflow pass. Every requirements change to FEAT-SCENARIO-DEFINITION-001 or CAP-LOAD-001 (both pinned by WVC) gets a "Workflow pin:" Log line. FEAT-ACTIVITY-FLOW-001 and ADR-WORKFLOW-ENGINE-001 are excluded from E0.
- The old REQUIREMENTS-FINISH-TRACKER-2026-09-24.md and METRIC-PROFILES-TRACKER-2026-09-24.md are archives; their banners point to the right successor.

History (below) describes the 9/24 tracker; the row mechanics still apply.

Phases:
- 0: Gene's owner questions (Q0-1..9 plus a sweep);
- A: library-fix-list-r1 L2 review, then L3 repair, then L4 approval;
- B: library-fix-list-r2 rebase, review and approval;
- C: five stale amendment packages;
- D: README status fixes;
- E: 24 normative definitions not READY;
- F: 134 inventory records awaiting ACCEPTED;
- G: deferred fixes.

**Why:** Gene asked for one document that tracks what is done and says what the next /goal prompt is, starting with the questions he must answer.

**How to apply:**
- The tracker drives itself. Gene runs `/clear` and then `/goal <tracker path>`, and that session does exactly one Step queue row, following the tracker's "Instructions for the /goal session".
- Row kinds are review, author, gene and plan. Gene rows ask him through AskUserQuestion.
- Each session records its result, writes the tracker through the vault writer, verifies the hash, and ends with `TRACKER STEP COMPLETE: <row> -> <result>; next: <row>`.
- A /goal condition must be a checkable sentence, not a bare file path. A path-only goal left the stop hook looping on 2026-09-24.
- Two tracker sessions raced on P0-1 on 2026-09-24 (the other wrote first at 19:40). Hash the vault copy right before writing; if the row is already done, write nothing, ask Gene, and stop.
- The `reqtools.py backlog` command writes `generated/BACKLOG.md` directly, bypassing the vault writer.
- Progress: P0-1 (owner-question sweep) done 2026-09-24 19:40; Q0 rows run Q0-1..Q0-17; Phase M (metric-profiles-r1, rows M1-M5) and A4 (Q-TRIP-WIRES-004) were added by the setup session at 19:29. P0-2 done 19:55 (all 17 Q0 answered, all recommended). P0-3 done 20:12 (BACKLOG.md re-published unchanged). A2 done 20:48 (FIX-REPORT-2.md; 58 package revisions moved, map in revision-map-r1b-to-r2.json). Next row: A2r (restricted clean re-review of L2-1/L2-2 -> claude-review-library-fix-list-r2b). A2r done ~21:10 (0 blocking/major). A3 done ~22:00: library-fix-list-r1 published (release review/approved/library-fix-list-r1-2026-09-24/), READY 55; next A4 (gene, Q-TRIP-WIRES-004). A4 done ~22:10: Gene chose per-attempt load cadence (Q0-18); rows A5-A8 (trip-wires-cadence-r1 amendment build/review/repair/approve) added; next A5.
- Publishing mechanics (A3): PyYAML safe_dump does NOT round-trip corpus YAML (0/64 at any width) — edit reviews/approvals/status by splicing top-level key blocks, then confirm `reqtools digest` MATCH. Readiness fixpoint via repeated `validate --readiness` on a scratch overlay (~30 s per run; 13 sweeps).
- Heredoc gotcha hit again in A2: a Python string with `review\amendments` wrote BEL (\a) into the tracker; scan for control bytes before every vault write.
- Another session may write the tracker between read and write: always diff the vault copy against the read copy and merge before writing; it happened on 2026-09-24 (P0-1, and again P0-3 at 20:12; Gene chose to close the extra session).

Related: [[project_library_fix_list_amendment_r1]], [[project_testdata_closeout_plan_2026-09-24]]
