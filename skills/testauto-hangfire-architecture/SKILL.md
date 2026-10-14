---
name: testauto-hangfire-architecture
description: >
  Hangfire Pro topology and concurrency architecture for TestAuto. Use when Hangfire is UNAVAILABLE
  and the null-object fallbacks bind (queries return empty, commands throw - the class inside
  HangfireUnavailableFallbacks.cs is HangfireUnavailable), diagnosing a CircuitUnhandledException dead
  page caused by an activation failure, understanding
  the queue layout (scheduled / default / scn-{name} / aggregation / persistence / workload /
  resource), reviewing AddHangfireCore / AddHangfireServers / AddHangfireRecurringJobs
  registration, implementing ScenarioDispatcher dispatch behavior, or debugging Hangfire
  queue isolation issues.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Hangfire Architecture

> **Scope**: speed-merchants (TestAuto.Web)
> **Source**: TestAuto/Documentation/ManagingJobsWithHangfire_v2.md — a **design doc**; some of its
> proposals (per-scenario `[Semaphore]`, recurring per-scenario dispatcher, config-driven queues)
> were **never implemented**. Sections below reflect the live code; aspirational leftovers are marked.

---

## Design Goals

| Goal | Mechanism (live) |
|---|---|
| Per-scenario queue isolation | `ProcessBatchJob` child jobs run on `scn-{scenarioName}`, served by a per-run dynamic server |
| Concurrency caps | `serverCount` dial in `ScenarioDispatcher` + `[DisableConcurrentExecution]` on `Dispatch`; throttling infra (`UseThrottling`, `IThrottlingManager`) is registered but no `[Semaphore]` attribute exists in code |
| Runtime concurrency dialing | `ScenarioDispatcher.Dispatch` enqueues `toEnqueue = serverCount − running` per dispatch |
| Follow-on chain | **NOT** "Batch → Aggregator → Persistence" — that design-doc phrasing does not match live code. Live: `ProcessBatchJob` → `MetricsPersistenceJob` → `WorkloadExecutionUpdateJob` → `ResourceCollectionJob`; the Aggregator is an optional side branch (see below) |

### The live follow-on chain (verified in `BatchJobOrchestrator.cs`)

The Aggregator is **not** a link in the persistence chain — it is an optional side branch. The real
chain is a sequence of `BackgroundJob.ContinueJobWith` hops, each `OnlyOnSucceededState`:

```
ProcessBatchJob (child, scn-{name})
   └─► MetricsPersistenceJob            :218-228 / :271-281 / :331-341  (only if RequiresMetrics)
         └─► WorkloadExecutionUpdateJob :428-432 (after the LAST MetricsPersistenceJob)
               └─► ResourceCollectionJob :474-478 (if FeatureFlags:EnableResourceCollection)

no-metrics path: ProcessBatchJob ──► WorkloadExecutionUpdateJob   :445-449 (after the last child job)

side branches off the parent batch (BatchJob.ContinueBatchWith, OnAnyFinishedState):
   • DynamicServerCleanupJob        :357-365  queue "default"
   • MetricBatchSummaryAggregator   :373-386  queue "aggregation", ONLY if CreateBatchSummaries = true
```

So `MetricsPersistenceJob → WorkloadExecutionUpdateJob` is the live hand-off; nothing flows
*through* the Aggregator, and with `CreateBatchSummaries = false` (the default) the Aggregator
never runs at all while the persistence chain still completes normally.

---

## Queue Topology

```
"scheduled"    → recurring cron jobs ([Queue("scheduled")]): WorkflowMonitorJob and
                 ResourceMetricsUpdateJob ONLY — ScheduledServer (WorkerCount 1)
"default"      → ScenarioDispatcher.Dispatch, BatchJobOrchestrator.StartBatchProcessing,
                 DynamicServerCleanupJob — DispatcherServer (WorkerCount 1)
"scn-{Name}"   → ProcessBatchJob child jobs — served by a per-run dynamic server
                 (DynamicServerManager); also what the dispatcher's FetchedCount reads
                 to compute the running count
"aggregation"  → MetricBatchSummaryAggregator (batch continuation, only when
                 CreateBatchSummaries = true) — FollowOnServer (WorkerCount 2)
"persistence"  → VESTIGIAL: declared on FollowOnServer but never receives jobs.
                 MetricsPersistenceJob has NO [Queue] attribute and is attached per child
                 job via BackgroundJob.ContinueJobWith<MetricsPersistenceJob>(...) with NO
                 explicit EnqueuedState, so it actually runs on the "default" queue
                 (DispatcherServer, WorkerCount 1). By contrast, "aggregation", "workload",
                 and "resource" ARE genuinely used (EnqueuedState("aggregation");
                 [Queue("workload")]/[Queue("resource")] on the respective jobs).
"workload"     → WorkloadExecutionUpdateJob ([Queue("workload")]) — FollowOnServer
"resource"     → ResourceCollectionJob ([Queue("resource")]) — FollowOnServer
```

