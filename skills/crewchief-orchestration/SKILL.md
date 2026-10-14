---
name: crewchief-orchestration
description: >
  The two-layer CrewChief run engine — UtilityOrchestrator (sequential steps, per-step retry, param swap/restore, ContinueOnError, central error hints) and WorkloadEngine (per-step orchestrator calls, inline step resolution, synthesized-failure guard). Use when tracing how a CrewChief workload executes, debugging retry/ContinueOnError/cancellation behavior, understanding why stored templates aren't mutated at run time, why a workload step is an independent COPY of the library step rather than a live link, or diagnosing a LegacyWorkloadRefException on load.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Orchestration

CrewChief runs a workload through two layers. `UtilityOrchestrator.ExecuteScenarioAsync` executes a list of resolved steps sequentially with per-step retry, error policy, and metrics. `WorkloadEngine.ExecuteAsync` sits above it, deserializing each `WorkloadDefinition` entry's `Inline` body into a concrete step and calling the orchestrator **once per step** for live progress and between-step cancellation — re-implementing `ContinueOnError` itself and synthesizing a failure result when the orchestrator returns none. See [[crewchief-executor-pattern]] for the executor side, [[crewchief-step-type-model]] for step (de)serialization, [[crewchief-token-replacement]] for parameter resolution, and [[testauto-batch-orchestration]] for the TestAuto cousin.

## When to Use
- "How does a CrewChief workload actually run its steps?"
- "Why doesn't running a step from the editor rewrite my `{{...}}` tokens?"
- "How do retry / RetryDelaySeconds / ContinueOnError interact, and in what order?"
- "Why does a ContinueOnError step with a validation error still fail the workload?"
- "Where are workload entries turned into steps?"
- "Why won't this workload load — `LegacyWorkloadRefException`?"

## Layer 1 — `UtilityOrchestrator.ExecuteScenarioAsync`

`CrewChief.Engine/Orchestration/UtilityOrchestrator.cs`. Signature: `(string scenarioName, List<UtilityStepBase> steps, Dictionary<string,string>? globalParameters=null, CancellationToken ct=default) → UtilityScenarioResult`.

