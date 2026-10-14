---
name: dotnet-testing
description: >
  Two test standards in one file — the TestAuto/speed-merchants integration-test base class hierarchy, plus the
  general .NET three-tier testing framework used by platform repos. Use when writing new integration tests,
  understanding how DI is wired in tests, troubleshooting test setup failures, navigating the test suite folder
  structure, the difference between BaseTest and PerformanceBaseTestClass, choosing a tier (Unit vs Integration
  vs Functional) or laying out a new test project, its required files (unittest.runsettings /
  automation.runsettings, BaseTestConfiguration, TestCategories, SettingsRetriever, {Service}AppFactory, Fakes/),
  the one-test-project-per-repository rule and its exceptions, mocks vs fakes vs spies, or waiting on state with
  PollingAssert instead of Task.Delay.
---

# Integration Test Infrastructure

The `Testing.SpeedMerchants.Integration` project contains all integration tests for the speed-merchants TestAuto system. Tests are organized into suites under `Tests/` and share two distinct base class patterns: `BaseTest` (DI-container-per-test, MSTest `[TestInitialize]`) and `PerformanceBaseTestClass` (static assembly-level init via `[AssemblyInitialize]`). Both delegate to `RegisterAllServices` in `TestAuto.DependencyInjection` to mirror production startup exactly.

### The three real test projects

The solution has exactly three, all prefixed `Testing.SpeedMerchants.` — **not** `TestAuto.Testing`,
and **not** the `Testing.{Service}.{Unit,Integration,Functional}` triad described in the generic
platform sections further down this file:

| Project | Packages | Contents |
|---|---|---|
| `Testing.SpeedMerchants.Unit` | MSTest + bUnit (`bunit.web`) + Moq + FluentAssertions | Unit tests, incl. Blazor component tests. The shared base here is **`TestBase`** (`Testing.SpeedMerchants.Unit/Web/Helpers/TestBase.cs:14`) — **not** `BaseTest`, which is Integration-only. Most unit classes inherit nothing at all: at HEAD 4c367fe6 only 5 of 68 `[TestClass]` files derive from `TestBase`. |
| `Testing.SpeedMerchants.Integration` | MSTest + Moq + FluentAssertions + `Profisee.Platform.Utilities.Testing.Extensions.MSTest` | Integration tests. Base classes are `BaseTest` / `PerformanceBaseTestClass`, documented below. |
| `Testing.SpeedMerchants.TestHelpers` | `MSTest.TestFramework` only | Shared helper **library** — no runnable tests. |

There is **no** `Functional` project and no browser/E2E project in this solution.

## When to Use

- "How do I write a new integration test?"
- "Why is my test missing a service registration?"
- "What is the difference between BaseTest and PerformanceBaseTestClass?"
- "Where does DI setup happen in tests?"
- "How are secrets loaded at test startup?"
- "Which test folder should I put this test in?"

## BaseTest

**File**: `Testing.SpeedMerchants.Integration/Helpers/BaseTest.cs`

Abstract base for per-test DI container setup. Runs `[TestInitialize]` before each test method.

Provides:
- `protected IServiceProvider ServiceProvider` — fully-built DI container
- `protected IConfiguration Configuration` — loaded from `appsettings.json` + environment variables
- `protected Serilog.ILogger Logger` — Debug-level console logger

Setup sequence in `Setup()`:
1. Creates a Serilog console logger at `MinimumLevel.Debug`.
2. Builds `IConfiguration` from four layers, in ascending precedence: `appsettings.json` (optional) → `appsettings.integration.json` (optional overlay) → a secrets file (loaded via `IntegrationSecretsLoader.LoadFlattenedSecrets` and added as an in-memory collection) → environment variables.
3. Creates a `ServiceCollection`, adds logger and configuration as singletons.
4. Calls `services.RegisterAllServices(Configuration, includeWebServices: true)` — mirrors `TestAuto.Web/Program.cs` exactly.
5. Registers `IWebUiClient` as a typed `HttpClient` with SSL bypass, base address from `WebUI:HostName`/`WebUI:HttpsPort` (defaults to `localhost:7019`), and a 20-minute timeout.
6. Adds `IHttpContextAccessor`.
7. Builds `ServiceProvider` and calls `ServiceProvider.DisplayRegisteredScenarios()`.

