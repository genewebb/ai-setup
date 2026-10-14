---
name: project_crewchief_steptype_coverage_assertions
description: "Adding a CrewChief step type is INDIVISIBLE — 6 files must land in one commit or the unit suite goes red; the step-type skill's \"four sites\" undercounts because it maps dispatch, not test coverage"
metadata: 
  node_type: memory
  type: project
  originSessionId: d393548d-e8e1-4994-a862-dd4b2229b125
  modified: 2026-08-04T13:31:35.835Z
---

Adding one `StepTypeRegistry` registration to CrewChief turns the unit suite red until **six** files
land together. Measured 2026-08-03 against `speed-merchants` (baseline: 2,656 unit tests green, 41s).

The atomic set:

1. `CrewChief.Engine/Steps/<X>Step.cs` (new)
2. `CrewChief.Engine/Steps/StepTypeRegistry.cs`
3. `CrewChief.Web/Helpers/UtilityStepTypeInfo.cs` — `AllTypes` entry **plus** FIVE switch arms: icon,
   display name, description, accent colour, tint
4. `CrewChief.Web/SampleContent/workloads/all-step-types.workload.json`
5. `CrewChief.Tests.Unit/Web/UtilityStepTypeInfoTests.cs` — hardcoded expected-key array

**CORRECTED 2026-08-04 — the set is FIVE, not six.** `StepDescriptionSeeder.cs` was wrongly listed.
`Seed()` loops `UtilityStepTypeInfo.AllTypes` and calls `GetDescription(type)` (`:49-55`), so it needs no
per-type edit, and `StepDescriptionSeederTests:36,41` asserts `added == AllTypes.Length` and compares to
`GetDescription` — self-referential both ways, forcing nothing. Likewise
`StepTypeParityTests.EveryUiTypeKey_HasVisualMetadata` only checks icon/name/accent are non-empty, and
all three switches have non-empty defaults, so a forgotten metadata arm passes and ships wrong visuals.

What forces each:

| Assertion | Forces |
|---|---|
| `StepTypeParityTests.RegistryAndUiTable_HaveTheSameCount` | 2 + 3 together |
| `StepTypeParityTests.EveryRegistration_HasAUiTypeKey` | same |
| `StepTypeParityTests.EveryUiTypeKey_ResolvesInTheRegistry` | 3 needs 2 |
| `StepTypeParityTests.EveryUiTypeKey_HasVisualMetadata` | all three metadata arms in 3 |
| `ShippedSampleContentTests.AllStepTypesWorkload_CoversEveryRegisteredStepType` | 5 |
| `ShippedSampleContentTests.InlineSteps_HaveNoUnknownProperties` | 5's JSON props must match 1's `[JsonProperty]` names exactly — anything else lands in `ExtensionData` and fails |
| `StepDescriptionSeederTests.Seed_PopulatesEveryStepTypeWithItsBuiltInDescription` | 4 (`added == AllTypes.Length`) |
| `UtilityStepTypeInfoTests.AllTypes_ContainsExpectedCanonicalKeys` | 6 |

The sample step in 5 must also set `continueOnError: true`
(`AllStepTypesWorkload_KeepsEveryStepNonDestructive`), and any `{{token}}` it uses needs a global
parameter carrying a value (`WorkloadPlainTokens_ResolveFromTheirGlobalParameters`,
`ShippedWorkloads_GlobalParametersAllHaveValues`).

Two GLOBAL census oracles also fire on any registry/executor addition (verified 2026-08-04):
`StepTypeRegistryTests.cs:23` `ExpectedMappings` (hand-transcribed, exact-set assert at `:115-121`,
`Except` both ways so extras fail too) and `EngineRegistrationTests.cs:44`
`Assert.AreEqual(21, executors.Count())`. That file's doc-comment at `:13-18` still says "nineteen" —
stale, not yet fixed in the repo.

**Why:** the `crewchief-adding-a-step-type` skill said four hand-maintained sites. It maps where code
*dispatches*, not where tests *assert coverage*. An executor + its `AddTransient` DI line can follow in
a later commit — those are not coverage-asserted — but the six above cannot be split.

**FIXED 2026-08-04:** the skill now carries the indivisibility section, the six-file atomic set, the
forcing-assertion table, both census oracles, and the self-referential-vs-hardcoded test. Do not
re-report it as undercounting. Note the "4 vs 12 vs 13 vs 14" counts in the various records disagree;
the skill deliberately carries the enumerated verified list instead of a headline number.

**How to apply:** never plan a step-type addition as incremental small edits. Coverage assertions
destroy divisibility. This breaks any orchestrator-worker loop whose planner enforces a 1-3 file
rule per iteration, and it breaks any scope list that omits the sample workload — see
[[project_crewchief_teams_step_loop]]. Related: [[project_crewchief_steptype_factory_duplicated]],
[[reference_newtonsoft_extensiondata_vs_missingmember]], [[project_crewchief_smart_seed]].
