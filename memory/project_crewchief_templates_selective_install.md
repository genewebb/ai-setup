---
name: project_crewchief_templates_selective_install
description: Templates page now lists reference-data sets too and supports checkbox/select-all selective install via ITemplateInstaller.InstallSelected
metadata: 
  node_type: memory
  type: project
  originSessionId: 8ff8b172-9d52-41ad-8c5c-02e4e6136777
  modified: 2026-07-25T15:03:08.527Z
---

2026-07-25: CrewChief `/templates` gained **selective install**. `ITemplateInstaller.InstallSelected(IReadOnlyCollection<string> fileNames)` installs only chosen rows; `SampleContentSeeder.Seed(onlyFileNames)` and `ReferenceDefaultsSeeder.Seed(onlyTypeNames)` take optional filters. Selection keys on `SampleTemplateStatus.FileName`; a `*.refkv.json` name is routed to the reference seeder with the suffix stripped to yield the type name.

`GetSampleStatuses()` now returns **both** kinds — `ReferenceDefaultsSeeder.GetStatuses()` was added, because shipped `*.refkv.json` sets were installed but invisible on the page (`SampleContentSeeder.SubfolderFor` returns null for anything not `*.step.json`/`*.workload.json`). Reference rows reuse `SampleTemplateState` but only NotInstalled / UpdateAvailable / UpToDate are reachable (key-level additive merge never conflicts), carry a `Detail` entry count, and get merge-specific tooltips. `InstallSelected` deliberately skips starter examples + step descriptions — they have no selectable row.

**Why:** operators wanted to pull in one template without touching the rest, and to see that reference data ships at all.

**How to apply:** new shipped kinds must be added to BOTH the installer and `GetSampleStatuses`, or they install invisibly. Page buttons carry `data-testid` (`install-all`, `install-selected`, `select-all`, `select-needed`, `clear-selection`) — bUnit tests target those, not `button.btn-primary` (now ambiguous). See [[project_crewchief_smart_seed]], [[project_crewchief_default_templates_ondemand]].

Several shipped samples (`configure-profisee`, `sql-select`, `stop-was`, `unit-test-all-steps`, …) have **no `_shippedUtc`** → `DateOnly.MinValue`, so once installed they can never receive an update. Still unstamped.
