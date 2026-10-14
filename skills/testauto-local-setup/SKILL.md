---
name: testauto-local-setup
description: >
  Local Profisee sandbox setup, secrets management, IaaS deployment, and TestAuto.Web
  configuration for the speed-merchants project. Use when onboarding new developers,
  setting up a local test environment, or troubleshooting environment-specific
  configuration issues (appsettings, connection strings, secrets file).
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Local Sandbox Setup

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: SetupLocalSpeedMerchants.md

---

## Prerequisites

- Profisee 26R1 or newer (local instance)
- Access to the production SpeedMerchants instance (for model/data export)
- Access to one of the IaaS machines: `SMVMTR1`, `SMVMTR2`, or `SMVMTR3`
- 1Password (for the master password)
- PowerShell running as Administrator

---

## Step 1 — Export Model and Data from Production

1. Export the **model** from production SpeedMerchants.
2. Export a **data archive** from production SpeedMerchants.

**Do not** include these entities in the data archive (large metrics tables, not needed for sandbox):

| Excluded Entity |
|---|
| `RecordApiExecution` |
| `HighCostQueryAnalysis` |
| `LookupOnlyMatchingApiExecution` |
| `LubcMatchingApiExecution` |
| `RecordInteractiveApiExecution` |
| `UnifiedMatchingApiExecution` |

---

## Step 2 — Install Profisee Locally

1. Install a local Profisee instance (26R1+). Name both the instance and the local database **`speedmerchants`**.
2. Import the model.
3. Import the data archive.

---

## Step 3 — Deploy TestAuto.Web

**Pre-built install approach** (recommended for non-dev-machine setups):

1. On an IaaS machine, locate `TestAuto.Web.zip` on the shared drive and copy to local machine.
2. Create the deploy directory: `C:\Deploy` <!-- example-path -->
3. Extract the zip to root of Deploy. Result:
   <!-- example-paths -->
   ```
   C:\Deploy\TestAuto.Web
   ```

---

## Step 4 — Configure App Settings

1. From one of the IaaS machines, copy the `appsettings.*` files from `C:\Deploy\TestAuto.Web`. <!-- example-path -->
2. Update settings to match your local environment (database names, URLs, machine name).

Key settings to review:
- `ProfiseeDBConnection` and `MessagingDBConnection` live under `ProfiseeAppSettings`
- `HangfireDB` and monitor DB strings come from secrets, not committed config
- `ExecutionMachine` must match the machine name used when creating workflow executions

---

## Step 5 — Configure Secrets

1. From an IaaS machine, copy the secrets file from `Deploy\Secrets`:
   ```
   <yourmachinename>_local_speedmerchants.json
   ```
2. Edit the secrets file for your environment:

| Setting | What to update |
|---|---|
| Metrics / ScenarioMgr URLs | Your local SpeedMerchants URL and API key |
| Remaining Profisee URLs | Your local running Profisee instance |
| Connection strings | Match your local databases |
| External links | Local or target machine addresses |
| Scripts directory | `C:\Deploy\TestAuto.Web\Scripts` <!-- example-path --> |
| Certificate thumbprint | Self-signed cert (see developer docs) |

---

## Step 6 — Launch TestAuto

> All PowerShell commands must be run as Administrator.

1. Clear any existing secrets:
   ```powershell
   Remove-Item "$env:APPDATA\TestAuto\master.json" -Force
   ```
2. Run the application:
   <!-- example-paths -->
   ```powershell
   C:\Deploy\TestAuto.Web\TestAuto.Web.exe
   ```
3. When prompted, enter the **master password** (stored in 1Password).
4. When prompted for the secrets file location, provide the full path:
   ```
   {SecretsDir}\<yourmachinename>_local_speedmerchants.json
   ```

---

## Architecture Notes

### Database Topology

TestAuto tables (`TestAutoWorkflow`, `TestAutoWorkflowDetail`, `TestAutoScenarios`, etc.) live in the **speedmerchants database** using the Metrics/ScenarioMgt secrets — **not** in Profisee's internal databases.

### Secrets Management

