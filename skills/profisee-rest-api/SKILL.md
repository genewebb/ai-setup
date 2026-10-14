---
name: profisee-rest-api
description: >
  IRestClient REST gateway integration pattern for Profisee MDM operations. Use when calling the
  Profisee REST API via IRestClient or IRestClientFactory, implementing
  EntityDataFacade/HttpClientFacade calls, resolving a client in an integration test (from BaseTest,
  or from the BaseRestClientTest base — which exists but has no inheritors yet), choosing
  GetRecordsAsync vs GetAllRecordsAsync, a query that silently returned only the first ~50-record
  page, or how records/entities/attributes are created, queried, or deleted.
---

# Profisee REST API Client

The speed-merchants test automation project communicates with Profisee through a
`IRestClient` abstraction. Concrete implementations wrap `HttpClient` via the
`HttpClientFacade` base class and `EntityDataFacade`. A `IRestClientFactory`
resolves per-subject-area clients at test runtime. Tests resolve `IRestClient`
directly from the DI container or construct one through `IRestClientFactory` when
they need a subject-area-specific client. A `BaseRestClientTest` base exists for
the first case (it extends `BaseTest` and exposes a resolved `IRestClient`), but
nothing derives from it yet — its declaration is its only occurrence in the repo,
so there is no existing test to copy the pattern from.

## When to Use

- "How do I call the Profisee REST API in a test?"
- "How do I create/update/delete records via REST?"
- "How does EntityDataFacade build URLs and send HTTP requests?"
- "How do integration tests get an IRestClient from DI?"
- "What subject areas are available in RestSubjectArea?"
- "How does HttpClientFacade wrap responses into JsonResponse?"

## IRestClient Interface

Defined in `TestAuto.Shared/Interfaces/IRestClient.cs`.

**Record operations**

| Method | Description |
|---|---|
| `CreateRecordsAsync(entityName, records, autoAddDbas)` | POST batch of records; returns `JsonResponse` |
| `CreateRecordsWithDetailAsync(entityName, records, autoAddDbas)` | POST with full response body (`CreatedRecordsResponseBody`) |
| `UpdateRecordsAsync(entityName, records, isUpsert)` | PATCH/upsert records |
| `UpdateRecordsWithDetailAsync(entityName, records, isUpsert)` | PATCH with full response (`UpdatedRecordsResponseBody`) |
| `DeleteRecordAsync(entityName, recordCode, clearReferencesBeforeDelete)` | DELETE single record |
| `DeleteRecordsAsync(entityName, recordCodes, clearReferencesBeforeDelete)` | DELETE list of records |
| `BulkDeleteRecordsAsync(entityName, recordCodes, clearReferencesBeforeDelete)` | Bulk DELETE |
| `GetRecordAsync(entityName, recordCode, selectAttributes, queryParameters)` | GET single `Record` by code |
| `GetRecordsAsync(entityName, selectAttributes, queryParameters, pageSize, pageNumber)` | Paged GET — one page, you control `pageSize`/`pageNumber` |
| `GetRecordsAsync(entityName, queryParameters)` | GET with query params only — **first page only, silently truncated** (see trap below) |
| `GetAllRecordsAsync(entityName, queryParameters, pageSize = 100)` | Pages internally until the whole result set is collected |
| `GetRecordsByCodesAsync(entityName, selectAttributes, recordCodes, pageSize, pageNumber)` | GET filtered by code list |
| `GetRecordWithHistoryAsync(entityName, recordCode, fromTransactionId, asOfFromTime, selectAttributes)` | History GET |
| `PatchRecordAsync(entityName, record)` | PATCH single record |
| `PatchRecordsAsync(entityName, records)` | PATCH multiple records |
| `PostRecordAsync(entityName, record)` | POST single record |
| `PostRecordsAsync(entityName, records)` | POST multiple records |

**Matching / lookup / survivorship operations**

