---
name: custom-parm-editor
description: >
  Custom parameter UI editor architecture and creation guide for TestAuto scenario types. Use when adding new enum-based editors, creating UI editors for scenario parameters, reviewing editor routing, or implementing conditional visibility patterns.
---

Repo: speed-merchants (paths below are repo-relative)

# Custom Parameter Editor Patterns

> **Scope**: speed-merchants (TestAuto.Web)  
> **Purpose**: Reference for creating custom parameter UI editors for scenario types

---

## Overview

This agent specializes in creating custom parameter (CustomParms) editors for TestAuto scenario types. Each scenario can have a tailored UI editor that provides structured, validated input forms instead of raw JSON editing.

**Important Note**: The UI presentation layer (how editors are displayed - inline, popup, dialog, etc.) is separate from the editor components themselves. This agent focuses on building the **editor components** that render the parameter forms. Whether these editors appear in a popup, modal, or inline is handled by the parent pages (`ScenarioEditor`, `WorkflowScenariosEditor`, etc.) and does not affect the editor component implementation.

---

## When to Use This Skill

Use this skill when:
- A new scenario type requires a custom parameter editor
- An existing scenario's parameters are complex enough to warrant a structured UI
- User requests a new custom parm editor for a specific scenario
- A scenario has 10+ parameters that would benefit from organized sections

---

## Custom Parameter Editor Architecture

### Core Concepts

1. **ScenarioTypesAttribute** - Each scenario class is decorated with this attribute:
   ```csharp
   [ScenarioTypes(
       typeof(TestDataType),
       typeof(MetricDetailType),
       typeof(MetricSummaryType),
       RestSubjectArea.SubjectArea,
       DataPattern.Pattern,
       CustomParmsEditorType.EditorTypeName)]  // <-- Specifies which editor to use
   ```

2. **CustomParmsEditorType Enum** - Defines available editor types:
   - Location: `TestAuto.Shared/Common/Scenario/ScenarioTypesAttribute.cs`
   - Values: `Default`, `JsonOnly`, `UtilityScenarioEditor`, `MatchingSnapshotCapture`, `UnifiedMatchingScenario`, `MetadataManagementEditor`, `MatchingStrategyConfigEditor`, `UnifiedMatchingPostRunCollection`, `ConnectStrategyPolling`, `ConnectPostRunCollection` (authoritative list lives in `ScenarioTypesAttribute.cs`; see [[testauto-scenario-types-attribute]])

3. **ScenarioTypeRegistry** - Runtime lookup that maps scenario names to editor types:
   - Location: `TestAuto.Shared/Helpers/ScenarioTypeRegistry.cs`
   - Uses reflection to discover all `IScenario` implementations and their attributes

4. **CustomParmsEditorHost** - Central router that renders the correct editor:
   - Location: `TestAuto.Web/Components/Common/CustomParmsEditorHost.razor`
   - Takes `EditorType` parameter and routes to concrete editor component

5. **Concrete Editors** - Blazor components that provide the actual UI:
   - Location: `TestAuto.Web/Components/Controls/`
   - Examples:
     - `DefaultCustomParmsEditor.razor` - Grid + JSON editor
     - `UtilityScenarioEditor.razor` - Multi-step utility configuration
     - `UnifiedMatchingScenarioEditor.razor` - Organized matching parameters

### Data Flow

```
Scenario Class (with [ScenarioTypes] attribute)
    |
ScenarioTypeRegistry.GetCustomParmsEditorType(scenarioName)
    |
CustomParmsEditorHost (receives EditorType parameter)
    |
Switch statement routes to concrete editor component
    |
Concrete editor reads/writes Configuration.ScenarioRuntime.CustomParms
    |
Parent page saves to Profisee entity attribute (JSON serialized)
```

### Storage

- **Runtime**: `ScenarioConfiguration.ScenarioRuntime.CustomParms` (Dictionary<string, JToken>)
- **Persistence**: Profisee entity attribute `TestAutoScenarios.CustomParms` (JSON string)
- **Type**: Always `Dictionary<string, Newtonsoft.Json.Linq.JToken>` - values can be primitives, objects, or arrays

---

## Key Files and Locations

### Enum and Registry
- `TestAuto.Shared/Common/Scenario/ScenarioTypesAttribute.cs` - CustomParmsEditorType enum
- `TestAuto.Shared/Helpers/ScenarioTypeRegistry.cs` - Runtime type lookup

