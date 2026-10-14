---
name: feedback_ui_mockups_before_implementing
description: "For any UI change, build full-page HTML mockups in C:\\tmp and open in Chrome for approval BEFORE writing component code"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 1bdf8c2b-86c9-4397-b982-386752ae932c
  modified: 2026-08-26T00:09:05.250Z
---

For UI work, produce **full-page HTML mockups** and open them in Chrome for approval **before** implementing anything in the real components.

**Why:** established 2026-08-25 during the CrewChief value-editor redesign. Implementing first meant building the tabbed card, then discovering the whole page blended white-on-white, then reworking it. Once mockups came first, the user picked a direction and gave precise corrections (bold the tab labels, move the Runtime chip next to Builder, narrow the card, move actions beside the container) in one pass. The user's own words: doing full mockups for approval "makes things faster".

**How to apply:**
- Write a self-contained `.html` to `C:\tmp\`, open with `Start-Process chrome.exe <path>`.
- Show **several distinct directions** (4–5), not one. Give each a number/letter, a one-line rationale, and an honest strength/cost pair.
- Render the **full page** in context — nav rail, toolbar, the real grid, real data copied from the user's actual files — not an isolated component. Isolated-component mockups hid the white-on-white problem.
- Use a **skin switcher** (buttons setting `body[data-skin]`) so all variants share one DOM and swap live; comparison is instant and the file stays maintainable.
- Mask any secret values in mockups; never paste real credentials.
- Iterate on the mockup until the user names a choice, THEN write component code. Ask for the letter explicitly — "the rest looks good" is not a pick.

Related: [[project_crewchief_value_card_2026-08-25]], [[feedback_ui_parity_before_new]], [[feedback_publish_artifacts_and_archive]].
