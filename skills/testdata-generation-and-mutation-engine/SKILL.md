---
name: testdata-generation-and-mutation-engine
description: >
  The shared engine contract behind the two standalone bulk test-data tools, TestData.Generation and
  TestData.Mutation — deterministic value derivation through SplitMix64, chunked resume over the
  co-tenanted dbo.tGenerationChunk/tGenerationPhase tables, the narrow SQL seams that make a run
  testable without SQL Server, the Profisee deploy package, the Blazor run host, and the two different
  ways each tool keeps a clear-text connection string out of its artefacts. Use when generating or
  mutating bulk data, resuming an interrupted run, adding a field generator or a mutation rule, adding a
  SQL call site, wiring either Blazor host, deploying a generated table to Profisee, or diagnosing why a
  rerun did not resume, why values shifted, or why a rate reads as a billion rows a second.
---

Repo: speed-merchants (paths below are repo-relative)

# TestData.Generation / TestData.Mutation — the engine contract

Two standalone products in `speed-merchants`, each with an engine, a CLI and a Blazor host. They are
**not** part of TestAuto's per-scenario record generation — `testauto-test-data-generation` and
`testdata-enrichment-pipeline` describe a different codebase with no shared type. These two tools bulk-
generate and bulk-mutate SQL data directly, and they share four contracts documented here.

> They also **share their checkpoint tables**. `dbo.tGenerationChunk` and `dbo.tGenerationPhase` are
> co-tenanted by both tools and kept apart only by a run-name prefix — Mutation writes `MUT:` — so a
> change to either store's key shape is a change to both products.

## When to Use

- "Generate 5 million uniques with twins at 5%"
- "The run died at 60% — how do I resume it?"
- "Add a new field kind / mutation rule / generator"
- "Why did the values change when I added a column?"
- "Deploy the generated table to Profisee"
- "Add a SQL call site to the engine"

## 1. Determinism is the load-bearing invariant

Every generated value is a pure function of **(RandomSeed, code, column ordinal)**, derived through
`SplitMix64.RowSeed` → `ColumnSeed`. `Random.Shared`, `Guid.NewGuid` and the clock are **banned as value
sources** — timing is audit metadata only. This is what makes a run reproducible and a resume safe.

Three traps, none derivable from reading one file:

| Trap | Consequence | Rule |
|---|---|---|
| `SplitMix64` is a **mutable struct** | A generator taking several draws re-copies the same state and returns the same number every time | Lift it into a local first: `var rng = ctx.Rng;` |
| Eight "coherent" field kinds read one per-row `PersonIdentity` instead of drawing | Adding or reordering a field would otherwise shift who a person is | Coherent kinds read the identity; they never draw |
| `MutationPass` skips NULL cells **below** `Pick` | The rule-selection draw is still spent | The stream stays a function of the SHAPE, not of the data |

That last one is the subtle one: the draw is consumed whether or not the cell is written, so two runs over
differently-populated data still produce the same stream.

## 2. Chunked resume — rerunning IS the resume

Work is partitioned into **half-open code ranges** `[StartCode, EndCodeExclusive)` that tile end-to-end.
A chunk is the checkpoint unit and **`EntityName` is the run identity**, so:

- There is **no resume flag**. Running the same shape file again resumes it.
- A chunk is checkpointed only after **every one of its tables** is written.
- Deleting the shape file does **not** clear checkpoints — they live in SQL.
- A resume is **REFUSED** if a live table's column ordinals have drifted, because the ordinals are the
  contract between the DDL and the bulk-copy reader (§3).
- A cancelled run is **Stopped (exit 2)** — never Failed, never 0.

## 3. Three narrow seams, so a run is testable with no SQL Server

The engine reaches SQL through exactly `IBulkWriter`, `ICheckpointClient` and `ISchemaGate`. Phase
progression, chunk partitioning, per-chunk table ORDER and the resume column guard are all testable by
faking that trio — `MutationOrchestratorTests` does exactly that.

Two shape details worth knowing:

- **`MutationPhases` is an enum, not strings**, and `WritingUniques`/`WritingClones` are two *markers*
  through ONE write stage.
- **`SyntheticDataReader` implements only the eight `IDataReader` members `SqlBulkCopy` actually calls**
  and throws `NotSupportedException` on the rest deliberately. Per-column factories are built once, never
  per row.
- `GetRecoveryModelAsync` returns **null** rather than throwing when it cannot determine the model.

## 4. Keeping the connection string out of the artefacts — two different answers

Both tools carry a clear-text connection string in the shape file, and both must keep it out of logs,
toasts, reports and saved profiles. **They solve it differently, and the contrast is the useful part.**