### Router
- `TestAuto.Web/Components/Common/CustomParmsEditorHost.razor` - Routing switch statement
- `TestAuto.Web/Components/Common/CustomParmsEditorHost.razor.cs` - Component logic

### Existing Editors (Examples to Study)
- `TestAuto.Web/Components/Controls/DefaultCustomParmsEditor.razor` - Default grid editor
- `TestAuto.Web/Components/Controls/JsonOnlyCustomParmsEditor.razor` - Raw JSON editor
- `TestAuto.Web/Components/Controls/UtilityScenarioEditor.razor` - Multi-step utility editor
- `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor` - Matching scenario editor
- `TestAuto.Web/Components/Controls/MatchingSnapshotCaptureEditor.razor` - Snapshot capture editor
- `TestAuto.Web/Components/Controls/ConnectStrategyPollingEditor.razor` - Connect strategy polling editor (enum: `ConnectStrategyPolling`, scenario: `ConnectStrategyPollingScenario`)
- `TestAuto.Web/Components/Controls/ConnectPostRunCollectionEditor.razor` - Connect post-run collection editor (enum: `ConnectPostRunCollection`, scenario: `ConnectPostRunCollectionScenario`)

### Supporting Components
- `TestAuto.Web/Components/Controls/JsonEditor.razor` - Reusable JSON text editor
- `TestAuto.Web/Components/Controls/ConfigurationSection.razor` - Collapsible section container
- `TestAuto.Web/Components/Controls/ObjectEditor.razor` - Inline JObject editor
- `TestAuto.Web/Components/Controls/ArrayEditor.razor` - Inline JArray editor
- `TestAuto.Web/Components/Controls/ContentSourceToggle.razor` - Reusable inline-vs-file content source switch (see note below)

---

## Steps to Create a New Custom Parm Editor

### Step 1: Add Enum Value

**File**: `TestAuto.Shared/Common/Scenario/ScenarioTypesAttribute.cs`

Add a new value to the `CustomParmsEditorType` enum:

```csharp
public enum CustomParmsEditorType
{
    Default,
    JsonOnly,
    UtilityScenarioEditor,
    MatchingSnapshotCapture,
    UnifiedMatchingScenario,
    YourNewEditorType  // <-- Add here with XML doc comment
}
```

### Step 2: Update ScenarioTypes Attribute

**File**: `{ScenarioProject}/Scenarios/{ScenarioClass}.cs`

Update or add the `[ScenarioTypes]` attribute on the scenario class:

```csharp
[ScenarioTypes(
    typeof(YourTestDataType),
    typeof(YourMetricDetailType),
    typeof(YourMetricSummaryType),
    RestSubjectArea.YourArea,
    DataPattern.Paged,
    CustomParmsEditorType.YourNewEditorType)]  // <-- Specify your editor
[ScenarioDisplay("YourScenario")]
public class YourScenario : ScenarioBase
{
    public override string ScenarioName { get; } = "YourScenario";
    // ...
}
```

### Step 3: Create the Editor Component

**File**: `TestAuto.Web/Components/Controls/YourNewEditor.razor`

Create the Blazor component with standard structure:

```razor
@*
    YourNewEditor - Structured CustomParms editor for YourScenario.
    Brief description of what this scenario configures.
*@

<div class="your-new-editor">
    <div class="alert alert-info mb-3" role="alert">
        <Icon Name="icon_name" Class="me-2" />
        <strong>Your Scenario Name</strong>
        <p class="mb-0 mt-1">
            Brief description and guidance for users.
        </p>
    </div>

    @* Section 1: Primary Settings *@
    <ConfigurationSection Title="Primary Settings" IsExpanded="true">
        <div class="row">
            <div class="col-md-6 mb-3">
                <label class="form-label">Parameter Name</label>
                <RadzenTextBox @bind-Value="@YourProperty" 
                               Style="width: 100%;"
                               Change="@(_ => SaveToConfiguration())" />
                <small class="text-muted">Help text for this parameter</small>
            </div>
        </div>
    </ConfigurationSection>

    @* JSON Preview *@
    <ConfigurationSection Title="JSON Preview" IsExpanded="false">
        <div class="alert alert-info mb-2">
            <Icon Name="info" Class="me-2" />
            <strong>Advanced:</strong> View or edit the generated CustomParms JSON directly.
        </div>
        <JsonEditor Title=""
                   JsonContent="@CustomParmsJson"
                   JsonContentChanged="@OnCustomParmsJsonChanged"
                   IsEditable="true"
                   Rows="15" />
    </ConfigurationSection>
</div>
```

