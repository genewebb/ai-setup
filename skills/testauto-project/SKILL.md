---
name: testauto-project
description: >
  TestAuto.Web project structure and critical rules. Use when navigating TestAuto
  project layout, understanding where files go in TestAuto, checking folder
  structure, or when tempted to cache ScenarioConfiguration — that is forbidden.
---

# TestAuto.Web Project Structure

> **UI terminology (2026-07)**: the web UI now labels workflows as **"Workloads"** (nav menu, page titles, help text). ALL code identifiers, routes, entities, and config keys remain `Workflow*` / `WorkloadExecution*` — "the Workloads page" = `Workflows.razor`, "Workload Builder" = `WorkflowBuilder.razor`, "Workload Execution" = `WorkflowExecution.razor`.

This rule defines the structure for the TestAuto.Web Blazor application.

## Project Overview

**TestAuto.Web** is a Blazor Web App (Interactive Server render mode, migrated 2026-07 from legacy Blazor Server) that provides:
- Web UI for test scenario management
- REST API controllers for automation
- Hangfire job scheduling
- Real-time execution monitoring

Hosting files: `Components/App.razor` is the root HTML document (loads `blazor.web.js`), `Components/Routes.razor` holds the `<Router>`, and the pipeline maps `MapRazorComponents<App>().AddInteractiveServerRenderMode()`. There is **no** `TestAuto.Web/Pages/` folder (the old `_Host.cshtml` + Razor Pages were deleted in the migration).

## Directory Structure

```
TestAuto.Web/
├── AutoRegistration/           # DI registration
│   └── WebModuleRegistrar.cs
├── BusinessLogic/              # Business layer (CRUD operations)
│   ├── Constants/              # Entity/field name constants
│   │   ├── EntityNames.cs
│   │   └── FieldNames.cs
│   ├── Helpers/                # Business logic helpers
│   │   ├── FilterBuilder.cs
│   │   ├── QueryParameterBuilder.cs
│   │   └── RecordMapper.cs
│   └── Services/               # Business services
│       ├── IScenarioService.cs
│       ├── ScenarioService.cs
│       ├── IWorkflowService.cs
│       └── WorkflowService.cs
├── Components/                 # Blazor components
│   ├── Common/                 # Shared/reusable components + list state
│   │                           #   (CustomParmsEditorHost, BulkCustomParmsEditorBase,
│   │                           #    BulkApplyPreflightPanel, FileUpload, LoadingSpinner,
│   │                           #    ProgressBar, StatusIndicator, ScenarioListState,
│   │                           #    ScenarioReorder, ScenarioDetailItem, IScenarioListItem)
│   ├── Controls/               # Custom controls (editors, dialogs, list surface)
│   ├── Dashboard/              # Dashboard components
│   ├── Dialogs/                # Modal dialogs
│   ├── Help/                   # In-app help/documentation components
│   ├── Layout/                 # Layout components
│   ├── Pages/                  # Routable Blazor pages — ALSO holds ScenarioEditorContent
│   │                           #   (.razor + .razor.cs), which is a shared editor body,
│   │                           #   not a routable page. It is NOT under Common/.
│   └── *.razor / *.razor.cs    # Component files
├── Configuration/              # App configuration
├── Controllers/                # REST API controllers
├── Documentation/              # Project documentation
├── Helpers/                    # UI helpers
│   ├── NotificationExtensions.cs
│   └── RecordExtensions.cs
├── Interfaces/                 # Project interfaces
├── Jobs/                       # Hangfire jobs owned by the Web project only —
│                               #   ConfigurationMigrationJob, WorkflowMonitorJob.
│                               #   Most jobs live in OTHER projects (see below).
├── Models/                     # View models, DTOs
├── Repositories/               # Data access
│   └── WebUiRepository.cs
├── Services/                   # Application services
├── Swagger/                    # API documentation
├── wwwroot/                    # Static assets
│   ├── css/
│   ├── js/
│   └── help/
├── Program.cs                  # Application entry point
└── appsettings.*.json          # Configuration files
```

