---
name: crewchief-workload-transfer
description: >
  CrewChief's files-only cross-machine transfer bundles: WorkloadBundle/WorkloadTransferService, the
  StepBundle/StepTransferService sibling, and the ExportStepsToLibraryDialog flow that promotes a
  workload's inline steps into the library. Use when moving a workload or library steps between
  CrewChief instances, building or importing a bundle, exporting steps to the library, or working on
  the export/import UI or its plaintext-secret leak guard.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Workload Transfer

Makes a workload **portable between CrewChief instances** with no database — a single self-contained JSON document carries the workload, whose entries already hold their full step bodies inline, so it runs identically on a target machine regardless of that machine's existing library. This is CrewChief's files-only analog of TestAuto's `IWorkflowTransferService`/`WorkflowBundle` (see [[testauto-workflow-transfer]]). Two siblings share the doctrine: the **step-library bundle** (`StepBundle`, below) moves selected library steps between instances, and `ExportStepsToLibraryDialog`/`IStepLibraryExporter` (below) promotes a workload's inline steps into the local library.

## When to Use
- Moving or replicating a workload between CrewChief instances.
- Building, serializing, parsing, previewing, or importing a `WorkloadBundle` — or its step-library sibling, a `StepBundle`.
- Working on the Web export/import UI (confirm dialogs, preview) or a CLI export/import.
- Promoting a workload's inline steps into the reusable step library (`ExportStepsToLibraryDialog` / `IStepLibraryExporter`).
- Adding/adjusting the plaintext-secret export guards.

## `WorkloadBundle`
Serialized to `<name>.workload-bundle.json`:
- `SchemaVersion` — `WorkloadBundle.CurrentSchemaVersion` = `"1.0"` (bumped only on a breaking shape change).
- `ExportedUtc` — informational timestamp.
- `Workload` — the exported `WorkloadFile`, carried **verbatim**. Every entry is already a self-contained `Inline` body, so there is nothing to flatten.

> [!note] `ReferencedSteps` was REMOVED
> The bundle is now exactly three fields — there is no library-step snapshot, because a workload no longer references library steps (see [[crewchief-orchestration]]: adding from the library deep-copies the step in). A bundle is self-contained by construction rather than by collection.
> `ParseBundle` tolerates an older bundle that still carries `ReferencedSteps` — the property is simply ignored on deserialize — and imports its inline workload normally (`WorkloadTransferServiceTests.ParseBundle_OlderBundleWithReferencedSteps_StillImportsItsInlineWorkload`).

## `IWorkloadTransferService` / `WorkloadTransferService`
`BundleSettings` = `{ Converters = { new UtilityStepConverter() }, Formatting.Indented }` so the polymorphic `StepFile.Step` round-trips and bundles are human-readable/diffable. All cloning is serialize→deserialize through `BundleSettings` (no shared references with live store instances).

| Method | Behavior |
|---|---|
| `BuildBundle(workloadName)` | Loads the workload and deep-clones it into the bundle (`:47-67`). No ref collection, no `IStepFileStore` lookup, no dangling-ref failure mode — those went away with `Ref`. A `LegacyWorkloadRefException` from the store load is caught and returned as a `Fail`, deliberately: exporting a workload we refuse to load would carry the broken shape to another machine |
| `SerializeBundle(bundle)` | Bundle → indented JSON |
| `ParseBundle(json)` | JSON → bundle; returns `null` for null/blank/malformed input or a bundle with no named workload. Runs `LegacyWorkloadRefGuard.ThrowIfLegacyRef` on the raw `workload` JObject **before** deserializing (`:98`), so a legacy bundle is refused at the import surface exactly as it is at the disk surface |
| `PreviewBundle(bundle)` | Read-only dry-run: same import validation gates, and mints the exact target name it would save under (via `BuildImportName`) with a `NameCollision` flag — never persists. There is no CREATE-vs-EXIST step classification any more |
| `ImportBundle(bundle)` | Saves the workload under a fresh non-colliding name. It creates **no** library steps — the workload carries its own step bodies |