### Step 4: Create the Code-Behind

**File**: `TestAuto.Web/Components/Controls/YourNewEditor.razor.cs`

```csharp
using Microsoft.AspNetCore.Components;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;
using TestAuto.Shared.Scenarios.Configuration.Scenario;

namespace TestAuto.Web.Components.Controls;

public partial class YourNewEditor : ComponentBase
{
    [Parameter, EditorRequired]
    public ScenarioConfiguration Configuration { get; set; } = default!;

    [Parameter]
    public EventCallback<ScenarioConfiguration> ConfigurationChanged { get; set; }

    private string YourProperty { get; set; } = string.Empty;
    private string CustomParmsJson { get; set; } = string.Empty;

    protected override void OnInitialized()
    {
        LoadFromConfiguration();
    }

    private void LoadFromConfiguration()
    {
        if (Configuration?.ScenarioRuntime?.CustomParms == null) return;
        var parms = Configuration.ScenarioRuntime.CustomParms;

        YourProperty = parms.TryGetValue("YourProperty", out var val) 
            ? val?.ToString() ?? string.Empty 
            : string.Empty;

        CustomParmsJson = JsonConvert.SerializeObject(parms, Formatting.Indented);
    }

    private async Task SaveToConfiguration()
    {
        if (Configuration?.ScenarioRuntime?.CustomParms == null)
        {
            if (Configuration?.ScenarioRuntime != null)
                Configuration.ScenarioRuntime.CustomParms = new Dictionary<string, JToken>();
            else return;
        }
        var parms = Configuration.ScenarioRuntime.CustomParms;
        parms["YourProperty"] = YourProperty;
        CustomParmsJson = JsonConvert.SerializeObject(parms, Formatting.Indented);
        await ConfigurationChanged.InvokeAsync(Configuration);
    }

    private async Task OnCustomParmsJsonChanged(string newContent)
    {
        try
        {
            CustomParmsJson = newContent;
            if (string.IsNullOrWhiteSpace(newContent))
                Configuration.ScenarioRuntime!.CustomParms = new Dictionary<string, JToken>();
            else
            {
                var dict = JsonConvert.DeserializeObject<Dictionary<string, JToken>>(newContent);
                Configuration.ScenarioRuntime!.CustomParms = dict ?? new Dictionary<string, JToken>();
            }
            LoadFromConfiguration();
            await ConfigurationChanged.InvokeAsync(Configuration);
        }
        catch (JsonException) { /* Invalid JSON - don't update */ }
    }
}
```

### Step 5: Update CustomParmsEditorHost Router

**File**: `TestAuto.Web/Components/Common/CustomParmsEditorHost.razor`

Add a new case to the switch statement:

```razor
@switch (ActiveEditorType)
{
    case CustomParmsEditorType.JsonOnly:
        <JsonOnlyCustomParmsEditor Configuration="@ScenarioConfig"
                                   ConfigurationChanged="@ConfigurationChanged" />
        break;

    case CustomParmsEditorType.YourNewEditorType:  // <-- Add your case
        <YourNewEditor Configuration="@ScenarioConfig"
                      ConfigurationChanged="@ConfigurationChanged" />
        break;

    case CustomParmsEditorType.Default:
    default:
        <DefaultCustomParmsEditor Configuration="@ScenarioConfig"
                                  ConfigurationChanged="@ConfigurationChanged" />
        break;
}
```

### Step 6: Build and Test

1. **Build the solution**:
   ```bash
   dotnet build TestAuto.Web/TestAuto.Web.csproj
   ```

2. **Test the editor**:
   - Navigate to Scenario Editor page
   - Select or create a scenario of your type
   - Verify the custom editor appears
   - Test all UI controls and validation
   - Verify JSON preview stays in sync

---

## Design Patterns and Best Practices

### 1. ConfigurationSection Pattern

Use `ConfigurationSection` component for collapsible sections:

