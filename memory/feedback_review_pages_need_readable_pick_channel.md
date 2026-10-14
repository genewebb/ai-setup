---
name: review-pages-need-readable-pick-channel
description: "A review/pick artifact whose only state is localStorage cannot deliver the user's picks back to Claude — give every decision page a channel Claude can read (artifact db capability, the markdown tick sheet, or a copyable summary line)."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 75aa89d7-1a8e-429e-bbf8-a3e0c469e0ac
  modified: 2026-09-05T22:17:35.748Z
---

On 2026-09-05 the UI-polish review artifact (row 46, vNext loop) stored Gene's six picks in a `localStorage` rail. Gene said "I made my UI picks"; the markdown tick sheet was untouched, the artifact had no comments, and localStorage never leaves the viewer's browser. The picks had to be asked for again.

**Why:** localStorage is per-browser and invisible to the session. A decision page whose whole point is to collect a choice has failed if the choice cannot reach the loop.

**How to apply:** For any pick sheet / decision page: (1) declare the artifact `db` capability (load `artifact-capabilities` first) so picks land where `read_db` can fetch them, OR (2) render a "copy this line" summary (`1 B · 2 A · …`) with a copy button and tell the user to paste it, AND (3) keep the markdown tick sheet as the durable record. Say in the page footer exactly which channel Claude will read. Related: [[publish-deliverables-as-artifacts]], [[loop-practices-that-caught-defects]].
