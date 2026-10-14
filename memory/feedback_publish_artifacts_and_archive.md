---
name: feedback-publish-artifacts-and-archive
description: "Standing preference (2026-08-24): publish substantial deliverables as interactive Artifact web pages, then archive a copy + index row to Q:\\Work\\Work\\99 Documentation\\claude\\webpages"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a02d7312-91e5-4a86-bb2d-f75bf8db3bab
  modified: 2026-08-24T14:39:28.648Z
---

Gene asked for the artifact web page to become a **standing feature**, not a one-off, after the
"TestData UI Shakedown" manual-test checklist (2026-08-24).

**Which format — he relaxed this on 2026-08-24: "If it is easier to do this in obsidian as a linked
markdown rather than a web page that is fine as well."**

- **Default to an Obsidian Markdown note** for anything he works THROUGH: checklists, test passes,
  runbooks, review lists. Obsidian's `- [ ]` tasks persist tick state **in the file**, so it syncs,
  greps and diffs — strictly better than a web page's `localStorage`, which is per-browser and
  invisible to everything else.
- **Reach for an Artifact web page** when the value is genuinely visual or interactive: a dashboard,
  a chart, a diagram, a side-by-side comparison, anything with live filtering. Load the
  `artifact-design` skill first — mandatory before writing any artifact file, Markdown included.
- Shipping both is fine, and is what the first one did.

**Where it goes.** `Q:\Work\Work\99 Documentation\claude\webpages\`, basename
`YYYY-MM-DD-lower-kebab-title`, and add an entry to that folder's `index.md` (newest first) with the
date, title, one-sentence description and links.

**Two traps that broke the first attempt — do not repeat them:**

1. **That folder is INSIDE the Obsidian vault** (vault root `Q:\Work\Work`). Obsidian cannot open an
   `.html` as a note; it tries to resolve one as a note and shows *page not found*. So a bare `.html`
   with a link from an index note is useless in Obsidian. Ship the `.md` and link that.
2. **A published artifact's file is a FRAGMENT, not a page.** The Artifact tool adds
   `<!doctype html>`, `<html>`, `<head>` and `<body>` at publish time, so the file as authored has
   none of them. Wrap it before archiving, and keep exactly one `<title>`.

**Why:** he wants to go back to them later. The hosted artifact is what he opens and shares; the
local copy is the durable record that stays browsable regardless of the hosted page, and the index is
what makes a folder of HTML files findable a year on.

**How to apply:**
- Make the page **operable**, not just readable, when the content is a list of things to do — real
  checkboxes with `localStorage` persistence (wrapped in try/catch: private windows and blocked site
  data throw). The checklist he liked had 31 persisted items and a sticky progress rail.
- Structure by the distinction that actually matters to him, not by feature order. That page grouped
  items by **risk tier** — never-exercised vs code-verified-confirm-visually vs known-behaviour —
  because "what has no automated coverage" was the useful cut.
- State known gaps explicitly as their own section, so he does not chase documented behaviour as a
  defect.
- **Updating**: republish to the SAME artifact URL and refresh the local copy in place; do not create
  a second artifact or a second index row.
- Titles: short, specific, no date or explainer inside the `<title>` — the date is the filename
  prefix and the explanation is the index row.

Related: [[project_doc_location]] (vault doc locations), [[feedback_max_response_4000_chars]] (why a
long deliverable belongs on a page rather than in a reply).