**Import validation** (`ValidateImportable`, shared by preview + import): rejects a null bundle, an unsupported `SchemaVersion`, or a workload that is missing / nameless / step-less.

### Always-new import naming — `BuildImportName` (pure, static)
Never overwrites. Returns `desiredName` if free (case-insensitive), else the first free of `<name>-imported`, `<name>-imported-2`, `<name>-imported-3`, … Blank name falls back to `"workload"`. Mirrors the Workloads copy-name minting. Import touches the workload store only — it no longer recreates library files, because the bundle carries no library steps.

### Plaintext-secret export guard — `FindPlaintextSecrets` (pure, static)
Warns (never blocks, never strips) before a plaintext secret is written into a shareable bundle:
- **Detection is a shared heuristic, not a per-service name list** — `TransferSecretScan` (`CrewChief.Data\Services\TransferSecretScan.cs`) is the ONE definition, called by both transfer services. It replaced the old per-service `SecretFieldLabels` maps, which exact-matched only `apiKey`/`password` and therefore **missed `sharePassword`, `credentialPassword`, and every `clientSecret`-shaped field**. Two calls:
  - `IsSecretishField(fieldName, out label)` (`:36`) — returns false for any name ending in **`SecretName`** (e.g. `sqlSourceConnectionSecretName` holds the *name* of a stored secret, not a value; flagging those would drown the report in false positives). Otherwise a friendly-label lookup (`apiKey` → "API Key", `password` → "Password", `sharePassword` → "Share Password", `credentialPassword` → "Run As Password") and, failing that, the canonical `SecretOutputMasker.LooksLikeSecretKey(fieldName)` heuristic with the raw field name as its own label.
  - `IsPlaintextLeak(value)` (`:59`) — non-blank AND `!TokenShapes.ContainsToken(value)`.
- **You normally do NOT register a new secret field.** Detection keys on the field *name* heuristically, so a new secret-ish field is covered automatically; `FriendlyLabels` only prettifies the report. Widening fails toward *more* warnings — the safe direction for a warn-only scan.
- **Password fields in the editor are components, not raw inputs.** `StepEditorCard.razor` contains **zero** `type="password"` bindings — every credential/secret field renders through **`SecretValueEditor`** (literal / `{{$config:...}}` secret-pick / `$ref` modes; a picked secret shows only `SecretCatalog.GetMaskedValue(...)`), and the Install/MapShare share credentials render through **`ShareCredentialEditor`**, itself a None/AzureFile/WindowsShare `SegmentedToggle` wrapping two `SecretValueEditor`s (share user + `sharePassword`, relabelled "Storage account key" in Azure mode). The old "mirror the editor's `type="password"` bindings" instruction is obsolete — there is nothing there to mirror. See [[crewchief-web-ui]]; for what `sharePassword` feeds at run time see [[crewchief-remote-box-prep]].
- **Scans**: the workload-level Run As trio, then every workload step entry's `Inline` JObject. (There are no referenced library steps to scan, and no `Overrides`.) Only **direct top-level** children are inspected (avoids false positives from nested blobs like a ConnEx `artifactJson` body).
- **A `{{...}}` token is NOT a leak** — `TokenRegex` (`\{\{.+?\}\}`) matches placeholders like `{{$config:RestClients:Connect:ApiKey}}`; a field steering a secret through configuration is fine. Only a non-empty, non-token literal produces a `PlaintextSecretFinding(Step, Field)`. Returns an empty list for a null or clean bundle.

