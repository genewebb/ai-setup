---
name: testauto-production-sync
description: >
  TestAuto's Production Sync subsystem — the six-phase clean-and-replace record copy between two Profisee
  instances, DBA dependency ordering, the blocking model comparison, the singleton state machine, the REST
  endpoint catalog, and its test doubles. Use when syncing records from one instance to another, when an
  entity is reported Blocked, when working on ProductionSyncJob / ModelComparer / DbaDependencyGraph /
  RestClientsCatalog, when a sync cannot be cancelled or restarted, or when writing tests against the
  FakeRestClient ledger.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Production Sync

Copies **records** from one Profisee instance to another by clean-and-replace, in an order that respects
domain-based-attribute dependencies. Shipped 2026-08-09.

> [!important] What it is NOT
> It never reads, writes, or repairs either **model**. It compares the two models only to decide what is
> safe to copy, and refuses the unsafe parts. It also sits **below** the repository layer by design — see
> [[testauto-record-repository]].

## When to Use

- Running or debugging a production→local record sync.
- "Why is this entity Blocked?"
- Changing phase order, dependency ordering, or the comparison rules.
- Working on cancellation, progress polling, or the endpoint catalog.
- Writing tests against `FakeRestClient` / the call `Ledger`.

## Six phases, deliberately sequential

`ProductionSyncJob.cs:90-156`:

1. **Preflight**
2. **Graph build**
3. **Delete**
4. **Load skeletons** — Code + Name only, `autoAddDbas: false`
5. **Update** — `isUpsert: false`
6. **Verify**

Skeleton-then-update exists because a record's DBA values may reference records that do not exist yet;
creating identity first and filling values second removes the ordering problem within an entity, while the
dependency graph solves it *between* entities.

There is **no fan-out**. Sequential execution is a design choice, not an oversight: it keeps progress
reporting and cancellation precise. Delete always re-queries page 1 (`:277-353`) rather than paging forward,
because deleting shifts the page window under you.

## Dependency ordering (`DbaDependencyGraph`)

An edge **A→B means A depends on B**. From that:

- `DeleteOrder` = **dependents first**
- `LoadOrder` = the exact reverse

Rules that keep it total and deterministic (`:28-56`, `:147-181`):

| Situation | Behaviour |
|---|---|
| Self-reference | Ignored silently |
| Duplicate DBAs | Collapsed |
| Edge to an entity outside the selected set | Run-level **warning**, excluded from ordering |
| **Cycle** | Never throws — broken **alphabetically**, deterministically |

Reverse post-order DFS. A cycle is a legitimate model shape, so failing the run over one would make the
feature unusable on real models.

## The comparison model (`IModelComparer`)

Entity identity = same attribute **count**, name-paired, with matching `DataTypeID` / `TypeID` /
`Precision` (`:196-227`). Two rules worth stating:

- **A target-only attribute is `Blocking`, not a tolerated extra** (`:131-146`). The target having a column
  the source lacks means a record write would silently leave it unset — a data problem disguised as success.
- **Domain attributes are compared by resolved NAME**, never raw `DomainEntityId`. Ids differ across
  instances; comparing them would block every domain attribute on every pair of real environments.

`Precision` **is** the size field. Severity is `Blocking` or `Info`; a blocked entity is excluded from every
later phase, **but the run continues** for the rest.

## State machine and snapshot discipline

`ProductionSyncState` — `ProductionSyncPhase` (10 values: `Idle`, `Preflight`, `Deleting`,
`LoadingSkeletons`, `UpdatingRecords`, `Verifying`, `Done`, `DoneWithDifferences`, `Failed`, `Cancelled`)
plus a 9-value per-entity `ProductionSyncEntityPhase` tracked independently.

- `IsActive` = `Preflight`..`Verifying`.
- `GetSnapshot()` is **lock-guarded** so the page's 2-second poll can never observe a torn state.
- It is a **singleton with no persistence** — a restart loses progress. That is the accepted trade-off for a
  foreground-ish operator tool.