| Method | Description |
|---|---|
| `PutMatchAsync(strategyName, recordCode)` | PUT match; returns `JsonResponse<MatchResponse>` |
| `PostLookupAsync(strategyName, lubcRecord, lubcAttributes, processAllAttributeSets, additionalAttributes)` | POST lookup |
| `PostSurvivorshipAsync(strategyName, matchClusterIds)` | POST survivorship |

**Entity operations**

| Method | Description |
|---|---|
| `CreateEntityAsync(entity)` | POST new entity |
| `CreateEntityAsync(request)` | POST with extended `EntityCreateRequest` |
| `DeleteEntityAsync(entityName)` | DELETE entity |
| `GetEntitiesAsync()` | GET all entities |
| `GetEntityAsync(entityName)` | GET single entity |
| `DeleteEntitiesAsync()` | DELETE all entities |

**Attribute operations**

| Method | Description |
|---|---|
| `CreateAttributesAsync(entityName, attributes)` | POST attributes to entity |
| `GetAttributesAsync(entityName)` | GET all attributes for entity |
| `DeleteAttributesAsync(entityName, attributeNames)` | DELETE named attributes |

**Endpoint management**

```csharp
EndpointUpdateResult UpdateEndpointFromRestDictionary(
    Dictionary<RestSubjectArea, (string BaseUrl, string ApiKey)> urlDict,
    RestSubjectArea restSubjectArea);
```

## RestSubjectArea Enum

Defined in `TestAuto.Shared/Rest/RestSubjectArea.cs`. Use with `IRestClientFactory.GetClient()`:

```csharp
public enum RestSubjectArea
{
    Profisee,    // Core MDM operations (records, entities, attributes)
    Metrics,
    Connect,
    Portal,
    Matching,
    Data,
    ScenarioMgt, // Hosts TestAutoSecrets entity
    Monitor
}
```

## IRestClientFactory

Defined in `TestAuto.Shared/Interfaces/IRestClientFactory.cs`.

```csharp
IRestClient GetClient(ScenarioConfiguration config, RestSubjectArea subjectArea);
```

Inject `IRestClientFactory` when a test needs a non-default subject area. Inject
`IRestClient` directly when the default (Profisee) client is sufficient.

## Integration Test Base Classes

### BaseTest (`Testing.SpeedMerchants.Integration/Helpers/BaseTest.cs`)

Abstract base for all integration tests. `[TestInitialize] Setup()` builds the DI
container via `services.RegisterAllServices(Configuration, includeWebServices: true)`,
loads config from `appsettings.json` and environment variables, configures Serilog
console logger, and registers `IWebUiClient` with SSL-bypass handler and a 20-minute
timeout. Exposes `ServiceProvider`, `Configuration`, and `Logger`.

### BaseRestClientTest (`Testing.SpeedMerchants.Integration/Tests/RESTGateway/Client/BaseRestClientTest.cs`)

Extends `BaseTest`. Resolves `IRestClient` from the DI container in `[TestInitialize]`
and exposes it as `RestClient`. Includes a smoke test:

```csharp
[TestCategory("Rest"), TestCategory("DependencyInjection")]
[TestMethod]
public void RestClient_IsNotNull() { Assert.IsNotNull(RestClient); }
```

Inherit this when all you need is the default Profisee REST client.

## HttpClientFacade and EntityDataFacade

`HttpClientFacade` (`TestAuto.Shared.Http/Facades/HttpClientFacade.cs`) is the
abstract base for all HTTP wrappers. It holds `HttpClient`, `PathAndQueryBuilder`,
`IAuthenticationKeyValue`, and `ILogger`. Protected async helpers:

- `CallPostAsync(serviceToCall, content, contentTypeOverride)` — POST with `application/json`
- `CallPatchAsync(serviceToCall, content)` — PATCH with `application/json-patch+json`
- `CallDeleteAsync(serviceToCall)` — DELETE by path
- `CallGetAsync(fullPath)` — GET to absolute path
- `CallPutAsync(fullPath, content)` — PUT with JSON body
- `GetGatewayResponseAsync(httpResponse)` — reads body, wraps in `JsonResponse`
- `GetGatewayResponseAsync<T>(httpResponse)` — typed deserialization into `JsonResponse<T>`

