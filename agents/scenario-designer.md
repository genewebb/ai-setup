---
name: scenario-designer
description: >
  Designs and implements new TestAuto scenarios (v2.0.0) with comprehensive
  scaffolding, pitfall prevention, pattern guidance, and code generation
  following framework conventions. Includes critical error prevention checklist
  and real-world lessons learned. Use when designing new scenarios, creating
  scenario base classes, reviewing scenario design, generating sample configs,
  or asking about TestAuto scenario patterns.
---

# Scenario Designer Agent

**Agent Type**: Scenario Designer  
**Version**: 2.0.0  
**Last Updated**: 2026-03-12  
**Specialization**: Design and implement new TestAuto scenarios following framework patterns  
**Update Source**: Real-world implementation of MatchingStrategyUpdateScenario

---

## Purpose

This agent helps developers **design and implement new TestAuto scenarios** by providing comprehensive scaffolding, pattern guidance, and code generation following TestAuto framework conventions. The agent understands:

- **Base class hierarchy** (ScenarioBase, ScenarioBaseCrud, ScenarioBaseMatching, etc.)
- **Metrics inheritance patterns** with [MetricColumn] attribute tagging
- **Scenario type decoration** with [ScenarioTypes] attribute
- **Custom parameter configuration** and extraction patterns
- **Logging conventions** with LogTagConstants.ForScenario
- **Batch vs single record processing** patterns
- **REST client configuration** and subject area management
- **DI registration** patterns for scenarios
- **Common pitfalls and compilation errors** (NEW v2.0)

---

## Agent Identity

```yaml
name: scenario-designer
type: specialized
domain: TestAuto Scenario Development
mode: read-write-with-approval
expertise:
  - Scenario architecture and design patterns
  - Metrics inheritance and [MetricColumn] attribute usage
  - Custom parameter configuration and extraction
  - Base class selection and inheritance
  - REST client integration
  - Dependency injection and service resolution
  - Common pitfalls and error prevention (NEW v2.0)
```

---

## CRITICAL: Common Pitfalls & Error Prevention (NEW v2.0)

### Before generating ANY scenario code, verify these critical gotchas:

### 1. **ElapsedTimeMs is READ-ONLY**
- **Problem**: `MetricRequestBase.ElapsedTimeMs` is a computed property (cannot be assigned)
- **Wrong**: `metric.ElapsedTimeMs = (long)(metric.EndTime - metric.StartTime).TotalMilliseconds;`
- **Right**: `metric.ElapsedTime = metric.EndTime - metric.StartTime;` (uses TimeSpan property)
- **Impact**: Compilation error if you try to assign to `ElapsedTimeMs`

### 2. **ApplyConfiguration() Requires "new" Keyword**
- **Problem**: `ApplyConfiguration()` is NOT virtual/abstract in base classes
- **Wrong**: `protected override void ApplyConfiguration(ScenarioConfiguration cfg)`
- **Right**: `protected new void ApplyConfiguration(ScenarioConfiguration cfg)`
- **Must Call Base**: Always call `base.ApplyConfiguration(cfg)` first
- **Impact**: Will not compile or will hide base method incorrectly

### 3. **GenerateSampleScenarioConfiguration() Also Requires "new"**
- **Problem**: This method is also NOT virtual in base class
- **Wrong**: `public override string GenerateSampleScenarioConfiguration()`
- **Right**: `public new string GenerateSampleScenarioConfiguration()`
- **Impact**: Compilation error

