---
name: crewchief-adding-a-step-type
description: >
  The keep-all-tables-in-sync checklist for adding a step type to CrewChief, plus the dual-dispatch drift hazard that silently mis-creates or fails a step and the coverage assertions that make the change INDIVISIBLE. Use when adding, renaming, or debugging a CrewChief step type, when scoping or planning a step-type addition, when a step saves as CommandLine unexpectedly, when a step deserializes but throws "No executor found for step type", when the unit suite goes red after a partial step-type change, or when reconciling the DeveloperPack ADR against the real code.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief: Adding a Step Type (footgun checklist)

Adding a step type to CrewChief is NOT one edit. Two separate counts matter, and conflating them is how scope estimates go wrong:

- **Four hand-maintained DISPATCH sites** — where the code routes a step (table below). This is what the 2026-07-26 duplication audit reduced from six to four.
- **A larger INDIVISIBLE set that must land together** — the files the test suite's coverage assertions force, measured at six plus three global census oracles (the third fires only for a *credentialed* step type). See [[#Adding a step type is INDIVISIBLE — read this before planning the work]]. Size the work from THIS, never from "four".

As of the 2026-07-26 duplication audit the dispatch count is **four hand-maintained sites**, not six. The orchestrator's alias table and BOTH editor `CreateStepForType` factories are now **derived from `StepTypeRegistry`**, so the two worst drift classes are closed by construction and guarded by `StepTypeParityTests`. What stays hand-maintained is the registry entry, the executor + its DI registration, the UI type table, and the editor card branch. This skill maps the live sites so a new step type is added consistently — or a mis-dispatch is diagnosed. See [[crewchief-step-type-model]] for the type/registry model and memory [[project_crewchief_steptype_factory_duplicated]] for the historical bug the derivation closed.

## When to Use
- "Add step type X to CrewChief" / "why is only the Engine half wired?"
- "My new step saved as a Command Line step"
- "A step throws 'No executor found for step type: <x>'" (now almost always a missing DI executor registration, not a missing alias)
- "Review this step-type PR for missed registration sites"
- "The DeveloperGuide/ADR line numbers don't match the code"

## The two independent dispatch tables

1. **Deserialization** — `StepTypeRegistry` (`CrewChief.Engine/Steps/StepTypeRegistry.cs`). Maps `type` string → CLR type. One `Register<T>(...)` line. Consulted by `UtilityStepConverter` and `UtilityStepBase.CreateFromJToken`.
2. **Executor dispatch** — `UtilityOrchestrator._executorsByType` (`CrewChief.Engine/Orchestration/UtilityOrchestrator.cs:27`, an `OrdinalIgnoreCase` dictionary built at `:54`). Each executor **self-registers under its own `executor.StepType`** in the ctor loop (`:55-59`); aliases are then **DERIVED from `StepTypeRegistry.Registrations`** (`:61-91`) — for each registration the loop finds the executor matching ANY of its accepted type strings, then maps *every* remaining string of that registration to it. Dispatch reads the dict at `:230` (miss → `$"No executor found for step type: {step.Type}"` at `:232`); `ValidateScenario` reads it via `ContainsKey` at `:479` (error text at `:482`).

