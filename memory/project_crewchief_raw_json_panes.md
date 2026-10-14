---
name: crewchief-raw-json-panes
description: "Raw-JSON view/edit panes shipped 2026-07-28 — JsonPane/MonacoJsonEditor/JsonDefinitionValidator architecture, key invariants, and the one tracked follow-up"
metadata: 
  node_type: memory
  type: project
  originSessionId: 7dc6c870-9aa7-4891-a85e-d99e95480385
  modified: 2026-07-28T15:50:42.519Z
---

Raw-JSON panes shipped across 4 CrewChief surfaces (2026-07-27/28, branch bug/cleanup/genewebb, spec + plan in `99 Documentation\speed-merchants\planning\Design_/Plan_CrewChiefRawJsonPanes.md`):
Steps edit dialog (whole StepFile), WorkloadEditor page-level (whole WorkloadFile) + per-step card (inline body), Activity run detail (read-only, ungated — run output is masked engine-side).

**Key mechanisms (don't re-derive):**
- `JsonDefinitionValidator.Validate(json, kind, baselineUnknownKeys)` is the ONE acceptance definition. Unknown-key **delta rule**: keys present when the pane opened → Note; newly typed → Error (a typo'd property otherwise runs as a silent no-op). Baseline identity is **name-only** (`inline.<key>`) for workload step bodies — index-qualified keys shifted on step delete; errors still display positional paths via `UnknownKeyOccurrence(Identity, DisplayPath)`.
- `JsonPane.TryCommitAsync()` is the only route to the bound model; `!IsDirty` returns **true** (an untouched pane that opened invalid must not trap the user — this was a shipped Critical).
- Per-step edits persist the parsed JObject verbatim via `StepEntryEditorState.RawJsonOverride`, consulted in `ToDomainEntry` as `UnreadableInline ?? RawJsonOverride ?? JObject.FromObject(...)`; any Fields edit nulls it. Whole-workload commits seed it (`RebuildEntriesFromWorkloadFile(seedRawOverrides: true)`) — initial load must pass false.
- Open per-step pane tracked by **entry object reference** (`_stepJsonEntry`), never index — index tracking corrupted a different step on delete+save. `@key="@entry"` on the outer card div.
- One reveal flag per page: `StepEditorCard` takes host-owned `Revealed`/`RevealedChanged` (no internal state). Steps dialog resets its flag at all 3 open sites; WorkloadEditor deliberately never resets (page-instance-per-workload ruling). Re-lock with a dirty draft: confirm → discard, or decline → `_relockPending` applied on every leave-the-pane transition.
- Step rename via JSON is refused (`JsonPane.ExtraValidate` seam) — renames must go through `StepFileStore.Rename`, and `StepFileStore.Save` uses `File.Move(overwrite: true)` which would destroy a same-named file.

**Why:** hand-editable JSON over a store with `[JsonExtensionData]` bags and permissive deserialization manufactures silent-no-op bugs; every guard above closes one that was actually found by review.

**How to apply:** any new JSON-editing surface must reuse `JsonPane` + the validator, snapshot the baseline on open, and never round-trip user text through DTOs.

**Tracked follow-up (not fixed):** [[secretrevealtoggle-grantvalid-desync]]. Related: [[newtonsoft-extensiondata-vs-missingmember]], [[blazormonaco-integration-gotchas]].
