---
name: testauto-record-transformation
description: >
  IRecordTransformer pipeline in TestAuto.Records for mutating source records into test data. Use
  when implementing a transformer, configuring weighted mutation rules, update/new ratio splitting,
  which transformer a scenario picks via UseMutationHelper, why MutationSettings/MutationStrategy
  appear to have no effect, wiring AttributeGroups, editing a CloneAndMutateScenario's
  DataMutationSettings (VariantGenerator rule numbers differ from MutationTransformer), or synonym
  swaps via SynonymHelper.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Record Transformation

> **Scope**: speed-merchants (TestAuto.Records)
> **Source**: `TestAuto.Records\Helpers\` + `TestAuto.Records\Interfaces\`

The `IRecordTransformer` pipeline takes a list of source `Record` objects and produces a mutated list split into update records (modified copies of source) and new records (cloned with new codes). Two concrete transformers exist: `MutationTransformer` (rule-based mutation) and `FakerTransformer` (delegates to `TransformationHelper` for realistic fake data).

---

## Interface Contract

```csharp
public interface IRecordTransformer
{
    Task<List<Record>> TransformRecordsAsync(
        List<Record> sourceRecords,
        int updatePercent,      // % of batchSize to produce as update records
        int newPercent,         // % of batchSize to produce as new records
        int batchSize,
        IRestClient restClient,
        string entityName,
        List<string> includedAttributes,
        ILogger logger = null
    );
}
```

Both transformers are registered in `RecordsModuleRegistrar` as `IRecordTransformer` (multiple registrations):

```csharp
services.AddTransient<FakerTransformer>();
services.AddTransient<MutationTransformer>();
services.AddTransient<IRecordTransformer, FakerTransformer>();
services.AddTransient<IRecordTransformer, MutationTransformer>();
```

---

## Update/New Ratio Split

`ITransformationHelper.ComputeUpdateCounts` partitions `batchSize` into `toUpdate` and `toNew` based on percentages. Then:

- **New records**: deep-cloned from source, code and name suffixed with `SharedConstants.NewSuffix`
- **Update records**: deep-cloned from source, name suffixed with `SharedConstants.ChangedSuffix`; each `includedAttributes` field is mutated
- **Survivors**: remaining records passed through unchanged

```
sourceRecords ──> strip system props
                     │
                     ├─► pick newIdx (random, size = toNew)  ──► clone + NewSuffix
                     ├─► pick updateIdx (remainder, size = toUpdate) ──► clone + mutate + ChangedSuffix
                     └─► survivors (neither) ──► pass through
