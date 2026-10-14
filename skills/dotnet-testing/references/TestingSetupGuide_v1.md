# Testing Setup Guide: .NET Service Repositories

> **Purpose**: Prescriptive guidance for setting up or aligning the test infrastructure in a .NET platform service repo. This guide is pattern-based and intentionally generic — it describes _how_ to structure testing across three tiers, not the specifics of any single service.
>
> **Use this guide when**:
>
> - You are creating the test structure for a brand-new service repository.
> - You are refactoring an existing repository where tests are slow, flaky, or hard to reason about.
> - You need to onboard new team members to testing standards and architecture.
> - You want to audit existing test coverage for quality (not just quantity).
>
> **Primary outcome**: A test suite that gives fast feedback, isolates failures clearly, and protects behavior instead of inflating test counts.
>
> **Non-goals**: This guide does NOT prescribe specific coverage percentages, test counts per class, or tool-specific configurations beyond MSTest. Those decisions depend on the risk profile and complexity of your service.

**How to use this guide:**
- **New project**: Work through [Project Structure](#project-structure) and each tier section in order. Use the [Quick-Start Checklist](#10-quick-start-checklist) to verify completeness.
- **Existing project**: Start with the [Quick-Start Checklist](#10-quick-start-checklist) as an audit. Identify gaps, then apply the [Refactor/Audit flow](#refactoraudit-flow-for-existing-repos).
- **Onboarding**: Read [Overview: The Three-Tier Testing Model](#overview-the-three-tier-testing-model) and [Design for Testability](#design-for-testability--architecture-guidance) first to understand the rationale before diving into implementation details.

---

## Document Overview

| Section | Purpose |
|---------|----------|
| [Three-Tier Testing Model](#overview-the-three-tier-testing-model) | Understand WHY we separate tests into tiers and WHEN to use each |
| [Design for Testability](#design-for-testability--architecture-guidance) | Architecture patterns that make testing easier and faster |
| [Project Structure](#project-structure) | Physical organization of test projects and files |
| [Unit Test Project](#1-unit-test-project) | Fast, isolated behavior verification |
| [Functional Project](#2-functional-project-shared-test-infrastructure) | Shared infrastructure and end-to-end tests |
| [Integration Test Project](#3-integration-test-project) | Real database and infrastructure validation |
| [Supporting Infrastructure](#4-central-package-version-management) | Package management, environment variables, CI |
| [Quick-Start Checklist](#10-quick-start-checklist) | Actionable setup and audit checklist |

---

## Overview: The Three-Tier Testing Model

### Why Three Tiers?

The three tiers exist to separate **speed**, **fidelity**, and **diagnostic value**. Each tier answers a different question about your code:

| Tier | Question It Answers | Feedback Speed | Failure Diagnosis |
|------|---------------------|----------------|-------------------|
| **Unit** | Does the business logic work correctly in isolation? | Milliseconds | Points to specific method/rule |
| **Integration** | Does the infrastructure layer (SQL, caching, serialization) behave correctly? | Seconds | Points to data access or external boundary |
| **Functional** | Does the full application (DI, middleware, auth, routing) work together? | Seconds to minutes | Points to wiring or cross-cutting concern |

### What Each Tier Validates

- **Unit** tests are fastest and should explain business behavior in isolation. They verify that given specific inputs, the business logic produces the expected outputs — no database, no HTTP, no file system.
- **Integration** tests validate infrastructure boundaries with real dependencies. They verify that your SQL queries return expected shapes, that your caching layer serializes correctly, and that constraints enforce rules.
- **Functional** tests validate end-to-end wiring through the real application host. They verify that authentication works, that DI resolves services correctly, that middleware executes in order, and that serialization round-trips cleanly.

### The Diagnostic Value

When a bug escapes, this structure helps answer: "Is the defect in business logic, infrastructure wiring, or cross-service behavior?" quickly and with low ambiguity.

**Example diagnostic flow:**
1. Unit tests pass, integration tests fail → The logic is correct, but SQL behavior differs from expectations (null handling, collation, index behavior)
2. Unit and integration tests pass, functional tests fail → The components work individually, but DI wiring, middleware order, or serialization is broken
3. All tests pass, production fails → Missing test scenario (add a regression test that reproduces the production condition)

### Project Organization by Tier

Every service repo should have three testing tiers, each in its own project:

| Tier            | Project Name Pattern            | Runs Against                         | Parallelism               | In CI Pipeline               | Typical Run Time |
| --------------- | ------------------------------- | ------------------------------------ | ------------------------- | ---------------------------- | ---------------- |
| **Unit**        | `Testing.{Service}.Unit`        | Nothing real (all mocked)            | Method-level, max workers | ✅ Yes                       | <5 seconds       |
| **Integration** | `Testing.{Service}.Integration` | Real database / infrastructure       | Class-level, 1 worker     | ❌ No (requires environment) | 1-5 minutes      |
| **Functional**  | `Testing.{Service}.Functional`  | Full running app via in-process host | Class-level, 1 worker     | ❌ No (requires environment) | 2-10 minutes     |

### The Cost Model: Why This Matters

Each tier has a different cost profile for setup, execution time, and diagnostic clarity. Understanding this drives correct tier selection:

| Cost Factor | Unit Test | Integration Test | Functional Test |
|-------------|-----------|------------------|------------------|
| **Setup time** | <1ms (in-memory only) | 100ms-2s (DB connection) | 2-10s (full host boot) |
| **Execution time** | <10ms | 100ms-5s | 500ms-30s |
| **Maintenance cost** | Low (isolated) | Medium (schema coupling) | High (full stack coupling) |
| **Failure diagnosis** | Trivial (one method) | Moderate (data + logic) | Complex (full pipeline) |
| **CI friendliness** | Excellent | Requires dedicated agent | Requires dedicated agent |

A unit test that runs in <1ms with zero infrastructure is **infinitely cheaper** to write, run, and debug than an integration test that requires a real SQL database. This means:

- **Maximize** the number of behaviors tested at the unit tier.
- **Push tests up a tier only when they cannot be validated without real infrastructure.**
- A slow or flaky test suite is a signal that tests have drifted too high in the hierarchy — business logic that lives in integration tests is costing the team 100× more per assertion than it should.

**ROI rule of thumb**: If you’re spending more time waiting for tests than writing code, tests are in the wrong tier.

> **Key insight**: The Functional project serves a **dual role** — it is both a shared test infrastructure library (helpers, fakes, factories) referenced by the Integration project, _and_ it contains its own end-to-end test classes. This design keeps reusable infrastructure consolidated while allowing both tiers to run their own tests.

### Choosing the Right Test Tier

Use this decision path before writing a test:

```
                   ┌──────────────────────────────────────┐
                   │ Can behavior be validated without    │
                   │ real I/O (DB, HTTP, files, queues)?  │
                   └─────────────────┬────────────────────┘
                                     │
               YES ┌─────────────────┴─────────────────┐ NO
                   ▼                                     ▼
            ┌─────────────┐           ┌──────────────────────────────────┐
            │  UNIT TEST  │           │ Does it depend on SQL shape,     │
            └─────────────┘           │ indexes, mappings, transactions, │
                                      │ or external service contracts?   │
                                      └───────────────┬──────────────────┘
                                                      │
                                  YES ┌───────────────┴─────────────────────┐ NO
                                      ▼                                     ▼
                               ┌──────────────────┐              ┌───────────────────┐
                               │ INTEGRATION TEST │              │ FUNCTIONAL TEST   │
                               └──────────────────┘              └───────────────────┘
```

**Concrete examples by tier:**

| Scenario | Correct Tier | Why |
|----------|--------------|-----|
| Validate order total calculation | Unit | Pure arithmetic; no I/O needed |
| Validate null input returns specific error | Unit | Input validation is pure logic |
| Validate SQL query returns expected columns | Integration | Depends on real schema shape |
| Validate unique constraint prevents duplicate | Integration | Requires real DB enforcement |
| Validate API returns 401 without token | Functional | Tests auth middleware pipeline |
| Validate JSON serialization round-trips | Functional | Tests MVC serializer config |

Avoid duplicating the same scenario across all three tiers unless each tier is asserting a different risk.

**Anti-patterns when choosing a tier:**

| Anti-pattern | Why It's Wrong | What To Do Instead |
|--------------|----------------|--------------------|
| Writing integration tests for pure business logic | SQL round-trips add cost (100ms vs 1ms) and noise without adding value | Keep business rules in unit tests; integration tests validate infrastructure |
| Writing functional tests for individual repository queries | Full host startup (~5s) is not justified for a single query path | Use integration tests for repository-level validation |
| Using Functional tier as a "safety net" for missing unit tests | Slow, environment-dependent tests that fail in CI | Fill gaps at the correct tier; Functional is for pipeline-level wiring only |
| Promoting tests to higher tiers because SUT is hard to construct | The tiers are complements, not fallbacks for design problems | Refactor the SUT to be more testable (extract interface, reduce dependencies) |
| Testing the same scenario in all three tiers "for safety" | Triple the maintenance cost with diminishing returns | Each tier validates different risks; one scenario per tier max |

## Design for Testability & Architecture Guidance

This guide assumes the codebase follows Dependency Inversion and Single Responsibility principles. Design choices that improve testability reduce friction across all three tiers.

### Core Principles

The goal is code that is **easy to test in isolation**. When code is hard to test, it’s usually a design signal, not a testing problem.

**Why testability matters architecturally:**
- **Explicit dependencies** (visible in constructors) — Every dependency is a seam. Hidden dependencies (service locators, static singletons) cannot be replaced in tests without invasive changes.
- **Clear boundaries** (one class, one responsibility) — A class that does one thing has fewer failure modes and simpler test scenarios. Mixed concerns force tests to set up unrelated state.
- **Minimal coupling** (changes propagate locally) — When a change breaks many tests across unrelated areas, coupling is too high. Tests that break only when the behavior they assert changes are well-aligned.

**What "design for testability" yields in practice:**
- Unit tests run in milliseconds because no real I/O is involved
- Failures point to a single method or rule, not a chain of components
- New features can be tested without spinning up databases or HTTP hosts

### Dependency Injection Patterns

- **Prefer constructor injection for dependencies.** It makes dependencies explicit and trivial to replace with fakes or spies in tests. Avoid property injection and service location patterns.

```csharp
// ✅ Good: Dependencies are explicit and replaceable
public class OrderService
{
    private readonly IOrderRepository _repository;
    private readonly INotificationService _notifications;

    public OrderService(IOrderRepository repository, INotificationService notifications)
    {
        _repository = repository;
        _notifications = notifications;
    }
}

// ❌ Bad: Hidden dependency, hard to test
public class OrderService
{
    public void ProcessOrder(Order order)
    {
        var repository = ServiceLocator.Get<IOrderRepository>(); // Hidden!
    }
}
```

### Separating Business Logic from Infrastructure

- **Keep business logic outside of framework hosting code.** Business rules should live in `Services.{Service}.Core` with no ASP.NET Core or EF-specific code mixed in. This enables fast unit tests that exercise pure logic.

**Why this separation matters:** Controllers, middleware, and DbContext are framework concerns. Business rules (calculations, validations, state transitions) are domain concerns. Mixing them forces tests to boot the framework or hit the database to verify a rule that could be tested in isolation. The pattern: **Controllers orchestrate; services decide.**

```csharp
// ✅ Good: Pure business logic, easily unit tested
public class PricingCalculator
{
    public decimal CalculateTotal(IEnumerable<LineItem> items, decimal taxRate)
    {
        var subtotal = items.Sum(i => i.Price * i.Quantity);
        return subtotal * (1 + taxRate);
    }
}

// ❌ Bad: Business logic mixed with framework concerns
public class PricingController : ControllerBase
{
    [HttpGet]
    public IActionResult Calculate([FromQuery] Guid orderId)
    {
        // Business logic embedded in controller - hard to unit test
        var subtotal = _context.LineItems.Where(x => x.OrderId == orderId).Sum(x => x.Price * x.Quantity);
        var tax = subtotal * 0.08m;
        return Ok(subtotal + tax);
    }
}
```

### Class Cohesion

- **Split heavy classes.** If a class requires many collaborators (5+), it usually has multiple responsibilities. Break it into smaller types so unit tests remain focused and maintainable. A test that mocks five dependencies is a design smell — the production class is doing too much.
- **Use small, intention-revealing interfaces.** Prefer `IUserRepository` and `IInvoiceSender` over a single large `IServiceFacade`. Small interfaces yield simpler fakes and clearer tests. A fake for `IUserRepository` needs only `GetById`; a fake for `IServiceFacade` must implement dozens of unrelated methods.

### Seams for Testing

- **Expose seams for difficult-to-recreate inputs.** Use factories, builders, or protected virtual creation points to let tests supply test doubles without reflection or internal wiring hacks. Example: `DateTime.UtcNow` is hard to control; a protected virtual `GetCurrentTime()` allows tests to inject a fixed value.
- **Favor composition over static/helper methods.** Static state is a common source of test flakiness; prefer instance services resolved by DI so tests can scope lifetime and isolation. Static methods cannot be replaced without changing production code.

```csharp
// ✅ Good: Factory method creates a seam for testing
public class ReportGenerator
{
    protected virtual DateTime GetCurrentTime() => DateTime.UtcNow;

    public Report Generate()
    {
        var timestamp = GetCurrentTime(); // Overridable in tests
        // ...
    }
}

// In test:
public class TestableReportGenerator : ReportGenerator
{
    public DateTime FixedTime { get; set; }
    protected override DateTime GetCurrentTime() => FixedTime;
}
```

### Recommended Patterns and Helpers

- **Test Data Builders**: Provide fluent builders for common domain objects to keep Arrange sections concise and expressive. Example: `new OrderBuilder().WithCustomer(id).WithLine(amt).Build()`.
- **Factory + Override Hooks for WebHost**: As described in Functional project, expose `OverrideTestServices` and `OverrideConfigBuilder` for concise per-test adjustments without subclassing.
- **Adapters for 3rd-party SDKs**: Wrap external SDKs with small adapters (interfaces) so fakes can replace them during tests.

**Design investment ROI**: Reducing test setup complexity by even 20% often multiplies test authoring speed and reduces flakiness. If developers avoid writing tests because setup is painful, the design needs work.

---

## Project Structure

The physical organization of test projects reflects the three-tier model. Each tier gets its own project, with the Functional project serving as the shared infrastructure hub.

**Why this structure:**
- **Separate projects** — Enable selective execution (run only unit tests in CI; integration/functional on demand). A single mixed project forces "run everything" or fragile filter logic.
- **Clear boundaries** — When a test fails, the project name tells you the tier. New tests go in the obvious place.
- **Dependency direction** (Integration → Functional) — Prevents circular references. Shared fakes, helpers, and factories live in Functional; Integration references them. Unit may reference Functional only for pure, stable utilities (e.g., test data builders), not for host or environment concerns.

**How to apply:** Create the three projects before writing tests. Reference production code (Api, Core, Infrastructure) from each test project as needed. Do not create a fourth "shared unit helpers" project unless the solution has many services sharing the same utilities — prefer keeping unit helpers in the Unit project until reuse across services is proven.

```
Solution/
├── Services.{Service}.Api/            ← production API
├── Services.{Service}.Core/           ← core business logic
├── Services.{Service}.Infrastructure/ ← data access, external integrations
├── Testing.{Service}.Unit/            ← unit tests
│   ├── Tests/
│   ├── Helpers/
│   │   └── BaseTestConfiguration.cs
│   ├── TestCategories.cs
│   ├── Usings.cs
│   └── unittest.runsettings
├── Testing.{Service}.Integration/     ← integration tests
│   ├── Tests/
│   ├── BaseTestConfiguration.cs
│   ├── TestCategories.cs
│   ├── Usings.cs
│   └── automation.runsettings
└── Testing.{Service}.Functional/      ← shared infra + E2E tests
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

## 1. Unit Test Project

### Purpose

Unit tests protect business behavior at the lowest cost. They are the **foundation** of your test pyramid — the majority of your tests should live here.

**What "unit" means in this context:**

A **unit** is one observable behavior — a single business rule, state transition, or return value. This is NOT necessarily one class or one method:
- One class method that handles five distinct failure modes warrants five focused tests
- One business rule that spans multiple private methods is still one unit
- The key is: one test, one reason to fail

**What to test at this tier:**
- Business logic calculations and transformations
- Input validation and error handling paths
- State machine transitions
- Domain model invariants
- Edge cases and boundary conditions

**What NOT to test at this tier:**
- Database queries (no way to validate SQL behavior without SQL)
- HTTP middleware behavior (requires pipeline)
- Serialization fidelity (requires real serializers)
- DI wiring (requires real container)

### Core Principles

What this means in practice:

- Test one unit of behavior at a time (usually one public method or one business rule path). A **unit** here means one observable behavior — a single business rule, state transition, or return value. One class method that handles five distinct failure modes warrants five focused tests; one business rule that spans multiple private methods is still one unit.
- **Avoid real IO entirely**: no database, no HTTP calls, no file system, no queues. If you find yourself setting up a connection string, you’re in the wrong tier.
- Replace collaborators with test doubles only where they are true dependencies of the behavior. Don’t mock everything — mock what matters.

**Why this matters (the business case):**

| Benefit | Impact |
|---------|--------|
| Fast tests run on every commit | Catch regressions in seconds, not minutes |
| Failing tests point to a small area | Fixes take minutes, not hours of debugging |
| Suite remains maintainable as service grows | New team members can understand and add tests quickly |
| Tests document business behavior | Tests become living documentation of requirements |

### Decision Criteria

How to decide a test belongs in this tier:

- If you can assert the outcome using in-memory inputs and doubles, it is a unit test.
- If the assertion depends on SQL behavior, middleware, serialization, or DI wiring, move up a tier.

**Quick litmus test**: Can this test run without any environment variables, connection strings, or external processes? If yes → unit test. If no → wrong tier.

### Project File Essentials

Keep unit projects lightweight. Include only packages that support isolated behavior testing. Heavy infrastructure packages indicate the project is drifting from its purpose.

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net8.0</TargetFramework>
    <Nullable>enable</Nullable>
    <IsPackable>false</IsPackable>
    <RootNamespace>Profisee.Platform.Testing.{Service}.Unit</RootNamespace>
    <AppendTargetFrameworkToOutputPath>false</AppendTargetFrameworkToOutputPath>
  </PropertyGroup>

  <ItemGroup>
    <!-- Test framework -->
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="MSTest.TestAdapter" />
    <PackageReference Include="MSTest.TestFramework" />
    <!-- Assertions -->
    <PackageReference Include="FluentAssertions" />
    <!-- Mocking / substitution: standardize on one library across the repo -->
    <PackageReference Include="NSubstitute" />
    <!-- Coverage -->
    <PackageReference Include="coverlet.collector" />
    <!-- Serilog test sink -->
    <PackageReference Include="Serilog.Sinks.TestCorrelator" />
  </ItemGroup>

  <ItemGroup>
    <!-- Reference production code under test -->
    <ProjectReference Include="..\Services.{Service}.Api\Services.{Service}.Api.csproj" />
    <ProjectReference Include="..\Services.{Service}.Core\Services.{Service}.Core.csproj" />
    <!-- Optional: reference Functional only for pure, stable test utilities -->
    <ProjectReference Include="..\Testing.{Service}.Functional\Testing.{Service}.Functional.csproj" />
  </ItemGroup>
</Project>
```

Keep the dependency direction intentional: if `Testing.{Service}.Unit` starts depending on web host helpers or integration fixtures, split those helpers into a neutral shared test utility library.

### Parallelism

Unit tests should run at maximum parallelism. Set this in two places:

**`Usings.cs`** — applies the assembly-level attribute:

```csharp
global using FluentAssertions;
global using Microsoft.VisualStudio.TestTools.UnitTesting;

[assembly: Parallelize(Workers = 0, Scope = ExecutionScope.MethodLevel)]
```

> `Workers = 0` means "use the number of logical CPU cores."
>
> If tests fail only under parallel execution, treat that as a design signal (usually hidden shared mutable state) and fix the test/setup rather than disabling parallelism globally.

**`unittest.runsettings`** — mirrors the attribute for CLI/IDE runners:

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

### Assembly Initialization

Create `Helpers/BaseTestConfiguration.cs`. This is the single place for assembly-wide one-time setup. The class must carry `[TestClass]`; the method must be `static` and carry `[AssemblyInitialize]`.

Keep assembly initialization minimal and deterministic:

- Set global logging/test sinks.
- Register one-time serializer/config defaults.
- Avoid heavy startup work that belongs in integration/functional tiers.

```csharp
[TestClass]
public class BaseTestConfiguration
{
    [AssemblyInitialize]
    public static void AssemblySetup(TestContext _)
    {
        // Configure Serilog to write to the TestCorrelator sink so log output
        // is captured per-test and can be asserted on.
        Log.Logger = new LoggerConfiguration()
            .Enrich.FromLogContext()
            .WriteTo.TestCorrelator()
            .WriteTo.Console()
            .CreateLogger();

        // Any other one-time global state (e.g., Hangfire batch support) goes here.
    }
}
```

### Test Category Constants

Categorization is required. Create `TestCategories.cs` as an internal static class:

```csharp
/// <summary>
/// A test should carry exactly one primary category. Secondary categories are optional.
/// </summary>
internal static class UnitTestCategories
{
    #region Primary categories (architectural layer)
    public const string API            = "API";
    public const string Core           = "Core";
    public const string Infrastructure = "Infrastructure";
    #endregion

    #region Secondary categories (feature area — add as needed)
    public const string Validation  = "Validation cases";
    public const string HangfireJobs = "Hangfire jobs";
    // ... add more as the service grows
    #endregion

    #region Test type
    public const string HappyPath   = "Happy path";
    public const string UnhappyPath = "Unhappy path";
    #endregion
}
```

### Anatomy of a Unit Test

A well-structured unit test follows the **Arrange-Act-Assert** pattern. Each section has a specific purpose:

| Section | Purpose | Guidance |
|---------|---------|----------|
| **Arrange** | Set up inputs and dependencies | Keep minimal; only what the test needs. If Arrange dominates the test, the SUT may have too many dependencies or the test may be verifying too much. |
| **Act** | Execute the behavior under test | Usually one line; the method call. If Act spans multiple calls, consider whether you're testing orchestration (may belong in integration) or a single unit (split the test). |
| **Assert** | Verify the outcome | Assert business behavior, not implementation. Ask: "If a refactor preserved behavior, would this assertion still pass?" |

**Intent-focused authoring:** Before writing, answer: "What single behavior am I verifying?" The test name should capture that. If you cannot name it in one sentence, split the test.

```csharp
[TestClass]
[TestCategory(UnitTestCategories.Core)]           // primary category on the class
public class MyServiceTests
{
    [TestMethod]
    [TestCategory(UnitTestCategories.HappyPath)]  // test-type category on the method
    public async Task MyMethod_GivenValidInput_ReturnsExpectedResult()
    {
        // Arrange: define only inputs and doubles relevant to the behavior under test.
        var dependency = Substitute.For<IMyDependency>();
        dependency.GetValueAsync(Arg.Any<int>()).Returns(42);

        var sut = new MyService(dependency);

        // Act
        var result = await sut.MyMethodAsync(1);

        // Assert: express business expectation, not internal implementation.
        result.Should().Be(42);
    }
}
```

### Naming Conventions

**Test method naming**: `{MethodUnderTest}_{GivenContext}_{ExpectedOutcome}`

Good names read like sentences describing the behavior:

| Name | Reads As |
|------|----------|
| `CalculateTotal_WithDiscountApplied_ReturnsReducedPrice` | "Calculate total, with discount applied, returns reduced price" |
| `Validate_WhenEmailMissing_ReturnsValidationError` | "Validate, when email missing, returns validation error" |
| `ProcessOrder_ForInactiveCustomer_ThrowsInvalidOperationException` | "Process order, for inactive customer, throws invalid operation exception" |

### Data-Driven Tests

Use `[DataRow]` or `[DynamicData]` to reduce duplication when the same logic applies to multiple input variations:

```csharp
[TestMethod]
[TestCategory(UnitTestCategories.UnhappyPath)]
[DataRow("", "Name is required")]
[DataRow(null, "Name is required")]
[DataRow("  ", "Name is required")]
public void Validate_GivenBlankName_ReturnsExpectedError(string? name, string expectedMessage)
{
    // Arrange
    var sut = new NameValidator();

    // Act
    var result = sut.Validate(name);

    // Assert
    result.IsValid.Should().BeFalse();
    result.Error.Should().Be(expectedMessage);
}
```

Use `[DataRow]` for simple literal inputs. Use `[DynamicData]` (pointing to a static property or method) when inputs require object construction. Avoid overusing data-driven tests when scenarios have meaningfully different assertions — separate named test methods are clearer in those cases.

### Unit Test Quality Bar (Quality Over Quantity)

Use these heuristics instead of raw test count targets:

- **Each test should fail for one reason only** — Single behavior assertion focus. If the test name cannot describe a single behavior, split the test.
- **Prefer one clear assertion block** — Many loosely related assertions obscure which behavior failed. Assert the outcome, not the implementation path.
- **Add negative-path tests only when they represent meaningful business or safety behavior** — Not to raise coverage. A null guard on an already-validated parameter rarely needs a test.
- **Avoid asserting private implementation details** (e.g., exact internal method call counts) unless the interaction _is_ the observable behavior. Tests should survive refactoring.
- **When fixing a bug, add one regression test** — Fails before the fix, passes after. This is the most valuable test you can write.

**When to add a unit test:**
- A new business rule or calculation is introduced
- A bug escaped to production (regression test)
- A behavior has multiple outcomes (success vs error paths)

**When to skip a unit test:**
- The code is a trivial getter/setter or pass-through with no logic
- The behavior is already covered by an integration or functional test at the same level of fidelity
- The test would assert only that a mock was called (not the business outcome)

#### Mocks vs Fakes vs Spies (When to use each)

- **Mock (substitute / verify interactions)**: use when the interaction itself is the observable behavior (for example, an outbound message must be sent). Prefer interaction verification sparingly — only when the side effect is part of the business contract.
- **Fake (in-memory, deterministic implementation)**: use for external systems where behavior can be simulated cheaply (in-memory repo, in-process queue). Fakes are typically hand-rolled and live in the Functional project if reused.
- **Spy (fake + observation)**: use when tests need to assert what was sent to a dependency (e.g., notification recipients). Implement a Spy by recording inputs in a collection property that tests assert against.

Guideline: prefer Fakes or Spies over strict interaction mocks for higher-level behavioral tests; rely on mocks when testing protocol-level interaction contracts.

#### Async tests, CancellationToken and MSTest

- Always return `Task` from async test methods; never use `async void`.
- Prefer `public async Task TestName_...()` in MSTest for async flows. Use `CancellationToken` parameters on production methods and supply `CancellationToken.None` or a `CancellationTokenSource` in tests to assert cooperative cancellation.
- Keep async timeouts explicit in polling helpers; prefer polling helpers (see PollingAssert) over fixed `Task.Delay` calls.

#### Test Data Builders and Fixtures

- Use small, focused builders to construct domain objects used across tests. Builders reduce noise and centralize valid default values.
- Use fixtures sparingly for heavy resources. Prefer per-class fixtures (`[ClassInitialize]`) over global fixtures to keep test runs isolated.

**How many tests to write for a given unit:**

A useful mental model: cover the **happy path** once, then add one test per distinct **failure mode** or **branch**. For a typical service method:

- One test for the expected success outcome with valid inputs.
- One test per distinct error case (not found, invalid state, null argument, authorization failure).
- One test per meaningful boundary condition (empty collection, maximum value, exactly-at-limit vs over-limit).

Do not aim for 100% line coverage. Aim for 100% coverage of behaviors that matter — critical paths, error boundaries, and business rules. Lines inside `catch` blocks that rethrow, defensive null guards on already-validated parameters, and trivial property setters do not need dedicated tests.

**Test class setup guidance:**

Use `[TestInitialize]` only for setup that applies to _every_ test in the class without exception. If only some tests need a particular collaborator or configuration, set it up inline in the `// Arrange` block. Shared setup that is sometimes irrelevant creates invisible coupling between tests and hides what each test actually depends on.

Avoid `static` mutable fields in unit test classes — they can cause subtle interference between tests running in parallel.

**Recognizing test smells:**

| Smell                                                    | What it signals                                   | Fix                                                                   |
| -------------------------------------------------------- | ------------------------------------------------- | --------------------------------------------------------------------- |
| Arrange block sets up 5+ mocks                           | The SUT has too many dependencies                 | Decompose the production class; the test is exposing a design problem |
| Arrange block is longer than Act + Assert combined       | Test is verifying too much in one shot            | Split into focused, single-behavior tests                             |
| Test asserts on 5+ unrelated properties                  | Test is covering multiple behaviors               | Extract to separate test methods                                      |
| Test only passes because a mock returns a specific value | Test is asserting mock behavior, not SUT behavior | Remove the mock or assert the business outcome instead                |
| Test name is vague (`Test1`, `MyService_Works`)          | Test intent is unclear                            | Rename using `{Method}_{Context}_{Outcome}`                           |
| Test passes even when the feature is broken              | Test is asserting the wrong thing                 | Add a failing assertion before writing the fix (red-green discipline) |

---

## 2. Functional Project (Shared Test Infrastructure)

### Purpose and Dual Role

This project serves a **dual purpose** that is critical to understand:

1. **Shared Infrastructure Library**: Contains reusable test helpers, fakes, factories, and fixtures that both this project's tests AND the Integration project depend on
2. **End-to-End Test Host**: Contains its own test classes that validate the full application pipeline

**Why this design?** Centralizing test infrastructure prevents duplication, ensures consistent behavior across test tiers, and makes maintenance easier. The Integration project references this project (not the other way around) to access shared helpers.

### What Lives Here

| Folder | Contents | Purpose |
|--------|----------|---------|
| `Fakes/` | Hand-rolled implementations | Replace production services (auth, security, external APIs) |
| `Helpers/` | Utility classes | Data setup, database queries, polling, config retrieval |
| `Factories/` | `WebApplicationFactory<T>` subclasses | Host the real API in-process for testing |
| `Fixtures/` | Configuration objects | `TestConfigSettings`, shared test data structures |
| `Tests/` | E2E test classes | Full pipeline validation (auth, routing, serialization) |

### Architecture Guidance

- Treat this project as your reusable **test host layer**.
- Keep business assertions in test classes; keep environment/bootstrap concerns in this project.
- Avoid pushing service-specific business rules into shared helpers — helpers should be generic infrastructure.

**For existing repos**: Move duplicated fakes/factories from integration tests into this project first, then consolidate environment/config helpers.

### Project File Essentials

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsPackable>false</IsPackable>
    <IsTestProject>true</IsTestProject>
    <AssemblyName>Profisee.Platform.Testing.{Service}.Functional</AssemblyName>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="MSTest.TestAdapter" />
    <PackageReference Include="MSTest.TestFramework" />
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="FluentAssertions.Json" />
    <PackageReference Include="NSubstitute" />
    <PackageReference Include="Microsoft.AspNetCore.Mvc.Testing" />
    <PackageReference Include="coverlet.collector" />
    <PackageReference Include="NServiceBus.Serilog" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\Services.{Service}.Api\..." />
    <ProjectReference Include="..\Services.{Service}.Infrastructure\..." />
  </ItemGroup>
</Project>
```

### Environment-Driven Settings

Integration and functional tests require a real database and a running Profisee instance. **Never hard-code connection strings.** All environment-specific values come from environment variables.

**`Helpers/SettingsRetriever.cs`** — reads environment variables and throws clearly if missing:

```csharp
public static class SettingsRetriever
{
    public static string SqlServer    => get(nameof(SqlServer));
    public static string MaestroDb    => get(nameof(MaestroDb));
    public static string ServerURL    => get(nameof(ServerURL));
    public static bool UseSeparateDatabases => getBool(nameof(UseSeparateDatabases));

    private static string get(string envVarName)
    {
        var value = Environment.GetEnvironmentVariable(envVarName);
        if (string.IsNullOrWhiteSpace(value))
            throw new ArgumentException($"Environment variable '{envVarName}' is not set.");
        return value;
    }

    private static bool getBool(string envVarName)
    {
        if (!bool.TryParse(get(envVarName), out bool parsed))
            throw new ArgumentException($"Environment variable '{envVarName}' must be true or false.");
        return parsed;
    }
}
```

> **Why throw instead of defaulting?** Tests that silently run against the wrong database or skip setup are harder to debug than tests that fail immediately with a clear message. **Fail fast** is the guiding principle for test configuration.

**`Helpers/AppSettingsHelper.cs`** — assembles the service's `AppSettings` object from `SettingsRetriever`:

```csharp
public static class AppSettingsHelper
{
    /// <summary>
    /// Creates a fully-configured AppSettings instance for test execution.
    /// All values are sourced from environment variables via SettingsRetriever.
    /// </summary>
    /// <exception cref="InvalidOperationException">Thrown when required configuration is missing.</exception>
    public static MyServiceAppSettings GetDefaultAppSettings()
    {
        var db = SettingsRetriever.MaestroDb
            ?? throw new InvalidOperationException("DB catalog cannot be null.");

        return new MyServiceAppSettings
        {
            ServiceDBConnection = BuildConnectionString(SettingsRetriever.SqlServer, db),
            // ... other settings
        };
    }
}
```

**When to use exceptions vs `Assert.Inconclusive`:**
- **Exceptions**: Use for missing REQUIRED settings — the test cannot run without them
- **`Assert.Inconclusive`**: Use for OPTIONAL scenarios (e.g., opt-in long-running suite, feature flag tests)

**`Fixtures/TestConfigSettings.cs`** — a `Dictionary<string, string?>` used to configure the in-process `WebApplicationFactory`. This replaces `appsettings.json` in tests:

```csharp
/// <summary>
/// Configuration dictionary for WebApplicationFactory. Use this as the single source
/// of truth for test-host configuration to prevent key drift between test classes.
/// </summary>
public class TestConfigSettings : Dictionary<string, string?>
{
    public TestConfigSettings()
    {
        this["ProfiseeAppSettings:ServiceDBConnection"] =
            $"Data Source={SettingsRetriever.SqlServer};Initial Catalog={SettingsRetriever.MaestroDb};...";
        this["ProfiseeAppSettings:AuthUrl"] = SettingsRetriever.ServerURL + "/auth";
        // ... other settings
    }
}
```

Use this fixture as the single source for test-host configuration keys. This avoids key drift between test classes.

### Fakes

Fakes are hand-rolled implementations of interfaces that need to be replaced for tests to work without real infrastructure.

**Why use fakes instead of mocks here?**
- Fakes provide predictable, reusable behavior across many tests
- Fakes are easier to debug (real code vs mock setup)
- Fakes can evolve as requirements change without updating every test

**Common fakes in a typical service:**

| Fake                  | What it replaces           | Why                                                           |
| --------------------- | -------------------------- | ------------------------------------------------------------- |
| `FakeAuthHandler`     | `AuthenticationHandler<T>` | Always returns an authenticated user — no bearer token needed |
| `FakeUserService`     | `IUserService`             | Bypasses WCF call to get user credentials                     |
| `FakeSecurityService` | `ISecurityService`         | Bypasses permission checks                                    |

**Naming conventions:**
- `Fake{InterfaceName}` — silent stand-in that provides working behavior
- `Spy{InterfaceName}` — observable stand-in that records calls for assertion

#### Rules for Writing Fakes

| Rule | Why |
|------|-----|
| Keep behavior deterministic and minimal | Fakes should be simple and predictable |
| Only implement behavior needed by current test cases | YAGNI applies to test infrastructure too |
| Do NOT encode production business rules | Fakes should simulate, not replicate |
| Add unit tests for complex fakes | Prevent accidental regressions in test infrastructure |

**Fake vs Spy distinction** — use a Fake when the test only needs the dependency to _not fail_; use a Spy when the test needs to _assert that a side-effecting call was made_:

```csharp
// Fakes/SpyNotificationService.cs
// A Spy records calls in addition to providing working fake behavior.
// Use this when a test needs to assert what was sent, not just that no exception occurred.
public class SpyNotificationService : INotificationService
{
    /// <summary>
    /// Captures all recipients and messages sent during a test run.
    /// Inspect this collection in assertions after the act step.
    /// </summary>
    public List<string> SentNotifications { get; } = new();

    public Task SendAsync(string recipient, string message, CancellationToken ct = default)
    {
        SentNotifications.Add($"{recipient}:{message}");
        return Task.CompletedTask;
    }
}

// Usage in a functional test class:
// var spy = new SpyNotificationService();
// ... inject spy via OverrideTestServices ...
// spy.SentNotifications.Should().ContainSingle()
//     .Which.Should().StartWith("admin@example.com:");
```

> **Naming rule**: `Fake{Name}` for silent stand-ins, `Spy{Name}` for observable stand-ins. This makes a test class's dependency on call-capture behavior visible at a glance.

### The App Factory

The `WebApplicationFactory<TEntryPoint>` is the cornerstone of functional tests. It boots the real API startup code in-process, then swaps out production services with fakes.

**Why use WebApplicationFactory?**
- **Runs the REAL application startup code** — Not a mock. Validates that `Program.cs` / `Startup` actually works. Catches DI registration errors, missing middleware, and configuration binding issues that unit and integration tests cannot see.
- **In-process HTTP client** — No network latency; requests hit the same process. Fast and deterministic.
- **Surgical service replacement** — Replace auth, external APIs, or databases with fakes while keeping the rest of the pipeline real. Tests validate wiring, not just individual components.

**What to validate here:** Authentication flow, authorization policies, middleware order, JSON serialization round-trips, routing. **What not to validate:** Individual repository queries (use integration tests) or pure business logic (use unit tests).

#### Key Design Decisions

| Concern | Approach | Why |
|---------|----------|-----|
| Configuration | `AddInMemoryCollection` injection | No file system dependency; test-controlled values |
| Authentication | Replace with `FakeAuthHandler` | Skip token validation; always authenticated |
| Authorization | Replace default policy | Skip permission checks; always authorized |
| External services | `services.Replace(...)` with fakes | Isolate from production dependencies |
| Per-test customization | `OverrideTestServices` callback | Avoid factory subclass proliferation |

#### Lifecycle Guidance

| Practice | Why |
|----------|-----|
| One factory per test class | Isolates test class configuration |
| Reuse `HttpClient` within class | Avoids socket exhaustion |
| Dispose in `[ClassCleanup]` | Prevents handler leaks in long runs |

```csharp
// Conceptual structure — adapt to your service's TEntryPoint and AppSettings type
public class MyServiceAppFactory : WebApplicationFactory<MyApiEntryPoint>
{
    public TestConfigSettings AppConfig { get; set; } = new();

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureAppConfiguration(config =>
            config.AddInMemoryCollection(AppConfig));

        builder.ConfigureTestServices(services =>
        {
            // Bypass authentication and authorization
            services.AddAuthentication("Test")
                .AddScheme<AuthenticationSchemeOptions, FakeAuthHandler>("Test", _ => { });
            services.AddAuthorization(opts =>
                opts.DefaultPolicy = new AuthorizationPolicyBuilder()
                    .RequireAssertion(_ => true).Build());

            // Replace production services with fakes
            services.Replace(ServiceDescriptor.Singleton<IUserService, FakeUserService>());
            services.Replace(ServiceDescriptor.Scoped<ISecurityService, FakeSecurityService>());
        });
    }
}
```

Keep all service replacement logic (`services.Replace(...)`) in one method to make dependency overrides auditable during code review.

**Supporting per-test-class overrides** — expose callback hooks so individual test classes can customize the factory for specific scenarios without proliferating subclasses:

```csharp
public class MyServiceAppFactory : WebApplicationFactory<MyApiEntryPoint>
{
    public TestConfigSettings AppConfig { get; set; } = new();

    // Set this in a test class's [ClassInitialize] to inject a Spy or override a config value
    // for a specific test scenario without creating a new factory subclass.
    public Action<IServiceCollection>? OverrideTestServices { get; set; }
    public Action<IConfigurationBuilder>? OverrideConfigBuilder { get; set; }

    protected override void ConfigureWebHost(IWebHostBuilder builder)
    {
        builder.ConfigureAppConfiguration(config =>
        {
            config.AddInMemoryCollection(AppConfig);
            OverrideConfigBuilder?.Invoke(config);  // applied after base config so it wins
        });

        builder.ConfigureTestServices(services =>
        {
            // Standard fakes registered here for all test classes
            services.AddAuthentication("Test")
                .AddScheme<AuthenticationSchemeOptions, FakeAuthHandler>("Test", _ => { });

            services.Replace(ServiceDescriptor.Singleton<IUserService, FakeUserService>());

            // Test-class-specific overrides applied last so they take precedence
            OverrideTestServices?.Invoke(services);
        });
    }
}

// Usage: a test class that needs to capture emails via a Spy
[ClassInitialize]
public static void ClassSetup(TestContext _)
{
    _spy = new SpyNotificationService();
    _factory = new MyServiceAppFactory
    {
        OverrideTestServices = services =>
            services.Replace(ServiceDescriptor.Singleton<INotificationService>(_spy))
    };
    _client = _factory.CreateClient();
}
```

> **Why callbacks over subclasses?** Each subclass of `WebApplicationFactory` creates a separate bootstrapped host. Callbacks allow customization without the overhead of a new host and keep all override patterns visible in the test class itself.

### Assembly Initialization (Functional)

The Functional project's `BaseTestConfiguration.cs` handles heavier one-time setup: stopping IIS app pools that share the same database schema, clearing distributed caches, and starting messaging infrastructure.

#### Safety Requirements

| Requirement | Why |
|-------------|-----|
| Log target identifiers before destructive steps | Audit trail for debugging and incident response |
| Guard environment-sensitive steps | Block accidental execution against production-like hosts |
| Make cleanup idempotent | Failed runs should not poison subsequent runs |

```csharp
[TestClass]
public class BaseTestConfiguration
{
    [AssemblyInitialize]
    public static async Task AssemblySetup(TestContext _)
    {
        // SAFETY: Log what we're about to affect
        Console.WriteLine($"Stopping app pool for service tests against: {SettingsRetriever.SqlServer}");

        // Stop the production IIS service so tests can connect to the same DB without conflicts
        IisAppPoolManager.StopAppPool("Profisee-{service}");

        // Clear any stale distributed cache entries
        await CacheCleaner.ClearAsync(AppSettingsHelper.GetDefaultAppSettings().ServiceDBConnection);

        // Configure Serilog (optional — commented out by default to reduce noise)
        // Log.Logger = new LoggerConfiguration().MinimumLevel.Warning().WriteTo.Console().CreateLogger();

        // Configure NServiceBus to use Serilog
        NServiceBus.Logging.LogManager.Use<SerilogFactory>();
    }

    [AssemblyCleanup]
    public static void AssemblyCleanup()
    {
        // Tear down messaging, then restore IIS
        MessagingHelper.ClearMessageQueue();
        MessagingHelper.StopMessageSession();
        IisAppPoolManager.StartAppPool("Profisee-{service}");
    }
}
```

> **Why stop IIS?** The production service and the test in-process host compete for the same SQL Server schema (Hangfire tables, etc.). Stopping the production app pool prevents lock conflicts during test runs.

### The PollingAssert Pattern

**Why polling instead of `Task.Delay`?**
- **Fixed delays are brittle** — Too short → flaky tests that fail under load. Too long → slow suite. Polling adapts to actual completion time.
- **Clear diagnostics** — When a poll times out, the failure message can include what was being waited for. A bare `Task.Delay(30000)` gives no context.
- **Deterministic under load** — Polling completes as soon as the condition is met; no arbitrary wait.

Functional tests often need to wait for asynchronous side effects (e.g., a Hangfire job completing, a message being processed). Use polling instead of fixed delays:

```csharp
// Poll every 100ms for up to maxWaitMs before failing
bool result = await PollingAssert.PollAsync(
    assertion: async () => await JobHasCompleted(jobId),
    maxWaitTimeMs: 30_000);

result.Should().BeTrue("the job should have completed within 30 seconds");
```

Keep polling helpers centralized and configurable (`poll interval`, `timeout`, `failure message`) so asynchronous tests fail with useful diagnostics instead of generic timeouts.

---

## 3. Integration Test Project

### Purpose

Integration tests validate infrastructure behavior against **real dependencies** — actual databases, actual file systems, actual external services.

**Why this tier exists:**

Unit tests mock infrastructure, which means they cannot catch infrastructure-specific failures. Integration tests fill that gap. They answer: "Does our code work correctly when talking to the real database, cache, or file system?" Without this tier, SQL bugs, schema drift, and serialization issues reach production.

**What unit tests cannot catch:**
- SQL query syntax errors or performance problems
- Schema drift (column renamed, type changed)
- Constraint violations (unique, foreign key)
- Index behavior (covering indexes, query plans)
- Transaction semantics (isolation levels, deadlocks)

Integration tests catch these issues before they reach production.

### What to Test Here

| Test Category | Examples |
|--------------|----------|
| Repository queries | Correct columns returned, null handling, ordering |
| Persistence rules | Unique constraints, foreign keys, cascades |
| Transaction behavior | Rollback on failure, isolation level effects |
| Cache adapters | Serialization round-trips, expiration behavior |
| Index behavior | Query uses expected index, no table scans |

### What NOT to Test Here

| Wrong Tier | Correct Tier | Why |
|------------|--------------|-----|
| Full HTTP pipeline | Functional | Integration tests don't boot the web host |
| Pure business rules | Unit | No infrastructure needed; faster at unit tier |
| DI wiring validation | Functional | Requires full container |

**Key principle**: Instantiate components directly so failures point to infrastructure logic without full host startup noise.

### Project File Essentials

```xml
<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <IsTestProject>true</IsTestProject>
    <AssemblyName>Profisee.Platform.Testing.{Service}.Integration</AssemblyName>
  </PropertyGroup>

  <ItemGroup>
    <PackageReference Include="Microsoft.NET.Test.Sdk" />
    <PackageReference Include="MSTest.TestAdapter" />
    <PackageReference Include="MSTest.TestFramework" />
    <PackageReference Include="FluentAssertions" />
    <PackageReference Include="FluentAssertions.Json" />
    <PackageReference Include="NSubstitute" />
    <PackageReference Include="coverlet.collector" />
    <!-- Custom MSTest extension for log capture on test result -->
    <PackageReference Include="Profisee.Platform.Utilities.Testing.Extensions.MSTest" />
  </ItemGroup>

  <ItemGroup>
    <ProjectReference Include="..\Services.{Service}.Api\..." />
    <ProjectReference Include="..\Services.{Service}.Infrastructure\..." />
    <!-- Reference the Functional project for shared helpers and fakes -->
    <ProjectReference Include="..\Testing.{Service}.Functional\..." />
  </ItemGroup>

  <!-- Copy appsettings from the API project so DI bootstrapping can find it -->
  <Target Name="PostBuild" AfterTargets="PostBuildEvent">
    <Exec Command="copy &quot;$(SolutionDir)Services.{Service}.Api\appsettings.json&quot; &quot;$(TargetDir)&quot;" />
  </Target>
</Project>
```

### Parallelism

Integration tests touch a shared database. Class-level parallelism with a single worker prevents data races:

**`automation.runsettings`**:

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

If test runtime becomes too long, optimize data setup and fixture reuse first. Do not increase worker count against a shared schema unless test data isolation guarantees are proven.

### Assembly Initialization

The Integration project's `BaseTestConfiguration.cs` is lighter than Functional — it typically just clears the distributed cache. No need to stop IIS because integration tests don't compete with the web host.

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

**Idempotency requirement**: A failed test run should NOT leave the next run in a poisoned state. Write setup to be safe to run multiple times.

### Anatomy of an Integration Test

Integration tests use `[ClassInitialize]` / `[ClassCleanup]` to create and tear down test data per test class, keeping test classes isolated from each other.

**Why class-level setup instead of method-level?**
- Database round-trips are expensive (~100ms each)
- Class-level setup runs once, method-level runs before EVERY test
- Class-level keeps related tests grouped with their shared data

```csharp
[LogResultTestClass]                                          // captures logs on failure
[TestCategory(AutomationTestCategories.Infrastructure)]
[TestCategory(AutomationTestCategories.GraphTables)]
public class MyRepositoryTests
{
    private static MyAppSettings? appSettings;
    private static MyTestHelper? testHelper;

    [ClassInitialize]
    public static void ClassSetup(TestContext _)
    {
        appSettings = AppSettingsHelper.GetDefaultAppSettings();
        testHelper  = new MyTestHelper(appSettings);

        // Create any required test data
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
        // Arrange — instantiate the component under test directly (no DI)
        var repo = new MyRepository(appSettings!);
        await testHelper!.InsertTestRecordAsync("TEST001");

        // Act
        var result = await repo.GetAsync("TEST001");

        // Assert
        result.Should().NotBeNull();
        result!.Code.Should().Be("TEST001");
    }
}
```

Key differences from unit tests:

- **No mocks** for the component under test (only for irrelevant external deps)
- **Real database** — actual SQL connections
- **`[LogResultTestClass]`** — custom attribute that captures and reports Serilog output when a test fails, making it much easier to diagnose failures

Data lifecycle guidance:

- Create data unique to the test class (for example, prefixed IDs with GUID suffixes) to avoid cross-class collisions.
- Prefer explicit cleanup in `ClassCleanup` even if teardown scripts exist.
- Avoid relying on execution order between test classes.

**Test data isolation strategies in detail:**

| Strategy              | When to use                                                  | Example                                                    |
| --------------------- | ------------------------------------------------------------ | ---------------------------------------------------------- |
| Prefixed string IDs   | When the schema uses string or name keys                     | `$"TEST_{nameof(MyRepositoryTests)}_{Guid.NewGuid():N}"`   |
| GUID primary keys     | When the schema uses `uniqueidentifier` PKs                  | `Guid.NewGuid()` — guaranteed unique per test run          |
| Dedicated test schema | When the service supports multi-tenancy or schema separation | Create schema in `ClassInitialize`, drop in `ClassCleanup` |
| Scoped DB transaction | When tests must not commit data at all                       | Wrap each test in a transaction; roll back in cleanup      |

The simplest and most common pattern is the **prefixed ID**: it survives failed cleanup runs (you can query by prefix to see stale data), makes logs readable (you can grep by class name), and does not require schema-level isolation support.

If `ClassInitialize` throws before all setup steps complete, `ClassCleanup` may still run. Write cleanup to be **idempotent** — use `DELETE WHERE ... IF EXISTS` style SQL rather than assuming data is present.

### `[LogResultTestClass]`

This is a custom MSTest attribute from `Profisee.Platform.Utilities.Testing.Extensions.MSTest`. Apply it to every integration and functional test class. It hooks into the MSTest lifecycle to write captured log output to the test result's `Message` field on failure.

### MSTest Lifecycle Scope Reference

Understanding which setup attribute to use prevents both duplicated setup work and subtle test isolation problems:

| Attribute              | Runs                       | Runs as                                | Use for                                                      |
| ---------------------- | -------------------------- | -------------------------------------- | ------------------------------------------------------------ |
| `[AssemblyInitialize]` | Once per test assembly     | `static` method on `[TestClass]` class | Global one-time setup: logging, cache clear, IIS stop        |
| `[AssemblyCleanup]`    | Once per test assembly     | `static` method on `[TestClass]` class | Teardown: restart IIS, stop messaging sessions               |
| `[ClassInitialize]`    | Once per test class        | `static` method                        | Per-class test data creation, shared repository/helper setup |
| `[ClassCleanup]`       | Once per test class        | `static` method                        | Per-class data deletion, resource disposal                   |
| `[TestInitialize]`     | Before _every_ test method | Instance method                        | Reset mutable state that must be clean for each test         |
| `[TestCleanup]`        | After _every_ test method  | Instance method                        | Per-test teardown (use sparingly; prefer `ClassCleanup`)     |

**Practical rules:**

- Integration tests: use `[ClassInitialize]` / `[ClassCleanup]` for test data. The cost of database round-trips per test method (`[TestInitialize]`) is too high.
- Unit tests: prefer constructor-based setup for invariant state. Use `[TestInitialize]` only when resetting mutable shared state is genuinely necessary — running it before every test that does not need it is waste.
- Never put test data creation in `[AssemblyInitialize]` for integration tests — shared data causes cross-class coupling and makes test failures hard to isolate.

### Integration Test Quality Bar (Quality Over Quantity)

**The goal**: Validate infrastructure contracts with the minimum number of tests that provide confidence.

#### What to Cover

| Coverage Area | Number of Tests | Why |
|--------------|-----------------|-----|
| CRUD operations | 1 per operation | Validate basic SQL works |
| Null handling | 1 per nullable column with business meaning | SQL null semantics differ from C# |
| Constraint violations | 1 per constraint | Verify DB enforces rules |
| Edge cases | 1 per boundary | Empty collections, max lengths |

#### Quality Principles

| Principle | Why |
|-----------|-----|
| Use realistic domain-shaped test data | Random strings hide real problems; realistic data reveals them |
| Prefer fewer stable tests with strong diagnostics | One reliable test beats five flaky ones |
| Add regression tests for production SQL errors | Prevent repeat incidents |

**When to add a new integration test:**
- A SQL-related bug escapes to production → add test that reproduces it
- New repository method added → add test for expected behavior
- Schema change affects existing queries → verify with test

**When NOT to add an integration test:**
- Business rule can be validated in unit test
- Coverage is purely for metrics, not risk reduction

---

## 4. Central Package Version Management

All three test projects should share package versions with the rest of the solution via `Directory.Packages.props` in the solution root. This prevents version drift between production and test code.

Why this matters:

- Upgrades happen once, not in each `.csproj`.
- Adapter/framework mismatches are reduced.
- Dependency reviews are easier in pull requests.

```xml
<!-- In Directory.Packages.props (solution root) -->
<PackageVersion Include="MSTest.TestAdapter"           Version="x.y.z" />
<PackageVersion Include="MSTest.TestFramework"         Version="x.y.z" />
<PackageVersion Include="Microsoft.NET.Test.Sdk"       Version="x.y.z" />
<PackageVersion Include="FluentAssertions"             Version="x.y.z" />
<PackageVersion Include="NSubstitute"                  Version="x.y.z" />
<PackageVersion Include="coverlet.collector"           Version="x.y.z" />
<PackageVersion Include="Serilog.Sinks.TestCorrelator" Version="x.y.z" />
```

Test projects reference packages **without** specifying versions:

```xml
<PackageReference Include="FluentAssertions" />
```

---

## 5. Environment Variable Requirements

Integration and functional tests require specific environment variables to be set on the developer machine or CI agent **before** running tests.

### Using Dev-Utilities (Recommended for Local Development)

**Most developers already have these configured.** The platform's `dev-utilities` (`ProfiseeDevUtils`) manages environment variables via `customVars.json`. If you've set up your local development environment using dev-utilities, the required test variables are already present.

**Location**: `{ReposRoot}\dev-utilities\ProfiseeDevUtils\local\customVars.json`

**To verify your current configuration:**
```powershell
# From the dev-utilities directory, run the utility to see all configured variables
# Or check the environment directly:
[Environment]::GetEnvironmentVariable("SqlServer")
[Environment]::GetEnvironmentVariable("MaestroDb")
```

### Required Variables (Mapped from Dev-Utilities)

The test infrastructure reuses existing platform environment variables — no additional configuration needed if dev-utilities is configured:

| Test Variable          | Dev-Utilities Variable   | Example Value                              | Used By                 |
| ---------------------- | ------------------------ | ------------------------------------------ | ----------------------- |
| `SqlServer`            | `SqlServer`              | `CORPLTR94`                                | Connection strings      |
| `MaestroDb`            | `MaestroDb`              | `Profisee`                                 | DB catalog name         |
| `ServerURL`            | `ServerURL`              | `https://CORPLTR94.corp.profisee.com/Profisee` | API endpoint       |
| `ServicesPublishPath`  | `ServicesPublishPath`    | `{ReposRoot}\platform\Server\Services` | Path to deployed services |
| `UseSeparateDatabases` | `UseSeparateDatabases`   | `false`                                    | DB catalog separation   |

### Additional Variables Available from Dev-Utilities

These variables are also available and may be useful for specific test scenarios:

| Variable                   | Purpose                                      |
| -------------------------- | -------------------------------------------- |
| `ServerRESTUrl`            | Full REST API URL with trailing slash        |
| `ServerRESTVersion`        | REST API version (e.g., `v1`)                |
| `MaestroAppPoolName`       | IIS App Pool name for the service            |
| `AutomationFolder`         | Path to automation test assets               |
| `UseWindowsAuthentication` | Whether Windows auth is enabled              |
| `UseHttps`                 | Whether HTTPS is configured                  |

### Why Environment Variables Instead of `appsettings.json`?

- Same test binary runs against different environments (dev, QA, staging)
- No secrets in source control
- CI agents can inject environment-specific values without file changes
- **Consistency with existing platform tooling** — dev-utilities already manages these

> ⚠️ **Safety**: The tests run against your configured `MaestroDb`. If you need isolation, create a separate database and update `customVars.json` or use a snapshot (`MaestroSnap`).

### Quick Validation Script (PowerShell)

Run this before starting integration/functional tests to catch missing configuration early:

```powershell
$required = @("SqlServer", "MaestroDb", "ServerURL", "ServicesPublishPath", "UseSeparateDatabases")
$missing = @()

foreach ($var in $required) {
    $value = [Environment]::GetEnvironmentVariable($var)
    if ([string]::IsNullOrWhiteSpace($value)) {
        $missing += $var
    } else {
        Write-Host "${var}: $value" -ForegroundColor Gray
    }
}

if ($missing.Count -gt 0) {
    Write-Host "`nMissing environment variables:" -ForegroundColor Red
    $missing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    Write-Host "`nRun dev-utilities to configure these, or set them manually." -ForegroundColor Yellow
    throw "Missing required environment variables"
}

Write-Host "`nAll required environment variables are set." -ForegroundColor Green
```

### CI Agent Configuration

For CI pipelines, ensure the build agent has these variables set. Options:
- **Azure DevOps**: Use variable groups linked to the pipeline
- **Self-hosted agents**: Configure via the dev-utilities on the agent machine
- **Pipeline variables**: Set inline in the YAML (avoid secrets in plain text)

---

## 6. CI Pipeline Integration

### Pipeline Strategy by Tier

| Tier | Runs In | Frequency | Why |
|------|---------|-----------|-----|
| Unit | Default CI pipeline | Every PR, every push | Fast, no infrastructure needed |
| Integration | Dedicated pipeline | Nightly or on-demand | Requires database access |
| Functional | Dedicated pipeline | Nightly or on-demand | Requires full environment |

### Unit Tests in CI

**Unit tests run on every build** (every PR, every branch push). They have no environmental requirements and are fast.

```yaml
- task: DotNetCoreCLI@2
  displayName: "run unit tests"
  inputs:
    command: "test"
    projects: "**/Testing.{Service}.Unit.csproj"
    arguments: '--configuration Debug --no-restore --settings unittest.runsettings --collect "Code coverage"'
```

### Integration/Functional Tests

**Integration and functional tests do not run in the default CI pipeline**. Run them in a dedicated pipeline on a self-hosted agent with required environment variables and test infrastructure.

**Why separate?**
- They require database access (self-hosted agent with network access)
- They take longer (don't block PR merges)
- They may have environment-specific failures (easier to diagnose on dedicated agent)

### Coverage and Signal Quality

Coverage is useful as a **trend indicator**, not a target:

| Practice | Why |
|----------|-----|
| Track coverage trends over time | Declining coverage signals gaps |
| Prioritize changed code paths | New/modified code should have tests |
| Require regression tests for bug fixes | Prove the fix works; prevent recurrence |

**Do NOT**: Gate PRs on arbitrary coverage thresholds. This encourages low-value tests written just to pass the gate.

---

## 7. Global Usings

Reduce boilerplate across test files by declaring common namespaces in `Usings.cs` (unit) or `GlobalUsings.cs` (integration/functional).

Minimum for unit tests:

```csharp
global using FluentAssertions;
global using Microsoft.VisualStudio.TestTools.UnitTesting;
```

Guidelines:

- Add service-specific globals only for types used in most test files.
- Keep global imports stable and minimal.
- Avoid broad imports that create ambiguous type names.

---

## 8. Test Files as Test Data

If tests rely on static input files (JSON payloads, CSV imports, etc.), place them in a `TestFiles/` folder within the project. Configure the `.csproj` to copy them to the output directory:

```xml
<ItemGroup>
  <Content Include="TestFiles\**\*.*">
    <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
  </Content>
</ItemGroup>
```

Access the folder at runtime:

```csharp
var testFilesFolder = Path.Combine(
    Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location)!,
    "TestFiles");
```

Best practices:

- Keep test files small and scoped to one scenario.
- Name files by intent (for example, `minimal-valid-request.json`).
- Treat static fixtures as immutable; copy in memory before mutation.

---

## 9. C# Test Comment Standards

Test code should be readable without excessive comments. Use comments to explain **intent and why**, not obvious mechanics.

**Principle:** A developer reading a test should understand *what behavior is being verified* and *why that scenario matters*. The test name and assertions carry most of that load; comments fill gaps.

### XML Comments for Reusable Helpers, Fakes, and Factories

Add XML documentation to any public helper, factory, fake, or spy consumed by multiple tests. Focus on **intent and usage context**:

```csharp
/// <summary>
/// Creates a repository with a real SQL connection for integration tests.
/// Use when validating query behavior against actual schema/indexes.
/// </summary>
/// <remarks>
/// Caller is responsible for disposing. Do not use for unit tests — use a fake instead.
/// </remarks>
public static MyRepository CreateRepository(MyAppSettings settings) => new(settings);
```

**What to include:**
- `<summary>` — One sentence: what it does and when to use it
- `<param>` / `<returns>` — For non-obvious parameters or return values
- `<remarks>` — Side effects, lifecycle expectations, or warnings (e.g., mutates shared state)

**What to skip:** XML on individual test methods. A well-named test (`Validate_WhenEmailMissing_ReturnsValidationError`) obviates the need for per-method docs.

### Inline Comments for Business Intent

Use short inline comments when the *why* is not obvious from the code:

```csharp
// Arrange: customer is inactive, so command should be rejected.
var command = new CreateOrderCommand(customerIsActive: false);
```

```csharp
// Act: simulate timeout — repository should return null, not throw.
dependency.GetAsync(Arg.Any<string>()).Returns(Task.FromResult<Record?>(null));
```

**Avoid:**
- Restating what the code does line-by-line
- Stale comments after behavior changes
- Hiding assumptions only in comments — encode them in test names and assertions

Example for a reusable builder helper:

```csharp
/// <summary>
/// Builds a valid <see cref="Order"/> with sensible defaults. Callers may override
/// properties via fluent methods when a specific scenario is required.
/// </summary>
/// <remarks>
/// The builder uses an in-memory default customer and should not be used as a data
/// migration tool. Use unique suffixes for persisted keys to avoid collisions.
/// </remarks>
public sealed class OrderBuilder { /* ... */ }
```

---

## 10. Quick-Start Checklist

Use this when adding the testing layer to a new service repo or auditing/refactoring an existing one.

**How to use this checklist:**
- For **new repos**: Work through each section sequentially
- For **existing repos**: Use as an audit tool — check items that exist, flag gaps
- For **refactoring**: Start with the "Refactor/Audit flow" section

**Quick verification (after setup):**
```powershell
# Unit tests — should complete in seconds, no environment required
dotnet test **/Testing.{Service}.Unit.csproj --settings unittest.runsettings

# Integration/Functional — require env vars; use automation.runsettings
dotnet test **/Testing.{Service}.Integration.csproj --settings automation.runsettings
dotnet test **/Testing.{Service}.Functional.csproj --settings automation.runsettings
```

### Unit test project

- [ ] Project name follows `Testing.{Service}.Unit` convention
- [ ] `IsPackable = false` set in `.csproj`
- [ ] `MSTest.TestFramework`, `MSTest.TestAdapter`, `Microsoft.NET.Test.Sdk` referenced
- [ ] `FluentAssertions` and one mocking library (`NSubstitute` or `Moq`) referenced
- [ ] `coverlet.collector` referenced
- [ ] `Serilog.Sinks.TestCorrelator` referenced if the service uses Serilog-based assertions
- [ ] `Usings.cs` declares global usings and `[assembly: Parallelize]`
- [ ] `unittest.runsettings` exists with method-level parallelism
- [ ] `Helpers/BaseTestConfiguration.cs` exists with minimal `[AssemblyInitialize]`
- [ ] `TestCategories.cs` exists with at least primary layer categories
- [ ] Every test class has exactly one primary `[TestCategory]`
- [ ] Test method names follow `{Method}_{Context}_{ExpectedOutcome}` and assert behavior outcomes

### Functional project (shared infrastructure)

- [ ] `IsTestProject = true` set in `.csproj`
- [ ] `Microsoft.AspNetCore.Mvc.Testing` referenced
- [ ] `Helpers/SettingsRetriever.cs` reads all required env vars and throws if missing
- [ ] `Helpers/AppSettingsHelper.cs` builds the service `AppSettings` from `SettingsRetriever`
- [ ] `Fixtures/TestConfigSettings.cs` exists as a `Dictionary<string, string?>` for `WebApplicationFactory`
- [ ] `Fakes/FakeAuthHandler.cs` exists to bypass authentication
- [ ] `Fakes/FakeUserService.cs` and `Fakes/FakeSecurityService.cs` exist (or service equivalents)
- [ ] `Factories/{Service}AppFactory.cs` exists extending `WebApplicationFactory<TEntryPoint>`
- [ ] `BaseTestConfiguration.cs` has safe `[AssemblyInitialize]` (logs targets, blocks unsafe environments)
- [ ] `BaseTestConfiguration.cs` has reliable `[AssemblyCleanup]` that restores infrastructure

### Integration test project

- [ ] `IsTestProject = true` set in `.csproj`
- [ ] References `Testing.{Service}.Functional` (not the other way around)
- [ ] `automation.runsettings` exists with `Workers=1`, `ClassLevel` scope
- [ ] `BaseTestConfiguration.cs` exists with idempotent `[AssemblyInitialize]` (cache clear)
- [ ] `Usings.cs` declares global usings
- [ ] `TestCategories.cs` exists with appropriate integration-level categories
- [ ] `[LogResultTestClass]` applied to every test class
- [ ] Every test class uses `[ClassInitialize]` / `[ClassCleanup]` for test data lifecycle and explicit cleanup

### Refactor/Audit flow for existing repos

- [ ] Inventory current tests by tier and move mixed tests into correct projects
- [ ] Consolidate duplicated fakes/helpers into Functional project
- [ ] Replace fixed delays with polling helpers
- [ ] Stabilize flaky tests before adding new coverage
- [ ] Add regression tests for recurring production defects

### Solution-level

- [ ] `Directory.Packages.props` contains versions for all test packages
- [ ] CI pipeline runs unit tests with `--collect "Code coverage"`
- [ ] Integration/functional tests run in a separate environment-aware pipeline
- [ ] `README.md` documents the required environment variables for running integration/functional tests locally

---

## 11. Common Mistakes to Avoid

| Mistake                                                                            | Why it hurts                                                            | Correct approach                                                                                            |
| ---------------------------------------------------------------------------------- | ----------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------- |
| Hard-coding connection strings in test code                                        | Tests break across environments and can hit unsafe targets              | Use `SettingsRetriever` and fail fast when required values are missing                                      |
| Using `Task.Delay(...)` for async completion                                       | Creates flaky and slow tests                                            | Use centralized polling helpers with configurable timeout and diagnostics                                   |
| Running integration tests in parallel against shared schema                        | Data races and nondeterministic failures                                | Keep `Workers=1`, `ClassLevel` unless data isolation is proven                                              |
| Mixing unit, integration, and functional tests in one project                      | CI selection and failure diagnosis become difficult                     | Keep each tier in its own project                                                                           |
| Adding many shallow tests only to raise coverage %                                 | High maintenance with low defect detection value                        | Add focused tests for risky behaviors and real regressions                                                  |
| Storing fake implementations in multiple projects                                  | Behavior drift across suites                                            | Keep fakes in Functional and reference from Integration                                                     |
| Over-commenting test mechanics                                                     | Noise hides business intent                                             | Comment why/intent; keep names and assertions self-explanatory                                              |
| Testing implementation details (exact call counts, private method invocations)     | Refactoring breaks tests even when behavior is correct                  | Assert on observable outputs and side effects, not on how the SUT achieves them                             |
| Putting one test method through multiple unrelated scenarios                       | Hard to identify which scenario failed; test name cannot be descriptive | One test method = one behavior path; use `[DataRow]` for input variations of the _same_ behavior            |
| Skipping `ClassCleanup` or making it conditional on test success                   | Leaves database in a dirty state; the next run inherits stale data      | Write cleanup to be idempotent (`DELETE ... WHERE EXISTS`) so it is safe to run even when setup was partial |
| Using `[TestInitialize]` for heavy setup in integration tests                      | Runs before every method, causing unnecessary DB round-trips            | Use `[ClassInitialize]` for shared setup; reserve `[TestInitialize]` for resetting cheap in-memory state    |
| Using the Functional tier as a substitute for missing unit tests                   | Slow, environment-dependent safety nets that fail in CI                 | Fill gaps in the unit tier with unit tests; use Functional only for pipeline-level wiring                   |
| Not asserting the failure message or error type, only that an exception was thrown | Tests pass for the wrong exception; error messages regress silently     | Assert both the exception type and the key text of the message                                              |

---

## 12. Summary: Key Principles

### The Testing Hierarchy

```
                    ┌─────────────────────────────┐
                    │     FUNCTIONAL TESTS        │  ← Fewest tests
                    │  Full pipeline validation   │     Slowest
                    │  (DI, auth, middleware)     │     Most complex
                    └─────────────────────────────┘
                              ▲
               ┌──────────────────────────────────┐
               │      INTEGRATION TESTS           │  ← Some tests
               │  Infrastructure validation       │     Medium speed
               │  (SQL, cache, serialization)     │     Shared DB
               └──────────────────────────────────┘
                              ▲
        ┌─────────────────────────────────────────────┐
        │              UNIT TESTS                     │  ← Most tests
        │  Business logic validation                  │     Fastest
        │  (pure functions, no I/O)                   │     Fully isolated
        └─────────────────────────────────────────────┘
```

### Golden Rules

1. **Test behavior, not implementation** — Tests should fail when the product is broken, not when you refactor. Assert outcomes and observable side effects, not internal call sequences.
2. **Quality over quantity** — One well-designed test that validates a critical path beats five shallow tests that only raise coverage. Add tests where risk is high; skip where risk is trivial.
3. **Right tier for the risk** — Push tests down to the lowest tier that validates the risk. Unit for logic; integration for SQL/infrastructure; functional for pipeline wiring.
4. **Fail fast on configuration** — Missing environment variables should throw, not default. Silent defaults hide misconfiguration and produce hard-to-diagnose failures.
5. **Isolation by design** — Tests should not depend on execution order or shared state. Each test should be runnable in isolation and produce the same result.
6. **Regression tests for bugs** — Every production bug gets a test that fails before the fix and passes after. This prevents recurrence and documents the defect.

### Quick Reference: Test Tier Selection

| If you're testing... | Use this tier |
|---------------------|---------------|
| Business calculation or transformation | Unit |
| Input validation rules | Unit |
| State machine transitions | Unit |
| SQL query correctness | Integration |
| Database constraint enforcement | Integration |
| Cache serialization | Integration |
| Authentication/authorization flow | Functional |
| DI container wiring | Functional |
| API serialization contracts | Functional |

### Appropriate Level of Testing (Quality Over Quantity)

**Aim for:** Tests that validate behaviors that matter — critical paths, error boundaries, business rules, and production defects.  
**Avoid:** Tests written solely to raise coverage, assert implementation details, or duplicate the same scenario across tiers.

**Decision framework:** Before adding a test, ask: (1) What risk does this mitigate? (2) Would a bug here escape to production without this test? (3) Is this the lowest tier that can validate it? If the answer to (1) or (2) is weak, consider skipping. If (3) suggests a lower tier, move the test down.

---

*Document maintained as part of the platform testing standards. Last conceptual review: 2026.*
