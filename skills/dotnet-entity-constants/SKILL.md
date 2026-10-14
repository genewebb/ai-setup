---
name: dotnet-entity-constants
description: >
  Entity helper utilities for creating, deleting, and retrieving Profisee entity metadata in TestAuto. Use when setting up or tearing down test entities and attributes via CDP service, generating typed attribute sets for an entity, or fetching entity metadata over REST.
---

# Entity Helper Utilities

Three static/concrete helpers cover the full lifecycle of Profisee entity metadata in test scenarios: `EntityArtifactHelper` performs synchronous CDP-layer create/delete operations for entities and their DBA (domain-based attribute) companions; `EntityAttributeGenerator` produces typed `MetadataAttribute` lists in repeating five-attribute sets; and `EntityDataFacade` exposes async REST operations against the Entities gateway endpoint.

## When to Use

- "I need to set up a fresh entity with attributes before a matching test"
- "I need to tear down an entity (and its DBA entities) after a test run"
- "I need to generate a batch of free-form and domain attributes for an entity"
- "I need to retrieve all entities or a specific entity via the REST API"
- "I need to create or update entities through the HTTP gateway"

## EntityArtifactHelper

Static class in `TestAuto.Shared.Helpers`. Operates synchronously against `ICdpService` and `IMetadataCache`. Calls `cdpService.ReloadCache()` before and after mutations to keep the in-process cache consistent.

### Nested result type

```csharp
public class EntityAndAttributesResult
{
    public Entity Entity { get; set; }
    public Dictionary<string, Entity> DbaDictionary { get; set; }
    public List<MetadataAttribute> Attributes { get; set; }
}
```

### Key methods

```csharp
// Deletes the named entity and up to nbrOfDomainAttributes companion DBA entities
// (named Dba_001_<entityName> … Dba_NNN_<entityName>).
// Returns the Entity that was deleted, or null if it did not exist.
public static Entity DeleteExistingArtifacts(
    IMetadataCache metadataCache,
    ICdpService cdpService,
    ILogger logger,
    string entityName,
    int nbrOfDomainAttributes)

// Creates the named entity, creates nbrOfDomainAttributes DBA entities, generates
// attributes via EntityAttributeGenerator, and persists them via AttributeRepository.
// Returns an EntityAndAttributesResult containing all created objects.
public static EntityAndAttributesResult RecreateEntityAndAttributes(
    IMetadataCache metadataCache,
    ICdpService cdpService,
    ILogger logger,
    string entityName,
    int nbrOfDomainAttributes,
    int nbrOfFreeFormAttributes)
```

Errors from any repository call are thrown as `Exception` with the full list of CDP error codes and descriptions.

## EntityAttributeGenerator

Static class in `TestAuto.Shared.Helpers`. Generates `MetadataAttribute` objects in repeating sets of five free-form attributes plus one `AttributeType.Domain` attribute per DBA entry.

```csharp
// nbrOfFreeFormAttributes must be a multiple of 5.
// Each set of 5 produces: MyFFA<NNN> (Text), MyLink<NNN> (Link),
//   MyNumeric<NNN> (Number, Precision=8), MyDate<NNN> (Date), MyDateTime<NNN> (DateTime).
// Each DBA entry in dbaDictionary produces one Domain attribute named after the DBA entity.
public static List<MetadataAttribute> GenerateAttributes(
    Entity entity,
    int nbrOfFreeFormAttributes,
    Dictionary<string, Entity> dbaDictionary)
```

Attribute name pattern: zero-padded three-digit counter, e.g. `MyFFA001`, `MyLink001`, `MyNumeric001`.

Domain attributes: `AttributeType.Domain`, `AttributeDataType.Text`, `Length = 250`, `DomainEntityId` set to the DBA entity's identifier.

## EntityDataFacade

Concrete class in `TestAuto.Shared.Http.Facades`, extends `HttpClientFacade`. Communicates with the Profisee REST gateway at the `Entities` service path. No interface — inject the concrete type directly.

### Constructors

```csharp
// Convenience: creates a fresh PathAndQueryBuilder internally.
public EntityDataFacade(HttpClient httpClient, IAuthenticationKeyValue authKey, ILogger logger)

// Full: inject a custom PathAndQueryBuilder for URL customization.
public EntityDataFacade(HttpClient httpClient, PathAndQueryBuilder builder, IAuthenticationKeyValue authKey, ILogger logger)
```

### Async methods

```csharp
// POST — creates entities from a JArray payload.
public async Task<JsonResponse> CreateEntitiesAsync(JArray entities)

// PATCH — updates entities from a JArray payload.
public async Task<JsonResponse> UpdateEntitiesAsync(JArray entities)

// DELETE — deletes a single entity by name.
public async Task<JsonResponse> DeleteEntityAsync(string entityName, CancellationToken cancellationToken = default)

// DELETE — deletes all entities (bulk).
public async Task<JsonResponse> DeleteEntitiesAsync(CancellationToken cancellationToken = default)

// GET — returns all entities; parses both envelope {"data":[…]} and bare array formats.
public async Task<List<Entity>> GetEntitiesAsync(CancellationToken cancellationToken = default)

// GET — returns a single entity by name; returns null on 404, throws on other non-success.
public async Task<Entity> GetEntityAsync(string entityName, CancellationToken cancellationToken = default)
```

### Utility methods

```csharp
// Configure the internal PathAndQueryBuilder with a fluent action.
public void ConfigurePath(Action<PathAndQueryBuilder> configure)

// Returns the currently built URL path (no leading slash) — useful for debug logging.
public string GetCurrentPath()
```

All methods log at Verbose/Debug level using `LogTagConstants.RestApi`.

## Examples

```csharp
// --- Setup: delete leftovers, then recreate entity with 10 free-form + 3 DBA attrs ---
EntityArtifactHelper.DeleteExistingArtifacts(
    metadataCache, cdpService, logger, "TestProduct", nbrOfDomainAttributes: 3);

var result = EntityArtifactHelper.RecreateEntityAndAttributes(
    metadataCache, cdpService, logger,
    entityName: "TestProduct",
    nbrOfDomainAttributes: 3,
    nbrOfFreeFormAttributes: 10);   // must be multiple of 5

// result.Entity          — the newly created Entity
// result.DbaDictionary   — {"Dba_001_TestProduct": Entity, ...}
// result.Attributes      — 10 free-form + 3 domain MetadataAttribute objects

// --- Generate attributes standalone ---
var attrs = EntityAttributeGenerator.GenerateAttributes(entity, 5, dbaDictionary);
// Produces: MyFFA001, MyLink001, MyNumeric001, MyDate001, MyDateTime001
//           + one Domain attr per DBA entry

// --- REST: fetch all entities ---
var facade = new EntityDataFacade(httpClient, authKey, logger);
List<Entity> all = await facade.GetEntitiesAsync();

// --- REST: fetch one entity (returns null if not found) ---
Entity e = await facade.GetEntityAsync("TestProduct");

// --- REST: create entity via JSON patch ---
var payload = JArray.Parse(@"[{""name"":""TestProduct""}]");
JsonResponse resp = await facade.CreateEntitiesAsync(payload);
```

## Sources

- `TestAuto.Shared/Helpers/EntityArtifactHelper.cs`
- `TestAuto.Shared/Helpers/EntityAttributeGenerator.cs`
- `TestAuto.Shared.Http/Facades/EntityDataFacade.cs`
