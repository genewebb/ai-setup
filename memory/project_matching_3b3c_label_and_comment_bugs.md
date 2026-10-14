---
name: project_matching_3b3c_label_and_comment_bugs
description: Two open TestAuto matching CODE issues (backlog) surfaced by the 2026-07-23 Mode 6 skill review — misleading Template_Scenario3B display label + reversed 3B/3C OperationType XML comments in MatchingOperationExecutor
metadata: 
  node_type: memory
  type: project
  originSessionId: e25dbfb4-02af-4011-8c05-18e207b68e9c
  modified: 2026-07-23T17:56:03.783Z
---

Two open **repo-code** work items in the TestAuto matching subsystem, surfaced (not fixed) during the 2026-07-23 Mode 6 skill-corpus review. Both are genuine code inconsistencies — NOT skill errors — and were deliberately left for the user to decide on. Tracked here as backlog.

**1. Misleading `Template_Scenario3B` display label.**
`UnifiedMatchingScenarioEditor.razor.cs:1123` ships `Template_Scenario3B = "Scenario 3B: Lookup + Create"`, but Scenario 3B operates as **`LookupOnly`** (RecordSource `NewValuesOnly`, no create — per-lookup scoring, mirrors 3A). Confirmed by the shipped sample config `UnifiedMatching_Scenario3B_LookupScoring_Small.json:28` (`"OperationType": "LookupOnly"`). The label says "Create" but nothing is created. Consider relabeling to "Scenario 3B: Lookup / Scoring" (or similar) — verify no code keys off the literal string first (it's a `const` used as a template key).

**2. Reversed 3B/3C OperationType XML doc-comments — the drift ORIGIN.**
`MatchingOperationExecutor.cs` (~lines 71-82, also 87/135/220 per the reviewer) has XML comments mapping 3B→create/LookupThenCreate and 3C→CreateOnly. That's **backwards**: real mapping (sample configs + top matrix) is **3B = LookupOnly, 3C = LookupThenCreate** (3C-Continuous uses `WaitForMatching=false`). These stale comments were the source that propagated the reversed mapping into the `testauto-matching-scenarios` skill's deep-dive (skill fixed 2026-07-23; the code comments are still wrong). Fix = correct the XML comments to match actual dispatch behavior.

**Why:** left for user decision because the scan target is read-only during skill audits and repo edits need explicit authorization; user asked to log them as work backlog.
**How to apply:** small, self-contained edits — (1) rename the const value (grep for the literal first), (2) rewrite the XML comments. No behavior change; label/comment only. See [[project_crewchief_review_2026-07-17]] pattern of surfacing repo-side issues as informational.