```razor
<ConfigurationSection Title="Section Name" IsExpanded="true">
    <!-- Your form fields here -->
</ConfigurationSection>
```

### 2. Two-Way Data Binding

Always use two-way binding with save callback:

```razor
<RadzenTextBox @bind-Value="@YourProperty" 
               Change="@(_ => SaveToConfiguration())" />
```

### 3. Type-Safe Property Extraction

```csharp
private T GetCustomParam<T>(string key, T defaultValue)
{
    if (Configuration?.ScenarioRuntime?.CustomParms?.TryGetValue(key, out var token) == true)
    {
        try { return token.ToObject<T>() ?? defaultValue; }
        catch { return defaultValue; }
    }
    return defaultValue;
}
```

### 4. JSON Preview Integration

Always include a JSON preview section at the bottom.

### 5. Inline Help Text

Provide contextual help for every parameter:

```razor
<label class="form-label">Parameter Name</label>
<RadzenTextBox @bind-Value="@YourProperty" />
<small class="text-muted">Brief explanation of what this parameter does</small>
```

### 6. Validation Feedback

Show validation warnings inline:

```razor
@if (TotalPercent != 100)
{
    <div class="alert alert-warning">
        Percentages should total 100% (currently @TotalPercent%)
    </div>
}
```

### 7. Approved Icons

Only use Material Symbols icons from the approved list:
- Navigation: `home`, `dashboard`, `menu`, `settings`
- Actions: `add`, `edit`, `delete`, `save`, `refresh`
- Data: `table_chart`, `storage`, `folder`, `dataset`
- Status: `check_circle`, `warning`, `error`, `info`

---

## Common Parameter Types

### String Parameters
```csharp
private string ParameterName { get; set; } = string.Empty;
// <RadzenTextBox @bind-Value="@ParameterName" Change="@(_ => SaveToConfiguration())" />
```

### Integer Parameters
```csharp
private int ParameterName { get; set; } = 0;
// <RadzenNumeric TValue="int" @bind-Value="@ParameterName" Min="0" Max="100" Change="@(_ => SaveToConfiguration())" />
```

### Boolean Parameters
```csharp
private bool ParameterName { get; set; } = false;
// <RadzenCheckBox @bind-Value="@ParameterName" TValue="bool" Change="@(_ => SaveToConfiguration())" />
```

### Dropdown Parameters
```csharp
private string SelectedOption { get; set; } = "Option1";
private List<string> Options = new() { "Option1", "Option2", "Option3" };
// <RadzenDropDown TValue="string" @bind-Value="@SelectedOption" Data="@Options" Change="@(_ => SaveToConfiguration())" />
```

---

## Testing Checklist

Before considering a new editor complete:

- [ ] Enum value added to `CustomParmsEditorType`
- [ ] Scenario class updated with correct `[ScenarioTypes]` attribute
- [ ] Editor component created (`.razor` and `.razor.cs`)
- [ ] Router updated in `CustomParmsEditorHost.razor`
- [ ] Solution builds without errors
- [ ] Editor appears when scenario is selected
- [ ] All form controls function correctly
- [ ] Changes persist when saving scenario
- [ ] JSON preview stays in sync with UI
- [ ] Structured <-> JSON switching works (if enabled)
- [ ] Validation messages appear when appropriate
- [ ] Help text is clear and accurate
- [ ] Icons are from approved Material Symbols list
- [ ] Code follows TestAuto coding standards

---

## Troubleshooting

### Editor Doesn't Appear

1. Check `ScenarioTypeRegistry` is finding your scenario
2. Check `CustomParmsEditorHost` routing
3. Check component registration (verify namespace)

### Changes Don't Save

1. Verify `ConfigurationChanged` callback is invoked
2. Check `CustomParms` dictionary is not null
3. Check parent page saves

### JSON Preview Out of Sync

1. Update JSON in both directions:
   - `LoadFromConfiguration()` -> Update `CustomParmsJson`
   - `SaveToConfiguration()` -> Update `CustomParmsJson`
   - `OnCustomParmsJsonChanged()` -> Update properties, reload UI

---

## Advanced Pattern: Multi-Step Editor (UtilityScenarioEditor Pattern)

When your scenario needs to manage a collection of heterogeneous items (like steps, rules, or stages), follow the `UtilityScenarioEditor` pattern:

### Architecture

