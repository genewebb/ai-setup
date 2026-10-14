---
name: feedback-speedy-view-memory-localstorage
description: "Speedy screens remember cards/list view and page size in browser localStorage like CrewChief/TestAuto, static SSR screens included (never cookies)"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 0359fc02-cccc-4830-81fb-20a4bcd43ea3
  modified: 2026-09-24T17:40:19.820Z
---

Every Speedy list screen remembers its cards/list view and page size in the browser's localStorage under `speedy.<screen>.view` / `speedy.<screen>.size`, the way CrewChief (`crewchief.<page>.viewMode`, CardViewState) and TestAuto do. Static-SSR screens (Secrets, Reference Data) included: server draws only what the address names plus a hidden `StaticStickyMarker`; `wwwroot/js/static-sticky.js` stores named values and re-navigates with a remembered one when the address omits it. The address always wins.

**Why:** Gene 2026-09-24, asked cookie vs localStorage for Secrets: "Do it the same way that crewchief and testauto do that today", then picked both static screens. The earlier cookie (`speedy.view.<screen>`) was an implementation shortcut he did not want.

**How to apply:** Any new screen with a view toggle or pager reuses StickyView (interactive) or StaticStickyMarker + static-sticky.js (static). Never add a cookie for UI preferences. Related: [[feedback-speedy-ui-is-crewchief-look-and-feel]] [[project_library_fix_list_amendment_r1]]
