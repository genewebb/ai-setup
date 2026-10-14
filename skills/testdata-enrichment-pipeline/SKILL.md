---
name: testdata-enrichment-pipeline
description: >
  Standalone ETL pipeline for enriching and cloning test data in SQL Server. Use when writing or
  debugging TestData.Enrichment.Core or TestData.CloneAndMutate, running the TestData.Enrichment
  console tool or its ScenarioRunner, implementing an EnrichmentService scenario, adding a
  FieldRuleDefinition generator, configuring CloneAndMutate mutation rules, DbCheckpointManager
  resume logic, or BulkCopyHelper inserts. The narrower add-an-IFieldGenerator walkthrough is
  testauto-enrichment-generators.
---

Repo: speed-merchants (paths below are repo-relative)

# TestData Enrichment Pipeline

This skill covers the **TestData.\*** project family: standalone ETL tools that operate
directly against SQL Server to enrich, mutate, and clone test data. These projects are
entirely separate from `TestAuto.*` and run outside of the scenario/Hangfire test
execution pipeline.

## Project Family

| Project | Role |
|---|---|
| `TestData.Enrichment` | Console exe entry point — loads a scenario file, runs `ScenarioRunner` |
| `TestData.Enrichment.Core` | Generic enrichment pipeline, field rule model, generator framework |
| `TestData.CloneAndMutate` | Clone originals across source systems, apply mutations, bulk insert |
| `TestData.Shared` | `DbCheckpointManager`, `BulkCopyHelper`, shared interfaces |

---

## ScenarioRunner — the console tool's actual pipeline

The `TestData.Enrichment` console exe does **not** use `EnrichmentService`. Its
`Program.cs` deserializes exactly one `ScenarioDefinition` from a command-line JSON
file (Newtonsoft), then **manually constructs** the runner:

```csharp
// Program.cs line 70 (DI block):  // DO NOT register ScenarioRunner!
// Program.cs line 164:
var runner = new ScenarioRunner(settings, checkpoint, perf, factory, scenarios);
```

ScenarioRunner stays out of the container because its constructor takes the
`IList<ScenarioDefinition>` parsed from the runtime file argument — the scenario
list doesn't exist until after the host is built, so it can't be resolved from DI.
The DI block registers everything *around* it instead: `AppSettings` (validated
options), `DbCheckpointManager`, `PerformanceTracker`, assembly-scanned
`[Generator]` types, and `FieldGeneratorFactory`.

### `RunScenarioAsync` flow (ScenarioRunner.cs)

```
1. scenario.Sources.Single() → TableSourceFetcher(srcDef.ConnectionString, srcDef)
2. Generator preload: for every Generate rule → factory.Create + Configure,
   then PreloadAsync(openConn) on each (e.g. SSN uniqueness set, code resume)
3. LoadLastCodeAsync + LoadLastBatchAsync          // resume cursor + batch number
4. Loop: FetchBatchAsync(lastKey, BatchSize)
5. _context["BatchNumber"] = batchNum              // feeds FieldRuleType.Context rules
6. Per record, inline rule switch: Map | Generate | Constant | Clear | Context
7. BulkMerge(enriched)                             // ALWAYS runs — even in TestMode
8. lastKey = batch[^1].Code; break if it did not advance (infinite-loop guard)
9. SaveLastCodeAsync + SaveLastBatchAsync          // skipped in TestMode
10. Break on: empty batch | TestMode (one batch only) | MaxBatches reached
```

**TestMode difference vs EnrichmentService**: ScenarioRunner still executes the
merge in TestMode — it only skips the checkpoint saves and stops after one batch.

### BulkMerge internals (ScenarioRunner.cs ~158–316)

1. Builds a `DataTable`: key column + the distinct `TargetColumn`s from FieldRules.
2. **Column-length truncation**: `GetTargetColumnMaxLengthsAsync` queries
   `INFORMATION_SCHEMA.COLUMNS` for the target table's `varchar`/`nvarchar`
   `CHARACTER_MAXIMUM_LENGTH`, and any string value longer than the column is
   silently `Substring`-truncated before staging (no warning logged).
3. Validates identifiers via `SqlIdentifierValidator`, creates
   `#Temp_{ScenarioName}` — key as `NVARCHAR(128)`, all other columns `NVARCHAR(MAX)`.
