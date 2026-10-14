---
name: crewchief-workload-and-runs
description: >
  CrewChief's workload run/resume model shared by CLI and Web over one runs.json — resume planner,
  cancellation-outcome mapping, the singleton run coordinator, the Activity page, per-instance step
  Labels, and completion notifiers. Use when running/resuming/restarting a workload, fix-and-continue
  logic, live per-step progress and output tail, the Activity page (paging, filters, failure banner),
  the WorkloadRunMonitor popup, duration formatting, renaming a step within one workload, or SMTP
  notifications.
---

Repo: speed-merchants (paths below are repo-relative)

# CrewChief Workload & Runs

CrewChief runs a **workload** (an ordered list of step entries) or a single ad-hoc **step**, records each execution as a `RunRecord` in the shared `runs.json`, and lets a failed/cancelled workload be resumed or restarted. The CLI and the Web app drive the *same* model and *share the same `runs.json`* — so run behavior must never drift between them. The engine's pure planning and mapping logic lives in `CrewChief.Data` precisely so both surfaces reuse it.

Contrast with TestAuto, which is DB + Hangfire backed (see [[testauto-workflow-execution]]): CrewChief is pure functions over a JSON file plus an in-process coordinator.

## When to Use
- Implementing or debugging run / resume / restart-from-step / cancel of a workload.
- Touching the fix-and-continue logic (which steps carry forward, which re-run).
- Wiring live per-step progress into the UI or the Activity page.
- Mapping the engine's cancellation contract to a run outcome.
- Adding or configuring completion notifications (SMTP).

## The model
- **`WorkloadFile` / `WorkloadStepEntry`** (Data) → mapped 1:1 by `WorkloadDefinitionMapper.ToDefinition` to the engine-level **`WorkloadDefinition` / `WorkloadEntry`** (Engine). The entry's `Inline` body is copied **verbatim**. The mapper also merges string-valued `ExtraParms` entries into `GlobalParameters` when they don't collide with an explicit key.
- **Every entry is inline.** The retired `Ref` (named a library step, resolved through a caller-supplied `Func<string, JObject?>`) and `Overrides` (shallow property overrides on a clone) are **gone from the model**, and with them the `resolveRef` delegate that used to thread through the coordinator, CLI, and engine. Adding a step from the library deep-copies it into `Inline` at that moment — see [[crewchief-orchestration]] for the materialize-on-add model and the `LegacyWorkloadRefGuard` load refusal.
- **`Label` (optional, per-instance display rename)** — a "rename within the workflow" on `WorkloadStepEntry`, mapped through to the engine `WorkloadEntry`.
- **Workload-level Run As** — a `WorkloadRunAs` trio (`credentialUserId` / `credentialPassword` / `credentialSecretName`) on the workload itself, inherited by box-prep steps that declare none. See below.

### Workload-level Run As inheritance

`WorkloadRunAs` (`CrewChief.Engine/Steps/WorkloadRunAsInheritance.cs:19`) is a
`readonly record struct (string? UserId, string? Password, string? SecretName)`.

> [!warning] `ToString()` is hand-written, and that is load-bearing
> A `record struct`'s **generated** `ToString` prints every member — which would put the Run-As **password**
> into any log line, exception message, or debugger view that stringified it. The explicit override (`:49`)
> exists solely to prevent that. Do not delete it, and do not "simplify" the struct back to the compiler
> default.

**`IsConfigured` (`:32`) is an any-non-blank test**, and inheritance uses the same test the router applies to
a step's own fields. So a **half-filled** workload pair is inherited *as-is* — and then rejected loudly by
`BoxPrepRouting` as `RunAsUnresolved` ([[crewchief-remote-box-prep]]). Requiring both halves before
inheriting would have silently dropped the pair and run the step as the CrewChief service identity, which is
exactly the silent identity substitution the routing model refuses.

`InheritIfBoxPrep` (`:157`) is the per-type arm list. Adding a credentialed step type means adding an arm
here **and** bumping the box-prep census — see [[crewchief-adding-a-step-type]].

> [!important] Compose-time callers must use `WorkloadStepMaterializer.Materialize`
> It applies **both** the Run-As inheritance **and** the global-parameter merge
> (`ParameterReconciler.MergeParameters`, `WorkloadStepMaterializer.cs:69`) onto a **copy**. Applying only
> the first produced false *"no Run As credential resolved"* verdicts that hard-blocked otherwise valid runs
> — see [[crewchief-capability-preflight]].

