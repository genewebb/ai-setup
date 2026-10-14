---
name: tdg-ui-family-redesign
description: "TestData.Generation Home page redesigned 2026-08-19 to CrewChief family look — sticky run rail, gradient panel bands, details-collapsed optional panels"
metadata: 
  node_type: memory
  type: project
  originSessionId: d204104c-f778-4885-86a9-0ec54efcd4b0
  modified: 2026-08-19T14:18:42.096Z
---

TestData.Generation Home.razor/.css redesigned 2026-08-19 (markup+CSS only, zero code-behind changes, build clean):

- **Two-column shell**: `.tdg-grid` = config column + 400px sticky right rail (`.tdg-col-run`) holding Run + Progress cards; stacks under 1280px. Sticky needs `align-items:start` on the grid.
- **Family gradients** taken verbatim from CrewChief `wwwroot/app.css` (cc-header-*/stat-icon): purple 667eea→764ba2, cyan 4facfe→00f2fe, pink f093fb→f5576c, sunset fa709a→fee140, green 11998e→38ef7d; tokens `--tdg-grad-*`. Each panel gets a slim gradient header band (`.tdg-panel-head`); RadzenCard padding zeroed, content in `.tdg-panel-body` so bands run edge-to-edge.
- **Optional panels are native `<details>`** (Column widths, Attribute naming, Deploy package) — collapsed by default, no code-behind bool; Blazor differ leaves user-toggled `open` alone.
- **Progress = stat tiles** (`.tdg-stat-grid`, 2-up) with gradient chips + `.tdg-eta` completion strip.
- Icons in plain markup: `<i class="notranslate rzi">name</i>` — `.rzi` is Radzen material.css's bundled Material Symbols ligature class (verified in nuget package css). Only family-proven icon names used (dataset, tune, edit_note, outbound, play_circle, schedule, history, monitor_heart, chevron_right).
- Page ground `#f2f5f9` so white cards read as cards.

**Parity pass 2 (same day, after screenshot review)**: serif-font root cause = no Bootstrap + material.css only fonts .rz-* — fix in wwwroot/app.css (`body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana }`, ground #f8f9fa, html 14/16px), NOT scoped sheet (dialogs render outside .tdg-page). Cards → CrewChief metrics-card recipe verbatim (radius 12, shadow 0 4px 6px .07, border #e9ecef, header padding .85/1.25, h2 1.1rem/600, icon 1.35rem); page max-width 1400 centered; title 1.9rem #2c3e50, underline dropped. All checkboxes → RadzenSwitch (create-db/drop/test-mode), defaults off.

**Enhancements SHIPPED same day** (308 tests green): (1) `ShapeSizeEstimator` in Engine\Generation — samples 100 real generator rows (EntityPlan+DbaSeeder+SyntheticDataReader, same seed) for measured avg row bytes × TotalRecords; declared-width bound useless (Text default nvarchar(4000) vs short Lorem). UI memoizes on size-relevant key; RevalidateNaming/LoadShape invalidate. (2) Run-facts chip strip above Start (columns/lookups/rows/~GB). (3) Verify-only button = Web twin of CLI --verify-only via `new Verifier(def, EntityPlan.Build(def))`. (4) Live tab title "43% · TestData Generation" via window.tdgSetTitle in App.razor + IJSRuntime in RepaintAsync. (5) `RunHistoryStore` (Web\Services, RunHistory\runhistory.json beside binaries, cap 20, failures swallowed) fed by GenerationRunService finally-block; Recent-runs list in Progress rail.

Related: [[project_perftestdata_generator]], [[project_crewchief_ui_conventions_2026-07]].
