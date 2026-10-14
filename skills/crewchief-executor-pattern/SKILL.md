---
name: crewchief-executor-pattern
description: >
  The IStepExecutor contract, the uniform executor skeleton, StepExecutionResult DTO, and multi-registration DI wiring in CrewChief.Engine. Use when writing, reviewing, or debugging a CrewChief step executor, understanding how process/timeout/cancellation are handled, how executors are discovered and indexed by StepType, or how failure messages get remediation hints.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Executor Pattern

Every CrewChief step type is executed by a dedicated `IStepExecutor`. There is **no abstract executor base** — each executor repeats the same skeleton by convention. Executors are registered as many `IStepExecutor` services and the `UtilityOrchestrator` receives them as an `IEnumerable<IStepExecutor>`, self-indexing by each executor's `StepType`. Results flow through the shared `StepExecutionResult` DTO. See [[crewchief-orchestration]] for how executors are driven, [[crewchief-step-type-model]] for the step side, [[result-pattern]] and [[dotnet-service-registration]] for the general idioms.

## When to Use
- "Write / review a new CrewChief step executor"
- "How does a CrewChief executor handle timeout and cancellation of a spawned process?"
- "How does the orchestrator find the right executor for a step?"
- "Where do the SQL/CURL/ConnEx-specific result fields live?"
- "Why does a failed step's error message have a ' — Hint:' suffix?"

## `IStepExecutor` contract

`CrewChief.Engine/Orchestration/IStepExecutor.cs` — three members:

```csharp
string StepType { get; }                                  // the key this executor indexes under
Task<StepExecutionResult> ExecuteAsync(UtilityStepBase step, CancellationToken ct = default);
bool CanExecute(UtilityStepBase step);                    // runtime `is <ConcreteStep>` + required-field guard
```

`StepType` is a plain string literal per executor, e.g. `CommandLineExecutor => "CommandLineStep"`, `CurlExecutor => "CURL"`, `PowerShellRestExecutor => "HTTP"`, `SqlScriptExecutor => "SqlStep"`, `IisResetExecutor => "IisResetStep"`, `EmailExecutor => "EmailStep"`. This is the *executor* dispatch key — distinct from `StepTypeRegistry`'s deserialization aliases (see the drift hazard in [[crewchief-adding-a-step-type]]).

## The uniform executor skeleton

There is no base class — each executor repeats this shape (canonical example: `CommandLineExecutor.cs`):

1. **`CanExecute`** does a runtime type check so alias `Type` strings still pass, plus a required-field guard, e.g.:
   ```csharp
   public bool CanExecute(UtilityStepBase step)
       => step is CommandLineStep c && !string.IsNullOrWhiteSpace(c.Command);
   ```
   (Runtime `is` — never a `step.Type == "..."` string compare — because `Type` is a raw alias that varies by how the JSON was authored.)
2. **`ExecuteAsync`**: guard with `if (!CanExecute(step)) return StepExecutionResult.CreateFailure(...)`, cast to the concrete step, start a `Stopwatch` + capture `StartedAtUtc`, build a `StepExecutionResult`, do the work in a `try`, `catch (Exception ex)` → set `Succeeded=false`, `Exception=ex`, `ErrorMessage=ex.Message`, and set `result.ContinuedOnError = true` when `step.ContinueOnError`, then a `finally` that stops the stopwatch and sets `CompletedAtUtc`/`ElapsedMs`.

### Process executors (CommandLine, Curl, PowerShell, CLU, Install/Uninstall/Configure, IisReset)

Verified in `CommandLineExecutor.ExecuteProcessAsync` (`CommandLineExecutor.cs:273-387`):
- `ProcessStartInfo` with `UseShellExecute=false`, `RedirectStandardOutput/Error=true`, `CreateNoWindow` from the step.
- stdout/stderr captured into two `StringBuilder`s via `OutputDataReceived`/`ErrorDataReceived`, after `BeginOutputReadLine()`/`BeginErrorReadLine()`.
- **Genuine async wait with cancellation + timeout** (lines 352-353):
  ```csharp
  await process.WaitForExitAsync(cancellationToken)
      .WaitAsync(TimeSpan.FromMilliseconds(timeoutMs), cancellationToken);
  ```
  `WaitForExitAsync(ct)` observes cancellation; `.WaitAsync(timeout, ct)` enforces the timeout. This actually unblocks the wait on cancel — unlike a `Task.Run(() => process.WaitForExit(ms), ct)` where the token could only prevent the delegate starting.
- On `TimeoutException` or `OperationCanceledException`: **kill the whole tree** via `TryKillProcessTree` → `process.Kill(entireProcessTree: true)` (lines 394-407). Essential because a `UseShell=true` command runs under `cmd`/`sh` and the real work is a child that a plain `Kill()` would orphan.

## `StepExecutionResult` — the shared DTO

`CrewChief.Engine/Steps/StepExecutionResult.cs`. One class carries results for every step family.

- **Success aliases**: `Succeeded` is the field; `Success` is a get/set alias forwarding to `Succeeded` (lines 40-44) — both names work.
- Common: `ExecutionId`, `StepIndex`, `StepType`, `StepKey`, `TimedOut`, `StartedAtUtc`/`CompletedAtUtc`/`ElapsedMs`, `ExitCode`, `StandardOutput`/`StandardError`, `ErrorMessage`, `Exception`, `ContinuedOnError`, `AttemptsUsed` (default 1), `InputText`, `WorkingDirectory`, `Metadata`.
- **Step-family fields** (nullable, only set by the relevant executor): SQL → `BatchCount`, `RowsAffectedTotal`, `RowsAffectedByBatch`, `FirstScalarResult`, `PassFailErrorDetail`; ConnEx/export → `ArtifactsProduced`, `ArtifactPaths`; CURL/HTTP → `HttpStatusCode`, `ResponseSizeBytes`.
- Factories: `CreateFailure(stepIndex, stepType, stepKey, errorMessage, exception=null)` and `CreateSuccess(stepIndex, stepType, stepKey, startTime, elapsedMs)`; helper `CalculateElapsedTime()`.

