---
name: profisee-logging-library
description: >
  Reference for Profisee.Platform.Utilities.Logging — the Serilog factory wrapper every
  Profisee/speed-merchants app uses. Use when working on the logger itself, sinks
  (File/SQL/Seq/custom), enrichers, CreateLogger overloads, LoggingOptions, runtime level control,
  destructuring, the logging.tSystemLog schema, MinimumLevel.Override / Serilog appsettings
  behavior, or "why is X logged / not logged / at this level". Consumer-side wiring is
  dotnet-logging-schema; [TAG] conventions are testauto-log-tags.
---

# Profisee.Platform.Utilities.Logging

The canonical logger factory for all Profisee/speed-merchants .NET apps. A thin, opinionated
wrapper over **Serilog** that produces a configured `Serilog.ILogger` from a `LoggingOptions`
object (or convenience overloads) and sets `Log.Logger` as a side effect when consumers route it.

- **Assembly / namespace**: `Profisee.Platform.Utilities.Logging`
- **Target framework**: `netstandard2.0` (consumable from .NET Framework and modern .NET)
- **Entry type**: `public static class Logger`
- **Repo**: `{ReposRoot}\utilities\Utilities.Logging` (`Logging/` = library, `LoggingTests/` = MSTest)
- **Consumer-side setup** (Program.cs, appsettings keys, `CreateStandardLogger`): see `dotnet-logging-schema`.

