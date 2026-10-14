---
name: testauto-http-facades
description: >
  HttpClientFacade abstract base class, domain-specific facades, and HTTP delegating
  handlers in TestAuto.Shared.Http. Use when creating a new facade for a Profisee REST
  subject area, understanding async vs legacy sync HTTP methods, debugging HTTP response
  parsing, registering a facade in DI, adding LoggingHandler/ApiKeyHandler/CurlLoggingHandler
  to an HttpClient pipeline, or understanding how request/response logging and auth injection
  work in the HTTP pipeline.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto HTTP Facades

> **Scope**: speed-merchants (TestAuto.Shared.Http)
> **Source**: `TestAuto.Shared.Http\Facades\HttpClientFacade.cs` + domain facade classes

TestAuto wraps `HttpClient` calls behind typed facades. Each subject area (Records, Entities, Monitor, Web UI) gets a concrete facade that inherits from `HttpClientFacade`. The base class provides standardized JSON parsing, error logging, and HTTP verb methods so concrete facades only implement the domain-specific API surface.

---

## Rule: reuse the path/query utility — never hand-roll URLs

**Every REST call must build its path and query string through the established utility for that client. Never concatenate URLs or query strings ad hoc.**

- **Facades** (`HttpClientFacade` subclasses): build relative paths via `PathAndQueryBuilder` and call through `CallPostAsync`/`CallPatchAsync`/`CallDeleteAsync` (relative) or the `*FullPath` overloads (absolute). Do not assemble query strings by hand inside a facade method.
- **`ConnectRestClient`** (non-facade): use its private `BuildPath(resource, extraSegments, queryParams)` helper — it joins segments, prefixes the API version, and `HttpUtility.UrlEncode`s every key/value. Every method (`GetBatchStatusAsync`, `GetJobActivitiesByBatchCodeAsync`, `FindLatestBatchByStrategyNameAsync`, …) goes through it.
- Reference path segments and attribute/query names from the existing constants (`HttpRequestConstants.PathSegments`, `AttributeNames`, `ConnectConstants`) — not inline string literals.

**Why**: one tested builder guarantees consistent encoding, segment joining, and gateway-version prefixing. Hand-rolled URLs reintroduce encoding bugs (un-escaped filter values, double slashes) and drift from the gateway contract.

✅ Correct — new Connect call reuses `BuildPath` (`ConnectRestClient.FindLatestBatchByStrategyNameAsync`, `TestAuto.Connect/Services/ConnectRestClient.cs:49-63`):

```csharp
var path = BuildPath(
    HttpRequestConstants.PathSegments.Connect.BatchJobActivities,
    queryParams: new Dictionary<string, string>
    {
        [AttributeNames.Filter] = $"[{ConnectConstants.JsonBatchStrategyNameField}] eq '{strategyName}'",
        ["orderBy"] = $"[{ConnectConstants.JsonEnterDTMField}] desc",
        ["PageSize"] = "1",
        ["Attributes"] = $"[{AttributeNames.Code}],[{ConnectConstants.JsonProcessingStateField}],[{ConnectConstants.JsonEnterDTMField}]"
    });
return await GetAsync(path, "GET Connect/FindLatestBatchByStrategyName", ct).ConfigureAwait(false);
```

**Don't drop the `Attributes` key.** Every `ConnectRestClient` GET projects an explicit attribute
list rather than letting the gateway return its default shape — `GetBatchStatusAsync` (`:37-47`) asks
for `[ProcessingState],[PageSize],[InvocationMode]`, `GetJobActivitiesByBatchCodeAsync` (`:65-78`)
asks for `[RecordCount]`. `Attributes` is an ordinary query-param entry, so it goes through
`BuildPath` and gets URL-encoded with everything else; its value is a comma-joined list of
bracketed attribute names built from `AttributeNames`/`ConnectConstants`, never inline literals.
Omit it and the caller's `data[0]` property lookup silently finds nothing.

