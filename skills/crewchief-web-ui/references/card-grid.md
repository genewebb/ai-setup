# Card Grid — StepCard and WorkloadCard

Reference for the `crewchief-web-ui` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Card grid — `StepCard` / `WorkloadCard` (`Controls/StepCard.razor(.cs)`, `WorkloadCard.razor(.cs)`)
The Steps and Workloads pages offer a **Card vs List view toggle** (two `RadzenButton`s in a
`.cc-view-toggle` group; `SetViewAsync` persists the choice per page via crewchief-io.js): card view renders a
`.cc-card-grid` of `StepCard`/`WorkloadCard` components (`Steps.razor:106`, `Workloads.razor:87`,
`WorkloadEditor.razor:282` — all three render `<div class="cc-card-grid @CardColsClass">`);
list view keeps the **retained `RadzenDataGrid`** — the grid was not replaced. Card parameters:
`Selected` + `ShowSelect` (multi-select checkbox), `IsRunning`, and per-action `EventCallback`s
`OnRun`/`OnEdit`/`OnCopy`/`OnRename`/`OnExport`/`OnDelete` (+ `OnToggleSelect`) — the secondary
actions live in a kebab **overflow menu**. `WorkloadCard` adds a
`StepCount` "N steps" pill. Shared card CSS (accent via `--cc-accent`, micro-row layout,
`.cc-card-grid`) lives in `wwwroot/app.css`; `WorkloadEditor` and `KeyValueReferenceData` reuse
`.cc-card-grid` too. Card view has its own pager footer (page size + prev/next), always visible.

**`StepCard` and `WorkloadCard` are both three rows, and must never hide what the list view shows.**
Row 1 = select box + icon + name + Run/Edit/⋮ — the name owns the row (status used to share it and cut long
names to a few characters). Row 2 = type name (StepCard) or "N steps" pill (WorkloadCard) · folder, then
status pushed right: the **Shadowed** badge (`ShadowedBy`, same testid `shadowed-badge` and wording as the
list's Name column), the compact `ReconciliationBadge`, and a compact `CapabilityBadge` (`CapabilitySteps` —
**null renders no capability badge**, so a test context without an `ICapabilityAdvisor` still renders the
card). Row 3 = StepCard: description + note indicator + tag chips; WorkloadCard: **`LastRunChip`** (when
`ShowLastRun`) + description + tag chips. Row-2 styles and the 0.75rem micro-card tag size live in
`wwwroot/app.css` under "Three-line library cards", shared by both cards.

**`WorkloadCard.IsRunning` means THIS workload is running** (`Coordinator.CurrentRun` is a workload run of
that name); `RunBlocked` is the separate "the app's single run slot is taken" flag that disables Run and
Resume. Passing the page-wide `Coordinator.IsBusy` as `IsRunning` spun every card at once — the Workloads
page says which run holds the slot ONCE, in `data-testid=running-notice`.

