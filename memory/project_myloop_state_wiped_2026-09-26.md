---
name: project-myloop-state-wiped-2026-09-26
description: 2026-09-26 Gene wiped ALL old /myloop state (every .loop* dir) to start clean; zip archive on NAS is the only copy
metadata:
  node_type: memory
  type: project
  originSessionId: 7b7a8c4b-5e40-4390-8aad-92dccba792b7
  modified: 2026-09-26T16:42:07.254Z
---

On 2026-09-26 Gene asked to "clean up all old /myloop, we will start clean" and "delete all unneeded .loop* directories".
63 `.loop*` directories were deleted: `C:\devops\repos\speedmerchants` (the .loop folder plus 11 .loop-archive-* folders), `C:\devops\repos\speed-merchants` (.loop plus the phase1/2/3 folders; Gene made a one-off exception to the never-touch rule), `D:\repos\speedmerchants`, and the C:\tmp scratch copies.

**The only copy:** `D:\DataArchive\myloop-2026-09-26\myloop-state-2026-09-26.zip` (2181 files, 21.4 MB, every entry read back OK), with `manifest.tsv` beside it. Entry prefixes are `speedmerchants-C/`, `speed-merchants-C/` and `speedmerchants-D/`.

**Why:** a fresh start. The loop had been paused since 9/17, and its RESTART-HERE, rows, ledger and ~400 graders were stale.

**How to apply:**
- /myloop has NO state to resume from. [[project-loop-paused-restart-here-2026-09-17]] is obsolete; start a new loop from scratch.
- Repo comments and docs still cite `.loop\criteria\*.ps1` and `.loop\tools\CriteriaCommon.ps1` paths (installer docs, Tests.Criteria.csproj, stack.setup.ts, unit test comments). No build depends on them.
- The e2e proof scripts write receipts to `.loop\proof\`. Check a script recreates the folder before assuming it does.
- The LOGIN.1 route grader `ui-routes-live.ps1` now exists only in the zip (`speedmerchants-C/.loop/criteria/ui-routes-live.ps1`). Restore it from there if a route grader is needed again.