`EntityDataFacade` (`TestAuto.Shared.Http/Facades/EntityDataFacade.cs`) extends
`HttpClientFacade` and implements entity-level REST operations. It uses
`PathAndQueryBuilder.ServiceCall(HttpRequestConstants.Services.Entities)` to
construct endpoint paths, then delegates to `CallPostAsync`/`CallPatchAsync`/etc.
A `ConfigurePath(Action<PathAndQueryBuilder>)` method allows callers to configure
the URL before each call.

## Common Query Patterns

**Get a single record with specific attributes:**

```csharp
var attributes = new List<string> { "Code", "Name", "Color", "ProductSubCategory" };
var record = await _restClient.GetRecordAsync(entityName, "1000000", attributes);
```

**Paged query (page 2, 5 records per page):**

```csharp
var result = await _restClient.GetRecordsAsync(
    entityName,
    selectAttributes,
    queryParameters: null,
    pageSize: 5,
    pageNumber: 2);
// result.Records is List<Record>
```

**Query by multiple codes:**

```csharp
var codes = records.Select(r => r.Code).ToList();
var result = await _restClient.GetRecordsByCodesAsync(
    entityName,
    selectAttributes,
    codes,
    pageSize: 50,
    pageNumber: 1);
```

**Assert HTTP status for create/delete operations:**

```csharp
var resp = await _restClient.CreateRecordsAsync(entityName, records);
Assert.IsTrue(
    resp.StatusCode == HttpStatusCode.OK || resp.StatusCode == HttpStatusCode.Created,
    $"Unexpected status: {resp.StatusCode}");
```

**Assert IsSuccess for entity/attribute operations:**

```csharp
var resp = await _restClient.CreateEntityAsync(entity);
Assert.IsTrue(resp.IsSuccess, $"Entity creation failed: {resp}");
```

**Cleanup pattern (always clear references before delete):**

```csharp
await _restClient.DeleteRecordsAsync(entityName, recordCodes, clearReferencesBeforeDelete: true);
await _restClient.DeleteAttributesAsync(entityName, attrNames);
await _restClient.DeleteEntityAsync(entityName);
```

**OData filter via query parameters** — note this is the *truncating* overload; fine here only
because the filter is expected to match a handful of rows:

```csharp
var response = await _restClient.GetRecordsAsync(
    entityName: "TestAutoSecrets",
    queryParameters: new Dictionary<string, string>
    {
        { "Filter", "[MachineName] eq 'SERVER01' and [IsActive] eq 'Y'" }
    });
```

## ⚠️ First-page truncation trap — `GetRecordsAsync` vs `GetAllRecordsAsync`

The two-argument `GetRecordsAsync(entityName, queryParameters)` overload **never sets a page
size**. `RestClient.cs:163-171` configures only `ServiceCall` + `AddPathSegment` +
`WithQueryParameters` — no `.WithPageSize()`, no `.WithPageNumber()` — so the gateway applies its
own default page (**50** at the time of writing) and you get page 1 and nothing else. There is no
exception, no warning, and no truncation flag: a 5,000-row entity comes back as 50 rows and the
caller happily processes a 1% sample. This is the exact failure mode behind several
"records went missing" investigations.

`IRestClient.cs:99-105` says so in its own XML doc — *"that overload returns only the first
server-default page (50) and silently truncates larger result sets."* Treat the 50 as the
**server's** default, not a client constant: it can change server-side, so never hard-code it.
Re-read the doc comment and `RestClient.cs` if the number matters to you.

**Fix — use `GetAllRecordsAsync` whenever you need the complete set:**

