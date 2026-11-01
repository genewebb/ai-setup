---
name: scorecard-wizard
description: >-
  Adapts the TestAuto.Web Matching scorecard wizard (4 steps, one chart series per workload execution, two-part
  baseline, read-only "Your comparison" panel, pick pills) to the other scorecards: CRUD (/version-compare, Batch CRUD
  and Stewardship) and Connect (/scorecards/connect). Use when asked to turn the CRUD or Connect scorecard into a
  wizard, to "make CRUD/Connect work like Matching", to add a run catalog, execution picker, per-execution series or
  pick pills to a scorecard, or to review such a port. NOT for the matching data itself (testauto-matching-* skills)
  or for writing a perf comparison report (skill-compare-performance-by-versions).
---

# Scorecard wizard: port the Matching pattern to CRUD and Connect

The Matching scorecard (`/scorecards/matching`) became a four-step wizard on 2026-10-29. Its mockup was approved as
Version 15 (artifact `QzYrz5HzKMyZQnRGnru4YJ`). This skill is the recipe for giving the CRUD and Connect scorecards the
same shape, reusing what Matching built rather than copying it.

## Gates (do not skip)

1. **Mockup first.** No code before Gene approves a mockup. Load `ui-ux-pro-max` and build the mockup as an artifact.
   Base it on the Matching mockup and swap in this family's steps. Iterate with AskUserQuestion until Gene says
   "approved".
2. **Plan, then build in slices.** Compile after every slice. Do not commit in speed-merchants: Gene commits.
3. **SQL on prod is Gene's.** Write the scripts. Prove them locally (see "Proving SQL"). Gene runs them on ScenarioMgt.
4. **Gene rebuilds and starts the app.** Never kill the running app. If the build is locked, say so.

## What Matching built (reuse these, file paths repo-relative)

| Piece | File | Reuse for CRUD / Connect |
|---|---|---|
| Pick pills (multi pick with All first, greyed + reason, counts, single-pick tab rows, wide pill with sub line, swatch) | `TestAuto.Web/Components/VersionCompare/PickPills.razor(.cs)` | As is |
| Step-3 table grouped by workflow run, checkbox per row and per group, read-only name | `.../ExecutionPicker.razor(.cs)` | Generalise: it takes `MatchRunInfo`; give it a small row interface or a second record |
| Chart / table card (collapse, Enlarge, Copy, PNG/JPG/PDF, Save, `Tools` slot for Export to Excel) | `.../ChartCard.razor(.cs)` | As is; tables go in its body |
| Table Copy/Save (paints HTML tables onto the canvas) | `TestAuto.Web/wwwroot/js/chart-export.js` `paintTable` | As is |
| Wizard CSS (`mw-*`: layout 375px panel + 56px rail, steps bar, pills, base bar, users bar) | `TestAuto.Web/wwwroot/css/version-compare.css` | As is |
| Execution catalog + unique series labels | `TestAuto.Web/Services/VersionCompare/MatchRunCatalog.cs` | Pattern; `SeriesLabels` logic can move to a shared helper |
| Run catalog table, labels table, sticky workflow link | `TestAuto.Utilities/Scripts/SQL/perfDashboard/22_MatchRunCatalog.sql` | Pattern for a CRUD/Connect catalog |
| Page state machine, view memory, deep links | `TestAuto.Web/Components/Pages/Matching.razor(.cs)` | Pattern |
| bUnit tests (wizard steps, pills, baseline, deep links, saved view) | `Testing.SpeedMerchants.Unit/Web/Components/Pages/MatchingPageTests.cs` | Pattern; its `Pill`, `ToCharts` helpers |

## The pattern, step by step

**Steps.** These are the steps Matching uses. For each family, map them to its own dimensions:

1. Versions and the family's "size" dimension.
2. The kind of run.
3. Workload executions.
4. Charts.

- Next is hidden on step 4.
- A step button is disabled until the earlier steps are valid.
- A remembered or linked step that is no longer reachable falls back to the last step that is.

**Pick sets.** A `null` set means "not picked yet", which counts as every available choice:

- The first toggle starts from all available choices.
- The All pill sets the group back to null, or clears it to empty.
- Versions are a real set: a new version comes in switched on (the `_seen` logic).

**One series per execution.**

