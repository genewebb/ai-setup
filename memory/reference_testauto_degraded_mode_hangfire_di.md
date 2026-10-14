---
name: reference_testauto_degraded_mode_hangfire_di
description: "When Hangfire is skipped TestAuto's unconditional Hangfire-dependent registrations fail at ACTIVATION, killing scenario enumeration and Blazor circuits - fixed with factory registrations plus null objects"
metadata: 
  node_type: memory
  type: reference
  originSessionId: b3eaccad-5bf3-41b5-8aea-971b41e625af
  modified: 2026-08-11T02:15:24.291Z
---

**Third instance of the same defect class: a service registered unconditionally whose dependency only exists when `AddHangfireCore` ran.** Verified on SMVMTR2 2026-08-10 (v1.35.9719.33351). Trigger was `HangfireDB is configured but unusable: Login failed for user 'SMVMTR2\ProfAdmin'` — the service runs under a LOCAL account, so an Integrated Security connection string presents a login SQL does not have.

Two failures, both at DI ACTIVATION rather than at use:

| Registration | Missing dependency | Symptom |
|---|---|---|
| `MetricsServiceExtensions.cs:59` `IHangfireReader`→`HangfireReader` | `Func<IStorageConnection>` (registered only in `HangfireCoreServiceExtensions.cs:69`) | `MetricBatchSummaryAggregator..ctor:38` resolves it eagerly, so **`GetServices<IScenario>()` throws** — 15+ call sites. Logged as `Failed to load scenario names via resolver`; scenario dropdowns silently empty. |
| `WebModuleRegistrar.cs:123-124` `ITestAutoBackgroundJobClient`→`HangfireBackgroundJobClientAdapter`, `ITestAutoMonitoringApi`→`HangfireMonitoringApiAdapter` | `Hangfire.IBackgroundJobClient` / `JobStorage` | `CircuitUnhandledException` — the Blazor page DIES. 5 services inject these (ScenarioWebService, MetricsWebService, TestAutoJobMonitoringService, ScenarioExecutionMonitoringService, ScenarioEnqueueService), so most of the monitoring UI. |

Diagnostic tell: `[STARTUP] Failed to resolve all scenarios (some may require external dependencies): Unable to resolve service for type 'System.Func\`1[Hangfire.Storage.IStorageConnection]'` appears at startup, well before any user hits a page.

Fixes 2026-08-10 (working tree; user rebuilds; unit suite 883 pass / 1 skip / 0 fail):
- Both sites converted to **factory registrations** so the interface always resolves and the decision is deferred until after `RegisterAllServices` publishes `HangfireAvailability`.
- New `TestAuto.DependencyInjection\ServiceExtensions\HangfireUnavailableFallbacks.cs`: `UnavailableBackgroundJobClient` (commands THROW naming `ReasonDisabled`) and `UnavailableMonitoringApi` (queries return EMPTY so pages render "no jobs"). Read/write asymmetry is deliberate — silently accepting an enqueue that will never run is worse than an error.
- `IHangfireReader` keeps its ctor contract; the substituted `Func<IStorageConnection>` throws with the reason on first actual use. Note `Func<Hangfire.Storage.IStorageConnection>` must be fully qualified in `MetricsServiceExtensions` — no `using Hangfire.Storage` there.

**Rule this establishes**: never register a type whose ctor takes a Hangfire service unless the registration itself is gated on `HangfireAvailability`, or the dependency is resolved via `GetService` inside a factory. `GetService<IHangfireReader>()` does NOT help — it returns null only when the service is unregistered, not when its dependency chain fails.

~~Latent bug spotted~~ FIXED 2026-08-10 late: `MetricBatchSummaryAggregator..ctor` resolved `IHangfireReader` (an `IDisposable` transient) from a `using var scope` disposed at ctor exit, then stored the instance — use-after-dispose. Fix: no scope; the type is a SINGLETON so its provider is the root — resolve directly, instances live for the app lifetime. Rule: a singleton must never resolve its stored fields from a ctor-local scope.

## Sequel: startup must NEVER activate scenarios (fixed same day)