- Per-entity errors are **capped at 200** with an `OverflowErrorCount` (`:126-146`, `:268-286`);
  `AddWarning` / `AddBlockedDifference` are uncapped, and `AddWarning` is never a no-op.
- Cancellation flows through `CurrentCancellationToken`, and **the runner — not `Cancel()` — finalizes the
  phase**, so the terminal state is written by whoever actually stopped.

## Endpoint catalog and the must-differ rule

`RestClientsCatalog` reads `RestClients:*` child sections that carry **both** `BaseUrl` and `ApiKey`, which
automatically excludes scalars like `DefaultTimeoutSeconds`. `NormalizeBaseUrl` (trim + strip trailing
slash, case-insensitive) is the **single shared rule** used by the page, the catalog, the service, and the
tests — so "are these the same endpoint?" cannot be answered two ways. `RestEndpointInfo.ToString()` is
overridden so an ApiKey never leaks into a log or an error message.

Runtime clients are built by `SyncEndpointFactory` for a **chosen** BaseUrl/ApiKey rather than a fixed
subject area; note it forces a trailing slash on `BaseAddress` (without it the last segment, e.g. `/rest`,
is dropped and the gateway serves an HTML error page) and defaults `RestClients:DefaultTimeoutSeconds` to
**600**, treating `<= 0` as `Timeout.InfiniteTimeSpan`.

> [!warning] One `IRestClient` per parallel task
> The three facades of a client share one mutable `PathAndQueryBuilder`. Sharing a client across a fan-out
> corrupts request paths — see [[testauto-bounded-parallel-fanout]].

## DI, enqueue, and the dead token

Lifetimes (`WebModuleRegistrar.cs:97-115`): catalog, comparer, service and runner are **Scoped**; the
**state is a Singleton**.

Enqueue is interface-based: `IBackgroundJobClient.Enqueue<IProductionSyncJobRunner>(x => x.ExecuteAsync(CancellationToken.None))`,
resolved by `AspNetCoreJobActivator`. **The token in that expression is never the live token** — the runner
reads the real one from `ProductionSyncState`. Start guards return a `ProductionSyncStartResult` rather than
throwing: empty selection, same endpoint, already active, Hangfire disabled. See
[[testauto-hangfire-architecture]].

## Error attribution and the 207 rule

Every create/update/delete response goes through `JsonResponse.GetErrors()`.

- **HTTP 207 is not success.** A multi-status batch carries per-record failures inside an otherwise
  "successful" response (`ProductionSyncJob.cs:695-726`).
- Attribute the failure using the **response** code, not the request code.
- A non-2xx, non-207 response attributes the failure to **every** attempted code.
- The gateway's error key is inconsistent — sometimes the record code, sometimes a synthetic `errorN`.

## Testing

`FakeSyncRestClients.cs` — an in-memory store plus an ordered call **`Ledger`** for ordering assertions;
unimplemented members throw `NotImplementedException` deliberately. `RecordFailureRule` produces a 207 whose
response code differs from the request code, which is the case that catches naive attribution.
`FakeSyncEndpointFactory` completes the set. Conventions: [[testauto-testing-patterns]].

## Sources

- `TestAuto.Web\Services\ProductionSync\` — `ProductionSyncJob.cs`, `ProductionSyncService.cs`, `ProductionSyncState.cs`, `DbaDependencyGraph.cs`, `ModelComparer.cs`, `RestClientsCatalog.cs`
- `TestAuto.Web\Components\Pages\ProductionSync.razor(.cs)`
- `TestAuto.Web\AutoRegistration\WebModuleRegistrar.cs`
- `TestAuto.Shared.Http\Rest\SyncEndpointFactory.cs`
- `Testing.SpeedMerchants.Unit\Web\ProductionSync\` (6 files) + `Web\Components\Pages\ProductionSyncPageTests.cs`
- `TestAuto.Web\Documentation\ProductionSync.md`

## Related

[[testauto-record-repository]] · [[testauto-hangfire-architecture]] · [[testauto-bounded-parallel-fanout]] · [[testauto-http-facades]] · [[testauto-testing-patterns]] · [[testauto-ui-patterns]] · [[api-response-standardization]]
