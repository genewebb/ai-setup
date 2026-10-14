---
name: dotnet-logging-schema
description: >
  Serilog logging setup and configuration pattern for speed-merchants .NET projects. Use when
  adding logging to a new project, configuring appsettings.json Serilog/Seq settings,
  understanding how the Profisee platform logger is bootstrapped, wiring UseSerilog() in
  Program.cs, or diagnosing why a sink (file, SQL, Seq) is not receiving logs.
  Note: log tag concatenation conventions are in the testauto-log-tags skill.
---

# Serilog Logging Setup and Configuration

All speed-merchants projects use `Profisee.Platform.Utilities.Logging` as a thin factory wrapper
over Serilog. Every entry point — `TestAuto.Web`, `TestAuto` (CLI), `TestData.Enrichment`,
`TestData.CloneAndMutate` — calls the same `CreateStandardLogger` helper before building the
host, so the file sink (plus SQL and Seq when configured) is active from the first line of startup output.
`Log.Logger` is set as a side effect, so the global static is safe to use immediately.

Log tag conventions (the `[TAG]` prefix on every message) are documented separately in
`testauto-log-tags`.

## When to Use

- "Add logging to a new .NET project in this repo"
- "Configure Seq sink" or "Seq URL not working"
- "Logging not appearing on startup before DI is built"
- "Change minimum log level at runtime"
- "Wire Serilog into ASP.NET Core host (UseSerilog)"
- "Understand how LoggingServiceExtensions or LoggingExtensions work"
- "appsettings.json Serilog / ProfiseeAppSettings logging keys"

## appsettings.json Schema

Logging is driven by keys under `ProfiseeAppSettings`, a top-level `Seq` section, and a
top-level `Serilog` block (honored because the platform logger calls
`ReadFrom.Configuration(configuration)` internally):

```json
{
  "ProfiseeAppSettings": {
    "LoggingFileSizeLimitBytes": "10000000",
    "MinimumLogLevel": "Warning",
    "ProfiseeDBConnection": "Data Source=.;Initial Catalog=Profisee;..."
  },
  "Seq": {
    "ServerUrl": "http://localhost:5341"
  },
  "Serilog": {
    "MinimumLevel": {
      "Default": "Information",
      "Override": {
        "Microsoft.AspNetCore": "Warning",
        "Microsoft.Hosting.Lifetime": "Information",
        "Hangfire.Server": "Warning"
      }
    }
  }
}
```

Key fields:

| Key | Purpose | Default |
|-----|---------|---------|
| `ProfiseeAppSettings:LoggingFileSizeLimitBytes` | Max size of the rolling log file | `10000000` (10 MB) |
| `ProfiseeAppSettings:MinimumLogLevel` | Serilog minimum level (Information, Debug, Verbose, …) | `Warning` (platform logger falls back to Warning when unset/unparseable) |
| `Serilog:MinimumLevel` | Standard Serilog level block (Default + per-namespace Override), read via `ReadFrom.Configuration` | see block above |
| `ProfiseeAppSettings:ProfiseeDBConnection` | DB connection string (used by the platform logger) | — |
| `Seq:ServerUrl` | Seq ingest URL; omit or leave blank to disable Seq | `http://localhost:5341` |

The logger also accepts `ProfiseeAppSettings:SeqUrl` as a fallback for `Seq:ServerUrl`.

## Program.cs Bootstrap

### ASP.NET Core (TestAuto.Web)

```csharp
// 1. RegisterAllServices calls AddLoggingServices, which calls CreateStandardLogger
//    and sets Log.Logger before the host is built.
var (services, updatedConfiguration) = builder.Services.RegisterAllServices(
    configuration: builder.Configuration,
    includeWebServices: true
);

// 2. Wire Serilog into the ASP.NET Core host AFTER Log.Logger has been set.
builder.Host.UseSerilog();
```

ASP.NET Core's built-in HTTP logging is suppressed to avoid duplicates from Serilog:

```csharp
builder.Logging.AddFilter("Microsoft.AspNetCore.Hosting.Diagnostics", LogLevel.Warning);
builder.Logging.AddFilter("Microsoft.AspNetCore.Routing", LogLevel.Warning);
builder.Logging.AddFilter("System.Net.Http.HttpClient", LogLevel.Warning);
builder.Logging.AddFilter("Microsoft.Extensions.Http", LogLevel.Warning);
```

### Console / Worker Host (TestData.Enrichment, TestAuto CLI)

