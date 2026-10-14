---
name: connex-import-tokenization
description: >
  ConnEx import tokenization in TestAuto.Web — discovering tokenizable fields in an exported ConnEx
  artifact, presenting them for selection, and producing a template with {{token}} placeholders. Use
  when working on the ConnEx import flow, the token scanner/tokenizer, the token-selection dialog,
  secret/reference pickers, the Template value source, Add-field tokenization of arbitrary artifact
  paths, or the single-vs-separate scenario import mode. Replaces the retired
  IServiceConfigTransformer classes.
---

> [!important] Scope: TestAuto only — CrewChief has an INDEPENDENT port
> Everything here describes `TestAuto.Web/Services/ConnExTokenization/`. CrewChief carries its own copy under
> `CrewChief.Engine/ConnEx/Tokenization/` (12 files) because it takes **zero** TestAuto assembly references,
> plus two CrewChief-only additions (`ConnExStepSetBuilder`, `ConversionProfile`). **A fix in one does not
> land in the other.** See [[crewchief-connect-import]].

# ConnEx Import Tokenization

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: `TestAuto.Web/Services/ConnExTokenization/` + `Components/Dialogs/ConnExTokenSelectionDialog`
> **History**: The per-provider `IServiceConfigTransformer` classes (`SqlServerConfigTransformer`,
> `SnowflakeConfigTransformer`, etc.) and `ServiceConfigTransformerResolver` were **retired (deleted)**
> on 2026-05-29. Their hardcoded field lists were replaced by the structural scanner/tokenizer below.
> Do not look for those classes — they no longer exist.

When TestAuto imports a ConnEx resource (ServiceConfiguration, IntegrationStrategy, ServiceProvider),
the raw export is transformed into an importable template by replacing values with `{{token}}`
placeholders. **What gets tokenized is now discovered structurally and chosen by the user** in a modal,
rather than hardcoded per provider.

---

## Pipeline

```
ImportResourceAsync (ConnExResourcePageBase)
  → export from ConnEx
  → ArtifactTokenScanner.Scan(exportJson, resourceType)   → IReadOnlyList<TokenCandidate>
    (page prepends the Description pseudo-row: IsDescription=true, ValueSource.Template)
  → ConnExTokenSelectionDialog (user checks/edits; Add field; Cancel aborts)
        → ConnExTokenSelectionResult { Candidates, SingleScenario }
  → ArtifactTokenizer.Apply(exportJson, non-description selections) → (tokenizedJson, parameters)
  → ConnExScenarioFactory.CreateImportScenarioAsync(..., parameters, descriptionTemplate, singleScenario)
    // artifact inline by default; saved to a file via ArtifactStorage only if too big
```

**`CreateImportScenarioAsync` creates one scenario *per ConnEx step* by default** (Import, plus
Enable/Execute for strategies), each a single-step `MultiStepUtilityScenario` differentiated by a
`Step N` suffix in its name — or, when the user chose *single combined scenario*, **one**
`MultiStepUtilityScenario` holding all steps (see *Import mode* below). It returns
`Task<ServiceResult<IReadOnlyList<string>>>` — the new scenario codes **in order**
(one entry in combined mode). Every entry in `parameters` is promoted to *each* scenario's
`GlobalParameters`, so one edit updates all steps that reference the token.

## Components (`TestAuto.Web/Services/ConnExTokenization/`)

