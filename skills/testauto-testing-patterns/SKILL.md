---
name: testauto-testing-patterns
description: >
  TestAuto (speed-merchants) testing conventions across its three test projects — Unit
  (bUnit/Radzen + Moq), Integration (BaseTest, IntegrationTestBase/ControllerTestBase), and
  TestHelpers. Use when creating a TestAuto test, deciding which project it belongs in, stubbing
  Radzen in bUnit, sharing assembly fixtures, parallelization and [DoNotParallelize], markdown test
  reports, speed-merchants.runsettings, cross-assembly "Run All" contention, or
  TestRetry.PollUntilNotNullAsync read-after-write polling.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Testing Patterns

TestAuto (speed-merchants) splits tests across **three** projects — not the generic `{Service}.Unit/Integration/Functional` three-tier model described in `dotnet-testing`. There is **no `TestAuto.Testing` project** (despite older docs that named one). Before adding a test, place it in the correct existing project; do not invent new test projects.

## When to Use

- "Create tests for this service or feature in TestAuto"
- "Which test project does this test belong in?"
- "How do I set up testing in TestAuto?"
- "What does BaseTest look like in TestAuto?"
- Whenever `dotnet-testing` (the generic skill) would tell you to create `{Service}.Unit/Integration/Functional` projects, or to serialize integration tests at ClassLevel with `Workers=1`

## ⚠️ Conflict with `dotnet-testing`

The generic `dotnet-testing` skill describes a `{Service}.Unit/Integration/Functional` three-tier model and prescribes `Workers=1` / `ClassLevel` parallelization for integration tests (shared DB). **Neither matches speed-merchants.** This repo uses Unit + Integration + TestHelpers, and parallelizes at **MethodLevel** in both test assemblies (see below). Use this skill when working in TestAuto; `dotnet-testing` applies to new platform-service repos created from scratch.

## Three-Project Layout

This repository has **three** test/test-support projects. There is no `TestAuto.Testing`.

| Project | Role | Key contents |
|---|---|---|
| `Testing.SpeedMerchants.Unit` | Fast, isolated unit + bUnit component tests (Moq-based, no live services) | `Web\Helpers\TestBase.cs` (mock-based), `Web\Infra\RadzenStubbingExtensions.cs` + `RazenChartStub.cs`, `Web\Helpers\TestReflectionHelpers.cs`, `Web\Data\TestDataFactory.cs`, `MSTestSettings.cs` |
| `Testing.SpeedMerchants.Integration` | Live-service integration/performance tests (real DI via `RegisterAllServices`, CDP, REST) | `Helpers\BaseTest.cs`, `Core\PerformanceBaseTestClass.cs`, `Helpers\ServiceHelper.cs`, `Web\Helpers\IntegrationTestBase.cs`, `Web\Helpers\ControllerTestBase.cs`, `Tests\…\UtilitiesTestBase.cs`, `Tests\RESTGateway\Client\BaseRestClientTest.cs`, `Helpers\ProfiseeTestAssertions` / `EntityAttributeValidationHelpers`, `MSTestSettings.cs` |
| `Testing.SpeedMerchants.TestHelpers` | Shared **non-test** support library (no test methods) referenced by both above | `Helpers\TestResultsHelper.cs` |

### Base-class map — pick the right base

| Base class | Project | Use for |
|---|---|---|
| `TestBase` (Unit) | Unit | Mock-based unit/component tests; no `RegisterAllServices`, no live services |
| `BaseTest` | Integration | Per-test full DI container via `RegisterAllServices(..., includeWebServices: true)` |
| `PerformanceBaseTestClass` | Integration | Assembly-scoped shared CDP/cache fixtures (see below) — when per-test container rebuild is too expensive |
| `IntegrationTestBase` | Integration | API tests booting the real `Program` via `WebApplicationFactory<Program>` (inherits prod DI) |
| `ControllerTestBase` | Integration | Controller isolation — clears services and re-calls `RegisterAllServices` inside the factory's `ConfigureServices`. **Zero inheritors today** — see note below |
| `BaseRestClientTest` | Integration | Extends `BaseTest` and adds a resolved `IRestClient`. **Zero inheritors today** — see note below |
| `UtilitiesTestBase` | Integration | Utility/CLI step-execution tests |