| | TestData.Generation | TestData.Mutation |
|---|---|---|
| Approach | **Structural** | **Procedural** |
| Mechanism | `ConnectionProfile` has **no public constructor** — `Sanitize(name, parts)` is the single construction path and the deserialiser ctor is private, so a saved profile *cannot* hold a password | Every `SqlException` message reaching a log, a UI toast or a rethrow must pass through `DatabaseOps.ScrubSecrets` first (36 call sites across 16 files) |
| Logging | `ConnectionStringParts.BuildRedacted()` routes through `ScrubSecrets` | same helper |
| Reports | The run-report model has **no field a connection string could occupy** — only `TargetServer`/`TargetDatabase`/`TargetSchema`, because reports get emailed | — |
| Failure mode | A new persisted field breaks it silently | A new SQL call site without the scrub leaks a password and **nothing fails a test** |

The structural answer is the stronger one. Prefer it when adding anything persisted.

Companion rules in `DatabaseOps`: error text is phrased **about** the connection string, never built from
it (`TryGetDatabaseName`); and `master`/`model`/`msdb`/`tempdb`/`ModelSource` are hard-protected from drop
with **no override flag**.

## 5. The Profisee deploy package (TestData.Generation only)

How a generated SQL table becomes a Profisee model. Three rules an agent gets wrong:

1. **Every gateway wire fact lives only in `DeployConstants`** — endpoints, the `x-api-key` header, content
   type, batch sizes, `attributeType`/`dataType` enum codes, and the **capitalised** Record `Code`/`Name`
   JSON keys that create accepts but GET returns lowercase. The two PS1 scripts are copied out of embedded
   resources **verbatim**, with `model.json` as the contract between them — so settling a gateway question
   is a one-constant edit plus a re-emit, never a script edit.
2. **`DeployModelBuilder` does bidirectional plan-vs-live-SQL drift detection** through `ISchemaReader` and
   throws `DeployModelDriftException` → CLI exit 1. The IDENTITY `Id` column is deliberately exempt.
3. **Two mappings are knowingly lossy** — decimal precision drops to Profisee's scale-only Number, and
   `datetime2` scale goes to 0 — and gateway ceilings are enforced at **mapping** time, not 120 attributes
   into a live deploy.

> `DeployConstants.cs:38-41` and `:97-111` cite `{ScratchRoot}\deploy-wire-check.md` (dated 2026-08-18) as the
> evidence for the content type and key casing. That file is machine-local and **not in the repo**, so the
> provenance for those wire facts is unverifiable from a clean checkout. Re-derive before trusting them.

## 6. The Blazor run host

Both hosts own **at most one run**, and everything is a singleton for a specific reason: **a circuit dies
on browser reconnect, and a circuit-scoped owner would kill a 500M-row run with it.**

- Pages hold **no run state** — they read `Snapshot` and subscribe to `Changed`.
- `Changed` fires on **arbitrary threads**, so a component MUST marshal via `InvokeAsync`.
- `IsRunning` is derived from **the Task**, not the phase, so a run that died pre-terminal cannot wedge
  the UI.
- Operator state is **files-only JSON beside the binaries** (`RunHistoryStore`, `ConnectionProfileStore`),
  capped, with write failures logged and **swallowed**.
- `Program.cs` pins `ContentRootPath` to `AppContext.BaseDirectory` **only when SCM-hosted**.

## 7. Progress and reporting — shared wording prevents CLI/Web divergence

`GenerationPhases` string constants hold values that are literally the narrow UI tile text (`"PrimaryKey"`,
not `"CreatingPrimaryKey"`), and `RunSnapshot.FinalSummaryText` is the **one sentence both surfaces print**.
Interlocked counters behind a single `Snapshot()` read path.

Two deliberate measurement guards:

- a **30s `RecentRateWindow`**, because throughput degrades as the table grows;
- a **1 ms `MinimumRateInterval` floor on the denominator**, so a short run cannot report
  "1,000,000,000 rows/s".

`--emit-report` writes from a single `finally`, so a report exists for **every** terminal outcome and can
never alter the exit code.

## Sources

- `TestData.Generation\TestData.Generation.Engine\Generation\SplitMix64.cs`
- `TestData.Generation\TestData.Generation.Engine\Model\ChunkMap.cs`
- `TestData.Generation\TestData.Generation.Engine\Sql\ChunkCheckpointStore.cs`
- `TestData.Generation\TestData.Generation.Engine\Generation\SyntheticDataReader.cs`
- `TestData.Generation\TestData.Generation.Engine\Deploy\DeployConstants.cs`
- `TestData.Generation\TestData.Generation.Engine\Deploy\DeployModelBuilder.cs`
- `TestData.Generation\TestData.Generation.Engine\Deploy\ProfiseeAttributeMapper.cs`
- `TestData.Generation\TestData.Generation.Engine\Model\ConnectionProfile.cs`
- `TestData.Generation\TestData.Generation.Engine\Model\GenerationRunState.cs`
- `TestData.Generation\TestData.Generation.Engine\Reporting\RunReportWriter.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Generation\SplitMix64.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Fields\FieldGenContext.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Generation\MutationPass.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Generation\IBulkWriter.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Generation\MutationPhases.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Sql\ChunkCheckpointStore.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Sql\DatabaseOps.cs`
- `TestData.Mutation\TestData.Mutation.Web\Services\MutationRunService.cs`
- `TestData.Mutation\TestData.Mutation.Web\Services\RunHistoryStore.cs`
