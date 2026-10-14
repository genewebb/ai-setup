---
name: testauto-modular-di
description: >
  IModuleRegistrar plugin architecture for TestAuto. Use when creating a new subsystem that
  needs DI registration, adding services to an existing module registrar, understanding why
  services are not resolving at startup, or tracing which assembly is responsible for a
  given service registration.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Modular DI Registration

> **Scope**: speed-merchants (TestAuto.AutoRegistration + all subsystem projects)
> **Source**: `TestAuto.AutoRegistration\Interfaces\IModuleRegistrar.cs`, `ModularDIExtensions.cs`

TestAuto uses a plugin-like DI architecture. Every subsystem ships its own `*ModuleRegistrar` class. A single extension method discovers and runs all of them at startup via reflection — `Program.cs` and `WebApplication` never need to reference individual subsystem namespaces.

---

## How It Works

### 1. Interface

```csharp
// TestAuto.AutoRegistration/Interfaces/IModuleRegistrar.cs
public interface IModuleRegistrar
{
    void RegisterServices(IServiceCollection services, IConfiguration configuration);
}
```

### 2. Auto-Discovery (`RegisterAllModuleServices`)

Called once at startup (typically in `Program.cs` or a host builder):

```csharp
services.RegisterAllModuleServices(configuration);
```

Implementation — scans every non-dynamic assembly already loaded in `AppDomain.CurrentDomain`:

```csharp
public static IServiceCollection RegisterAllModuleServices(
    this IServiceCollection services,
    IConfiguration configuration)
{
    var assemblies = AppDomain.CurrentDomain.GetAssemblies()
        .Where(a => !a.IsDynamic)
        .ToList();

    var registrarTypes = assemblies
        .SelectMany(a =>
        {
            try { return a.GetTypes(); }
            catch (ReflectionTypeLoadException ex) { return ex.Types.Where(t => t != null); }
        })
        .Where(t =>
            typeof(IModuleRegistrar).IsAssignableFrom(t) &&
            t.IsClass &&
            !t.IsAbstract);

    foreach (var registrarType in registrarTypes)
    {
        if (Activator.CreateInstance(registrarType) is IModuleRegistrar registrar)
        {
            Log.Logger.InformationWithTagAndConsole(LogTagConstants.Startup,
                "Registered module: {RegistrarType}", registrarType.FullName);
            registrar.RegisterServices(services, configuration);
        }
    }

    return services;
}
```

**Key constraint**: A registrar must be loaded into `AppDomain` before `RegisterAllModuleServices` runs. Plugin assemblies in the `Plugins/` directory are loaded by MSBuild post-build (`CopyToHosts` target). If a plugin is missing from `Plugins/`, its registrar silently does not fire.

---

## Known Module Registrars

| Registrar | Assembly | What It Registers |
|---|---|---|
| `WebModuleRegistrar` | `TestAuto.Web` | Repositories, facades, scenario execution services, workflow orchestration, Hangfire adapters, batch processing |
| `RecordsModuleRegistrar` | `TestAuto.Records` | Domain attribute cache, transformers (FakerTransformer, MutationTransformer), faker helpers |
| `MatchingModuleRegistrar` | `TestAuto.Matching` | Only `MonitorActivityCollector` (concrete type, `AddTransient`, factory-built from `MonitorDataFacade` + `ILogger`) — `MatchingModuleRegistrar.cs:28`. Everything else is deliberately per-scenario (see below) |
| `ConnectModuleRegistrar` | `TestAuto.Connect` | ConnectRestClient, Connect-related services |
| `UtilitiesModuleRegistrar` | `TestAuto.Utilities` | All `IStepExecutor` implementations, UtilityOrchestrator |
| `MetadataModuleRegistrar` | `TestAuto.Metadata` | **Nothing — empty placeholder.** See below |

### `MetadataModuleRegistrar` registers nothing

`TestAuto.Metadata\AutoRegistration\MetadataModuleRegistrar.cs:15` — the entire body of
`RegisterServices` is two startup log lines around a `//Add any registrations here that do not
rely on the scenario configuration` comment. There is **no `services.Add*` call at all**.