### The parameter-driven workload pattern

The shipped workloads demonstrate the canonical composition: a workload-level `globalParameters` block of
`profisee_*` variables that **self-compose** —
`profisee_service_name` = `"Profisee {{profisee_version_number}} (Profisee)"` — consumed by every inline
step, plus the workload-level Run As trio above. Bumping one version variable retargets the whole workload.
Inventory in [[crewchief-default-templates]]; token mechanics in [[crewchief-token-replacement]]. When set, `WorkloadEngine` stamps it over the resolved step's `Description` just before execution (`WorkloadEngine.cs` ~153-156), so it shows everywhere the step name surfaces — run records, Activity step lists, cancel/failure messages — WITHOUT touching the shared library step. The Activity page's `StepLabel` helper also prefers the entry's `Label` even before any result is recorded.
- **`RunRecord`** — `Id`, `Kind` (`"step"`/`"workload"`), `Name`, `StartedUtc`/`FinishedUtc`, `Succeeded`, `Outcome` (`Running`/`Succeeded`/`Failed`/`Cancelled`), `ResumedFromRunId`, `StartAtIndex`, `TotalSteps`, and `StepResults` (flattened `StepResultRecord`s). Written best-effort as `Running` before execution, then `Update`d on completion.

> Editor note: the *Web editor's* per-step state (`StepEntryEditorState` in `WorkloadEditor.razor.cs:88`) preserves an unparseable inline body verbatim via `UnreadableInline` / its own `IsUnreadable` so a bad inline round-trips untouched on Save (only cleared when the user explicitly replaces it). **`UnreadableInline` is editor state and exists only there.**
>
> **But `IsUnreadable` now exists on `WorkloadFile` TOO, and it means something different — do not conflate them.** `WorkloadFile.cs:61` declares `public bool IsUnreadable => !string.IsNullOrEmpty(LoadError);` for the whole-file broken stub: `GetAll` never throws on a bad file, so an unparseable workload comes back as an inert stub carrying `Name` + `LoadError` + `Folder` and zero steps. **Any caller that judges, saves or runs a workload must check it first** — `Save` refuses a stub (writing would truncate the real file), the run coordinator refuses to run one, and `ValidateCommand` special-cases it because zero steps would otherwise reconcile Green as "No steps". See [[crewchief-file-persistence]]. *Corrected 2026-09-09: this note previously asserted `IsUnreadable` was NOT a property on `WorkloadFile`. It is — an agent trusting the old text would skip the required check.*

## Resume planning — `WorkloadResumePlanner` (pure, static)
Shared by Web and CLI so the two resume gates cannot diverge:

