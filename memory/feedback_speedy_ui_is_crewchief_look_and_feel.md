---
name: feedback-speedy-ui-is-crewchief-look-and-feel
description: "The speedy UI wears CrewChief's full look and feel (layout, sidebar, type, components, colours), not a re-coloured speedy instrument kit; depart only where speedy needs something CrewChief lacks"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 22d5dbd3-c155-4749-bee7-fcbb38ec1329
  modified: 2026-09-17T03:40:26.410Z
---

The speedy web UI must look and feel like CrewChief.Web: its own stylesheets (Bootstrap 5.3.0, Radzen material-base, `wwwroot/app.css`), dark `#111827` left sidebar with Material Icons, white top row, page title + subtitle, pastel stat tiles, bordered tables with coloured left edge, pill badges, Segoe UI type. Change it only where a speedy screen needs something CrewChief has no pattern for (tachometer, throttle), and list each such departure with its reason.

**Why:** Gene rejected 52.P1.8a attempt 1 on 2026-09-14: it only swapped the dark palette values in speedy.css to CrewChief colours, keeping speedy's condensed display type, mono letter-spaced labels, dark header bars and tile grid, so every screen still read as the old dark kit.

**How to apply:** Mockups link CrewChief's stylesheets byte-for-byte (copied locally; the reference screenshot is `CrewChief.Web/wwwroot/help-images/workload-run-dialog.png`) plus at most one small departures sheet. Render each screen headless and compare it with the CrewChief screenshot before reporting. Related: [[feedback-ui-port-characterise-and-uxreview]], [[feedback-ui-mockups-before-implementing]].

**Standing rule 9/16 23:40: never ask Gene a UI decision.** Default every UI choice (direction letters, palette, component pick, layout variant) to CrewChief look and feel, log it in `rows\_decisions.md`, keep going. Page layout gets adjusted AFTER a working version exists, never as a blocking question before one.

**Rejected again 9/14 (att 2 + every gallery screen).** Root cause was the WORKFLOW: myloop's mockup class check, prompt block, verifier and batch recipe all pinned `_assets/speedy.css`, dragging every worker back to the dark kit. Fixed: `sheets:` / `.loop/foreman.json mockupSheets` (CrewChief bootstrap + material-base + app.css + speedy-crewchief.css under `_assets/`); check fails undefined classes AND wrong links. Every old kit/dial/gallery screen must be redrawn, not just new ones.