- Relabel each run's `Version` with its series label before it reaches the calculator: `run with { Version = label }`.
- `ByVersion`, change tables, insights and charts then draw one series per execution without changes.
- Labels use `MatchRunCatalog.SeriesLabels`:
  - the version alone when it is unique in the tab;
  - version · M/d when the version repeats;
  - version · M/d · code when that still repeats.
- Labels are unique ignoring case, because the calculators group case-insensitively.

**Colours.**

- One colour per execution, indexed by execution order **within its chart tab**. A global index wraps the 10-colour
  palette, so two bars in one tab could otherwise share a colour.
- The side-panel swatch uses the same function, so it always matches the chart.

**Baseline in two parts.**

1. A version for the whole page. The default is the oldest picked version in `VersionOrder` (Gene ruling 10/29).
2. A run of that version, picked per chart tab:
   - the default is the earliest run;
   - with one run, the bar shows text ("the only X run on this tab");
   - with none, a note says the tab falls back to its earliest run;
   - changing the version clears the per-tab run picks.

**Chart tabs.** On step 4 there are two pill rows: the "size" dimension, then the kind of run at that size.

- Kinds with no run at that size are greyed, with the reason on hover.
- A kind with no data in the open view is greyed, with the reason. For Matching this is Lookup Before Create on
  Batch phases.
- Charts run full width with no horizontal scroll.

**Side panel "Your comparison".**

- Read only, with no Change links. Collapsible to a 56px rail, and the collapsed state is saved in the view.
- Rows: versions, baseline version only, size, kinds, any per-tab filter, executions (swatch, code, details; the
  first 8, then "and N more"), run conditions.

**Header.**

- Order: breadcrumb, store chip, Color theme select (left of Reload), Reload, Rebuild summaries.
- The old intro text becomes the hover text of Rebuild summaries.

**View memory.**

- Bump the page's `ViewShape`; an older shape is ignored.
- Store it in localStorage under the page's own key (never cookies).

**Deep links** (hub `?tab=&baseline=&versions=`). Keep them working, with one bUnit test each:

- `tab` opens the Charts step on that view;
- `versions` sets step 1 and resets the later picks;
- `baseline` sets the baseline version and clears the run picks.

## Mapping to CRUD and Connect (confirm every row with Gene at the mockup gate)

These pages are one component, `VersionCompare.razor(.cs)`, driven by `ScorecardPage`:

- `CrudPage` holds Batch and User.
- `ConnectPage` holds Connect.
- Rows are `PerfSummaryRow`.
- Dimensions come from `ScorecardFamilies` (`ScorecardFamily.cs`). For CRUD they are users, rules and attributes;
  attributes are hidden for Batch. For Connect they are providers, worker threads, page size, attributes and rules.
- Charts are chosen by `ChartKind`: Heatmap, Delta, Bars, Dumbbell, Range, Indexed, Absolute, Scalability.

The open questions below are guesses to put to Gene, not decisions:

| Matching concept | CRUD candidate | Connect candidate | Open question |
|---|---|---|---|
| Record volume | user load (scale dimension) | provider pair or page size | Which dimension is the "size" row on step 4? |
| Run type | operation (Create/Update/...) or Batch vs Stewardship tab | Import vs Export operation | Do the family tabs stay as the view toggle? |
| Simulated users filter (S3 tabs only) | none, or rules | worker threads | Is there a per-tab filter at all? |
| Batch phases / Latency toggle | the family tabs (Batch / Stewardship) | none (one family) | |
| Change table per tab | the existing heatmap or change table | same | Keep the chart picker (Heatmap ... Scalability) on step 4? |
| Execution picker | today executions start EMPTY ("the owner picks codes on purpose") | same | Matching starts with ALL picked; which does CRUD want? |

The CRUD rules still apply (see memory): the Speedy master/detail layout does not apply to scorecards; use mockups
first; use RadzenSwitch rather than SelectBar; use free OSS libraries only, with Radzen for charts.

## Data: a run catalog per family

Matching needed `perfDashboard.MatchRunCatalog` because the summaries carried neither the workflow run nor (for
latency) the volume. For CRUD and Connect:

- **Check first, read only** (prod MCP `speedmerchants-prod-mssql`). Do the summary tables already carry what the
  steps need: volume, users, run date, execution code? If they do, build the catalog in memory, as
  `MatchRunCatalog.Build` does, and skip the SQL.
