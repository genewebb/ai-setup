---
name: testauto-record-repository
description: >
  Repository and Record access patterns for TestAuto. Use when adding a new entity to a
  project, migrating from DTOs to Records, implementing SafeGetValue or Record.AddAttribute,
  following the one-repository-per-project rule, or fixing Razor RZ9980 generic type errors.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Record and Repository Patterns

> **Scope**: speed-merchants (all TestAuto projects)
> **Source**: `TestAuto/Documentation/MigrateFromDTOs.md`

TestAuto uses the Profisee `Record` type directly as the primary data transfer object, replacing custom DTOs. Every project follows a **one-repository-per-project** pattern using `IRestClient` for external calls and `WebUIDataFacade` for web UI paging.

---

## One-Repository-Per-Project Rule

| Project | Interface | Implementation | Notes |
|---|---|---|---|
| `TestAuto.Web` | `IWebUiRepository` | `WebUiRepository` | One `WebUIDataFacade` shared across all entities; **DI-registered** |
| `TestAuto.Matching` | `IRecordPoolRepository` | `RecordPoolRepository` | Instantiated per-scenario with a connection string (**not** DI-registered) |
| `TestAuto.Connect` | `IConnectExecutionRepository` | `ConnectExecutionRepository` | Connect execution metrics access |

`IWebUiRepository`/`WebUiRepository` is the only **DI-registered**, `WebUIDataFacade`-backed repository in the solution. `TestAuto.Matching` (`IRecordPoolRepository`/`RecordPoolRepository`, instantiated per-scenario with a connection string rather than resolved from DI) and `TestAuto.Connect` (`IConnectExecutionRepository`/`ConnectExecutionRepository`) each follow the same one-repository-per-project pattern. Other projects (`TestAuto.Metrics`, `TestAuto.Records`) call `IRestClient` directly without a repository layer.

**Rule**: Each project has at most one repository interface, one implementation, and one DI registration. Add methods for new entities to the existing repository — never create a second repository class for the same project.

```csharp
// Register single repository for all entities in the project (WebModuleRegistrar.cs)
services.AddScoped<IWebUiRepository, WebUiRepository>();
```

---

## Record Construction

Use `AddAttribute()` to set values:

```csharp
var record = new Record();
record.AddAttribute("Name", "Test Name");
record.AddAttribute("Status", "Active");
record.AddAttribute("CreatedAt", DateTime.UtcNow);
```

### Code Generation (Create with auto-generated code)

```csharp
var response = await _restClient.CreateRecordsWithDetailAsync(EntityName, new List<Record> { record });
var createdResponse = response.GetContent();
if (createdResponse?.CreatedRecordCodes?.Count > 0)
    return createdResponse.CreatedRecordCodes[0];
```

---

## SafeGetValue — Type-Safe Property Access

```csharp
using TestAuto.Shared.Extensions;

var status    = record.SafeGetValue<string>("Status");
var progress  = record.SafeGetValue<int>("Progress");
var startedAt = record.SafeGetValue<DateTime?>("StartedAt");
```

> Missing `using TestAuto.Shared.Extensions` produces CS1061: 'Record' does not contain a definition for 'SafeGetValue' and no accessible extension method 'SafeGetValue' ... are you missing a using directive? (`SafeGetValue` is an extension method, so the missing-using diagnostic is CS1061, not CS1929.)

---

## Razor Generic Type Pitfall (RZ9980)

The Razor compiler treats `<string>` in method calls as an unclosed HTML tag.

**Broken:**
```razor
@GetRecord().SafeGetValue<string>("Name")
```

**Fixed** — wrap in parentheses:
```razor
@(GetRecord().SafeGetValue<string>("Name"))
@(GetRecord().SafeGetValue<int?>("Count")?.ToString("N0") ?? "-")
```

---

## Type Conversion — Record → Specific Type

When a service requires a concrete type but you receive a `Record`:

```csharp
var configRecord = request.SafeGetValue<Record>("Configuration");
var configJson   = JsonConvert.SerializeObject(configRecord);
var config       = JsonConvert.DeserializeObject<MySpecificType>(configJson);
if (config == null)
    return BadRequest("Invalid configuration format");
```