```

---

## Which transformer actually runs

`IRecordTransformer` has two implementations, but only **one** scenario chooses between them at
run time. Re-read these two files before assuming a `UseMutationHelper` value has any effect
(verified 2026-07-27 @ 4c367fe6):

| Scenario | Transformer selection | Effect of `UseMutationHelper` CustomParm |
|---|---|---|
| `UpdateContinuousRecordsByPageAndBatchScenario` (class name spelled correctly; **file** is the misspelled `UpdateContinousRecordsByPageAndBatchScenario.cs`) | `UpdateContinousRecordsByPageAndBatchScenario.cs:292-294` — `_transformContext.UseMutationHelper ? _mutationTransformer : _fakerTransformer` | **LIVE** — `true` routes to `MutationTransformer`, `false`/absent to `FakerTransformer` |
| `UpdateRecordsByPageAndBatchScenario` | `UpdateRecordsByPageAndBatchScenario.cs:216` — hard-wired `await _fakerTransformer.TransformRecordsAsync(...)` | **INERT** — the parm is parsed into the context (`:95`, `:103`) and logged (`:109`), but `MutationTransformer` is never reached |

The parm name is the constant `RecordsConstants.UseMutationHelper`
(`TestAuto.Records\Common\RecordsConstants.cs:15`), parsed with `bool.TryParse` (default `false`).

In the Continuous scenario the two transformers are **not** injected — they are reflection-based
accessors over `_services.ScenarioEntityTestDataManager`
(`UpdateContinousRecordsByPageAndBatchScenario.cs:429-434`), each returning `null` if the manager
has no matching `MutationTransformer` / `FakerTransformer` property. A missing property therefore
surfaces as an NRE at the transform call, not as a DI resolution failure.

Rule of thumb: **Faker** = realistic replacement data via `ITransformationHelper` (Bogus);
**MutationTransformer** = corrupt-the-existing-value typo/format mutations.

---

## MutationTransformer

Applies attribute-level mutation rules to update records. Two tiers — but see the reachability
warning below.

### Tier 1 — Per-attribute weighted rules (`MutationSettings.RuleDefinitions`) — CURRENTLY UNREACHABLE

If `TransformationContext.MutationSettings` is set and contains a rule definition for the attribute, a cumulative-weight roll selects one mutation function.

> [!important] LIVE as of 2026-08 — the old "dead path" warning is obsolete
> This path used to be unreachable: `TransformRecordsAsync` built its own local context with
> `MutationSettings = null`, so the per-attribute rule guard could never be true and every run fell
> through to Tier 2 with a hard-coded `SlightTypo`. **That is fixed** — though not the way the old
> warning predicted. `IRecordTransformer.TransformRecordsAsync` still takes **no** context argument;
> instead `MutationTransformer` exposes a settable **`TransformationContext? Context` property**
> (`MutationTransformer.cs:45`).
>
> **Consequence — whoever resolves the transformer must assign `Context` before calling it.** When
> `Context` is null the transformer logs a warning naming the entity and falls back to
> `MutationStrategy.SlightTypo` with `Seed = NoSeed (0)` and no per-attribute rules (`:69-86`). A silent
> `SlightTypo`-only run is therefore now a *symptom of an unassigned `Context`*, not the design.

**`TransformationContext.Seed` is honoured** — with a subtlety worth knowing. `0` means "no seed" and
yields an unseeded `Random`. A non-zero seed builds a per-instance **seed source** (`new Random(seed)`) from
which each invocation draws a *child* seed, so repeated runs reproduce **and** successive pages within one
run still vary. A naive per-call `new Random(seed)` would make every page write identical values. The
returned `Random` is invocation-local; only the seed source is shared, guarded by `_rngLock` (`:27-29`).

Note the constructor gained an optional `Serilog.ILogger` parameter (`:52`).

> [!warning] `Seed` is NOT supported on the Faker path, and never will be
> `FakerTransformer` (`TestAuto.Records/Helpers/FakerTransformer.cs:12-35`) resolves `IFaker` as a
> **singleton `BogusFaker` wrapping one shared `Bogus.Faker`**. Reseeding it would reseed every concurrent
> scenario in the process, so `TransformationContext.Seed` is deliberately inert here.
> `TransformationHelper.TransformRecordsAsync` additionally selects records via process-wide
> `Random.Shared`.
>
> **A run that must be reproducible has to set `UseMutationHelper = true`.** Note that
> `UpdateRecordsByPageAndBatchScenario` is hard-wired to the Faker path, so a `TransformSeed` on that
> scenario does nothing.

> ⚠️ **This rule vocabulary belongs to `MutationTransformer` ONLY.** `CloneAndMutateScenario`
> runs through `VariantGenerator`, which interprets the SAME `RuleDefinitions` numbers with a
> DIFFERENT vocabulary — see the "VariantGenerator" section below before editing any
> `DataMutationSettings` JSON.

| Rule # | Mutation |
|---|---|
| 0 | No change (keep original) |
| 1 | Blank the field |
| 2 | `MutationHelper.SlightTypo` |
| 3 | `MutationHelper.SwapCharacters` |
| 4 | `MutationHelper.MutateAddress` |
| 5 | `MutationHelper.MutateCity` |
| 6 | `MutationHelper.CaseToggle` |
| 7 | `MutationHelper.MutateState` |
| 8 | `MutationHelper.MutateCountry` |
| 9 | `MutationHelper.MutatePostal` |
| 10 | `MutationHelper.MutateEmail` |
| 11 | `MutationHelper.MutatePhone` |

Example `MutationSettings` JSON (stored in `CustomParms["DataMutationSettings"]`):

```json
{
  "RuleDefinitions": {
    "FirstName": {
      "Rules": [0, 2, 3],
      "Weights": [0.5, 0.3, 0.2],
      "ApplyMoreThanASingleRule": false
    },
    "Email": {
      "Rules": [10, 1],
      "Weights": [0.8, 0.2]
    }
  },
  "AttributeGroups": {
    "NameGroup": ["FirstName", "LastName", "MiddleName"]
  }
}
```

### Tier 2 — Global fallback (`TransformationContext.MutationStrategy`)

When no per-attribute rules exist, `MutationStrategy` enum determines the function applied to all included attributes:

```csharp
public enum MutationStrategy
{
    SlightTypo,
    SwapCharacters,
    MutateAddress,
    MutateCity,
    CaseToggle,
    MutateState,
    MutateCountry,
    MutatePostal,
    MutateEmail,
    MutatePhone,
    MutateDOB,
    MutateSSN
}
```

### TransformationContext

`TestAuto.Shared\Common\Data\TransformationContext.cs`:

```csharp
var context = new TransformationContext
{
    // LIVE selector — read at UpdateContinousRecordsByPageAndBatchScenario.cs:292
    // to pick MutationTransformer vs FakerTransformer. NOT "reserved for future use".
    UseMutationHelper = useMutation,
    MutationStrategy = strat,           // global fallback (Tier 2)
    Seed = transformSeed,
    MutationSettings = settings         // intended to enable per-attribute rules
};
```

> ⚠️ The context a scenario builds is used **only** to pick the transformer. It is never handed
> to the transformer — `IRecordTransformer.TransformRecordsAsync` takes no context parameter, and
> `MutationTransformer` fabricates its own (see the Tier-1 warning above). So
> `MutationStrategy`/`Seed`/`MutationSettings` set by a scenario do not reach the mutation code.

---

## FakerTransformer

Delegates directly to `ITransformationHelper.TransformRecordsAsync` (the same helper used internally by `MutationTransformer`). Use when you want realistic fake data generated by Bogus rather than rule-based typo mutations.

```csharp
// FakerTransformer just delegates — it has no independent logic
public Task<List<Record>> TransformRecordsAsync(...) =>
    _helper.TransformRecordsAsync(...);