```csharp
// Bootstrap early config from appsettings.json so the logger is live before host build
var earlyConfig = new ConfigurationBuilder()
    .AddJsonFile("appsettings.json", optional: false, reloadOnChange: false)
    .AddEnvironmentVariables()
    .Build();
LoggingExtensions.CreateStandardLogger(earlyConfig);   // TestData.*
// -- or --
LoggingServiceExtensions.CreateStandardLogger(earlyConfig);  // TestAuto CLI

var builder = Host.CreateDefaultBuilder(args)
    // ...ConfigureServices...
    .UseSerilog();  // picks up Log.Logger set above

// Always close the logger on exit
Log.CloseAndFlush();
```

## CreateStandardLogger Implementation

`LoggingServiceExtensions` (in `TestAuto.DependencyInjection`) and
`LoggingExtensions` (in `TestData.Shared`) share the same core implementation, with one
divergence: the TestAuto version additionally reads `FeatureFlags:EnableHttpRequestLogging`
and writes a `Serilog:MinimumLevel:Override:System.Net.Http.HttpClient` override
(`Information` when the flag is on, `Warning` when off) before creating the logger — the
TestData.Shared version does not. Shared core:

```csharp
public static Serilog.ILogger CreateStandardLogger(IConfiguration configuration)
{
    var loggingConnectionString = configuration.GetConnectionString(SqlConnectionStringSecretAliases.ProfiseeDb)
        ?? configuration[ProfiseeAppSettingsConfigurationKeys.ProfiseeDbConnection]
        ?? string.Empty;

    var fileSizeLimitBytes = configuration.GetValue<int>(
        "ProfiseeAppSettings:LoggingFileSizeLimitBytes", 10_000_000);

    var seqUrl = configuration["Seq:ServerUrl"]
        ?? configuration["ProfiseeAppSettings:SeqUrl"]
        ?? string.Empty;

    var loggingOptions = new LoggingOptions
    {
        Configuration = configuration,
        LoggingConnectionString = loggingConnectionString,
        FileSizeLimitBytes = fileSizeLimitBytes,
        SeqUrl = seqUrl,
    };

    var logger = ProfiseeLogger.CreateLogger(loggingOptions);

    // Optionally override minimum level from config
    var minimumLogLevelStr = configuration["ProfiseeAppSettings:MinimumLogLevel"];
    if (!string.IsNullOrWhiteSpace(minimumLogLevelStr) &&
        Enum.TryParse<Serilog.Events.LogEventLevel>(minimumLogLevelStr, true, out var level))
    {
        ProfiseeLogger.ChangeMinimumLogLevel(level);
    }

    Log.Logger = logger;  // sets global static
    return logger;
}
```

## Sinks

Sinks are configured inside `Profisee.Platform.Utilities.Logging` via `LoggingOptions`.
Only the rolling file sink is always active; there is **no console sink** — console output
comes only from the `*WithTagAndConsole` helper methods (see `testauto-log-tags`):

| Sink | Enabled | Controlled by |
|------|---------|---------------|
| Rolling file | Always | `LoggingOptions.FileSizeLimitBytes` |
| SQL Server (`logging.tSystemLog`) | When `LoggingConnectionString` is non-empty | `ProfiseeAppSettings:ProfiseeDBConnection` / connection string |
| Seq | When `SeqUrl` is non-empty | `Seq:ServerUrl` in appsettings |

If `Seq:ServerUrl` is absent or empty, startup logs a message:
`"SeqUrl is not configured. Seq sink will not receive logs."`

> [!important] "No console sink" is correct — several repo docs say otherwise and are wrong
> This gets re-challenged, so here is the hard evidence (checked 2026-07-27 against
> `Profisee.Platform.Utilities.Logging` **1.0.1.173**, the version pinned at
> `Directory.Packages.props:67`):
>
> The assembly's Serilog sink assembly references are exactly
> **`Serilog.Sinks.Async`, `Serilog.Sinks.File`, `Serilog.Sinks.MSSqlServer`, `Serilog.Sinks.Seq`** —
> there is **no `Serilog.Sinks.Console` reference and not a single "Console" string** in the DLL.
> The package *nuspec* does list `Serilog.Sinks.Console` as a dependency, but the library never
> calls it, so it is a transitive package that is never wired into a sink.
>
> **Sources that wrongly claim a console sink** — do not treat these as authority:
> - `TestData.Shared/Extensions/LoggingExtensions.cs:14` — comment says "the same Profisee sinks
>   (console, file, SEQ)". The comment is stale; the method just forwards `LoggingOptions` to
>   `ProfiseeLogger.CreateLogger` and adds no console sink.
> - `TestAuto.Web/Documentation/00_SolutionInventory.md:328` and `CompleteReference.md:308` —
>   "sinks: Console, File, Seq, MSSqlServer".
>
> **Sources that agree with this skill**: `TestAuto.Web/Documentation/10_ADR_005_SerilogForLogging.md:102`
> and `CompleteReference.md:6734` — "Structured logs are no longer emitted to a Serilog Console
> sink… Startup banner/diagnostic lines are still written to the console directly via the
> `*WithTagAndConsole` helpers."
>
> So: console text you see at startup comes from `*WithTagAndConsole`
> (`TestAuto.Shared/Extensions/LoggerTagExtensions.cs:49,74,81,100,107`), **not** from a Serilog
> sink. Re-verify by re-reading the DLL's assembly references if the package version changes.