> **Two of these bases are currently unused.** `ControllerTestBase` and `BaseRestClientTest` each appear exactly once repo-wide — their own declarations. Nothing derives from either (`rg ': ControllerTestBase'` and `rg ': BaseRestClientTest'` both return nothing). They are legitimate choices for a new test and the descriptions above are accurate, but do not go looking for existing tests to copy the pattern from: there are none. Copy from a `BaseTest` or `IntegrationTestBase` derivative instead, and expect to be the first user of the base you pick.

**Exception:** Add a *new* test project only when explicitly instructed, or when a hard framework/isolation constraint prevents using one of the three above.

## Parallelization: MethodLevel, opt-out per test

Both test assemblies declare method-level parallelization in `MSTestSettings.cs`:

```csharp
// Testing.SpeedMerchants.Unit\MSTestSettings.cs  AND
// Testing.SpeedMerchants.Integration\MSTestSettings.cs
[assembly: Parallelize(Scope = ExecutionScope.MethodLevel)]
```

This **deviates from `dotnet-testing`'s** "integration = `Workers=1` / `ClassLevel`" guidance: speed-merchants runs integration tests in parallel at the method level for throughput. Tests that share mutable state or a shared resource opt **out individually** with `[DoNotParallelize]` (e.g. `Tests\Matching\MatchingStrategyConfigurationServiceTests.cs`), rather than serializing the whole assembly. When you write an integration test that mutates shared DB state in a way that races other tests, add `[DoNotParallelize]` to that test/class — do not change the assembly setting.

### Cross-assembly contention (VS "Run All") — solution-wide `speed-merchants.runsettings`

`MethodLevel` + `[DoNotParallelize]` only isolate classes **within a single testhost**. They cannot stop a *different* problem: Visual Studio "Run All" discovers **both** test projects (Unit and Integration) and the vstest runner executes the two **assemblies concurrently** (up to the core count), in **separate processes**. The Integration suite hits a **LIVE** Profisee model, SQL, and WebUI, so two assemblies running at once corrupt shared state — producing failures that a single `dotnet test <project>` run never reproduces.

The fix is the solution-wide `speed-merchants.runsettings` at the repo root, which serializes the **assemblies** without sacrificing method-level parallelism *inside* each one:

```xml
<RunSettings>
  <RunConfiguration>
    <!-- Run test assemblies one at a time so Integration never shares the live env with another testhost -->
    <MaxCpuCount>1</MaxCpuCount>
    <ResultsDirectory>.\TestResults</ResultsDirectory>
    <TargetFrameworks>net10.0</TargetFrameworks>
  </RunConfiguration>
  <MSTest>
    <Parallelize>
      <Workers>0</Workers>          <!-- 0 = use core count; method-level parallelism kept inside each assembly -->
      <Scope>MethodLevel</Scope>     <!-- DoNotParallelize still protects model-mutating classes -->
    </Parallelize>
  </MSTest>
</RunSettings>
```

- `MaxCpuCount = 1` is the key line — it serializes *assemblies* (no Unit/Integration overlap). It does **not** serialize tests within an assembly; that is governed by the `<MSTest><Parallelize>` block.
- **VS**: Test menu → *Configure Run Settings* → *Select Solution-Wide runsettings File* → pick `speed-merchants.runsettings`.
- **CLI**: pass it via `dotnet test --settings speed-merchants.runsettings` (this matches the green CLI run the suite was tuned against).

## BaseTest Pattern

> [!note] Scope: `BaseTest` is **Integration-only**
> This section describes `Testing.SpeedMerchants.Integration\Helpers\BaseTest.cs`. It is **not** the
> base for unit tests — `Testing.SpeedMerchants.Unit` has its own, differently-named
> `TestBase` (`Testing.SpeedMerchants.Unit\Web\Helpers\TestBase.cs:14`, mock-based, no
> `RegisterAllServices`). Do not put `: BaseTest` on a unit test, and do not assume every test class
> has a base at all — at HEAD 4c367fe6 only 5 of the 68 `[TestClass]` files in the Unit project
> derive from `TestBase`; the rest inherit nothing. Use the base-class map above to choose.

