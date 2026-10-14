---
name: testauto-custom-parm-defaults
description: >
  Default-CustomParms mechanism for TestAuto scenarios — [CustomParm] static classes reflected into a
  defaults dictionary by CustomParmDictionaryHelper.BuildDictionary, with scenario CustomParms as
  overrides. Use when adding a scenario parameter, editing a *CustomParms / *Constants class, calling
  BuildDictionary, whether a REQUIRED parameter may be [CustomParm] (the self-referential nameof
  trap), or why a missing required CustomParm did not fail fast.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto CustomParm Defaults (`[CustomParm]` + `BuildDictionary`)

> **Scope**: speed-merchants — cross-domain (Connect, Matching, Records, Metadata, Scenarios)
> **Core source**: `TestAuto.Scenarios\Common\CustomParmAttribute.cs`, `TestAuto.Scenarios\Helpers\CustomParmDictionaryHelper.cs`

Every scenario domain builds its runtime parameter dictionary the same way: a static
parameter class exposes `[CustomParm]`-attributed static string properties;
`CustomParmDictionaryHelper.BuildDictionary(typeof(ThatClass), overrides: …)` reflects them
into a `Dictionary<string, string>` of defaults, then applies the scenario's configured
`CustomParms` as overrides on top. The resulting dictionary (often `_allParams` / `parmDict`)
is what the scenario reads at runtime.

## Mechanism

```csharp
// TestAuto.Scenarios\Common\CustomParmAttribute.cs
[AttributeUsage(AttributeTargets.Property)]
public class CustomParmAttribute : Attribute
{
    public string? Key { get; }                  // null → property name is the key
    public CustomParmAttribute(string? key = null) { Key = key; }
}
```

`BuildDictionary(Type staticParmClass, string? dictionaryName, IDictionary<string,string>? overrides, Action<string>? logAction, bool displayDictionary, Action<string>? logLine)`:

1. Reflects `public static` properties carrying `[CustomParm]`.
2. Dictionary key = `attr.Key ?? prop.Name`; value = the property's value `.ToString()`.
3. Applies `overrides` (the scenario's configured `CustomParms`) last — overrides always win.
4. Optional `logAction` (one-line dump) and `displayDictionary`+`logLine` (per-entry dump, use Serilog `DebugWithTag`/`InformationWithTag`). `DumpDictionaryToConsole` is `[Obsolete]`.

Canonical call shape (identical in every domain):

```csharp
IDictionary<string, string>? overrides = null;
if (customParms != null)
    overrides = customParms.ToDictionary(kvp => kvp.Key, kvp => kvp.Value?.ToString() ?? string.Empty);

var parmDict = CustomParmDictionaryHelper.BuildDictionary(
    typeof(ConnectCustomParms),               // the domain's parameter class
    dictionaryName: "ConnectAllParams",
    overrides: overrides,
    logAction: msg => _logger.DebugWithTag(tag, msg),
    displayDictionary: true,
    logLine: msg => _logger.DebugWithTag(tag, msg));
```

## Parameter classes per domain

| Domain | Static class passed to `BuildDictionary` | Consumer |
|---|---|---|
| Connect | `ConnectCustomParms` | `ScenarioBaseConnect.ConfigureAllParams()` → `_allParams` |
| Records CRUD (base) | `RecordsCustomParms` | `ScenarioBaseCrud` → `_allParams` ("RecordsAllParams") |
| Records CRUD (create/update) | `RecordsConstants` | `CreateRecordsByPageAndBatchScenario`, `UpdateRecordsByPageAndBatchScenario` |
| Matching | `MatchingConstants` | `MatchingStrategyPollingScenario`, `MatchingSnapshotCaptureScenario`, `MatchingResultsScenario` |
| Metadata | `MetadataScenarioConstants` | `MetadataLoadScenario` |

(`RecordsCustomParms` carries `[CustomParm]` props mapping to `SharedConstants.Key*` values.)

## The three property idioms

| Idiom | Example | Dictionary effect |
|---|---|---|
| Identity / key constant | `[CustomParm] public static string EntityName => nameof(EntityName);` | Seeds `EntityName="EntityName"`. The prop doubles as a code-side key constant (`_allParams[ConnectCustomParms.EntityName]`). |
| Key mapping | `[CustomParm] public static string TimeLimit => SharedConstants.KeyTimeLimit;` | Seeds the shared-constants key string as the value. |
| Real default | `[CustomParm] public static string RemoteObjectTypeDefault => "Table";` | Seeds an actual usable default value (`*Default` naming convention). |

## ⚠️ The self-referential default trap (REQUIRED parameters)

A `[CustomParm]` identity property **always** seeds a non-empty placeholder
(`StrategyName="StrategyName"`) into the defaults dictionary. Any "is the key present and
non-empty?" required-field validation downstream then **always passes**, even when the user
never configured the parameter — the scenario runs with a garbage literal instead of failing
fast.

**Rule: a REQUIRED parameter must NOT be `[CustomParm]`.** Declare it as a plain `const`
key and read the RAW configured `CustomParms` directly, so a missing value is genuinely
missing:

```csharp
// ConnectCustomParms.cs — NOTE block (the authoritative statement of this rule)
// --- ConnectStrategyPollingScenario parameters ---
// NOTE: these are NOT [CustomParm] on purpose. A [CustomParm] member with `=> nameof(X)` seeds a
// self-referential default (e.g. StrategyName="StrategyName") into CustomParmDictionaryHelper.BuildDictionary,
// which would defeat the scenario's required-field validation. The poller reads the RAW CustomParms instead,
// so a missing StrategyName correctly fails fast. See the scenario's ParsePollingParms.

/// <summary>Required. Profisee Connect strategy name whose most-recent batch is polled.</summary>
public const string StrategyName = nameof(StrategyName);
```

```csharp
// ConnectStrategyPollingScenario.ApplyConfiguration — reading RAW CustomParms
// Read the RAW CustomParms (not CustomParmDictionaryHelper defaults) so a missing required value
// is genuinely missing and fails fast — see the note in ConnectCustomParms.
var raw = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
var customParms = cfg?.ScenarioRuntime?.CustomParms;
if (customParms != null)
    foreach (var kvp in customParms)
        raw[kvp.Key] = kvp.Value?.ToString() ?? string.Empty;

var parms = ParsePollingParms(raw);   // throws ArgumentException on missing StrategyName
```

Decision rule when adding a parameter:

- **Optional with a sensible default** → `[CustomParm]` (use a `*Default` prop for the value).
- **Optional lookup key only** → `[CustomParm]` identity prop is fine.
- **Required (scenario must not run without it)** → plain `const` + RAW CustomParms read + explicit validation.

## Related

- [[testauto-connex-service]] — documents `_allParams` on `ScenarioBaseConnect`
- [[testauto-scenario-catalog]] — per-scenario CustomParms reference
- [[custom-parm-editor]] — the UI editor side of CustomParms

## Sources

- `TestAuto.Scenarios\Common\CustomParmAttribute.cs`
- `TestAuto.Scenarios\Helpers\CustomParmDictionaryHelper.cs`
- `TestAuto.Connect\Configuration\ConnectCustomParms.cs` (NOTE block, lines 37-44)
- `TestAuto.Connect\Common\ScenarioBaseConnect.cs`
- `TestAuto.Connect\Scenarios\ConnectStrategyPollingScenario.cs` (RAW read, ~133-146)
- `TestAuto.Records\Configuration\RecordsCustomParms.cs`
- `TestAuto.Records\Common\ScenarioBaseCrud.cs`
- `TestAuto.Records\Scenarios\CRUD\Creates\CreateRecordsByPageAndBatchScenario.cs`
- `TestAuto.Metadata\Scenarios\MetadataLoadScenario.cs`
- `TestAuto.Matching\Scenarios\MatchingResultsScenario.cs`