```

---

## AttributeGroups — consumed by `VariantGenerator` ONLY

`DataMutationSettings.AttributeGroups`
(`TestAuto.Shared\Common\Data\DataMutationSettings.cs:23`, shape
`Dictionary<string, List<string>>`) has exactly **one** consumer in TestAuto:
`VariantGenerator.cs:69` (`mutationSettings.AttributeGroups`). Bare-name grep of the whole repo
(2026-07-27 @ 4c367fe6) returns only that read site, the model declaration, sample JSON, and docs
— `MutationTransformer` never touches it. The model's own XML comment says so:
*"Optional groups of attributes (not used by MutationTransformer directly…)"*
(`DataMutationSettings.cs:20`). Re-run `grep -rn AttributeGroups` before assuming otherwise.

Its only real job is therefore the **blanking constraint** in `VariantGenerator` (below): at most
one attribute per group may be blanked (rule 1) per variant; a second blank roll in the same group
downgrades to rule 0 (no change).

> ❌ Do **not** describe `AttributeGroups` as "correlated mutation" (mutate `LastName` whenever
> `FirstName` is mutated, shared seed). No code implements that. The identically named
> `TestData.CloneAndMutate\Mutation\MutationSettings.cs:14` property is a *separate* class in the
> standalone console tool and is likewise unconsumed there — see [[testdata-enrichment-pipeline]].

---

## VariantGenerator — the ACTIVE path for `CloneAndMutateScenario`

`CloneAndMutateScenario` does **not** use `MutationTransformer`. It calls
`VariantGenerator.GenerateAttributeVariants(baseRecord, config, sourceSystems, variantCount, mutationSettings, transformSeed)`
(`TestAuto.Records\Helpers\VariantGenerator.cs`), which reads the same
`CustomParms["DataMutationSettings"]` JSON but interprets `RuleDefinitions` rule numbers with a
**different vocabulary**:

| Rule # | `VariantGenerator.ApplyRule` (active for CloneAndMutate) | `MutationTransformer` (table above) |
|---|---|---|
| 0 | No change (passthrough) | No change |
| 1 | Blank the field (max one per AttributeGroup per variant) | Blank the field |
| 2 | **no-op** (falls through to passthrough) | `SlightTypo` |
| 3 | `MutationHelper.SwapCharacters` | `SwapCharacters` |
| 4 | `MutationHelper.SlightTypo` | `MutateAddress` |
| 5 | Synonym swap via `SynonymHelper.ApplySynonyms(attr, input, rng)` | `MutateCity` |
| 6+ | **no-op** | `CaseToggle` … `MutatePhone` |

Consequences when editing a CloneAndMutate config: rule 4 produces a typo (not an address
mutation), rule 5 is the only way to get synonym replacement, and rules 2 and 6-11 silently
do nothing.

Other `VariantGenerator` behaviors not present in `MutationTransformer`:

- **Deterministic per-variant seed**: `seed = int.Parse(baseRecord.Code) * 31 + idx` — same base record + variant index always mutates identically (base `Record.Code` must parse as an integer or it throws).
- ~~**`MaxAttributeChanges` cap**~~ — **no longer a VariantGenerator-only feature.**
  `DataMutationSettings.MaxAttributeChanges` is now enforced in `MutationTransformer` too, via
  `SelectAttributesToMutate`, which draws a random subset from the **seeded** RNG so the choice is
  reproducible. `0` means no cap.
- **Group-blank constraint**: rule 1 is limited to one blank per `AttributeGroups` group per variant.
- **Enrich/carry-forward**: the original clone is enriched (source system = first of `sourceSystems`, `FullName` recomputed from First+Last); variants carry the original's enrichment forward.

### SynonymHelper (rule 5 payload)

`TestAuto.Shared\Helpers\SynonymHelper.cs` loads the six **embedded** lists at
`TestAuto.Shared\SynonymLists\<Category>.json` (PLURAL folder): `Address`, `City`, `Country`,
`DateOfBirth`, `Email`, `StreetAddress` (there is **no** `FirstName` list). The dictionary key
is the bare **filename stem** (`Address`, `City`, …) — this matches the attribute/category name
`VariantGenerator` passes to `ApplySynonyms(attr, …)`.

> ✅ **Fixed 2026-07-13 — rule 5 (synonym swap) is now functional.** Two historical traps were
> corrected together: (1) the resource filter is now `n.Contains(".SynonymLists.")` (the old
> `Contains("SynonymList.")` matched zero manifest names, making the loader a permanent no-op);
> (2) the constructor no longer deserializes each file as a flat `List<string>` — the shipped
> files are **Profisee Matching synonym-file exports** (`MatchingSynonymTypes` schema), which
> the old code could not parse.

**Parsing** (`ExtractSynonymTerms`): `JToken.SelectTokens("$..Synonyms")` recursive descent
handles both export layouts — legacy (`Synonyms` = direct array with top-level `Name`/`Term`,
e.g. `Address.json`, AssemblyVersion 2.5.7) and current (`Synonyms.MatchingSynonym[]` with
nested `Identifier.Name` + `Term`, 21.x–23.x exports) — plus wrapped/unwrapped roots and
single-or-array `MatchingSynonymType`. Each entry yields `Identifier.Name` (or `Name`) plus any
non-empty `Term`; results are whitespace-filtered and case-insensitively de-duplicated. Each
file parses inside a per-file try/catch — a malformed file logs a Startup warning and yields an
empty category instead of aborting the constructor (which runs during scenario construction, so
a throw would cascade into scenario-resolution failure). Loaded term counts for reference:
Address 576, Country 57, DateOfBirth 27, StreetAddress 21, Email 20, City 11.

`ApplySynonyms(category, input, rng)` (unchanged):

1. Finds all synonyms from the category list that appear in `input` (case-insensitive substring).
2. Picks one matched term at random, picks a random *other* synonym as replacement.
3. Replaces only the **first occurrence** (regex, case-insensitive, 50 ms timeout).
4. Returns input unchanged if the category is unknown, has <2 entries, or nothing matches.

To add a synonym category: add `SynonymLists\<Category>.json` as an **EmbeddedResource** in
`TestAuto.Shared` using the Matching export schema (any JSON containing a `Synonyms` node in
either supported layout). A flat JSON string array is **not** parsed by the current extractor.

---

## Adding a New Transformer

1. Implement `IRecordTransformer` in `TestAuto.Records/Helpers/`.
2. Register in `RecordsModuleRegistrar`:
   ```csharp
   services.AddTransient<MyNewTransformer>();
   services.AddTransient<IRecordTransformer, MyNewTransformer>();
   ```
3. Inject `IEnumerable<IRecordTransformer>` where you need to select between transformers, or inject the concrete type directly.

---

## Sources

- `TestAuto.Records\Interfaces\IRecordTransformer.cs`
- `TestAuto.Records\Helpers\MutationTransformer.cs`
- `TestAuto.Records\Helpers\FakerTransformer.cs`
- `TestAuto.Records\AutoRegistration\RecordsModuleRegistrar.cs`
- `TestAuto.Shared\Common\Data\TransformationContext.cs`
- `TestAuto.Shared\Common\Data\DataMutationSettings.cs` (AttributeGroups at :23)
- `TestAuto.Records\Common\RecordsConstants.cs` (`UseMutationHelper` at :15)
- `TestAuto.Records\Scenarios\CRUD\Updates\UpdateContinousRecordsByPageAndBatchScenario.cs` (live selector :292-294; reflection accessors :429-434)
- `TestAuto.Records\Scenarios\CRUD\Updates\UpdateRecordsByPageAndBatchScenario.cs` (Faker hard-wired at :216)
- `TestAuto.Records\Helpers\VariantGenerator.cs` (ApplyRule ~223-232, seed/groups/cap ~68-125)
- `TestAuto.Shared\Helpers\SynonymHelper.cs`
- `TestAuto.Records\Scenarios\Mutate\CloneAndMutateScenario.cs`
