---
name: project_workload_profile_attach_gate_2026-09-24
description: Workload run profiles 9/24 - gate APPROVED (editor = layout A, profiles section = B cards); Targets lowest param layer incl. nested child Targets; Acceptance trip wires judge step runs; coordinator SliceFrom used to DROP Profiles (fixed)
metadata:
  type: project
---

Gene approved the mockup on 2026-09-24 (artifact L4A3owmGjQEsTq7pHTBT7h): the workload editor follows layout A, and its run-profiles section uses the B cards (`WorkloadProfilesPanel`). The Effective parameters view sits under the cards.

Parameter layers: parent calling step < child Targets < child globals < child step. At the top level: Targets < workload default < step < run keys. Gene put it as "the lowest level always wins". Both the runner and the editor use `WorkloadParameterLayers`, so they agree.

Acceptance (`StepRunAcceptance`): each finished top-level step counts as one call, and a step run is one iteration. TripRun is checked after every step; VerdictFail and Warn are checked once the run ends. Load-engine rules (FailIteration, StopThisUser, HoldRung, the batch, rung and user windows, throughput) are reported as "not applied" and are never read as zero. The verdict goes into `WorkloadRunRecord.Problem`, `AcceptanceProfile` and `AcceptanceNotes`. The notes are not shown in the UI yet, and that needs a mockup first.

**Why:** A bug was found on 9/24: `WorkloadRunCoordinator.SliceFrom` and `ModelImportFamily.Copy` rebuilt definitions without `Profiles`. That meant every UI or CLI run silently lost its embedded profiles. Both are fixed, and a regression test covers it.

**How to apply:** Any new code that copies a WorkloadDefinition must copy `Profiles`. The Acceptance status codes, retries, timeout and ContinueOnError are NOT applied yet, because the step settings govern those. See [[feedback_ui_mockups_before_implementing]].
