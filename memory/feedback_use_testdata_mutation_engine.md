---
name: feedback-use-testdata-mutation-engine
description: "For any record mutation work, use the TestData.Mutation engine (rule catalog by name), not TestAuto's legacy MutationTransformer/MutationHelper"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8ecc9a58-e238-47c7-875f-417dfa1ed23f
  modified: 2026-11-05T03:27:00.602Z
---

When TestAuto needs to mutate records (e.g. Matching Scenario 2 Updated records), use `TestData.Mutation\TestData.Mutation.Engine` (`MutationRuleCatalog`, `SplitMix64`, `RuleWeights`), not `TestAuto.Records\Helpers\MutationTransformer` / `TestAuto.Shared\Helpers\MutationHelper` (int rule codes, no DOB/SSN rule, phone fully randomised).

**Why:** Gene 2026-11-04: "Lets do this right... TestData.Mutation... is newer and better. When we get to the vNext everything will be available in a single solution." Also never append fixed text to match fields (defeats the matching test).

**How to apply:** mutate only the matching strategy's fields (read from `matching.tMatchingStrategy`), rules from a CustomParm, seeded per Code. Plan: `Q:\Work\Work\99 Documentation\speed-merchants\planning\2026-11-04-matching-scenario2-mutation-plan.md`. Gotcha: 26R3 stores `Attribute.name` lowercase; TestAuto's `MatchingAttributeSetParser` reads `Name` and returns 0 sets until fixed (fixed 11/04).

**Rule-set gotcha (measured 11/04):** MaxAttributeChanges is spent in field order, so every field needs a `NoChange` weight. Without one, the first two fields take every change: DOB changed 10/10 rows and 4 fields never changed. Use NoChange 3 against 1 total for the real rules (all 8 strategy fields hit, 12–29 per 100 rows).
