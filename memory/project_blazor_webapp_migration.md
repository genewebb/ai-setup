---
name: project_blazor_webapp_migration
description: "TestAuto.Web migrated 2026-07-13 from legacy Blazor Server to the Blazor Web App model (net10) — hosting shape, deleted files, PersistentState, reconnect + static-asset gotchas"
metadata: 
  node_type: memory
  type: project
  originSessionId: 41312f61-f553-4040-94c7-96d9550ee761
---

On 2026-07-13 (workflow `wf_d26481c4-e9d`, branch `bug/documentation_updates/genewebb`) TestAuto.Web was migrated from the legacy Blazor Server model to the **Blazor Web App model**, plus the quick wins from `Plan_Net10BlazorAdoption.md` (Obsidian planning folder). All builds 0 warnings/0 errors; 4/4 new bUnit grid tests pass. **Verification status (2026-07-13):** user confirmed the app compiles and BASIC live testing passed post-migration; DETAILED testing (full 30-page click-through, circuit-resume-with-state, reconnect window, first-paint asset check — the LIVE-VERIFY checklist in Plan_Net10BlazorAdoption.md) still to follow. Not merged/committed at write time.

**New hosting shape (don't reintroduce the old one):**
- `Program.cs`: `AddRazorComponents().AddInteractiveServerComponents(...)` (CircuitOptions + AddHubOptions preserved on the chain). `AddRazorPages()` REMOVED.
- `PipelineExtensions.cs`: `UseAntiforgery()` (line ~100, after auth, before endpoints) + `MapRazorComponents<TestAuto.Web.Components.App>().AddInteractiveServerRenderMode()` (~162). `MapBlazorHub`/`MapFallbackToPage` gone.
- `Components/App.razor` = root HTML document (`blazor.web.js` autostart=false, script order preserved, `blazor-reconnect.js` last, `<ResourcePreloader />` after `<base>`); `Components/Routes.razor` = router; `@rendermode="InteractiveServer"` on HeadOutlet + Routes. App.razor carries its own `@using static ...Web.RenderMode` because the root `_imports.razor` (lowercase) lacks it.
- **`TestAuto.Web/Pages/` is fully deleted** — `_Host.cshtml` plus the `Docs/*` Razor Pages + `Shared/_ValidationSummary.cshtml`, which were confirmed dead (MapRazorPages was never called). `/docs` now hits Blazor NotFound.

**Grids (A2/A3):** ExecutionMonitoring's two tables and ExecutionHistory's table are now `RadzenDataGrid` (Template columns over `Record` + existing helpers). ExecutionMonitoring keeps its own **server-side paging** controls — grid paging OFF (enabling it would double-paginate); ExecutionHistory uses client grid paging (PageSize 25). Row highlight preserved via `RowRender`+`GetRowClass`. The `PeriodicTimer` loop calls `grid.Reload()` via `@ref`. Tests: `ExecutionMonitoringGridTests` + `ExecutionHistoryGridTests` (bUnit, **Moq — NOT NSubstitute**, which is not in CPM; assert on `tr.rz-data-row`).

**[PersistentState] (C1):** 10 public props on `ExecutionMonitoring.razor.cs` (filters, page sizes, current pages). Page sizes use a 0-sentinel so `LoadConfiguration` only applies the WebUI default when nothing was rehydrated. Data collections deliberately NOT persisted (re-fetched). HighlightedJobId not persisted (derived from ?jobId).

**Reconnect (A1→C2):** `blazor-reconnect.js` now passes ONLY `circuit: { reconnectionOptions: { maxRetries:100, retryIntervalMilliseconds:3000 } }` (blazor.web.js shape). Key finding: the app supplies NO reconnect-modal element, so blazor.web.js uses `DefaultReconnectDisplay` (open shadow root, id `components-reconnect-modal`, never applies state classes to the host) → the file's MutationObserver failsafe is **inert by design** on this path; the framework self-heals (rejected→reload, failed→retry on visibilitychange — a backgrounded tab may look dead until focused). Observer also handles the new `components-reconnect-resume-failed` class for the user-modal path.

**Static assets (C3):** `UseStaticFiles()` → `MapStaticAssets()` (endpoint mapping). GOTCHA: files dropped into wwwroot at RUNTIME are NOT served by MapStaticAssets (build-time manifest) — re-add UseStaticFiles alongside if that need arises. `asp-append-version` cache-busting is gone (tag helpers don't run in razor components); fingerprinting via MapStaticAssets replaces it.

**Loose ends:** `TestAuto.DependencyInjection\Documentation\ReadMe.md` (~66-82) still shows the legacy AddServerSideBlazor/_Host example (out of scope, flagged). Timer tick Reload()s the history grid without refetching it (harmless, pre-existing data flow). B0 audit doc: `Net10Blazor_MigrationAudit.md` (zero NEEDS-FIX; also lists 5 optional localStorage-read cleanups). Related: [[project_net10_profisee_upgrade]], [[feedback_radzenswitch_not_selectbar]], [[feedback_ui_parity_before_new]].