Integration test classes that need a full DI container inherit from `BaseTest`, which handles DI setup consistently. The
`[TestInitialize]` method is named `Setup()` (not `TestInitialize()`), and the class also
exposes a `protected Serilog.ILogger Logger` property (a Debug-level console logger) alongside
`ServiceProvider` and `Configuration`:

```csharp
[TestClass]
public abstract class BaseTest
{
    protected IServiceProvider ServiceProvider { get; private set; }
    protected IConfiguration Configuration { get; private set; }
    protected Serilog.ILogger Logger { get; private set; }

    [TestInitialize]
    public void Setup()
    {
        Logger = new LoggerConfiguration()
            .MinimumLevel.Debug().WriteTo.Console().CreateLogger();

        Configuration = BuildConfiguration();
        var services = new ServiceCollection();
        services.AddSingleton<Serilog.ILogger>(Logger);
        services.AddSingleton<IConfiguration>(Configuration);
        var (_, _) = services.RegisterAllServices(Configuration, includeWebServices: true);
        ServiceProvider = services.BuildServiceProvider();
    }

    private IConfiguration BuildConfiguration()
    {
        // NOTE: simplified illustration. The real BaseTest.cs (lines 31–45) layers four
        // config sources by precedence (low → high):
        //   appsettings.json (optional) → appsettings.integration.json (optional) →
        //   secrets file (loaded via IntegrationSecretsLoader.LoadFlattenedSecrets and
        //   spliced in as an in-memory collection) → environment variables.
        // Integration tests load a TestAutoSecrets export FILE here instead of the
        // entity-based secrets production loads at startup.
        return new ConfigurationBuilder()
            .AddJsonFile("appsettings.json", optional: true)
            .AddJsonFile("appsettings.integration.json", optional: true)
            // + secrets-file in-memory collection, then .AddEnvironmentVariables()
            .Build();
    }
}
```

An integration test that needs the real DI container inherits `BaseTest` (prefer one of the more
specific Integration bases — `BaseRestClientTest`, `IntegrationTestBase`, `ControllerTestBase`,
`UtilitiesTestBase` — when it fits):

```csharp
[TestClass]
public class MyServiceTests : BaseTest
{
    [TestMethod]
    public async Task MyMethod_GivenValidInput_ReturnsExpected()
    {
        var service = ServiceProvider.GetRequiredService<IMyService>();
        // ...
    }
}
```

## Read-after-write retry (commit-visibility latency)

Integration tests run against a **live, sometimes load-latent Profisee server**. A create API can confirm the write (it returns created-record evidence), yet a follow-up *by-code read* may transiently return `null` because the write has not yet become visible to that read path. Polling absorbs this latency without hiding real failures.

Use the shared helper in `Testing.SpeedMerchants.Integration/Helpers/TestRetry.cs` rather than hand-rolling `Task.Delay` loops or — worse — adding a blanket `Thread.Sleep` after every create:

```csharp
// Retries until the fetch yields non-null, or attempts are exhausted (default 15 × 1s).
var record = await TestRetry.PollUntilNotNullAsync(
    () => _restClient.GetRecordAsync(entity, createdCode, selectAttributes: null));

Assert.IsNotNull(record, "record should be readable after create");
```

> [!warning] The method is `GetRecordAsync` — there is no `GetRecordByCodeAsync`
> `GetRecordByCodeAsync` has **zero hits repo-wide** (verified 2026-07-27, HEAD 4c367fe6). The real
> member is declared at `TestAuto.Shared/Interfaces/IRestClient.cs:60`:
>
> ```csharp
> Task<Record> GetRecordAsync(
>     string entityName,
>     string recordCode,
>     List<string>? selectAttributes,
>     Dictionary<string, string>? queryParameters = null);
> ```
>
> Note it returns `Task<Record>`, and the third parameter (`selectAttributes`) is **required
> positionally** — pass `null` for all attributes. For multi-record reads, prefer
> `GetAllRecordsAsync` over `GetRecordsAsync` (the latter caps at the server default page size).