> **`AddExecutorAlias` no longer exists in CrewChief** — zero hits anywhere under `CrewChief\`. It was a 23-line hand-maintained list, replaced by the registry-derived loop above (BL-B4). Do not cite it for CrewChief. (The identifier *does* still live in the unrelated `TestAuto.Utilities\Services\UtilityOrchestrator.cs` — see [[testauto-utilities-module]]; do not carry that behavior across.)

Table 2 is now derived from table 1, so a registry entry whose executor is registered in DI cannot be missing an alias. The residual gap is narrower but real: if **no** executor is registered for a registration, the loop `continue`s (`:79-80`) — legitimate when a host wires a subset, fatal when you simply forgot the `AddTransient<IStepExecutor, X>`.

## The four hand-maintained sites

| # | Site | File | What it does | Miss it → |
|---|---|---|---|---|
| 1 | `StepTypeRegistry.Register<T>(...)` | `Engine/Steps/StepTypeRegistry.cs:54-72` | canonical + aliases → CLR type; also the source the orchestrator aliases and both editor factories derive from | `Unknown step type` on load, AND no executor alias, AND the editor factory falls back to `CommandLineStep` |
| 2 | Executor class + `AddTransient<IStepExecutor, X>` | `Engine/EngineServiceCollectionExtensions.cs:32-90` | supplies the `StepType` key the orchestrator self-registers | `No executor found for step type: <x>` at dispatch (the alias loop `continue`s past a registration with no executor) |
| 3 | `UtilityStepTypeInfo.AllTypes` (+ the icon/name/desc/color switches) | `Web/Helpers/UtilityStepTypeInfo.cs:166-169` | the picker's offered type keys + visual metadata | type not offered in the picker / default `play_circle` icon — and `StepTypeParityTests` fails |
| 4 | `StepEditorCard` `Step is XxxStep` editor branch | `Web/Components/Controls/StepEditorCard.razor(.cs)` | renders the per-type editor fields | no editable fields for the new type |

> **"Four sites" counts DISPATCH, not COVERAGE.** The table above is where the code *routes* a step. It
> is not the set of files you must change to keep the suite green — that set is larger and is enumerated
> in the next section. Do not use the number 4 to size the work.

**Derived — do NOT hand-edit:**
- Orchestrator aliases (`UtilityOrchestrator.cs:61-91`) come from `StepTypeRegistry.Registrations`.
- Both editor factories: `Steps.CreateStepForType` (`Steps.razor.cs:635-644`) and `WorkloadEditor.CreateStepForType` (`WorkloadEditor.razor.cs:550-558`) are one line each — `StepTypeRegistry.CreateStep(type) ?? new CommandLineStep()` (`Steps.razor.cs:640`, `WorkloadEditor.razor.cs:554`) — plus a shared `ConfigureStep` switch-defaults tail. The historical hand-synced, case-SENSITIVE 19-arm switches are gone.

## Adding a step type is INDIVISIBLE — read this before planning the work

This is the fact that changes how you plan, and the one the "four sites" figure hides. Adding one
`StepTypeRegistry` registration turns the unit suite **red** until a set of files lands **together**.
Measured 2026-08-03 against `speed-merchants` (baseline 2,656 unit tests green, ~41s) while adding the
Teams step; every assertion below re-verified against the live code 2026-08-04.

There is no way to stage this as a sequence of small green commits. Coverage assertions destroy
divisibility: they enumerate the registry exhaustively, so they fail the moment the registry grows and
keep failing until every enumeration is updated.

### The atomic set — these five change together or the suite is red

| # | File | Why it is forced |
|---|---|---|
| 1 | `CrewChief.Engine/Steps/<X>Step.cs` (new) | the type itself; its `[JsonProperty]` names are load-bearing for #4 |
| 2 | `CrewChief.Engine/Steps/StepTypeRegistry.cs` | the registration every oracle counts |
| 3 | `CrewChief.Web/Helpers/UtilityStepTypeInfo.cs` | `AllTypes` entry **plus** FIVE switch arms — icon, display name, description, accent colour, tint (for the Teams step: `:34, 63, 90, 145, 172`) |
| 4 | `CrewChief.Web/SampleContent/workloads/all-step-types.workload.json` | the shipped sample must cover EVERY registered type |
| 5 | `CrewChief.Tests.Unit/Web/UtilityStepTypeInfoTests.cs` | hardcoded expected-key array |

### The assertions that force them

| Assertion | Forces |
|---|---|
| `StepTypeParityTests.RegistryAndUiTable_HaveTheSameCount` | 2 + 3 together |
| `StepTypeParityTests.EveryRegistration_HasAUiTypeKey` | same |
| `StepTypeParityTests.EveryUiTypeKey_ResolvesInTheRegistry` | 3 needs 2 |
| `ShippedSampleContentTests.AllStepTypesWorkload_CoversEveryRegisteredStepType` (`:202`) | 4 |
| `ShippedSampleContentTests.InlineSteps_HaveNoUnknownProperties` (`:171`) | 4's JSON property names must match 1's `[JsonProperty]` names EXACTLY — anything else lands in `ExtensionData` and fails (see [[reference_newtonsoft_extensiondata_vs_missingmember]]) |
| `UtilityStepTypeInfoTests.AllTypes_ContainsExpectedCanonicalKeys` (`:114`) | 5 |

### Two tests that look forcing and are NOT (verified 2026-08-04)

Do not put these files in scope — and do not trust these tests to catch a half-finished job:

- **`StepDescriptionSeeder.cs` needs no edit.** `Seed()` loops `UtilityStepTypeInfo.AllTypes` and calls
  `GetDescription(type)` (`:49-55`); the description arm lives in `UtilityStepTypeInfo` (site 3), which
  its own doc-comment calls "the single source of per-type descriptions". `StepDescriptionSeederTests
  .Seed_PopulatesEveryStepTypeWithItsBuiltInDescription` (`:29`) asserts `added ==
  UtilityStepTypeInfo.AllTypes.Length` and compares each stored value to
  `UtilityStepTypeInfo.GetDescription(type)` — **self-referential on both counts**, so it forces nothing.
- **`StepTypeParityTests.EveryUiTypeKey_HasVisualMetadata`** (`:67-78`) only asserts icon, display name
  and accent colour are non-empty. Every one of those switches has a non-empty `_ =>` default (a missing
  icon arm yields `play_circle`), so a forgotten metadata arm **passes this test** and ships as wrong
  visuals. Treat site 3's five arms as a manual checklist item, not a guarded one.

The sample step in #5 must also set `continueOnError: true`
(`AllStepTypesWorkload_KeepsEveryStepNonDestructive`, `:225`), and any `{{token}}` it uses needs a
global parameter carrying a value (`WorkloadPlainTokens_ResolveFromTheirGlobalParameters`,
`ShippedWorkloads_GlobalParametersAllHaveValues`).

### Three global census oracles — invisible to code tracing

These are not step-type-specific, which is exactly why tracing the code never finds them. They are
hand-transcribed counts of the whole world, and they go red on ANY registry or executor addition:

| Oracle | File | Shape |
|---|---|---|
| Accepted-type-string census | `CrewChief.Tests.Unit/Engine/StepTypeRegistryTests.cs:23` | `ExpectedMappings` — a hand-transcribed `(TypeString, ClrType)[]`, asserted to match `StepTypeRegistry.AllTypeStrings` **exactly** at `:115-121` (`Except` run in BOTH directions, so extras fail too, not just omissions) |
| Executor census | `CrewChief.Tests.Unit/Engine/EngineRegistrationTests.cs:44` | `Assert.AreEqual(22, executors.Count())` (22 as of the 2026-08-06 WebSiteStep addition) — a bare literal. Add an executor without bumping it and the test fails with a number, telling you nothing about which type is new |
| **Box-prep family census** | `CrewChief.Tests.Unit/Engine/WorkloadRunAsInheritanceTests.cs:353` | `Assert.AreEqual(7, boxPrepTypes.Count)` — reflects over `StepTypeRegistry.Registrations` and keeps every type **declaring a `CredentialSecretName` property** (`:350`). Fires **only if the new type is credentialed**, and additionally forces an arm in `WorkloadRunAsInheritance.InheritIfBoxPrep` — so a credentialed step type has a *larger* indivisible set than a plain one |

Add an executor + its `AddTransient` and you must touch the second one. Add any accepted type string
and you must touch the first. Give the new step a `CredentialSecretName` property — i.e. make it a
box-prep step — and you must touch the third **and** add an inheritance arm.

> [!note] There is no marker interface for "box-prep"
> Membership of that family is **defined by the presence of a property**, not by a base class or interface.
> That is why the third oracle is a reflection query rather than a list, and why it catches a new
> credentialed type automatically instead of waiting for someone to remember.

> **Verified drift, 2026-08-04:** `EngineRegistrationTests.cs:13-18`'s XML doc-comment still says
> "exactly the **nineteen** step executors" and lists 19 by name, while the assertion on `:44` read
> `21` and the body asserted `TeamsExecutor` too. **FIXED 2026-08-06**: the comment now says
> twenty-two and matches the assertion (22, WebSiteStep included). The assertion stays authoritative.
> Not fixed here (this skill does not edit the repo) — fix it in the repo when you are next in that file.

### Self-referential vs hardcoded — do not add the wrong ones to scope

Not every counting test is an oracle. `StepsPageTests` compares `all.Length` against a filtered count of
*itself* — self-referential, so it tracks any registry change automatically and does NOT belong in scope.
`EngineRegistrationTests` compares against the literal `22`. Only hardcoded oracles force a file.

The general shapes worth grepping before you plan the work:

```powershell
rg -n 'AreEqual\(\s*\d+\s*,.*\.(Count|Length)' CrewChief\CrewChief.Tests.Unit
rg -n 'CollectionAssert\.AreEqual|ToHashSet\(\)|\.Except\(' CrewChief\CrewChief.Tests.Unit
```

### What CAN be deferred

An executor class and its `AddTransient<IStepExecutor, X>` are **not** coverage-asserted by the parity
tests — the registry-derived alias loop simply `continue`s past a registration with no executor. So a
type can be registered, offered in the picker, and sampled before its executor exists; it will throw
`No executor found for step type` at run time but the suite stays green. That is the only genuine seam
in this work. Note that adding the executor later still trips the `22`-literal census above.

See memory [[project_crewchief_steptype_coverage_assertions]]. If you are planning this inside an
orchestrator-worker loop, this is the canonical case its "1-3 files per action" rule must yield to —
declare the six as a named indivisible set.

## The residual CommandLine fallback (still a live footgun)

Both factories still end in `?? new CommandLineStep()`. It can only bite now when a UI type key exists that the registry does not resolve — i.e. site 3 added without site 1. That is exactly what `StepTypeParityTests` (`CrewChief.Tests.Unit\Web\StepTypeParityTests.cs`) exists to catch: `EveryUiTypeKey_ResolvesInTheRegistry`, `EveryRegistration_HasAUiTypeKey`, `RegistryAndUiTable_HaveTheSameCount`, `CreateStep_IsCaseInsensitive_AndNullForUnknown`, `EveryUiTypeKey_HasVisualMetadata`. If you see a new type materialize as a Command Line step, run that test class first.

`AllTypes` keys are the *picker's* strings (`"SQL"`, `"HTTP"`, `"CURL"`, `"SetApiKey"`, `"IisReset"`, `"EmailStep"`, …), and `StepTypeRegistry.CreateStep` matches them **case-insensitively** against canonical names and aliases — so each `AllTypes` entry must be *some* accepted registry string, not necessarily the canonical one.

## Symptoms → cause table

| Symptom | Root cause |
|---|---|
| New step type saves/creates as a **Command Line** step | the UI type key (site 3) does not resolve in `StepTypeRegistry` (site 1), so `CreateStep` returned null and the `?? new CommandLineStep()` tail fired. `StepTypeParityTests` should already be red |
| Deserializes fine but throws **`No executor found for step type: <x>`** at run | site 2 gap: no `IStepExecutor` registered for that type, so the registry-derived alias loop skipped the whole registration (`UtilityOrchestrator.cs:79-80`) and dispatch missed at `:230-232` |
| **`Unknown step type: <x>`** on load | site 1 gap: string not registered in `StepTypeRegistry` (`UtilityStepConverter.cs:49` / `UtilityStepBase.cs:109`) |
| Type missing from the "Add Step" picker / default icon | site 3 gap: not in `AllTypes` / not in the `UtilityStepTypeInfo` switches |
| Editor shows no fields for the type | site 4 gap: no `Step is XxxStep` branch in `StepEditorCard` |

## Worked example (`email`) — the alias gap is FIXED, do not re-report it

`StepTypeRegistry` registers the short aliases **`"iisreset"`** and **`"email"`** (`StepTypeRegistry.cs:71-72`). Historically the hand-maintained alias list omitted the Email step's aliases entirely, so `{"type":"email"}` deserialized fine and then died at dispatch. **That is no longer true.** The alias loop (`UtilityOrchestrator.cs:61-91`) walks `StepTypeRegistry.Registrations`, finds `EmailExecutor` by its `StepType` `"EmailStep"` (`EmailExecutor.cs:121`), and maps the registration's remaining string `"email"` to it — same for `IisResetExecutor`'s `"IisResetStep"` (`IisResetExecutor.cs:71`) and `"iisreset"`. Both `{"type":"emailstep"}` and `{"type":"email"}` now dispatch.

The mechanism this example still teaches: the dictionary is keyed by whatever `step.Type` literally says, and editor-created steps dodge alias questions entirely because `UtilityStepConverter.WriteJson` synthesizes `type = value.GetType().Name` (`"EmailStep"`). Hand-authored JSON using a short alias depends on the derivation — which now holds for every registration that has an executor.

## DeveloperPack / ADR warning

The repo's DeveloperPack is **internally inconsistent** on this topic: `10_ADR_008_StepTypeRegistry.md:14-15` still describes two `CreateStepForType` *switches* at `Steps.razor.cs:279-301` / `WorkloadEditor.razor.cs:378-400` (both wrong — the switches are gone and the real methods are at `Steps.razor.cs:635-644` / `WorkloadEditor.razor.cs:550-558`), while `11_DeveloperGuide.md:59`, `07_TestStrategyAndGaps.md:59`, and `08_RefactoringBacklog.md:29` correctly record the 2026-07-26 registry delegation. `12_QuestionsAndBacklog.md:43` lists "derive the orchestrator alias table from the registry" as REMAINING — also stale; it has since been done. **Trust the code, not the ADR** — verify against the files above before acting.

## Sources
- `CrewChief\CrewChief.Engine\Steps\StepTypeRegistry.cs`
- `CrewChief\CrewChief.Engine\Orchestration\UtilityOrchestrator.cs`  (self-registration loop 55-59, registry-derived alias loop 61-91, dispatch 230-232, validation 479-482)
- `CrewChief\CrewChief.Engine\Executors\IisResetExecutor.cs`  (StepType line 71)
- `CrewChief\CrewChief.Engine\Executors\EmailExecutor.cs`  (StepType line 121)
- `CrewChief\CrewChief.Web\Components\Pages\Steps.razor.cs`  (CreateStepForType 635-644)
- `CrewChief\CrewChief.Web\Components\Pages\WorkloadEditor.razor.cs`  (CreateStepForType 550-558)
- `CrewChief\CrewChief.Web\Helpers\UtilityStepTypeInfo.cs`  (AllTypes 166-169)
- `CrewChief\CrewChief.Web\Components\Controls\StepEditorCard.razor.cs`  (`Step is XxxStep` branches)
- `CrewChief\CrewChief.Engine\EngineServiceCollectionExtensions.cs`  (executor DI registration, 32-90)
- `CrewChief\CrewChief.Tests.Unit\Web\StepTypeParityTests.cs`  (registry ↔ UI-table ↔ factory parity guard)

Coverage oracles that force the indivisible set (verified 2026-08-04):

- `CrewChief\CrewChief.Tests.Unit\Engine\StepTypeRegistryTests.cs`  (`ExpectedMappings` 23, exact-set assertion 115-121)
- `CrewChief\CrewChief.Tests.Unit\Engine\EngineRegistrationTests.cs`  (executor census `AreEqual(22, …)` at 44; doc-comment fixed 2026-08-06)
- `CrewChief\CrewChief.Tests.Unit\Web\ShippedSampleContentTests.cs`  (unknown-properties 171, coverage 202, non-destructive 225)
- `CrewChief\CrewChief.Tests.Unit\Web\StepDescriptionSeederTests.cs`  (seeder coverage 29)
- `CrewChief\CrewChief.Tests.Unit\Web\UtilityStepTypeInfoTests.cs`  (expected-canonical-keys array 114; 22 keys at 117)
- `CrewChief\CrewChief.Tests.Unit\Engine\WorkloadRunAsInheritanceTests.cs`  (box-prep family census `AreEqual(7, …)` at 353, structural guard 334-365)
- `CrewChief\CrewChief.Web\Services\StepDescriptionSeeder.cs`
- `CrewChief\CrewChief.Web\SampleContent\workloads\all-step-types.workload.json`
