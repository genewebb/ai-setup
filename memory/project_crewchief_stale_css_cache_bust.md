---
name: project_crewchief_stale_css_cache_bust
description: CrewChief.Web served stale CSS after republish (plain UseStaticFiles + unversioned links) — UI redesigns looked unstyled; fixed with MVID ?v= fingerprints in App.razor
metadata: 
  node_type: memory
  type: project
  originSessionId: 1972b516-f552-4d7c-a424-c78cb065beeb
  modified: 2026-07-22T01:39:23.203Z
---

**Root cause of repeated "the UI still looks wrong / rebuilt, no change" reports (found 2026-07-21):**
CrewChief.Web uses plain `app.UseStaticFiles()` (Program.cs — NOT MapStaticAssets) and App.razor linked
`app.css` / `CrewChief.Web.styles.css` with **unversioned URLs**. No Cache-Control → browsers apply
heuristic caching and keep the OLD stylesheet after a republish, while markup updates live over SignalR.
Symptom: brand-new markup renders completely unstyled (e.g. the Configure wizard showed as a bulleted
vertical list of default buttons with count text glued to labels — user screenshot). The styles WERE
present in the published `wwwroot/CrewChief.Web.styles.css`; the browser just never refetched it.

**Fix:** `Components/App.razor.cs` defines `internal static readonly string AssetVersion` =
`typeof(App).Assembly.ManifestModule.ModuleVersionId.ToString("N")[..8]` (changes every build), and
App.razor appends `?v=@AssetVersion` to `app.css`, `CrewChief.Web.styles.css`, `js/help-docs.js`,
`js/crewchief-io.js`. Every rebuild → new URL → cache can never be stale.

**Why:** any future "I changed the CSS but it looks the same" report — check delivery/caching BEFORE
redesigning markup. Verify with: does the published/obj `scopedcss/bundle/CrewChief.Web.styles.css`
contain the new selector? If yes, it's cache/delivery, not the component.

**How to apply:** keep the `?v=` pattern on any newly-linked local static asset in App.razor; don't
remove AssetVersion; if MapStaticAssets is ever adopted, switch to `@Assets[...]` fingerprinting instead.

Related: [[project_crewchief_configure_switches]] (the wizard whose styling this masked),
[[project-crewchief-ui-conventions-2026-07]]