`BaseTest` also re-exposes the helper so derived integration tests can call it unqualified —
`BaseTest.cs:108-112` forwards straight to `TestRetry.PollUntilNotNullAsync`.

```csharp
public static async Task<T?> PollUntilNotNullAsync<T>(
    Func<Task<T?>> fetch, int maxAttempts = 15, int delayMs = 1000) where T : class
```

- **It does not mask a genuine failure.** A record that is truly missing still returns `null` after the timeout, and the caller's assertion fails as normal — the helper only absorbs commit-visibility latency, it never invents data.
- Reach for it on **read-back-after-create / after-update** assertions where the write was already confirmed by the create/update response. Do *not* use it to paper over a flaky write whose create call itself failed — fix that instead.
- Used in `BaseTest` and read-back assertions such as `ScenarioDisplayDataComparisonTests` / `ScenarioEditorDecompressionTests`.

## DI Registration: `includeWebServices: true`

The test setup calls `RegisterAllServices` with `includeWebServices: true`. This matches production initialization and ensures:
- All services registered through the same central mechanism
- Dependencies like `IMemoryCache` are automatically registered via `AddControllers()`
- Tests validate production DI wiring, not a custom subset

**Never** manually build the DI container or register services individually in tests.

```csharp
// GOOD
services.RegisterAllServices(configuration, includeWebServices: true);

// BAD — partial registration, misses production dependencies
services.AddScoped<IMyService, MyService>();
services.AddScoped<IRestClient, RestClient>();
```

### Why `includeWebServices: true`? (production parity)

The flag is not optional decoration — the codified RULE comment in
`Testing.SpeedMerchants.Integration\Helpers\BaseTest.cs` (~lines 53–56) spells out the rationale:

> RULE: All tests MUST use central registration (RegisterAllServices) to match production initialization.
> This matches TestAuto.Web/Program.cs which calls RegisterAllServices with includeWebServices: true.
> This ensures all services (including IMemoryCache via AddControllers() in AddWebServices()) are registered
> through the same central mechanism as production, preventing test-specific workarounds.

Concretely:

- **Production parity** — `TestAuto.Web\Program.cs` (~line 181) calls `RegisterAllServices(..., includeWebServices: true)`. A test that passes `false` (or hand-registers services) is exercising a DI graph that does not exist in production.
- **`IMemoryCache` is the canary** — `AddWebServices()` calls `AddControllers()`, which transitively registers `IMemoryCache`. Services that depend on it resolve fine in production but blow up in a test that skipped web services, leading to test-only registration hacks. The flag prevents the hack.
- **Where it appears** — direct calls live in `BaseTest.cs` (~line 57) and `ControllerTestBase.cs` (~lines 58–61, inside a `WebApplicationFactory` `ConfigureServices` override). `IntegrationTestBase.cs` does **not** call it directly — it boots the real `Program` via `WebApplicationFactory<Program>`, so it inherits `includeWebServices: true` from `Program.cs` itself.
- Background-job/CLI hosts legitimately pass `includeWebServices: false`; tests targeting those hosts may mirror that (e.g. `MonitorActivityEndToEndTests.cs`). Match the host you are testing.

## Assembly-Level Shared Fixtures (`PerformanceBaseTestClass`)

For expensive setup (CDP connection, metadata cache), the integration suite uses MSTest
`[AssemblyInitialize]`/`[AssemblyCleanup]` instead of per-test `[TestInitialize]`. See
`Testing.SpeedMerchants.Integration\Core\PerformanceBaseTestClass.cs`:

