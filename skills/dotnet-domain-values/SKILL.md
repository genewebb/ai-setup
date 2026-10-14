---
name: dotnet-domain-values
description: >
  Domain attribute cache and domain value constants pattern for TestAuto. Use when
  injecting IDomainAttributeCache, calling GetDomainValues or GetAllAttributes,
  referencing AttributeNames constants in record access, using DomainValues.Yes/No
  for Y/N fields, using ExecutionStatusValues for status comparisons, or
  understanding how PDATA domain names are loaded and cached at startup.
---

# Domain Attribute Cache and Domain Value Constants

`IDomainAttributeCache` / `DomainAttributeCache` provides a lazy, thread-safe singleton cache of valid code values for every Profisee domain attribute used in TestAuto. The cache is keyed by domain attribute name (the PDATA entity attribute names returned by `MetadataConstants.PDATADomainNames()`) and is populated on first access by delegating to `IScenarioDomainTestDataManager`. Companion constants classes (`AttributeNames`, `DomainValues`, `ExecutionStatusValues`) eliminate hard-coded attribute name strings across all record access.

## When to Use

- "I need to pick a random valid domain value for a domain-backed attribute during record generation"
- "What constant should I use instead of the raw string `\"IsActive\"` or `\"ExecutionStatus\"`?"
- "How do I inject or resolve `IDomainAttributeCache` in a data-record generator or transformation helper?"
- "Why is the cache throwing `KeyNotFoundException` for a domain attribute name?"
- "I need to compare an execution status against `Complete` or `Failed` without hard-coding strings"
- "How does domain attribute loading work — when does it hit the API vs. serve from cache?"

## IDomainAttributeCache Interface

Defined in `TestAuto.Records/Interfaces/IDomainAttributeCache.cs`, namespace `TestAuto.Records.Interfaces`.

```csharp
public interface IDomainAttributeCache
{
    // Returns the list of valid Code values for one domain attribute.
    // Throws KeyNotFoundException if the attribute name is not in the cache.
    List<string> GetDomainValues(string domainAttributeName);

    // Returns a defensive snapshot of the full cache (all domain attributes -> values).
    Dictionary<string, List<string>> GetAllAttributes();

    // Clears the cache and resets the initialized flag so the next call reloads.
    void Clear();
}
```

## DomainAttributeCache Implementation

Defined in `TestAuto.Records/Cache/DomainAttributeCache.cs`, namespace `TestAuto.Records.Cache`.

**Storage**: `ConcurrentDictionary<string, List<string>>` keyed by domain attribute name.

**Initialization**: Double-checked locking on a `bool _initialized` flag. The first call to `GetDomainValues` or `GetAllAttributes` triggers `EnsureCacheLoaded()`, which acquires `_lock` and calls `LoadCache()` once. Subsequent calls skip the lock entirely.

**Loading**: `LoadCache()` iterates all names from `MetadataConstants.PDATADomainNames()`. For each name it calls `_dataManager.InitializeDomainScenario(domainName)` then reads up to 100 records via `_dataManager.GetScenarioRecords(1, 100)`, extracting the `MetadataConstants.AttributeCode` field from each `Record` into a `List<string>`.

**DI registration** (singleton, in `RecordsModuleRegistrar`):

```csharp
services.AddSingleton<IDomainAttributeCache, DomainAttributeCache>();
services.AddSingleton<IScenarioDomainTestDataManager, ScenarioDomainTestDataManager>();
```

**`Clear()`** acquires the same `_lock`, clears the dictionary, and resets `_initialized = false` so the next access reloads from the API.

**`GetAllAttributes()`** returns a snapshot (`ToDictionary` with a copied `List<string>`) to prevent external mutation of cached lists.

### Gotcha: an attribute key can be present with an EMPTY value list

`GetDomainValues` throws `KeyNotFoundException` only when the attribute **name is absent**. A subtler case: the key is present but its `List<string>` is **empty** — this happens when the attribute's backing domain entity has no members, so `LoadCache()` cached zero codes for it. Code that picks a random attribute from `GetAllAttributes()` and then indexes its values (e.g. `values[rnd.Next(values.Count)]`) will throw on an empty list.

**Filter to populated attributes before selecting**, so a generator stays robust regardless of which domain entities are populated:

```csharp
var populated = _domainAttributeCache.GetAllAttributes()
    .Where(kvp => kvp.Value != null && kvp.Value.Count > 0)   // skip empty-domain attributes
    .Select(kvp => kvp.Key)
    .ToList();
if (populated.Count == 0)
    throw new InvalidOperationException("DomainAttributeCache has no domain attributes with cached values.");

var attributeName = populated[rnd.Next(populated.Count)];
var values = _domainAttributeCache.GetDomainValues(attributeName);  // guaranteed non-empty
var value = values[rnd.Next(values.Count)];
```

This is the guard used by `CloneAndMutateRecords` and `StewardshipFilterRecords`.

## Domain Value Constants

All constants live in `TestAuto.Shared/Constants/AttributeNames.cs` in the file-scoped namespace `TestAuto.Shared.Constants` (consumers need `using TestAuto.Shared.Constants;`). The file defines three public static classes: `AttributeNames`, `DomainValues`, `ExecutionStatusValues`.

### AttributeNames — common cross-entity attribute names

