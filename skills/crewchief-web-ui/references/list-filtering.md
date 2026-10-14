# Sticky Filters and Multi-Facet List Filtering

Reference for the `crewchief-web-ui` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Sticky filters
- `wwwroot/js/crewchief-io.js` exposes `crewchiefIo.getItem`/`setItem` (localStorage, degrade-safe)
  and `downloadText` (Blob download for workload-bundle export).
- `Components/Pages/FilterPersistence.cs` is a best-effort helper
  (`LoadTagFilterAsync`/`SaveTagFilterAsync`) that serializes a tag list to JSON, drops tags no
  longer available on restore, and swallows JS-unavailable / malformed-JSON errors. Restore in
  `OnAfterRenderAsync(firstRender)`; save on change.
- **Inconsistency to know**: `Activity.razor.cs` calls `JS.InvokeAsync("crewchiefIo.getItem"/…)`
  **inline** rather than going through `FilterPersistence` — a minor divergence, not a second helper.
- See memory [[reference_crewchief_sticky_filters]].

## Multi-facet list filtering (Steps + Workloads)
- Both list pages carry a **facet row** built from **pure, static, testable** filter methods composed
  over one another. **Steps** has **4 facets** — Name / Description / Tags / **Type**:
  `FilterByDescription(FilterByName(FilterByType(FilterByTags(_steps, _selectedTags), _selectedTypes),
  _nameFilter), _descriptionFilter)`. **Workloads** has **3** — Name / Description / Tags, **no Type
  facet** (a workload has no Type): `FilterByDescription(FilterByName(FilterByTags(...), _nameFilter),
  _descriptionFilter)`.
- `FilterByName`/`FilterByDescription` both delegate to a shared `FilterByText(items, search, selector)`
  (case-insensitive `Contains`, blank/whitespace = match-all). The Steps **Type** dropdown is fed by
  `TypeOptions` — distinct `Step.Type` projected through a `TypeFilterOption(Value, Text)` record
  (canonical value + friendly `UtilityStepTypeInfo.GetDisplayName`).
- **Tag semantics are deliberately OR (ANY), not AND (ALL)**: a row matches if it carries *any* selected
  tag; Type is likewise OR. Radzen's `AllowClear` sets the bound list to null on clear, so every filter
  method treats null as "no filter" (a past NRE tore down the circuit).
- **Of the facets, only the tag filter is sticky** (`FilterPersistence` + the `crewchief.steps.tagFilter`
  key). The Name / Description / Type facets are plain fields (`_nameFilter` / `_descriptionFilter` /
  `_selectedTypes`) — intentionally **NOT persisted**. (Activity's status filter is sticky too, under
  `crewchief.activity.statusFilter`.)

## Steps + Workloads pages: active-filter chips, selection bar, empty state
The two library pages share this shape, and the logic lives in `ListFilters.cs` so they cannot drift:
`ActiveFilterChip` + `ActiveFilterChips.Build` (keys `FolderKey`/`NameKey`/`DescriptionKey`/`ParamsKey`/
`TagPrefix`/`TypePrefix`), `ListFilters.HiddenSelection`, `ListFilters.OutsideFolder`. The page statics
`Steps.BuildActiveFilterChips` / `HiddenSelection` / `StepsOutsideFolder` and
`Workloads.WorkloadsOutsideFolder` are thin tested delegates. **The page property is `ActiveChips`, not
`ActiveFilterChips`** — a page property with the class's name shadows the static class inside the page.
- **Facet order is identical**: Name, Description, Tags, [Type — Steps only], Params.
- **Every active facet renders as a removable chip** above the results: folder, tags, type, name,
  description, params, with **Clear all** and "N of M steps/workloads". Folder and tag chips are amber
  (`Remembered`) because those two are restored from localStorage — the page can open already narrowed.
  Removing a chip goes through the facet's OWN handler (paging reset, persistence); a tag removal assigns a
  **new** list (Radzen stale-selection trap).
- **Bulk actions live in a selection bar**, rendered only while something is checked: count, "N hidden by
  filters", `BulkTagBar`, Check Capability (`data-testid=check-capability`), [Merge Selected — Workloads],
  Delete Selected, Clear selection. The headers keep only Import + Add. Neither page has a Check Capability
  button with nothing ticked (WorkloadEditor still shows a disabled one — it acts on the whole workload).
- **The selection survives filter changes**, so bulk delete opens a confirm that **names every checked item
  and flags the filter-hidden ones**, with "Only delete the N visible". Deleted names leave the selection;
  a hidden one skipped by "only visible" (or a failed delete) stays checked. The Workloads confirm also
  names, per row, the workloads OUTSIDE the selection whose `RunWorkloadStep` runs it
  (see [[crewchief-nested-workloads]]).
- **One empty state for both views**: "No steps/workloads yet" (Import / Add) for an empty library,
  otherwise "No … match these filters" + the chip labels + Clear filters. When a folder is selected,
  `OutsideFolder` (the other filters re-run with the folder facet off, minus the folder and its children)
  drives "N match in other folders: name (folder)…" and a **Search all folders** button. An empty library
  therefore renders a SECOND Import button — target the header one by `title` in a test.

## Sticky view state — `CardViewState` (the other half)
- One `CardViewState` per screen owns **view mode + cards-per-row + page size**, all persisted:
  `crewchief.<page>.viewMode` / `.cardCols` / `.pageSize`, with the OLD dashed keys
  (`<page>-view-mode` / `-card-cols`) read as a fallback **and written forward** on first restore.
- Screens: `steps`, `workloads`, `workload-editor`, `refdata`, `activity`. Every one restores in
  `OnAfterRenderAsync(firstRender)` via `RestoreAsync(JS, allowedPageSizes)` — the allow-list is the
  page's Per-page options, so a stored size the page no longer offers is ignored.
- **Activity** has a card/list toggle too (run micro-cards + one shared `runDetailPanel` Razor template
  rendered by both presentations) and is the ONE screen constructed with `defaultCardView: false`.
- On Steps/Workloads the Radzen grid's rows-per-page is the SAME sticky size as the card grid
  (`PageSize="@CardPageSize"` + `PageSizeChanged`). Page **index** is deliberately not persisted.
- Reference Data has the 2/3/4 picker as well; its scoped `.cc-typegrid` rule must NOT set
  `grid-template-columns` or it out-specifies the `.cc-card-grid--2/--4` modifiers.
- Nothing here survives an **origin change** — localStorage is per-origin, so moving from
  `http://localhost:<port>` to `https://<fqdn>:<port>` looks exactly like "the stickiness was lost".
- **Radzen grid gotcha**: after the bound list is swapped (delete/save → `RefreshFromStore`), hold the
  grid via `@ref` (`_stepsGrid` / `_workloadsGrid`) and call `grid.Reload()` (through `InvokeAsync`) or
  Radzen reverts a `Data`-bound grid to its **unsorted** view. Sortable **synthetic keys**
  (`TagsSortKey`, `StepCount`) back the Tags/Steps columns, and the grids set `AllowColumnResize`.