Removing the HangfireReader throw let scenario enumeration walk further and exposed the real sequencing defect: **`GetServices<IScenario>()` at startup opened the Profisee platform DB on a remote SQL host, to print a log line.** Chain: `ScenarioDisplayExtensions.cs:24-26` → `ScenarioName` is an INSTANCE property so DI activates all ~25 scenarios → one graph resolves `IMetadataCache` → `CachingServiceExtensions.cs:36-41` eagerly resolves `ICdpService` and dereferences `cdpService.OperationContext.MetadataCache` → `CdpService` ctor (NuGet `Profisee.Platform.Utilities.Cdp`) opens `ProfiseeAppSettings:ProfiseeDBConnection` → `Error 4060: Cannot open database "Profisee"` → 8 Polly retries, all before Kestrel binds. `ReferenceDataCache.LoadScenarioNames()` repeated it during the cache preload, where the catch turned it into "Failed to load scenario names via resolver" and silently empty dropdowns.

Not a new regression: under the old console host running as a DOMAIN account that connection succeeded silently, so the boot-time dependency was always there and invisible. The service migration changed the identity (local `SMVMTR2\ProfAdmin` cannot do Integrated Security to a remote SQL), not the sequence.

**The codebase already had the answer**: `ScenarioTypeRegistry.BuildTypeMap` reads each name from `Activator.CreateInstance(type, true)` — parameterless, no DI, no external dependency. Fix = new `ScenarioTypeRegistry.GetScenarioNames()` (keys of `_typeMap`, sorted), used by both `ScenarioDisplayExtensions.DisplayRegisteredScenarios` and `ReferenceDataCache.LoadScenarioNames`; both try/catch blocks deleted because nothing can fail. Build clean, unit suite 883 pass / 1 skip.

**Rule**: never read scenario metadata by activating the container. Registry only contains scenarios carrying `[ScenarioTypes]` — a missing attribute is the bug to fix, not a reason to go back to `GetServices<IScenario>()`.

Still eager, NOT fixed: the `IMetadataCache` singleton factory itself. Any future startup consumer re-opens SQL. Also unverified: whether the NServiceBus `Services.Monitor` endpoint hits `MonitorDB` at startup once secrets are loaded (`MonitorServiceExtensions.cs:33-40` skips registration only when MonitorDB is absent).

## The actual root cause: committed appsettings shipped `Data Source=.`

`TestAuto.Web/appsettings.json:19-21` shipped three hardcoded platform connection strings:
`ProfiseeDBConnection`, `MessagingDBConnection`, `MonitorDbConnection` — all
`Data Source=.;Initial Catalog=Profisee;Integrated Security=True;Persist Security Info=True;Pooling=True;Max Pool Size=100;Encrypt=False`.

`.` is the LOCAL default instance. On a TestAuto box that instance has only system databases, so any consumer got `Error 4060: Cannot open database "Profisee"`. **The 4060 was never against smvmdb2** — an earlier hypothesis in this session guessed a remote host and recommended SQL auth to smvmdb2; the appsettings value is direct evidence and it says `.`. Don't repeat that guess.

Second consequence, worse: `MonitorServiceExtensions.cs:36` skips monitor registration only when the value `IsNullOrWhiteSpace`. A committed non-empty default means it NEVER skips, so `AddMonitorCommander`'s send-only NServiceBus endpoint (an `IHostedService`) registered and connected at BOOT on every run, secrets or not.

Fix: all three set to `""` in `TestAuto.Web/appsettings.json`, with a `_PlatformDbConnectionsNote` key recording why. Verified safe — every reader tolerates empty exactly as missing: `Context.cs:36` and `LoggingServiceExtensions.cs:31` both end `?? string.Empty`; `MonitorServiceExtensions.cs:34-36` guards with `IsNullOrWhiteSpace`; `RegisterAllServices.cs:668,672` only log them; `MessagingDBConnection` has no C# reader in this repo. Note `installer/stage/web/appsettings.json` and `bin/**` carry copies — staging/build outputs, not sources.

**Operating invariant (user, 2026-08-10)**: startup must work with NO secrets; once secrets exist anything is possible, and a direct DB connection is legitimate only when something actually needs one. Boot must never open a database.

## `CdpService`'s CONSTRUCTOR queries SQL (the load-bearing fact)

