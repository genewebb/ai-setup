---
name: reference_crewchief_sticky_filters
description: CrewChief sticky page filters persist in localStorage via crewchief-io.js getItem/setItem + FilterPersistence helper
metadata: 
  node_type: memory
  type: reference
  originSessionId: 9d8fc319-68e4-4547-b000-0c8f949ea498
  modified: 2026-08-02T22:02:53.784Z
---

CrewChief page filters persist across reloads/navigations (like TestAuto's sticky filters) via browser **localStorage**, not a service/DB.

Primitive: `wwwroot/js/crewchief-io.js` exposes `crewchiefIo.getItem(key)` / `crewchiefIo.setItem(key,value)` (try/catch → null/no-op if storage unavailable). Pages call these through injected `IJSRuntime`.

Pattern:
- Read in `OnAfterRenderAsync(firstRender)` (NOT OnInitialized — JS interop only works post-prerender on the interactive circuit), guarded by a `_..Loaded` bool; then set field + `StateHasChanged()`.
- Write on the change handler (fire-and-forget `_ = ...`).
- bUnit `JSRuntimeMode.Loose` returns default (null) for getItem → tests fall back to the default filter with no extra DI; verify writes with `ctx.JSInterop.VerifyInvoke("crewchiefIo.setItem")` and test restore with `ctx.JSInterop.Setup<string>("crewchiefIo.getItem", key).SetResult(...)`.

Multi-select tag filters use `FilterPersistence` (static helper, `...Components.Pages`): `LoadTagFilterAsync` (deserializes JSON list, intersects with currently-available values so removed tags don't linger) / `SaveTagFilterAsync` (JSON array; empty selection clears the key). Newtonsoft only.

Applied so far — keys:
- Activity status filter: `crewchief.activity.statusFilter` (plain string, handled inline in Activity.razor.cs).
- Steps tag filter: `crewchief.steps.tagFilter` (JSON list, via FilterPersistence).
- Workloads tag filter: `crewchief.workloads.tagFilter` (JSON list, via FilterPersistence).

**Radzen AllowClear → null crash (fixed 2026-07-17):** a `RadzenDropDown Multiple AllowClear` sets the bound `_selectedTags` to **null** when the user clicks "clear". A `FilterByTags` that did `selectedTags.ToList()` threw `ArgumentNullException` **during render** (get_FilteredWorkloads → BuildRenderTree), which tore down the whole circuit (followed by a cascade of `JSDisconnectedException` from Radzen's own DebounceFilter on the now-dead circuit). Fix: make the pure `FilterByTags` null-safe (`if (selectedTags is null) return all;`) on BOTH Steps and Workloads, AND normalize `_selectedTags ??= new()` in `OnSelectedTagsChanged` (also stops `SaveTagFilterAsync` NRE). Regression tests: `FilterByTags_NullSelectedTags_ReturnsAll*`. Rule: any client-side filter fed by a clearable Radzen control must treat null as "no filter".

The sticky-filter restore itself was confirmed WORKING on .NET 10 (the `OnAfterRenderAsync(firstRender)` pattern holds across page-to-page nav); the earlier "reverts to none" report was a pre-`ec5cdcff` build.

Any NEW filter anywhere should follow this same pattern. Related: [[project_crewchief_activity_merge]].

**View state (2026-08-02):** `Components/Pages/CardViewState.cs` owns view mode + cards-per-row + **page size** per screen — `crewchief.<page>.viewMode` / `.cardCols` / `.pageSize`, legacy dashed keys (`<page>-view-mode`, `-card-cols`) read as fallback and now **written forward** on restore. Screens: steps, workloads, workload-editor, refdata, activity. `RestoreAsync(JS, allowedPageSizes)` ignores a stored size the page no longer offers. Activity gained a card/list toggle (run micro-cards + a single `runDetailPanel` Razor template shared by table row and card panel) and is the only screen with `defaultCardView: false`. Steps/Workloads list grids bind `PageSize="@CardPageSize"` + `PageSizeChanged` so card and list share one sticky size; page **index** never persists.

**"Stickiness got lost everywhere at once" is usually the origin, not the code** — localStorage is per-origin, so the HTTPS/FQDN switch (`http://localhost:<port>` → `https://<fqdn>:<port>`) orphans every saved preference. Check the URL before hunting for a regression.
