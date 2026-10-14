---
name: testauto-debugging-common-failures
description: >
  Common TestAuto failure patterns, root causes, and fixes: DI registration errors for
  runtime-connection-string services, scenario execution hangs, workflow advancement
  failures, and scenario-not-found errors. Use when triaging runtime exceptions,
  investigating CI failures, or reviewing new scenario code for DI anti-patterns.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Debugging: Common Failures

> **Scope**: speed-merchants (TestAuto.Web + TestAuto.Matching)
> **Source**: bugs/matching-activity-monitor-service-di-registration-fix.md

---

## Failure 1: Service Not Registered in DI (Runtime Connection String Services)

### Symptom

```
System.InvalidOperationException:
No service for type 'TestAuto.Matching.Interfaces.IXxxService' has been registered.
```

### Root Cause

Services that require a **runtime connection string** from `ScenarioConfiguration` cannot be registered in DI at startup — the connection string isn't known yet. Attempting `serviceProvider.GetRequiredService<IXxxService>()` in a constructor fails at runtime.

### DI Registration Decision Tree

```
Does the service constructor require a connection string from ScenarioConfiguration?
├─ YES → DO NOT register in DI
│         - Declare as nullable field: private IMyService? _myService;
│         - Create in ApplyConfiguration: _myService = new MyService(connStr, _logger);
│         - Add null check before use in ProcessBatchAsync / PollForCompletionAsync
│         - Document in constructor comment and ModuleRegistrar
│
└─ NO  → Register in DI normally
          - Used by all projects? → RegisterAllServices / AutoRegistration
          - Used by one project? → {Project}ModuleRegistrar
          - Web-specific? → AddWebServices / WebModuleRegistrar
```

### Services Requiring Runtime Connection Strings (TestAuto.Matching)

Documented in the `MatchingModuleRegistrar.cs` comments (~lines 35–48, which call out `IRecordMixManager`, `IRecordPoolRepository`, `IMatchingCountersService`, and `IMatchingStrategyConfigurationService`; the registrar itself registers `MonitorActivityCollector`) — do NOT register these in DI:

Listed most-hit first — `IRecordPoolRepository` and `IRecordMixManager` are the two you will
actually trip over, and they are the only two the registrar's comment block names up front
(`MatchingModuleRegistrar.cs:35-37`). At HEAD 4c367fe6 they are also by far the most-referenced:
`IRecordPoolRepository` 22 hits, `IRecordMixManager` 12, versus 6–7 each for the rest.

| Interface | Connection Used | How to Instantiate |
|---|---|---|
| `IRecordPoolRepository` | Matching database | `new RecordPoolRepository(matchingConnStr, recordPoolConfiguration, _logger)` |
| `IRecordMixManager` | Requires REST client + repository | Via factory in `ApplyConfiguration` |
| `IMatchingCountersService` | Model database | `new MatchingCountersService(...)` |
| `IMatchingStrategyConfigurationService` | Matching database | `new MatchingStrategyConfigurationService(...)` |
| `IMatchingActivityMonitorService` | Monitor database | `new MatchingActivityMonitorService(matchingConnStr, _logger)` — note this one is **not** named in the registrar comments, so there is no in-repo breadcrumb warning you off DI |

### Correct Pattern

Shown with `IRecordPoolRepository` / `IRecordMixManager`, the common case. The same shape applies to
every interface in the table above.

```csharp
// Fields — nullable, NOT readonly
private IRecordPoolRepository? _recordPoolRepository;
private IRecordMixManager? _recordMixManager;

// Constructor — document that these are NOT from DI
// Note: IRecordPoolRepository and IRecordMixManager are NOT registered in DI.
// They require a runtime connection string from ScenarioConfiguration and are
// created per-scenario in ApplyConfiguration.

// ApplyConfiguration — create with runtime connection string
var matchingConnStr = DatabaseConnectionStringHelper.GetConnectionString(
    cfg, "Matching", _applicationConfiguration);
_recordPoolRepository = new RecordPoolRepository(matchingConnStr, recordPoolConfiguration, _logger);
_recordMixManager     = /* factory using the REST client + _recordPoolRepository */;

// Before use — null guard
if (_recordPoolRepository == null)
    throw new InvalidOperationException(
        $"{ScenarioName}: service not initialized. Ensure ApplyConfiguration was called.");
```

> The `MatchingActivityMonitorService` variant of this bug (the original write-up this skill grew
> from) is the *rarer* instance of the same pattern — reach for it only after ruling out the
> record-pool / record-mix services above.

Connection string helper: `TestAuto.Scenarios/Helpers/DatabaseConnectionStringHelper.cs`

### How to Find Other Instances of This Bug

```bash
git grep -n "GetRequiredService<I.*Service>" | grep -v "// Note:"
```