> **`CollectionUpdateJob` is DEAD CODE — do not list it as a scheduled job.**
> `TestAuto.DependencyInjection/Jobs/CollectionUpdateJob.cs` declares `[Queue("scheduled")]` and a
> generic `ICollectionService`-driven recurring job, but a repo-wide grep for `CollectionUpdateJob`
> returns **only its own declaration** (`:19`, `:28`, `:35`) — no `RecurringJob.AddOrUpdate`, no
> `BackgroundJob.Enqueue`, no DI registration, no callers. The only recurring job registered in
> `HangfireServerServiceExtensions.RegisterRecurringJobs` is
> `RecurringJob.AddOrUpdate<ResourceMetricsUpdateJob>(…)` (`:85`); `WorkflowMonitorJob` is registered
> separately by `WebModuleRegistrar.RegisterWebRecurringJobs`. The `[Queue]` attribute on an
> un-enqueued class proves nothing about the live topology.

Server/queue bindings are fixed in `AddHangfireServers` (there is no `"dispatcher"` queue and
queues are NOT computed from `IConfiguration["Scenarios:{Name}"]` keys); only the `scn-{Name}`
servers are created dynamically per orchestrator run.

---

## Service Registration (split across three extensions)

There is **no `AddHangfireServices`**. Registration is split across
`TestAuto.DependencyInjection/ServiceExtensions/HangfireCoreServiceExtensions.cs` and
`HangfireServerServiceExtensions.cs`:

### 1. `AddHangfireCore(services, cfg)` — storage only, no servers

- Requires `ConnectionStrings:HangfireDB` (user secrets / env / TestAutoSecrets) — throws if missing; `EnsureDatabaseExists` creates the database if absent

### Degraded mode — `HangfireAvailability` is the single source of truth

`AddHangfireCore` still throws (`HangfireCoreServiceExtensions.cs:34`), but `RegisterAllServices`
(`:116-163`) **catches** it and records the outcome in the singleton `HangfireAvailability`
(`Enabled` + `ReasonDisabled`). Registration is skipped — never fatal — under three distinct conditions,
one of which is easy to miss: a connection string containing **unresolved `{{Section:Key}}` tokens**.

> [!danger] Gate on `HangfireAvailability.Enabled`, never on the connection string
> Two deciders is one too many. A token-garbage connection string *looks* configured to a string-based
> check, and a dashboard that re-derived availability that way crashed the pipeline **at build time** and
> killed the Windows service (2026-08-09). Every downstream consumer — dashboard, Production Sync, any new
> feature — must read the marker (`PipelineExtensions.cs:179-194`).

`WebRecurringJobsService.StartAsync` no longer throws when Hangfire is absent: it logs a warning and
returns, so a degraded box still reaches the web host and the operator can fix secrets in the browser
instead of reading an event-log stack trace.

This is one instance of a wider convention — **one decider, one immutable singleton marker, no consumer
re-derives the answer** — now used three times: `HangfireAvailability`, `RuntimeSecretsStatus`, and
`IHttpsRuntimeStatus`. Each carries a human-readable reason string because the decision happens before
Serilog's file sink exists. See [[testauto-windows-service-hosting]].

### Enqueueing a DI-resolved runner — and the dead token

The house pattern for a background runner that needs DI is
`IBackgroundJobClient.Enqueue<TInterface>(x => x.ExecuteAsync(CancellationToken.None))`, resolved at run
time by `AspNetCoreJobActivator`.

> [!warning] The token baked into the enqueue expression is NEVER the token observed at run time
> Hangfire serializes the expression, so `CancellationToken.None` is literally what the method receives.
> A runner that needs to be cancellable must read a **live** token from shared state (e.g.
> `ProductionSyncState.CurrentCancellationToken`), not from its own parameter. See
> [[testauto-production-sync]].
- `services.AddHangfire(...)`: `AspNetCoreJobActivator`, `UseSqlServerStorage` with `SchemaName = testautojobs`, poll interval from `ProfiseeAppSettings:HangfirePollingIntervalInSeconds` (default 5 s), configurable `Hangfire:CommandBatchMaxTimeoutMinutes` / `Hangfire:SlidingInvisibilityTimeoutMinutes` (default 10)
- `GlobalConfiguration`: `UseBatches()`, `UseThrottling(ThrottlingAction.RetryJob, poll)`, `UseSerilogLogProvider()`
- Registers `IThrottlingManager`, a `Func<IStorageConnection>` factory, and `AddHostedService<HangfireInitializer>()`