Secrets are stored in the DB-backed `TestAutoSecrets` Profisee entity and loaded at startup by `RegisterAllServices.LoadEntitySecrets` (encoded/decoded via `SecretStorageHelper`). The master password (kept in DPAPI-encrypted `master.json`) decrypts the stored secrets. See the `testauto-secrets-management` skill for the full pattern.

### DI Registration

Registration is **modular, not centralized in one file**. `WebModuleRegistrar` is only the *Web*
module's registrar — each subsystem ships its own `IModuleRegistrar`, and
`TestAuto.DependencyInjection/ServiceExtensions/RegisterAllServices.cs` is the composition root that
pulls them together (discovery in `TestAuto.AutoRegistration/DIServiceRegistration/ModularDIExtensions.cs`).

Registrars present at HEAD 4c367fe6 (re-grep `IModuleRegistrar` — this list grows):
`TestAuto.Web/AutoRegistration/WebModuleRegistrar.cs`,
`TestAuto.Connect/AutoRegistration/ConnectModuleRegistrar.cs`,
`TestAuto.Matching/AutoRegistration/MatchingModuleRegistrar.cs`,
`TestAuto.Metadata/AutoRegistration/MetadataModuleRegistrar.cs`,
`TestAuto.Records/AutoRegistration/RecordsModuleRegistrar.cs`,
`TestAuto.Utilities/AutoRegistration/UtilitiesModuleRegistrar.cs`.

So: put a new service in **its own project's registrar**, not in `WebModuleRegistrar`, unless the
service genuinely belongs to `TestAuto.Web`. Some infrastructure is also registered directly by
`RegisterAllServices` / the `ServiceExtensions` helpers rather than by any registrar. See the
`testauto-modular-di` skill for the full pattern.

Tests must call `services.RegisterAllServices(configuration, includeWebServices: true)` to match
production DI exactly.

### Startup Failures

DB unavailable or `HttpClient` timeout during `LoadEntitySecrets` must be caught and logged. The app continues in degraded state via `IAppStartupStatus` singleton. MainLayout banners surface the error. **Never re-throw startup exceptions.**

---

## Production Reference

Production SpeedMerchants: `https://profiseecloud.dev/speedmerchantstest/`

---

## Sources

- `{VaultDocsRoot}\speed-merchants\setup\SetupLocalSpeedMerchants.md` — *moved into the Work vault; the old `devopslocal\Documentation\speed-merchants\setup\` path no longer exists (verified 2026-07-27)*
- `AGENTS.md` (Learned Workspace Facts section) — *source removed 2026-05-31; content migrated to work-ai skills/memory, this skill is now canonical*
- `TestAuto.Web\Documentation\11_DeveloperGuide.md`
- `TestAuto.Web\Documentation\RunningTheApplication.md`

---

## Developer Quick-Start Prerequisites

These are the minimum tools needed to build and run from source (distinct from the IaaS/sandbox prerequisites above).

| Requirement             | Version | Notes                      |
| ----------------------- | ------- | -------------------------- |
| .NET SDK                | 8.0+    | Verify with `dotnet --version` |
| SQL Server              | 2019+   | Local or remote instance   |
| Visual Studio / VS Code | Latest  | With C# extension          |
| Git                     | 2.x     | For source control         |

### Build & Run Commands

```bash
# Restore packages
dotnet restore

# Build solution
dotnet build

# Run web application
cd TestAuto.Web
dotnet run