```
UtilityScenarioEditor (main editor)
  +-- Global Parameters (simple key-value dictionary)
  +-- Steps Collection (List<UtilityStepBase>)
  |   +-- UtilityStepEditorCard          <-- shared chrome wrapper around every step
  |       +-- CommandLineStep  -> CommandLineStepEditorCard
  |       +-- SqlStep          -> SqlStepEditorCard
  |       +-- PowerShellStep   -> PowerShellStepEditorCard
  |       +-- CLUStep          -> CLUStepEditorCard
  |       +-- HttpRequestStep  -> HttpRequestStepEditorCard   (Parameter name is CurlStep)
  |       +-- MonitorStep      -> MonitorStepEditorCard
  |       +-- ConnExStep       -> ConnExStepEditorCard        (+ a per-step "Validate" action
  |                                                             calling ValidateConnExStepAsync)
  +-- JSON Preview
```

All **seven** step types are dispatched by a `step is XxxStep` type-test chain in `UtilityScenarioEditor.razor` — there is no registry or dictionary. `ConnExStep` and `MonitorStep` are full members of that chain, not special cases. Add a new branch there whenever you add a step type, or the step renders with no type-specific editor.

### When to Use This Pattern

Use the UtilityScenarioEditor pattern when:
- Your scenario has a collection of heterogeneous items (different types)
- Each item type needs its own specialized UI

---

## Runtime CustomParms Access Helpers

When reading `CustomParms` at scenario runtime (in the scenario class, not in the UI editor), use `CustomParmHelper` for type-safe access.

### Flat key access (built-in)

```csharp
// Dictionary<string, JToken>
if (customParms.TryGetValue("MyKey", out var token))
{
    var value = token.Value<string>();
}
```

### Nested JObject access — `GetCustomObject`

```csharp
public static class CustomParmHelper
{
    public static JObject? GetCustomObject(IDictionary<string, JToken> customParms, string key)
    {
        if (customParms.TryGetValue(key, out var token) && token is JObject obj)
            return obj;
        return null;
    }
}
```

Usage:

```csharp
var settings = CustomParmHelper.GetCustomObject(customParms, "DataMutationSettings");
if (settings != null)
{
    var ruleDefinitions = settings["RuleDefinitions"] as JObject;
    var attributeGroups = settings["AttributeGroups"] as JObject;
}
```

### Manual nested access (inline)

```csharp
if (customParms.TryGetValue("DataMutationSettings", out var token)
    && token is JObject dataMutationSettings)
{
    var firstNameRules = dataMutationSettings["RuleDefinitions"]?["FirstName"]?["Rules"] as JArray;
    var nameGroup      = dataMutationSettings["AttributeGroups"]?["NameGroup"] as JArray;
}
```

### Strongly-typed deserialization

Define C# classes and deserialize for type safety:

```csharp
public class DataMutationSettings
{
    public Dictionary<string, RuleDefinition> RuleDefinitions { get; set; }
    public Dictionary<string, List<string>> AttributeGroups { get; set; }
}

public class RuleDefinition
{
    public List<int> Rules { get; set; }
    public List<double> Weights { get; set; }
    public bool ApplyMoreThanASingleRule { get; set; }
}

// Usage:
var settings = customParms["DataMutationSettings"].ToObject<DataMutationSettings>();
```

### Decision guide

| Scenario | Approach |
|---|---|
| Flat single value | `customParms["Key"].Value<T>()` |
| Nested object, few fields | Manual `JObject` access |
| Nested object, used repeatedly | `GetCustomObject` helper |
| Complex nested structure | Strongly-typed deserialization |

**Source**: `TestAuto\Documentation\ParmHelper.md`
- Items can be added, removed, or reordered
- You want to provide a wizard-like experience for building complex configurations

---

## Examples to Study

### Simple Editor: JsonOnlyCustomParmsEditor
Location: `TestAuto.Web/Components/Controls/JsonOnlyCustomParmsEditor.razor`
Simplest possible editor - just a JSON text area.

### Intermediate Editor: MatchingSnapshotCaptureEditor
Location: `TestAuto.Web/Components/Controls/MatchingSnapshotCaptureEditor.razor`
Demonstrates multiple form fields, step reference linking, inline validation.