| Category | Constants |
|---|---|
| Core | `Code`, `Name`, `Description`, `IsActive`, `Version`, `Tags`, `Category`, `CategoryId` |
| Audit | `EnterDTM`, `LastChgDTM`, `CreatedAt`, `CreatedBy` |
| Secrets | `MachineName`, `ProfileType`, `SecretData`, `SecretDataDisplay` |
| Execution | `ExecutionStatus`, `StartTime`, `EndTime`, `ErrorMessage`, `ExecutionOrder`, `Workload`, `WorkloadExecution`, `DispatchJobId` |
| Scenario/Template | `DisplayName`, `DisplayDescription`, `Scenario`, `ScenarioData`, `ScenarioDataDisplay`, `ScenarioDisplayName`, `ScenarioConfiguration`, `TemplateData`, `TemplateDataDisplay`, `TemplateId`, `ProfiseeVersion` |
| Infrastructure | `AppServer`, `DBServer`, `ExecutionMachine`, `ExecutionMode`, `SimulatedUserCount`, `NodeCount`, `DqRuleCount`, `AttributeCount` |
| Validation Log | `ValidationType`, `ValidationResult`, `ValidationDetails`, `ScenarioName`, `Severity` |
| Server Profile | `AvailableInWebUI`, `ServerProfileType` |
| Lookup/Domain | `ShowInActive`, `ShowInHistory` |
| Statistics | `TotalExecutions`, `SuccessfulExecutions`, `FailedExecutions`, `CancelledExecutions`, `AverageExecutionTime`, `SuccessRate`, `TotalBatches`, `CompletedBatches`, `FailedBatches` |
| Workflow | `Workflow`, `WorkflowExecutionParent`, `Active` |
| Progress/Status | `ExecutionId`, `Status`, `CollectionStatus`, `OverallProgress`, `CurrentStage`, `CurrentActivity`, `LastUpdated`, `StageProgress`, `ExecutionsByScenario`, `ExecutionsByStatus` |
| Job Management | `JobId`, `State`, `IsHealthy`, `ActiveJobs`, `QueuedJobs` |
| Filter/File | `Filter`, `FilePath` |
| Model Source | `ModelSourceType`, `AvailableRecords` |
| Utility Type | `FileExtensionTypes` |

### DomainValues — Y/N boolean domain fields

```csharp
DomainValues.Yes  // "Y"
DomainValues.No   // "N"
```

Used for attributes like `IsActive`, `Active`, `AvailableInWebUI`, `ShowInActive`, `ShowInHistory`.

### ExecutionStatusValues — execution lifecycle states

```csharp
ExecutionStatusValues.Queued      // "Queued"
ExecutionStatusValues.Pending     // "Pending"
ExecutionStatusValues.Running     // "Running"
ExecutionStatusValues.Complete    // "Complete"
ExecutionStatusValues.Completed   // "Completed"  (alternate form)
ExecutionStatusValues.Failed      // "Failed"
ExecutionStatusValues.Cancelled   // "Cancelled"
ExecutionStatusValues.Unknown     // "Unknown"
```

Note: both `Complete` and `Completed` exist; check which value the target Profisee entity domain uses before comparing.

## Examples

### Resolve from DI and read values

```csharp
// Integration test — resolve from container
var domainCache = ServiceProvider.GetRequiredService<IDomainAttributeCache>();

// Get all valid codes for a specific domain attribute
var values = domainCache.GetDomainValues("SomeDomainAttributeName");
Assert.IsTrue(values.Any(), "Expected at least one cached domain value");
```

### Constructor injection in a record generator

```csharp
public class CloneAndMutateRecords : DataRecordBase
{
    private readonly IDomainAttributeCache _domainAttributeCache;

    public CloneAndMutateRecords(IConfiguration configuration, IDomainAttributeCache domainAttributeCache)
        : base(configuration)
    {
        _domainAttributeCache = domainAttributeCache
            ?? throw new ArgumentNullException(nameof(domainAttributeCache));
    }

    private string PickRandomDomainValue(string attributeName)
    {
        var values = _domainAttributeCache.GetDomainValues(attributeName);
        return values[Random.Shared.Next(values.Count)];
    }
}
```

### Using AttributeNames and DomainValues constants

```csharp
// Instead of: record["IsActive"] = "Y";
record[AttributeNames.IsActive] = DomainValues.Yes;

// Instead of: if (status == "Complete")
if (status == ExecutionStatusValues.Complete || status == ExecutionStatusValues.Completed)
    MarkWorkloadDone();
```

### Iterate all domain names (same pattern used in LoadCache)

```csharp
var domainNames = MetadataConstants.PDATADomainNames();
foreach (var domainName in domainNames)
{
    var values = domainCache.GetDomainValues(domainName);
    Console.WriteLine($"{domainName}: {string.Join(", ", values)}");
}
```

## Sources

- `TestAuto.Records/Cache/DomainAttributeCache.cs`
- `TestAuto.Records/Interfaces/IDomainAttributeCache.cs`
- `TestAuto.Shared/Constants/AttributeNames.cs`
- `TestAuto.Records/AutoRegistration/RecordsModuleRegistrar.cs` (DI registration)
- `Testing.SpeedMerchants.Integration/Tests/Cache/DomainAttributeCacheTests.cs`