Any hit that doesn't have the "Note: NOT registered in DI" comment is a candidate for this bug pattern.

---

## Failure 2: Scenario Stuck in "Running" Status

See `testauto-workflow-execution` skill — Troubleshooting section.

**Quick checklist**:
1. Does `WorkloadExecution` exist for the `WorkloadExecutionCode`? (Check SQL / Hangfire dashboard)
2. Is `WorkflowMonitorJob` running? (Hangfire → Recurring Jobs → job id **`workflow-monitor`**)
   - It is a **minute**-granularity cron, not seconds. `WebModuleRegistrar.RegisterWebRecurringJobs`
     builds `$"*/{intervalMinutes} * * * *"` from `WorkflowMonitor:IntervalMinutes`
     (`TestAuto.Web/AutoRegistration/WebModuleRegistrar.cs:144-146`), registered on the
     `scheduled` queue in **UTC**.
   - **Shipped value is `1` minute** (`TestAuto.Web/appsettings.json:60-61`); the in-code fallback
     if the key is absent is `5`. So expect a sweep about once a minute — if you are waiting only
     a few seconds for a workflow to advance, that is normal, not a hang.
   - The job is skipped entirely when `FeatureFlags:EnableWorkflowMonitor` is `false`
     (`WebModuleRegistrar.cs:141`; shipped `true` at `appsettings.json:177`). The disabled-branch
     log line used to misreport the key as `Features:EnableWorkflowMonitor`; it now names
     `FeatureFlags:EnableWorkflowMonitor` correctly (`WebModuleRegistrar.cs:188`), so the log and
     the key agree.
3. Did the Hangfire job for the scenario crash? (Check Seq logs, LogTag: `BatchOrchestrator`)

---

## Failure 3: Workflow Never Advances to Next Step

**Quick checklist**:
1. `TestAutoWorkflowExecutionDetail.WorkloadExecutionCode` is populated (not null)?
2. `WorkflowMonitorJob` is scheduled? (Hangfire Recurring Jobs)
3. Next detail has status `Pending`?

Diagnostic SQL:
```sql
SELECT ExecutionOrder, ExecutionStatus, WorkloadExecutionCode, StartTime, EndTime
FROM TestAutoWorkflowExecutionDetail
WHERE WorkflowExecution = '<ExecutionCode>'
ORDER BY ExecutionOrder;
```

---

## Failure 4: "Scenario Not Found" Error

**Root causes** (in order of likelihood):
1. Scenario assembly (`TestAuto.Xxx.dll`) not in the Plugins directory
2. `ScenarioConfiguration.ScenarioName` doesn't match the registered class name exactly
3. `ScenarioData` is empty or corrupted in `TestAutoScenarios`

Check Seq startup logs for: *"Scanning X assemblies for IScenario implementations"* — verify your scenario is listed.

---

## Failure 5: Startup Failure / Degraded State

TestAuto must **not** crash on startup failures (DB unavailable, `HttpClient` timeout in `LoadEntitySecrets`).

**Correct pattern**: catch and log startup exceptions; surface them in `MainLayout` banners via `IAppStartupStatus` singleton. **Never re-throw startup exceptions.**

If the app crashes on startup instead of showing a banner, look for `throw` in startup code paths.

---

## Where to Look First

| Problem area | Where to look |
|---|---|
| DI registration errors | Exception message → check ModuleRegistrar for the interface |
| Hangfire job failures | Hangfire Dashboard → Jobs → Failed |
| Workflow execution state | SQL: `TestAutoWorkflowExecution` + `TestAutoWorkflowExecutionDetail` |
| Scenario execution state | SQL: `WorkloadExecution` table |
| Startup / configuration | Seq logs, filter by LogTag `Startup` or service name |
| Matching-specific failures | `MatchingModuleRegistrar.cs` comments (~lines 35-48) |

---

## Red Herrings to Rule Out Quickly

- **NServiceBus / MonitorCommander log noise**: `MonitorCommander` logs through `NServiceBus LogManager`, not Serilog. Quieting those messages is an NServiceBus log-level concern, not a Serilog source-context filter.
- **`IsFromWorkflowExecution: false`**: standalone WorkflowBuilder runs are not tracked by WorkflowMonitorJob — this is by design, not a bug.
- **Machine mismatch error**: workflows are targeted to specific `ExecutionMachine` values — run on the correct machine or create a new execution on the current machine.

---

## Sources

- `{VaultDocsRoot}\speed-merchants\bugs\matching-activity-monitor-service-di-registration-fix.md`
- `{VaultDocsRoot}\speed-merchants\architecture\WORKFLOW-KNOWLEDGE-BASE.md`
- `AGENTS.md` — *source removed 2026-05-31; content migrated to work-ai skills/memory, this skill is now canonical*