4. `SqlBulkCopy` into the temp table (BatchSize from settings, 120 s timeout).
5. Conditional `MERGE` inside a transaction:
   - `WHEN MATCHED THEN UPDATE` clause emitted only if `scenario.AllowUpdates`
   - `WHEN NOT MATCHED BY TARGET THEN INSERT` clause emitted only if `scenario.AllowInserts`
6. Temp table dropped in `finally` (drop failure logged as warning, not rethrown).

### ScenarioDefinition / SourceDefinition (TestData.Enrichment.Core\Models)

`ScenarioDefinition`: `Name`, `Sources` (a list, but the runner requires exactly
one — `Sources.Single()`), `FieldRules`, `TargetTable` (e.g. `dbo.RetailClient`),
`KeyColumn` (default `"Code"`), and the merge gates `AllowInserts` /
`AllowUpdates` (both default `true`).

`SourceDefinition`: `Type`, `KeyColumn?` (falls back to the scenario key),
`SortColumns` (the column(s) to ORDER BY and page on), `Filter` (optional custom
WHERE clause *without* the `WHERE` keyword), `ConnectionString`, `TableName`,
`Columns`.

### ICheckpointAware (optional generator interface)

`TestData.Enrichment.Core\Interfaces\ICheckpointAware.cs` declares a single
`Task SaveCheckpointAsync()` for generators that need to persist their own
progress. `CodeGenerator` implements it: `PreloadAsync` resumes `_current` from
checkpoint key `CodeGenerator:{TargetTable}.{ColumnName}`, and
`SaveCheckpointAsync` writes the last issued sequence number back through
`ICheckpointManager`.

**Gotcha**: nothing in the repo currently *calls* `SaveCheckpointAsync` —
ScenarioRunner never invokes it, so CodeGenerator's own checkpoint is read on
preload but never written by the orchestrator. Don't rely on it persisting
without adding the call.

---

## EnrichmentService\<TSource, TTarget, TEnriched\>

The generic, repository-based pipeline class. **Not used by the TestData.Enrichment
console tool** — that path is `ScenarioRunner` (above). Keep this in mind when
tracing runtime behavior: EnrichmentService is the library abstraction for
strongly-typed source/target pairs. Constructor takes:
- `IEnrichmentRepository<TSource, TTarget, TEnriched>` — fetch source, fetch target, bulk merge
- `IEnrichmentTransformer<TSource, TTarget, TEnriched>` — transforms a (source, target?) pair into `TEnriched`
- `ICheckpointManager` — resume cursor
- `PerformanceTracker` — batch timing/throughput metrics
- `AppSettings` — `BatchSize` and `TestMode` flags

### Pipeline loop in `RunAsync`

```
1. LoadLastCodeAsync(scenarioName)        // resume from checkpoint
2. FetchSourceBatchAsync(lastKey, batch)  // page forward by Code
3. FetchTargetBatchAsync(lastKey, batch)  // lookup by same page key
4. Build Dictionary<string,TTarget> from target batch
5. For each source: transformer.Transform(src, tgt?) → TEnriched
6. BulkMergeAsync(enrichedList)           // skipped in TestMode
7. SaveLastCodeAsync(scenarioName, lastKey) // advance cursor
8. Break when sourceBatch.Count < batchSize (last page)
```

**Key constraint**: all record types must expose a `public string Code { get; }` property.
The pipeline uses reflection (`GetProperty("Code")`) to extract the cursor key. Records
without this property throw `InvalidOperationException` at runtime.

**TestMode**: when `AppSettings.TestMode == true`, the merge and checkpoint save are both
skipped. The loop still runs and logs what it would have done.

---

## FieldRuleDefinition

Drives how a single target column is populated. Lives in
`TestData.Enrichment.Core/Models/FieldRuleDefinition.cs`.

```csharp
public class FieldRuleDefinition
{
    public string TargetColumn { get; set; }   // destination column name (required)
    public FieldRuleType RuleType { get; set; } // Map | Generate | Constant | Context | Clear

    // Used when RuleType == Map:
    public string? SourceColumn { get; set; }

    // Used when RuleType == Generate:
    public string? Generator { get; set; }           // "SSN", "Email", "DOB", "Code", "Cleanup"
    public Dictionary<string, object>? Options { get; set; } // e.g. EmailProviders list

    // Used when RuleType == Constant:
    public object? Constant { get; set; }

    // Used when RuleType == Context:
    public string? ContextKey { get; set; }
}
```

