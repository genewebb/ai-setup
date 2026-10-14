---
name: crewchief-architecture
description: >
  Orientation map for the standalone CrewChief step/workflow automation tool (6 projects, .NET 10,
  files-only, zero TestAuto refs). Use when starting work anywhere under CrewChief\, deciding which
  project a change belongs in, adding a NuGet package or endpoint, reasoning about its build
  isolation and security posture, or how the Web host runs as a Windows Service (UseWindowsService /
  content-root pinning / machine-shared secrets).
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Architecture

CrewChief is a **brand-new, fully standalone automation product** living inside the speed-merchants
repo at `CrewChief\`. It has its own solution (`CrewChief.sln`) with **zero references to any
`TestAuto.*` project** — it builds and runs independently of the rest of the repo. Its purpose is to
author and run **steps and workloads** that automate remote-machine **box prep** (IIS app pools, MSI
install/uninstall, `Configuration.exe`, Windows services, SQL, HTTP, PowerShell, snapshots).

Its engine was **copied** from `TestAuto.Utilities`/`TestAuto.Shared` @ commit `fb144dc7`, namespaces
rewritten to `CrewChief.Engine.*`; **class/member names were kept unchanged** so step JSON stays
compatible and the copy stays diffable against its source. Persistence is **files-only — no database**
(a step's own SQL step may hit any DB, but CrewChief itself stores nothing in one). See memory
[[project_crewchief_standalone]].

## When to Use
- Starting any task under `CrewChief\` and needing the lay of the land.
- Deciding which of the 6 projects a change belongs in.
- Adding a NuGet package (central package management is CrewChief-local — read the isolation note).
- Adding a Web endpoint or reasoning about who can reach it (no-auth posture).
- Explaining build conventions (flattened output, inherited strong-name signing, warnings-off).

## The 6-project map

Dependency direction is clean and acyclic: **`Web|Cli → Data → Engine`**. Engine depends on neither
Data nor the surfaces.

| Project | Role (one line) | Deep-dive skill |
|---|---|---|
| `CrewChief.Cli` | `crewchief` console; verbs `run`/`list`/`history`/`resume` + secrets bootstrap; exit codes 0/1/2/3; `AssemblyName=crewchief` | [[crewchief-cli]] |
| `CrewChief.Data` | Files-only persistence (steps/workloads/runs/reference KV), resume/outcome mappers, transfer bundles, two-layer secrets, SMTP notify | [[crewchief-file-persistence]], [[crewchief-secrets]] |
| `CrewChief.Engine` | Step DTOs, `IStepExecutor` implementations, `UtilityOrchestrator`/`WorkloadEngine`, templating, `StepTypeRegistry`/`UtilityStepConverter` | [[crewchief-executor-pattern]], [[crewchief-step-type-model]] |
| `CrewChief.Web` | Blazor Server UI; hosts `IWorkloadRunCoordinator`, help system, secrets console | [[crewchief-web-ui]] |
| `CrewChief.Tests.Unit` | Fast unit + bUnit tests; executor-seam fakes, loopback HTTP, fake console/clock/DPAPI | [[crewchief-testing]] |
| `CrewChief.Tests.Integration` | Live-SQL / remote-lab tests, gated + `Assert.Inconclusive` when prereqs absent | [[crewchief-testing]] |

`Web` and `Cli` are **peer surfaces** — neither references the other; both go through the same Data +
Engine services, which is what makes a step/workload/run identical across surfaces. `WorkloadEngine`
runs one step per `UtilityOrchestrator.ExecuteScenarioAsync` call for live per-step progress and
between-step cancellation. Step dispatch is polymorphic on the JSON `type` field via
`UtilityStepConverter`, backed by the shared `StepTypeRegistry` — **19 step types**, with no
discrepancy to reconcile: the registry's static ctor holds 19 `Register<…>` entries
(`CrewChief.Engine\Steps\StepTypeRegistry.cs:54-72`), DI registers 19 `IStepExecutor`s
(`CrewChief.Engine\EngineServiceCollectionExtensions.cs:32-90`), and `CrewChief\README.md:71` says
"CrewChief runs **19** step types". Email, IisReset, and DatabaseOperations are ordinary registry
entries (`StepTypeRegistry.cs:72`, `:71`, `:65`) — not extras counted only by the DeveloperPack.

## Tech-stack mandates (verified from `Directory.Packages.props`)

Central package management is on (`ManagePackageVersionsCentrally=true`). **The `Directory.Packages.props`
that governs CrewChief is CrewChief's own** (`CrewChief\Directory.Packages.props`) — NuGet uses the
**nearest** file, so CrewChief's versions are **fully isolated from the repo root**. Bumping a root
package version does NOT change CrewChief, and vice-versa. Pinned versions actually present:

| Package | Version | Mandate |
|---|---|---|
| Newtonsoft.Json | 13.0.4 | JSON library — **NOT** System.Text.Json |
| Serilog (+ AspNetCore 3.4.0, Sinks.Console 6.1.1, Sinks.File 7.0.0) | 4.3.1 | Logging — **NOT** MEL `ILogger` (see [[crewchief-logging]]) |
| Radzen.Blazor | 7.1.7 | UI component library |
| Microsoft.Data.SqlClient | 7.0.2 | ADO.NET data access — **NO Entity Framework** |
| System.Security.Cryptography.ProtectedData | 10.0.9 | DPAPI CurrentUser wrap for sealed secrets — the **one** extra package the brief permits |
| Microsoft.Extensions.* (Config/DI/Http/Caching) | 10.0.9 | .NET 10 aligned |
| Microsoft.Extensions.Hosting.WindowsServices | 10.0.9 | Lets the Web host run under the SCM as a Windows Service (see Windows-Service hosting below) |
| bunit.web 1.40.0 · Moq 4.18.4 · MSTest.* 3.1.1 · Microsoft.NET.Test.Sdk 17.3.2 · coverlet.collector 6.0.2 | — | test stack |
| Microsoft.Web.Administration 11.1.0 · System.ServiceProcess.ServiceController 10.0.9 · YamlDotNet 16.2.0 · MD2RazorGenerator 1.2.2 | — | box-prep + help-doc tooling |

These are the same mandates as the parent project — see [[testauto-tech-stack]].

## Build conventions

- **`CrewChief\Directory.Build.props`** chains to the repo-root props via
  `GetPathOfFileAbove('Directory.Build.props', ...)` — without that explicit import the nearest-file
  rule would drop the root's settings. From the root it **inherits strong-name signing**
  (`ProfiseeSN.snk`, `SignAssembly=true`) and global **`WarningLevel 0` / `TreatWarningsAsErrors false`**
  (`NoWarn` adds CS1591, CS8002).
- **Flattened output**: `AppendTargetFrameworkToOutputPath=false` → binaries land in `bin\Debug\`,
  **not** `bin\Debug\net10.0\` (applies to every project under `CrewChief\`).
- **csproj conventions**: `TargetFramework=net10.0`, `Nullable enable`, `ImplicitUsings enable`,
  `InvariantGlobalization=true`; the CLI sets `OutputType=Exe` and `AssemblyName=crewchief`.

See [[dotnet-project-structure]] for the wider repo layout conventions.

## Windows-Service hosting mode (`CrewChief.Web\Program.cs`)

The Web host runs **both** interactively and as a Windows Service from the **same binary** (installer's
"Install as Windows Service" option). The wiring lives in the first ~24 lines of `Program.cs`:

- `builder.Host.UseWindowsService(options => options.ServiceName = "CrewChief")` — a **no-op outside the
  SCM**, so an interactive launch is unaffected. Requires the `Microsoft.Extensions.Hosting.WindowsServices`
  package (tech-stack table above).
- `WindowsServiceHelpers.IsWindowsService()` detects the SCM launch into a `runningAsService` flag.
- **Content-root pinning**: under the SCM the process starts in `System32`, which would silently relocate
  `data\` and `logs\`. So `WebApplicationOptions.ContentRootPath = runningAsService ? AppContext.BaseDirectory
  : null` — service mode pins the content root to the exe folder; interactive mode keeps the default.
- **Secrets follow the mode**: `runningAsService` is passed straight into
  `SecretsRootResolver.Resolve(builder.Configuration[SecretsRootResolver.ConfigKey], runningAsService)`, so
  service mode drives the **machine-shared** secrets default (`%ProgramData%\CrewChief\secrets`, DPAPI
  LocalMachine scope) instead of the interactive per-user `%APPDATA%\CrewChief`. The installer sets
  `CREWCHIEF_SECRETS_FOLDER` machine-wide so the **CLI** (which always passes `runningAsWindowsService:
  false`) still resolves the same store. See [[crewchief-secrets]] for the full precedence chain.

> [!warning] Content-root pinning is NOT sufficient — the CWD must move too
> Serilog resolves a **relative sink path against the process CWD**, not the content root, and the SCM sets
> the CWD to `%SystemRoot%\System32`. `Program.cs:47` therefore calls
> `Directory.SetCurrentDirectory(AppContext.BaseDirectory)` before any Serilog configuration.
>
> The blast radius is wider than logging: **every step that shells out without an explicit
> `workingDirectory` inherits this CWD** — `IProcessRunner`, `CommandLineExecutor`, `CurlExecutor`,
> `PowerShellScriptExecutor`, `PowerShellRestExecutor`, `CLUExecutor`, `ConnExExecutor`. Any workload
> writing to a bare relative path behaves differently under the service than it did interactively.

- **Persisted DataProtection key ring** (`Program.cs:263-266`):
  `AddDataProtection().PersistKeysToFileSystem(<dataFolder>/dataprotection-keys).ProtectKeysWithDpapi(protectToLocalMachine: true).SetApplicationName("CrewChief")`.
  Without it every service restart minted a fresh ring and threw
  `AntiforgeryValidationException … key {GUID} was not found in the key ring` on the next form post.
  `SetApplicationName` pins the isolation key to a constant so a content-root move does not orphan the ring,
  and `protectToLocalMachine: true` means the ring survives a service-account change. It deliberately does
  **not** live under `%ProgramData%\CrewChief` — that folder's ACL belongs to the secret store, and putting
  the ring there would widen that folder's write surface.
- `public partial class Program { }` (`:455`) is appended so `WebApplicationFactory<Program>` can boot the
  real host from `CrewChief.Tests.Integration`.

## Composition-root registration LISTS live in `AddCrewChief*` extensions, never inline

Three subsystems now register through their own extension method — `AddCrewChiefSecretsSubsystem` (`:274`),
`AddCrewChiefSecretRevealServices` (`:328`), `AddCrewChiefCapabilitySubsystem` (`:342`) — and each has a
matching `*CompositionRootTests`.

The rule exists because **every service in those lists is resolved at *activation* time**: a Blazor
`[Inject]`, a `UseMiddleware<T>`, a render-path dependency. A missing registration therefore **compiles
clean and passes every test that `new`s the type up directly**, then takes the Windows service down on first
request. The guard test must build its provider from *the same extension method the app calls* — a
hand-copied registration list would recreate exactly the drift it exists to catch.

Note `AddCrewChiefCapabilitySubsystem` lives in **CrewChief.Engine**, not `CrewChief.Web/Services/`, unlike
the two secrets extensions: `CrewChief.Cli` must share it and cannot reference `CrewChief.Web`.

## Security posture (durable gotcha)

**There is no authentication or authorization anywhere in CrewChief.** A grep for
`UseAuthentication` / `AddAuthentication` / `[Authorize]` / `UseAuthorization` across the project
matches **only DeveloperPack docs — never any code**. And `CrewChief.Web\Program.cs` binds **all
interfaces** via `k.ListenAnyIP(httpPort)` / `k.ListenAnyIP(httpsPort, ...)` on the ports from
`WebUI:HttpPort`/`HttpsPort` (defaults 5030/5031).

> **"Operator" == anyone with network reach to :5030/:5031.** Any endpoint you add is reachable by
> anyone who can route to the box, unauthenticated, and every step type can run processes / SQL / HTTP
> on the host. This is documented as **ADR-009** (`DeveloperPack\10_ADR_009_NoAuthAllInterfaceBinding.md`)
> and is the still-open **BL-1 ("No-auth RCE")** backlog item
> (`DeveloperPack\12_QuestionsAndBacklog.md`). Treat CrewChief as an isolated single-operator box until
> that gate lands.

## Related
- Secrets rename history (Encryption Secrets / Local Secrets): memory [[project_crewchief_tier_rename]]
- Sibling skills: [[crewchief-cli]] · [[crewchief-file-persistence]] · [[crewchief-secrets]] · [[crewchief-executor-pattern]] · [[crewchief-web-ui]] · [[crewchief-testing]] · [[crewchief-logging]] · [[crewchief-step-type-model]]

## Sources
- `CrewChief\Directory.Packages.props`
- `CrewChief\Directory.Build.props`
- `Directory.Build.props` (the inherited repo-root props)
- `CrewChief\CrewChief.Cli\CrewChief.Cli.csproj`
- `CrewChief\CrewChief.Web\Program.cs`
- `CrewChief\CrewChief.Web\DeveloperPack\01_ArchitectureOverview.md`
- `CrewChief\CrewChief.Web\DeveloperPack\10_ADR_009_NoAuthAllInterfaceBinding.md`
- `CrewChief\CrewChief.Web\DeveloperPack\12_QuestionsAndBacklog.md`
- `CrewChief\README.md`