## Enrichers

Enrichers are managed inside `Profisee.Platform.Utilities.Logging`. No custom enricher
registration is performed in this codebase beyond what the platform package provides.

The `Log.ForContext("SourceContext", ...)` pattern adds a source label to pipeline-stage
log entries in `Program.cs`:

```csharp
var programLogger = Log.ForContext("SourceContext", typeof(Program).FullName ?? nameof(Program));
```

## Profisee Platform Logging

`Profisee.Platform.Utilities.Logging` is the canonical logger factory. Key types:

| Type | Usage |
|------|-------|
| `Profisee.Platform.Utilities.Logging.Logger` (aliased `ProfiseeLogger`) | `ProfiseeLogger.CreateLogger(loggingOptions)` — constructs the Serilog `ILogger` |
| `LoggingOptions` | DTO carrying `Configuration`, `LoggingConnectionString`, `FileSizeLimitBytes`, `SeqUrl` |
| `ProfiseeLogger.ChangeMinimumLogLevel(LogEventLevel)` | Runtime level override |

Standard import alias used wherever the logger is constructed:
```csharp
using ProfiseeLogger = Profisee.Platform.Utilities.Logging.Logger;
```

Extension methods (`InformationWithTag`, `WarningWithTag`, `ErrorWithTag`, `FatalWithTag`,
`VerboseWithTag`, `InformationWithTagAndConsole`, `WarningWithTagAndConsole`) live in
`TestAuto.Shared.Extensions` — see `testauto-log-tags` for tag conventions.

## DI Registration (TestAuto.Web / TestAuto CLI)

`LoggingServiceExtensions.AddLoggingServices` is called by `RegisterAllServices`. It:
1. Calls `CreateStandardLogger` (sets `Log.Logger`)
2. Registers `Serilog.ILogger` as a singleton in the DI container

`builder.Host.UseSerilog()` must be called **after** `RegisterAllServices` so that
`Log.Logger` is already set when ASP.NET Core wires up the host.

For console/worker projects, register the logger manually before `.UseSerilog()`:
```csharp
services.AddSingleton<Serilog.ILogger>(_ => Log.Logger);
```

## Adding Logging to a New Project

1. **NuGet packages** — add references to:
   - `Profisee.Platform.Utilities.Logging`
   - `Serilog.Extensions.Hosting` (console/worker — provides `.UseSerilog()`)
   - Reference `TestAuto.Shared` (for extension methods) or `TestData.Shared` (TestData.* tools)

2. **appsettings.json** — add the required keys:
   ```json
   {
     "ProfiseeAppSettings": {
       "LoggingFileSizeLimitBytes": "10000000",
       "MinimumLogLevel": "Warning",
       "ProfiseeDBConnection": "<connection string>"
     },
     "Seq": {
       "ServerUrl": "http://localhost:5341"
     }
   }
   ```

3. **Program.cs — early bootstrap** — call `CreateStandardLogger` before building the host:
   ```csharp
   var earlyConfig = new ConfigurationBuilder()
       .AddJsonFile("appsettings.json", optional: false, reloadOnChange: false)
       .AddEnvironmentVariables()
       .Build();
   LoggingExtensions.CreateStandardLogger(earlyConfig);        // TestData.* projects
   // or: LoggingServiceExtensions.CreateStandardLogger(earlyConfig);  // TestAuto.* projects
   ```

4. **Host builder** — wire Serilog:
   ```csharp
   builder.UseSerilog();   // uses Log.Logger set in step 3
   ```

5. **DI registration** — register the instance for injection:
   ```csharp
   services.AddSingleton<Serilog.ILogger>(_ => Log.Logger);
   ```

6. **Flush on exit** — always add at the end of `Main`/top-level statements:
   ```csharp
   Log.CloseAndFlush();
   ```

7. **Suppress ASP.NET noise** (web projects only) — add the four `AddFilter` calls from the
   Program.cs Bootstrap section above.

## Sources

- `TestAuto.Web/appsettings.json`
- `TestAuto.Web/appsettings.development.json`
- `TestAuto.Web/Program.cs`
- `TestData.Enrichment/Program.cs`
- `TestAuto/Program.cs`
- `TestAuto.DependencyInjection/ServiceExtensions/LoggingServiceExtensions.cs`
- `TestData.Shared/Extensions/LoggingExtensions.cs`