## Contents
- [CreateLogger pipeline (order of operations)](#createlogger-pipeline)
- [Public API: the Logger class](#public-api)
- [LoggingOptions](#loggingoptions)
- [Sinks](#sinks)
- [Enrichers](#enrichers)
- [Destructuring (hiding/shaping data)](#destructuring)
- [Configuration & level control](#configuration--level-control)
- [Built-in filters](#built-in-filters)
- [SQL Server log schema](#sql-server-log-schema)
- [Static write helpers](#static-write-helpers)
- [Package dependencies (available sinks)](#package-dependencies)
- [Testing patterns](#testing-patterns)
- [Gotchas](#gotchas)

## CreateLogger pipeline

`CreateLogger(LoggingOptions)` is the single real implementation; every other overload builds a
`LoggingOptions` and calls it. The configuration is assembled in this **exact order** — order
matters because Serilog is last-write-wins for several settings:

1. **Base configuration** (`createBaseLoggerConfiguration`)
   - `MinimumLevel.ControlledBy(_levelSwitch)` — a static `LoggingLevelSwitch`, **default `Warning`**.
   - Built-in NServiceBus filters (see [Built-in filters](#built-in-filters)).
   - Enrichers: `FromLogContext`, `WithAssemblyName`, `WithAssemblyVersion`, `WithEnvironmentUserName`, `WithMachineName`, `WithEventType`.
   - `Destructure.UsingAttributes()` (Destructurama.Attributed) + any `DestructuringPolicies` passed in.
2. **Custom delegate** — `LoggingOptions.CustomLogConfigProvider?.Invoke(logConfig)`. Runs against the
   *already-built* base config, so it can add filters/sinks/enrichers **or override** earlier settings
   (e.g. `config => config.MinimumLevel.Debug()` replaces the level switch — proven in tests).
3. **`ReadFrom.Configuration(Configuration)`** — if `Configuration` is non-null, the **entire Serilog
   appsettings section is honored** (`Serilog:MinimumLevel`, `Serilog:MinimumLevel:Override:{ns}`,
   `Serilog:WriteTo:*`, `Serilog:Enrich:*`, etc.). Then the level switch is set from
   `ProfiseeAppSettings:MinimumLogLevel` (default `Warning` if missing/unparseable).
4. **Sinks** (`addSinks`) — File (always) + SQL Server / Seq / custom (conditional). See [Sinks](#sinks).

> **This is the key to per-namespace noise control.** Because step 3 calls `ReadFrom.Configuration`,
> you can suppress chatty namespaces (e.g. `System.Net.Http.HttpClient`, `Microsoft.AspNetCore`,
> `Hangfire`) **without touching code** by adding a `Serilog:MinimumLevel:Override` section to
> appsettings. This is more reliable than `builder.Logging.AddFilter(...)`, which does not consistently
> survive the `UseSerilog()` bridge.

## Public API

`Logger` (static). Key members:

| Member | Purpose |
|---|---|
| `CreateLogger()` | Bare logger (File sink only; no DB/Seq). |
| `CreateLogger(string connStr, int fileSizeLimitBytes=10MB, CustomLogConfigProviderDelegate=null, Assembly=null)` | + SQL Server sink. |
| `CreateLogger(IConfiguration, string connStr, …)` | + reads Serilog/appsettings config. |
| `CreateLogger(IConfiguration, string connStr, IEnumerable<IDestructuringPolicy>, …)` | + custom destructuring. |
| `CreateLogger(IConfiguration, string connStr, IEnumerable<IDestructuringPolicy>, IEnumerable<ILogEventSink> customSinks, int fileSizeLimitBytes=10MB, CustomLogConfigProviderDelegate=null, Assembly=null, bool autoCreateLogTable=false)` | Most explicit overload. |
| `CreateLogger(LoggingOptions)` | The canonical implementation. **Prefer this.** |
| `ChangeMinimumLogLevel(LogEventLevel)` | Mutates the static level switch **at runtime** (affects already-created loggers that use the switch). |
| `WriteToLog` / `WriteErrorToLog` / `WriteInfoToLog` | Static convenience writers over `Log.*` (see [helpers](#static-write-helpers)). |
| `delegate CustomLogConfigProviderDelegate(LoggerConfiguration) : LoggerConfiguration` | Hook to mutate the config mid-pipeline (step 2). |

**Public constants** (property names used by enrichers, the file template, and the SQL columns):
`EventLogSourceName` (`"Profisee Master Data Maestro"`, legacy), `EventTypePropertyName`,
`EventCodePropertyName`, `AssemblyNamePropertyName`, `AssemblyVersionPropertyName`,
`SourceContextPropertyName`, `EnvironmentUserNamePropertyName`, `MachineNamePropertyName`.

## LoggingOptions

The configuration DTO (`Logging/LoggingOptions.cs`):

| Property | Type | Default | Effect |
|---|---|---|---|
| `Configuration` | `IConfiguration` | null | If set, `ReadFrom.Configuration` runs (Serilog section honored) and `ProfiseeAppSettings:MinimumLogLevel` sets the switch. |
| `LoggingConnectionString` | string | null | If non-empty, enables the **SQL Server** sink → `logging.tSystemLog`. |
| `SeqUrl` | string | null | If non-empty, enables the **Seq** sink. |
| `DestructuringPolicies` | `IEnumerable<IDestructuringPolicy>` | null | Custom object→log shaping (applied in base config, before the delegate). |
| `CustomSinks` | `IEnumerable<ILogEventSink>` | null | Arbitrary extra sinks (e.g. an in-memory test sink). |
| `FileSizeLimitBytes` | int | `10_000_000` (10 MB) | Rolling file size limit. |
| `CustomLogConfigProvider` | delegate | null | Step-2 config mutation hook. |
| `Assembly` | `Assembly` | null | Used by AssemblyName/Version enrichers; falls back to entry/calling assembly. |
| `AutoCreateLogTable` | bool | false | Passes `AutoCreateSqlTable` to the MSSqlServer sink. |

## Sinks

`addSinks` wires these — note that **only the File sink is unconditional**:

| Sink | When | Details |
|---|---|---|
| **File** (async, rolling) | **Always** | Wrapped in `WriteTo.Async`. Template = `MessageTemplates.LogFileOutputTemplate`. `rollOnFileSizeLimit: true`, `retainedFileCountLimit: 10`, size = `FileSizeLimitBytes`. Path resolved by `getLogFilePath()` — tries `{BaseDirectory}\LogFiles`, then `%AppData%\Profisee\{version}\{assembly}\LogFiles`, falling back to a bare `SystemLog.log` if neither is writable. |
| **SQL Server** | `LoggingConnectionString` non-empty | `WriteTo.MSSqlServer` → table `logging.tSystemLog`, `BatchPostingLimit: 1000`, `BatchPeriod: 15s`, `AutoCreateSqlTable` from option. See [schema](#sql-server-log-schema). |
| **Seq** | `SeqUrl` non-empty | `WriteTo.Seq(SeqUrl)`. |
| **Custom** | `CustomSinks` provided | Each added via `WriteTo.Sink(sink)`. |

> **Console is NOT wired by the library.** The `Serilog.Sinks.Console` package is referenced, but
> `addSinks` does not add it. Console output (and AWS/Azure analytics sinks, also referenced) only
> appear if a consumer adds them via the `Serilog:WriteTo` appsettings section (step 3) or `CustomSinks`.
> (The older `dotnet-logging-schema` skill's "console always active" claim refers to consumer config,
> not the library.)

> **Windows Event Log is removed.** `EventIdProvider.cs` is fully commented out and `addSinks` notes
> "windows event log has been removed." The `EventLogSourceName` constant and `WindowsEventLogTests`
> are legacy leftovers.

## Enrichers

Defined in `Logging/Enrichers/`. Every event is enriched with:

| Property | Source | Notes |
|---|---|---|
| `EventType` | `EventTypeEnricher` | **Hex hash of the message template text** (`MessageTemplate.Text.GetHashCode():X`). Groups all events sharing a template — useful for "events by type" in Seq/SQL. Added only if absent. |
| `AssemblyName` | `WithAssemblyName` | From entry/calling assembly (or `Assembly` option / `<T>`). |
| `AssemblyVersion` | `WithAssemblyVersion` | Full version by default; `useSemVer:true` → `Major.Minor.Build`. `WithAssemblyInformationalVersion` also available (uses `AssemblyInformationalVersionAttribute`). |
| `EnvironmentUserName` | `Serilog.Enrichers.Environment` | |
| `MachineName` | `Serilog.Enrichers.Environment` | |
| (log context) | `FromLogContext` | Enables `LogContext.PushProperty(...)`, e.g. `EventCode`. |

The `WithEventType` / `WithAssemblyName` / `WithAssemblyVersion` / `WithAssemblyInformationalVersion`
extension methods live in `EnrichmentConfigurations` (the AssemblyName/Version code is vendored from
`Serilog.Enrichers.AssemblyName` because the NuGet DLL isn't strong-named).

## Destructuring

- `Destructure.UsingAttributes()` is always on → **`Destructurama.Attributed` attributes work**, most
  importantly `[NotLogged]` to redact a property (e.g. secrets) when an object is logged with `{@Obj}`.
- Pass `DestructuringPolicies` (`IEnumerable<IDestructuringPolicy>`) to reshape objects globally — e.g.
  project a `FooBar` down to a safe `FooBase` before serialization. Implement `IDestructuringPolicy.TryDestructure`.

## Configuration & level control

There are **three** ways the minimum level is influenced; understand the precedence:

1. **Static switch** — base config uses `MinimumLevel.ControlledBy(_levelSwitch)`, default `Warning`.
   `ChangeMinimumLogLevel(level)` mutates it at runtime (live for loggers still bound to the switch).
2. **`ProfiseeAppSettings:MinimumLogLevel`** — read in step 3; calls `ChangeMinimumLogLevel(parsed)`
   (default `Warning` if absent/unparseable). This is the normal "set the level from appsettings" path.
3. **`Serilog:` appsettings section** (via `ReadFrom.Configuration`) and/or the **custom delegate** can
   set `MinimumLevel` / `MinimumLevel.Override` directly. A static `MinimumLevel.X()` **replaces** the
   `ControlledBy(switch)` binding (last-write-wins), after which `ChangeMinimumLogLevel` no longer
   affects that logger. Per-namespace `Override` is the recommended way to silence noisy categories.

Example appsettings to cut HTTP/framework noise while keeping app logs at Information:

```json
{
  "ProfiseeAppSettings": { "MinimumLogLevel": "Information" },
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft": "Warning",
        "Microsoft.AspNetCore": "Warning",
        "System.Net.Http.HttpClient": "Warning",
        "Hangfire": "Warning"
      }
    }
  },
  "Seq": { "ServerUrl": "http://localhost:5341" }
}
```

## Built-in filters

The base config always excludes these noisy sources (NServiceBus license/feature spam):
`Filter.ByExcluding(Matching.FromSource("NServiceBus.LicenseManager"))` and
`...("NServiceBus.Features.AutoSubscribe")`.

## SQL Server log schema

Target table: **`logging.tSystemLog`** (must match `tSystemLog` in the Database project). The sink:

- **Adds** custom queryable columns: `EventType` (nvarchar 32), `EventCode` (nvarchar 6),
  `AssemblyName` (200), `AssemblyVersion` (200), `SourceContext` (500), `EnvironmentUserName` (200),
  `MachineName` (200).
- **Removes** standard columns `MessageTemplate` and `Properties` (XML).
- **Adds** standard column `LogEvent` (serialized **JSON** — query with SQL Server JSON functions).
- **TimeStamp stored in UTC.** Batched at 1000 rows / 15s. `AutoCreateSqlTable` only when opted in.

## Static write helpers

Convenience methods over Serilog's global `Log.*`, each pushing an `EventCode` property via
`LogContext`:

- `WriteToLog(string msg, LogEventLevel level, int eventCode=0)` — routes to `Log.Error/Fatal/Warning/Verbose/Debug/Information`.
- `WriteToLog(Exception ex, string msg, int eventCode=0)` — `Log.Error(ex, msg)`.
- `WriteErrorToLog(Exception ex, int eventCode=0)` — flattens exception properties into the message.
- `WriteErrorToLog(string message, int eventCode=0)` / `WriteInfoToLog(string message, int eventCode=0)`.

Prefer injected `Serilog.ILogger` with structured templates in app code; these statics exist for
legacy/global call sites. (For `[TAG]`-prefixed structured logging conventions, see `testauto-log-tags`.)

## Package dependencies

Available sinks/enrichers (referenced in `Utilities.Logging.csproj`; **only File/SQL/Seq are wired by
default** — the rest are opt-in via `Serilog:WriteTo` config or `CustomSinks`):

`Serilog` 4.3.1, `Serilog.Settings.Configuration` 8.0 (`ReadFrom.Configuration`),
`Serilog.Sinks.Async`, `Serilog.Sinks.File`, `Serilog.Sinks.MSSqlServer` 6.6, `Serilog.Sinks.Seq` 8.0,
`Serilog.Sinks.Console`, `Serilog.Sinks.AzureAnalytics`, `AWS.Logger.SeriLog`,
`Serilog.Enrichers.Environment`, `Serilog.Enrichers.Thread`, `Serilog.Expressions`, `SerilogMetrics`,
`Destructurama.Attributed` 4.0, `Microsoft.Data.SqlClient` 5.2.

## Testing patterns

`LoggingTests/` (MSTest) shows the supported extensibility, and the patterns to reuse:

- **In-memory sink** — `InMemorySerilogTestSink : ILogEventSink` buffers `LogEvent`s in a
  `ConcurrentQueue` and exposes `GetLogEvents()` / `Clear()`. Pass it as a `CustomSinks` entry to assert
  on emitted events without a DB/Seq.
- **Custom delegate** — `CustomLogConfigProviderDelegateTests` proves: the delegate (a) adds filters
  (`config.Filter.ByExcluding(...)`), (b) merges with — not replaces — the base config (destructuring
  still applies), and (c) can **override** the base level (`config.MinimumLevel.Debug()` wins over the
  Information switch).
- **Destructuring policy** — `TestDestructurePolicy` reshapes `FooBar`→`FooBase`; `[NotLogged]`
  (`ObjectWithTopSecretData.TopSecret`) demonstrates attribute redaction.

## Gotchas

- **Default level is `Warning`, not Information.** If neither `ProfiseeAppSettings:MinimumLogLevel`
  nor a `Serilog:MinimumLevel` is set, you get Warning+ only. Consumers that "see nothing" usually
  haven't set the level.
- **Order matters.** The custom delegate runs *before* `ReadFrom.Configuration`; a `Serilog:` section
  can therefore override delegate choices for anything Serilog treats as last-write-wins.
- **Console isn't automatic** — add it via the `Serilog:WriteTo:Console` section if you want it.
- **`EventType` is a template hash**, not a semantic code. Use `EventCode` (pushed via the write
  helpers / `LogContext`) for meaningful codes.
- **`netstandard2.0`** — keep new code netstandard-compatible; this library is consumed by both .NET
  Framework and modern .NET hosts.

## Sources
- `{ReposRoot}\utilities\Utilities.Logging\Logging\Logger.cs`
- `{ReposRoot}\utilities\Utilities.Logging\Logging\LoggingOptions.cs`
- `{ReposRoot}\utilities\Utilities.Logging\Logging\MessageTemplates.cs`
- `{ReposRoot}\utilities\Utilities.Logging\Logging\Enrichers\{EnrichmentConfigurations,EventTypeEnricher}.cs`
- `{ReposRoot}\utilities\Utilities.Logging\Logging\Utilities.Logging.csproj`
- `{ReposRoot}\utilities\Utilities.Logging\LoggingTests\*` (usage/extensibility patterns)
- Related: `dotnet-logging-schema` (consumer setup), `testauto-log-tags` (tag conventions)