**`LastRunChip`** (`Controls/LastRunChip.razor`): a workload's newest run from `RunDisplay.LatestRunsByName(
RunHistory.GetAll(), "workload")` (null history → empty map). States (`data-state`): never / running (the
coordinator's live run) / succeeded / failed / cancelled / unfinished (`Outcome=="Running"` on disk but NOT
the live run — the app stopped mid-run). The chip links to `/activity`; a separate Resume button renders only
when `RunDisplay.CanResume` (Failed/Cancelled) and routes through the page's own `ResumeAsync`, so the shape
guard and capability preflight still apply. Used in both the card and the list view's "Last run" column.

**`ItemOverflowMenu` is the ONE Copy/Rename/[Export steps]/Export/Delete menu** for a library item —
`StepCard`, `WorkloadCard` and both list views' Actions columns render it (a list row is Run + Edit + ⋮, no
longer six or seven buttons). `OnExportSteps` adds "Export steps to library" only when a handler is supplied
(workloads); `ExportTitle`/`ExportLabel` default to `Export step bundle`/`Export` (workloads pass `Export
bundle`). Items keep their `title`s, are always in the DOM, and Delete sits below a divider. It opens
**`position: fixed` at the click point** (`MouseEventArgs.ClientX/Y`, right-aligned via
`translateX(-100%)`): a Radzen grid cell clips its content and the grid body scrolls, so an
absolutely-positioned dropdown in a list row is cut off. A `transform` on any ancestor would break the fixed
placement — the same reason micro cards stay flat on hover.

**`.cc-card-grid` is a FIXED grid, not auto-fill**: the base class is
`grid-template-columns: repeat(3, minmax(0, 1fr))` (3-up desktop default — it *was* a 280px
auto-fill that packed 5-6 skinny columns on a wide monitor), with `.cc-card-grid--2` / `--4`
modifier classes for 2/4 columns. The narrow-screen media queries are **declared AFTER the
modifiers so they win at equal specificity**: ≤1200px clamps every choice to 2-up, ≤768px to 1-up.

**Cards-per-row picker (2/3/4) — state lives in the shared `CardViewState`, NOT on the pages**:
`Components/Pages/CardViewState.cs` is the ONE implementation of list-page card/list view state —
card-vs-list toggle, cards-per-row, and page index/size with a `PageSize => Math.Max(1, …)` guard
so `PageCount` can never divide by zero (a hand-rolled copy once killed the circuit that way).

Steps / Workloads / WorkloadEditor each hold a `CardViewState` instance (`_cards`) and keep their
old member names as **thin delegating one-liners**, so the markup never changed:

```csharp
// Steps.razor.cs:47-51 (Workloads.razor.cs:59-63, WorkloadEditor.razor.cs:300-304 identical)
private string CardColsClass => _cards.ColsClass;
private int _cardCols       => _cards.Cols;
private Task SetCardColsAsync(int cols) => _cards.SetColsAsync(JS, cols);
```

Note `_cardCols` is an expression-bodied **property**, not a field — do not assign to it; call
`SetCardColsAsync`. Behaviour now owned by `CardViewState`:

- `Cols` defaults to **3**; `SetColsAsync` clamps 2–4 (`CardViewState.cs:83`) and persists.
- `ColsClass` maps 2 → `cc-card-grid--2`, 4 → `cc-card-grid--4`, 3 → `string.Empty`
  (`CardViewState.cs:63`) — 3 is the `.cc-card-grid` base.
- `ColumnOptions` is a **static** `IReadOnlyList<SegmentedOption<int>>` on `CardViewState`
  (`:66-71`), replacing what used to be three identical per-page `CardColumnOptions` copies.
- Storage keys are standardized on the dotted form `crewchief.<pageKey>.viewMode` /
  `crewchief.<pageKey>.cardCols` (`:45-46`). The old dashed keys (`steps-card-cols`,
  `workloads-card-cols`, `workload-editor-card-cols`) are read **once as a fallback** by
  `GetItemWithLegacyFallbackAsync` (`:180-187`) so no saved preference is lost.
- `RestoreAsync(JS)` does the first-interactive-render restore and is **idempotent** via an internal
  `_restored` flag (`:93-96`) — it replaces the five divergent per-page first-render guards. Call it
  from `OnAfterRenderAsync(firstRender)`; it returns `true` when something changed, i.e. when you
  must `StateHasChanged()`. Every storage call is best-effort: no JS (prerender, storage disabled)
  degrades to defaults, never an error.
- `SetViewTransient(bool)` switches view **without persisting** — for navigation side effects (a
  card's Edit jumping to the detail list), which are not a preference change.

When adding a new list page, construct a `CardViewState(pageKey, defaultPageSize, legacyKeyPrefix,
defaultCardView)` and delegate — do not hand-roll another paging/cols block. The picker itself is a
`SegmentedToggle TValue="int"` rendered next to the card/list view toggle **only while in card
view**. `KeyValueReferenceData` keeps the plain 3-up default — no picker.

**WorkloadEditor card-view move buttons**: the card toolbar has four move buttons (Move to top /
up / down / bottom; `.cc-cardbtn--move`, `background: #94a3b8`) calling the **same**
`MoveEntryToTop`/`MoveEntryUp`/`MoveEntryDown`/`MoveEntryToBottom` handlers and icons as the detail
list, disabled at the ends (`index == 0` / `index == _entries.Count - 1`). The card `@for` loop
iterates the page slice (`StepCardFirstIndex..StepCardEndIndex`) but `index` stays the entry's
**absolute** position in `_entries`, so moves (and the number circle) are paging-safe.

**Shared run monitor**: starting a run from Workloads or WorkloadEditor goes through
`HandleStartResult` → `_showingRunMonitor = true`, which opens the shared compact
`Controls/WorkloadRunMonitor.razor(.cs)` (`@bind-Visible`) with an **"Open Activity"** hand-off
button — the former page-local run-dialog copies were deleted. Its full contract (polling, live
output tail, duration display) is in [[crewchief-workload-and-runs]] — reference, don't duplicate.