```csharp
[TestClass]
public class PerformanceBaseTestClass
{
    protected internal static CdpService cdpService;
    protected internal static MetadataCache metadataCache;
    protected internal static User superUser;
    protected internal static ILogger Logger;
    protected internal static IConfiguration Configuration;

    [AssemblyInitialize]
    public static void AssemblyInitialize(TestContext _)
    {
        Configuration = new ConfigurationBuilder()
            .SetBasePath(Directory.GetCurrentDirectory())
            .AddJsonFile("appsettings.json", optional: true, reloadOnChange: true)
            .AddEnvironmentVariables()
            .Build();

        ServiceHelper.RegisterServices(Configuration);   // once per assembly
        cdpService = ServiceHelper.CdpService;
        superUser = ServiceHelper.User;
        metadataCache = ServiceHelper.DataMetadataCache;
        Logger = ServiceHelper.logger;
    }

    [AssemblyCleanup]
    public static void AssemblyCleanup()
    {
        Log.CloseAndFlush();
    }
}
```

Key points:

- **Once per assembly, not per test** — static fields (`cdpService`, `metadataCache`, etc.) are populated a single time via `ServiceHelper.RegisterServices` and shared by every test in the assembly. Contrast with `BaseTest`, which rebuilds the full DI container in `[TestInitialize]` for every test.
- **Use it for performance/CDP tests** that need a live `CdpService` and `MetadataCache` but cannot afford container rebuild per test. Use `BaseTest` when test isolation matters more than setup cost.
- **Failure handling** — init failures are logged via `MSTestInitLogger.LogAssemblyInitFailure` and surfaced with `Assert.Fail`, so a broken environment fails fast instead of producing 200 confusing downstream errors.
- `[AssemblyCleanup]` calls `Log.CloseAndFlush()` — without it, buffered Serilog sinks can drop the tail of the log.

## bUnit/Radzen Component Tests

Blazor component tests use bUnit. Radzen components that touch JS interop (charts especially) will fail in bUnit unless stubbed.

### Stubbing RadzenChart (`RadzenStubbingExtensions`)

`Testing.SpeedMerchants.Unit\Web\Infra\RadzenStubbingExtensions.cs` provides a bUnit `TestContext` extension that handles both problems in one call:

```csharp
public static void UseRadzenChartStubs(this Bunit.TestContext ctx)
{
    // Ignore incidental JS during tests
    ctx.JSInterop.Mode = JSRuntimeMode.Loose;

    // Correct overload: Add(Predicate<Type> condition, Func<Type, IComponent> factory)
    ctx.ComponentFactories.Add(
        condition: (Type t) => t == typeof(RadzenChart),
        factory: (Type _) => new RadzenChartStub()
    );
}
```

- `JSRuntimeMode.Loose` swallows incidental JS calls instead of throwing on every unconfigured invocation.
- The `ComponentFactories.Add(Predicate<Type>, Func<Type, IComponent>)` overload swaps `RadzenChart` for a stub by type predicate — the same pattern extends to other JS-heavy visualizations (e.g. `RadzenSparkline`, `RadzenGauge`).

The stub itself is `RadzenChartStub` — a `sealed ComponentBase` that renders a bare `<div data-testid="radzen-chart-stub">`, forwards unmatched attributes, and **intentionally does NOT render `ChildContent`** so Radzen series/axes never instantiate (they would re-trigger JS interop). Note the file is named `RazenChartStub.cs` (typo in the filename, not the class):
`Testing.SpeedMerchants.Unit\Web\Infra\RazenChartStub.cs`.

### Radzen services in component tests

`UseRadzenChartStubs` does **not** register Radzen services. Tests that exercise page logic mock those per-test with Moq — see `Testing.SpeedMerchants.Unit\Web\Components\Pages\WorkflowScenariosEditorTests.cs` (~lines 24–39), which sets up `Mock<NotificationService>`, `Mock<DialogService>`, `Mock<ErrorNotificationService>`, and `Mock<NavigationManager>` in `[TestInitialize]`.

Also note the cheaper alternative used widely in this suite: test the data/logic layer behind the component **without rendering it at all** (the `ConnExStepEditorCardTests` / `UtilityScenarioEditorToggleBugTests` pattern).

### Gotcha: Newtonsoft round-trips APPEND to pre-initialized collections

If a DTO initializes a collection property with a default value (e.g. `ExpectedStatusCodes = new List<int> { 200 }`), Newtonsoft's default `ObjectCreationHandling` **reuses the existing list and appends** the deserialized items instead of replacing them. Round-tripping `[200, 201]` yields `[200, 200, 201]`.

