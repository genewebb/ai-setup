---
name: testdata-generation-and-mutation-shape-authoring
description: >
  Authoring the shape-JSON files that drive TestData.Generation and TestData.Mutation — both contracts are
  CLOSED sets with no invention allowed, fixed column ordinals, derived child discriminators, capped
  checkpoint keys and width traps that only bite at run time. Use when writing or editing a generation or
  mutation shape file, choosing a field kind or a mutation rule, adding a generator to the registry, sizing
  a run, hitting a validator refusal, or being asked for "N million uniques with twins at X%".
---

Repo: speed-merchants (paths below are repo-relative)

# Shape authoring — TestData.Generation and TestData.Mutation

The shape JSON is each tool's **entire API surface**, and in both products it is a **closed contract**:
the field kinds, generator names and mutation rules are fixed sets sourced from the code's own constants.
**Nothing may be invented.** A shape naming a kind that does not exist is refused; a shape that is
structurally valid but arithmetically wrong runs for hours and produces the wrong data.

> **Defer to the shipped authority, do not restate it.** Each product ships an exhaustive brief and an
> in-app manual: `TestData.Generation/Claude/CLAUDE.md` + `/help/shape-reference`, and
> `TestData.Mutation/Claude/CLAUDE.md` + its 21 `Web/Documentation/*.md` pages. Those are authoritative
> for the key tables. This skill carries the **code-side invariants and the traps**, so the two cannot
> drift. Read the brief for the tables; read this for what the tables do not say.
>
> Note the briefs live in a `Claude/` **subfolder**, so they are *not* auto-loaded as memory files — they
> are an installer payload for an agent working on a deployed box (`{app}\Claude`).

## When to Use

- "Give me 5 million uniques with twins at 5%"
- "Which field kinds / mutation rules are available?"
- "Add a generator" / "the validator refused my shape"
- "Why did this shape pass validation and then fail 40 minutes in?"

## The closed sets

| Product | Closed set | Count | Source of truth |
|---|---|---|---|
| Mutation | field kinds | **26** | `Engine/Fields/PersonFieldPack.cs:6` |
| Mutation | mutation rules | **20** | `Engine/Mutation/MutationRuleCatalog.cs:22-45` |
| Generation | `TypeRules` keys + generator names | closed | `Engine/Generation/GeneratorRegistry.cs` constants |

The catalogues are closed **because of determinism** (see
[[testdata-generation-and-mutation-engine]] §1) — an open set would let a shape change the draw stream.

`ShapeValidator` sources its `KnownGenerators` from `GeneratorRegistry`'s own constants rather than a
second list, so validator and registry **cannot drift**. Keep it that way when adding a generator.

> The in-repo Mutation brief is itself stale on the count: `CLAUDE.md:137` says "one of the **24**", while
> its own §7 header at `:300` and `PersonFieldPack.cs:6` both say **26**. Twenty-six is correct. The same
> brief calls the web help a "16-page manual" where there are now 21 pages.

## Column ordinals are a contract, not a formatting choice

Both tools fix the column order, and it is **the contract between the DDL builder and the bulk-copy
reader**:

- **Generation**: `Code, Name, Dba block, Date, DateTime, Text, Link, Number`. The optional IDENTITY `Id`
  sits **outside** the ordinal contract entirely.
- **Mutation**: fixed bulk-copy ordinals, and a resume is refused if a live table's ordinals have drifted.

`Code`, `Name` and `Dba` are system-fixed `nvarchar(250)` because **a Dba value IS an entity Code** — see
`reference_profisee_dba_is_entity_code`.

## Naming and length ceilings

| Rule | Ceiling | Why |
|---|---|---|
| `Naming.ColumnNames` list length | **must EQUAL** the Shape count | No topping up, no truncating — a mismatch is a refusal, not a best effort |
| resolved `entity_column` lookup name | **≤ 50 chars** | Gateway limit |
| Mutation checkpoint key `MUT:{EntityName}\|{table}` | **≤ 100 chars** | `ChunkCheckpointStore.RunNameLength` — a long entity name silently truncates the run identity, which is what a resume matches on |

## Traps that only bite at run time

These are the ones that pass validation and fail later:

- **Width overflow.** A `Gender` field with a `Typo` rule overflows `nvarchar(1)` — and only at RUN time,
  because the validator checks the shape, not the product of kind × rule × width.
- **Derived child DISC.** A child code is derived as a 3-letter discriminator, e.g. `{code:D10}-ADD-01`.
  It is derived, not authored — do not try to set it.
- **Un-ruled fields copy verbatim.** A field with no mutation rule is not skipped; it is copied as-is.
  "I left it out so it would not change" and "I left it out so it would not appear" are different
  intentions with the same syntax.

## The authoring workflow

Standing instruction from both briefs, and it is a **behavioural** rule rather than a code one:

1. **Never author a shape from scratch when a shipped sample is closer.** Copy, edit, validate.
2. `--test-mode` probe first.
3. Report the arithmetic — rows, chunks, estimated duration.
4. **Then STOP.** Never start a full run unprompted.
5. Never modify a file under `samples\` — installers ship them `onlyifdoesntexist uninsneveruninstall`
   precisely because an operator edits them in place.

## Sources

- `TestData.Mutation\TestData.Mutation.Engine\Model\MutationShape.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Model\MutationShapeValidator.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Fields\PersonFieldPack.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Mutation\MutationRuleCatalog.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Sql\MutationSchemaBuilder.cs`
- `TestData.Mutation\TestData.Mutation.Engine\Sql\ChunkCheckpointStore.cs`
- `TestData.Mutation\Claude\CLAUDE.md` — authoritative for the key tables
- `TestData.Mutation\TestData.Mutation.Web\Documentation\20_ShapeReference.md`, `21_FieldKinds.md`, `22_MutationRules.md`, `26_Uniqueness.md`
- `TestData.Generation\TestData.Generation.Engine\Model\ShapeValidator.cs`
- `TestData.Generation\TestData.Generation.Engine\Model\EntityPlan.cs`
- `TestData.Generation\TestData.Generation.Engine\Generation\GeneratorRegistry.cs`
- `TestData.Generation\TestData.Generation.Engine\Naming\NamingSettings.cs`
- `TestData.Generation\TestData.Generation.Engine\Sql\SchemaBuilder.cs`
- `TestData.Generation\Claude\CLAUDE.md` — authoritative for the key tables