It exists so the module participates in auto-discovery (and so its "Adding
MetadataModuleRegistrar." / "Finished Adding MetadataModuleRegistrar." lines confirm the assembly
loaded), but do not expect any Metadata service to come from it. The metadata *import* services
TestAuto.Web actually uses — `IModelMetadataHarvester`, `IModelImportScenarioFactory`,
`ITargetDataStoreScriptGenerator` — are registered in `TestAuto.Web\Program.cs` (~`:270`-`:273`),
**not** here. Its XML doc comment also mis-states its purpose ("Registers all DI services for the
Metrics module") — ignore that.

---

## Creating a New Module Registrar

1. Create a class in your subsystem project implementing `IModuleRegistrar`:

```csharp
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Serilog;
using TestAuto.AutoRegistration.Interfaces;
using TestAuto.Shared.Constants;
using TestAuto.Shared.Extensions;

namespace MySubsystem.AutoRegistration;

public class MySubsystemModuleRegistrar : IModuleRegistrar
{
    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        Log.Logger.InformationWithTagAndConsole(LogTagConstants.Startup, "Adding MySubsystemModuleRegistrar");

        services.AddScoped<IMyService, MyService>();
        services.AddTransient<IMyHelper, MyHelper>();

        Log.Logger.InformationWithTagAndConsole(LogTagConstants.Startup, "Finished Adding MySubsystemModuleRegistrar.");
    }
}
```

2. Add a reference to `TestAuto.AutoRegistration` in your project's `.csproj`.

3. Verify the assembly is copied into all relevant `Plugins/` directories via the `CopyToHosts` MSBuild target.

4. No changes needed to `Program.cs` — auto-discovery picks it up.

---

## Troubleshooting

### "Service not registered" at runtime

1. Check the startup logs in Seq for `Registered module: MySubsystem.AutoRegistration.MySubsystemModuleRegistrar`. If absent, the assembly was not loaded.
2. Verify the DLL timestamp in `TestAuto.Web/Plugins/` matches your recent build.
3. Rebuild the full solution so `CopyToHosts` runs.

### Registrar fires but service still not found

Check whether the service is registered with a compatible lifetime (Scoped vs. Transient vs. Singleton) for the injection site. Scoped services cannot be injected into Singletons.

### Matching-specific services not in DI

`MatchingModuleRegistrar` intentionally skips **four** interfaces — they need runtime connection
strings from `ScenarioConfiguration`, which do not exist at container-build time, so they are
constructed per-scenario instead:

| Not registered | Constructed where / how |
|---|---|
| `IRecordMixManager` | in `UnifiedMatchingScenario` — `new RecordMixManager(...)` (`MatchingModuleRegistrar.cs:35`) |
| `IRecordPoolRepository` | in the scenario with the Matching connection string — `new RecordPoolRepository(connStr, logger)` (`:35`, `:38`) |
| `IMatchingCountersService` | per-scenario with connection string, Model database name, and schema (`:41`) |
| `IMatchingStrategyConfigurationService` | per-scenario with the MatchingDB connection string — `new MatchingStrategyConfigurationService(matchingConnStr, logger)`; gives direct SQL access to `[matching].[tMatchingStrategy]` (`:45`) |

So `GetRequiredService<IRecordMixManager>()` will always throw. If you hit a resolution failure
for any of the four, the fix is to construct it in the scenario — **not** to add it to the
registrar.

---

## Sources

- `TestAuto.AutoRegistration\Interfaces\IModuleRegistrar.cs`
- `TestAuto.AutoRegistration\DIServiceRegistration\ModularDIExtensions.cs`
- `TestAuto.Web\AutoRegistration\WebModuleRegistrar.cs`
- `TestAuto.Records\AutoRegistration\RecordsModuleRegistrar.cs`
- `TestAuto.Matching\AutoRegistration\MatchingModuleRegistrar.cs`
- `TestAuto.Connect\AutoRegistration\ConnectModuleRegistrar.cs`
- `TestAuto.Utilities\AutoRegistration\UtilitiesModuleRegistrar.cs`
- `TestAuto.Metadata\AutoRegistration\MetadataModuleRegistrar.cs` (empty placeholder)
- `TestAuto.DependencyInjection\ServiceExtensions\RegisterAllServices.cs` (`RegisterAllModuleServices` call site, ~:167)
