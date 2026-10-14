---
name: testauto-lookup-cache-pattern
description: >
  In-memory lookup cache and reference data cache patterns for TestAuto. Use when injecting
  ILookupCacheService or IReferenceDataCache, adding new cached reference data types, working
  with ShowInActive / ShowInHistory ExecutionStatus filters, calling PreloadCommonLookupsAsync,
  registering caching services via AddCachingServices, or deciding whether to use the cache
  versus hitting the database directly.
---

Repo: speed-merchants (paths below are repo-relative)

# Lookup Cache Pattern

TestAuto has two distinct caching layers in `TestAuto.Shared.Caching`:

| Cache | Interface | Implementation | Purpose |
|---|---|---|---|
| Low-level general cache | `ICacheService` | `MemoryCacheService` | TryGet/Set/GetOrAdd with TTL and statistics |
| Domain lookup cache | `ILookupCacheService` | `LookupCacheService` | Cached access to Scenario, ExecutionStatus, TemplateCategory, Tag records by ID |
| Startup reference cache | `IReferenceDataCache` | `ReferenceDataCache` | Full reference lists loaded once at startup (server profiles, env types, scenario names, etc.) |

---

## ICacheService Contract

Defined in `TestAuto.Shared.Interfaces.ICacheService`.

```csharp
bool TryGet<T>(string key, out T? value);
void Set<T>(string key, T value, TimeSpan? expiration = null);
T GetOrAdd<T>(string key, Func<T> factory, TimeSpan? expiration = null);
Task<T> GetOrAddAsync<T>(string key, Func<Task<T>> factory, TimeSpan? expiration = null);
bool Remove(string key);
void Clear();
CacheStatistics GetStatistics();
```

`CacheStatistics` exposes `TotalRequests`, `CacheHits`, `CacheMisses`, `TotalItems`, `MemoryUsageBytes`, and a computed `HitRate` property.

**Implementation**: `MemoryCacheService` uses `ConcurrentDictionary<string, CacheItem>` with a background `Timer` that runs cleanup every 1 minute to evict expired entries. Each `CacheItem` stores a nullable `ExpiresAt` — no expiration means the entry lives until `Clear()` is called or the item is explicitly removed.

---

## ILookupCacheService Contract

Defined in `TestAuto.Shared.Interfaces.ILookupCacheService`. Returns Profisee CDP `Record` objects.

```csharp
Task<Record?> GetScenarioAsync(string scenarioId);
Task<Record?> GetExecutionStatusAsync(string statusId);
Task<Record?> GetTemplateCategoryAsync(string categoryId);
Task<Record?> GetTagAsync(string tagId);
Task<List<string>> GetActiveExecutionStatusCodesAsync();
Task<List<string>> GetHistoryExecutionStatusCodesAsync();
Task<string> GetTemplateCategoryNameAsync(string categoryId); // returns record.Name ?? "General"
Task<string> GetTagNameAsync(string tagId);                  // returns record.Name ?? ""
void ClearAllLookupCaches();
Task PreloadCommonLookupsAsync();
```

The concrete `LookupCacheService` additionally exposes `GetScenarioCodeAsync(scenarioId)` and `GetExecutionStatusCodeAsync(statusId)` (both return `record.Code ?? "Unknown"`) — these are **not** on the `ILookupCacheService` interface, so they are only reachable via the concrete class.

---

## 30-Minute TTL and Cache Key Namespacing

All individual record lookups use a fixed TTL of 30 minutes. The TTL constant is:

```csharp
private static readonly TimeSpan LookupCacheTtl = TimeSpan.FromMinutes(30);
```

Cache keys follow a `lookup:<type>:<id>` pattern:

| Record Type | Key prefix | Example key |
|---|---|---|
| Scenario | `lookup:scenario:` | `lookup:scenario:abc123` |
| ExecutionStatus | `lookup:executionstatus:` | `lookup:executionstatus:xyz` |
| TemplateCategory | `lookup:templatecategory:` | `lookup:templatecategory:General` |
| Tag | `lookup:tag:` | `lookup:tag:smoke` |

The pattern is always: check cache with `TryGet`, on miss fetch from `IRestClient`, store with 30-minute TTL, return result.

---

## ExecutionStatus Domain Attribute Filtering

`LookupCacheService` exposes two methods that filter `ExecutionStatus` records by domain attributes stored on each record:

### ShowInActive (`AttributeNames.ShowInActive = "ShowInActive"`)