### 2. `AddHangfireServers(services, configuration)` — three fixed servers

```csharp
// ScheduledServer  → Queues: ["scheduled"],                                    WorkerCount 1
// DispatcherServer → Queues: ["default"],                                      WorkerCount 1
// FollowOnServer   → Queues: ["aggregation","persistence","workload","resource"], WorkerCount 2
```

(`scn-{Name}` servers are NOT registered here — `BatchJobOrchestrator` spins one up
dynamically per run and `DynamicServerCleanupJob` tears it down.)

### 3. `AddHangfireRecurringJobs(services, configuration)`

Registers `AddHostedService<HangfireRecurringJobsService>()`, which calls
`RegisterRecurringJobs(configuration)` at startup — e.g. `ResourceMetricsUpdateJob`
(`ResourceCollection:UpdateJobIntervalMinutes`, default 2, queue `scheduled`, gated by
`ResourceCollection:Enable`). Web-specific recurring jobs (WorkflowMonitorJob) are registered
separately via `WebModuleRegistrar.RegisterWebRecurringJobs`.

---

## Configuration

> **Aspirational (NOT implemented)**: the design doc proposed a per-scenario
> `"Scenarios": { "{Name}": { "Concurrency": N } }` appsettings block feeding queue names and
> semaphore keys. No such block exists. Live concurrency comes from the `serverCount` argument
> the caller passes to `ScenarioDispatcher.Dispatch` (from the scenario configuration's
> Hangfire server count).

---

## HangfireInitializer (Startup)

`TestAuto.DependencyInjection/Helpers/HangfireInitializer.cs` does **not** schedule any jobs.
It only guarantees the schema/tables exist and that `JobStorage.Current` is set:

```csharp
public class HangfireInitializer : IHostedService
{
    private readonly IServiceProvider _sp;
    public HangfireInitializer(IServiceProvider sp) => _sp = sp;

    public Task StartAsync(CancellationToken _)
    {
        HangfireCoreServiceExtensions.ForceHangfireSchema(_sp);  // sets JobStorage.Current
        return Task.CompletedTask;
    }
    public Task StopAsync(CancellationToken _) => Task.CompletedTask;
}
```

Recurring jobs are scheduled elsewhere (`HangfireRecurringJobsService`,
`WebModuleRegistrar.RegisterWebRecurringJobs`); `ScenarioDispatcher` is not a recurring job —
it is enqueued on demand when a scenario is run.

---

## ScenarioDispatcher (Per-Run Dialing)

`TestAuto.Scenarios/BatchProcessing/ScenarioDispatcher.cs` — enqueued **on demand** (not
recurring) when a scenario run starts. Checks running count vs the requested server count and
enqueues the delta:

```csharp
[DisableConcurrentExecution(timeoutInSeconds: 30)]
[AutomaticRetry(Attempts = 0)]
[DisplayName("{0} Dispatch (Servers: {1})")]
public void Dispatch(string scenarioName, int serverCount, string configJson, string securityJson)
{
    var queueName = "scn-" + QueueNameHelper.Normalize(scenarioName);
    int running   = (int)JobStorage.Current.GetMonitoringApi().FetchedCount(queueName);
    int toEnqueue = Math.Max(0, serverCount - running);

    // Partitions TestRecordLimit across the orchestrators, then:
    for (int i = 0; i < toEnqueue; i++)
    {
        var job = Job.FromExpression<BatchJobOrchestrator>(orch =>
            orch.StartBatchProcessing(scenarioName, threadId, serverCount,
                orchestratorCfg, batchSize, string.Empty, security));
        _jobs.Create(job, new EnqueuedState(queue: "default"));   // NOT the scn- queue
    }
}
```

**Dialing**: concurrency is the `serverCount` argument per run — there is no recurring tick
or config re-read.

---

## [Semaphore] — NOT Implemented (design-doc aspiration)

The design doc proposed decorating `ProcessBatchJob` with Hangfire.Pro `[Semaphore]`. **No
`[Semaphore]` attribute exists anywhere in the codebase.** Live `ProcessBatchJob`
(`BatchJobOrchestrator.cs`) carries only:

```csharp
[DisplayName("{0} Server {1} Batch {2} of {3}")]
```

Actual concurrency control:
- `serverCount` partitioning in `ScenarioDispatcher.Dispatch`
- `[DisableConcurrentExecution(timeoutInSeconds: 30)]` on `Dispatch`
- Per-run dynamic server WorkerCount on the `scn-{Name}` queue
- Throttling infrastructure (`UseThrottling`, `IThrottlingManager`) is registered in
  `AddHangfireCore` but no semaphore keys are declared

---

## BatchJobOrchestrator — Per-Scenario Queues & Continuations