## Key Patterns

### Blazor Components

Components use **partial class pattern** - logic in separate `.razor.cs` file:

```
Components/
├── MyComponent.razor           # Markup only
└── MyComponent.razor.cs        # Code-behind (partial class)
```

**Rules:**
- **Default to code-behind**: state, lifecycle methods, event handlers, and service calls belong in
  the `.razor.cs` partial class.
- **Small inline `@code` blocks are allowed and are in active use** — this is a strong default, not
  an absolute ban. At HEAD 4c367fe6, 11 of the 129 `.razor` files under `TestAuto.Web/Components`
  carry an `@code` block (re-run `grep -rl "@code" --include=*.razor TestAuto.Web/Components` — the
  count moves). Legitimate cases:
  - **`RenderFragment` helpers**, which need Razor template syntax and cannot live in a `.cs` file.
    `Components/Pages/ScenarioCompare.razor:113` is the canonical example:
    `private RenderFragment RenderSide(CompareSide side) => @<div class="col-md-6">…`
  - **Tiny leaf controls** whose entire logic is a couple of `[Parameter]` declarations and a
    one-line handler — e.g. `Components/Controls/ContentSourceToggle.razor`,
    `PagingControl.razor`, `TimeRangeCompact.razor`, `SecretValueEditor.razor`, and the
    `*StepEditorCard.razor` family (`SqlStepEditorCard`, `PowerShellStepEditorCard`,
    `CommandLineStepEditorCard`, `ConnExStepEditorCard`).

  If a block grows past a screenful, or starts injecting services and managing lifecycle, move it
  to a `.razor.cs`. Do not flag an existing small `@code` block as a violation in review.
- Use `[Inject]` for dependency injection
- Components use Radzen Blazor library

### BusinessLogic Layer

All CRUD operations go through `BusinessLogic/Services/`:

```csharp
// ✅ GOOD - Use service
var result = await ScenarioService.GetAllScenariosAsync();

// ❌ BAD - Direct IRestClient in page
var response = await _restClient.GetRecordsAsync(...);
```

### Constants Usage

Never hard-code entity/field names:

```csharp
// ✅ GOOD
await _restClient.GetRecordsAsync(EntityNames.TestAutoScenario, null);
var code = record[FieldNames.Code]?.ToString();

// ❌ BAD
await _restClient.GetRecordsAsync("TestAutoScenario", null);
var code = record["Code"]?.ToString();
```

### Controllers

Controllers are thin - delegate to services:

```csharp
[ApiController]
[Route("api/[controller]")]
public class ScenarioController : ControllerBase
{
    private readonly IScenarioService _scenarioService;
    
    [HttpGet]
    public async Task<IActionResult> GetAll()
    {
        var result = await _scenarioService.GetAllScenariosAsync();
        return result.IsSuccess ? Ok(result.Data) : BadRequest(result.ErrorMessage);
    }
}
```

### Service Registration

Register services in `WebModuleRegistrar.cs`, not `Program.cs`:

```csharp
// In WebModuleRegistrar.cs
public void RegisterServices(IServiceCollection services, IConfiguration configuration)
{
    // Business Logic Services
    services.AddScoped<IScenarioService, ScenarioService>();
    services.AddScoped<IWorkflowService, WorkflowService>();
}
```

## UI Components (Radzen)

Use **Radzen Blazor** components with **Material icons**:

```razor
<RadzenButton Icon="add_circle" Text="Add" Click="@OnAdd" />
<RadzenDataGrid Data="@items" TItem="MyModel">
    ...
</RadzenDataGrid>
```

## File Naming

