---
name: testauto-enrichment-generators
description: >
  Field generator patterns for the standalone TestData.Enrichment console tool and
  TestData.Enrichment.Core (NOT any TestAuto.* project, despite the skill name). Use when adding a
  generator class, implementing IFieldGenerator<SourceRecord>, adding the required
  FieldGeneratorFactory case, debugging "Unknown generator" / "Unsupported FieldRuleType", the
  [Generator] reflection scan in Program.cs, or configuring FieldRules JSON.
---

Repo: speed-merchants (paths below are repo-relative)

# TestData Enrichment — Field Generator Pattern

> **Scope**: speed-merchants — the standalone `TestData.Enrichment` console tool and its
> `TestData.Enrichment.Core` library. Despite the `testauto-` name prefix this skill does **not**
> cover any `TestAuto.*` project. For the surrounding ETL pipeline (ScenarioRunner, BulkMerge,
> checkpoints, CloneAndMutate) see [[testdata-enrichment-pipeline]] — same codebase, wider scope.
> **Source**: live code in `TestData.Enrichment\Program.cs` + `TestData.Enrichment.Core\Services\FieldGeneratorFactory.cs`

Adding a new generator takes **3** steps: create the decorated class, **add a `case` to
`FieldGeneratorFactory.Create()`**, then wire it in the JSON `FieldRules`.

DI registration is the only step that is automatic — every `[Generator]`-attributed
`IFieldGenerator<SourceRecord>` is transient-registered by a hand-rolled reflection scan in
`Program.cs` (see below). **Registration alone is not enough**: the factory resolves the JSON
`"Generator"` string through a hardcoded `switch`, not through the attribute, so a generator that
skips step 2 throws at run time.

---

## Step 1 — Create the Generator Class

Decorate with `[Generator("Name")]` and implement `IFieldGenerator<SourceRecord>`:

```csharp
[Generator("Phone")]
public class PhoneFieldGenerator : IFieldGenerator<SourceRecord>
{
    private string _targetTable = "";
    private string _columnName  = "";

    public string ColumnName => _columnName;

    public void Configure(FieldRuleDefinition rule, ScenarioDefinition scenario)
    {
        _columnName  = rule.TargetColumn;
        _targetTable = scenario.TargetTable;
    }

    public Task PreloadAsync(SqlConnection _)
        => Task.CompletedTask;

    public object? Generate(SourceRecord src, SourceRecord? _)
        => /* your generation logic here */;
}
```

### Interface contract

| Method | When called | Purpose |
|---|---|---|
| `Configure(rule, scenario)` | Once at startup | Read rule config + scenario definition; store anything needed for generation |
| `PreloadAsync(connection)` | Once at startup, after Configure | Load lookup tables or large datasets from DB if needed |
| `Generate(src, reference?)` | Once per record | Return the generated value for this record |

By convention the `[Generator("Name")]` value matches the `"Generator"` key in the JSON
`FieldRules` — but nothing enforces that, because the factory never reads the attribute (see
Step 2). The attribute's only runtime effect is DI registration and the startup "Loaded {Count}
generators" log line (`Program.cs:112-130`).

`GeneratorAttribute` lives at `TestData.Enrichment.Core\Services\GeneratorAttribute .cs` — note the
**space before `.cs`** in the real filename.

---

## DI registration is automatic — resolution is NOT

`Program.cs` scans the loaded assemblies with plain reflection and transient-registers every
matching type. The filter has four clauses, not one:

```csharp
// TestData.Enrichment/Program.cs:51-62 — hand-rolled reflection scan (NOT Scrutor)
var generatorTypes = AppDomain.CurrentDomain.GetAssemblies()
    .SelectMany(a => a.GetTypes())
    .Where(t =>
        typeof(IFieldGenerator<SourceRecord>).IsAssignableFrom(t) &&
        !t.IsInterface &&
        !t.IsAbstract &&
        t.GetCustomAttribute<GeneratorAttribute>() != null)
    .ToList();

foreach (var gt in generatorTypes)
    services.AddTransient(gt);
```

A type that carries `[Generator]` but does **not** implement `IFieldGenerator<SourceRecord>` (or
is abstract) is silently skipped by this filter.

> **No Scrutor anywhere.** A repo-wide grep for `Scrutor` / `services.Scan` returns zero hits
> (checked 2026-07-27 @ 4c367fe6). Re-run the grep if you need to confirm.
>
> ⚠️ **The in-repo doc is wrong on this point.**
> `TestData.Enrichment.Core\Generators\adding_new_generator.md` step 2 tells you to register with
> Scrutor's `services.Scan(...)`, and closes with *"your new generator will be picked up
> automatically by the engine"*. Both claims are stale: there is no Scrutor package, and being
> "picked up" by the DI scan does **not** make the generator reachable — `FieldGeneratorFactory`
> still throws `Unknown generator '<name>'` until you add a `case`. That file is in the read-only
> scan target and has not been corrected; trust this skill over it.