| Type | Responsibility |
|---|---|
| `ArtifactTokenScanner` | Walks the export JSON, emits `TokenCandidate`s by **structural rules** (no provider-specific code). Also: `EnumerateLeaves(exportJson)` → every dot-navigable scalar leaf (`ArtifactLeaf(Path, Value)`; array/`[index]` paths skipped — the case-insensitive resolver can't navigate them), and `BuildCandidateForPath(exportJson, jsonPath)` → an Add-field candidate. |
| `TokenCandidate` | One discoverable field: `JsonPath`, `Kind`, `FieldLabel`, `CurrentValue`, `IsGuid`, `IsLocked`, `ReferenceTarget`, `DefaultTokenName`, `NamePath`, + editable `Selected`/`TokenName`/`ValueSource`/`EditableValue`/`SecretSection`/`SecretItem`, flags `IsCustomField` (added via Add-field) / `IsDescription` (the description pseudo-row), and computed `SecretConfigReference`. |
| `ArtifactTokenizer` | Applies confirmed selections → `(tokenizedJson, parameters)`; skips `IsDescription` rows (no artifact path — the factory applies the description). Holds the credential vault→LocalVault reshape (migrated from the old transformers). |
| `SecretCatalog` | Enumerates secret `Section → Item` from `IConfiguration`, masked. |
| `CandidateKind.cs` | The classifying enums: `CandidateKind` (OwnIdentity/Reference/Literal/Credential), `ValueSource` (Literal/Secret/Reference/**Template**), `ReferenceType` (ServiceConfig/ServiceProvider/Entity). |
| `ConnExTokenSelectionDialog` | Radzen modal (`RadzenDataGrid`): Description editor at the top, per-row checkbox, token name, **value-source** cell (Literal/Secret/Template select bar on non-Reference rows; secret `Section → Entry` dropdowns; template textbox + *Insert ref* picker), GUID regenerate button, **Add field** dropdown, **Single combined scenario** switch, Import/Cancel. Injects `ISecretCatalog` + `IArtifactTokenScanner`; takes `ArtifactJson` (powers Add-field) and `PageKey` params. Returns `ConnExTokenSelectionResult { Candidates, SingleScenario }` (null on cancel). |
| `ParameterResolver` (`TestAuto.Utilities/Services/`) | Shared `IParameterResolver` used by both `UtilityOrchestrator` (run time) and `ConnExScenarioFactory` (import time) — see *Shared parameter resolution* below. |

## Scanner's structural rules (the key idea — no per-provider code)

- record-level `Id`/`Name` → `CandidateKind.OwnIdentity`
- nested `{ id, name }` Identifier (`entityId`, `serviceConfigurationId`, `serviceProviderId`) → `CandidateKind.Reference`
- setting with `assignmentType: "Literal"` → `CandidateKind.Literal`
- setting with `assignmentType: "Credential"` → `CandidateKind.Credential` (always tokenized; its value is sourced from a secret **by default**, but can be toggled to a literal — see *Credential value source* below)

Smart default token names (backward-compatible with existing templates): `StrategyId/Name`,
`ServiceConfigId/Name`, `EntityId/Name`, `ServiceProviderId/Name`; SqlServer settings →
`DbServer`, `DatabaseName`, `DbUsername`, `DbPassword`.

### Strategy-only auto-candidates: `TargetDatabaseTableName` + `RunAsUser` (2026-06-11)

For an **IntegrationStrategy** import the scanner also emits two **auto-selected** candidates, each
**defaulted to the value already in the artifact** (presence-based — service-config/provider artifacts
have neither field, so nothing is added):

- **`TargetDatabaseTableName`** — `Kind = Literal` with `TokenCandidate.ScopedTableReplace = true`, value =
  the artifact's `Configuration.remoteObjectName`. The source table appears in three kinds of places, so a
  plain whole-node swap isn't enough. `ArtifactTokenizer.ReplaceTableNameScoped` rewrites **all** source-side
  occurrences: `remoteObjectName` (whole value), each mapping's `value.dataSource` (whole value), and the
  `[table]` portion of every `value.parameters.*.value.expressionText`. It is **scoped** to those fields so it
  never touches the target entity name, the `mappings` key, or the `[Entity].[Attr]` parameter keys — which
  matters when the table name equals the entity name (e.g. a literal `RetailClient` table).
- **`RunAsUser`** — `Kind = Literal` at `Configuration.runAsUser`, value = the artifact's `runAsUser`.

**Escaping (important) — two escape points in time.** Token replacement at run time is a *textual* substitution
into the raw artifact JSON string (`ConnExExecutor` → `ITextTemplater.ReplaceTokens`), so any injected value
that contains a backslash or quote — e.g. `runAsUser` = `CORP\agenewe` — must be stored as `CORP\\agenewe` or
the substituted artifact becomes invalid JSON (`JToken.Parse` throws `Bad JSON escape sequence: \Q`). A value
gets escaped at **exactly one** of two moments depending on where it comes from:

1. **Import time — literal values.** The tokenizer JSON-escapes every extracted **literal** parameter value
   (`ArtifactTokenizer.Escape` — doubles `\`, escapes `"`). No-op for GUIDs/plain names, so it is applied to all
   extracted Literal/Reference/Credential-literal values.
2. **Run time — config/secret/template-resolved values.** A parameter whose value is a `{{$config:...}}` /
   `{{$env:...}}` token (Secret/Template source) is **not** a literal at import — `ArtifactTokenizer.Escape`
   never sees the real value, only the token. The real value (`CORP\QAAutomation`) only exists after
   `ParameterResolver.ResolveSpecialParameterValues` resolves it at run time, so it is escaped **there** instead:
   `UtilityOrchestrator` calls `ResolveSpecialParameterValues(mergedParams, escapeForJson: step is ConnExStep)`,
   and the resolver runs `EscapeForJsonStringLiteral` (kept **identical** to `ArtifactTokenizer.Escape`) on the
   resolved value. Only ConnEx sets `escapeForJson: true` (its params are substituted into a raw JSON artifact);
   SQL/PowerShell/Curl/CLU consume the raw value and must **not** be escaped. Literal params are skipped by the
   resolver (they contain no `{{$config}}`/`{{$env}}` token), so a value already escaped at import time is
   **never double-escaped**. Without this, a Secret-sourced `runAsUser` produced `\Q` and failed JSON parsing —
   see memory `project_connex_runasuser_json_escape`.

## Value sources per candidate

- **Literal / OwnIdentity**: the extracted value (editable), a secret reference, or a **template** (see below).
- **Reference** (`entityId`/`serviceConfigurationId`/`serviceProviderId`): the existing id + its sibling name are carried through from the export (`TokenCandidate.ReferenceName`); the tokenizer emits both an id token and a `<name>` token so references stay valid across imports. There is **no** API-backed picker catalog — the value is editable in the dialog like a literal.
- **Credential**: tokenized either way, but the **value source is user-selectable** (`TokenCandidate.ValueSource`):
  - `Secret` (default): a secret picked via `SecretCatalog` → value stored as a **`{{$config:Section:Item}}`** reference (resolved at execution by `TextTemplater`; never the plaintext secret).
  - `Literal`: an editable plaintext value entered in the dialog (no secret lookup).
- **Template** (`ValueSource.Template`, any non-Reference row): a free-form string mixing literal text with
  `{{$config:Section:Item}}`/`{{$env:KEY}}` references — see *Template value source* below.
- **GUID** rows expose a regenerate button (own-identity = new item / no collision; reference rows carry a caution).

All selected parameters are promoted to the scenario's **`GlobalParameters`** so one edit updates every step that references the token.

### Credential value source — secret ↔ literal toggle

A Credential row is no longer hard-locked to a secret. The dialog exposes a value-source toggle, and the
pipeline honors it consistently:

- **`ArtifactTokenizer`** reads `TokenCandidate.ValueSource`: emits the `{{$config:Section:Item}}` secret
  reference for `Secret`, or the editable literal value for `Literal`.
- **`ConnExTokenSelectionDialog.OnValueSourceChanged`** clears the now-irrelevant fields on toggle so a
  stale value can't leak through: switching **to Secret** clears `EditableValue`; switching **to Literal**
  clears `SecretSection`/`SecretItem`; switching **to Template** keeps `EditableValue` (the template text) —
  its Section/Item are transient state for the insert-reference picker.
- **Validation** keys on `ValueSource == ValueSource.Secret` (a secret-sourced row must have Section + Item
  chosen), not on `CandidateKind.Credential`. So a Credential toggled to Literal is validated like any
  literal row.

## Template value source & "Add field" (2026-06-08)

### `ValueSource.Template` — combined config-reference + literal values

A Template value is **just a parameter whose value is a template string** — e.g.
`{{$config:ServerNames:DatabaseServerName}}_ModelSource`. No new resolution engine: the artifact node
becomes `{{TokenName}}` as usual, and `ArtifactTokenizer` stores the template **verbatim** as the
parameter value (`parameters[TokenName] = EditableValue` — same code path as Literal). The normal
parameter-resolution pass resolves the `$config:`/`$env:` references at execution.

- Offered on **any non-Reference row** (OwnIdentity, Literal, Credential, custom/added) via the
  Literal | Secret | Template `RadzenSelectBar` in the value-source cell. Reference rows keep their plain
  editable id textbox (no select bar).
- UI: a free-form textbox bound to `EditableValue`, plus an **Insert ref** picker (Section/Entry dropdowns
  fed by `SecretCatalog` + button) that **appends** the `{{$config:Section:Item}}` reference to the text
  and resets the picker. (`{{$env:...}}` references can be typed by hand.)
- `Validate()`: a selected Template row must have a non-empty `EditableValue`.

### "Add field" — tokenize any artifact path

Below the grid, an *Add field* dropdown lists every artifact leaf not already covered by a row
(`ArtifactTokenScanner.EnumerateLeaves` — dot-navigable scalar leaves only; array/`[index]` paths are
skipped because the tokenizer's case-insensitive path resolver doesn't navigate them). Picking a path and
clicking **Add field** calls `ArtifactTokenScanner.BuildCandidateForPath(exportJson, jsonPath)`:

- Returns a `CandidateKind.Literal` candidate with `IsCustomField = true`, defaulting to
  `ValueSource.Literal` (the user can switch it to Secret/Template).
- Token name suggestion: the path's leaf segment, except a leaf literally named `value`/`id`/`name` uses
  its **parent** key instead; then through `SuggestSettingToken` for the friendly SQL names.
- Returns `null` for blank paths, unparseable JSON, or object/array nodes.
- The dialog's working row list (`_rows`) grows in place; `AvailableLeafPaths` refreshes so a used path
  disappears from the dropdown.

## Hybrid description resolution (2026-06-08)

The import description is editable in the dialog and resolved **twice, differently**:

| Where stored | Resolution | Why |
|---|---|---|
| Scenario `DisplayName`/`DisplayDescription` | **Import time** — `IParameterResolver.ResolveBestEffort` in the factory | Clean text in the scenario list (e.g. `Import SMVMDB3_ModelSource`) |
| `ConnExStep.Description` | **Run time** — `ConnExExecutor.ResolveDescriptionForLog` | Log lines / `result.StepKey` resolve against the live environment |

Mechanics:

- `ConnExResourcePageBase` **prepends a Description pseudo-row** to the candidates before opening the
  dialog: `IsDescription = true`, `ValueSource.Template`, `JsonPath` empty, default text `Import {Name}`.
  The dialog edits it at the top (own template editor + Insert ref), excluded from the field grid and from
  token-name validation (non-empty text only).
- `ArtifactTokenizer.Apply` **skips** `IsDescription` rows — the page extracts the row's `EditableValue`
  as `descriptionTemplate` and passes it to the factory.
- `ConnExScenarioFactory`: base label = the user's template (or default `ConnEx Import: {resourceName}`);
  each step's `Description` is set to `"<baseLabel> - Step N: Operation"` when multi-step (no suffix for a
  single step) and stored **templated**. `DisplayName`/`DisplayDescription` are resolved at import via
  `ResolveBestEffort` against a copy of the GlobalParameters that first went through
  `ResolveSpecialParameterValues` (so `{{token}}` → param value → `{{$config:...}}` chains resolve).
- `ConnExExecutor.ResolveDescriptionForLog(step)` resolves `step.Description` with the templater against
  `step.Parameters` at run time for the log label and `result.StepKey`; if any token is unresolvable (or
  resolution throws) it keeps the raw templated text — it's only a label, never a failure.

## Import mode — separate vs single combined scenario (2026-06-08)

At import time the user chooses how multi-step strategy imports materialize (a single-step config import
is one scenario either way):

- **Dialog**: a *Single combined scenario* `RadzenSwitch` (default **off** = separate, today's behavior);
  the choice returns as `ConnExTokenSelectionResult.SingleScenario`.
- **Page**: passes it to the factory as `combineIntoSingleScenario`; the success notification reflects the
  shape ("single combined scenario" vs "N scenarios (one per step)").
- **Factory** (`combineIntoSingleScenario` param, default `false`):
  - *Separate* (default): the existing per-step loop — one single-step `MultiStepUtilityScenario` per step,
    Tags `ConnEx,Import,{resourceType},Step{N}`, DisplayName = the step's resolved description.
  - *Single*: **one** `MultiStepUtilityScenario` holding every step; DisplayName = the resolved base label
    (no `Step N` suffix); Tags `ConnEx,Import,{resourceType},Combined`; each inner step keeps its
    `Step N: Operation` description so the run log distinguishes them.
  - Both branches share `BuildConfig(steps, globalParameters)`, `BuildAndSizeAsync` (inline artifact with
    file fallback + 4,000-char limit check), and `NewScenarioRecord` helpers.

## Shared parameter resolution — `IParameterResolver` (TestAuto.Utilities)

`ParameterResolver` (`TestAuto.Utilities/Services/ParameterResolver.cs`, interface in
`Interfaces/IParameterResolver.cs`, registered in `UtilitiesModuleRegistrar`) is the single implementation
shared by run-time orchestration and import-time naming. It wraps `ITextTemplater`:

- `ResolveSpecialParameterValues(parameters, bool escapeForJson = false)` — for each parameter value containing
  `{{$config:...}}` or `{{$env:...}}` (case-insensitive), replaces the value **only if every token resolves**;
  otherwise logs a warning and leaves the value intact so the step executor's own validation surfaces the missing
  source. Plain `{{param}}` tokens are untouched. This is the two-hop chain ConnEx imports promote: artifact holds
  `{{DbPassword}}`, the parameter `DbPassword` holds `{{$config:...}}`. When `escapeForJson: true` (ConnEx steps
  only) each resolved value is JSON-string-literal escaped — see "Escaping (important)" above.
- `ResolveBestEffort(input, parameters)` — token-by-token, case-insensitive parameter lookup; resolves what
  it can, leaves unresolvable tokens literal. Used for display strings (scenario DisplayName).
- `UtilityOrchestrator` constructs its own `new ParameterResolver(...)` internally (keeps its public ctor
  unchanged); `ConnExScenarioFactory` takes `IParameterResolver` from DI.

## Credential reshape (now in `ArtifactTokenizer`)

**Before (export):** `"PasswordVault": { "assignmentType": "Credential", "value": { "name": "...", "vaultId": "..." } }`
**After (template):**
```json
"PasswordVault": {
  "assignmentType": "Credential",
  "name": "PasswordVault",
  "value": { "name": "PasswordVault Credential", "providerType": "LocalVault", "configuration": { "value": "{{DbPassword}}" } }
}
```
`vaultId` is dropped; `providerType` becomes `LocalVault`; value becomes the token.

## Adding a new provider

Usually **nothing to do** — discovery is structural (`assignmentType` + Identifier shape), so new
providers' literals/credentials/references are found automatically, and **Add field** covers anything
the scanner misses. Only touch `ArtifactTokenScanner.SuggestSettingToken` if you want a friendlier
default token name for a new setting key.

## Sources

- `TestAuto.Web/Services/ConnExTokenization/ArtifactTokenScanner.cs` (Scan, EnumerateLeaves, BuildCandidateForPath)
- `TestAuto.Web/Services/ConnExTokenization/IArtifactTokenScanner.cs` (ArtifactLeaf record)
- `TestAuto.Web/Services/ConnExTokenization/ArtifactTokenizer.cs`
- `TestAuto.Web/Services/ConnExTokenization/SecretCatalog.cs`
- `TestAuto.Web/Services/ConnExTokenization/CandidateKind.cs`
- `TestAuto.Web/Services/ConnExTokenization/TokenCandidate.cs`
- `TestAuto.Web/Components/Dialogs/ConnExTokenSelectionDialog.razor(.cs)` (incl. ConnExTokenSelectionResult)
- `TestAuto.Web/Components/Pages/ConnExResourcePageBase.cs` (ImportResourceAsync, Description pseudo-row)
- `TestAuto.Web/Interfaces/IConnExScenarioFactory.cs`, `Services/ConnExScenarioFactory.cs` (CreateImportScenarioAsync → `ServiceResult<IReadOnlyList<string>>`, descriptionTemplate + combineIntoSingleScenario params, GlobalParameters promotion)
- `TestAuto.Utilities/Services/ParameterResolver.cs`, `TestAuto.Utilities/Interfaces/IParameterResolver.cs` (`escapeForJson` gate + `EscapeForJsonStringLiteral`)
- `TestAuto.Utilities/Services/UtilityOrchestrator.cs` (consumes the shared resolver; passes `escapeForJson: step is ConnExStep`)
- `Testing.SpeedMerchants.Unit/Tests/Utilities/Services/ParameterResolverTests.cs` (runtime JSON-escape regression: `CORP\QAAutomation` → `CORP\\QAAutomation`, no-escape default, no double-escape of literals)
- `TestAuto.Utilities/Executors/ConnExExecutor.cs` (ResolveDescriptionForLog)
- Design spec: `{VaultDocsRoot}\speed-merchants\planning\Archive\Design_ConnExImportTokenSelection_2026-05-29.md`
- Design spec: `docs/superpowers/specs/2026-06-08-connex-import-token-enhancements-design.md` (token enhancements: Template, Add-field, description, single/separate) — *source removed 2026-06-21 (deleted from repo); content captured in this skill, which is now canonical for these enhancements*