| Type | Pattern | Example |
|------|---------|---------|
| Blazor component | `{Name}.razor` + `{Name}.razor.cs` | `ScenarioList.razor` |
| Controller | `{Resource}Controller.cs` | `ScenarioController.cs` |
| Service interface | `I{Name}Service.cs` | `IScenarioService.cs` |
| Service impl | `{Name}Service.cs` | `ScenarioService.cs` |
| Dialog component | `{Action}{Resource}Dialog.razor` | `SaveTemplateDialog.razor` |
| View model | `{Name}Model.cs` or `{Name}ViewModel.cs` | `ScenarioViewModel.cs` |

## Dependencies

TestAuto.Web's direct project references:
- `TestAuto.Shared` (+ `TestAuto.Shared.Security`, `TestAuto.Shared.Http`) - Common interfaces, models, security, HTTP
- `TestAuto.DependencyInjection` - Central DI registration
- `TestAuto.Commands` - Command execution wrappers
- `TestAuto.Matching` - Matching scenarios
- `TestAuto.Metrics` - Metrics collection
- (`TestAuto.Scenarios` is only a transitive dependency, not a direct reference)

Key packages:
- `Radzen.Blazor` - UI components
- `Hangfire` - Background jobs

---

# No Scenario Config Cache Rule

## Rule: Do NOT Cache or Persist ScenarioConfiguration for Hangfire Jobs

**CRITICAL RULE**: Never store `ScenarioConfiguration` in cache (IDistributedCache, IMemoryCache, Redis, etc.) and pass a reference/key to Hangfire jobs instead of the full config. Do not implement "config by reference" patterns for scenario execution.

### Why This Rule Exists

- **Problem assumptions**: The "VALUE IS TOO BIG" or Hangfire argument display is often misdiagnosed as a size limit issue. The actual problem is typically elsewhere (parsing, deserialization, configuration structure).
- **Complexity**: Cache-based config passing adds failure modes (expiry, cache miss, distributed cache sync) without addressing the real root cause.
- **Maintainability**: Passing the full ScenarioConfiguration as job arguments is the intended design. Fix the actual issue, not the symptom.

### What is Forbidden

- ❌ Storing `ScenarioConfiguration` in IDistributedCache, IMemoryCache, Redis, or similar
- ❌ Passing a cache key or reference to `ProcessBatchJob` or `ScenarioDispatcher.Dispatch` instead of the config
- ❌ Creating `IScenarioConfigCacheService` or equivalent "config by reference" abstractions
- ❌ Modifying `BatchJobOrchestrator` or `ScenarioDispatcher` to load config from cache at runtime

### Correct Approach

- ✅ Pass `ScenarioConfiguration` directly as job arguments
- ✅ Use Serilog logging to trace the flow from Web UI submit through job processing in Seq
- ✅ Investigate parsing, deserialization, or configuration structure if jobs fail

### Enforcement

- Code reviews must reject any PR that introduces cache persistence for scenario configuration
- Search for `IScenarioConfigCacheService`, `ScenarioConfigCache`, or similar patterns

---

## Solution Architecture Overview

### Project Inventory

All application projects in `speed-merchants.sln` with their single-line purpose:

