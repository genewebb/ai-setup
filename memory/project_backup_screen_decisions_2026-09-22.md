---
name: project-backup-screen-decisions-2026-09-22
description: "Gene 2026-09-22 at the Backup mockup gate: direction A (standing master/detail, Contents/Restore pane tabs, inline confirms); backup administration open to anyone signed in"
metadata: 
  node_type: memory
  type: project
  originSessionId: b1f8cd5f-6ce3-4617-9512-c6797bf44a0a
  modified: 2026-09-22T13:02:51.908Z
---

Gene, 2026-09-22, crewchief-backup-restore Goal 2 mockup gate (C:/tmp/speedy-mockups/backup-screen-gate.html):
"1. A 2. Anyone logged in".

- **Layout A**: standing CrewChief master/detail shell - archive cards left (date as name, file name + size as
  meta, delete checkboxes beneath), open archive right with Contents / Restore pane tabs, confirmations as
  inline alertdialog panels. B (stepper) and C (donor three cards) rejected.
- **Who may administer backups**: anyone signed in - no narrower web policy. The host's page-level MayView
  (authenticated; narrows only if a deployment configures ViewRoles) is the gate; no extra check on the page.

**Why:** A keeps the standing layout ([[feedback-speedy-master-detail-layout]]); UI-only administration means
the web session is the only route, so no separate admin role was wanted.

**How to apply:** built as src/Web/Components/Pages/BackupPage.razor(.cs) over IBackupAdministration. A future
change to either choice needs Gene again; a deployment with ViewRoles set narrows who can back up.
