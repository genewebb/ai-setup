---
name: feedback_scratch_dir_is_c_temp
description: "Scratch/work area is C:\\temp, NOT C:\\tmp — corrected 2026-08-27"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 58643c62-5a5a-4b93-bd61-29e95b1c0942
  modified: 2026-08-27T12:51:51.558Z
---

Use `C:\temp` as the scratch/work area for build logs, generated bundles, mockup HTML, and any
throwaway artifact. NOT `C:\tmp`.

**Why:** stated 2026-08-27 — "You have been using c:\tmp as a work area for a lot of things switch to
c:\temp instead". `C:\tmp` had accumulated a lot of unrelated junk (installers, backups, logs).

**How to apply:** write new scratch files under `C:\temp`. Note that `C:\devops\myworkspace\CLAUDE.md`
still documents `C:\tmp` as the scratch folder and the harness's additional working directories still
list `C:\tmp`, not `C:\temp` — both are stale and worth updating. Pre-existing `C:\tmp` content was left
in place; only the active work area moved (`C:\tmp\hotfix-bundle` → `C:\temp\hotfix-bundle`).

Distinct from CrewChief's own backup folder, which is now `C:\Deploy\CrewChief\Backups` — see
[[project_crewchief_backup_location_refdata_authority]]. UI mockups still follow
[[feedback_ui_mockups_before_implementing]] but land in `C:\temp` now.
