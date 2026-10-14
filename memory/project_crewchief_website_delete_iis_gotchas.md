---
name: crewchief-website-delete-iis-gotchas
description: "WebSite Delete fixes 2026-08-26 — three IIS teardown defects (stop-before-remove poisons the commit, nested apps are flat siblings, orphan set read after mutation); verified live on SMVM2"
metadata: 
  node_type: memory
  type: project
  originSessionId: 8ef1cab9-d624-45b8-8f0e-1737f389d149
  modified: 2026-08-26T21:19:40.627Z
---

Three defects fixed 2026-08-26 in CrewChief's WebSite Delete, both paths (`DefaultWebSiteRunner`
ServerManager + `RemoteWindowsOps.BuildWebSiteControlScript`). Verified live on SMVM2: 19 orphaned
Profisee apps and their pools removed. See [[project_crewchief_website_step.md]].

1. **Never stop before removing.** `Site.Stop()` / `Stop-Website` persists `serverAutoStart="false"`
   into applicationHost.config out of band, so the NEXT `CommitChanges` / `Remove-Website` fails
   against a copy that is now stale on disk. Symptom: delete fails the first time, passes on the
   re-run — because run 1 left the site Stopped and run 2 skips the stop. Removing the site/pool from
   config is sufficient; IIS tears the workers down. Same trap in `Stop-WebAppPool` → `Remove-WebAppPool`.
   **`IAppPoolRunner` Delete still has this pattern** (stop-then-commit) — latent, only bites a RUNNING pool.

2. **IIS applications are FLAT config entries, not a tree.** `/Profisee` and `/Profisee/api` are
   SIBLINGS. Removing `/Profisee` alone strands all 19 `/Profisee/*` apps in applicationHost.config,
   and their pools then read "still in use" forever. Delete must take the whole subtree,
   **deepest first by segment depth** (not string length — `/Profisee/abcdefghij` is longer but
   shallower than `/Profisee/api/data`). Apps first, then pools: deleting a pool first leaves its app
   pointing at nothing and it serves 503 instead of being cleanly gone.
   `ProfiseeDevUtils/Infrastructure/IIS.cs` (dev-utilities repo) shows the same order — `Profisee\api`
   then `Profisee` — and uses the **backslash** form for a nested `Remove-WebApplication -Name`.

3. **Read the "still in use" set BEFORE the mutation.** Computing it afterwards asks the cmdlets to
   re-read config they have just written; one stale read reports every candidate as in use and
   silently keeps every orphan. Kept pools are now reported WITH the reason
   (`WebSiteRunResult.SkippedAppPools` / `.Note`) — the silent skip is what hid this for weeks.

**A pool whose app is already gone can never be found by a site/app delete** — nothing in config links
it any more. Needs an AppPool Delete step naming it explicitly.

**IIS Manager lies for a minute or two.** Pools/apps kept showing after a successful delete until a
manual refresh. Verify with `appcmd list apps` / `appcmd list app "<path>"`, never the MMC snap-in —
`appcmd list app` silently resolving to the PARENT path is how you prove an app is absent.