> **Rule**: All tests MUST use `RegisterAllServices` via `BaseTest` — never add one-off service registrations in individual tests.

## PerformanceBaseTestClass

**File**: `Testing.SpeedMerchants.Integration/Core/PerformanceBaseTestClass.cs`

`[TestClass]` base for performance and assembly-scoped tests. Uses `[AssemblyInitialize]` / `[AssemblyCleanup]` so setup runs once per test assembly rather than per test.

Provides static fields shared across all inheriting tests:
- `protected internal static CdpService cdpService`
- `protected internal static IMessageSession messageSession` — ⚠️ **never initialized, always `null`** (see below)
- `protected internal static User superUser`
- `protected internal static MetadataCache metadataCache`
- `protected internal static string BaseFilePath` — from `TestConfiguration:BaseFilePath` config key (default: `{ScratchRoot}\`)
- `protected internal static ILogger Logger`
- `protected internal static IConfiguration Configuration`

Initialization delegates to `ServiceHelper.RegisterServices(Configuration)` (not `RegisterAllServices` directly), then extracts `CdpService`, `User`, `MetadataCache`, and logger from `ServiceHelper`.

> [!warning] `messageSession` is a null trap
> `PerformanceBaseTestClass.cs:19` declares
> `protected internal static IMessageSession messageSession;` but **`AssemblyInitialize` never
> assigns it.** The initializer sets `Configuration`, `BaseFilePath`, `cdpService`, `superUser`,
> `metadataCache`, and `Logger` — `messageSession` is skipped, and no other code in the repo writes
> to it (verified 2026-07-27, HEAD 4c367fe6: the only other `messageSession` hits are
> `TestAuto.Shared/Common/CdpContext.cs:15,20,34,37`, which is that class's own unrelated private
> field).
>
> **Consequence**: any derived test that touches `messageSession` gets an immediate
> `NullReferenceException`, not a helpful "not configured" message. It is effectively dead
> inherited state. If you need NServiceBus messaging in a test, resolve `IMessageSession` from a DI
> container yourself — do not rely on this field. If you are adding messaging support, assign it in
> `AssemblyInitialize` rather than leaving the declaration as-is.

Cleanup calls `Log.CloseAndFlush()`.

On failure, uses `MSTestInitLogger.LogAssemblyInitFailure` and calls `Assert.Fail(...)` so the entire assembly is marked failed rather than silently skipped.

Helper: `GenerateRandomName()` — returns `z{Guid:N}n` (guaranteed unique, sortable to end of lists).

## RegisterAllServices

**File**: `TestAuto.DependencyInjection/ServiceExtensions/RegisterAllServices.cs`
**Class**: `RegisterAllAutoTestServicesExtensions` (extension on `IServiceCollection`)

Signature:
```csharp
public static (IServiceCollection Services, IConfiguration Configuration) RegisterAllServices(
    this IServiceCollection services,
    IConfiguration configuration,
    bool includeWebServices = false,
    bool skipEntityLoad = false,
    Action<IConfigurationBuilder>? configureAdditional = null)
```

Registration order:
1. `IMasterPasswordManager` + `ISecretEncryptionService` (always first, no config needed)
2. Entity-based secrets loaded from `TestAutoSecrets` via ScenarioMgt REST API (`IsActive=Y AND MachineName=<this machine>`) — skipped if `skipEntityLoad: true` or master password not configured. Secrets are decrypted, decompressed, and merged into `IConfiguration`.
3. Hangfire core (skipped if `HangfireDB` connection string absent)
4. `IScenarioResolver`, `RestUrlManagement` (if minimum config present)
5. Logging, caching, rules evaluator, context, CDP, monitor, OData translator, verb services
6. REST services + metrics (if minimum config present: `RestClients:ScenarioMgt:BaseUrl` + `ApiKey`)
7. `IReferenceDataCache`
8. Plugins (`RegisterPlugins`) + scenario management (`AddScenarioManagementServices`)
9. All `IModuleRegistrar` implementations (`RegisterAllModuleServices`)
10. Hangfire servers + recurring jobs (if HangfireDB configured)
11. `SecurityUtility` + `MachineSecretService` (and its focused interfaces: `IMachineSecretService`, `ISecretImportExportService`, `ISecretRotationService`, `IConnectionTestService`)
12. Web services (`AddWebServices`) — only when `includeWebServices: true`

Returns updated `(IServiceCollection, IConfiguration)` tuple so callers can use the enriched configuration after entity secrets are merged in.

Graceful degradation: if ScenarioMgt is unreachable, secrets fail to load, or HangfireDB is absent, the app/tests start in a degraded state with warnings rather than crashing.

## Test Organization

```
Testing.SpeedMerchants.Integration/Tests/
  Cache/               — MemoryCache and domain attribute cache tests
  Cdp/                 — CDP service integration tests
  CommandLine/         — CLI scenario execution tests
  Configuration/       — Configuration loading tests
  Logs/                — Log plumbing: LogDetailServiceTests (Seq + platform-log
                         merge, partial-failure handling), PlatformLogQueryTests
  Matching/            — Matching engine: end-to-end, keyset perf, memory leak,
                         strategy config, activity monitor, record mix/pool,
                         metrics collector, scenario execution, REST load tests
  Performance/         — Performance data helpers
  RESTGateway/
    Attributes/        — Attribute facade tests
    Client/            — REST client query/update/workload tests
    Connect/           — ConnEx facade and import tests
    Entity/            — Entity CRUD, TestAutoEntity, WebUI repo, workload execution,
                         utility step templates, scenario file path audit
    Monitor/           — Monitor data facade tests
    Scenario/          — Test data creation helpers
  ResourceManagement/  — Resource collection unit tests
  Security/            — Client ID and decryption tests
  Utilities/
    Helpers/           — UtilitiesTestBase
    Integration/       — End-to-end, orchestrator, scenario, monitor activity,
                         script locator integration tests
  Workflows/           — Workflow execution tests
```

Key suites:
- **Matching** — largest suite; covers the full matching pipeline, metrics, and performance scenarios
- **RESTGateway** — covers all REST client interactions against live Profisee instances
- **Utilities/Integration** — orchestrator and scenario runner end-to-end flows
- **Logs** — `Tests/Logs/` holds `LogDetailServiceTests` and `PlatformLogQueryTests`

**Folder ↔ namespace convention**: each `Tests/<Area>/` folder maps to the namespace
`Testing.SpeedMerchants.Integration.Tests.<Area>` — e.g. `Tests/Logs/LogDetailServiceTests.cs`
declares `namespace Testing.SpeedMerchants.Integration.Tests.Logs;`. Keep new folders and
namespaces in step.

## Examples

```csharp
// Inheriting BaseTest (per-test DI, most common pattern)
[TestClass]
public class MyServiceTests : BaseTest
{
    [TestMethod]
    public void ShouldDoThing()
    {
        var svc = ServiceProvider.GetRequiredService<IMyService>();
        // act & assert
    }
}

// Inheriting PerformanceBaseTestClass (assembly-scoped static init)
[TestClass]
public class MyPerfTests : PerformanceBaseTestClass
{
    [TestMethod]
    public void ShouldRunFast()
    {
        // cdpService, superUser, metadataCache are already initialized
        var result = cdpService.DoSomething(superUser);
        Assert.IsNotNull(result);
    }
}
```

## Sources

- `Testing.SpeedMerchants.Integration/Helpers/BaseTest.cs`
- `Testing.SpeedMerchants.Integration/Core/PerformanceBaseTestClass.cs`
- `TestAuto.DependencyInjection/ServiceExtensions/RegisterAllServices.cs`

---

# Legacy: Three-Tier Testing Framework (General .NET)

> The content below documents the general three-tier testing pattern used for other .NET repos.
> For speed-merchants integration tests specifically, use the sections above.

> [!important] This section is the **Profisee platform template**, not speed-merchants
> Everything below describes `Profisee.Platform.Testing.{Service}.{Unit,Integration,Functional}`
> repos. Its package list (**NSubstitute**, `Serilog.Sinks.TestCorrelator`, `coverlet.collector`)
> and the `net8.0`/`net6.0` target framework in `references/TestingSetupGuide_v1.md` are **correct
> for those repos** — do not "fix" them, and do not apply them to speed-merchants.
>
> speed-merchants uses **Moq**, not NSubstitute, and has no Functional tier. See the
> "three real test projects" table at the top of this file, and the `testauto-tech-stack` skill.

> **Reference**: Full guidance in `references/TestingSetupGuide_v1.md`. This skill provides triggers, execution order, and verification.

---

## When to Use This Rule

**Apply this rule when the user requests:**
- "Create test structure for this repo"
- "Set up testing for a new service"
- "Refactor tests into three tiers"
- "Add unit/integration/functional tests"
- "Audit or align test infrastructure"

**Scope**: This rule describes the **three-tier model** (Unit, Integration, Functional). It **supersedes** the single-test-project rule when the user explicitly requests three-tier structure or references this testing guide.

---

## Placeholder Resolution

Replace `{Service}` throughout with the service name. Resolve in this order:

1. **User-provided name** — If the user says "for Matching service", use `Matching`
2. **Solution/project name** — Extract from `Services.{X}.Api` or solution name (e.g., `TestAuto` → `TestAuto`, `Matching` → `Matching`)
3. **Ask if ambiguous** — Do not guess; request clarification

**Examples:**
| Source | {Service} |
|--------|-----------|
| `Services.Matching.Api` | `Matching` |
| `TestAuto.sln` | `TestAuto` |
| User: "for the governance service" | `Governance` |

---

## Agent Execution Order (New Repo)

When creating test structure for a **new** service, follow this order:

1. **Create `Testing.{Service}.Unit`**
   - Add `Helpers/BaseTestConfiguration.cs`, `TestCategories.cs`, `Usings.cs`, `unittest.runsettings`
   - Reference Api + Core (and optionally Functional for pure utilities)
   - See the Unit Test Project section for details

2. **Create `Testing.{Service}.Functional`** (before Integration — Integration references it)
   - Add `Helpers/SettingsRetriever.cs`, `AppSettingsHelper.cs`, `Fixtures/TestConfigSettings.cs`
   - Add `Fakes/` (FakeAuthHandler, FakeUserService, FakeSecurityService or equivalents)
   - Add `Factories/{Service}AppFactory.cs` extending `WebApplicationFactory<TEntryPoint>`
   - Add `BaseTestConfiguration.cs` with `[AssemblyInitialize]` / `[AssemblyCleanup]`
   - See the Functional Test Project section for details

3. **Create `Testing.{Service}.Integration`**
   - Reference Functional project
   - Add `BaseTestConfiguration.cs`, `automation.runsettings`
   - Add `TestCategories.cs`, `Usings.cs`
   - See the Integration Test Project section for details

4. **Update `Directory.Packages.props`** with test package versions (MSTest, FluentAssertions, NSubstitute, coverlet.collector, Serilog.Sinks.TestCorrelator)

5. **Verify** — Run verification commands (see below)

---

## Agent Execution Order (Refactor/Audit)

When refactoring an **existing** repo:

1. **Audit** — Inventory tests by tier; identify tests in wrong projects
2. **Consolidate** — Move duplicated fakes/helpers into Functional project
3. **Migrate** — Move tests to correct tier (Unit vs Integration vs Functional)
4. **Replace** — Replace `Task.Delay` with polling helpers where applicable
5. **Stabilize** — Fix flaky tests before adding new coverage
6. **Add regressions** — Add tests for recurring production defects

---

## Tier Selection (IF/THEN Rules)

**Before writing a test, apply this decision path:**

| IF | THEN |
|----|------|
| Behavior can be validated without real I/O (DB, HTTP, files, queues) | **Unit test** |
| Depends on SQL shape, indexes, transactions, or external contracts | **Integration test** |
| Depends on full HTTP pipeline, auth, DI wiring, or serialization | **Functional test** |

**Anti-patterns — DO NOT:**
- Add integration tests for pure business logic → use Unit
- Add functional tests for individual repository queries → use Integration
- Use Functional as a safety net for missing unit tests → fill gaps at Unit tier
- Test the same scenario in all three tiers → one scenario per tier max

---

## Verification Commands

**After creating or refactoring test structure, run:**

```powershell
# Unit tests — must complete in <10 seconds, no environment required
dotnet test "**/Testing.{Service}.Unit.csproj" --settings unittest.runsettings

# Integration — requires env vars (SqlServer, MaestroDb, ServerURL, etc.)
dotnet test "**/Testing.{Service}.Integration.csproj" --settings automation.runsettings

# Functional — requires env vars and may stop IIS app pool
dotnet test "**/Testing.{Service}.Functional.csproj" --settings automation.runsettings
```

**Success criteria:**
- Unit tests: All pass, run time < 10 seconds
- Integration/Functional: All pass when env vars are configured; skip verification if env not available and document in output

---

## Required Files Checklist

| Project | Required Files |
|---------|----------------|
| Unit | `BaseTestConfiguration.cs`, `TestCategories.cs`, `Usings.cs`, `unittest.runsettings` |
| Functional | `SettingsRetriever.cs`, `AppSettingsHelper.cs`, `TestConfigSettings.cs`, `FakeAuthHandler`, AppFactory, `BaseTestConfiguration.cs` |
| Integration | `BaseTestConfiguration.cs`, `automation.runsettings`, `TestCategories.cs`, `Usings.cs` |

---

## Rule Precedence

- **This rule** applies when the user requests three-tier structure or references the Testing Setup Guide.
- **Single-test-project rule** applies when no explicit three-tier request is made. If both could apply, prefer this rule when the user says "set up testing" or "create test structure" with no mention of a single project.

---

# Unit Test Project

> **Reference**: Full guidance in `references/TestingSetupGuide_v1.md` Section 1. Apply when creating or editing Unit test projects.

---

## Project Structure

```
Testing.{Service}.Unit/
├── Tests/
├── Helpers/
│   └── BaseTestConfiguration.cs
├── TestCategories.cs
├── Usings.cs
└── unittest.runsettings
```

---

## Required Files

### 1. `Helpers/BaseTestConfiguration.cs`

```csharp
[TestClass]
public class BaseTestConfiguration
{
    [AssemblyInitialize]
    public static void AssemblySetup(TestContext _)
    {
        Log.Logger = new LoggerConfiguration()
            .Enrich.FromLogContext()
            .WriteTo.TestCorrelator()
            .WriteTo.Console()
            .CreateLogger();
    }
}
```

### 2. `TestCategories.cs`

```csharp
internal static class UnitTestCategories
{
    public const string API            = "API";
    public const string Core           = "Core";
    public const string Infrastructure = "Infrastructure";
    public const string Validation     = "Validation cases";
    public const string HappyPath      = "Happy path";
    public const string UnhappyPath    = "Unhappy path";
}
```

### 3. `Usings.cs`

```csharp
global using FluentAssertions;
global using Microsoft.VisualStudio.TestTools.UnitTesting;

[assembly: Parallelize(Workers = 0, Scope = ExecutionScope.MethodLevel)]
```

### 4. `unittest.runsettings`

```xml
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <MSTest>
    <Parallelize>
      <Workers>0</Workers>
      <Scope>MethodLevel</Scope>
    </Parallelize>
  </MSTest>
</RunSettings>
```

---

## Project References

- **Must reference**: `Services.{Service}.Api`, `Services.{Service}.Core`
- **Optional**: `Testing.{Service}.Functional` — only for pure, stable test utilities (e.g., builders), NOT host or environment helpers

---

## Package References

- `Microsoft.NET.Test.Sdk`, `MSTest.TestAdapter`, `MSTest.TestFramework`
- `FluentAssertions`, `NSubstitute`, `coverlet.collector`, `Serilog.Sinks.TestCorrelator`

Use `Directory.Packages.props` for versions; reference without version in `.csproj`.

---

## Test Method Naming

**Pattern**: `{MethodUnderTest}_{GivenContext}_{ExpectedOutcome}`

| Example | Reads As |
|---------|----------|
| `CalculateTotal_WithDiscountApplied_ReturnsReducedPrice` | "Calculate total, with discount applied, returns reduced price" |
| `Validate_WhenEmailMissing_ReturnsValidationError` | "Validate, when email missing, returns validation error" |

---

## Arrange-Act-Assert

- **Arrange**: Minimal; only what the test needs. If Arrange dominates, SUT may have too many dependencies.
- **Act**: Usually one line. If multiple calls, consider splitting or moving to Integration.
- **Assert**: Business behavior, not implementation. Would it survive a refactor that preserved behavior?

---

## When to Add vs Skip

**Add a unit test when:**
- New business rule or calculation
- Bug escaped to production (regression test)
- Behavior has multiple outcomes (success vs error paths)

**Skip a unit test when:**
- Trivial getter/setter or pass-through
- Already covered by integration/functional at same fidelity
- Would assert only that a mock was called (not business outcome)

---

## Anti-Patterns (DO NOT)

| Anti-pattern | Fix |
|--------------|-----|
| Arrange sets up 5+ mocks | Decompose SUT; too many dependencies |
| Arrange longer than Act + Assert | Split into focused tests |
| Test asserts 5+ unrelated properties | Extract to separate test methods |
| Test name vague (`Test1`, `MyService_Works`) | Rename using `{Method}_{Context}_{Outcome}` |
| Connection string or env vars in unit test | Wrong tier → move to Integration |

---

## Mocks vs Fakes vs Spies

- **Mock**: Interaction is observable behavior (e.g., outbound message must be sent). Use sparingly.
- **Fake**: In-memory deterministic implementation. Hand-rolled; lives in Functional if reused.
- **Spy**: Fake + records calls for assertion. Use when test needs to assert what was sent.

Prefer Fakes/Spies over strict mocks for behavioral tests.

---

# Integration Test Project

> **Reference**: Full guidance in `references/TestingSetupGuide_v1.md` Section 3. Apply when creating or editing Integration test projects.

---

## Project Structure

```
Testing.{Service}.Integration/
├── Tests/
├── BaseTestConfiguration.cs
├── TestCategories.cs
├── Usings.cs
└── automation.runsettings
```

**Dependency**: Must reference `Testing.{Service}.Functional` for shared helpers, fakes, and `AppSettingsHelper`.

---

## What to Test Here

| Category | Examples |
|----------|----------|
| Repository queries | Correct columns, null handling, ordering |
| Persistence rules | Unique constraints, foreign keys, cascades |
| Transaction behavior | Rollback on failure, isolation levels |
| Cache adapters | Serialization round-trips, expiration |
| Index behavior | Query uses expected index |

---

## What NOT to Test Here

| Wrong | Correct | Why |
|-------|---------|-----|
| Full HTTP pipeline | Functional | Integration does not boot web host |
| Pure business rules | Unit | No infrastructure needed |
| DI wiring | Functional | Requires full container |

---

## Required Files

### 1. `automation.runsettings`

```xml
<?xml version="1.0" encoding="utf-8"?>
<RunSettings>
  <MSTest>
    <Parallelize>
      <Workers>1</Workers>
      <Scope>ClassLevel</Scope>
    </Parallelize>
  </MSTest>
</RunSettings>
```

**CRITICAL**: `Workers=1` — Integration tests share a database. Parallel workers cause data races.

### 2. `BaseTestConfiguration.cs`

```csharp
[TestClass]
public class BaseTestConfiguration
{
    [AssemblyInitialize]
    public static async Task AssemblySetup(TestContext _)
    {
        var settings = AppSettingsHelper.GetDefaultAppSettings();
        await CacheCleaner.ClearAsync(settings.ServiceDBConnection);
    }
}
```

Write setup to be **idempotent** — safe to run multiple times.

---

## Test Class Pattern

- **Apply `[LogResultTestClass]`** to every test class (from `Profisee.Platform.Utilities.Testing.Extensions.MSTest`)
- Use **`[ClassInitialize]` / `[ClassCleanup]`** for test data lifecycle — NOT `[TestInitialize]` (too expensive per method)
- Instantiate components **directly** (no DI) so failures point to infrastructure

```csharp
[LogResultTestClass]
[TestCategory(AutomationTestCategories.Infrastructure)]
public class MyRepositoryTests
{
    private static MyAppSettings? appSettings;
    private static MyTestHelper? testHelper;

    [ClassInitialize]
    public static void ClassSetup(TestContext _)
    {
        appSettings = AppSettingsHelper.GetDefaultAppSettings();
        testHelper = new MyTestHelper(appSettings);
        testHelper.CreateTestSchema();
    }

    [ClassCleanup(ClassCleanupBehavior.EndOfClass)]
    public static async Task ClassCleanup()
    {
        await testHelper!.DeleteTestSchemaAsync();
    }

    [TestMethod]
    public async Task MyRepository_WhenRecordExists_ReturnsRecord()
    {
        var repo = new MyRepository(appSettings!);
        await testHelper!.InsertTestRecordAsync("TEST001");
        var result = await repo.GetAsync("TEST001");
        result.Should().NotBeNull();
        result!.Code.Should().Be("TEST001");
    }
}
```

---

## Test Data Isolation

| Strategy | When | Example |
|----------|------|---------|
| Prefixed string IDs | String/name keys | `$"TEST_{nameof(MyRepositoryTests)}_{Guid.NewGuid():N}"` |
| GUID primary keys | `uniqueidentifier` PKs | `Guid.NewGuid()` |
| Dedicated test schema | Multi-tenancy | Create in ClassInitialize, drop in ClassCleanup |

**Cleanup must be idempotent** — use `DELETE WHERE ...` style; `ClassCleanup` may run even if `ClassInitialize` threw.

---

## When to Add vs Skip

**Add when:**
- SQL-related bug escaped to production
- New repository method added
- Schema change affects existing queries

**Skip when:**
- Business rule can be validated in unit test
- Coverage is purely for metrics

---

# Functional Test Project

> **Reference**: Full guidance in `references/TestingSetupGuide_v1.md` Section 2. Apply when creating or editing Functional test projects.

---

## Dual Role

1. **Shared Infrastructure Library** — Helpers, fakes, factories used by Integration project
2. **End-to-End Test Host** — Own test classes validating full application pipeline

**Dependency direction**: Integration references Functional. Functional does NOT reference Integration.

---

## Project Structure

```
Testing.{Service}.Functional/
├── Tests/
├── Fakes/
├── Factories/
├── Fixtures/
├── Helpers/
├── BaseTestConfiguration.cs
├── TestCategories.cs
└── GlobalUsings.cs
```

---

## Required Files

### 1. `Helpers/SettingsRetriever.cs`

**Never hard-code connection strings.** Read from environment variables; throw if missing.

```csharp
public static class SettingsRetriever
{
    public static string SqlServer => get(nameof(SqlServer));
    public static string MaestroDb => get(nameof(MaestroDb));
    public static string ServerURL => get(nameof(ServerURL));
    public static bool UseSeparateDatabases => getBool(nameof(UseSeparateDatabases));

    private static string get(string envVarName)
    {
        var value = Environment.GetEnvironmentVariable(envVarName);
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException($"Environment variable '{envVarName}' is not set.");
        return value;
    }
    private static bool getBool(string envVarName) { /* ... */ }
}
```

### 2. `Helpers/AppSettingsHelper.cs`

Assembles `AppSettings` from `SettingsRetriever`. Throws if required config missing.

### 3. `Fixtures/TestConfigSettings.cs`

`Dictionary<string, string?>` for `WebApplicationFactory`. Single source for test-host config keys.

### 4. `Fakes/` — At minimum

| Fake | Replaces | Purpose |
|------|----------|---------|
| `FakeAuthHandler` | `AuthenticationHandler<T>` | Always authenticated |
| `FakeUserService` | `IUserService` | Bypass WCF |
| `FakeSecurityService` | `ISecurityService` | Bypass permission checks |

**Naming**: `Fake{Name}` = silent stand-in. `Spy{Name}` = records calls for assertion.

### 5. `Factories/{Service}AppFactory.cs`

Extends `WebApplicationFactory<TEntryPoint>`. Must:
- Use `AddInMemoryCollection` for config (no file system)
- Replace auth with `FakeAuthHandler`
- Replace production services with fakes via `services.Replace(...)`
- Expose `OverrideTestServices` and `OverrideConfigBuilder` for per-test-class customization

```csharp
public class MyServiceAppFactory : WebApplicationFactory<MyApiEntryPoint>
{
    public TestConfigSettings AppConfig { get; set; } = new();
    public Action<IServiceCollection>? OverrideTestServices { get; set; }
    public Action<IConfigurationBuilder>? OverrideConfigBuilder { get; set; }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureAppConfiguration(config =>
        {
            config.AddInMemoryCollection(AppConfig);
            OverrideConfigBuilder?.Invoke(config);
        });
        builder.ConfigureTestServices(services =>
        {
            services.AddAuthentication("Test")
                .AddScheme<AuthenticationSchemeOptions, FakeAuthHandler>("Test", _ => { });
            services.Replace(ServiceDescriptor.Singleton<IUserService, FakeUserService>());
            OverrideTestServices?.Invoke(services);
        });
    }
}
```

### 6. `BaseTestConfiguration.cs`

Heavier setup: stop IIS app pool, clear cache, configure NServiceBus. **Log targets before destructive steps.** Make cleanup idempotent.

---

## What to Validate Here

- Authentication flow, authorization policies
- Middleware order
- JSON serialization round-trips
- Routing
- DI container wiring

**What NOT to validate:** Individual repository queries (use Integration) or pure business logic (use Unit).

---

## PollingAssert (Not Task.Delay)

Use polling for async completion. Fixed delays are flaky or slow.

```csharp
bool result = await PollingAssert.PollAsync(
    assertion: async () => await JobHasCompleted(jobId),
    maxWaitTimeMs: 30_000);