`StartBatchProcessing` computes `queueName = "scn-" + QueueNameHelper.Normalize(scenarioName)`,
spins up a dynamic server for that queue (registered with `DynamicServerManager`), and wires
the chain like this:

```csharp
// Child page jobs → scn-{name} queue (inside the Hangfire.Pro parent batch)
string childJobId = parent.Create(
    () => ProcessBatchJob(...),
    new EnqueuedState(queueName));

// Per-child metrics persistence → plain job continuation, NO explicit queue
BackgroundJob.ContinueJobWith<MetricsPersistenceJob>(
    childJobId,
    job => job.ExecutePersistenceAsync(...),
    JobContinuationOptions.OnlyOnSucceededState);

// Dynamic server cleanup → batch continuation on "default"
BatchJob.ContinueBatchWith(parentBatchId,
    batch => batch.Create<DynamicServerCleanupJob>(
        job => job.Execute(serverKey, scenarioName),
        new EnqueuedState("default")),
    $"Cleanup ScenarioServer for '{scenarioName}'",
    BatchContinuationOptions.OnAnyFinishedState);

// Aggregator → batch continuation on "aggregation", only when CreateBatchSummaries = true
BatchJob.ContinueBatchWith(parentBatchId,
    batch => batch.Create<MetricBatchSummaryAggregator>(
        agg => agg.AggregateAndWriteSummaries(...),
        new EnqueuedState("aggregation")),
    $"Aggregate Summaries for '{scenarioName}'",
    BatchContinuationOptions.OnAnyFinishedState);
```

`WorkloadExecutionUpdateJob` (`[Queue("workload")]`) and `ResourceCollectionJob`
(`[Queue("resource")]`) are attached via `BackgroundJob.ContinueJobWith` afterwards.

---

## Old vs New Design Comparison

| Feature | Old | New (live) |
|---|---|---|
| Queue isolation | All on `default` | `ProcessBatchJob` children on `scn-{name}` per run; role queues (`scheduled`/`aggregation`/`persistence`/`workload`/`resource`) |
| Concurrency cap | Server-wide `WorkerCount` only | Per-run `serverCount` dial (`[Semaphore]` was proposed but never shipped) |
| Runtime dialing | Manual config change + restart | `serverCount` passed per dispatch — no restart |
| Server scaling | Single pool | Fixed role servers + one dynamic server per scenario run |

---

## Worker Pool Scaling

Role servers are fixed in `AddHangfireServers`; per-scenario capacity comes from the dynamic
server `BatchJobOrchestrator` creates for each run's `scn-{Name}` queue (cleaned up by
`DynamicServerCleanupJob`). Global `WorkerCount` still applies per server; the dispatcher's
`serverCount − running` delta prevents over-scheduling.

## When Hangfire is unavailable - the asymmetric fallback contract

`HangfireAvailability.Enabled == false` does **not** unregister the job surfaces.
`ITestAutoBackgroundJobClient` and `ITestAutoMonitoringApi` stay registered and bind to null-object
stand-ins in `HangfireUnavailableFallbacks.cs` - note the **class inside that file is
`HangfireUnavailable`**, so grepping for the filename as an identifier finds nothing.

The contract is **deliberately asymmetric**:

| Direction | Behaviour | Why |
|---|---|---|
| **Queries** | Return **EMPTY** | A monitoring page renders "no jobs" instead of dying |
| **Commands** | **THROW**, naming the recorded reason | Silently accepting an enqueue that will never run is the worse failure |

`JobDetails` returns an **empty, never null** History, because callers enumerate it without a null check.

### Why this exists at all

The real adapters take Hangfire's own `IBackgroundJobClient` / `JobStorage`, which are registered **only
inside the skipped `AddHangfireCore`**. So without the fallbacks, five injecting services failed at
**activation** - surfacing as a `CircuitUnhandledException`, i.e. **a dead Blazor page**, rather than as a
disabled feature.

The **marker** convention itself (ask `HangfireAvailability`, never the connection string) is covered in
[[testauto-windows-service-hosting]]. What lives here is the **false branch**.

## Sources

- `TestAuto\Documentation\ManagingJobsWithHangfire_v2.md` — the
  **design doc** this skill was originally written from; treat every claim in it as unverified
- Live code the sections above were verified against:
  - `TestAuto.Scenarios\BatchProcessing\BatchJobOrchestrator.cs`
  - `TestAuto.Scenarios\BatchProcessing\ScenarioDispatcher.cs`
  - `TestAuto.Metrics\Helpers\MetricBatchSummaryAggregator.cs`
  - `TestAuto.DependencyInjection\ServiceExtensions\HangfireServerServiceExtensions.cs`
  - `TestAuto.DependencyInjection\Jobs\CollectionUpdateJob.cs` (unwired)