| Function | Behavior |
|---|---|
| `CanResume(record)` | Eligible only when `Kind == "workload"` AND `Outcome` is terminal `Failed` or `Cancelled` (a `Running` run isn't terminal; a `Succeeded` run has nothing to resume) |
| `ShapeChanged(workload, record)` | `true` when `workload.Steps.Count != record.TotalSteps` — resuming a reshaped workload would mis-map indexes; callers must block and tell the user to restart |
| `ComputeStartAtIndex(record)` | First index in `0..TotalSteps-1` with no *succeeded* result; `0` if no results; falls back to `max(index)+1` if all recorded steps succeeded |
| `GetCompletedIndexes(record)` | Set of indices recorded as succeeded — the engine skips these on resume |
| `BuildPriorResults(record)` | Projects **all** prior successes forward, relabeling `Status` → `"Succeeded (prior run)"` |
| `BuildPriorResultsBefore(record, startIndex)` | Same, but only successes **strictly before** `startIndex` (the explicit "restart from step N" path); pair with a `null` completed-index set so nothing at/after N is skipped |

**Key invariant (finding N2):** "succeeded" is a **prefix match** — `IsSucceededStatus` matches both `"Succeeded"` and `"Succeeded (prior run)"`. Every already-succeeded step is carried forward AND skipped — even a success that ran *after* an earlier `ContinueOnError` failure — so a (possibly non-idempotent) step that already succeeded is **never re-run**. Fix-and-continue carries all successes; user-chosen restart-from-N carries only successes before N and re-runs the rest.

## Cancellation outcome — `WorkloadRunOutcomeMapper.Map`
The engine has two distinct cancellation shapes that BOTH mean cancelled:
1. **In-step cancel** never throws — the orchestrator catches `OperationCanceledException` internally and returns a result with `WasCancelled == true`.
2. **Between-step / pre-cancelled** cancel **throws** `OperationCanceledException` from `ExecuteAsync` with no result.

`Map(succeeded, wasCancelled, threwOperationCanceled)` → `"Cancelled"` if either cancel flag is set, else `succeeded ? "Succeeded" : "Failed"`. Callers MUST catch `OperationCanceledException` around `ExecuteAsync` and pass `true` for `threwOperationCanceled` — never let it surface as a `Failed` run.

## Web run coordinator — `IWorkloadRunCoordinator` / `WorkloadRunCoordinator`
Application **singleton** that owns run *execution*, decoupled from any page lifetime, so Workloads/WorkloadEditor and the Activity page share one engine and one live view.

- **One run at a time** — `_isBusy` under `_sync`; a second start returns `RunStartOutcome.Busy`. Start methods return a `RunStartResult(Outcome, Message)` (`Started`/`Busy`/`WorkloadMissing`/`ShapeChanged`/`NothingToRun`/`MappingError`).
- **Copy-on-write snapshots** — readers see an immutable `RunRecord` via `CurrentRun`; the background thread mutates a private working copy and only ever *swaps* a fresh `Snapshot` (with its own `StepResults` list) under `_sync`, so a page can enumerate mid-run without a torn read or "Collection was modified".
- **`Changed` event** — raised (possibly off-thread) on start / each step / finish; each subscriber invoked in its own try/catch so a throwing page handler can't fail the run. Subscribers marshal via `InvokeAsync(StateHasChanged)`.
- **`InlineProgress<T>`** — a *synchronous* `IProgress<T>` (unlike `Progress<T>` it invokes inline on the reporting thread, no `SynchronizationContext` post) so per-step run-history writes happen in order.
- Background `Task.Run`; entry points `StartFreshAsync` / `StartStepAsync` / `ResumeAsync` / `RestartFromAsync` (`ResumeAsync`/`RestartFromAsync` apply the shape-change + nothing-to-run guards and call the resume planner). Pre-validates synchronously via `_engine.Validate` so a bad workload surfaces a `MappingError` immediately rather than as a `Running→Failed` run.
- **`StartStepAsync(StepFile step, IReadOnlyDictionary<string,string>? promptedParameters = null)`** runs a single library step as a one-entry ad-hoc run (`Kind` `"step"`) through the same engine/run-history/live-progress/notifier pipeline. The optional `promptedParameters` — the step-editor token-prompt dialog's collected values — become the run's global parameters, so a step's run-time token prompt now flows into an ACTUAL step run (not just the inline Test). Same single-run-at-a-time gate as a workload run.
- Terminal `IsBusy=false` and the final snapshot are published atomically under `_sync`; then notifiers fire (`FireNotifierSafeAsync`, catch-per-notifier).

The CLI (`RunCommand`) mirrors all of this without the coordinator: `run workload|step <name> [--param k=v]` and `resume <runId>`, same `RunRecord` shape, same `WorkloadRunOutcomeMapper`, same resume-eligibility gate, same fire-and-forget-with-catch notifiers, its own `SynchronousProgress<T>`, and best-effort `SafeAppend`/`SafeUpdate` (a runs.json IO failure is logged and swallowed so it never corrupts the CLI exit code — see [[crewchief-file-persistence]] for the shared-file race).

## Unified Activity page
One component serves `/activity`, `/execution`, `/workloads/execution`, `/history` (back-compat routes → one page — see memory [[project_crewchief_activity_merge]]).
- Newest-first list of every `RunRecord`; **sticky status filter** persisted to localStorage (`crewchief.activity.statusFilter`) via `crewchiefIo.getItem/setItem`, restored in `OnAfterRenderAsync` (see [[reference_crewchief_sticky_filters]]); a **case-insensitive run-name filter** (`_nameFilter`, trimmed `Contains`) layers on top of the status filter — `FilteredRuns` applies both.
- **Config-driven client-side paging** — `_pageIndex`/`_pageSize` live in fields so the 1s ticker and coordinator re-renders never reset the operator's page; default size from `WebUI:Activity:DefaultPageSize` (fallback 25), pager choices from `WebUI:Activity:PageSizeOptions` (fallback 10/25/50/100); `PagedRuns` slices `FilteredRuns`; `ClampPage()` keeps the index in range after deletes/clears; any status- or name-filter change resets to page 0.
- **Single-expanded accordion** keyed by run `Id` so live re-renders never collapse it; the expanded detail renders the coordinator's live `CurrentRun` when it's the active run, else the persisted copy. `ActiveRun` (`IsBusy ? CurrentRun : null`) feeds the summary card's live-progress section.
- **`FailureBanner(run)`** — one-line stop explanation in the expanded detail: Cancelled → "cancelled after X of Y step(s)" plus a not-started count; Failed → the first step whose `Status` contains "Fail" (by index) plus how many steps never started; null for succeeded/running.
- Live per-step table: the running step shows `Running…`, queued steps `Pending`, others `Not run`; a **`PeriodicTimer` (1s)** ticks the elapsed clock while `IsBusy`.
- Actions: **restart-from-any-step**, **Resume (first failure)** for terminal Failed/Cancelled, **Cancel**, per-row delete, bulk delete, clear-all — all through the shared coordinator.

## Live-run visibility & monitor topology (2026-07-22)
- **Coordinator surface** (`IWorkloadRunCoordinator`, both published under the SAME `_sync` lock as `CurrentRun`):
  - **Planned-step capture — `BuildPlannedSteps`** (`WorkloadRunCoordinator.cs:409`, `private static List<PlannedStepInfo>`, taking only the `WorkloadDefinition`). There is **no** `BuildPlannedStepNames` — that identifier does not exist. One build at run START feeds BOTH planned surfaces:
    - **`CurrentRunPlannedSteps`** (`IWorkloadRunCoordinator.cs:90`) — `IReadOnlyList<PlannedStepInfo>`, the record `PlannedStepInfo(string Name, string Type)` (`IWorkloadRunCoordinator.cs:46`). `Name` = entry `Label` → inline `description` → (type display, else `"Step"`), all trimmed (the old `Ref`-name rung is gone with `Ref`); `Type` is the **RAW** step type (e.g. `"DatabaseOperationsStep"`, read case-insensitively off `"type"`), deliberately matching the `Type` recorded on completed `StepResultRecord`s. This is what lets the shared monitor render a step's Name AND Type *before* it executes. Consumed by `WorkloadRunMonitor.razor.cs:135-137` (`PlannedField`).
    - **`CurrentRunStepNames`** (`IWorkloadRunCoordinator.cs:83`) — the single combined `"Name · TypeDisplay"` label per index, derived from the same list via `CombinedLabel` (`WorkloadRunCoordinator.cs:445`): the `UtilityStepTypeInfo.GetDisplayName(Type)` suffix is appended **only when it adds info** (skipped when the type is blank or its display equals the name). Feeds the Activity summary banner.
    - Both are assigned together under the same `_sync` lock (`WorkloadRunCoordinator.cs:246-247`) as `CurrentRun`, and the list is built just before it at `:216`. **It no longer does any file I/O**: `BuildPlannedSteps` reads each entry's own `Inline` body, so there is nothing to resolve, nothing to fail, and no best-effort swallow — the old `resolveRef` step-store read (and the "leaves `Type` blank on resolve failure" caveat) disappeared with `Ref`.
  - **`CurrentStepStartedUtc`** — set to run start, then refreshed to `DateTime.UtcNow` on each step-completion progress report (steps run sequentially, so a completion IS the next step's start). Drives the Activity page's ticking per-step elapsed on the Running… pill (`RunningStepElapsed`, refreshed by the existing 1s ticker).
- **`RunDisplay.FormatDurationMs(ms)`** (`RunDisplay.cs:57`) — a **clock-style** duration (NOT tiered prose) used by run rows, per-step lines, and dialogs. Exactly TWO branches on `hours >= 1`: `mm:ss.fff` (`"00:00.502"`, `"01:23.200"`, `"59:59.400"`) promoting to `h:mm:ss.fff` (`"1:00:00.000"`, `"2:05:09.000"`). Rounding happens ONCE, at the **millisecond** level (`(long)Math.Round(milliseconds)`, `RunDisplay.cs:62`) — so 350.6 ms → `"00:00.351"` and 999.5 ms → `"00:01.000"`, and a `.fff` remainder is never double-rounded into a `:60` seconds field. Negative clamps to 0. This is the same clock as the live `FormatElapsed(TimeSpan)` (`RunDisplay.cs:92`, `mm:ss` / `h:mm:ss`) **minus** the `.fff`: the live clocks tick once a second, so displayed milliseconds would only ever be stale. Tests: `RunDisplayTests` (`CrewChief.Tests.Unit\Web\RunDisplayTests.cs`) pins every branch plus the round-once and negative-clamp cases.
- **Activity page additions**:
  - Summary banner shows run **Name · Kind** plus `Step N of M: <current step name>` — N = executing index + 1, name from `CurrentStepDisplay` reading `Coordinator.CurrentRunStepNames[idx]` (null → count only).
  - **Auto-follow** — a run that STARTS while the page is open auto-expands exactly ONCE per run id (`_autoExpandedRunId` guard, also set when landing on the page mid-run), so a manual collapse afterward is respected (later `Changed` events see the same id and do nothing).
  - Numbered step list is **1-based** with `UtilityStepTypeInfo.GetIcon/GetAccentColor` type icons; the type key comes from the recorded result's `Type` first, else the expanded workload's `Inline` `"type"` read **case-insensitively** (`StepTypeKey`; a pending ref entry stays icon-less — not worth a store read per render).
  - Step-output modal widened to `max-width: min(1080px, 96vw)` with **Prev/Next** across the run's recorded steps (index order), per-pane **Copy** (`navigator.clipboard.writeText`, best-effort — a blocked clipboard just toasts) and **Download .txt** (`crewchiefIo.downloadText`).
  - "Restart from step" dropdown labels are **1-based** (matching the numbered list, prior status appended) but the option VALUES stay **zero-based** — the index `RestartFromAsync` expects (`RestartStepOptions`).
- **Live output tail** — static hub `CrewChief.Engine.Orchestration.LiveStepOutput` (`Clear`/`Publish`/`Snapshot`, `MaxChars = 8000` front-trim). **Deliberately NO event** — the Activity page polls `Snapshot()` on its existing 1-second ticker, so a chatty process can never cause a re-render storm. `UtilityOrchestrator` `Clear()`s at each step start (fresh tail per step); `DefaultProcessRunner` (in `IProcessRunner.cs`) `Publish`es each stdout/stderr line as it arrives. **LOCAL process steps only** — remote WSMan steps redirect output to temp files ON the target and report at completion, so their output still lands all-at-once. Rendered as a bottom-pinned `column-reverse` `<pre>` (scroll anchored to newest line, no JS) in the expanded live run. Tests: `LiveStepOutputTests`.
- **Monitor topology** — `/activity` is the FULL monitor (history, restart-from-step, resume, output dialogs, live tail). The compact "Workload Run" popup is the SHARED component `Controls/WorkloadRunMonitor.razor(.cs)`: self-sufficient (injects the coordinator, subscribes `Changed` marshalled via `InvokeAsync`, runs its own 1s `PeriodicTimer` only while `Visible` AND busy, `IDisposable` unsubscribes + stops the ticker), two-way `Visible` bind, compact #/Name/Type/Status/Duration table (1-based, `FormatDurationMs`, expandable per-step output/error rows, `Steps: SucceededStepCount / TotalSteps`), **Cancel** while running, and an **"Open Activity"** hand-off button. `HandleStartResult` on the Workloads page AND the WorkloadEditor sets `_showingRunMonitor = true` on a successful start — they **no longer navigate**, and the former page-local dialog COPIES are deleted. This component being the ONLY copy is the point: the pre-consolidation design had the same dialog pasted into both pages and display fixes routinely missed one of them.

## Notifications
- **`INotifier`** injected as `IEnumerable<INotifier>` — safely no-ops (empty enumeration) until an implementation exists; callers invoke each fire-and-forget-with-catch.
- **`SmtpNotifier`** — pure `ShouldNotify(mode, outcome)` gate: `OnFailure` (default / any unrecognized mode) sends only for `Failed`/`Cancelled` (**cancelled counts as failure**); `Always` also sends for `Succeeded`; a non-terminal outcome never sends. Send goes through an injectable **`ISmtpSender`** seam (`SmtpSender` wraps BCL `System.Net.Mail.SmtpClient` — no new NuGet); tests mock the seam.
- A notification failure is **always caught and logged** (both the notifier's own inner try/catch and the caller's outer one) — it must never fail the run it reports on.
- **`NotificationSettings`** binds `CrewChief:Notifications` (appsettings, with per-machine `User`/`Password` supplied via the **Local Secrets store** — the `LocalSecretsConfigurationSource` layered on top of appsettings in both Program.cs). The old `secrets.local.json` config-source layering is GONE — no Program.cs wires an `AddJsonFile("secrets.local.json")`; a stray `secrets.local.json` mention still lingers in the `NotificationSettings.cs`/`ApiKeyEncryptor.cs` doc-comments but is stale (see memory [[project_crewchief_secrets_local_json_eliminated]]). `SmtpNotifier` is **always registered** as an `INotifier` and internally gated by `Enabled` (chosen over conditional DI registration for simplicity).

## Sources
- `CrewChief\CrewChief.Data\Services\WorkloadResumePlanner.cs`
- `CrewChief\CrewChief.Data\Services\WorkloadRunOutcomeMapper.cs`
- `CrewChief\CrewChief.Data\Services\WorkloadDefinitionMapper.cs`
- `CrewChief\CrewChief.Data\Models\RunRecord.cs`
- `CrewChief\CrewChief.Data\Models\WorkloadFile.cs`
- `CrewChief\CrewChief.Data\Models\WorkloadStepEntry.cs` (optional per-instance `Label`)
- `CrewChief\CrewChief.Engine\Orchestration\WorkloadDefinition.cs`
- `CrewChief\CrewChief.Engine\Orchestration\WorkloadEngine.cs` (Label → step.Description override, ~153-156)
- `CrewChief\CrewChief.Data\Notifications\INotifier.cs`
- `CrewChief\CrewChief.Data\Notifications\SmtpNotifier.cs`
- `CrewChief\CrewChief.Data\Notifications\NotificationSettings.cs`
- `CrewChief\CrewChief.Web\Services\IWorkloadRunCoordinator.cs`
- `CrewChief\CrewChief.Web\Services\WorkloadRunCoordinator.cs`
- `CrewChief\CrewChief.Web\Components\Pages\Activity.razor`
- `CrewChief\CrewChief.Web\Components\Pages\Activity.razor.cs` (paging, name filter, FailureBanner, ActiveRun, auto-follow, output dialog, live tail)
- `CrewChief\CrewChief.Web\Components\Pages\RunDisplay.cs` (shared display statics: FormatDurationMs, FormatElapsed, SucceededStepCount, badges)
- `CrewChief\CrewChief.Engine\Orchestration\LiveStepOutput.cs` (static live-tail hub, Clear/Publish/Snapshot, MaxChars 8000)
- `CrewChief\CrewChief.Web\Components\Controls\WorkloadRunMonitor.razor` (shared compact run monitor markup)
- `CrewChief\CrewChief.Web\Components\Controls\WorkloadRunMonitor.razor.cs` (self-sufficient code-behind: coordinator subscription, ticker, ExecutingStepIndex)
- `CrewChief\CrewChief.Cli\Commands\RunCommand.cs`
- `CrewChief\CrewChief.Web\Components\Pages\WorkloadEditor.razor.cs` (UnreadableInline editor state only)

## Related
- [[crewchief-file-persistence]] — runs.json storage, locking, truncation
- [[crewchief-workload-transfer]] — export/import a workload between instances
- [[crewchief-orchestration]] — the engine/orchestrator that executes entries
- [[crewchief-step-type-model]] — `UtilityStepConverter` / step types
- [[crewchief-cli]] — CLI run parity
- [[crewchief-web-ui]] — coordinator + Activity UI
- [[testauto-workflow-execution]] — TestAuto's DB/Hangfire equivalent
- Memory: [[project_crewchief_activity_merge]], [[reference_crewchief_sticky_filters]], [[project_crewchief_standalone]]