# Navigate to https://localhost:8443
# (or https://localhost:7019 for dev with launchSettings)
```

### Launch Flags (Published Executable)

When running the published `TestAuto.Web.exe` directly:

| Flag | Description | Example |
|---|---|---|
| `--urls` | Binding address | `--urls "https://corpltr94.corp.profisee.com:7019"` |
| `--skip-cache` | Disable reference data cache loading on startup | `--skip-cache` |
| `--no-cache` | Alternative flag for the same cache disable | `--no-cache` |
| `--environment` | Override ASPNETCORE_ENVIRONMENT | `--environment Production` |

**Example (production-style launch):**
```bash
.\TestAuto.Web.exe --urls "https://corpltr94.corp.profisee.com:7019" --skip-cache
```

### Reference Data Cache

The reference data cache pre-loads dropdown data (Server Profiles, Environment Types, etc.) on startup.

One gate decides it (`TestAuto.Web\ServiceExtensions\PipelineExtensions.cs:105`):

```csharp
var preloadCache = app.Configuration.GetValue<bool>("FeatureFlags:PreloadReferenceDataCache", true) && !skipCache;
```

`skipCache` is parsed in `TestAuto.Web\Program.cs:77`
(`args.Contains("--skip-cache") || args.Contains("--no-cache")`) and passed through
`app.ConfigurePipeline(webUIConfig, httpsPort, skipCache)` at `Program.cs:344`.

| Setting | Location | Effect |
|---|---|---|
| `--skip-cache` / `--no-cache` | Command-line flag | Disables cache for that run. **Most reliable option.** |
| `FeatureFlags:PreloadReferenceDataCache: false` | `TestAuto.Web\appsettings.json` (the `FeatureFlags` block starts at `:171`; shipped value is `true`) | Disables cache permanently |

> [!warning] Two traps in this area — both verified 2026-07-27
> **1. `appsettings.Production.json` does NOT disable the cache.** That file
> (`TestAuto.Web\appsettings.Production.json`) contains only `WebUI`, `WebApi`, `Kestrel`, and
> `Logging` — it has no `FeatureFlags` section at all. Setting `ASPNETCORE_ENVIRONMENT=Production`
> leaves preloading **on** (the `GetValue` default is `true`).
>
> **2. `appsettings.CommandLine.json`'s override is a no-op.** It sets
> `"Features": { "PreloadReferenceDataCache": false }` — section **`Features`**, but the runtime
> reads **`FeatureFlags:`**. The key never binds. The repo's own docs flag this
> (`TestAuto.Web\Documentation\RunningTheApplication.md:115`,
> `TestAuto.Web\Documentation\CompleteReference.md:6139`). Note also that this file only loads at
> all if `ASPNETCORE_ENVIRONMENT=CommandLine` — nothing calls `AddJsonFile` for it explicitly.
>
> If you need the cache off, use `--skip-cache` or fix `FeatureFlags` in `appsettings.json`.

**Performance impact**: Cache loading adds ~2–5 seconds startup time (makes 3 REST API calls).

**When to disable**: CLI/batch/API-only usage, production deployments, automated tests, any context where the Scenario Editor UI is not needed.

**When to keep enabled**: Running the full web UI — dropdowns will be empty until first access if cache is disabled.

### Run Tests

```bash
# Run all tests
dotnet test

# Run unit tests only
dotnet test Testing.SpeedMerchants.Unit

# Run integration tests only
dotnet test Testing.SpeedMerchants.Integration

# Run with verbose output
dotnet test --verbosity detailed

# Run with code coverage
dotnet test --collect:"XPlat Code Coverage"
```

---

## Module Map

### Navigation Diagram

```
                Start Here
                    │
                    ▼
          ┌─────────────────────┐
          │   TestAuto.Web      │  Web UI entry point
          │   Program.cs        │
          └──────────┬──────────┘
                     │
                     ▼
          ┌─────────────────────┐
          │ RegisterAllServices │  Central DI registration
          └──────────┬──────────┘
                     │
     ┌───────────────┼───────────────┐
     │               │               │
     ▼               ▼               ▼
