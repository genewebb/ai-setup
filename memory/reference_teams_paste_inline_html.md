---
name: reference-teams-paste-inline-html
description: "Best format for sharing analysis in Microsoft Teams = inline-styled HTML page, open in Edge, Ctrl+A/Ctrl+C, paste; confirmed working 2026-10-10"
metadata:
  node_type: memory
  type: reference
  originSessionId: 016cab1b-bfd1-4fa4-946f-bc0e278dfb35
  modified: 2026-10-10T20:22:34.121Z
---

Teams chat cannot render a full web page (no JS, no `<style>` classes). What pasted cleanly (Gene confirmed 2026-10-10, `c:\tmp\lubc-teams.html`):

- Separate "-teams.html" file: plain `<p>`, `<b>`, `<ul>`, `<table>` with **inline `style=` only** (border 1px #d1d1d1, padding 5px 10px, header bg #f0f0f0, red #c4314b for bad deltas), Segoe UI 14px, ~760px wide.
- Open it in Edge, Ctrl+A, Ctrl+C, paste into the Teams message box. Table, bold and colors survived.
- Charts go as a separate PNG (headless Edge screenshot cropped with System.Drawing), pasted into the same message.

**How to apply:** when Gene wants a result "for Teams", build the inline-styled HTML + chart PNG. Don't use a Markdown table; Teams Markdown table rendering is unverified.

Headless Edge screenshot trap: minimum viewport is ~492px even with `--window-size=390`; to check phone width, render the page inside a 390px `<iframe>`.