`Profisee.Platform.Utilities.Cdp.Services.CdpService..ctor(IContext)` runs `DoesModelExist()` → `DoesTableExists()` → `executeScalar()` against the Profisee platform DB. So **resolving `ICdpService` — or `IMetadataCache`, whose factory resolves it — is a database round trip, not a lookup.** Any type taking either as a CONSTRUCTOR dependency opens SQL merely by being activated. Same construction, two faces: with `Data Source=.` present it threw `4060 Cannot open database "Profisee"`; with the string blank, `InvalidOperationException: The ConnectionString property has not been initialized`.

Second incident 2026-08-10 (v1.36, after Hangfire was working): `Hangfire.CreateBatchFailedException` — `BatchJobOrchestrator.StartBatchProcessingCore` → inside `Hangfire.BatchJob.StartNew` callback → `ScenarioServiceExtensions.<AddScenarioManagementServices>b__1_4` → a manager ctor → `CachingServiceExtensions.<AddCachingServices>b__0_0` → `CdpService..ctor` → throw. **The batch never started**; the scenario died at creation.

Fixed by `Lazy<>` (5 files, build clean, unit 786 pass / 1 skip on `bug/testing_updates/genewebb`):
- `CachingServiceExtensions` + `CdpServiceExtensions`: added `AddTransient(sp => new Lazy<IMetadataCache>(...))` and the `Lazy<ICdpService>` twin.
- `ScenarioQueueLoadManager`, `ScenarioEntityTestDataManager`, `ScenarioDomainTestDataManager`: ctors take `Lazy<IMetadataCache>`/`Lazy<ICdpService>`, exposed as private `Metadata`/`Cdp` properties (named to avoid shadowing the `CdpService` type). All three used them only inside methods, so nothing else changed. Public interfaces untouched.

`IContext → Context` (`ContextServiceExtensions.cs:15`); `Context.ConnectionString` (`Context.cs:36`) = `ProfiseeAppSettings:ProfiseeDBConnection ?? string.Empty`. `CdpContext.cs` is a SECOND `IContext` implementation reading `settings.ServiceDBConnection` — **not registered, dead code**; don't be misled by it.

**Rule**: never take `ICdpService` or `IMetadataCache` as a constructor dependency. Use `Lazy<>`.

Earlier note, now superseded — `IMetadataCache`/CDP needed no further change: its singleton factory runs on FIRST RESOLUTION, and the only boot-time resolver was scenario activation. Remaining resolvers are `IScenarioQueueLoadManager` / `IScenarioEntityTestDataManager` / `IScenarioDomainTestDataManager`, reached during a scenario run — the legitimate case. CDP is unused scaffolding kept for future use; do not refactor it to `Lazy<>` without cause.

Also folded in: `DisplayRegisteredScenarios` was printing a 3rd and 4th copy of names already logged by the reflection-only assembly scan at `ScenarioManagementServiceExtensions.cs:133-145`. Its only unique property was proving DI resolvability — which is what opened SQL. Now one aggregate line plus a new `ScenarioTypeRegistry.GetScenarioTypesMissingAttribute()` warning (a scenario lacking `[ScenarioTypes]` runs but breaks CustomParms-editor and metric-type lookups).

Environment facts for this box: `smvmdb2:1433` is open and `SMVM2:1433` closed (SMVM2 is app tier only) — relevant only if a scenario deliberately targets the platform DB. SMVMTR2's local instance holds only system DBs. `SecretStorageHelper.IsSensitiveKey` (`:237-242`) matches KEY names only against apikey/password/pwd/clientid/secret/token/thumbprint — so a `Password=` embedded in `ProfiseeDBConnection`/`HangfireDB` displayed UNMASKED on /secrets. FIXED 2026-08-10 late: `MaskEmbeddedCredentials` in `MaskSensitiveValues`' else-branch masks `(?:password|pwd)\s*=\s*[^;"]+` case-insensitively inside any string value; Data Source / Initial Catalog / User ID stay visible for diagnostics. 3 tests via `GetDisplayText` end-to-end (unit suite 886 pass).

Related: [[project_testauto_secrets_persistence_diagnosis]] (gap #2, the earlier instance), [[reference_testauto_entra_p2p_cert_lockout]], [[reference_smvm2_profadmin_lockout]], [[project_smvm2_sql_login_lockout_orphan]]
