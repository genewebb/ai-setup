---
name: reference-unified-matching-code-vs-docs-2026-10-16
description: "UnifiedMatchingScenario real runtime behaviour vs MatchingScenarioDeepDive.md/skill claims (verified in code 10/16), plus where the non-dev archify diagrams live"
metadata:
  node_type: memory
  type: reference
  originSessionId: 6f9ac4ca-33ca-4506-8071-1e033690d5be
  modified: 2026-10-16T16:27:33.042Z
---

Verified in speed-merchants code 2026-10-16 (branch bug/26r3_ga_testing_updates, HEAD 81097936). Docs (MatchingScenarioDeepDive.md, StrategyPatternDesign.md) and the testauto-matching-scenarios skill lag on these:

- Scenario 2 template = OperationType BatchLoad -> BatchLoadStrategy (not PerRecord). 1 metric row per batch.
- 3A template sets WaitForMatching=false -> ContinuousStrategy (harmless: LookupOnly never creates). 3A record source = target entity filtered Match Status 20/30/40/50; wizard 3A source-system choice unused at runtime.
- "BatchLoad" is NOT bulk: one POST/PATCH per record, sequential.
- No runtime mutation: "Changed" records are read pre-mutated from RetailClientCloned (20/30/40) and PATCHed keeping Code; TransformSeed/UpdateVariationLevel unused.
- 3B (LookupThenCreate, WaitForMatching=true, PerRecord) = real-time: polls Profisee DB data.t<Entity> by SQL for Match Cluster -> Golden Record -> survivorship. Its 85/15 create/update has no runtime effect (only applied in Mixed mode).
- 3C (CreateOnly, WaitForMatching=false) writes Pending rows; UnifiedMatchingPostRunCollectionScenario fills them in place (default 20 parallel).
- Simulated users = MaxHangfireScenarioServersCount; ConcurrentThreads NOT used by UnifiedMatchingScenario (MatchingScenarioConfig.cs:34-39).
- ExpectEmptyModel check skipped for BatchLoad (so never fires for Scenario 1). ContinuousMatching CustomParm dead.
- No MatchingApiRest / direct Matching API lookup code exists; lookups go via gateway {ver}/matching/{strategy}/lookup.
- Run Profile = label only (UnifiedMatchingApiExecutionRunProfile), stamped on 3 metric entities; changes nothing at runtime.

Non-developer archify diagrams (index.html landing + overview, housekeeping, metrics, run profiles, scenarios 1/2/3a/3b/3c) published to `Q:\Work\Work\99 Documentation\matching\ScenarioDocumentation\`, JSON sources in `source\` (regenerate with archify `deliver workflow`). Related: [[reference-matching-lookup-2219-is-no-match]].