┌───────────┐   ┌───────────┐   ┌───────────┐
│ Scenarios │   │  Matching │   │  Shared   │
│   Core    │   │ Scenarios │   │ Utilities │
└───────────┘   └───────────┘   └───────────┘
```

### Key Files by Purpose

| Purpose             | Key File(s)                                                                     |
| ------------------- | ------------------------------------------------------------------------------- |
| Application entry   | `TestAuto.Web/Program.cs`                                                       |
| DI registration     | `TestAuto.DependencyInjection/ServiceExtensions/RegisterAllServices.cs`         |
| Matching scenarios  | `TestAuto.Matching/Scenarios/UnifiedMatchingScenario.cs`                        |
| Batch orchestration | `TestAuto.Scenarios/BatchProcessing/ScenarioEnqueueService.cs`                  |
| Server management   | `TestAuto.Scenarios/BatchProcessing/DynamicServerManager.cs`                    |
| REST client         | `TestAuto.Shared.Http/Rest/RestClient.cs`                                       |
| Configuration       | `TestAuto.Shared/Scenarios/Configuration/`                                      |
| Constants           | `TestAuto.Matching/Common/MatchingConstants.cs`                                 |
| Secret management   | `TestAuto.Shared.Security/Services/SecretEncryptionService.cs`                  |

---

## Adding a New Feature: Decision Checklist

### Which Projects to Modify

| Feature Type | Projects to Modify                      |
| ------------ | --------------------------------------- |
| New scenario | `TestAuto.{Area}`, `TestAuto.Scenarios` |
| New metric   | `TestAuto.Metrics`, `TestAuto.{Area}`   |
| New UI page  | `TestAuto.Web`                          |
| New service  | Target project + its module registrar   |

### New Service Pattern

1. Create interface in `Interfaces/`:

```csharp
public interface IMyService
{
    Task<Result> DoSomethingAsync(Input input);
}
```

2. Create implementation in `Services/` (inject `Serilog.ILogger`, not `ILogger<T>`):

```csharp
public class MyService : IMyService
{
    private readonly Serilog.ILogger _logger;

    public MyService(Serilog.ILogger logger)
    {
        _logger = logger;
    }

    public async Task<Result> DoSomethingAsync(Input input)
    {
        _logger.Information("Processing {Input}", input);
        // Implementation
    }
}
```

3. Register in the module registrar (`*ModuleRegistrar.cs`):

```csharp
public void RegisterServices(IServiceCollection services, IConfiguration configuration)
{
    services.AddTransient<IMyService, MyService>();
}
```

### New Scenario Pattern

1. Inherit from the appropriate base class:

```csharp
public class MyScenario : ScenarioBaseMatching
{
    public override async Task<MetricBatchSummary> ProcessBatchAsync(...)
    {
        // Implementation
    }
}
```

2. Create a sample JSON configuration in `Samples/TestCases/`.
3. Add tests in the corresponding test project.

### New Test Pattern

```csharp
[TestClass]
public class MyServiceTests
{
    [TestMethod]
    public async Task DoSomethingAsync_WithValidInput_ReturnsExpectedResult()
    {
        // Arrange
        var service = new MyService(Mock.Of<Serilog.ILogger>());

        // Act
        var result = await service.DoSomethingAsync(testInput);

        // Assert
        Assert.IsTrue(result.IsSuccess);
    }
}
```

### Step Order Summary

1. Create feature branch from `develop`
2. Identify affected projects using the table above
3. Implement interface + service + registration
4. Add tests in the corresponding test project
5. Add XML documentation and sample configuration
6. Open PR targeting `develop`

---

## Troubleshooting (Developer Guide)

### Common Issues

| Issue                   | Cause              | Solution                     |
| ----------------------- | ------------------ | ---------------------------- |
| Build fails             | Missing packages   | `dotnet restore`             |
| Connection refused      | DB not running     | Start SQL Server             |
| 401 Unauthorized        | Invalid API key    | Check secrets configuration  |
| Test timeout            | Slow environment   | Increase timeout value       |
| Hangfire not processing | Server not started | Check startup logs           |

### Debugging Tips

1. **Check Serilog logs** — output to `logs/` folder by default
2. **Hangfire dashboard** — navigate to `/hangfire` for job status
3. **Enable debug logging** — set `MinimumLevel` to `Debug` in appsettings
4. **Verify connection strings** — confirm DB connectivity before blaming code

---

## Glossary

| Term                 | Definition                                                  |
| -------------------- | ----------------------------------------------------------- |
| **Scenario**         | A test configuration that executes against Profisee         |
| **Batch**            | A group of records processed together                       |
| **CM**               | Continuous Matching — real-time matching mode               |
| **Golden Record**    | The master record produced from a match group               |
| **LUBC**             | Lookup-Before-Create pattern                                |
| **Record Mix**       | Distribution of New / Update / No-Change records in a batch |
| **ModelSource**      | Database containing source test data                        |
| **Metrics**          | Performance measurements collected during test runs         |
| **Hangfire**         | Background job processing framework used for orchestration  |
| **Module Registrar** | Pattern for scoped DI service registration per project      |
