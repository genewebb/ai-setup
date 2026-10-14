---
name: testauto-execution-context
description: >
  Execution context objects in TestAuto.Shared for carrying configuration, services,
  and state through the scenario pipeline. Use when injecting or constructing IContext,
  CdpContext, ConcurrencyContext, SecurityContext, ScenarioExecutionContext, or
  TransformationContext; understanding what each context carries; or deciding which
  context type fits a scenario execution scope.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Execution Context Objects

> **Scope**: speed-merchants (TestAuto.Shared)
> **Source**: `TestAuto.Shared/Common/`

TestAuto uses a family of context objects to pass configuration, infrastructure services, and execution state through the scenario pipeline. These are not general service locators — each context type is scoped to a specific concern.

---

## Context Summary

| Class | Namespace | Purpose | Key Properties |
|---|---|---|---|
| `Context` (implements `Profisee.Platform.Utilities.Cdp.Interface.IContext`) | `TestAuto.Shared.Common` | Profisee CDP context for TestAuto.Web | ConnectionString, ModelName, MetadataCacheProvider, RulesEvaluator, DistributedCache, RecordLimit, AttributeLimit |
| `CdpContext` (implements `Profisee.Platform.Utilities.Cdp.Interface.IContext`) | `TestAuto.Shared.Common` | Direct Profisee CDP context with messaging enabled | ConnectionString (ServiceDBConnection), MessagingEndpointInstance, HistoryRetentionDays |
| `ConcurrencyContext` | `TestAuto.Shared.Common` | Thread-level concurrency tracking | ThreadIndex, TotalThreads |
| `SecurityContext` | `TestAuto.Shared.Common` | User identity and token for a scenario run | UserName, Role, Token |
| `ScenarioExecutionContext` | `TestAuto.Shared.Common.Scenario` | Run-level correlation and timing | CorrelationId (Guid), RunStartTime, RunEndTime |
| `TransformationContext` | `TestAuto.Shared.Common.Data` | Configuration for the record transformation pipeline | Seed, UseMutationHelper, MutationStrategy, MutationSettings |

---

## `Context` / `IContext` (Profisee CDP for TestAuto.Web)

> **`IContext` here is always `Profisee.Platform.Utilities.Cdp.Interface.IContext`** — a
> Profisee platform interface, not a TestAuto one. `Context.cs` imports it via
> `using Profisee.Platform.Utilities.Cdp.Interface;` (`Context.cs:4`) and declares
> `public class Context : IContext` (`Context.cs:11`); `CdpContext` spells it out fully at
> `CdpContext.cs:12`. Both classes implement the **same** interface — there is no separate
> "TestAuto `IContext`" and no `Profisee.IContext`.

Injected via DI in `TestAuto.Web`. Wraps `IConfiguration` to expose Profisee settings.

```csharp
public string ConnectionString =>
    _configuration["ProfiseeAppSettings:ProfiseeDbConnection"] ?? string.Empty;

public string ModelName =>
    _configuration["ProfiseeAppSettings:SchemaName"] ?? "data";

public bool DoWriteSqlToLog =>
    new[] { "Debug", "Information", "Warning" }.Contains(
        _configuration["ProfiseeAppSettings:LogEventLevel"]);
```

- `MessagingEndpointInstance` is **always null** in TestAuto — messaging is forcibly disabled.
- `RecordLimit` and `AttributeLimit` default to `-1` (unlimited).
- `VersionId` is always `1`.

---

## `CdpContext` (Profisee CDP — defined but not wired up)

A direct Profisee CDP context (implementing the same `Profisee.Platform.Utilities.Cdp.Interface.IContext`) intended for background services that interact with the CDP outside the web layer (messaging enabled). **It is NOT registered in DI and has no live consumers** — a repo-wide grep for `CdpContext` returns exactly two hits: the class declaration (`CdpContext.cs:12`) and its constructor `CdpContext(AppSettingsBase settings, IMessageSession messageSession)` (`CdpContext.cs:34`). Treat it as defined-but-inactive; nothing currently constructs or injects it.

Property-level facts (accurate, from the class):
- Uses `AppSettingsBase.ServiceDBConnection` (not `ProfiseeAppSettings:ProfiseeDbConnection`)
- `EndPointEnabled = "1"` (messaging enabled)
- `DoWriteSqlToLog = true` always

---

## `ConcurrencyContext`

Passed to multi-threaded scenarios to identify the current worker:

```csharp
var context = new ConcurrencyContext { ThreadIndex = 3, TotalThreads = 20 };
```

- `ThreadIndex` is 0-based
- Used by scenarios to partition record sets across threads

---

## `SecurityContext`

Carries the authenticated user's identity token through the scenario execution chain. Not injected by DI — constructed from the current user session before dispatch.

```csharp
var sec = new SecurityContext
{
    UserName = "gene.webb@profisee.com",
    Role = "Admin",
    Token = bearerToken
};
```

---

## `ScenarioExecutionContext`

Created once per test run at dispatch time. `CorrelationId` is a new `Guid` generated in the constructor and is immutable.

```csharp
var ctx = new ScenarioExecutionContext();
// ctx.CorrelationId — auto-generated Guid
// ctx.RunStartTime  — DateTime.UtcNow at construction
ctx.RunEndTime = DateTime.UtcNow; // set on completion
```

---

## `TransformationContext`

Passed to the `IRecordTransformer` pipeline (see `testauto-record-transformation` skill). Controls mutation strategy and reproducibility.

```csharp
var ctx = new TransformationContext
{
    Seed = 42,
    UseMutationHelper = true,
    MutationStrategy = MutationStrategy.SlightTypo,
    MutationSettings = dataMutationSettingsFromConfig
};
```

`MutationStrategy` values: `SlightTypo`, `SwapCharacters`, `MutateAddress`, `MutateCity`, `CaseToggle`, `MutateState`, `MutateCountry`, `MutatePostal`, `MutateEmail`, `MutatePhone`, `MutateDOB`, `MutateSSN`.

---

## Sources

- `TestAuto.Shared\Common\Context.cs`
- `TestAuto.Shared\Common\CdpContext.cs`
- `TestAuto.Shared\Common\ConcurrencyContext.cs`
- `TestAuto.Shared\Common\SecurityContext.cs`
- `TestAuto.Shared\Common\Scenario\ScenarioExecutionContext.cs`
- `TestAuto.Shared\Common\Data\TransformationContext.cs`