**Executor index** (ctor, lines 54-91): builds `_executorsByType` (OrdinalIgnoreCase, line 54) from the injected `IEnumerable<IStepExecutor>` keyed by each `executor.StepType` (lines 55-59), then **derives** aliases from `StepTypeRegistry.Registrations` (lines 61-91) — for each registration it finds the executor matching any accepted type string and maps every remaining string of that registration to it. The old hand-maintained `AddExecutorAlias(...)` list is **gone from CrewChief** (zero hits under `CrewChief\`; the identifier survives only in the unrelated `TestAuto.Utilities` orchestrator); a registration with no registered executor is skipped (`continue`, lines 79-80). Also constructs its own `ParameterResolver(_textTemplater, _logger)` so the public ctor is unchanged.

**Per-step loop** (lines 158-370, inside `ExecuteScenarioAsync` at line 112):
1. `cancellationToken.ThrowIfCancellationRequested()` at the top of each step (line 160).
2. **Merge params**: new OrdinalIgnoreCase dict = global params, then step params overlaid (**step wins**). Runs for every step even with no globals.
3. **Resolve special values**: `_parameterResolver.ResolveSpecialParameterValues(mergedParams, escapeForJson: step is ConnExStep)` — resolves `{{$config:}}`/`{{$env:}}` parameter *values* now, so executors (single-pass templaters) don't embed the literal token. `escapeForJson` is true **only for ConnEx** (JSON-artifact injection). The resolve call is at line 198; an `UnresolvedParameterTokenException` (base of `CircularParameterReferenceException`) is caught at line 200 and turned into a normal step failure that honors `ContinueOnError` (lines 200-227).
4. **Dispatch**: `_executorsByType.TryGetValue(step.Type, out var executor)` (line 230) — miss → `No executor found for step type: {step.Type}` failure (lines 230-255, message at 232).
5. **Param swap/restore** (lines 257-312): `originalParameters = step.Parameters; step.Parameters = mergedParams;` (lines 261-262, restored at 312) for the executor call only, restored in a `finally`. **CRITICAL**: the caller's step is never mutated — the stored workload template and the editor's bound step model keep their original `{{...}}` tokens, so a single-step editor test run can't bake resolved literals into a subsequent Save.
6. **Retry** (lines 268-307): `maxAttempts = RetryEnabled ? 1 + Math.Clamp(MaxRetries,0,10) : 1` (line 268); `retryDelaySeconds = Math.Clamp(RetryDelaySeconds,0,300)` (line 269). Loop attempts; a thrown exception becomes a failure result; `OperationCanceledException` is **re-thrown, never retried**; `stepResult.AttemptsUsed = attempt`; break on success or when attempts exhausted; `Task.Delay(retryDelaySeconds, ct)` between attempts. Timeout applies per attempt.
7. **After retries — result-shaping chokepoint** (lines 330-345): set `ContinuedOnError=true` if failed and `step.ContinueOnError` (line 332); `ExecutionErrorHints.Decorate(...)` applied centrally to a failed `ErrorMessage` (line 340); then **stamp the description** — if `stepResult.Description` is blank, set it to `step.Description` (lines 344-345). `StepExecutionResult.Description` (`Steps/StepExecutionResult.cs`) is a nullable `string?`; stamping it centrally here means run tables/logs show the human-readable description instead of the per-executor `StepKey`, for **every** step type, without per-executor wiring (same one-chokepoint rationale as `Decorate`). Then record result + metric; stop the loop if failed and not `ContinueOnError`.

**Overall success** (lines 374-378): `allStepsExecuted && (allStepsSucceeded || allFailedStepsContinued)` — i.e. every planned step ran AND either all succeeded or every failure was a `ContinueOnError` failure.

**Exception handling**: `OperationCanceledException` → `WasCancelled=true`, `Succeeded=false`; any other → captured into `ErrorMessage`/`Exception`. `finally` stores step metrics and builds the scenario metric.

**Live output tap — `LiveStepOutput`** (`Orchestration/LiveStepOutput.cs`): process-wide live tail of the *currently executing* step's console output (static class: `Clear` / `Publish` / `Snapshot`; lock-guarded `StringBuilder`, keeps only the last `MaxChars = 8000` chars via front-trim). Contract: the orchestrator calls `LiveStepOutput.Clear()` at the start of each step in the per-step loop (line 168, right after the cancellation check at 160 — so the UI never shows the previous step's output under the current step); `DefaultProcessRunner` (`Executors/IProcessRunner.cs:97,105`) publishes each stdout/stderr line as it arrives; readers **poll** `Snapshot()` — deliberately **no event**, so a chatty process can't cause per-line re-render storms (the Activity page reuses its existing 1-second ticker). Static by design: executors construct their runners directly (no DI seam) and the coordinator enforces one run at a time. LOCAL process steps only — the remote WSMan driver redirects output to temp files ON the target and reads them back at completion, so remote steps still deliver output all-at-once. UI consumption is documented in [[crewchief-workload-and-runs]]; the test-parallelism gotcha in [[crewchief-testing]].

**`ValidateScenario`** (lines 447-697, returning `UtilityScenarioValidation`): per step checks non-null, non-blank `Type`, `_executorsByType.ContainsKey(step.Type)` (line 479, error text at 482), `executor.CanExecute(step)`, then a big type-specific `switch` (SQL secret names, CommandLine/Curl `command`, ConnEx via `ValidateConnExStep` — called at line 534, defined at 702 — Wait seconds, ServiceControl/AppPool action parse, HealthGate url/services, DatabaseOperations/Uninstall/Install/Configure delegate to the step's own `GetValidationError()`, SetApiKey fields). Warnings for no-inline-content and timeouts > 3600s.

## Layer 2 — `WorkloadEngine.ExecuteAsync`

`CrewChief.Engine/Orchestration/WorkloadEngine.cs`. Signature includes `IProgress<StepExecutionResult>? perStep`, `int startAtIndex`, `IReadOnlySet<int>? completedStepIndexes`.

Why it exists (class remarks lines 18-28): the orchestrator has no per-step progress hook and only reports success/failure after a whole list finishes. So the engine calls `ExecuteScenarioAsync` **once per resolved step (a single-element list)** to get live progress and honor cancellation *between* steps. Consequences:

- **Validate-all-first** (`WorkloadEngine.cs:97`): `Validate(wf)` — no `resolveRef` delegate any more — runs over every entry (including those before `startAtIndex`); any error → `InvalidOperationException`. `startAtIndex` range-checked at lines 118-123.
- **Resume skip** (lines 139-145): entries in `completedStepIndexes` are skipped, never re-executed (so a step that succeeded after an earlier `ContinueOnError` failure isn't run twice).
- **Per-step call** (`ResolveStep` at line 149, `ExecuteScenarioAsync(wf.Name, new List<…>{ step }, wf.GlobalParameters, ct)` at lines 156-160). Each result/metric is **re-stamped** with the workload entry index `i` (line 166) — the per-step call always reports internal index 0.
- **ContinueOnError re-implemented here** (lines 168-173 for the flag, 226-244 for the stop decision): the engine — not the single-step orchestrator call — decides to continue, so it sets `ContinuedOnError` and evaluates whether to stop.
- **Cancellation** (lines 184-199): the orchestrator never throws on mid-step cancel (it returns `WasCancelled=true`); the engine surfaces that as a cancelled workload and breaks; `ContinueOnError` never overrides cancellation.
- **Synthesized-failure guard** (lines 201-224): when the per-step call returns **zero** `StepResults` and wasn't cancelled (how an orchestrator-side *validation* failure surfaces — e.g. a SqlStep missing its connection-secret name, which the engine's own `Validate` doesn't catch), the engine synthesizes a failed `StepExecutionResult` and forces `completedAllSteps=false` **regardless of ContinueOnError** — so a step that couldn't even be attempted can never be masked into overall success (NEW-1).
- **Final success** (lines 246-249): `completedAllSteps && !WasCancelled && StepResults.Count>0 && All(r => r.Succeeded || r.ContinuedOnError)`.

## Inline step resolution — the live library link is GONE

`ResolveStep` (`WorkloadEngine.cs:265-267`) + `WorkloadDefinition.cs`:

- Every `WorkloadEntry` carries a **self-contained `Inline` step body**. The retired `Ref` (named a library step) and `Overrides` (a `JObject` of per-entry property sets) are deleted from both `WorkloadStepEntry` and `WorkloadEntry`, and the `resolveRef` delegate is gone from every signature — `Validate(WorkloadDefinition wf)` now takes one argument.
- **Adding a step from the library MATERIALIZES it**: the library step's body is deep-copied into `Inline` at that instant, and the two are independent from then on. To adopt a later change to the library template, delete the step from the workload and import it again.
- Consequence: renaming a library step affects **no** workload. There is no reference to follow, so `IStepFileStore.UpdateStepReferences` was deleted (zero hits repo-wide) — do not go looking for a rename follow-up call.
- `Validate` (`:48`) rejects a null `Inline` before anything else: *"Entry {i}: no inline step definition. Every workload step must define its step inline — add the step from the library (which copies it in) or define it from scratch."*
- An optional `Label` (per-instance display rename) is stamped by `WorkloadEngine` over the resolved step's `Description` (see [[crewchief-workload-and-runs]]).

> [!warning] Legacy `ref`/`overrides` files are REFUSED on load, never migrated
> Newtonsoft ignores unknown JSON properties, so once `Ref`/`Overrides` came off the DTO a legacy entry like `{"ref": "uninstall-profisee-server"}` deserializes **cleanly** into an entry with no `Inline` — an empty step. A box-prep workload would then "run" an uninstall that did nothing at all and report success. Refusing to load is the only honest outcome.
>
> `LegacyWorkloadRefGuard.ThrowIfLegacyRef` (`CrewChief.Data/Models/LegacyWorkloadRefGuard.cs`) is the ONE detector. It inspects the parsed `JObject` **before** deserialization — never the absence of a field, because the retired fields no longer exist on the DTO and are invisible afterwards. Property lookup is case-insensitive (`JObject`'s own indexer is not). Shared by `WorkloadFileStore` (disk load) and `WorkloadTransferService` (bundle import) so neither surface can be the one that lets a legacy ref through. It throws `LegacyWorkloadRefException` carrying `WorkloadName`, the 1-based `StepNumber`, and `StepRef`. There is **no automatic migration by design**: the operator-facing message names the offending step and tells them to remove it and re-import from the library.

**One serializer** (`WorkloadEngine.cs:34-39`): `StepSerializer = UtilityStepConverter.Serializer`, used by **both** `Validate()` and execution, so validation can never judge a step by different rules than the run that follows it. The second, stricter `MissingMemberHandling.Error` serializer that used to exist solely to reject an `Overrides` key that wasn't a real property on the referenced step type went away with `Overrides`.

`WorkloadDefinition` is deliberately engine-level (UI/file-agnostic): the Web layer maps its own `WorkloadFile` → `WorkloadDefinition`. `GlobalParameters` is OrdinalIgnoreCase and merged *under* each step's own params (step wins) by the orchestrator.

## Metrics

Both layers roll per-step `UtilityStepMetric`s into a scenario-level metric via `UtilityScenarioMetric.FromStepMetrics(stepMetrics, name, wasCancelled)`, then `SetSkippedSteps(...)` for a planned-but-not-run tail after an early stop/cancel (`UtilityOrchestrator.cs:420-424`, `WorkloadEngine.cs:254-255`).

## Sources
- `CrewChief\CrewChief.Engine\Orchestration\UtilityOrchestrator.cs`
- `CrewChief\CrewChief.Engine\Orchestration\LiveStepOutput.cs`
- `CrewChief\CrewChief.Engine\Orchestration\WorkloadEngine.cs`
- `CrewChief\CrewChief.Engine\Orchestration\WorkloadDefinition.cs`
