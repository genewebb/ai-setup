---
name: feedback-simple-recovery-rerun-over-journal
description: Gene prefers "abandon and rerun" over crash-recovery journals for fast operations (Backup restore 9/22)
metadata:
  type: feedback
---

For operations that finish in seconds (for example a Backup restore), do not build crash-recovery journals, reconciliation, or gates that block other features. Abandon the interrupted run and let the operator run it again. A cheap in-process put-back on a known failure is fine.

**Why:** Gene, 2026-09-22: "just kill an interrupted restore and let it start over the restore literally takes seconds so dont over engineer this".
**How to apply:** when a requirement or goal asks for durable recovery of a quick operation, propose rerun-to-complete first, and flag the requirement text for amendment. Related: [[project-backup-restore-review-2026-09-22]]