---

## Step 2 — Add a `case` to `FieldGeneratorFactory.Create()` (REQUIRED)

`TestData.Enrichment.Core\Services\FieldGeneratorFactory.cs` resolves generators with **two
nested hardcoded switches** — the outer on `rule.RuleType`, the inner on the `rule.Generator`
string (`FieldGeneratorFactory.cs:25-93`). Instances are built with
`ActivatorUtilities.CreateInstance<T>(_sp, …ctor args…)`, so each case also supplies that
generator's constructor arguments — which is precisely why this cannot be attribute-driven today.

```csharp
// FieldGeneratorFactory.cs — inner switch, ~lines 55-88
case "SSN":     return ActivatorUtilities.CreateInstance<SsnFieldGenerator>(_sp, scenario.TargetTable, rule.TargetColumn);
case "Email":   return ActivatorUtilities.CreateInstance<EmailFieldGenerator>(_sp, scenario.TargetTable, rule.TargetColumn, _settings.EmailProviders);
case "DOB":     return ActivatorUtilities.CreateInstance<DobFieldGenerator>(_sp, 18, 80, rule.TargetColumn);  // age range hardcoded here
case "Code":    return ActivatorUtilities.CreateInstance<CodeGenerator>(_sp);
case "Cleanup": return ActivatorUtilities.CreateInstance<CleanupGenerator>(_sp);
default:        throw new InvalidOperationException($"Unknown generator '{rule.Generator}' for TargetColumn '{rule.TargetColumn}' in scenario '{scenario.Name}'.");
```

The outer switch handles the structural rule types (`Map`, `Clear`, `Constant`, `Context`), each
with its own `ActivatorUtilities.CreateInstance` call and ctor args; an unhandled `FieldRuleType`
throws `Unsupported FieldRuleType '<type>'`.

Re-read the file rather than trusting the case list above — it is the kind of thing that grows.

---

## Step 3 — Wire in JSON FieldRules

In the scenario's `FieldRules` array:

```json
{
  "TargetColumn": "PhoneNumber",
  "RuleType": "Generate",
  "Generator": "Phone"
}
```

The engine matches `"Generator": "Phone"` to the `case "Phone":` you added in Step 2 — **not** to
the `[Generator("Phone")]` attribute. Miss Step 2 and this JSON throws
`Unknown generator 'Phone' for TargetColumn 'PhoneNumber' in scenario '<name>'` on the first
`Create()` call (generator preload, before any batch runs).

---

## Built-in Generators

Named generators reachable from JSON (i.e. present in the factory's inner switch):

| Generator Name | Class | Generates |
|---|---|---|
| `"SSN"` | `SsnFieldGenerator` | Social Security Numbers (preloads existing SSNs for uniqueness) |
| `"Email"` | `EmailFieldGenerator` | Email addresses (needs `AppSettings.EmailProviders`) |
| `"DOB"` | `DobFieldGenerator` | Dates of Birth; age range 18–80 hardcoded in the factory case |
| `"Code"` | `CodeGenerator` | Sequential/formatted codes; also implements `ICheckpointAware` |
| `"Cleanup"` | `CleanupGenerator` | Normalises/sanitises values; bound to `FieldGenerators:Cleanup` config |

Structural generators are selected by `RuleType`, not by name: `MapFieldGenerator`,
`ClearFieldGenerator`, `ConstantFieldGenerator`, `ContextFieldGenerator`.

Copy `SsnFieldGenerator` or `EmailFieldGenerator` as a starting point for a new generator.

> Only attribute-decorated classes appear in the startup "Loaded {Count} generators" log. Do not
> read that count as "generators usable from JSON" — the two sets differ (e.g. `ContextFieldGenerator`
> carries no `[Generator]` attribute yet is still constructible via the factory's `Context` case).

---

## Sources

- `TestData.Enrichment.Core\Services\FieldGeneratorFactory.cs` (required switch)
- `TestData.Enrichment\Program.cs` (DI scan :51-62; diagnostic re-scan :112-130)
- `TestData.Enrichment.Core\Services\GeneratorAttribute .cs` (filename has a space)
- `TestData.Enrichment.Core\Generators\` (all generator classes)
- `TestData.Enrichment.Core\Generators\adding_new_generator.md` — **STALE**, see the Scrutor caveat above
