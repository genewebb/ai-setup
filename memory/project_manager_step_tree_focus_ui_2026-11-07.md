---
name: project-manager-step-tree-focus-ui-2026-11-07
description: "TestAutoManager nested step tree + focus-panel UI (theme C) + History tab, and CrewChief live step file; built 11/07, uncommitted, not deployed"
metadata:
  node_type: memory
  type: project
  originSessionId: 95f5b98f-d94c-408a-8901-e309c3b37709
  modified: 2026-11-08T02:53:30.381Z
---

Built 2026-11-07 (branch bug/crud_pack_updates/genewebb, uncommitted, NOT deployed to SMVMTR1):

- CrewChief CLI writes `<dataFolder>\live\<runId>.json` (LiveRunTreeWriter, AsyncLocal hub LiveStepTree in engine), prints
  `Log folder:` / `Run id:` / `Live steps:` lines at top of run output; runs.json StepResultRecord gains `startedUtc` + `children`.
- TestAutoManager reads "Live steps:" line, maps to UNC, shows every depth (RoundFocus component, mockup C, dark bar theme),
  falls back to run-log step table for an old CLI. History tab = finished rounds list -> /history/{id} read-only.
  `TestAutoManager:LaneRunner=false` = view-only instance (no box touched).
- Bug found by watching a real (synthetic demo) run: throttled writes dropped a nested start with no trailing write, so a
  long nested step was invisible until it finished. Fixed with a one-shot trailing timer + lock. **Why:** unit test had
  pinned the drop; only a live run showed it. **How to apply:** for any throttled writer, test "held event written with
  no later event".
- Deploy order once round done: CrewChief CLI to TR1 cli folder, then TestAutoManager (needs version bump). Never mid-round.

Plan doc: Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-07-manager-step-tree-focus-ui-plan.md
Related: [[project-mid-release-round-runner-plan-2026-11-07]]
