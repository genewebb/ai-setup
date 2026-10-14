---
name: testauto-log-tags
description: >
  TestAuto Serilog log tag rules — the LoggerTagExtensions *WithTag helpers plus the two constant
  families and which one is actually used. Use when writing a log statement, choosing between
  LogTagConstants (bare values, wrapped by the helpers) and LogConstants (pre-bracketed, for manual
  concatenation, and unused in production), reviewing log code for $"..." interpolation bugs, working
  out why Serilog named properties disappear in SEQ, why a [TAG] LIKE search returns nothing for a
  tag that looks correct, tagging per scenario with ForScenario, or BeginTimedOperationWithTag
  timed-operation logging.
---

Repo: speed-merchants (paths below are repo-relative)

# TestAuto Log Tag Concatenation

When combining a log tag constant with a Serilog message template, always use `+` string concatenation. Never use `$"..."` string interpolation.

## When to Use

- "How do I write a tagged log statement?" — and which constant family to reach for
- "Why does my `[TAG]` search in SEQ/SQL find nothing when the tag looks right?"
- "Why are my Serilog named properties not showing up in SEQ?"
- Reviewing any log call that uses `LogConstants.*` or `LogTagConstants.*`
- Code review on `.Information(...)`, `.Warning(...)`, `.Error(...)` calls in TestAuto
- Any time interpolation and structured logging are mixed
- "How do I log the elapsed time of an operation with a tag?" — use `BeginTimedOperationWithTag`

## The Rule

**CRITICAL:** Never interpolate log tags with `$"..."` — use `+` concatenation so Serilog named properties remain intact.

```csharp
// GOOD — named property {EntityCount} captured by Serilog
logger.Information(LogConstants.MetadataCrud + " Loading {EntityCount} entities", count);

// BAD — $"..." evaluates the entire string first, collapsing named properties into a literal
logger.Information($"{LogConstants.MetadataCrud} Loading {EntityCount} entities", count);
```

## Why It Matters

Serilog processes message templates at the point of the log call. When you use string interpolation (`$"..."`), C# evaluates the entire string before Serilog sees it. The result is a pre-rendered string with no named properties — Serilog cannot extract `{EntityCount}` because it has already been replaced with its runtime value.

In SEQ this means:
- No structured property columns for the interpolated values
- No ability to filter logs by property (`EntityCount = 5000`)
- Log entries appear as flat text instead of structured events

With `+` concatenation, the template string is passed intact to Serilog, which captures each `{Property}` as a structured field alongside the rendered message.

## Applies To

Every `logger.*` call (`.Information`, `.Warning`, `.Error`, `.Debug`, `.Verbose`) where the message string contains a `LogConstants.*` or `LogTagConstants.*` value.

```csharp
// Correct — a pre-bracketed LogConstants value concatenated with +
logger.Information(LogConstants.Scenario + " Starting {BatchSize} records", batchSize);

// Correct — a bare LogTagConstants value handed to a *WithTag helper, which adds the brackets.
// This is what production actually does (tag first; the exception overload puts ex AFTER the tag).
logger.WarningWithTag(LogTagConstants.BatchOrchestrator, "Retry {Attempt} of {Max}", attempt, max);
logger.ErrorWithTag(LogTagConstants.Metrics, ex, "Failed to persist {Count} metrics", count);

// Wrong — interpolation pre-renders the string, so Serilog captures no named properties:
logger.Information($"{LogConstants.Scenario} Starting {batchSize} records");
logger.Warning($"{LogTagConstants.BatchOrchestrator} Retry {attempt} of {max}");

// Wrong for a DIFFERENT reason — concatenating a BARE LogTagConstants value keeps the named
// properties but emits the tag UNBRACKETED ("BATCH_ORCHESTRATOR Retry 2 of 5"), so the
// WHERE Message LIKE '%[BATCH_ORCHESTRATOR]%' search that the tag exists for never matches it:
logger.Warning(LogTagConstants.BatchOrchestrator + " Retry {Attempt} of {Max}", attempt, max);
```

## Two constant families — brackets and adoption

The two families are NOT interchangeable, because only one of them carries the brackets:

| Family | Value shape | How it is meant to be used | Repo adoption |
|---|---|---|---|
| `LogTagConstants` (`TestAuto.Shared/Constants/LogTagConstants.cs`) | **bare** — `MetadataCrud = "METADATA_CRUD"` | pass as the `tag` argument of a `*WithTag` helper, which wraps it as `[TAG]` via `PrependTag` | **live** — ~2,900 `WithTag(` call sites, and **zero** raw `LogTagConstants.X + "…"` concatenations anywhere in the repo |
| `LogConstants` (`TestAuto.Shared/Constants/LogConstants.cs`) | **pre-bracketed** — `MetadataCrud = "[METADATA_CRUD]"` | concatenate with `+` straight into a message template | **declared but unused** — the class declaration is its ONLY repo-wide occurrence; zero production call sites |

Practical rule: for new code use a `*WithTag` helper with `LogTagConstants` (`LogTagConstants.ForScenario(name)` for a per-scenario tag). Reach for `LogConstants` only when you must assemble the message string by hand — that is what its brackets are for. Never concatenate a bare `LogTagConstants` value: you keep the structured properties but lose the `[TAG]` marker that makes the log SQL-queryable.

## Code Review Checklist

When reviewing log statements, flag any line matching the pattern `logger.*($"` or `_logger.*($"` — string interpolation starting directly in the log call arguments.

Safe patterns look like:
- `logger.*(LogConstants.SomeTag + " Message {Property}", value)`
- `logger.*(LogTagConstants.SomeTag + " Message {Property}", value)`

## LoggerTagExtensions Helpers