| Project | Purpose |
|---|---|
| `TestAuto` | Console CLI entry point — command-line scenario execution |
| `TestAuto.AutoRegistration` | DI auto-registration framework and `IModuleRegistrar` interfaces |
| `TestAuto.Commands` | Command execution wrappers (REST client commands, test run commands) |
| `TestAuto.Connect` | Connect API scenarios, builders, and connection management |
| `TestAuto.DependencyInjection` | Central DI registration hub — wires all modules and loads secrets at startup |
| `TestAuto.External` | Third-party integrations: Azure, Grafana, Prometheus |
| `TestAuto.Matching` | Matching scenario implementations, record pool, and matching metrics |
| `TestAuto.Metadata` | Metadata scenarios and sample configurations |
| `TestAuto.Metrics` | Metrics collection infrastructure — builders, factories, Hangfire jobs, storage |
| `TestAuto.Records` | Record CRUD performance scenarios and test data generators |
| `TestAuto.Scenarios` | Core scenario infrastructure: batch processing, execution engine, server management, validation |
| `TestAuto.Shared` | Common utilities, DTOs, REST client infrastructure, interfaces (~268 C# files) |
| `TestAuto.Shared.Caching` | Cached reference data (split from Shared) |
| `TestAuto.Shared.Http` | HTTP client factory extensions and utilities (split from Shared) |
| `TestAuto.Shared.Security` | AES-256 secret encryption, DPAPI, master password management (split from Shared) |
| `TestAuto.Utilities` | Utility scenarios: SQL executors, PowerShell runners, ConnEx executors |
| `TestAuto.Web` | Blazor Web App (Interactive Server) Web UI — scenario management, API controllers, Hangfire dashboard |
| `TestData.Generation` | Standalone bulk SQL test-data generator — engine, CLI and Blazor host; deterministic generation on chunked code ranges, plus a Profisee deploy package. See [[testdata-generation-and-mutation-engine]] |
| `TestData.Mutation` | Standalone bulk mutation tool — engine, CLI and Blazor host; shares the `dbo.tGenerationChunk`/`tGenerationPhase` checkpoint tables with TestData.Generation, kept apart by a `MUT:` run-name prefix. See [[testdata-generation-and-mutation-engine]] |
| `TestData.CloneAndMutate` | Test data mutation — clones and mutates existing records for test variation |
| `TestData.Enrichment` | Test data enrichment pipeline |
| `TestData.Enrichment.Core` | Core enrichment library shared by enrichment projects |
| `TestData.Shared` | Shared utilities across test data projects |

Test projects (not application logic):

| Project | Framework | Purpose |
|---|---|---|
| `Testing.SpeedMerchants.Unit` | MSTest + bUnit + Moq + FluentAssertions | Unit tests for matching, REST, Blazor components, controllers |
| `Testing.SpeedMerchants.Integration` | MSTest + Moq + FluentAssertions | Integration tests for E2E matching, REST gateway, cache, security |
| `Testing.SpeedMerchants.TestHelpers` | MSTest (library only) | Shared test helper library — not directly executable |

---

### Runtime Entry Points

| Runtime | Type | Entry Point | Purpose |
|---|---|---|---|
| **TestAuto.Web** | ASP.NET Core Blazor Web App (Interactive Server) | `TestAuto.Web/Program.cs` → `WebApplication.CreateBuilder` | Primary Web UI for scenario execution, monitoring, and the Hangfire dashboard (`/hangfire`) |
| **TestAuto Console** | .NET Console | `TestAuto/Program.cs` | CLI-based scenario execution — runs scenarios headlessly from command line |
| **Hangfire Workers** | Background job processor | Hosted in-process by `TestAuto.Web`; job *classes* are spread across several projects (table below) | Distributed background execution — enqueued by Web/CLI, processed by Hangfire workers |

Hangfire is hosted in-process with `TestAuto.Web` — there is no separate Hangfire worker process. The Web app acts as both the dashboard host and the job processor.

**Where the job classes actually live.** They are *not* all under `TestAuto.Web/Jobs/`, and not all
under `TestAuto.DependencyInjection/Jobs/`. Four different projects own jobs (HEAD 4c367fe6 — re-run
`find . -name "*Job.cs"` before relying on this list):

| Project / folder | Jobs |
|---|---|
| `TestAuto.Scenarios/Jobs/` | `DynamicServerCleanupJob`, `ResourceCollectionJob`, `ResourceMetricsUpdateJob`, `WorkloadExecutionUpdateJob` |
| `TestAuto.Web/Jobs/` | `ConfigurationMigrationJob`, `WorkflowMonitorJob` |
| `TestAuto.DependencyInjection/Jobs/` | `CollectionUpdateJob` |
| `TestAuto.Metrics/HangfireJobs/` | `MetricsPersistenceJob` (note the folder is `HangfireJobs`, not `Jobs`) |

Rule of thumb: a job goes in the project that owns the domain it operates on. Only put it in
`TestAuto.Web/Jobs/` if it is genuinely Web-specific.

---

### C4 Context Summary

**Users**

| Actor | Role | Primary Activities |
|---|---|---|
| Performance Engineer | Test execution | Configure scenarios, run tests, analyze results |
| Developer | Scenario development | Create/modify scenarios, debug issues |
| Operations | Monitoring | Monitor job execution via Hangfire dashboard, handle failures |

**External Systems**

| System | Protocol | Purpose |
|---|---|---|
| Profisee MDM | REST API (HTTPS) | Target system under test — all matching, lookup, and record operations run against Profisee |
| ModelSource Database | SQL Server | Test data source — 120M records across source systems, accessed via keyset pagination |
| Metrics Store (TestAutoMetrics DB) | SQL Server / REST | Stores timing and performance metrics written during test execution |
| Hangfire Database | SQL Server | Job queue and state persistence for background execution |

---

### Container Summary

```
┌──────────────────────── TestAuto System ────────────────────────────┐
│                                                                     │
│   TestAuto.Web (Blazor Web App)                                     │
│   ├── Blazor pages — scenario management UI                         │
│   ├── REST API controllers — automation endpoints                   │
│   ├── Hangfire dashboard — /hangfire                                │
│   └── In-process Hangfire workers — processes background jobs       │
│                                                                     │
│   TestAuto Console (.NET Console CLI)                               │
│   └── Headless scenario execution — calls same DI + services        │
│                                                                     │
│   Hangfire DB (SQL Server)                                          │
│   └── Job queue, job state, recurring job schedules                 │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
         │ REST (HTTPS)        │ SQL              │ SQL / REST
         ▼                     ▼                  ▼
   Profisee MDM          ModelSource DB     Metrics Store (TestAutoMetrics)
```

Both Web and CLI share the same DI registration (`TestAuto.DependencyInjection`) and scenario execution pipeline (`TestAuto.Scenarios`). They differ only in presentation layer (Blazor UI vs. console args).

---

### Key Namespace Map

| Namespace | Concern |
|---|---|
| `TestAuto.Matching.Scenarios` | Matching scenario implementations (`UnifiedMatchingScenario`, etc.) |
| `TestAuto.Scenarios.BatchProcessing` | Hangfire batch orchestration — `ScenarioEnqueueService`, `ScenarioDispatcher`, `BatchJobOrchestrator`, `DynamicServerManager` |
| `TestAuto.Scenarios.Management` | Workload/job/load management (`WorkloadManager`, `JobManager`, `LoadManager`) |
| `TestAuto.Scenarios.Services` | Core scenario services (configuration, validation, execution helpers) |
| `TestAuto.Shared.Rest` | REST client infrastructure — `RestUrlDefinition` (`IRestClient` itself lives in `TestAuto.Shared.Interfaces`) |
| `TestAuto.Shared.Security` | AES-256 encryption, DPAPI, `ISecretEncryptionService`, `IMasterPasswordManager` |
| `TestAuto.Shared.Scenarios.Configuration.Scenario` | `ScenarioConfiguration` model and related DTOs — the central config contract |
| `TestAuto.Metrics` | Metrics collection and persistence — builders, factories, storage |
| `TestAuto.Web.BusinessLogic` | Web business logic services (`IScenarioService`, `IWorkflowService`) |
| `TestAuto.Web.Controllers` | Thin REST API controllers — delegate to `BusinessLogic` services |
| `TestAuto.DependencyInjection` | Central DI registration hub, secrets bootstrap |
| `TestAuto.AutoRegistration` | `IModuleRegistrar` contract used by every project to self-register its services |

---

## Sources

- `TestAuto.Web/Documentation/00_SolutionInventory.md`
- `TestAuto.Web/Documentation/01_ArchitectureOverview.md`
