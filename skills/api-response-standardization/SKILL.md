---
name: api-response-standardization
description: >
  BaseApiController and the API response envelope types in TestAuto.Web. Use when creating an API
  controller, returning standardized error/success/paginated responses, choosing a controller base
  class, picking between BaseApiController's envelopes and the ApiSuccessResponse<T>/ApiErrorResponse
  pair the Blazor client actually uses, or disambiguating the three ErrorResponse types.
  BaseApiController is only partially adopted — check adoption before assuming a controller follows
  it.
---

Repo: speed-merchants (paths below are repo-relative)

# API Response Standardization

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: `TestAuto.Web/Controllers/BaseApiController.cs`

> [!WARNING]
> **`BaseApiController` is the intended standard, not the established practice.** Read the
> "Adoption reality" section below **before** you describe this pattern to anyone or assume a
> controller follows it. Exactly one controller derives from it, and its three helper methods have
> zero call sites anywhere in the repo. The envelope actually on the wire is
> `TestAuto.Shared.Common.ApiSuccessResponse<T>` / `ApiErrorResponse`, which has a **different
> shape**.

`BaseApiController` provides three helper methods for constructing consistent JSON responses and declares standard `ProducesResponseType` attributes for 400/401/403/404/500 error codes. The sections below describe the type **as designed**; adoption is covered immediately after.

---

## Adoption reality (verified 2026-07-27)

Counts drift — re-derive with
`grep -rnE "class [A-Za-z0-9_]+Controller *: *[A-Za-z0-9_]+" TestAuto.Web/Controllers` plus a
bare-name grep for each helper. What that produced:

### Base-class census — 1 of 22

| Base | Count | Controllers |
|---|---|---|
| `BaseApiController` | **1** | `ExecutionMonitoringController.cs:14` |
| `ControllerBase` (direct) | **21** | `Developer`, `Diagnostics`, `ExecutionControl`, `Health`, `Jobs`, `Metrics`, `Migration`, `Performance`, `ScenarioEditor`, `ScenarioExecution`, `ScenarioRecords`, `Scenarios`, `Secrets`, `UtilityScripts`, `V1/ScenarioEditor`, plus the `sealed` ones: `FileExport`, `FileSystem`, `Import`, `ScenarioVersioning`, `Template`, `Validation` |

`Controllers/WorkflowManagementController.cs` was a 1-byte empty file and **has been deleted** — a
repo-wide grep for the name now returns zero hits. There is no workflow-management controller; workflow
management is a Blazor-page + service concern (see [[testauto-workflow-execution]]).

### Helper adoption — zero

A bare-name grep across the whole repo finds each helper exactly once, at its own definition:

| Helper | Definition | Call sites |
|---|---|---|
| `CreateErrorResponse` | `BaseApiController.cs:25` | **0** |
| `CreateSuccessResponse<T>` | `BaseApiController.cs:53` | **0** |
| `CreatePaginatedResponse<T>` | `BaseApiController.cs:75` | **0** |

Even `ExecutionMonitoringController` — the one derived controller — never calls them. It inherits
only the `[ApiController]` / `[Produces]` / `[ProducesResponseType]` attribute block and then returns
`ApiSuccessResponse` like everyone else (18 references in that file alone). So `SuccessResponse<T>`
and `PaginatedResponse<T>` have **never been serialized by this application**, and the
`ProducesResponseType(typeof(ErrorResponse), …)` declarations advertise a Swagger error shape that no
endpoint actually returns.

### What is actually on the wire — `ApiSuccessResponse<T>` / `ApiErrorResponse`

Defined in `TestAuto.Shared/Common/ApiResponse.cs`, referenced by 12 of the 22 controllers
(`Developer`, `ExecutionControl`, `ExecutionMonitoring`, `FileExport`, `FileSystem`, `Import`,
`Migration`, `ScenarioEditor`, `ScenarioRecords`, `ScenarioVersioning`, `Template`, `Validation`) and
consumed by the Blazor client — e.g. `ExecutionHistory.razor.cs:74` deserializes
`ApiSuccessResponse<IEnumerable<Record>>`.

It is **not** interchangeable with `SuccessResponse<T>`:

| | `SuccessResponse<T>` (`BaseApiController.cs:124`) | `ApiSuccessResponse<T>` (`ApiResponse.cs`) |
|---|---|---|
| `success` bool | absent | **present**, defaults `true` |
| `Data` | `T`, non-nullable, `default!` | `T?`, nullable |
| JSON naming | none — relies on the host serializer's camelCase | explicit Newtonsoft `[JsonProperty("data")]` etc. |
| Construction | `CreateSuccessResponse(...)` protected helper | `ApiSuccessResponse<T>.Ok(data, message)` static factory |
| `Timestamp` | set by the helper | self-initializing `= DateTime.UtcNow` |
| Error partner | `ErrorResponse` (`Message`/`Details`/`Timestamp`/`RequestId`) | `ApiErrorResponse` — adds `success: false`, with `Fail(message, details, requestId)` and `Fail(ex, message, requestId)` factories |

