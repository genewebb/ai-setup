---
name: reference_archify_viewer_behaviour_verified
description: "Archify viewer behaviours verified by recording (hover vs click card, Escape keeps focus, headless reduced motion, deep links) — plausible guesses were wrong"
metadata:
  node_type: memory
  type: reference
  originSessionId: b6471baf-5175-4790-a6d7-f6a502d6ce3f
  modified: 2026-09-24T20:57:19.218Z
---

Verified 2026-09-24 by recording real sessions on the Speedy diagrams (record.mjs):
- Hover a box = lights up direct connections, fades rest. It does NOT open a card.
- Click a box = opens the card ("Semantic Passport") with in/out links. Clicking a box inside a guided view leaves the view.
- Escape closes only the card; the focus stays. Clicking empty canvas clears both. Clicking an active guided view again does NOT turn it off.
- `meta.animation: "trace"` plays once on open and defaults to Live. Headless Edge reports prefers-reduced-motion, which forces Still and disables the button: emulate `no-preference` via CDP `Emulation.setEmulatedMedia`.
- Deep links: `#focus=<node id>`, `#view=<view id>`; hashchange applies them without a reload (the demo iframe follows the narration this way).

**Why:** the narration claimed "hover opens a card" and "click the view again to exit"; both were false until recorded.
**How to apply:** before narrating or documenting any viewer behaviour, record it and look. See [[project_speedy_demo_diagrams]].