- **The workflow link** follows this chain: `data.tWorkloadExecution.Code` = ExecutionId, then
  `data.tTestAutoWorkflowExecutionDetail.WorkloadExecution`, then `WorkflowExecutionParent`, then
  `data.tTestAutoWorkflowExecution` (Code, Name).
  - Detail rows are deleted when a workflow is reset or deleted, and parents are recreated on rerun.
  - So a catalog must keep a link it found once (**sticky** merge), and Gene must rebuild before resetting a workflow.
  - On 10/29, prod had 0 summary executions with a detail link. Expect "not started from a workflow" for old data.
- **Names:**
  - A label table (`ExecutionId`, `Label`, `ChangedBy`, `ChangedAt`) is seeded by the procedure.
  - Seeded labels are refreshed. A label whose `ChangedBy` is not `seed` is left alone.
  - The app only reads the table.
- **Rebuild:** `RebuildSql` runs the catalog procedure last, behind `IF OBJECT_ID(..., N'P') IS NOT NULL`, so the
  page works before the script runs. Add the procedure to the rebuild modal list.
- **Late columns:** read each optional column with its own `COL_LENGTH` check (one `DECLARE @x` per table, then
  `EXEC(@x)`), so a database built before the column exists reads NULL.

## Proving SQL (no prod DDL, ever)

- ScriptDom parse checks only syntax. To prove binding, run the scripts on the local dev DB (CORPLTR94 `speedmerchants`):
  - use `sqlcmd -E -b` with an outer `BEGIN TRAN` ... `ROLLBACK`;
  - pull in the scripts with `:r`;
  - insert SYNTHETIC rows after the summary procedures run (they delete or refill rows without source);
  - run the catalog procedure twice and SELECT the result.
- The local schema can lag prod. On 10/29 local had no `data.tUnifiedMatchingApiExecution.SourceRecordCount`. Add the
  missing column inside the same rolled-back transaction, after confirming on prod (read only) that it exists there.
- Never write `data.tWorkloadExecution`, even locally. Prove the sticky merge by pre-seeding catalog rows instead.
- After the run, check that nothing remains (`OBJECT_ID` is NULL).

## Traps met on the Matching build

- **Razor `<text>`:** inside an `@for`/`@if` block a bare `<text>` is the Razor text tag (error RZ1023, "cannot contain
  attributes"). Wrap SVG text in `<g>`.
- **Radzen button text:** `RadzenButton` text includes the icon name (`"downloadExport to Excel"`). In bUnit, match
  with `EndsWith` or `Contains`.
- **Collapsed cards:** `ChartCard` starts collapsed (owner 2026-10-28). bUnit page tests cascade `VcChartsOpen = true`.
  A test that renders the page without it sees no tables. Reuse the page test's `Render` helper.
- **"No change" band:** the band is ±`Labels.FlatPercent` (5%). Check that a test's expected percent is outside it.
- **Recomputed picks:** computed pick properties (`PickedRuns` and the like) run again on every call. Fine at tens of
  executions; cache per render if a page slows down.
- **Old test helpers:** a test that used the old drop-downs (`Option<T>`, `RadzenDropDown` names) breaks once the page
  moves to pills. Grep the test project for the page type before building.

## Verification checklist

- [ ] Web project builds; unit project builds.
- [ ] The page's bUnit tests are rewritten. Each of these has a test:
  - [ ] steps, Next and Back;
  - [ ] All pill, both ways;
  - [ ] greyed pill with its reason;
  - [ ] side panel collapse;
  - [ ] baseline version default, run default, and reset;
  - [ ] each deep-link parameter;
  - [ ] saved view (new shape) and old shape ignored;
  - [ ] rebuild modal lists the catalog procedure.
- [ ] Unit tests: series labels (unique ignoring case, the date path, the code path); catalog fill and name order.
- [ ] Whole unit project passes. Do not run integration tests on CORPLTR94: they hang before seeding.
- [ ] SQL proved locally in a rolled-back transaction, or the report says "parse-checked only".
- [ ] Final report lists the deviations from the mockup, the rollout order (scripts, Rebuild summaries once, rebuild
      catalog before any workflow reset, Gene rebuilds app), and the open questions.
