---
name: reference-playwright-enhanced-nav-waitforloadstate
description: "Blazor enhanced navigation under Playwright - a clicked link IS requested (as fetch), but WaitForLoadState returns instantly, so asserts read the pre-click DOM"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 2a529a18-ca19-4ca7-9770-df371ae3ba24
  modified: 2026-09-21T15:38:26.907Z
---

In Speedy (static SSR + blazor.web.js), clicking an in-page `<a href>` does an ENHANCED navigation: a `fetch` (resource type fetch, not document) whose response is patched into the loaded DOM. Under Playwright, `WaitForLoadStateAsync(NetworkIdle)` returns immediately for the already-loaded document, so a count taken right after reads the page BEFORE the patch. Looked like "click produces no server request" (interface-audit O-1, open for days) — measured 2026-09-21: request made, 200, DOM patched ~later.

**Fix:** after a click, wait on an element that exists ONLY at the destination (e.g. `[aria-current='true']` on the chosen card, the destination pane's marker) — never on something the pre-click page already had.

**Why it mattered:** the workaround (load hrefs cold instead of clicking) hid a real defect — Secrets section/edit links dropped `profile=` and landed on an empty screen. Cold loads always started from a profile-bearing address. Clicking-for-real found it. Related: [[feedback-verify-no-guessing]].
