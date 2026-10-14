---
name: testauto-config-validation
description: >
  Multi-layer FluentValidation pipeline for ScenarioConfiguration in TestAuto. Use when adding a
  validation rule, debugging a failure message, working out which validator fires when, implementing
  IValidationService, JobConfigurationValidator / LoadConfigurationValidator behavior, a rule that
  appears not to fire (the Validation:ShadowMode kill switch), the never-invoked CrossFieldValidator,
  or validator DI registration.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto ScenarioConfiguration Validation

> **Scope**: speed-merchants (TestAuto.Shared.Validation)
> **Source**: `TestAuto.Shared\Validation\*.cs`

ScenarioConfiguration goes through a layered FluentValidation pipeline before execution. Each validator has a distinct scope — from structural presence checks to cross-field consistency warnings.

---

## Entry Points

There are **three independent entry points**. Nothing composes them together, and no single
call runs every validator in the assembly.

| Entry point | What it resolves | Evidence |
|---|---|---|
| `IValidationService.ValidateConfigurationAsync` (Web/UI/controllers) | one injected `IValidator<ScenarioConfiguration>` → `ScenarioConfigurationValidator` | `TestAuto.Web\Services\ValidationService.cs:53` (ctor `:40`) |
| `IConfigurationValidationManager.ValidateScenarioAsync` (validate a config *file*) | the same single `IValidator<ScenarioConfiguration>` | `TestAuto.Shared\Helpers\ConfigurationValidationManager.cs:19` |
| `VerbRunTestOptionsHandler` (CLI `run-test`) | `IValidator<WorkloadConfiguration>`, `IValidator<JobConfiguration>`, `IValidator<LoadConfiguration>` | `TestAuto.Commands\RunTest\VerbRunTestOptionsHandler.cs:170`, `:203`, `:236` |

## Validator Hierarchy

```
ValidateConfigurationAsync(ScenarioConfiguration)      [Web path]
  └── ScenarioConfigurationValidator      (the ONLY validator this path runs —
        │                                  validates ScenarioName + NotNull on all 7
        │                                  sections, then delegates each section)
        ├── ScenarioTablesValidator           (SourceEntityName)
        ├── ScenarioDataShapeValidator        (attribute counts)
        ├── ScenarioRuntimeValidator          (runtime counts/concurrency + CustomParms)
        ├── ScenarioQueryValidator            (query parameters)
        ├── ScenarioRestTargetValidator       (SubjectAreaOverrides only)
        ├── ScenarioEnvironmentValidator      (environment settings)
        └── ScenarioTestingValidator          (testing limits)

LoadConfigurationValidator                             [CLI path only]
  └── JobConfigurationValidator                        (RuleForEach Jobs)
        └── WorkloadConfigurationValidator             (RuleForEach Workloads)
              └── ScenarioConfigurationBaseValidator   (nested, parameterless — its only use)

CrossFieldValidator                                    [NOT INVOKED — see below]
```

> `ScenarioConfigurationValidator` is the *only* validator on the Web path. It does **not**
> compose `WorkloadConfigurationValidator`, `ScenarioConfigurationBaseValidator`, or
> `CrossFieldValidator`.

---

## CrossFieldValidator Is Registered But Never Invoked

`CrossFieldValidator` is a fully implemented `AbstractValidator<ScenarioConfiguration>`
(`TestAuto.Shared\Validation\CrossFieldValidator.cs:10`) with seven `Custom` rules — **none of
which ever run in production**.

- It is registered by concrete type: `services.AddSingleton<CrossFieldValidator>();`
  (`TestAuto.DependencyInjection\ServiceExtensions\ScenarioManagementServiceExtensions.cs:219`).
- A repo-wide grep for `CrossFieldValidator` returns exactly **three** hits: the class
  declaration, its constructor, and that one registration line. **Nothing resolves it** —
  no `GetRequiredService<CrossFieldValidator>()`, no constructor injection, no `SetValidator`,
  no `Include(...)`.
- The rules below are therefore a **specification of intent, not observed behaviour**. If you
  need them enforced, wire the validator in explicitly (e.g. `Include(new CrossFieldValidator())`
  inside `ScenarioConfigurationValidator`, or resolve and run it alongside the main validator in
  `ValidationService`).

> Caveat when wiring it up: `AddValidatorsFromAssemblyContaining<ScenarioConfigurationValidator>`
> (`ScenarioManagementServiceExtensions.cs:214`) scans the whole assembly, so
> `CrossFieldValidator` and `ScenarioConfigurationBaseValidator` are *also* registered against
> `IValidator<ScenarioConfiguration>`. Only one instance comes back from
> `GetRequiredService<IValidator<ScenarioConfiguration>>()` (last registration wins). Do not
> rely on scan order — compose explicitly.