❌ Wrong — hand-rolled URL + query, bypassing the builder (breaks encoding, ignores constants):

```csharp
var path = $"v1/Connect/BatchJobActivities?filter=[Name] eq '{strategyName}'&orderBy=[$EnterDTM] desc";
```

---

## Base Class Anatomy (`HttpClientFacade`)

**Location**: `TestAuto.Shared.Http/Facades/HttpClientFacade.cs`

### Constructor

```csharp
protected HttpClientFacade(
    HttpClient httpClient,
    IAuthenticationKeyValue authKey,
    ILogger logger)

// Overload with explicit PathAndQueryBuilder:
protected HttpClientFacade(
    HttpClient httpClient,
    PathAndQueryBuilder pathAndQueryBuilder,
    IAuthenticationKeyValue authKey,
    ILogger logger)
```

All three fields are stored as `protected` members so concrete facades can use them directly.

### Response Helpers

| Method | Returns | Use when |
|---|---|---|
| `GetGatewayResponseAsync(HttpResponseMessage)` | `Task<JsonResponse>` | Response body is raw JSON (JToken) |
| `GetGatewayResponseAsync<T>(HttpResponseMessage)` | `Task<JsonResponse<T>>` | Response body is a `DataResponse<T>` wrapper |

Both async overloads:
- Dispose the `HttpResponseMessage` in a `finally` block.
- On non-2xx: log `ErrorWithTag(LogTagConstants.RestApi, ...)`. The non-generic overload returns a `JsonResponse` whose `ResponseContent` is a `{ status, error }` JObject; the generic `GetGatewayResponseAsync<T>` returns `ResponseContent = null` (only `StatusCode` is set — check it, don't expect an error body).
- On 2xx: deserialize the body and return a populated `JsonResponse`.

### Async Call Methods (use these)

```csharp
// Relative path via PathAndQueryBuilder
protected Task<HttpResponseMessage> CallPostAsync(string serviceToCall, JToken content, string? contentTypeOverride = null)
protected Task<HttpResponseMessage> CallPatchAsync(string serviceToCall, JToken content)
protected Task<HttpResponseMessage> CallDeleteAsync(string serviceToCall)

// Absolute path (bypasses PathAndQueryBuilder)
protected Task<HttpResponseMessage> CallGetAsync(string fullPath)
protected Task<HttpResponseMessage> CallPutAsync(string fullPath, JToken content)
protected Task<HttpResponseMessage> CallDeleteAsync(string fullPath, JToken content)
protected Task<HttpResponseMessage> CallPostAsyncFullPath(string fullPath, JToken content, string? contentTypeOverride = null)
protected Task<HttpResponseMessage> CallDeleteAsyncFullPath(string fullPath)
```

### No synchronous HTTP methods

The base class exposes **only** async `Call*Async` methods — there are no synchronous HTTP methods (no `callRestApiGet/Post/Patch/Put/Delete`, no sync `GetGatewayResponse`). Every HTTP call goes through the async API.

---

## The gateway pages metadata endpoints — and truncates silently

`GET /Entities` and `GET /Entities/{e}/Attributes` page at a **server default of ~50** and simply stop.
Nothing in the response says the list was cut, so an unpaged read looks like a complete, smaller model.

- **`EntityDataFacade.GetEntitiesAsync`** now pages at `PageSize 100` and stops on a short page
  (`:128-160`), with a **seen-set guard** (`HashSet`, `:131`, `:160`) so a gateway that ignores paging
  parameters cannot spin forever — a page contributing nothing new means the set is complete.
- **It THROWS on a non-success response** (`:146`) rather than returning an empty list. This matters: a
  **401 once masqueraded as "every entity is missing"**, which reads as a catastrophic model problem rather
  than an auth problem.
- **`AttributeDataFacade.GetAttributesAsync`** sends an explicit `PageSize 1000` (`:93`).
- `GetEntityAsync` treats **404 as non-existence** (returns null) but throws on every other non-success
  status (`:216-223`) — absence and failure are different answers.
- `RecordDataFacade.PutMatchAsync` no longer deserializes an error body into an all-null `MatchResponse`,
  which previously turned a failure into a success-shaped object full of nulls.

## Failures carry the server's payload — `ResponseBase<T>.RawErrorBody`

`ResponseBase<T>` gained `string? RawErrorBody` (`TestAuto.Shared/Rest/ResponseBase.cs:26`), filled by both
the typed and untyped `JsonResponse` paths (`HttpClientFacade.cs:77`, `:115`).

The rule: **on failure `ResponseContent` must be null** — the body is not a `T`, and forcing it through
deserialization is what produced the all-null objects above. The verbatim server payload travels on
`RawErrorBody` instead, so the caller can surface the real reason without the type system pretending the
error was a success value.

## Async vs Sync Decision Table

| Scenario | Use |
|---|---|
| New facade method | Async (`CallPostAsync`, `GetGatewayResponseAsync`) |
| Calling from a Blazor component | Async only — sync `.Result` deadlocks SignalR |
| Relative path via `PathAndQueryBuilder` | `CallPostAsync(serviceToCall, ...)` |
| Known absolute URL | `CallPostAsyncFullPath(fullPath, ...)` |
| JSON-patch content type | `CallPatchAsync` — hardcodes `application/json-patch+json` |

---

## Known Domain Facades

| Facade | Subject Area | Key Operations |
|---|---|---|
| `RecordDataFacade` | Records REST | CRUD for records, batch operations |
| `EntityDataFacade` | Entities/attributes REST | Entity and attribute metadata queries |
| `MonitorDataFacade` | Monitor activities | Querying monitor activity log |
| `WebUIDataFacade` | ScenarioMgt | Web UI specific Profisee calls |

---

## Creating a New Facade

1. Create the facade class inheriting `HttpClientFacade`:

```csharp
using TestAuto.Shared.Http.Facades;
using TestAuto.Shared.Interfaces;

namespace TestAuto.MySubsystem.Facades;

public class MySubjectFacade : HttpClientFacade
{
    public MySubjectFacade(HttpClient httpClient, IAuthenticationKeyValue authKey, ILogger logger)
        : base(httpClient, authKey, logger) { }

    public async Task<JsonResponse> GetThingAsync(string thingId)
    {
        var path = $"v1/MySubject/{thingId}";
        using var httpResponse = await CallGetAsync(path).ConfigureAwait(false);
        return await GetGatewayResponseAsync(httpResponse).ConfigureAwait(false);
    }

    public async Task<JsonResponse> CreateThingAsync(JObject payload)
    {
        using var httpResponse = await CallPostAsync("v1/MySubject", payload).ConfigureAwait(false);
        return await GetGatewayResponseAsync(httpResponse).ConfigureAwait(false);
    }
}
```

2. Register in the module registrar (factory pattern — inject `IHttpClientFactory` and `Func<RestSubjectArea, IAuthenticationKeyValue>`):

```csharp
services.AddScoped<MySubjectFacade>(sp =>
{
    var httpClientFactory = sp.GetRequiredService<IHttpClientFactory>();
    var httpClient = httpClientFactory.CreateClient(HttpClientNames.MyClient);
    var authKeyFor = sp.GetRequiredService<Func<RestSubjectArea, IAuthenticationKeyValue>>();
    var authKey = authKeyFor(RestSubjectArea.MyArea);
    var logger = sp.GetRequiredService<Serilog.ILogger>();
    return new MySubjectFacade(httpClient, authKey, logger);
});
```

3. Name the `HttpClient` registration in the shared HTTP setup (typically `Program.cs` or `SharedModuleRegistrar`) so `IHttpClientFactory` can create it with the correct `BaseAddress` and delegating handlers.

---

## Notes

- `GetGatewayResponseAsync` always disposes the `HttpResponseMessage` via `finally` — do not dispose it yourself after calling this method.
- `PathAndQueryBuilder` is mutable. The default constructor creates a fresh instance per facade — do not share a single instance across threads or calls.
- `ConnectRestClient` does **not** extend `HttpClientFacade` — it uses `IHttpClientFactory` directly and has its own `ParseResponseAsync`. See `testauto-connex-service` skill.

---

## HTTP Delegating Handlers

Three `DelegatingHandler` implementations intercept the `HttpClient` pipeline for cross-cutting concerns. All live in `TestAuto.Shared.Http/Rest/`.

### `LoggingHandler`

Logs every request/response. Uses `Microsoft.Extensions.Logging.ILogger<LoggingHandler>` — **not**
Serilog and **not** the `*WithTag` helpers, so these events carry no `LogTag` property.

Message templates quoted verbatim from `TestAuto.Shared.Http/Rest/LoggingHandler.cs` — match these
exactly when writing a Seq query, since a template mismatch returns nothing:

| Event | Level | Template (verbatim) | Line |
|---|---|---|---|
| Request line | `Information` | `"→ {Method} {Uri}"` | `:23` |
| Request body | `Debug` | `"Request Body:\n{Body}"` — guarded by `_logger.IsEnabled(LogLevel.Debug) && request.Content != null` | `:29` |
| Response summary | `Information` | `"← {Method} {Uri} responded {StatusCode} in {Elapsed}ms"` | `:37` |
| Error response body | `Error` | `"Response Body:\n{Body}"` — always on non-2xx; `"<no content>"` when `response.Content` is null | `:49` |
| Success response body | `Debug` | `"Response Body:\n{Body}"` — same template as the error case, different level | `:55` |

Two details that bite when querying:

- The response summary contains the literal word **`responded`** between `{Uri}` and `{StatusCode}`.
  A search for `← {Method} {Uri} {StatusCode}` will not match.
- `{StatusCode}` is captured as `(int)response.StatusCode` (`:40`), so it is the numeric **404**, not
  the enum name `NotFound`. Filter on the integer.
- Success and error bodies share the identical `Response Body:\n{Body}` template — the only
  discriminator is the log **level**, not the message.

### `ApiKeyHandler`

Injects the Profisee API key into every outgoing request header. Uses Serilog `ILogger`.

```csharp
// Reads key name and value from IAuthenticationKeyValue
// Skips injection if the header is already present (logs Debug via DebugWithTag)
```

### `CurlLoggingHandler`

Converts every outgoing request into a CURL command and logs it at `Information` level under `LogTagConstants.RestApi`. Useful for reproducing API calls manually.

```
CURL Command: curl -X POST -H "Authorization: Bearer ..." -d "{...}" "https://..."
```

### Registration Order

Handlers execute in the order they are registered on the `HttpMessageHandler` chain. Typical order:

```csharp
services.AddHttpClient("MyClient")
    .AddHttpMessageHandler<ApiKeyHandler>()      // 1. inject auth key
    .AddHttpMessageHandler<LoggingHandler>()     // 2. log with auth present
    .AddHttpMessageHandler<CurlLoggingHandler>() // 3. emit curl (optional, dev only)
    ;
```

Register `ApiKeyHandler` before `LoggingHandler` so auth headers appear in the logged request.

---

## Sources

- `TestAuto.Shared.Http\Facades\HttpClientFacade.cs`
- `TestAuto.Shared.Http\Rest\PathAndQueryBuilder.cs`
- `TestAuto.Shared.Http\Rest\LoggingHandler.cs`
- `TestAuto.Shared.Http\Rest\ApiKeyHandler.cs`
- `TestAuto.Shared.Http\Rest\CurlLoggingHandler.cs`
- `TestAuto.Web\AutoRegistration\WebModuleRegistrar.cs` (facade registration example)
