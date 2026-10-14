---
name: dotnet-service-registration
description: >
  RegisterAllServices host-level startup entry point in TestAuto.DependencyInjection.
  Use when understanding the full startup registration order, diagnosing degraded-start
  behavior (missing secrets, missing Hangfire, skipped plugins), adding a new top-level
  registration phase, or tracing which guard (hasMinimumConfig, hasHangfireConfig) is
  suppressing a registration. For the IModuleRegistrar plugin pattern itself, see
  [[testauto-modular-di]].
---

Repo: speed-merchants (paths below are repo-relative)

# Service Registration — Host Entry Point

> **Scope**: speed-merchants (`TestAuto.DependencyInjection`)
> **Source**: `TestAuto.DependencyInjection/ServiceExtensions/RegisterAllServices.cs`
> **Related**: [[testauto-modular-di]] — documents `IModuleRegistrar` and `RegisterAllModuleServices`

`RegisterAllServices` is the single call site that bootstraps every service for TestAuto. It returns `(IServiceCollection Services, IConfiguration Configuration)` — the enriched configuration (with secrets merged in) must be retained by the caller.

---

## Call Signature

```csharp
var (services, configuration) = services.RegisterAllServices(
    configuration,
    includeWebServices: false,   // true when hosting the Web UI
    skipEntityLoad: false,       // true if secrets were injected during first-time setup
    configureAdditional: null    // optional IConfigurationBuilder delegate run after secrets load
);
```

---

## Startup Sequence (in order)

| Step | What happens | Guard |
|------|-------------|-------|
| 1 | Register `IMasterPasswordManager` + `ISecretEncryptionService` (no config needed) | — |
| 2 | `LoadEntitySecrets` — decrypt and merge machine secrets into `IConfiguration` | skipped if `skipEntityLoad` |
| 2a | Log all connection strings (Data Source + Catalog only) | — |
| 3 | Validate `hasMinimumConfig` (`RestClients:ScenarioMgt:BaseUrl` + `ApiKey` present) — `:93` | — |
| 3a | Validate `hasHangfireConfig` — `!string.IsNullOrEmpty(configuration.GetConnectionString("HangfireDB"))` — `:103` | — |
| 4 | `AddHangfireCore` — `:108` | **`hasHangfireConfig`** (not `hasMinimumConfig`) |
| 5 | `IScenarioResolver` (always), `RestUrlManagement` — `:116`-`:119` | `hasMinimumConfig` for `RestUrlManagement` only |
| 6 | `AddLoggingServices`, `AddCachingServices`, `AddRulesEvaluatorServices`, `AddContextServices`, `AddCdpServices`, `AddMonitorServices`, `AddODataTranslatorServices`, `AddVerbServices` — `:123`-`:130` | — (always run) |
| 6b/6c | `AddRestServices` + `AddMetricsServices` — `:138`, `:141`. **Else-branch**: bare `services.AddHttpClient()` so the bootstrap page still works — `:147` | `hasMinimumConfig` |
| 6d | `services.AddSingleton<IReferenceDataCache, ReferenceDataCache>()` — shared across all projects — `:151` | — (always runs) |
| 6e/6f | `RegisterPlugins` + `AddScenarioManagementServices` — `:157`-`:158` | `hasMinimumConfig` |
| — | `RegisterAllModuleServices` — fires all `IModuleRegistrar` from loaded assemblies — `:167` | — (always runs) |
| 7 | `AddHangfireServers` + `AddHangfireRecurringJobs` — `:172`, `:175` | **`hasHangfireConfig`** (not `hasMinimumConfig`) |
| 8 | `SecurityUtility` — `:179` | — (always runs) |
| 8a | `MachineSecretService` + its 4 interfaces (`IMachineSecretService`, `ISecretImportExportService`, `ISecretRotationService`, `IConnectionTestService`) — `:186`-`:198` | `hasMinimumConfig` |
| 9 | `AddWebServices` — `:204` | `includeWebServices` |

**`RegisterAllModuleServices` always runs**, even without minimum config — plugin registrars that do not need REST will still fire.

### Two independent guards — don't conflate them

`hasMinimumConfig` and `hasHangfireConfig` are computed separately and gate disjoint sets of
registrations:

- **Hangfire (both core *and* servers/recurring jobs) is gated *only* by `hasHangfireConfig`** —
  i.e. purely by the presence of the `HangfireDB` connection string. `hasMinimumConfig` has **no**
  effect on Hangfire. A host with valid ScenarioMgt REST credentials but no `HangfireDB` starts
  with zero Hangfire; conversely a host with `HangfireDB` but no REST config still gets Hangfire
  core and servers.
- When `hasHangfireConfig` is false the code logs
  `"Skipping Hangfire initialization - HangfireDB connection string not configured"` (`:112`) —
  grep Seq for that exact string to confirm which guard tripped.
- `IReferenceDataCache` (step 6d) is **ungated** — it registers even in a fully degraded start, so
  a missing `IReferenceDataCache` at runtime is never a config-degradation symptom; look for a
  wrong host/assembly instead.

---

## Secrets Loading (`LoadEntitySecrets`)

Queries the `TestAutoSecrets` entity in the ScenarioMgt Profisee instance for:

```
[IsActive] eq 'Y' AND [MachineName] eq '{Environment.MachineName}'
```

Uses a raw `HttpClient` (not `IRestClient` — DI is not available yet). Decrypts the `SecretData` attribute via `SecretStorageHelper.LoadDecryptAndDecompress`, flattens nested JSON to colon-separated keys (e.g., `RestClients:Profisee:BaseUrl`), then merges over the existing `IConfiguration` via `ConfigurationBuilder.AddInMemoryCollection`.

Always sets `WebUI:ExecutionMachine` to `Environment.MachineName` after flattening.

### Graceful degradation

Any failure (HTTP error, timeout, missing record, encryption not configured) logs a warning and returns the original config unchanged. The app starts in a **degraded state**: REST, metrics, plugins, and Hangfire are skipped due to failed `hasMinimumConfig` checks.

---

## Degraded-Start Checklist

If features are missing at runtime:

1. Check startup logs for the `SECRETS LOADING` box — did it print `ACTIVE SECRETS RECORD LOADED`?
2. If not: verify the `TestAutoSecrets` entity has a record with `IsActive=Y` and `MachineName=<this machine>`.
3. Check `hasMinimumConfig`: `RestClients:ScenarioMgt:BaseUrl` and `RestClients:ScenarioMgt:ApiKey` must be non-empty after secrets load.
4. Check `hasHangfireConfig`: `ConnectionStrings:HangfireDB` must be non-empty. Hangfire core AND servers are both skipped if absent — and *only* this guard controls them, so a Hangfire outage is never explained by `hasMinimumConfig`.
5. Verify plugin assemblies are in `Plugins/` — `RegisterPlugins` (step 6e, `RegisterAllServices.cs:157`) only fires when `hasMinimumConfig` is true.
6. `IReferenceDataCache` is registered unconditionally (`:151`), so its absence points at a host/assembly problem, not a degraded start.

---

## Sources

- `TestAuto.DependencyInjection\ServiceExtensions\RegisterAllServices.cs`
- `TestAuto.AutoRegistration\Interfaces\IModuleRegistrar.cs`
