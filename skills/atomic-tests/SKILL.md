---
name: atomic-tests
description: CRITICAL standard for speed-merchants tests — every test must be atomic (self-contained, order-independent, self-provisioning, self-cleaning). Use when writing, fixing, or reviewing any unit or integration test, especially ones that touch the shared live Profisee/ConnEx/ScenarioMgt instances.
---

# Atomic Tests (speed-merchants)

> **Scope**: All tests in `Testing.SpeedMerchants.*`. This is a hard requirement, not a preference.

A test is **atomic** when it can run **in isolation, in any order, repeatedly, in parallel**, with **no dependence on pre-existing instance/environment state** and **no state left behind**. Non-atomic tests are what caused the integration suite's cascading failures (182 leaked model entities corrupted the shared `CdpService` cache; parallel runs raced; "read the latest record" tests read another test's data).

## The five rules

1. **Self-provision every prerequisite.** The test creates the entities/records/configs/strategies/scenarios it needs in Arrange. Never "find an existing X and act on it" — if X must exist, the test creates X. Never depend on config like `ConnectTests:KnownStrategyName` pointing at hand-made data.
2. **Tear down everything, always.** Delete what you created in cleanup. Track created resource ids in a list and delete each tolerantly (one failed delete must not strand the rest).
3. **Survive partial Setup failure.** MSTest does **not** run `[TestCleanup]` when `[TestInitialize]` throws. So `Setup` must wrap provisioning in `try { … } catch { TearDown(); throw; }`, and `TestCleanup` calls the same teardown. (See `RecordGeneratorTests` for the canonical shape.)
4. **Be idempotent against crashed prior runs.** Unique-name per run where possible; and/or pre-delete by the resource's unique key before creating, so a leftover from a crash can't cause a 409/collision. ConnEx configs are name-unique — pre-delete by name.
5. **Serialize shared-model mutators.** Any test class that creates/deletes model entities or calls `ReloadCache` must be `[DoNotParallelize]` — `CdpService..ctor` reloads the model cache, so a concurrent delete in another class throws `KeyNotFoundException` in `Profisee.Platform.Utilities.Cdp.Cache.MetadataCache`.

## Schema vs data

- **Model schema** (entities + attributes) may be assumed to exist — provision it **once** out-of-band (e.g. the `TestAutoValidationLogs` entity). A test must not create/delete the entity *definition* every run.
- **Records / ConnEx configs / strategies / scenarios** are *data* — each test creates and deletes its own.

## Instance topology (which client for which entity)

Two distinct Profisee instances are reached by subject area — sending an entity to the wrong one yields "entity does not exist":

| Entities | Client | MCP to inspect |
|---|---|---|
| Model entities (RetailClient, Color_*, etc.), ConnEx strategy bindings | `RestSubjectArea.Profisee` (default `IRestClient`) | `profiseeMcpLocal`, SQL `corpltr94_profisee` (`meta.vSYSTEM_SCHEMA_ENTITY/ATTRIBUTES`) |
| TestAuto config entities: `TestAutoScenarios`, `TestAutoTemplates`, `TestAutoValidationLogs`, `WorkloadExecution`, `Scenario`, `ExecutionStatus` | `RestSubjectArea.ScenarioMgt` (see `WebUiRepository`) | `speedMcpLocal` |

Build a non-default client with `factory.GetClient(new ScenarioConfiguration(), RestSubjectArea.ScenarioMgt)`. `IEntityValidationService` and the default `IRestClient` are bound to **Profisee** — construct your own against ScenarioMgt for TestAuto entities.

## Gotchas that masquerade as test bugs

- **`GetRecordsAsync` silently caps at the server-default first page (50)** and truncates. Use `GetAllRecordsAsync(entity, query, pageSize)` whenever you need the full set (e.g. to find a just-created record, or to enumerate scenarios). See `[[project_getrecords_pagesize_truncation]]`.
- **ConnEx delete is a query param, not a path segment.** `DELETE /v1/Connect/Configurations/{id}` → **405**. Correct: `DELETE /v1/Connect/Configurations?ConfigurationUids={id}` (`ConnExConstants.ConfigurationDeleteParam`; likewise `IntegrationStrategyUids`, `ServiceProviderUids`). Accept 200/201/204/207/404.
- **Profisee trims surrounding whitespace on `Name`.** A name built from `$"{a}-{b}-{desc}"` where `desc` ends in a space won't round-trip — `.Trim()` it before create and compare.
- **Import RESPONSE records use PascalCase** top-level keys (`Configuration`, `Name`); only the nested credential `configuration.value` stays lowercase. Read JTokens with the response's actual casing.
- **`importData` must be a JSON-encoded STRING**, not a raw object, or the gateway returns 400 "Unexpected character … Path 'importData'".

## Canonical atomic shape

```csharp
[TestClass]
[DoNotParallelize] // only if it mutates the shared model / ReloadCache
public class FooTests : BaseTest
{
    private readonly List<string> _createdCodes = new();
    private IRestClient _client = null!;

    [TestInitialize]
    public new void Setup()
    {
        base.Setup();
        var factory = ServiceProvider.GetRequiredService<IRestClientFactory>();
        _client = factory.GetClient(new ScenarioConfiguration(), RestSubjectArea.ScenarioMgt);
        try { /* provision prerequisites, track ids in _createdCodes */ }
        catch { TearDown(); throw; }   // MSTest skips TestCleanup on Setup throw
    }

    [TestCleanup] public void Cleanup() => TearDown();

    private void TearDown()
    {
        foreach (var code in _createdCodes)
            try { _client.DeleteRecordsAsync(EntityName, new[]{code}.ToList(), true).GetAwaiter().GetResult(); } catch { }
        _createdCodes.Clear();
    }
}
```

## Sources / related

- `Testing.SpeedMerchants.Integration/Data/RecordGeneratorTests.cs` — self-clean-on-Setup-throw pattern
- `Testing.SpeedMerchants.Integration/Tests/RESTGateway/Connect/ConnExServiceConfigImportTests.cs` — name-based idempotent pre-clean + query-param delete
- `MSTestSettings.cs` — method-level parallelization (why `[DoNotParallelize]` matters)
- Memory: `[[feedback-tests-must-be-atomic]]`, `[[project_getrecords_pagesize_truncation]]`