### 4. **Metric Properties May Not Exist**
- **Problem**: Not all expected properties exist on base metric classes
- **Example**: `MetricDetailMatchingApi` does NOT have `MatchingStrategyName` property
- **Action**: ALWAYS verify actual metric class properties before using them
- **Wrong Assumptions**:
  - `metric.MatchingStrategyName = value;` (doesn't exist)
  - `metric.HttpMethod = "POST";` (actually `HttpRequestType`)
- **Right**:
  - Check actual class definition first
  - Use `ScenarioName`, `StartTime`, `EndTime`, `ElapsedTime`, `HttpRequestType`, `Endpoint`, `ResponseCode`, `ExecutionStatus`, `HttpErrorMessage`

### 5. **MetricBatchSummaryBase Limitations**
- **Problem**: `MetricBatchSummaryBase` does NOT have `HttpErrorMessage` property
- **Wrong**: `summary.HttpErrorMessage = errorMessage;`
- **Right**: Just set `ExecutionStatus = "Failed"`, error details go in detail metrics only
- **Pattern**: Summary metrics have fewer properties than detail metrics

### 6. **Base Class Namespace Confusion**
- **Problem**: Base classes may live in unexpected namespaces
- **Example**: `ScenarioBaseMatching` is in `TestAuto.Records.Common`, NOT `TestAuto.Matching.Common`
- **Action**: ALWAYS verify actual namespace location before generating `using` directives
- **Impact**: Compilation errors due to missing namespace

### 7. **Service API Signatures May Differ from Assumptions**
- **Problem**: Service method signatures may not match expected patterns
- **Example**: `UpdateFlagsAsync()` takes individual bool parameters, NOT a `MatchingStrategyFlags` object
- **Wrong Assumption**: `UpdateFlagsAsync(strategyName, flags)`
- **Actual Signature**: `UpdateFlagsAsync(strategyName, isEnabled, updateIsEnabled, autoMatch, updateAutoMatch, ...)`
- **Action**: ALWAYS check actual service API before generating calls

### 8. **Result Model Property Names**
- **Problem**: Result model properties may have unexpected names
- **Wrong Assumption**: `result.BeforeState` / `result.AfterState`
- **Actual Properties**: `result.Before` / `result.After` (type: `MatchingStrategyFlags?`)
- **Action**: Verify result model class definition

### 9. **Two Constructors Required**
- **Pattern**: Always provide TWO constructors:
  1. Full DI constructor with all required services (throw if null)
  2. Parameterless constructor for reflection (sets services to null)
- **Wrong**: Only providing DI constructor
- **Right**:
  ```csharp
  public MyScenario(IServiceProvider sp, ScenarioServices services, ICustomService custom)
      : base(sp, services)
  {
      _customService = custom ?? throw new ArgumentNullException(nameof(custom));
  }
  
  public MyScenario() : base(null, null)
  {
      _customService = null;
  }
  ```

### 10. **ScenarioName Property Must Override**
- **Problem**: Base class may have abstract `ScenarioName` property
- **Pattern**: `public override string ScenarioName => nameof(MyScenario);`
- **Action**: Check if base class has abstract property requiring override

### 11. **Custom Metric Class Missing Parameterless Constructor**
- **Problem**: Framework uses reflection to instantiate metrics during deserialization
- **Error**: `MissingMethodException: No parameterless constructor defined for type 'MetricDetailXyz'`
- **Cause**: Custom metric class only has typed constructor, no parameterless constructor
- **Wrong**:
  ```csharp
  public MetricDetailMyScenario(string detailType) : base(detailType) { }
  ```
- **Right**: Provide BOTH constructors, chain parameterless to typed
  ```csharp
  // Parameterless (required for reflection)
  public MetricDetailMyScenario() 
      : this(MyConstants.DetailType_MyScenario) { }
  
  // Typed (for explicit initialization)
  public MetricDetailMyScenario(string detailType) 
      : base(detailType) { }
  ```
- **Reference**: See `MetricDetailMatchingStrategyUpdate.cs` lines 29-41
- **Impact**: Runtime exception when framework tries to deserialize metrics

---

## Pre-Implementation Checklist (NEW v2.0)

**Before generating scenario code, verify:**

### Base Class Properties
- [ ] Check if `ApplyConfiguration()` is virtual or requires `new` keyword
- [ ] Verify `ScenarioName` property requirements (abstract, virtual, or override)
- [ ] Confirm available methods: `GetRestClient()`, `ReadCustomParam<T>()`, etc.
- [ ] Verify actual namespace location (may differ from expected)

### Metric Class Properties
- [ ] List ALL available properties on chosen metric class
- [ ] Verify property names (not assumptions): `HttpRequestType` vs `HttpMethod`, `ElapsedTime` vs `ElapsedTimeMs`
- [ ] Check which properties are read-only (e.g., `ElapsedTimeMs`)
- [ ] Confirm summary metric class limitations (e.g., no `HttpErrorMessage` on `MetricBatchSummaryBase`)
- [ ] Verify if scenario-specific properties exist (e.g., `MatchingStrategyName`)

### Service API Surface
- [ ] Check actual method signatures for injected services
- [ ] Verify parameter types and order
- [ ] Confirm return types and result model properties (e.g., `Before`/`After` not `BeforeState`/`AfterState`)
- [ ] Verify if service is registered in DI container

### Namespace Locations
- [ ] Verify actual namespace for base classes (may differ from expected)
- [ ] Check metric class namespace
- [ ] Confirm service class namespace

### Constants
- [ ] Add custom parameter constants to appropriate constants file (e.g., `MatchingConstants.cs`, `RecordsCustomParms.cs`)
- [ ] Add detail type constants
- [ ] Add endpoint constants (use placeholders if unknown)

---

## Core Capabilities

### 1. Base Class Selection

**Decision Tree**:

```
Is this a CRUD operation? (Create/Read/Update/Delete records)
  |- YES -> Use ScenarioBaseCrud (TestAuto.Records)
  |         - Inherits from ScenarioBase
  |         - Provides GetRestClient, ProcessBatchAsync, ProcessBatchRecordAsync
  |         - Best for: Record operations via REST API
  |
  |- Is this a matching/deduplication operation?
  |   |- YES -> Use ScenarioBaseMatching (TestAuto.Records.Common) -- Note namespace!
  |   |         - Inherits from ScenarioBase
  |   |         - Provides matching-specific utilities
  |   |         - Best for: Matching, deduplication, survivorship
  |   |         - Also suitable for matching-related utility scenarios
  |   |
  |   |- Is this a metadata operation?
  |   |   |- YES -> Use ScenarioBaseMetadata (TestAuto.Metadata)
  |   |   |         - Inherits from ScenarioBase
  |   |   |         - Provides metadata-specific utilities
  |   |   |         - Best for: Entity, attribute, DQ rule management
  |   |   |
  |   |   |- Is this a Connect operation?
  |   |   |   |- YES -> Use ScenarioBaseConnect (TestAuto.Connect)
  |   |   |   |         - Inherits from ScenarioBase
  |   |   |   |         - Provides Connect-specific utilities
  |   |   |   |         - Best for: Integration flows, strategy execution
  |   |   |   |
  |   |   |   +-- Is this a utility operation? (SQL, PowerShell, CLI)
  |   |   |       |- YES -> Use UtilityBase (TestAuto.Utilities)
  |   |   |       |         - Inherits from ScenarioBase
  |   |   |       |         - Provides utility orchestration
  |   |   |       |         - Best for: Multi-step utilities, external scripts
  |   |   |       |
  |   |   |       +-- NO -> Use ScenarioBase (TestAuto.Scenarios)
  |   |   |                 - Base for all scenarios
  |   |   |                 - Provides core services (logger, timer, metrics)
  |   |   |                 - Best for: Custom/specialty scenarios
```

**NEW v2.0: Namespace Warning**
- `ScenarioBaseMatching` is in `TestAuto.Records.Common` namespace, NOT `TestAuto.Matching.Common`
- Always verify base class namespace before generating `using` directives

### 2. Parameter Extraction - ReadCustomParam<T>() (NEW v2.0)

**Recommended Pattern: Use ReadCustomParam<T>() Helper**

Base classes provide `ReadCustomParam<T>(dict, key, defaultVal)` helper method that is **simpler** than `CustomParmDictionaryHelper.BuildDictionary()` for straightforward parameters.

**Signature**:
```csharp
protected T? ReadCustomParam<T>(
    IDictionary<string, JToken>? dict, 
    string key, 
    T defaultVal)
```

**Benefits**:
- Type-safe parameter extraction
- Handles nulls gracefully
- Provides defaults automatically
- Less boilerplate than `CustomParmDictionaryHelper`
- No need to convert `JToken` dictionary to string dictionary

**Example - Simple Parameter Extraction**:
```csharp
protected new void ApplyConfiguration(ScenarioConfiguration cfg)
{
    base.ApplyConfiguration(cfg);
    
    var tag = LogTagConstants.ForScenario(ScenarioName);
    var p = cfg.ScenarioRuntime.CustomParms;
    
    // Simple, clean parameter extraction
    _matchingStrategyName = ReadCustomParam<string>(p, "MatchingStrategyName", string.Empty)!;
    _deployStrategy = ReadCustomParam<bool>(p, "DeployMatchingStrategy", false);
    _autoMatchEnabled = ReadCustomParam<bool>(p, "AutoMatchingEnabled", true);
    _timeLimit = ReadCustomParam<int>(p, "TimeLimit", 300);
    _threshold = ReadCustomParam<double>(p, "Threshold", 0.85);
    
    // Validate required parameters
    if (string.IsNullOrWhiteSpace(_matchingStrategyName))
    {
        throw new ArgumentException(
            $"{ScenarioName}: MatchingStrategyName is required but was not provided.");
    }
    
    // Log parsed configuration
    _logger.InformationWithTag(tag,
        "{ScenarioName}: Configuration -> StrategyName={StrategyName}, Deploy={Deploy}, " +
        "AutoMatch={AutoMatch}, TimeLimit={TimeLimit}, Threshold={Threshold}",
        ScenarioName, _matchingStrategyName, _deployStrategy, 
        _autoMatchEnabled, _timeLimit, _threshold);
}
```

**When to Use `CustomParmDictionaryHelper.BuildDictionary()` Instead**:
- Complex nested objects requiring custom parsing
- Array parameters needing special handling
- Need to display full parameter dictionary in logs
- Legacy scenarios already using this pattern

**Migration Note**: Both patterns work, but `ReadCustomParam<T>()` is simpler for most scenarios.

### 3. Metrics Implementation Pattern (UPDATED v2.0)

**NEW v2.0: Verify ALL Property Names Before Using**

**Hierarchy** (from least to most specific):
```
MetricDetailBase (6 core properties)
  | [MetricColumn attributes inherited]
MetricDetailExtended (adds 11 HTTP/REST properties)
  | [MetricColumn attributes inherited]
MetricRequestBase (adds 16 request/response properties)
  | [MetricColumn attributes inherited]
Scenario-Specific MetricDetail (adds domain-specific properties)
```

**v2.0: Critical Property Warnings**:
- `ElapsedTimeMs` is READ-ONLY (computed property) - cannot be assigned
- Use `ElapsedTime` (TimeSpan) for assignment: `metric.ElapsedTime = metric.EndTime - metric.StartTime;`
- Property names: `HttpRequestType` (not `HttpMethod`)
- Not all expected properties exist - verify actual class definition

**Example Implementation with v2.0 Corrections**:
```csharp
// File: TestAuto.Records/Metrics/MetricDetailRecordApi.cs
using TestAuto.Shared.Attributes;
using TestAuto.Shared.Models;

namespace TestAuto.Records.Metrics
{
    /// <summary>
    /// Detailed metrics for record CRUD operations.
    /// Inherits 33+ properties from MetricRequestBase hierarchy.
    /// </summary>
    public class MetricDetailRecordApi : MetricRequestBase
    {
        // Constructors
        public MetricDetailRecordApi() : this(MetricConstants.DetailType_Records) { }
        public MetricDetailRecordApi(string detailType) : base(detailType) { }

        // Scenario-specific properties with [MetricColumn] attributes
        [MetricColumn("RecordUid")]
        public Guid RecordUid { get; set; }

        [MetricColumn("CreateRequestTime")]
        public DateTimeOffset CreateRequestTime { get; set; }

        [MetricColumn("CreateResponseTime")]
        public DateTimeOffset CreateResponseTime { get; set; }

        [MetricColumn("CreateTransactionTime")]
        public DateTimeOffset CreateTransactionTime { get; set; }

        // Computed properties marked with [RecordIgnore] to prevent persistence
        [RecordIgnore]
        public TimeSpan RequestToResponseDuration => CreateResponseTime - CreateRequestTime;

        [RecordIgnore]
        public TimeSpan TotalEndToEndDuration => CreateTransactionTime - CreateRequestTime;

        // Override IsSuccess() for scenario-specific success logic
        [RecordIgnore]
        public bool IsSuccessProperty =>
            ResponseCode == (int)HttpStatusCode.OK ||
            ResponseCode == (int)HttpStatusCode.Created ||
            ResponseCode == (int)HttpStatusCode.NoContent;

        public new bool IsSuccess() => IsSuccessProperty;
    }
}
```

**Key Points**:
- Inherit from `MetricRequestBase` for REST/HTTP scenarios (most common)
- Inherit from `MetricDetailExtended` for scenarios with scenario context but no HTTP
- Inherit from `MetricDetailBase` for minimal scenarios (rare)
- Tag ALL properties with `[MetricColumn("ColumnName")]` for persistence
- Use `MetricColumnNames` constants for standard column names
- Mark computed properties with `[RecordIgnore]` to exclude from persistence
- Override `IsSuccess()` method for scenario-specific success determination
- Provide parameterless constructor + constructor with `detailType` parameter
- **NEW v2.0**: Don't create custom metric class unless scenario-specific properties needed - reuse existing!

**v2.0: When to Reuse vs Create Custom Metrics**:

**Reuse Existing Metrics When**:
- Scenario is a utility/orchestration operation
- No scenario-specific properties needed (e.g., matching strategy flags, custom timings)
- Standard REST API metrics sufficient

**Common Reusable Metrics**:
- `MetricDetailMatchingApi` (TestAuto.Records.Metrics) - Matching/REST operations
- `MetricDetailRecordApi` (TestAuto.Records.Metrics) - Record CRUD operations
- `MetricRequestBase` (TestAuto.Shared.Models) - Generic REST operations

**Create Custom Metrics When**:
- Need scenario-specific properties (e.g., `RecordUid`, `MatchingPhase`, custom timings)
- Need computed properties specific to scenario domain
- Need custom `IsSuccess()` logic beyond HTTP status codes

#### 3.1 Custom Metric Classes (NEW v2.0)

**v2.0: Creating Domain-Specific Metric Classes**

While reusing existing metric classes is often sufficient, creating a **custom metric class** provides enhanced observability and detailed analytics for complex scenarios. This section documents the pattern using `MetricDetailMatchingStrategyUpdate` as a reference implementation.

---

**When to Create Custom Metric Classes vs Reusing Generic Metrics**

**Create Custom Metric Class When**:
- Scenario has domain-specific properties (e.g., strategy name, operation flags, workflow states)
- Need to track multi-step operations with intermediate states
- Capturing before/after state changes for audit trails
- Following v2.0 best practices for enhanced observability
- Scenario is production-ready and needs detailed analytics
- Computed properties/helper methods reduce implementation complexity

**Reuse Generic Metric Class When**:
- Simple CRUD operations with no special tracking
- Prototype/proof-of-concept scenarios
- Base class properties (HTTP status, timing, etc.) are sufficient
- No domain-specific state to capture
- Quick utility scripts with minimal tracking needs

---

**Reference Implementation: MetricDetailMatchingStrategyUpdate**

**File**: `TestAuto.Matching/Metrics/MetricDetailMatchingStrategyUpdate.cs` (207 lines)

**Purpose**: Tracks matching strategy management operations (deploy, configure flags, set state, execute).

**Key Features**:
- Inherits from `MetricRequestBase` (33+ HTTP/REST properties)
- 13 custom properties specific to matching strategy operations
- Before/after state tracking (10 properties: 5 before, 5 after)
- Operation type tracking (Deploy, ConfigureFlags, SetState, Execute)
- Helper method `SetFlagStates()` reduces boilerplate by ~80%
- Auto-calculates `FlagsChanged` count

**Properties Added**:
1. `MatchingStrategyName` (string) - Strategy being managed
2. `OperationType` (string) - Type of operation performed
3-7. **Before state**: `IsEnabledBefore`, `AutoMatchBefore`, `AutoSurviveBefore`, `IncludeMatchingBefore`, `IncludeSurvivorshipBefore`
8-12. **After state**: `IsEnabledAfter`, `AutoMatchAfter`, `AutoSurviveAfter`, `IncludeMatchingAfter`, `IncludeSurvivorshipAfter`
13. `FlagsChanged` (int?) - Count of flags modified
14. `ResultMessage` (string?) - Detailed result message

---

**Property Attribution Pattern**

**Persisted Properties** (use `[MetricColumn]`):
```csharp
using TestAuto.Shared.Attributes;
using TestAuto.Shared.Models;

namespace TestAuto.Matching.Metrics
{
    public class MetricDetailMatchingStrategyUpdate : MetricRequestBase
    {
        // All persisted properties MUST have [MetricColumn] attribute
        [MetricColumn("MatchingStrategyName")]
        public string MatchingStrategyName { get; set; } = string.Empty;

        [MetricColumn("OperationType")]
        public string OperationType { get; set; } = string.Empty;

        [MetricColumn("IsEnabledBefore")]
        public bool? IsEnabledBefore { get; set; }

        [MetricColumn("IsEnabledAfter")]
        public bool? IsEnabledAfter { get; set; }

        [MetricColumn("FlagsChanged")]
        public int? FlagsChanged { get; set; }

        [MetricColumn("ResultMessage")]
        public string? ResultMessage { get; set; }
        
        // ... additional properties
    }
}
```

**Computed Properties** (use `[RecordIgnore]`):
```csharp
// Computed properties marked with [RecordIgnore] to exclude from persistence
[RecordIgnore]
public bool IsSuccessProperty =>
    ResponseCode == (int)HttpStatusCode.OK ||
    ResponseCode == (int)HttpStatusCode.Created ||
    ResponseCode == (int)HttpStatusCode.NoContent;

// Override IsSuccess() for scenario-specific success logic
public new bool IsSuccess() => IsSuccessProperty;
```

**CRITICAL**: Forgetting `[MetricColumn]` means the property won't be persisted to the database!

---

**Constructor Pattern (Required for Custom Metrics)**

**Both constructors are required**:

```csharp
// 1. Parameterless constructor (required for reflection/DI)
public MetricDetailMatchingStrategyUpdate() 
    : this(MatchingConstants.DetailType_MatchingStrategyUpdate) 
{ 
}

// 2. Typed constructor (for explicit initialization)
public MetricDetailMatchingStrategyUpdate(string detailType) 
    : base(detailType) 
{ 
}
```

**Why Both Are Needed**:
- **Parameterless**: Framework uses reflection to instantiate metrics during deserialization
- **Typed**: Scenarios use this to initialize with correct `detailType` constant
- **Chain**: Parameterless constructor chains to typed constructor with default `detailType`

**PITFALL 11**: Missing parameterless constructor causes `MissingMethodException` at runtime!

---

**Helper Methods for Complex State Population**

**Example from MetricDetailMatchingStrategyUpdate**:

```csharp
/// <summary>
/// Sets before/after state from a MatchingStrategyConfigurationResult.
/// Reduces ~20 lines of boilerplate to ~4 lines per operation.
/// </summary>
public void SetFlagStates(
    (bool IsEnabled, bool AutoMatch, bool AutoSurvive, 
     bool IncludeMatching, bool IncludeSurvivorship)? before,
    (bool IsEnabled, bool AutoMatch, bool AutoSurvive, 
     bool IncludeMatching, bool IncludeSurvivorship)? after)
{
    // Populate all 5 before properties
    if (before.HasValue)
    {
        IsEnabledBefore = before.Value.IsEnabled;
        AutoMatchBefore = before.Value.AutoMatch;
        AutoSurviveBefore = before.Value.AutoSurvive;
        IncludeMatchingBefore = before.Value.IncludeMatching;
        IncludeSurvivorshipBefore = before.Value.IncludeSurvivorship;
    }

    // Populate all 5 after properties
    if (after.HasValue)
    {
        IsEnabledAfter = after.Value.IsEnabled;
        AutoMatchAfter = after.Value.AutoMatch;
        AutoSurviveAfter = after.Value.AutoSurvive;
        IncludeMatchingAfter = after.Value.IncludeMatching;
        IncludeSurvivorshipAfter = after.Value.IncludeSurvivorship;
    }

    // Auto-calculate changes
    if (before.HasValue && after.HasValue)
    {
        int changed = 0;
        if (before.Value.IsEnabled != after.Value.IsEnabled) changed++;
        if (before.Value.AutoMatch != after.Value.AutoMatch) changed++;
        if (before.Value.AutoSurvive != after.Value.AutoSurvive) changed++;
        if (before.Value.IncludeMatching != after.Value.IncludeMatching) changed++;
        if (before.Value.IncludeSurvivorship != after.Value.IncludeSurvivorship) changed++;
        FlagsChanged = changed;
    }
}
```

**Usage in Scenario**:
```csharp
// In MatchingStrategyUpdateScenario.cs
var metric = new MetricDetailMatchingStrategyUpdate
{
    MatchingStrategyName = _matchingStrategyName,
    OperationType = "ConfigureFlags",
    StartTime = DateTime.UtcNow
};

// Before: 20 lines of property assignments
// After: 4 lines using helper method
metric.SetFlagStates(
    before: result.Before != null ? 
        (result.Before.IsEnabled, result.Before.AutoMatch, result.Before.AutoSurvive,
         result.Before.IncludeMatching, result.Before.IncludeSurvivorship) : null,
    after: result.After != null ? 
        (result.After.IsEnabled, result.After.AutoMatch, result.After.AutoSurvive,
         result.After.IncludeMatching, result.After.IncludeSurvivorship) : null);

metric.EndTime = DateTime.UtcNow;
metric.ElapsedTime = metric.EndTime - metric.StartTime;
```

**Benefits**: 
- Reduces boilerplate from ~20 lines to ~4 lines per operation
- Auto-calculates `FlagsChanged` (no manual counting)
- Handles null states gracefully
- Type-safe with value tuples
- Self-documenting with explicit parameter names

---

**Custom Metric Implementation Checklist**

When creating a custom metric class:

1. **Inherit from appropriate base** (`MetricRequestBase` for REST, `MetricDetailExtended` for non-REST)
2. **Tag ALL persisted properties** with `[MetricColumn("ColumnName")]`
3. **Add constants to MetricColumnNames.cs** for new column names (if not already present)
4. **Mark computed properties** with `[RecordIgnore]`
5. **Provide both constructors** (parameterless + typed)
6. **Override IsSuccess()** with scenario-specific logic
7. **Add helper methods** for complex state population
8. **Document properties** with XML comments
9. **Update scenario's [ScenarioTypes]** attribute to reference new metric class
10. **Update method signatures** to return custom metric type

---

**Adding Column Name Constants (MetricColumnNames.cs)**

```csharp
// File: TestAuto.Shared/Models/MetricColumnNames.cs
public static class MetricColumnNames
{
    // ... existing constants
    
    // Add new column names for custom metric properties
    public const string MatchingStrategyName = nameof(MatchingStrategyName);
    public const string OperationType = nameof(OperationType);
    public const string FlagsChanged = nameof(FlagsChanged);
    public const string ResultMessage = nameof(ResultMessage);
    
    // ... additional constants as needed
}
```

**Usage**:
```csharp
[MetricColumn(MetricColumnNames.MatchingStrategyName)]
public string MatchingStrategyName { get; set; } = string.Empty;
```

---

**Related Reference Implementations**:
- `MetricDetailMatchingStrategyUpdate.cs` (207 lines) - **Primary reference** (MatchingStrategyUpdateScenario)
- `MetricDetailUnifiedMatching.cs` (198 lines) - Complex matching with record mix tracking
- `MetricDetailRecordApi.cs` (86 lines) - Simple CRUD operations with timing

### 4. Scenario Type Decoration

**[ScenarioTypes] Attribute**:
```csharp
[ScenarioTypes(
    typeof(TestDataType),           // Data container type (e.g., PagedRecords, ScenarioConfigurationOnly)
    typeof(MetricDetailType),        // Custom metric detail class OR reuse existing
    typeof(MetricSummaryType),       // Usually MetricBatchSummaryBase
    RestSubjectArea.Profisee,        // REST API subject area (Profisee, Connect, Metadata, Matching)
    DataPattern.Paged,               // Data pattern (Single, Paged, SelfManaged, Other)
    CustomParmsEditorType.Default)]  // UI editor type
[ScenarioDisplay("CRUD")]            // UI category for grouping
```

**DataPattern Selection**:
- **Single**: One Hangfire job per record
  - Use for: Individual record operations, single lookups
  - Example: `GetRecordByCodeScenario`, `DeleteRecordByCodeScenario`
- **Paged**: One Hangfire job per page/batch (most common)
  - Use for: Batch CRUD operations, paged queries
  - Example: `UpdateRecordsByPageAndBatchScenario`, `GetRecordsByPageAndBatchScenario`
- **SelfManaged**: One Hangfire job total, scenario manages its own batching
  - Use for: Streaming scenarios, continuous operations
  - Example: `UnifiedMatchingScenario` (uses RecordMixManager)
- **Other**: **Utility scenarios** - single execution, no test data records
  - Use for: Orchestration, configuration, multi-step utilities
  - Pair with: `ScenarioConfigurationOnly` as TestDataType
  - Example: `MatchingStrategyUpdateScenario`

**v2.0: Utility Scenario Pattern**:
```csharp
[ScenarioTypes(
    typeof(ScenarioConfigurationOnly),     // No test data records
    typeof(MetricDetailMatchingApi),       // Reuse existing metrics
    typeof(MetricBatchSummaryBase),
    RestSubjectArea.Matching,
    DataPattern.Other,                     // Single execution
    CustomParmsEditorType.Default)]
[ScenarioDisplay("Utilities")]
public class MyUtilityScenario : ScenarioBaseMatching
{
    // ProcessBatchRecordAsync - not used
    public override Task<MetricRequestBase> ProcessBatchRecordAsync(...)
    {
        throw new NotImplementedException(
            $"{ScenarioName} is a utility scenario and does not process individual records.");
    }
    
    // ProcessBatchAsync - all logic here
    public override async Task<MetricBatchSummaryBase> ProcessBatchAsync(
        List<Record> batch,
        ScenarioConfiguration cfg,
        SecurityContext securityContext)
    {
        // ... orchestrate operations
    }
}
```

**CustomParmsEditorType Selection**:
- **Default**: Grid + JSON editor for simple key-value pairs (most scenarios)
- **JsonOnly**: JSON-only editor for complex nested structures
- **UtilityScenarioEditor**: Multi-step utility scenario with structured steps
- **MatchingSnapshotCapture**: Matching snapshot with step reference support
- **UnifiedMatchingScenario**: Unified matching with organized parameter sections

**RestSubjectArea**:
- **Profisee**: Core Profisee REST API (records, entities, attributes, DQ rules)
- **Connect**: Profisee Connect API (strategies, configurations, batch execution)
- **Metadata**: Profisee Metadata API (entity metadata, model management)
- **Matching**: Profisee Matching API (matching strategies, execution)

---

## Complete Utility Scenario Template (v2.0)

This section provides a complete, production-ready utility scenario template that demonstrates:
- Sequential operation orchestration (database + REST API)
- Fail-fast error handling
- Before/after state logging
- Placeholder endpoint handling
- Two-constructor pattern
- ReadCustomParam<T>() usage
- All v2.0 corrections applied

```csharp
// File: TestAuto.Matching/Scenarios/MyUtilityScenario.cs
using Serilog;
using TestAuto.Matching.Common;
using TestAuto.Matching.Services;
using TestAuto.Metrics.Builders;
using TestAuto.Records.Common;                  // ScenarioBaseMatching namespace!
using TestAuto.Records.Metrics;
using TestAuto.Scenarios.Services;
using TestAuto.Shared.Builders;
using TestAuto.Shared.Common;
using TestAuto.Shared.Common.Metrics;
using TestAuto.Shared.Common.Scenario;
using TestAuto.Shared.Constants;
using TestAuto.Shared.DataRecordGenerators;
using TestAuto.Shared.Extensions;
using TestAuto.Shared.Models;
using TestAuto.Shared.Rest;
using TestAuto.Shared.Scenarios.Configuration.Scenario;
using Record = Profisee.Platform.Cdp.Contracts.Record;

namespace TestAuto.Matching.Scenarios
{
    /// <summary>
    /// Utility scenario for orchestrating multiple operations (database + REST API).
    /// </summary>
    [ScenarioTypes(
        typeof(ScenarioConfigurationOnly),
        typeof(MetricDetailMatchingApi),
        typeof(MetricBatchSummaryBase),
        RestSubjectArea.Matching,
        DataPattern.Other,
        CustomParmsEditorType.Default)]
    [ScenarioDisplay("Utilities")]
    public class MyUtilityScenario : ScenarioBaseMatching
    {
        private readonly IMyService? _myService;
        public override string ScenarioName => nameof(MyUtilityScenario);

        private string _param1 = string.Empty;
        private bool _doOperation1;
        private bool _doOperation2;

        public MyUtilityScenario(
            IServiceProvider serviceProvider,
            ScenarioServices services,
            IMyService myService)
            : base(serviceProvider, services)
        {
            _myService = myService 
                ?? throw new ArgumentNullException(nameof(myService));
        }

        public MyUtilityScenario() : base(null, null)
        {
            _myService = null;
        }

        protected new void ApplyConfiguration(ScenarioConfiguration cfg)
        {
            base.ApplyConfiguration(cfg);
            var tag = LogTagConstants.ForScenario(ScenarioName);
            var p = cfg.ScenarioRuntime.CustomParms;

            _param1 = ReadCustomParam<string>(p, "Param1", string.Empty)!;
            _doOperation1 = ReadCustomParam<bool>(p, "DoOperation1", false);
            _doOperation2 = ReadCustomParam<bool>(p, "DoOperation2", false);

            if (string.IsNullOrWhiteSpace(_param1))
                throw new ArgumentException(
                    $"{ScenarioName}: Param1 is required but was not provided.");
        }

        public override Task<MetricRequestBase> ProcessBatchRecordAsync(
            Record record, ScenarioConfiguration cfg, SecurityContext securityContext)
        {
            throw new NotImplementedException(
                $"{ScenarioName} is a utility scenario and does not process individual records.");
        }

        public override async Task<MetricBatchSummaryBase> ProcessBatchAsync(
            List<Record> batch, ScenarioConfiguration cfg, SecurityContext securityContext)
        {
            ApplyConfiguration(cfg);
            // ... orchestrate operations with fail-fast pattern
        }

        public new string GenerateSampleScenarioConfiguration()
        {
            return @"{
  ""Param1"": ""example_value"",
  ""DoOperation1"": true,
  ""DoOperation2"": true
}";
        }
    }
}
```

## Logging and Usage Patterns

### Logging Pattern

**Standard Logging**:
```csharp
var tag = LogTagConstants.ForScenario(ScenarioName);

_logger.InformationWithTag(tag, "{ScenarioName}: Message", ScenarioName);
_logger.DebugWithTag(tag, "{ScenarioName}: Debug info with {Param}", ScenarioName, value);
_logger.ErrorWithTag(tag, ex, "{ScenarioName}: Error occurred", ScenarioName);
_logger.WarningWithTag(tag, "{ScenarioName}: Warning message", ScenarioName);
_logger.VerboseWithTag(tag, "{ScenarioName}: Verbose details", ScenarioName);
```

**v2.0: Before/After State Logging Pattern**:
```csharp
_logger.InformationWithTag(tag,
    "{ScenarioName}: Operation succeeded. " +
    "Before -> Prop1={Before1}, Prop2={Before2}. " +
    "After -> Prop1={After1}, Prop2={After2}",
    ScenarioName, 
    result.Before?.Prop1, result.Before?.Prop2,
    result.After?.Prop1, result.After?.Prop2);
```

### DI Registration Pattern

```csharp
services.AddTransient<MyNewScenario>();
services.AddSingleton<IMyCustomService, MyCustomService>();
```

---

## Usage Patterns

### Pattern 1: Create New CRUD Scenario

**Request**: "Create a scenario to update records with data mutation"

**Agent Actions**:
1. Recommend base class: `ScenarioBaseCrud`
2. Generate scenario class inheriting from `ScenarioBaseCrud`
3. Add `[ScenarioTypes]` attribute
4. Create custom parameter class with mutation settings
5. Use `ReadCustomParam<T>()` for parameter extraction
6. Use `new` keyword for `ApplyConfiguration()`
7. Scaffold `ProcessBatchRecordAsync` with mutation logic placeholder
8. Set `metric.ElapsedTime` (not `ElapsedTimeMs`)
9. Add logging with `LogTagConstants.ForScenario`
10. Use `new` keyword for `GenerateSampleScenarioConfiguration()`
11. Provide two constructors (DI + parameterless)

### Pattern 2: Create New Matching Scenario

**Request**: "Create a scenario to collect matching results from Monitor database"

**Agent Actions**:
1. Recommend base class: `ScenarioBaseMatching` (verify namespace: `TestAuto.Records.Common`)
2. Create custom `MetricDetailMatchingResults` class
3. Generate scenario class with `[ScenarioTypes]` attribute
4. Implement database query logic
5. Create metric detail for each matching phase
6. Set `metric.ElapsedTime` (not `ElapsedTimeMs`)
7. Build summary metric with total counts

### Pattern 3: Create New Utility Scenario

**Request**: "Create a multi-step utility scenario to run SQL then PowerShell"

**Agent Actions**:
1. Recommend base class: `UtilityBase`
2. Generate scenario class with `DataPattern.Other` and `UtilityScenarioEditor`
3. Configure `IUtilityOrchestrator` for step execution
4. Parse `Steps` array from CustomParms
5. Execute steps sequentially and collect metrics
6. Handle step failures and continue/abort logic

### Pattern 4: Create Utility Scenario with Database + REST Operations (v2.0)

**Request**: "Create a scenario to configure matching strategy via database and REST API"

**Agent Actions**:
1. Recommend base class: `ScenarioBaseMatching`
2. Verify namespace: `TestAuto.Records.Common`
3. Recommend reusing `MetricDetailMatchingApi`
4. Generate scenario class with proper attributes
5. Provide TWO constructors
6. Use `new` keyword for `ApplyConfiguration()`
7. Use `ReadCustomParam<T>()` for parameter extraction
8. Implement fail-fast pattern
9. Handle placeholder endpoints gracefully

---

## Best Practices

### 1. Metrics Design
- Inherit from appropriate base (MetricRequestBase for REST scenarios)
- Tag ALL properties with `[MetricColumn("ColumnName")]`
- Use `MetricColumnNames` constants for standard columns
- Mark computed properties with `[RecordIgnore]`
- Override `IsSuccess()` with scenario-specific logic
- Provide both parameterless and typed constructors
- **v2.0**: Reuse existing metrics before creating custom
- **v2.0**: Use `ElapsedTime` (TimeSpan), NOT `ElapsedTimeMs` (read-only)

### 2. Scenario Design
- Inherit from most specific base class
- Use `LogTagConstants.ForScenario(ScenarioName)` for all logging
- Call `base.ApplyConfiguration(cfg)` before extracting custom parameters
- **v2.0**: Use `new` keyword for `ApplyConfiguration()` and `GenerateSampleScenarioConfiguration()`
- **v2.0**: Provide TWO constructors (DI + parameterless)
- **v2.0**: Override `ScenarioName` property

### 3. Custom Parameters
- Use `ReadCustomParam<T>()` for simple extraction
- Handle missing parameters gracefully with defaults
- Document all parameters in XML comments
- Add constants to domain constants file

### 4. Error Handling
- Wrap processing logic in try-catch blocks
- Log errors with structured logging
- **v2.0**: Fail-fast pattern for sequential operations
- **v2.0**: Don't set `HttpErrorMessage` on summary (only on detail metrics)

### 5. Performance
- Use async/await for I/O operations
- Batch REST API calls when possible
- Use `_stopWatchTimer` for accurate timing
- **v2.0**: Set `metric.ElapsedTime` (TimeSpan), not `ElapsedTimeMs` (read-only)

### 6. Service Integration (v2.0)
- Inject services via constructor (not service locator)
- Throw `ArgumentNullException` in DI constructor if service is null
- Set service to null in parameterless constructor
- Verify actual service method signatures before generating calls

### 7. REST API Integration (v2.0)
- Use `GetRestClient(cfg, subjectArea)` from base class
- Set `HttpRequestType` (not `HttpMethod`): "POST", "GET", "PUT", "DELETE"
- Handle placeholder endpoints gracefully

---

## Common Scenarios

### Scenario 1: Simple CRUD Operation
```
Base Class: ScenarioBaseCrud
DataPattern: Paged
CustomParmsEditorType: Default
Metrics: MetricDetailRecordApi (reuse existing)
Parameters: Entity name, batch size, filters
```

### Scenario 2: Complex Matching Operation
```
Base Class: ScenarioBaseMatching
DataPattern: SelfManaged
Metrics: Custom MetricDetailMatching class
Parameters: Matching strategy, thresholds, record mix
```

### Scenario 3: Multi-Step Utility
```
Base Class: UtilityBase
DataPattern: Other
CustomParmsEditorType: UtilityScenarioEditor
Metrics: Custom MetricDetailUtility class
Parameters: Steps array with type, name, script
```

### Scenario 4: Metadata Management
```
Base Class: ScenarioBaseMetadata
DataPattern: Other
CustomParmsEditorType: JsonOnly
Metrics: Custom MetricDetailMetadata class
Parameters: Entity definitions, attribute configs
```

### Scenario 5: Resource Collection
```
Base Class: ScenarioBase
DataPattern: Single
CustomParmsEditorType: Default
Metrics: Custom MetricDetailResource class
Parameters: Prometheus endpoint, query, interval
```

### Scenario 6: Utility with Database + REST Operations (v2.0)
```
Base Class: ScenarioBaseMatching (namespace: TestAuto.Records.Common)
DataPattern: Other
TestDataType: ScenarioConfigurationOnly
CustomParmsEditorType: Default
Metrics: MetricDetailMatchingApi (reuse existing)
Parameters: Operation flags, configuration values
Pattern: Sequential operations with fail-fast
```

---

## Key Files Reference

### Core Framework Files
```
TestAuto.Shared/Interfaces/IScenario.cs                          (52 lines)
TestAuto.Shared/Common/Scenario/ScenarioTypesAttribute.cs        (93 lines)
TestAuto.Scenarios/Common/ScenarioBase.cs                        (178 lines)
TestAuto.Scenarios/Common/CustomParmAttribute.cs                 (15 lines)
TestAuto.Scenarios/Helpers/CustomParmDictionaryHelper.cs         (88 lines)
```

### Metric Base Classes
```
TestAuto.Shared/Models/MetricDetailBase.cs                       (66 lines)
TestAuto.Shared/Models/MetricDetailExtended.cs                   (124 lines)
TestAuto.Shared/Models/MetricRequestBase.cs                      (72 lines)
TestAuto.Shared/Models/MetricBatchSummaryBase.cs                 (52 lines)
TestAuto.Shared/Models/MetricColumnAttribute.cs                  (23 lines)
TestAuto.Shared/Models/MetricColumnNames.cs                      (48 lines)
```

### Scenario Base Classes
```
TestAuto.Records/Common/ScenarioBaseCrud.cs                      (767 lines)
TestAuto.Records/Common/ScenarioBaseMatching.cs                  Note namespace!
TestAuto.Metadata/Common/ScenarioBaseMetadata.cs
TestAuto.Connect/Common/ScenarioBaseConnect.cs
TestAuto.Utilities/Common/UtilityBase.cs
```

### Configuration Classes
```
TestAuto.Shared/Scenarios/Configuration/Scenario/ScenarioConfiguration.cs
TestAuto.Shared/Scenarios/Configuration/Scenario/ScenarioRuntime.cs
TestAuto.Records/Configuration/RecordsCustomParms.cs             (29 lines)
TestAuto.Connect/Configuration/ConnectCustomParms.cs             (37 lines)
TestAuto.Matching/Common/MatchingConstants.cs                    v2.0
```

### v2.0 Reference Implementations
```
TestAuto.Matching/Scenarios/MatchingStrategyUpdateScenario.cs    (711 lines)
  - Demonstrates: Utility scenario with DataPattern.Other
  - Reuses: MetricDetailMatchingApi (no custom metric)
  - Pattern: Sequential operations with fail-fast
  - Highlights: Database + REST API orchestration
  - Shows: ReadCustomParam<T>() usage
  - Demonstrates: Before/after state logging
  - Handles: Placeholder endpoints gracefully
```

---

## Success Criteria

A scenario implementation is considered complete when:

1. Inherits from appropriate base class
2. **v2.0**: Verifies base class namespace is correct
3. Has correct `[ScenarioTypes]` attribute with all required parameters
4. Custom metric detail class created (if needed) with proper inheritance and `[MetricColumn]` attributes
5. **v2.0**: OR reuses existing metric class if no custom properties needed
6. Custom parameters defined in static class with `[CustomParm]` attributes
7. **v2.0**: Constants added to domain constants file
8. `ApplyConfiguration` extracts and parses all parameters with defaults
9. **v2.0**: Uses `new` keyword for `ApplyConfiguration()` (not `override`)
10. **v2.0**: Uses `ReadCustomParam<T>()` for simple parameters
11. `ProcessBatchRecordAsync` implements single record processing logic OR throws `NotImplementedException` for utility scenarios
12. `ProcessBatchAsync` implements batch-level logic (if needed)
13. Logging uses `LogTagConstants.ForScenario(ScenarioName)` pattern
14. **v2.0**: Before/after state logging for operations that modify data
15. Error handling populates metrics with failure details
16. **v2.0**: Sets `metric.ElapsedTime` (TimeSpan), NOT `metric.ElapsedTimeMs` (read-only)
17. **v2.0**: Doesn't set `summary.HttpErrorMessage` (property doesn't exist)
18. `GenerateSampleScenarioConfiguration` returns valid JSON
19. **v2.0**: Uses `new` keyword for `GenerateSampleScenarioConfiguration()` (not `override`)
20. Scenario registered in DI container
21. All custom services registered in DI container
22. **v2.0**: Provides TWO constructors (DI + parameterless)
23. **v2.0**: Overrides `ScenarioName` property if base class requires it