### FieldRuleType values

| Value | Behavior |
|---|---|
| `Map` | Copy value from `SourceColumn` on the source record |
| `Generate` | Invoke the named generator (see below) |
| `Constant` | Write the literal `Constant` value to every row |
| `Context` | Pull value from a runtime context bag via `ContextKey` |
| `Clear` | Set the column to null/empty |

---

## FieldGeneratorFactory

Resolves `IFieldGenerator<SourceRecord>` from a `FieldRuleDefinition` and a
`ScenarioDefinition`. Uses `ActivatorUtilities.CreateInstance` (DI-aware construction)
for every generator type.

**Selection logic**:
1. Switch on `rule.RuleType` first.
2. For `Generate`, switch on `rule.Generator` string.
3. Unknown rule types or generator names throw `InvalidOperationException`.

Named generators understood by the factory:

| Generator name | Class | Notes |
|---|---|---|
| `"SSN"` | `SsnFieldGenerator` | Preloads existing SSNs from DB; generates unique 9-digit strings via Bogus |
| `"Email"` | `EmailFieldGenerator` | Requires `Options["EmailProviders"]` list; builds `first[sep]last@provider`, increments counter on collision |
| `"DOB"` | `DobFieldGenerator` | Age range 18–80 (hardcoded in factory; override via `rule.Options` if needed) |
| `"Code"` | `CodeGenerator` | Generates sequential/formatted code values |
| `"Cleanup"` | `CleanupGenerator` | Normalises/sanitises field values |

Structural generators (created for `Map`, `Clear`, `Constant`, `Context`):
- `MapFieldGenerator` — copies source → target column
- `ClearFieldGenerator` — nulls target column
- `ConstantFieldGenerator` — writes a fixed value
- `ContextFieldGenerator` — reads from a keyed runtime context

### Adding a new generator

1. Create `MyGenerator.cs` in `TestData.Enrichment.Core/Generators/`, implement
   `IFieldGenerator<SourceRecord>`, decorate with `[Generator("MyName")]`.
2. Add a `case "MyName":` branch in `FieldGeneratorFactory.Create()`.
3. Register the class in DI if it needs injected dependencies.

---

## DbCheckpointManager (TestData.Shared)

Persists resume state in `dbo.tCheckpoint` (auto-created on first use).

```sql
CREATE TABLE dbo.tCheckpoint (
    ScenarioName NVARCHAR(100) NOT NULL PRIMARY KEY,
    LastCode     NVARCHAR(100) NULL,
    LastBatch    INT           NULL,
    ModifiedDate DATETIME2     NULL
)
```

### API

| Method | Purpose |
|---|---|
| `LoadLastCodeAsync(scenario)` | Returns `""` if no checkpoint exists |
| `SaveLastCodeAsync(scenario, code)` | MERGE upsert — safe to call every batch |
| `LoadLastBatchAsync(scenario)` | Returns `1` if no checkpoint exists |
| `SaveLastBatchAsync(scenario, batchNumber)` | Stores batch number cursor instead of code |
| `ResetAsync(scenario)` | Deletes the row — forces full re-run next time |

**Resume pattern used by EnrichmentService**: pass `lastCode` as the "greater-than" page
key to `FetchSourceBatchAsync`. On crash/restart, `LoadLastCodeAsync` returns the last
successfully saved code and resumes from there without reprocessing.

---

## BulkCopyHelper (TestData.Shared)

Static helper wrapping `SqlBulkCopy`. Two overloads:

```csharp
// Opens its own connection — use for standalone inserts
await BulkCopyHelper.BulkCopyAsync(
    items,
    destinationTable: "dbo.tMyTable",
    connectionString: connStr,
    batchSize: 1000,            // optional; defaults to all rows
    columnMappings: null,       // optional; defaults to name-match
    cancellationToken: ct);

// Reuses an existing open SqlConnection — use when staging into a temp table
await BulkCopyHelper.BulkCopyAsync(
    connection,
    items,
    destinationTable: "#TempStage",
    batchSize: 1000,
    columnMappings: null,
    cancellationToken: ct);
```