result.Should().BeTrue("the job should have completed within 30 seconds");
```

---

## Environment Variables

Required: `SqlServer`, `MaestroDb`, `ServerURL`, `ServicesPublishPath`, `UseSeparateDatabases`. Use dev-utilities or set manually. **Throw if missing** — do not default.

---

# Single Test Project Rule

## Rule: One Test Project Per Repository

**CRITICAL RULE**: Each repository should contain only a single `*.Testing` project unless otherwise instructed. All tests must be added to that project in the appropriate folder structure.

### Why This Rule Exists

1. **Consistency**: Centralizes all tests in one location for easier discovery and maintenance
2. **Shared Infrastructure**: Test utilities, base classes, and configuration are shared across all tests
3. **Simplified CI/CD**: Single test project simplifies build pipelines and test execution
4. **Dependency Management**: Avoids duplicating test dependencies across multiple projects
5. **Code Reuse**: Helpers, mocks, and test utilities are available to all tests

### Implementation Guidelines

#### Folder Structure

Organize tests within the `*.Testing` project using a logical folder hierarchy:

```
TestAuto.Testing/
├── Tests/
│   ├── Matching/                    # Tests for TestAuto.Matching
│   │   ├── MatchingRecordProgressTests.cs
│   │   ├── PartitionCalculationTests.cs
│   │   └── MatchingResultsQueryHelperTests.cs
│   ├── Scenarios/                   # Tests for TestAuto.Scenarios
│   ├── Services/                    # Tests for shared services
│   ├── Configuration/               # Configuration tests
│   ├── RESTGateway/                 # REST client tests
│   └── Workflows/                   # Workflow tests
├── Helpers/                         # Shared test utilities
│   ├── BaseTest.cs
│   └── TestRecordResponseHelpers.cs
├── Common/                          # Shared test infrastructure
└── appsettings.json                 # Test configuration
```

#### Naming Conventions

- **Test Classes**: `{ClassName}Tests.cs` (e.g., `MatchingRecordProgressTests.cs`)
- **Test Methods**: `{MethodName}_{Scenario}_{ExpectedResult}` (e.g., `CalculatePartition_WithRemainder_FirstInstancesGetExtraRecord`)
- **Folders**: Match the source project structure where practical

#### Adding New Tests

When adding tests for a new component:

1. **Identify the appropriate folder** in the existing `*.Testing` project
2. **Create a subfolder** if testing a new area (e.g., `Tests/NewFeature/`)
3. **Add project reference** if the `*.Testing` project doesn't already reference the source project
4. **Use shared infrastructure** like `BaseTest` for common setup

#### Example - ❌ BAD

```
Solution/
├── MyProject/
├── MyProject.Tests/           # ❌ Separate test project
├── MyProject.UnitTests/       # ❌ Another separate test project
└── MyProject.IntegrationTests/ # ❌ Yet another test project
```

#### Example - ✅ GOOD

```
Solution/
├── MyProject/
└── MyProject.Testing/         # ✅ Single test project
    └── Tests/
        ├── Unit/              # Unit tests organized by type
        ├── Integration/       # Integration tests
        └── Performance/       # Performance tests
```

### Exceptions

Create a separate test project only when:

1. **Explicitly instructed** by the user or project requirements
2. **Isolation requirements** mandate separate test assemblies (rare)
3. **Framework incompatibility** prevents combining tests (e.g., different test frameworks)

When creating an exception, document the reason in the project's build notes.

### Enforcement

- **Code Reviews**: Verify new tests are added to the existing `*.Testing` project
- **Build Process**: CI/CD should only reference the single test project
- **Documentation**: Update build notes when adding new test folders

---

# Running Tests

When running unit tests:
1. Do one test at time working in a group
2. If a problem is encountered with a test that will fix other tests ask for confirmation to apply that to the other tests
3. Assume that the problem is with the test first then the code
4. Do not delete tests to get them to pass
5. Do not stub a test out to get it to pass
6. When running tests all tests should pass before the task is complete