`Testing.SpeedMerchants.Unit\Web\Components\ConnExStepEditorCardTests.cs` (~lines 61–65) documents and asserts this deliberately:

```csharp
// Newtonsoft appends deserialized items to the default-initialized list [200],
// so [200, 201] in JSON becomes [200, 200, 201]. This is expected Newtonsoft behavior
// for pre-initialized collections. The editor and executor handle this correctly
// because they replace the list (not append) when setting values.
reloaded.ExpectedStatusCodes.Should().Contain(200).And.Contain(201);
```

Rules of thumb:
- In round-trip tests, assert **membership** (`Contain(...)`) on pre-initialized collections, not sequence equality.
- In production code, **replace** such lists when setting values — never append to the deserialized result.

### Selectors must come from Radzen's RENDERED DOM, not the `.razor` source

Radzen components render their own markup, which does **not** resemble what the `.razor` spells. A
`RadzenCheckBox` becomes an `.rz-chkbox` / `.rz-chkbox-box` pair with a hidden `<input>` carrying
`aria-checked`. So:

- **Read the selector off a first rendered pass, then lock it in.** Never guess it from the component source
  or from HTML intuition — a guessed selector fails in a way that looks like a broken component.
- **Prefer arranging the data so you never touch a fragile control.** Naming a fixture so it satisfies the
  component's own default-selection rule beats simulating a Radzen dropdown interaction. Evidence:
  `ProductionSyncPageTests.cs:36-42`, `:57-80`.

### Hand-rolled fakes for wide interfaces: implement what's called, THROW on the rest

Where Moq is impractical (a wide interface, or one needing cross-call ordering), the house convention is a
hand-written fake with three properties:

1. **Implement only the members the system under test actually calls.**
2. **`throw new NotImplementedException()` from every other member** — deliberately, so an unexpected call
   fails loudly instead of returning a silent default that quietly changes the test's meaning
   (`FakeSyncRestClients.cs:47-57`).
3. **Expose an ordered call `Ledger`** (`:68-70`, records of `SyncCallRecord` `:18-28`) so tests can assert
   **cross-phase ordering** — "every skeleton create precedes any update", "deletes run dependents-first" —
   which no per-call assertion can express.

Companion: `FakeSyncEndpointFactory` (`:379`). See [[testauto-production-sync]] for the scenarios these
drive.

## TestResultsHelper: Markdown Test Reports

`Testing.SpeedMerchants.TestHelpers\Helpers\TestResultsHelper.cs` writes timestamped markdown reports for integration/performance tests, organized by `[TestCategory]` reflection:

```
{solution root}/.cursor/documentation/{category1}/{category2}/.../Results/{yyyy-MM-dd_HHmmss}_{testName}.md
```

> Note: this output path is a **repo-local convention** (`.cursor/documentation/` under the solution root, found by walking up to `speed-merchants.sln`). It is distinct from the Obsidian-vault rule for AI-generated documentation artifacts — these files are test output written by the tests themselves.

Usage pattern (e.g. `Testing.SpeedMerchants.Integration\Tests\Matching\DatabaseConnectivityTests.cs:206`, `EndToEndMatchingTests.cs:89`):

```csharp
var results = TestResultsHelper.FromTestMethod(GetType(), nameof(Fetch1000Records_VerifyIndexUsage_Works));
results.WriteHeader("What this test measured");
results.WriteConfiguration(new Dictionary<string, object> { ["BatchSize"] = 1000 });
results.WritePerformanceMetrics(elapsedMs, recordCount, batchCount);
results.WriteTable("Breakdown", new[] { "Phase", "ms" }, rows);
results.WriteResult(passed: true);
results.Save();   // nothing is written until Save()
```

