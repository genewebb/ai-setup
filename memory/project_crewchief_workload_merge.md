---
name: crewchief-workload-merge
description: Merge 1..n workloads into a new one — pure WorkloadMerger (Data\Services) + Workloads-page dialog; first-wins global params with conflict reporting
metadata: 
  node_type: memory
  type: project
  originSessionId: 41e17cf9-9594-4457-a016-c1f758673b47
  modified: 2026-07-27T01:40:56.826Z
---

CrewChief workload merge (implemented 2026-07-26, port of TestAuto's Workflows-page merge mode):

- **Core**: `CrewChief.Data\Services\WorkloadMerger.cs` — pure static, store-free (CLI-reusable). `Merge(sources, newName, description?, tags?)` → `MergeResult(Workload, Conflicts)`. Steps concatenated in source order with `Overrides`/`Inline` JObjects deep-cloned; `GlobalParameters` merge FIRST-source-wins with every discarded differing value reported as a `ParameterConflict(Key, KeptValue, KeptFrom, DiscardedValue, DiscardedFrom)`; tags union (first-appearance, ordinal-distinct) unless explicit tags passed (empty list = tagless); `ExtraParms` first-wins deep-cloned. Also `FindParameterConflicts` (dialog live preview), `UnionTags`, `BuildMergedName` ("merged-workload", "-2", …).
- **UI**: Workloads page — the bulk-select checkbox set was renamed `_selectedForDelete` → `_selected` (drives bulk delete AND merge). "Merge Selected (n)" toolbar button (icon `merge_type`) opens a modal: reorderable source list (order = merged step order; reordering live-updates which conflict value wins), kebab name via `NamingHelpers.GetNameError`, description prefilled "Merged from: …", editable union tags. Save via `WorkloadFileStore.Save`; sources untouched.
- **Tests**: `CrewChief.Tests.Unit\Data\WorkloadMergerTests.cs` (18 tests, pure in-memory).
- Design choice: first-wins (not last-wins) keeps the earliest source as baseline and surfaces conflicts in the dialog + success toast instead of silently changing later sources' step behavior.

Related: [[project_crewchief_standalone]], [[crewchief-file-persistence]]
