---
name: dotnet-project-structure
description: >
  Standard .NET solution folder structure patterns, naming conventions, and the AutoRegistration
  module pattern. Use when creating new projects, adding project layers, organizing files in an
  existing solution, reviewing folder structure, or onboarding to a .NET codebase.
---

Repo: speed-merchants (paths below are repo-relative)

# .NET Project Structure

Standard folder structure and naming conventions for .NET projects. Reusable baseline — project-specific rules extend this base.

## When to Use

- "Where should I put this new service?"
- "What folders does a new project need?"
- "How do I organize this project?"
- "What's the AutoRegistration pattern?"
- Onboarding to a .NET solution for the first time.

---

## Core Folders

Every project should include these where applicable:

| Folder | Purpose | Contents |
|--------|---------|----------|
| `AutoRegistration/` | DI module registration | `*ModuleRegistrar.cs` implementing `IModuleRegistrar` |
| `Common/` | Shared types within the project | DTOs, enums, base classes, shared models |
| `Interfaces/` | Contract definitions | `I*.cs` interface files |
| `Services/` | Business logic | Service implementations |
| `Helpers/` | Utility classes | Static helpers, extension method classes |
| `Extensions/` | Extension methods | `*Extensions.cs` files |
| `Models/` | Data models | POCOs, view models, request/response objects |
| `Constants/` | Constant values | Static constant classes |

## Optional Folders (Use When Needed)

| Folder | Purpose | When to Use |
|--------|---------|-------------|
| `Builders/` | Builder pattern classes | Complex object construction |
| `Factories/` | Factory pattern classes | Object creation logic |
| `Validators/` | Validation logic | Input/business rule validation |
| `Configuration/` | Config classes | Settings, options patterns |
| `Scenarios/` | Test scenarios | Performance/integration test scenarios |
| `Samples/` | Sample data | JSON samples, test fixtures |
| `Documentation/` | Project docs | Markdown documentation |
| `Scripts/` | Utility scripts | SQL, PowerShell, shell scripts |

---

## Naming Conventions

### Files

| Type | Convention | Example |
|------|------------|---------|
| Interface | `I{Name}.cs` | `IScenarioService.cs` |
| Implementation | `{Name}.cs` | `ScenarioService.cs` |
| Extension methods | `{Type}Extensions.cs` | `StringExtensions.cs` |
| Constants | `{Domain}Constants.cs` | `MatchingConstants.cs` |
| Base class | `{Name}Base.cs` | `ScenarioBase.cs` |
| Module registrar | `{Project}ModuleRegistrar.cs` | `WebModuleRegistrar.cs` |

### Classes

- **PascalCase** for all class names
- **Suffix with type:** `*Service`, `*Helper`, `*Builder`, `*Factory`, `*Validator`
- **Prefix interfaces** with `I`

---

## AutoRegistration Pattern

Every project with services must have an `AutoRegistration/` folder:

```
{ProjectName}/
└── AutoRegistration/
    └── {ProjectName}ModuleRegistrar.cs
```

The registrar implements `IModuleRegistrar` and registers all project services:

```csharp
public class {ProjectName}ModuleRegistrar : IModuleRegistrar
{
    public void RegisterServices(IServiceCollection services, IConfiguration configuration)
    {
        services.AddScoped<IMyService, MyService>();
    }
}
```

### Registrar vs `Program.cs` — the real speed-merchants convention

The rule is **"a registrar by default"**, not "never `Program.cs`". `TestAuto.Web/Program.cs`
legitimately contains a `// ── Web-specific services ──` block (`Program.cs:249`-`:276`) that
registers several service families directly, alongside the auto-discovered registrars.

| Belongs in a `*ModuleRegistrar` | Legitimately sits in `Program.cs` |
|---|---|
| Ordinary business-logic services, repositories, facades, orchestrators — anything resolvable from `IServiceCollection` + `IConfiguration` alone | Registrations that need the **host builder** itself (`builder.Configuration`, `builder.ConfigureHttpsCertificate`, options binding) |
| Anything a *plugin* assembly ships (it must self-register — nothing else references it) | Framework/host plumbing: `AddRazorComponents`, `AddAuthentication`, `AddAuthorization`, `AddSwaggerGen`, `AddRadzenComponents`, `AddResponseCompression`, `AddHttpContextAccessor` |
| Anything the CLI host also needs (registrars run in both hosts) | Singletons built from values computed during startup — e.g. `IAppStartupStatus` (`:220`) and `AddSingleton(updatedConfiguration)` (`:204`), which only exist after `RegisterAllServices` returns (`:179`) |
| | Typed `HttpClient` registrations needing startup-time config, e.g. `AddHttpClient<IWebUiClient, WebUiClient>` (`:308`) |

Verified `Program.cs` registrations that are **not** in `WebModuleRegistrar`:

- **Script discovery** — `AddSingleton<IScriptDiscoveryService>` via factory (`:251`)
- **ConnEx** — `IConnExApiClient`, `IConnExScenarioFactory`, `IConnExArtifactStorage`,
  `IArtifactTokenScanner`, `IArtifactTokenizer`, `ISecretCatalog` (`:259`-`:267`)
- **Metadata import** — `IModelMetadataHarvester`, `IModelImportScenarioFactory`,
  `ITargetDataStoreScriptGenerator` (`:270`-`:273`)
- **Secrets** — `ISecretSectionRegistry` plus
  `Configure<SecretReplacementOptions>(builder.Configuration.GetSection(...))` (`:274`-`:276`)

Note that `MetadataModuleRegistrar` exists but registers **nothing** — the metadata-import
services above are the Web host's, and they live in `Program.cs`. So an empty registrar is not
evidence that a subsystem has no services.

**Guidance:** prefer the registrar. Reach for `Program.cs` only when the registration genuinely
needs `WebApplicationBuilder` state that `RegisterServices(IServiceCollection, IConfiguration)`
cannot see. When you do, keep it inside the existing `// ── Web-specific services ──` block
rather than scattering it through startup.

---

## Dependency Hierarchy

Projects follow this dependency flow — lower layers must not reference higher ones:

```
Shared/Common          (no dependencies)
    ↓
Interfaces             (depends on Shared)
    ↓
Infrastructure         (depends on Interfaces)
    ↓
Business Logic         (depends on Infrastructure)
    ↓
Web/API                (depends on Business Logic)
    ↓
Tests                  (depends on all)
```

---

## File Organization Rules

1. **One class per file** (except small related types like simple enums alongside a class)
2. **Filename matches class name** exactly
3. **No nested classes** in separate files — extract to own file
4. **Group by feature** when a folder grows to 10+ files
5. **Keep folders flat** — avoid deep nesting (max 3 levels)

---

## Anti-Patterns to Avoid

| Anti-Pattern | Do This Instead |
|--------------|-----------------|
| `Utils/` folder | Use specific folders: `Helpers/`, `Extensions/` |
| `Misc/` folder | Organize by purpose |
| Deep nesting (4+ levels) | Flatten or split project |
| Giant classes (500+ lines) | Split by responsibility |
| Inline DTOs inside controllers | Extract to `Common/` or `Models/` |

---

## Sources

- `.cursor\rules\base\projects\_base-structure.mdc` (deleted 2026-05-16)
- `TestAuto.Web\Program.cs` (Web-specific services block, ~:249-276)
- `TestAuto.Web\AutoRegistration\WebModuleRegistrar.cs`
- `TestAuto.Metadata\AutoRegistration\MetadataModuleRegistrar.cs` (empty placeholder)