- Converts the `IEnumerable<T>` to a `DataTable` via the `ToDataTable()` extension
  (maps column names by default; override with `columnMappings` dict).
- Column mappings are added by name automatically from the DataTable columns.
- Does **not** handle transactions — wrap in a `SqlTransaction` at the call site if needed.

---

## CloneAndMutateService (TestData.CloneAndMutate)

Clones existing `RetailClient` records across multiple source systems, applies mutations
to each clone, then bulk-inserts all clones.

### Pipeline loop in `RunAsync`

```
1. LoadLastCodeAsync("CloneAndMutate")  // checkpoint cursor
2. FetchOriginalsAfterAsync(lastCode, batchSize)
3. For each original × each CloneSourceSystem:
       clone = transformer.DeepClone(original)
       clone.Code = nextCode++ (zero-padded 10 digits from CodeSeed)
       clone.SourceSystem = sys
       clone.OriginalRecordId2 = original.Code
       transformer.Mutate(clone, MutationSettings)
4. BulkInsertClonesAsync(clones)
5. SaveLastCodeAsync("CloneAndMutate", lastCode)
6. Break on: empty batch | TestMode record limit | MaxBatches limit
```

**Settings that drive CloneAndMutate**:
- `BatchSize` — records fetched per iteration
- `CodeSeed` — starting long value for generated codes
- `CloneSourceSystems` — list of source system names; one clone per system per original
- `MutationSettings` — passed verbatim to `IMutationTransformer.Mutate`
- `TestMode` + `TestRecordLimit` — cap total originals processed
- `MaxBatches` — hard cap on iterations regardless of data remaining

---

## Mutation Engine (TestData.CloneAndMutate\Mutation)

> **Disambiguation**: `TestData.CloneAndMutate.Mutation.MutationTransformer` is a
> completely different class from `TestAuto.Records\Helpers\MutationTransformer.cs`
> (scenario-driven record mutation inside the TestAuto pipeline) — that one is
> covered by [[testauto-record-transformation]]. Same name, separate codebases.

### RuleIds registry (Mutation\RuleIds.cs)

14 integer rule ids (0–13). Per the file's own comment: keep in sync with the
switch in `MutationTransformer`.

| Id | Const | Effect |
|---:|---|---|
| 0 | `NoChange` | leave value as-is |
| 1 | `Blank` | return empty string |
| 2 | `Typo` | `SlightTypo` — swap adjacent / delete / duplicate / flip one char |
| 3 | `Swap` | `SwapCharacters` — reverse `Swap.Count` chars at `Swap.Position` (Beginning/Middle/End) |
| 4 | `Address` | `MutateAddress` — tweak a digit in the leading house number, else SlightTypo |
| 5 | `City` | `MutateCity` — SlightTypo on the trimmed value |
| 6 | `CaseToggle` | toggle case of one random letter |
| 7 | `State` | 2-letter code → replace one letter; otherwise SlightTypo |
| 8 | `Country` | normalize to a random US variant ("United States" / "USA" / "United States of America") |
| 9 | `Postal` | `MutatePostal` — mutate one digit (ZIP-aware) |
| 10 | `Email` | `MutateEmail` — plus-alias, or typo in local/domain part |
| 11 | `Phone` | `MutatePhone` — replace exactly one digit, formatting chars preserved |
| 12 | `DOBShift` | `MutateDOB` — shift date ±1–5 days, returns `yyyy-MM-dd` |
| 13 | `SSNMutate` | `MutateSSN` — tweak one digit, hyphens preserved |

### MutationTransformer (Mutation\MutationTransformer.cs)

- `Mutate(clone, MutationSettings)` iterates `RuleDefinitions` keys, reflects the
  matching `RetailClient` property, applies one mutation, and converts non-string
  results via `Convert.ChangeType` (silently nulls on conversion failure). Uses
  `Random.Shared` so rapid calls don't re-seed.
- `DeepClone` = Newtonsoft serialize/deserialize round-trip.
- `ApplyMutation` (~lines 102–170): **weighted random rule selection** —
  `roll = rng.NextDouble() * sum(Weights)`, accumulate weights until
  `roll <= acc`; defaults to the **last** rule id if nothing matched. Returns the
  value unchanged when `Rules`/`Weights` are null, empty, mismatched in count, or
  total weight ≤ 0. The chosen id is then dispatched via `switch (chosen)` to the
  matching `MutationHelper` static.