Key points:
- **Factories**: `FromTestMethod(Type, methodName)` merges class-level and method-level `[TestCategory]` attributes into the folder path; `FromTestClass(Type, testName)` uses class-level only. No categories → `General/`.
- **Sections**: `WriteHeader`, `WriteConfiguration`, `WritePerformanceMetrics` (computes rec/sec throughput; also has a dictionary overload), `WriteTable`, `WriteSection` (text or bullets), `WriteCodeBlock`, `WriteError(Exception)`, `WriteResult(bool)`.
- Content accumulates in a `StringBuilder`; call `Save()` at the end (typically in a `finally` so failed runs still produce a report alongside `WriteError`).
- File names are sanitized and truncated to 80 chars; the helper throws if it cannot locate `speed-merchants.sln` walking up from `AppContext.BaseDirectory`.

## Unit Test Execution Rules

When running and fixing tests:

1. Run one test (or one focused group) at a time
2. If a fix would affect multiple tests, ask for confirmation before making broad changes
3. Assume the problem is with the test first, then the code
4. Do NOT delete tests to get them to pass
5. Do NOT stub out a test to force it to pass
6. All tests must pass before the task is considered complete

## Sources

- `AGENTS.md` — Single Test Project rule, Testing Infrastructure (BaseTest) rule (source deleted; canonical rules now in this skill)
- `Testing.SpeedMerchants.Unit\Web\Infra\RadzenStubbingExtensions.cs` — bUnit TestContext extension (Loose JSInterop + RadzenChart stub factory)
- `Testing.SpeedMerchants.Unit\Web\Infra\RazenChartStub.cs` — RadzenChartStub (filename has typo; class name is correct)
- `Testing.SpeedMerchants.Unit\Web\Components\ConnExStepEditorCardTests.cs` — Newtonsoft pre-initialized-collection append gotcha (~lines 61–65)
- `Testing.SpeedMerchants.Unit\Web\Components\Pages\WorkflowScenariosEditorTests.cs` — per-test Moq setup of NotificationService/DialogService/ErrorNotificationService/NavigationManager
- `Testing.SpeedMerchants.Integration\Core\PerformanceBaseTestClass.cs` — [AssemblyInitialize]/[AssemblyCleanup] shared static fixtures
- `Testing.SpeedMerchants.Integration\Helpers\BaseTest.cs` — RULE comment and includeWebServices: true rationale (~lines 53–57)
- `Testing.SpeedMerchants.Integration\Web\Helpers\ControllerTestBase.cs` — includeWebServices: true inside WebApplicationFactory ConfigureServices (~lines 58–61)
- `TestAuto.Web\Program.cs` — production RegisterAllServices(..., includeWebServices: true) (~line 181)
- `Testing.SpeedMerchants.TestHelpers\Helpers\TestResultsHelper.cs` — markdown test report helper
- `speed-merchants.runsettings` — solution-wide MaxCpuCount=1 runsettings (cross-assembly contention fix; rationale in its XML comment header)
- `Testing.SpeedMerchants.Integration\Helpers\TestRetry.cs` — PollUntilNotNullAsync read-after-write polling helper
- `Testing.SpeedMerchants.Integration\Tests\Matching\DatabaseConnectivityTests.cs` (line 206), `EndToEndMatchingTests.cs` (line 89) — FromTestMethod usage examples
- `Testing.SpeedMerchants.Unit\MSTestSettings.cs` (line 3), `Testing.SpeedMerchants.Integration\MSTestSettings.cs` (line 6) — `[assembly: Parallelize(Scope = ExecutionScope.MethodLevel)]` in both assemblies
- `Testing.SpeedMerchants.Integration\Tests\Matching\MatchingStrategyConfigurationServiceTests.cs` (line 30) — `[DoNotParallelize]` per-test opt-out for shared-state tests
- `Testing.SpeedMerchants.Integration\Web\Helpers\IntegrationTestBase.cs` — API tests via `WebApplicationFactory<Program>`
- `Testing.SpeedMerchants.Integration\Helpers\ServiceHelper.cs` — assembly-scoped CDP/cache registration used by `PerformanceBaseTestClass`
- `Testing.SpeedMerchants.Unit\Web\Helpers\TestBase.cs` — mock-based Unit base (no `RegisterAllServices`)
- csproj inventory (24 projects) — confirms there is **no `TestAuto.Testing` project**; only `Testing.SpeedMerchants.{Unit,Integration,TestHelpers}`