---

## Variable Scope for Catch Blocks

Declare before the `try` block so the catch block can reference the variable:

```csharp
MyType? config = null;
try
{
    config = JsonConvert.DeserializeObject<MyType>(json);
    // ... use config
}
catch (Exception ex)
{
    _logger.LogError(ex, "Failed to process {Config}", config?.Name);
    return StatusCode(500, "Failed to process request");
}
```

---

## When to Migrate from DTOs to Records

Migrate when:
- The entity maps directly to a Profisee platform entity accessible via `IRestClient`
- The data flows through the Profisee CDP layer and benefits from an automatic audit trail
- You need code generation (`CreatedRecordCodes`) from the platform

Keep DTOs when:
- The data is internal-only and never round-trips to the Profisee REST API
- The shape is complex and the Record key-value model adds more friction than value

### WorkloadExecution Table Role

`WorkloadExecution` is the canonical reference implementation for migration work. It stores execution state as `Record` objects against this entity rather than custom DTO classes. The entity framework handles the audit trail automatically — no manual timestamp or user fields required.

---

## 6-Phase Migration Checklist

When migrating a subject area from DTOs to Records:

| Phase | Action | Safety Gate |
|---|---|---|
| **1** | Create/update repository interface + implementation using `Record` | — |
| **2** | Register in DI | — |
| **3** | Write comprehensive CRUD test (Create → Get → Update → Get → List → Delete → Get=null) | **MUST PASS before Phase 4** |
| **4** | Update controllers: change method signatures to `ActionResult<Record>` | After CRUD test passes |
| **5** | Update Razor components: wrap generic calls in `()`, fix nullable `ToString` | After Phase 4 compiles |
| **6** | Remove old DTOs, old repository, unused using statements | After Phase 5 tests pass |

> Never delete existing DTOs or modify UI until the CRUD test from Phase 3 passes completely.

### CRUD Test Template

```csharp
[TestMethod]
public async Task {Entity}Repository_FullCrudOperations_ShouldWorkCorrectly()
{
    // 1. CREATE
    var record = CreateTest{Entity}Record();
    var code   = await _repository.Create{Entity}Async(record);
    Assert.IsNotNull(code);
    Assert.IsFalse(string.IsNullOrEmpty(code));

    // 2. GET
    var retrieved = await _repository.Get{Entity}Async(code);
    Assert.IsNotNull(retrieved);
    Assert.AreEqual(code, retrieved.SafeGetValue<string>("Code"));

    // 3. UPDATE
    var updated = retrieved.Clone();
    updated.SetValue("SomeField", "UpdatedValue");
    Assert.IsTrue(await _repository.Update{Entity}Async(updated));

    // 4. GET after update
    var afterUpdate = await _repository.Get{Entity}Async(code);
    Assert.AreEqual("UpdatedValue", afterUpdate.SafeGetValue<string>("SomeField"));

    // 5. LIST
    var list = await _repository.Get{Entities}PagedAsync(pageSize: 10, pageNumber: 1);
    Assert.IsTrue(list.Records.Any(r => r.SafeGetValue<string>("Code") == code));

    // 6. DELETE
    Assert.IsTrue(await _repository.Delete{Entity}Async(code));

    // 7. GET after delete — must return null
    Assert.IsNull(await _repository.Get{Entity}Async(code));
}
```

---

## Sources

- `TestAuto\Documentation\MigrateFromDTOs.md`

## Related: Production Sync (raw IRestClient, not repositories)

The Production Sync feature (`TestAuto.Web\Services\ProductionSync\`, page `/production-sync`) works
BELOW the repository layer on purpose: it moves records between two arbitrary Profisee instances via
`ISyncEndpointFactory`-built `IRestClient`s (paged `GetRecordsAsync` pageSize 1000,
`CreateRecordsAsync` skeletons, `UpdateRecordsAsync(isUpsert:false)`, `BulkDeleteRecordsAsync`
clearReferencesBeforeDelete). Do not route it through entity repositories — repositories bind to the
fixed subject-area clients and a single entity shape; sync must stay entity-agnostic and
endpoint-agnostic. Gotcha inherited here: always pass explicit pageSize (default truncates at 50).
