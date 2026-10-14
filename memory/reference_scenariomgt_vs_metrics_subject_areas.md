---
name: reference_scenariomgt_vs_metrics_subject_areas
description: "ScenarioMgt = reference data, Metrics = where metric rows land; reference data always comes from ScenarioMgt REST, never from a DB directly"
metadata: 
  node_type: memory
  type: reference
  originSessionId: a4cc8752-9b45-4de8-9f92-6c35f5301e4c
  modified: 2026-08-05T14:17:40.243Z
---

Subject-area split in TestAuto, stated by the user 2026-08-05:

- **`ScenarioMgt`** holds **all reference data** — `ConnectRunProfile`, `ServerProfile`, `ProfiseeVersion`,
  `Scenario`, the workflow/scenario definitions, etc.
- **`Metrics`** is **where metric rows land** — `ConnectApiExecution`, `UnifiedMatchingApiExecution`, …

They resolve to the same Profisee instance today (same `BaseUrl` in every shipped secrets profile), **but the
design permits splitting them.** So code must not treat them as interchangeable:

> Reference data always comes from **ScenarioMgt** (DB or REST depending on need), and **the database must not
> be referenced directly for reference data**. Metrics go to the `Metrics` subject area.

Practical consequences:

- A scenario reading reference data uses `ScenarioServices.GetRestClient(cfg, RestSubjectArea.ScenarioMgt)`.
  Picking `Metrics` because "it's the same endpoint" is wrong and silently breaks on a split.
- On a real runner ScenarioMgt is often an **Azure SaaS Profisee instance with a SaaS database**
  (e.g. `profiseecloud.dev/speedmerchantstest`), so there is **no SQL endpoint reachable from the box**.
  `ConnectionStrings:MetricsDB` / `ScenarioMgtDB` are vestigial there — no value can be correct.
- Landmine: `DatabaseConnectionStringHelper.GetConnectionString(cfg, area, config)` maps area → `{Area}DB`, and
  when that key is **missing it silently falls back to `ProfiseeDB`** — the instance under test, which holds no
  reference-data tables. A reference-data SQL read therefore fails with a confusing object-not-found rather
  than a missing-config error.

This is the rule the Connect post-run collection violated — see
[[project_connect_postrun_cross_database_hang]].