---

## Per-Validator Scope

| Validator | Validates (complete rule list) | When to Use Directly |
|---|---|---|
| `ScenarioConfigurationValidator` | `ScenarioName` NotEmpty; `NotNull` on each of `ScenarioTables`, `ScenarioDataShape`, `ScenarioRuntime`, `ScenarioQuery`, `ScenarioRestTarget`, `ScenarioEnvironment`, `ScenarioTesting`, each then `SetValidator`-delegated | Via `IValidationService` in normal DI flow |
| `ScenarioConfigurationBaseValidator` | `ScenarioName` NotEmpty; `ScenarioTables` NotNull → `SourceEntityName` NotEmpty; `ScenarioRuntime` NotNull → `ScenarioRuntimeValidator`; `ScenarioDataShape` → `ScenarioDataShapeValidator` *only when non-null*; `ScenarioRestTarget` NotNull → `ScenarioRestTargetValidator`. Note: **no** Query/Environment/Testing rules | Nested in `WorkloadConfigurationValidator` — no DI needed |
| `WorkloadConfigurationValidator` | `Scenarios` NotNull + at least one entry; per wrapper: `Name` NotEmpty, `ScenarioConfiguration` NotNull → `ScenarioConfigurationBaseValidator` | Nested by `JobConfigurationValidator`; also resolvable as `IValidator<WorkloadConfiguration>` |
| `ScenarioTablesValidator` | `SourceEntityName` NotEmpty — **this is its only rule** (no entity-name format check, no "required tables" check) | — |
| `ScenarioDataShapeValidator` | `FreeformAttributes` >= 0; `DomainAttributes` >= 0 (file is `ScenarioDataShapeValidatorcs.cs` — filename typo is real) | — |
| `ScenarioRuntimeValidator` | `When(NumberOfGeneratedTestRecordsPerBatch != 0 \|\| BatchSize != 0 \|\| PageNumber != 0)` → each must be > 0 (an all-zero runtime is a valid config-only runtime); always: `MaxHangfireScenarioServersCount` > 0, `MaxConcurrentBatchesPerHangfireScenarioServer` > 0; conditional CustomParms keys `VariantCount`, `TransformSeed`, `SourceSystems`, `DataMutationSettings` (must contain `RuleDefinitions`), `MaxAttributeChanges` | — |
| `ScenarioQueryValidator` | `Filter`, `SelectAttributes`, `SortAttributes` — each *only when* already non-whitespace, must not be empty/whitespace; `QueryParameters` keys and values non-empty when the dictionary is populated | — |
| `ScenarioRestTargetValidator` | **Only** `RuleForEach(SubjectAreaOverrides)`: for a `RestTargetOverride` with a non-blank `RestUrlBase` → must be a valid absolute URI *and* `RestApiKey` must be non-blank. Top-level `RestUrlBase`/`RestApiKey` are **not** validated | — |
| `ScenarioEnvironmentValidator` | `DqRuleCount` >= 0; `HangfireJob` >= 0; `SimulatedUserThreadId` >= 0; `TargetEnvironment` required; `TargetEnvironmentName` required; `ProfiseeVersion` required | — |
| `ScenarioTestingValidator` | `TestRecordLimit` required and > 0; `TestOverrideQueueName` — when supplied, letters/digits/`-`/`_` only | — |
| `CrossFieldValidator` | Cross-section rules (see below) — **never invoked** | — |

---

## Job / Load Configuration Validators (CLI path)

Two more validators exist for the CLI's nested `run-test` shapes. They are **not** reachable
from `IValidationService`; the CLI resolves them directly.

| Validator | Type | Rules | File |
|---|---|---|---|
| `JobConfigurationValidator` | `AbstractValidator<JobConfiguration>` | `JobId` NotEmpty; `JobName` NotEmpty; `Workloads` NotNull + at least one; `RuleForEach(Workloads) → new WorkloadConfigurationValidator()` | `TestAuto.Shared\Validation\JobConfiguratoinValidator.cs:6` (filename misspelling is real — the *class* is spelled correctly) |
| `LoadConfigurationValidator` | `AbstractValidator<LoadConfiguration>` | `Driver`, `GlobalScenarioConfiguration`, `ScenarioExecutionContext`, `SecurityContext` all NotNull; `LoadThreadCount` > 0; `Jobs` NotNull + at least one; `RuleForEach(Jobs) → new JobConfigurationValidator()` | `TestAuto.Shared\Validation\LoadConfiguratorValidator.cs:6` (filename misspelling is real) |

Both nest their children with `new ...Validator()` rather than DI, so the whole
Load → Job → Workload → ScenarioConfigurationBase chain runs from a single
`IValidator<LoadConfiguration>` resolve.