```csharp
// Signature: IRestClient.cs:106-109
Task<RecordResult> GetAllRecordsAsync(
    string entityName,
    Dictionary<string, string>? queryParameters,
    int pageSize = 100);

var all = await _restClient.GetAllRecordsAsync(
    EntityNames.TestAutoWorkflowDetail,
    new Dictionary<string, string> { { "Filter", filter } });
// all.Records holds every match; all.TotalCount == all.Records.Count
```

Implementation (`RestClient.cs:173-214`): a `while (true)` loop that requests
`pageSize`/`pageNumber` pages via the same record facade and accumulates. It breaks on **(a)** an
empty page, **(b)** `all.Count >= page.TotalCount`, or **(c)** a short final page
(`page.Records.Count < pageSize`) — correct for anything from 0 rows to millions. The returned
`RecordResult` is rebuilt with `Records = all` and **`TotalCount = all.Count`** (the accumulated
count, *not* the server's original `TotalCount`), carrying `StatusCode`/`HttpErrorMessage` forward
from the last page fetched.

`WebUIDataFacade` carries a parallel `GetAllRecordsAsync(string entityName, int pageSize = 100)`
with identical loop and termination logic (`WebUIDataFacade.cs:190-226`) — it takes no query
parameters.

**Which to call:**

| Need | Method |
|---|---|
| Every matching record | `GetAllRecordsAsync(entity, queryParams)` |
| One explicit page (UI grid, sampling, smoke test) | `GetRecordsAsync(entity, attrs, queryParams, pageSize, pageNumber)` |
| A known-tiny result (single-record filter, config lookup) | `GetRecordsAsync(entity, queryParams)` — acceptable, but state the assumption in a comment |
| Records for a known code list | `GetRecordsByCodesAsync(...)` — also paged, `pageSize` defaults to **50**; loop or raise it for >50 codes |

## Examples

Full scenario test showing factory-based client creation with a non-default subject area:

```csharp
[TestInitialize]
public new void Setup()
{
    base.Setup();
    var factory = ServiceProvider.GetRequiredService<IRestClientFactory>();
    var config = new ScenarioConfiguration();
    _restClient = factory.GetClient(config, RestSubjectArea.Profisee);
}
```

Adding attribute values to a `Record` before posting:

```csharp
var rec = new Record { Code = "1000000", Name = "RestClient - Batch Record 1000000" };
rec.AddAttribute("Color", colorCode);          // Domain attribute: use code string
rec.AddAttribute("Description", "Text_1234");  // FreeForm Text
rec.AddAttribute("Price", 42);                 // FreeForm Number
rec.AddAttribute("CreatedOn", DateTime.UtcNow.ToString("o")); // FreeForm DateTime
```

EntityDataFacade path-building pattern (production HTTP layer):

```csharp
pathAndQueryBuilder
    .Clear()
    .ServiceCall(HttpRequestConstants.Services.Entities)
    .AddPathSegment(entityName);
var path = pathAndQueryBuilder.Build().TrimStart('/');
```

## Sources

- `TestAuto.Shared/Interfaces/IRestClient.cs`
- `TestAuto.Shared/Interfaces/IRestClientFactory.cs`
- `TestAuto.Shared/Rest/RestSubjectArea.cs`
- `TestAuto.Shared.Http/Rest/RestClient.cs` (`GetRecordsAsync` overloads :150-171; `GetAllRecordsAsync` :173-214; `GetRecordsByCodesAsync` :216+)
- `TestAuto.Shared.Http/Facades/HttpClientFacade.cs`
- `TestAuto.Shared.Http/Facades/EntityDataFacade.cs`
- `TestAuto.Shared.Http/Facades/WebUIDataFacade.cs` (parallel `GetAllRecordsAsync` :190-226)
- `Testing.SpeedMerchants.Integration/Tests/RESTGateway/Client/BaseRestClientTest.cs`
- `Testing.SpeedMerchants.Integration/Tests/RESTGateway/Client/RestQueryTests.cs`
- `Testing.SpeedMerchants.Integration/Helpers/BaseTest.cs`
