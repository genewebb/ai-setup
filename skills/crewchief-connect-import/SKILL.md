---
name: crewchief-connect-import
description: >
  CrewChief's native Connect-export to workload conversion — the /connect-import wizard, IConnectImportEmitter,
  the CrewChief-side ConnEx tokenization port, ConnExStepSetBuilder, and the replayable ConversionProfile.
  Use when converting a Profisee Connect portal export into a CrewChief workload, emitting RESET workloads (IEntityResetEmitter / IDatastoreResetEmitter / DatastoreResetEmitterRegistry and its short-type-name matching), supplying datastore shapes from a separate model export, working on the
  connect-import wizard or its token-selection dialog, building ConnEx step sets from artifacts, saving or
  replaying a conversion profile, or diagnosing a dry-run validation pass.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Connect Import

Turns a native **Profisee Connect portal export** into a runnable CrewChief workload: load the export,
review the artifacts found in it, choose which values become `{{tokens}}`, emit an ordered ConnEx step set,
and save the whole set of choices as a replayable profile.

This is CrewChief's **own** implementation. TestAuto has a parallel one ([[connex-import-tokenization]])
scoped entirely to `TestAuto.Web/Services/ConnExTokenization/`; CrewChief takes **zero** TestAuto
dependencies (see [[crewchief-architecture]]), so the tokenizer was ported into
`CrewChief.Engine/ConnEx/Tokenization/` rather than referenced. Do not assume a fix in one lands in the other.

CrewChief also has a **model** importer — [[crewchief-model-import]] (`/model-import`) — which converts a
Profisee model export into a `-teardown` / `-build` / `-refdata` / `-datastore` / `-full-run` workload
family. It borrows this feature's entity/attribute create payloads and SQL type map by **copy**, not by
reference, so a change here does not reach it.

## When to Use

- Converting a Connect export into a CrewChief workload.
- Working on `/connect-import` (the 5-step wizard) or `ConnExTokenSelectionDialog`.
- Adding or changing artifact detection, token scanning, or normalization.
- Working on `ConversionProfile` save/replay.
- "Why did the dry run keep going after a step failed?"

## The wizard

`/connect-import` (`CrewChief.Web/Components/Pages/ConnectImport.razor(.cs)`) is a five-step flow:
**Load → Review → Configure → Output → Finish**. It is backed by two services registered in `Program.cs`:
`IConnectImportEmitter` and a files-only `IConversionProfileStore`.

`IConnectImportEmitter` (`Services/ConnectImport/IConnectImportEmitter.cs`) has three members:

| Member | Role |
|---|---|
| `BuildStepSet` (`:119`) | Artifacts + token selections → an ordered ConnEx step set |
| `Emit` (`:136`) | Step set → the emitted workload/steps |
| `ValidateAsync` (`:145`) | The dry run |

> [!important] The dry run forces `ContinueOnError`, not just `DryRun`
> `ValidateAsync` clones every step with **`DryRun` *and* `ContinueOnError` both on** (`:154`). Setting only
> `DryRun` would stop the validation at the first failing step, which defeats the purpose — the operator
> wants the complete list of what is wrong in one pass, not one problem per round trip.

## Tokenization — the CrewChief port

`CrewChief.Engine/ConnEx/Tokenization/` (12 files): `ConnExArtifactDetector`, `ArtifactTokenScanner`,
`ArtifactTokenizer`, `ArtifactNormalizer`, `TokenCandidate`, `CandidateKind`, their interfaces, plus two
CrewChief-only additions.

### `ConnExStepSetBuilder`

Turns tokenized artifacts into an **ordered** ConnEx step set. The subtle part is identity: it locates each
artifact's identity candidate via `Selections` / `DefaultTokenName`, so a **renamed token still produces
correct `resourceId` references** between steps. Resolving identity by the token's current *name* would
break every cross-reference the moment an operator renamed one in the dialog.

Ordering matters because ConnEx resources must be created before the resources that reference them — the
three-resource ordering rule described in [[testauto-connex-provider-templates]] applies here too.

