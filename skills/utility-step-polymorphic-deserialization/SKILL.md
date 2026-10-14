---
name: utility-step-polymorphic-deserialization
description: >
  The two polymorphic-deserialization switches for UtilityStepBase step types in TestAuto.Utilities —
  UtilityStepConverter (runtime) and UtilityStepBase.CreateFromJToken (Web/editor) — and the rule
  that they stay in sync. Use when deserializing MultiStepUtilityScenario JSON, adding a step type or
  alias to either switch, registering the converter, or debugging "Unknown step type" errors that
  appear at run time but not in the editor.
---

Repo: speed-merchants (paths below are repo-relative)

# Utility Step Polymorphic Deserialization (`UtilityStepConverter`)

> **Scope**: speed-merchants (TestAuto.Utilities)
> **Source**: `TestAuto.Utilities/Common/DTOs/UtilityStepConverter.cs`

`UtilityStepConverter` is a Newtonsoft `JsonConverter<UtilityStepBase>` that dispatches on the `"Type"` property of a step JSON object to instantiate the correct concrete subclass. This is what allows MultiStepUtilityScenario configs to use short type strings like `"sql"` or `"connex"` instead of fully-qualified class names.

---

## Registration

Use the static `Serializer` property to get a pre-configured `JsonSerializer`:

```csharp
// Deserialize a step list from JSON
var steps = jsonObject["Steps"].ToObject<List<UtilityStepBase>>(UtilityStepConverter.Serializer);
```

Or register manually in `JsonSerializerSettings`:

```csharp
var settings = new JsonSerializerSettings
{
    Converters = { new UtilityStepConverter() }
};
```

---

## Type Dispatch Table

The converter matches the `"Type"` (or `"type"`) property case-insensitively:

| JSON type string(s) | Concrete class |
|---|---|
| `"sqlstep"`, `"sql"` | `SqlStep` |
| `"powershellstep"`, `"powershell"`, `"ps"` | `PowerShellStep` |
| `"commandlinestep"`, `"commandline"`, `"cli"`, `"cmd"` | `CommandLineStep` |
| `"clustep"`, `"clu"` | `CLUStep` |
| `"httprequeststep"`, `"httprequest"`, `"http"`, `"curlstep"`, `"curl"` | `HttpRequestStep` |
| `"connexstep"`, `"connex"` | `ConnExStep` |
| `"monitorstep"`, `"monitor"` | `MonitorStep` |

Any other value throws `JsonSerializationException("Unknown step type: {stepType}")`.

---

## Read Behavior

1. Load the step JSON into a `JObject`
2. Extract `"Type"` or `"type"` (case-sensitive key lookup, both checked)
3. Switch on `stepType.ToLowerInvariant()` to instantiate the concrete type
4. Populate the instance using `serializer.Populate` from a sub-reader of the original `JObject`

Throws if `Type` is missing or empty.

---

## Write Behavior

To avoid infinite recursion, `WriteJson` serializes via `JObject.FromObject(value)` (clean serializer, no converter). Then it ensures the `"Type"` property is set to `value.GetType().Name` if missing or empty before writing to the output.

---

## ⚠️ Two Dispatch Paths — `UtilityStepConverter` AND `UtilityStepBase.CreateFromJToken`

There are **two independent switches over the same type strings**. They are not layered — neither calls the other — and each serves a different half of the app.

| | `UtilityStepConverter.ReadJson` | `UtilityStepBase.CreateFromJToken` |
|---|---|---|
| Location | `UtilityStepConverter.cs:20-89` | `UtilityStepBase.cs:83-113` |
| Signature | Newtonsoft `JsonConverter<UtilityStepBase>` hook | `public static UtilityStepBase CreateFromJToken(JToken)` |
| How it builds the object | `new XxxStep()` then `serializer.Populate(subReader, step)` — **honors the caller's `JsonSerializer` settings** | `JsonConvert.DeserializeObject<XxxStep>(token.ToString())` — a **fresh default serializer**, settings not inherited |
| Unknown type throws | `JsonSerializationException("Unknown step type: {stepType}")` | `NotSupportedException("Step type '{stepType}' is not supported. Supported types are: …")` |
| Missing `Type` throws | `JsonSerializationException` | `InvalidOperationException` (and `ArgumentNullException` for a null token) |
| Null-`Parameters` guard | **none** | `step.Parameters ??= new Dictionary<string,string>(OrdinalIgnoreCase)` at `:110` |