- **Exactly one rule fires per attribute per record.**
  `MutationRuleDefinition.ApplyMoreThanASingleRule` exists on the model (and in
  `Mutation.md`), but this transformer never reads it.

### Format-preserving regexes (Mutation\MutationHelper.cs)

Compiled regexes classify the input so mutations preserve a plausible shape:

| Regex | Pattern | Used by |
|---|---|---|
| `EmailRegex` | `^\s*([^@\s]+)@([\w\.-]+\.[A-Za-z]{2,})\s*$` | `MutateEmail` — splits local/domain; mutates one side or adds `+N` alias |
| `UsZipRegex` | `^\d{5}(-\d{4})?$` | `MutatePostal` — mutates one of the first 5 digits only |
| `SsnLikeRegex` | `^\d{3}-\d{2}-\d{4}$` | `MutateSSN` — picks one of the 9 digit positions, skips the hyphens |
| `DigitsRegex` | `^\d+$` | `MutatePostal` fallback for non-ZIP all-digit values |

Non-matching inputs fall back to `SlightTypo` (or a single-digit change), so the
output stays realistic rather than garbage.

### Mutation.md (repo doc) — trust the code over it

`TestData.CloneAndMutate\Mutation\Mutation.md` explains rule semantics, the Swap
config shape, and a sample per-field weight table — useful for config examples.
But it has drifted from the code: it lists rules only 0–11 (no `DOBShift`=12 /
`SSNMutate`=13; it folds DOB/SSN into rule 4), claims `MutatePhone` replaces
*each* digit (code replaces exactly one), and describes two-rule
`ApplyMoreThanASingleRule` behavior the transformer does not implement. It also
notes `AttributeGroups` is defined but not consumed. Verify behavior against
`RuleIds.cs` / `MutationHelper.cs`.

---

## When to Use This Skill vs Others

| Situation | Skill to use |
|---|---|
| Writing or extending TestData.Enrichment.Core / CloneAndMutate | **this skill** |
| Checkpoint or BulkCopy in TestData.Shared | **this skill** |
| CloneAndMutate mutation rules (RuleIds/MutationHelper) | **this skill** |
| Step-by-step *add a new IFieldGenerator* walkthrough (attribute, factory `case`, FieldRules JSON) | [[testauto-enrichment-generators]] — **same `TestData.Enrichment*` codebase despite its `testauto-` name**; it is the narrower sibling of this skill, not a TestAuto counterpart |
| Record mutation inside TestAuto (`TestAuto.Records\Helpers\MutationTransformer.cs`) | [[testauto-record-transformation]] |
| Test-record generation inside TestAuto (`TestDataFactory`, `[ScenarioTypes]` generators) | [[testauto-test-data-generation]] |
| Hangfire job execution pipeline in TestAuto | `testauto-hangfire-architecture` |

---

## Sources

- `TestData.Enrichment\Program.cs`
- `TestData.Enrichment.Core\Services\ScenarioRunner.cs`
- `TestData.Enrichment.Core\Services\EnrichmentService.cs`
- `TestData.Enrichment.Core\Models\FieldRuleDefinition.cs`
- `TestData.Enrichment.Core\Models\ScenarioDefinition.cs`
- `TestData.Enrichment.Core\Models\SourceDefinition.cs`
- `TestData.Enrichment.Core\Interfaces\ICheckpointAware.cs`
- `TestData.Enrichment.Core\Services\FieldGeneratorFactory.cs`
- `TestData.Enrichment.Core\Generators\` (all generators)
- `TestData.Shared\Services\DBCheckpointManager.cs`
- `TestData.Shared\Helpers\BulkCopyHelper.cs`
- `TestData.CloneAndMutate\Services\CloneAndMutateService.cs`
- `TestData.CloneAndMutate\Mutation\RuleIds.cs`
- `TestData.CloneAndMutate\Mutation\MutationTransformer.cs`
- `TestData.CloneAndMutate\Mutation\MutationRuleDefinition.cs`
- `TestData.CloneAndMutate\Mutation\MutationHelper.cs` (namespace `TestData.CloneAndMutate.Helpers`)
- `TestData.CloneAndMutate\Mutation\Mutation.md` (partially stale — see caveats above)
