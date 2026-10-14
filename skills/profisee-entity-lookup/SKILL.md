---
name: profisee-entity-lookup
description: >
  Patterns for looking up Profisee entity metadata at runtime via IMetadataCache or EntityDataFacade. Use when resolving an entity by name, checking whether an entity exists, retrieving attribute lists, filtering attributes by type, or wiring up the metadata cache in DI.
---

# Profisee Entity Lookup and Metadata Cache

TestAuto has two complementary ways to resolve entity metadata at runtime. **`IMetadataCache`** is the in-process CDP cache (synchronous, registered as a singleton from `ICdpService.OperationContext`). **`EntityDataFacade`** is the REST facade (async, hits the Profisee REST gateway). Use `IMetadataCache` inside service/scenario classes that already have a `ICdpService` dependency; use `EntityDataFacade` in HTTP-based test flows or when you need the full `Entity` object from the API.

Both paths return `null` when the entity does not exist — never throw for a missing entity, always null-check.

## When to Use

- "Does entity X exist before I run the test?"
- "Get all attributes for entity X so I can build a record request"
- "Filter attributes to only FreeForm or Domain types"
- "Check metadata existence in a scenario initialization guard"
- "Look up an entity by name via REST (EntityDataFacade)"
- "Wire up IMetadataCache in DI / understand where it comes from"

## IMetadataCache / MetadataCache

`IMetadataCache` comes from `Profisee.Platform.Utilities.Cdp.Interface`. It is registered as a singleton in DI by `AddCachingServices()` — the registration resolves it from `ICdpService.OperationContext.MetadataCache`.

Key synchronous methods (all return `null` when not found):

```csharp
// Look up a single entity by name — returns null if missing
Entity GetEntity(string entityName);

// Look up a single entity by Guid — returns null if missing
Entity GetEntity(Guid entityId);

// Get all attributes for an entity (by name or Guid)
List<MetadataAttribute> GetEntityAttributes(string entityName);
List<MetadataAttribute> GetEntityAttributes(Guid entityId);
```

**Always call `cdpService.ReloadCache()` before reading from the cache** after any create/delete operation to ensure the in-memory cache reflects the current schema state.

## EntityDataFacade Lookup Methods

`EntityDataFacade` (in `TestAuto.Shared.Http/Facades/EntityDataFacade.cs`) wraps the REST gateway:

```csharp
// Returns null on HTTP 404; throws HttpRequestException on other non-success codes
Task<Entity> GetEntityAsync(string entityName, CancellationToken cancellationToken = default)

// Returns a List<Entity> of all entities; parses both envelope {"data":[...]} and bare array formats
Task<List<Entity>> GetEntitiesAsync(CancellationToken cancellationToken = default)
```

`GetEntityAsync` post-processes the result: if the deserialized `entity.Name` is empty but `entity.Identifier.Name` is populated, it back-fills `Name` from the identifier.

The same methods are also declared on `IRestClient`:

```csharp
Task<Entity> GetEntityAsync(string entityName);
Task<List<Entity>> GetEntitiesAsync();
Task<List<MetadataAttribute>> GetAttributesAsync(string entityName);
```

## Attribute Lookup

Via `IMetadataCache` (synchronous):

```csharp
var allAttrs = _metadataCache.GetEntityAttributes(entityName);
var freeformAttrs = allAttrs.Where(a => a.Configuration.TypeID == AttributeType.FreeForm).ToList();
var domainAttrs   = allAttrs.Where(a => a.Configuration.TypeID == AttributeType.Domain).ToList();
```

Via `IRestClient` (async, REST):

```csharp
var attributes = await _restClient.GetAttributesAsync(entityName);
var existingNames = attributes.Select(a => a.Name).ToHashSet(StringComparer.OrdinalIgnoreCase);
```

## DI Registration

`AddCachingServices()` in `TestAuto.DependencyInjection/ServiceExtensions/CachingServiceExtensions.cs` wires everything up:

```csharp
// IMetadataCache resolved from ICdpService.OperationContext
services.AddSingleton<IMetadataCache>(sp =>
{
    var cdpService = sp.GetRequiredService<ICdpService>();
    return cdpService.OperationContext.MetadataCache
           ?? throw new InvalidOperationException("CdpService.OperationContext.MetadataCache is null.");
});
```

Inject `IMetadataCache` directly in constructors; do not resolve it from `ICdpService` manually in application code.

## Examples

### Check existence and get attributes (IMetadataCache)

```csharp
public class MyScenario
{
    private readonly IMetadataCache _metadataCache;
    private readonly ICdpService _cdpService;

    public void Initialize(string entityName)
    {
        _cdpService.ReloadCache();                          // flush stale cache first
        var entity = _metadataCache.GetEntity(entityName);
        if (entity == null)
            throw new InvalidOperationException($"Entity '{entityName}' does not exist.");

        var attrs = _metadataCache.GetEntityAttributes(entityName);
        var freeformNames = attrs
            .Where(a => a.Configuration.TypeID == AttributeType.FreeForm)
            .Select(a => a.Name)
            .ToList();
    }
}
```

### Check existence via REST (EntityDataFacade)

```csharp
var entity = await entityDataFacade.GetEntityAsync("MyEntity");
if (entity == null)
{
    // 404 — entity does not exist
    return;
}
// entity.Name is always populated (back-filled from Identifier if needed)
```

### Delete-and-recreate guard pattern (EntityArtifactHelper)

```csharp
cdpService.ReloadCache();
var existing = metadataCache.GetEntity(entityName);   // null = safe to create
if (existing != null)
{
    var req = new DeleteArtifactsRequest
    {
        ArtifactKeys = new List<string> { existing.Id.ToString() },
        User = UserHelper.GetAdminUser()
    };
    cdpService.EntityRepository.Delete(req);
    cdpService.ReloadCache();
}
```

## Sources

- `TestAuto.Shared.Http/Facades/EntityDataFacade.cs`
- `TestAuto.DependencyInjection/ServiceExtensions/CachingServiceExtensions.cs`
- `TestAuto.Shared/Common/Context.cs`
- `TestAuto.Shared/Helpers/EntityArtifactHelper.cs`
- `TestAuto.Scenarios/Management/ScenarioEntityTestDataManager.cs`
- `TestAuto.Shared/Interfaces/IRestClient.cs` (interface declarations)
- `TestAuto.Shared/Validation/EntityValidationService.cs` (REST-based validation usage)