### Complex Editor: UtilityScenarioEditor (RECOMMENDED EXAMPLE)
Location: `TestAuto.Web/Components/Controls/UtilityScenarioEditor.razor`
**Best example to study** - demonstrates multi-step configuration, type-specific sub-editors, modal dialogs, global parameters, collapsible sections, step reordering, token replacement preview, inline execution, JSON preview integration.

### Enterprise Editor: UnifiedMatchingScenarioEditor
Location: `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor`
Demonstrates 50+ parameters organized into sections, conditional sections, computed validations, complex data types.

---

---

## Advanced Pattern: Conditional Section Visibility

When an editor has 10+ parameters that only apply to certain configurations, use computed boolean properties to show/hide sections. This pattern comes from `UnifiedMatchingScenarioEditor` (50+ parameters, 12 conditional sections).

### Computed Visibility Properties

```csharp
// Derive from primary settings — don't store separate "visible" flags
private bool IsBatchMode => OperationType == "BatchLoad";
private bool IsLookupMode => OperationType is "LookupOnly" or "LookupThenCreate";
private bool IsMixed => RecordSource == "Mixed";
private bool ShowRecordMix => IsMixed && (IsBatchMode || IsLookupThenCreate);
```

### Section Visibility in Razor

```razor
@if (IsBatchMode && IsMixed)
{
    <ConfigurationSection Title="Record Mix" IsExpanded="true">
        <!-- only renders for the relevant scenario variant -->
    </ConfigurationSection>
}
```

**Key rule**: Properties that are hidden still get saved by `SaveToConfiguration()`. Switching scenario variants back does not lose previously entered values.

---

## Advanced Pattern: Scenario Templates

When an editor supports multiple named variants, provide quick-start templates:

```csharp
private void ApplyScenarioTemplate(string template)
{
    switch (template)
    {
        case "Scenario1":
            OperationType = "BatchLoad";
            RecordSource = "NewOnly";
            ExpectEmptyModel = true;
            break;
        case "Custom":
        default:
            // no-op — user has diverged from preset
            break;
    }
    SelectedScenarioTemplate = template;
    _ = SaveToConfiguration();
}
```

**Rule**: Manually changing `OperationType` or `RecordSource` should reset the template label to "Custom" to prevent stale labels when the user diverges from preset values.

---

## Advanced Pattern: Validation Warnings

Show inline validation warnings at render time (not just on save):

```csharp
private List<string> GetValidationWarnings()
{
    var warnings = new List<string>();
    if (ChangedPercent + NewPercent != 100)
        warnings.Add($"Percentages total {ChangedPercent + NewPercent}% — should be 100%");
    if (SleepMinMs > SleepMaxMs && SleepMaxMs > 0)
        warnings.Add("Sleep min is greater than sleep max");
    if (IsLookupMode && string.IsNullOrWhiteSpace(MatchingStrategyName))
        warnings.Add("Matching Strategy Name is required for lookup scenarios");
    return warnings;
}
```

In Razor:

```razor
@{
    var warnings = GetValidationWarnings();
}
@if (warnings.Count > 0)
{
    <div class="alert alert-warning">
        @foreach (var w in warnings) { <div>⚠ @w</div> }
    </div>
}
```

---

## Advanced Pattern: Dead / Partially-Dead Parameters

Document parameters that exist in CustomParms but have no runtime effect. Mark them clearly in the editor to prevent confusion:

```razor
@* Dead code — kept for potential future use (RecycleMode) *@
<small class="text-muted">Note: Currently only "WarnAndStop" behavior is implemented.</small>
```

Keep dead parameters in the editor only if they may be activated in a future scenario variant. Remove them if they are permanently unused.

---

## Enterprise Editor Reference: UnifiedMatchingScenarioEditor

The largest custom parms editor in the codebase. Study it for:
- 50+ parameters organized into 12 conditional sections
- Template system with 6 scenario variants
- Bidirectional JSON preview
- Inline validation for complex cross-field constraints (percentages must total 100%)
- Dead-code documentation pattern

**Location**: `TestAuto.Web/Components/Controls/UnifiedMatchingScenarioEditor.razor` + `.razor.cs`

---

## Pattern: Internal Static Constants Mirror (Plugin Scenarios)

When the scenario lives in a **plugin assembly that TestAuto.Web does not reference** (e.g. TestAuto.Connect), the editor cannot use the scenario project's key constants directly. Instead, the editor file declares an `internal static class ...Constants` that mirrors the runtime key names and defaults:

