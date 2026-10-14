---
name: crewchief-testing
description: >
  Test conventions for CrewChief across the Unit and Integration suites — executor-seam fakes, bUnit
  component tests, gated-Inconclusive integration prereqs, in-proc test doubles, and MSTest
  parallelization. Use when writing or reviewing a CrewChief test, adding a seam fake, gating a
  live-dependency test, or wiring bUnit DI.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Testing

CrewChief has two MSTest suites: `CrewChief.Tests.Unit` (fast, no *network* infrastructure — includes bUnit
component tests) and `CrewChief.Tests.Integration` (real SQL / remote WinRM, gated). Both use
MSTest + Moq; the Unit suite adds bUnit (`bunit.web`). Read [[crewchief-architecture]] first for the
project map. The atomic-test discipline here matches memory [[feedback_tests_must_be_atomic]] with one
noted exception (see Integration gating).

> [!note] Connect-export fixtures live IN the project (moved 2026-08-19)
> The `Engine\ConnExTokenization\*Tests.cs` classes plus `ConnectImportPageTests`/`ConnectImportEmitTests`
> read real Profisee Connect portal exports from the project-local
> `CrewChief.Tests.Unit\TestData\ConnectExports\` (resolved via `AppDomain.CurrentDomain.BaseDirectory`,
> copied to output by the csproj's `TestData\**\*` item). They deliberately **`Assert.Fail`, not
> `Assert.Inconclusive`**, when a fixture is missing, on the doctrine that a fixture-less run must not pass
> vacuously. Historical note: these fixtures used to live at the machine-local `{ScratchRoot}\ConnectExports`; a
> scratch-folder wipe broke 64 tests, and the user ruled "unit tests must not rely on artifacts outside the
> project folder" — never reintroduce machine-local fixture paths in the Unit suite.

## When to Use
- Writing/reviewing a unit test for a side-effecting executor (Install/ServiceControl/AppPool/Remote…).
- Writing a bUnit component test for a CrewChief.Web page.
- Adding a test that needs a live SQL Server or a real remote machine.
- Reaching for an HTTP endpoint, console, clock, or DPAPI in a test (use the existing doubles).
- Deciding whether a test should opt out of parallelization.

## Executor-seam discipline

Every side-effecting executor puts its OS/process/fs/remote action behind an **injectable interface**
(`IProductInstallRunner`, `IServiceControlRunner`, `IAppPoolRunner`, `IHealthProbe`, `IProcessRunner`,
`IRemoteCommandRunner`). Unit tests drive the executor's **decision logic** with hand-written
**"Recording" fakes** (`RecordingInstallRunner`, `RecordingRemoteCommandRunner`) that count calls and
capture the last request, returning canned results — no real filesystem, msiexec, IIS, or remote
session is touched. See [[crewchief-executor-pattern]] and [[crewchief-remote-box-prep]].

What these tests assert (from `InstallExecutorTests`):

| Concern | Assertion pattern |
|---|---|
| Local-vs-remote branch | `foreach (var local in new[] { "", "localhost", ".", Environment.MachineName })` → the **local runner** is called and the **remote runner's `CallCount == 0`**; a real target (`"REMOTEBOX99"`) inverts it |
| msiexec arg shape | `remote.LastRequest.Executable == "msiexec"` and `Arguments` == `{ "/i", <path>, "/qn", "/norestart", <args> }`; the MSI is listed in `StageFiles` |
| Credential gating | no resolvable credential → step **fails and `remote.CallCount == 0`** ("Transport must not be touched without a resolvable credential"); error mentions `credentialSecretName` |
| Failure/timeout mapping | runner result `Succeeded=false`/`TimedOut=true` → `result.Succeeded=false`, `result.TimedOut`, honors `ContinueOnError` (`ContinuedOnError`) |
| Cancellation | pre-cancelled token → `Assert.ThrowsExceptionAsync<OperationCanceledException>` |
| Converter round-trip | serialize/deserialize through `UtilityStepConverter`; assert camelCase (`"msiPath"`) + alias/case-insensitive `type` deserialization |

Local targets (`""`, `"localhost"`, `"."`, machine name) must pass a **null** machine name to the local
seam and never hit the transport.

## bUnit component tests

Pattern (from `HomePageTests`): each test builds **its own `Bunit.TestContext`** and seed data so tests
stay atomic/order-independent.

- `ctx.JSInterop.Mode = JSRuntimeMode.Loose;`
- `ctx.Services.AddRadzenComponents();`
- Register **Moq'd stores as singletons** (`IStepFileStore`, `IWorkloadFileStore`, `IRunHistory`,
  `IWorkloadRunCoordinator`, `IReferenceDataCache`).
- Assert via `cut.WaitForAssertion(...)` on **CSS-class selectors** (`cut.Find(".stat-steps .stat-value")`)
  or `StringAssert.Contains(cut.Markup, ...)`.
- **Live-refresh** is tested by mutating the backing list and raising the coordinator event:
  `coordinator.Raise(c => c.Changed += null)`, then re-asserting the tile updated with no manual refresh.
- **Degrade test**: a store `.Throws(...)` must render an inline tile error ("unavailable"), not blank
  the page.
- Shared DI helper `SecretCatalogTestServices.AddSecretCatalogForTests(...)` registers what a
  `StepEditorCard` needs (secret catalog, remote inventories, connection/endpoint testers). It backs the
  KV reference store with a **unique temp folder per registration**
  (`Path.Combine(GetTempPath(), "crewchief-test-refkv", Guid.NewGuid("N"))`) so one test's writes can't
  leak into another's reads.

## Integration gating (null-not-error contract)

`IntegrationConfig` resolves optional live prereqs, **first non-empty wins**: environment variable →
then a gitignored `integrationsettings.local.json` next to the test assembly. Keys:

| Prereq | Env var | file key |
|---|---|---|
| SQL Server conn string | `CREWCHIEF_IT_SQL` | `SqlConnectionString` |
| Remote WinRM host | `CREWCHIEF_REMOTE_TEST_HOST` | `RemoteHost` |
| Remote user | `CREWCHIEF_REMOTE_TEST_USER` | `RemoteUser` |
| Remote password | `CREWCHIEF_REMOTE_TEST_PW` | `RemotePassword` |
| Remote credential secret name | `CREWCHIEF_REMOTE_TEST_CRED_SECRET` | `RemoteCredentialSecretName` |

Two newer gating vars are read **directly by the test, deliberately outside `IntegrationConfig`**:
`CREWCHIEF_TEST_RUNAS_USER` and `CREWCHIEF_TEST_RUNAS_PASSWORD` (`LocalRunAsIntegrationTests.cs:82,95-96`).

> [!danger] Lockout-safe defaults for tests that authenticate a real Windows credential
> A test that calls `LogonUser` moves a **real account's lockout counter**, and site policy locks after 3
> consecutive bad attempts with no time-based reset. So the default credential is a **GUID-suffixed
> nonexistent account** — `"cc-nonexistent-" + Guid.NewGuid().ToString("N")[..12]` (`:53-56`) — which
> exercises the failure path without touching any real principal's counter. Supply the env vars only when
> you intend to authenticate for real. `LogonLockoutSafetyTests` pins the four independent mechanisms.

**Credentialed remote ops** (`CredentialedRemoteOpsIntegrationTests`, also `[TestCategory("RemoteLab")]`) resolve the run-as credential first-hit: explicit `RemoteUser`/`RemotePassword` → the **real Local Secrets store** looked up by `RemoteCredentialSecretName` → the conventional `RemoteRuntime:<host-short-name>`. The real-store read mirrors the CLI composition root (DPAPI master, machine-shared vs per-user scope, `CREWCHIEF_LOCAL_SECRETS_MASTER` fallback) so it needs an **unlocked** box, else Inconclusive. The test self-provisions against a deliberately harmless service: a **Spooler Stop→assert Stopped→Start→assert Running** roundtrip proves *control* (not just read) rights. App-pool enumeration on a Profisee lab box **fails** (not skips) if WinRM/rights/WebAdministration are missing.

When a prereq is absent, `IntegrationConfig` returns `null` and the test calls **`Assert.Inconclusive`,
never `Assert.Fail`** — a missing environment must never fail the suite. The repo README states the
contract, not a count: the Integration suite is "all green apart from the SQL-gated cases, which
report Inconclusive (never Failed) when no `CREWCHIEF_IT_SQL` is configured on the machine". Never
quote a pass/skip tally — it is stale the moment a test is added; assert the *shape* instead
(nothing Failed; absent prereqs Inconclusive). Tests touching a real machine carry
`[TestCategory("RemoteLab")]` **in addition to** `[TestCategory("Integration")]`.

Each integration test **self-provisions**: `EndToEndIntegrationTests` builds its own DI container per
test (`services.AddCrewChiefEngine(configuration)`) in `[TestInitialize]`, uses a `Guid`-suffixed temp
dir (`CrewChief_IT_E2E_{Guid:N}`) and table (`CrewChief_IT_{Guid:N}`), and cleans up in a `finally`
block / `[TestCleanup]` via `DropTableIfExistsAsync` (best-effort, swallows errors so cleanup never
masks the real assertion).

> **Tension note:** this Inconclusive-on-missing-prereq pattern is the same one the TestAuto skill audit
> chose **not** to enshrine — it partially conflicts with the atomic-tests rule "self-provision, don't
> skip" ([[atomic-tests]], memory [[feedback_tests_must_be_atomic]]). CrewChief's actual behavior is to
> skip (Inconclusive) when SQL/remote infra is genuinely unavailable, while still self-provisioning
> everything it *can* (DI, temp dirs, temp tables). Document CrewChief's real behavior; don't "fix" it
> to Fail.

## Test doubles / harnesses

| Double | Location | What it gives you |
|---|---|---|
| `LoopbackHttpServer` | `Tests.Unit\Engine\LoopbackHttpServer.cs` | in-proc `HttpListener` on `127.0.0.1`, free port via `GetFreeTcpPort()` (no URL-ACL / admin), settable `ResponseBody`/`StatusCode`/`ContentType`, captures `LastMethod`/`LastPath`/`LastBody` — real endpoint for Curl/PSRest executor tests |
| `FakeConsoleIo` | `Tests.Unit\Secrets\SecretsTestDoubles.cs` | scriptable `IConsoleIo`; hidden reads via `QueueHidden(...)` dequeued in order; captures `Output`/`Errors` so tests can assert **a secret value never appears** in what the CLI prints |
| `ManualClock` | same file | deterministic `IClock` with `Advance(TimeSpan)` for lockout escalation/expiry without waiting |
| `FakePassphraseProtector` | same file | reversible Base64 `IPassphraseProtector` so the DPAPI seam is exercisable off real DPAPI / off Windows (NOT secure — round-trip proof only) |

### Naming taxonomy — five prefixes, distinct meanings

| Prefix | Semantics |
|---|---|
| `Fake*` | A working in-memory implementation |
| `Stub*` | Returns canned values, records nothing |
| `Recording*` | Call count + last request (`RecordingWebSiteRunner`, `RecordingTeamsSender`, `RecordingTokenResolver`, `RecordingLocalRunner`) |
| `Counting*` | **Invocation counts specifically** — because the load-bearing guarantees are *negative*: "probed exactly once", "never probed on the badge render path", "never started a run" (`CountingProber`, `CountingLogon`, `CountingRunner`) |
| `Scripted*` | A queue of pre-scripted responses driving a state machine across calls (`ScriptedLogon`, `ScriptedProcessRunner`, `ScriptedWinRmProbe`) |

`Counting*` and `Scripted*` are new with the capability subsystem. Reach for `Counting*` whenever the
assertion is about how *often* something happened rather than what it returned — a `Recording*` double
cannot express "and it did not happen again".

### bUnit DI: lifetimes must mirror the real circuit, and `TryAdd` keeps tests in control

`SecretCatalogTestServices` registers with **`TryAdd*` throughout** (`:35-36`, `:69-74`, `:83-84`) so a test
that supplies its own double — **before or after** calling the helper — always wins. Order-independence is
the point; a helper that unconditionally registered would make the call site's position significant.

Two lifetime choices carry meaning:

- **`TryAddScoped<ISecretRevealSession, SecretRevealSession>()`** (`:40`) — Scoped means *one instance per
  `TestContext`*, which is exactly the production "one instance per browser circuit". A Singleton would let
  two toggles in different tests share a grant; a Transient would let two toggles in the **same** test
  disagree, which is the very desync the session type exists to fix.
- **`ICapabilityCheckService` registered lazily over whatever `ICapabilityAdvisor` the test supplies**, so a
  test can swap the advisor without also having to rebuild the service on top of it.

### Testing shared per-circuit state needs a test-local host component

A single rendered instance cannot observe a contract that is *about* two instances agreeing. So
`SecretRevealToggleTests` declares a **test-local `ComponentBase`** — `public class TwoToggleHost` (`:21`) —
whose `BuildRenderTree` (`:38`) renders two copies of the component under test, and asserts against
`ctx.RenderComponent<TwoToggleHost>()`. Reach for this shape whenever the behaviour under test is
"instances sharing one circuit-scoped service stay in sync".

## Composition-root guard tests

A named test family whose defining rule is: **seed the provider from the app's own `AddCrewChief*`
extension method, never from a hand-copied registration list** — copying recreates precisely the drift the
test exists to kill.

They guard dependencies resolved at *activation* time (Blazor `[Inject]`, `UseMiddleware<T>`) that no other
test can see, because a missing registration still compiles and still passes any test that `new`s the type
up directly. `SecretsCompositionRootTests` (`:20-38`) documents the real `ISecretsAccessProbe` outage that
took the Windows service down. `CapabilityCompositionRootTests` (`:17-46`) pins each prober seam **twice**
— structurally *and* behaviourally — because a `_ => null` stub is otherwise indistinguishable from a
legitimate null. `EngineRegistrationTests` (`:96-107`) asserts executors receive `BoxPrepCommandRunner`, not
`DefaultRemoteCommandRunner` directly.

## One-truth agreement tests

When N components each answer a *different* question about the same input, drive all N **real** components
in a single test. `LocalRunAsOneTruthTests` (`:17-42`) exists because `BoxPrepRouting.Decide` changed while
`EffectiveIdentity.For` kept the older rule — every per-component test stayed green while the components
drifted apart, and the advisor blessed the wrong account. The rule it states: *per-component tests are not
enough; the agreement itself needs a test.*

## Derived-inventory oracles need an anti-vacuity floor

A third oracle shape sits between "self-referential (worthless)" and "hardcoded literal (brittle)": derive
the expected set from the embedded manifest, assert every property per member, **then add an explicit
minimum-count floor**. Without the floor, a broken embedding glob yields zero resources and the derivation
passes vacuously. `ShippedContentRoutingTests` (`:24-36`) spells out the reasoning — a literal list of
expected filenames "turns every such edit into a red build, which trains people to *fix* the test by editing
the list" — and carries `MinimumShippedPerKind`. The same instinct drives `AreEquivalent`-not-`Contains` in
`StepCapabilityRequirementsTests` (`:86-97`), which pins the **absence** of `RemoteWinRm` as hard as the
presence of the other three.

## In-proc web host — the eager-config trap

The Integration suite pulls in `Microsoft.AspNetCore.Mvc.Testing` to boot the **real** `Program.cs`
in-process via `WebApplicationFactory<Program>` (which is why `Program.cs` ends with
`public partial class Program { }`).

The durable gotcha: `WebApplicationFactory`'s `ConfigureAppConfiguration` overrides are applied at
`builder.Build()` — **after** CrewChief's `Program.cs` has already eagerly resolved the secrets root and the
data folder. So the in-factory config override is **inert documentation**; isolation must be done with
**process environment variables set before host creation**. `CompositionSmokeTests` (`:29-41`) says it
outright: *"BOTH keys are read eagerly and the override is inert; the env vars alone are load-bearing. Do
not delete them."* Tolerated side effects are enumerated at `:42-49` (a `LocalMachine\My` read, replacement
of the global `Serilog.Log.Logger`), which is also why the class is `[DoNotParallelize]` (`:51-59`).

## MSTest parallelization

Both `MSTestSettings.cs` (Unit and Integration) contain exactly:
`[assembly: Parallelize(Scope = ExecutionScope.MethodLevel)]`. Tests that touch process-global state opt
out with **`[DoNotParallelize]`** — **14 Unit classes and 2 Integration classes as of 2026-08-10**. Three
distinct triggers, not one:

| Trigger | Example |
|---|---|
| Process-global **statics** | `LiveStepOutputTests` (see the gotcha below) |
| Process-global **registries** | `SecretScrubberTests` — the known-value registry sits behind the process-singleton Serilog logger, so one method's `SecretScrubber.ResetKnownValuesForTests()` wipes another's registration; it resets in **both** `[TestInitialize]` and `[TestCleanup]` |
| Mutating **environment variables** or the global `Serilog.Log.Logger` | `CompositionSmokeTests` |

Plus the pre-existing secrets/lockout tests, `RunHistoryFileTests`, `CliArgs`/`SecretCommands` CLI tests,
and `OrchestratorIntegrationTests`. The four Web secrets bUnit classes carry the attribute **defensively**
by mirroring their siblings, not because a shared static was ever proven.

**Static-state gotcha (2026-07-22):** any test exercising process-wide **static** state must be
`[DoNotParallelize]` — statics exist in the engine because executors construct their runners directly
(no DI seam), so parallel tests share them. Concrete case: `LiveStepOutput` (the live-tail hub) is a
static buffer that `DefaultProcessRunner` publishes every `OutputDataReceived`/`ErrorDataReceived` line
into — including from the **real processes the executor tests spawn in parallel**. `LiveStepOutputTests`
failed intermittently (another test's process output landed between its `Clear()` and `Snapshot()`)
until the class was marked `[TestClass] [DoNotParallelize]`. Symptom shape: a different single test
failing on some full-suite runs, passing on re-run/in isolation. Apply the same rule to any future
static/ambient seam in the engine.

## Related
- [[crewchief-executor-pattern]] · [[crewchief-remote-box-prep]] · [[crewchief-secrets]]
- [[dotnet-testing]] · [[testauto-testing-patterns]] · [[atomic-tests]]

## Sources
- `CrewChief\CrewChief.Tests.Unit\Engine\InstallExecutorTests.cs`
- `CrewChief\CrewChief.Tests.Unit\Engine\LoopbackHttpServer.cs`
- `CrewChief\CrewChief.Tests.Unit\Engine\LiveStepOutputTests.cs`
- `CrewChief\CrewChief.Tests.Unit\Web\HomePageTests.cs`
- `CrewChief\CrewChief.Tests.Unit\Web\SecretCatalogTestServices.cs`
- `CrewChief\CrewChief.Tests.Unit\Secrets\SecretsTestDoubles.cs`
- `CrewChief\CrewChief.Tests.Unit\MSTestSettings.cs`
- `CrewChief\CrewChief.Tests.Integration\MSTestSettings.cs`
- `CrewChief\CrewChief.Tests.Integration\TestHelpers\IntegrationConfig.cs`
- `CrewChief\CrewChief.Tests.Integration\Engine\RemoteCommandRunnerIntegrationTests.cs`
- `CrewChief\CrewChief.Tests.Integration\Engine\CredentialedRemoteOpsIntegrationTests.cs`
- `CrewChief\CrewChief.Tests.Unit\Engine\RemoteWindowsOpsTests.cs`, `RemoteCredentialResolverTests.cs`
- `CrewChief\CrewChief.Tests.Integration\Engine\EndToEndIntegrationTests.cs`
- `CrewChief\CrewChief.Tests.Integration\Engine\SqlScriptExecutorIntegrationTests.cs`
