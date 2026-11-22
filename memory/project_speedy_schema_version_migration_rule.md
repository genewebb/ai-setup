---
name: project-speedy-schema-version-migration-rule
description: "Speedy saved-file versioning rule (owner 2026-10-03): first schemaVersion bump must add an up-only migration step; no down-export yet"
metadata:
  node_type: memory
  type: project
  originSessionId: 23931cca-ef33-4d65-bd80-3f161cee66e7
  modified: 2026-10-03T18:06:01.550Z
---

Every Speedy store stamps a schemaVersion (profiles ProfileFileStore.cs:44, steps StepFileStore.cs:56, scenario configs ScenarioConfigurationFileStore.cs:42 — all 1 as of 2026-10-03). Stores can refuse a retired version; there is no upgrade chain and no export-to-older. Legacy (donor) conversion is a one-off into v1 (G3.T064/G3.T207).

Owner rule, confirmed 2026-10-03: the FIRST row that bumps any store to version 2 must add an up-only v(n) to v(n+1) migration step plus an upgrade test. Export to an older version stays out until a customer needs it.

**Why:** owner wants "current is 3, this file is 1, here is how 1 becomes 3", without paying for a framework before any bump exists.
**How to apply:** when planning or reviewing any row that changes a Current*SchemaVersion constant, require the migration step and test in that row's title/write set. Related: [[feedback-auto-approve-recommendations-speedy-build]]