## Result types (`.Ok`/`.Fail`, NOT a shared base)
`WorkloadBundleResult`, `WorkloadImportResult`, and `WorkloadBundlePreviewResult` are **three independent `sealed record`s**, each with its own static `Ok(...)` / `Fail(error)` factory — they do **not** derive from a common base or the general [[result-pattern]] type. Shapes:
- `WorkloadBundleResult(Success, Bundle?, Error)`
- `WorkloadBundlePreviewResult(Success, Preview?, Error)` where `WorkloadBundlePreview(WorkloadName, TargetName, NameCollision, StepCount)` — the `StepsToCreate` / `StepsThatExist` members went away with library references
- `WorkloadImportResult(Success, ImportedName?, Error)` — likewise no `CreatedSteps` / `KeptExistingSteps`

## Step-library transfer — `StepBundle` + `IStepTransferService`/`StepTransferService`
Sibling of the workload bundle for moving **selected library steps** (no workload) between instances. `StepBundle` (`CrewChief.Data\Models\StepBundle.cs`) serializes to `<name>.step-bundle.json`: `SchemaVersion` (`CurrentSchemaVersion` = `"1.0"`), `ExportedUtc`, and `Steps` — the exported `StepFile`s carried verbatim. `StepTransferService` uses the same `BundleSettings` recipe (`UtilityStepConverter` + `Formatting.Indented`) so the polymorphic `StepFile.Step` round-trips, and clones via serialize→deserialize. The export/import UI lives on the **Steps page** (`Steps.razor`/`.razor.cs`).

Same five-method shape as the workload service, with step-specific behavior:
- `BuildBundle(stepNames)` — distinct names in first-seen order (case-insensitive); **all-or-nothing**: any name missing from `IStepFileStore` fails the whole export and lists every missing step.
- `SerializeBundle` / `ParseBundle` — as the workload versions; `ParseBundle` returns `null` for null/blank/malformed JSON or a bundle with no steps.
- `PreviewBundle` — per bundled step a `StepImportEntry(SourceName, TargetName, NameCollision, TypeKey)`; target names are minted against the current library **plus names already claimed earlier in the same bundle**, so two same-named bundled steps don't collide with each other.
- `ImportBundle` — **always-new for every step**: each bundled step is saved (under a minted unique name on collision). Note the contrast with workload import, which *keeps* an existing same-named library step instead of importing a copy.

Details:
- **Own `BuildImportName`** (pure, static, `StepTransferService.cs:205`) — same `-imported` / `-imported-N` minting, but blank falls back to `"step"`. The workload service has its **own identically-named static**; they are separate methods, not shared.
- **Step-scoped `FindPlaintextSecrets`** (pure, static, `StepTransferService.cs:167`) — sibling of the workload-side scanner above. The detection logic is **no longer duplicated**: both call the shared `TransferSecretScan.IsSecretishField` / `IsPlaintextLeak` (`:181`, `:185`). What still differs is only the *surface* scanned — this one inspects each bundled step's serialized `Step` top-level fields (library steps have no `Inline`/`Overrides`), while the workload scanner also walks entry `Inline` JObjects and the workload-level Run As trio.
- **Result types** — `StepBundleResult(Success, Bundle?, Error)`, `StepBundlePreviewResult(Success, Preview?, Error)` with `StepBundlePreview(StepCount, Entries)`, `StepImportResult(Success, ImportedNames, Error)`: independent `sealed record`s with static `Ok`/`Fail`, declared alongside the interface in `IStepTransferService.cs` (not one-file-per-type).

Reference-data key-value sets have their own analogous bundle (`ReferenceBundle` / `ReferenceTransferService`) — documented in [[crewchief-reference-data]], not here.