`TestAuto.Shared.Extensions.LoggerTagExtensions` provides `*WithTag` extension methods on Serilog `ILogger` (`VerboseWithTag`, `DebugWithTag`, `InformationWithTag`, `WarningWithTag`, `ErrorWithTag`, `FatalWithTag`, plus `*WithTagAndConsole` variants that also echo to Console). They all route through a private `PrependTag(string tag, string messageTemplate)` utility that prefixes the message as `[{tag}] {messageTemplate}` (or returns the template unchanged when the tag is null/empty).

Why the prefix exists: `LogTag` is a Serilog property used for Seq filtering, but the Profisee logging sink may not persist it to SQL. Prepending `[TAG]` into the message text keeps logs queryable via `WHERE Message LIKE '%[PURVIEW]%'`.

Note: `PrependTag` interpolates only the **tag** — the message template itself is passed through untouched, so Serilog named properties (`{Property}`) survive. This is the safe counterpart to the `$"..."` anti-pattern above; never replicate it by interpolating the whole template yourself.

### Timed Operations: BeginTimedOperationWithTag

```csharp
public static IDisposable BeginTimedOperationWithTag(this ILogger logger, string tag, string description, string operationId)
```

Structured timed-operation logging with automatic elapsed-time reporting:

1. On call: logs **Information** — `[tag] Beginning operation {OperationId}: {Description}` — and starts a `Stopwatch`.
2. Returns an `IDisposable` (private `TimedOperationDisposable`).
3. On `Dispose()`: stops the stopwatch and logs **Information** — `[tag] Completed operation {OperationId} in {ElapsedMs} ms`. Dispose is idempotent (double-dispose logs nothing extra).

Both events go out at Information level with `OperationId`, `Description`, and `ElapsedMs` as structured Serilog properties, so Seq can correlate begin/complete pairs by `OperationId` and chart `ElapsedMs`.

```csharp
// Illustrative usage — see the adoption note below; there are no production call sites
using (_logger.BeginTimedOperationWithTag(LogTagConstants.ForScenario(ScenarioName), "Bulk create records", "create-batch-01"))
{
    await CreateRecordsAsync(records);
} // dispose logs: [SCENARIO:...] Completed operation create-batch-01 in 1234 ms
```

#### Adoption status — declared and tested, no production call sites

`BeginTimedOperationWithTag` exists **twice** in this repo, as two independent copies, and neither is called by product code. A bare-name grep across the whole repo (checked 2026-07-27 — re-run it before relying on this) returns only these:

| Site | What it is |
|---|---|
| `TestAuto.Shared\Extensions\LoggerTagExtensions.cs:140` | The TestAuto declaration. **Zero call sites** anywhere — no TestAuto production code, and no TestAuto test exercises it. |
| `CrewChief\CrewChief.Engine\Logging\LoggerTagExtensions.cs:128` | A **separate, duplicated** declaration in CrewChief. CrewChief does not reference `TestAuto.Shared`. |
| `CrewChief\CrewChief.Tests.Unit\Engine\LoggingTagTests.cs:172,186` | The only invocations in the repo. They exercise **CrewChief's** copy, not TestAuto's — `BeginTimedOperationWithTag_LogsBeginOnEntryAndCompletedOnDispose` (`:170`) and `BeginTimedOperationWithTag_DisposeIsIdempotent` (`:184`). |

Practical consequences:

- The behavior described above (begin/complete pair, idempotent dispose, `ElapsedMs` property) is **verified by tests**, so it works — it is just unadopted. Treat it as a ready-to-use helper, not as an established convention you are matching.
- Do not tell a reader "TestAuto uses `BeginTimedOperationWithTag` for timed operations". It doesn't. If you add the first call site, say so explicitly in the change.
- The two copies can drift. A fix to one does not reach the other; check both when changing timed-operation semantics.

The same "declared and tested but never called from production" pattern affects several `LogTagConstants` members on the CrewChief side — see the `crewchief-logging` skill.

`LogTagConstants.ForScenario(scenarioName)` is the typical tag source (see `TestAuto.Records\Common\ScenarioBaseCrud.cs` for real `*WithTag` usage with that tag).

## Connect scenarios: `PushScenarioLogContext` is mandatory in a wholesale override

`ScenarioBaseConnect.PushScenarioLogContext(cfg)` (`TestAuto.Connect/Common/ScenarioBaseConnect.cs:105`)
pushes the scenario's identifying properties — notably `WorkloadExecution` — onto Serilog's `LogContext`.
The base calls it for you (`:88`).

> [!warning] Any scenario that overrides `ProcessBatchAsync` wholesale MUST wrap its body
> ```csharp
> using (PushScenarioLogContext(cfg)) { /* ... */ }
> ```
> Skip it and every event from that scenario reaches SEQ with **no `WorkloadExecution` property**, which
> makes a failing run untraceable by its execution code — the one identifier an investigator starts from.
> `LogContext` is a stack, so pops happen in reverse order; do not hand-manage the disposables.

`ConnectConstants.DiagPrefix = "[DIAG]"` (`ConnectConstants.cs:40`) marks **temporary** Error-level
diagnostics that are explicitly slated for demotion. Do not treat a `[DIAG]` line as a real error, and do
not copy the pattern as a durable convention.

## Sources

- `AGENTS.md` — Log Tag Special Rule section (source deleted; canonical rule now in this skill)
- `TestAuto.Shared\Extensions\LoggerTagExtensions.cs` — `*WithTag` helpers, `PrependTag`, `BeginTimedOperationWithTag` / `TimedOperationDisposable`
- `TestAuto.Records\Common\ScenarioBaseCrud.cs` — real `InformationWithTag`/`ErrorWithTag` call sites using `LogTagConstants.ForScenario(...)`