```csharp
/// <summary>
/// CustomParms keys/defaults for ConnectPostRunCollectionScenario.
/// Mirrors TestAuto.Connect.Configuration.ConnectCustomParms to avoid a cross-project dependency
/// (TestAuto.Web does not reference the TestAuto.Connect plugin assembly).
/// </summary>
internal static class ConnectPostRunConstants
{
    public const string StrategyName = "StrategyName";
    public const string RunProfileCode = "RunProfileCode";
    // ...
    public const int DefaultMaxBatchAgeMinutes = 60;
    public const int DefaultJobPageSize = 1000;
    public const int DefaultConcurrentThreads = 4;
}
```

### Real examples

- `ConnectPostRunConstants` — bottom of `ConnectPostRunCollectionEditor.razor.cs` (~lines 224-236). Mirrors key names from `TestAuto.Connect/Configuration/ConnectCustomParms.cs` and defaults from `ConnectPostRunCollectionScenario` (MaxBatchAge 60, JobPageSize 1000, ConcurrentThreads 4).
- `ConnectPollingConstants` — bottom of `ConnectStrategyPollingEditor.razor.cs` (~lines 178-191). Mirrors `ConnectStrategyPollingScenario` defaults (PollInterval 30s, MaxWait 720 min).

### Trade-off

| Pro | Con |
|---|---|
| TestAuto.Web stays decoupled from the plugin assembly (Connect remains a runtime-loaded plugin) | Key names and default values must be kept **in sync manually** — a rename in `ConnectCustomParms` or a default change in the scenario silently desyncs the editor |

**Rule**: when changing a CustomParms key or default in a plugin scenario, grep TestAuto.Web for the mirroring `...Constants` class and update it in the same change. The editors also mirror the scenario's runtime *validation* ranges (e.g. `ParsePostRunParms` / `ParsePollingParms`) in `GetValidationWarnings()` — keep those in sync too.

---

## Supporting Component: ContentSourceToggle

`TestAuto.Web/Components/Controls/ContentSourceToggle.razor` is a small reusable toggle for editors that let the user choose between **inline content and file-based content** (e.g. inline script vs. ScriptKey/file). It renders a labeled `RadzenSwitch` with optional icons on each side.

Parameters: `Title`, `InlineLabel`, `FileLabel` (required), `InlineIcon`, `FileIcon` (optional), `UseFile` (bool state), `OnToggleChanged` (`EventCallback<bool>`). Note it exposes a plain `UseFile` + `OnToggleChanged` callback pair, not `@bind-UseFile` two-way binding — the parent flips its own flag in the callback and calls its save method.

---

## Sources

- `TestAuto.Shared\Common\Scenario\ScenarioTypesAttribute.cs` — `CustomParmsEditorType` enum (incl. `ConnectStrategyPolling`, `ConnectPostRunCollection`)
- `TestAuto.Web\Components\Common\CustomParmsEditorHost.razor` — routing switch
- `TestAuto.Web\Components\Controls\ConnectPostRunCollectionEditor.razor.cs` — editor + `ConnectPostRunConstants`
- `TestAuto.Web\Components\Controls\ConnectStrategyPollingEditor.razor.cs` — editor + `ConnectPollingConstants`
- `TestAuto.Connect\Scenarios\ConnectPostRunCollectionScenario.cs` — `[ScenarioTypes(... CustomParmsEditorType.ConnectPostRunCollection)]`
- `TestAuto.Connect\Scenarios\ConnectStrategyPollingScenario.cs` — `[ScenarioTypes(... CustomParmsEditorType.ConnectStrategyPolling)]`
- `TestAuto.Connect\Configuration\ConnectCustomParms.cs` — runtime CustomParms key constants mirrored by the editors
- `TestAuto.Web\Components\Controls\ContentSourceToggle.razor` — inline-vs-file toggle component
- `TestAuto\Documentation\ParmHelper.md` — runtime CustomParms access helpers

---

## Related Documentation

- **Approved Icons**: `blazor-icons` skill
- **UI dialog patterns**: `testauto-ui-patterns` skill (dialog sizing, popup-not-inline rule)
- **Blazor Standards**: Cross-repo Blazor coding standards
- **Radzen Components**: https://blazor.radzen.com/