## Promote inline steps to the library — `ExportStepsToLibraryDialog` + `IStepLibraryExporter`
Not a bundle at all — a same-machine flow that turns a workload's **inline** steps into reusable library `StepFile`s. `ExportStepsToLibraryDialog.razor` (`CrewChief.Web\Components\Controls\`, ~222 lines, reused by the Workloads list **and** `WorkloadEditor`) drives `IStepLibraryExporter`/`StepLibraryExporter` (`CrewChief.Data\Services\StepLibraryExporter.cs`):
- `BuildInlineCandidates(workload)` (`StepLibraryExporter.cs:79`) — one `StepLibraryExportCandidate` per entry. Every entry is inline now, so there is nothing to skip and no `CountLibraryReferences` (that method was deleted — 0 hits repo-wide). Each candidate carries a `DeepClone` of the inline body — the **source workload is never mutated**.
- **Name suggestions** — seed = first non-blank of workload-entry `Label` → inline `description` → type key, then `Slugify` (non-`[a-z0-9]` runs → `-`, falls back to `"exported-step"`) and `MakeUnique` (appends `-2`, `-3`, …). De-duped across the existing library **and** the rest of the batch (each suggestion claims its name before the next is minted).
- `ExportInline(inline, name, description, tags)` — **new-only**: throws `ArgumentException` for a non-kebab name and `InvalidOperationException` when the name already exists — it never overwrites a library step. Deserializes the inline body through `UtilityStepConverter` and saves a fresh `StepFile`.
- Dialog behavior: rebuilds candidates on every closed→open transition (fresh library snapshot); per-row live validation (required, kebab-case, library duplicate, duplicate-within-selected-batch); rows exported one at a time with per-row error notifications, then `OnExported(count)`.

## DI registration
`CrewChief.Web\Program.cs:300-303` registers all four as singletons, in this order: `IWorkloadTransferService` (`:300`), `IStepTransferService` (`:301`), `IReferenceTransferService` (`:302`, see [[crewchief-reference-data]]), `IStepLibraryExporter` (`:303`).

## Contrast with TestAuto ([[testauto-workflow-transfer]])
- TestAuto **fully resolves** each step's config on export and **re-mints DB codes** on import (DB-backed).
- CrewChief carries each entry's `Inline` body **verbatim**, creates no library files on import, mints a filename-safe unique name, and adds the **plaintext-secret scanner** (no DB, no code re-minting).

## Sources
- `CrewChief\CrewChief.Data\Models\WorkloadBundle.cs`
- `CrewChief\CrewChief.Data\Services\WorkloadTransferService.cs`
- `CrewChief\CrewChief.Data\Services\IWorkloadTransferService.cs`
- `CrewChief\CrewChief.Data\Models\StepBundle.cs`
- `CrewChief\CrewChief.Data\Services\StepTransferService.cs` (`FindPlaintextSecrets` :167, `BuildImportName` :205)
- `CrewChief\CrewChief.Data\Services\TransferSecretScan.cs` (the shared secret-field heuristic) + `CrewChief.Tests.Unit\Data\TransferSecretScanTests.cs`
- `CrewChief\CrewChief.Data\Services\IStepTransferService.cs` (interface + step result records)
- `CrewChief\CrewChief.Data\Services\StepLibraryExporter.cs` (interface :42, `BuildInlineCandidates` :81, `ExportInline` :146)
- `CrewChief\CrewChief.Web\Components\Controls\ExportStepsToLibraryDialog.razor`
- `CrewChief\CrewChief.Web\Components\Pages\Steps.razor` / `.razor.cs` (step-bundle export/import UI)
- `CrewChief\CrewChief.Web\Program.cs` (transfer/exporter DI, :300-303)
- `CrewChief\CrewChief.Web\Components\Controls\SecretValueEditor.razor`, `ShareCredentialEditor.razor` (how secret/password fields are actually authored — no `type="password"` anywhere in `StepEditorCard.razor`)

## Related
- [[crewchief-workload-and-runs]] — the workload/step model being transferred
- [[crewchief-file-persistence]] — the file stores export reads / import writes
- [[testauto-workflow-transfer]] — TestAuto's DB-backed equivalent
- [[crewchief-reference-data]] — the analogous `ReferenceBundle`/`ReferenceTransferService` for key-value reference-data sets
- [[result-pattern]] — the general result convention (these types resemble but don't share it)
- Memory: [[project_crewchief_standalone]]
