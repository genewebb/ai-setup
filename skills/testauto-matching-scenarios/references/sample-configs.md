# Matching Sample Configurations (3A / 3B / 3C)

Reference for the `testauto-matching-scenarios` skill. Loaded on demand — see `SKILL.md` for the decision rules and gotchas that decide whether you need this file.

---

## Sample Configs

These abridge the real on-disk samples in `TestAuto.Matching/Samples/TestCases/Small/`. **`CustomParms`
in the shipped samples is nested into named sections** (`TimingParms`, `MatchingFlow`,
`MatchingDefinition`, `AvailableRecordsBySourceSystem`, `NewRecordDistribution`,
`ChangedRecordDistribution`, `ExistingRecordDistribution`, `MutationSettings`) — it is *not* the flat
dict the wizard emits. Both shapes work because `MatchingScenarioConfigBuilder.Read<T>` tries a
top-level lookup first and then walks every nested `JObject` for the key
(`TestAuto.Matching/Helpers/MatchingScenarioConfigBuilder.cs:256-280`). Keep the sections when copying
a sample; do not flatten them.

> These snippets reflect the **samples**, whose 3B/3C `OperationType` values differ from the wizard's.
> See the OperationType × RecordSource Matrix above before using them as a template for new work.

### Scenario 3A — Lookup Stress Test (`UnifiedMatching_Scenario3A_LookupStress_Small.json`)

```json
{
  "ScenarioName": "UnifiedMatchingScenario",
  "ScenarioTables": { "SourceEntityName": "RetailClient", "TargetEntityName": "RetailClient" },
  "ScenarioRuntime": {
    "BatchSize": 500,
    "MaxHangfireScenarioServersCount": 1,
    "CustomParms": {
      "TimingParms": { "TimeLimit": "01:00:00", "IterationLimit": 0, "SleepMinMs": 0, "SleepMaxMs": 0 },
      "MatchingFlow": {
        "OperationType": "LookupOnly",
        "RecordSource": "ExistingMatchedOnly",
        "ExpectEmptyModel": false,
        "ExpectIndexedModel": true,
        "CaptureMatchingCounters": true
      },
      "MatchingDefinition": {
        "MatchingStrategyName": "RetailClientMatching",
        "MatchingColumnNames": {
          "MatchStatusColumnName": "Match Status",
          "MatchClusterColumnName": "Match Cluster",
          "GoldenRecordColumnName": "Golden Record"
        }
      },
      "AvailableRecordsBySourceSystem": { "1": 3000000, "2": 6881257, "3": 40118743,
                                          "20": 50000000, "30": 50000000, "40": 50000000 },
      "NewRecordDistribution":      { "Percent": 0, "SourceSystems": {} },
      "ChangedRecordDistribution":  { "Percent": 0, "SourceSystems": {} },
      "ExistingRecordDistribution": {
        "Percent": 100,
        "MatchStatusFilter": "Matched",
        "SourceSystems": {
          "1":  { "Percent": 17, "OffsetPercent": 0 },
          "2":  { "Percent": 17, "OffsetPercent": 0 },
          "3":  { "Percent": 17, "OffsetPercent": 0 },
          "20": { "Percent": 17, "OffsetPercent": 0 },
          "30": { "Percent": 16, "OffsetPercent": 0 },
          "40": { "Percent": 16, "OffsetPercent": 0 }
        }
      },
      "MutationSettings": { "TransformSeed": 12345, "RuleDefinitions": null, "AttributeGroups": null }
    }
  },
  "ScenarioTesting": { "TestRecordLimit": 5000, "IterationLimit": 0 }
}
```

### Scenario 3B — Lookup Scoring Test (`UnifiedMatching_Scenario3B_LookupScoring_Small.json`)

Identical shape; the sample's `MatchingFlow` and record distributions are:

```json
{
  "MatchingFlow": {
    "OperationType": "LookupOnly",
    "RecordSource": "NewValuesOnly",
    "ExpectEmptyModel": false,
    "ExpectIndexedModel": true,
    "CaptureMatchingCounters": true
  },
  "NewRecordDistribution": {
    "Percent": 100,
    "SourceSystems": {
      "1":  { "Percent": 17, "OffsetPercent": 2 },
      "2":  { "Percent": 17, "OffsetPercent": 2 },
      "3":  { "Percent": 17, "OffsetPercent": 2 },
      "20": { "Percent": 17, "OffsetPercent": 2 },
      "30": { "Percent": 16, "OffsetPercent": 2 },
      "40": { "Percent": 16, "OffsetPercent": 2 }
    }
  },
  "ChangedRecordDistribution":  { "Percent": 0, "SourceSystems": {} },
  "ExistingRecordDistribution": { "Percent": 0, "SourceSystems": {} }
}
```

> The sample uses `OffsetPercent` (a percentage into each source pool), **not** the flat
> `HoldoutStartAfterRow` / `NewRecordStartingOffset` row offsets the wizard writes.

### Scenario 3C — LUBC User Simulation (Continuous / Interactive)

Two samples ship: `UnifiedMatching_Scenario3C_Continuous_Small.json` and
`..._Interactive_Small.json`. They are identical apart from `WaitForMatching` (and the Continuous
variant additionally setting `CollectMetricsPostTest`):

```json
{
  "MatchingFlow": {
    "OperationType": "LookupThenCreate",
    "RecordSource": "Mixed",
    "WaitForMatching": false,          // Interactive sample: true (and no CollectMetricsPostTest)
    "CollectMetricsPostTest": true,
    "ExpectEmptyModel": false,
    "ExpectIndexedModel": true,
    "CaptureMatchingCounters": true
  },
  "NewRecordDistribution": {
    "Percent": 15,
    "SourceSystems": {
      "1": { "Percent": 34, "OffsetPercent": 1 },
      "2": { "Percent": 33, "OffsetPercent": 1 },
      "3": { "Percent": 33, "OffsetPercent": 1 }
    }
  },
  "ChangedRecordDistribution": {
    "Percent": 85,
    "SourceSystems": {
      "20": { "Percent": 40, "OffsetPercent": 0 },
      "30": { "Percent": 40, "OffsetPercent": 0 },
      "40": { "Percent": 20, "OffsetPercent": 0 }
    }
  },
  "ExistingRecordDistribution": { "Percent": 0, "SourceSystems": {} }
}
```

The 3C samples also carry a populated `MutationSettings.RuleDefinitions` map (per-attribute mutation
rules + weights) which the 3A/3B samples leave `null`.

---