Controls which execution status codes are visible in the **active executions** view (currently running / queued).

- `GetActiveExecutionStatusCodesAsync()` fetches all `ExecutionStatus` records (pageSize=100) and returns the `Code` values where `ShowInActive == "Y"` or `"YES"` (case-insensitive).
- Used by `ExecutionControlController` and `ExecutionMonitoring.razor.cs` to filter which statuses qualify as "active".

### ShowInHistory (`AttributeNames.ShowInHistory = "ShowInHistory"`)

Controls which execution status codes appear in the **execution history** view (completed / historical).

- `GetHistoryExecutionStatusCodesAsync()` fetches all `ExecutionStatus` records and returns codes where `ShowInHistory == "Y"` or `"YES"`.
- Used by `ExecutionControlController` to validate that a requested status filter is valid for history display. Statuses not marked for history are ignored with a warning log.

Both attributes are on the `ExecutionStatus` entity in Profisee. Setting `ShowInActive = Y` on a status makes it appear in the active queue monitor. Setting `ShowInHistory = Y` makes it appear as a valid history filter. A status can have both, either, or neither set.

---

## IReferenceDataCache and ReferenceDataCache

A heavier singleton cache loaded once at startup. Unlike `LookupCacheService` which caches individual records by ID, `ReferenceDataCache` loads **full lists** of reference values and exposes them as `IReadOnlyList<string>` or typed info objects.

**What it loads** (see `LoadAllAsync`):

| Method | Entity | Returns |
|---|---|---|
| `GetServerProfiles()` | `ServerProfile` (AvailableInWebUI=Y) | codes |
| `GetEnvironmentTypes()` | `EnvironmentType` | names |
| `GetProfiseeVersions()` | `ProfiseeVersion` (AvailableInWebUI=Y) | codes |
| `GetExecutionModes()` | `ExecutionMode` | codes |
| `GetTemplateCategories()` | `TestAutoTemplateCategory` | names |
| `GetTags()` | `TestAutoTags` | names |
| `GetScenarioNames()` | Registered `IScenario` services (in-process) | scenario type names |
| `GetUtilityTypes()` | `TestAutoUtilityType` | codes |
| `GetFileExtensions(typeCode)` | `TestAutoUtilityType.FileExtensionTypes` attribute | `HashSet<string>` of extensions |
| `GetServerProfileType(code)` | `ServerProfile.ServerProfileType` attribute | type string |
| `GetSecretProfileTypes()` | `TestAutoSecretsProfileType` | `SecretProfileTypeInfo` |
| `GetModelSources()` | `TestAutoModelSource` | `ModelSourceInfo` |
| `GetModelSourceTypes()` | `TestAutoModelSourceType` | codes |
| `GetMatchingStrategies()` | `TestAutoMatchingStrategy` | `MatchingStrategyInfo` |
| `GetMatchingAttributeReferences()` | `TestAutoMatchingStrategyAttributesReference` | `MatchingAttributeReferenceInfo` |
| `GetMatchingAttributes()` | `TestAutoMatchingAttributes` | `MatchingAttributeInfo` |
| `GetMatchingStatuses()` | `TestAutoMatchingStatus` | `MatchingStatusInfo` |
| `GetRunProfiles()` | `Constants.EntityNames.UnifiedMatchingApiExecutionRunProfile` (pageSize 1000) | `RunProfileInfo` — `Code`, `ProfiseeVersion`, `MatchingStrategyCode` (both `ExtractDomainCode`d), `MatchingScenarioName`, `SourceRecordCount`, `RuleCount`; Code-ordered |
| `GetConnectRunProfiles()` | `Constants.EntityNames.ConnectRunProfile` (`data.tConnectRunProfile`, pageSize 1000) | plain `string` codes — the entity has **no Name**, so only `Code` is meaningful; distinct + Code-ordered |

Two accessors are **derived filters**, not extra loads — they filter the already-loaded list:
`GetMatchingAttributeReferencesInUse()` and `GetMatchingStatusesInUse()` (`.Where(x => x.InUse)`).
`GetMatchingStatuses()` itself returns everything, InUse or not — use the `…InUse()` variant when
you want only active rows.