## DI: multi-registration + self-indexing

`CrewChief.Engine/EngineServiceCollectionExtensions.cs` (`AddCrewChiefEngine`): every executor is registered as a *separate* `IStepExecutor`:

```csharp
services.AddTransient<IStepExecutor, SqlScriptExecutor>();
services.AddTransient<IStepExecutor, PowerShellScriptExecutor>();
services.AddTransient<IStepExecutor, CommandLineExecutor>();
services.AddTransient<IStepExecutor, CurlExecutor>();        // StepType "CURL"
services.AddTransient<IStepExecutor, PowerShellRestExecutor>(); // StepType "HTTP"
// … ConnEx, Wait, MapShare, ServiceControl, HealthGate, DatabaseOperations,
//     AppPool, Uninstall, Install, Configure, IisReset, SetApiKey, Email
```

The orchestrator ctor takes `IEnumerable<IStepExecutor>` and builds `_executorsByType[executor.StepType] = executor` (OrdinalIgnoreCase), then layers short aliases on top (see [[crewchief-orchestration]]). Because CURL reports `"CURL"` and HTTP reports `"HTTP"`, both register cleanly with no shadowing (they used to be one fused step — see memory [[project_crewchief_http_curl_split]]). Editor-side helpers (`IRemoteServiceInventory`, `IRemoteAppPoolInventory`, `IConnectionTester`, `IServerFileBrowser`, `IRemoteCommandRunner`, `IApiKeyEncryptor`, `IEmailSender`, etc.) are registered here too as singletons/transients feeding those executors.

### Constructor chain for remote-credentialed executors (testability seam)
The remote executors that grew a credentialed path (`ServiceControlExecutor`, `AppPoolExecutor`, `IisResetExecutor`) expose a **three-constructor chain** so the credentialed transport can be faked without a live box:
- **DI ctor** `(ILogger, IConfiguration, ITextTemplater)` — the one MS.DI resolves; it news up a `DefaultRemoteCommandRunner` + `DefaultRemoteCredentialResolver(configuration)` internally.
- **Legacy test ctor** (the older 3-arg shape) — injects an **inert** resolver (`new DefaultRemoteCredentialResolver(new ConfigurationBuilder().Build())`) so a remote step deterministically takes the *legacy* ambient-identity path (no credential resolvable).
- **All-seams-explicit ctor** — every collaborator (`IRemoteCommandRunner`, `IRemoteCredentialResolver`, local runner) is a parameter, for tests that want a fake transport and assert on the credentialed path.

This is why unit tests can prove the local/credentialed-remote/legacy routing (see [[crewchief-remote-box-prep]]) without touching WSMan.

## Central failure decoration

`CrewChief.Engine/Executors/ExecutionErrorHints.cs` — `Decorate(message)` appends `" — Hint: <remediation>"` when `Explain(message)` matches a known low-level failure (access-denied/error 5, RPC 1722, SQL login-failed, timeouts, service-not-found, DNS, elevation, duplicate switch, …); returns the message unchanged otherwise. The **orchestrator** applies this centrally to every failed step's `ErrorMessage` (`UtilityOrchestrator.cs:331-332`) — one chokepoint, so no per-executor wiring is needed.

## Truncation gotcha (do not copy the private helpers)

The canonical truncator is `CrewChief.Engine/Helpers/TextTruncationHelper.cs` — `TruncateWithMarker` preserves **head + tail** around a ` ... [N chars truncated] ... ` marker (`TruncateForMetrics`=4000, `TruncateForLogging`=1000, `TruncateForDisplay`=500; throws if `maxChars < 100`).

But three process executors carry their **own private head-only** `TruncateForMetrics` copies that just cut the tail and append a marker — inconsistent with the shared helper and with each other:
- `CommandLineExecutor.cs:430-439` → `"... [truncated]"`
- `CurlExecutor.cs:348-352` → `"... (truncated)"`
- `SqlScriptExecutor.cs:605-611` → `"... [truncated]"`

When reviewing an executor, prefer `TextTruncationHelper`; treat these private copies as a known inconsistency (tail context is lost).

## Sources
- `CrewChief\CrewChief.Engine\Orchestration\IStepExecutor.cs`
- `CrewChief\CrewChief.Engine\Steps\StepExecutionResult.cs`
- `CrewChief\CrewChief.Engine\Executors\CommandLineExecutor.cs`
- `CrewChief\CrewChief.Engine\EngineServiceCollectionExtensions.cs`
- `CrewChief\CrewChief.Engine\Executors\ExecutionErrorHints.cs`
- `CrewChief\CrewChief.Engine\Helpers\TextTruncationHelper.cs`
- `CrewChief\CrewChief.Engine\Executors\CurlExecutor.cs`  (StepType line 38; private TruncateForMetrics 348-352)
- `CrewChief\CrewChief.Engine\Executors\SqlScriptExecutor.cs`  (StepType line 59; private TruncateForMetrics 605-611)