---

## CrossFieldValidator Rules (specified, not executed)

| Rule | Severity | Condition |
|---|---|---|
| TestRecordLimit vs. generated records | Error | `TestRecordLimit > NumberOfGeneratedTestRecordsPerBatch` |
| BatchSize vs. TestRecordLimit | Error | `BatchSize > TestRecordLimit` |
| Small batch for large limit | Warning | `TestRecordLimit > 1000` and `BatchSize < 50` |
| Dev environment with prod-scale settings | Warning | `TargetEnvironment` contains "dev" and `DqRuleCount > 100` or `HangfireJob > 10` |
| Prod environment with dev-scale settings | Warning | `TargetEnvironment` contains "prod" and `DqRuleCount < 10` or `HangfireJob < 2` |
| High concurrency in dev | Warning | Dev environment and `MaxConcurrentBatchesPerHangfireScenarioServer > 5` |
| Low concurrency in prod | Warning | Prod environment and `MaxConcurrentBatchesPerHangfireScenarioServer < 3` (may impact performance) |
| REST override missing API key | Error | `RestUrlBase` set without `RestApiKey` (or vice versa) |
| Total attributes very high | Warning | `FreeformAttributes + DomainAttributes > 1000` |
| No attributes defined | Error | Total attributes == 0 |
| Empty query for named entity | Warning | `SourceEntityName` is set but query is completely empty |

---

## Adding a Validation Rule

### To an existing sub-validator (most common)

Open the appropriate `*Validator.cs` file and add a `RuleFor` or `RuleForEach`:

```csharp
// Example (in ScenarioRuntimeValidator): require NumberOfGeneratedTestRecordsPerBatch > 0
RuleFor(x => x.NumberOfGeneratedTestRecordsPerBatch)
    .GreaterThan(0)
    .WithMessage("ScenarioRuntime.NumberOfGeneratedTestRecordsPerBatch must be greater than 0.");
```

### Cross-field rule (CrossFieldValidator)

> **A rule added here will not fire** until `CrossFieldValidator` is actually wired into an
> execution path (see the section above). If you need a cross-section rule enforced *today*, put
> a `RuleFor(x => x).Custom(...)` directly in `ScenarioConfigurationValidator` instead.

```csharp
RuleFor(x => x)
    .Custom((configuration, context) =>
    {
        if (configuration.SectionA?.ValueA > configuration.SectionB?.ValueB)
        {
            context.AddFailure(new ValidationFailure("SectionA.ValueA",
                $"ValueA ({configuration.SectionA.ValueA}) cannot exceed ValueB ({configuration.SectionB.ValueB})"));
        }
    });
```

For warnings (not errors), set `Severity = Severity.Warning` on the `ValidationFailure`.

---

## Common Error Messages Reference

| Message fragment | Root cause |
|---|---|
| `ScenarioName is required` | `ScenarioName` is null or empty |
| `ScenarioTables is missing` | `ScenarioTables` section absent from JSON |
| `SourceEntityName is required` | `ScenarioTables.SourceEntityName` not set |
| `ScenarioRuntime is missing` | `ScenarioRuntime` section absent |
| `ScenarioRestTarget is missing` | `ScenarioRestTarget` section absent |
| `TestRecordLimit cannot exceed` | Cross-field: limit exceeds generated count. **CrossFieldValidator-only — cannot appear at runtime today** |
| `RestApiKey is required when RestUrlBase is provided` | Subject area override has only one of the two. This one *does* fire — `ScenarioRestTargetValidator` emits it independently of `CrossFieldValidator` |
| `ScenarioTesting.TestRecordLimit is required and must be greater than 0` | `ScenarioTestingValidator` — `TestRecordLimit` <= 0 |
| `ScenarioEnvironment.TargetEnvironmentName is required` / `ProfiseeVersion is required` | `ScenarioEnvironmentValidator` — commonly missed because these two are absent from older sample configs |
| `RestUrlBase must be a valid absolute URL` | `ScenarioRestTargetValidator` — override URL fails `Uri.TryCreate(..., UriKind.Absolute, ...)` |

---

## Using IValidationService

```csharp
// Inject in constructor
public class MyService(IValidationService validationService) { }

// Validate
var result = await validationService.ValidateConfigurationAsync(scenarioConfiguration);
if (!result.IsValid)
{
    var errors = result.Errors.Select(e => e.ErrorMessage);
    // handle errors
}
```

### Shadow mode (`Validation:ShadowMode`)

`ValidationService` supports a **phased-rollout kill switch**. This is the single biggest
gotcha in this subsystem: with shadow mode on, `ValidateConfigurationAsync` **always returns
a valid result**, so `result.IsValid` is meaningless.