Every loader is individually try/catch-wrapped: a failure logs an error and yields an **empty
list** for that one entity, so a partially-populated cache is a normal degraded state rather than
a startup failure. The single `LoadAllAsync` completion log line names every list and its count —
that log is the fastest way to confirm the live set (re-read `LoadAllAsync` rather than trusting
this table's row count, which grows over time; verified 2026-07-27 @ 4c367fe6).

**DBA value extraction**: Domain attribute values from Profisee arrive as `"D [Development]"` strings. `ReferenceDataCache` has an `ExtractDomainCode` helper that strips everything after the first space or bracket to get the code portion.

**Lazy REST client initialization**: The REST client is not injected at construction time. It is resolved from `IServiceProvider` on first use in `EnsureRestClientInitialized()`. This allows the singleton to be created even when secrets / REST services are unavailable at startup (degraded mode).

---

## PreloadCommonLookupsAsync (LookupCacheService)

Called manually to warm the lookup cache before requests arrive. Loads:
1. All `ExecutionStatus` records (pageSize=100) — each is individually cached by ID
2. First 10 `Scenario` records (pageSize=10)
3. Up to 50 `TestAutoTemplateCategory` records
4. Up to 50 `TestAutoTags` records

Errors during preload are caught and logged; the cache simply remains empty for failed entities and will be populated on-demand.

This method is **not called automatically at startup** — it must be called explicitly. In contrast, `IReferenceDataCache.EnsureLoadedAsync()` IS called at startup via `PipelineExtensions.ConfigurePipeline` when `FeatureFlags:PreloadReferenceDataCache` is `true` (default).

---

## Startup Registration

All caching services are registered by calling `services.AddCachingServices()` in `CachingServiceExtensions.cs`:

```csharp
services.AddSingleton<IDistributedCache, MemoryDistributedCache>();
services.AddSingleton<IMetadataCacheProvider, MetadataCacheProvider>();
services.AddSingleton<IMetadataCache>(sp => sp.GetRequiredService<ICdpService>().OperationContext.MetadataCache);
services.TryAddSingleton<ICacheService, MemoryCacheService>();  // TryAdd — safe to call multiple times
services.AddSingleton<LookupCacheService>();
services.AddSingleton<ILookupCacheService>(sp => sp.GetRequiredService<LookupCacheService>());
```

`IReferenceDataCache` and `ReferenceDataCache` are registered separately — check `WebServiceExtensions.cs` or `RegisterAllServices.cs`.

---

## Startup Preload (IReferenceDataCache)

In `PipelineExtensions.ConfigurePipeline`, after services are built:

```csharp
var preloadCache = app.Configuration.GetValue<bool>("FeatureFlags:PreloadReferenceDataCache", true) && !skipCache;
if (preloadCache)
{
    var cache = scope.ServiceProvider.GetService<IReferenceDataCache>();
    _ = cache.EnsureLoadedAsync();  // fire-and-forget; errors are caught and logged
}
```

If REST services are unavailable (secrets not loaded, degraded mode), the warning is logged and the cache is left empty. It will be populated on first request that calls `EnsureLoadedAsync()`.

---

## When to Use the Cache vs. Database Directly

| Scenario | Use |
|---|---|
| Resolving a foreign key reference (scenario ID → code, status ID → code, tag ID → name) | `ILookupCacheService` |
| Populating a dropdown of all known reference values (server profiles, env types, tags) | `IReferenceDataCache` |
| Checking if a status is valid for active/history display | `ILookupCacheService.GetActiveExecutionStatusCodesAsync()` / `GetHistoryExecutionStatusCodesAsync()` |
| Writing or updating a record (mutations) | Always hit the REST API directly — do not cache write results |
| One-off lookup where stale data is unacceptable | Call `ClearAllLookupCaches()` then re-fetch, or use `IReferenceDataCache.RefreshAsync()` |
| Unit tests with no database | Mock `ICacheService` and/or `ILookupCacheService`; do not use `ReferenceDataCache` in unit tests |

---

## Sources
- `TestAuto.Shared.Caching\Services\LookupCacheService.cs`
- `TestAuto.Shared.Caching\Services\MemoryCacheService.cs`
- `TestAuto.Shared.Caching\Services\ReferenceDataCache.cs`
- `TestAuto.Shared\Interfaces\ICacheService.cs`
- `TestAuto.Shared\Interfaces\ILookupCacheService.cs`
- `TestAuto.Shared\Interfaces\IReferenceDataCache.cs`
- `TestAuto.DependencyInjection\ServiceExtensions\CachingServiceExtensions.cs`
- `TestAuto.Web\ServiceExtensions\PipelineExtensions.cs`
