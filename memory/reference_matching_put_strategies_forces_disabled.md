---
name: reference_matching_put_strategies_forces_disabled
description: "PUT /v{n}/Strategies (matching upsert) ALWAYS saves Status=0 (disabled) regardless of body status; enable separately via POST v1/psl/matchingstrategies/enable?strategyUids=<code>, which queues Index+Cluster+Survive"
metadata: 
  node_type: memory
  type: reference
  originSessionId: 7cb23a63-eb62-412f-89bb-3dff2735da06
  modified: 2026-09-14T15:46:40.119Z
---

Source (`matching` repo, main f0873d436): `MatchingStrategyService.UpsertMatchingStrategies` `:200-201` — `// Upserted strategies are inactive by default` `matchingStrategyRecord.Status = 0;`. Body `status`/`statusID` ignored for enablement.
Contrast: `SaveMatchingStrategy` (PUT `v1/psl/matchingstrategies/save`, `:128-136`) PRESERVES DB status unless a disabling change (name, IncludeMatching/IncludeSurvivorship, output attributes).
Enable: `EnableStrategies` (`:802`), route `POST v{n}/psl/matchingstrategies/enable?strategyUids=<guid>` (PortalSupportController, `IgnoreApi` so not in Swagger). No-op if Status already 1; otherwise sets Status=1 and queues job IndexActions.Index + Cluster (if AutoMatch) + Survive (if AutoSurvive).
Verified live CORPLTR94 26.2 9/14: PUT at 15:34:12 UTC left Status 0, AutoMatch/AutoSurvive 1.
Also: `StrategyDisabler` sets Status 0 when any cluster job fails (entity-lock TimeoutException) — see [[project_unified_matching_metric_defects_2026-09-13]].
`StatusID` = process state (98 FINISHED), not enable flag — [[reference_profisee_matching_strategy_table_by_version]].
