---
name: testauto-tech-stack
description: >
  TestAuto (speed-merchants) technology stack mandates and forbidden patterns. Use when
  starting a new class, adding a NuGet package, choosing a logging interface, or selecting
  a JSON library — specifically to avoid Entity Framework, System.Text.Json, or
  Microsoft.Extensions.Logging.ILogger which are all forbidden in this repo.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Technology Stack

TestAuto has a strict technology stack. Deviating from it — even with libraries that are popular elsewhere on the platform — is forbidden.

## When to Use

- "What logging library should I use?"
- "Can I use System.Text.Json here?"
- "Should I add Entity Framework for this?"
- Adding any new NuGet package to a TestAuto project
- Starting a new service or class and choosing dependencies
- Code review on `using` directives or `.csproj` package references

## Required Stack

| Category | Required library / pattern | Notes |
|---|---|---|
| Framework | .NET 10, Blazor Web App (Interactive Server render mode), ASP.NET Core Web API | |
| UI Components | Radzen.Blazor | Material Symbols icons — see `blazor-icons` |
| Data Access (Profisee) | `IRestClient` | See `profisee-rest-api` |
| Data Access (SQL) | `SqlHelper` | See `dotnet-sql-data-access` |
| Logging | `Serilog.ILogger` → SQL sink to `[logging].[tSystemLog]` | See `dotnet-logging-schema` |
| JSON | `Newtonsoft.Json` | In all application code |
| Testing | MSTest + bUnit (Blazor) + Moq + FluentAssertions. **No E2E/browser framework.** | See `testauto-testing-patterns` |
| DI | Central `RegisterAllServices` | See `dotnet-service-registration` |
| Secrets | DB-backed `TestAutoSecrets` store (`RegisterAllServices.LoadEntitySecrets` + `SecretStorageHelper`) | See `testauto-secrets-management` |
| Job Processing | Hangfire | |
| DevOps | Azure DevOps | |

## Forbidden Patterns

| Forbidden | Required alternative | Reason |
|---|---|---|
| Entity Framework | `SqlHelper` (raw SQL) or `IRestClient` (Profisee data) | Not part of this stack |
| `System.Text.Json` in application code | `Newtonsoft.Json` (`JsonConvert`) | Standardized on Newtonsoft |
| `Microsoft.Extensions.Logging.ILogger` | `Serilog.ILogger` | Different interface, same name — see below |
| Hard-coded domain values | Fetch from DB/config at runtime | See `dotnet-domain-values` |
| Hard-coded entity/attribute name strings | `EntityNames.*` and `FieldNames.*` constants | See `dotnet-entity-constants` |

## Common Trap: ILogger Namespace Collision

Both Microsoft and Serilog expose an `ILogger` interface with the same short name. This is the most common mistake in the repo.

```csharp
// WRONG — Microsoft's ILogger, not Serilog
using Microsoft.Extensions.Logging;
public MyService(ILogger<MyService> logger) { }  // Generic — also wrong

// CORRECT — Serilog's ILogger
using Serilog;
public MyService(ILogger logger) { }  // Non-generic, Serilog

// Also correct (explicit alias used in some TestAuto files)
using ILogger = Serilog.ILogger;
```

In TestAuto, `ILogger` always means `Serilog.ILogger`. If you see `Microsoft.Extensions.Logging.ILogger` in a constructor or `using` statement, that is a bug.

## Common Trap: System.Text.Json vs Newtonsoft

```csharp
// WRONG
using System.Text.Json;
var json = JsonSerializer.Serialize(obj);
var obj = JsonSerializer.Deserialize<T>(json);

// CORRECT
using Newtonsoft.Json;
var json = JsonConvert.SerializeObject(obj);
var obj = JsonConvert.DeserializeObject<T>(json);
```

The `Newtonsoft.Json` restriction applies to **application code**. ASP.NET Core's own internal pipeline may use `System.Text.Json` — that is not the concern. Any `using System.Text.Json` in a TestAuto project file is a violation.

## Package Selection Checklist

Before adding a new NuGet package:

1. Does the functionality exist in the approved stack table above? → Use it.
2. Does it duplicate a forbidden library (EF, System.Text.Json)? → Stop; use the approved alternative.
3. Is it a test-only dependency? → Confirm it is in the approved testing packages: **MSTest**
   (`MSTest.TestAdapter` + `MSTest.TestFramework`), **bUnit** (`bunit` / `bunit.web`), **Moq**, and
   **FluentAssertions** — all declared centrally in `Directory.Packages.props`.

   > [!warning] Playwright and NSubstitute are NOT in this solution
   > A repo-wide grep for `playwright` and `nsubstitute` across `*.cs`, `*.csproj`, and `*.props`
   > returns **zero hits** (verified 2026-07-27, HEAD 4c367fe6). There is no browser/E2E test
   > framework here, and the mocking library is **Moq**, not NSubstitute. Do not write test code
   > against either, and do not cite them as "the existing pattern".
4. None of the above? → Discuss with the team before adding.

## Sources

- `AGENTS.md` — Technology Stack: Required / Forbidden sections (source deleted; canonical rules now in this skill)