- Read **once at construction** from `IConfiguration`:
  `configuration.GetValue<bool>("Validation:ShadowMode", defaultValue: true)`
  (`TestAuto.Web\Services\ValidationService.cs:47`). It cannot change per request.
- **Default is `true`** when the key is absent. The shipped `appsettings.json` sets
  `"Validation": { "ShadowMode": false }` (`TestAuto.Web\appsettings.json:169`, mirrored in
  `installer\stage\web\appsettings.json:169`), so a *deployed* app validates for real — but any
  host that omits the key silently validates nothing.
- When on and the result is invalid: each failure is logged as
  `[SHADOW] Validation failure suppressed — Property: {Property}, Error: {Error}` at Warning
  level, and an empty `new ValidationResult()` is returned (`:67`-`:76`).
- When on and the validator **throws**: the exception is logged and swallowed, again returning
  an empty valid result (`:84`-`:87`). With shadow mode off, the exception becomes a single
  `ValidationFailure("Validation", "Unhandled validation error: …")`.
- Debugging "my new rule doesn't fire": check `Validation:ShadowMode` before anything else,
  then search Seq for `[SHADOW]`.

### Other members of `IValidationService` are stubs

`ValidateSectionAsync` returns valid unless `sectionData` is null (`:97`).
`GetValidationRulesAsync` returns a small hand-written list for `ScenarioTables` /
`ScenarioRuntime` and an Info placeholder otherwise (`:115`).
`ValidateWithRulesAsync` ignores `ruleNames` and defers to `ValidateConfigurationAsync` (`:182`).
`GetValidationSuggestionsAsync` maps every failure to the same generic suggestion string (`:191`).

---

## DI Registration

| Registration | Where |
|---|---|
| `services.AddValidatorsFromAssemblyContaining<ScenarioConfigurationValidator>(ServiceLifetime.Singleton)` — assembly-wide scan; validators are **Singleton** so DI validate-on-build can resolve them | `TestAuto.DependencyInjection\ServiceExtensions\ScenarioManagementServiceExtensions.cs:214` |
| `services.AddSingleton<CrossFieldValidator>()` — concrete type only; never resolved | same file, `:219` |
| `services.AddScoped<IConfigurationValidationManager, ConfigurationValidationManager>()` | same file, `:220` |
| `services.AddFluentValidationAutoValidation()` + `AddFluentValidationClientsideAdapters()` | same file, `:221`-`:222` |
| `services.TryAddScoped<IValidationService, ValidationService>()` — the Web implementation | `TestAuto.Web\AutoRegistration\WebModuleRegistrar.cs:92` |

`ScenarioServices` also takes an `IValidator<ScenarioConfiguration>` constructor argument
(`ScenarioManagementServiceExtensions.cs:208`), resolved from the same scan.

Because the scan registers **three** `AbstractValidator<ScenarioConfiguration>` types against
`IValidator<ScenarioConfiguration>`, adding a fourth changes which one a plain
`IValidator<ScenarioConfiguration>` resolve returns. Prefer explicit composition inside
`ScenarioConfigurationValidator` over adding a new top-level `AbstractValidator<ScenarioConfiguration>`.

---

## Sources

- `TestAuto.Shared\Validation\ScenarioConfigurationBaseValidator.cs`
- `TestAuto.Shared\Validation\ScenarioConfigurationValidator.cs`
- `TestAuto.Shared\Validation\CrossFieldValidator.cs`
- `TestAuto.Shared\Validation\WorkloadConfigurationValidator.cs`
- `TestAuto.Shared\Validation\ScenarioEnvironmentValidator.cs`
- `TestAuto.Shared\Validation\ScenarioQueryValidator.cs`
- `TestAuto.Shared\Validation\ScenarioTablesValidator.cs`
- `TestAuto.Shared\Validation\ScenarioRuntimeValidator.cs`
- `TestAuto.Shared\Validation\ScenarioTestingValidator.cs`
- `TestAuto.Shared\Validation\ScenarioRestTargetValidator.cs`
- `TestAuto.Shared\Validation\ScenarioDataShapeValidatorcs.cs`
- `TestAuto.Shared\Validation\JobConfiguratoinValidator.cs`
- `TestAuto.Shared\Validation\LoadConfiguratorValidator.cs`
- `TestAuto.Web\Services\ValidationService.cs` (ShadowMode)
- `TestAuto.Shared\Helpers\ConfigurationValidationManager.cs`
- `TestAuto.DependencyInjection\ServiceExtensions\ScenarioManagementServiceExtensions.cs` (DI, ~208-222)
- `TestAuto.Commands\RunTest\VerbRunTestOptionsHandler.cs` (CLI Workload/Job/Load validation)
