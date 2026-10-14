---
name: reference-stream-kit-mtime-grader-clause-breaks-on-integrate
description: "Stream kit - a grader clause that compares file mtimes (e.g. \"axe report newer than every page file\") passes in the builder worktree but is always red on main after the integrator applies the patch"
metadata:
  node_type: memory
  type: reference
  originSessionId: f7b3d4d2-e1f5-4c6b-b4e6-b2df519d12cf
  modified: 2026-09-27T22:47:56.693Z
---

Imported MyLoop graders with an mtime freshness clause (rd-25 S2: axe reports must be newer than every write-set page file) cannot survive the stream kit's build→integrate handoff: `git apply` on main re-stamps the page files, so the integrator's main-tree grader run is red on that clause alone, for any correct patch. Seen 2026-09-27 on G1.T01 (integrate bounced to ticketed at 22:39Z; builder sent it to planned).

**How to apply:** when authoring/importing a kit task, drop or rewrite mtime clauses so the evidence is regenerated on main (integrator re-runs the axe group after apply), or check content instead of timestamps. Don't rebuild a task bounced only on such a clause - send it to `planned` with the reason. Reusable axe runner: `C:\tmp\speedy-build\rd-25\run-axe-rd.ps1 -Tree <tree>` (isolated host published from the tree; copies Tests.E2E + scripts out, junctions main node_modules; writes nothing in the tree).

Related: [[project-stream-kit-replaces-myloop]]