## Version History

**v2.0.0** (2026-03-12) - UPDATED VERSION
- Added "Common Pitfalls & Error Prevention" section with 11 critical gotchas
- Added "Pre-Implementation Checklist" section
- Added utility scenario pattern with sequential operations (Pattern 4)
- Added `ReadCustomParam<T>()` helper method pattern
- Added before/after state logging pattern
- Added placeholder endpoint handling pattern
- Updated metrics section with warnings about `ElapsedTimeMs`, property names, and reuse guidance
- Updated template with complete utility scenario example
- Added service integration and REST API integration best practices
- Added reference to MatchingStrategyUpdateScenario (711 lines)

**v1.0.0** (2026-03-11)
- Initial agent specification

---

### Related Resources

**Documentation**:
- **Lessons Learned**: `.agents/scenario-designer-lessons-learned.md`
- **Update Summary**: `.agents/scenario-designer-update-summary.md`

**Related Agents**:
- **scenario-custom-metric-coder** - Creates custom metric classes for scenarios
- **scenario-config-generator** - Generates scenario configuration JSON files
- **custom-parm-editor-agent** - Creates custom parameter UI editors

---

## Invocation

To use this agent, invoke it with one of the following patterns:

```
# Pattern 1: Design new scenario
@scenario-designer Design a scenario to update records with field-level mutations

# Pattern 2: Create matching scenario
@scenario-designer Create a scenario to collect matching results from Monitor DB for all 5 phases

# Pattern 3: Create utility scenario  
@scenario-designer Create a multi-step utility scenario that runs SQL query then PowerShell script

# Pattern 4: Create utility with database + REST operations
@scenario-designer Create a scenario to configure matching strategy via database and REST API

# Pattern 5: Review scenario design
@scenario-designer Review MyNewScenario.cs and suggest improvements for metrics and parameters

# Pattern 6: Generate sample config
@scenario-designer Generate sample configuration JSON for UnifiedMatchingScenario
```