**If you are adding an endpoint today**, match the surrounding controller: derive from
`ControllerBase` and return `ApiSuccessResponse<T>.Ok(...)` / `ApiErrorResponse.Fail(...)`. Adopting
`BaseApiController` instead would change the JSON contract (adding the `success` flag, dropping the
Newtonsoft property names) and break existing Blazor callers. Migrating to `BaseApiController`
wholesale is a real refactor with a client-side half — not a drop-in.

### Three colliding `ErrorResponse` shapes

Beware the name — there are three distinct types and they disagree on the error field:

| Type | Error field |
|---|---|
| `TestAuto.Web.Controllers.ErrorResponse` (`BaseApiController.cs:97`) | `Message` |
| `TestAuto.Web.Models.Responses.ErrorResponse` (`Models/Responses/ErrorResponse.cs`) | `Error` |
| `TestAuto.Shared.Common.ApiErrorResponse` (`TestAuto.Shared/Common/ApiResponse.cs:45`) | `Message` + `Success = false` |

`BaseApiController.cs` has `using TestAuto.Shared.Common;` at the top but declares its own
`ErrorResponse` in the same namespace as the controller, so the unqualified `ErrorResponse` in its
`[ProducesResponseType]` attributes binds to the **local** one. Always qualify, or check the `using`
block, before assuming which shape a signature means.

### Known defect in `CreateErrorResponse`

All five branches of `CreateErrorResponse` pass the body through. The 403 branch is
`403 => StatusCode(403, errorResponse)` (`BaseApiController.cs:39`).

The earlier `Forbid()` defect — which silently discarded the body and its `RequestId`, so a caller got an
empty 403 — **was fixed in 2026-08**. Keep `StatusCode(403, …)`; do not "simplify" it back to `Forbid()`,
which takes no body and would reintroduce the bug.

---

## `BaseApiController`

```csharp
[ApiController]
[Produces("application/json")]
[ProducesResponseType(typeof(ErrorResponse), 400)]
[ProducesResponseType(typeof(ErrorResponse), 401)]
[ProducesResponseType(typeof(ErrorResponse), 403)]
[ProducesResponseType(typeof(ErrorResponse), 404)]
[ProducesResponseType(typeof(ErrorResponse), 500)]
public abstract class BaseApiController : ControllerBase
```

---

## Helper Methods

### `CreateErrorResponse`

```csharp
protected ActionResult<ErrorResponse> CreateErrorResponse(
    string message,
    string? details = null,
    int statusCode = 400)
```

Dispatches to the correct `IActionResult` based on `statusCode` (400→`BadRequest`, 404→`NotFound`, 500→`StatusCode(500,…)`, etc.). Sets `Timestamp = DateTime.UtcNow` and `RequestId = HttpContext.TraceIdentifier`.

```csharp
return CreateErrorResponse("Scenario not found", $"Code: {code}", 404);
```

### `CreateSuccessResponse<T>`

```csharp
protected ActionResult<SuccessResponse<T>> CreateSuccessResponse<T>(T data, string? message = null)
```

Returns `200 OK` with a `SuccessResponse<T>` envelope. Default message: `"Operation completed successfully"`.

```csharp
return CreateSuccessResponse(scenario, "Scenario loaded");
```

### `CreatePaginatedResponse<T>`

```csharp
protected ActionResult<PaginatedResponse<T>> CreatePaginatedResponse<T>(
    IEnumerable<T> data, int pageNumber, int pageSize, int totalCount)
```

Computes `TotalPages`, `HasNextPage`, and `HasPreviousPage` automatically.

---

## Response Envelope Shapes

### `ErrorResponse`

```json
{
  "message": "Scenario not found",
  "details": "Code: ABC",
  "timestamp": "2026-05-20T10:00:00Z",
  "requestId": "0HN5..."
}
```

### `SuccessResponse<T>`

```json
{
  "data": { ... },
  "message": "Scenario loaded",
  "timestamp": "2026-05-20T10:00:00Z",
  "requestId": "0HN5..."
}
```

### `PaginatedResponse<T>`

```json
{
  "data": [ ... ],
  "pageNumber": 1,
  "pageSize": 25,
  "totalCount": 150,
  "totalPages": 6,
  "hasNextPage": true,
  "hasPreviousPage": false,
  "timestamp": "2026-05-20T10:00:00Z",
  "requestId": "0HN5..."
}
```

---

## Sources

- `TestAuto.Web\Controllers\BaseApiController.cs` (the designed standard + its three envelope types)
- `TestAuto.Shared\Common\ApiResponse.cs` (`ApiSuccessResponse<T>` / `ApiErrorResponse` — what is actually returned)
- `TestAuto.Web\Models\Responses\ErrorResponse.cs` (third, `Error`-keyed variant)
- `TestAuto.Web\Controllers\ExecutionMonitoringController.cs` (the only `BaseApiController` subclass)
- `TestAuto.Web\Components\Pages\ExecutionHistory.razor.cs` (client-side `ApiSuccessResponse<T>` deserialization)