> [!important] Teardown tolerance has TWO layers (2026-09-19)
> The two Delete steps accept `200, 204, 404` **and** are emitted with `ContinueOnError` per
> `ConnExStepSetRequest.TeardownContinueOnError` (default **true**, teardown-scoped, never leaks onto other
> steps). Before this the flag was hard-wired `false` and a missing target that the gateway reported as
> anything but 404 stopped the whole import. The wizard's Finish step now carries both switches: **Include
> teardown** and **Teardown steps continue on error** (`IncludeTeardown` / `TeardownContinueOnError` on
> `ConnectImportEmitRequest`). The gateway's actual not-found status was never live-verified.

### `ArtifactTokenizer` — the entity name lives in FOUR places

A strategy repeats its target entity name at `entityId.name`, as the **`mappings` dictionary KEY**, as that
mapping's own `name`, and as the `[Entity]` prefix of every **`[Entity].[Attribute]` parameter KEY** (126
sites in the PDATA120 fixture). Until 2026-09-19 only `entityId.id/name` were tokenized and the rest shipped
hardcoded. `ReplaceEntityNameScoped` (keyed on `ReferenceTarget == Entity`, matching the artifact's CURRENT
name read before the node is overwritten) now rewrites all four with `{{EntityName}}`. It is deliberately
scoped to those target-side sites: `remoteObjectName` / `dataSource` / `expressionText` are source-side and
belong to the `TargetDatabaseTableName` row, which keeps the Export-direction R4 trap (table name equals
entity name) from having the two rows steal each other's sites. Run-time substitution is textual, so a token
inside a JSON property KEY resolves like any other. **TestAuto's port still has this gap.**

### `ConversionProfile`

A **versioned, Newtonsoft-round-trippable replay record** of an operator's token selections. It exists so
that re-importing a newer export of the same Connect solution does not mean re-answering every token
question. Treat it as persisted data: adding a field means thinking about older profiles on disk.

Fixture note: the tokenization unit tests read real portal exports from the project-local
`CrewChief.Tests.Unit\TestData\ConnectExports\` (copied to output; formerly the machine-local
`{ScratchRoot}\ConnectExports`, moved in-repo 2026-08-19 per user rule "unit tests must not rely on artifacts
outside the project folder") and **`Assert.Fail`** when a fixture is missing — see [[crewchief-testing]].

## The reset-workload emitter family

Beyond `IConnectImportEmitter`, import can emit **reset** workloads: `IEntityResetEmitter` and
`IDatastoreResetEmitter`.

Per-datastore behaviour is resolved through `DatastoreResetEmitterRegistry` by **substring-matching
`Configuration.$type` on the SHORT type name** - because a Newtonsoft `$type` carries assembly identity,
so an exact match would break on any assembly change.

### Contract

| Rule | Detail |
|---|---|
| Emitters are **pure** | They return failure **results**, never throw |
| An unknown datastore | An explicit **Unsupported + reason**, not a silent skip and not an exception |
| "Shapes" are **EXPLICIT inputs** | They come from a **separate model export**, because the strategy artifact carries mapping expressions only - it does not describe the datastore's shape |
| Naming | `<base>-reset-entities` / `<base>-reset-datastore` / `<base>-full-run` |

That third row is the one that surprises: you cannot derive a reset workload from the strategy artifact
alone, so the wizard needs the model export too.

## Sources

- `CrewChief\CrewChief.Web\Services\ConnectImport\IConnectImportEmitter.cs`
- `CrewChief\CrewChief.Web\Services\ConnectImport\ConnectImportEmitter.cs`
- `CrewChief\CrewChief.Web\Components\Pages\ConnectImport.razor(.cs)`
- `CrewChief\CrewChief.Web\Components\Controls\ConnExTokenSelectionDialog.razor(.cs)`
- `CrewChief\CrewChief.Engine\ConnEx\Tokenization\` (12 files)
- `CrewChief\CrewChief.Web\Documentation\07_CookbookConnectImport.md`
- `CrewChief\CrewChief.Web\Documentation\49_WorkloadConnectImport.md`

## Related

[[connex-import-tokenization]] · [[crewchief-step-executors]] · [[crewchief-web-ui]] · [[crewchief-architecture]] · [[crewchief-token-replacement]] · [[crewchief-testing]]
