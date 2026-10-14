---
name: blazormonaco-integration-gotchas
description: "BlazorMonaco 3.4.0 wiring — never add require.config (breaks the JSON worker), window.monaco loads async, readiness probe + textarea fallback pattern"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 7dc6c870-9aa7-4891-a85e-d99e95480385
  modified: 2026-07-28T15:51:11.455Z
---

From shipping Monaco in CrewChief.Web (mirrors TestAuto.Web):

- **Exactly three script tags** before `blazor.web.js`: `_content/BlazorMonaco/jsInterop.js`, `.../vs/loader.js`, `.../vs/editor/editor.main.js`. **Never add an inline `require.config({ paths: { vs: ... } })`** — `jsInterop.js:1` already sets an ABSOLUTE `paths.vs` (`document.baseURI + ...`); overriding it with a page-relative string breaks `require.toUrl` inside Monaco's Blob-based worker bootstrap, so the JSON language worker silently never starts (editor looks fine, **no error squiggles**).
- `editor.main.js` does NOT set `window.monaco` — that happens in `editor.api-*.js`, a separate file the AMD loader fetches **asynchronously**. So "the script tags are synchronous" does not make `monaco` available at first render.
- Pattern that works: `crewchiefIo.isMonacoReady()` (`typeof window.monaco !== "undefined"`), re-probed on every render while `!_libraryReady`, `StateHasChanged` only on the ready transition (else render loop), one `Logger.Warning` on not-ready, textarea fallback (`data-testid="monaco-fallback"`) otherwise.
- **bUnit always exercises the textarea fallback** (loose JSInterop returns false to the probe forever). The textarea's content is a `value` attribute — assert `cut.Markup`, never `.TextContent`. Nothing in the unit suite can prove Monaco actually mounts or the worker starts — that needs one manual browser check (squiggles on broken JSON).
- Central package management: version pinned in BOTH `CrewChief/Directory.Packages.props` and root `Directory.Packages.props` (keep equal, 3.4.0).

Related: [[crewchief-raw-json-panes]].