**Who calls which** (production, non-test):

- **Converter — the runtime path.** Its only production consumer is `UtilityBase.ParseStepsFromConfiguration` (`UtilityBase.cs:162-169`), which builds a `JsonSerializer` with the converter and calls `stepsToken.ToObject<List<UtilityStepBase>>(serializer)`. This is how `MultiStepUtilityScenario` loads steps when a scenario **executes**.
- **`CreateFromJToken` — the Web/editor path.** `UtilityScenarioEditor.razor.cs:200` (load), `:633` (duplicate step), `:918`; `ConnExResourcePageBase.cs:464`; `UtilityCommandTest.razor.cs:221`.

### The keep-in-sync rule

**Every alias added to one switch must be added to the other.** As of HEAD both cover the identical set: `sqlstep|sql`, `powershellstep|powershell|ps`, `commandlinestep|commandline|cli|cmd`, `clustep|clu`, `httprequeststep|httprequest|http|curlstep|curl`, `connex|connexstep`, `monitor|monitorstep`.

### What breaks on drift

Because the two paths sit on opposite sides of the app, a one-sided edit fails **late and asymmetrically** — never at compile time:

| Drift | Symptom |
|---|---|
| Added to the **converter only** | The scenario runs fine, but the Web editor throws `NotSupportedException: Step type 'X' is not supported` the moment anyone opens that scenario. The config is unopenable and unmaintainable in the UI even though it executes. |
| Added to **`CreateFromJToken` only** | Authors can build and save the step in the editor, and it looks correct on disk — then the run dies in `UtilityBase.ParseStepsFromConfiguration` with `JsonSerializationException: Unknown step type: X`. The whole `Steps` array fails to deserialize, so **every** step in the scenario is lost, not just the new one. |
| Aliases diverge (e.g. `"cmd"` in one switch only) | The same JSON works or fails depending on whether it is being *executed* or *opened in the editor* — the most confusing failure mode of the three. |

A secondary, quieter asymmetry: a step with an explicit `"parameters": null` comes out of the **converter** with `Parameters == null` (Newtonsoft's `Populate` overwrites the field initializer), while `CreateFromJToken` normalizes it back to an empty case-insensitive dictionary. Executors and editors that assume a non-null dictionary can therefore NRE at run time but not in the editor. Guard `Parameters` in any new executor rather than relying on the DTO initializer.

---

## Adding a New Step Type

1. Create a concrete class inheriting `UtilityStepBase`
2. Add a `case` in `UtilityStepConverter.ReadJson` with all desired alias strings
3. **Add the matching arm to `UtilityStepBase.CreateFromJToken`'s switch expression with the identical alias set** — see the drift table above; missing this is silent until run time or until someone opens the scenario in the editor
4. Update the `NotSupportedException` message's "Supported types are: …" list in `CreateFromJToken` (it is hand-maintained, not generated)
5. No changes to `WriteJson` — it auto-emits `GetType().Name` as the type string

> This is only the deserialization half. A new step type also needs an executor, DI registration, and an orchestrator alias — see the full checklist in [[testauto-utilities-module]].

---

## Sources

- `TestAuto.Utilities\Common\DTOs\UtilityStepConverter.cs`
- `TestAuto.Utilities\Common\DTOs\UtilityStepBase.cs` — `CreateFromJToken`, the second dispatch switch
- `TestAuto.Utilities\Common\UtilityBase.cs` — sole production consumer of the converter (runtime step parsing)
- `TestAuto.Web\Components\Controls\UtilityScenarioEditor.razor.cs` — `CreateFromJToken` consumer (editor load / duplicate)
